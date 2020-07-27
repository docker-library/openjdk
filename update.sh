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
sed_s() {
	local lhs="$1"; shift
	local rhs="$1"; shift
	rhs="$(sed_escape_rhs "$rhs")"
	echo -n "s/$lhs/$rhs/g"
}
sed_s_pre() {
	local lhs="$1"; shift
	local rhs="$1"; shift
	rhs="$(sed_escape_rhs "$rhs")"
	echo -n "s/^($lhs) .*$/\1 $rhs/"
}

for javaVersion in "${versions[@]}"; do
	for javaType in jdk jre; do
		dir="$javaVersion/$javaType"
		[ -d "$dir" ] || continue

		downloadSource= # "adopt", "oracle"
		linuxVersion= # "11.0.8", "15-ea+33", "8u262", etc
		alpineVersion=
		windowsVersion=
		linuxArchCase=
		alpineArchCase=
		windowsDownloadUrl=
		windowsDownloadSha256=

		case "$javaVersion" in
			8 | 11)
				downloadSource='adopt'

				githubUrl="$(adopt-github-url "$javaVersion")"
				sourcesUrl="$(adopt-sources-url "$githubUrl")"
				adoptVersion="$(adopt-version "$githubUrl")"
				javaUrlBase="${sourcesUrl%%-sources_*}-"
				javaUrlVersion="${sourcesUrl#${javaUrlBase}sources_}"
				javaUrlVersion="${javaUrlVersion%.tar.gz}"
				javaUrlBase+="${javaType}_" # "jre_", "jdk_", etc

				possibleArches=(
					# https://github.com/AdoptOpenJDK/openjdk8-upstream-binaries/releases
					# https://github.com/AdoptOpenJDK/openjdk11-upstream-binaries/releases
					'aarch64_linux'
					'x64_linux'
					'x64_windows'
				)
				for arch in "${possibleArches[@]}"; do
					case "$arch" in
						*_linux) downloadSuffix='.tar.gz' ;;
						*_windows) downloadSuffix='.zip' ;;
						*) echo >&2 "error: unknown Adopt Upstream arch: '$arch'"; exit 1 ;;
					esac
					downloadUrl="${javaUrlBase}${arch}_${javaUrlVersion}${downloadSuffix}"
					downloadFile="$(basename "$downloadUrl")"
					if curl -fsSL "$githubUrl" |tac|tac| grep -qF "$downloadFile"; then
						case "$arch" in
							*_windows)
								windowsVersion="$adoptVersion"
								windowsDownloadUrl="$downloadUrl"
								;;
							*_linux)
								linuxVersion="$adoptVersion"
								case "$arch" in
									aarch64_*) caseArch='arm64 | aarch64'; bashbrewArch='arm64v8' ;;
									x64_*) caseArch='amd64 | i386:x86-64'; bashbrewArch='amd64' ;;
									*) echo >&2 "error: unknown Adopt Upstream linux arch: '$arch'"; exit 1 ;;
								esac
								newArchCase="$(printf '\t\t%s) downloadUrl=%q ;;' "$caseArch" "$downloadUrl")"
								newArchCase="# $bashbrewArch"$'\n'"$newArchCase"$' \\\n'
								linuxArchCase+="$newArchCase"
								;;
							*) echo >&2 "error: unknown Adopt Upstream arch: '$arch'"; exit 1 ;;
						esac
					fi
				done
				;;

			14 | 15 | 16)
				downloadSource='oracle'

				possibleArches=(
					# https://jdk.java.net/15/
					# https://jdk.java.net/16/
					'linux-aarch64'
					'linux-x64'
					'linux-x64-musl'
					'windows-x64'
				)
				for arch in "${possibleArches[@]}"; do
					downloadSuffix="_${arch}_bin"
					case "$arch" in
						linux-*) downloadSuffix+='.tar.gz' ;;
						windows-*) downloadSuffix+='.zip' ;;
						*) echo >&2 "error: unknown Oracle arch: '$arch'"; exit 1 ;;
					esac
					if downloadUrl="$(jdk-java-net-download-url "$javaVersion" "$downloadSuffix")" \
						&& [ -n "$downloadUrl" ] \
						&& downloadSha256="$(wget -qO- "$downloadUrl.sha256")" \
						&& [ -n "$downloadSha256" ] \
					; then
						downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"
						case "$arch" in
							windows-*)
								windowsVersion="$downloadVersion"
								windowsDownloadUrl="$downloadUrl"
								windowsDownloadSha256="$downloadSha256"
								;;
							linux-*)
								if [[ "$arch" == *-musl ]]; then
									if [ -z "$alpineVersion" ] || [ "$alpineVersion" = "$downloadVersion" ]; then
										alpineVersion="$downloadVersion"
									else
										echo >&2 "error: mismatched Alpine versions! ('$alpineVersion' vs '$downloadVersion')"
										exit 1
									fi
								else
									if [ -z "$linuxVersion" ] || [ "$linuxVersion" = "$downloadVersion" ]; then
										linuxVersion="$downloadVersion"
									else
										echo >&2 "error: mismatched Linux versions! ('$linuxVersion' vs '$downloadVersion')"
										exit 1
									fi
								fi
								case "$arch" in
									linux-aarch64) caseArch='arm64 | aarch64'; bashbrewArch='arm64v8' ;;
									linux-aarch64-musl) caseArch='aarch64'; bashbrewArch='arm64v8' ;;
									linux-x64) caseArch='amd64 | i386:x86-64'; bashbrewArch='amd64' ;;
									linux-x64-musl) caseArch='x86_64'; bashbrewArch='amd64' ;;
									*) echo >&2 "error: unknown Alpine Oracle arch: '$arch'"; exit 1 ;;
								esac
								newArchCase="$(printf '\t\t%s) \\\n\t\t\tdownloadUrl=%q; \\\n\t\t\tdownloadSha256=%q; \\\n\t\t\t;;' "$caseArch" "$downloadUrl" "$downloadSha256")"
								newArchCase="# $bashbrewArch"$'\n'"$newArchCase"$' \\\n'
								if [[ "$arch" == *-musl ]]; then
									alpineArchCase+="$newArchCase"
								else
									linuxArchCase+="$newArchCase"
								fi
								;;
						esac
					fi
				done
				;;

			*)
				echo >&2 "error: unknown java version $javaVersion"
				exit 1
				;;
		esac

		if [ -z "$downloadSource" ]; then
			echo >&2 "error: missing download source for $javaVersion-$javaType"
			exit 1
		fi

		echo "$javaVersion-$javaType: $linuxVersion ($downloadSource)"
		if [ -n "$alpineVersion" ] && [ "$linuxVersion" != "$alpineVersion" ]; then
			echo "  - alpine: $alpineVersion"
		fi
		if [ -n "$windowsVersion" ] && [ "$linuxVersion" != "$windowsVersion" ]; then
			echo "  - windows: $windowsVersion"
		fi

		# add "arch case" boilerplate
		archCasePrefix=$'case "$arch" in \\\n'
		archCaseSuffix=$'# fallback\n'
		archCaseSuffix+=$'\t\t*) echo >&2 "error: unsupported architecture: \'$arch\'"; exit 1 ;; \\\n'
		archCaseSuffix+=$'\tesac'
		linuxArchCase="${archCasePrefix}${linuxArchCase}${archCaseSuffix}"
		alpineArchCase="${archCasePrefix}${alpineArchCase}${archCaseSuffix}"

		for variant in \
			oraclelinux7 \
			{,slim-}buster \
			alpine3.12 \
			windows/windowsservercore-{1809,ltsc2016} \
			windows/nanoserver-1809 \
		; do
			[ -d "$dir/$variant" ] || continue

			sedArgs=( -r )
			variantVersion=
			variantJavaHome=
			variantArchCase=

			case "$variant" in
				alpine*)
					template="Dockerfile-$downloadSource-alpine.template"
					from="alpine:${variant#alpine}"
					variantVersion="$alpineVersion"
					variantJavaHome="/opt/openjdk-$javaVersion"
					variantArchCase="$alpineArchCase"
					;;
				oraclelinux*)
					template="Dockerfile-$downloadSource-oraclelinux.template"
					from="oraclelinux:${variant#oraclelinux}-slim"
					variantVersion="$linuxVersion"
					variantJavaHome="/usr/java/openjdk-$javaVersion"
					variantArchCase="$linuxArchCase"
					;;
				windows/*)
					variantVersion="$windowsVersion"
					variantJavaHome="C:\\\\openjdk-$javaVersion"
					windowsRelease="$(basename "$variant")" # "windowsservercore-1809", "nanoserver-1809", etc
					windowsVariant="${windowsRelease%%-*}" # "windowsservercore", "nanoserver"
					windowsRelease="${windowsRelease#$windowsVariant-}" # "1809", "ltsc2016", etc
					windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
					template="Dockerfile-$downloadSource-windows-$windowsVariant.template"
					from="mcr.microsoft.com/windows/$windowsVariant:$windowsRelease"
					if [ "$windowsVariant" = 'nanoserver' ]; then
						servercore="openjdk:${variantVersion//+/-}-$javaType-windowsservercore-$windowsRelease"
						sedArgs+=( -e "$(sed_s '%%SERVERCORE-IMAGE%%' "$servercore")" )
					fi
					sedArgs+=( -e "$(sed_s_pre 'ENV JAVA_URL' "$windowsDownloadUrl")" )
					[ -z "$windowsDownloadSha256" ] || sedArgs+=( -e "$(sed_s_pre 'ENV JAVA_SHA256' "$windowsDownloadSha256")" )
					;;
				slim-*)
					template="Dockerfile-$downloadSource-debian-slim.template"
					from="debian:${variant#slim-}-slim"
					variantVersion="$linuxVersion"
					variantJavaHome="/usr/local/openjdk-$javaVersion"
					variantArchCase="$linuxArchCase"
					;;
				*)
					template="Dockerfile-$downloadSource-debian.template"
					case "$javaType" in
						jdk) from="buildpack-deps:$variant-scm" ;;
						jre) from="buildpack-deps:$variant-curl" ;;
					esac
					variantVersion="$linuxVersion"
					variantJavaHome="/usr/local/openjdk-$javaVersion"
					variantArchCase="$linuxArchCase"
					;;
			esac

			sedArgs+=(
				-e "$(sed_s_pre 'FROM' "$from")"
				-e "$(sed_s_pre 'ENV JAVA_VERSION' "$variantVersion")"
				-e "$(sed_s_pre 'ENV JAVA_HOME' "$variantJavaHome")"
			)
			[ -z "$variantArchCase" ] || sedArgs+=( -e "$(sed_s '%%ARCH-CASE%%' "$variantArchCase")" )

			case "$javaType" in
				jre)
					sedArgs+=(
						# no javac or jshell in JRE
						-e '/javac --version/d'
						-e '/jshell/d'
					)
					;;
			esac

			if [ "$javaVersion" = '8' ]; then
				sedArgs+=(
					# no "--" style flags on OpenJDK 8
					-e 's! --version! -version!g'

					# and no "jshell" until OpenJDK 9
					-e '/jshell/d'
				)
			fi

			if [ -z "$variantVersion" ]; then
				echo >&2 "warning: missing '$dir/$variant' version!"
				rm -f "$dir/$variant/Dockerfile"
				continue
			fi

			# extra sed to remove any blank line at EOF that removing "jshell" leaves behind
			sed "${sedArgs[@]}" "$template" | sed -e '${/^$/d;}' > "$dir/$variant/Dockerfile"
		done
	done
done
