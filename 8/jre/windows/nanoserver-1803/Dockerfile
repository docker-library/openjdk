FROM mcr.microsoft.com/windows/nanoserver:1803

SHELL ["cmd", "/s", "/c"]

ENV JAVA_HOME C:\\openjdk-8
# "ERROR: Access to the registry path is denied."
USER ContainerAdministrator
RUN echo Updating PATH: %JAVA_HOME%\bin;%PATH% \
	&& setx /M PATH %JAVA_HOME%\bin;%PATH%
USER ContainerUser

# https://adoptopenjdk.net/upstream.html
ENV JAVA_VERSION 8u232
# https://github.com/docker-library/openjdk/issues/320#issuecomment-494050246

COPY --from=openjdk:8u232-windowsservercore-1803 $JAVA_HOME $JAVA_HOME

RUN echo Verifying install ... \
	&& echo   java -version && java -version
