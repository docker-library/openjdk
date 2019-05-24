FROM mcr.microsoft.com/windows/servercore:ltsc2016

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV JAVA_HOME C:\\openjdk-8
RUN $newPath = ('{0}\bin;{1}' -f $env:JAVA_HOME, $env:PATH); \
	Write-Host ('Updating PATH: {0}' -f $newPath); \
# Nano Server does not have "[Environment]::SetEnvironmentVariable()"
	setx /M PATH $newPath

# https://adoptopenjdk.net/upstream.html
ENV JAVA_VERSION 8u212-b04
ENV JAVA_BASE_URL https://github.com/AdoptOpenJDK/openjdk8-upstream-binaries/releases/download/jdk8u212-b04/OpenJDK8U-
ENV JAVA_URL_VERSION 8u212b04
# https://github.com/docker-library/openjdk/issues/320#issuecomment-494050246

RUN $url = ('{0}x64_windows_{1}.zip' -f $env:JAVA_BASE_URL, $env:JAVA_URL_VERSION); \
	Write-Host ('Downloading {0} ...' -f $url); \
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
	Invoke-WebRequest -Uri $url -OutFile 'openjdk.zip'; \
# TODO signature? checksum?
	\
	Write-Host 'Expanding ...'; \
	New-Item -ItemType Directory -Path C:\temp | Out-Null; \
	Expand-Archive openjdk.zip -DestinationPath C:\temp; \
	Move-Item -Path C:\temp\* -Destination $env:JAVA_HOME; \
	Remove-Item C:\temp; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item openjdk.zip -Force; \
	\
	Write-Host 'Verifying install ...'; \
	Write-Host '  javac -version'; javac -version; \
	Write-Host '  java -version'; java -version; \
	\
	Write-Host 'Complete.'
