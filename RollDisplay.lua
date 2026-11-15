local _, ns = ...

local display = {}
ns.RollDisplay = display

local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8X8",
    edgeFile = "Interface\\Buttons\\WHITE8X8",
    edgeSize = 1,
}

function display.Label(english, russian)
    return GetLocale() == "ruRU" and russian or english
end

local label = display.Label
display.Choices = {
    need = { text = NEED or "Need", color = "ffff5050", order = 1, atlas = "lootroll-icon-need" },
    greed = { text = GREED or "Greed", color = "ff50ff50", order = 2, atlas = "lootroll-icon-greed" },
    disenchant = { text = ROLL_DISENCHANT or "Disenchant", color = "ff9d6bff", order = 3 },
    transmog = { text = TRANSMOGRIFY or "Transmog", color = "ff7dbbff", order = 4, atlas = "lootroll-icon-transmog" },
    pass = { text = PASS or "Pass", color = "ff909090", order = 5, atlas = "lootroll-icon-pass" },
    offspec = { text = label("Off spec", "Доп. роль"), color = "ffffae63", atlas = "lootroll-icon-need" },
    waiting = { text = label("Waiting", "Ожидает"), color = "ffadadad" },
}

function display.Escape(text)
    return (text:gsub("|", "||"))
end

function display.Tint(text, color)
    return "|c" .. color .. text .. "|r"
end

function display.ShortName(name)
    return name:match("^[^%s%-]+") or name
end

local function coordinates(class)
    return class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
end

function display.ColoredName(name, class)
    local color = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    return display.Tint(display.Escape(name), color and color.colorStr or "ffffffff")
end

function display.PlayerText(name, class)
    local coords = coordinates(class)
    local colored = display.ColoredName(name, class)
    if not coords then return colored end
    return ("|T%s:13:13:0:0:256:256:%d:%d:%d:%d|t %s"):format(CLASS_TEXTURE,
        coords[1] * 256, coords[2] * 256, coords[3] * 256, coords[4] * 256, colored)
end

function display.SetClassIcon(icon, unknown, name, class)
    local coords = name and coordinates(class)
    if coords then
        icon:SetTexture(CLASS_TEXTURE)
        icon:SetTexCoord(unpack(coords))
    end
    icon:SetShown(coords ~= nil)
    unknown:SetShown(name ~= nil and not coords)
end

local function hasAtlas(atlas)
    return type(CreateAtlasMarkup) == "function"
        and (not C_Texture or not C_Texture.GetAtlasInfo or C_Texture.GetAtlasInfo(atlas))
end

local markers = {}
function display.ChoiceIcon(choice)
    local info = display.Choices[choice]
    local atlas = info and info.atlas
    if not atlas then return "" end
    if markers[atlas] == nil then
        markers[atlas] = hasAtlas(atlas) and CreateAtlasMarkup(atlas, 11, 11) .. " " or ""
    end
    return markers[atlas]
end

function display.ChoiceText(choice, value, withIcon)
    local info = display.Choices[choice]
    if not info then return end
    local icon = withIcon and display.ChoiceIcon(choice) or ""
    return icon .. display.Tint(info.text .. (value and " " .. value or ""), info.color)
end

local warningColors = { atypical = {1, 0.63, 0.12}, incompatible = {1, 0.22, 0.30} }
display.WarningColors = warningColors
local warningMarkers = {}

function display.WarningDot(kind)
    local color = warningColors[kind]
    if not color then return "" end
    if not warningMarkers[kind] then
        local red, green, blue = color[1] * 255, color[2] * 255, color[3] * 255
        local atlas = "common-radiobutton-dot"
        if hasAtlas(atlas) then
            warningMarkers[kind] = CreateAtlasMarkup(atlas, 8, 8, 0, 0, red, green, blue) .. " "
        else
            local fallback = ("ff%02x%02x%02x"):format(math.floor(red + 0.5), math.floor(green + 0.5), math.floor(blue + 0.5))
            warningMarkers[kind] = display.Tint("!", fallback) .. " "
        end
    end
    return warningMarkers[kind]
end

function display.NewPanel(name, parent, width, height, opacity)
    local frame = CreateFrame("Frame", name, parent or UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if width and height then frame:SetSize(width, height) end
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, opacity or 0.7)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    return frame
end
