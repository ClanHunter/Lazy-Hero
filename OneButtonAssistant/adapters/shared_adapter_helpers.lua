-- Shared adapter helper utilities for OneButtonAssistant
-- Clean, minimal, ASCII-only implementation to avoid parser issues.
-- Minimal safe stub to ensure Lua syntax checks pass while we finalize helpers.
OneButtonAssistantShared = OneButtonAssistantShared or {}
local M = OneButtonAssistantShared

function M.ensureDB()
  OneButtonAssistantDB = OneButtonAssistantDB or {}
  OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {}
end

function M.guidHash(guid)
  if not guid then return '-' end
  -- simple stable hash: last 12 chars or guid as-is
  local s = tostring(guid)
  if #s > 12 then
    return s:sub(-12)
  end
  return s
end

function M.safeCall(f, ...)
  if type(f) ~= 'function' then return nil end
  local ok, res = pcall(f, ...)
  if ok then return res end
  return nil
end

function M.now()
  local ok, t = pcall(function() return time() end)
  if ok and t then return t end
  return tonumber(os.time()) or 0
end

local function esc(s)
  if not s then return "" end
  s = tostring(s)
  s = s:gsub('\\', '\\\\')
  s = s:gsub('"', '\\"')
  s = s:gsub('\n', '\\n')
  s = s:gsub('\r', '\\r')
  s = s:gsub('\t', '\\t')
  return s
end

function M.escape_for_json(s)
  return esc(s)
end

