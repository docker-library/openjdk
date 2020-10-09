FROM mcr.microsoft.com/windows/nanoserver:1809

SHELL ["cmd", "/s", "/c"]

ENV JAVA_HOME C:\\openjdk-16
# "ERROR: Access to the registry path is denied."
USER ContainerAdministrator
RUN echo Updating PATH: %JAVA_HOME%\bin;%PATH% \
	&& setx /M PATH %JAVA_HOME%\bin;%PATH%
USER ContainerUser

# https://jdk.java.net/
# >
# > Java Development Kit builds, from Oracle
# >
ENV JAVA_VERSION 16-ea+19

COPY --from=openjdk:16-ea-19-jdk-windowsservercore-1809 $JAVA_HOME $JAVA_HOME

RUN echo Verifying install ... \
	&& echo   javac --version && javac --version \
	&& echo   java --version && java --version

# "jshell" is an interactive REPL for Java (see https://en.wikipedia.org/wiki/JShell)
CMD ["jshell"]
