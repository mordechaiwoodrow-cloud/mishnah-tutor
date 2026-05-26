# align-translations.ps1
# Uses Claude Haiku to align Hebrew Mishnah text with the Koren Steinsaltz
# English translation, extracting only the actual translation (no commentary)
# and splitting it into segments/phrases that match the Hebrew structure.
#
# Usage:
#   $env:ANTHROPIC_API_KEY = 'sk-ant-...'
#   .\align-translations.ps1                  # process everything (resumable)
#   .\align-translations.ps1 -Tractate Avot   # process one tractate only

param(
  [string]$ApiKey   = $env:ANTHROPIC_API_KEY,
  [string]$Tractate = '',
  [string[]]$Sedarim = @(),   # e.g. -Sedarim Zeraim,Moed
  [string]$DataFile = (Join-Path $PSScriptRoot 'mishna-data.json'),
  [string]$Model    = 'claude-haiku-4-5-20251001'
)

if (-not $ApiKey) { $ApiKey = Read-Host 'Enter your Anthropic API key' }
$ErrorActionPreference = 'Continue'

# ── Helpers ──────────────────────────────────────────────────────────────────
function Strip-Html([string]$s) {
  if (-not $s) { return '' }
  $s = [regex]::Replace($s, '<[^>]+>', '')
  $s = [regex]::Replace($s, '\s+', ' ')
  return $s.Trim()
}

function Invoke-Sefaria([string]$url) {
  for ($i = 1; $i -le 3; $i++) {
    try   { return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 25 }
    catch { if ($i -lt 3) { Start-Sleep -Milliseconds (800 * $i) } else { throw } }
  }
}

function Invoke-Claude([string]$heText, [string]$enText) {
  # If input contains <b> tags, the bold parts are the Mishnah translation
  # and everything else is Steinsaltz commentary to discard. Otherwise the
  # input is already a clean translation (no commentary mixed in).
  $hasBold = $enText -match '<b>'
  $enRule = if ($hasBold) {
@'
- For `en`: include ONLY the text that appeared INSIDE <b>...</b> tags, joined naturally, that corresponds to that Hebrew phrase. STRIP every HTML tag (<b>, </b>, <i>, </i>, <br>, etc.) from the output. NEVER include text that was outside the <b> tags. NO commentary, NO Steinsaltz explanations.
'@
  } else {
@'
- For `en`: extract the portion of the English that corresponds to that Hebrew phrase. The input is already clean translation; just split it appropriately. Strip any HTML tags.
'@
  }

  $prompt = @"
Align this Hebrew Mishnah with its English translation.

Rules:
- A SEGMENT is a logical grouping: an opinion (e.g. ``the words of Rabbi X``, ``Beit Shammai say``), a story (starts with ``מעשה``), a generalization (starts with ``ולא זו בלבד``), or an unmarked block of related sentences. Use 1 segment if everything is one continuous thought.
- A PHRASE within a segment is one Hebrew sentence ending in a period. Merge sentences of 1-3 words into the nearest neighbor.
- Every Hebrew word from the input MUST appear in some phrase, in the original order, with original nikud preserved.
$enRule
- If a Hebrew phrase has NO matching English, set ``en`` to "". Do NOT invent translation.
- Output MUST be valid JSON. No markdown fences, no prose before or after.

Hebrew:
$heText

English:
$enText

Output (JSON array only):
[{"phrases":[{"he":"...","en":"..."}, ...]}, ...]
"@

  $body = @{
    model      = $Model
    max_tokens = 4096
    messages   = @(@{ role = 'user'; content = $prompt })
  } | ConvertTo-Json -Depth 5 -Compress
  # Send body as UTF-8 bytes (PS 5.1 otherwise sends as Windows-1252, mangling Hebrew)
  $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($body)

  $headers = @{
    'x-api-key'         = $ApiKey
    'anthropic-version' = '2023-06-01'
  }

  for ($attempt = 1; $attempt -le 4; $attempt++) {
    try {
      $rawResp = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' `
        -Method Post -Headers $headers -Body $bodyBytes `
        -ContentType 'application/json; charset=utf-8' -TimeoutSec 90 -UseBasicParsing
      # Decode response bytes as UTF-8 (PS 5.1 mis-detects encoding for raw bytes)
      $respText = [System.Text.Encoding]::UTF8.GetString($rawResp.RawContentStream.ToArray())
      $resp = $respText | ConvertFrom-Json
      $raw = $resp.content[0].text
      # Strip code fences
      $raw = [regex]::Replace($raw, '(?s)```(?:json)?\s*', '')
      $raw = $raw.Replace('```', '').Trim()
      # Find the outermost JSON array (greedy, allow nested brackets)
      $start = $raw.IndexOf('[')
      $end   = $raw.LastIndexOf(']')
      if ($start -ge 0 -and $end -gt $start) { $raw = $raw.Substring($start, $end - $start + 1) }
      try {
        $parsed = $raw | ConvertFrom-Json
      } catch {
        # Sometimes Claude leaves a trailing comma — try to fix
        $fixed = [regex]::Replace($raw, ',(\s*[\]}])', '$1')
        $parsed = $fixed | ConvertFrom-Json
      }
      if ($parsed -is [array] -and $parsed.Count -gt 0 -and $parsed[0].phrases) {
        return $parsed
      }
      # Sometimes Claude returns a single object instead of array — wrap it
      if ($parsed.phrases) { return @($parsed) }
      return $null
    } catch {
      $msg = $_.ToString()
      if ($msg -match '429|overloaded|rate.limit' -and $attempt -lt 4) {
        Write-Host ' [rate-limit, 30s wait]' -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 30
      } elseif ($attempt -lt 4) {
        Start-Sleep -Milliseconds (1500 * $attempt)
      } else { return $null }
    }
  }
  return $null
}

