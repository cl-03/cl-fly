@echo off
setlocal
powershell -ExecutionPolicy Bypass -File "%~dp0cleanup-legacy-ports.ps1"
endlocal
