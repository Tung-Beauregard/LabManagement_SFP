@echo off
rem One-time setup on the PC with NIST: lets the GC-MS page's launch button start tools\nist-bridge.cmd.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nist-bridge-install.ps1"
pause
