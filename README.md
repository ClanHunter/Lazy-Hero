# OneButtonAssistant BG Logger

Lua for recording World of Warcraft battleground combat into the `OneButtonAssistantDB` saved table, then exporting a match as newline-delimited JSON (NDJSON).

The repository contains the logger (`OneButtonAssistantBGLogger`, version `0.2`), the shared helper table those calls use (`OneButtonAssistantShared`), a pull request template, and two GitHub Actions workflows. There is no addon `.toc`, no dependency manifest, and no core `OneButtonAssistant` implementation in this tree. The logger registers itself as the `"bglogger"` adapter only when a global `OneButtonAssistant` with a `RegisterAdapter` method is already present.

## Tech stack

- Lua, using World of Warcraft client APIs (`CreateFrame`, the combat log, unit functions, and `C_Map` when position logging is on).
- GitHub Actions on `ubuntu-latest`. The syntax workflow installs `lua5.3`.

There is no package manager and no build step.

## Repository layout

```
.github/PULL_REQUEST_TEMPLATE.md
.github/workflows/lua_syntax_check.yml
.github/workflows/create_pr.yml
OneButtonAssistant/OneButtonAssistant_bglogger.lua
OneButtonAssistant/adapters/shared_adapter_helpers.lua
```

| Path | Role |
| --- | --- |
| `OneButtonAssistant/OneButtonAssistant_bglogger.lua` | Logger. Sets global `OneButtonAssistantBGLogger` and returns that table. |
| `OneButtonAssistant/adapters/shared_adapter_helpers.lua` | Helpers. Sets global `OneButtonAssistantShared` and returns that table. |
| `.github/workflows/lua_syntax_check.yml` | Compiles every tracked `.lua` file on pull requests and on manual runs. |
| `.github/workflows/create_pr.yml` | Manual workflow that prints a placeholder message. |
| `.github/PULL_REQUEST_TEMPLATE.md` | Pull request template. The checklist asks for `luac -p`, in-game checks when a change affects play, and a backup of files before editing. |

## Setup

Clone the repository. Nothing else is required to read or syntax-check it.

The syntax workflow compiles each tracked Lua file without running it. Locally, with Lua 5.3 on `PATH` as `lua`:

```bash
lua -e "assert(loadfile('OneButtonAssistant/OneButtonAssistant_bglogger.lua'))"
lua -e "assert(loadfile('OneButtonAssistant/adapters/shared_adapter_helpers.lua'))"
```

On some systems the 5.3 binary is named `lua5.3`. `loadfile` only parses. Executing the logger calls `CreateFrame` while the file loads, so running it needs a World of Warcraft client (or another host that provides the WoW APIs the file calls).

## Loading

Load `OneButtonAssistant/adapters/shared_adapter_helpers.lua` before `OneButtonAssistant/OneButtonAssistant_bglogger.lua` when the logger should use the shared helpers.

The logger binds helpers once, at load:

```lua
local shared = OneButtonAssistantShared or {}
```

Database setup, time, GUID hashing, NDJSON formatting, chunking, and the export frame are taken from that table. If the helper file is not loaded yet, `shared` is an empty table and those calls stay on the logger's local fallbacks for the rest of the session. Two call sites look up the global again later: `OneButtonAssistantShared.gather_player_meta` when a match starts, and `OneButtonAssistantShared.parse_combat_extras` for each combat event.

`shared_adapter_helpers.lua` can be parsed outside the game. Its WoW calls sit inside `pcall` / `safeCall` and return `nil` when those globals are missing. `create_export_frame` returns `nil` when `CreateFrame` or `UIParent` is missing.

## Recording

`OneButtonAssistantBGLogger.Start()` opens a match. `Stop()` closes it and appends the match to `OneButtonAssistantDB.bgLogs`. `Start` returns `false` when a match is already open. `Stop` returns `false` when none is open.

A frame named `OneButtonAssistantBGLoggerFrame` registers `PLAYER_ENTERING_WORLD`, `ZONE_CHANGED_NEW_AREA`, `PLAYER_LEAVING_WORLD`, and `COMBAT_LOG_EVENT_UNFILTERED`. `SetScript("OnEvent", ...)` runs twice in the file. The second handler replaces the first and acts only on `COMBAT_LOG_EVENT_UNFILTERED`. After load, entering or leaving a zone does not start or stop a match. Use `Start` and `Stop`.

