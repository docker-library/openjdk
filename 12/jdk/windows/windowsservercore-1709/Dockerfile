FROM microsoft/windowsservercore:1709

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV JAVA_HOME C:\\jdk-12
RUN $newPath = ('{0}\bin;{1}' -f $env:JAVA_HOME, $env:PATH); \
	Write-Host ('Updating PATH: {0}' -f $newPath); \
# Nano Server does not have "[Environment]::SetEnvironmentVariable()"
	setx /M PATH $newPath

# http://jdk.java.net/
ENV JAVA_VERSION 12-ea+11
ENV JAVA_URL https://download.java.net/java/early_access/jdk12/11/GPL/openjdk-12-ea+11_windows-x64_bin.zip
ENV JAVA_SHA256 1065039397db6f47d45893bf20ecaf301404736b710e0ddd60f49b6480488dfd

RUN Write-Host ('Downloading {0} ...' -f $env:JAVA_URL); \
	[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
	Invoke-WebRequest -Uri $env:JAVA_URL -OutFile 'openjdk.zip'; \
	Write-Host ('Verifying sha256 ({0}) ...' -f $env:JAVA_SHA256); \
	if ((Get-FileHash openjdk.zip -Algorithm sha256).Hash -ne $env:JAVA_SHA256) { \
		Write-Host 'FAILED!'; \
		exit 1; \
	}; \
	\
	Write-Host 'Expanding ...'; \
	Expand-Archive openjdk.zip -DestinationPath C:\; \
	\
	Write-Host 'Verifying install ...'; \
	Write-Host '  java -version'; java -version; \
	Write-Host '  javac -version'; javac -version; \
	\
	Write-Host 'Removing ...'; \
	Remove-Item openjdk.zip -Force; \
	\
	Write-Host 'Complete.'

# https://docs.oracle.com/javase/10/tools/jshell.htm
# https://en.wikipedia.org/wiki/JShell
CMD ["jshell"]
