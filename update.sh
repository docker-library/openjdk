#!/bin/bash
set -eo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

declare -A suites=(
	[6]='wheezy'
	[7]='jessie'
	[8]='jessie'
	[9]='sid'
)

declare -A addSuites=(
	[8]='jessie-backports'
	[9]='experimental'
)

declare -A variants=(
	[jre]='curl'
	[jdk]='scm'
)

declare -A debCache=()

travisEnv=
for version in "${versions[@]}"; do
	javaVersion="$version" # "6-jdk"
	javaType="${javaVersion##*-}" # "jdk"
	javaVersion="${javaVersion%-*}" # "6"

	suite="${suites[$javaVersion]}"
	addSuite="${addSuites[$javaVersion]}"
	variant="${variants[$javaType]}"

	javaHome="/usr/lib/jvm/java-$javaVersion-openjdk-$(dpkg --print-architecture)"
	if [ "$javaType" = 'jre' -a "$javaVersion" -lt 9 ]; then
		# woot, this hackery stopped in OpenJDK 9+!
		javaHome+='/jre'
	fi

	needCaHack=
	if [ "$javaVersion" -ge 8 ]; then
		needCaHack=1
	fi

	dist="debian:${addSuite:-$suite}"
	debianPackage="openjdk-$javaVersion-$javaType"
	if [ "$javaType" = 'jre' ]; then
		debianPackage+='-headless'
	fi
	debCacheKey="$dist-openjdk-$javaVersion"
	debianVersion="${debCache[$debCacheKey]}"
	if [ -z "$debianVersion" ]; then
		debianVersion="$(set -x; docker run --rm "$dist" bash -c 'apt-get update -qq && apt-cache show "$@"' -- "$debianPackage" |tac|tac| awk -F ': ' '$1 == "Version" { print $2; exit }')"
		debCache["$debCacheKey"]="$debianVersion"
	fi
	fullVersion="${debianVersion%%-*}"

	cat > "$version/Dockerfile" <<-EOD
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

		FROM buildpack-deps:$suite-$variant

		# A few problems with compiling Java from source:
		#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
		#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
		#       really hairy.

		RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*
	EOD

	if [ "$addSuite" ]; then
		cat >> "$version/Dockerfile" <<-EOD

			RUN echo 'deb http://httpredir.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list
		EOD
	fi

	cat >> "$version/Dockerfile" <<-EOD

		# Default to UTF-8 file.encoding
		ENV LANG C.UTF-8
	EOD

	cat >> "$version/Dockerfile" <<EOD

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \\
		echo '#!/bin/bash'; \\
		echo 'set -e'; \\
		echo; \\
		echo 'dirname "\$(dirname "\$(readlink -f "\$(which javac || which java)")")"'; \\
	} > /usr/local/bin/docker-java-home \\
	&& chmod +x /usr/local/bin/docker-java-home
EOD

	cat >> "$version/Dockerfile" <<-EOD

		ENV JAVA_HOME $javaHome

		ENV JAVA_VERSION $fullVersion
		ENV JAVA_DEBIAN_VERSION $debianVersion
	EOD

	if [ "$needCaHack" ]; then
		cat >> "$version/Dockerfile" <<-EOD

			# see https://bugs.debian.org/775775
			# and https://github.com/docker-library/java/issues/19#issuecomment-70546872
			ENV CA_CERTIFICATES_JAVA_VERSION 20140324
		EOD
	fi

	cat >> "$version/Dockerfile" <<EOD

RUN set -x \\
	&& apt-get update \\
	&& apt-get install -y \\
		$debianPackage="\$JAVA_DEBIAN_VERSION" \\
EOD
	if [ "$needCaHack" ]; then
		cat >> "$version/Dockerfile" <<EOD
		ca-certificates-java="\$CA_CERTIFICATES_JAVA_VERSION" \\
EOD
	fi
	cat >> "$version/Dockerfile" <<EOD
	&& rm -rf /var/lib/apt/lists/* \\
	&& [ "\$JAVA_HOME" = "\$(docker-java-home)" ]
EOD

	if [ "$needCaHack" ]; then
		cat >> "$version/Dockerfile" <<-EOD

			# see CA_CERTIFICATES_JAVA_VERSION notes above
			RUN /var/lib/dpkg/info/ca-certificates-java.postinst configure
		EOD
	fi

	cat >> "$version/Dockerfile" <<-EOD

		# If you're reading this and have any feedback on how this image could be
		#   improved, please open an issue or a pull request so we can discuss it!
	EOD

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml
