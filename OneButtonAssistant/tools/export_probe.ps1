# Export OneButtonAssistant saved-variables into workspace for sharing
# Usage: run this after quitting WoW so SavedVariables are flushed to disk.

$searchRoot = Join-Path $env:USERPROFILE 'Documents\World of Warcraft'
$matches = @()
try { $matches = Get-ChildItem -Path $searchRoot -Recurse -Filter 'OneButtonAssistant.lua' -ErrorAction SilentlyContinue -Force } catch {}
if(-not $matches -or $matches.Count -eq 0){
    Write-Host "No 'OneButtonAssistant.lua' found under $searchRoot`nMake sure you quit WoW after running /oba probe so SavedVariables are flushed to disk."
    exit 1
}

$destDir = 'C:\Lazy Hero\OneButtonAssistant'
if(-not (Test-Path $destDir)){ New-Item -Path $destDir -ItemType Directory | Out-Null }
$ts = Get-Date -Format 'yyyyMMdd-HHmmss'

foreach($f in $matches){
    $destName = "probe_output_$($ts)_$($f.Directory.Name).lua"
    $destPath = Join-Path $destDir $destName
    Copy-Item -Path $f.FullName -Destination $destPath -Force
    Copy-Item -Path $f.FullName -Destination (Join-Path $destDir 'probe_output.lua') -Force

    Write-Host "Copied:`n  $($f.FullName)`n -> $destPath`n  (also copied -> $destDir\probe_output.lua)"
    Write-Host "LastWriteTime: $($f.LastWriteTime)   Size: $((Get-Item $destPath).Length) bytes`n"

    # Read as raw text and test for keys
    $content = Get-Content -Path $f.FullName -Raw -ErrorAction SilentlyContinue
    $hasAdapterProbe = $content -match 'adapterProbe'
    $hasLastRaw = $content -match 'lastRawSuggestion'

    Write-Host "Contains adapterProbe: $hasAdapterProbe    Contains lastRawSuggestion: $hasLastRaw`n"

    if($hasAdapterProbe){
        # Print a short snippet starting from the adapterProbe key (first 3000 chars)
        $m = [regex]::Match($content, 'adapterProbe\s*=\s*\{', 'Singleline')
        if($m.Success){
            $start = $m.Index
            $len = [math]::Min(3000, $content.Length - $start)
            $snippet = $content.Substring($start, $len)
            Write-Host 'adapterProbe snippet (first 3000 chars):'
            Write-Host $snippet
        } else {
            Write-Host 'adapterProbe found but could not locate start index for snippet.'
        }
    }

    if($hasLastRaw){
        # Try to extract the lastRawSuggestion block (best-effort)
        $m2 = [regex]::Match($content, 'lastRawSuggestion\s*=\s*\{.*?\}\s*,?', 'Singleline')
        if($m2.Success){
            Write-Host 'lastRawSuggestion snippet (matched block):'
            Write-Host $m2.Value
        } else {
            Write-Host 'lastRawSuggestion present but full block not matched (file may be large).'
        }
    }

    Write-Host ('-' * 70)
}

Write-Host 'Done. Files copied into:' $destDir
