#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
	json='{}'
else
	json="$(< versions.json)"
fi
versions=( "${versions[@]%/}" )

tmp="$(mktemp -d)"
rmTmp="$(printf 'rm -rf %q' "$tmp")"
trap "$rmTmp" EXIT

_get() {
	local url="$1"; shift
	local file="${url////_}"
	file="${file//%/_}"
	file="${file//+/_}"
	file="${file//:/_}"
	file="$tmp/$file"
	if [ ! -s "$file" ]; then
		curl -fsSL "$url" -o "$file" --retry 5 || return 1
	fi
	if [ "$#" -gt 0 ]; then
		grep "$@" "$file"
	else
		cat "$file"
	fi
}

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
		_get "$githubUrl" \
			-oEm1 'href="[^"]+-sources_[^"]+[.]tar[.]gz"' \
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
		_get "$githubUrl" \
			-oE '<title>.+</title>' \
			| grep -oE ' OpenJDK [^ ]+ ' \
			| cut -d' ' -f3
	)" || return 1

	echo "$version"
}

jdk-java-net-download-url() {
	local javaVersion="$1"; shift
	local fileSuffix="$1"; shift
	_get "https://jdk.java.net/$javaVersion/" \
		-Eom1 "https://download.java.net/[^\"]+$fileSuffix"
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

for version in "${versions[@]}"; do
	export version
	doc='{}'
	if [ "$version" -le 11 ]; then
		githubUrl="$(adopt-github-url "$version")"
		sourcesUrl="$(adopt-sources-url "$githubUrl")"
		javaUrlBaseBase="${sourcesUrl%%-sources_*}-"
		javaUrlVersion="${sourcesUrl#${javaUrlBaseBase}sources_}"
		javaUrlVersion="${javaUrlVersion%.tar.gz}"

		adoptVersion="$(adopt-version "$githubUrl")"
		echo "$version: $adoptVersion"
		export adoptVersion
		doc="$(jq <<<"$doc" -c '
			.version = env.adoptVersion
			| .source = "adopt"
		')"

		possibleArches=(
			# https://github.com/AdoptOpenJDK/openjdk8-upstream-binaries/releases
			# https://github.com/AdoptOpenJDK/openjdk11-upstream-binaries/releases
			'aarch64_linux'
			'x64_linux'
			'x64_windows'
		)

		for javaType in jdk jre; do
			export javaType
			javaUrlBase="${javaUrlBaseBase}${javaType}_" # "jre_", "jdk_", etc
			for arch in "${possibleArches[@]}"; do
				case "$arch" in
					*_linux) downloadSuffix='.tar.gz'; bashbrewArch= ;;
					*_windows) downloadSuffix='.zip'; bashbrewArch='windows-' ;;
					*) echo >&2 "error: unknown Adopt Upstream arch: '$arch'"; exit 1 ;;
				esac
				downloadUrl="${javaUrlBase}${arch}_${javaUrlVersion}${downloadSuffix}"
				downloadFile="$(basename "$downloadUrl")"
				if _get "$githubUrl" -qF "$downloadFile"; then
					case "$arch" in
						aarch64_*) bashbrewArch+='arm64v8' ;;
						x64_*) bashbrewArch+='amd64' ;;
						*) echo >&2 "error: unknown Adopt Upstream arch: '$arch'"; exit 1 ;;
					esac
					export bashbrewArch downloadUrl
					doc="$(jq <<<"$doc" -c '
						.[env.javaType].arches[env.bashbrewArch] = {
							url: env.downloadUrl,
						}
					')"
				fi
			done
		done
	else
		doc="$(jq <<<"$doc" -c '
			.source = "oracle"
		')"
		possibleArches=(
			# https://jdk.java.net/17/
			# https://jdk.java.net/18/
			'linux-aarch64'
			'linux-x64'
			'linux-x64-musl'
			'windows-x64'
		)
		for arch in "${possibleArches[@]}"; do
			downloadSuffix="_${arch}_bin"
			case "$arch" in
				linux-*) downloadSuffix+='.tar.gz'; bashbrewArch= ;;
				windows-*) downloadSuffix+='.zip'; bashbrewArch='windows-' ;;
				*) echo >&2 "error: unknown Oracle arch: '$arch'"; exit 1 ;;
			esac
			jqExprPrefix=
			if [[ "$arch" == *-musl ]]; then
				jqExprPrefix='.alpine'
			fi
			if downloadUrl="$(jdk-java-net-download-url "$version" "$downloadSuffix")" \
				&& [ -n "$downloadUrl" ] \
				&& downloadSha256="$(_get "$downloadUrl.sha256")" \
				&& [ -n "$downloadSha256" ] \
			; then
				downloadVersion="$(jdk-java-net-download-version "$version" "$downloadUrl")"
				currentVersion="$(jq <<<"$doc" -r "$jqExprPrefix.version // \"\"")"
				if [ -n "$currentVersion" ] && [ "$currentVersion" != "$downloadVersion" ]; then
					echo >&2 "error: Oracle version mismatch: '$currentVersion' vs '$downloadVersion'"
					exit 1
				elif [ -z "$currentVersion" ]; then
					echo "$version: $downloadVersion${jqExprPrefix:+ (alpine)}"
				fi
				case "$arch" in
					*-aarch64*) bashbrewArch+='arm64v8' ;;
					*-x64*) bashbrewArch+='amd64' ;;
					*) echo >&2 "error: unknown Oracle arch: '$arch'"; exit 1 ;;
				esac
				export arch bashbrewArch downloadUrl downloadSha256 downloadVersion
				doc="$(jq <<<"$doc" -c '
					'"$jqExprPrefix"'.version = env.downloadVersion
					| '"$jqExprPrefix"'.jdk.arches[env.bashbrewArch] = {
						url: env.downloadUrl,
						sha256: env.downloadSha256,
					}
				')"
			fi
		done
	fi

	if ! jq <<<"$doc" -e '[ .. | objects | select(has("arches")) | .arches | has("amd64") ] | all' &> /dev/null; then
		echo >&2 "error: missing 'amd64' for '$version'; cowardly refusing to continue! (because this is almost always a scraping flake or similar bug)"
		exit 1
	fi

	if [ "$version" = '11' ]; then
		for arch in arm64v8 windows-amd64; do
			export arch
			if ! jq <<<"$doc" -e '[ .. | objects | select(has("arches")) | .arches | has(env.arch) ] | all' &> /dev/null; then
				echo >&2 "error: missing '$arch' for '$version'; cowardly refusing to continue! (because this is almost always a scraping flake or similar bug)"
				exit 1
			fi
		done
	fi

	json="$(jq <<<"$json" -c --argjson doc "$doc" '
		.[env.version] = $doc + {
			variants: [
				(
					"8",
					"7"
				| "oraclelinux" + .),
				(
					"bullseye",
					"buster"
				| ., "slim-" + .),
				if $doc.alpine then
					"3.14",
					"3.13"
				| "alpine" + . else empty end,
				if $doc.jdk.arches | keys | any(startswith("windows-")) then
					(
						"1809",
						"ltsc2016"
					| "windows/windowsservercore-" + .),
					(
						"1809"
					| "windows/nanoserver-" + .)
				else empty end
			],
		}
	')"
done

jq <<<"$json" -S . > versions.json
