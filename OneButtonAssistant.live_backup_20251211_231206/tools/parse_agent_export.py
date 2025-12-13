#!/usr/bin/env python3
"""Parse a saved-agent export Lua fragment and produce CSV/NDJSON/JSON outputs.

Input: saved_exports/agentExport_283600-2402.lua
Outputs written to: saved_exports/parsed/
- capture_entries.csv
- logger_dump.ndjson
- heuristics.json
- aliases.json
- adapters.json
- full_parsed.json (best-effort)
"""
import re
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / 'saved_exports' / 'agentExport_283600-2402.lua'
OUT = ROOT / 'saved_exports' / 'parsed'
OUT.mkdir(parents=True, exist_ok=True)

s = SRC.read_text(encoding='utf-8', errors='ignore')

# Helper: convert a small Lua table string to JSON-ish by regex replacements
def lua_table_to_json(lua_text):
    t = lua_text
    # replace ["key"] = with "key":
    t = re.sub(r'\["([^\"]+)"\]\s*=\s*', r'"\1": ', t)
    # replace equals for bareword keys like ["..."] already handled; replace = with : for any remaining occurrences of = between tokens
    # convert true/false/nil
    t = re.sub(r'\bnil\b', 'null', t)
    t = re.sub(r'\btrue\b', 'true', t)
    t = re.sub(r'\bfalse\b', 'false', t)
    # remove trailing commas before closing braces
    t = re.sub(r',\s*}', '}', t)
    t = re.sub(r',\s*\]', ']', t)
    # ensure keys are quoted (most are already)
    # convert Lua long string markers not expected here
    return t

# Try to build a full JSON object by wrapping the single key in braces
wrapped = '{' + lua_table_to_json(s) + '}'

# Quick cleanup: remove Lua comments -- none expected
try:
    full = json.loads(wrapped)
except Exception as e:
    # fallback: try to extract specific parts manually
    full = None
    print('Full JSON parse failed:', e)

# Extract capture entries via regex if direct parse failed or even if succeeded

def extract_capture_entries(text):
    # locate lastRawSuggestion capture entries block
    m = re.search(r'\["lastRawSuggestion"\]\s*=\s*\{', text)
    if not m:
        return []
    start = m.start()
    # find '"capture"] = {' after that
    m2 = re.search(r'\["capture"\]\s*=\s*\{', text[m.start():])
    if not m2:
        return []
    cap_start = start + m2.end()
    # find '"entries" = {' after cap_start
    m3 = re.search(r'\["entries"\]\s*=\s*\{', text[cap_start:])
    if not m3:
        return []
    entries_start = cap_start + m3.end()
    # now parse balanced braces from entries_start
    idx = entries_start
    depth = 0
    entries_block = ''
    for i in range(entries_start, len(text)):
        ch = text[i]
        entries_block += ch
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth < 0:
                break
        # stop when we hit the closing brace of the entries array (depth== -1?)
        # safer approach: detect the matching closing '}' for the entries initial '{' by scanning
    # Instead, find the substring between the 'entries' opening brace and the next top-level '},' that closes it.
    # Simpler: find the text starting at entries_start-1 and find matching brace
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
    # find top-level entries: occurrences of '{' '}' at depth 1 inside block
    entries = []
    i = 1 # skip outer '{'
    while i < len(block)-1:
        if block[i] == '{':
            j = find_matching_brace(block, i)
            if j == -1:
                break
            entry_text = block[i:j+1]
            # parse key/value pairs inside entry
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
                    # number
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

capture_entries = extract_capture_entries(s)
print('capture entries parsed:', len(capture_entries))

# write capture CSV
import csv
csvf = OUT / 'capture_entries.csv'
if capture_entries:
    keys = ['spellId','spellName','dest','t','subevent']
    with csvf.open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(keys)
        for e in capture_entries:
            row = [e.get(k, '') for k in keys]
            w.writerow(row)
    print('wrote', csvf)

# Extract loggerDump events: find ['loggerDump'] = { ... }
def extract_logger_events(text):
    m = re.search(r'\["loggerDump"\]\s*=\s*\{', text)
    if not m:
        return []
    start = m.end()
    # find matching brace
    open_idx = text.find('{', m.start())
    def find_matching(s,i):
        depth=0
        for j in range(i, len(s)):
            if s[j]=='{': depth+=1
            elif s[j]=='}':
                depth-=1
                if depth==0:
                    return j
        return -1
    close = find_matching(text, open_idx)
    if close==-1:
        return []
    block = text[open_idx:close+1]
    # find top-level elements inside block: each is a table { ... }, parse event/time and data
    events = []
    i = 1
    while i < len(block)-1:
        if block[i] == '{':
            j = find_matching(block, i)
            if j==-1: break
            item = block[i:j+1]
            # extract event and time
            ev = re.search(r'\["event"\]\s*=\s*"([^"]+)"', item)
            tm = re.search(r'\["time"\]\s*=\s*([\d\.]+)', item)
            data_m = re.search(r'\["data"\]\s*=\s*(\{.*\})\s*,?\s*\Z', item, re.S)
            # if data_m fails, try to capture smaller
            data_text = None
            # crude: try to find data = { ... } within item
            dm = re.search(r'\["data"\]\s*=\s*\{', item)
            if dm:
                open_d = item.find('{', dm.start())
                close_d = find_matching(item, open_d)
                if close_d!=-1:
                    data_text = item[open_d:close_d+1]
            entry = {'event': ev.group(1) if ev else None, 'time': float(tm.group(1)) if tm else None}
            # try to convert data_text to json-ish
            if data_text:
                data_json = lua_table_to_json(data_text)
                # try load
                try:
                    dj = json.loads(data_json)
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

