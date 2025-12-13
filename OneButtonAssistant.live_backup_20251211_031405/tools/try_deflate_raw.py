#!/usr/bin/env python3
import base64, zlib, gzip
from pathlib import Path

raws = []
inp = Path('OneButtonAssistant/patches/details_import_string.txt').read_text(encoding='utf-8', errors='ignore')

# candidate mapping
s = inp.replace('(', '+').replace(')', '/')
filtered = ''.join(ch for ch in s if ch in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')
try:
    b = base64.b64decode(filtered)
    raws.append(('mapped_parens', b))
except Exception as e:
    print('base64 decode failed:', e)

try:
    b2 = base64.b64decode(''.join(ch for ch in inp if ch in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/='))
    raws.append(('filtered_only', b2))
except Exception:
    pass

out = Path('OneButtonAssistant/patches/details_deflate_attempts.txt')
with out.open('w', encoding='utf-8') as fh:
    for tag,b in raws:
        fh.write(f'--- RAW {tag} len={len(b)} ---\n')
        # try zlib with various wbits
        for w in [15, 31, -15]:
            try:
                dec = zlib.decompress(b, w)
                fh.write(f'zlib(wbits={w}) success, len={len(dec)}\n')
                try:
                    fh.write('text-snippet: ' + dec.decode('utf-8', errors='replace')[:2000].replace('\n','\\n') + '\n')
                except Exception:
                    fh.write('binary decode failed\n')
            except Exception as e:
                fh.write(f'zlib(wbits={w}) fail: {e}\n')
        # try gzip
        try:
            dec = gzip.decompress(b)
            fh.write(f'gzip success len={len(dec)}\n')
            fh.write('text-snippet: ' + dec.decode('utf-8', errors='replace')[:2000].replace('\n','\\n') + '\n')
        except Exception as e:
            fh.write(f'gzip fail: {e}\n')

print('Wrote', out)
