@echo off
setlocal
chcp 65001 >nul
title KupaDesk Antigravity Plugin Installer
echo Installing KupaDesk plugin from https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/ ...
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/kupakupar/kupadesk-antigravity/main/install.ps1 | iex"
set EXIT_CODE=%ERRORLEVEL%
echo.
if %EXIT_CODE% EQU 0 (
  echo Installation finished.
) else (
  echo Installation failed with code %EXIT_CODE%.
)
pause
exit /b %EXIT_CODE%
