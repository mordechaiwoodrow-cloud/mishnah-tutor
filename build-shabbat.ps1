# build-shabbat.ps1
# Fetches Shabbat (24 chapters) from Sefaria with sentence-based phrase splitting.
# No API key required.
# Phrase rule: each sentence (ends with . ! ?) = one phrase;
#              sentences of <=3 words merge into nearest neighbor.
# Uses a custom JSON builder to guarantee segments are ALWAYS serialized as
# JSON arrays [...] — even when there is only 1 segment (works around PS5.1 bug).

param([string]$OutputFile = (Join-Path $PSScriptRoot 'mishna-data.json'))
$ErrorActionPreference = 'Continue'

# ── Text helpers ──────────────────────────────────────────────────────────────

function Strip-Html([string]$s) {
  if (-not $s) { return '' }
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = [regex]::Replace($s, '\s+', ' ')
  return $s.Trim()
}

function Extract-EnglishText([string]$s) {
  if (-not $s) { return '' }
  $bolds = [regex]::Matches($s, '(?s)<b>(.*?)</b>')
  if ($bolds.Count -gt 0) {
    $joined = ($bolds | ForEach-Object { $_.Groups[1].Value }) -join ' '
    $joined = [regex]::Replace($joined, '<[^>]+>', '')
    $joined = [regex]::Replace($joined, '\s+', ' ')
    return $joined.Trim()
  }
  return Strip-Html $s
}

function Invoke-Sefaria([string]$url) {
  for ($i = 1; $i -le 3; $i++) {
    try   { return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20 }
    catch { if ($i -lt 3) { Start-Sleep -Milliseconds (600 * $i) } else { throw } }
  }
}

# ── Sentence splitting ────────────────────────────────────────────────────────

# Split text at sentence boundaries.
# Sentences of <=3 words are merged into their previous neighbor
# (or next, if there is no previous).
function Get-Sentences([string]$text) {
  $text = $text.Trim()
  $raw  = @([regex]::Split($text, '(?<=[.!?])\s+') |
            Where-Object { $_.Trim() -ne '' })
  if ($raw.Count -le 1) { return @($text) }

  $buf = [System.Collections.ArrayList]::new()
  foreach ($s in $raw) {
    $wc = @($s.Trim() -split '\s+').Count
    if ($wc -le 3 -and $buf.Count -gt 0) {
      $buf[$buf.Count - 1] = ($buf[$buf.Count - 1] + ' ' + $s.Trim())
    } else {
      $buf.Add($s.Trim()) | Out-Null
    }
  }
  # If first sentence is still <=3 words, push onto next
  if ($buf.Count -ge 2 -and (@($buf[0] -split '\s+').Count -le 3)) {
    $buf[1] = ($buf[0] + ' ' + $buf[1])
    $buf.RemoveAt(0)
  }
  return @($buf)
}

# ── Phrase builder ────────────────────────────────────────────────────────────

# Each English sentence → one phrase; Hebrew sliced proportionally.
# Returns a plain PS array (the JSON builder handles array-ness).
function Make-Phrases([string]$heText, [string]$enText) {
  $heText = $heText.Trim(); $enText = $enText.Trim()
  $sents  = Get-Sentences $enText
  if ($sents.Count -le 1) { return @(@{ he = $heText; en = $enText }) }

  $phrases  = [System.Collections.ArrayList]::new()
  $enTotal  = [Math]::Max($enText.Length, 1)
  $heTotal  = $heText.Length
  $heCursor = 0; $enCursor = 0

  for ($i = 0; $i -lt $sents.Count; $i++) {
    $enS      = $sents[$i]
    $enCursor += $enS.Length + 1
    if ($i -lt $sents.Count - 1) {
      $frac    = [Math]::Min($enCursor, $enTotal) / $enTotal
      $heSplit = [int]($frac * $heTotal)
      while ($heSplit -lt ($heTotal - 1) -and $heText[$heSplit] -ne ' ') { $heSplit++ }
      $heS      = $heText.Substring($heCursor, [Math]::Max(0, $heSplit - $heCursor)).Trim()
      $heCursor = [Math]::Min($heSplit + 1, $heTotal)
    } else {
      $heS = if ($heCursor -lt $heTotal) { $heText.Substring($heCursor).Trim() } else { '' }
    }
    $phrases.Add(@{ he = $heS; en = $enS }) | Out-Null
  }
  return @($phrases)
}

