-- Basic UI helpers for OneButtonAssistant (Ace3 optional)
local UI = {}

function UI:Init()
  if not LibStub then
    print("[OneButtonAssistant] LibStub not found; skipping AceConfig UI.")
    return
  end
  local AceConfig = LibStub and LibStub("AceConfig-3.0", true)
  if not AceConfig then
    print("[OneButtonAssistant] AceConfig-3.0 not found; UI will be minimal.")
    return
  end
  -- Register options here if AceConfig is available
end

OneButtonAssistantUI = UI
