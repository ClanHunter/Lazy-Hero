#!/usr/bin/env python3
"""Lookup spell name -> id mappings using Blizzard Game Data API.

Usage:
  - Set environment variables `BLIZZARD_ACCESS_TOKEN` OR `BLIZZARD_CLIENT_ID` and `BLIZZARD_CLIENT_SECRET`.
  - Optionally set `BLIZZARD_REGION` (default: us). Valid: us, eu, kr, tw, cn
  - Run:
      python tools/blizzard_lookup.py

What it does:
  - Reads `saved_exports/parsed/capture_entries_token_mapped.csv` for unique spell names missing mapped_token
  - Queries Blizzard search API for each unmapped name
  - Writes `saved_exports/parsed/spell_name_mapping_blizzard.json` with suggested mappings

Notes:
  - You can obtain a client id/secret at https://develop.battle.net/ and then request a token.
  - This script is best-effort: it prefers exact, case-insensitive matches, then first search result.
"""
import os
import sys
import time
import json
import urllib.parse
import urllib.request
from pathlib import Path
import csv

ROOT = Path(__file__).resolve().parents[1]
PARSED = ROOT / 'saved_exports' / 'parsed'
IN_CSV = PARSED / 'capture_entries_token_mapped.csv'
OUT_JSON = PARSED / 'spell_name_mapping_blizzard.json'

REGION = os.environ.get('BLIZZARD_REGION', 'us')
API_HOST = {
    'us': 'us.api.blizzard.com',
    'eu': 'eu.api.blizzard.com',
    'kr': 'kr.api.blizzard.com',
    'tw': 'tw.api.blizzard.com',
    'cn': 'gateway.battlenet.com.cn'
}.get(REGION, 'us.api.blizzard.com')
NAMESPACE = {
    'us': 'static-us',
    'eu': 'static-eu',
    'kr': 'static-kr',
    'tw': 'static-tw',
    'cn': 'static-cn'
}.get(REGION, 'static-us')
LOCALE = 'en_US' if REGION != 'cn' else 'zh_CN'


def get_access_token_from_env_or_oauth():
    token = os.environ.get('BLIZZARD_ACCESS_TOKEN')
    if token:
        return token
    client_id = os.environ.get('BLIZZARD_CLIENT_ID')
    client_secret = os.environ.get('BLIZZARD_CLIENT_SECRET')
    if client_id and client_secret:
        # request token
        data = urllib.parse.urlencode({'grant_type': 'client_credentials'}).encode('utf-8')
        auth = (client_id + ':' + client_secret).encode('utf-8')
        import base64
        hdr = {'Authorization': 'Basic ' + base64.b64encode(auth).decode('ascii'), 'Content-Type': 'application/x-www-form-urlencoded'}
        req = urllib.request.Request('https://oauth.battle.net/token', data=data, headers=hdr, method='POST')
        try:
            with urllib.request.urlopen(req) as resp:
                body = resp.read().decode('utf-8')
                j = json.loads(body)
                return j.get('access_token')
        except Exception as e:
            print('Failed to obtain token via OAuth:', e)
            return None
    print('No access token or client credentials in environment.')
    return None


def search_spell_by_name(name, token):
    # Build search URL
    # Use the search endpoint: /data/wow/search/spell
    q = urllib.parse.quote(name, safe='')
    url = f'https://{API_HOST}/data/wow/search/spell?namespace={NAMESPACE}&locale={LOCALE}&name.en_US={q}&pageSize=10'
    # append access token
    url = url + f'&access_token={urllib.parse.quote(token)}'
    try:
        with urllib.request.urlopen(url) as resp:
            body = resp.read().decode('utf-8')
            j = json.loads(body)
            # results array under 'results' or 'results'
            results = j.get('results') or []
            suggestions = []
            for r in results:
                data = r.get('data') or r.get('spell') or r.get('data')
                # data may be nested
                if isinstance(r, dict) and 'data' in r and isinstance(r['data'], dict):
                    d = r['data']
                else:
                    d = r
                # attempt to extract id and name
                sid = d.get('id') if isinstance(d, dict) else None
                sname = None
                # some search results include 'name' inside 'data' or 'value'
                if isinstance(d, dict):
                    sname = d.get('name') or d.get('spellName')
                suggestions.append({'id': sid, 'name': sname, 'raw': r})
            return suggestions
    except urllib.error.HTTPError as e:
        # handle 404 or rate limit
        msg = e.read().decode('utf-8') if e.fp else str(e)
        print('HTTPError', e.code, msg)
        return []
    except Exception as e:
        print('search error', e)
        return []


def main():
    if not IN_CSV.exists():
        print('Input CSV not found:', IN_CSV)
        sys.exit(1)
    rows = []
    with IN_CSV.open('r', encoding='utf-8', newline='') as fh:
        r = csv.DictReader(fh)
        for row in r:
            rows.append(row)
    # find unique unmapped names
    unmapped = {}
    for row in rows:
        mapped = row.get('mapped_token') or row.get('token')
        name = (row.get('spellName') or '').strip()
        if not name:
            continue
        if not mapped:
            unmapped.setdefault(name, 0)
            unmapped[name] += 1
    print('unique unmapped names:', len(unmapped))
    if not unmapped:
        print('Nothing to map.')
        sys.exit(0)
    token = get_access_token_from_env_or_oauth()
    if not token:
        print(
            "\nTo obtain an access token, either:\n"
            "  1) Set BLIZZARD_ACCESS_TOKEN environment variable with an existing token, or\n"
            "  2) Create a Blizzard app at https://develop.battle.net/ to get CLIENT_ID and CLIENT_SECRET, then set BLIZZARD_CLIENT_ID and BLIZZARD_CLIENT_SECRET environment variables and rerun.\n"
        )
        sys.exit(1)
    mappings = {}
    for i,(name,count) in enumerate(sorted(unmapped.items(), key=lambda x:-x[1])):
        print(f'[{i+1}/{len(unmapped)}] Searching for "{name}" (count {count})...')
        suggestions = search_spell_by_name(name, token)
        mapped = None
        confidence = 'none'
        if suggestions:
            # try exact case-insensitive match
            for s in suggestions:
                sname = s.get('name')
                if sname and sname.lower() == name.lower():
                    mapped = s.get('id')
                    confidence = 'exact_ci'
                    break
            if not mapped:
                # fallback to first suggestion
                mapped = suggestions[0].get('id')
                confidence = 'first_result'
        mappings[name] = {'count': count, 'mapped_id': mapped, 'confidence': confidence, 'suggestions': suggestions}
        # sleep a bit to respect rate limits
        time.sleep(0.2)
    OUT_JSON.write_text(json.dumps(mappings, indent=2, ensure_ascii=False), encoding='utf-8')
    print('Wrote mapping suggestions to', OUT_JSON)

if __name__ == '__main__':
    main()
