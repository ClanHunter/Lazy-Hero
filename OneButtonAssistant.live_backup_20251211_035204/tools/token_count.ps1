$root = "C:\Lazy Hero\OneButtonAssistant"
Get-ChildItem -Path $root -Filter '*.lua' -Recurse | ForEach-Object {
  $t = Get-Content -Raw $_.FullName
  $f = ([regex]::Matches($t,'\bfunction\b')).Count
  $i = ([regex]::Matches($t,'\bif\b')).Count
  $fr = ([regex]::Matches($t,'\bfor\b')).Count
  $w = ([regex]::Matches($t,'\bwhile\b')).Count
  $r = ([regex]::Matches($t,'\brepeat\b')).Count
  $e = ([regex]::Matches($t,'\bend\b')).Count
  Write-Output "FILE: $($_.FullName)"
  Write-Output "  function:$f if:$i for:$fr while:$w repeat:$r end:$e"
  Write-Output ""
}