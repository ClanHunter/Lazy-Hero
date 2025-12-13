BG Export / In-Game Validation Plan

Purpose
- Provide a concise in-game checklist to validate macro placement, heuristic promotion UI, BG logging privacy toggles, NDJSON export retrieval, and position logging opt-in.

Preconditions
- Install the addon build into WoW Retail's `Interface\AddOns` for a test character.
- Use a test account or a friend in a test battleground; do not upload or share raw GUIDs.

Checklist

1) Macro creation & placement
- Command: `/oba makemacros` (or `/oba autoplace 25` when testing) to request macro creation.
- Verify: macros named `OBA - <command>` appear in your macro list (use `Esc -> Macros`)
- Verify placement: macros were placed only on empty slots within 25..48 (action bars 3-4). No existing icons were moved.
- Test: If in combat during request, macros are queued and placed automatically after combat ends.
- Expected: `OneButtonAssistantDB.macroBatchPending` cleared after placement and `OneButtonAssistantDB.macroSlot` updated if autoplace used.

2) Heuristic promotion UI
- Trigger: Let `spellspy` or an adapter suggest an alias, or simulate by calling `OneButtonAssistant:PromoteHeuristic('testtoken')` in /run.
- Verify: `StaticPopup` named `ONEBUTTONASSISTANT_HEURISTIC_CONFIRM` appears prompting to accept/reject.
- Test: Click Accept -> `OneButtonAssistantDB.aliases['testtoken']` should be set and `OneButtonAssistantDB.heuristics['testtoken']` removed.
- Test: Click Cancel -> heuristic removed and not promoted.
- Config: Toggle auto-confirm with `/oba heuristics autoconfirm on|off` and verify behavior.

3) BG logging lifecycle (privacy-safe default)
- Start logging: `/oba bg start` (or enter a PvP instance where logging auto-starts).
- Verify: `OneButtonAssistantDB.bgLogs` receives a `match` entry after leaving the match.
- Verify `meta.player.guid` is hashed (not raw GUID): compare format to ensure it's numeric string, not the native GUID pattern.
- Verify aggregated `stats` (damageDone, healingDone, interruptsByPlayer, etc.) appear and increment across obvious events.
- Caps: Generate many events and verify `meta.truncated` is set if `bgConfig.maxEvents` exceeded.

4) Position logging opt-in
- By default `OneButtonAssistantDB.bgConfig.logPositions` is `false`.
- Enable positions: run `/run if OneButtonAssistantBGLogger then OneButtonAssistantBGLogger:EnablePositionLogging(true) end`.
- Play a short match; after export, inspect events in `OneButtonAssistantDB.bgLogs[..].events` and confirm events include `pos` objects (with `m,x,y` or `x,y,z`).
- Disable positions and repeat; confirm `pos` no longer present in new events.
- Privacy check: ensure you only enable position logging in tests and avoid sharing raw export with others unless anonymized.

5) NDJSON export & chunking
- Prepare single-match export: `/oba bg export <matchID>` then inspect `OneButtonAssistantDB.bgExport[<matchID>]` contains newline-delimited JSON where the first line is a `meta` object and subsequent lines are event objects.
- Prepare chunked export: `/oba bg exportall [linesPerChunk]` then inspect `OneButtonAssistantDB.bgExportChunks[<matchID>]` contains an array of chunk strings.
- Use in-addon UI: run `/run if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.ShowExportUI then OneButtonAssistantBGLogger:ShowExportUI('<matchID>', 1) end` and confirm a copy-friendly window opens with the chunk text.
- Extraction: copy-paste chunk(s) to local files, join chunks with newlines to reconstruct full NDJSON for parser consumption.

6) Parser run (offline)
- Ensure Python installed locally. From a shell:

```powershell
python -m pip install -r "OneButtonAssistant\tools\requirements.txt"
python "OneButtonAssistant\tools\parse_bg_savedvars.py" --ndjson-file path\to\match.ndjson --out-summary summary.csv --out-damage-ts damage_ts.csv --out-burst burst.csv --out-burst-spells burst_spells.csv --out-activity activity.csv --out-objectives objectives.csv
```

- Verify created CSVs look sane (non-empty), timestamps align with match duration, and `burst_spells.csv` contains per-spell contributions for the top windows.

Notes & Safety
- Exports contain hashed GUIDs by default. Do not share raw NDJSON publicly. Consider redacting or only sharing aggregated CSV outputs.
- Position logging is opt-in for privacy. Only enable it when you control the data and participants consent.

If you want, I can also add an in-addon UI button that auto-opens after `exportall` completes to make copy/pasting even easier.
