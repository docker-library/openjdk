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
	
	dist="$(grep '^FROM ' "$version/Dockerfile" | cut -d' ' -f2)"
	
	fullVersion=
	case "$flavor" in
		openjdk)
			debianVersion="$(set -x; docker run --rm "$dist" bash -c "apt-get update &> /dev/null && apt-cache show $flavor-$javaVersion-$javaType | grep '^Version: ' | head -1 | cut -d' ' -f2")"
			fullVersion="${debianVersion%%-*}"
			;;
	esac
	
	if [ "$fullVersion" ]; then
		(
			set -x
			sed -ri '
				s/\b(JAVA_VERSION)=[^ \t\n]*/\1='"$fullVersion"'/g
				s/\b(JAVA_DEBIAN_VERSION)=[^ \t\n]*/\1='"$debianVersion"'/g;
			' "$version/Dockerfile"
		)
	fi
done

