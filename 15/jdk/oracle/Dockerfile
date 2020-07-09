FROM oraclelinux:7-slim

RUN set -eux; \
	yum install -y \
		gzip \
		tar \
		\
# jlink --strip-debug on 13+ needs objcopy: https://github.com/docker-library/openjdk/issues/351
# Error: java.io.IOException: Cannot run program "objcopy": error=2, No such file or directory
		binutils \
# java.lang.UnsatisfiedLinkError: /usr/java/openjdk-12/lib/libfontmanager.so: libfreetype.so.6: cannot open shared object file: No such file or directory
# https://github.com/docker-library/openjdk/pull/235#issuecomment-424466077
		freetype fontconfig \
	; \
	rm -rf /var/cache/yum

# Default to UTF-8 file.encoding
ENV LANG en_US.UTF-8

ENV JAVA_HOME /usr/java/openjdk-15
ENV PATH $JAVA_HOME/bin:$PATH

# https://jdk.java.net/
# > Java Development Kit builds, from Oracle
ENV JAVA_VERSION 15-ea+31

RUN set -eux; \
	\
	objdump="$(command -v objdump)"; \
	arch="$(objdump --file-headers "$objdump" | awk -F '[:,]+[[:space:]]+' '$1 == "architecture" { print $2 }')"; \
# this "case" statement is generated via "update.sh"
	case "$arch" in \
# arm64v8
		arm64 | aarch64) \
			downloadUrl=https://download.java.net/java/early_access/jdk15/31/GPL/openjdk-15-ea+31_linux-aarch64_bin.tar.gz; \
			downloadSha256=27ef4fe5b302ff8804a86a7b455ebd16a5adbfb0f83cf8453026957a46088455; \
			;; \
# amd64
		amd64 | i386:x86-64) \
			downloadUrl=https://download.java.net/java/early_access/jdk15/31/GPL/openjdk-15-ea+31_linux-x64_bin.tar.gz; \
			downloadSha256=87a9314b733f711973093455f055a9f461a01a7c52dfe77d29da67d47795141b; \
			;; \
# fallback
		*) echo >&2 "error: unsupported architecture: '$arch'"; exit 1 ;; \
	esac; \
	\
	curl -fL -o /openjdk.tgz "$downloadUrl"; \
	echo "$downloadSha256 */openjdk.tgz" | sha256sum -c -; \
	\
	mkdir -p "$JAVA_HOME"; \
	tar --extract --file /openjdk.tgz --directory "$JAVA_HOME" --strip-components 1; \
	rm /openjdk.tgz; \
	\
# https://github.com/oracle/docker-images/blob/a56e0d1ed968ff669d2e2ba8a1483d0f3acc80c0/OracleJava/java-8/Dockerfile#L17-L19
	ln -sfT "$JAVA_HOME" /usr/java/default; \
	ln -sfT "$JAVA_HOME" /usr/java/latest; \
	for bin in "$JAVA_HOME/bin/"*; do \
		base="$(basename "$bin")"; \
		[ ! -e "/usr/bin/$base" ]; \
		alternatives --install "/usr/bin/$base" "$base" "$bin" 20000; \
	done; \
	\
# https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
# https://openjdk.java.net/jeps/341
	java -Xshare:dump; \
	\
# see "update-ca-trust" script which creates/maintains this cacerts bundle
	rm -rf "$JAVA_HOME/lib/security/cacerts"; \
	ln -sT /etc/pki/ca-trust/extracted/java/cacerts "$JAVA_HOME/lib/security/cacerts"; \
	\
# basic smoke test
	java --version; \
	javac --version

# https://docs.oracle.com/javase/10/tools/jshell.htm
# https://docs.oracle.com/javase/10/jshell/
# https://en.wikipedia.org/wiki/JShell
CMD ["jshell"]
