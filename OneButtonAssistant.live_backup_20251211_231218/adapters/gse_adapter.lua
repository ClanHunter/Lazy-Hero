-- GSE adapter stub for OneButtonAssistant
local GSEAdapter = {}

-- Helper: try to extract a usable key/name from an arbitrary raw suggestion table
local function extractKeyFromRaw(raw)
  if not raw then return nil end
  if type(raw) ~= "table" then return tostring(raw) end
  local candidates = { "key", "spell", "suggestion", "next", "action", "name", "id", "spellID" }
  for _,k in ipairs(candidates) do
    if raw[k] then return raw[k] end
  end
  if raw[1] then return raw[1] end
  for k,v in pairs(raw) do
    if type(v) == "string" or type(v) == "number" then return v end
    if type(v) == "table" then
      for kk,vv in pairs(v) do
        if type(vv) == "string" or type(vv) == "number" then return vv end
      end
    end
  end
  return nil
end

function GSEAdapter:IsAvailable()
  return (type(GSE) == "table") or (type(_G["GSE"]) == "table")
end

function GSEAdapter:LoadSequences()
  -- Placeholder for loading user GSE sequences and translating them into priorities
  -- Try common API names safely
  local sequences = nil
  local candidates = { "GetSequence", "GetSequences", "GetProfile", "GetAllSequences" }
  for _, fname in ipairs(candidates) do
    local fn = GSE[fname]
    if type(fn) == "function" then
      -- avoid calling potentially heavy functions during probe; try calling only the simplest ones
      local ok, res = pcall(fn, GSE)
      if ok and res then sequences = res; break end
    end
  end
  return sequences
end

function GSEAdapter:FetchState(unit)
  -- GSE doesn't typically provide dynamic state; return nil
  return nil
end

function GSEAdapter:GetSuggestion(unit)
  -- If a persisted raw suggestion exists (saved on WoW exit), prefer it for offline analysis
  if OneButtonAssistantDB and OneButtonAssistantDB.lastRawSuggestion and OneButtonAssistantDB.lastRawSuggestion.gse then
    local raw = OneButtonAssistantDB.lastRawSuggestion.gse
    local key = extractKeyFromRaw(raw)
    if key then return { key = key, name = tostring(key), raw = raw, reason = "saved:gse" } end
  end
  if not self:IsAvailable() then return nil end
  -- GSE is primarily a macro/sequencer; it may expose sequences but not live suggestions
  -- Some setups might include helper functions; attempt to map a current sequence to an action
  local seq = nil
  local ok, res = pcall(function()
    if GSE.GetCurrentSequence and type(GSE.GetCurrentSequence) == "function" then
      return GSE:GetCurrentSequence(unit)
    elseif GSE.GetSequence and type(GSE.GetSequence) == "function" then
      return GSE:GetSequence(unit)
    end
    return nil
  end)
  if ok and res then seq = res end
  if seq then
    -- If sequence is a table, try to return its next action name
    if type(seq) == "table" then
      local name = seq.next or seq[1] or seq.name
      local out = { key = name, name = tostring(name), raw = seq, reason = "gse:sequence" }
      if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "gse_sequence", out) end
      return out
    else
      local out = { key = tostring(seq), name = tostring(seq), raw = seq, reason = "gse:sequence" }
      if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "gse_sequence", out) end
      return out
    end
    -- Fallback: inspect UsedSequences table (non-invasive)
    if type(GSE.UsedSequences) == "table" then
      for k,v in pairs(GSE.UsedSequences) do
        local name = k
        if type(name) == "string" and name ~= "" then
          local out = { key = name, name = name, raw = { used = true }, reason = "gse:usedSequences" }
          if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "gse_used", out) end
          return out
        end
      end
    end

    -- Best-effort: try safe, non-crashing calls to common GSE API functions that return sequence names
    local tryNameFns = { "GetSequenceNames", "GetSequenceSummary", "GetSequenceNamesFromLibrary", "GetSequence" }
    for _, fname in ipairs(tryNameFns) do
      local f = GSE[fname]
      if type(f) == "function" then
        local ok, res = pcall(f, GSE)
        if ok and res then
          if type(res) == "table" then
            local name = nil
            -- if function returns a list of names, pick first
            if #res > 0 and type(res[1]) == "string" then name = res[1] end
            -- if returns a table keyed by name, pick first key
            if not name then for k,v in pairs(res) do if type(k) == "string" then name = k; break end end end
            if name then
              local out = { key = name, name = name, raw = res, reason = "gse:api("..fname..")" }
              if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "gse_api", out) end
              return out
            end
          elseif type(res) == "string" then
            local out = { key = res, name = res, raw = res, reason = "gse:api("..fname..")" }
            if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, "gse_api", out) end
            return out
          end
        end
      end
    end
  end
  return nil
end

-- Probe GSE runtime table for introspection
function GSEAdapter:Probe()
  -- Non-invasive probe: record field types but avoid calling functions that may be heavy or cause timeouts
  local result = { name = "GSE", found = self:IsAvailable(), fields = {}, note = "Non-invasive probe: function bodies are not executed." }
  local tbl = GSE or _G["GSE"]
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

OneButtonAssistantGSEAdapter = GSEAdapter
