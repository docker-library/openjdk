#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# sort version numbers with lowest first
IFS=$'\n'; versions=( $(sort -V <<<"${versions[*]}") ); unset IFS

abs-url() {
	local url="$1"; shift
	local base="$1"; shift

	case "$url" in
		http://* | https://* ) ;;

		/*)
			local extra="${base#*://*/}"
			local baseBase="${base%$extra}"
			baseBase="${baseBase%/}"
			url="$baseBase$url"
			;;

		*)
			echo >&2 "error: TODO parse '$url' relative to '$base'"
			exit 1
			;;
	esac

	echo "$url"
}

adopt-github-url() {
	local javaVersion="$1"; shift

	local url
	url="$(
		curl -fsS --head "https://github.com/AdoptOpenJDK/openjdk${javaVersion}-upstream-binaries/releases/latest" | tac|tac \
			| tr -d '\r' \
			| awk 'tolower($1) == "location:" { print $2; found = 1; exit } END { if (!found) { exit 1 } }'
	)" || return 1

	url="$(abs-url "$url" 'https://github.com')" || return 1

	echo "$url"
}

adopt-sources-url() {
	local githubUrl="$1"; shift

	local url
	url="$(
		curl -fsSL "$githubUrl" | tac|tac \
			| grep -oEm1 'href="[^"]+-sources_[^"]+[.]tar[.]gz"' \
			| cut -d'"' -f2 \
			|| :
	)"
	[ -n "$url" ] || return 1

	url="$(abs-url "$url" "$githubUrl")" || return 1

	echo "$url"
}

adopt-version() {
	local githubUrl="$1"; shift

	local version
	version="$(
		wget -qO- "$githubUrl" | tac|tac \
			| grep -oE '<title>.+</title>' \
			| grep -oE ' OpenJDK [^ ]+ ' \
			| cut -d' ' -f3
	)" || return 1

	echo "$version"
}

jdk-java-net-download-url() {
	local javaVersion="$1"; shift
	local fileSuffix="$1"; shift
	wget -qO- "https://jdk.java.net/$javaVersion/" \
		| tac|tac \
		| grep -Eom1 "https://download.java.net/[^\"]+$fileSuffix"
}

jdk-java-net-download-version() {
	local javaVersion="$1"; shift
	local downloadUrl="$1"; shift

	downloadVersion="$(grep -Eom1 "openjdk-$javaVersion[^_]*_" <<<"$downloadUrl")" || return 1
	downloadVersion="${downloadVersion%_}"
	downloadVersion="${downloadVersion#openjdk-}"
	if [ "$javaVersion" = '11' ]; then
		# 11 is now GA, so drop any +NN (https://github.com/docker-library/openjdk/pull/235#issuecomment-425378941)
		# future releases will be 11.0.1, for example
		downloadVersion="${downloadVersion%%+*}"
	fi

	echo "$downloadVersion"
}

