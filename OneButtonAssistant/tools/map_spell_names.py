#!/usr/bin/env python3
"""Map spell names to tokens using captured rows as a local lookup.
- Reads: saved_exports/parsed/capture_entries_tokenized.csv
- Produces: saved_exports/parsed/capture_entries_token_mapped.csv and .ndjson
Mapping strategy:
1) Build map from rows where spellId is integer -> name
2) For rows without a numeric spellId, try exact name match (case-sensitive), then case-insensitive
3) Add `mapped_token` column with `spell:<id>` when found, and `mapped_source` describing match
"""
import csv, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PARSED = ROOT / 'saved_exports' / 'parsed'
IN = PARSED / 'capture_entries_tokenized.csv'
OUT_CSV = PARSED / 'capture_entries_token_mapped.csv'
OUT_ND = PARSED / 'capture_entries_token_mapped.ndjson'

if not IN.exists():
    print('input missing:', IN)
    raise SystemExit(1)

rows = []
with IN.open('r', encoding='utf-8', newline='') as fh:
    r = csv.DictReader(fh)
    for row in r:
        rows.append(row)

# Build mapping name -> id from rows with numeric spellId
name_to_id = {}
for r in rows:
    sid = r.get('spellId')
    name = r.get('spellName')
    if not name: continue
    try:
        sid_int = int(sid)
        # prefer first seen mapping
        if name not in name_to_id:
            name_to_id[name] = sid_int
    except Exception:
        continue

# helper lowercase map
lower_map = {k.lower(): v for k, v in name_to_id.items()}

mapped_count = 0
for r in rows:
    mapped = ''
    src = ''
    sid = r.get('spellId')
    name = (r.get('spellName') or '').strip()
    # skip if token already present
    if r.get('token'):
        r['mapped_token'] = r.get('token')
        r['mapped_source'] = 'already_token'
        continue
    # try numeric id
    try:
        sid_int = int(sid)
        r['mapped_token'] = f'spell:{sid_int}'
        r['mapped_source'] = 'from_id'
        mapped_count += 1
        continue
    except Exception:
        pass
    # try exact name match
    if name in name_to_id:
        r['mapped_token'] = f'spell:{name_to_id[name]}'
        r['mapped_source'] = 'match_exact'
        mapped_count += 1
        continue
    # try case-insensitive
    if name.lower() in lower_map:
        r['mapped_token'] = f'spell:{lower_map[name.lower()]}'
        r['mapped_source'] = 'match_case_insensitive'
        mapped_count += 1
        continue
    # not found
    r['mapped_token'] = ''
    r['mapped_source'] = 'unmapped'

# write CSV
with OUT_CSV.open('w', encoding='utf-8', newline='') as fh:
    fieldnames = list(rows[0].keys())
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    for r in rows:
        w.writerow(r)
print('wrote', OUT_CSV)

# write ndjson
with OUT_ND.open('w', encoding='utf-8') as fh:
    for r in rows:
        fh.write(json.dumps(r, ensure_ascii=False) + '\n')
print('wrote', OUT_ND)
print('mapped_count', mapped_count, 'of', len(rows))
