#!/usr/bin/env python3
"""Map spell names to tokens for a given parsed id.
Writes capture_entries_token_mapped_<id>.csv and .ndjson
"""
import sys, csv, json
from pathlib import Path
if len(sys.argv)<2:
    print('usage: map_spell_names_id.py <id>')
    raise SystemExit(1)
id = sys.argv[1]
PARSED = Path(__file__).resolve().parents[1] / 'saved_exports' / 'parsed'
IN = PARSED / f'capture_entries_tokenized_{id}.csv'
OUT_CSV = PARSED / f'capture_entries_token_mapped_{id}.csv'
OUT_ND = PARSED / f'capture_entries_token_mapped_{id}.ndjson'
if not IN.exists():
    print('input missing:', IN)
    raise SystemExit(1)
rows = []
with IN.open('r', encoding='utf-8', newline='') as fh:
    r = csv.DictReader(fh)
    for row in r:
        rows.append(row)
name_to_id = {}
for r in rows:
    sid = r.get('spellId')
    name = r.get('spellName')
    if not name: continue
    try:
        sid_int = int(sid)
        if name not in name_to_id:
            name_to_id[name] = sid_int
    except Exception:
        continue
lower_map = {k.lower(): v for k, v in name_to_id.items()}
mapped_count = 0
for r in rows:
    if r.get('token'):
        r['mapped_token'] = r.get('token')
        r['mapped_source'] = 'already_token'
        continue
    sid = r.get('spellId')
    name = (r.get('spellName') or '').strip()
    try:
        sid_int = int(sid)
        r['mapped_token'] = f'spell:{sid_int}'
        r['mapped_source'] = 'from_id'
        mapped_count += 1
        continue
    except Exception:
        pass
    if name in name_to_id:
        r['mapped_token'] = f'spell:{name_to_id[name]}'
        r['mapped_source'] = 'match_exact'
        mapped_count += 1
        continue
    if name.lower() in lower_map:
        r['mapped_token'] = f'spell:{lower_map[name.lower()]}'
        r['mapped_source'] = 'match_case_insensitive'
        mapped_count += 1
        continue
    r['mapped_token'] = ''
    r['mapped_source'] = 'unmapped'
with OUT_CSV.open('w', encoding='utf-8', newline='') as fh:
    fieldnames = list(rows[0].keys())
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
        w.writerow(r)
with OUT_ND.open('w', encoding='utf-8') as fh:
    for r in rows:
        fh.write(json.dumps(r, ensure_ascii=False) + '\n')
print('wrote', OUT_CSV, 'and', OUT_ND)
print('mapped_count', mapped_count, 'of', len(rows))