travisEnv=
appveyorEnv=
for javaVersion in "${versions[@]}"; do
	for javaType in jdk jre; do
		dir="$javaVersion/$javaType"
		[ -d "$dir" ] || continue

		case "$javaVersion" in
			8 | 11)
				# TODO Dockerfile-adopt-*.template
				githubUrl="$(adopt-github-url "$javaVersion")"
				sourcesUrl="$(adopt-sources-url "$githubUrl")"
				adoptVersion="$(adopt-version "$githubUrl")"
				javaUrlBase="${sourcesUrl%%-sources_*}-"
				javaUrlVersion="${sourcesUrl#${javaUrlBase}sources_}"
				javaUrlVersion="${javaUrlVersion%.tar.gz}"
				javaUrlBase+="${javaType}_" # "jre_", "jdk_", etc

				echo "$javaVersion-$javaType: $adoptVersion ($javaUrlVersion; $javaUrlBase)"

				sedArgs=(
					-e 's!^(ENV JAVA_VERSION) .*!\1 '"$adoptVersion"'!'
					-e 's!^(ENV JAVA_BASE_URL) .*!\1 '"$javaUrlBase"'!'
					-e 's!^(ENV JAVA_URL_VERSION) .*!\1 '"$javaUrlVersion"'!'
				)

				case "$javaType" in
					jdk)
						baseFrom='buildpack-deps:buster-scm'
						;;

					jre)
						baseFrom='buildpack-deps:buster-curl'
						sedArgs+=( -e '/javac --version/d' )
						;;

					*) echo >&2 "echo: unexpected javaType: $javaType"; exit 1 ;;
				esac

				if [ "$javaVersion" = '8' ]; then
					sedArgs+=(
						# no "--" style flags on OpenJDK 8
						-e 's! --version! -version!g'

						# and no "jshell" until OpenJDK 9
						-e '/jshell/d'
					)
				fi
				if [ "$javaType" = 'jre' ]; then
					# no "jshell" in JRE
					sedArgs+=( -e '/jshell/d' )
				fi

				linuxSedArgs=(
					-e 's!^(ENV JAVA_HOME) .*!\1 /usr/local/openjdk-'"$javaVersion"'!'
					"${sedArgs[@]}"
				)
				sed -r "${linuxSedArgs[@]}" -e 's!^(FROM) .*!\1 '"$baseFrom"'!' Dockerfile-adopt-linux.template > "$dir/Dockerfile"
				sed -r "${linuxSedArgs[@]}" Dockerfile-adopt-slim.template > "$dir/slim/Dockerfile"
				dockerfiles=( "$dir/Dockerfile" "$dir/slim/Dockerfile" )

				if [ -d "$dir/windows" ]; then
					for winD in "$dir"/windows/*/; do
						winD="${winD%/}"
						windowsVersion="$(basename "$winD")"
						windowsVariant="${windowsVersion%%-*}" # "windowsservercore", "nanoserver"
						windowsVersion="${windowsVersion#$windowsVariant-}" # "1803", "ltsc2016", etc
						windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
						serverCoreImage="openjdk:$adoptVersion-windowsservercore-$windowsVersion" # "openjdk:8u212-b04-windowsservercore-1809", etc
						sed -r "${sedArgs[@]}" \
							-e 's!^(ENV JAVA_HOME) .*!\1 C:\\\\openjdk-'"$javaVersion"'!' \
							-e 's!^(FROM) .*$!\1 mcr.microsoft.com/windows/'"$windowsVariant"':'"$windowsVersion"'!' \
							-e 's!%%SERVERCORE-IMAGE%%!'"$serverCoreImage"'!g' \
							"Dockerfile-adopt-windows-$windowsVariant.template" > "$winD/Dockerfile"
						dockerfiles+=( "$winD/Dockerfile" )
					done
				fi

				# remove any blank line at EOF that removing "jshell" in 8 leaves
				sed -i -e '${/^$/d;}' "${dockerfiles[@]}"
				;;

			14 | 15)
				if [ -d "$dir/alpine" ]; then
					downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_linux-x64-musl_bin.tar.gz')"
					downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
					downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

					echo "$javaVersion-$javaType: $downloadVersion (alpine)"

					sed -r \
						-e 's!^(ENV JAVA_HOME) .*!\1 /opt/openjdk-'"$javaVersion"'!' \
						-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
						-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
						-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
						Dockerfile-oracle-alpine.template > "$dir/alpine/Dockerfile"
				fi

				downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_linux-x64_bin.tar.gz')"
				downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
				downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

				echo "$javaVersion-$javaType: $downloadVersion (oracle)"

				for variant in oracle debian slim; do
					[ "$variant" = 'debian' ] && variantDir="$dir" || variantDir="$dir/$variant"
					[ -d "$variantDir" ] || continue
					sed -r \
						-e 's!^(ENV JAVA_HOME) .*!\1 /usr/java/openjdk-'"$javaVersion"'!' \
						-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
						-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
						-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
						"Dockerfile-oracle-$variant.template" > "$variantDir/Dockerfile"
				done

				if [ -d "$dir/windows" ]; then
					downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_windows-x64_bin.zip')"
					downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
					downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

					echo "$javaVersion-$javaType: $downloadVersion (windows)"

					for winD in "$dir"/windows/*/; do
						winD="${winD%/}"
						windowsVersion="$(basename "$winD")"
						windowsVariant="${windowsVersion%%-*}" # "windowsservercore", "nanoserver"
						windowsVersion="${windowsVersion#$windowsVariant-}" # "1803", "ltsc2016", etc
						windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
						serverCoreImage="openjdk:${downloadVersion//+/-}-windowsservercore-$windowsVersion" # "openjdk:8u212-b04-windowsservercore-1809", etc
						sed -r \
							-e 's!^(FROM) .*$!\1 mcr.microsoft.com/windows/'"$windowsVariant"':'"$windowsVersion"'!' \
							-e 's!^(ENV JAVA_HOME) .*!\1 C:\\\\openjdk-'"$javaVersion"'!' \
							-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
							-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
							-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
							-e 's!%%SERVERCORE-IMAGE%%!'"$serverCoreImage"'!g' \
							"Dockerfile-oracle-windows-$windowsVariant.template" > "$winD/Dockerfile"
					done
				fi
				;;

			*)
				echo >&2 "error: unknown java version $javaVersion"
				exit 1
				;;
		esac
	done

	for winVariant in \
		nanoserver-1809 \
		windowsservercore-{1809,ltsc2016} \
	; do
		[ -f "$javaVersion/jdk/windows/$winVariant/Dockerfile" ] \
			|| [ -f "$javaVersion/jre/windows/$winVariant/Dockerfile" ] \
			|| continue

		case "$winVariant" in
			nanoserver-*) ;; # nanoserver images COPY --from=...:...-windowsservercore-...
			# https://www.appveyor.com/docs/windows-images-software/
			*-1809)
				appveyorEnv='\n    - version: '"$javaVersion"'\n      variant: '"$winVariant"'\n      APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2019'"$appveyorEnv"
				;;
			*-ltsc2016)
				appveyorEnv='\n    - version: '"$javaVersion"'\n      variant: '"$winVariant"'\n      APPVEYOR_BUILD_WORKER_IMAGE: Visual Studio 2017'"$appveyorEnv"
				;;
		esac
	done

	if [ -d "$javaVersion/jdk/alpine" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=alpine'"$travisEnv"
	fi
	if [ -d "$javaVersion/jdk/slim" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=slim'"$travisEnv"
	fi
	if [ -e "$javaVersion/jdk/Dockerfile" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion$travisEnv"
	fi
	if [ -d "$javaVersion/jdk/oracle" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=oracle'"$travisEnv"
	fi
done

travis="$(awk -v 'RS=\n\n' '$1 == "matrix:" { $0 = "matrix:\n  include:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
cat <<<"$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
cat <<<"$appveyor" > .appveyor.yml