# ── Custom JSON serialiser (preserves array shape) ───────────────────────────
function J-Str([string]$s) {
  if ($null -eq $s) { return '""' }
  return $s | ConvertTo-Json
}
function J-Segs($segs) {
  $arr = if ($segs -is [array]) { $segs } else { @($segs) }
  $sp  = foreach ($seg in $arr) {
    $phs = $seg.phrases
    if ($phs -isnot [array]) { $phs = @($phs) }
    $pp  = foreach ($ph in $phs) {
      '{"he":' + (J-Str $ph.he) + ',"en":' + (J-Str $ph.en) + '}'
    }
    '{"phrases":[' + ($pp -join ',') + ']}'
  }
  return '[' + ($sp -join ',') + ']'
}

# ── Save partial / final mishna-data.json (resumable) ────────────────────────
function Save-Progress($outs, $curTract, $curTractData, $prog, $progFile, $met, $df) {
  $parts = [System.Collections.ArrayList]::new()
  $parts.Add('"_meta":' + ($met | ConvertTo-Json -Depth 5 -Compress)) | Out-Null

  foreach ($seder in $met.sedarim) {
    foreach ($t in $met.tractates.$seder) {
      $slug = $t.sefaria
      $td = if ($slug -eq $curTract) { $curTractData } else { $outs[$slug] }
      if (-not $td) { $parts.Add('"' + $slug + '":{}') | Out-Null; continue }
      $chParts = [System.Collections.ArrayList]::new()
      $chNames = if ($td -is [System.Collections.IDictionary]) {
        @($td.Keys | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ })
      } else {
        @($td.PSObject.Properties.Name | Where-Object { $_ -match '^\d+$' } | Sort-Object { [int]$_ })
      }
      foreach ($chNum in $chNames) {
        $chData = if ($td -is [System.Collections.IDictionary]) { $td[$chNum] } else { $td.$chNum }
        $mParts = [System.Collections.ArrayList]::new()
        $mNames = if ($chData -is [System.Collections.IDictionary]) {
          @($chData.Keys | Sort-Object { [int]$_ })
        } else {
          @($chData.PSObject.Properties.Name | Sort-Object { [int]$_ })
        }
        foreach ($mNum in $mNames) {
          $mData = if ($chData -is [System.Collections.IDictionary]) { $chData[$mNum] } else { $chData.$mNum }
          $mParts.Add('"' + $mNum + '":' + (J-Segs $mData)) | Out-Null
        }
        $chParts.Add('"' + $chNum + '":{' + ($mParts -join ',') + '}') | Out-Null
      }
      $parts.Add('"' + $slug + '":{' + ($chParts -join ',') + '}') | Out-Null
    }
  }
  $final = '{' + ($parts -join ',') + '}'
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($df, $final, $utf8)
  $prog | ConvertTo-Json -Compress | Out-File -FilePath $progFile -Encoding utf8 -NoNewline
}

# ── Load data ────────────────────────────────────────────────────────────────
Write-Host 'Loading mishna-data.json...' -ForegroundColor Cyan
$existingJson = [System.IO.File]::ReadAllText($DataFile, [System.Text.Encoding]::UTF8)
$data = $existingJson | ConvertFrom-Json
$meta = $data._meta

# Determine which tractates to process
$tractatesToDo = @()
foreach ($seder in $meta.sedarim) {
  if ($Sedarim.Count -gt 0 -and $Sedarim -notcontains $seder) { continue }
  foreach ($t in $meta.tractates.$seder) {
    if (-not $Tractate -or $t.sefaria -eq $Tractate -or $t.display -eq $Tractate) {
      $tractatesToDo += $t.sefaria
    }
  }
}
Write-Host "Will process $($tractatesToDo.Count) tractate(s)." -ForegroundColor Cyan

