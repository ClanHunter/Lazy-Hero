<#
flatten_addon.ps1
Safely detect and fix single-level nested addon folders for OneButtonAssistant.

Usage examples:
  # Dry-run (default): shows what would be moved
  .\flatten_addon.ps1

  # Perform the move interactively (prompts for confirmation)
  .\flatten_addon.ps1 -AutoFix

  # Specify custom AddOns path and addon name
  .\flatten_addon.ps1 -AddOnsPath "C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns" -AddonName "OneButtonAssistant" -AutoFix

  # Force move without prompts (overwrites existing files)
  .\flatten_addon.ps1 -AutoFix -Force

#>
param(
    [string]$AddOnsPath = "C:\\Program Files (x86)\\World of Warcraft\\_retail_\\Interface\\AddOns",
    [string]$AddonName = "OneButtonAssistant",
    [switch]$AutoFix,
    [switch]$Force
)

function Write-Ok($s){ Write-Host $s -ForegroundColor Green }
function Write-Warn($s){ Write-Host $s -ForegroundColor Yellow }
function Write-Err($s){ Write-Host $s -ForegroundColor Red }

if (-not (Test-Path $AddOnsPath)) {
    Write-Err "AddOns path not found: $AddOnsPath"
    Write-Err "Please verify the path and rerun with -AddOnsPath pointing to your WoW AddOns folder."
    exit 1
}

$addonRoot = Join-Path $AddOnsPath $AddonName
$nestedPath = Join-Path $addonRoot $AddonName

if (-not (Test-Path $addonRoot)) {
    Write-Err "Addon folder not found: $addonRoot"
    Write-Host "Available folders under AddOns:"; Get-ChildItem -Path $AddOnsPath -Directory | ForEach-Object { Write-Host " - " $_.Name }
    exit 1
}

# Check for nested folder with same name
if (Test-Path $nestedPath) {
    Write-Warn "Detected nested folder: $nestedPath"
} else {
    # Also handle case where all files are under a single subfolder (any name)
    $subdirs = Get-ChildItem -Path $addonRoot -Directory
    if ($subdirs.Count -eq 1) {
        $onlySub = $subdirs[0].FullName
        # Check whether the .toc is in the only subfolder
        $tocInOnlySub = Get-ChildItem -Path $onlySub -Filter "*.toc" -File -Recurse -ErrorAction SilentlyContinue
        if ($tocInOnlySub) {
            Write-Warn "Detected single nested folder: $onlySub (contains a .toc)."
            $nestedPath = $onlySub
        }
    }
}

if (-not (Test-Path $nestedPath)) {
    Write-Ok "No single-level nested folder detected for '$AddonName'. Nothing to do."
    exit 0
}

# Verify nested folder contains a .toc (safety)
$tocFiles = Get-ChildItem -Path $nestedPath -Filter "*.toc" -File -Recurse -ErrorAction SilentlyContinue
if (-not $tocFiles) {
    Write-Err "Nested folder does not contain a .toc file. Aborting to avoid unsafe moves."
    exit 1
}

# List files to move
Write-Host "Files that would be moved from:`n  $nestedPath`ninto:`n  $addonRoot`n"
$items = Get-ChildItem -Path $nestedPath -Force
foreach ($it in $items) {
    Write-Host (($it.PSIsContainer) ? "[DIR] " : "[FILE]") $it.Name
}

# Check for conflicts
$conflicts = @()
foreach ($it in $items) {
    $dest = Join-Path $addonRoot $it.Name
    if (Test-Path $dest) { $conflicts += $it.Name }
}

if ($conflicts.Count -gt 0) {
    Write-Warn "The following items already exist in the target folder and would conflict if moved:"
    foreach ($c in $conflicts) { Write-Host " - $c" }
    if (-not $Force) {
        Write-Warn "Run with -Force to overwrite these existing items, or resolve manually."
    } else {
        Write-Warn "-Force specified: existing items will be overwritten."
    }
}

if (-not $AutoFix) {
    Write-Host "Dry-run complete. To actually move files, re-run with -AutoFix (and optionally -Force)."
    exit 0
}

# Perform the move
try {
    # Backup: copy the current root folder to a timestamped backup (safer)
    $backupParent = Join-Path $AddOnsPath "_backups"
    if (-not (Test-Path $backupParent)) { New-Item -Path $backupParent -ItemType Directory | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupPath = Join-Path $backupParent "$AddonName-backup-$timestamp"
    Write-Host "Creating backup of current addon root at: $backupPath"
    Copy-Item -Path $addonRoot -Destination $backupPath -Recurse -Force

    # Move items
    foreach ($it in $items) {
        $src = $it.FullName
        $dest = Join-Path $addonRoot $it.Name
        if (Test-Path $dest) {
            if ($Force) {
                if ($it.PSIsContainer) { Remove-Item -Path $dest -Recurse -Force }
                else { Remove-Item -Path $dest -Force }
            } else {
                Write-Warn "Skipping existing item: $dest"
                continue
            }
        }
        Write-Host "Moving: $src -> $dest"
        Move-Item -Path $src -Destination $dest -Force
    }

    # Remove now-empty nested folder
    if (Test-Path $nestedPath) {
        $remaining = Get-ChildItem -Path $nestedPath -Force
        if ($remaining.Count -eq 0) {
            Remove-Item -Path $nestedPath -Force
            Write-Ok "Removed empty nested folder: $nestedPath"
        } else {
            Write-Warn "Nested folder not empty after move; remaining items:"; $remaining | ForEach-Object { Write-Host " - " $_.Name }
        }
    }

    Write-Ok "Move complete. It's recommended to start WoW and verify the addon appears in the AddOns list."
    Write-Host "Backup of original root was saved to: $backupPath"
} catch {
    Write-Err "An error occurred during move: $_"
    Write-Err "You can restore from the backup at: $backupPath"
    exit 1
}
