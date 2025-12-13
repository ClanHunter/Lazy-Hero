#!/usr/bin/env python3
"""Generate a master class/spec/talent template including PvP talents.

Reads:
 - WAR_WITHIN_class_matrix.csv
 - inputs/pvp_talents.csv

Writes:
 - inputs/master_talent_template.json
 - inputs/master_talent_template.csv

This is idempotent and safe to run repeatedly.
"""
import csv
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INPUTS = ROOT / 'inputs'
CLASS_MATRIX = ROOT / 'WAR_WITHIN_class_matrix.csv'
PVP_CSV = INPUTS / 'pvp_talents.csv'
OUT_JSON = INPUTS / 'master_talent_template.json'
OUT_CSV = INPUTS / 'master_talent_template.csv'


def split_list(cell):
    if not cell:
        return []
    parts = [p.strip() for p in cell.split(';') if p.strip()]
    return parts


# load pvp csv into map keyed by (Class,Spec)
pvp_map = {}
if PVP_CSV.exists():
    with PVP_CSV.open('r', encoding='utf-8', newline='') as fh:
        r = csv.DictReader(fh)
        for row in r:
            key = (row.get('Class','').strip(), row.get('Spec','').strip())
            pvp_map[key] = {
                'CoreAbilities': split_list(row.get('CoreAbilities','')),
                'SpecTalents': split_list(row.get('SpecTalents','')),
                'HeroTalents': split_list(row.get('HeroTalents','')),
                'PvPTalents': split_list(row.get('PvPTalents','')),
            }

entries = []
# read class matrix and combine
with CLASS_MATRIX.open('r', encoding='utf-8', newline='') as fh:
    r = csv.DictReader(fh)
    for row in r:
        speckey = row.get('SpecKey') or f"{row.get('Class','').strip()}_{row.get('Spec','').strip()}"
        class_name = row.get('Class','').strip()
        spec_name = row.get('Spec','').strip()
        role = row.get('Role','').strip()
        # base entry
        e = {
            'SpecKey': speckey,
            'Class': class_name,
            'Spec': spec_name,
            'Role': role,
            'BurstVsSustain': row.get('BurstVsSustain','').strip(),
            'Mobility': row.get('Mobility','').strip(),
            'Control': row.get('Control','').strip(),
            'Complexity': row.get('Complexity','').strip(),
            'PrimaryResource': row.get('PrimaryResource','').strip(),
            'Feel': row.get('Feel','').strip(),
            'RotationKeywords': row.get('RotationKeywords','').strip(),
            'CoreAbilities': [],
            'SpecTalents': [],
            'HeroTalents': [],
            'PvPTalents': [],
        }
        p = pvp_map.get((class_name, spec_name))
        if p:
            e['CoreAbilities'] = p['CoreAbilities']
            e['SpecTalents'] = p['SpecTalents']
            e['HeroTalents'] = p['HeroTalents']
            e['PvPTalents'] = p['PvPTalents']
        entries.append(e)

# also include any entries present in pvp_map but missing from class matrix
for (cls, spec), v in pvp_map.items():
    found = any(e['Class']==cls and e['Spec']==spec for e in entries)
    if not found:
        entries.append({
            'SpecKey': f"{cls}_{spec}",
            'Class': cls,
            'Spec': spec,
            'Role': '',
            'BurstVsSustain': '',
            'Mobility': '',
            'Control': '',
            'Complexity': '',
            'PrimaryResource': '',
            'Feel': '',
            'RotationKeywords': '',
            'CoreAbilities': v['CoreAbilities'],
            'SpecTalents': v['SpecTalents'],
            'HeroTalents': v['HeroTalents'],
            'PvPTalents': v['PvPTalents'],
        })

# write json
OUT_JSON.write_text(json.dumps(entries, indent=2, ensure_ascii=False), encoding='utf-8')

# write csv (flatten lists to semicolon-separated)
with OUT_CSV.open('w', encoding='utf-8', newline='') as fh:
    fieldnames = ['SpecKey','Class','Spec','Role','BurstVsSustain','Mobility','Control','Complexity','PrimaryResource','Feel','RotationKeywords','CoreAbilities','SpecTalents','HeroTalents','PvPTalents']
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader()
    for e in entries:
        row = {k: ('; '.join(e[k]) if isinstance(e[k], list) else e[k]) for k in fieldnames}
        w.writerow(row)

print('Wrote', OUT_JSON, 'and', OUT_CSV)