ndjf = OUT / 'logger_dump.ndjson'
with ndjf.open('w', encoding='utf-8') as fh:
    for ev in logger_events:
        fh.write(json.dumps(ev, ensure_ascii=False) + '\n')
print('wrote', ndjf)

# heuristics and aliases and adapters

def extract_simple_table(text, key):
    m = re.search(rf'\["{re.escape(key)}"\]\s*=\s*\{{', text)
    if not m: return None
    start = m.end()-1
    # find matching brace
    def find_matching(s,i):
        depth=0
        for j in range(i, len(s)):
            if s[j]=='{': depth+=1
            elif s[j]=='}':
                depth-=1
                if depth==0: return j
        return -1
    close = find_matching(text, start)
    if close==-1: return None
    block = text[start:close+1]
    # simple arrays of strings: detect "..."
    arr = re.findall(r'"([^"]+)"', block)
    if arr:
        return arr
    # else convert to JSON and load
    jtxt = lua_table_to_json(block)
    try:
        return json.loads(jtxt)
    except Exception:
        return block

adapters = extract_simple_table(s, 'adapters')
(adapters_file := OUT / 'adapters.json').write_text(json.dumps(adapters, indent=2, ensure_ascii=False))
print('wrote adapters.json')

# heuristics
m = re.search(r'\["heuristics"\]\s*=\s*\{', s)
heur = {}
if m:
    # capture until matching brace
    start = m.end()-1
    def find_matching(s,i):
        depth=0
        for j in range(i, len(s)):
            if s[j]=='{': depth+=1
            elif s[j]=='}':
                depth-=1
                if depth==0: return j
        return -1
    close = find_matching(s, start)
    block = s[start:close+1]
    # find each top-level key within heuristics
    for m2 in re.finditer(r'\["([^\"]+)"\]\s*=\s*\{', block):
        k = m2.group(1)
        open_idx = m2.end()-1
        close_idx = find_matching(block, open_idx)
        entry_block = block[open_idx:close_idx+1]
        # extract fields
        fields = re.findall(r'\["([^\"]+)"\]\s*=\s*("[^"]*"|[\d\.]+|nil|true|false)', entry_block)
        d = {}
        for kk,vv in fields:
            if vv.startswith('"'):
                d[kk]=vv[1:-1]
            elif vv=='nil':
                d[kk]=None
            elif vv=='true':
                d[kk]=True
            elif vv=='false':
                d[kk]=False
            else:
                d[kk]=float(vv) if '.' in vv else int(vv)
        heur[k]=d

(OUT / 'heuristics.json').write_text(json.dumps(heur, indent=2, ensure_ascii=False))
print('wrote heuristics.json')

# aliases
m = re.search(r'\["aliases"\]\s*=\s*\{', s)
aliases = {}
if m:
    start = m.end()-1
    def find_matching(s,i):
        depth=0
        for j in range(i, len(s)):
            if s[j]=='{': depth+=1
            elif s[j]=='}':
                depth-=1
                if depth==0: return j
        return -1
    close = find_matching(s, start)
    block = s[start:close+1]
    pairs = re.findall(r'\["([^\"]+)"\]\s*=\s*"([^"]*)"', block)
    for k,v in pairs:
        aliases[k]=v

(OUT / 'aliases.json').write_text(json.dumps(aliases, indent=2, ensure_ascii=False))
print('wrote aliases.json')

# bgExport and bgExportChunks
if '"bgExport"' in s or '["bgExportChunks"]' in s:
    # crude extraction: find bgExportChunks block if present
    if '["bgExportChunks"]' in s:
        m = re.search(r'\["bgExportChunks"\]\s*=\s*\{', s)
        if m:
            start = m.end()-1
            def find_matching(s,i):
                depth=0
                for j in range(i, len(s)):
                    if s[j]=='{': depth+=1
                    elif s[j]=='}':
                        depth-=1
                        if depth==0: return j
                return -1
            close = find_matching(s, start)
            block = s[start:close+1]
            # find top-level chunks which are strings possibly with newlines escaped
            chunks = re.findall(r'"([\s\S]*?)"\s*,?', block)
            # write each chunk
            chdir = OUT / 'bgchunks'
            chdir.mkdir(exist_ok=True)
            for i,ch in enumerate(chunks):
                (chdir / f'chunk_{i}.ndjson').write_text(ch.encode('utf-8').decode('unicode_escape'))
            print('wrote bgchunks:', len(chunks))

# Dump full parsed if possible
if full:
    (OUT / 'full_parsed.json').write_text(json.dumps(full, indent=2, ensure_ascii=False))
    print('wrote full_parsed.json')

print('done')
