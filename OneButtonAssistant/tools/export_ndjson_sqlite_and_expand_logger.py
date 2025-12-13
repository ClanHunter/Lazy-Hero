#!/usr/bin/env python3
"""Create NDJSON and SQLite from capture entries, and expand logger events.

Outputs written to saved_exports/parsed/
- capture_entries.ndjson
- capture_entries.sqlite (table: captures)
- logger_dump_expanded.ndjson
- logger_dump_expanded.csv
"""
import csv, json, sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARSED = ROOT / 'saved_exports' / 'parsed'
PARSED.mkdir(parents=True, exist_ok=True)

# 1) capture entries -> ndjson + sqlite
cap_csv = PARSED / 'capture_entries_tokenized.csv'
cap_ndjson = PARSED / 'capture_entries.ndjson'
cap_sqlite = PARSED / 'capture_entries.sqlite'
if cap_csv.exists():
    rows = []
    with cap_csv.open('r', encoding='utf-8', newline='') as fh:
        r = csv.DictReader(fh)
        for row in r:
            # normalize types
            try:
                row['spellId'] = int(row['spellId']) if row.get('spellId') not in (None, '', 'None') and str(row.get('spellId')).isdigit() else row.get('spellId')
            except:
                pass
            # time as float
            try:
                row['t'] = float(row['t']) if row.get('t') not in (None, '') else None
            except:
                pass
            rows.append(row)
    # write ndjson
    with cap_ndjson.open('w', encoding='utf-8') as fh:
        for r in rows:
            fh.write(json.dumps(r, ensure_ascii=False) + '\n')
    # write sqlite
    conn = sqlite3.connect(cap_sqlite)
    cur = conn.cursor()
    # determine columns
    cols = list(rows[0].keys()) if rows else ['spellId','spellName','dest','t','subevent','token']
    # create table
    col_defs = ', '.join([f'"{c}" TEXT' for c in cols])
    cur.execute('DROP TABLE IF EXISTS captures')
    cur.execute(f'CREATE TABLE captures ({col_defs})')
    # insert rows
    placeholders = ', '.join(['?'] * len(cols))
    for r in rows:
        vals = [str(r.get(c) if r.get(c) is not None else '') for c in cols]
        cur.execute(f'INSERT INTO captures VALUES ({placeholders})', vals)
    conn.commit()
    conn.close()
    print('wrote', cap_ndjson, 'and', cap_sqlite)
else:
    print('capture tokenized csv not found', cap_csv)

# 2) expand logger dump
ld_in = PARSED / 'logger_dump_normalized.ndjson'
ld_exp_nd = PARSED / 'logger_dump_expanded.ndjson'
ld_exp_csv = PARSED / 'logger_dump_expanded.csv'
expanded = []
if ld_in.exists():
    with ld_in.open('r', encoding='utf-8') as fh:
        for line in fh:
            o = json.loads(line)
            base = {'event': o.get('event'), 'time': o.get('time')}
            data = o.get('data') or {}
            # flatten data.raw if present
            raw = data.get('raw') if isinstance(data, dict) else None
            if isinstance(raw, dict):
                # bring top-level keys from raw into row, prefix with raw_
                flat = {('raw_' + k): (v if not isinstance(v, dict) else json.dumps(v, ensure_ascii=False)) for k,v in raw.items()}
                row = {**base, **flat}
            else:
                row = {**base}
            # also include full data as 'data' field
            row['data'] = data
            expanded.append(row)
    # write ndjson
    with ld_exp_nd.open('w', encoding='utf-8') as fh:
        for r in expanded:
            fh.write(json.dumps(r, ensure_ascii=False) + '\n')
    # write csv: flatten columns
    # collect all keys
    keys = set()
    for r in expanded:
        for k in r.keys(): keys.add(k)
    keys = sorted(keys)
    with ld_exp_csv.open('w', encoding='utf-8', newline='') as fh:
        w = csv.DictWriter(fh, fieldnames=keys)
        w.writeheader()
        for r in expanded:
            # ensure all values are serializable strings
            out = {}
            for k in keys:
                v = r.get(k, '')
                if isinstance(v, (dict, list)):
                    out[k] = json.dumps(v, ensure_ascii=False)
                else:
                    out[k] = v
            w.writerow(out)
    print('wrote', ld_exp_nd, 'and', ld_exp_csv)
else:
    print('logger normalized not found', ld_in)

print('done')
