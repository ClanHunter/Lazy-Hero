-- OneButtonAssistant Icon Browser
local addonName = "OneButtonAssistant"
OneButtonAssistant = OneButtonAssistant or {}
local OBA = OneButtonAssistant

local icons = {
  -- a small curated set of common WoW icon texture names (extendable)
  "INV_Misc_QuestionMark",
  "INV_Misc_Head_Dragon_01",
  "INV_Sword_27",
  "INV_Axe_1H_Blacksmithing_01",
  "INV_Shield_05",
  "Spell_Nature_Lightning",
  "Spell_Fire_FlameShock",
  "Ability_BackStab",
  "Ability_Hunter_RapidKilling",
  "INV_Elemental_Primal_Fire",
}

function OBA:ToggleIconBrowser()
  if self._iconBrowser and self._iconBrowser:IsShown() then
    self._iconBrowser:Hide()
    return
  end
  if not self._iconBrowser then
    local f = CreateFrame("Frame", "OneButtonAssistantIconBrowser", UIParent, "BackdropTemplate")
    f:SetSize(420, 300)
    f:SetPoint("CENTER")
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "", tile = true, tileSize = 16 })
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetPoint("TOPLEFT", 12, -12)
    f.title:SetText("OneButtonAssistant Icon Browser")
    f.close = CreateFrame("Button", nil, f, "GameMenuButtonTemplate")
    f.close:SetSize(80, 24); f.close:SetPoint("TOPRIGHT", -12, -12); f.close:SetText("Close")
    f.close:SetScript("OnClick", function() f:Hide() end)

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -44)
    scroll:SetPoint("BOTTOMRIGHT", -30, 12)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(360, 1)
    scroll:SetScrollChild(content)

    local cols = 8
    local size = 40
    for i, iconName in ipairs(icons) do
      local btn = CreateFrame("Button", nil, content)
      local col = ((i-1) % cols)
      local row = math.floor((i-1) / cols)
      btn:SetSize(size, size)
      btn:SetPoint("TOPLEFT", 8 + col * (size + 6), -8 - row * (size + 6))
      btn.icon = btn:CreateTexture(nil, "BACKGROUND")
      btn.icon:SetAllPoints()
      btn.icon:SetTexture("Interface\\Icons\\" .. iconName)
      btn:SetScript("OnEnter", function(self)
        btn:SetScript("OnClick", function()
          -- set as current logo/icon for OBA
          OneButtonAssistantDB = OneButtonAssistantDB or {}
          local tex = "Interface\\Icons\\" .. iconName
          OneButtonAssistantDB.logoIcon = tex
          -- try to update button UI immediately via public API
          if OneButtonAssistant and OneButtonAssistant.SetLogoIcon then pcall(OneButtonAssistant.SetLogoIcon, OneButtonAssistant, tex) end
          print("OneButtonAssistant: Selected icon -> " .. iconName)
        end)
        -- set as current logo/icon for OBA
        OneButtonAssistantDB = OneButtonAssistantDB or {}
        OneButtonAssistantDB.logoIcon = "Interface\\Icons\\" .. iconName
        print("OneButtonAssistant: Selected icon -> " .. iconName)
      end)
    end

    self._iconBrowser = f
  end
  self._iconBrowser:Show()
end

-- Expose icons list for reference
OneButtonAssistant.WoWIcons = icons

return OneButtonAssistant