While a match is open, each `COMBAT_LOG_EVENT_UNFILTERED` is read with `CombatLogGetCurrentEventInfo`. Events whose subevent is not in the whitelist are dropped. `sampling` keeps every Nth whitelisted event (`1` keeps all). A per-match cap, `maxEvents` (default `2000`), stops further rows and sets `meta.truncated`. Saved matches are capped by `maxMatches` (default `50`); the oldest match is removed past that cap.

Default whitelist:

- `SPELL_CAST_SUCCESS`, `SPELL_DAMAGE`, `SPELL_HEAL`
- `SPELL_AURA_APPLIED`, `SPELL_AURA_REMOVED`
- `SPELL_INTERRUPT`, `SPELL_DISPEL`, `SPELL_STOLEN`
- `PARTY_KILL`, `UNIT_DIED`, `UNIT_DESTROYED`

Each stored event has:

| Field | Source |
| --- | --- |
| `t` | Combat-log timestamp (argument 1). |
| `e` | Subevent (argument 2). |
| `src`, `dst` | Hashed source and destination GUIDs (arguments 4 and 8). |
| `s` | Argument 12, when it is a number. |
| `sn` | Argument 13, when it is a string. |
| `amt` | The first number from argument 14 onward. |
| `pos` | Present only when position logging is enabled. Not written by either NDJSON formatter. |

`matchID` is `floor(now) .. "-" .. zone .. "-" ..` a random integer from 1000 through 9999. `Start` uses `GetZoneText` when that call succeeds, otherwise the zone string `"manual"`.

Time comes from the bound `now`. The shared helper uses `time()`, then `os.time()`. The logger fallback uses `GetTime()` when that global exists, otherwise `time()`.

### Player, team, and stats

Player fields stored on the match are `name`, `race`, `level`, `faction`, `guid`, and `class`.

- `name`, `race`, `level`, and `faction` come from the first return of `UnitName`, `UnitRace`, `UnitLevel`, and `UnitFactionGroup`. Missing calls become `"player"`, `"UNKNOWN"`, `0`, and `"unknown"`.
- `class` is read as the second result of a single-value `safeCall` of `UnitClass`. That second result is nil, so the stored class is `"UNKNOWN"`.
- `guid` is the hashed player GUID, or `"-"` when `UnitGUID` is missing.

Team summary counts units `1 .. GetNumGroupMembers()`. In a raid the unit id is `raidN`; otherwise it is `partyN`. The count key is the first return of `UnitClass` (the localized class name).

Stats update only when the hashed source or destination equals the hashed guid stored on the player:

| Subevent | Counter |
| --- | --- |
| Name contains `DAMAGE` | `damageDone` from source, `damageTaken` from destination, using `amt`. |
| Name contains `HEAL` | `healingDone` from source, using `amt`. |
| `SPELL_INTERRUPT` | `interruptsByPlayer` / `interruptsOnPlayer`. |
| `SPELL_DISPEL` or `SPELL_STOLEN` | `dispelsByPlayer` / `dispelsOnPlayer`. |
| `SPELL_AURA_APPLIED` | `auraAppliedByPlayer` / `auraAppliedToPlayer`. |
| `PARTY_KILL` | `kills` when the source is the player. |
| `UNIT_DIED` | `deaths` when the destination is the player. |

`assists` is initialized to `0` and never incremented. `objectives` is initialized to `{}` and never filled. Neither is written by the NDJSON formatters.

### GUID hash and positions

The shared `guidHash` returns `"-"` for a missing GUID, otherwise the last 12 characters of the GUID string. The logger fallback, used when the shared table was not bound at load, appends `OneButtonAssistantDB.bgSalt` (a random integer string created once) and hashes with a djb-style sum modulo `1000000007`. Stats compare hashes, so the player guid and the combat-log endpoints have to come from the same function.

Position logging defaults to off. `EnablePositionLogging(true)` sets `OneButtonAssistantDB.bgConfig.logPositions`. While that flag is true, each event may gain `pos`: map id plus `x` and `y` to four decimals from `C_Map.GetBestMapForUnit` / `GetPlayerMapPosition`, or `x`, `y`, and `z` from `UnitPosition` when the map call does not return a point.

## Saved table

The scripts use the global `OneButtonAssistantDB`. This repository does not declare it as a saved variable.

| Field | Contents |
| --- | --- |
| `bgLogs` | Match array. Oldest entries are dropped past `maxMatches`. |
| `bgConfig` | `whitelist`, `maxEvents`, `maxMatches`, `sampling`, `logPositions`. Filled with the defaults above the first time the logger loads. |
| `bgSalt` | Salt for the logger's fallback GUID hash. Created by that fallback's `ensureDB`, not by the shared `ensureDB`. |
| `bgExport` | `matchID` to one NDJSON string. |
| `bgExportChunks` | `matchID` to an array of NDJSON chunk strings. |
| `bgExportManifest` | `matchID` to `{ chunks = <count>, linesPerChunk = <n> }`. |

