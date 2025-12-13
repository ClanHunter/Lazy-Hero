# Simple Lua block-balancer checker
# Scans .lua files in the OneButtonAssistant folder and reports mismatched blocks (if/function/do/repeat etc.)
$folder = "C:\Lazy Hero\OneButtonAssistant"
Get-ChildItem -Path $folder -Filter *.lua -Recurse | ForEach-Object {
    $path = $_.FullName
    $text = Get-Content -Raw -Path $path
    # Remove long comments like --[[ ... ]] and --[=[ ... ]=]
    $clean = $text -replace "(?s)--\s*\[=*\[.*?\]=*\]",""
    # Remove long bracketed strings like [[ ... ]] (and variants with = signs)
    $clean = $clean -replace '(?s)\[=*\[.*?\]=*\]',''
    # Remove simple string literals ("..." and '...') including multiline safely
    $clean = $clean -replace '(?s)"([^"\\]|\\.)*"',''
    $clean = $clean -replace "(?s)'([^'\\]|\\.)*'",''
    # remove single-line comments (// style not used in Lua but strip -- rest-of-line)
    $clean = $clean -replace "--.*",""
    # find tokens in order
    $pattern = "\b(function|if|for|while|do|repeat|end|until)\b"
    $matches = [regex]::Matches($clean, $pattern)
    $stack = New-Object System.Collections.ArrayList
    $index = 0
    foreach ($m in $matches) {
        $tok = $m.Groups[1].Value
        $index++
        # compute approximate line number
        $before = $clean.Substring(0, [math]::Min($m.Index, $clean.Length))
        $lineNum = ($before -split "\n").Length
        switch ($tok) {
            'function' { [void]$stack.Add(@{tok='function'; idx=$m.Index}) }
            'if' { [void]$stack.Add(@{tok='if'; idx=$m.Index}) }
            'for' { [void]$stack.Add(@{tok='for'; idx=$m.Index}) }
            'while' { [void]$stack.Add(@{tok='while'; idx=$m.Index}) }
            'do' { [void]$stack.Add(@{tok='do'; idx=$m.Index}) }
            'repeat' { [void]$stack.Add(@{tok='repeat'; idx=$m.Index}) }
            'end' {
                if ($stack.Count -eq 0) {
                    Write-Host ("UNMATCHED 'end' in " + $path + " at token #" + $index + " (line " + $lineNum + ")")
                } else {
                    $top = $stack[$stack.Count-1]
                    $null = $stack.RemoveAt($stack.Count-1)
                }
            }
            'until' {
                # until should match a repeat
                if ($stack.Count -eq 0) {
                    Write-Host ("UNMATCHED 'until' in " + $path + " at token #" + $index + " (line " + $lineNum + ")")
                } else {
                    $top = $stack[$stack.Count-1]
                    if ($top.tok -ne 'repeat') {
                        Write-Host ("MISMATCH 'until' didn't match 'repeat' in " + $path + " at token #" + $index + " (line " + $lineNum + ")")
                    } else {
                        $null = $stack.RemoveAt($stack.Count-1)
                    }
                }
            }
        }
    }
    if ($stack.Count -gt 0) {
        Write-Host ("Unclosed blocks in " + $path + ":") -ForegroundColor Yellow
        foreach ($item in $stack) {
            $pos = $item.idx
            $line = ($clean.Substring(0, [math]::Min($pos, $clean.Length)) -split "\n").Length
            Write-Host (" - " + $item.tok + " at pos " + $pos + " (line " + $line + ")")
        }
    } else {
        Write-Host ("OK: " + $path + " - all blocks balanced")
    }
}
