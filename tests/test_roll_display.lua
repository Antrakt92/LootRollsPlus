local root = arg[1] or "."
local locale = "enUS"
function GetLocale() return locale end

local function loadDisplay()
    local ns = {}
    assert(loadfile(root .. "/RollDisplay.lua"))("LootRollsPlus", ns)
    return ns.RollDisplay
end

local available = { ["lootroll-icon-need"] = true, ["lootroll-icon-greed"] = true }
local atlasQueries, atlasMarkup = {}, {}
C_Texture = {
    GetAtlasInfo = function(atlas)
        atlasQueries[atlas] = (atlasQueries[atlas] or 0) + 1
        return available[atlas] and {} or nil
    end,
}
function CreateAtlasMarkup(atlas, width, height)
    assert(width == 11 and height == 11)
    atlasMarkup[atlas] = (atlasMarkup[atlas] or 0) + 1
    assert(available[atlas], "missing atlases must never reach markup")
    return "<" .. atlas .. ">"
end

local display = loadDisplay()
assert(display.ChoiceText("need", nil) == "|cffff5050Need|r")
assert(display.ChoiceText("need", 96, true) == "<lootroll-icon-need> |cffff5050Need 96|r")
assert(display.ChoiceText("greed", 79, true) == "<lootroll-icon-greed> |cff50ff50Greed 79|r")
assert(display.ChoiceText("pass", nil, true) == "|cff909090Pass|r")
assert(display.ChoiceText("pass", nil, true) == "|cff909090Pass|r")
assert(display.ChoiceText("offspec", nil, true) == "<lootroll-icon-need> |cffffae63Off spec|r")
assert(atlasQueries["lootroll-icon-need"] == 1 and atlasMarkup["lootroll-icon-need"] == 1)
assert(atlasQueries["lootroll-icon-pass"] == 1 and atlasMarkup["lootroll-icon-pass"] == nil)
assert(display.ChoiceText("unknown", 15, true) == nil)
assert(display.WarningDot("atypical") == "|cffffa11f!|r ")
assert(display.WarningDot("incompatible") == "|cffff384d!|r ")

RAID_CLASS_COLORS = { PALADIN = {colorStr = "fff58cba"} }
CLASS_ICON_TCOORDS = { PALADIN = {0.25, 0.5, 0, 0.25} }
local icon = {
    SetTexture = function(self, texture) self.texture = texture end,
    SetTexCoord = function(self, ...) self.coords = {...} end,
    SetShown = function(self, shown) self.shown = shown end,
}
local unknown = { SetShown = icon.SetShown }
display.SetClassIcon(icon, unknown, "Tirion", "PALADIN")
assert(icon.shown and not unknown.shown)
assert(icon.texture:find("UI-CharacterCreate-Classes", 1, true) and icon.coords[2] == 0.5)
assert(display.PlayerText("Tirion", "PALADIN"):find(":64:128:0:64|t |cfff58cbaTirion|r", 1, true))
assert(display.ColoredName("Tirion|r", "PALADIN") == "|cfff58cbaTirion||r|r")
display.SetClassIcon(icon, unknown, "Tirion", nil)
assert(not icon.shown and unknown.shown)
assert(display.ColoredName("Tirion", nil) == "|cffffffffTirion|r")
display.SetClassIcon(icon, unknown, nil, "PALADIN")
assert(not icon.shown and not unknown.shown)

locale = "ruRU"
NEED, GREED = "Нужда", "Алчность"
CreateAtlasMarkup = nil
display = loadDisplay()
assert(display.ChoiceText("need", 88, true) == "|cffff5050Нужда 88|r")
assert(display.ChoiceText("greed", nil, true) == "|cff50ff50Алчность|r")
assert(display.ChoiceText("offspec", nil, true) == "|cffffae63Доп. роль|r")
assert(display.WarningDot("incompatible") == "|cffff384d!|r ")
assert(display.ShortName("Ирина-СеребряныйБор") == "Ирина")
assert(display.PlayerText("Ирина", "PALADIN"):find("|cfff58cbaИрина|r", 1, true))
print("Shared roll display locale, class, and atlas tests passed")
