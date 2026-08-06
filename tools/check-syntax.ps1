param(
  [string]$Index = (Join-Path $PSScriptRoot "..\index.html")
)
$ErrorActionPreference = "Stop"

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  $env:Path = "$machinePath;$userPath"
  $node = Get-Command node -ErrorAction SilentlyContinue
}
if (-not $node) { throw "node not found on PATH" }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("syntaxcheck_" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $work | Out-Null
$failed = 0

function Test-Html {
  param([string]$Html, [string]$Label, [string]$Work)

  $scripts = [regex]::Matches($Html, '(?is)<script\b(?<attrs>[^>]*)>(?<body>.*?)</script>')
  $i = 0
  $script:bad = 0
  foreach ($s in $scripts) {
    $i++
    if ($s.Groups['attrs'].Value -match '\bsrc\s*=') { continue }
    $body = $s.Groups['body'].Value
    if ([string]::IsNullOrWhiteSpace($body)) { continue }
    $isModule = $s.Groups['attrs'].Value -match 'type\s*=\s*["'']module["'']'
    $ext = if ($isModule) { "mjs" } else { "js" }
    $f = Join-Path $Work "$Label-$i.$ext"
    [System.IO.File]::WriteAllText($f, $body, (New-Object System.Text.UTF8Encoding($false)))
    $out = & node --check $f 2>&1
    if ($LASTEXITCODE -ne 0) {
      $script:bad++
      Write-Output "FAIL  $Label script #$i"
      Write-Output ($out | Out-String).Trim()
    }
  }
  Write-Output "$Label : checked $i script block(s), $script:bad failed"
}

$content = [System.IO.File]::ReadAllText($Index, [System.Text.Encoding]::UTF8)
Test-Html -Html $content -Label "main" -Work $work
$failed += $script:bad

$m = [regex]::Match($content, 'GC_IFRAME_B64\s*=\s*"([^"]+)"')
if ($m.Success) {
  $iframe = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($m.Groups[1].Value))
  Test-Html -Html $iframe -Label "gc-iframe" -Work $work
  $failed += $script:bad
}

$css = [regex]::Matches($content, '(?is)<style\b[^>]*>(.*?)</style>')
$ci = 0
foreach ($c in $css) {
  $ci++
  $body = $c.Groups[1].Value
  $stripped = [regex]::Replace($body, '(?s)/\*.*?\*/', '')
  $open = ([regex]::Matches($stripped, '\{')).Count
  $close = ([regex]::Matches($stripped, '\}')).Count
  if ($open -ne $close) {
    $failed++
    Write-Output "FAIL  css block #$ci brace imbalance: $open open / $close close"
  }
}
Write-Output "css : checked $ci style block(s)"

Remove-Item -Recurse -Force $work
if ($failed -gt 0) { Write-Output "RESULT: $failed problem(s)"; exit 1 }
Write-Output "RESULT: all checks passed"
