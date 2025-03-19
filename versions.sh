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
	possibleArches=(
		# https://jdk.java.net/25/
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

	if ! jq <<<"$doc" -e '[ .. | objects | select(has("arches")) | .arches | has("amd64") ] | all' &> /dev/null; then
		echo >&2 "error: missing 'amd64' for '$version'; cowardly refusing to continue! (because this is almost always a scraping flake or similar bug)"
		exit 1
	fi

	json="$(jq <<<"$json" -c --argjson doc "$doc" '
		.[env.version] = $doc + {
			variants: [
				(
					"9",
					"8",
					empty
				| "oraclelinux" + .),
				(
					"bookworm",
					"bullseye",
					empty
				| ., "slim-" + .),
				if $doc.alpine then
					"3.19",
					"3.18",
					empty
				| "alpine" + . else empty end,
				if $doc.jdk.arches | keys | any(startswith("windows-")) then
					(
						"ltsc2025",
						"ltsc2022",
						"1809",
						empty
					| "windows/windowsservercore-" + .),
					(
						"ltsc2025",
						"ltsc2022",
						"1809",
						empty
					| "windows/nanoserver-" + .)
				else empty end
			],
		}
	')"
done

jq <<<"$json" -S . > versions.json
