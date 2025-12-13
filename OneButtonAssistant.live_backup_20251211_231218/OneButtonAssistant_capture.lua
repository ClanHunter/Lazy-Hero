-- Lightweight, safe combat-log capture for OneButtonAssistant
-- Records recent player spell events into OneButtonAssistantDB.lastRawSuggestion.capture

local MAX_ENTRIES = 200

local frame = CreateFrame("Frame", "OneButtonAssistant_CaptureFrame")

local function safeInsert(tbl, v)
    if not tbl then return end
    table.insert(tbl, 1, v)
    if #tbl > MAX_ENTRIES then
        table.remove(tbl)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event ~= "COMBAT_LOG_EVENT_UNFILTERED" then return end
    local ok, timestamp, subevent, hideCaster, sourceGUID, sourceName, sourceFlags, sourceRaidFlags,
          destGUID, destName, destFlags, destRaidFlags, spellId, spellName = pcall(CombatLogGetCurrentEventInfo)
    if not ok then return end
    if not sourceGUID then return end

    local playerGUID = UnitGUID("player")
    if sourceGUID ~= playerGUID then return end

    -- capture common spell events that indicate an action
    if subevent == "SPELL_CAST_START" or subevent == "SPELL_CAST_SUCCESS" or subevent == "SPELL_AURA_APPLIED" then
        OneButtonAssistantDB = OneButtonAssistantDB or {}
        OneButtonAssistantDB.lastRawSuggestion = OneButtonAssistantDB.lastRawSuggestion or {}
        OneButtonAssistantDB.lastRawSuggestion.capture = OneButtonAssistantDB.lastRawSuggestion.capture or { entries = {} }
        local entries = OneButtonAssistantDB.lastRawSuggestion.capture.entries
        local record = {
            t = GetTime(),
            subevent = subevent,
            spellId = spellId,
            spellName = spellName,
            dest = destName,
        }
        safeInsert(entries, record)
    end
end)

frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")

-- optional slash helper to dump recent capture into chat for quick inspection
SLASH_OBA_CAPTURE1 = "/oba_capture"
SlashCmdList["OBA_CAPTURE"] = function()
    if not OneButtonAssistantDB or not OneButtonAssistantDB.lastRawSuggestion or not OneButtonAssistantDB.lastRawSuggestion.capture then
        print("OneButtonAssistant: no capture data recorded yet")
        return
    end
    local entries = OneButtonAssistantDB.lastRawSuggestion.capture.entries
    print("OneButtonAssistant: recent capture entries:")
    for i = 1, math.min(10, #entries) do
        local e = entries[i]
        print(i .. ") ", e.subevent, e.spellId or "?", e.spellName or "?", e.dest or "-")
    end
end
