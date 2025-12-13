local addonName = "OneButtonAssistant"
OneButtonAssistant = OneButtonAssistant or {}
local OBA = OneButtonAssistant

local frame = CreateFrame("Frame", "OneButtonAssistantFrame")

-- Ensure the slash command exists immediately; the real handler will be attached when the addon loads.
SLASH_ONEBUTTONASSISTANT1 = "/oba"
SlashCmdList["ONEBUTTONASSISTANT"] = function(msg)
  if OBA and OBA.HandleSlash then
    OBA:HandleSlash(msg)
  else
    print("|cffffff00["..addonName.."]|r OneButtonAssistant not initialized. Type \"/help\" for a listing of a few commands.")
  end
end
 
local function safePrintRecursive(prefix, value, depth, maxDepth)
  depth = depth or 0
  maxDepth = maxDepth or 3
  local t = type(value)
  if t == "table" then
    OBA:Print(prefix.."(table) {")
    local count = 0
    for k,v in pairs(value) do
      count = count + 1
      if count > 200 then
        OBA:Print(string.format("%s  ... (%d more entries)", prefix, #value - 200))
        break
      end
      local keyStr = tostring(k)
      if type(v) == "table" then
        safePrintRecursive(prefix.."  "..keyStr..": ", v, depth + 1, maxDepth)
      else
        OBA:Print(string.format("%s  %s: %s", prefix, keyStr, tostring(v)))
      end
    end
    OBA:Print(prefix.."}")
  else
    OBA:Print(prefix..tostring(value))
  end
end
 

function OBA:Print(msg)
  print("|cffffff00["..addonName.."]|r "..tostring(msg))
end

function OBA:HandleSlash(msg)
  local cmd, rest = msg:match("^(%S*)%s*(.*)$")
  cmd = cmd or ""
  rest = rest or ""
  if cmd == "test" then
    if self.Engine and self.Engine.RunSelfTest then local res = self.Engine:RunSelfTest(); for i,v in ipairs(res) do if v then self:Print(string.format("Test %d -> %s (%s)", i, tostring(v.name), tostring(v.reason))) end end else self:Print("Engine self-test not available.") end
  elseif cmd == "next" then
    local action = self:GetNextActionForUnit("target")
    if action then self:Print(string.format("Next: %s (%s)", action.name or tostring(action.key), action.reason or "")) else self:Print("No suggestion available from adapters/engine. Try: /oba_capture then /oba probe then /oba next") end
  elseif cmd == "info" then
    self:Print("OneButtonAssistant diagnostics:")
    if self.adapters then for k,v in pairs(self.adapters) do self:Print(string.format("- adapter: %s", tostring(k))) end else self:Print("- adapters: none") end
    if OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion.capture and type(OneButtonAssistantDB.lastRawSuggestion.capture.entries) == "table" then
      self:Print(string.format("- capture entries: %d", #OneButtonAssistantDB.lastRawSuggestion.capture.entries))
    else
      self:Print("- capture entries: 0")
    end
  elseif cmd == "dumplastraw" then
    if OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion then
      self:Print("OneButtonAssistantDB.lastRawSuggestion contents:")
      for k,v in pairs(OneButtonAssistantDB.lastRawSuggestion) do local t=type(v); if t=="table" then local summary=v.name or v.key or v.suggestion or "(table)"; self:Print(string.format("- %s: %s", tostring(k), tostring(summary))) else self:Print(string.format("- %s: %s", tostring(k), tostring(v))) end end
    else
      self:Print("No OneButtonAssistantDB.lastRawSuggestion present (in-memory).")
    end
  elseif cmd == "probe" then
    self:Print("Running adapter probe (this collects adapter API info into saved variables).")
    if self.adapters then
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      OneButtonAssistantDB.adapterProbe = OneButtonAssistantDB.adapterProbe or {}
      for name, adapter in pairs(self.adapters) do if adapter and type(adapter.Probe) == "function" then local ok,res=pcall(adapter.Probe, adapter); if ok and res then OneButtonAssistantDB.adapterProbe[name]=res else OneButtonAssistantDB.adapterProbe[name]={ error = tostring(res) } end else OneButtonAssistantDB.adapterProbe[name]={ error = "no-probe" } end end
      self:Print("Probe complete. Results saved to OneButtonAssistantDB.adapterProbe")
    else
      self:Print("No adapters registered to probe.")
    end
  elseif cmd == "log" or cmd == "dump" then
    if OneButtonAssistantLogger and OneButtonAssistantLogger.GetAll then local logs=OneButtonAssistantLogger:GetAll() or {}; if #logs==0 then self:Print("Logger empty.") else OneButtonAssistantDB=OneButtonAssistantDB or {}; OneButtonAssistantDB.loggerDump=logs; self:Print("Logger dumped to OneButtonAssistantDB.loggerDump (showing up to 10 entries):"); for i=1, math.min(10,#logs) do local e=logs[i]; local t=e.time or "?"; local ev=e.event or "?"; local d=e.data or "?"; self:Print(string.format("%d: %s - %s - %s", i, tostring(t), tostring(ev), tostring(d))) end end else self:Print("No logger available.") end
  elseif cmd == "showraw" then
    local adapterName = rest:match("^(%S+)") or ""
    if adapterName == "" then
      self:Print("Usage: /oba showraw <adapter>")
    else
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      local saved = OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion[adapterName]
      if saved then
        self:Print("Saved raw suggestion for '"..adapterName.."':")
        if type(saved) == "table" then
          for k,v in pairs(saved) do
            local summary = (type(v) == "table") and (v.name or v.key or v.suggestion or "(table)") or tostring(v)
            self:Print(string.format("- %s: %s", tostring(k), tostring(summary)))
          end
        else
          self:Print(tostring(saved))
        end
      else
        local adapter = self.adapters and self.adapters[adapterName]
        if adapter and adapter.GetSuggestion then
          local ok, sug = pcall(adapter.GetSuggestion, adapter, "target")
          if ok and sug then
            self:Print("Adapter returned suggestion:")
            self:Print(string.format("- key: %s name: %s reason: %s", tostring(sug.key), tostring(sug.name), tostring(sug.reason)))
          else
            self:Print("No saved raw suggestion or live suggestion available for '"..adapterName.."'.")
          end
        else
          self:Print("No saved raw suggestion or live suggestion available for '"..adapterName.."'.")
        end
      end
    end
  elseif cmd == "showrawfull" then
    local adapterName = rest:match("^(%S+)") or ""
    if adapterName == "" then
      self:Print("Usage: /oba showrawfull <adapter> — deep, bounded dump")
    else
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      local saved = OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion[adapterName]
      if saved then
        self:Print("Saved raw suggestion (full) for '"..adapterName.."':")
        safePrintRecursive("", saved, 0, 4)
      else
        local adapter = self.adapters and self.adapters[adapterName]
        if adapter and adapter.GetSuggestion then
          local ok, sug = pcall(adapter.GetSuggestion, adapter, "target")
          if ok and sug and sug.raw then
            self:Print("Live adapter raw suggestion (full):")
            safePrintRecursive("", sug.raw, 0, 4)
          else
            self:Print("No saved raw suggestion or live raw available for '"..adapterName.."'.")
          end
        else
          self:Print("No saved raw suggestion or live raw available for '"..adapterName.."'.")
        end
      end
    end
  elseif cmd == "setbuff" then
    local buff, spellkey, thresh = rest:match("^(%S+)%s+(%S+)%s*(%S*)$")
    if not buff or not spellkey then
      self:Print("Usage: /oba setbuff <buffName> <spellKey> [thresholdSeconds]")
    else
      self:SetBuffRefresh(buff, spellkey, tonumber(thresh) or 5)
    end
  elseif cmd == "bind" then
    local key = rest:match("^(%S+)") or ""
    if key == "" then
      self:Print("Usage: /oba bind <KEY>  -- binds the key to the OBA button (saves binding).")
    else
      if self.BindButtonToKey then self:BindButtonToKey(key) else self:Print("Bind API not available.") end
    end
  elseif cmd == "unbind" then
    if self.UnbindButton then self:UnbindButton() else self:Print("Unbind API not available.") end
  elseif cmd == "autoplace" then
    local slot = tonumber(rest:match("^(%d+)") or rest)
    if not slot then
      self:Print("Usage: /oba autoplace <slotNumber>  -- overlays the OBA button on the given ActionButton slot (non-invasive).")
    else
      if self.AutoPlaceOnActionSlot then self:AutoPlaceOnActionSlot(slot) else self:Print("Auto-place API not available.") end
    end
  elseif cmd == "clearplace" then
    if self.ClearAutoPlace then self:ClearAutoPlace() else self:Print("ClearAutoPlace API not available.") end
  elseif cmd == "showbuff" then
    -- Show buff refresh mappings and remaining times
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    local map = OneButtonAssistantDB.buffRefresh or {}
    if next(map) == nil then
      self:Print("No buff refresh mappings configured. Use /oba setbuff <buffName> <spellKey> [threshold]")
    else
      self:Print("Buff refresh mappings:")
      for buff, cfg in pairs(map) do
        local rem = nil
        if self.Engine and self.Engine.GetBuffRemaining then rem = self.Engine:GetBuffRemaining(buff) end
        local ready = "unknown"
        if cfg and cfg.spellKey and type(cfg.spellKey) == "string" then
          -- try to query cooldown via GetSpellCooldown (safe)
          local ok, start, dur, enabled = pcall(function() return GetSpellCooldown(cfg.spellKey) end)
          if ok and start and dur and dur > 0 then
            local expires = (start + dur)
            local now = GetTime and GetTime() or time()
            if expires <= now then ready = "ready" else ready = string.format("ready in %.1fs", expires - now) end
          elseif ok and start and dur and dur == 0 then ready = "ready" end
        end
        self:Print(string.format("- %s -> %s (threshold %.1fs) remaining: %s cooldown: %s", tostring(buff), tostring(cfg.spellKey), tonumber(cfg.refreshThreshold) or 0, tostring(rem or "n/a"), tostring(ready)))
      end
    end
  elseif cmd == "debug" then
    -- runtime debug control: /oba debug on|off|ui
    local sub = rest:match("^(%S+)") or ""
    sub = tostring(sub):lower()
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    if sub == "on" then
      OneButtonAssistantDB.debugPrints = true
      self:Print("Debug prints enabled (OneButtonAssistantDB.debugPrints = true)")
    elseif sub == "off" then
      OneButtonAssistantDB.debugPrints = false
      self:Print("Debug prints disabled (OneButtonAssistantDB.debugPrints = false)")
    elseif sub == "ui" or sub == "window" or sub == "frame" or sub == "show" then
      -- Toggle the existing debug UI (same behavior as before)
      if not self.ToggleDebugUI then
        function OBA:ToggleDebugUI()
          if self._debugFrame and self._debugFrame:IsShown() then
            self._debugFrame:Hide()
            return
          end
          if not self._debugFrame then
            local f = CreateFrame("Frame", "OneButtonAssistantDebugFrame", UIParent)
            f:SetSize(220, 120)
            f:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
            f.bg = f:CreateTexture(nil, "BACKGROUND")
            f.bg:SetAllPoints()
            f.bg:SetColorTexture(0,0,0,0.6)
            f.text = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
            f.text:SetPoint("TOPLEFT", 6, -8)
            f.text:SetJustifyH("LEFT")
            f:SetMovable(true)
            f:EnableMouse(true)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", function(self) self:StartMoving() end)
            f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
            self._debugFrame = f
          end
          self._debugFrame:Show()
          if self.UpdateDebugFrame then pcall(self.UpdateDebugFrame, self) end
        end

        function OBA:UpdateDebugFrame()
          if not self._debugFrame or not self._debugFrame:IsShown() then return end
          local lines = {}
          local sug = nil
          pcall(function() sug = self:GetNextActionForUnit("target") end)
          table.insert(lines, "Suggestion: " .. (sug and (tostring(sug.name) .. " (" .. tostring(sug.reason) .. ")") or "none"))
          table.insert(lines, "")
          table.insert(lines, "Tracked buffs:")
          if OneButtonAssistantDB and OneButtonAssistantDB.buffRefresh then
            for b,c in pairs(OneButtonAssistantDB.buffRefresh) do
              local rem = nil
              pcall(function() if self.Engine and self.Engine.GetBuffRemaining then rem = self.Engine:GetBuffRemaining(b) end end)
              table.insert(lines, string.format("%s -> %s (rem: %s)", tostring(b), tostring(c.spellKey), tostring(rem or "n/a")))
            end
          else
            table.insert(lines, "(none)")
          end
          self._debugFrame.text:SetText(table.concat(lines, "\n"))
        end
      end
      self:ToggleDebugUI()
    else
      self:Print("Usage: /oba debug on|off|ui  (use 'ui' to show the debug frame)")
    end
    elseif cmd == "hold" then
      -- /oba hold ui|show|status|set|reset
      local sub, arg = rest:match("^(%S*)%s*(.*)$")
      sub = sub or ""
      arg = arg or ""
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      if sub == "ui" or sub == "show" then
        if not self.ToggleHoldUI then
          function OBA:ToggleHoldUI()
            if self._holdFrame and self._holdFrame:IsShown() then self._holdFrame:Hide(); return end
            if not self._holdFrame then
              local f = CreateFrame("Frame", "OneButtonAssistantHoldFrame", UIParent)
              f:SetSize(340, 280)
              f:SetPoint("CENTER", UIParent, "CENTER", 0, 50)
              f.bg = f:CreateTexture(nil, "BACKGROUND")
              f.bg:SetAllPoints()
              f.bg:SetColorTexture(0,0,0,0.7)
              f.title = f:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
              f.title:SetPoint("TOP", 0, -10)
              f.title:SetText("OneButtonAssistant — Hold Settings")

              local entries = {
                { key = "clearHoldSeconds", label = "Clear hold (sec)", def = 0.75 },
                { key = "clearHoldStep", label = "Hold step (sec)", def = 0.25 },
                { key = "maxClearHoldSeconds", label = "Max hold (sec)", def = 5.0 },
                { key = "clearHoldDecayThreshold", label = "Decay threshold (clicks)", def = 3 },
                { key = "clearHoldDecayCooldownMinutes", label = "Decay cooldown (min)", def = 5 },
                { key = "clearHoldMin", label = "Min hold (sec)", def = 0.75 },
              }

              f.fields = {}
              for i, e in ipairs(entries) do
                local y = -30 - (i-1) * 36
                local lbl = f:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
                lbl:SetPoint("TOPLEFT", 14, y)
                lbl:SetJustifyH("LEFT")
                lbl:SetText(e.label)
                local eb = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
                eb:SetSize(140, 24)
                eb:SetPoint("TOPRIGHT", -14, y)
                eb:SetAutoFocus(false)
                eb:SetText(tostring(OneButtonAssistantDB[e.key] or e.def))
                f.fields[e.key] = { edit = eb, def = e.def }
              end

              -- Apply button
              local apply = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
              apply:SetSize(100, 26)
              apply:SetPoint("BOTTOMRIGHT", -14, 12)
              apply:SetText("Apply")
              apply:SetScript("OnClick", function()
                OneButtonAssistantDB = OneButtonAssistantDB or {}
                for k,v in pairs(f.fields) do
                  local txt = v.edit:GetText() or tostring(v.def)
                  local num = tonumber(txt)
                  if num ~= nil then OneButtonAssistantDB[k] = num else OneButtonAssistantDB[k] = txt end
                end
                if OneButtonAssistantDB.debugPrints then print(string.format("OneButtonAssistant: Hold settings applied (hold=%.2f)", OneButtonAssistantDB.clearHoldSeconds or 0.75)) end
              end)

              -- Reset button
              local reset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
              reset:SetSize(100, 26)
              reset:SetPoint("BOTTOMLEFT", 14, 12)
              reset:SetText("Reset")
              reset:SetScript("OnClick", function()
                for k,v in pairs(f.fields) do
                  v.edit:SetText(tostring(v.def))
                  OneButtonAssistantDB[k] = v.def
                end
                if OneButtonAssistantDB.debugPrints then print("OneButtonAssistant: Hold settings reset to defaults") end
              end)

              -- Close on Esc
              f:SetPropagateKeyboardInput(true)
              f:SetScript("OnKeyDown", function(self, key)
                if key == "ESCAPE" then self:Hide() end
              end)

              f:SetMovable(true)
              f:EnableMouse(true)
              f:RegisterForDrag("LeftButton")
              f:SetScript("OnDragStart", function(self) self:StartMoving() end)
              f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

              self._holdFrame = f
            end
            self._holdFrame:Show()
          end
        end
        self:ToggleHoldUI()
      elseif sub == "set" then
        local v = tonumber(arg)
        if not v then self:Print("Usage: /oba hold set <seconds>") else OneButtonAssistantDB.clearHoldSeconds = v; self:Print(string.format("Set clearHoldSeconds = %.2f", v)) end
      elseif sub == "reset" then
        OneButtonAssistantDB.clearHoldSeconds = 0.75
        OneButtonAssistantDB.clearHoldStep = 0.25
        OneButtonAssistantDB.maxClearHoldSeconds = 5.0
        OneButtonAssistantDB.clearHoldDecayThreshold = 3
        OneButtonAssistantDB.clearHoldDecayCooldownMinutes = 5
        OneButtonAssistantDB.clearHoldMin = 0.75
        self:Print("Hold settings reset to defaults.")
      elseif sub == "status" or sub == "show" then
        self:Print(string.format("clearHoldSeconds=%.2f, step=%.2f, max=%.2f, decayThreshold=%d, cooldownMin=%.1f, min=%.2f",
          tonumber(OneButtonAssistantDB.clearHoldSeconds or 0.75), tonumber(OneButtonAssistantDB.clearHoldStep or 0.25), tonumber(OneButtonAssistantDB.maxClearHoldSeconds or 5.0), tonumber(OneButtonAssistantDB.clearHoldDecayThreshold or 3), tonumber(OneButtonAssistantDB.clearHoldDecayCooldownMinutes or 5), tonumber(OneButtonAssistantDB.clearHoldMin or 0.75)))
      else
        self:Print("Usage: /oba hold ui|show|status|set <sec>|reset")
      end
  elseif cmd == "testcast" then
    local v = rest
    if not v or v == "" then
      self:Print("Usage: /oba testcast <spellName or spell:<id> | spellId>")
    else
      if self.SetButtonSuggestion then
        self:SetButtonSuggestion(v)
        self:Print("Test suggestion set: "..tostring(v))
      else
        self:Print("Button API not available.")
      end
    end
  elseif cmd == "icons" then
    if self.ToggleIconBrowser then pcall(self.ToggleIconBrowser, self) else self:Print("Icon browser not available.") end
  elseif cmd == "spellspy" then
    local sub = rest:match("^(%S+)") or ""
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    if sub == "on" then
      OneButtonAssistantDB.spellSpyEnabled = true
      if self.adapters and self.adapters.spellspy and self.adapters.spellspy.Enable then pcall(self.adapters.spellspy.Enable, self.adapters.spellspy, true) end
      self:Print("SpellSpy adapter enabled (listening to combat log).")
    elseif sub == "off" then
      OneButtonAssistantDB.spellSpyEnabled = false
      if self.adapters and self.adapters.spellspy and self.adapters.spellspy.Enable then pcall(self.adapters.spellspy.Enable, self.adapters.spellspy, false) end
      self:Print("SpellSpy adapter disabled.")
    else
      self:Print("Usage: /oba spellspy on|off (auto-add aliases from combat log)")
    end
  elseif cmd == "bg" then
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    local sub, arg = rest:match("^(%S*)%s*(.*)$")
    sub = sub or ""
    arg = arg or ""
    if sub == "start" then
      if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.Start then
        local ok = pcall(OneButtonAssistantBGLogger.Start, OneButtonAssistantBGLogger)
        if ok then self:Print("BG logging started.") else self:Print("Failed to start BG logging.") end
      else
        self:Print("BG logger not available.")
      end
    elseif sub == "stop" then
      if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.Stop then
        local ok = pcall(OneButtonAssistantBGLogger.Stop, OneButtonAssistantBGLogger)
        if ok then self:Print("BG logging stopped.") else self:Print("Failed to stop BG logging.") end
      else
        self:Print("BG logger not available.")
      end
    elseif sub == "export" then
      local id = arg
      if id == "" then
        self:Print("Usage: /oba bg export <matchID>  — puts selected match into OneButtonAssistantDB.bgExport for extraction.")
      else
        if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.Export then
          local ok, res = pcall(OneButtonAssistantBGLogger.Export, OneButtonAssistantBGLogger, id)
          if ok and res then self:Print("Exported match "..tostring(id).." to OneButtonAssistantDB.bgExport") else self:Print("Match not found or export failed.") end
        else
          self:Print("BG logger not available.")
        end
      end
    elseif sub == "exportall" or sub == "exportchunks" then
      -- /oba bg exportall [linesPerChunk]
      local lines = tonumber(arg) or (OneButtonAssistantDB and OneButtonAssistantDB.bgConfig and OneButtonAssistantDB.bgConfig.exportChunkLines) or 500
      if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.PrepareAllChunks then
        local ok, res = pcall(OneButtonAssistantBGLogger.PrepareAllChunks, OneButtonAssistantBGLogger, lines)
        if ok and res then
          local count = 0
          for id,n in pairs(res) do count = count + 1 end
          self:Print(string.format("Prepared chunked exports for %d matches (linesPerChunk=%d). Chunks available in OneButtonAssistantDB.bgExportChunks.<matchID>", count, lines))
        else
          self:Print("Failed to prepare chunked exports.")
        end
      else
        self:Print("BG logger chunked export API not available.")
      end
    elseif sub == "clear" then
      if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.Clear then
        local ok = pcall(OneButtonAssistantBGLogger.Clear, OneButtonAssistantBGLogger)
        if ok then self:Print("Cleared saved BG logs.") else self:Print("Failed to clear BG logs.") end
      else
        self:Print("BG logger not available.")
      end
    elseif sub == "list" then
      if OneButtonAssistantBGLogger and OneButtonAssistantBGLogger.GetAll then
        local ok, logs = pcall(OneButtonAssistantBGLogger.GetAll, OneButtonAssistantBGLogger)
        if ok and logs then
          self:Print(string.format("Saved matches: %d", #logs))
          for i = 1, math.min(#logs, 50) do local m = logs[i]; self:Print(string.format("%d: %s (events=%d) start=%s", i, tostring(m.meta.matchID), tonumber(m.meta.events) or 0, tostring(m.meta.startTime))) end
        else
          self:Print("No saved BG logs.")
        end
      else
        self:Print("BG logger not available.")
      end
    else
      self:Print("Usage: /oba bg start|stop|list|export <matchID>|clear")
    end
  elseif cmd == "saveall" or cmd == "exportdata" then
    -- Snapshot selected addon state into SavedVariables so the external tool
    -- (assistant) can read it after logout. Stored under OneButtonAssistantDB.agentExport.<id>
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    local nowt = (GetTime and GetTime()) or time()
    local id = tostring(math.floor(nowt)) .. "-" .. tostring(math.random(1000,9999))
    local snap = { meta = { created = nowt, id = id, player = {} }, data = {} }
    -- safe player info
    pcall(function()
      local ok, pname = pcall(UnitName, "player")
      local ok2, _, pclass = pcall(UnitClass, "player")
      local ok3, realm = pcall(GetRealmName)
      snap.meta.player.name = ok and pname or "unknown"
      snap.meta.player.class = ok2 and pclass or "UNKNOWN"
      snap.meta.player.realm = ok3 and realm or "unknown"
    end)
    -- copy a whitelist of saved-variables and runtime state we care about
    local keys = { "SpellSpy", "bgLogs", "bgConfig", "bgExport", "bgExportChunks", "bgExportManifest", "adapterProbe", "loggerDump", "heuristics", "aliases", "macroBatchPending", "lastRawSuggestion" }
    for _,k in ipairs(keys) do
      if OneButtonAssistantDB[k] ~= nil then snap.data[k] = OneButtonAssistantDB[k] end
    end
    -- adapters list
    if self.adapters then
      local al = {}
      for an,_ in pairs(self.adapters) do table.insert(al, an) end
      snap.data.adapters = al
    end
    OneButtonAssistantDB.agentExport = OneButtonAssistantDB.agentExport or {}
    OneButtonAssistantDB.agentExport[id] = snap
    self:Print(string.format("Saved agent export: OneButtonAssistantDB.agentExport['%s'] (logout to persist)", id))
  elseif cmd == "alias" then
    local verb, a, b = rest:match("^(%S+)%s*(%S*)%s*(.*)$")
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
    if verb == "set" and a ~= "" and b ~= "" then
      OneButtonAssistantDB.aliases[a:lower()] = b
      self:Print(string.format("Alias set: %s -> %s", a, b))
    elseif verb == "del" and a ~= "" then
      OneButtonAssistantDB.aliases[a:lower()] = nil
      self:Print(string.format("Alias removed: %s", a))
    elseif verb == "list" then
      if next(OneButtonAssistantDB.aliases) == nil then self:Print("No aliases configured.") else for k,v in pairs(OneButtonAssistantDB.aliases) do self:Print(string.format("%s -> %s", tostring(k), tostring(v))) end end
    else
      self:Print("Usage: /oba alias set <token> <map> | del <token> | list")
    end
  elseif cmd == "heuristics" then
    -- Operate on OneButtonAssistantDB.heuristics for authoritative info
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
    OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
    local sub, token = rest:match("^(%S*)%s*(%S*)$")
    sub = sub or ""
    token = token or ""
    if sub == "list" or sub == "ls" then
      local found = false
      for k,v in pairs(OneButtonAssistantDB.heuristics) do
        found = true
        local val = v.value or tostring(OneButtonAssistantDB.aliases[k] or "(unknown)")
        local tnum = v.time or (GetTime and GetTime() or nil)
        local timestr = tnum and tostring(tnum) or "(no time)"
        -- try to format readable time if os.date available
        local ok, f = pcall(function()
          if type(os) == "table" and os.date and tnum then return os.date("%c", math.floor(tnum)) end
        end)
        if ok and f and f ~= "" then timestr = f end
        local src = v.source or "engine"
        self:Print(string.format("%s -> %s (at %s) [%s]", tostring(k), tostring(val), tostring(timestr), tostring(src)))
      end
      if not found then self:Print("No heuristic aliases present.") end
    elseif sub == "show" then
      if token == "" then self:Print("Usage: /oba heuristics show <token>") else
        local lk = tostring(token):lower()
        local entry = OneButtonAssistantDB.heuristics[lk]
        if not entry then self:Print(string.format("No heuristic entry for '%s'", lk)) else
          local val = entry.value or tostring(OneButtonAssistantDB.aliases[lk] or "(unknown)")
          local tnum = entry.time or (GetTime and GetTime() or nil)
          local timestr = tnum and tostring(tnum) or "(no time)"
          local ok, f = pcall(function()
            if type(os) == "table" and os.date and tnum then return os.date("%c", math.floor(tnum)) end
          end)
          if ok and f and f ~= "" then timestr = f end
          local src = entry.source or "engine"
          self:Print(string.format("heuristic %s -> %s", lk, tostring(val)))
          self:Print(string.format("  added: %s  source: %s", tostring(timestr), tostring(src)))
        end
      end
    elseif sub == "clear" then
      if token == "" then
        local removed = 0
        for k,_ in pairs(OneButtonAssistantDB.heuristics) do
          OneButtonAssistantDB.heuristics[k] = nil
          if OneButtonAssistantDB.aliases and OneButtonAssistantDB.aliases[k] then OneButtonAssistantDB.aliases[k] = nil end
          removed = removed + 1
        end
        self:Print(string.format("Cleared %d heuristic aliases.", removed))
      else
        local lk = tostring(token):lower()
        if OneButtonAssistantDB.heuristics[lk] then
          OneButtonAssistantDB.heuristics[lk] = nil
          if OneButtonAssistantDB.aliases and OneButtonAssistantDB.aliases[lk] then OneButtonAssistantDB.aliases[lk] = nil end
          self:Print(string.format("Cleared heuristic alias: %s", lk))
        else
          self:Print(string.format("No heuristic alias found for '%s'", tostring(token)))
        end
      end
    else
      self:Print("Usage: /oba heuristics list | /oba heuristics show <token> | /oba heuristics clear [token]")
    end
      -- end heuristics
    elseif cmd == "heuristics" then
      -- noop placeholder to avoid fall-through
  else
    self:Print("Commands: /oba test | /oba next | /oba probe | /oba log")
  end
end

function OBA:SetBuffRefresh(buffName, spellKey, threshold)
  if not buffName or not spellKey then return false end
  threshold = tonumber(threshold) or 5
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.buffRefresh = OneButtonAssistantDB.buffRefresh or {}
  OneButtonAssistantDB.buffRefresh[buffName] = { spellKey = spellKey, refreshThreshold = threshold }
  if self.Engine and self.Engine.SetBuffRefreshMap then
    self.Engine:SetBuffRefreshMap(OneButtonAssistantDB.buffRefresh)
  end
  self:Print(string.format("Configured buff '%s' -> %s (threshold %.1fs)", buffName, spellKey, threshold))
  return true
end

function OBA:PromoteHeuristic(token)
  if not token then return false end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
  OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
  local lk = tostring(token):lower()
  local entry = OneButtonAssistantDB.heuristics[lk]
  if not entry then return false end
  OneButtonAssistantDB.aliases[lk] = entry.value or OneButtonAssistantDB.aliases[lk]
  OneButtonAssistantDB.heuristics[lk] = nil
  self:Print(string.format("Heuristic promoted: %s -> %s", lk, tostring(OneButtonAssistantDB.aliases[lk])))
  return true
end

function OBA:RejectHeuristic(token)
  if not token then return false end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.heuristics = OneButtonAssistantDB.heuristics or {}
  OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
  local lk = tostring(token):lower()
  local entry = OneButtonAssistantDB.heuristics[lk]
  if not entry then return false end
  -- only remove alias if it matches the heuristic value (avoid deleting user-set aliases)
  if OneButtonAssistantDB.aliases and OneButtonAssistantDB.aliases[lk] == entry.value then
    OneButtonAssistantDB.aliases[lk] = nil
  end
  OneButtonAssistantDB.heuristics[lk] = nil
  self:Print(string.format("Heuristic rejected: %s", lk))
  return true
end

-- Create a set of macros that invoke common /oba subcommands and place them on action slots between startSlot..endSlot (inclusive)
function OBA:CreateSlashMacroSet(startSlot, endSlot)
  startSlot = tonumber(startSlot) or 25
  endSlot = tonumber(endSlot) or 48
  if startSlot < 1 then startSlot = 1 end
  if endSlot < startSlot then endSlot = startSlot end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.macroBatchPending = OneButtonAssistantDB.macroBatchPending or {}

  -- canonical list of commands to create macros for. Keep concise; subcommands needing args get a basic macro body.
  local cmdList = {
    "test",
    "next",
    "info",
    "dumplastraw",
    "probe",
    "log",
    "showraw",
    "showrawfull",
    "showbuff",
    "bind",
    "unbind",
    "autoplace",
    "clearplace",
    "debug",
    "icons",
    "spellspy on",
    "spellspy off",
    "alias list",
    "heuristics list",
    "heuristics autoconfirm off",
  }

  -- Add class-specific macro tokens so users get useful per-class quick macros.
  local classSpecific = {
    DEATHKNIGHT = {
      -- use testcast so macros call the test suggestion path and set the button suggestion
      "testcast deathgrip",
      "testcast raisedead",
      "testcast armyofthedead",
      "testcast asphyxiate",
      "testcast mindfreeze",
      "testcast antimagic_shell",
      "testcast icebound_fortitude",
    },
    DEMONHUNTER = {
      -- Demon Hunter: Havoc (DPS) and Vengeance (Tank) quick checks
      "testcast chaos_strike",
      "testcast eye_beam",
      "testcast fel_rush",
      "testcast vengeful_retreat",
      "testcast metamorphosis",
      "testcast demon_spikes",
      "testcast soul_cleave",
      "testcast fiery_brand",
    },
    DRUID = {
      -- general Druid utilities and forms
      "testcast bear_form",
      "testcast cat_form",
      "testcast travel_form",
      "testcast aquatic_form",
      "testcast moonkin_form",
      -- crowd control / defensive
      "testcast entangling_roots",
      "testcast hibernate",
      "testcast cyclone",
      "testcast barkskin",
      "testcast rebirth",
      "testcast dash",
      "testcast stampeding_roar",
      "testcast innervate",
      "testcast natures_cure",
      -- spec-core shortcuts
      "testcast moonfire",
      "testcast starfall",
      "testcast shred",
      "testcast rip",
      "testcast mangle",
      "testcast rejuvenation",
      "testcast wild_growth",
      "testcast tranquility",
    },
    MAGE = {
      -- Mage utilities and core spells
      "testcast arcane_intellect",
      "testcast blink",
      "testcast polymorph",
      "testcast spell:2139",
      "testcast spellsteal",
      "testcast ice_block",
      "testcast mirror_image",
      "testcast slow_fall",
      "testcast portal",
      "testcast teleport",
      -- talents/util
      "testcast dragons_breath",
      "testcast blast_wave",
      "testcast ring_of_frost",
      "testcast mass_invisibility",
      "testcast temporal_warp",
      -- Arcane
      "testcast arcane_blast",
      "testcast arcane_missiles",
      "testcast arcane_barrage",
      "testcast evocation",
      -- Fire
      "testcast fireball",
      "testcast pyroblast",
      "testcast flamestrike",
      "testcast combustion",
      -- Frost
      "testcast frostbolt",
      "testcast ice_lance",
      "testcast flurry",
      "testcast blizzard",
    },
    MONK = {
      -- Monk general utilities
      "testcast roll",
      "testcast provoke",
      "testcast paralysis",
      "testcast transcendence",
      "testcast detox",
      "testcast touch_of_death",
      "testcast fortifying_brew",
      "testcast expel_harm",
      "testcast vivify",
      "testcast tiger_palm",
      -- talents / utility
      "testcast ring_of_peace",
      "testcast diffuse_magic",
      "testcast dampen_harm",
      "testcast chi_torpedo",
      "testcast jade_serpent_statue",
      -- Brewmaster
      "testcast keg_smash",
      "testcast breath_of_fire",
      "testcast purifying_brew",
      "testcast celestial_brew",
      -- Mistweaver
      "testcast enveloping_mist",
      "testcast essence_font",
      "testcast renewing_mist",
      "testcast soothing_mist",
      -- Windwalker
      "testcast blackout_kick",
      "testcast rising_sun_kick",
      "testcast fists_of_fury",
      "testcast spinning_crane_kick",
    },
    PALADIN = {
      -- Paladin core utilities and blessings
      "testcast judgment",
      "testcast crusader_strike",
      "testcast hammer_of_justice",
      "testcast divine_shield",
      "testcast lay_on_hands",
      "testcast blessing_of_freedom",
      "testcast blessing_of_protection",
      "testcast blessing_of_sacrifice",
      "testcast flash_of_light",
      "testcast cleanse_toxins",
      "testcast consecration",
      "testcast divine_steed",
      -- talents / utility
      "testcast holy_prism",
      "testcast repentance",
      "testcast hammer_of_wrath",
      "testcast divine_toll",
      "testcast shield_of_vengeance",
      -- Holy
      "testcast holy_light",
      "testcast light_of_dawn",
      "testcast holy_shock",
      "testcast beacon_of_light",
      -- Protection
      "testcast shield_of_the_righteous",
      "testcast avengers_shield",
      "testcast hammer_of_the_righteous",
      "testcast guardian_of_ancient_kings",
      -- Retribution
      "testcast blade_of_justice",
      "testcast templars_verdict",
      "testcast divine_storm",
      "testcast wake_of_ashes",
    },
    PRIEST = {
      -- Priest: Discipline / Holy / Shadow
      "testcast penance",
      "testcast atonement",
      "testcast pain_suppression",
      "testcast holy_word",
      "testcast holy_word_serenity",
      "testcast renew",
      "testcast vampiric_touch",
      "testcast devouring_plague",
    },
    SHAMAN = {
      -- Shaman core abilities and totem utilities
      "testcast spell:403",
      "testcast spell:8050",
      "testcast spell:8056",
      "testcast spell:421",
      "testcast spell:8004",
      "testcast spell:2645",
      "testcast spell:20608",
      "testcast purge",
      "testcast spell:8143",
      "testcast spell:192058",
      "testcast wind_shear",
      "testcast spell:108271",
      -- talents / utility
      "testcast earthgrab_totem",
      "testcast thunderstorm",
      "testcast spell:58875",
      "testcast totemic_projection",
      "testcast spell:108281",
      -- Elemental
      "testcast lava_burst",
      "testcast spell:8042",
      "testcast spell:61882",
      -- Enhancement
      "testcast spell:17364",
      "testcast spell:60103",
      "testcast spell:187874",
      "testcast spell:51533",
      -- Restoration
      "testcast spell:77472",
      "testcast spell:1064",
      "testcast spell:73920",
      "testcast spell:61295",
    },
    WARLOCK = {
      -- Warlock summons, utilities, and core spells
      "testcast summon_demon",
      "testcast health_funnel",
      "testcast soulstone",
      "testcast create_healthstone",
      "testcast fear",
      "testcast corruption",
      "testcast drain_life",
      "testcast unending_resolve",
      "testcast demonic_gateway",
      "testcast ritual_of_summoning",
      -- talents / utility
      "testcast howl_of_terror",
      "testcast mortal_coil",
      "testcast shadowfury",
      "testcast soulburn",
      "testcast demonic_circle",
      -- Affliction
      "testcast agony",
      "testcast unstable_affliction",
      "testcast drain_soul",
      "testcast seed_of_corruption",
      -- Demonology
      "testcast hand_of_guldan",
      "testcast demonbolt",
      "testcast summon_felguard",
      "testcast call_dreadstalkers",
      -- Destruction
      "testcast incinerate",
      "testcast conflagrate",
      "testcast chaos_bolt",
      "testcast rain_of_fire",
    },
    WARRIOR = {
      -- Warrior core abilities and utilities
      "testcast charge",
      "testcast heroic_leap",
      "testcast execute",
      "testcast victory_rush",
      "testcast shield_slam",
      "testcast pummel",
      "testcast rallying_cry",
      "testcast intimidating_shout",
      "testcast berserker_rage",
      "testcast hamstring",
      "testcast battle_shout",
      -- talents / utility
      "testcast shockwave",
      "testcast storm_bolt",
      "testcast spell_reflection",
      "testcast thunder_clap",
      "testcast avatar",
      -- Arms
      "testcast mortal_strike",
      "testcast overpower",
      "testcast colossus_smash",
      "testcast sweeping_strikes",
      -- Fury
      "testcast bloodthirst",
      "testcast raging_blow",
      "testcast rampage",
      "testcast enrage",
      -- Protection
      "testcast shield_block",
      "testcast revenge",
      "testcast devastate",
      "testcast last_stand",
    },
    ROGUE = {
      -- Rogue stealth/utilities and core abilities
      "testcast stealth",
      "testcast sap",
      "testcast cheap_shot",
      "testcast spell:1766",
      "testcast blind",
      "testcast vanish",
      "testcast cloak_of_shadows",
      "testcast evasion",
      "testcast sprint",
      "testcast pick_lock",
      "testcast pick_pocket",
      "testcast crimson_vial",
      "testcast shiv",
      -- talents / utility
      "testcast gouge",
      "testcast distract",
      "testcast shadowstep",
      "testcast smoke_bomb",
      "testcast thistle_tea",
      -- Assassination
      "testcast mutilate",
      "testcast rupture",
      "testcast envenom",
      "testcast garrote",
      -- Outlaw
      "testcast sinister_strike",
      "testcast pistol_shot",
      "testcast between_the_eyes",
      "testcast roll_the_bones",
      -- Subtlety
      "testcast backstab",
      "testcast shadowstrike",
      "testcast eviscerate",
      "testcast symbols_of_death",
    },
    HUNTER = {
      -- core hunter abilities and utility shortcuts
      "testcast auto_shot",
      "testcast arcane_shot",
      "testcast steady_shot",
      "testcast kill_shot",
      "testcast hunters_mark",
      "testcast tranquilizing_shot",
      "testcast feign_death",
      "testcast disengage",
      "testcast aspect_cheetah",
      "testcast aspect_turtle",
      "testcast misdirection",
      "testcast revive_pet",
      "testcast mend_pet",
      "testcast call_pet",
      -- talent/util
      "testcast binding_shot",
      "testcast scatter_shot",
      "testcast explosive_trap",
      "testcast steel_trap",
      "testcast intimidation",
      -- Beast Mastery shortcuts
      "testcast kill_command",
      "testcast bestial_wrath",
      "testcast dire_beast",
      "testcast barbed_shot",
      -- Marksmanship shortcuts
      "testcast aimed_shot",
      "testcast rapid_fire",
      "testcast multi_shot",
      "testcast volley",
      -- Survival shortcuts
      "testcast raptor_strike",
      "testcast mongoose_bite",
      "testcast carve",
      "testcast explosive_shot",
    },
  }
  -- initialize placement slot pointer before iterating class-specific macros
  local slot = startSlot
  local _, pclass = pcall(UnitClass, "player")
  if pclass and classSpecific[pclass] then
    for _, item in ipairs(classSpecific[pclass]) do
      if slot > endSlot then break end
      local macroName = "OBA - " .. (item:gsub("%s+", "_"))
      local macroBody = "/oba " .. item
      if type(CreateMacro) == "function" and GetMacroIndexByName(macroName) == 0 then pcall(function() CreateMacro(macroName, "INV_Misc_QuestionMark", macroBody, true) end) end
      -- only queue placement if macro not already placed and slot empty
      local idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(macroName) or 0
      local alreadyPlaced = false
      if idx and idx > 0 and type(GetActionInfo) == "function" then
        for s=1,120 do local atype, aid = GetActionInfo(s); if atype == "macro" and aid == idx then alreadyPlaced = true; break end end
      end
      local slotOccupied = false
      if type(GetActionInfo) == "function" then local atype = select(1, GetActionInfo(slot)); if atype and atype ~= "" then slotOccupied = true end end
      if not alreadyPlaced and not slotOccupied then
        local dup = false
        for _, e in ipairs(OneButtonAssistantDB.macroBatchPending) do if e.name == macroName then dup = true; break end end
        if not dup then table.insert(OneButtonAssistantDB.macroBatchPending, { name = macroName, slot = slot }) end
      end
      slot = slot + 1
    end
  end

  slot = startSlot
  for i, c in ipairs(cmdList) do
    if slot > endSlot then break end
    local macroName = "OBA - " .. (c:gsub("%s+", "_"))
    local macroBody = "/oba " .. c
    -- ensure macro exists
    if type(CreateMacro) == "function" then
      if GetMacroIndexByName(macroName) == 0 then
        pcall(function() CreateMacro(macroName, "INV_Misc_QuestionMark", macroBody, true) end)
      end
    end
    -- determine whether to queue placement: only if macro is not already placed anywhere and target slot is empty
    local idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(macroName) or 0
    local alreadyPlaced = false
    if idx and idx > 0 and type(GetActionInfo) == "function" then
      for s=1,120 do
        local atype, aid = GetActionInfo(s)
        if atype == "macro" and aid == idx then alreadyPlaced = true; break end
      end
    end
    local slotOccupied = false
    if type(GetActionInfo) == "function" then
      local atype = select(1, GetActionInfo(slot))
      if atype and atype ~= "" then slotOccupied = true end
    end
    if not alreadyPlaced and not slotOccupied then
      -- avoid duplicate pending entries
      local dup = false
      for _, e in ipairs(OneButtonAssistantDB.macroBatchPending) do if e.name == macroName then dup = true; break end end
      if not dup then table.insert(OneButtonAssistantDB.macroBatchPending, { name = macroName, slot = slot }) end
    end
    slot = slot + 1
  end

  -- attempt immediate placement if out of combat
  if InCombatLockdown() then
    self:Print("In combat — macro placements deferred until after combat.")
    -- register a one-off regen handler to place pending macros
    if not self._batchMacroRegenFrame then
      local f = CreateFrame("Frame")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
      f:SetScript("OnEvent", function()
        if OneButtonAssistantDB and OneButtonAssistantDB.macroBatchPending and #OneButtonAssistantDB.macroBatchPending > 0 then
          pcall(function() OBA:PlacePendingMacroBatch() end)
        end
      end)
      self._batchMacroRegenFrame = f
    end
    return true
  else
    return pcall(function() self:PlacePendingMacroBatch() end)
  end
end

function OBA:PlacePendingMacroBatch()
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  local pending = OneButtonAssistantDB.macroBatchPending or {}
  if #pending == 0 then self:Print("No pending macro placements."); return true end
  for _, item in ipairs(pending) do
    local name = item.name
    local slot = tonumber(item.slot) or 0
    if name and slot >= 1 and slot <= 120 then
      local idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(name) or 0
      if idx == 0 then
        -- macro missing (create minimal macro body)
        if type(CreateMacro) == "function" then CreateMacro(name, "INV_Misc_QuestionMark", "/script print('macro missing')", true); idx = GetMacroIndexByName(name) end
      end
      if idx and idx > 0 then
        -- skip if macro already placed somewhere
        local alreadyPlaced = false
        if type(GetActionInfo) == "function" then
          for s=1,120 do
            local atype, aid = GetActionInfo(s)
            if atype == "macro" and aid == idx then alreadyPlaced = true; break end
          end
        end
        if alreadyPlaced then
          -- nothing to do
        else
          -- only place if target slot is empty (avoid moving existing actions)
          local atype = nil
          if type(GetActionInfo) == "function" then atype = select(1, GetActionInfo(slot)) end
          if not atype or atype == "" then
            pcall(function()
              PickupMacro(idx)
              PlaceAction(slot)
              ClearCursor()
            end)
          end
        end
      end
    end
  end
  -- clear pending list
  OneButtonAssistantDB.macroBatchPending = {}
  self:Print("Placed macros for /oba commands on requested action slots.")
  return true
end


function OBA:BuildStateFromAdapters(unit)
  local state = {}
  local externalSuggestion = nil
  if self.adapters then
    for name, adapter in pairs(self.adapters) do
      if adapter and adapter.IsAvailable and adapter:IsAvailable() then
        if adapter.FetchState then
          local ok, s = pcall(adapter.FetchState, adapter, unit)
          if ok and type(s) == "table" then for k,v in pairs(s) do state[k] = v end end
        end
        if not externalSuggestion and adapter.GetSuggestion then
          local ok2, sug = pcall(adapter.GetSuggestion, adapter, unit)
          if ok2 and sug then
            externalSuggestion = sug
            if self.SaveRawSuggestion and type(self.SaveRawSuggestion) == "function" then pcall(self.SaveRawSuggestion, self, name, (sug.raw or sug)) end
          end
        end
      end
    end
  end

  -- saved-variables / capture fallback
  if not externalSuggestion and OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion then
    for k,v in pairs(OneButtonAssistantDB.lastRawSuggestion) do
      if type(v) == "table" then
        local key = v.key or v.spell or v.suggestion or v.next or v.action or v.name or (v[1] and tostring(v[1]))
        if key then
          externalSuggestion = { key = key, name = tostring(key), raw = v, reason = "saved:" .. tostring(k) }
          if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "saved_raw_suggestion", { adapter = k, suggestion = externalSuggestion }) end
          break
        end
      end
    end
    if not externalSuggestion and OneButtonAssistantDB.lastRawSuggestion.capture and type(OneButtonAssistantDB.lastRawSuggestion.capture.entries) == "table" and #OneButtonAssistantDB.lastRawSuggestion.capture.entries > 0 then
      local e = OneButtonAssistantDB.lastRawSuggestion.capture.entries[1]
      if e then
        local key = e.spellId or e.spellName or e.spell
        if key then
          externalSuggestion = { key = tostring(key), name = tostring(e.spellName or key), raw = e, reason = "capture" }
          if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "capture_suggestion", externalSuggestion) end
        end
      end
    end
  end
  return state, externalSuggestion
end

-- Debounced update queue: coalesce frequent events (like COMBAT_LOG) into a single update call
function OBA:QueueUpdate(unit)
  unit = unit or "target"
  if self._updateScheduled then
    -- already scheduled, remember last unit
    self._updateUnit = unit
    return
  end
  self._updateUnit = unit
  self._updateScheduled = true
  if C_Timer then
    local interval = 0.25
    if OneButtonAssistantDB and type(OneButtonAssistantDB.updateInterval) == "number" then interval = OneButtonAssistantDB.updateInterval end
    if interval < 0.05 then interval = 0.05 end
    if interval > 1.0 then interval = 1.0 end
    C_Timer.After(interval, function()
      self._updateScheduled = nil
      local u = self._updateUnit or "target"
      self._updateUnit = nil
      local ok, res = pcall(function()
        local sug = self:GetNextActionForUnit(u)
        if sug then
          local key = sug.key or sug.spell or sug.name or sug
          if key then self:SetButtonSuggestion(key) else self:SetButtonSuggestion(nil) end
        else
          self:SetButtonSuggestion(nil)
        end
      end)
      -- update debug UI if present (best-effort)
      if self.UpdateDebugFrame then pcall(self.UpdateDebugFrame, self) end
      if not ok then
        -- don't spam errors; log if logger available
        if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "update_error", res) end
      end

    end)
  else
    -- fallback: immediate
    local suc, _ = pcall(function()
      local sug = self:GetNextActionForUnit(unit)
      if sug then local key = sug.key or sug.spell or sug.name or sug; if key then self:SetButtonSuggestion(key) else self:SetButtonSuggestion(nil) end else self:SetButtonSuggestion(nil) end
    end)
    self._updateScheduled = nil
    if self.UpdateDebugFrame then pcall(self.UpdateDebugFrame, self) end
  end
end

function OBA:SaveRawSuggestion(adapterName, raw)
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.lastRawSuggestion = OneButtonAssistantDB.lastRawSuggestion or {}
  OneButtonAssistantDB.lastRawSuggestion[adapterName] = raw
  if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then OneButtonAssistantLogger:Log("rawSuggestion:"..tostring(adapterName), raw) end
end

function OBA:GetNextActionForUnit(unit)
  unit = unit or "target"
  local state, ext = self:BuildStateFromAdapters(unit)
  if ext and self.Engine and self.Engine.MapExternalSuggestion then
    local mapped = self.Engine:MapExternalSuggestion(ext)
    if mapped then return mapped end
  end
  if self.Engine and self.Engine.GetNextAction then return self.Engine:GetNextAction(state) end
  return nil
end

function OBA:OnAddonLoaded()
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  if OneButtonAssistantEngine then self.Engine = OneButtonAssistantEngine end
  -- load adapters
  self.adapters = self.adapters or {}
  if OneButtonAssistantHekiliAdapter then self.adapters.hekili = OneButtonAssistantHekiliAdapter end
  if OneButtonAssistantGSEAdapter then self.adapters.gse = OneButtonAssistantGSEAdapter end
  if OneButtonAssistantWeakAurasAdapter then self.adapters.weakauras = OneButtonAssistantWeakAurasAdapter end
  if OneButtonAssistantPlayerStateAdapter then self.adapters.playerstate = OneButtonAssistantPlayerStateAdapter end
  if OneButtonAssistantSpellSpyAdapter then self.adapters.spellspy = OneButtonAssistantSpellSpyAdapter end
  if OneButtonAssistantDetailsAdapter then self.adapters.details = OneButtonAssistantDetailsAdapter end
  -- register a focused slash handler that delegates to the central handler
  SLASH_ONEBUTTONASSISTANT1 = "/oba"
  SlashCmdList["ONEBUTTONASSISTANT"] = function(msg)
    if OBA and OBA.HandleSlash then
      OBA:HandleSlash(msg)
    else
      print("|cffffff00["..addonName.."]|r OneButtonAssistant handler not ready.")
    end
  end
  -- register runtime events for auto-updating the OBA button (omit heavy COMBAT_LOG)
  frame:RegisterEvent("PLAYER_TARGET_CHANGED")
  frame:RegisterEvent("UNIT_AURA")
  frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
  -- ensure click-macro exists and (if possible) place it on ActionBar slot 1
  -- This will create a per-character macro named 'OneButtonAssistant' and attempt to place it on action slot 1 (ActionButton1).
  pcall(function()
    if not OneButtonAssistantDB then OneButtonAssistantDB = {} end
    if not OneButtonAssistantDB.macroCreated then
      -- try to create macro (character-specific)
      if type(CreateMacro) == "function" then
        local name = "OneButtonAssistant"
        local body = "/click OneButtonAssistant_Button"
        -- create macro if missing
        if GetMacroIndexByName(name) == 0 then
          CreateMacro(name, "INV_Misc_QuestionMark", body, true)
        end
        OneButtonAssistantDB.macroCreated = true
      end
    end
    -- attempt to place macro on slot 1 if requested/safe
    local desiredSlot = (OneButtonAssistantDB and OneButtonAssistantDB.macroSlot) or 1
    if desiredSlot and tonumber(desiredSlot) then
      self:PlaceMacroOnActionSlot(desiredSlot)
    end
  end)
  -- enable spellspy adapter if user requested (saved setting)
  if OneButtonAssistantDB and OneButtonAssistantDB.spellSpyEnabled and self.adapters and self.adapters.spellspy and self.adapters.spellspy.Enable then
    pcall(self.adapters.spellspy.Enable, self.adapters.spellspy, true)
  end

  -- Define a popup to confirm heuristic aliasing (shown when engine proposes an auto-alias)
  if type(StaticPopupDialogs) == "table" then
    StaticPopupDialogs["ONEBUTTONASSISTANT_HEURISTIC_CONFIRM"] = {
      text = "Auto-add heuristic alias for '%s' -> %s?",
      button1 = ACCEPT,
      button2 = CANCEL,
      timeout = 0,
      whileDead = true,
      hideOnEscape = true,
      -- data object is passed as the 4th arg to StaticPopup_Show; OnAccept/OnCancel receive that via 'data' parameter
      OnAccept = function(self, data)
        pcall(function()
          if data and data.token and OneButtonAssistant and OneButtonAssistant.PromoteHeuristic then
            OneButtonAssistant:PromoteHeuristic(data.token)
          end
        end)
      end,
      OnCancel = function(self, data)
        pcall(function()
          if data and data.token and OneButtonAssistant and OneButtonAssistant.RejectHeuristic then
            OneButtonAssistant:RejectHeuristic(data.token)
          end
        end)
      end,
      exclusive = true,
    }
  end
end

-- Try to place the OneButtonAssistant macro on a given action slot (1..120). Works only out-of-combat.
function OBA:PlaceMacroOnActionSlot(slot)
  slot = tonumber(slot) or 1
  if slot < 1 then slot = 1 end
  if slot > 120 then slot = 120 end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  local name = "OneButtonAssistant"
  local idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(name) or 0
  if idx == 0 then
    -- macro not present; try to create it
    if type(CreateMacro) == "function" then
      pcall(function() CreateMacro(name, "INV_Misc_QuestionMark", "/click OneButtonAssistant_Button", true) end)
      idx = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(name) or 0
    end
  end
  if idx == 0 then return false end

  -- if macro is already placed on any action slot, do not move it; record its slot and return
  if type(GetActionInfo) == "function" then
    for i = 1, 120 do
      local atype, aid = GetActionInfo(i)
      if atype == "macro" and aid == idx then
        OneButtonAssistantDB.macroSlot = i
        return true
      end
    end
  end

  -- if target slot is occupied, do not move existing actions
  if type(GetActionInfo) == "function" then
    local atype = select(1, GetActionInfo(slot))
    if atype and atype ~= "" then return false end
  end

  if InCombatLockdown() then
    -- defer until out of combat
    OneButtonAssistantDB.macroPending = slot
    -- register a handler to place after combat
    if not self._macroRegenFrame then
      local f = CreateFrame("Frame")
      f:RegisterEvent("PLAYER_REGEN_ENABLED")
      f:SetScript("OnEvent", function()
        if OneButtonAssistantDB and OneButtonAssistantDB.macroPending then
          local s = OneButtonAssistantDB.macroPending
          OneButtonAssistantDB.macroPending = nil
          pcall(function()
            local id2 = (type(GetMacroIndexByName) == "function") and GetMacroIndexByName(name) or 0
            if id2 and id2 > 0 then
              -- if macro already placed somewhere, record that slot and don't move it
              local placed = false
              if type(GetActionInfo) == "function" then
                for i = 1, 120 do
                  local atype, aid = GetActionInfo(i)
                  if atype == "macro" and aid == id2 then
                    OneButtonAssistantDB.macroSlot = i
                    placed = true
                    break
                  end
                end
              end
              if not placed then
                -- only place if target slot appears empty
                if type(GetActionInfo) ~= "function" or (select(1, GetActionInfo(s)) == nil) then
                  PickupMacro(id2)
                  PlaceAction(s)
                  ClearCursor()
                  OneButtonAssistantDB.macroSlot = s
                end
              end
            end
          end)
        end
      end)
      self._macroRegenFrame = f
    end
    return nil
  end

  -- perform placement now (out of combat)
  local ok, err = pcall(function()
    -- Only place if slot appears empty and macro not already placed elsewhere
    if type(GetActionInfo) == "function" then
      local atype = select(1, GetActionInfo(slot))
      if atype and atype ~= "" then return end
    end
    PickupMacro(idx)
    PlaceAction(slot)
    ClearCursor()
  end)
  if ok then
    OneButtonAssistantDB.macroSlot = slot
    return true
  else
    OneButtonAssistantDB.macroPending = slot
    return false
  end
end

function OBA:OnEvent(event, ...)
  if event == "ADDON_LOADED" then
    if select(1, ...) == addonName then
      self:OnAddonLoaded()
    end
    return
  end
  -- runtime events: debounce and update suggestion
  if event == "PLAYER_TARGET_CHANGED" then
    self:QueueUpdate("target")
  elseif event == "UNIT_AURA" then
    local unit = select(1, ...)
    if unit == "player" or unit == "target" then self:QueueUpdate(unit) end
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local unit = select(1, ...)
    if unit == "player" then self:QueueUpdate("target") end
  end
end

frame:SetScript("OnEvent", function(_, event, ...) OBA:OnEvent(event, ...) end)
frame:RegisterEvent("ADDON_LOADED")

-- Safe, non-invasive observer for Blizzard action button clicks.
-- This uses hooksecurefunc so it does not interfere with protected secure behavior.
pcall(function()
  hooksecurefunc("ActionButton_OnClick", function(self, button)
    local enabled = false
    pcall(function() enabled = (OneButtonAssistantDB and OneButtonAssistantDB.debugPrints) or false end)
    if not enabled then return end
    local name = tostring((self and self:GetName()) or "unknown")
    local slot = tonumber(name:match("ActionButton(%d+)") or "")
    local actType, actId = nil, nil
    if slot then
      local ok, t, id = pcall(GetActionInfo, slot)
      if ok then actType = t; actId = id end
    end
    local msg = string.format("OneButtonAssistant: Blizzard action button clicked: %s (button=%s) actionType=%s actionId=%s slot=%s", name, tostring(button), tostring(actType), tostring(actId), tostring(slot))
    pcall(print, msg)
    if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
      pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "ActionButtonClickDebug", { name = name, button = button, actionType = actType, actionId = actId, slot = slot })
    end
  end)
end)
