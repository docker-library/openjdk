#!/usr/bin/env bash
set -Eeuo pipefail

cd "$(dirname "$(readlink -f "$BASH_SOURCE")")"

versions=( "$@" )
if [ ${#versions[@]} -eq 0 ]; then
	versions=( */ )
fi
versions=( "${versions[@]%/}" )

# sort version numbers with lowest first
IFS=$'\n'; versions=( $(sort -V <<<"${versions[*]}") ); unset IFS

declare -A suites=(
	# FROM buildpack-deps:SUITE-xxx
	[7]='jessie'
	[8]='stretch'
	[11]='stretch'
)
defaultAlpineVersion='3.9'
declare -A alpineVersions=(
	#[8]='3.7'
)

declare -A addSuites=(
	# there is no "buildpack-deps:backports-xxx"
	[11]='stretch-backports'
)

declare -A buildpackDepsVariants=(
	[jre]='curl'
	[jdk]='scm'
)

declare -A debCache=()
declare -A debVerCache=()
dpkgArch="$(dpkg --print-architecture)"
debian-latest-version() {
	local package="$1"; shift
	local suite="$1"; shift

	local debVerCacheKey="$package-$suite"
	if [ -n "${debVerCache[$debVerCacheKey]:-}" ]; then
		echo "${debVerCache[$debVerCacheKey]}"
		return
	fi

	local debMirror='https://deb.debian.org/debian'
	local secMirror='http://security.debian.org'

	local remotes=( "$debMirror/dists/$suite/main" )
	case "$suite" in
		sid) ;;

		experimental)
			remotes+=( "$debMirror/dists/sid/main" )
			;;

		*-backports)
			suite="${suite%-backports}"
			remotes+=( "$debMirror/dists/$suite/main" )
			;&
		*)
			remotes+=(
				"$debMirror/dists/$suite-updates/main"
				"$secMirror/dists/$suite/updates/main"
			)
			;;
	esac

	local latestVersion= remote=
	for remote in "${remotes[@]}"; do
		if [ -z "${debCache[$remote]:-}" ]; then
			local urlBase="$remote/binary-$dpkgArch/Packages" url= decomp=
			for comp in xz bz2 gz ''; do
				if wget --quiet --spider "$urlBase.$comp"; then
					url="$urlBase.$comp"
					case "$comp" in
						xz) decomp='xz -d' ;;
						bz2) decomp='bunzip2' ;;
						gz) decomp='gunzip' ;;
						'') decomp='cat' ;;
					esac
					break
				fi
			done
			if [ -z "$url" ]; then
				continue
			fi
			debCache[$remote]="$(wget -qO- "$url" | eval "$decomp")"
		fi
		IFS=$'\n'
		local versions=( $(
			awk -F ': ' '
				$1 == "Package" { pkg = $2 }
				pkg == "'"$package"'" && $1 == "Version" { print $2 }
			' <<<"${debCache[$remote]}"
		) )
		unset IFS
		local version=
		for version in ${versions[@]+"${versions[@]}"}; do
			if [ -z "$latestVersion" ] || dpkg --compare-versions "$version" '>>' "$latestVersion"; then
				latestVersion="$version"
			fi
		done
	done

	debVerCache[$debVerCacheKey]="$latestVersion"
	echo "$latestVersion"
}

template-generated-warning() {
	local from="$1"; shift
	local javaVersion="$1"; shift

	cat <<-EOD
		#
		# NOTE: THIS DOCKERFILE IS GENERATED VIA "update.sh"
		#
		# PLEASE DO NOT EDIT IT DIRECTLY.
		#

		FROM $from

		# A few reasons for installing distribution-provided OpenJDK:
		#
		#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
		#
		#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
		#     really hairy.
		#
		#     For some sample build times, see Debian's buildd logs:
		#       https://buildd.debian.org/status/logs.php?pkg=openjdk-$javaVersion
	EOD
}

