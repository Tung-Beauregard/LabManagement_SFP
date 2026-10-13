@echo off
rem Lets the GC-MS page send spectra to NIST MS Search on this PC. Keep this window open while searching.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nist-bridge.ps1" %*
pause
