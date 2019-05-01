FROM mcr.microsoft.com/windows/servercore:1803

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# https://adoptopenjdk.net/
ENV JAVA_VERSION 12.0.1+12
ENV JAVA_URL https://github.com/AdoptOpenJDK/openjdk12-binaries/releases/download/jdk-12.0.1%2B12/OpenJDK12U-jdk_x64_windows_hotspot_12.0.1_12.msi
ENV JAVA_SHA256 c08f97625f0562889497b4cfc023bd06ada9554050c9b34c1050167fcf89847c

RUN Write-Host ('Downloading {0} ...' -f $env:JAVA_URL); \
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; \
        Invoke-WebRequest -Uri $env:JAVA_URL -OutFile 'openjdk.msi'; \
        Write-Host ('Verifying sha256 ({0}) ...' -f $env:JAVA_SHA256); \
        if ((Get-FileHash openjdk.msi -Algorithm sha256).Hash -ne $env:JAVA_SHA256) { \
                Write-Host 'FAILED!'; \
                exit 1; \
        }; \
        \
        New-Item -ItemType Directory -Path C:\temp | Out-Null;

RUN Write-Host 'Installing using MSI ...'; \
        Start-Process -FilePath "msiexec.exe" -ArgumentList '/i', 'openjdk.msi', '/L*V', 'C:\temp\OpenJDK.log', \
        '/quiet', 'ADDLOCAL=FeatureEnvironment,FeatureJarFileRunWith,FeatureJavaHome' -Wait -Passthru; \
        Write-Host 'Removing ...'; \
        Remove-Item openjdk.msi -Force;

RUN Write-Host 'Verifying install ...'; \
        Write-Host '  java -version'; java -version; \
        Write-Host '  javac -version'; javac -version; \
        Write-Host '  JAVA_HOME'; Test-Path $env:JAVA_HOME;

# https://docs.oracle.com/javase/10/tools/jshell.htm
# https://en.wikipedia.org/wiki/JShell
CMD ["jshell"]
