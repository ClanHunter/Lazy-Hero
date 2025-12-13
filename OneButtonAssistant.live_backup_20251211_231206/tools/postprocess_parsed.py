#!/usr/bin/env python3
"""Post-process parsed outputs:
- Tokenize capture entries -> capture_entries_tokenized.csv
- Normalize logger_dump.ndjson (convert string "null" to null, ensure numbers restored)
- Produce a small summary JSON
"""
import csv, json, re
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
PARSED = ROOT / 'saved_exports' / 'parsed'
PARSED.mkdir(parents=True, exist_ok=True)

# Tokenize capture entries
cap_in = PARSED / 'capture_entries.csv'
cap_out = PARSED / 'capture_entries_tokenized.csv'
entries = []
if cap_in.exists():
    with cap_in.open('r', encoding='utf-8', newline='') as fh:
        r = csv.DictReader(fh)
        for row in r:
            # normalize keys
            spellId = row.get('spellId','')
            token = ''
            if spellId:
                try:
                    sid = int(spellId)
                    token = f"spell:{sid}"
                except:
                    # sometimes spellId like 'name:Foo'
                    if str(spellId).startswith('name:'):
                        token = ''
                    else:
                        token = ''
            row['token'] = token
            entries.append(row)
    # write out tokenized
    with cap_out.open('w', encoding='utf-8', newline='') as fh:
        fieldnames = list(entries[0].keys())
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        for r in entries:
            w.writerow(r)
    print('wrote', cap_out)
else:
    print('capture file not found:', cap_in)

# Normalize logger ndjson
ld_in = PARSED / 'logger_dump.ndjson'
ld_out = PARSED / 'logger_dump_normalized.ndjson'
normed = []
if ld_in.exists():
    with ld_in.open('r', encoding='utf-8') as fh:
        for line in fh:
            line=line.strip()
            if not line: continue
            try:
                obj = json.loads(line)
            except Exception:
                # skip malformed
                continue
            # recursive normalization: replace string 'null' -> None, numeric strings -> numbers
            def normalize(v):
                if isinstance(v, dict):
                    return {k: normalize(val) for k,val in v.items()}
                if isinstance(v, list):
                    return [normalize(x) for x in v]
                if isinstance(v, str):
                    if v == 'null':
                        return None
                    # match a number
                    if re.fullmatch(r'-?\d+\.?\d*', v):
                        # avoid leading zeros weirdness
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
    with ld_out.open('w', encoding='utf-8') as fh:
        for o in normed:
            fh.write(json.dumps(o, ensure_ascii=False) + '\n')
    print('wrote', ld_out)
else:
    print('logger_dump not found:', ld_in)

# Summary
summary = {
    'capture_rows': len(entries),
    'logger_events': len(normed),
}
(PARSED / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
print('wrote summary.json')
