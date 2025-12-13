#!/usr/bin/env python3
"""Postprocess parsed files for a specific id.
Usage: python postprocess_parsed_id.py 296367-1706
Reads: saved_exports/parsed/capture_entries_<id>.csv and logger_dump_<id>.ndjson
Writes: capture_entries_tokenized_<id>.csv, logger_dump_normalized_<id>.ndjson, summary_<id>.json
"""
import sys, csv, json, re
from pathlib import Path
if len(sys.argv)<2:
    print('usage: postprocess_parsed_id.py <id>')
    raise SystemExit(1)
id = sys.argv[1]
PARSED = Path(__file__).resolve().parents[1] / 'saved_exports' / 'parsed'
cap_in = PARSED / f'capture_entries_{id}.csv'
log_in = PARSED / f'logger_dump_{id}.ndjson'
if not cap_in.exists():
    print('capture file not found:', cap_in)
    raise SystemExit(1)
entries = []
with cap_in.open('r', encoding='utf-8', newline='') as fh:
    r = csv.DictReader(fh)
    for row in r:
        spellId = row.get('spellId','')
        token = ''
        if spellId:
            try:
                sid = int(spellId)
                token = f'spell:{sid}'
            except:
                token = ''
        row['token'] = token
        entries.append(row)
out_cap = PARSED / f'capture_entries_tokenized_{id}.csv'
with out_cap.open('w', encoding='utf-8', newline='') as fh:
    fieldnames = list(entries[0].keys())
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    for r in entries:
        w.writerow(r)
print('wrote', out_cap)

# normalize logger
normed = []
if log_in.exists():
    with log_in.open('r', encoding='utf-8') as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
            except Exception:
                continue
            def normalize(v):
                if isinstance(v, dict):
                    return {k: normalize(val) for k,val in v.items()}
                if isinstance(v, list):
                    return [normalize(x) for x in v]
                if isinstance(v, str):
                    if v == 'null':
                        return None
                    if re.fullmatch(r'-?\d+\.?\d*', v):
                        try:
                            if '.' in v:
                                return float(v)
                            else:
                                return int(v)
                        except:
                            return v
                    return v
                return v
            obj['data'] = normalize(obj.get('data'))
            normed.append(obj)
out_log = PARSED / f'logger_dump_normalized_{id}.ndjson'
with out_log.open('w', encoding='utf-8') as fh:
    for o in normed:
        fh.write(json.dumps(o, ensure_ascii=False) + '\n')
print('wrote', out_log)
summary = {'capture_rows': len(entries), 'logger_events': len(normed)}
(PARSED / f'summary_{id}.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print('wrote summary for', id)
