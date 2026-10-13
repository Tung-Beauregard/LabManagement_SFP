param(
  [int]$Port = 28790,
  [string]$NistDir = '',
  [string]$WorkDir = 'C:\SFPLAB-NIST',
  [int]$TimeoutSec = 180
)
# Local bridge between the GC-MS page and NIST MS Search on this PC (not part of the deployed site).
# The page POSTs an .MSP text to http://localhost:28790/search; this script hands it to NIST through the
# standard automation files (AUTOIMP.MSD -> FILESPEC.FIL -> spectra), runs "nistms$.exe /INSTRUMENT /PAR=2",
# waits for SRCREADY.TXT and returns SRCRESLT.TXT. NIST deletes FILESPEC.FIL after reading it, so it is
# rewritten for every search. AUTOIMP.MSD is restored afterwards so ChemStation or AMDIS setups are untouched.
# Usage: double-click tools\nist-bridge.cmd (or: powershell -NoProfile -ExecutionPolicy Bypass -File tools\nist-bridge.ps1)

$ErrorActionPreference = 'Stop'
$AllowedOrigins = @('https://tung-beauregard.github.io')
$LocalOrigin = '^http://(localhost|127\.0\.0\.1)(:\d+)?$'
$Latin1 = [Text.Encoding]::GetEncoding(28591)

if (-not $NistDir) {
  $cands = @('C:\NIST20\MSSEARCH', 'C:\NIST23\MSSEARCH', 'C:\NIST26\MSSEARCH', 'C:\NIST17\MSSEARCH')
  $cands += Get-ChildItem 'C:\' -Directory -Filter 'NIST*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'MSSEARCH' }
  $NistDir = $cands | Where-Object { Test-Path (Join-Path $_ 'nistms$.exe') } | Select-Object -First 1
}
if (-not $NistDir -or -not (Test-Path (Join-Path $NistDir 'nistms$.exe'))) {
  Write-Host '找不到 NIST MS Search(nistms$.exe)。請用 -NistDir 指定 MSSEARCH 資料夾,例如 -NistDir C:\NIST20\MSSEARCH'
  exit 1
}
# NIST is a 32-bit program that splits FILESPEC.FIL on spaces: keep the work folder short and space-free
if ($WorkDir -match '\s') { Write-Host 'WorkDir 不能有空白'; exit 1 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

function Invoke-NistSearch([string]$msp) {
  $query = Join-Path $WorkDir 'QUERY.MSP'
  $spec = Join-Path $WorkDir 'FILESPEC.FIL'
  $auto = Join-Path $NistDir 'AUTOIMP.MSD'
  $ready = Join-Path $NistDir 'SRCREADY.TXT'
  $result = Join-Path $NistDir 'SRCRESLT.TXT'
  [IO.File]::WriteAllText($query, $msp, $Latin1)
  [IO.File]::WriteAllText($spec, "$query OVERWRITE`r`n", $Latin1)
  $oldAuto = $null
  if (Test-Path $auto) { $oldAuto = [IO.File]::ReadAllBytes($auto) }
  try {
    [IO.File]::WriteAllText($auto, "$spec`r`n", $Latin1)
    foreach ($f in @($ready, $result)) { if (Test-Path $f) { Remove-Item -LiteralPath $f } }
    Start-Process -FilePath (Join-Path $NistDir 'nistms$.exe') -ArgumentList '/INSTRUMENT', '/PAR=2' -WorkingDirectory $NistDir
    $t0 = Get-Date
    while (-not (Test-Path $ready)) {
      if (((Get-Date) - $t0).TotalSeconds -gt $TimeoutSec) {
        throw 'NIST 沒有在時限內回應。請看 NIST 視窗是不是跳出了訊息,按掉之後再搜一次。'
      }
      Start-Sleep -Milliseconds 300
    }
  } finally {
    if ($oldAuto) { [IO.File]::WriteAllBytes($auto, $oldAuto) }
    elseif (Test-Path $auto) { Remove-Item -LiteralPath $auto }
  }
  for ($i = 0; $i -lt 20; $i++) {
    try { return [IO.File]::ReadAllText($result, $Latin1) } catch { Start-Sleep -Milliseconds 150 }
  }
  throw '讀不到 NIST 的結果檔 SRCRESLT.TXT'
}

function Send-Json($ctx, [int]$status, $obj) {
  $bytes = [Text.Encoding]::UTF8.GetBytes(($obj | ConvertTo-Json -Compress))
  $ctx.Response.StatusCode = $status
  $ctx.Response.ContentType = 'application/json; charset=utf-8'
  $ctx.Response.ContentLength64 = $bytes.Length
  $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "NIST 連線程式執行中:http://localhost:$Port/  (NIST: $NistDir)"
Write-Host '保持這個視窗開著;關掉就停止。'
while ($listener.IsListening) {
  $ctx = $null
  try {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $origin = $req.Headers['Origin']
    if ($origin) {
      if (-not (($AllowedOrigins -contains $origin) -or ($origin -match $LocalOrigin))) {
        Send-Json $ctx 403 @{ ok = $false; error = "origin not allowed: $origin" }
        Write-Host "403 $origin"
        continue
      }
      $ctx.Response.Headers.Add('Access-Control-Allow-Origin', $origin)
      $ctx.Response.Headers.Add('Vary', 'Origin')
    }
    if ($req.HttpMethod -eq 'OPTIONS') {
      $ctx.Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      $ctx.Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')
      # Chrome asks before a public page may reach localhost (Private Network Access)
      $ctx.Response.Headers.Add('Access-Control-Allow-Private-Network', 'true')
      $ctx.Response.StatusCode = 204
      continue
    }
    $path = $req.Url.AbsolutePath
    if ($req.HttpMethod -eq 'GET' -and ($path -eq '/ping' -or $path -eq '/')) {
      Send-Json $ctx 200 @{ ok = $true; app = 'sfplab-nist-bridge'; version = 1; nist = $NistDir }
      continue
    }
    if ($req.HttpMethod -eq 'POST' -and $path -eq '/search') {
      if ($req.ContentLength64 -gt 4MB) { Send-Json $ctx 413 @{ ok = $false; error = '資料太大' }; continue }
      $reader = New-Object IO.StreamReader($req.InputStream, $Latin1)
      $msp = $reader.ReadToEnd(); $reader.Close()
      $n = ([regex]::Matches($msp, '(?m)^Name:')).Count
      if ($n -lt 1) { Send-Json $ctx 400 @{ ok = $false; error = '沒有質譜' }; continue }
      $t0 = Get-Date
      try {
        $text = Invoke-NistSearch $msp
        Send-Json $ctx 200 @{ ok = $true; result = $text }
        Write-Host ("{0:HH:mm:ss} 搜尋 {1} 張質譜,{2:N1} 秒" -f (Get-Date), $n, ((Get-Date) - $t0).TotalSeconds)
      } catch {
        Send-Json $ctx 500 @{ ok = $false; error = $_.Exception.Message }
        Write-Host ("{0:HH:mm:ss} 失敗:{1}" -f (Get-Date), $_.Exception.Message)
      }
      continue
    }
    Send-Json $ctx 404 @{ ok = $false; error = 'not found' }
  } catch {
    Write-Host "request failed: $($_.Exception.Message)"
  } finally {
    if ($ctx) { try { $ctx.Response.Close() } catch {} }
  }
}
