param(
    [Parameter(Mandatory=$true)]
    [int]$Interface
)

$tocPath = Join-Path -Path (Join-Path -Path (Get-Location) -ChildPath "OneButtonAssistant") -ChildPath "OneButtonAssistant.toc"

if (-not (Test-Path $tocPath)) {
    Write-Error "Could not find OneButtonAssistant.toc at $tocPath. Run this from the repository root."
    exit 2
}

$content = Get-Content -Raw -Path $tocPath

# Replace existing Interface line or add it if missing
if ($content -match '(?m)^## Interface:.*$') {
    $new = $content -replace '(?m)^## Interface:.*$', "## Interface: $Interface"
} else {
    # Prepend the Interface line to the file
    $new = "## Interface: $Interface`r`n" + $content
}

Set-Content -Path $tocPath -Value $new -Encoding UTF8
Write-Output "Updated OneButtonAssistant.toc -> Interface: $Interface"
