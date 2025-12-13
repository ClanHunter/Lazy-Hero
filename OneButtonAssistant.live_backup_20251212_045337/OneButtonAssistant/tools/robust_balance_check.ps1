$root = "C:\Lazy Hero\OneButtonAssistant"
Get-ChildItem -Path $root -Filter '*.lua' -Recurse | ForEach-Object {
  $text = Get-Content -Raw $_.FullName
  $len = $text.Length
  $i = 0
  $line = 1
  $stack = @()
  while ($i -lt $len) {
    $ch = $text[$i]
    if ($ch -eq "`n") { $line++ }

    # handle comments starting with --
    if ($ch -eq '-' -and ($i + 1) -lt $len -and $text[$i+1] -eq '-') {
      # check for long bracket comment --[==[ ... ]==]
      if (($i + 2) -lt $len -and $text[$i+2] -eq '[') {
        $skipIndex = SkipLongBracket ($i + 2)
        if ($skipIndex -gt 0) { $i = $skipIndex; continue }
      }
      # otherwise single-line comment
      $i += 2
      while ($i -lt $len -and $text[$i] -ne "`n") { $i++ }
      continue
    }

    # handle long bracket strings [=*[ ... ]=*]
    if ($ch -eq '[') {
      $j = $i + 1
      $eqs = ''
      while ($j -lt $len -and $text[$j] -eq '=') { $eqs += '='; $j++ }
      if ($j -lt $len -and $text[$j] -eq '[') {
        # found long-bracket start
        $i = $j + 1
        while ($i -lt $len) {
          if ($text[$i] -eq "`n") { $line++ }
          if ($text[$i] -eq ']') {
            $m = $i + 1; $okClose = $true
            foreach ($c in $eqs.ToCharArray()) { if ($m -ge $len -or $text[$m] -ne $c) { $okClose = $false; break } ; $m++ }
            if ($okClose -and $m -lt $len -and $text[$m] -eq ']') { $i = $m + 1; break }
          }
          $i++
        }
        continue
      }
    }

    # skip quoted strings "..." and '...'
    if ($ch -eq '"' -or $ch -eq "'") {
      $quote = $ch
      $i++
      while ($i -lt $len) {
        $c2 = $text[$i]
        if ($c2 -eq "`n") { $line++ }
        if ($c2 -eq '\\') { $i += 2; continue }
        if ($c2 -eq $quote) { $i++; break }
        $i++
      }
      continue
    }

    # parse words (allow letters, underscore and digits after first char)
    if ($ch -match '[A-Za-z_]') {
      $sb = ''
      while ($i -lt $len -and ($text[$i] -match '[A-Za-z0-9_\_]')) { $sb += $text[$i]; $i++ }
      $token = $sb
      switch ($token) {
        'function' { $stack += @{ token='function'; line=$line } }
        'if' { $stack += @{ token='if'; line=$line } }
        'for' { $stack += @{ token='for'; line=$line } }
        'while' { $stack += @{ token='while'; line=$line } }
        'repeat' { $stack += @{ token='repeat'; line=$line } }
        'end' {
          if ($stack.Count -gt 0) { $stack = $stack[0..($stack.Count-2)] } else { Write-Output "EXTRA end in $($_.FullName) at line $line" }
        }
        default { }
      }
      continue
    }

    $i++
  }

  Write-Output "FILE: $($_.FullName)"
  if ($stack.Count -eq 0) {
    Write-Output "  All openers matched."
  } else {
    Write-Output "  Unmatched openers: $($stack.Count)"
    foreach ($item in $stack) { Write-Output "    $($item.token) at line $($item.line)" }
    $first = $stack[0]
    $lines = (Get-Content -Raw $_.FullName).Split("`n")
    $ln = $first.line
    $startLine = [Math]::Max(1, $ln - 3)
    $endLine = [Math]::Min($lines.Length, $ln + 3)
    Write-Output "  Context around first unmatched opener (lines $startLine..$endLine):"
    for ($l = $startLine; $l -le $endLine; $l++) { Write-Output ("  " + $l + ": " + $lines[$l-1]) }
  }
  Write-Output ""
}
