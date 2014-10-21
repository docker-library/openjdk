#!/bin/bash
set -e

declare -A aliases
aliases=(
	[openjdk-7-jdk]='jdk latest'
	[openjdk-7-jre]='jre'
)
defaultType='jdk'
defaultFlavor='openjdk'

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( */ )
versions=( "${versions[@]%/}" )
url='git://github.com/docker-library/java'

echo '# maintainer: InfoSiftr <github@infosiftr.com> (@infosiftr)'

for version in "${versions[@]}"; do
	commit="$(git log -1 --format='format:%H' -- "$version")"
	
	flavor="${version%%-*}" # "openjdk"
	javaVersion="${version#*-}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"
	
	fullVersion="$(grep -m1 'ENV JAVA_VERSION ' "$version/Dockerfile" | cut -d' ' -f3 | tr '~' '-')"
	
	bases=( $flavor-$fullVersion )
	if [ "${fullVersion%-*}" != "$fullVersion" ]; then
		bases+=( $flavor-${fullVersion%-*} ) # like "8u40-b09
	fi
	bases+=( $flavor-$javaVersion )
	if [ "$flavor" = "$defaultFlavor" ]; then
		for base in "${bases[@]}"; do
			bases+=( "${base#$flavor-}" )
		done
	fi
	
	versionAliases=()
	for base in "${bases[@]}"; do
		versionAliases+=( "$base-$javaType" )
		if [ "$javaType" = "$defaultType" ]; then
			versionAliases+=( "$base" )
		fi
	done
	versionAliases+=( ${aliases[$version]} )
	
	echo
	for va in "${versionAliases[@]}"; do
		echo "$va: ${url}@${commit} $version"
	done
done