# Track per-mishna progress to allow resume — write a sidecar marker file
$progressFile = Join-Path $PSScriptRoot 'align-progress.json'
$progress = @{}
if (Test-Path $progressFile) {
  $pj = [System.IO.File]::ReadAllText($progressFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
  foreach ($p in $pj.PSObject.Properties) { $progress[$p.Name] = $true }
  Write-Host "Resuming - $($progress.Count) mishnayot already aligned." -ForegroundColor Yellow
}

# Build the data we'll write back as a mutable hashtable of tractate-strings
$tractOutputs = @{}
foreach ($prop in $data.PSObject.Properties) {
  if ($prop.Name -eq '_meta') { continue }
  $tractOutputs[$prop.Name] = $prop.Value
}

$tn = 0; $total = 0; $ok = 0; $fail = 0
foreach ($tractSlug in $tractatesToDo) {
  $tn++
  $maxCh = 1
  # Find chapter count from existing data
  $existing = $data.$tractSlug
  if ($existing) {
    $maxCh = ($existing.PSObject.Properties.Name | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Measure-Object -Max).Maximum
  }
  Write-Host "`n[$tn/$($tractatesToDo.Count)] $tractSlug ($maxCh chapters)" -ForegroundColor Cyan

  $tractData = [ordered]@{}
  # preserve existing chapters
  if ($existing) {
    foreach ($cp in $existing.PSObject.Properties) { $tractData[$cp.Name] = $cp.Value }
  }

  for ($ch = 1; $ch -le $maxCh; $ch++) {
    Write-Host "  ch.$ch " -NoNewline -ForegroundColor Yellow

    # Fetch HTML-preserving fresh data so Claude sees bold structure
    $sefData = $null
    try {
      $url = "https://www.sefaria.org/api/texts/Mishnah_$tractSlug.$ch`?context=0&commentary=0&ven=William_Davidson_Edition_-_English&vlang=english"
      $sefData = Invoke-Sefaria $url
      # Avot/etc fallback
      $hasEn = $false
      foreach ($t in $sefData.text) {
        $s = if ($t -is [array]) { $t -join ' ' } else { [string]$t }
        if ($s.Trim().Length -gt 10) { $hasEn = $true; break }
      }
      if (-not $hasEn) {
        $alt = Invoke-Sefaria "https://www.sefaria.org/api/texts/Mishnah_$tractSlug.$ch`?context=0&commentary=0&ven=Mishnah_Yomit_by_Dr._Joshua_Kulp&vlang=english"
        if ($alt.text) { $sefData.text = $alt.text }
      }
    } catch {
      Write-Host "FETCH-FAIL" -ForegroundColor Red
      continue
    }

    $heArr = if ($sefData.he   -is [array]) { $sefData.he   } else { @($sefData.he) }
    $enArr = if ($sefData.text -is [array]) { $sefData.text } else { @($sefData.text) }
    $count = [Math]::Max($heArr.Count, $enArr.Count)

    $chOrdered = [ordered]@{}
    # preserve previously aligned mishnayot in this chapter
    if ($existing -and $existing.$ch) {
      foreach ($mp in $existing.$ch.PSObject.Properties) {
        $chOrdered[$mp.Name] = $mp.Value
      }
    }

    for ($m = 0; $m -lt $count; $m++) {
      $mNum = $m + 1
      $key  = "$tractSlug.$ch.$mNum"
      $total++

      if ($progress[$key]) {
        Write-Host '.' -NoNewline -ForegroundColor DarkGray
        continue
      }

      $heRaw = if ($m -lt $heArr.Count) { $heArr[$m] } else { '' }
      $enRaw = if ($m -lt $enArr.Count) { $enArr[$m] } else { '' }
      if ($heRaw -is [array]) { $heRaw = $heRaw -join ' ' }
      if ($enRaw -is [array]) { $enRaw = $enRaw -join ' ' }

      $he = Strip-Html ([string]$heRaw)
      # Pass raw HTML English to Claude so it can see <b>...</b> markers and
      # extract only the actual Mishnah translation (inside bold) — drop everything else.
      # Only collapse whitespace; keep all tags.
      $enRawStr = [string]$enRaw
      $en = [regex]::Replace($enRawStr, '\s+', ' ').Trim()

      if (-not $he) {
        Write-Host '_' -NoNewline -ForegroundColor DarkGray
        $progress[$key] = $true
        continue
      }

      $segs = Invoke-Claude $he $en
      if ($segs) {
        $chOrdered["$mNum"] = $segs
        $ok++
        $progress[$key] = $true
        Write-Host '+' -NoNewline -ForegroundColor Green
      } else {
        $fail++
        Write-Host '!' -NoNewline -ForegroundColor Red
      }

      # Light rate-limit guard
      Start-Sleep -Milliseconds 250

      # Periodic save (every 25 mishnayot)
      if (($ok + $fail) % 25 -eq 0 -and ($ok + $fail) -gt 0) {
        $tractData["$ch"] = $chOrdered
        Save-Progress $tractOutputs $tractSlug $tractData $progress $progressFile $meta $DataFile
      }
    }

    $tractData["$ch"] = $chOrdered
    Write-Host ''
  }

  $tractOutputs[$tractSlug] = $tractData
  Save-Progress $tractOutputs $tractSlug $tractData $progress $progressFile $meta $DataFile
  Write-Host "  done ($ok ok / $fail fail so far)" -ForegroundColor Green
}

Write-Host "`nAll done. $total mishnayot considered, $ok aligned, $fail failed." -ForegroundColor Green
