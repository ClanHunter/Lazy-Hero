-- OneButtonAssistant secure action button
local addonName = "OneButtonAssistant"
OneButtonAssistant = OneButtonAssistant or {}
local OBA = OneButtonAssistant

-- Create a secure action button that updates its protected attributes via a secure attribute handler
local btn = CreateFrame("Button", "OneButtonAssistant_Button", UIParent, "SecureActionButtonTemplate,SecureHandlerAttributeTemplate")
btn:SetSize(40,40)
btn:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 120)
btn:RegisterForClicks("AnyDown")

-- simple visible texture (separate texture so we can update it insecurely)
local icon = btn:CreateTexture(nil, "ARTWORK")
icon:SetAllPoints()
icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

-- Safe wrappers for WoW API that may be nil in offline/static analysis
local function SafeGetSpellInfoAll(idOrName)
  if type(GetSpellInfo) ~= "function" then return nil end
  local ok, name, rank, icon = pcall(GetSpellInfo, idOrName)
  if not ok then return nil end
  return name, rank, icon
end

local function UpdateIconFromValue(val)
  -- val may be like "spell:12345" or a spell name or other token
  if not val or val == "" then
    pcall(function() icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end)
    return
  end
  -- check aliases first
  if OneButtonAssistantDB and OneButtonAssistantDB.aliases then
    local lk = tostring(val):lower()
    local ali = OneButtonAssistantDB.aliases[lk]
    if ali then val = ali end
  end
  local typ, payload = tostring(val):match("^(%a+):(.+)$")
  local spellIdOrName = (typ == "spell" and payload) or val
  local tex = nil
  if tonumber(spellIdOrName) then
    local _,_,t = SafeGetSpellInfoAll(tonumber(spellIdOrName))
    tex = t
  else
    local _,_,t = SafeGetSpellInfoAll(spellIdOrName)
    tex = t
  end
  if tex then pcall(function() icon:SetTexture(tex) end) else pcall(function() icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end) end
end

-- flash overlay for suggestion changes (insecure visual only)
local flash = btn:CreateTexture(nil, "OVERLAY")
flash:SetAllPoints()
flash:SetTexture("Interface\\FullScreenTextures\\OutOfControl")
flash:SetBlendMode("ADD")
flash:Hide()
local flashAG = flash:CreateAnimationGroup()
local flashAnim = flashAG:CreateAnimation("Alpha")
flashAnim:SetDuration(0.28)
flashAnim:SetFromAlpha(1)
flashAnim:SetToAlpha(0)
flashAnim:SetSmoothing("OUT")
flashAG:SetScript("OnPlay", function() flash:Show() end)
flashAG:SetScript("OnFinished", function() flash:Hide(); flash:SetAlpha(1) end)

-- make movable
btn:SetMovable(true)
btn:EnableMouse(true)
btn:RegisterForDrag("LeftButton")
btn:SetScript("OnDragStart", function(self) if InCombatLockdown() then return end; self:StartMoving() end)
btn:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); local x,y = self:GetCenter(); OneButtonAssistantDB = OneButtonAssistantDB or {}; OneButtonAssistantDB.buttonPos = { x = x, y = y } end)

-- restore position if saved
if OneButtonAssistantDB and OneButtonAssistantDB.buttonPos and OneButtonAssistantDB.buttonPos.x then
  local pos = OneButtonAssistantDB.buttonPos
  btn:ClearAllPoints(); btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", pos.x, pos.y)
end

-- secure snippet: runs when attribute "suggestion" changes (even during combat)
-- Sets the protected attributes (type, spell, item, macrotext) to enable proper click behavior
btn:SetAttribute("_onattribute-suggestion", [[
  local v = new
  -- maintain a secure-side sequence token to ensure a value set in protected code
  local sseq = self:GetAttribute("secure_seq")
  if not sseq then sseq = 0 end
  sseq = sseq + 1
  self:SetAttribute("secure_seq", sseq)
  -- also expose it as 'secure_seq' attribute for insecure readers to correlate
  self:SetAttribute("secure_seq", sseq)
  if v and v ~= "" then
    -- support formats: "spell:12345", "spell:name", or plain spell name
    local typ, val = string.match(v, "^(%a+):(.+)$")
    if typ == "spell" then
      self:SetAttribute("type", "spell")
      self:SetAttribute("spell", val)
    elseif typ == "item" then
      self:SetAttribute("type", "item")
      self:SetAttribute("item", val)
    elseif typ == "macro" then
      -- allow macro: prefix to set macrotext in secure handler
      self:SetAttribute("type", "macro")
      -- ensure macrotext starts with a slash for safety
      local mt = val
      if string.sub(mt,1,1) ~= "/" then mt = "/cast " .. mt end
      self:SetAttribute("macrotext", mt)
    else
      -- default to spell by name/id
      self:SetAttribute("type", "spell")
      self:SetAttribute("spell", v)
    end
  else
    self:SetAttribute("type", nil)
    self:SetAttribute("spell", nil)
    self:SetAttribute("item", nil)
    self:SetAttribute("macrotext", nil)
    -- clear secure token when suggestion cleared
    self:SetAttribute("secure_seq", nil)
  end
]])

