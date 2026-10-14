param([switch]$Uninstall)
# Registers the sfplab-nist: link for the current Windows user, so the GC-MS page's
# "啟動 NIST 連線程式" button can start tools\nist-bridge.cmd on this PC (not part of the deployed site).
# Per-user (HKCU\Software\Classes), no admin rights needed; -Uninstall removes it again.
# The link's address is ignored on purpose: whatever page opens it, the only thing that runs is the bridge,
# and the browser asks before opening it.
# Usage: double-click tools\nist-bridge-install.cmd (remove: tools\nist-bridge-uninstall.cmd)

$ErrorActionPreference = 'Stop'
$key = 'HKCU:\Software\Classes\sfplab-nist'

if ($Uninstall) {
  if (Test-Path $key) { Remove-Item -Path $key -Recurse -Force; Write-Host '已移除網頁上「啟動 NIST 連線程式」的功能。' }
  else { Write-Host '這台電腦原本就沒有安裝。' }
  exit 0
}

$bridge = Join-Path $PSScriptRoot 'nist-bridge.cmd'
if (-not (Test-Path $bridge)) { Write-Host "找不到 $bridge"; exit 1 }
$cmdExe = Join-Path $env:SystemRoot 'System32\cmd.exe'
New-Item -Path $key -Force | Out-Null
Set-ItemProperty -Path $key -Name '(Default)' -Value 'URL:SFPLAB NIST 連線程式'
Set-ItemProperty -Path $key -Name 'URL Protocol' -Value ''
New-Item -Path "$key\shell\open\command" -Force | Out-Null
# start /min: the bridge window opens minimised on the taskbar; no %1, so the link's address never reaches a command line
Set-ItemProperty -Path "$key\shell\open\command" -Name '(Default)' -Value ('"{0}" /c start "SFPLAB NIST" /min "{1}"' -f $cmdExe, $bridge)
Write-Host '完成:網頁上的「啟動 NIST 連線程式」按鈕在這台電腦可以用了。'
Write-Host "連線程式位置:$bridge"
Write-Host '(資料夾搬到別處後要再執行一次這個檔;要移除就執行 nist-bridge-uninstall.cmd)'
