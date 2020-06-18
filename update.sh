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

# see https://stackoverflow.com/a/2705678/433558
sed_escape_rhs() {
	sed -e 's/[\/&]/\\&/g' <<<"$*" | sed -e ':a;N;$!ba;s/\n/\\n/g'
}

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
						serverCoreImage="openjdk:$adoptVersion-$javaType-windowsservercore-$windowsVersion" # "openjdk:8u212-b04-jre-windowsservercore-1809", etc
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

			14 | 15 | 16)
				possibleArches=(
					# https://jdk.java.net/15/
					# https://jdk.java.net/16/
					'linux-aarch64'
					'linux-x64'
					'linux-x64-musl'
					'windows-x64'
				)
				declare -A archSha256s=()
				declare -A archUrls=()
				declare -A archVersions=()

				for arch in "${possibleArches[@]}"; do
					case "$arch" in
						linux-*) downloadSuffix="_${arch}_bin.tar.gz" ;;
						windows-*) downloadSuffix="_${arch}_bin.zip" ;;
						*) echo >&2 "error: unknown Oracle arch: '$arch'"; exit 1 ;;
					esac
					if downloadUrl="$(jdk-java-net-download-url "$javaVersion" "$downloadSuffix")" \
						&& [ -n "$downloadUrl" ] \
						&& downloadSha256="$(wget -qO- "$downloadUrl.sha256")" \
						&& [ -n "$downloadSha256" ] \
					; then
						archSha256s["$arch"]="$downloadSha256"
						archUrls["$arch"]="$downloadUrl"
						downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"
						archVersions["$arch"]="$downloadVersion"
					fi
				done

				arch='linux-x64-musl'
				if [ -n "${archSha256s["$arch"]:-}" ]; then
					downloadUrl="${archUrls["$arch"]}"
					downloadSha256="${archSha256s["$arch"]}"
					downloadVersion="${archVersions["$arch"]}"
					unset archUrls["$arch"] archSha256s["$arch"] archVersions["$arch"]

					echo "$javaVersion-$javaType: $downloadVersion (alpine)"

					mkdir -p "$dir/alpine"

					sed -r \
						-e 's!^(ENV JAVA_HOME) .*!\1 /opt/openjdk-'"$javaVersion"'!' \
						-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
						-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
						-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
						Dockerfile-oracle-alpine.template > "$dir/alpine/Dockerfile"
				else
					rm -rf "$dir/alpine"
				fi

				arch='windows-x64'
				if [ -n "${archSha256s["$arch"]:-}" ]; then
					downloadUrl="${archUrls["$arch"]}"
					downloadSha256="${archSha256s["$arch"]}"
					downloadVersion="${archVersions["$arch"]}"
					unset archUrls["$arch"] archSha256s["$arch"] archVersions["$arch"]

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
				else
					rm -rf "$dir/windows"
				fi

				downloadVersion="${archVersions['linux-x64']}"
				linuxArchCase=$'case "$arch" in \\\n'
				for arch in "${possibleArches[@]}"; do
					if [ -n "${archSha256s["$arch"]:-}" ]; then
						if [ "$downloadVersion" != "${archVersions["$arch"]}" ]; then
							echo >&2 "error: version for '$arch' does not match 'linux-x64': $downloadVersion vs ${archVersions["$arch"]}"
							exit 1
						fi
						case "$arch" in
							# dpkg-architecture | "objdump --file-headers /sbin/init | awk -F '[:,]+[[:space:]]+' '$1 == "architecture" { print $2 }'"
							*-x64) caseArch='amd64 | i386:x86-64'; bashbrewArch='amd64' ;;
							*-aarch64) caseArch='arm64 | aarch64'; bashbrewArch='arm64v8' ;;
							*) echo >&2 "error: unknown Oracle case arch: '$arch'"; exit 1 ;;
						esac
						linuxArchCase+="# $bashbrewArch"$'\n'
						newArchCase="$(printf '\t\t%s) \\\n\t\t\tdownloadUrl=%q; \\\n\t\t\tdownloadSha256=%q; \\\n\t\t\t;;' "$caseArch" "${archUrls["$arch"]}" "${archSha256s["$arch"]}")"
						linuxArchCase+="$newArchCase"$' \\\n'
					fi
				done
				linuxArchCase+=$'# fallback\n'
				linuxArchCase+=$'\t\t*) echo >&2 "error: unsupported architecture: \'$arch\'"; exit 1 ;; \\\n'
				linuxArchCase+=$'\tesac'

				echo "$javaVersion-$javaType: $downloadVersion (oracle); ${!archSha256s[*]}"

				for variant in oracle debian slim; do
					[ "$variant" = 'debian' ] && variantDir="$dir" || variantDir="$dir/$variant"
					mkdir -p "$variantDir"
					sed -r \
						-e 's!^(ENV JAVA_HOME) .*!\1 /usr/java/openjdk-'"$javaVersion"'!' \
						-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
						-e 's!%%ARCH-CASE%%!'"$(sed_escape_rhs "$linuxArchCase")"'!g' \
						"Dockerfile-oracle-$variant.template" > "$variantDir/Dockerfile"
				done
				;;

			*)
				echo >&2 "error: unknown java version $javaVersion"
				exit 1
				;;
		esac
	done
done
