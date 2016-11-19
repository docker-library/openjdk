FROM microsoft/nanoserver

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

ENV JAVA_VERSION 1.8.0.111-3
ENV JAVA_ZIP_VERSION 1.8.0-openjdk-1.8.0.111-3.b15
ENV JAVA_SHA256 e080371bf57536668416157660e05d95fe04db15da36234d32bda8e301bb0454

ENV JAVA_HOME C:\\java-${JAVA_ZIP_VERSION}.ojdkbuild.windows.x86_64

RUN Invoke-WebRequest $('https://github.com/ojdkbuild/ojdkbuild/releases/download/{0}/java-{1}.ojdkbuild.windows.x86_64.zip' -f $env:JAVA_VERSION, $env:JAVA_ZIP_VERSION) -OutFile 'openjdk.zip' -UseBasicParsing ; \
    if ((Get-FileHash openjdk.zip -Algorithm sha256).Hash -ne $env:JAVA_SHA256) {exit 1} ; \
    Expand-Archive openjdk.zip -DestinationPath C:\ ; \
    $env:PATH = '{0}\bin;{1}' -f $env:JAVA_HOME, $env:PATH ; \
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment\' -Name Path -Value $env:PATH ; \
    Remove-Item -Path openjdk.zip
