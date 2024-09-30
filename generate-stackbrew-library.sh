#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	# https://github.com/docker-library/openjdk/issues/505
	# https://github.com/docker-library/openjdk/pull/510#issue-1327751730
	# > Once Oracle stops publishing OpenJDK 18 builds, those will be removed
	# > 19+ will be removed as soon as each release hits GA 
	# To prevent user breakage, we are not moving "latest", "jre" or "jdk" to early access builds; the last non-ea was 18
	#[18-jdk]='jdk latest'
	#[18-jre]='jre'
)
defaultType='jdk'

image="${1:-openjdk}"

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

if [ "$#" -eq 0 ]; then
	versions="$(jq -r 'keys | map(@sh) | join(" ")' versions.json)"
	eval "set -- $versions"
fi

# sort version numbers with highest first
IFS=$'\n'; set -- $(sort -rV <<<"$*"); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		files="$(
			git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						if ($i ~ /^--from=/) {
							next
						}
						print $i
					}
				}
			'
		)"
		fileCommit Dockerfile $files
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesBase="${BASHBREW_LIBRARY:-https://github.com/docker-library/official-images/raw/HEAD/library}/"

	local parentRepoToArchesStr
	parentRepoToArchesStr="$(
		find -name 'Dockerfile' -exec awk -v officialImagesBase="$officialImagesBase" '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|.*\/.*)(:|$)/ {
					printf "%s%s\n", officialImagesBase, $2
				}
			' '{}' + \
			| sort -u \
			| xargs -r bashbrew cat --format '["{{ .RepoName }}:{{ .TagName }}"]="{{ join " " .TagEntry.Architectures }}"'
	)"
	eval "declare -g -A parentRepoToArches=( $parentRepoToArchesStr )"
}
getArches 'openjdk'

cat <<-EOH
# this file is generated via https://github.com/docker-library/openjdk/blob/$(fileCommit "$self")/$self

Maintainers: Tianon Gravi <admwiggin@gmail.com> (@tianon),
             Joseph Ferguson <yosifkit@gmail.com> (@yosifkit)
GitRepo: https://github.com/docker-library/openjdk.git
EOH

# prints "$2$1$3$1...$N"
join() {
	local sep="$1"; shift
	local out; printf -v out "${sep//%/%%}%s" "$@"
	echo "${out#$sep}"
}

_latest() {
	local javaVersion="$1"; shift
	local variant="$1"; shift

	# "windowsservercore" variants should always be part of the "latest" tag
	if [[ "$variant" == windowsservercore* ]]; then
		return 0
	fi

	if [ "$javaVersion" -ge 12 ]; then
		# version 12+ moves "latest" over to the Oracle-based builds (and includes Windows!)
		if [ "$variant" = "$defaultOracleVariant" ]; then
			return 0
		fi
	else
		# for versions < 12, the Debian variant should be "latest"
		if [ "$variant" = "$defaultDebianVariant" ]; then
			return 0
		fi
	fi

	return 1
}

aliases() {
	local javaVersion="$1"; shift
	local javaType="$1"; shift
	local fullVersion="$1"; shift
	local variants=( "$@" )

	if [[ "$fullVersion" =~ ^[0-9]+$ ]]; then
		# if fullVersion is only digits, add "-rc" to the end (because we're probably in the final-phases of pre-release before GA when we drop support from the image)
		fullVersion="$fullVersion-rc"
	fi

	local bases=()
	while [ "${fullVersion%[.-]*}" != "$fullVersion" ]; do
		bases+=( $fullVersion )
		fullVersion="${fullVersion%[.-]*}"
	done
	bases+=( $fullVersion )
	if [ "$javaVersion" != "$fullVersion" ]; then
		bases+=( $javaVersion )
	fi

	local versionAliases=()
	for base in "${bases[@]}"; do
		versionAliases+=( "$base-$javaType" )
		if [ "$javaType" = "$defaultType" ]; then
			versionAliases+=( "$base" )
		fi
	done

	# add aliases and the prefixed versions (so the silly prefix versions come dead last)
	versionAliases+=( ${aliases[$javaVersion-$javaType]:-} )

	local variantAliases=()
	local variant
	for variant in "${variants[@]}"; do
		case "$variant" in
			latest) variantAliases+=( "${versionAliases[@]}" ) ;;
			'') ;;
			*)
				local thisVariantAliases=( "${versionAliases[@]/%/-$variant}" )
				variantAliases+=( "${thisVariantAliases[@]//latest-/}" )
				;;
		esac
	done

	echo "${variantAliases[@]}"
}

