#!/usr/bin/env python3
"""
export_handbook.py

Convert the Markdown handbook to HTML and (optionally) PDF.

Dependencies:
  pip install markdown2 weasyprint

Usage:
  python tools/export_handbook.py --input ../WAR_WITHIN_Class_Handbook.md --out outputs/handbook.html --pdf outputs/handbook.pdf

If `weasyprint` is not available, the script will still produce HTML. PDF production requires
the `weasyprint` package and its system dependencies (cairo, pango, gdk-pixbuf).
"""
import argparse
import os
import sys

try:
    import markdown2
except Exception:
    print('Please `pip install markdown2` to use this script. HTML output will not be generated.')
    markdown2 = None

try:
    from weasyprint import HTML
except Exception:
    HTML = None


def convert_md_to_html(md_text):
    if markdown2:
        return markdown2.markdown(md_text, extras=["fenced-code-blocks"]) 
    else:
        # naive fallback
        return '<pre>' + md_text.replace('&', '&amp;').replace('<','&lt;') + '</pre>'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', required=True, help='Path to handbook Markdown')
    parser.add_argument('--out', required=True, help='Path to write HTML output')
    parser.add_argument('--pdf', help='Optional path to write PDF output')
    args = parser.parse_args()

    if not os.path.exists(args.input):
        print('Input file not found:', args.input)
        sys.exit(2)

    with open(args.input, 'r', encoding='utf-8') as fh:
        md = fh.read()

    html = convert_md_to_html(md)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, 'w', encoding='utf-8') as fh:
        fh.write('<meta charset="utf-8">\n')
        fh.write('<style>body{font-family:system-ui,Segoe UI,Arial,Helvetica,sans-serif;line-height:1.4;padding:20px;} pre{background:#f7f7f7;padding:10px;border-radius:4px;} table{border-collapse:collapse;} table, th, td{border:1px solid #ccc;padding:6px}</style>\n')
        fh.write(html)
    print('Wrote HTML:', args.out)

    if args.pdf:
        if HTML is None:
            print('WeasyPrint not available; cannot produce PDF. Install with `pip install weasyprint` and system deps.')
            return
        # Render PDF
        try:
            HTML(string=html).write_pdf(args.pdf)
            print('Wrote PDF:', args.pdf)
        except Exception as e:
            print('PDF render failed:', e)


if __name__ == '__main__':
    main()
