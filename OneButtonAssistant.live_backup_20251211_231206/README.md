**OneButtonAssistant — Install & Test Guide**

- **Purpose:** Retail-only WoW addon providing a protected OneButton, conservative adapters, SpellSpy-style recording, and battleground logging exports with privacy-aware tooling.

**1) TOC Interface number (important)**
- The `## Interface:` line in `OneButtonAssistant.toc` must match your WoW client build number for the addon to load.
- To find your client's interface number:
  - Open the game's `World of Warcraft\framexml\toc.lua` (or check an existing working addon's `.toc`) or search the web for "WoW interface number" for your client patch.
  - In-game: type `/dump GetBuildInfo()` in the chat (requires a small helper addon to run protected code) — the first returned value is the version; you can map to the interface number via known tables online.

- To update the TOC safely from this workspace, run the provided PowerShell helper:
```powershell
# Example: set Interface to 30300
.\.\OneButtonAssistant\tools\set_toc_interface.ps1 -Interface 30300
```

**2) Install into WoW AddOns folder**
- Copy the `OneButtonAssistant` folder into your AddOns directory, typically:
  - `%USERPROFILE%\Documents\World of Warcraft\_retail_\Interface\AddOns\`
- After copying, ensure the `OneButtonAssistant.toc` file is at the top level of the addon folder.

**3) Basic in-game test flow**
- Start WoW and log into a character.
- Confirm addon loaded: `/reload` then check `Loaded AddOns` in the character select screen or watch chat for `[OneButtonAssistant] ready` messages.
- SpellSpy lifecycle:
  - On entering world the addon readies SpellSpy (you'll see a ready message in chat).
  - Enter combat to start recording (`PLAYER_REGEN_DISABLED` triggers start).
  - Exit the game via the in-game Exit/Logout button to ensure SavedVariables are written.

**4) Verify SavedVariables were written (local)**
- Find the addon SavedVariables file:
```powershell
Get-ChildItem -Path "$env:USERPROFILE\Documents\World of Warcraft\_retail_\WTF" -Recurse -Filter "OneButtonAssistant*.lua" -ErrorAction SilentlyContinue
```
- Open the file and look for `OneButtonAssistantDB.SpellSpy` (or use the `normalize_probe_output.py` tool to extract a manifest):
```powershell
& 'C:\Users\Ryan\AppData\Local\Programs\Python\Python312\python.exe' "OneButtonAssistant\tools\normalize_probe_output.py" --savedvars "C:\path\to\OneButtonAssistant.lua" --input "OneButtonAssistant\probe_output.lua" --output "OneButtonAssistant\patches\probe_output_normalized.ndjson" --manifest "OneButtonAssistant\patches\probe_output_manifest.json" --hash-guid --include-positions
```

**5) Useful slash commands (in-game)**
- `/oba_spellspy status` — show SpellSpy counts and recording state
- `/oba_spellspy start` — force start recording
- `/oba_spellspy stop` — stop recording
- `/oba_spellspy clear` — clear collected entries
- `/oba_spellspy export` — mark an export timestamp in SavedVariables

**6) Offline analysis**
- `tools/normalize_probe_output.py` extracts `spellId` where possible, optionally hashes GUIDs, and writes a manifest. Example:
```powershell
& 'C:\Users\Ryan\AppData\Local\Programs\Python\Python312\python.exe' "OneButtonAssistant\tools\normalize_probe_output.py" --input "OneButtonAssistant\probe_output.lua" --output "OneButtonAssistant\patches\probe_output_normalized.ndjson" --manifest "OneButtonAssistant\patches\probe_output_manifest.json" --hash-guid --salt "your_secret_salt" --include-positions
```

**7) Packaging for install**
- If you'd like, I can create a zip (`OneButtonAssistant.zip`) of the addon folder ready to drop into the `AddOns` directory.

**8) Next steps I can do for you**
- Update the `## Interface:` number for you if you provide the target value.
- Create a zip package for easy install.
- Parse your SavedVariables file (if you provide it) and generate a privacy-aware export and manifest.

-- End of README
OneButtonAssistant (Retail-only) - Starter scaffold

Overview
- This repository contains a minimal Retail-only World of Warcraft addon scaffold for a One-Button Assistant.
- It does NOT include or modify any third-party addons. Instead it provides adapter stubs so the addon can integrate at runtime with addons you install (GSE, Hekili, WeakAuras, TellMeWhen, OmniCC, Ace3).

Next steps
1. Update the `## Interface` number in `OneButtonAssistant.toc` to match your WoW client build number (check an existing working addon TOC for the correct value).
2. Install third-party addons you want to integrate (GSE, Hekili, WeakAuras, etc.) via CurseForge/WowUp/Manually.
3. Run the game with this addon folder placed under your `World of Warcraft/_retail_/Interface/AddOns/` directory.

Developer notes
- The design uses an adapter approach to avoid modifying third-party addon's source. This respects licensing and authorship.
- If you have explicit permission (and a compatible license) to embed or modify a third-party addon, provide the source and I can help integrate it locally.

Adapter notes
- `adapters/hekili_adapter.lua`: best-effort runtime wrapper that attempts to call common Hekili APIs to fetch suggestions and limited state.
- `adapters/gse_adapter.lua`: attempts to inspect GSE sequences; GSE typically doesn't provide live suggestions, so this adapter is limited.
- `adapters/weak_auras_adapter.lua`: exposes a global function `OneButtonAssistant_ReceiveWAState(state)` that you can call from a WeakAuras custom trigger/action to push state (talents/procs/enemyCount) into the engine.

Because addon APIs vary across versions, these adapters use protected calls and fall back gracefully when the target addon does not expose an expected function. For reliable integration, install the target addon in your client and test the adapter behavior.

Runtime adapter probing (how to help me adapt to your installed versions)
- To help me iterate adapters against your installed addon versions, run `/oba probe` in-game. This will:
	- Introspect the runtime tables for the installed addons (Hekili, GSE, WeakAuras) using safe, limited calls.
	- Save the probe summary to the saved variables table `OneButtonAssistantDB.adapterProbe`.
	- Print a short confirmation in chat.

	After running `/oba probe`, exit the game (or access the saved variables file) and copy the `OneButtonAssistantDB.adapterProbe` contents or share the saved-variables file. With that data I can refine the adapter code to call the correct API functions for your installed versions.

Warning: the probe attempts only a small number of guarded calls (functions starting with `Get`/`Is`/`Suggest`/`Sequence`) and tries to avoid causing side effects. Still, run it with normal caution and avoid running probes during critical gameplay.

Files of interest
- `OneButtonAssistant_core.lua`: Addon bootstrap and event handling.
- `OneButtonAssistant_engine.lua`: Rotation engine stub and API (`GetNextAction`).
- `adapters/`: Adapter stubs for Hekili and GSE.
- `OneButtonAssistant_ui.lua`: AceConfig UI stub.
- `OneButtonAssistant_logger.lua`: Simple logger for replay analysis.
- `examples/weak_auras_hook.lua`: Example hook for WeakAuras to call.

Licensing & Permissions
- Do not bundle or redistribute third-party addons without checking their licenses and obtaining permission if required.
- This scaffold is intended to integrate with addons the user has installed.

Want me to:
- Add a sample priority engine (single-target vs AoE switching)?
- Add AceConfig options with a small options table?
- Implement Hekili/GSE translator examples (requires those addons installed for testing)?
