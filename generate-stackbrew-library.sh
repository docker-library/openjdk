#!/usr/bin/env bash
set -Eeuo pipefail

declare -A aliases=(
	[11-jdk]='jdk latest'
	[11-jre]='jre'
)
defaultType='jdk'

image="${1:-openjdk}"

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

# sort version numbers with highest first
IFS=$'\n'; versions=( $(echo "${versions[*]}" | sort -rV) ); unset IFS

# get the most recent commit which modified any of "$@"
fileCommit() {
	git log -1 --format='format:%H' HEAD -- "$@"
}

# get the most recent commit which modified "$1/Dockerfile" or any file COPY'd from "$1/Dockerfile"
dirCommit() {
	local dir="$1"; shift
	(
		cd "$dir"
		fileCommit \
			Dockerfile \
			$(git show HEAD:./Dockerfile | awk '
				toupper($1) == "COPY" {
					for (i = 2; i < NF; i++) {
						print $i
					}
				}
			')
	)
}

getArches() {
	local repo="$1"; shift
	local officialImagesUrl='https://github.com/docker-library/official-images/raw/master/library/'

	eval "declare -g -A parentRepoToArches=( $(
		find -name 'Dockerfile' -exec awk '
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|mcr[.]microsoft[.]com[/][^:]+)(:|$)/ {
					print "'"$officialImagesUrl"'" $2
				}
			' '{}' + \
			| sort -u \
			| xargs bashbrew cat --format '[{{ .RepoName }}:{{ .TagName }}]="{{ join " " .TagEntry.Architectures }}"'
	) )"
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

	if [ "$javaVersion" -ge 12 ]; then
		# version 12+ moves "latest" over to the Oracle-based builds
		[ "$variant" = 'oracle' ]
	else
		# for versions < 12, the non-variant variant (which is Debian) should be "latest"
		[ -z "$variant" ]
	fi
}

aliases() {
	local javaVersion="$1"; shift
	local javaType="$1"; shift
	local fullVersion="$1"; shift
	local variants=( "$@" )

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
		if [ -n "$variant" ]; then
			local thisVariantAliases=( "${versionAliases[@]/%/-$variant}" )
			variantAliases+=( "${thisVariantAliases[@]//latest-/}" )
		fi
		if _latest "$javaVersion" "$variant"; then
			variantAliases+=( "${versionAliases[@]}" )
		fi
	done
	versionAliases=( "${variantAliases[@]}" )

	echo "${versionAliases[@]}"
}

for javaVersion in "${versions[@]}"; do
	for javaType in jdk jre; do
		for v in \
			oracle '' slim alpine \
			windows/windowsservercore-{ltsc2016,1709,1803,1809} \
			windows/nanoserver-{sac2016,1709,1803,1809} \
		; do
			dir="$javaVersion/$javaType${v:+/$v}"
			[ -n "$v" ] && variant="$(basename "$v")" || variant=

			[ -f "$dir/Dockerfile" ] || continue

			commit="$(dirCommit "$dir")"

			fullVersion="$(git show "$commit":"$dir/Dockerfile" | awk '$1 == "ENV" && $2 == "JAVA_VERSION" { gsub(/[~+]/, "-", $3); print $3; exit }')"

			variantArches=
			if [ "$javaVersion" -ge 10 ]; then
				# http://jdk.java.net/10/, http://jdk.java.net/11/, http://jdk.java.net/12/, ...
				# (no arches except amd64 supported)
				case "$v" in
					oracle|alpine) variantArches='amd64' ;;
				esac
			fi
			if [ -z "$variantArches" ]; then
				case "$v" in
					windows/*) variantArches='windows-amd64' ;;
					*)
						variantParent="$(awk 'toupper($1) == "FROM" { print $2 }' "$dir/Dockerfile")"
						variantArches="${parentRepoToArches[$variantParent]}"
						;;
				esac
			fi

			sharedTags=()
			for windowsShared in windowsservercore nanoserver; do
				if [[ "$variant" == "$windowsShared"* ]]; then
					sharedTags=( $(aliases "$javaVersion" "$javaType" "$fullVersion" "$windowsShared") )
					break
				fi
			done

			variantAliases=()
			fromTag="$(git show "$commit":"$dir/Dockerfile" | awk -v variant="$variant" '
				$1 == "FROM" {
					switch ($2) {
						case /^mcr.microsoft.com\//:
							$2 = ""
							break
						case /^(alpine|oraclelinux):/:
							gsub(/:/, "", $2) # "alpine3.7", "alpine3.6", etc
							gsub(/-slim$/, "", $2) # "oraclelinux:7-slim"
							break
						default:
							gsub(/^[^:]+:/, "", $2) # peel off "debian:", "buildpack-deps:", etc
							gsub(/-[^-]+$/, "", $2) # peel off "-scm", "-curl", etc
							break
					}
					fromTag = $2
				}
				$1 == "RUN" && $2 == "echo" && $4 == "http://deb.debian.org/debian" && $5 !~ /-backports$/ {
					fromTag = $5 # "experimental", etc
				}
				END {
					if (fromTag) {
						if (variant && fromTag !~ /^(alpine|oraclelinux)/) {
							# "slim-stretch", "slim-jessie", etc
							printf "%s-", variant
						}
						print fromTag
					}
				}
			')"
			if [ -n "$fromTag" ]; then
				variantAliases+=( "$fromTag" )
			fi
			variantAliases+=( "$variant" )

			echo
			echo "Tags: $(join ', ' $(aliases "$javaVersion" "$javaType" "$fullVersion" "${variantAliases[@]}"))"
			if [ "${#sharedTags[@]}" -gt 0 ]; then
				echo "SharedTags: $(join ', ' "${sharedTags[@]}")"
			fi
			cat <<-EOE
				Architectures: $(join ', ' $variantArches)
				GitCommit: $commit
				Directory: $dir
			EOE
			[ "$variant" = "$v" ] || echo "Constraints: $variant"
		done
	done
done
