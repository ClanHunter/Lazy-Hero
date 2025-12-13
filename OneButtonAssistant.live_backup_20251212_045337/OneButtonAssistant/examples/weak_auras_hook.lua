-- Example WeakAuras hook: function WeakAuras can call to get next action
function OneButtonAssistant_GetNextAction(unit)
  if OneButtonAssistantEngine then
    return OneButtonAssistantEngine:GetNextAction(unit)
  end
  return nil
end
