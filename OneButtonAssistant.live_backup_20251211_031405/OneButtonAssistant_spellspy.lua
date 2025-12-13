-- SpellSpy: record observed spells/auras/talents/racials/abilities across combats
-- Saves unique observed entries into OneButtonAssistantDB.SpellSpy (persisted by WoW on logout)

local addonName = "OneButtonAssistant"
local SpellSpy = CreateFrame("Frame", addonName .. "SpellSpy")

-- defaults
local defaults = {
  enabled = true,
  maxUnique = 2000,       -- stop once this many unique spellIDs recorded
  idleTimeout = 600,      -- seconds without a new unique entry before auto-stop (across combats)
}

-- Ensure SavedVariables table exists
if not OneButtonAssistantDB then OneButtonAssistantDB = {} end
if not OneButtonAssistantDB.SpellSpy then
  OneButtonAssistantDB.SpellSpy = { config = {}, spells = {}, talents = {}, auras = {}, racials = {}, meta = {} }
end

local DB = OneButtonAssistantDB.SpellSpy
-- merge defaults
for k,v in pairs(defaults) do if DB.config[k] == nil then DB.config[k] = v end end

-- internal state
local recording = false
local lastNewTime = 0

local function addUnique(tableName, id, name, extra)
  if not id or id == 0 then return false end
  local tbl = DB[tableName]
  if not tbl then return false end
  if not tbl[id] then
    tbl[id] = { name = name, addedAt = time(), extra = extra }
    lastNewTime = time()
    return true
  end
  return false
end

local function HandleCombatLog()
  local timestamp, event, hideCaster, srcGUID, srcName, srcFlags, srcRaidFlags,
        dstGUID, dstName, dstFlags, dstRaidFlags, spellId, spellName, spellSchool = CombatLogGetCurrentEventInfo()
  if not event then return end

  -- handle spell casts and aura changes
  if event:match("^SPELL_") or event:match("^SPELL_PERIODIC_") then
    if spellId and spellId ~= 0 then
      addUnique("spells", tostring(spellId), spellName)
    elseif spellName then
      -- fallback: store by name with pseudo-id
      addUnique("spells", "name:"..spellName, spellName)
    end
  end

  if event:match("AURA_") and spellId and spellId ~= 0 then
    addUnique("auras", tostring(spellId), spellName)
  end

  -- SPELL_SUMMON may include pets/elementals by name
  if event == "SPELL_SUMMON" and spellId and spellId ~= 0 then
    addUnique("spells", tostring(spellId), spellName)
  end
end

local function StartRecording()
  if recording or not DB.config.enabled then return end
  recording = true
  lastNewTime = time()
  SpellSpy:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  -- keep listening to combats across sessions until stopped
  DEFAULT_CHAT_FRAME:AddMessage("[OneButtonAssistant] SpellSpy: recording started")
end

local function StopRecording(reason)
  if not recording then return end
  recording = false
  SpellSpy:UnregisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
  DEFAULT_CHAT_FRAME:AddMessage(("[OneButtonAssistant] SpellSpy: recording stopped (%s)"):format(reason or "manual"))
end

local function CheckAutoStop()
  -- stop if we've reached maxUnique
  local count = 0
  for k in pairs(DB.spells) do count = count + 1 end
  if count >= (DB.config.maxUnique or defaults.maxUnique) then
    StopRecording("maxUnique reached")
    return
  end
  -- stop if idle timeout reached (no new unique entries)
  if (time() - (lastNewTime or 0)) >= (DB.config.idleTimeout or defaults.idleTimeout) then
    StopRecording("idle timeout")
  end
end

SpellSpy:SetScript("OnEvent", function(self, event, ...)
  if event == "PLAYER_ENTERING_WORLD" then
    DB.meta.lastReady = time()
    -- prepare but do not start until combat
    DEFAULT_CHAT_FRAME:AddMessage("[OneButtonAssistant] SpellSpy: ready")
  elseif event == "PLAYER_REGEN_DISABLED" then -- entered combat
    StartRecording()
  elseif event == "PLAYER_REGEN_ENABLED" then -- left combat
    -- keep recording across combats; allow auto-stop check
    CheckAutoStop()
  elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
    HandleCombatLog()
  elseif event == "PLAYER_LOGOUT" then
    -- ensure meta saved timestamp and reason
    DB.meta.lastSaved = time()
    DB.meta.savedReason = "PLAYER_LOGOUT"
    -- SavedVariables are persisted automatically; mention intent
  end
end)

-- register core events
SpellSpy:RegisterEvent("PLAYER_ENTERING_WORLD")
SpellSpy:RegisterEvent("PLAYER_REGEN_DISABLED")
SpellSpy:RegisterEvent("PLAYER_REGEN_ENABLED")
SpellSpy:RegisterEvent("PLAYER_LOGOUT")

-- slash commands: /oba spellspy status|stop|clear|export
SLASH_OBA_SPELLSPY1 = "/oba_spellspy"
SlashCmdList["OBA_SPELLSPY"] = function(msg)
  local cmd = msg:match("^(%S+)") or msg
  cmd = cmd and cmd:lower() or "status"
  if cmd == "status" then
    local count = 0
    for _ in pairs(DB.spells) do count = count + 1 end
    DEFAULT_CHAT_FRAME:AddMessage(('[OneButtonAssistant] SpellSpy: %d unique spells, recording=%s'):format(count, tostring(recording)))
  elseif cmd == "stop" then
    StopRecording("manual")
  elseif cmd == "start" then
    StartRecording()
  elseif cmd == "clear" then
    DB.spells = {}
    DB.auras = {}
    DB.talents = {}
    DB.racials = {}
    DEFAULT_CHAT_FRAME:AddMessage('[OneButtonAssistant] SpellSpy: cleared saved entries')
  elseif cmd == "export" then
    -- quick export to the addon's saved table; it's already stored in OneButtonAssistantDB.SpellSpy
    DB.meta.exportedAt = time()
    DEFAULT_CHAT_FRAME:AddMessage('[OneButtonAssistant] SpellSpy: export marked in SavedVariables')
  else
    DEFAULT_CHAT_FRAME:AddMessage('[OneButtonAssistant] SpellSpy commands: status|start|stop|clear|export')
  end
end

-- provide a simple API for other modules
OneButtonAssistant = OneButtonAssistant or {}
OneButtonAssistant.SpellSpy = OneButtonAssistant.SpellSpy or {}
OneButtonAssistant.SpellSpy.GetCounts = function()
  local s,a,t,r = 0,0,0,0
  for _ in pairs(DB.spells) do s = s + 1 end
  for _ in pairs(DB.auras) do a = a + 1 end
  for _ in pairs(DB.talents) do t = t + 1 end
  for _ in pairs(DB.racials) do r = r + 1 end
  return { spells = s, auras = a, talents = t, racials = r }
end

-- end of SpellSpy
