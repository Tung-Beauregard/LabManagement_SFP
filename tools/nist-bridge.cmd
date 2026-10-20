@echo off
rem Lets the GC-MS page send spectra to NIST MS Search on this PC. Keep this window open while searching.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0nist-bridge.ps1" %*
rem Only stop to show the message when something went wrong (an instance already running exits with 0).
rem Not "if errorlevel 1": that is false for negative codes, and PowerShell returns -196608 when it cannot
rem start the script, so the window would close before anyone could read why.
if not "%errorlevel%"=="0" pause
