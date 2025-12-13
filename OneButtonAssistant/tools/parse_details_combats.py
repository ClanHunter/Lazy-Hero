#!/usr/bin/env python3
"""
Extract per-combat actor totals and segment summaries from the cleaned Details savedvars block.

This script uses conservative regex scanning of the cleaned text (`details_extracted_block.txt`) to
find actor `name` + nearby `total` values and segment `name` + `elapsed` values. It writes CSVs to
`OneButtonAssistant/patches/`:
- `details_actors_totals.csv` (actor name, total)
- `details_segments.csv` (segment name, elapsed)

This is heuristics-first (not a full Lua parser) but works well on typical Details SavedVariables text dumps.
"""
import re
from pathlib import Path
import csv

infile = Path('OneButtonAssistant/patches/details_extracted_block.txt')
outdir = Path('OneButtonAssistant/patches')
text = infile.read_text(encoding='utf-8')

def extract_actor_totals(t, window=800):
    # Find all occurrences of "name": "..." and look ahead for a "total": number
    actors = {}
    for m in re.finditer(r'"name"\s*:\s*"([^"]+)"', t):
        name = m.group(1)
        start = m.end()
        snippet = t[start:start+window]
        tm = re.search(r'"total"\s*:\s*([0-9]+(?:\.[0-9]+)?)', snippet)
        if tm:
            total = float(tm.group(1))
            # keep the maximum total seen for the name (some names appear multiple times across combats)
            actors[name] = max(actors.get(name, 0.0), total)
    return actors

def extract_segments(t):
    segments = []
    # look for patterns with name and elapsed/duration
    for m in re.finditer(r'"name"\s*:\s*"([^"]+)"[\s\S]{0,200}?"elapsed"\s*:\s*([0-9]+(?:\.[0-9]+)?)', t):
        segments.append((m.group(1), float(m.group(2))))
    # also try alternate key 'total' as duration where 'elapsed' absent
    if not segments:
        for m in re.finditer(r'"name"\s*:\s*"([^"]+)"[\s\S]{0,200}?"total"\s*:\s*([0-9]+(?:\.[0-9]+)?)', t):
            segments.append((m.group(1), float(m.group(2))))
    return segments

actors = extract_actor_totals(text)
segments = extract_segments(text)

print('Found actors:', len(actors))
print('Found segments:', len(segments))

# Write actors CSV
if actors:
    with open(outdir / 'details_actors_totals.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['name','total'])
        for name, total in sorted(actors.items(), key=lambda kv: -kv[1]):
            w.writerow([name, ('%.2f' % total)])

# Write segments CSV
if segments:
    with open(outdir / 'details_segments.csv', 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['segment_name','elapsed'])
        for name, elapsed in segments:
            w.writerow([name, ('%.2f' % elapsed)])

print('Wrote CSVs to', outdir)
