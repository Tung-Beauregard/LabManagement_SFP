@echo off
rem Removes what nist-bridge-install.cmd registered (the sfplab-nist: link for this Windows user).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nist-bridge-install.ps1" -Uninstall
pause
