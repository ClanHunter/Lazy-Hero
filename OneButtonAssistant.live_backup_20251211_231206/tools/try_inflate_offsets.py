#!/usr/bin/env python3
"""Try to find embedded compressed streams (gzip/zlib/deflate) inside
decoded candidate byte sequences and attempt to decompress them from offsets.

This will re-run a few mapping heuristics (same as the scanner) and search
for common compression headers (gzip 1f 8b, zlib 78 9c/01/da) and try
zlib.decompress with several wbits values starting at matching offsets.

Usage: python OneButtonAssistant/tools/try_inflate_offsets.py
"""
import base64
import zlib
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


def find_headers(b):
    headers = []
    for i in range(len(b)-1):
        a, c = b[i], b[i+1]
        if a == 0x1f and c == 0x8b:
            headers.append(('gzip', i))
        if a == 0x78 and c in (0x01, 0x5e, 0x9c, 0xda):
            headers.append(('zlib', i))
    return headers


def attempt_decompress_at(b, offset):
    # try gzip via zlib with wbits=16+MAX_WBITS
    tries = []
    for w in (zlib.MAX_WBITS | 16, zlib.MAX_WBITS, -zlib.MAX_WBITS, -15):
        try:
            out = zlib.decompress(b[offset:], w)
            return out, w
        except Exception as e:
            tries.append(str(e))
    return None, tries


def main():
    s = load_input()
    candidate_maps = [
        {'(': '+', ')': '/'},
        {'(': '/', ')': '+'},
        {'[': '+', ']': '/'},
        {'{': '+', '}': '/'},
        {')': '+', '(': '/'},
    ]
    cnt = Counter(s)
    top_chars = [c for c, _ in cnt.most_common(64)]
    base64_alphabet = list('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
    freq_map = {top_chars[i]: base64_alphabet[i] for i in range(min(len(top_chars), 64))}
    candidate_maps.append(freq_map)

    results = []
    for i, m in enumerate(candidate_maps):
        b = try_map_and_decode(s, m)
        if b is None:
            print('MAP', i, 'base64 decode failed')
            continue
        headers = find_headers(b)
        print('MAP', i, 'decoded len', len(b), 'headers found', len(headers))
        for kind, off in headers:
            print(' try', kind, 'at', off)
            out, info = attempt_decompress_at(b, off)
            if out is not None:
                print('  SUCCESS offset', off, 'wbits', info, 'len', len(out))
                # write to file for inspection
                Path('OneButtonAssistant/patches/details_inflated_from_map%d_offset%d.bin' % (i, off)).write_bytes(out)
                print('  -> wrote OneButtonAssistant/patches/details_inflated_from_map%d_offset%d.bin' % (i, off))
                return
            else:
                print('  failed:', info)
    print('No successful inflation found')


if __name__ == '__main__':
    main()
