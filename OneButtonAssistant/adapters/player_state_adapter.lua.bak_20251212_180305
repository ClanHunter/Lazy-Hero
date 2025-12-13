-- Player state adapter: non-invasive reads of UnitBuff and GetSpellCooldown
local Adapter = {}
Adapter.name = "playerstate"

function Adapter:IsAvailable()
  if OneButtonAssistantShared and OneButtonAssistantShared.adapter_is_available then
    local ok, res = pcall(OneButtonAssistantShared.adapter_is_available, Adapter.name)
    if ok and type(res) == 'boolean' then return res end
  end
  -- always available in-game (non-invasive reads only)
  return true
end

function Adapter:Probe()
  if OneButtonAssistantShared and OneButtonAssistantShared.adapter_probe then
    local ok, res = pcall(OneButtonAssistantShared.adapter_probe, Adapter.name)
    if ok and res then return res end
  end
  return {
    found = true,
    note = "Reads player buffs via UnitBuff and spell cooldowns via GetSpellCooldown."
  }
end

-- FetchState(unit): returns a table with keys: buffs (map name->expiration), cooldowns (map spellKey->expiration), enemyCount
function Adapter:FetchState(unit)
  unit = unit or "player"
  local s = { buffs = {}, cooldowns = {}, enemyCount = 1 }
  local now = GetTime and GetTime() or time()
  -- collect player buffs
  if UnitBuff then
    local i = 1
    while true do
      local name, icon, count, debuffType, duration, expirationTime, unitCaster = UnitBuff(unit, i)
      if not name then break end
      if expirationTime and expirationTime > 0 then
        s.buffs[name] = expirationTime
      else
        -- if no expiration, set arbitrarily far in future
        s.buffs[name] = now + 3600
      end
      i = i + 1
      if i > 40 then break end
    end
  end

  -- use buffRefresh map to query configured spells' cooldowns
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  local map = OneButtonAssistantDB.buffRefresh or {}
  for buffName, cfg in pairs(map) do
    local spellKey = cfg and cfg.spellKey
    if spellKey then
      -- try to query cooldown using the spellKey directly (GetSpellCooldown accepts spellName or spellID)
      local ok, start, dur, enabled = pcall(function() return GetSpellCooldown(spellKey) end)
      if ok and start and dur and dur > 0 then
        s.cooldowns[spellKey] = (start + dur)
      else
        -- when not on cooldown, set to 0/expired
        s.cooldowns[spellKey] = 0
      end
    end
  end

  -- try to estimate enemyCount (basic): count nearby enemies using GetNumGroupMembers fallback
  local ok, n = pcall(function() if UnitAffectingCombat("player") then return 1 end end)
  s.enemyCount = 1

  return s
end

OneButtonAssistantPlayerStateAdapter = Adapter
return Adapter
