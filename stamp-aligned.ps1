# stamp-aligned.ps1
# Marks pre-aligned tractates in mishna-data.json's _meta.aligned array.
# Run this after align-translations.ps1 completes.
#
# Usage:
#   .\stamp-aligned.ps1 -Tractates Berakhot,Shabbat,Eruvin,...
#   .\stamp-aligned.ps1 -FromProgress      # auto-detect from align-progress.json

param(
  [string[]]$Tractates = @(),
  [switch]$FromProgress,
  [string]$DataFile     = (Join-Path $PSScriptRoot 'mishna-data.json'),
  [string]$ProgressFile = (Join-Path $PSScriptRoot 'align-progress.json')
)

$bytes = [System.IO.File]::ReadAllBytes($DataFile)
$json  = [System.Text.Encoding]::UTF8.GetString($bytes)
$data  = $json | ConvertFrom-Json

if ($FromProgress -and (Test-Path $ProgressFile)) {
  $progBytes = [System.IO.File]::ReadAllBytes($ProgressFile)
  $progJson  = [System.Text.Encoding]::UTF8.GetString($progBytes)
  $prog      = $progJson | ConvertFrom-Json
  # Tally aligned mishnayot per tractate
  $perTract = @{}
  foreach ($p in $prog.PSObject.Properties) {
    $tract = ($p.Name -split '\.')[0]
    if (-not $perTract.ContainsKey($tract)) { $perTract[$tract] = 0 }
    $perTract[$tract]++
  }
  # Tractate is "aligned" if progress count == total mishnayot in that tractate
  $detected = @()
  foreach ($tract in $perTract.Keys) {
    $tractData = $data.$tract
    if (-not $tractData) { continue }
    $total = 0
    foreach ($chProp in $tractData.PSObject.Properties) {
      $total += $chProp.Value.PSObject.Properties.Count
    }
    if ($perTract[$tract] -ge $total) {
      $detected += $tract
    } else {
      Write-Host "  partial: $tract ($($perTract[$tract])/$total) — not marking" -ForegroundColor Yellow
    }
  }
  $Tractates = $detected
}

if (-not $Tractates -or $Tractates.Count -eq 0) {
  Write-Host 'Nothing to mark. Pass -Tractates or -FromProgress.' -ForegroundColor Red
  exit
}

Write-Host "Marking aligned tractates: $($Tractates -join ', ')" -ForegroundColor Cyan

# Merge with any existing _meta.aligned
$existing = @()
if ($data._meta -and $data._meta.aligned) { $existing = @($data._meta.aligned) }
$merged = @($existing + $Tractates | Select-Object -Unique)

# Build the final JSON by string replacement on the _meta block (preserves rest of file)
$metaProps = $data._meta.PSObject.Properties
$metaObj = @{}
foreach ($p in $metaProps) { $metaObj[$p.Name] = $p.Value }
$metaObj['aligned'] = $merged

$metaJson = $metaObj | ConvertTo-Json -Depth 6 -Compress

# Find and replace the _meta value in the file
# The original looks like: {"_meta":{...},"Berakhot":...
$pattern = '"_meta":\s*\{[^}]*(\{[^}]*\}[^}]*)*\}'
$newPrefix = '"_meta":' + $metaJson

# Simpler approach: parse, rewrite via custom serializer that we already use elsewhere.
# Just decode whole file, modify _meta, write back. But we need to preserve segment array
# shape — use the same J-Segs approach. Easier: just write the new JSON via .NET serializer
# (which we trust for non-segment parts) but reuse the existing segment shape from disk.

# Actually safest: surgical regex replacement of the _meta portion only.
# The _meta block is the first object after the opening '{'. We find it by counting braces.
$content = $json
if ($content[0] -ne '{') { throw 'Unexpected file shape' }

# Find _meta opening
$mIdx = $content.IndexOf('"_meta":')
if ($mIdx -lt 0) { throw '_meta not found' }
$braceIdx = $content.IndexOf('{', $mIdx)
$depth = 0
$endIdx = -1
for ($i = $braceIdx; $i -lt $content.Length; $i++) {
  $c = $content[$i]
  if ($c -eq '{') { $depth++ }
  elseif ($c -eq '}') { $depth--; if ($depth -eq 0) { $endIdx = $i; break } }
}
if ($endIdx -lt 0) { throw 'Could not find end of _meta object' }

$newContent = $content.Substring(0, $mIdx) + '"_meta":' + $metaJson + $content.Substring($endIdx + 1)

$utf8 = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($DataFile, $newContent, $utf8)

Write-Host "Done. _meta.aligned now contains $($merged.Count) tractate(s)." -ForegroundColor Green
