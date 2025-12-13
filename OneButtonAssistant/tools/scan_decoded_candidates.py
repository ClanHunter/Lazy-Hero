#!/usr/bin/env python3
"""Scan the saved Details export string with several mapping heuristics
and print any long printable ASCII runs found in the decoded byte outputs.

Usage: python OneButtonAssistant/tools/scan_decoded_candidates.py
"""
import base64
import re
from collections import Counter
from pathlib import Path


def load_input():
    p = Path('OneButtonAssistant/patches/details_import_string.txt')
    if not p.exists():
        print('File not found:', p)
        raise SystemExit(1)
    return p.read_text(encoding='utf-8', errors='ignore').strip()


BASE64_ALLOWED = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')


def base64_filter(s):
    return ''.join(ch for ch in s if ch in BASE64_ALLOWED)


def try_map_and_decode(s, mapping):
    t = s
    for a, b in mapping.items():
        t = t.replace(a, b)
    filt = base64_filter(t)
    try:
        return base64.b64decode(filt)
    except Exception:
        return None


def find_printable_runs(b, min_len=20):
    if not b:
        return []
    # Replace non-printable with newline, then find runs of printable ASCII
    t = ''.join(chr(x) if 32 <= x <= 126 else '\n' for x in b)
    return re.findall(r'[ -~]{%d,}' % min_len, t)


def main():
    s = load_input()

    # small set of obvious maps
    candidate_maps = [
        {'(': '+', ')': '/'},
        {'(': '/', ')': '+'},
        {'[': '+', ']': '/'},
        {'{': '+', '}': '/'},
        {')': '+', '(': '/'},
    ]

    # frequency-based map (map most-frequent chars to base64 alphabet)
    cnt = Counter(s)
    top_chars = [c for c, _ in cnt.most_common(64)]
    base64_alphabet = list('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
    freq_map = {top_chars[i]: base64_alphabet[i] for i in range(min(len(top_chars), 64))}
    candidate_maps.append(freq_map)

    print('Trying', len(candidate_maps), 'mapping candidates')
    for i, m in enumerate(candidate_maps):
        b = try_map_and_decode(s, m)
        if b is None:
            print('\nMAP', i, ' -> base64 decode failed')
            continue
        runs = find_printable_runs(b, min_len=20)
        print('\nMAP', i, 'decoded bytes:', len(b), 'printable-runs:', len(runs))
        for r in runs[:10]:
            print('  RUN:', r[:400])
        # show a hexdump-ish prefix for inspection
        print('  prefix repr:', repr(b[:200]))


if __name__ == '__main__':
    main()
