# rebuild-all.ps1
# Rebuilds mishna-data.json from scratch using Sefaria (free, no API key).
# Applies sentence-based phrase splitting to every tractate.
# Uses a custom JSON builder to guarantee segments are always JSON arrays.

param([string]$OutputFile = (Join-Path $PSScriptRoot 'mishna-data.json'))
$ErrorActionPreference = 'Continue'

$TRACTATES = @(
  @{s='Berakhot';      d='Berakhot';       seder='Zeraim';   ch=9},
  @{s='Peah';          d="Pe'ah";          seder='Zeraim';   ch=8},
  @{s='Demai';         d='Demai';          seder='Zeraim';   ch=7},
  @{s='Kilayim';       d="Kil'ayim";       seder='Zeraim';   ch=9},
  @{s='Sheviit';       d="Shevi'it";       seder='Zeraim';   ch=10},
  @{s='Terumot';       d='Terumot';        seder='Zeraim';   ch=11},
  @{s='Maasrot';       d="Ma'asrot";       seder='Zeraim';   ch=5},
  @{s='Maaser_Sheni';  d="Ma'aser Sheni";  seder='Zeraim';   ch=5},
  @{s='Challah';       d='Challah';        seder='Zeraim';   ch=4},
  @{s='Orlah';         d="'Orlah";         seder='Zeraim';   ch=3},
  @{s='Bikkurim';      d='Bikkurim';       seder='Zeraim';   ch=4},
  @{s='Shabbat';       d='Shabbat';        seder='Moed';     ch=24},
  @{s='Eruvin';        d='Eruvin';         seder='Moed';     ch=10},
  @{s='Pesachim';      d='Pesachim';       seder='Moed';     ch=10},
  @{s='Shekalim';      d='Shekalim';       seder='Moed';     ch=8},
  @{s='Yoma';          d='Yoma';           seder='Moed';     ch=8},
  @{s='Sukkah';        d='Sukkah';         seder='Moed';     ch=5},
  @{s='Beitzah';       d='Beitzah';        seder='Moed';     ch=5},
  @{s='Rosh_Hashanah'; d='Rosh Hashanah';  seder='Moed';     ch=4},
  @{s='Taanit';        d="Ta'anit";        seder='Moed';     ch=4},
  @{s='Megillah';      d='Megillah';       seder='Moed';     ch=4},
  @{s='Moed_Katan';    d="Mo'ed Katan";    seder='Moed';     ch=3},
  @{s='Chagigah';      d='Chagigah';       seder='Moed';     ch=3},
  @{s='Yevamot';       d='Yevamot';        seder='Nashim';   ch=16},
  @{s='Ketubot';       d='Ketubot';        seder='Nashim';   ch=13},
  @{s='Nedarim';       d='Nedarim';        seder='Nashim';   ch=11},
  @{s='Nazir';         d='Nazir';          seder='Nashim';   ch=9},
  @{s='Sotah';         d='Sotah';          seder='Nashim';   ch=9},
  @{s='Gittin';        d='Gittin';         seder='Nashim';   ch=9},
  @{s='Kiddushin';     d='Kiddushin';      seder='Nashim';   ch=4},
  @{s='Bava_Kamma';    d='Bava Kamma';     seder='Nezikin';  ch=10},
  @{s='Bava_Metzia';   d="Bava Metzi'a";   seder='Nezikin';  ch=10},
  @{s='Bava_Batra';    d='Bava Batra';     seder='Nezikin';  ch=10},
  @{s='Sanhedrin';     d='Sanhedrin';      seder='Nezikin';  ch=11},
  @{s='Makkot';        d='Makkot';         seder='Nezikin';  ch=3},
  @{s='Shevuot';       d="Shevu'ot";       seder='Nezikin';  ch=8},
  @{s='Eduyot';        d='Eduyot';         seder='Nezikin';  ch=8},
  @{s='Avodah_Zarah';  d='Avodah Zarah';   seder='Nezikin';  ch=5},
  @{s='Pirkei_Avot';   d='Avot';           seder='Nezikin';  ch=5},
  @{s='Horayot';       d='Horayot';        seder='Nezikin';  ch=3},
  @{s='Zevachim';      d='Zevachim';       seder='Kodashim'; ch=14},
  @{s='Menachot';      d='Menachot';       seder='Kodashim'; ch=13},
  @{s='Chullin';       d='Chullin';        seder='Kodashim'; ch=12},
  @{s='Bekhorot';      d='Bekhorot';       seder='Kodashim'; ch=9},
  @{s='Arakhin';       d='Arakhin';        seder='Kodashim'; ch=9},
  @{s='Temurah';       d='Temurah';        seder='Kodashim'; ch=7},
  @{s='Keritot';       d='Keritot';        seder='Kodashim'; ch=6},
  @{s='Meilah';        d="Me'ilah";        seder='Kodashim'; ch=6},
  @{s='Tamid';         d='Tamid';          seder='Kodashim'; ch=7},
  @{s='Middot';        d='Middot';         seder='Kodashim'; ch=5},
  @{s='Kinnim';        d='Kinnim';         seder='Kodashim'; ch=3},
  @{s='Kelim';         d='Keilim';         seder='Toharot';  ch=30},
  @{s='Oholot';        d='Oholot';         seder='Toharot';  ch=18},
  @{s='Negaim';        d='Negaim';         seder='Toharot';  ch=14},
  @{s='Parah';         d='Parah';          seder='Toharot';  ch=12},
  @{s='Tohorot';       d='Tohorot';        seder='Toharot';  ch=10},
  @{s='Mikvaot';       d='Mikvaot';        seder='Toharot';  ch=10},
  @{s='Niddah';        d='Niddah';         seder='Toharot';  ch=10},
  @{s='Makhshirin';    d='Makhshirin';     seder='Toharot';  ch=6},
  @{s='Zavim';         d='Zavim';          seder='Toharot';  ch=5},
  @{s='Tevul_Yom';     d='Tevul Yom';      seder='Toharot';  ch=4},
  @{s='Yadayim';       d='Yadayim';        seder='Toharot';  ch=4},
  @{s='Oktzin';        d='Oktzin';         seder='Toharot';  ch=3}
)

