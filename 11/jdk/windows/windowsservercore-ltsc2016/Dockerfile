FROM mcr.microsoft.com/windows/servercore:ltsc2016

# $ProgressPreference: https://github.com/PowerShell/PowerShell/issues/2138#issuecomment-251261324
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# https://adoptopenjdk.net/
ENV JAVA_VERSION 11.0.3+7
ENV JAVA_URL https://github.com/AdoptOpenJDK/openjdk11-binaries/releases/download/jdk-11.0.3%2B7/OpenJDK11U-jdk_x64_windows_hotspot_11.0.3_7.msi
ENV JAVA_SHA256 6eb277a3e9305fdf380900d20f4ef7a474f13fdbc92f7709b57945f6ffdc80fc

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