# ── Segmentation ──────────────────────────────────────────────────────────────

# Merge orphan attribution pieces ("Rabbi X said" alone → "Rabbi X said — content")
function Merge-Attributions([string[]]$parts) {
  $out = [System.Collections.ArrayList]::new()
  $i   = 0
  while ($i -lt $parts.Count) {
    $p = $parts[$i].Trim()
    if ($i -lt $parts.Count - 1 -and $p.Length -lt 70 -and
        $p -match '(?i)(said|says|stated|declared|replied|asked|responded|:)\s*$') {
      $out.Add($p + ' — ' + $parts[$i + 1].Trim()) | Out-Null
      $i += 2
    } else {
      $out.Add($p) | Out-Null; $i++
    }
  }
  return @($out)
}

function Make-Segment([string]$he, [string]$en) {
  return @{ phrases = Make-Phrases $he $en }
}

# Returns a plain PS array of segment objects (1 or more).
function Smart-Segment([string]$he, [string]$en) {

  # Strategy 1: em-dash split (Mishnah case-transition marker)
  $heDash = @([regex]::Split($he, '\s*[—–]\s*') | Where-Object { $_ -ne '' })
  $enDash = @([regex]::Split($en, '\s*[—–]\s*') | Where-Object { $_ -ne '' })
  if ($heDash.Count -ge 2 -and $enDash.Count -ge 2) {
    $hM = Merge-Attributions $heDash
    $eM = Merge-Attributions $enDash
    $n  = [Math]::Min($hM.Count, $eM.Count)
    if ($n -ge 2) {
      $segs = [System.Collections.ArrayList]::new()
      for ($i = 0; $i -lt $n; $i++) { $segs.Add((Make-Segment $hM[$i] $eM[$i])) | Out-Null }
      return @($segs)
    }
  }

  # Strategy 2: English opinion markers, Hebrew proportional
  $opPat = '(?=Beit Shammai|Beit Hillel|Rabbi \w+ says|The Sages say|Rabban \w+ says)'
  $enOp  = @([regex]::Split($en, $opPat) | Where-Object { $_ -ne '' })
  if ($enOp.Count -ge 2) {
    $enOp = @($enOp | ForEach-Object {
      $t = [regex]::Replace($_.Trim(), '(?i)^\s*(and|or|but)\s+', '')
      [regex]::Replace($t, '(?i)\s+(and|or|but)\s*$', '.')
    })
    $enOp    = Merge-Attributions $enOp
    $enTotal = [Math]::Max($en.Length, 1); $heTotal = $he.Length
    $heCur   = 0; $enCur = 0
    $segs    = [System.Collections.ArrayList]::new()
    for ($i = 0; $i -lt $enOp.Count; $i++) {
      $enS    = $enOp[$i]
      $enCur += $enOp[$i].Length
      if ($i -lt $enOp.Count - 1) {
        $heSplit = [int]([Math]::Min($enCur, $enTotal) / $enTotal * $heTotal)
        while ($heSplit -lt $heTotal - 1 -and $he[$heSplit] -ne ' ') { $heSplit++ }
        $heS   = $he.Substring($heCur, [Math]::Max(0, $heSplit - $heCur)).Trim()
        $heCur = $heSplit
      } else {
        $heS = $he.Substring([Math]::Min($heCur, $heTotal)).Trim()
      }
      if ($heS -or $enS) { $segs.Add((Make-Segment $heS $enS)) | Out-Null }
    }
    if ($segs.Count -ge 2) { return @($segs) }
  }

  # Strategy 3: split sentence groups in half
  $sents = Get-Sentences $en
  if ($sents.Count -ge 3) {
    $half = [int]($sents.Count / 2)
    $en1  = ($sents[0..($half - 1)] -join ' ').Trim()
    $en2  = ($sents[$half..($sents.Count - 1)] -join ' ').Trim()
    $sp   = [int]($en1.Length / $en.Length * $he.Length)
    while ($sp -lt $he.Length - 1 -and $he[$sp] -ne ' ') { $sp++ }
    $he1  = $he.Substring(0, [Math]::Min($sp, $he.Length)).Trim()
    $he2  = $he.Substring([Math]::Min($sp, $he.Length)).Trim()
    return @((Make-Segment $he1 $en1), (Make-Segment $he2 $en2))
  }

  # Fallback: single segment
  return @((Make-Segment $he $en))
}

