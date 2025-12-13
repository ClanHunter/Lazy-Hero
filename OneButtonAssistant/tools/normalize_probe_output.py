#!/usr/bin/env python3
"""
normalize_probe_output.py

Enhanced normalizer:
- Maps `spellName` -> `spellId` using `inputs/enhancement_shaman_spells.csv` and `inputs/spells.csv`.
- Optionally hashes GUIDs using a provided salt (or salt extracted from a SavedVariables file).
- Optionally extracts position data when present.
- Produces:
  - NDJSON of normalized events (`--output`)
  - A deduplicated manifest JSON (`--manifest`) with counts, first/last seen, and examples.

Usage examples:
  python tools/normalize_probe_output.py --input OneButtonAssistant/probe_output.lua --output OneButtonAssistant/patches/probe_output_normalized.ndjson --manifest OneButtonAssistant/patches/probe_output_manifest.json --hash-guid --salt mysecret --include-positions

If `--savedvars PATH` is given, the script will attempt to extract `OneButtonAssistantDB` and use `bgSalt` from it as the GUID salt.
"""

import re
import csv
import json
import sys
import argparse
import hashlib
import html
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_IN = ROOT / "probe_output.lua"
DEFAULT_OUT = ROOT / "patches" / "probe_output_normalized.ndjson"
DEFAULT_MANIFEST = ROOT / "patches" / "probe_output_manifest.json"


def load_mappings():
	mapping = {}
	enh = ROOT / "inputs" / "enhancement_shaman_spells.csv"
	if enh.exists():
		with enh.open(encoding='utf-8') as fh:
			rdr = csv.DictReader(fh)
			for row in rdr:
				name = (row.get('SpellName') or row.get('Spell') or '').strip()
				sid = (row.get('SpellID') or row.get('ID') or '').strip()
				if name and sid:
					try:
						mapping[name] = int(sid)
					except:
						pass
	spells_csv = ROOT / "inputs" / "spells.csv"
	if spells_csv.exists():
		with spells_csv.open(encoding='utf-8') as fh:
			rdr = csv.reader(fh)
			for row in rdr:
				if not row: continue
				if len(row) >= 2:
					n = row[0].strip().strip('"')
					sid = row[1].strip()
					try:
						sidv = int(sid)
					except:
						continue
					if n.lower().startswith('spell:'):
						continue
					mapping[n] = sidv
	return mapping


def extract_savedvars(savedvars_path: Path):
	"""Try to extract OneButtonAssistantDB table and bgSalt from a SavedVariables Lua file.
	This is a best-effort heuristic parser (not a full Lua interpreter).
	Returns dict with any found keys.
	"""
	data = {}
	try:
		text = savedvars_path.read_text(encoding='utf-8')
	except Exception:
		return data

	# find bgSalt = "..."
	m = re.search(r'bgSalt\s*=\s*"([^"]+)"', text)
	if m:
		data['bgSalt'] = m.group(1)

	# attempt to find SpellSpy table entries: OneButtonAssistantDB = { SpellSpy = { ... } }
	m2 = re.search(r'OneButtonAssistantDB\s*=\s*({.+?\n})', text, re.S)
	if m2:
		snippet = m2.group(1)
		# rudimentary find of SpellSpy table
		sp = re.search(r'SpellSpy\s*=\s*({.+?})', snippet, re.S)
		if sp:
			# try to find bgSalt inside SpellSpy meta
			mb = re.search(r'bgSalt\s*=\s*"([^"]+)"', sp.group(1))
			if mb:
				data['bgSalt'] = mb.group(1)
	return data


def hash_guid(guid: str, salt: str) -> str:
	if guid is None:
		return None
	h = hashlib.sha256()
	h.update((salt or "").encode('utf-8'))
	h.update(guid.encode('utf-8'))
	return h.hexdigest()


