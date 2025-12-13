#!/usr/bin/env python3
"""
Attempt to decode the Details export using python-libdeflate if available.

Usage:
  pip install python-libdeflate
  python tools/try_decode_with_libdeflate.py

This script tries a common character map ( '(' -> '+', ')' -> '/' ), base64-decodes,
then attempts libdeflate decompression and writes output to
`OneButtonAssistant/patches/details_libdeflate_output.txt` if successful.
"""
from pathlib import Path
import base64

inp = Path('OneButtonAssistant/patches/details_import_string.txt').read_text(encoding='utf-8', errors='ignore').strip()
outp = Path('OneButtonAssistant/patches/details_libdeflate_output.txt')

try:
    import libdeflate as ld
    libdeflate_name = 'libdeflate'
except Exception:
    try:
        import pylibdeflate as ld
        libdeflate_name = 'pylibdeflate'
    except Exception:
        print('Neither "libdeflate" nor "pylibdeflate" Python bindings found.')
        print('Try: python -m pip install --upgrade pip')
        print('Then: python -m pip install pylibdeflate')
        raise SystemExit(2)

# common mapping
s = inp.replace('(', '+').replace(')', '/')
s_filtered = ''.join(ch for ch in s if ch in 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=')
try:
    b = base64.b64decode(s_filtered)
except Exception as e:
    print('base64 decode failed:', e)
    raise SystemExit(3)

try:
    # pylibdeflate exposes a Decompressor class; libdeflate may expose different API
    decoded = None
    if libdeflate_name == 'pylibdeflate':
        d = ld.Decompressor()
        decoded = d.decompress(b)
    else:
        # try common function name
        if hasattr(ld, 'decompress'):
            decoded = ld.decompress(b)
        elif hasattr(ld, 'Decompressor'):
            d = ld.Decompressor()
            decoded = d.decompress(b)
        else:
            raise RuntimeError('libdeflate module present but no known API found')

    if decoded is None:
        raise RuntimeError('decompression returned None')

    try:
        txt = decoded.decode('utf-8')
        outp.write_text(txt, encoding='utf-8')
        print('Wrote decoded text to', outp)
    except Exception:
        outp.write_bytes(decoded)
        print('Wrote decoded binary to', outp)
except Exception as e:
    print('libdeflate decompress failed:', e)
    raise SystemExit(4)
