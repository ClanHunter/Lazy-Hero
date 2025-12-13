#!/usr/bin/env python3
"""Extract agentExport[...] blocks from savedvars OneButtonAssistant.lua into saved_exports/*.lua

Writes files under saved_exports/agentExport_<id>.lua
"""
import re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
SV = ROOT / 'savedvars' / 'OneButtonAssistant.lua'
OUT = ROOT / 'saved_exports'
OUT.mkdir(parents=True, exist_ok=True)
text = SV.read_text(encoding='utf-8', errors='ignore')
# find agentExport table
m = re.search(r'\["agentExport"\]\s*=\s*\{', text)
if not m:
    print('no agentExport found')
    raise SystemExit(1)
start = m.end()
# find each entry key like ["12345-6789"] = {
pattern = re.compile(r'\["(\d+-\d+)"\]\s*=\s*\{')
for mm in pattern.finditer(text, start):
    id_ = mm.group(1)
    entry_start = mm.start()
    # find matching brace for this entry's opening '{' at mm.end()-1
    open_idx = text.find('{', mm.end()-1)
    # find matching closing brace
    depth = 0
    for i in range(open_idx, len(text)):
        ch = text[i]
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                close_idx = i
                break
    else:
        print('no matching brace for', id_)
        continue
    block = text[entry_start:close_idx+1]
    outf = OUT / f'agentExport_{id_}.lua'
    outf.write_text(block, encoding='utf-8')
    print('wrote', outf)
print('done')
