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
    -- clear suggestion (safe to do insecurely)
    pcall(function() btn:SetAttribute("suggestion", "") end)
    -- also clear visible icon immediately
    UpdateIconFromValue(nil)
    return
  end
  -- if numeric, prefer spell:<id>
  if tonumber(val) then val = "spell:" .. tostring(val) end
  -- update visible icon immediately (even if we must defer secure attribute changes)
  pcall(function() UpdateIconFromValue(val) end)
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
  local ok, err = pcall(function() btn:SetAttribute("suggestion", tostring(val)) end)
  if ok then
    pcall(function() table.insert(OneButtonAssistantDB.assignLog, { action = "apply", suggestion = tostring(val), time = (GetTime and GetTime() or 0) }) end)
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
    table.insert(OneButtonAssistantDB.clickLog, { button = tostring(mouseButton), type = tostring(typ), spell = tostring(spell), item = tostring(item), macro = tostring(macro), time = (GetTime and GetTime() or 0) })
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
