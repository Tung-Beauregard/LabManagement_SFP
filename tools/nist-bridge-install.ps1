param([switch]$Uninstall)
# Registers the sfplab-nist: link for the current Windows user, so the GC-MS page's
# "啟動 NIST 連線程式" button can start tools\nist-bridge.cmd on this PC (not part of the deployed site).
# Per-user (HKCU\Software\Classes), no admin rights needed; -Uninstall removes it again.
# The link runs PowerShell on nist-bridge-launch.ps1, which takes no parameters: Windows may append the link
# to the command line, and the launcher ignores it. Do not register "cmd /c ..." instead: cmd would parse
# whatever gets appended. The browser asks before opening the link.
# Usage: double-click tools\nist-bridge-install.cmd (remove: tools\nist-bridge-uninstall.cmd)

$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Classes\sfplab-nist'

if ($Uninstall) {
  if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force; Write-Host '已移除網頁上「啟動 NIST 連線程式」的功能。' }
  else { Write-Host '這台電腦原本就沒有安裝。' }
  exit 0
}

foreach ($f in 'nist-bridge.cmd', 'nist-bridge-launch.ps1') {
  if (-not (Test-Path (Join-Path $PSScriptRoot $f))) { Write-Host "找不到 $(Join-Path $PSScriptRoot $f)"; exit 1 }
}
$launcher = Join-Path $PSScriptRoot 'nist-bridge-launch.ps1'
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(Default)' -Value 'URL:SFPLAB NIST 連線程式'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
New-Item -Path "$key\shell\open\command" -Force | Out-Null
Set-ItemProperty -Path "$key\shell\open\command" -Name '(Default)' -Value ('"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $ps, $launcher)
Write-Host '完成:網頁上的「啟動 NIST 連線程式」按鈕在這台電腦可以用了。'
Write-Host "連線程式位置:$(Join-Path $PSScriptRoot 'nist-bridge.cmd')"
Write-Host '(資料夾搬到別處後要再執行一次這個檔;要移除就執行 nist-bridge-uninstall.cmd)'
