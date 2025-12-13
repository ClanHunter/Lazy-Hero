#!/usr/bin/env python3
"""
convert_pvp_csv_to_json.py

Reads `inputs/pvp_talents.csv` and writes `outputs/pvp_quickref.csv` (copy) and
`outputs/pvp_quickref.json` (structured JSON) for programmatic use.

Usage:
  python tools/convert_pvp_csv_to_json.py

"""
import csv, json, os

IN = os.path.join(os.path.dirname(__file__), '..', 'inputs', 'pvp_talents.csv')
OUT_CSV = os.path.join(os.path.dirname(__file__), '..', 'outputs', 'pvp_quickref.csv')
OUT_JSON = os.path.join(os.path.dirname(__file__), '..', 'outputs', 'pvp_quickref.json')

os.makedirs(os.path.dirname(OUT_CSV), exist_ok=True)

rows = []
with open(IN, newline='', encoding='utf-8') as fh:
    reader = csv.DictReader(fh)
    headers = reader.fieldnames
    for r in reader:
        def split_semis(s):
            if s is None: return []
            return [x.strip() for x in s.split(';') if x.strip()]
        obj = {
            'Class': r.get('Class',''),
            'Spec': r.get('Spec',''),
            'CoreAbilities': split_semis(r.get('CoreAbilities','')),
            'SpecTalents': split_semis(r.get('SpecTalents','')),
            'HeroTalents': split_semis(r.get('HeroTalents','')),
            'PvPTalents': split_semis(r.get('PvPTalents','')),
        }
        rows.append(obj)

# write a straight CSV copy (clean fields)
with open(OUT_CSV, 'w', newline='', encoding='utf-8') as fh:
    writer = csv.writer(fh)
    writer.writerow(['Class','Spec','CoreAbilities','SpecTalents','HeroTalents','PvPTalents'])
    for r in rows:
        writer.writerow([
            r['Class'], r['Spec'],
            '; '.join(r['CoreAbilities']),
            '; '.join(r['SpecTalents']),
            '; '.join(r['HeroTalents']),
            '; '.join(r['PvPTalents'])
        ])

with open(OUT_JSON, 'w', encoding='utf-8') as fh:
    json.dump(rows, fh, ensure_ascii=False, indent=2)

print('Wrote:', OUT_CSV)
print('Wrote:', OUT_JSON)