template-java-home-script() {
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

template-contribute-footer() {
	cat <<-'EOD'

		# If you're reading this and have any feedback on how this image could be
		# improved, please open an issue or a pull request so we can discuss it!
		#
		#   https://github.com/docker-library/openjdk/issues
	EOD
}

jdk-java-net-download-url() {
	local javaVersion="$1"; shift
	local fileSuffix="$1"; shift
	wget -qO- "https://jdk.java.net/$javaVersion/" \
		| tac|tac \
		| grep -Eom1 "https://download.java.net/[^\"]+$fileSuffix"
}

jdk-java-net-download-version() {
	local javaVersion="$1"; shift
	local downloadUrl="$1"; shift

	downloadVersion="$(grep -Eom1 "openjdk-$javaVersion[^_]*_" <<<"$downloadUrl")"
	downloadVersion="${downloadVersion%_}"
	downloadVersion="${downloadVersion#openjdk-}"
	if [ "$javaVersion" = '11' ]; then
		# 11 is now GA, so drop any +NN (https://github.com/docker-library/openjdk/pull/235#issuecomment-425378941)
		# future releases will be 11.0.1, for example
		downloadVersion="${downloadVersion%%+*}"
	fi

	echo "$downloadVersion"
}

travisEnv=
appveyorEnv=
for javaVersion in "${versions[@]}"; do
	for javaType in jdk jre; do
		dir="$javaVersion/$javaType"

		suite="${suites[$javaVersion]:-}"
		if [ -n "$suite" ]; then
			addSuite="${addSuites[$javaVersion]:-}"
			buildpackDepsVariant="${buildpackDepsVariants[$javaType]}"

			debianPackage="openjdk-$javaVersion-$javaType"
			debSuite="${addSuite:-$suite}"
			debian-latest-version "$debianPackage" "$debSuite" > /dev/null # prime the cache
			debianVersion="$(debian-latest-version "$debianPackage" "$debSuite")"
			fullVersion="${debianVersion%%-*}"
			fullVersion="${fullVersion#*:}"

			tilde='~'
			case "$javaVersion" in
				11)
					# https://github.com/docker-library/openjdk/pull/235#issuecomment-425378941
					fullVersion="${fullVersion%%$tilde*}"
					fullVersion="${fullVersion%%+*}"
					;;
			esac
			fullVersion="${fullVersion//$tilde/-}"

			echo "$javaVersion-$javaType: $fullVersion (debian $debianVersion)"

			template-generated-warning "buildpack-deps:$suite-$buildpackDepsVariant" "$javaVersion" > "$dir/Dockerfile"

			cat >> "$dir/Dockerfile" <<'EOD'

