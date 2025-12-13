-- Details adapter: conservative probe for Details addon presence
local Adapter = {}
Adapter.name = "details"

function Adapter:IsAvailable()
  return (type(Details) == "table") or (type(_G["Details"]) == "table")
end

function Adapter:Probe()
  if type(Details) ~= "table" then return { found = false } end
  local ok, ver = pcall(function() return Details.version end)
  return { found = true, version = (ok and ver) or "unknown" }
end

function Adapter:FetchState(unit)
  -- very conservative: don't call Details internals; if Details exposes a safe API in future we can pcall and map
  return nil
end

OneButtonAssistantDetailsAdapter = Adapter
return Adapter
