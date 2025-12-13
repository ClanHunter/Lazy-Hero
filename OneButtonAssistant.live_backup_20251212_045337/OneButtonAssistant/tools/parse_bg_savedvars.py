#!/usr/bin/env python3
"""
parse_bg_savedvars.py

Example helper to parse `OneButtonAssistantDB.bgExport[matchID]` NDJSON strings (exported from the addon)
and write them out as JSON or CSV for analysis.

Usage:
  python tools/parse_bg_savedvars.py --ndjson-file path/to/ndjson.txt --out match.json

If you have a SavedVariables Lua file, extract the `OneButtonAssistantDB.bgExport[...]` string(s)
and save them as plain text files, then point this script to them.
"""
import argparse
import json
import csv
import os
import sys


def parse_ndjson_text(text):
    lines = [l.strip() for l in text.splitlines() if l.strip()]
    if not lines:
        return None
    # first line may be meta wrapper like {"meta":{...}}
    meta = None
    events = []
    for i, l in enumerate(lines):
        try:
            obj = json.loads(l)
        except Exception:
            # try to coerce (replace single quotes) -- best-effort
            try:
                obj = json.loads(l.replace("'", '"'))
            except Exception:
                obj = None
        if not obj:
            continue
        if i == 0 and 'meta' in obj:
            meta = obj['meta']
        else:
            events.append(obj)
    return { 'meta': meta, 'events': events }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ndjson-file', required=True)
    parser.add_argument('--out-json', help='Write parsed JSON to this file')
    parser.add_argument('--out-csv', help='Write flattened CSV of events to this file')
    parser.add_argument('--out-summary', help='Write single-row summary CSV (meta + stats) to this file')
    parser.add_argument('--out-damage-ts', help='Write damage time-series CSV (per-second) to this file')
    parser.add_argument('--out-burst', help='Write burst-windows CSV to this file')
    parser.add_argument('--out-burst-spells', help='Write per-spell breakdown CSV for top burst windows')
    parser.add_argument('--out-activity', help='Write activity heatmap CSV (time buckets) to this file')
    parser.add_argument('--out-objectives', help='Write objective timeline CSV to this file')
    parser.add_argument('--window-size', type=int, default=5, help='Window size (seconds) for burst detection')
    parser.add_argument('--top-n', type=int, default=5, help='Top N burst windows to output')
    args = parser.parse_args()

    if not os.path.exists(args.ndjson_file):
        print('NDJSON file not found:', args.ndjson_file)
        sys.exit(2)

    with open(args.ndjson_file, 'r', encoding='utf-8') as fh:
        text = fh.read()

    parsed = parse_ndjson_text(text)
    if not parsed:
        print('Failed to parse NDJSON')
        sys.exit(2)

    if args.out_json:
        with open(args.out_json, 'w', encoding='utf-8') as fh:
            json.dump(parsed, fh, ensure_ascii=False, indent=2)
        print('Wrote JSON:', args.out_json)

    if args.out_csv:
        events = parsed.get('events', [])
        if events:
            keys = set()
            for e in events:
                for k in e.keys(): keys.add(k)
            keys = sorted(keys)
            with open(args.out_csv, 'w', newline='', encoding='utf-8') as fh:
                writer = csv.DictWriter(fh, fieldnames=keys)
                writer.writeheader()
                for e in events:
                    writer.writerow(e)
            print('Wrote CSV:', args.out_csv)
    # write a single-row summary CSV combining meta.player and stats for quick analytics
    if args.out_summary:
        meta = parsed.get('meta') or {}
        stats = parsed.get('meta', {}).get('stats') or parsed.get('stats') or {}
        player = meta.get('player') or {}
        # build a flat summary dict
        summary = {
            'matchID': meta.get('matchID'),
            'zone': meta.get('zone'),
            'startTime': meta.get('startTime'),
            'endTime': meta.get('endTime'),
            'events': meta.get('events'),
            'truncated': meta.get('truncated'),
            'player_name': player.get('name'),
            'player_class': player.get('class'),
            'player_race': player.get('race'),
            'player_level': player.get('level'),
            'player_faction': player.get('faction'),
            'player_guid': player.get('guid'),
        }
        # include stats fields (ensure deterministic order)
        stat_keys = ['damageDone','healingDone','damageTaken','kills','deaths','interruptsByPlayer','interruptsOnPlayer','dispelsByPlayer','dispelsOnPlayer','auraAppliedByPlayer','auraAppliedToPlayer']
        for k in stat_keys:
            summary[k] = stats.get(k)
        # write CSV (single row)
        with open(args.out_summary, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.DictWriter(fh, fieldnames=list(summary.keys()))
            writer.writeheader()
            writer.writerow(summary)
        print('Wrote summary CSV:', args.out_summary)

    # damage time-series (per-second buckets)
    player_guid = (parsed.get('meta') or {}).get('player', {}).get('guid')
    events = parsed.get('events', [])
    if args.out_damage_ts:
        # bucket by integer second
        buckets = {}
        total_buckets = {}
        for e in events:
            t = e.get('t')
            if t is None:
                continue
            sec = int(float(t))
            if sec not in buckets:
                buckets[sec] = 0
            if sec not in total_buckets:
                total_buckets[sec] = 0
            # treat DAMAGE events
            et = e.get('e','')
            if isinstance(et, str) and ('DAMAGE' in et or et in ('SWING_DAMAGE','RANGE_DAMAGE')):
                amt = e.get('amt') or 0
                try:
                    amt = float(amt)
                except Exception:
                    amt = 0
                if e.get('src') == player_guid:
                    buckets[sec] += amt
                total_buckets[sec] += amt
        # write CSV sorted by time
        with open(args.out_damage_ts, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.DictWriter(fh, fieldnames=['time','player_damage','total_damage'])
            writer.writeheader()
            for sec in sorted(set(list(buckets.keys()) + list(total_buckets.keys()))):
                writer.writerow({'time':sec,'player_damage':buckets.get(sec,0),'total_damage':total_buckets.get(sec,0)})
        print('Wrote damage time-series CSV:', args.out_damage_ts)

    # burst window detection (sliding window over buckets)
    if args.out_burst:
        window = int(args.window_size or 5)
        # reuse buckets computed above (if any) or recompute
        if 'buckets' not in locals():
            buckets = {}
            for e in events:
                t = e.get('t')
                if t is None: continue
                sec = int(float(t))
                if sec not in buckets: buckets[sec] = 0
                et = e.get('e','')
                if isinstance(et, str) and ('DAMAGE' in et or et in ('SWING_DAMAGE','RANGE_DAMAGE')) and e.get('src') == player_guid:
                    try: amt = float(e.get('amt') or 0)
                    except: amt = 0
                    buckets[sec] = buckets.get(sec,0) + amt
        secs = sorted(buckets.keys())
        # build prefix sums for fast window sums
        windows = []
        if secs:
            min_s = secs[0]
            max_s = secs[-1]
            arr = [0] * (max_s - min_s + 1)
            for s,v in buckets.items(): arr[s - min_s] = v
            prefix = [0]
            for v in arr:
                prefix.append(prefix[-1] + v)
            for i in range(0, len(arr)):
                j = min(i + window, len(arr))
                wsum = prefix[j] - prefix[i]
                windows.append((min_s + i, wsum))
        # compute z-score across windows if we have more than one
        vals = [w[1] for w in windows]
        mean = sum(vals) / len(vals) if vals else 0
        import math
        std = math.sqrt(sum((v - mean) ** 2 for v in vals) / len(vals)) if vals else 0
        # annotate windows with zscore
        windows_z = []
        for (start, val) in windows:
            z = 0.0
            if std and std > 0:
                z = (val - mean) / std
            windows_z.append((start, val, z))
        # pick top N by z-score (de-emphasize long low-variance spikes)
        topn = sorted(windows_z, key=lambda x: x[2], reverse=True)[:args.top_n]
        # write CSV with zscore
        with open(args.out_burst, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.DictWriter(fh, fieldnames=['window_start','window_seconds','player_damage','zscore'])
            writer.writeheader()
            for (start, val, z) in topn:
                writer.writerow({'window_start': start, 'window_seconds': window, 'player_damage': val, 'zscore': z})
        print('Wrote burst windows CSV (with z-score):', args.out_burst)
        # optional per-spell breakdown for the top windows
        if args.out_burst_spells:
            # build simple event index by second for fast lookups
            sec_events = {}
            for e in events:
                t = e.get('t')
                if t is None: continue
                sec = int(float(t))
                sec_events.setdefault(sec, []).append(e)
            # accumulate per-window per-spell damage for the player
            rows = []
            for (start, val, z) in topn:
                s0 = start
                s1 = start + window - 1
                spell_totals = {}
                for sec in range(s0, s1 + 1):
                    for e in sec_events.get(sec, []):
                        et = e.get('e','')
                        if isinstance(et, str) and ('DAMAGE' in et or et in ('SWING_DAMAGE','RANGE_DAMAGE')) and e.get('src') == player_guid:
                            amt = 0.0
                            try: amt = float(e.get('amt') or 0)
                            except: amt = 0.0
                            key = None
                            if e.get('s'):
                                key = 'id:' + str(e.get('s'))
                            elif e.get('sn'):
                                key = 'name:' + str(e.get('sn'))
                            else:
                                key = 'unknown'
                            spell_totals[key] = spell_totals.get(key, 0.0) + amt
                for spell_key, dmg in spell_totals.items():
                    if spell_key.startswith('id:'):
                        sid = spell_key.split(':',1)[1]
                        sname = ''
                    else:
                        sid = ''
                        sname = spell_key.split(':',1)[1]
                    rows.append({'window_start': start, 'window_seconds': window, 'zscore': z, 'spell_key': spell_key, 'spellId': sid, 'spellName': sname, 'damage': dmg})
            # write CSV
            with open(args.out_burst_spells, 'w', newline='', encoding='utf-8') as fh:
                writer = csv.DictWriter(fh, fieldnames=['window_start','window_seconds','zscore','spell_key','spellId','spellName','damage'])
                writer.writeheader()
                for r in rows:
                    writer.writerow(r)
            print('Wrote per-spell burst breakdown CSV:', args.out_burst_spells)

    # activity heatmap (time buckets of event counts)
    if args.out_activity:
        activity = {}
        for e in events:
            t = e.get('t')
            if t is None: continue
            sec = int(float(t))
            activity[sec] = activity.get(sec,0) + 1
        with open(args.out_activity, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.DictWriter(fh, fieldnames=['time','event_count'])
            writer.writeheader()
            for sec in sorted(activity.keys()): writer.writerow({'time':sec,'event_count':activity[sec]})
        print('Wrote activity heatmap CSV:', args.out_activity)

    # objective timeline detection (best-effort by keywords)
    if args.out_objectives:
        keywords = ['FLAG','CAPTURE','RETURN','ASSAULT','DEFEND','RESOURCE','GATHER','SCORE','TOWER','GRAVEYARD','VEHICLE']
        found = []
        for e in events:
            sn = (e.get('sn') or '').upper()
            et = (e.get('e') or '').upper()
            combined = sn + ' ' + et
            for kw in keywords:
                if kw in combined:
                    found.append({'time': int(float(e.get('t') or 0)), 'event': e.get('e'), 'spellName': e.get('sn'), 'note': kw})
                    break
        with open(args.out_objectives, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.DictWriter(fh, fieldnames=['time','event','spellName','note'])
            writer.writeheader()
            for r in found: writer.writerow(r)
        print('Wrote objectives CSV:', args.out_objectives)


if __name__ == '__main__':
    main()
