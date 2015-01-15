FROM buildpack-deps:wheezy-micro

# A few problems with compiling Java from source:
#  1. Oracle.  Licensing prevents us from redistributing the official JDK.
#  2. Compiling OpenJDK also requires the JDK to be installed, and it gets
#       really hairy.

RUN apt-get update && apt-get install -y unzip && rm -rf /var/lib/apt/lists/*

ENV JAVA_VERSION 6b33
ENV JAVA_DEBIAN_VERSION 6b33-1.13.5-2~deb7u1

RUN apt-get update && apt-get install -y openjdk-6-jre="$JAVA_DEBIAN_VERSION" && rm -rf /var/lib/apt/lists/*

# If you're reading this and have any feedback on how this image could be
#   improved, please open an issue or a pull request so we can discuss it!
