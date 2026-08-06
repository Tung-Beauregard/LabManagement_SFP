param(
  [string]$Index = (Join-Path $PSScriptRoot "..\index.html"),
  [Parameter(Mandatory = $true)][string]$Source
)
$ErrorActionPreference = "Stop"

$decoded = [System.IO.File]::ReadAllText($Source, [System.Text.Encoding]::UTF8)
$b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($decoded))
if ($b64.Contains('"')) { throw "encoded payload contains a quote; would break the constant" }

$content = [System.IO.File]::ReadAllText($Index, [System.Text.Encoding]::UTF8)
$m = [regex]::Match($content, 'GC_IFRAME_B64\s*=\s*"([^"]+)"')
if (-not $m.Success) { throw "GC_IFRAME_B64 not found in $Index" }

if ($m.Groups[1].Value -eq $b64) {
  Write-Output "no change: iframe payload is already identical"
  return
}

$updated = $content.Replace($m.Groups[1].Value, $b64)
[System.IO.File]::WriteAllText($Index, $updated, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "injected $($decoded.Length) chars ($($b64.Length) base64) into $Index"