-- Insecure handler to update icon and tooltip when suggestion attribute changes
btn:SetScript("OnAttributeChanged", function(self, name, value)
  if name == "suggestion" then
    local prev = self.__suggestion
    if value and value ~= "" then
      local typ, val = value:match("^(%a+):(.+)$")
      local spellIdOrName = (typ == "spell" and val) or value
      local tex
      if tonumber(spellIdOrName) then
        local _,_,t = SafeGetSpellInfoAll(tonumber(spellIdOrName))
        tex = t
      else
        local _,_,t = SafeGetSpellInfoAll(spellIdOrName)
        tex = t
      end
      if tex then icon:SetTexture(tex) else icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark") end
      self.__suggestion = value
      -- guarded debug print and logger entry for suggestion applied (insecure path)
      pcall(function()
        local dbg = OneButtonAssistantDB and OneButtonAssistantDB.debugPrints
        if dbg then
          pcall(function() print(string.format("OneButtonAssistant: SuggestionApplied -> %s (time=%.3f)", tostring(self.__suggestion), (GetTime and GetTime() or 0))) end)
              if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
                pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "SuggestionApplied", { suggestion = tostring(self.__suggestion), time = (GetTime and GetTime() or 0) })
              end
              -- persist that the insecure handler observed an apply (for offline correlation)
              pcall(function()
                OneButtonAssistantDB = OneButtonAssistantDB or {}
                OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
                local ok, stack = pcall(function() return debugstack() end)
                -- capture current attributes as seen by the insecure handler
                local atype, aspell, aitem, amacro, aseq, asecure = nil, nil, nil, nil, nil, nil
                pcall(function()
                  atype = self:GetAttribute("type")
                  aspell = self:GetAttribute("spell")
                  aitem = self:GetAttribute("item")
                  amacro = self:GetAttribute("macrotext")
                  aseq = self:GetAttribute("seq")
                  asecure = self:GetAttribute("secure_seq")
                end)
                table.insert(OneButtonAssistantDB.assignLog, { action = "observed_apply", suggestion = tostring(self.__suggestion), time = (GetTime and GetTime() or 0), caller = (ok and stack) or nil, attrs = { type = tostring(atype), spell = tostring(aspell), item = tostring(aitem), macro = tostring(amacro), seq = tostring(aseq), secure_seq = tostring(asecure) } })
              end)
        end
      end)
      -- flash when suggestion actually changed (opt-out via OneButtonAssistantDB.flashOnChange = false)
      local enabled = true
      if OneButtonAssistantDB and OneButtonAssistantDB.flashOnChange == false then enabled = false end
      if enabled and prev ~= self.__suggestion then
        flashAG:Stop()
        flash:SetAlpha(1)
        flashAG:Play()
      end
    else
      icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
      self.__suggestion = nil
      -- persist that the insecure handler observed the suggestion being cleared
      pcall(function()
        OneButtonAssistantDB = OneButtonAssistantDB or {}
        OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
        local ok, stack = pcall(function() return debugstack() end)
        local atype, aspell, aitem, amacro, aseq, asecure = nil, nil, nil, nil, nil, nil
        pcall(function()
          atype = self:GetAttribute("type")
          aspell = self:GetAttribute("spell")
          aitem = self:GetAttribute("item")
          amacro = self:GetAttribute("macrotext")
          aseq = self:GetAttribute("seq")
          asecure = self:GetAttribute("secure_seq")
        end)
        table.insert(OneButtonAssistantDB.assignLog, { action = "observed_clear", time = (GetTime and GetTime() or 0), caller = (ok and stack) or nil, attrs = { type = tostring(atype), spell = tostring(aspell), item = tostring(aitem), macro = tostring(amacro), seq = tostring(aseq), secure_seq = tostring(asecure) } })
      end)
    end
  end
