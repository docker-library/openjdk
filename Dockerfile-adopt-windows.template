FROM placeholder

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV JAVA_HOME placeholder
RUN $newPath = ('{0}\bin;{1}' -f $env:JAVA_HOME, $env:PATH); \
	Write-Host ('Updating PATH: {0}' -f $newPath); \
# Nano Server does not have "[Environment]::SetEnvironmentVariable()"
	setx /M PATH $newPath

# https://adoptopenjdk.net/upstream.html
ENV JAVA_VERSION placeholder
ENV JAVA_BASE_URL placeholder
ENV JAVA_URL_VERSION placeholder
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
	Write-Host '  javac --version'; javac --version; \
	Write-Host '  java --version'; java --version; \
	\
	Write-Host 'Complete.'

# "jshell" is an interactive REPL for Java (see https://en.wikipedia.org/wiki/JShell)
CMD ["jshell"]