RUN apt-get update && apt-get install -y --no-install-recommends \
		bzip2 \
		unzip \
		xz-utils \
	&& rm -rf /var/lib/apt/lists/*
EOD

			if [ "$addSuite" ]; then
				cat >> "$dir/Dockerfile" <<-EOD

					RUN echo 'deb http://deb.debian.org/debian $addSuite main' > /etc/apt/sources.list.d/$addSuite.list
				EOD
			fi

			cat >> "$dir/Dockerfile" <<-EOD

				# Default to UTF-8 file.encoding
				ENV LANG C.UTF-8
			EOD

			template-java-home-script >> "$dir/Dockerfile"

			jreSuffix=
			if [ "$javaType" = 'jre' -a "$javaVersion" -lt 9 ]; then
				# woot, this hackery stopped in OpenJDK 9+!
				jreSuffix='/jre'
			fi
			cat >> "$dir/Dockerfile" <<-EOD

				# do some fancy footwork to create a JAVA_HOME that's cross-architecture-safe
				RUN ln -svT "/usr/lib/jvm/java-$javaVersion-openjdk-\$(dpkg --print-architecture)" /docker-java-home
				ENV JAVA_HOME /docker-java-home$jreSuffix

				ENV JAVA_VERSION $fullVersion
				ENV JAVA_DEBIAN_VERSION $debianVersion
			EOD

			sillyCaSymlink=$'\\'
			sillyCaSymlinkCleanup=$'\\'
			case "$javaVersion" in
				11)
					sillyCaSymlink+=$'\n# ca-certificates-java does not work on src:openjdk-11 with no-install-recommends: (https://bugs.debian.org/914860, https://bugs.debian.org/775775)\n# /var/lib/dpkg/info/ca-certificates-java.postinst: line 56: java: command not found\n\tln -svT /docker-java-home/bin/java /usr/local/bin/java; \\\n\t\\'
					sillyCaSymlinkCleanup+=$'\n\trm -v /usr/local/bin/java; \\\n\t\\'

					sillyCaSymlinkCleanup+=$'\n# ca-certificates-java does not work on src:openjdk-11: (https://bugs.debian.org/914424, https://bugs.debian.org/894979, https://salsa.debian.org/java-team/ca-certificates-java/commit/813b8c4973e6c4bb273d5d02f8d4e0aa0b226c50#d4b95d176f05e34cd0b718357c532dc5a6d66cd7_54_56)\n\tkeytool -importkeystore -srckeystore /etc/ssl/certs/java/cacerts -destkeystore /etc/ssl/certs/java/cacerts.jks -deststoretype JKS -srcstorepass changeit -deststorepass changeit -noprompt; \\\n\tmv /etc/ssl/certs/java/cacerts.jks /etc/ssl/certs/java/cacerts; \\\n\t/var/lib/dpkg/info/ca-certificates-java.postinst configure; \\\n\t\\'
					;;
			esac

			cat >> "$dir/Dockerfile" <<EOD

RUN set -ex; \\
	\\
# deal with slim variants not having man page directories (which causes "update-alternatives" to fail)
	if [ ! -d /usr/share/man/man1 ]; then \\
		mkdir -p /usr/share/man/man1; \\
	fi; \\
	$sillyCaSymlink
	apt-get update; \\
	apt-get install -y --no-install-recommends \\
		$debianPackage="\$JAVA_DEBIAN_VERSION" \\
	; \\
	rm -rf /var/lib/apt/lists/*; \\
	$sillyCaSymlinkCleanup
# verify that "docker-java-home" returns what we expect
	[ "\$(readlink -f "\$JAVA_HOME")" = "\$(docker-java-home)" ]; \\
	\\
# update-alternatives so that future installs of other OpenJDK versions don't change /usr/bin/java
	update-alternatives --get-selections | awk -v home="\$(readlink -f "\$JAVA_HOME")" 'index(\$3, home) == 1 { \$2 = "manual"; print | "update-alternatives --set-selections" }'; \\
# ... and verify that it actually worked for one of the alternatives we care about
	update-alternatives --query java | grep -q 'Status: manual'
EOD

			if [ "$javaType" = 'jdk' ] && [ "$javaVersion" -ge 10 ]; then
				cat >> "$dir/Dockerfile" <<-'EOD'

					# https://docs.oracle.com/javase/10/tools/jshell.htm
					# https://en.wikipedia.org/wiki/JShell
					CMD ["jshell"]
				EOD
			fi

			template-contribute-footer >> "$dir/Dockerfile"
		fi

		if [ -d "$dir/alpine" ] && [ "$javaVersion" -lt 10 ]; then
			alpineVersion="${alpineVersions[$javaVersion]:-$defaultAlpineVersion}"
			alpinePackage="openjdk$javaVersion"
			alpineJavaHome="/usr/lib/jvm/java-1.${javaVersion}-openjdk"
			alpinePathAdd="$alpineJavaHome/jre/bin:$alpineJavaHome/bin"
			case "$javaType" in
				jdk)
					;;
				jre)
					alpinePackage+="-$javaType"
					alpineJavaHome+="/$javaType"
					;;
			esac

			alpineMirror="http://dl-cdn.alpinelinux.org/alpine/v${alpineVersion}/community/x86_64"
			alpinePackageVersion="$(
				wget -qO- "$alpineMirror/APKINDEX.tar.gz" \
					| tar --extract --gzip --to-stdout APKINDEX \
					| awk -F: '$1 == "P" { pkg = $2 } pkg == "'"$alpinePackage"'" && $1 == "V" { print $2 }'
			)"

			alpineFullVersion="${alpinePackageVersion/./u}"
			alpineFullVersion="${alpineFullVersion%%.*}"

			echo "$javaVersion-$javaType: $alpineFullVersion (alpine $alpinePackageVersion)"

			template-generated-warning "alpine:$alpineVersion" "$javaVersion" > "$dir/alpine/Dockerfile"

			cat >> "$dir/alpine/Dockerfile" <<-'EOD'

				# Default to UTF-8 file.encoding
				ENV LANG C.UTF-8
			EOD

			template-java-home-script >> "$dir/alpine/Dockerfile"

			cat >> "$dir/alpine/Dockerfile" <<-EOD
				ENV JAVA_HOME $alpineJavaHome
				ENV PATH \$PATH:$alpinePathAdd
			EOD
			cat >> "$dir/alpine/Dockerfile" <<-EOD

				ENV JAVA_VERSION $alpineFullVersion
				ENV JAVA_ALPINE_VERSION $alpinePackageVersion
			EOD
			cat >> "$dir/alpine/Dockerfile" <<EOD

RUN set -x \\
	&& apk add --no-cache \\
		${alpinePackage}="\$JAVA_ALPINE_VERSION" \\
	&& [ "\$JAVA_HOME" = "\$(docker-java-home)" ]
EOD

			template-contribute-footer >> "$dir/alpine/Dockerfile"
		elif [ -d "$dir/alpine" ]; then
			downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_linux-x64-musl_bin.tar.gz')"
			downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
			downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

			echo "$javaVersion-$javaType: $downloadVersion (alpine)"

			sed -r \
				-e 's!^(ENV JAVA_HOME) .*!\1 /opt/openjdk-'"$javaVersion"'!' \
				-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
				-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
				-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
				Dockerfile-alpine.template > "$dir/alpine/Dockerfile"
		fi

		if [ -d "$dir/oracle" ]; then
			downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_linux-x64_bin.tar.gz')"
			downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
			downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

			echo "$javaVersion-$javaType: $downloadVersion (oracle)"

			sed -r \
				-e 's!^(ENV JAVA_HOME) .*!\1 /usr/java/openjdk-'"$javaVersion"'!' \
				-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
				-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
				-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
				Dockerfile-oracle.template > "$dir/oracle/Dockerfile"
		fi

		if [ -d "$dir/slim" ]; then
			# for the "slim" variants,
			#   - swap "buildpack-deps:SUITE-xxx" for "debian:SUITE-slim"
			#   - swap "openjdk-N-(jre|jdk) for the -headless versions, where available (openjdk-8+ only for JDK variants)
			sed -r \
				-e 's!^FROM buildpack-deps:([^-]+)(-.+)?!FROM debian:\1-slim!' \
				-e 's!(openjdk-([0-9]+-jre|([89][0-9]*|[0-9][0-9]+)-jdk))=!\1-headless=!g' \
				"$dir/Dockerfile" > "$dir/slim/Dockerfile"
		fi

		if [ -d "$dir/windows" ]; then
			case "$javaVersion" in
				8 | 10)
					ojdkbuildVersion="$(
						git ls-remote --tags 'https://github.com/ojdkbuild/ojdkbuild.git' \
							| cut -d/ -f3 \
							| grep -E '^(1[.])?'"$javaVersion"'[.-]' \
							| sort -V \
							| tail -1
					)"
					if [ -z "$ojdkbuildVersion" ]; then
						echo >&2 "error: '$dir/windows' exists, but Java $javaVersion doesn't appear to have a corresponding ojdkbuild release"
						exit 1
					fi
					ojdkbuildZip="$(
						wget -qO- "https://github.com/ojdkbuild/ojdkbuild/releases/tag/$ojdkbuildVersion" \
							| grep --only-matching -E 'java-[0-9.]+-openjdk-[b0-9.-]+[.]ojdkbuild(ea)?[.]windows[.]x86_64[.]zip' \
							| sort -u
					)"
					if [ -z "$ojdkbuildZip" ]; then
						echo >&2 "error: $ojdkbuildVersion doesn't appear to have the release file we need (yet?)"
						exit 1
					fi
					ojdkbuildSha256="$(wget -qO- "https://github.com/ojdkbuild/ojdkbuild/releases/download/${ojdkbuildVersion}/${ojdkbuildZip}.sha256" | cut -d' ' -f1)"
					if [ -z "$ojdkbuildSha256" ]; then
						echo >&2 "error: $ojdkbuildVersion seems to have $ojdkbuildZip, but no sha256 for it"
						exit 1
					fi

					case "$ojdkbuildVersion" in
						*-ea-* )
							# convert "9-ea-b154-1" into "9-b154"
							ojdkJavaVersion="$(sed -r 's/-ea-/-/' <<<"$ojdkbuildVersion" | cut -d- -f1,2)"
							;;

						1.* )
							# convert "1.8.0.111-3" into "8u111"
							ojdkJavaVersion="$(cut -d. -f2,4 <<<"$ojdkbuildVersion" | cut -d- -f1 | tr . u)"
							;;

						10.* )
							# convert "10.0.1-1.b10" into "10.0.1"
							ojdkJavaVersion="${ojdkbuildVersion%%-*}"
							;;

						* )
							echo >&2 "error: unable to parse ojdkbuild version $ojdkbuildVersion"
							exit 1
							;;
					esac

					echo "$javaVersion-$javaType: $ojdkJavaVersion (windows ojdkbuild $ojdkbuildVersion)"

					sed -ri \
						-e 's/^(ENV JAVA_VERSION) .*/\1 '"$ojdkJavaVersion"'/' \
						-e 's/^(ENV JAVA_OJDKBUILD_VERSION) .*/\1 '"$ojdkbuildVersion"'/' \
						-e 's/^(ENV JAVA_OJDKBUILD_ZIP) .*/\1 '"$ojdkbuildZip"'/' \
						-e 's/^(ENV JAVA_OJDKBUILD_SHA256) .*/\1 '"$ojdkbuildSha256"'/' \
						"$dir"/windows/*/Dockerfile
					;;

				*)
					downloadUrl="$(jdk-java-net-download-url "$javaVersion" '_windows-x64_bin.zip')"
					downloadSha256="$(wget -qO- "$downloadUrl.sha256")"
					downloadVersion="$(jdk-java-net-download-version "$javaVersion" "$downloadUrl")"

					echo "$javaVersion-$javaType: $downloadVersion (windows)"

					for winD in "$dir"/windows/*/; do
						winD="${winD%/}"
						windowsVersion="$(basename "$winD")"
						windowsVariant="${windowsVersion%%-*}" # "windowsservercore", "nanoserver"
						windowsVersion="${windowsVersion#$windowsVariant-}" # "1803", "ltsc2016", etc
						windowsVariant="${windowsVariant#windows}" # "servercore", "nanoserver"
						sed -r \
							-e 's!^(FROM) .*$!\1 mcr.microsoft.com/windows/'"$windowsVariant"':'"$windowsVersion"'!' \
							-e 's!^(ENV JAVA_HOME) .*!\1 C:\\\\openjdk-'"$javaVersion"'!' \
							-e 's!^(ENV JAVA_VERSION) .*!\1 '"$downloadVersion"'!' \
							-e 's!^(ENV JAVA_URL) .*!\1 '"$downloadUrl"'!' \
							-e 's!^(ENV JAVA_SHA256) .*!\1 '"$downloadSha256"'!' \
							Dockerfile-windows.template > "$winD/Dockerfile"
					done
					;;
			esac

			for winVariant in \
				nanoserver-{1809,1803} \
				windowsservercore-{1809,1803,ltsc2016} \
			; do
				[ -f "$dir/windows/$winVariant/Dockerfile" ] || continue

				from="${winVariant%%-*}"
				from="${from#windows}" # "servercore", "nanoserver"
				from="mcr.microsoft.com/windows/$from:${winVariant#*-}"

				sed -ri \
					-e 's!^FROM .*!FROM '"$from"'!' \
					"$dir/windows/$winVariant/Dockerfile"

				case "$winVariant" in
					*-1803 ) travisEnv='\n    - os: windows\n      dist: 1803-containers\n      env: VERSION='"$javaVersion VARIANT=windows/$winVariant$travisEnv" ;;
					*-1809 ) ;; # no AppVeyor or Travis support for 1809: https://github.com/appveyor/ci/issues/1885
					* ) appveyorEnv='\n    - version: '"$javaVersion"'\n      variant: '"$winVariant$appveyorEnv" ;;
				esac
			done
		fi
	done

	if [ -d "$javaVersion/jdk/alpine" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=alpine'"$travisEnv"
	fi
	if [ -d "$javaVersion/jdk/slim" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=slim'"$travisEnv"
	fi
	if [ -e "$javaVersion/jdk/Dockerfile" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion$travisEnv"
	fi
	if [ -d "$javaVersion/jdk/oracle" ]; then
		travisEnv='\n    - os: linux\n      env: VERSION='"$javaVersion"' VARIANT=oracle'"$travisEnv"
	fi
done

travis="$(awk -v 'RS=\n\n' '$1 == "matrix:" { $0 = "matrix:\n  include:'"$travisEnv"'" } { printf "%s%s", $0, RS }' .travis.yml)"
echo "$travis" > .travis.yml

appveyor="$(awk -v 'RS=\n\n' '$1 == "environment:" { $0 = "environment:\n  matrix:'"$appveyorEnv"'" } { printf "%s%s", $0, RS }' .appveyor.yml)"
echo "$appveyor" > .appveyor.yml
