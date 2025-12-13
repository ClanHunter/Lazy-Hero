import re,sys,hashlib,os
from collections import defaultdict

def iter_lua_files(paths):
    for p in paths:
        for root,dirs,files in os.walk(p):
            for f in files:
                if f.endswith('.lua'):
                    yield os.path.join(root,f)

def extract_functions(text):
    # naive parser: find function definitions (named and assigned) and capture until matching 'end'
    funcs = []
    tokens = re.finditer(r"(^|\n)\s*(local\s+)?(function\s+[\w\.:]+\s*\(|[\w\.:]+\s*=\s*function\s*\()", text)
    starts = [m.start(0)+ (1 if m.group(1) else 0) for m in tokens]
    # slower: iterate through all positions
    i=0
    for m in re.finditer(r"(^|\n)\s*(local\s+)?(function\s+[\w\.:]+\s*\(|[\w\.:]+\s*=\s*function\s*\()", text):
        s = m.start()
        # find end by scanning and counting nested 'function'/'end'
        idx = s
        fn_count = 0
        pattern = re.compile(r"\b(function)\b|\b(end)\b")
        for mm in pattern.finditer(text, s):
            if mm.group(1):
                fn_count += 1
            else:
                fn_count -= 1
            if fn_count==0:
                endpos = mm.end()
                snippet = text[s:endpos]
                # get signature line
                sig = text[s:text.find('\n',s)+1]
                funcs.append((s,endpos,sig,snippet))
                break
    return funcs

root_paths = ['C:/Program Files (x86)/World of Warcraft/_retail_/Interface/AddOns/OneButtonAssistant','C:/Lazy Hero/OneButtonAssistant']
files = list(iter_lua_files(root_paths))
print(f"Found {len(files)} lua files to analyze", file=sys.stderr)
func_map = defaultdict(list)
file_issues = []
for filepath in files:
    try:
        with open(filepath, 'r', encoding='utf-8', errors='replace') as fh:
            txt = fh.read()
    except Exception as e:
        print(f"ERR reading {filepath}: {e}", file=sys.stderr)
        continue
    funcs = extract_functions(txt)
    for s,e,sig,body in funcs:
        h = hashlib.sha256(body.strip().encode('utf-8')).hexdigest()
        func_map[h].append((filepath,sig,len(body)))
    # basic function/end balance check
    fn_count = len(re.findall(r"\bfunction\b", txt))
    end_count = len(re.findall(r"\bend\b", txt))
    if fn_count != end_count:
        file_issues.append((filepath,fn_count,end_count))

# report duplicates where same body appears in >1 place
dups = {h:v for h,v in func_map.items() if len(v)>1}
print('DUPLICATE_FUNCTION_GROUPS:')
for h,v in sorted(dups.items(), key=lambda x: -len(x[1])):
    print('GROUP', h, 'COUNT', len(v))
    for fp,sig,size in v:
        print(f"  {size}\t{fp}\t{sig.strip()}")

print('\nFILES_WITH_FUNCTION_END_MISMATCH:')
for fp,fn,end in file_issues:
    print(f"{fp}\tfunctions={fn}\tend={end}")

# write JSON summary
import json
out = {'dups':{h:[{'file':fp,'sig':sig,'size':size} for fp,sig,size in v] for h,v in dups.items()}, 'issues': [{'file':fp,'functions':fn,'end':end} for fp,fn,end in file_issues]}
with open('c:/Lazy Hero/onebutton_dup_report.json','w',encoding='utf-8') as outfh:
    json.dump(out,outfh,indent=2)
print('REPORT_WRITTEN c:/Lazy Hero/onebutton_dup_report.json')
