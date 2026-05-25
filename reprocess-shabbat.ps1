# reprocess-shabbat.ps1
# Re-segments all single-phrase fallback mishnayot in tractate Shabbat.
# Reads mishna-data.json, updates only Shabbat, writes back.
#
# Usage:
#   $env:ANTHROPIC_API_KEY = "sk-ant-..."
#   .\reprocess-shabbat.ps1

param(
  [string]$ApiKey = $env:ANTHROPIC_API_KEY
)

if (-not $ApiKey) {
  $ApiKey = Read-Host "Enter your Anthropic API key"
}

$OutputFile = Join-Path $PSScriptRoot 'mishna-data.json'
$ErrorActionPreference = 'Continue'

# ── Helpers ───────────────────────────────────────────────────────────────────

function Strip-Html($s) {
  if (-not $s -or $s -isnot [string]) { return '' }
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = [regex]::Replace($s, '\s+', ' ')
  return $s.Trim()
}

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
      $raw = [regex]::Replace($raw, '(?s)```(?:json)?\s*', '')
      $raw = $raw.Replace('```', '').Trim()
      $match = [regex]::Match($raw, '(?s)\[.*\]')
      if ($match.Success) { $raw = $match.Value }
      $parsed = $raw | ConvertFrom-Json
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

# ── Load existing data ────────────────────────────────────────────────────────
Write-Host "Loading mishna-data.json..." -ForegroundColor Cyan
$existingJson = [System.IO.File]::ReadAllText($OutputFile, [System.Text.Encoding]::UTF8)
$data = $existingJson | ConvertFrom-Json

# Build a mutable hashtable for the full dataset
$output = @{}
foreach ($prop in $data.PSObject.Properties) {
  $output[$prop.Name] = $prop.Value
}

# ── Process Shabbat ───────────────────────────────────────────────────────────
Write-Host "Processing Shabbat (24 chapters)..." -ForegroundColor Cyan

$shabbatData = @{}
$improved = 0
$kept = 0
$errors = 0

for ($ch = 1; $ch -le 24; $ch++) {

  # Fetch fresh text from Sefaria
  $sefData = $null
  try {
    $url = "https://www.sefaria.org/api/texts/Mishnah_Shabbat.$ch`?context=0&commentary=0"
    $sefData = Invoke-Sefaria $url
  } catch {
    Write-Warning "  ch.$ch Sefaria FAILED: $_"
    if ($data.Shabbat -and $data.Shabbat."$ch") {
      $shabbatData["$ch"] = $data.Shabbat."$ch"
    } else {
      $shabbatData["$ch"] = @{}
    }
    continue
  }

  $heArr = if ($sefData.he   -is [array]) { $sefData.he   } else { @($sefData.he) }
  $enArr = if ($sefData.text -is [array]) { $sefData.text } else { @($sefData.text) }
  $count = [Math]::Max($heArr.Count, $enArr.Count)

  $chData = @{}

  for ($m = 0; $m -lt $count; $m++) {
    $mNum = $m + 1

    # Check existing data quality
    $existing = $null
    if ($data.Shabbat -and $data.Shabbat."$ch" -and $data.Shabbat."$ch"."$mNum") {
      $existing = $data.Shabbat."$ch"."$mNum"
    }

    $totalPhrases = 0
    if ($existing -is [array]) {
      foreach ($seg in $existing) {
        if ($seg.phrases) { $totalPhrases += $seg.phrases.Count }
      }
    }

    # Keep already-good entries (more than 1 phrase = properly segmented)
    if ($totalPhrases -gt 1) {
      $chData["$mNum"] = $existing
      $kept++
      Write-Host "." -NoNewline
      continue
    }

    # Re-process fallback entries
    $heRaw = if ($m -lt $heArr.Count -and $heArr[$m]) { $heArr[$m] } else { '' }
    $enRaw = if ($m -lt $enArr.Count -and $enArr[$m]) { $enArr[$m] } else { '' }
    if ($heRaw -is [array]) { $heRaw = $heRaw -join ' ' }
    if ($enRaw -is [array]) { $enRaw = $enRaw -join ' ' }

    $he = Strip-Html ([string]$heRaw)
    $en = Extract-EnglishText ([string]$enRaw)

    $segments = Invoke-Claude $he $en
    if (-not $segments) {
      Write-Host "!" -NoNewline
      $chData["$mNum"] = @(@{ phrases = @(@{ he = $he; en = $en }) })
      $errors++
    } else {
      Write-Host "+" -NoNewline
      $chData["$mNum"] = $segments
      $improved++
    }

    Start-Sleep -Milliseconds 1500
  }

  $shabbatData["$ch"] = $chData
  Write-Host " ch.$ch($count)" -NoNewline
  Write-Host ""
}

$output['Shabbat'] = $shabbatData

# ── Write updated output ──────────────────────────────────────────────────────
Write-Host "`nWriting updated mishna-data.json..." -ForegroundColor Cyan
$utf8 = New-Object System.Text.UTF8Encoding($false)
$json = $output | ConvertTo-Json -Depth 12 -Compress
[System.IO.File]::WriteAllText($OutputFile, $json, $utf8)

$sizeMB = [Math]::Round((Get-Item $OutputFile).Length / 1MB, 1)
Write-Host "Done! Kept $kept, improved $improved, $errors still fallback. File: $sizeMB MB" -ForegroundColor Green
Write-Host "Dots=kept  +=newly segmented  !=fallback" -ForegroundColor DarkGray