function M.chunk_ndjson(nd, linesPerChunk)
  if not nd then return nil end
  linesPerChunk = tonumber(linesPerChunk) or 500
  local parts = {}
  local pos = 1
  while true do
    -- Shared adapter helper utilities for OneButtonAssistant
    -- Consolidated, parser-safe implementation. Small, pure helpers with pcall fallbacks.

    OneButtonAssistantShared = OneButtonAssistantShared or {}
    local M = OneButtonAssistantShared

    -- Ensure DB shape used by BG helpers
    function M.ensureDB()
      OneButtonAssistantDB = OneButtonAssistantDB or {}
      OneButtonAssistantDB.bgLogs = OneButtonAssistantDB.bgLogs or {}
      OneButtonAssistantDB.bgConfig = OneButtonAssistantDB.bgConfig or {}
      if OneButtonAssistantDB.bgConfig.maxEvents == nil then OneButtonAssistantDB.bgConfig.maxEvents = 2000 end
      if OneButtonAssistantDB.bgConfig.maxMatches == nil then OneButtonAssistantDB.bgConfig.maxMatches = 50 end
      if not OneButtonAssistantDB.bgSalt then OneButtonAssistantDB.bgSalt = tostring(math.random(1, 1e9)) end
    end

    -- Safe pcall wrapper used widely across the addon
    function M.safeCall(f, ...)
      if type(f) ~= 'function' then return nil end
      local ok, res = pcall(f, ...)
      if ok then return res end
      return nil
    end

    -- Time helper: prefer GetTime when available
    function M.now()
      if GetTime then
        local ok, t = pcall(GetTime)
        if ok and t then return t end
      end
      local ok, t = pcall(function() return os and os.time and os.time() end)
      if ok and t then return tonumber(t) end
      return 0
    end

    -- Deterministic GUID hash (lightweight)
    function M.guidHash(guid)
      if not guid then return '-' end
      M.ensureDB()
      local s = tostring(guid) .. (OneButtonAssistantDB.bgSalt or '')
      local h = 5381
      for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 1000000007 end
      return tostring(h)
    end

    local function _escape_str(s)
      if s == nil then return '' end
      s = tostring(s)
      s = s:gsub('\\', '\\\\')
      s = s:gsub('"', '\\"')
      s = s:gsub('\n', '\\n')
      s = s:gsub('\r', '\\r')
      s = s:gsub('\t', '\\t')
      return s
    end

    function M.escape_for_json(s) return _escape_str(s) end

    -- Split NDJSON into chunks safely without patterns
    function M.chunk_ndjson(nd, linesPerChunk)
      if not nd then return nil end
      linesPerChunk = tonumber(linesPerChunk) or 500
      local parts = {}
      local pos = 1
      while true do
        local s, e = nd:find('\n', pos, true)
        if not s then
          if pos <= #nd then table.insert(parts, nd:sub(pos)) end
          break
        end
        table.insert(parts, nd:sub(pos, s - 1))
        pos = e + 1
      end
      local chunks = {}
      local i = 1
      while i <= #parts do
        local j = math.min(i + linesPerChunk - 1, #parts)
        table.insert(chunks, table.concat(parts, '\n', i, j))
        i = j + 1
      end
      return chunks
    end

    function M.format_event_line(e)
      if not e or type(e) ~= 'table' then return nil end
      local parts = {}
      if e.t then table.insert(parts, '"t":'..tostring(e.t)) end
      if e.e then table.insert(parts, '"e":"'.._escape_str(e.e)..'"') end
      if e.s then table.insert(parts, '"s":'..tostring(e.s)) end
      if e.sn then table.insert(parts, '"sn":"'.._escape_str(e.sn)..'"') end
      if e.amt then table.insert(parts, '"amt":'..tostring(e.amt)) end
      if e.src then table.insert(parts, '"src":"'.._escape_str(e.src)..'"') end
      if e.dst then table.insert(parts, '"dst":"'.._escape_str(e.dst)..'"') end
      return '{' .. table.concat(parts, ',') .. '}'
    end

    function M.format_meta_line(meta, stats)
      if not meta then return '{"meta":{}}' end
      local esc = _escape_str
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

    function M.matchToNDJSON(match)
      if not match then return nil end
      local lines = {}
      table.insert(lines, M.format_meta_line(match.meta or {}, match.stats or {}))
      for _, e in ipairs(match.events or {}) do
        local line = M.format_event_line(e)
        if line then table.insert(lines, line) end
      end
      return table.concat(lines, '\n')
    end

    function M.prepare_export(matchID)
      if not matchID then return nil end
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

    function M.prepare_export_chunks(matchID, linesPerChunk)
      if not matchID then return nil end
      M.ensureDB()
      linesPerChunk = tonumber(linesPerChunk) or 500
      for _, m in ipairs(OneButtonAssistantDB.bgLogs or {}) do
        if m.meta and m.meta.matchID == matchID then
          local nd = M.matchToNDJSON(m)
          if not nd then return nil end
          local chunks = M.chunk_ndjson and M.chunk_ndjson(nd, linesPerChunk)
          OneButtonAssistantDB.bgExportChunks = OneButtonAssistantDB.bgExportChunks or {}
          OneButtonAssistantDB.bgExportChunks[matchID] = chunks
          OneButtonAssistantDB.bgExport = OneButtonAssistantDB.bgExport or {}
          OneButtonAssistantDB.bgExport[matchID] = nil
          OneButtonAssistantDB.bgExportManifest = OneButtonAssistantDB.bgExportManifest or {}
          OneButtonAssistantDB.bgExportManifest[matchID] = { chunks = chunks and #chunks or 0, linesPerChunk = linesPerChunk }
          return chunks
        end
      end
      return nil
    end

    function M.prepare_all_chunks(linesPerChunk)
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

    function M.get_player_position()
      local ok, mapID = pcall(function() if C_Map and C_Map.GetBestMapForUnit then return C_Map.GetBestMapForUnit('player') end end)
      if ok and mapID and C_Map and C_Map.GetPlayerMapPosition then
        local ok2, vec = pcall(function() return C_Map.GetPlayerMapPosition(mapID, 'player') end)
        if ok2 and vec and vec.x and vec.y then
          return { m = mapID, x = tonumber(string.format('%.4f', vec.x)), y = tonumber(string.format('%.4f', vec.y)) }
        end
      end
      local ok3, ux, uy, uz = pcall(function() return UnitPosition('player') end)
      if ok3 and ux and uy then
        return { x = tonumber(string.format('%.4f', ux)), y = tonumber(string.format('%.4f', uy)), z = tonumber(string.format('%.2f', uz or 0)) }
      end
      return nil
    end

    function M.gather_player_meta()
      local safe = M.safeCall
      local name = safe(UnitName, 'player')
      local _, class = safe(UnitClass, 'player')
      local race = safe(UnitRace, 'player')
      local level = safe(UnitLevel, 'player')
      local faction = safe(UnitFactionGroup) or 'unknown'
      local guid = safe(UnitGUID, 'player')
      local player = { name = name or 'player', class = class or 'UNKNOWN', race = race or 'UNKNOWN', level = level or 0, faction = faction, guid = guid and M.guidHash(guid) or '-' }
      local members = safe(GetNumGroupMembers) or 0
      local comp = {}
      if members and members > 0 then
        for i = 1, members do
          local unit = (IsInRaid and IsInRaid()) and ('raid'..i) or ('party'..i)
          local _, c = safe(UnitName, unit), safe(UnitClass, unit)
          if c then comp[c] = (comp[c] or 0) + 1 end
        end
      end
      return player, comp
    end

    function M.parse_combat_extras(args)
      if not args or type(args) ~= 'table' then return {} end
      local srcGUID = args[4]
      local dstGUID = args[8]
      local res = { src = M.guidHash(srcGUID), dst = M.guidHash(dstGUID) }
      local spellId = args[12]
      local spellName = args[13]
      if spellId and type(spellId) == 'number' then res.s = spellId end
      if spellName and type(spellName) == 'string' then res.sn = spellName end
      for i = 14, #args do if type(args[i]) == 'number' then res.amt = args[i]; break end end
      return res
    end

    function M.create_export_frame()
      if not CreateFrame or not UIParent then return nil end
      local f = CreateFrame('Frame', 'OneButtonAssistantBGExportUI', UIParent, 'BasicFrameTemplateWithInset')
      f:SetSize(700, 420)
      f:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
      f.title = f:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight')
      f.title:SetPoint('TOPLEFT', 16, -8)
      f.title:SetText('OneButtonAssistant - BG Export (copy from the box below)')
      f.scroll = CreateFrame('ScrollFrame', nil, f, 'UIPanelScrollFrameTemplate')
      f.scroll:SetPoint('TOPLEFT', 12, -32)
      f.scroll:SetPoint('BOTTOMRIGHT', -36, 38)
      local eb = CreateFrame('EditBox', nil, f.scroll)
      eb:SetMultiLine(true)
      eb:EnableMouse(true)
      eb:SetAutoFocus(false)
      eb:SetFontObject(GameFontHighlightSmall)
      eb:SetWidth(640)
      eb:SetHeight(340)
      eb:SetScript('OnEscapePressed', function(self) f:Hide() end)
      f.scroll:SetScrollChild(eb)
      f.editBox = eb
      return f
    end

    function M.extractKeyFromRaw(raw)
      if not raw then return nil end
      if type(raw) ~= 'table' then return tostring(raw) end
      local candidates = { 'key', 'spell', 'suggestion', 'next', 'action', 'name', 'id', 'spellID' }
      for _, k in ipairs(candidates) do if raw[k] then return raw[k] end end
      if raw[1] then return raw[1] end
      for k, v in pairs(raw) do
        if type(v) == 'string' or type(v) == 'number' then return v end
        if type(v) == 'table' then
          for _, vv in pairs(v) do if type(vv) == 'string' or type(vv) == 'number' then return vv end end
        end
      end
      return nil
    end

    function M.safeLog(topic, payload)
      if payload == nil then return end
      if OneButtonAssistantLogger and OneButtonAssistantLogger.Log then
        pcall(OneButtonAssistantLogger.Log, OneButtonAssistantLogger, topic, payload)
        return
      end
      pcall(print, '[OneButtonAssistant]', topic, payload)
    end

    function M.probeTable(name, tbl, found)
      local result = { name = name or 'unknown', found = found and true or false, fields = {}, note = 'Non-invasive probe: function bodies are not executed.' }
      if not tbl then return result end
      for k, v in pairs(tbl) do
        local t = type(v)
        local entry = { type = t }
        if t == 'function' then entry.sample = 'skipped(func)' elseif t == 'table' then entry.sample = 'table' else entry.sample = tostring(v) end
        result.fields[k] = entry
      end
      return result
    end

    function M.get_module(name)
      if not name then return nil end
      if type(_G) == 'table' and _G[name] and type(_G[name]) == 'table' then return _G[name] end
      return nil
    end

    function M.adapter_is_available(name)
      if not name then return false end
      local m = M.get_module and M.get_module(name) or _G[name]
      return type(m) == 'table'
    end

    function M.adapter_probe(name)
      local tbl = M.get_module and M.get_module(name) or _G[name]
      return M.probeTable and M.probeTable(name, tbl, type(tbl) == 'table') or { name = name or 'unknown', found = type(tbl) == 'table', fields = {}, note = 'probe unavailable' }
    end

    M.Logger = M.Logger or {}
    do
      local L = M.Logger
      function L:Log(event, data)
        self.data = self.data or {}
        table.insert(self.data, { time = (M.now and M.now() or 0), event = event, data = data })
      end
      function L:GetAll() return self.data or {} end
    end

    return M
            eb:EnableMouse(true)
