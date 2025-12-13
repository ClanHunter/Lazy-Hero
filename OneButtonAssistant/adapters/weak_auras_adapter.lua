-- WeakAuras adapter: exposes a hook that WA can call to provide state updates
local WAAdapter = {}

local shared = OneButtonAssistantShared

-- store last pushed WA state for FetchState
WAAdapter._lastPush = nil

function WAAdapter:IsAvailable()
  if shared and shared.adapter_is_available then
    return shared.adapter_is_available("WeakAuras")
  end
  return (type(WeakAuras) == "table") or (type(_G["WeakAuras"]) == "table")
end

-- WeakAuras can call this global function to push state into the engine
function OneButtonAssistant_ReceiveWAState(state)
  -- expected state is a table like: { talents = {...}, procs = {...}, enemyCount = n, cooldowns = {...} }
  if type(state) ~= "table" then return false end
  -- cache for FetchState
  WAAdapter._lastPush = state
    if OneButtonAssistant and OneButtonAssistantEngine and OneButtonAssistantEngine.UpdateState then
    OneButtonAssistantEngine:UpdateState(state)
    if shared and shared.safeLog then
      shared.safeLog("weakauras_state", state)
    end
    -- attempt to save raw suggestion snapshot if present
    pcall(function()
        if OneButtonAssistant and OneButtonAssistant.SaveRawSuggestion and state then
        -- save the full state as a raw suggestion under weakauras for later inspection
        OneButtonAssistant:SaveRawSuggestion("weakauras", state)
      end
    end)
    return true
  end
  return false
end

-- For compatibility expose adapter object
OneButtonAssistantWeakAurasAdapter = WAAdapter

local function extractKeyFromRaw(raw)
  if shared and shared.extractKeyFromRaw then return shared.extractKeyFromRaw(raw) end
  if not raw then return nil end
  if type(raw) ~= "table" then return tostring(raw) end
  return nil
end
-- Probe WeakAuras runtime table for introspection
function WAAdapter:Probe()
  if shared and shared.adapter_probe then
    return shared.adapter_probe("WeakAuras")
  end
  -- Non-invasive probe: record field types but DO NOT execute WeakAuras functions (they often require parameters)
  local result = { name = "WeakAuras", found = self:IsAvailable(), fields = {}, note = "Non-invasive probe: function bodies are not executed." }
  local tbl = WeakAuras or _G["WeakAuras"]
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

-- allow adapters to return a best-effort state gathered from recent WA pushes
function WAAdapter:FetchState(unit)
  -- Return the cached WA state (may be nil)
  if self._lastPush and type(self._lastPush) == "table" then
    return self._lastPush
  end
  return nil
end

-- Provide a best-effort suggestion mapping from the last WA push
function WAAdapter:GetSuggestion(unit)
  -- Prefer persisted saved raw suggestion if present (offline analysis)
  if OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion.weakauras then
    local raw = OneButtonAssistantDB.lastRawSuggestion.weakauras
    local key = extractKeyFromRaw(raw)
    if key then return { key = key, name = tostring(key), raw = raw, reason = "saved:weakauras" } end
  end
  if self._lastPush and type(self._lastPush) == "table" then
    local s = self._lastPush
    -- common fields: suggestion, next, action, spell
    local key = s.suggestion or s.next or s.action or s.spell or s.name
      if key then
      local out = { key = key, name = tostring(key), raw = s, reason = "weakauras:push" }
      if shared and shared.safeLog then shared.safeLog("weakauras_suggestion", out) end
      return out
    end
  end
  return nil
end
