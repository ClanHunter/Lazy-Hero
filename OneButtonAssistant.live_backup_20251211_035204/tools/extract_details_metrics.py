#!/usr/bin/env python3
"""
Extract useful metrics from the cleaned Details savedvars block (text-only heuristics).

This avoids full JSON parsing and instead uses regex to pull out common structures:
- combat_id_global
- spell_pool (id -> count)
- trinket_data (id -> spellName)
- savedCustomSpells (list of [id, name, icon/number])

Outputs CSVs into `OneButtonAssistant/patches/` and prints a short summary.
"""
import re
from pathlib import Path
import csv

infile = Path('OneButtonAssistant/patches/details_extracted_block.txt')
outdir = Path('OneButtonAssistant/patches')
text = infile.read_text(encoding='utf-8')

def extract_combat_id_global(t):
    m = re.search(r'"combat_id_global"\s*:\s*(\d+)', t)
    return int(m.group(1)) if m else None

def extract_spell_pool(t):
    m = re.search(r'"spell_pool"\s*:\s*\{', t)
    if not m:
        return {}
    start = m.end()-1
    # find matching brace
    depth = 0
    i = start
    while i < len(t):
        if t[i] == '{': depth += 1
        elif t[i] == '}':
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    block = t[start+1:end]
    # find patterns like "12345": 7 or 12345: 7 or 7,
    pairs = {}
    for m in re.finditer(r'"?(\d+)"?\s*:\s*(\d+)', block):
        pairs[m.group(1)] = int(m.group(2))
    # also capture standalone numeric entries at start lines like '7,' (we'll ignore them)
    return pairs

def extract_trinket_data(t):
    m = re.search(r'"trinket_data"\s*:\s*\{', t)
    if not m:
        return {}
    start = m.end()-1
    depth = 0
    i = start
    while i < len(t):
        if t[i] == '{': depth += 1
        elif t[i] == '}':
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    block = t[start+1:end]
    # entries like "1234219": { ... "spellName": "Footbomb to the Face"},
    res = {}
    for m in re.finditer(r'"(\d+)"\s*:\s*\{([^}]+)\}', block, re.S):
        inner = m.group(2)
        sm = re.search(r'"spellName"\s*:\s*"([^"]+)"', inner)
        if sm:
            res[m.group(1)] = sm.group(1)
    return res

def extract_saved_custom_spells(t):
    m = re.search(r'"savedCustomSpells"\s*:\s*\{', t)
    if not m:
        return []
    start = m.end()-1
    depth = 0
    i = start
    while i < len(t):
        if t[i] == '{': depth += 1
        elif t[i] == '}':
            depth -= 1
            if depth == 0:
                end = i
                break
        i += 1
    block = t[start+1:end]
    # find inner anonymous arrays like [
    items = []
    # pattern: {\s*(\d+),\s*"([^"]+)",\s*"?([^",}\n]+)"?\s*}\s*,?
    for m in re.finditer(r'[\{\[]\s*(\d+)\s*,\s*"([^"]+)"\s*,\s*"?([^\",\}\n]+)"?\s*[\}\]]', block):
        items.append((m.group(1), m.group(2), m.group(3)))
    return items

combat_id = extract_combat_id_global(text)
spell_pool = extract_spell_pool(text)
trinkets = extract_trinket_data(text)
custom_spells = extract_saved_custom_spells(text)

print('combat_id_global =', combat_id)
print('spell_pool entries =', len(spell_pool))
print('trinket entries =', len(trinkets))
print('savedCustomSpells entries =', len(custom_spells))

# Write CSVs
if spell_pool:
    with open(outdir / 'details_spell_pool.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['spellId','count'])
        for k,v in sorted(spell_pool.items(), key=lambda kv: -kv[1]):
            w.writerow([k,v])
if trinkets:
    with open(outdir / 'details_trinket_data.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['id','spellName'])
        for k,v in trinkets.items():
            w.writerow([k,v])
if custom_spells:
    with open(outdir / 'details_custom_spells.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['id','name','icon_or_number'])
        for a,b,c in custom_spells:
            w.writerow([a,b,c])

print('Wrote CSVs to', outdir)
