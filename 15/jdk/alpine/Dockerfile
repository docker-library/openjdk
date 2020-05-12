FROM alpine:3.11

ENV JAVA_HOME /opt/openjdk-15
ENV PATH $JAVA_HOME/bin:$PATH

# https://jdk.java.net/
# > Java Development Kit builds, from Oracle
ENV JAVA_VERSION 15-ea+10
ENV JAVA_URL https://download.java.net/java/early_access/alpine/10/binaries/openjdk-15-ea+10_linux-x64-musl_bin.tar.gz
ENV JAVA_SHA256 15a5e8002e24ed129b82bfe55ffe4bdbf3cfd0a7e5ad3399879cdd44175bfd06
# "For Alpine Linux, builds are produced on a reduced schedule and may not be in sync with the other platforms."

RUN set -eux; \
	\
	wget -O /openjdk.tgz "$JAVA_URL"; \
	echo "$JAVA_SHA256 */openjdk.tgz" | sha256sum -c -; \
	\
	mkdir -p "$JAVA_HOME"; \
	tar --extract --file /openjdk.tgz --directory "$JAVA_HOME" --strip-components 1; \
	rm /openjdk.tgz; \
	\
# https://github.com/docker-library/openjdk/issues/212#issuecomment-420979840
# https://openjdk.java.net/jeps/341
	java -Xshare:dump; \
	\
# basic smoke test
	java --version; \
	javac --version

# https://docs.oracle.com/javase/10/tools/jshell.htm
# https://docs.oracle.com/javase/10/jshell/
# https://en.wikipedia.org/wiki/JShell
CMD ["jshell"]
