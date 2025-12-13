-- Simple in-memory logger for rotation analysis
-- Delegate logger to shared helpers when available
local shared = OneButtonAssistantShared
if shared and shared.Logger then
  OneButtonAssistantLogger = shared.Logger
else
  -- fallback simple logger
  local Logger = {}
  function Logger:Log(event, data)
    self.data = self.data or {}
    table.insert(self.data, { time = (time and time()) or 0, event = event, data = data })
  end
  function Logger:GetAll()
    return self.data or {}
  end
  OneButtonAssistantLogger = Logger
end