end)

-- Tooltip
btn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self.__suggestion then
    local typ, val = self.__suggestion:match("^(%a+):(.+)$")
    local spellName
    if typ == "spell" and tonumber(val) then
      local n = SafeGetSpellInfoAll(tonumber(val))
      spellName = n
    else
      local n = SafeGetSpellInfoAll(typ == "spell" and val or self.__suggestion)
      spellName = n
    end
    GameTooltip:AddLine(spellName or "OneButtonAssistant")
    GameTooltip:AddLine("Click to cast the suggested spell.")
  else
    GameTooltip:AddLine("OneButtonAssistant")
    GameTooltip:AddLine("No suggestion set.")
  end
  GameTooltip:Show()
end)
btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Public API: set the suggestion for the button. Accepts a table or string.
function OBA:SetButtonSuggestion(suggestion)
  -- suggestion may be a table with .key or .name, or a string like "spell:12345" or a spell name
  local val = nil
  if type(suggestion) == "table" then
    val = suggestion.key or suggestion.spell or suggestion.name or suggestion[1]
  else
    val = suggestion
  end
  if not val then
    -- schedule a deferred clear (hold for a short period) to avoid racey immediate clears
    pcall(function()
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
      local ok, stack = pcall(function() return debugstack() end)
      table.insert(OneButtonAssistantDB.assignLog, { action = "clear", time = (GetTime and GetTime() or 0), caller = (ok and stack) or nil })
    end)
    -- generate a unique clear id and mark pending
    self._clearId = (self._clearId or 0) + 1
    local clearId = self._clearId
    self._clearPending = clearId
    -- capture current suggestion sequence so we don't clear a newly-applied suggestion
    local capturedSeq = self._lastAppliedSeq
    local delay = (OneButtonAssistantDB and OneButtonAssistantDB.clearHoldSeconds) or 0.75
    if C_Timer and type(C_Timer.After) == "function" then
      C_Timer.After(delay, function()
        if OBA and OBA._clearPending == clearId then
          -- only apply the clear if the last applied suggestion sequence hasn't changed
          if capturedSeq == OBA._lastAppliedSeq then
            pcall(function() btn:SetAttribute("suggestion", "") end)
            pcall(function() UpdateIconFromValue(nil) end)
            pcall(function()
              OneButtonAssistantDB = OneButtonAssistantDB or {}
              OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
              table.insert(OneButtonAssistantDB.assignLog, { action = "clear_applied", time = (GetTime and GetTime() or 0) })
            end)
            -- clear recorded last-applied sequence because suggestion was removed
            OBA._lastAppliedSeq = nil
          else
            -- the suggestion sequence changed since scheduling; skip the clear
            pcall(function()
              OneButtonAssistantDB = OneButtonAssistantDB or {}
              OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
              table.insert(OneButtonAssistantDB.assignLog, { action = "clear_skipped_seq_mismatch", scheduled_seq = capturedSeq, current_seq = OBA._lastAppliedSeq, time = (GetTime and GetTime() or 0) })
            end)
          end
          OBA._clearPending = nil
        end
      end)
    else
      -- fallback immediate clear
      pcall(function() btn:SetAttribute("suggestion", "") end)
      pcall(function() UpdateIconFromValue(nil) end)
      -- record the clear and clear the last-applied seq
      pcall(function()
        OneButtonAssistantDB = OneButtonAssistantDB or {}
        OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
        table.insert(OneButtonAssistantDB.assignLog, { action = "clear_applied", time = (GetTime and GetTime() or 0) })
      end)
      OBA._lastAppliedSeq = nil
    end
    return
  end
  -- if numeric, prefer spell:<id>
  if tonumber(val) then val = "spell:" .. tostring(val) end
  -- update visible icon immediately (even if we must defer secure attribute changes)
  pcall(function() UpdateIconFromValue(val) end)
  -- cancel any pending clear when a new suggestion arrives
  self._clearPending = nil
  -- guarded debug print and logger entry for suggestion assignment
  pcall(function()
    local dbg = OneButtonAssistantDB and OneButtonAssistantDB.debugPrints
    if dbg then
      pcall(function() print(string.format("OneButtonAssistant: SetButtonSuggestion -> %s (time=%.3f)", tostring(val), (GetTime and GetTime() or 0))) end)
      if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
        pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "SetButtonSuggestion", { suggestion = tostring(val), time = (GetTime and GetTime() or 0) })
      end
    end
  end)
  -- persist assignment attempts to saved variables for offline analysis
  pcall(function()
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
  end)
  -- If we're in combat, avoid calling protected APIs which may cause ADDON_ACTION_BLOCKED/taint.
  if InCombatLockdown() then
    -- store pending suggestion to apply after combat
    self._pendingSuggestion = tostring(val)
    pcall(function() table.insert(OneButtonAssistantDB.assignLog, { action = "defer", suggestion = tostring(val), time = (GetTime and GetTime() or 0) }) end)
    return
  end
  -- apply suggestion (pcall to avoid accidental protected-call errors)
  -- advance suggestion sequence so clears can detect newer applies
  self._seq = (self._seq or 0) + 1
  self._lastAppliedSeq = self._seq
  local ok, err = pcall(function()
    pcall(function() btn:SetAttribute("seq", self._seq) end)
    btn:SetAttribute("suggestion", tostring(val))
  end)
  if ok then
    pcall(function() table.insert(OneButtonAssistantDB.assignLog, { action = "apply", suggestion = tostring(val), time = (GetTime and GetTime() or 0), seq = self._seq }) end)
  else
    -- fall back to saving pending suggestion
    self._pendingSuggestion = tostring(val)
    pcall(function() table.insert(OneButtonAssistantDB.assignLog, { action = "error", suggestion = tostring(val), time = (GetTime and GetTime() or 0), error = tostring(err) }) end)
    if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then OneButtonAssistantLogger:Log("SetButtonSuggestionError", err) end
  end
