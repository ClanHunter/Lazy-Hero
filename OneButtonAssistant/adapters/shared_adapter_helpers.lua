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
    if nd and nd ~= "" then
      local i = 1
      while i <= #nd do
        local s = nd:find("\n", i, true)
        if not s then
          table.insert(parts, nd:sub(i))
          break
        end
        table.insert(parts, nd:sub(i, s-1))
        i = s + 1
      end
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
  if e.e then table.insert(parts, '"e":"'..esc(e.e)..'"') end
  if e.s then table.insert(parts, '"s":'..tostring(e.s)) end
  if e.sn then table.insert(parts, '"sn":"'..esc(e.sn)..'"') end
  if e.amt then table.insert(parts, '"amt":'..tostring(e.amt)) end
  if e.src then table.insert(parts, '"src":"'..esc(e.src)..'"') end
  if e.dst then table.insert(parts, '"dst":"'..esc(e.dst)..'"') end
  return '{' .. table.concat(parts, ',') .. '}'
end

function M.matchToNDJSON(match)
  if not match or type(match) ~= 'table' then return nil end
  local lines = {}
  local meta = match.meta or {}
  local metaParts = {}
  for k, v in pairs(meta) do
    if type(v) == 'string' then
      table.insert(metaParts, '"'..tostring(k)..'":"'..esc(v)..'"')
    else
      table.insert(metaParts, '"'..tostring(k)..'":'..tostring(v))
    end
  end
  table.insert(lines, '{"meta":{'..table.concat(metaParts, ',')..'}}')
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
      if not chunks then
        -- fallback simple chunking using safe find/sub loop (avoids pattern parser issues)
        local parts = {}
        local ppos = 1
        while true do
          local ss, ee = nd:find("\n", ppos, true)
          if not ss then
            if ppos <= #nd then table.insert(parts, nd:sub(ppos)) end
            break
          end
          table.insert(parts, nd:sub(ppos, ss - 1))
          ppos = ee + 1
        end
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
  local player = {
    name = name or 'player',
    class = class or 'UNKNOWN',
    race = race or 'UNKNOWN',
    level = level or 0,
    faction = faction,
    guid = guid and M.guidHash(guid) or '-',
  }
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

-- CI touch: refreshed blob to ensure runners pick up latest file (2025-12-19T17:51:00Z)
-- Backup: OneButtonAssistant/adapters/shared_adapter_helpers.lua.bak_20251219_175100
return M
