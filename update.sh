#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


for version in "${versions[@]}"; do
	dist="$(grep '^FROM debian:' "$version/Dockerfile" | cut -d: -f2)"
	
	fullVersion="$(set -x; docker run --rm debian:"$dist" bash -c "apt-get update &> /dev/null && apt-cache show openjdk-$version-jdk | grep '^Version: ' | head -1 | cut -d' ' -f2")"
	fullVersion="${fullVersion%%[-~]*}"
	
	(
		set -x
		sed -ri 's/(ENV JAVA_VERSION) .*/\1 '"$fullVersion"'/g' "$version/Dockerfile"
	)
done

