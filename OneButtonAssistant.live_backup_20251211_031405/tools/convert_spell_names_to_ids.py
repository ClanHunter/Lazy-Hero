#!/usr/bin/env python3
"""
convert_spell_names_to_ids.py

Simple migration helper to replace quoted spell names in `OneButtonAssistant_engine.lua`
with numeric IDs provided by the user. This tool makes backups and supports a dry-run.

Usage:
  python tools/convert_spell_names_to_ids.py --mapping spells.csv --file ../OneButtonAssistant_engine.lua

Mapping CSV format (no header):
  "Spell Name",12345
  "Another Spell",67890

Notes:
 - This script performs simple textual substitution: it replaces occurrences of the
   exact quoted spell name (e.g. "Flame Shock") with the numeric literal 12345.
 - It makes a backup copy of the target file as <file>.bak before modifying.
 - Review changes (or use --dry-run) before committing to source control.
"""
import argparse
import csv
import json
import os
import re
import shutil
import sys


def load_mapping_csv(path):
    mapping = {}
    with open(path, newline='', encoding='utf-8') as fh:
        reader = csv.reader(fh)
        for row in reader:
            if not row: continue
            name = row[0].strip()
            if len(row) > 1:
                try:
                    sid = int(row[1])
                except Exception:
                    sid = None
            else:
                sid = None
            if name and sid:
                mapping[name] = sid
    return mapping


def replace_in_file(file_path, mapping, dry_run=False):
    with open(file_path, 'r', encoding='utf-8') as fh:
        text = fh.read()

    new_text = text
    replacements = []
    # Replace occurrences of quoted spell names: "Spell Name"
    for name, sid in mapping.items():
        # match exact quoted string, allow single or double quotes in file
        for q in ('"', "'"):
            pattern = re.escape(q) + re.escape(name) + re.escape(q)
            # Replace with numeric literal (no quotes)
            new_text, count = re.subn(pattern, str(sid), new_text)
            if count:
                replacements.append((name, sid, count))

    if dry_run:
        return replacements, None

    # Backup
    bak_path = file_path + '.bak'
    shutil.copyfile(file_path, bak_path)
    with open(file_path, 'w', encoding='utf-8') as fh:
        fh.write(new_text)
    return replacements, bak_path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--mapping', required=True, help='CSV file with mapping: "Spell Name",id')
    parser.add_argument('--file', required=True, help='Target Lua file to modify')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args()

    if not os.path.exists(args.mapping):
        print('Mapping file not found:', args.mapping)
        sys.exit(2)
    if not os.path.exists(args.file):
        print('Target file not found:', args.file)
        sys.exit(2)

    mapping = load_mapping_csv(args.mapping)
    if not mapping:
        print('No valid mappings found in', args.mapping)
        sys.exit(2)

    replacements, bak = replace_in_file(args.file, mapping, dry_run=args.dry_run)
    if not replacements:
        print('No occurrences replaced.')
    else:
        print('Replacements:')
        for name, sid, count in replacements:
            print('  %s -> %s (count=%d)' % (name, sid, count))
        if bak:
            print('Backup created at', bak)
    if args.dry_run:
        print('Dry-run complete. No files changed.')


if __name__ == '__main__':
    main()