`Clear()` replaces `bgLogs` with `{}`. `GetAll()` returns `bgLogs`.

## Export

`PrepareExport(matchID)` finds that match, writes NDJSON to `OneButtonAssistantDB.bgExport[matchID]`, and returns the string. Unknown ids return `nil`.

`PrepareExportChunks(matchID, linesPerChunk)` builds the same NDJSON, splits on newlines into chunks of `linesPerChunk` lines (default `500`), stores the chunks, sets `bgExport[matchID]` to `nil`, and writes a manifest entry.

`PrepareAllChunks(linesPerChunk)` does that for every saved match and returns a map of match id to chunk count.

`Export(matchID)` returns the match table. The prepare call inside `Export` is `PrepareExport(BGLogger, matchID)`. `PrepareExport` only reads its first parameter, so that call looks up a match id equal to the logger table and does not write `bgExport`. Call `PrepareExport(matchID)` to produce the string.

`ShowExportUI(matchID, chunkIndex)` displays text that is already stored. Chunk index defaults to `1` and is clamped to the chunk list. With no chunks, it shows `bgExport[matchID]`. It returns `false` when no string is stored. The window is a 700×420 frame titled `OneButtonAssistant - BG Export (copy from the box below)`, with a multiline edit box. Escape hides it. The frame is created by `shared.create_export_frame` when that function is on the table captured at load, otherwise by `CreateFrame` when `CreateFrame` and `UIParent` exist. The frame name passed to `CreateFrame` is `OneButtonAssistantBGExportUI`.

NDJSON is one JSON object per line. Line 1 is `{"meta":...}`. Each later line is one event.

- Shared `matchToNDJSON` (helpers bound at logger load) writes each top-level `meta` field. Strings are escaped. Any other value, including the `player` and `team` tables, is `tostring`'d. `stats` is a sibling of `meta`, so this formatter does not emit stats. Event lines include `t`, `e`, `s`, `sn`, `amt`, `src`, and `dst` when set.
- The logger fallback writes `matchID`, `zone`, `startTime`, `endTime`, `events`, `truncated`, a `player` object, and a `stats` object (`damageDone`, `healingDone`, `damageTaken`, `kills`, `deaths`, interrupt, dispel, and aura counters). Event lines use the same event fields.

The shared escaper handles backslash, quotes, newline, carriage return, and tab. The logger fallback escapes backslash and quotes. Neither event formatter writes `pos`.

## Public API

Functions on `OneButtonAssistantBGLogger`:

| Function | Behavior |
| --- | --- |
| `Start()` | Open a match. `false` if one is already recording. |
| `Stop()` | Close and store the current match. `false` if none is recording. |
| `Clear()` | Set `bgLogs` to `{}`. |
| `GetAll()` | Return `bgLogs`. |
| `Export(matchID)` | Return the match table. Does not write `bgExport` (see Export). |
| `PrepareExport(matchID)` | Store and return one NDJSON string. |
| `PrepareExportChunks(matchID, linesPerChunk)` | Store chunks. Default 500 lines. |
| `PrepareAllChunks(linesPerChunk)` | Chunk every saved match. |
| `EnablePositionLogging(enable)` | Set `logPositions`. Returns the flag. |
| `IsPositionLoggingEnabled()` | Return `logPositions`. |
| `ShowExportUI(matchID, chunkIndex)` | Show prepared text. `false` if none is stored. |

`OneButtonAssistantShared` defines `ensureDB`, `guidHash`, `safeCall`, `now`, `escape_for_json`, `chunk_ndjson`, `format_event_line`, `matchToNDJSON`, `prepare_export`, `prepare_export_chunks`, `prepare_all_chunks`, `get_player_position`, `gather_player_meta`, `parse_combat_extras`, and `create_export_frame`.

## Continuous integration

**Lua Syntax Check** (`.github/workflows/lua_syntax_check.yml`) runs on `pull_request` and `workflow_dispatch`. It checks out the repo, installs `lua5.3`, and for each path from `git ls-files '*.lua'` runs:

```bash
lua -e "assert(loadfile('$f'))"
```

A failed compile fails the job.

**Create PR (manual)** (`.github/workflows/create_pr.yml`) runs only on `workflow_dispatch`. The job checks out the repo and prints that the workflow is a placeholder. It does not open a pull request.
