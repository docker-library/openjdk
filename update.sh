#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )


travisEnv=
for version in "${versions[@]}"; do
	flavor="${version%%-*}" # "openjdk"
	javaVersion="${version#*-}" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"

	# Determine debian:SUITE based on FROM directive
	dist="$(grep '^FROM ' "$version/Dockerfile" | cut -d' ' -f2 | sed -r 's/^buildpack-deps:(\w+)-.*$/debian:\1/')"

	# Use debian:SUITE-backports if backports packages are required
	if grep -q backports "$version/Dockerfile"; then
		dist+="-backports"
	fi

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
				s/(ENV JAVA_VERSION) .*/\1 '"$fullVersion"'/g;
				s/(ENV JAVA_DEBIAN_VERSION) .*/\1 '"$debianVersion"'/g;
			' "$version/Dockerfile"
		)
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
