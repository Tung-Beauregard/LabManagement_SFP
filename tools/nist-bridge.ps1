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

# Started again (the page's launch button, or a second double-click) while one is already running:
# say so and leave with exit code 0, so nist-bridge.cmd closes the window instead of pausing
try {
  $running = Invoke-RestMethod -Uri "http://localhost:$Port/ping" -TimeoutSec 2
  if ($running.app -eq 'sfplab-nist-bridge') { Write-Host 'NIST 連線程式已經在執行,不用再開一個。'; Start-Sleep -Seconds 2; exit 0 }
} catch {}

if (-not $NistDir) {
  $cands = @('C:\NIST20\MSSEARCH', 'C:\NIST23\MSSEARCH', 'C:\NIST26\MSSEARCH', 'C:\NIST17\MSSEARCH')
  $cands += Get-ChildItem 'C:\' -Directory -Filter 'NIST*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'MSSEARCH' }
  $NistDir = $cands | Where-Object { Test-Path (Join-Path $_ 'nistms$.exe') } | Select-Object -First 1
}
if (-not $NistDir -or -not (Test-Path (Join-Path $NistDir 'nistms$.exe'))) {
  Write-Host '找不到 NIST MS Search(nistms$.exe)。請用 -NistDir 指定 MSSEARCH 資料夾,例如 -NistDir C:\NIST20\MSSEARCH'
  exit 1
}
# Version label for the page's citations ("NIST 20" from C:\NIST20\MSSEARCH)
$NistLabel = 'NIST'
if ($NistDir -match 'NIST(\d+)') { $NistLabel = 'NIST ' + $Matches[1] }
# NIST is a 32-bit program that splits FILESPEC.FIL on spaces: keep the work folder short and space-free
if ($WorkDir -match '\s') { Write-Host 'WorkDir 不能有空白'; exit 1 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# CAS -> NIST name table, built once from NIST's own RI compound list (nist_ri) with lib2nist.
# SRCRESLT.TXT loses Greek letters (alpha and beta both come out as "a", gamma as "c"), while the library
# keeps them as .alpha./.beta.; the page shows the proper name for each CAS from this table.
# It is derived from the licensed library, so it stays in $WorkDir; only the names for CAS numbers that
# appear in a search result are sent to the page.
$Greek = @{ alpha='α'; beta='β'; gamma='γ'; delta='δ'; epsilon='ε'; zeta='ζ'; eta='η'; theta='θ'; iota='ι'; kappa='κ'
  lambda='λ'; mu='μ'; nu='ν'; xi='ξ'; omicron='ο'; pi='π'; rho='ρ'; sigma='σ'; tau='τ'; upsilon='υ'; phi='φ'; chi='χ'; psi='ψ'; omega='ω' }
# NIST writes Greek letters three ways: .alpha. (most), <<alpha>> (about 100 names), and spelled out
# (beta-Isopropyltropolone, 3Beta,20-dihydroxy-5alpha-...). Spelled-out words are only converted for the
# common letters and only as whole words, so names like "Betaine" or "PI-103" stay as they are.
function Convert-Greek([string]$s) {
  $ev = [Text.RegularExpressions.MatchEvaluator]{ param($m)
    $w = $m.Groups[1].Value; $g = $Greek[$w]
    if (-not $g) { return $m.Value }
    if ($w.Length -gt 1 -and $w -ceq $w.ToUpper() -and ($m.Value -match '^[.<]' -or $w -eq 'DELTA')) { return $g.ToUpper() }   # .DELTA. -> Δ
    return $g }
  $s = [regex]::Replace($s, '\.([A-Za-z]+)\.', $ev)
  $s = [regex]::Replace($s, '<<([A-Za-z]+)>>', $ev)
  [regex]::Replace($s, '(?<![A-Za-z])\.?(alpha|beta|gamma|delta|epsilon|omega)\.?(?![A-Za-z])', $ev, 'IgnoreCase')
}
# NIST's primary name is often a CAS index name ("1,3-Cyclohexadiene, 1-methyl-4-(1-methylethyl)-");
# then take the first synonym that looks like a common name (".alpha.-Terpinene")
function Select-Name([string]$primary, $syns) {
  if ($primary -notmatch ', ') { return $primary }
  foreach ($s in $syns) {
    if ($s.StartsWith('$:') -or $s -match ', ' -or $s.Length -gt 40 -or $s -match '#|\(Salt/Mix\)|^NSC |^UN ' -or
        $s -cmatch '^[^a-z]*$' -or [regex]::Matches($s, '[A-Za-z]').Count -lt 3) { continue }
    return $s
  }
  return $primary
}
$NameFile = Join-Path $WorkDir 'nist_names.tsv'
function Build-NameTable {
  $riLib = Join-Path $NistDir 'nist_ri'; $l2n = Join-Path $NistDir 'lib2nist.exe'; $dbu = Join-Path $riLib 'USER.DBU'
  if (-not (Test-Path $dbu) -or -not (Test-Path $l2n)) { return $false }
  if ((Test-Path $NameFile) -and (Get-Item $NameFile).LastWriteTime -gt (Get-Item $dbu).LastWriteTime) { return $true }
  Write-Host '第一次啟動:從 NIST 的 RI 資料庫建立 CAS 對照表,約需四分鐘,會跳出 lib2nist 視窗,之後不用再做…'
  $ini = Join-Path $WorkDir 'lib2nist.ini'; $msp = Join-Path $WorkDir 'nist_ri.msp'; $log = Join-Path $WorkDir 'lib2nist.log'
  if (-not ((Test-Path $msp) -and (Get-Item $msp).LastWriteTime -gt (Get-Item $dbu).LastWriteTime)) {
    # an .ini on the command line keeps lib2nist from writing its settings into the registry;
    # do not start it hidden: with -WindowStyle Hidden it sits idle and never writes the output
    [IO.File]::WriteAllText($ini, "[Directory]`r`nNIST=<None>`r`n[Output]`r`nDB=0`r`nText=1`r`nTextFileType=0`r`nIncludeSynonyms=1`r`nKeepIDs=1`r`n", $Latin1)
    Start-Process -FilePath $l2n -ArgumentList '/log1', "`"$log`"", "`"$ini`"", '/OutMSP', '/NoAlias', '/AllowNoPeaks', "`"$riLib`"", "`"=$msp`"" -Wait
  }
  if (-not (Test-Path $msp)) { return $false }
  Write-Host '整理對照表…'
  # one regex pass over the whole export (a line-by-line PowerShell loop takes minutes); only about 39k of the
  # 140k compounds have a CAS number, the rest are listed with CASNO: 0 and cannot be matched anyway
  $text = [IO.File]::ReadAllText($msp, $Latin1)
  $rx = New-Object Text.RegularExpressions.Regex('^Name: ([^\r\n]*)((?:\r?\n(?!CASNO: |Name: )[^\r\n]*)*)\r?\nCASNO: ([1-9][0-9]{4,})\r?$', [Text.RegularExpressions.RegexOptions]::Multiline)
  $sb = New-Object Text.StringBuilder
  foreach ($m in $rx.Matches($text)) {
    $name = $m.Groups[1].Value; $cas = $m.Groups[3].Value; $syn = @()
    if ($name.Contains(', ')) { $syn = @([regex]::Matches($m.Groups[2].Value, '(?m)^Synon: ([^\r\n]*)') | ForEach-Object { $_.Groups[1].Value }) }
    $nm = Select-Name $name $syn
    if ($nm.Contains('.')) { $nm = Convert-Greek $nm }
    [void]$sb.Append($cas.Substring(0, $cas.Length - 3)).Append('-').Append($cas.Substring($cas.Length - 3, 2)).Append('-').Append($cas.Substring($cas.Length - 1)).Append("`t").Append($nm).Append("`n")
  }
  $text = $null
  [IO.File]::WriteAllText($NameFile, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
  Remove-Item -LiteralPath $msp
  return $true
}
$Names = New-Object 'Collections.Generic.Dictionary[string,string]'
if (Build-NameTable) {
  foreach ($l in [IO.File]::ReadLines($NameFile, [Text.Encoding]::UTF8)) {
    $i = $l.IndexOf("`t"); if ($i -le 0) { continue }
    $nm = $l.Substring($i + 1)
    # tables built before the <<alpha>> / spelled-out handling are fixed here, so no rebuild is needed
    if ($nm -match '(?i)alpha|beta|gamma|delta|epsilon|omega|<<') { $nm = Convert-Greek $nm }
    $Names[$l.Substring(0, $i)] = $nm
  }
}
Write-Host "CAS 對照表:$($Names.Count) 筆"

# CAS -> RI remembered from every search on this PC. Wiley hits carry no RI, so when the top 20 hits of a
# compound happen to be all Wiley spectra, an RI seen in an earlier search still fills the gap.
$RiFile = Join-Path $WorkDir 'ri_cache.tsv'
$RiCache = New-Object 'Collections.Generic.Dictionary[string,int]'
if (Test-Path $RiFile) {
  foreach ($l in [IO.File]::ReadLines($RiFile)) { $p = $l.Split("`t"); if ($p.Length -eq 2) { $RiCache[$p[0]] = [int]$p[1] } }
}
function Get-Extras([string]$text) {
  # PowerShell variable names ignore case: a local $names here would hide the script-level $Names table
  $outNames = @{}; $outRi = @{}; $new = $false
  foreach ($m in [regex]::Matches($text, 'CAS:([\d-]+); Mw: \d+; Lib: <<[^>]*>>; Id: \d+; RI: (\d+)')) {
    $c = $m.Groups[1].Value; if ($c -eq '0') { continue }
    $r = [int]$m.Groups[2].Value
    if ($r -gt 0 -and -not $RiCache.ContainsKey($c)) { $RiCache[$c] = $r; $new = $true }
    if ($Names.ContainsKey($c)) { $outNames[$c] = $Names[$c] }
    if ($RiCache.ContainsKey($c)) { $outRi[$c] = $RiCache[$c] }
  }
  if ($new) { [IO.File]::WriteAllLines($RiFile, [string[]]@($RiCache.GetEnumerator() | ForEach-Object { "$($_.Key)`t$($_.Value)" })) }
  return @{ names = $outNames; ri = $outRi }
}

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
      Send-Json $ctx 200 @{ ok = $true; app = 'sfplab-nist-bridge'; version = 2; nist = $NistDir; names = $Names.Count; ri = $RiCache.Count }
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
        $ex = Get-Extras $text
        Send-Json $ctx 200 @{ ok = $true; result = $text; names = $ex.names; ri = $ex.ri; lib = $NistLabel }
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
