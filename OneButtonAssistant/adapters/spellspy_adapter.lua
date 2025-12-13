-- SpellSpy adapter: optional COMBAT_LOG-based spell capture and alias auto-add
local Adapter = {}
Adapter.name = "spellspy"

Adapter.enabled = false

function Adapter:IsAvailable()
  if OneButtonAssistantShared and OneButtonAssistantShared.adapter_is_available then
    local ok, res = pcall(OneButtonAssistantShared.adapter_is_available, Adapter.name)
    if ok and type(res) == 'boolean' then return res end
  end
  return true
end

function Adapter:Probe()
  if OneButtonAssistantShared and OneButtonAssistantShared.adapter_probe then
    local ok, res = pcall(OneButtonAssistantShared.adapter_probe, Adapter.name)
    if ok and res then return res end
  end
  return { found = true, note = "Optional COMBAT_LOG listener to capture spells and auto-add aliases (off by default)." }
end

local function safeLower(s) if not s then return s end return tostring(s):lower() end

function Adapter:Enable(enable)
  enable = not not enable
  if enable == self.enabled then return end
  self.enabled = enable
  if enable then
    self.frame = self.frame or CreateFrame("Frame")
    self.frame:SetScript("OnEvent", function(_, event, ...)
      local ok, timestamp, eventType, hideCaster, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName = pcall(CombatLogGetCurrentEventInfo)
      if not ok then return end
      if not eventType then return end
      -- focus on player and hostile casts plus self
      if eventType:match("^SPELL_") then
        -- spellId/spellName positions vary by event; CombatLogGetCurrentEventInfo returns many values; try to find first numeric
        local id = nil; local name = nil
        for i=1, select('#', CombatLogGetCurrentEventInfo()) do
          local v = select(i, CombatLogGetCurrentEventInfo())
          if not id and type(v) == 'number' then id = v end
          if not name and type(v) == 'string' then
            -- heuristic: spell names are strings longer than 1 and not unit names
            if #v > 1 then name = v end
          end
        end
        -- prefer first found
        if id and name then
          -- record into OneButtonAssistantDB.aliases if user enabled auto-add
          OneButtonAssistantDB = OneButtonAssistantDB or {}
          OneButtonAssistantDB.aliases = OneButtonAssistantDB.aliases or {}
          if OneButtonAssistantDB.autoAliasAdd ~= false then
            local key = safeLower(name)
            OneButtonAssistantDB.aliases[key] = "spell:" .. tostring(id)
            if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then OneButtonAssistantLogger:Log("spellspy:add_alias", { token = key, map = "spell:"..tostring(id) }) end
          end
        end
      end
    end)
    self.frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  else
    if self.frame then
      self.frame:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
      self.frame:SetScript("OnEvent", nil)
    end
  end
end

function Adapter:FetchState(unit)
  -- no state contribution, just optional background aliasing
  return nil
end

OneButtonAssistantSpellSpyAdapter = Adapter
return Adapter