# ── Helpers ───────────────────────────────────────────────────────────────────

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
    $j = ($bolds | ForEach-Object { $_.Groups[1].Value }) -join ' '
    $j = [regex]::Replace($j, '<[^>]+>', '')
    $j = [regex]::Replace($j, '\s+', ' ')
    return $j.Trim()
  }
  return Strip-Html $s
}

function Invoke-Sefaria([string]$url) {
  for ($i = 1; $i -le 3; $i++) {
    try   { return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 25 }
    catch { if ($i -lt 3) { Start-Sleep -Milliseconds (800 * $i) } else { throw } }
  }
}

# ── Hebrew-driven phrase segmentation ─────────────────────────────────────────

# Split Hebrew text on sentence-ending periods. Merge sentences of <=3 words
# into the nearest neighbor. The final ':' (sof-pasuk) is treated as text end.
function Get-HebrewSentences([string]$text) {
  $text = $text.Trim().TrimEnd(':',' ').Trim()
  $raw  = @([regex]::Split($text, '(?<=\.)\s+') | Where-Object { $_.Trim() -ne '' })
  if ($raw.Count -le 1) { return @($text) }
  $buf = [System.Collections.ArrayList]::new()
  foreach ($s in $raw) {
    $t  = $s.Trim()
    $wc = @($t -split '\s+').Count
    if ($wc -le 3 -and $buf.Count -gt 0) { $buf[$buf.Count-1] = $buf[$buf.Count-1] + ' ' + $t }
    else { $buf.Add($t) | Out-Null }
  }
  # If the very first sentence is still <=3 words, glue it onto the next one
  if ($buf.Count -ge 2 -and (@($buf[0] -split '\s+').Count -le 3)) {
    $buf[1] = $buf[0] + ' ' + $buf[1]; $buf.RemoveAt(0)
  }
  return @($buf)
}

