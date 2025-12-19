-- Shared adapter helper utilities for OneButtonAssistant
OneButtonAssistantShared = OneButtonAssistantShared or {}

local M = OneButtonAssistantShared

-- Extract a usable key/name from an arbitrary raw suggestion table/value
function M.extractKeyFromRaw(raw)
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

-- Safe logger wrapper: pcall into OneButtonAssistantLogger if present
function M.safeLog(topic, payload)
  if not payload then return end
  if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
    pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, topic, payload)
    return
  end
  -- fallback: write to print (non-invasive)
  -- pcall to avoid spam if print is overridden
  pcall(print, "[OneButtonAssistant]", topic, payload)
end

-- Generic non-invasive probe helper. Returns a table describing fields.
function M.probeTable(name, tbl, found)
  local result = { name = name or "unknown", found = found and true or false, fields = {}, note = "Non-invasive probe: function bodies are not executed." }
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

-- Return a module table from the global namespace (safe lookup helper)
function M.get_module(name)
  if not name then return nil end
  if type(_G) == 'table' and _G[name] and type(_G[name]) == 'table' then
    return _G[name]
  end
  return nil
end

-- Adapter availability helper: safe check for presence of a named global module/table
function M.adapter_is_available(name)
  if not name then return false end
  if M.get_module then
    local m = M.get_module(name)
    return type(m) == 'table'
  end
  return (type(_G[name]) == 'table')
end

-- Adapter probe wrapper: returns shared.probeTable result when available
function M.adapter_probe(name)
  local tbl = nil
  if M.get_module then tbl = M.get_module(name) else tbl = _G[name] end
  if M.probeTable then return M.probeTable(name, tbl, type(tbl) == 'table') end
  return { name = name or 'unknown', found = type(tbl) == 'table', fields = {}, note = 'probe unavailable' }
end

-- Simple in-memory logger for compatibility across adapters
M.Logger = M.Logger or {}
do
  local L = M.Logger
  function L:Log(event, data)
    self.data = self.data or {}
    table.insert(self.data, { time = (time and time()) or 0, event = event, data = data })
  end
  function L:GetAll()
    return self.data or {}
  end
end

-- Safe call wrapper used widely across the addon (pcall wrapper)
function M.safeCall(f, ...)
  if not f then return nil end
  local ok, res = pcall(f, ...)
  if ok then return res end
  return nil
end

-- Time helper: prefer GetTime when available
function M.now()
  return (GetTime and GetTime()) or time()
end

-- Ensure the bg logger DB structure exists
function M.ensureDB()
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {}
  OneButtonAssistantDB.bgConfig = OneButtonAssistantDB.bgConfig or {}
  if OneButtonAssistantDB.bgConfig.maxEvents == nil then OneButtonAssistantDB.bgConfig.maxEvents = 2000 end
  if OneButtonAssistantDB.bgConfig.maxMatches == nil then OneButtonAssistantDB.bgConfig.maxMatches = 50 end
  if not OneButtonAssistantDB.bgSalt then OneButtonAssistantDB.bgSalt = tostring(math.random(1, 1e9)) end
end

-- guidHash: deterministic obfuscated hash for GUIDs (same algorithm as original bglogger)
function M.guidHash(guid)
  if not guid then return "-" end
  M.ensureDB()
  local s = tostring(guid) .. (OneButtonAssistantDB.bgSalt or "")
  local h = 5381
  for i = 1, #s do
    h = (h * 33 + string.byte(s, i)) % 1000000007
  end
  return tostring(h)
end

-- Escape a string for inclusion in a minimal JSON context (used by NDJSON export)
function M.escape_for_json(s)
  if s == nil then return "" end
  local str = tostring(s)
  str = str:gsub('\\', '\\\\')
  str = str:gsub('"', '\\"')
  str = str:gsub('\n', '\\n')
  str = str:gsub('\r', '\\r')
  str = str:gsub('\t', '\\t')
  return str
end