end

-- expose button object for debugging
OBA.Button = btn

-- Debug: report what the secure button will do when activated (click or binding)
btn:SetScript("OnClick", function(self, mouseButton, down)
  -- Respect runtime toggle stored in saved variables to avoid noisy prints.
  local enabled = false
  pcall(function() enabled = (OneButtonAssistantDB and OneButtonAssistantDB.debugPrints) or false end)
  if not enabled then return end
  local typ = self:GetAttribute("type")
  local spell = self:GetAttribute("spell")
  local item = self:GetAttribute("item")
  local macro = self:GetAttribute("macrotext")
  local seq = self:GetAttribute("seq")
  local secure_seq = self:GetAttribute("secure_seq")
  local msg = string.format("OneButtonAssistant: Button activated (mouse=%s) -> type=%s spell=%s item=%s macro=%s",
    tostring(mouseButton), tostring(typ), tostring(spell), tostring(item), tostring(macro))
  -- print to chat for immediate feedback
  pcall(function() print(msg) end)
  -- also send to logger if available (non-blocking)
  if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
    pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "ButtonClickDebug", { button = mouseButton, type = typ, spell = spell, item = item, macro = macro })
  end
  -- persist click snapshot for offline analysis (guarded by debugPrints)
  pcall(function()
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    OneButtonAssistantDB.clickLog = OneButtonAssistantDB.clickLog or {}
    table.insert(OneButtonAssistantDB.clickLog, { button = tostring(mouseButton), type = tostring(typ), spell = tostring(spell), item = tostring(item), macro = tostring(macro), seq = tostring(seq), secure_seq = tostring(secure_seq), time = (GetTime and GetTime() or 0) })
  end)
  -- Dynamic hold adjustment: if click observed nil attributes shortly after an apply, increase the clear hold
  pcall(function()
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    local clearHold = OneButtonAssistantDB.clearHoldSeconds or 0.75
    local maxHold = OneButtonAssistantDB.maxClearHoldSeconds or 5.0
    local step = OneButtonAssistantDB.clearHoldStep or 0.25
    local checkWindow = OneButtonAssistantDB.adjustCheckWindow or 2.0
    -- only consider a failure if all attributes are nil
    if tostring(typ) == "nil" and tostring(spell) == "nil" and tostring(item) == "nil" and tostring(macro) == "nil" then
      -- find last apply/observed_apply timestamp
      local lastApplyTime = nil
      if OneButtonAssistantDB.assignLog then
        for i = #OneButtonAssistantDB.assignLog, 1, -1 do
          local e = OneButtonAssistantDB.assignLog[i]
          if e and e.time and (e.action == "apply" or e.action == "observed_apply" or e.action == "apply_pending") then
            lastApplyTime = e.time
            break
          end
        end
      end
      local now = (GetTime and GetTime() or 0)
      if lastApplyTime and (now - lastApplyTime) <= checkWindow then
        local newHold = clearHold + step
        if newHold > maxHold then newHold = maxHold end
        if newHold > clearHold then
          OneButtonAssistantDB.clearHoldSeconds = newHold
          OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
          table.insert(OneButtonAssistantDB.assignLog, { action = "clear_hold_increase", old = clearHold, new = newHold, time = now })
          if OneButtonAssistantDB.debugPrints then pcall(function() print(string.format("OneButtonAssistant: Increased clear hold %.2fs -> %.2fs", clearHold, newHold)) end) end
        end
      end
    end
    -- decay: reduce clearHoldSeconds after a number of consecutive successful clicks
    local successThreshold = OneButtonAssistantDB.clearHoldDecayThreshold or 3
    local decayStep = OneButtonAssistantDB.clearHoldStep or 0.25
    local baseHold = OneButtonAssistantDB.clearHoldMin or 0.75
    local decayCooldownMinutes = OneButtonAssistantDB.clearHoldDecayCooldownMinutes or 5
    local decayCooldownSeconds = decayCooldownMinutes * 60
    -- on success (attributes present), increment success counter; on failure reset it
    if not (tostring(typ) == "nil" and tostring(spell) == "nil" and tostring(item) == "nil" and tostring(macro) == "nil") then
      OneButtonAssistantDB._clearSuccessCount = (OneButtonAssistantDB._clearSuccessCount or 0) + 1
      if OneButtonAssistantDB._clearSuccessCount >= successThreshold then
        local cur = OneButtonAssistantDB.clearHoldSeconds or baseHold
        local newHold = cur - decayStep
        if newHold < baseHold then newHold = baseHold end
        if newHold < cur then
          -- check cooldown: only allow a decay if sufficient time has passed since last decay
          local now = (GetTime and GetTime() or 0)
          local lastDecay = OneButtonAssistantDB._lastClearDecayTime or 0
          if (now - lastDecay) >= decayCooldownSeconds then
            OneButtonAssistantDB.clearHoldSeconds = newHold
            OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
            table.insert(OneButtonAssistantDB.assignLog, { action = "clear_hold_decrease", old = cur, new = newHold, time = now })
            OneButtonAssistantDB._lastClearDecayTime = now
            if OneButtonAssistantDB.debugPrints then pcall(function() print(string.format("OneButtonAssistant: Decreased clear hold %.2fs -> %.2fs (cooldown %.1fmin)", cur, newHold, decayCooldownMinutes)) end) end
          else
            -- record that decay was skipped due to cooldown
            OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}
            table.insert(OneButtonAssistantDB.assignLog, { action = "clear_hold_decrease_skipped", old = cur, attempted = newHold, time = now, cooldown_remaining = math.max(0, decayCooldownSeconds - (now - lastDecay)) })
            if OneButtonAssistantDB.debugPrints then pcall(function() print(string.format("OneButtonAssistant: Decay skipped; %.1fsec cooldown remaining", math.max(0, decayCooldownSeconds - (now - lastDecay)))) end) end
          end
        end
        OneButtonAssistantDB._clearSuccessCount = 0
      end
    else
      OneButtonAssistantDB._clearSuccessCount = 0
    end
  end)
