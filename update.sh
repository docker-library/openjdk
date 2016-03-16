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

alpineVersion='3.3'
alpineMirror="http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/community/x86_64"
curl -fsSL'#' "$alpineMirror/APKINDEX.tar.gz" | tar -zxv APKINDEX

declare -A debCache=()

java-home-script() {
	cat <<'EOD'

# add a simple script that can auto-detect the appropriate JAVA_HOME value
# based on whether the JDK or only the JRE is installed
RUN { \
		echo '#!/bin/sh'; \
		echo 'set -e'; \
		echo; \
		echo 'dirname "$(dirname "$(readlink -f "$(which javac || which java)")")"'; \
	} > /usr/local/bin/docker-java-home \
	&& chmod +x /usr/local/bin/docker-java-home
EOD
}

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

  cp docker-jvm-opts.sh "$version"

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
	EOD

	cat >> "$version/Dockerfile" <<'EOD'

RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*
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

	java-home-script >> "$version/Dockerfile"

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

COPY docker-jvm-opts.sh /usr/local/bin/docker-jvm-opts.sh

		# If you're reading this and have any feedback on how this image could be
		#   improved, please open an issue or a pull request so we can discuss it!
	EOD

	variant='alpine'
	if [ -d "$version/$variant" ]; then
		alpinePackage="openjdk$javaVersion"
		alpineJavaHome="/usr/lib/jvm/java-1.${javaVersion}-openjdk"
		case "$javaType" in
			jdk)
				;;
			jre)
				alpinePackage+="-$javaType"
				alpineJavaHome+="/$javaType"
				;;
		esac
		alpinePackageVersion="$(awk -F: '$1 == "P" { pkg = $2 } pkg == "'"$alpinePackage"'" && $1 == "V" { print $2 }' APKINDEX)"
		alpineFullVersion="${alpinePackageVersion/./u}"
		alpineFullVersion="${alpineFullVersion%%.*}"

		cat > "$version/$variant/Dockerfile" <<-EOD
			#
			# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
			#
			# PLEASE DO NOT EDIT IT DIRECTLY.
			#

			FROM alpine:$alpineVersion

			# A few problems with compiling Java from source:
			#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
			#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
			#       really hairy.

			# Default to UTF-8 file.encoding
			ENV LANG C.UTF-8
		EOD

		java-home-script >> "$version/$variant/Dockerfile"

		cat >> "$version/$variant/Dockerfile" <<-EOD
			ENV JAVA_HOME $alpineJavaHome
		EOD
		cat >> "$version/$variant/Dockerfile" <<-'EOD'
			ENV PATH $PATH:$JAVA_HOME/bin
		EOD
		cat >> "$version/$variant/Dockerfile" <<-EOD

			ENV JAVA_VERSION $alpineFullVersion
			ENV JAVA_ALPINE_VERSION $alpinePackageVersion
		EOD
		cat >> "$version/$variant/Dockerfile" <<EOD

RUN set -x \\
	&& apk add --no-cache \\
		${alpinePackage}="\$JAVA_ALPINE_VERSION" \\
	&& [ "\$JAVA_HOME" = "\$(docker-java-home)" ]
EOD

		travisEnv='\n  - VERSION='"$version"' VARIANT='"$variant$travisEnv"
	fi

	travisEnv='\n  - VERSION='"$version$travisEnv"
done

travis="$(awk -v 'RS=\n\n' '$1 == "env:" { $0 = "env:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

rm APKINDEX