for version; do
	export version

	variants="$(jq -r '.[env.version].variants | map(@sh) | join(" ")' versions.json)"
	eval "variants=( $variants )"

	defaultOracleVariant="$(jq -r '
		.[env.version].variants
		| map(select(
			startswith("oraclelinux")
		))
		| .[0]
	' versions.json)"
	defaultDebianVariant="$(jq -r '
		.[env.version].variants
		| map(select(
			startswith("alpine")
			or startswith("oraclelinux")
			or startswith("slim-")
			or startswith("windows/")
			| not
		))
		| .[0]
	' versions.json)"
	defaultAlpineVariant="$(jq -r '
		.[env.version].variants
		| map(select(
			startswith("alpine")
		))
		| .[0]
	' versions.json)"

	for javaType in jdk jre; do
		export javaType

		for v in "${variants[@]}"; do
			dir="$version/$javaType/$v"
			[ -f "$dir/Dockerfile" ] || continue

			variant="$(basename "$v")"
			export variant

			commit="$(dirCommit "$dir")"

			fullVersion="$(jq -r '.[env.version] | if env.variant | startswith("alpine") then .alpine.version else .version end | gsub("[+]"; "-")' versions.json)"

			variantArches=
			case "$v" in
				windows/*) variantArches='windows-amd64' ;;
				*)
					# see "update.sh" for where these comment lines get embedded
					parent="$(awk 'toupper($1) == "FROM" { print $2; exit }' "$dir/Dockerfile")"
					parentArches="${parentRepoToArches[$parent]:-}"
					variantArches="$(
						comm -12 \
							<(
								jq -r '
									.[env.version]
									| if env.variant | startswith("alpine") then .alpine else . end
									| .[env.javaType].arches
									| keys[]
								' versions.json | sort
							) \
							<(xargs -n1 <<<"$parentArches" | sort)
					)"
					;;
			esac

			sharedTags=()
			for windowsShared in windowsservercore nanoserver; do
				if [[ "$variant" == "$windowsShared"* ]]; then
					sharedTags+=( $(aliases "$version" "$javaType" "$fullVersion" "$windowsShared") )
					break
				fi
			done
			if _latest "$version" "$variant"; then
				sharedTags+=( $(aliases "$version" "$javaType" "$fullVersion" 'latest') )
			fi

			variantAliases=( "$variant" )
			case "$variant" in
				"$defaultOracleVariant") variantAliases+=( oracle ) ;;
				"slim-$defaultDebianVariant") variantAliases+=( slim ) ;;
				"$defaultAlpineVariant") variantAliases+=( alpine ) ;;
			esac

			constraints=
			case "$v" in
				windows/*)
					constraints="$variant"
					if [[ "$variant" == nanoserver-* ]]; then
						# nanoserver variants "COPY --from=...:...-windowsservercore-... ..."
						constraints+=", windowsservercore-${variant#nanoserver-}"
					fi
					;;
			esac

			echo
			echo "Tags: $(join ', ' $(aliases "$version" "$javaType" "$fullVersion" "${variantAliases[@]}"))"
			if [ "${#sharedTags[@]}" -gt 0 ]; then
				echo "SharedTags: $(join ', ' "${sharedTags[@]}")"
			fi
			cat <<-EOE
				Architectures: $(join ', ' $variantArches)
				GitCommit: $commit
				Directory: $dir
			EOE
			[ -z "$constraints" ] || echo "Constraints: $constraints"
		done
	done
done
