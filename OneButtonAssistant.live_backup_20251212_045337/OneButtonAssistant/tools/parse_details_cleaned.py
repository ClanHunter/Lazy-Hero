#!/usr/bin/env python3
"""
Heuristic converter: take the cleaned JSON-like block produced by the inspector
(`patches/details_extracted_block.txt`) and try to transform it into valid JSON.
Writes `patches/details_parsed.json` on success and prints a summary.

This is best-effort — Details savedvars can be complex. Review the output file
if parsing fails or values look incorrect.
"""
import re
import json
from pathlib import Path


inpath = Path('OneButtonAssistant/patches/details_extracted_block.txt')
outpath = Path('OneButtonAssistant/patches/details_parsed.json')

text = inpath.read_text(encoding='utf-8')

# Remove any trailing commas before closing braces/brackets
text = re.sub(r',\s*([}\]])', r'\1', text)

def infer_brace_types(s):
    """Convert Lua-style anonymous tables to JSON arrays where appropriate.

    Heuristic: when a `{` is followed (after whitespace/newlines) by either a number,
    a string literal, or another `{` without the pattern '"key"\s*:' before the next comma/brace,
    treat it as an array (`[`). Otherwise keep as object (`{`).
    """
    out = []
    stack = []  # track replacements: '{'->'{' or '['
    i = 0
    L = len(s)
    while i < L:
        c = s[i]
        if c == '{':
            # look ahead to determine if this is an object with quoted keys or an array
            j = i + 1
            # skip whitespace/newlines
            while j < L and s[j].isspace():
                j += 1
            # find next structural chars up to a limit
            look = s[j:j+200]
            is_object = False
            # if we see "...": before a comma or closing brace, treat as object
            m = re.search(r'"[^\n\r"]+"\s*:\s*', look)
            if m:
                is_object = True
            else:
                # if next char is '}' it's an empty object
                if j < L and s[j] == '}':
                    is_object = True
                else:
                    # otherwise treat as array
                    is_object = False
            if is_object:
                out.append('{')
                stack.append('}')
            else:
                out.append('[')
                stack.append(']')
            i += 1
        elif c == '}':
            if stack:
                closing = stack.pop()
                out.append(closing)
            else:
                out.append('}')
            i += 1
        else:
            out.append(c)
            i += 1
    return ''.join(out)

# Apply brace inference
# Targeted fix: savedCustomSpells is a list of anonymous tables — convert that whole block to JSON arrays
m = re.search(r'"savedCustomSpells"\s*:\s*\{', text)
if m:
    start = m.start()
    # find the opening brace position
    brace_pos = text.find('{', m.end()-1)
    # find matching closing brace
    depth = 0
    i = brace_pos
    end_pos = None
    while i < len(text):
        if text[i] == '{':
            depth += 1
        elif text[i] == '}':
            depth -= 1
            if depth == 0:
                end_pos = i
                break
        i += 1
    if end_pos:
        block = text[brace_pos:end_pos+1]
        # convert all inner '{' to '[' and '}' to ']' within the block
        block_fixed = block.replace('{', '[').replace('}', ']')
        text = text[:brace_pos] + block_fixed + text[end_pos+1:]

text2 = infer_brace_types(text)

# Also convert Lua-style keyless inner brackets like { 1, 2, 3 } that remain
text2 = re.sub(r'\{\s*([0-9]+\s*(?:,\s*[0-9]+)+)\s*\}', lambda m: '[' + m.group(1) + ']', text2)

# Normalize nil to null
text2 = text2.replace('nil', 'null')

# Attempt to load as JSON
try:
    obj = json.loads(text2)
except Exception as e:
    inter = Path('OneButtonAssistant/patches/details_intermediate.txt')
    inter.write_text(text2, encoding='utf-8')
    print('Failed to parse JSON:', e)
    print('Wrote intermediate cleaned text to', inter)
    raise SystemExit(2)

# Save parsed JSON
outpath.write_text(json.dumps(obj, indent=2, ensure_ascii=False), encoding='utf-8')

print('Parsed JSON saved to', outpath)
print('Top-level keys and simple counts:')
if isinstance(obj, dict):
    for k in sorted(obj.keys()):
        v = obj[k]
        if isinstance(v, dict):
            print(f'- {k}: object with {len(v)} keys')
        elif isinstance(v, list):
            print(f'- {k}: list with {len(v)} items')
        else:
            print(f'- {k}: {type(v).__name__}')
else:
    print('Parsed root is', type(obj).__name__)
