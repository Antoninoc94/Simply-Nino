@echo off
setlocal

set "ITGMANIA_SAVE_DIR=C:\Dati\ITGmania\Save"

cd /d "%~dp0ITGWebAPP"

if not exist node_modules (
    echo Installo le dipendenze npm...
    call npm install
)

echo.
echo Avvio ITGLiveScore server...
echo   Overlay:   http://localhost:3000
echo   WebSocket: ws://localhost:8081
echo   Save dir:  %ITGMANIA_SAVE_DIR%
echo.

node server.js

pause
