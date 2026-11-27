@echo off
rem Buduje APK MapyChodzone dla współczesnych telefonów (arm64):
rem   build\app\outputs\flutter-apk\app-arm64-v8a-release.apk
rem TEMP/TMP i jdk.net.unixdomain.tmpdir w C:\TMP\jtmp: Gradle na tym komputerze nie może
rem otworzyć gniazd w domyślnym katalogu tymczasowym (ścieżka użytkownika z kropką).
setlocal
set "JAVA_HOME=C:\Users\grzegorz.kotarba\dev\jdk-17.0.19+10"
set "ANDROID_HOME=C:\Users\grzegorz.kotarba\dev\android-sdk"
set "PUB_CACHE=C:\pubcache"
if not exist C:\TMP\jtmp mkdir C:\TMP\jtmp
set "TEMP=C:\TMP\jtmp"
set "TMP=C:\TMP\jtmp"
set "JAVA_TOOL_OPTIONS=-Djdk.net.unixdomain.tmpdir=C:\TMP\jtmp"
set "PATH=C:\Users\grzegorz.kotarba\dev\flutter\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"
cd /d "%~dp0"
call flutter build apk --release --split-per-abi --target-platform android-arm64
exit /b %ERRORLEVEL%
