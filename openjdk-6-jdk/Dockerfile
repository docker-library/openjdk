FROM buildpack-deps:wheezy-scm

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*

# Default to UTF-8 file.encoding
ENV LANG C.UTF-8

ENV JAVA_VERSION 6b36
ENV JAVA_DEBIAN_VERSION 6b36-1.13.8-1~deb7u1

RUN apt-get update && apt-get install -y openjdk-6-jdk="$JAVA_DEBIAN_VERSION" && rm -rf /var/lib/apt/lists/*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
