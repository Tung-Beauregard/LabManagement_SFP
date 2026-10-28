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

# NIST is a 32-bit program that splits FILESPEC.FIL on spaces: keep the work folder short and space-free.
# Created before NIST is looked for, because the not-found message tells people to put nistdir.txt in it.
if ($WorkDir -match '\s') { Write-Host 'WorkDir 不能有空白'; exit 1 }
New-Item -ItemType Directory -Force $WorkDir | Out-Null

# The NIST folder path must not contain [ ] or `: the rest of this script uses plain Test-Path, which reads them
# as wildcards, so such a folder would be accepted here and then never seen again (searches time out and the
# AUTOIMP.MSD of ChemStation / AMDIS gets overwritten)
function Test-NistDir([string]$dir) {
  if (-not $dir -or $dir -match '[\[\]`]') { return $false }
  try { return [IO.File]::Exists([IO.Path]::Combine($dir, 'nistms$.exe')) } catch { return $false }
}
# One spelling for a folder: C:/NIST20/MSSEARCH, C:\NIST20\MSSEARCH\. and C:\NIST20\MSSEARCH\ all become
# C:\NIST20\MSSEARCH. Windows reports running programs in this form, so the single-instance check below would
# otherwise mistake the bridge's own NIST for another copy.
function Get-CanonicalDir([string]$dir) { try { return [IO.Path]::GetFullPath($dir).TrimEnd('\') } catch { return $dir } }
# Look for NIST*\MSSEARCH at the root of each local disk and USB drive: C: first (same order as before, so a PC
# with NIST on C: behaves exactly as it used to), then other fixed disks, then removable drives, each by letter.
# The first drive that has one wins. The drive list and order come from the drive type alone, and a drive is only
# touched (IsReady, folder listing) when its turn comes, so a PC with NIST on C: never reads its USB sticks.
# Only the top level of a drive is checked, so old copies kept deep in data folders
# (e.g. D:\01_實驗室資料\GCMS\NIST02) are never picked. Network drives and CD/DVD are skipped: a disconnected
# network drive can stall the start-up for a long time. A drive that is pulled out or unreadable is skipped.
function Find-NistDirs {
  $drives = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq [IO.DriveType]::Fixed -or $_.DriveType -eq [IO.DriveType]::Removable } |
    Sort-Object @{ Expression = { if ($_.Name -eq 'C:\') { 0 } elseif ($_.DriveType -eq [IO.DriveType]::Fixed) { 1 } else { 2 } } }, Name)
  foreach ($d in $drives) {
    $hits = New-Object 'System.Collections.Generic.List[string]'
    try {
      if (-not $d.IsReady) { continue }
      $root = $d.RootDirectory.FullName
      $cands = @(foreach ($v in 'NIST20', 'NIST23', 'NIST26', 'NIST17') { [IO.Path]::Combine($root, $v, 'MSSEARCH') })
      $cands += @(foreach ($f in [IO.Directory]::GetDirectories($root, 'NIST*')) { [IO.Path]::Combine($f, 'MSSEARCH') })
      # the fixed names and the folder listing can name the same folder twice (also in a different letter case)
      $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
      foreach ($c in $cands) { if ((Test-NistDir $c) -and $seen.Add($c)) { $hits.Add($c) } }
    } catch { continue }
    if ($hits.Count -gt 0) { return $hits.ToArray() }
  }
  return @()
}
# $WorkDir\nistdir.txt pins one NIST copy (the page's launch button starts this script without arguments, so it
# cannot pass -NistDir). Notepad saves UTF-8 without a BOM by default, which Get-Content in PowerShell 5.1 would
# read as ANSI and garble a path with Chinese folder names: honour a BOM, else try strict UTF-8, else ANSI (Big5).
$NistFile = [IO.Path]::Combine($WorkDir, 'nistdir.txt')
function Read-NistPin {
  # Returns the candidate paths (usually one). Without a BOM the bytes are read both as strict UTF-8 and as ANSI,
  # because some Big5 text (e.g. 羅, 簡) is also valid UTF-8; the caller takes whichever names a real NIST folder.
  # Invisible format characters (U+202A from a path copied out of a Properties dialog, U+200B, U+FEFF) are removed.
  if (-not [IO.File]::Exists($NistFile)) { return @() }
  try { $bytes = [IO.File]::ReadAllBytes($NistFile) } catch { return @() }
  $texts = @()
  $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) -or
         ($bytes.Length -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF)))
  if ($bom) {
    $ms = New-Object IO.MemoryStream -ArgumentList (, $bytes)
    $sr = New-Object IO.StreamReader -ArgumentList $ms, $true
    $texts += $sr.ReadToEnd(); $sr.Close()
  } else {
    try { $texts += (New-Object Text.UTF8Encoding -ArgumentList $false, $true).GetString($bytes) } catch {}
    $texts += [Text.Encoding]::Default.GetString($bytes)
  }
  $out = New-Object 'System.Collections.Generic.List[string]'
  foreach ($t in $texts) {
    $line = @($t -split "`r?`n" | ForEach-Object { ($_ -replace '\p{Cf}', '').Trim() } | Where-Object { $_ }) | Select-Object -First 1
    if ($line) { $line = $line.Trim('"').Trim() }
    if ($line -and -not $out.Contains($line)) { $out.Add($line) }
  }
  return $out.ToArray()
}
# Which NIST to use when -NistDir is not given. A path in nistdir.txt is authoritative: when that folder is not
# there (USB stick not plugged in), say so and use nothing, rather than quietly searching another copy's library.
# Without the file, scan the drives. Sets $script:NistMode to 'pin' or 'scan'.
function Resolve-NistDir {
  $pins = @(Read-NistPin)
  if ($pins.Count -gt 0) {
    $script:NistMode = 'pin'
    foreach ($p in $pins) { if (Test-NistDir $p) { $p = Get-CanonicalDir $p; $script:NistPin = $p; return $p } }
    $pin = $pins[0]; $script:NistPin = $pin
    if ($pin -match '[\[\]`]') { Write-Host ($NistFile + ' 指定的路徑不能有 [ ] 或 ` 符號:' + $pin + '。請把 NIST 的資料夾改名,或刪掉這個檔改成自動尋找') }
    else { Write-Host ($NistFile + ' 指定的位置沒有 nistms$.exe:' + $pin + '。隨身碟沒插上就插上後再試;換了磁碟代號就改這個檔;不想固定用這一份,就刪掉這個檔改成自動尋找') }
    return ''
  }
  $script:NistMode = 'scan'
  $found = @(Find-NistDirs)
  if ($found.Count -gt 1) { Write-Host ('找到多份 NIST:' + ($found -join '、') + ';使用第一份。要固定用另一份,把它的路徑寫進 ' + $NistFile) }
  if ($found.Count -gt 0) { return (Get-CanonicalDir $found[0]) }
  return ''
}
function Get-NistLabel([string]$dir) { if ($dir -match 'NIST(\d+)') { return 'NIST ' + $Matches[1] }; return 'NIST' }

if ($PSBoundParameters.ContainsKey('NistDir')) {
  $NistMode = 'param'
  $NistDir = $NistDir.Trim().Trim('"')
  if (-not (Test-NistDir $NistDir)) {
    if ($NistDir -match '[\[\]`]') { Write-Host ('-NistDir 的路徑不能有 [ ] 或 ` 符號:' + $NistDir + '。請把 NIST 的資料夾改名後再試') }
    else { Write-Host ('-NistDir 指定的資料夾裡沒有 nistms$.exe:' + $NistDir + '。請指定 NIST 的 MSSEARCH 資料夾,例如 -NistDir E:\NIST20\MSSEARCH') }
    exit 1
  }
  $NistDir = Get-CanonicalDir $NistDir
} else {
  $NistMode = 'scan'
  $NistDir = Resolve-NistDir
  if (-not $NistDir) {
    if ($NistMode -eq 'scan') {
      Write-Host ('找不到 NIST MS Search(nistms$.exe)。已找過每顆本機磁碟與隨身碟根目錄的 NIST* 資料夾(路徑有 [ ] 的不算)。裝在別的位置的話,把 MSSEARCH 資料夾的完整路徑寫進 ' + $NistFile + ',或執行時加 -NistDir,例如 -NistDir E:\NIST20\MSSEARCH')
    }
    exit 1
  }
}
# Version label for the page's citations ("NIST 20" from C:\NIST20\MSSEARCH)
$NistLabel = Get-NistLabel $NistDir

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
# NIST's other plain-text marks: (.+/-.) (.+.) (.-.) for (±) (+) (-), and CAS index edition tags such as
# "Lactide (6CI)". Greek letters as above; NIST writes the double-bond Δ in lowercase too (.delta.5,7-), so a δ
# right before a locant becomes Δ (δ-3-Carene and δ-Cadinene keep their δ: a hyphen comes first).
$RxNistHint = New-Object Text.RegularExpressions.Regex('[.<]|alpha|beta|gamma|delta|epsilon|omega|CI\)', 'IgnoreCase')
function Format-NistName([string]$s) {
  if (-not $RxNistHint.IsMatch($s)) { return $s }
  $s = $s.Replace('.+/-.', '±').Replace('(.+.)', '(+)').Replace('(.-.)', '(-)')
  $s = [regex]::Replace($s, '\s*\(\d*CI\)\s*$', '')
  return [regex]::Replace((Convert-Greek $s), '(?<![A-Za-z])δ(?=\(?\d)', 'Δ')
}
# Which name to show for a CAS. NIST's primary name is sometimes a CAS index name
# ("1,3-Cyclohexadiene, 1-methyl-4-(1-methylethyl)-") or a semi-systematic one ("Cadina-1(10),4-diene") while a
# synonym is the name people use (".alpha.-Terpinene", "δ-Cadinene"). Every name gets a "how systematic" score:
# CAS index comma, bicyclo / stereo brackets, ξ, stereo locants, substituent prefixes with locants,
# parent-hydride stems, 3 per locant. A name is replaced only when it scores 15 or more (20 or more when it is a
# plain substituent name with no brackets, stereo, ξ or parent-hydride stem: 6,10-Dimethyl-5,9-undecadien-2-one,
# 1,1,6-Trimethyl-1,2-dihydronaphthalene and 5,6,7,8,4'-Pentamethoxyflavone are what people write, and NIST lists
# Dihydropseudoionone, Dehydro-ar-ionene and Ponkanetin before Geranylacetone or Tangeretin), and only by a
# synonym that scores 9 or less and at least 10 lower. So 1,8-Cineole, 1-Octen-3-ol, 2-Methyl-1-butene and
# 1,2,3-Trimethoxybenzene stay as NIST has them, and a systematic name is never swapped for another systematic one.
# Synonyms that are registry or product codes (Surfynol 104, Rcra waste number U208), annotations (Steriochemistry
# unspecified, Dioxin (herbicide contaminant)), bare class words (Carboximide, Alkaloid A), acronyms, all-caps,
# very long, or longer than the name they would replace are never chosen. Some NIST records carry another compound's
# synonym list (14504-09-7, C6Cl6O2, lists 8-Bromoguanine), so a pick must also fit the record's formula: no name
# word for an element the formula lacks, a word for every Br, Cl, F, I, S, P or Si it has, and no alcohol / ketone /
# aldehyde / ether mix-up with the name it replaces (4-Methyl-1-phenylpentan-3-ol is not Isopropyl phenethyl ketone,
# and 3-ethoxy-3,7-dimethyl-1,6-octadiene is not Ethyl linalool). A pick may not add E/Z or cis/trans the name
# did not have, nor drop the locants of a multiplied substituent (2,3,5-Trimethyl-6-butylpyrazine is not just
# Butyltrimethylpyrazine).
$RxLocant  = [regex]'(?<=^|[-,(\[ ])\d+[a-z]?(?=[-,()\]'']|$)'
$RxSubst   = New-Object Text.RegularExpressions.Regex('\d[\d,a-z'']*-(?:di|tri|tetra|penta|hexa|hepta|octa|nona|deca)?(?:methyl|ethyl|propyl|butyl|pentyl|hexyl|isopropyl|methoxy|ethoxy|hydroxy|oxo|methylene|methylidene|ethenyl|ethylidene|propenyl|vinyl|acetyl|formyl|hydro)|methylethyl|methylethenyl|ylidene|propan-2-yl|prop-1-en-2-yl|carboxaldehyde', 'IgnoreCase')
$RxStereo  = [regex]'\(\d+[a-z]?[RSαβξ]|\brel\b|[RS]\*'
# bicyclo / spiro numbers (bicyclo[3.1.1]) and stereo descriptors in brackets ([1S-(1α,4aβ)]-, [S-(Z,E)]-);
# fusion locants (Benz[a]anthracene, Imidazo[1,2-b]pyridazine) belong to ordinary names
$RxBracket = [regex]'\[\d+\.\d+|\[[^\]]*(?:\d[RS]\b|[αβξ]|\b[RS]-)'
$RxParent  = [regex]'^[A-Z][a-z]+a-\d'
$RxEZ      = [regex]'\(\d+[EZ]'
$RxOptical = [regex]'^(?:\([+\-−±]\)-|\(\+/-\)-|\([RS]\)-|D-|L-|DL-|dl-|d-|l-)'
# any stereo information at all; a pick may only carry E/Z or cis/trans when the name it replaces had some
$RxAnyStereo = [regex]'\([^)]*\b[EZRS]\b[^)]*\)|(?<![A-Za-z])(?:cis|trans|endo|exo|rel|rac)(?=[-,])|[αβξ±]|\(\d+[a-z]?[RSαβξEZ]|[EZ]-'
$RxAddedStereo = [regex]'\((?:[EZ])(?:,[EZ])*\)|(?<![A-Za-z])(?:cis|trans)(?=[-,])'
$RxJunk    = New-Object Text.RegularExpressions.Regex('#|\(Salt/Mix\)|^(?:NSC|UN|NCI|CCRIS|HSDB|EINECS|AI3|BRN|FEMA|UNII|CHEBI|DTXSID|MFCD|ZINC|SCHEMBL)\b|\d{5,}|\b(?:compound|inhibitor|derivative|oil|hallucinogen|steroid|unspecified|related|waste|number|parent|artifact|activator|contaminant|herbicide|insecticide|pesticide|fungicide|antioxidant|plasticizer|reagent|impurity|metabolite|isomer|alkaloid)\b|methylethyl|^(?:Di|Tri)?(?:carboximide|imide|amide|lactone|ester|ketone|aldehyde|alcohol|ether|acid)$', 'IgnoreCase')
# trailing product codes (Ionox 100, Permethyl 99A, Surfynol TG, Rcra ... U208), a trailing qualifier in
# parentheses after a space (Dihydroxytoluene (Related)), and names that start with an acronym word (MP diol glycol)
$RxTrail   = [regex]'\s(?:\d+[A-Za-z]*|[A-Z]\d+|[A-Z]{2})$|\s\([^)]*[A-Za-z]{3,}[^)]*\)|^[A-Z]{2,}\s'
# a single trailing capital, roman numeral or "Base" is usually a catalogue name (Grotan B, Chroman I); such a
# pick is used only when no other synonym qualifies (Cembrene A has no better one)
$RxWeakEnd = [regex]'\s(?:[A-Z]|[IVX]+|Base)$'
# a lowercase word after the first one has to look like chemistry (acetate, oxide, ...); "Kodaflex txib" does not
$RxChemWord = [regex]'^(?:[a-z]*(?:ane|ene|yne|ol|al|one|ate|ite|ide|ine|yl|ic|ose|oid|in|ium)|acid|ester|ether|alcohol|glycol|lactone|anhydride|ketone|aldehyde|oxide|epoxide|amine|amide|nitrile|acetal|hydrate)$'
# product and registry codes (MGA 100, JWH-018) and acronyms (TMPD Glycol, Butyl-PBD); case-sensitive, so
# Terpinen-4-ol and trans-2-Hexenal are not caught. Also the ASCII Greek of old names (2-Methyltetrahydro-b-carboline)
$RxCode    = [regex]'\b[A-Z]{2,}[\s\-]?\d+\b|[A-Z]{3}|(?<![A-Za-z])[abgd]-(?=[a-z])'
# a lowercase first letter is only normal for stereo and position prefixes (trans-, p-, tert-, ...)
$RxLowerOk = [regex]'^(?:cis|trans|endo|exo|syn|anti|erythro|threo|meso|rac|rel|ent|epi|allo|sec|tert|iso|neo|nor|dl|[ompndl])[-,]'
# a multiplied substituent; when the replaced name gives its locants, a pick without digits loses the isomer
$RxMulti   = New-Object Text.RegularExpressions.Regex('(?:di|tri|tetra|penta|hexa)(?:methyl|ethyl|propyl|butyl|chloro|fluoro|bromo|iodo|methoxy|hydroxy|amino|nitro)', 'IgnoreCase')
# also refused: a bare prefix ("trans-"), and the old Δ double-bond notation (Ergosta-5,7-dien-3β-ol is the
# name in use, not Δ5,7-Ergostadienol)
function Test-UsableSynonym([string]$s) {
  if (-not ($s.Length -ge 5 -and $s.Length -le 60 -and $s.Split(' ').Count -le 4 -and -not $s.StartsWith('$:') -and
    -not $s.EndsWith('-') -and -not $s.StartsWith('Δ') -and -not $RxJunk.IsMatch($s) -and -not $RxCode.IsMatch($s) -and -not $RxTrail.IsMatch($s) -and
    $s -cmatch '[a-z]{3}' -and ($s -cmatch '^[^a-z]' -or $RxLowerOk.IsMatch($s)))) { return $false }
  $w = $s.Split(' ')
  for ($i = 1; $i -lt $w.Count; $i++) { if ($w[$i] -cmatch '^[a-z]+$' -and -not $RxChemWord.IsMatch($w[$i])) { return $false } }
  # a three-letter-or-longer word with no vowel is an abbreviation (Hcdd)
  foreach ($x in ($s -split "[\s\-(),']")) { if ($x -cmatch '^[A-Za-z]{3,}$' -and $x -notmatch '[aeiouy]') { return $false } }
  return $true
}
# element -> the name fragments that stand for it
$ElemWords = @{ Br = 'brom'; Cl = 'chlor'; F = 'fluor'; I = 'iod'; S = 'thi|sulf|sulph|mercapt'; P = 'phosph'; Si = 'sil'
  N = 'nitr|amino|amine|amide|aza|pyrid|indol|imidazol|purin|guanin|cytosin|quinolin|ephedrin|nicotin|cyan' }
$RxFormula = [regex]'(?m)^Formula: ([^\r\n]*)'
function Get-NameClass([string]$s) {
  $l = $s.ToLowerInvariant()
  if ($l -match 'ketone|one\b') { return 'ketone' }
  if ($l -match 'alcohol|ol\b|hydroxy') { return 'alcohol' }
  if ($l -match 'aldehyde|al\b') { return 'aldehyde' }
  if ($l -match 'ether|oxy\b|(?:meth|eth|prop|but|pent|hex|benzyl|phen)oxy') { return 'ether' }
  return ''
}
# $els: element symbols of the record's formula (empty when NIST gives none: then only the class check applies)
function Test-FormulaFit([string]$pick, [string]$cur, $els) {
  if ($els.Count -gt 0) {
    $n = $pick.ToLowerInvariant()
    foreach ($e in $ElemWords.Keys) {
      $has = $els.Contains($e); $named = $n -match $ElemWords[$e]
      if ($named -and -not $has) { return $false }
      if ($has -and -not $named -and $e -ne 'N') { return $false }
    }
  }
  $a = Get-NameClass $pick; $b = Get-NameClass $cur
  return (-not $a -or -not $b -or $a -eq $b)
}
function Get-LocantFree([string]$s) { return ([regex]::Replace($s, "[\d,'\-()\[\]\s]", '')).ToLowerInvariant() }
function Get-NameScore([string]$s) {
  $n = 3 * $RxLocant.Matches($s).Count
  if ($s.Contains(', ')) { $n += 100 }
  if ($RxBracket.IsMatch($s)) { $n += 30 }
  if ($s.Contains('ξ')) { $n += 20 }
  if ($RxStereo.IsMatch($s)) { $n += 15 }
  if ($RxSubst.IsMatch($s)) { $n += 4 }
  if ($RxParent.IsMatch($s)) { $n += 9 }
  if ($RxEZ.IsMatch($s)) { $n += 4 }
  if ($RxOptical.IsMatch($s)) { $n += 2 }
  return $n
}
# $primary is already formatted; the synonyms come from $block (the record's lines between Name and CASNO).
# A CAS index name is first swapped for the first synonym that is not one, as earlier versions did. The result
# (or a primary that was not a CAS index name) is then replaced as described above. Among the qualifying synonyms,
# NIST's order decides (picking the lowest score instead turned 2,4-Lutidine into α,γ-Dimethylpyridine), except
# that one of the same class as the name it replaces comes first (Brassicasterol over Brassicasterin) and a
# catalogue-looking ending comes last. When the pick carries an optical prefix and NIST also lists the plain name,
# the plain name is used ((+)-δ-Cadinene -> δ-Cadinene).
$RxSynon = [regex]'(?m)^Synon: ([^\r\n]*)'
function Select-Name([string]$primary, [string]$block) {
  $cur = $primary
  if ($primary.Contains(', ')) {
    $first = $null
    foreach ($sm in $RxSynon.Matches($block)) {
      $s = $sm.Groups[1].Value.Trim()
      if ($s.StartsWith('$:') -or $s -match ', ' -or $s.Length -gt 40 -or $s -match '#|\(Salt/Mix\)|^NSC |^UN ' -or
          $s -cmatch '^[^a-z]*$' -or [regex]::Matches($s, '[A-Za-z]').Count -lt 3) { continue }
      $first = $s; break
    }
    if (-not $first) { return $primary }
    $cur = Format-NistName $first
  }
  $ps = Get-NameScore $cur
  $plainName = -not ($RxBracket.IsMatch($cur) -or $cur.Contains('ξ') -or $RxStereo.IsMatch($cur) -or $RxParent.IsMatch($cur) -or $RxEZ.IsMatch($cur))
  if ($ps -lt 15 -or ($plainName -and $ps -lt 20)) { return $cur }
  $bare = Get-LocantFree $cur
  $curStereo = $RxAnyStereo.IsMatch($cur)
  $curMulti = @(if ($RxLocant.IsMatch($cur)) { $RxMulti.Matches($cur) | ForEach-Object { $_.Value.ToLowerInvariant() } })
  $curClass = Get-NameClass $cur
  $els = New-Object 'Collections.Generic.HashSet[string]'
  $fm = $RxFormula.Match($block)
  if ($fm.Success) { foreach ($em in [regex]::Matches($fm.Groups[1].Value, '[A-Z][a-z]?')) { [void]$els.Add($em.Value) } }
  $ok = New-Object 'Collections.Generic.List[string]'
  foreach ($sm in $RxSynon.Matches($block)) {
    $s = Format-NistName $sm.Groups[1].Value.Trim()
    # a common name is shorter than the systematic one it stands for; the longer picks were all worse.
    # The same name without its locants is no improvement (2,4,5-Trimethylthiazole -> Trimethylthiazole loses
    # which isomer it is)
    if ($s.Length -gt $cur.Length -or -not (Test-UsableSynonym $s) -or (Get-LocantFree $s) -eq $bare) { continue }
    $sc = Get-NameScore $s
    if ($sc -gt 9 -or $sc -gt $ps - 10 -or -not (Test-FormulaFit $s $cur $els)) { continue }
    if (-not $curStereo -and $RxAddedStereo.IsMatch($s)) { continue }
    if ($s -notmatch '\d' -and @($RxMulti.Matches($s) | Where-Object { $curMulti -contains $_.Value.ToLowerInvariant() }).Count -gt 0) { continue }
    if (-not $ok.Contains($s)) { $ok.Add($s) }
  }
  if ($ok.Count -eq 0) { return $cur }
  $pick = $null
  foreach ($pass in 1..3) {
    foreach ($s in $ok) {
      $weak = $RxWeakEnd.IsMatch($s)
      if (($pass -eq 1 -and $curClass -and -not $weak -and (Get-NameClass $s) -eq $curClass) -or ($pass -eq 2 -and -not $weak) -or $pass -eq 3) { $pick = $s; break }
    }
    if ($pick) { break }
  }
  if ($RxOptical.IsMatch($pick)) { $plain = $RxOptical.Replace($pick, ''); if ($ok.Contains($plain)) { return $plain } }
  return $pick
}
$NameFile = Join-Path $WorkDir 'nist_names.tsv'
# First line of the table. Tables built by older versions of this script (no header, CAS index rule only)
# are rebuilt once; older scripts skip this line because it has no tab.
$NameTableTag = '#sfplab-names v2'
function Test-NameTableTag {
  if (-not (Test-Path $NameFile)) { return $false }
  $r = New-Object IO.StreamReader($NameFile, [Text.Encoding]::UTF8)
  try { return ($r.ReadLine() -eq $NameTableTag) } finally { $r.Close() }
}
function Get-TableCount {
  if (-not (Test-Path $NameFile)) { return 0 }
  $n = 0; foreach ($l in [IO.File]::ReadLines($NameFile)) { if ($l.IndexOf("`t") -gt 0) { $n++ } }
  return $n
}
function Build-NameTable {
  $riLib = Join-Path $NistDir 'nist_ri'; $l2n = Join-Path $NistDir 'lib2nist.exe'; $dbu = Join-Path $riLib 'USER.DBU'
  # cannot rebuild: keep using whatever table is there
  if (-not (Test-Path $dbu) -or -not (Test-Path $l2n)) { return (Test-Path $NameFile) }
  if ((Test-Path $NameFile) -and (Get-Item $NameFile).LastWriteTime -gt (Get-Item $dbu).LastWriteTime -and (Test-NameTableTag)) { return $true }
  # One builder at a time: pressing the page's launch button again during the build starts a second copy of this
  # script, which would otherwise read the half-written export or race on the table
  $lockFile = Join-Path $WorkDir 'nist_names.lock'
  try { $lock = [IO.File]::Open($lockFile, 'OpenOrCreate', 'ReadWrite', 'None') }
  catch { Write-Host 'CAS 對照表正在由另一個連線程式視窗建立,這個視窗不用開,會自動關掉。'; Start-Sleep -Seconds 3; exit 0 }
  try {
    Write-Host '從 NIST 的 RI 資料庫建立(或更新)CAS 對照表,約需四分鐘,會跳出 lib2nist 視窗,請不要關掉它,之後不用再做…'
    $ini = Join-Path $WorkDir 'lib2nist.ini'; $msp = Join-Path $WorkDir 'nist_ri.msp'; $log = Join-Path $WorkDir 'lib2nist.log'
    if (-not ((Test-Path $msp) -and (Get-Item $msp).LastWriteTime -gt (Get-Item $dbu).LastWriteTime)) {
      # lib2nist writes to a .part file that becomes nist_ri.msp only when its log says it converted the whole
      # library (its exit code is 0 even when it fails), so a window closed halfway never leaves a short export
      $part = Join-Path $WorkDir 'nist_ri.part.msp'
      if (Test-Path $part) { Remove-Item -LiteralPath $part }
      # an .ini on the command line keeps lib2nist from writing its settings into the registry;
      # do not start it hidden: with -WindowStyle Hidden it sits idle and never writes the output
      [IO.File]::WriteAllText($ini, "[Directory]`r`nNIST=<None>`r`n[Output]`r`nDB=0`r`nText=1`r`nTextFileType=0`r`nIncludeSynonyms=1`r`nKeepIDs=1`r`n", $Latin1)
      Start-Process -FilePath $l2n -ArgumentList '/log1', "`"$log`"", "`"$ini`"", '/OutMSP', '/NoAlias', '/AllowNoPeaks', "`"$riLib`"", "`"=$part`"" -Wait
      $logText = if (Test-Path $log) { [IO.File]::ReadAllText($log, $Latin1) } else { '' }
      $i = $logText.LastIndexOf('conversion into text file started')
      $done = $i -ge 0 -and $logText.Substring($i) -match 'Converted ([1-9]\d*) spectra'
      if (-not $done -or -not (Test-Path $part)) {
        if (Test-Path $part) { Remove-Item -LiteralPath $part }
        Write-Host 'lib2nist 沒有完成匯出(視窗被關掉,或出了錯),先沿用原本的 CAS 對照表,下次啟動再試。'
        return (Test-Path $NameFile)
      }
      Move-Item -LiteralPath $part -Destination $msp -Force
    }
    Write-Host '整理對照表…'
    # one regex pass over the whole export (a line-by-line PowerShell loop takes minutes); only about 39k of the
    # 140k compounds have a CAS number, the rest are listed with CASNO: 0 and cannot be matched anyway
    $text = [IO.File]::ReadAllText($msp, $Latin1)
    $rx = New-Object Text.RegularExpressions.Regex('^Name: ([^\r\n]*)((?:\r?\n(?!CASNO: |Name: )[^\r\n]*)*)\r?\nCASNO: ([1-9][0-9]{4,})\r?$', [Text.RegularExpressions.RegexOptions]::Multiline)
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append($NameTableTag).Append("`n")
    $count = 0
    foreach ($m in $rx.Matches($text)) {
      $name = $m.Groups[1].Value.Trim(); $cas = $m.Groups[3].Value
      $name = Format-NistName $name
      $nm = Select-Name $name $m.Groups[2].Value
      [void]$sb.Append($cas.Substring(0, $cas.Length - 3)).Append('-').Append($cas.Substring($cas.Length - 3, 2)).Append('-').Append($cas.Substring($cas.Length - 1)).Append("`t").Append($nm).Append("`n")
      $count++
    }
    $text = $null
    # a table much shorter than the one it would replace means a damaged export: keep the old one
    $old = Get-TableCount
    if ($old -gt 0 -and $count -lt 0.9 * $old) {
      Write-Host "新的 CAS 對照表只有 $count 筆,比原本的 $old 筆少很多,先沿用原本的,下次啟動再試。"
      Remove-Item -LiteralPath $msp
      return $true
    }
    # written next to it and then moved into place, so a crash halfway never leaves a short table with the tag
    $tmp = $NameFile + '.tmp'
    [IO.File]::WriteAllText($tmp, $sb.ToString(), (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $NameFile -Force
    Remove-Item -LiteralPath $msp
    return $true
  } finally { $lock.Close() }
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
  # NIST may live on a USB stick, so check it again before every search. A pinned copy (nistdir.txt, re-read
  # every time) is never swapped for another one; a scanned copy is re-scanned only when it has gone missing,
  # e.g. the stick came back under another drive letter. A copy given with -NistDir is only checked.
  if ($NistMode -ne 'param') {
    $nd = $script:NistDir
    if ($NistMode -eq 'pin' -or [IO.File]::Exists($NistFile) -or -not (Test-NistDir $nd)) { $nd = Resolve-NistDir }
    if ($nd -and $nd -ne $script:NistDir) { $script:NistDir = $nd; $script:NistLabel = Get-NistLabel $nd; Write-Host ('NIST 位置改變,改用 ' + $nd) }
    $ok = [bool]$nd -and (Test-NistDir $script:NistDir)
  } else { $ok = Test-NistDir $script:NistDir }
  if (-not $ok) {
    # A pin is never swapped for another copy, so restarting cannot help: name the file and the path instead
    if ($script:NistMode -eq 'pin') {
      throw ($NistFile + ' 指定的 ' + $script:NistPin + ' 裡沒有 NIST(nistms$.exe)。隨身碟沒插上就插上後再搜;換了磁碟代號就改這個檔;不想固定用這一份就刪掉這個檔。')
    }
    # the page only offers its launch button after a search finds no bridge at all, hence the wording
    throw 'NIST 資料夾不見了(隨身碟拔掉了,或換了磁碟代號?)。插回去後再搜一次。還是不行,把 NIST 連線程式的視窗關掉再搜一次,網頁會出現「啟動 NIST 連線程式」鈕。'
  }
  $query = Join-Path $WorkDir 'QUERY.MSP'
  $spec = Join-Path $WorkDir 'FILESPEC.FIL'
  $auto = Join-Path $NistDir 'AUTOIMP.MSD'
  $ready = Join-Path $NistDir 'SRCREADY.TXT'
  $result = Join-Path $NistDir 'SRCRESLT.TXT'
  [IO.File]::WriteAllText($query, $msp, $Latin1)
  [IO.File]::WriteAllText($spec, "$query OVERWRITE`r`n", $Latin1)
  # NIST MS Search runs as a single instance. If a copy from another folder is open (ChemStation or AMDIS's own,
  # or the copy used before a switch), our launch is handed to it, it reads its own AUTOIMP.MSD and the search
  # would only time out after $TimeoutSec: stop early and say which window to close
  $here = Get-CanonicalDir $NistDir
  $other = @(Get-CimInstance Win32_Process -Filter "Name='nistms.exe' OR Name='nistms`$.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -and ((Get-CanonicalDir ([IO.Path]::GetDirectoryName($_.ExecutablePath))) -ne $here) })
  if ($other.Count -gt 0) { throw ('另一份 NIST 正在執行(' + $other[0].ExecutablePath + ')。NIST 一次只能開一份,請先關掉那個 NIST 視窗再搜一次。') }
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
