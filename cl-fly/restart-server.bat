@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0restart-server.ps1"
endlocal
