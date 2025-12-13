#!/usr/bin/env python3
"""Run the parse_agent_export logic for a specific agentExport file name.
Usage: python parse_agent_export_id.py 296367-1706
"""
import sys
from pathlib import Path
if len(sys.argv) < 2:
    print('Usage: parse_agent_export_id.py <id>')
    raise SystemExit(1)
id = sys.argv[1]
SRC = Path(__file__).resolve().parents[1] / 'saved_exports' / f'agentExport_{id}.lua'
if not SRC.exists():
    print('Source not found:', SRC)
    raise SystemExit(1)
# Reuse parse_agent_export.py logic by importing its functions is awkward; instead, read and reuse same code body minimal
s = SRC.read_text(encoding='utf-8', errors='ignore')
OUT = Path(__file__).resolve().parents[1] / 'saved_exports' / 'parsed'
OUT.mkdir(parents=True, exist_ok=True)
import re, json, csv

def lua_table_to_json(lua_text):
    t = lua_text
    t = re.sub(r'\["([^\"]+)"\]\s*=\s*', r'"\1": ', t)
    t = re.sub(r'\bnil\b', 'null', t)
    t = re.sub(r'\btrue\b', 'true', t)
    t = re.sub(r'\bfalse\b', 'false', t)
    t = re.sub(r',\s*}', '}', t)
    t = re.sub(r',\s*\]', ']', t)
    return t

# copy extract_capture_entries from original script
import math

def extract_capture_entries(text):
    m = re.search(r'\["lastRawSuggestion"\]\s*=\s*\{', text)
    if not m:
        return []
    start = m.start()
    m2 = re.search(r'\["capture"\]\s*=\s*\{', text[m.start():])
    if not m2:
        return []
    cap_start = start + m2.end()
    m3 = re.search(r'\["entries"\]\s*=\s*\{', text[cap_start:])
    if not m3:
        return []
    entries_start = cap_start + m3.end()
    def find_matching_brace(s, i):
        depth = 0
        for j in range(i, len(s)):
            if s[j] == '{':
                depth += 1
            elif s[j] == '}':
                depth -= 1
                if depth == 0:
                    return j
        return -1
    open_idx = text.find('{', entries_start-1)
    close_idx = find_matching_brace(text, open_idx)
    if close_idx == -1:
        return []
    block = text[open_idx:close_idx+1]
    entries = []
    i = 1
    while i < len(block)-1:
        if block[i] == '{':
            j = find_matching_brace(block, i)
            if j == -1:
                break
            entry_text = block[i:j+1]
            pairs = re.findall(r'\["([^\"]+)"\]\s*=\s*("[^"]*"|[\d\.]+|nil|true|false)', entry_text)
            d = {}
            for k,v in pairs:
                val = v
                if val.startswith('"') and val.endswith('"'):
                    d[k] = val[1:-1]
                elif val == 'nil':
                    d[k] = None
                elif val == 'true':
                    d[k] = True
                elif val == 'false':
                    d[k] = False
                else:
                    if '.' in val:
                        try:
                            d[k] = float(val)
                        except:
                            d[k] = val
                    else:
                        try:
                            d[k] = int(val)
                        except:
                            d[k] = val
            entries.append(d)
            i = j+1
        else:
            i += 1
    return entries

entries = extract_capture_entries(s)
print('capture entries parsed:', len(entries))
if entries:
    with (OUT / f'capture_entries_{id}.csv').open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        keys = ['spellId','spellName','dest','t','subevent']
        w.writerow(keys)
        for e in entries:
            w.writerow([e.get(k,'') for k in keys])
    print('wrote', OUT / f'capture_entries_{id}.csv')

# extract logger events

def extract_logger_events(text):
    m = re.search(r'\["loggerDump"\]\s*=\s*\{', text)
    if not m:
        return []
    start = m.end()
    def find_matching(s,i):
        depth=0
        for j in range(i, len(s)):
            if s[j]=='{': depth+=1
            elif s[j]=='}':
                depth-=1
                if depth==0: return j
        return -1
    open_idx = text.find('{', m.start())
    close = find_matching(text, open_idx)
    if close==-1:
        return []
    block = text[open_idx:close+1]
    events = []
    i = 1
    while i < len(block)-1:
        if block[i] == '{':
            j = find_matching(block, i)
            if j==-1: break
            item = block[i:j+1]
            ev = re.search(r'\["event"\]\s*=\s*"([^\"]+)"', item)
            tm = re.search(r'\["time"\]\s*=\s*([\d\.]+)', item)
            dm = re.search(r'\["data"\]\s*=\s*\{', item)
            data_text = None
            if dm:
                open_d = item.find('{', dm.start())
                close_d = find_matching(item, open_d)
                if close_d!=-1:
                    data_text = item[open_d:close_d+1]
            entry = {'event': ev.group(1) if ev else None, 'time': float(tm.group(1)) if tm else None}
            if data_text:
                try:
                    dj = json.loads(lua_table_to_json(data_text))
                    entry['data'] = dj
                except Exception:
                    entry['data_raw'] = data_text
            events.append(entry)
            i = j+1
        else:
            i += 1
    return events

logger_events = extract_logger_events(s)
print('logger events parsed:', len(logger_events))
with (OUT / f'logger_dump_{id}.ndjson').open('w', encoding='utf-8') as fh:
    for ev in logger_events:
        fh.write(json.dumps(ev, ensure_ascii=False) + '\n')
print('wrote', OUT / f'logger_dump_{id}.ndjson')

print('done')
