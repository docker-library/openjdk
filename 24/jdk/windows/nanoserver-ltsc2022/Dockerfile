#
# NOTE: THIS DOCKERFILE IS GENERATED VIA "apply-templates.sh"
#
# PLEASE DO NOT EDIT IT DIRECTLY.
#

FROM mcr.microsoft.com/windows/nanoserver:ltsc2022

SHELL ["cmd", "/s", "/c"]

ENV JAVA_HOME C:\\openjdk-24
# "ERROR: Access to the registry path is denied."
USER ContainerAdministrator
RUN echo Updating PATH: %JAVA_HOME%\bin;%PATH% \
	&& setx /M PATH %JAVA_HOME%\bin;%PATH% \
	&& echo Complete.
USER ContainerUser

# https://jdk.java.net/
# >
# > Java Development Kit builds, from Oracle
# >
ENV JAVA_VERSION 24-ea+32

COPY --from=openjdk:24-ea-32-jdk-windowsservercore-ltsc2022 $JAVA_HOME $JAVA_HOME

RUN echo Verifying install ... \
	&& echo   javac --version && javac --version \
	&& echo   java --version && java --version \
	&& echo Complete.

# "jshell" is an interactive REPL for Java (see https://en.wikipedia.org/wiki/JShell)
CMD ["jshell"]
