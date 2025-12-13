#!/usr/bin/env python3
"""
Try to decode a Details export string using several likely substitution rules
and common decoding pipelines (base64 -> zlib/gzip/brotli). This is heuristic
and will try small sets of character maps commonly seen in addon export encodings.

Writes results to `OneButtonAssistant/patches/details_decode_attempts.txt`.
"""
import base64, binascii, zlib, gzip
from pathlib import Path
import itertools

inp = Path('OneButtonAssistant/patches/details_import_string.txt').read_text(encoding='utf-8', errors='ignore').strip()
outf = Path('OneButtonAssistant/patches/details_decode_attempts.txt')

def try_base64_and_decompress(s):
    res = []
    try:
        b = base64.b64decode(s, validate=True)
    except Exception:
        return res
    res.append(('base64_decode_len', len(b)))
    # try gzip
    try:
        dec = gzip.decompress(b)
        res.append(('gzip', dec[:1000]))
        return res
    except Exception:
        pass
    # try zlib
    try:
        dec = zlib.decompress(b)
        res.append(('zlib', dec[:1000]))
        return res
    except Exception:
        pass
    # no decompress
    res.append(('raw', b[:1000]))
    return res

def run_attempts():
    reports = []
    # Candidate small substitution maps: map some punctuation to base64 +/
    candidates = [
        { '(': '+', ')': '/' },
        { '(': '/', ')': '+' },
        { '[': '+', ']': '/' },
        { '{': '+', '}': '/' },
        { '(': '+', ')': '/', '[': '-', ']': '_' },
    ]
    # Also try removing characters not in base64 alphabet
    base64_alphabet = set('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')

    # First try raw base64 decode
    reports.append(('raw_input_try', try_base64_and_decompress(inp)))

    for cmap in candidates:
        s = inp
        for a,b in cmap.items():
            s = s.replace(a,b)
        # strip any characters not in base64 alphabet
        s_filtered = ''.join(ch for ch in s if ch in base64_alphabet)
        reports.append((f'map_{cmap}', try_base64_and_decompress(s_filtered)))

    # Try mapping by replacing all parentheses with base64 padding alternatives
    s_alt = inp.replace('(', '+').replace(')', '/')
    s_filtered = ''.join(ch for ch in s_alt if ch in base64_alphabet)
    reports.append(("map_parens_to_plus_slash", try_base64_and_decompress(s_filtered)))

    # Frequency-based map: take the 64 most frequent chars and map to base64 alphabet
    freq = {}
    for ch in inp:
        freq[ch] = freq.get(ch,0) + 1
    sorted_chars = sorted(freq.items(), key=lambda kv: -kv[1])
    top_chars = [c for c,_ in sorted_chars[:64]]
    base64_chars = list('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/')
    if len(top_chars) >= 20:
        trans = {top_chars[i]: base64_chars[i] for i in range(min(len(top_chars),64))}
        s = ''.join(trans.get(ch, '') for ch in inp)
        reports.append(('freq_top64_map', try_base64_and_decompress(s)))

    # Write report
    with outf.open('w', encoding='utf-8') as fh:
        for tag, out in reports:
            fh.write(f'--- ATTEMPT {tag} ---\n')
            if not out:
                fh.write('no result\n')
                continue
            for item in out:
                fh.write(f'{item[0]}: ')
                if isinstance(item[1], (bytes, bytearray)):
                    try:
                        txt = item[1].decode('utf-8')
                        fh.write('text: ' + txt[:1000].replace('\n','\\n'))
                    except Exception:
                        fh.write('bytes: ' + repr(item[1][:200]))
                else:
                    fh.write(repr(item[1]))
                fh.write('\n')
    print('Wrote attempts to', outf)

if __name__ == '__main__':
    run_attempts()