-- Split an NDJSON string into chunks by number of lines. Returns array of chunk strings.
function M.chunk_ndjson(nd, linesPerChunk)
  if not nd then return nil end
  linesPerChunk = tonumber(linesPerChunk) or 500
  local parts = {}
]+)\n?") do table.insert(parts, line) end
  for line in nd:gmatch("([^\\n]+)\\n?") do table.insert(parts, line) end
  local chunks = {}
  local i = 1
  while i <= #parts do
    local j = math.min(i + linesPerChunk - 1, #parts)
    local seg = table.concat(parts, "\n", i, j)
    table.insert(chunks, seg)
    i = j + 1
  end
  return chunks
end

-- Format a single event as a compact JSON line (used by NDJSON export)
function M.format_event_line(e)
  if not e then return nil end
  local esc = M.escape_for_json
  local parts = {}
  if e.t then table.insert(parts, '"t":'..tostring(e.t)) end
  if e.e then table.insert(parts, '"e":"'..esc(e.e)..'"') end
  if e.s then table.insert(parts, '"s":'..tostring(e.s)) end
  if e.sn then table.insert(parts, '"sn":"'..esc(e.sn)..'"') end
  if e.amt then table.insert(parts, '"amt":'..tostring(e.amt)) end
  if e.src then table.insert(parts, '"src":"'..esc(e.src)..'"') end
  if e.dst then table.insert(parts, '"dst":"'..esc(e.dst)..'"') end
  return '{' .. table.concat(parts, ',') .. '}'
end

-- Format the meta + player + stats line for a match as a single NDJSON meta line
function M.format_meta_line(meta, stats)
  if not meta then return '{"meta":{}}' end
  local esc = M.escape_for_json
  local metaParts = {}
  table.insert(metaParts, '"matchID":"'..esc(meta.matchID)..'"')
  table.insert(metaParts, '"zone":"'..esc(meta.zone)..'"')
  table.insert(metaParts, '"startTime":'..tostring(meta.startTime or 0))
  table.insert(metaParts, '"endTime":'..tostring(meta.endTime or 0))
  table.insert(metaParts, '"events":'..tostring(meta.events or 0))
  table.insert(metaParts, '"truncated":'..tostring(meta.truncated and true or false))
  local p = meta.player or {}
  local playerParts = {}
  if p.name then table.insert(playerParts, '"name":"'..esc(p.name)..'"') end
  if p.class then table.insert(playerParts, '"class":"'..esc(p.class)..'"') end
  if p.race then table.insert(playerParts, '"race":"'..esc(p.race)..'"') end
  if p.level then table.insert(playerParts, '"level":'..tostring(p.level)) end
  if p.faction then table.insert(playerParts, '"faction":"'..esc(p.faction)..'"') end
  if p.guid then table.insert(playerParts, '"guid":"'..esc(p.guid)..'"') end
  table.insert(metaParts, '"player":{'..table.concat(playerParts, ',')..'}')
  local sp = stats or {}
  local statsParts = {}
  table.insert(statsParts, '"damageDone":'..tostring(sp.damageDone or 0))
  table.insert(statsParts, '"healingDone":'..tostring(sp.healingDone or 0))
  table.insert(statsParts, '"damageTaken":'..tostring(sp.damageTaken or 0))
  table.insert(statsParts, '"kills":'..tostring(sp.kills or 0))
  table.insert(statsParts, '"deaths":'..tostring(sp.deaths or 0))
  table.insert(statsParts, '"interruptsByPlayer":'..tostring(sp.interruptsByPlayer or 0))
  table.insert(statsParts, '"interruptsOnPlayer":'..tostring(sp.interruptsOnPlayer or 0))
  table.insert(statsParts, '"dispelsByPlayer":'..tostring(sp.dispelsByPlayer or 0))
  table.insert(statsParts, '"dispelsOnPlayer":'..tostring(sp.dispelsOnPlayer or 0))
  table.insert(statsParts, '"auraAppliedByPlayer":'..tostring(sp.auraAppliedByPlayer or 0))
  table.insert(statsParts, '"auraAppliedToPlayer":'..tostring(sp.auraAppliedToPlayer or 0))
  table.insert(metaParts, '"stats":{'..table.concat(statsParts, ',')..'}')
  return '{"meta":{'..table.concat(metaParts, ',')..'}}'
end

-- Build NDJSON string for a match (shared implementation)
function M.matchToNDJSON(match)
  if not match then return nil end
  local esc = M.escape_for_json
  local lines = {}
  local m = match.meta or {}
  local p = m.player or {}
  local s = match.stats or {}
  if M.format_meta_line then
    table.insert(lines, M.format_meta_line(m, s))
  else
    local metaParts = {}
    table.insert(metaParts, '"matchID":"'..esc(m.matchID)..'"')
    table.insert(metaParts, '"zone":"'..esc(m.zone)..'"')
    table.insert(metaParts, '"startTime":'..tostring(m.startTime or 0))
    table.insert(metaParts, '"endTime":'..tostring(m.endTime or 0))
    table.insert(metaParts, '"events":'..tostring(m.events or 0))
    table.insert(metaParts, '"truncated":'..tostring(m.truncated and true or false))
    local playerParts = {}
    if p.name then table.insert(playerParts, '"name":"'..esc(p.name)..'"') end
    if p.class then table.insert(playerParts, '"class":"'..esc(p.class)..'"') end
    if p.race then table.insert(playerParts, '"race":"'..esc(p.race)..'"') end
    if p.level then table.insert(playerParts, '"level":'..tostring(p.level)) end
    if p.faction then table.insert(playerParts, '"faction":"'..esc(p.faction)..'"') end
    if p.guid then table.insert(playerParts, '"guid":"'..esc(p.guid)..'"') end
    table.insert(metaParts, '"player":{'..table.concat(playerParts, ',')..'}')
    local statsParts = {}
    local sp = s
    table.insert(statsParts, '"damageDone":'..tostring(sp.damageDone or 0))
    table.insert(statsParts, '"healingDone":'..tostring(sp.healingDone or 0))
    table.insert(statsParts, '"damageTaken":'..tostring(sp.damageTaken or 0))
    table.insert(statsParts, '"kills":'..tostring(sp.kills or 0))
    table.insert(statsParts, '"deaths":'..tostring(sp.deaths or 0))
    table.insert(statsParts, '"interruptsByPlayer":'..tostring(sp.interruptsByPlayer or 0))
    table.insert(statsParts, '"interruptsOnPlayer":'..tostring(sp.interruptsOnPlayer or 0))
    table.insert(statsParts, '"dispelsByPlayer":'..tostring(sp.dispelsByPlayer or 0))
    table.insert(statsParts, '"dispelsOnPlayer":'..tostring(sp.dispelsOnPlayer or 0))
    table.insert(statsParts, '"auraAppliedByPlayer":'..tostring(sp.auraAppliedByPlayer or 0))
    table.insert(statsParts, '"auraAppliedToPlayer":'..tostring(sp.auraAppliedToPlayer or 0))
    table.insert(metaParts, '"stats":{'..table.concat(statsParts, ',')..'}')
    table.insert(lines, '{"meta":{'..table.concat(metaParts, ',')..'}}')
  end
  for _, e in ipairs(match.events or {}) do
    local line = nil
    if M.format_event_line then
      line = M.format_event_line(e)
    else
      local parts = {}
      if e.t then table.insert(parts, '"t":'..tostring(e.t)) end
      if e.e then table.insert(parts, '"e":"'..esc(e.e)..'"') end
      if e.s then table.insert(parts, '"s":'..tostring(e.s)) end
      if e.sn then table.insert(parts, '"sn":"'..esc(e.sn)..'"') end
      if e.amt then table.insert(parts, '"amt":'..tostring(e.amt)) end
      if e.src then table.insert(parts, '"src":"'..esc(e.src)..'"') end
      if e.dst then table.insert(parts, '"dst":"'..esc(e.dst)..'"') end
      line = '{' .. table.concat(parts, ',') .. '}'
    end
    if line then table.insert(lines, line) end
  end
  return table.concat(lines, "\n")
end

-- Prepare NDJSON export for a match and write to OneButtonAssistantDB.bgExport
function M.prepare_export(matchID)
  if not matchID then return nil end
  M.ensureDB = M.ensureDB or function() OneButtonAssistantDB = OneButtonAssistantDB or {}; OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {} end
  M.ensureDB()
  for _, m in ipairs(OneButtonAssistantDB.bgLogs or {}) do
    if m.meta and m.meta.matchID == matchID then
      local nd = M.matchToNDJSON(m)
      OneButtonAssistantDB.bgExport = OneButtonAssistantDB.bgExport or {}
      OneButtonAssistantDB.bgExport[matchID] = nd
      return nd
    end
  end
  return nil
end

-- Prepare NDJSON chunks for a match and write to OneButtonAssistantDB.bgExportChunks
function M.prepare_export_chunks(matchID, linesPerChunk)
  if not matchID then return nil end
  M.ensureDB = M.ensureDB or function() OneButtonAssistantDB = OneButtonAssistantDB or {}; OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {} end
  M.ensureDB()
  linesPerChunk = tonumber(linesPerChunk) or 500
  for _, m in ipairs(OneButtonAssistantDB.bgLogs or {}) do
    if m.meta and m.meta.matchID == matchID then
      local nd = M.matchToNDJSON(m)
      if not nd then return nil end
      local chunks = M.chunk_ndjson and M.chunk_ndjson(nd, linesPerChunk)
      if not chunks then
        -- fallback simple chunking
        local parts = {}
        for line in nd:gmatch("([^\n]+)\n?") do table.insert(parts, line) end
        chunks = {}
        local i = 1
        while i <= #parts do
          local j = math.min(i + linesPerChunk - 1, #parts)
          local seg = table.concat(parts, "\n", i, j)
          table.insert(chunks, seg)
          i = j + 1
        end
      end
      OneButtonAssistantDB.bgExportChunks = OneButtonAssistantDB.bgExportChunks or {}
      OneButtonAssistantDB.bgExportChunks[matchID] = chunks
      OneButtonAssistantDB.bgExport = OneButtonAssistantDB.bgExport or {}
      OneButtonAssistantDB.bgExport[matchID] = nil
      OneButtonAssistantDB.bgExportManifest = OneButtonAssistantDB.bgExportManifest or {}
      OneButtonAssistantDB.bgExportManifest[matchID] = { chunks = #chunks, linesPerChunk = linesPerChunk }
      return chunks
    end
  end
  return nil
end

-- Prepare chunked exports for all saved matches and return a map of matchID -> chunk count
function M.prepare_all_chunks(linesPerChunk)
  M.ensureDB = M.ensureDB or function() OneButtonAssistantDB = OneButtonAssistantDB or {}; OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {} end
  M.ensureDB()
  local results = {}
  for _, m in ipairs(OneButtonAssistantDB.bgLogs or {}) do
    local id = m.meta and m.meta.matchID
    if id then
      local chunks = M.prepare_export_chunks(id, linesPerChunk)
      results[id] = chunks and #chunks or 0
    end
  end
  return results
end

-- Get player position in a safe, guarded way. Returns a position table or nil.
function M.get_player_position()
  -- Try C_Map-based precise map coords first
  local ok, mapID = pcall(function() if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit("player") end end)
  if ok and mapID and C_Map and C_Map.GetPlayerMapPosition then
    local ok2, vec = pcall(function() return C_Map.GetPlayerMapPosition(mapID, "player") end)
    if ok2 and vec and vec.x and vec.y then
      return { m = mapID, x = tonumber(string.format("%.4f", vec.x)), y = tonumber(string.format("%.4f", vec.y)) }
    end
  end
  -- Fallback to UnitPosition for rough coordinates
  local ok3, ux, uy, uz = pcall(function() return UnitPosition("player") end)
  if ok3 and ux and uy then
    return { x = tonumber(string.format("%.4f", ux)), y = tonumber(string.format("%.4f", uy)), z = tonumber(string.format("%.2f", uz or 0)) }
  end
  return nil
end

-- Gather player metadata and a simple team composition summary.
-- Returns (playerTable, teamTable)
function M.gather_player_meta()
  local safe = M.safeCall or function(f, ...) if not f then return nil end local ok, res = pcall(f, ...) if ok then return res end return nil end
  local name = safe(UnitName, "player")
  local _, class = safe(UnitClass, "player")
  local race = safe(UnitRace, "player")
  local level = safe(UnitLevel, "player")
  local faction = safe(UnitFactionGroup) or "unknown"
  local guid = safe(UnitGUID, "player")
  local player = {
    name = name or "player",
    class = class or "UNKNOWN",
    race = race or "UNKNOWN",
    level = level or 0,
    faction = faction,
    guid = guid and M.guidHash(guid) or "-",
  }
  local members = safe(GetNumGroupMembers) or 0
  local comp = {}
  if members and members > 0 then
    for i = 1, members do
      local unit = (IsInRaid and IsInRaid()) and ("raid"..i) or ("party"..i)
      local _, c = safe(UnitName, unit), safe(UnitClass, unit)
      if c then comp[c] = (comp[c] or 0) + 1 end
    end
  end
  return player, comp
end

-- Parse common combat-log fields from the args array returned by CombatLogGetCurrentEventInfo().
-- Returns a table with { src=<hash>, dst=<hash>, s=<spellId?>, sn=<spellName?>, amt=<amount?> }
function M.parse_combat_extras(args)
  if not args or type(args) ~= 'table' then return {} end
  local srcGUID = args[4]
  local dstGUID = args[8]
  local src = M.guidHash(srcGUID)
  local dst = M.guidHash(dstGUID)
  local res = { src = src, dst = dst }
  local spellId = args[12]
  local spellName = args[13]
  if spellId and type(spellId) == 'number' then res.s = spellId end
  if spellName and type(spellName) == 'string' then res.sn = spellName end
  for i = 14, #args do
    if type(args[i]) == 'number' then res.amt = args[i]; break end
  end
  return res
end

-- Create and return a reusable export UI frame (does not assign to globals).
-- Caller should assign to their local/export variable (e.g., `BGLogger._exportFrame`).
function M.create_export_frame()
  if not CreateFrame or not UIParent then return nil end
  local f = CreateFrame("Frame", "OneButtonAssistantBGExportUI", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(700, 420)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.title:SetPoint("TOPLEFT", 16, -8)
  f.title:SetText("OneButtonAssistant - BG Export (copy from the box below)")
  f.scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", 12, -32)
  f.scroll:SetPoint("BOTTOMRIGHT", -36, 38)
  local eb = CreateFrame("EditBox", nil, f.scroll)
  eb:SetMultiLine(true)
  eb:EnableMouse(true)
  eb:SetAutoFocus(false)
  eb:SetFontObject(GameFontHighlightSmall)
  eb:SetWidth(640)
  eb:SetHeight(340)
  eb:SetScript("OnEscapePressed", function(self) f:Hide() end)
  f.scroll:SetScrollChild(eb)
  f.editBox = eb
  return f
end

return M
