param(
  [switch]$Backup
)

$src = "C:\Lazy Hero\OneButtonAssistant"
$dest = "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\OneButtonAssistant"

function Copy-Dir($source, $target) {
  if (-not (Test-Path $source)) {
    Write-Error "Source path not found: $source"
    return $false
  }
  if (-not (Test-Path $target)) {
    New-Item -ItemType Directory -Path $target -Force | Out-Null
  }
  robocopy $source $target /MIR /COPY:DAT /R:2 /W:1 | Out-Null
  return $true
}

if ($Backup) {
  $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
  $bak = "$dest-backup-$stamp"
  Write-Output "Creating backup of installed AddOn to: $bak"
  Copy-Item -Path $dest -Destination $bak -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output "Syncing $src -> $dest"
$ok = Copy-Dir -source $src -target $dest
if ($ok) { Write-Output "Sync completed." } else { Write-Error "Sync failed." }
