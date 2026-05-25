# generate-mishna-data.ps1
# Fetches all 63 tractates from Sefaria, parses each mishnah with Claude (once),
# and saves mishna-data.json so the website never needs to call Claude again.
#
# Usage:
#   .\generate-mishna-data.ps1 -ApiKey "sk-ant-..."
# Or set env var first:
#   $env:ANTHROPIC_API_KEY = "sk-ant-..."
#   .\generate-mishna-data.ps1

param(
  [string]$ApiKey = $env:ANTHROPIC_API_KEY
)

if (-not $ApiKey) {
  $ApiKey = Read-Host "Enter your Anthropic API key"
}

$ErrorActionPreference = 'Continue'
$ProgressFile = Join-Path $PSScriptRoot 'mishna-data-progress.json'
$OutputFile   = Join-Path $PSScriptRoot 'mishna-data.json'

$TRACTATES = @(
  # Zeraim
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
  # Moed
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
  # Nashim
  @{s='Yevamot';       d='Yevamot';        seder='Nashim';   ch=16},
  @{s='Ketubot';       d='Ketubot';        seder='Nashim';   ch=13},
  @{s='Nedarim';       d='Nedarim';        seder='Nashim';   ch=11},
  @{s='Nazir';         d='Nazir';          seder='Nashim';   ch=9},
  @{s='Sotah';         d='Sotah';          seder='Nashim';   ch=9},
  @{s='Gittin';        d='Gittin';         seder='Nashim';   ch=9},
  @{s='Kiddushin';     d='Kiddushin';      seder='Nashim';   ch=4},
  # Nezikin
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
  # Kodashim
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
  # Toharot
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

function Strip-Html($s) {
  if (-not $s -or $s -isnot [string]) { return '' }
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = [regex]::Replace($s, '\s+', ' ')
  return $s.Trim()
}

# Extract only <b>...</b> content from Sefaria English (the actual Mishnah text).
# Sefaria wraps the Mishnah text in <b> tags; surrounding text is commentary.
# Falls back to full strip-html if no <b> tags are found.
function Extract-EnglishText($s) {
  if (-not $s -or $s -isnot [string]) { return '' }
  $bolds = [regex]::Matches($s, '(?s)<b>(.*?)</b>')
  if ($bolds.Count -gt 0) {
    $parts = @($bolds | ForEach-Object { $_.Groups[1].Value })
    $result = $parts -join ' '
    $result = [regex]::Replace($result, '<[^>]+>', '')
    $result = [regex]::Replace($result, '\s+', ' ')
    return $result.Trim()
  }
  return Strip-Html $s
}

function Invoke-Sefaria($url) {
  $attempts = 0
  while ($attempts -lt 3) {
    $attempts++
    try {
      return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 20
    } catch {
      if ($attempts -lt 3) { Start-Sleep -Milliseconds (500 * $attempts) }
      else { throw }
    }
  }
}

function Invoke-Claude($heText, $enText) {
  $prompt = @"
Split this Mishnah into segments and phrase pairs. Return ONLY a JSON array, no markdown, no explanation.

Hebrew: $heText
English: $enText

Rules:
- A SEGMENT is a group of related clauses forming one complete thought (2-3 segments per Mishnah)
- A PHRASE is one clause within a segment (split at commas, conjunctions, speaker tags like "Rabbi X says:")
- Aim for 2-4 phrases per segment
- Align Hebrew and English phrases semantically
- Keep every word of the Hebrew and English — do not omit or summarize

Output format (JSON array only):
[{"phrases":[{"he":"...","en":"..."},{"he":"...","en":"..."}]},{"phrases":[{"he":"...","en":"..."}]}]
"@

  $body = @{
    model      = 'claude-haiku-4-5-20251001'
    max_tokens = 2000
    messages   = @(@{ role = 'user'; content = $prompt })
  } | ConvertTo-Json -Depth 5 -Compress

  $headers = @{
    'x-api-key'         = $ApiKey
    'anthropic-version' = '2023-06-01'
    'content-type'      = 'application/json'
  }

  $attempts = 0
  while ($attempts -lt 4) {
    $attempts++
    try {
      $resp = Invoke-RestMethod -Uri 'https://api.anthropic.com/v1/messages' `
        -Method Post -Headers $headers -Body $body -TimeoutSec 40
      $raw = $resp.content[0].text
      # Strip markdown code fences if present
      $raw = [regex]::Replace($raw, '(?s)```(?:json)?\s*', '')
      $raw = $raw.Replace('```', '').Trim()
      # Extract JSON array
      $match = [regex]::Match($raw, '(?s)\[.*\]')
      if ($match.Success) { $raw = $match.Value }
      $parsed = $raw | ConvertFrom-Json
      # Validate: must be array with at least 1 segment containing at least 1 phrase
      if ($parsed -is [array] -and $parsed.Count -gt 0 -and $parsed[0].phrases) {
        return $parsed
      }
      return $null
    } catch {
      $msg = $_.ToString()
      if ($msg -match '429|rate.limit' -and $attempts -lt 4) {
        Write-Host " [rate limit, waiting 60s]" -ForegroundColor Yellow -NoNewline
        Start-Sleep -Seconds 60
      } elseif ($attempts -lt 4) {
        Start-Sleep -Milliseconds (1000 * $attempts)
      } else {
        return $null
      }
    }
  }
  return $null
}

# Fallback: single segment/phrase when Claude fails
function Split-Fallback($he, $en) {
  return @(@{ phrases = @(@{ he = $he; en = $en }) })
}

# ── Load progress: first from progress file, then from existing output JSON ───
$progress = @{}

if (Test-Path $ProgressFile) {
  Write-Host "Resuming from progress file..." -ForegroundColor Yellow
  try {
    $loaded = Get-Content $ProgressFile -Raw | ConvertFrom-Json
    $loaded.PSObject.Properties | ForEach-Object { $progress[$_.Name] = $_.Value }
    Write-Host "  Loaded $($progress.Count) entries from progress file" -ForegroundColor Yellow
  } catch {
    Write-Warning "Could not load progress file."
  }
}

# Also seed progress from any existing output file (skip flat 1-phrase entries so they get re-processed)
if (Test-Path $OutputFile) {
  Write-Host "Seeding progress from existing mishna-data.json..." -ForegroundColor Yellow
  try {
    $existingJson = [System.IO.File]::ReadAllText($OutputFile, [System.Text.Encoding]::UTF8)
    $existing = $existingJson | ConvertFrom-Json
    $seededCount = 0
    foreach ($tractProp in $existing.PSObject.Properties) {
      if ($tractProp.Name -eq '_meta') { continue }
      $tractName = $tractProp.Name
      foreach ($chProp in $tractProp.Value.PSObject.Properties) {
        foreach ($mProp in $chProp.Value.PSObject.Properties) {
          $m = $mProp.Value
          # Count total phrases across all segments
          $totalPhrases = 0
          $totalSegments = 0
          if ($m -is [array]) {
            $totalSegments = $m.Count
            foreach ($seg in $m) {
              if ($seg.phrases) { $totalPhrases += $seg.phrases.Count }
            }
          }
          # Only keep entries that are properly segmented (more than 1 phrase total, or more than 1 segment)
          if ($totalPhrases -gt 1 -or $totalSegments -gt 1) {
            $key = "$tractName.$($chProp.Name).$($mProp.Name)"
            if (-not $progress.ContainsKey($key)) {
              $progress[$key] = $m
              $seededCount++
            }
          }
        }
      }
    }
    Write-Host "  Seeded $seededCount properly-segmented entries from existing output" -ForegroundColor Yellow
  } catch {
    Write-Warning "Could not seed from existing output: $_"
  }
}

# ── Build metadata ────────────────────────────────────────────────────────────
$sedarim = @('Zeraim','Moed','Nashim','Nezikin','Kodashim','Toharot')
$tractsBySedarim = @{}
foreach ($s in $sedarim) { $tractsBySedarim[$s] = @() }
foreach ($t in $TRACTATES) {
  $tractsBySedarim[$t.seder] += @{ sefaria = $t.s; display = $t.d }
}

$output = @{ _meta = @{ sedarim = $sedarim; tractates = $tractsBySedarim } }

# ── Main loop ─────────────────────────────────────────────────────────────────
$totalMishna = 0
$totalErrors = 0
$tractIdx    = 0

foreach ($tract in $TRACTATES) {
  $tractIdx++
  Write-Host "`n[$tractIdx/63] $($tract.d)  (Seder $($tract.seder))" -ForegroundColor Cyan

  $tractData = @{}

  for ($ch = 1; $ch -le $tract.ch; $ch++) {

    # Fetch chapter from Sefaria
    $data = $null
    try {
      $url  = "https://www.sefaria.org/api/texts/Mishnah_$($tract.s).$ch`?context=0&commentary=0"
      $data = Invoke-Sefaria $url
    } catch {
      Write-Warning "  ch.$ch Sefaria FAILED: $_"
      $totalErrors++
      $tractData["$ch"] = @{}
      continue
    }

    $heArr = if ($data.he   -is [array]) { $data.he   } else { @($data.he) }
    $enArr = if ($data.text -is [array]) { $data.text } else { @($data.text) }
    $count = [Math]::Max($heArr.Count, $enArr.Count)

    $chData = @{}

    for ($m = 0; $m -lt $count; $m++) {
      $mNum = $m + 1
      $key  = "$($tract.s).$ch.$mNum"

      # Check progress cache
      if ($progress.ContainsKey($key)) {
        $chData["$mNum"] = $progress[$key]
        $totalMishna++
        Write-Host "." -NoNewline
        continue
      }

      $heRaw = if ($m -lt $heArr.Count -and $heArr[$m]) { $heArr[$m] } else { '' }
      $enRaw = if ($m -lt $enArr.Count -and $enArr[$m]) { $enArr[$m] } else { '' }
      if ($heRaw -is [array]) { $heRaw = $heRaw -join ' ' }
      if ($enRaw -is [array]) { $enRaw = $enRaw -join ' ' }

      $he = Strip-Html ([string]$heRaw)
      # Extract only the Mishnah text from English (bold tags), not the surrounding commentary
      $en = Extract-EnglishText ([string]$enRaw)

      # Call Claude
      $segments = Invoke-Claude $he $en
      if (-not $segments) {
        Write-Host "!" -NoNewline
        $segments = Split-Fallback $he $en
        $totalErrors++
      } else {
        Write-Host "+" -NoNewline
      }

      $chData["$mNum"]    = $segments
      $progress[$key]     = $segments
      $totalMishna++

      # Small delay to respect rate limits (~40 req/min safe zone)
      Start-Sleep -Milliseconds 1500
    }

    $tractData["$ch"] = $chData
    Write-Host " ch.$ch($count)" -NoNewline

    # Save progress after each chapter
    $progress | ConvertTo-Json -Depth 10 -Compress | Set-Content $ProgressFile -Encoding utf8
    Start-Sleep -Milliseconds 200
  }

  $output[$tract.s] = $tractData
  Write-Host ""
}

# ── Write final output ────────────────────────────────────────────────────────
Write-Host "`nWriting $OutputFile..." -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding($false)
$json = $output | ConvertTo-Json -Depth 12 -Compress
[System.IO.File]::WriteAllText($OutputFile, $json, $utf8)

$sizeMB = [Math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
Write-Host "Done! $totalMishna mishnayot processed, $totalErrors fell back to single-phrase. File: mishna-data.json ($sizeMB MB)" -ForegroundColor Green
Write-Host "Dots = cached, + = newly segmented, ! = fallback (1 phrase)" -ForegroundColor DarkGray

# Clean up progress file on success
if ($totalErrors -eq 0 -and (Test-Path $ProgressFile)) {
  Remove-Item $ProgressFile -Confirm:$false
  Write-Host "Progress file removed." -ForegroundColor DarkGray
}
