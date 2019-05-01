FROM mcr.microsoft.com/windows/servercore:1803

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# https://adoptopenjdk.net/
ENV JAVA_VERSION 8.0.212+3
ENV JAVA_URL https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b03/OpenJDK8U-jdk_x64_windows_hotspot_8u212b03.msi
ENV JAVA_SHA256 86cf932a04dff28e19a5f715cbb8f2c34ce78fa12d30578bcaf7fb46f88a3acb

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
