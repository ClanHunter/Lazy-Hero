**OneButtonAssistant BG Export (NDJSON) — README**

Overview:
- The addon logs compact battleground events into `OneButtonAssistantDB.bgLogs` (per-match entries).
- For extraction, use either the single-match NDJSON export at `OneButtonAssistantDB.bgExport[<matchID>]` or chunked exports at `OneButtonAssistantDB.bgExportChunks[<matchID>]` (array of NDJSON chunks).

How exports are produced in-game:
- `/oba bg export <matchID>` — prepares a single NDJSON string at `OneButtonAssistantDB.bgExport[<matchID>]` (may be large).
- `/oba bg exportall [linesPerChunk]` — splits every saved match into chunks (default 500 lines per chunk) and writes them to `OneButtonAssistantDB.bgExportChunks[<matchID>]` as an array of chunk strings; a manifest is available at `OneButtonAssistantDB.bgExportManifest[<matchID>]`.

Why chunking exists:
- SavedVariables are stored as plain Lua files. Very large single-line strings can be difficult to extract via simple copy/paste or may exceed editor copy limits.
- Chunking splits NDJSON into manageable strings so you can copy/paste each chunk out of your SavedVariables file into a local file and reassemble them offline.

Privacy and data minimization:
- GUIDs in exported events are anonymized via a salted hash (`OneButtonAssistantDB.bgSalt`) before being written to saved variables.
- By default the logger uses a conservative whitelist and caps: `bgConfig.whitelist`, `bgConfig.maxEvents` (default 2000), `bgConfig.maxMatches` (default 50), and `bgConfig.sampling` (default 1 = record all matching events).
- You can reduce logging volume and sensitivity by updating `OneButtonAssistantDB.bgConfig` in-game (via `/run` or an options UI if available):
  - `OneButtonAssistantDB.bgConfig.sampling = 5`  -- record roughly every 5th matching event
  - `OneButtonAssistantDB.bgConfig.maxEvents = 500` -- lower per-match cap
  - `OneButtonAssistantDB.bgConfig.whitelist = { SPELL_DAMAGE = true, SPELL_HEAL = true }` -- only record chosen event types
- The addon attempts to avoid recording raw player names or un-hashed GUIDs. Meta contains hashed GUID for the local player for correlation only.

How to extract NDJSON from SavedVariables (recommended workflow):
1. In-game: run `/oba bg export <matchID>` or `/oba bg exportall <linesPerChunk>` (choose a chunk size like 500).
2. Log out of the character or reload UI (`/reload`) to ensure SavedVariables are flushed to disk.
3. On your computer, locate the SavedVariables file for the addon. Typical path (Windows):
   `C:\Program Files (x86)\World of Warcraft\_retail_\WTF\Account\<ACCOUNT>\SavedVariables\OneButtonAssistant.lua`
4. Open `OneButtonAssistant.lua` in a text editor and search for `OneButtonAssistantDB.bgExport` or `OneButtonAssistantDB.bgExportChunks`.
5. Copy the NDJSON string(s) (or chunk strings) into local files. If using chunks, concatenate them with `"\n"` between chunks to reconstruct the full NDJSON content for a match.

Offline parsing tools:
- `tools/parse_bg_savedvars.py` accepts NDJSON files and can output:
  - full parsed JSON (`--out-json`)
  - flattened events CSV (`--out-csv`)
  - one-line summary CSV (`--out-summary`)
  - damage time-series CSV (`--out-damage-ts`)
  - burst-window CSV (`--out-burst`) with `--window-size` and `--top-n`
  - activity heatmap CSV (`--out-activity`)
  - objective timeline CSV (`--out-objectives`)

Example offline reassembly (PowerShell):
```powershell
# if you have chunks saved as chunk1.txt, chunk2.txt, ...
Get-Content .\chunk1.txt, .\chunk2.txt | Out-File -Encoding utf8 .\match-123.ndjson
# then parse
python .\OneButtonAssistant\tools\parse_bg_savedvars.py --ndjson-file .\match-123.ndjson --out-summary .\match-123-summary.csv --out-damage-ts .\match-123-damage.csv
```

Limitations & notes:
- Position/heatmap data: the addon does not currently record player positions. Activity heatmaps are generated from event density over time; if you need spatial heatmaps, the addon must be extended to record locations using secure APIs where available.
- Objective detection is keyword-driven and best-effort; adjustments for specific battlegrounds may improve detection accuracy.

If you'd like, I can add: (a) an in-addon copy-to-clipboard helper that emits chunks via a simple UI for easy extraction, (b) position logging (privacy tradeoff), or (c) a small web/dashboard generator that consumes the CSV outputs and renders quick visualizations.
