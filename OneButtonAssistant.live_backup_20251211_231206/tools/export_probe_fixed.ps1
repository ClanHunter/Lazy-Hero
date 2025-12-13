# export_probe_fixed.ps1
# Run after you quit WoW so SavedVariables are flushed to disk.

$candidatePaths = @(
  "$env:USERPROFILE\Documents\World of Warcraft\_retail_\WTF\Account",
  "$env:USERPROFILE\Documents\World of Warcraft\_retail_\WTF\Account\SavedVariables",
  "$env:USERPROFILE\Documents\World of Warcraft\WTF\Account",
  "$env:USERPROFILE\Documents\World of Warcraft\WTF\Account\SavedVariables",
  "$env:USERPROFILE\Documents\World of Warcraft\_classic_\WTF\Account",
  "$env:USERPROFILE\Documents\World of Warcraft\_classic_\WTF\Account\SavedVariables"
)

$foundFiles = @()

foreach ($p in $candidatePaths) {
  if (Test-Path $p) {
    try {
      $foundFiles += Get-ChildItem -Path $p -Recurse -Filter 'OneButtonAssistant.lua' -ErrorAction SilentlyContinue -Force
    } catch {}
  }
}

# Fallback: look in Documents and Desktop (faster than full user-profile)
if ($foundFiles.Count -eq 0) {
  Write-Host "No files found in standard SavedVariables paths; falling back to Documents/Desktop search..."
  $fallbackRoots = @(
    "$env:USERPROFILE\Documents",
    "$env:USERPROFILE\Desktop"
  )
  foreach ($r in $fallbackRoots) {
    if (Test-Path $r) {
      try {
        $foundFiles += Get-ChildItem -Path $r -Recurse -Filter 'OneButtonAssistant.lua' -ErrorAction SilentlyContinue -Force
      } catch {}
    }
  }
}

# Last-resort: full userprofile search (can be slow)
if ($foundFiles.Count -eq 0) {
  Write-Host "Still none found. Running a full user-profile search (may be slow) -- press Ctrl+C to cancel."
  try {
    $foundFiles += Get-ChildItem -Path $env:USERPROFILE -Recurse -Filter 'OneButtonAssistant.lua' -ErrorAction SilentlyContinue -Force
  } catch {}
}

if ($foundFiles.Count -eq 0) {
  Write-Host "No 'OneButtonAssistant.lua' found. Make sure you exited WoW after running /oba probe."
  exit 1
}

$destDir = 'C:\Lazy Hero\OneButtonAssistant'
if (-not (Test-Path $destDir)) { New-Item -Path $destDir -ItemType Directory | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach ($f in $foundFiles | Sort-Object LastWriteTime -Descending) {
  $destName = "probe_output_$($ts)_$($f.Directory.Name).lua"
  $destPath = Join-Path $destDir $destName
  Copy-Item -Path $f.FullName -Destination $destPath -Force
  Copy-Item -Path $f.FullName -Destination (Join-Path $destDir 'probe_output.lua') -Force
  Write-Host "Copied:`n  $($f.FullName)`n -> $destPath`n  (also copied -> $destDir\probe_output.lua)"
  Write-Host "LastWriteTime: $($f.LastWriteTime)   Size: $((Get-Item $destPath).Length) bytes`n"
  $content = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
  Write-Host "Contains 'adapterProbe': " + [bool]($content -match 'adapterProbe')
  Write-Host "Contains 'lastRawSuggestion': " + [bool]($content -match 'lastRawSuggestion')
  Write-Host ('-' * 60)
}

Write-Host "Done. Files copied into: $destDir"
