#!/usr/bin/env python3
import csv
from pathlib import Path

rows=[
('Lightning Bolt','113.82M','100.0%'),
('Tempest','59.43M','52.2%'),
('Stormstrike','54.45M','47.8%'),
('Windfury Attack','35.52M','31.2%'),
('Awakening Storms','27.80M','24.4%'),
('Stormblast','26.90M','23.6%'),
('Windstrike','22.73M','20.0%'),
('Tempest Strikes','19.15M','16.8%'),
('Doom Winds','17.85M','15.7%'),
('Melee','17.34M','15.2%'),
("Storm's Eye","17.32M","15.2%"),
('Flametongue Attack','14.41M','12.7%'),
('Lightning Rod','12.90M','11.3%'),
('Windstrike Off','11.57M','10.2%'),
('Righteous Fire','10.01M','8.8%'),
('Melee','9.31M','8.2%'),
('Ethereal Reaping','7.00M','6.2%'),
('Crash Lightning','5.62M','4.9%'),
('Ascendance','4.65M','4.1%'),
('Authority of Radiant Power','3.21M','2.8%'),
('Windlash','1.64M','1.4%'),
('Ice Strike','1.55M','1.4%'),
('Frost Shock','1.10M','1.0%'),
('Windlash Off','1.07M','0.9%'),
('Flame Shock','734K','0.6%')
]

def to_num(s):
    s=s.strip()
    if s.endswith('M'):
        return float(s[:-1])*1e6
    if s.endswith('K'):
        return float(s[:-1])*1e3
    return float(s)

out=Path('OneButtonAssistant/patches/Wickedstorm_PvP_Training_Dummy_damage.csv')
total=sum(to_num(r[1]) for r in rows)
with out.open('w',newline='',encoding='utf-8') as fh:
    w=csv.writer(fh)
    w.writerow(['spell','damage_text','damage','percent_reported','percent_of_total'])
    for name,txt,pr in rows:
        num=int(to_num(txt))
        pot=100.0*(num/total) if total>0 else 0.0
        w.writerow([name,txt,num,pr,f"{pot:.2f}%"])

print('Wrote',out)
print('Total damage:',int(total))