# ── Custom JSON builder (fixes PS5.1 single-element array bug) ────────────────

# Properly JSON-escape a string value (including surrounding quotes).
function Json-Str([string]$s) {
  if ($null -eq $s) { return '""' }
  return $s | ConvertTo-Json   # ConvertTo-Json on a bare string produces "..." with escaping
}

# Serialize a segments array to JSON — ALWAYS produces [...] even for 1 segment.
function Segs-ToJson($segs) {
  # Normalise to a plain array regardless of type returned by Smart-Segment
  if     ($segs -is [System.Collections.ArrayList]) { $arr = $segs.ToArray() }
  elseif ($segs -is [array])                        { $arr = $segs }
  else                                               { $arr = @($segs) }

  $segParts = foreach ($seg in $arr) {
    $phrases = $seg.phrases
    if     ($phrases -is [System.Collections.ArrayList]) { $phrases = $phrases.ToArray() }
    elseif ($phrases -isnot [array])                     { $phrases = @($phrases) }

    $phParts = foreach ($ph in $phrases) {
      '{"he":' + (Json-Str $ph.he) + ',"en":' + (Json-Str $ph.en) + '}'
    }
    '{"phrases":[' + ($phParts -join ',') + ']}'
  }
  return '[' + ($segParts -join ',') + ']'
}

