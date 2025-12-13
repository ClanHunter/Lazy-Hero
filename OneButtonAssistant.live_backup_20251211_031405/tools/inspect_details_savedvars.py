#!/usr/bin/env python3
"""
Lightweight inspector for Details addon SavedVariables.

Usage:
    python tools/inspect_details_savedvars.py --file ./OneButtonAssistant/savedvars/Details.lua

This script heuristically extracts the first large Lua table literal from the file,
performs conservative Lua->JSON-like transformations, and prints top-level keys
and simple metrics (counts for lists/tables). It is intended for quick inspection
so we can decide what exact metrics to extract next.
"""
import argparse
import re
import json
import sys


def find_first_table_block(s):
    # Find the first '=' followed by '{' that likely starts the big DB table
    m = re.search(r'=\s*{', s)
    if not m:
        return None
    start = m.start() + s[m.start():].find('{')
    # find matching brace
    depth = 0
    i = start
    while i < len(s):
        if s[i] == '{':
            depth += 1
        elif s[i] == '}':
            depth -= 1
            if depth == 0:
                return s[start:i+1]
        i += 1
    return None


def lua_to_json_like(t):
    # Remove Lua comments
    t = re.sub(r'--.*?\n', '\n', t)
    # Convert Lua boolean/nil
    t = t.replace('nil', 'null')
    t = t.replace('true', 'true').replace('false', 'false')
    # Quote bare keys: key = -> "key":
    t = re.sub(r'([\w_\-]+)\s*=\s*', r'"\1": ', t)
    # Convert ['key'] or ["key"] = -> "key":
    t = re.sub(r"\[\s*'([^']+)'\s*\]\s*=", r'"\1":', t)
    t = re.sub(r'\[\s*"([^\"]+)"\s*\]\s*=', r'"\1":', t)
    # Replace = between arrays like [1] = { ... }
    t = re.sub(r'\[\s*(\d+)\s*\]\s*=', r'"\1":', t)
    # Remove Lua table constructors for keyless arrays: convert { a, b, c } -> [a,b,c]
    # This is hard; we will attempt a conservative approach: replace top-level occurrences later.
    # Ensure true/false are lowercase for JSON
    t = re.sub(r'\btrue\b', 'true', t)
    t = re.sub(r'\bfalse\b', 'false', t)
    # Remove trailing commas before closing braces/brackets
    t = re.sub(r',\s*([}\]])', r'\1', t)
    return t


def try_parse_block(block):
    jtext = lua_to_json_like(block)
    # Attempt to replace Lua-style single-quoted strings to double-quoted
    jtext = re.sub(r"'([^']*)'", lambda m: json.dumps(m.group(1)), jtext)
    # Ensure double-quoted strings are valid JSON
    # Finally, try to load
    try:
        obj = json.loads(jtext)
        return obj
    except Exception as e:
        return None


def summarize(obj, depth=1):
    if isinstance(obj, dict):
        for k in sorted(obj.keys()):
            v = obj[k]
            t = type(v).__name__
            if isinstance(v, dict):
                print(f'- {k}: table with {len(v)} keys')
            elif isinstance(v, list):
                print(f'- {k}: list of {len(v)} items')
            else:
                print(f'- {k}: {t}')
    else:
        print('Top-level is not a table/dict; parsed type:', type(obj))


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--file', '-f', required=True, help='Path to Details savedvars file (.lua)')
    args = p.parse_args()

    with open(args.file, 'r', encoding='utf-8', errors='ignore') as fh:
        s = fh.read()

    block = find_first_table_block(s)
    if not block:
        print('Could not find a Lua table block in the file. Please provide a Details.lua or Details_Streamer.lua file with saved data.')
        sys.exit(2)

    obj = try_parse_block(block)
    if obj is None:
        # fallback: write the cleaned block for manual inspection
        cleaned = lua_to_json_like(block)
        out = './OneButtonAssistant/patches/details_extracted_block.txt'
        with open(out, 'w', encoding='utf-8') as fo:
            fo.write(cleaned)
        print('Failed to parse the Lua block as JSON. A cleaned block has been written to', out)
        print('Please inspect or paste the cleaned file so I can refine the parser.')
        sys.exit(3)

    print('Top-level keys and simple metrics:')
    summarize(obj)

    # If common Details keys exist, show quick stats
    for key in ('segments_added', 'segments', 'tabela_historico', 'raid_roster', 'total'):
        if key in obj:
            v = obj[key]
            if isinstance(v, list):
                print(f'Quick: {key} -> {len(v)} items')
            elif isinstance(v, dict):
                print(f'Quick: {key} -> {len(v.keys())} keys')


if __name__ == '__main__':
    main()