# Phrases are driven by Hebrew sentence boundaries; English is sliced
# proportionally and snapped to word boundaries.
function Get-Phrases([string]$heText, [string]$enText) {
  $heText = $heText.Trim(); $enText = $enText.Trim()
  $heSents = Get-HebrewSentences $heText
  if ($heSents.Count -le 1) { return @(@{ he = $heText; en = $enText }) }

  $phrases = [System.Collections.ArrayList]::new()
  $heTotal = [Math]::Max($heText.Length, 1)
  $enTotal = $enText.Length
  $heCur = 0; $enCur = 0

  for ($i = 0; $i -lt $heSents.Count; $i++) {
    $heS = $heSents[$i]
    # advance heCur past this sentence in the original text
    $idx = $heText.IndexOf($heS, $heCur)
    if ($idx -ge 0) { $heCur = $idx + $heS.Length } else { $heCur += $heS.Length }

    if ($i -lt $heSents.Count - 1) {
      $frac    = [Math]::Min($heCur, $heTotal) / $heTotal
      $target  = [int]($frac * $enTotal)
      # Snap to nearest English period within +/- 25% of total length
      $window  = [int]($enTotal * 0.25)
      $bestDot = -1; $bestDist = $window + 1
      for ($k = [Math]::Max(0, $target - $window); $k -lt [Math]::Min($enTotal, $target + $window); $k++) {
        if ($enText[$k] -eq '.') {
          $d = [Math]::Abs($k - $target)
          if ($d -lt $bestDist -and ($k + 1) -gt $enCur) { $bestDist = $d; $bestDot = $k }
        }
      }
      if ($bestDot -ge 0) {
        $enSplit = $bestDot + 1
      } else {
        $enSplit = $target
        while ($enSplit -lt $enTotal-1 -and $enText[$enSplit] -ne ' ') { $enSplit++ }
      }
      $enS = $enText.Substring($enCur, [Math]::Max(0, $enSplit - $enCur)).Trim()
      $enCur = [Math]::Min($enSplit + 1, $enTotal)
    } else {
      $enS = if ($enCur -lt $enTotal) { $enText.Substring($enCur).Trim() } else { '' }
    }
    $phrases.Add(@{ he = $heS; en = $enS }) | Out-Null
  }
  return @($phrases)
}

# ── Hebrew-marker-based segment splitting ────────────────────────────────────
# Builds a regex pattern that tolerates Hebrew nikud (vowel marks) between letters.
function NP([string]$word) {
  $N = '[֑-ׇ׳״]*'
  $parts = foreach ($c in $word.ToCharArray()) {
    if ($c -eq ' ') { '\s+' } else { [regex]::Escape("$c") + $N }
  }
  return ($parts -join '')
}

$script:wawOpt = '(?:' + (NP 'ו') + ')?'

# Fixed segment-start markers (split BEFORE these phrases)
$script:fixedMarkers = @(
  'וחכמים אומרים','חכמים אומרים',
  'מעשה',
  'ולא זו בלבד','לא זו בלבד',
  'בית שמאי אומרים','בית הלל אומרים','ובית שמאי אומרים','ובית הלל אומרים',
  'כלל אמרו','כלל גדול אמרו',
  'אמרו לו','אמרו לה','אמרו להם','אמרו להן',
  'אמר לו','אמר לה','אמר להם','אמר להן'
)
$script:fixedPats = @($script:fixedMarkers | ForEach-Object { NP $_ })
$script:rabbiSays = $script:wawOpt + (NP 'רבי') + '\s+\S+\s+' + (NP 'אומר')
$script:rabbiSaid = $script:wawOpt + (NP 'אמר') + '\s+' + (NP 'רבי') + '\s+\S+'
$script:allPats   = @($script:fixedPats) + @($script:rabbiSays, $script:rabbiSaid)
$script:segMarkerRegex = '(?<=^|[\s.,:;])(?=' + ($script:allPats -join '|') + ')'

# Dialogue verbs that should merge into a preceding מעשה (story) segment
$script:dlgPats = @('אמרו לו','אמרו לה','אמרו להם','אמרו להן','אמר לו','אמר לה','אמר להם','אמר להן') |
                  ForEach-Object { NP $_ }
