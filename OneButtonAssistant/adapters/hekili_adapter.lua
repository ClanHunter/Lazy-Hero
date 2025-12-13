-- Hekili adapter stub for OneButtonAssistant
local HekiliAdapter = {}

local shared = OneButtonAssistantShared

local function extractKeyFromRaw(raw)
  if shared and shared.extractKeyFromRaw then return shared.extractKeyFromRaw(raw) end
  if not raw then return nil end
  if type(raw) ~= "table" then return tostring(raw) end
  return nil
end

function HekiliAdapter:IsAvailable()
  if shared and shared.adapter_is_available then
    return shared.adapter_is_available("Hekili")
  end
  return (type(Hekili) == "table") or (type(_G["Hekili"]) == "table")
end

function HekiliAdapter:GetSuggestion(unit)
  -- NON-INVASIVE: do not call any Hekili functions. Inspect tables only.
  -- If a persisted raw suggestion exists (saved on WoW exit), prefer it for offline analysis
  if OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion.hekili then
    local raw = OneButtonAssistantDB.lastRawSuggestion.hekili
    local key = extractKeyFromRaw(raw)
    if key then return { key = key, name = tostring(key), raw = raw, reason = "saved:hekili" } end
  end
  if not self:IsAvailable() then return nil end
  local tbl = Hekili or _G["Hekili"]
  if not tbl then return nil end

  -- Prefer DisplayPool snapshot if present
  if type(tbl.DisplayPool) == "table" and #tbl.DisplayPool > 0 then
    local first = tbl.DisplayPool[1]
      if type(first) == "table" then
      local out = { key = first.spellID or first.name or first[1], name = first.name or tostring(first.spellID or first[1]), raw = first, reason = "hekili:display" }
      if shared and shared.safeLog then shared.safeLog("hekili_display", out) end
      return out
    end
  end

  -- Try State pools without calling any functions
  if type(tbl.State) == "table" then
    local pool = tbl.State.Pool or tbl.State.Priority or tbl.State
    if type(pool) == "table" then
      local first = nil
      if #pool > 0 then
        first = pool[1]
      else
        for k,v in pairs(pool) do if type(v) == "table" then first = v; break end end
      end
        if first and type(first) == "table" then
        local out = { key = first.spellID or first.name or first[1], name = first.name or tostring(first.spellID or first[1]), raw = first, reason = "hekili:state" }
        if shared and shared.safeLog then shared.safeLog("hekili_state", out) end
        return out
      end
    end
  end

  -- If there's a Queue table, try to pick a first entry without calling methods
  if type(tbl.Queue) == "table" then
    local q = tbl.Queue
    local first = nil
    if #q > 0 then first = q[1] else for k,v in pairs(q) do if type(v) == "table" then first = v; break end end end
      if first and type(first) == "table" then
      local out = { key = first.spellID or first.name or first[1], name = first.name or tostring(first.spellID or first[1]), raw = first, reason = "hekili:queue" }
      if shared and shared.safeLog then shared.safeLog("hekili_queue_table", out) end
      return out
    end
  end

  -- Best-effort: try safe, non-crashing calls to commonly available Hekili API functions
  local tryFns = { "GetNextPrediction", "GetNextAction", "GetNext", "GetNextSpell", "GetNextPredictionForUnit" }
  for _, fname in ipairs(tryFns) do
    local f = tbl[fname] or (type(tbl[fname]) == "function" and tbl[fname])
    if type(f) == "function" then
      local ok, res = pcall(f, tbl, unit)
        if ok and res and type(res) == "table" then
        local key = res.spellID or res.spellId or res.spell or res.name or extractKeyFromRaw(res)
        if key then
          local out = { key = key, name = tostring(res.name or key), raw = res, reason = "hekili:api("..fname..")" }
          if shared and shared.safeLog then shared.safeLog("hekili_api", out) end
          return out
        end
      end
    end
  end

  return nil
end

OneButtonAssistantHekiliAdapter = HekiliAdapter

-- Expose a safe FetchState to provide summary info for the engine
function HekiliAdapter:FetchState(unit)
  -- NON-INVASIVE: collect only table/string/number fields without calling Hekili functions
  if not self:IsAvailable() then return nil end
  local tbl = Hekili or _G["Hekili"]
  if not tbl then return nil end
  local state = {}

  -- Basic metadata
  if tbl.Version then state.version = tbl.Version end
  if tbl.VersionString then state.versionString = tbl.VersionString end
  if tbl.CurrentBuild then state.currentBuild = tbl.CurrentBuild end
  if tbl.name then state.name = tbl.name end

  -- enemy counts: ECount (table) length or numeric fields
  if type(tbl.ECount) == "table" then
    state.eCount = #tbl.ECount
  end
  if type(tbl.TTD) == "table" then
    state.ttdTable = tbl.TTD
  end

  -- Snapshot top of DisplayPool / State tables
  if type(tbl.DisplayPool) == "table" and #tbl.DisplayPool > 0 then
    state._displayTop = tbl.DisplayPool[1]
  elseif type(tbl.State) == "table" then
    local pool = tbl.State.Pool or tbl.State.Priority or tbl.State
    if type(pool) == "table" then
      if #pool > 0 then
        state._displayTop = pool[1]
      else
        for k,v in pairs(pool) do if type(v) == "table" then state._displayTop = v; break end end
      end
    end
  end

  return state
end

-- Probe Hekili runtime table for introspection to help adapt adapters to concrete API versions.
function HekiliAdapter:Probe()
  if shared and shared.adapter_probe then
    return shared.adapter_probe("Hekili")
  end
  local tbl = Hekili or _G["Hekili"]
  if shared and shared.probeTable then
    return shared.probeTable("Hekili", tbl, self:IsAvailable())
  end
  local result = { name = "Hekili", found = self:IsAvailable(), fields = {}, note = "Non-invasive probe: function bodies are not executed." }
  if not tbl then return result end
  for k,v in pairs(tbl) do
    local t = type(v)
    local entry = { type = t }
    if t == "function" then
      entry.sample = "skipped(func)"
    elseif t == "table" then
      entry.sample = "table"
    else
      entry.sample = tostring(v)
    end
    result.fields[k] = entry
  end
  return result
end