# Build the full Shabbat JSON object string {"1":{"1":[...],...},...}
function Build-ShabbatJson($data) {
  $chParts = foreach ($ch in 1..24) {
    $chKey = "$ch"
    if (-not $data.ContainsKey($chKey)) { continue }
    $mParts = $data[$chKey].Keys |
              Sort-Object { [int]$_ } |
              ForEach-Object { "`"$_`":" + (Segs-ToJson $data[$chKey][$_]) }
    "`"$chKey`":{" + ($mParts -join ',') + '}'
  }
  return '{' + ($chParts -join ',') + '}'
}

# ── Main ──────────────────────────────────────────────────────────────────────

Write-Host "Loading $OutputFile..." -ForegroundColor Cyan
$existingJson = [System.IO.File]::ReadAllText($OutputFile, [System.Text.Encoding]::UTF8)
$existing     = $existingJson | ConvertFrom-Json

$shabbatData  = @{}
$improved     = 0
$singleFb     = 0

Write-Host "Fetching Shabbat (24 chapters) from Sefaria..." -ForegroundColor Cyan

for ($ch = 1; $ch -le 24; $ch++) {
  Write-Host "  ch.$ch" -NoNewline -ForegroundColor Yellow

  $sefData = $null
  try {
    $url     = "https://www.sefaria.org/api/texts/Mishnah_Shabbat.$ch`?context=0&commentary=0"
    $sefData = Invoke-Sefaria $url
  } catch {
    Write-Host " [Sefaria error]" -ForegroundColor Red
    $shabbatData["$ch"] = @{}; continue
  }

  $heArr = if ($sefData.he   -is [array]) { $sefData.he   } else { @($sefData.he) }
  $enArr = if ($sefData.text -is [array]) { $sefData.text } else { @($sefData.text) }
  $count = [Math]::Max($heArr.Count, $enArr.Count)

  $chData = @{}
  for ($m = 0; $m -lt $count; $m++) {
    $mNum  = $m + 1
    $heRaw = if ($m -lt $heArr.Count -and $heArr[$m]) { $heArr[$m] } else { '' }
    $enRaw = if ($m -lt $enArr.Count -and $enArr[$m]) { $enArr[$m] } else { '' }
    if ($heRaw -is [array]) { $heRaw = $heRaw -join ' ' }
    if ($enRaw -is [array]) { $enRaw = $enRaw -join ' ' }

    $he   = Strip-Html ([string]$heRaw)
    $en   = Extract-EnglishText ([string]$enRaw)
    $segs = Smart-Segment $he $en

    $segArr = if ($segs -is [array]) { $segs } else { @($segs) }
    $totalPhrases = 0
    foreach ($s in $segArr) { if ($s.phrases) { $totalPhrases += @($s.phrases).Count } }

    if ($segArr.Count -ge 2 -or $totalPhrases -ge 2) {
      Write-Host '+' -NoNewline -ForegroundColor Green; $improved++
    } else {
      Write-Host '.' -NoNewline; $singleFb++
    }

    $chData["$mNum"] = $segs
  }

  $shabbatData["$ch"] = $chData
  Write-Host " ($count)" -ForegroundColor DarkGray
}

# ── Build output JSON ─────────────────────────────────────────────────────────
Write-Host "`nBuilding Shabbat JSON..." -ForegroundColor Cyan
$shabbatJsonStr = '"Shabbat":' + (Build-ShabbatJson $shabbatData)

# Rebuild output: serialize everything except Shabbat, then inject new Shabbat block
$outputWithout = @{}
foreach ($p in $existing.PSObject.Properties) {
  if ($p.Name -ne 'Shabbat') { $outputWithout[$p.Name] = $p.Value }
}
$baseJson = $outputWithout | ConvertTo-Json -Depth 12 -Compress
# Inject Shabbat before the LAST closing brace only
$lastBrace = $baseJson.LastIndexOf('}')
$fullJson  = $baseJson.Substring(0, $lastBrace) + ',' + $shabbatJsonStr + '}'

Write-Host "Writing $OutputFile..." -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputFile, $fullJson, $utf8)
$sizeMB = [Math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
Write-Host "Done! improved=$improved  single-fallback=$singleFb  size=$sizeMB MB" -ForegroundColor Green

# ── Validate ──────────────────────────────────────────────────────────────────
Write-Host "Validating..." -ForegroundColor Cyan
$check  = [System.IO.File]::ReadAllText($OutputFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
$notArr = 0; $noPhrase = 0
foreach ($chP in $check.Shabbat.PSObject.Properties) {
  foreach ($mP in $chP.Value.PSObject.Properties) {
    if ($mP.Value -isnot [array]) {
      Write-Host "  NOT-ARRAY Ch$($chP.Name):M$($mP.Name)" -ForegroundColor Red; $notArr++
    } else {
      foreach ($seg in $mP.Value) {
        if (-not $seg.phrases -or @($seg.phrases).Count -eq 0) {
          Write-Host "  NO-PHRASES Ch$($chP.Name):M$($mP.Name)" -ForegroundColor Red; $noPhrase++
        }
      }
    }
  }
}
if ($notArr -eq 0 -and $noPhrase -eq 0) {
  Write-Host "All 139 mishnayot valid." -ForegroundColor Green
} else {
  Write-Host "$notArr not-array, $noPhrase no-phrases." -ForegroundColor Red
}

# Show sample to eyeball quality
Write-Host "`nSample - Shabbat 2:1:" -ForegroundColor Cyan
foreach ($seg in $check.Shabbat."2"."1") {
  Write-Host "  SEG:" -ForegroundColor Yellow
  foreach ($ph in $seg.phrases) {
    $preview = if ($ph.en.Length -gt 90) { $ph.en.Substring(0,90) } else { $ph.en }
    Write-Host "    $preview"
  }
}
