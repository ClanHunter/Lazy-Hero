-- Simple in-memory logger for rotation analysis
local Logger = {}

function Logger:Log(event, data)
  self.data = self.data or {}
  table.insert(self.data, {time = time(), event = event, data = data})
end

function Logger:GetAll()
  return self.data or {}
end

OneButtonAssistantLogger = Logger
