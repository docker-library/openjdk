#!/bin/bash
set -eu

declare -A aliases=(
	[8-jdk]='jdk latest'
	[8-jre]='jre'
)
defaultType='jdk'

image="${1:-openjdk}"

self="$(basename "$BASH_SOURCE")"
cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )

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
				toupper($1) == "FROM" && $2 !~ /^('"$repo"'|scratch|microsoft\/[^:]+)(:|$)/ {
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

aliases() {
	local javaVersion="$1"; shift
	local javaType="$1"; shift
	local fullVersion="$1"; shift
	local variant="${1:-}" # optional

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

	# generate "openjdkPrefix" before adding aliases ("latest") so we avoid tags like "openjdk-latest"
	local openjdkPrefix=( "${versionAliases[@]/#/openjdk-}" )

	# add aliases and the prefixed versions (so the silly prefix versions come dead last)
	versionAliases+=( ${aliases[$javaVersion-$javaType]:-} )

	if [ "$image" = 'java' ]; then
		# add "openjdk" prefixes (these should stay very last so their use is properly discouraged)
		versionAliases+=( "${openjdkPrefix[@]}" )
	fi

	if [ "$variant" ]; then
		versionAliases=( "${versionAliases[@]/%/-$variant}" )
		versionAliases=( "${versionAliases[@]//latest-/}" )
	fi

	echo "${versionAliases[@]}"
}

for version in "${versions[@]}"; do
	javaVersion="$version" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-$javaType}" # "6"

	for v in \
		'' slim alpine \
		windows/windowsservercore windows/nanoserver \
	; do
		dir="$version${v:+/$v}"
		[ -n "$v" ] && variant="$(basename "$v")" || variant=

		[ -f "$dir/Dockerfile" ] || continue

		commit="$(dirCommit "$dir")"

		fullVersion="$(git show "$commit":"$dir/Dockerfile" | awk '$1 == "ENV" && $2 == "JAVA_VERSION" { gsub(/[~+]/, "-", $3); print $3; exit }')"

		case "$v" in
			windows/*) variantArches='windows-amd64' ;;
			*)
				variantParent="$(awk 'toupper($1) == "FROM" { print $2 }' "$dir/Dockerfile")"
				variantArches="${parentRepoToArches[$variantParent]}"
				;;
		esac

		echo
		cat <<-EOE
			Tags: $(join ', ' $(aliases "$javaVersion" "$javaType" "$fullVersion" "$variant"))
			Architectures: $(join ', ' $variantArches)
			GitCommit: $commit
			Directory: $dir
		EOE
		[ "$variant" = "$v" ] || echo "Constraints: $variant"
	done
done
