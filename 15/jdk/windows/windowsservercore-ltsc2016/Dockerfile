FROM mcr.microsoft.com/windows/servercore:ltsc2016

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# enable TLS 1.2 (Nano Server doesn't support using "[Net.ServicePointManager]::SecurityProtocol")
# https://docs.microsoft.com/en-us/system-center/vmm/install-tls?view=sc-vmm-1801
# https://docs.microsoft.com/en-us/windows-server/identity/ad-fs/operations/manage-ssl-protocols-in-ad-fs#enable-tls-12
RUN Write-Host 'Enabling TLS 1.2 (https://githubengineering.com/crypto-removal-notice/) ...'; \
	$tls12RegBase = 'HKLM:\\SYSTEM\CurrentControlSet\Control\SecurityProviders\SCHANNEL\Protocols\TLS 1.2'; \
	if (Test-Path $tls12RegBase) { throw ('"{0}" already exists!' -f $tls12RegBase) }; \
	New-Item -Path ('{0}/Client' -f $tls12RegBase) -Force; \
	New-Item -Path ('{0}/Server' -f $tls12RegBase) -Force; \
	New-ItemProperty -Path ('{0}/Client' -f $tls12RegBase) -Name 'DisabledByDefault' -PropertyType DWORD -Value 0 -Force; \
	New-ItemProperty -Path ('{0}/Client' -f $tls12RegBase) -Name 'Enabled' -PropertyType DWORD -Value 1 -Force; \
	New-ItemProperty -Path ('{0}/Server' -f $tls12RegBase) -Name 'DisabledByDefault' -PropertyType DWORD -Value 0 -Force; \
	New-ItemProperty -Path ('{0}/Server' -f $tls12RegBase) -Name 'Enabled' -PropertyType DWORD -Value 1 -Force

ENV JAVA_HOME C:\\openjdk-15
RUN $newPath = ('{0}\bin;{1}' -f $env:JAVA_HOME, $env:PATH); \
	Write-Host ('Updating PATH: {0}' -f $newPath); \
# Nano Server does not have "[Environment]::SetEnvironmentVariable()"
	setx /M PATH $newPath

# https://jdk.java.net/
# > Java Development Kit builds, from Oracle
ENV JAVA_VERSION 15-ea+14
ENV JAVA_URL https://download.java.net/java/early_access/jdk15/14/GPL/openjdk-15-ea+14_windows-x64_bin.zip
ENV JAVA_SHA256 411989eacb4772fbec0f334fbb94ab162b5abb91fd3a677892c09c15083f1e01

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

# https://docs.oracle.com/javase/10/tools/jshell.htm
# https://en.wikipedia.org/wiki/JShell
CMD ["jshell"]
