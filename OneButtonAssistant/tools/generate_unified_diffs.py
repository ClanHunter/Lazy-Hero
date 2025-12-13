import os
import sys
import difflib

root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
patches_dir = os.path.join(root, 'patches')
if not os.path.isdir(patches_dir):
    os.makedirs(patches_dir)

bak_files = []
for dirpath, dirnames, filenames in os.walk(root):
    for fn in filenames:
        if fn.endswith('.bak'):
            bak_files.append(os.path.join(dirpath, fn))

if not bak_files:
    print('No .bak files found under', root)
    sys.exit(0)

generated = []
for bak in bak_files:
    orig = bak[:-4]  # strip .bak
    rel_bak = os.path.relpath(bak, root)
    rel_orig = os.path.relpath(orig, root)
    base = os.path.basename(orig)
    outname = base + '.unified.diff'
    outpath = os.path.join(patches_dir, outname)

    try:
        with open(bak, 'rb') as f:
            bak_bytes = f.read()
        # decode leniently
        bak_text = bak_bytes.decode('utf-8', errors='surrogateescape')
        bak_lines = bak_text.splitlines(keepends=True)
    except Exception as e:
        bak_lines = [f'<<ERROR READING BAK: {e}>>\n']

    if os.path.exists(orig):
        try:
            with open(orig, 'rb') as f:
                orig_bytes = f.read()
            orig_text = orig_bytes.decode('utf-8', errors='surrogateescape')
            orig_lines = orig_text.splitlines(keepends=True)
        except Exception as e:
            orig_lines = [f'<<ERROR READING FILE: {e}>>\n']
    else:
        orig_lines = [f'<<MISSING CURRENT FILE: {orig}>>\n']

    diff_lines = list(difflib.unified_diff(bak_lines, orig_lines, fromfile=rel_bak, tofile=rel_orig, lineterm=''))
    if not diff_lines:
        # produce a small note if identical
        diff_lines = [f'--- {rel_bak}\n', f'+++ {rel_orig}\n', '@@ -1 +1 @@\n', 'No changes\n']

    with open(outpath, 'w', encoding='utf-8') as out:
        out.writelines(line + '\n' for line in diff_lines)

    generated.append(outname)
    print('Wrote', outname)

# write manifest of unified diffs
manifest = os.path.join(patches_dir, 'manifest_unified.txt')
with open(manifest, 'w', encoding='utf-8') as m:
    for name in generated:
        m.write(name + '\n')
print('\nGenerated unified diffs:', len(generated))
print('Manifest at', manifest)
