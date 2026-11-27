@echo off
rem Buduje wersję przeglądarkową MapyChodzone (build\web) razem z danymi regionów (build\web\dane).
rem   build_web.cmd [katalog-z-danymi]      domyślnie C:\TMP\My_GIT\mapychodzone-dane\build
rem Test lokalny:   node tool\web.mjs serwer 8090   ->  http://localhost:8090/
rem Wydanie:        npx firebase-tools deploy --only hosting   ->  https://mapychodzone.web.app
setlocal
set "DANE=%~1"
if "%DANE%"=="" set "DANE=C:\TMP\My_GIT\mapychodzone-dane\build"
set "PUB_CACHE=C:\pubcache"
set "PATH=C:\Users\grzegorz.kotarba\dev\flutter\bin;%PATH%"
cd /d "%~dp0"
call flutter build web --release || exit /b 1
node tool\web.mjs dane "%DANE%"
exit /b %ERRORLEVEL%
