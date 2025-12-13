#!/usr/bin/env python3
import base64, binascii, gzip, zlib, bz2, lzma, math
from pathlib import Path

inp = Path('OneButtonAssistant/patches/details_import_string.txt').read_text(encoding='utf-8', errors='ignore').strip()
out = Path('OneButtonAssistant/patches/details_import_analysis.txt')

def entropy(b):
    if not b:
        return 0.0
    freq = {}
    for x in b:
        freq[x] = freq.get(x,0)+1
    ent = 0.0
    L = len(b)
    for v in freq.values():
        p = v / L
        ent -= p * math.log2(p)
    return ent

report = []
report.append(f'length_chars: {len(inp)}')
report.append(f'chars_sample: {inp[:200]!r}')

# Check base64-ish
try:
    b = base64.b64decode(inp, validate=True)
    report.append('base64: valid')
    report.append(f'base64_decoded_len: {len(b)}')
    report.append(f'base64_entropy: {entropy(b):.4f} bits/byte')
    # try decompressions
    for name,fn in [('gzip', gzip.decompress), ('zlib', zlib.decompress), ('bz2', bz2.decompress), ('lzma', lzma.decompress)]:
        try:
            dec = fn(b)
            report.append(f'decompressed_with_{name}: success, len={len(dec)}')
            try:
                s = dec.decode('utf-8')
                report.append(f'decompressed_{name}_text_snippet: {s[:400]!r}')
            except Exception:
                report.append(f'decompressed_{name}_bin_preview: {dec[:100]!r}')
        except Exception as e:
            report.append(f'decompressed_with_{name}: fail ({e})')
except binascii.Error:
    report.append('base64: invalid')
except Exception as e:
    report.append(f'base64: error {e}')

# Check if hex
try:
    hb = bytes.fromhex(inp)
    report.append('hex: valid')
    report.append(f'hex_len: {len(hb)}')
    report.append(f'hex_entropy: {entropy(hb):.4f} bits/byte')
except Exception:
    report.append('hex: invalid')

# Try raw decompression attempts of the raw bytes of the text
raw = inp.encode('utf-8', errors='ignore')
report.append(f'raw_entropy: {entropy(raw):.4f} bits/byte')
for name,fn in [('gzip', gzip.decompress), ('zlib', zlib.decompress), ('bz2', bz2.decompress), ('lzma', lzma.decompress)]:
    try:
        dec = fn(raw)
        report.append(f'raw_decompressed_with_{name}: success len={len(dec)}')
    except Exception as e:
        report.append(f'raw_decompressed_with_{name}: fail ({e})')

out.write_text('\n'.join(report), encoding='utf-8')
print('Wrote analysis to', out)