end)

-- Public API: set the persistent logo/icon for the button (texture path like "Interface\\Icons\\INV_Sword_27")
function OBA:SetLogoIcon(texturePath)
  if not texturePath then return false end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.logoIcon = texturePath
  -- update icon texture immediately (insecure UI change)
  pcall(function()
    if icon and type(icon.SetTexture) == "function" then
      icon:SetTexture(texturePath)
    end
  end)
  return true
end

-- Apply pending suggestion after combat ends
local regenFrame = CreateFrame("Frame")
regenFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
regenFrame:SetScript("OnEvent", function()
  if OBA and OBA._pendingSuggestion then
    local s = OBA._pendingSuggestion
    OBA._pendingSuggestion = nil
    -- guarded log for deferred suggestion application
    pcall(function()
      local dbg = OneButtonAssistantDB and OneButtonAssistantDB.debugPrints
      if dbg then
        pcall(function() print(string.format("OneButtonAssistant: Applying pending suggestion -> %s (time=%.3f)", tostring(s), (GetTime and GetTime() or 0))) end)
        if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
          pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "ApplyingPendingSuggestion", { suggestion = tostring(s), time = (GetTime and GetTime() or 0) })
        end
      end
      pcall(function() OneButtonAssistantDB = OneButtonAssistantDB or {}; OneButtonAssistantDB.assignLog = OneButtonAssistantDB.assignLog or {}; table.insert(OneButtonAssistantDB.assignLog, { action = "apply_pending", suggestion = tostring(s), time = (GetTime and GetTime() or 0) }) end)
        -- increment sequence and set seq attribute so clears can reason about ordering
        OBA._seq = (OBA._seq or 0) + 1
        OBA._lastAppliedSeq = OBA._seq
        pcall(function() btn:SetAttribute("seq", OBA._seq) end)
        btn:SetAttribute("suggestion", s)
    end)
  end
