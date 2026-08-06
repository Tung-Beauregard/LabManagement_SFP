param(
  [string]$Index = (Join-Path $PSScriptRoot "..\index.html"),
  [Parameter(Mandatory = $true)][string]$Out
)
$ErrorActionPreference = "Stop"

$content = [System.IO.File]::ReadAllText($Index, [System.Text.Encoding]::UTF8)
$m = [regex]::Match($content, 'GC_IFRAME_B64\s*=\s*"([^"]+)"')
if (-not $m.Success) { throw "GC_IFRAME_B64 not found in $Index" }

$decoded = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Groups[1].Value))
[System.IO.File]::WriteAllText($Out, $decoded, (New-Object System.Text.UTF8Encoding($false)))

Write-Output "extracted $($decoded.Length) chars to $Out"