$script:dialogRegex = '^\s*(' + ($script:dlgPats -join '|') + ')'
$script:storyRegex  = '^\s*' + (NP 'מעשה')

function Get-HebrewSegments([string]$he) {
  $raw = @([regex]::Split($he, $script:segMarkerRegex) | Where-Object { $_.Trim() -ne '' })
  if ($raw.Count -le 1) { return $raw }
  $result = [System.Collections.ArrayList]::new()
  $inStory = $false
  foreach ($seg in $raw) {
    if ($seg -match $script:storyRegex) {
      $result.Add($seg) | Out-Null; $inStory = $true
    } elseif ($inStory -and ($seg -match $script:dialogRegex)) {
      $result[$result.Count-1] = $result[$result.Count-1].TrimEnd() + ' ' + $seg.TrimStart()
    } else {
      $result.Add($seg) | Out-Null; $inStory = $false
    }
  }
  return @($result)
}

function Get-Segments([string]$he, [string]$en) {
  $heSegs = @(Get-HebrewSegments $he)
  if ($heSegs.Count -le 1) {
    return @(@{ phrases = Get-Phrases $he $en })
  }

  # Slice English proportionally to Hebrew segment lengths, snap to period
  $segs    = [System.Collections.ArrayList]::new()
  $heTotal = [Math]::Max($he.Length, 1)
  $enTotal = $en.Length
  $heCum   = 0
  $enCur   = 0

  for ($i = 0; $i -lt $heSegs.Count; $i++) {
    $heSeg = $heSegs[$i].Trim()
    $heCum += $heSegs[$i].Length

    if ($i -lt $heSegs.Count - 1) {
      $frac    = $heCum / $heTotal
      $target  = [int]($frac * $enTotal)
      $window  = [int]($enTotal * 0.25)
      $bestDot = -1; $bestDist = $window + 1
      $kStart  = [Math]::Max($enCur, $target - $window)
      $kEnd    = [Math]::Min($enTotal, $target + $window)
      for ($k = $kStart; $k -lt $kEnd; $k++) {
        if ($en[$k] -eq '.') {
          $d = [Math]::Abs($k - $target)
          if ($d -lt $bestDist) { $bestDist = $d; $bestDot = $k }
        }
      }
      if ($bestDot -ge 0) { $enSplit = $bestDot + 1 }
      else {
        $enSplit = $target
        while ($enSplit -lt $enTotal-1 -and $en[$enSplit] -ne ' ') { $enSplit++ }
      }
      $enSeg = $en.Substring($enCur, [Math]::Max(0, $enSplit - $enCur)).Trim()
      $enCur = [Math]::Min($enSplit + 1, $enTotal)
    } else {
      $enSeg = if ($enCur -lt $enTotal) { $en.Substring($enCur).Trim() } else { '' }
    }

    $segs.Add(@{ phrases = Get-Phrases $heSeg $enSeg }) | Out-Null
  }
  return @($segs)
}

# ── Custom JSON serialiser (guarantees [...] for any segment count) ────────────

function ConvertTo-JsonStr([string]$s) {
  if ($null -eq $s) { return '""' }
  return $s | ConvertTo-Json
}

function ConvertTo-SegsJson($segs) {
  $arr = if ($segs -is [array]) { $segs } else { @($segs) }
  $sp  = foreach ($seg in $arr) {
    $phs = $seg.phrases
    if ($phs -isnot [array]) { $phs = @($phs) }
    $pp  = foreach ($ph in $phs) {
      '{"he":' + (ConvertTo-JsonStr $ph.he) + ',"en":' + (ConvertTo-JsonStr $ph.en) + '}'
    }
    '{"phrases":[' + ($pp -join ',') + ']}'
  }
  return '[' + ($sp -join ',') + ']'
}

# ── Main ──────────────────────────────────────────────────────────────────────

