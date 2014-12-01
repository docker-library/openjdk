#!/bin/bash
set -e

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


for version in "${versions[@]}"; do
	flavor="${version%%-*}" # "openjdk"
	javaVersion="${version#*-}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"
	
	dist="$(grep '^FROM debian:' "$version/Dockerfile" | cut -d: -f2)"
	
	fullVersion=
	case "$flavor" in
		openjdk)
			debianVersion="$(set -x; docker run --rm debian:"$dist" bash -c "apt-get update &> /dev/null && apt-cache show $flavor-$javaVersion-$javaType | grep '^Version: ' | head -1 | cut -d' ' -f2")"
			fullVersion="${debianVersion%%-*}"
			;;
	esac
	
	if [ "$fullVersion" ]; then
		(
			set -x
			sed -ri '
				s/(ENV JAVA_VERSION) .*/\1 '"$fullVersion"'/g;
				s/(ENV JAVA_DEBIAN_VERSION) .*/\1 '"$debianVersion"'/g;
			' "$version/Dockerfile"
		)
	fi
done

