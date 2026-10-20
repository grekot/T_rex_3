@echo off
rem Buduje APK aplikacji Korona osobno dla każdej architektury procesora:
rem   build\app\outputs\flutter-apk\app-arm64-v8a-release.apk  <- ten dla współczesnych telefonów
setlocal
set "JAVA_HOME=C:\Users\grzegorz.kotarba\dev\jdk-17.0.19+10"
set "ANDROID_HOME=C:\Users\grzegorz.kotarba\dev\android-sdk"
set "PUB_CACHE=C:\pubcache"
set "PATH=C:\Users\grzegorz.kotarba\dev\flutter\bin;%JAVA_HOME%\bin;%ANDROID_HOME%\platform-tools;%PATH%"
cd /d "%~dp0"
call flutter build apk --release --split-per-abi
exit /b %ERRORLEVEL%