end)

-- Keybinding helpers (non-invasive but will modify user's bindings when requested)
function OBA:BindButtonToKey(key)
  if not key or key == "" then return false end
  if InCombatLockdown() then print("OneButtonAssistant: Cannot change bindings while in combat.") return false end
  -- set a click binding to the secure button
  SetBindingClick(key, btn:GetName())
  -- persist current binding set (account/character)
  local set = GetCurrentBindingSet()
  if not SaveBindings(set) then print("OneButtonAssistant: Failed to save bindings.") end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.binding = { key = key, set = set }
  print(string.format("OneButtonAssistant: Bound %s to %s (and saved).", key, btn:GetName()))
  return true
end

function OBA:UnbindButton()
  if InCombatLockdown() then print("OneButtonAssistant: Cannot change bindings while in combat.") return false end
  local info = OneButtonAssistantDB and OneButtonAssistantDB.binding
  if info and info.key then
    SetBinding(info.key, nil)
    if info.set then SaveBindings(info.set) end
    OneButtonAssistantDB.binding = nil
    print(string.format("OneButtonAssistant: Unbound %s.", tostring(info.key)))
    return true
  end
  print("OneButtonAssistant: No binding to remove.")
  return false
end

-- Auto-place overlay: move the OBA button to overlay the default Blizzard action button slot (non-invasive)
function OBA:AutoPlaceOnActionSlot(slot)
  slot = tonumber(slot) or 1
  local name = "ActionButton" .. tostring(slot)
  local target = _G[name]
  if not target then print("OneButtonAssistant: Action button not found: "..tostring(name)); return false end
  if InCombatLockdown() then print("OneButtonAssistant: Cannot move button while in combat."); return false end
  local x,y = target:GetCenter()
  if x and y then
    btn:ClearAllPoints()
    btn:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
    OneButtonAssistantDB = OneButtonAssistantDB or {}
    OneButtonAssistantDB.buttonPos = { x = x, y = y }
    OneButtonAssistantDB.autoplaced = { slot = slot }
    print(string.format("OneButtonAssistant: Auto-placed on %s (slot %d).", name, slot))
    return true
  end
  print("OneButtonAssistant: Failed to determine action button position.")
  return false
end

function OBA:ClearAutoPlace()
  if InCombatLockdown() then print("OneButtonAssistant: Cannot change position while in combat."); return false end
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.autoplaced = nil
  print("OneButtonAssistant: Auto-place cleared. You can now drag the button.")
  return true
end

-- initialize to nil
OBA:SetButtonSuggestion(nil)

-- If a saved logo icon exists, apply it to the button immediately
if OneButtonAssistantDB and OneButtonAssistantDB.logoIcon then
  pcall(function()
    if icon and type(icon.SetTexture) == "function" then
      icon:SetTexture(OneButtonAssistantDB.logoIcon)
    end
  end)
end

-- initialization complete (no debug print)

-- Sanitize persisted aliases/heuristics: remove any addon-supplied macro suggestions
pcall(function()
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  -- remove alias values that are macro:...
  if OneButtonAssistantDB.aliases then
    for k, v in pairs(OneButtonAssistantDB.aliases) do
      if type(v) == "string" and v:match("^macro:") then
        OneButtonAssistantDB.aliases[k] = nil
      end
    end
  end
  -- remove heuristic entries that contain macro values
  if OneButtonAssistantDB.heuristics then
    for k, v in pairs(OneButtonAssistantDB.heuristics) do
      if type(v) == "table" and type(v.value) == "string" and v.value:match("^macro:") then
        OneButtonAssistantDB.heuristics[k] = nil
      end
    end
  end
  -- optional debug print
  if OneButtonAssistantDB.debugPrints then pcall(function() print("OneButtonAssistant: Removed addon macro-suggestions from saved aliases/heuristics.") end) end
end)
