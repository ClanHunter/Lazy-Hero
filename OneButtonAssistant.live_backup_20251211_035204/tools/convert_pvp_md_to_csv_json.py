#!/usr/bin/env python3
"""
convert_pvp_md_to_csv_json.py

Parses `WAR_WITHIN_QuickRef_PvP.md` (simple Markdown table) and exports CSV and JSON
for programmatic use.

Usage:
  python tools/convert_pvp_md_to_csv_json.py --input ../WAR_WITHIN_QuickRef_PvP.md --csv outputs/pvp_quickref.csv --json outputs/pvp_quickref.json

This script performs a table parse; it expects a single table in the Markdown file.
"""
import argparse
import csv
import json
import os
import re
import sys


def parse_markdown_table(md_text):
    # find the first table block (start with | Class | ...)
    lines = md_text.splitlines()
    table_lines = []
    in_table = False
    for ln in lines:
        if ln.strip().startswith('|'):
            table_lines.append(ln)
            in_table = True
        else:
            if in_table:
                break
    if not table_lines:
        return None
    # remove leading/trailing separators
    header = table_lines[0]
    sep = table_lines[1] if len(table_lines) > 1 else ''
    rows = table_lines[2:]

    def split_row(r):
        parts = [c.strip() for c in r.strip().strip('|').split('|')]
        return parts

    headers = split_row(header)
    data = []
    for r in rows:
        if not r.strip().startswith('|'): continue
        parts = split_row(r)
        # pad parts to header length
        while len(parts) < len(headers): parts.append('')
        row = dict(zip(headers, parts))
        data.append(row)
    return headers, data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True)
    parser.add_argument('--csv', required=True)
    parser.add_argument('--json', required=True)
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print('Input not found:', args.input)
        sys.exit(2)
    with open(args.input, 'r', encoding='utf-8') as fh:
        md = fh.read()

    parsed = parse_markdown_table(md)
    if not parsed:
        print('Failed to locate table in', args.input)
        sys.exit(2)
    headers, data = parsed

    os.makedirs(os.path.dirname(args.csv), exist_ok=True)
    with open(args.csv, 'w', newline='', encoding='utf-8') as fh:
        writer = csv.DictWriter(fh, fieldnames=headers)
        writer.writeheader()
        for row in data:
            writer.writerow(row)
    print('Wrote CSV:', args.csv)

    os.makedirs(os.path.dirname(args.json), exist_ok=True)
    with open(args.json, 'w', encoding='utf-8') as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    print('Wrote JSON:', args.json)


if __name__ == '__main__':
    main()