def parse_probe_file(path: Path, mapping: dict, output_path: Path, manifest_path: Path, hash_guid_flag=False, salt=None, include_positions=False, savedvars=None):
	text = path.read_text(encoding='utf-8')

	# Find occurrences of spellName entries and capture a window of surrounding text
	pattern = re.compile(r'(\{[^}]{0,3000}?\})', re.S)
	# fallback: match lines with ["spellName"] = "Name"
	name_pattern = re.compile(r'\[\s*"spellName"\s*\]\s*=\s*"([^"]+)"', re.IGNORECASE)

	events = []

	# try to parse explicit tables first
	for m in pattern.finditer(text):
		chunk = m.group(1)
		nm = name_pattern.search(chunk)
		if nm:
			name = html.unescape(nm.group(1))
			evt = { 'spellName': name }
			# try to find spellId nearby
			sidm = re.search(r'\[\s*"spellId"\s*\]\s*=\s*(%d+)', chunk)
			if sidm:
				evt['spellId'] = int(sidm.group(1))
			else:
				sid = mapping.get(name)
				if sid:
					evt['spellId'] = sid
			# try to extract GUIDs
			g = None
			gm = re.search(r'GUID["\']?\s*\]?\s*[:=]\s*["\']?([0-9A-Fa-f:-]+)["\']?', chunk)
			if not gm:
				gm = re.search(r'srcGUID\s*\]\s*=\s*"([^"]+)"', chunk)
			if gm:
				g = gm.group(1)
				if hash_guid_flag and salt is not None:
					evt['guidHash'] = hash_guid(g, salt)
				else:
					evt['guid'] = g
			# positions
			if include_positions:
				xm = re.search(r'posX\s*\]\s*=\s*([0-9\.\-]+)', chunk)
				ym = re.search(r'posY\s*\]\s*=\s*([0-9\.\-]+)', chunk)
				if xm and ym:
					try:
						evt['pos'] = { 'x': float(xm.group(1)), 'y': float(ym.group(1)) }
					except:
						pass

			# timestamps
			tm = re.search(r'timestamp\s*\]\s*=\s*([0-9\.]+)', chunk)
			if tm:
				try:
					evt['timestamp'] = float(tm.group(1))
				except:
					pass

			events.append(evt)

	# As fallback, search for spellName lines and capture nearby context
	if not events:
		for m in name_pattern.finditer(text):
			name = html.unescape(m.group(1))
			start = max(0, m.start()-200)
			end = min(len(text), m.end()+200)
			window = text[start:end]
			evt = { 'spellName': name }
			sid = mapping.get(name)
			if sid:
				evt['spellId'] = sid
			gm = re.search(r'srcGUID\s*\]\s*=\s*"([^"]+)"', window)
			if gm:
				g = gm.group(1)
				if hash_guid_flag and salt is not None:
					evt['guidHash'] = hash_guid(g, salt)
				else:
					evt['guid'] = g
			if include_positions:
				xm = re.search(r'posX\s*\]\s*=\s*([0-9\.\-]+)', window)
				ym = re.search(r'posY\s*\]\s*=\s*([0-9\.\-]+)', window)
				if xm and ym:
					try:
						evt['pos'] = { 'x': float(xm.group(1)), 'y': float(ym.group(1)) }
					except:
						pass
			events.append(evt)

	# write NDJSON and build manifest
	manifest = {}
	counts = defaultdict(int)
	first_seen = {}
	last_seen = {}
	examples = defaultdict(list)

	output_path.parent.mkdir(parents=True, exist_ok=True)
	with output_path.open('w', encoding='utf-8') as out:
		for evt in events:
			name = evt.get('spellName')
			sid = evt.get('spellId')
			ts = evt.get('timestamp') or None
			key = f"{sid or 'name:'+name}"
			counts[key] += 1
			if ts:
				if key not in first_seen or ts < first_seen[key]:
					first_seen[key] = ts
				if key not in last_seen or ts > last_seen[key]:
					last_seen[key] = ts
			if len(examples[key]) < 5:
				examples[key].append(evt)
			out.write(json.dumps(evt, ensure_ascii=False) + "\n")

	for k in counts:
		manifest[k] = {
			'count': counts[k],
			'first_seen': first_seen.get(k),
			'last_seen': last_seen.get(k),
			'examples': examples[k]
		}

	manifest_path.parent.mkdir(parents=True, exist_ok=True)
	manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
	return output_path, manifest_path


def main(argv=None):
	p = argparse.ArgumentParser()
	p.add_argument('--input', '-i', default=str(DEFAULT_IN))
	p.add_argument('--output', '-o', default=str(DEFAULT_OUT))
	p.add_argument('--manifest', '-m', default=str(DEFAULT_MANIFEST))
	p.add_argument('--hash-guid', action='store_true', help='Hash GUIDs for privacy')
	p.add_argument('--salt', default=None, help='Salt to use for GUID hashing')
	p.add_argument('--include-positions', action='store_true', help='Extract position fields if present')
	p.add_argument('--savedvars', default=None, help='Path to a SavedVariables file to extract bgSalt')
	args = p.parse_args(argv)

	inp = Path(args.input)
	out = Path(args.output)
	manifest = Path(args.manifest)

	mapping = load_mappings()

	salt = args.salt
	if args.savedvars:
		sv = Path(args.savedvars)
		if sv.exists():
			svdata = extract_savedvars(sv)
			if 'bgSalt' in svdata and not salt:
				salt = svdata['bgSalt']

	if not inp.exists():
		print(f"Input file {inp} not found.")
		return 2

	outp, mpath = parse_probe_file(inp, mapping, out, manifest, hash_guid_flag=args.hash_guid, salt=salt, include_positions=args.include_positions, savedvars=args.savedvars)
	print(f"Wrote normalized NDJSON to: {outp}")
	print(f"Wrote manifest JSON to: {mpath}")
	return 0


if __name__ == '__main__':
	raise SystemExit(main())