$sedarim        = @('Zeraim','Moed','Nashim','Nezikin','Kodashim','Toharot')
$tractsBySedarim = @{}
foreach ($s in $sedarim) { $tractsBySedarim[$s] = @() }
foreach ($t in $TRACTATES) {
  $tractsBySedarim[$t.seder] += @{ sefaria = $t.s; display = $t.d }
}
$meta = @{ sedarim = $sedarim; tractates = $tractsBySedarim }

$tractIdx = 0
$totalM   = 0
# Accumulate all JSON pieces as strings (avoids PS5.1 single-array serialisation bug)
$tractJsonParts = [System.Collections.ArrayList]::new()

foreach ($tract in $TRACTATES) {
  $tractIdx++
  Write-Host "[$tractIdx/63] $($tract.d)" -ForegroundColor Cyan -NoNewline

  $tractData = [System.Collections.ArrayList]::new()  # chapter json strings

  for ($ch = 1; $ch -le $tract.ch; $ch++) {
    $sefData = $null
    try {
      $url     = "https://www.sefaria.org/api/texts/Mishnah_$($tract.s).$ch`?context=0&commentary=0"
      $sefData = Invoke-Sefaria $url
    } catch {
      Write-Host " [ch$ch ERR]" -NoNewline -ForegroundColor Red
      $tractData.Add("`"$ch`":{}") | Out-Null
      continue
    }

    $heArr = if ($sefData.he   -is [array]) { $sefData.he   } else { @($sefData.he) }
    $enArr = if ($sefData.text -is [array]) { $sefData.text } else { @($sefData.text) }
    $count = [Math]::Max($heArr.Count, $enArr.Count)

    $mJsonParts = [System.Collections.ArrayList]::new()
    for ($m = 0; $m -lt $count; $m++) {
      $mNum  = $m + 1
      $heRaw = if ($m -lt $heArr.Count -and $heArr[$m]) { $heArr[$m] } else { '' }
      $enRaw = if ($m -lt $enArr.Count -and $enArr[$m]) { $enArr[$m] } else { '' }
      if ($heRaw -is [array]) { $heRaw = $heRaw -join ' ' }
      if ($enRaw -is [array]) { $enRaw = $enRaw -join ' ' }

      $he   = Strip-Html ([string]$heRaw)
      $en   = Extract-EnglishText ([string]$enRaw)
      $segs = Get-Segments $he $en
      $mJsonParts.Add("`"$mNum`":" + (ConvertTo-SegsJson $segs)) | Out-Null
      $totalM++
    }

    $tractData.Add("`"$ch`":{" + ($mJsonParts -join ',') + '}') | Out-Null
    Write-Host '.' -NoNewline
  }

  $tractJsonParts.Add("`"$($tract.s)`":{" + ($tractData -join ',') + '}') | Out-Null
  Write-Host " done" -ForegroundColor DarkGray
}

# Build final JSON with meta
$metaJson  = $meta | ConvertTo-Json -Depth 5 -Compress
$allParts  = @("`"_meta`":$metaJson") + @($tractJsonParts)
$finalJson = '{' + ($allParts -join ',') + '}'

Write-Host "`nWriting $OutputFile ($([Math]::Round($finalJson.Length/1MB,1)) MB estimated)..." -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputFile, $finalJson, $utf8)
$sizeMB = [Math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
Write-Host "Done! $totalM mishnayot. File: $sizeMB MB" -ForegroundColor Green

# Validate
Write-Host "Validating..." -ForegroundColor Cyan
try {
  $check = [System.IO.File]::ReadAllText($OutputFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  $notArr = 0
  foreach ($tP in $check.PSObject.Properties) {
    if ($tP.Name -eq '_meta') { continue }
    foreach ($chP in $tP.Value.PSObject.Properties) {
      foreach ($mP in $chP.Value.PSObject.Properties) {
        if ($mP.Value -isnot [array]) { $notArr++ }
      }
    }
  }
  if ($notArr -eq 0) { Write-Host "JSON valid. All mishnayot are arrays." -ForegroundColor Green }
  else               { Write-Host "$notArr mishnayot not arrays." -ForegroundColor Red }
} catch {
  Write-Host "JSON invalid: $_" -ForegroundColor Red
}
