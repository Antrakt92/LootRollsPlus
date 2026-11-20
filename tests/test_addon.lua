-- Drives the actual TOC in order with a minimal WoW event and widget model.
local root = arg[1] or "."
local frames, timers, tooltip = {}, {}, {}
local timerNow = 0
function GetTime() return timerNow end
local noop = function() end
local widget = {}
local methods = {
    "SetBackdrop", "SetBackdropColor", "SetBackdropBorderColor", "SetPoint", "ClearAllPoints",
    "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetVertexColor", "SetTexture",
    "SetHighlightTexture", "SetMovable", "EnableMouse", "RegisterForDrag", "SetClampedToScreen",
    "StartMoving", "StopMovingOrSizing", "SetFrameStrata", "SetTextColor", "SetAllPoints",
    "SetColorTexture", "SetVerticalScroll", "SetChecked", "SetAlpha", "SetFontObject",
    "SetJustifyV", "SetMaxLines", "SetNormalFontObject", "SetHighlightFontObject",
    "SetResizable", "SetMinResize", "SetNormalTexture", "RegisterForClicks", "SetAutoFocus", "SetHitRectInsets",
    "SetOrientation", "SetValueStep", "SetObeyStepOnDrag", "EnableMouseWheel",
}
for _, name in ipairs(methods) do widget[name] = noop end
function widget:SetUserPlaced(placed) self.userPlaced = placed end
function widget:SetWidth(w) self.width = w end
function widget:EnableMouse(enabled) self.mouseEnabled = enabled end
function widget:SetHeight(h) self.height = h end
function widget:SetSize(w, h) self.width, self.height = w, h end
function widget:GetWidth() return self.width end
function widget:GetHeight() return self.height end
function widget:GetBottom() return self.mockBottom end
function widget:GetTop() return self.mockTop end
function widget:GetCenter() return self.mockCenter end
function widget:GetLeft() return self.mockLeft or (self:GetName() or ""):match("^LootRollsPlusLive") and 500 end
function widget:GetRight() return self.mockRight or (self:GetName() or ""):match("^LootRollsPlusLive") and 777 end
function widget:GetEffectiveScale() return self.mockScale or 1 end
function widget:GetName() return self.name end
function widget:GetParent() return self.parent end
function widget:SetPoint(...) self.lastPoint = {...} end
function widget:GetPoint() return "TOPLEFT", UIParent, "TOPLEFT", 10, -10 end
function widget:StartSizing(direction) self.sizingDirection = direction end
function widget:SetResizeBounds(...) self.resizeBounds = {...} end
function widget:GetStringWidth() return #self.value * 6 end
function widget:GetUnboundedStringWidthForText(text)
    local plain = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|A.-|a", "XX")
    return #plain * (self.mockGlyphWidth or 6)
end
function widget:SetText(value) self.value = value end
function widget:SetOwner(owner) self.tooltipOwner = owner end
function widget:SetHyperlink(link)
    if self.failNextHyperlink or self.failHyperlink then
        self.failNextHyperlink = nil
        self:Hide()
        return false
    end
    self.tooltipLink = link
    return true
end
function widget:ClearLines()
    self.tooltipLink, self.value, self.footer, self.doubleLines, self.plainLines = nil, nil, nil, {}, {}
end
function widget:AddLine(value)
    self.footer = value
    self.plainLines[#self.plainLines + 1] = setmetatable({value = value}, {__index = widget})
end
function widget:NumLines() return self.plainLines and #self.plainLines or 0 end
function widget:GetLeftLine(index) return self.plainLines and self.plainLines[index] end
function widget:AddDoubleLine(label, value) self.doubleLines[#self.doubleLines + 1] = {label, value} end
function widget:ProcessInfo(info)
    assert(info.getterName == "GetHyperlink")
    self.excludedLines = info.excludeLines
    if not self:SetHyperlink(info.getterArgs[1]) then return false end
    info.tooltipPostCall(self)
    self:Show()
    return true
end
function widget:SetTexture(value) self.texture = value end
function widget:SetVertexColor(...) self.vertexColor = {...} end
function widget:AddMaskTexture(mask) self.mask = mask end
function widget:SetTexCoord(...) self.coords = {...} end
function widget:SetColorTexture(...) self.color = {...} end
function widget:SetScript(event, fn) self.scripts[event] = fn end
function widget:GetScript(event) return self.scripts[event] end
function widget:RegisterEvent(event) self.events[event] = true end
function widget:UnregisterEvent(event) self.events[event] = nil end
function widget:SetScrollChild(child) self.scrollChild = child end
function widget:SetVerticalScroll(offset) self.verticalScroll = offset end
function widget:GetVerticalScroll() return self.verticalScroll or 0 end
function widget:IsShown() return self.shown end
function widget:GetText() return self.value end
function widget:GetChecked() return self.checked end
function widget:SetMinMaxValues(minValue, maxValue) self.minValue, self.maxValue = minValue, maxValue end
function widget:SetValue(value)
    self.number = math.min(self.maxValue, math.max(self.minValue, value))
    if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, self.number) end
end
function widget:SetChecked(value) self.checked = value end
function widget:IsVisible()
    return self.shown and (not self.parent or self.parent:IsVisible())
end
function widget:SetShown(shown)
    if shown then self:Show() else self:Hide() end
end
function widget:Show()
    if not self.shown then
        self.shown = true
        if self.scripts.OnShow then self.scripts.OnShow(self) end
    end
end
function widget:Hide()
    if self.shown then
        self.shown = false
        if self.scripts.OnHide then self.scripts.OnHide(self) end
    end
end

local function newWidget(kind, parent)
    local result = setmetatable({kind = kind, parent = parent, shown = true, scripts = {}, events = {}, children = {}}, {__index = widget})
    if parent then parent.children[#parent.children + 1] = result end
    return result
end
function widget:CreateTexture() return newWidget("Texture", self) end
function widget:SetThumbTexture(path)
    self.thumb = self:CreateTexture()
    self.thumb:SetTexture(path)
end
function widget:GetThumbTexture() return self.thumb end
function widget:CreateMaskTexture() return newWidget("MaskTexture", self) end
function widget:CreateFontString()
    local text = newWidget("FontString", self)
    text.font, text.fontSize, text.fontFlags = "Fonts\\FRIZQT__.TTF", 12, ""
    return text
end
function widget:GetFont() return self.font, self.fontSize, self.fontFlags end
function widget:SetFont(path, size, flags)
    self.font, self.fontSize, self.fontFlags = path, size, flags
end
function widget:GetHighlightTexture() return newWidget("Texture", self) end
function CreateFrame(kind, name, parent, template)
    local frame = newWidget(kind, parent)
    frame.name = name
    if template == "UIPanelScrollFrameTemplate" then
        frame.ScrollBar = newWidget("Slider", frame)
    end
    frames[#frames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

local function dispatch(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] then frame.scripts.OnEvent(frame, event, ...) end
    end
end

local function flushTimers()
    for i = #timers, 1, -1 do
        if timers[i].at <= timerNow then table.remove(timers, i).fn() end
    end
end

local function fire(event, ...)
    dispatch(event, ...)
    flushTimers()
end

local function tickLiveSource()
    for _, frame in ipairs(frames) do
        if frame.events.GAME_PAD_ACTIVE_CHANGED and frame:IsVisible() then
            frame:GetScript("OnUpdate")(frame, 0.2)
        end
    end
end

local function contains(value, fragment)
    assert(type(value) == "string" and value:find(fragment, 1, true),
        ("expected %q in %q"):format(fragment, tostring(value)))
end

local function nextVisibleRow(frame)
    for _, child in ipairs(frame.children) do
        if child.entry and child:IsShown() then return child end
    end
    error("no visible loot row")
end

local function visibleText(frame, out)
    out = out or {}
    if frame:IsVisible() then
        if frame.value then out[#out + 1] = frame.value end
        for _, child in ipairs(frame.children) do visibleText(child, out) end
    end
    return table.concat(out, "\n")
end

UIParent = newWidget("Frame")
UIParent:SetSize(1400, 900)
UISpecialFrames, StaticPopupDialogs, SlashCmdList = {}, {}, {}
YES, NO = "Yes", "No"
local popup
function StaticPopup_Show(key)
    assert(StaticPopupDialogs[key], "unknown popup: " .. key)
    popup = key
end
function wipe(tbl) for key in pairs(tbl) do tbl[key] = nil end return tbl end
function GetLocale() return "enUS" end
function UnitName() return "Self" end
function UnitClass() return "Paladin", "PALADIN" end
function UnitSex() return 2 end
function IsInGroup() return true end
function IsInRaid() return false end
function GetNumGroupMembers() return 1 end
local shift, insertedLink
function IsShiftKeyDown() return shift end
function ChatEdit_InsertLink(link) insertedLink = link end
local mouseFoci = {}
function GetMouseFoci() return mouseFoci end
local function mouseDown(button, ...)
    mouseFoci = {...}
    dispatch("GLOBAL_MOUSE_DOWN", button)
    mouseFoci = {}
end
local instanceID = 189
function GetInstanceInfo()
    local name, kind = "Outside", "none"
    if instanceID then name, kind = "Scarlet Monastery", "party" end
    return name, kind, 0, "", 5, 0, false, instanceID, 5
end
date, tinsert = os.date, table.insert
local wallTime, historyTime = os.time({year = 2026, month = 11, day = 14, hour = 12}), 200
function time(value) return value and os.time(value) or wallTime end
C_Timer = {After = function(delay, fn) timers[#timers + 1] = {at = timerNow + delay, fn = fn} end}
RAID_CLASS_COLORS = {PALADIN = {colorStr = "fff58cba"}, MAGE = {colorStr = "ff69ccf0"}}
LOCALIZED_CLASS_NAMES_MALE = {PALADIN = "Paladin", MAGE = "Mage"}
CLASS_ICON_TCOORDS = {PALADIN = {0, 0.25, 0, 0.25}, MAGE = {0.25, 0.5, 0, 0.25}}
local tooltipOwner, tooltipOnHide
function CreateAtlasMarkup(atlas, width, height, _, _, red, green, blue)
    if red then return ("|A:%s:%d:%d:0:0:%d:%d:%d|a"):format(atlas, height, width, red, green, blue) end
    return ("|A:%s:%d:%d:0:0|a"):format(atlas, height, width)
end
GameTooltip = {
    SetOwner = function(_, owner) tooltip, tooltipOwner = {}, owner end,
    IsOwned = function(_, owner) return tooltipOwner == owner end,
    IsShown = function() return tooltipOwner ~= nil end,
    SetHyperlink = function(_, link) tooltip[#tooltip + 1] = link end,
    AddLine = function(_, line) tooltip[#tooltip + 1] = line end,
    AddDoubleLine = function(_, left, right) tooltip[#tooltip + 1] = left .. " " .. right end,
    Show = noop,
    HookScript = function(_, event, hook)
        assert(event == "OnHide")
        tooltipOnHide = hook
    end,
    Hide = function()
        tooltipOwner = nil
        if tooltipOnHide then tooltipOnHide() end
    end,
}
local cloth = "|cnIQ2:|Hitem:123::::::::|h[Cloth Robe]|h|r"
local shield = "|cnIQ2:|Hitem:130::::::::|h[Shield]|h|r"
C_Item = {
    GetItemIconByID = function() return 84 end,
    GetItemInfoInstant = function(link)
        if link == shield then return 130, "Armor", "Shield", "INVTYPE_SHIELD", 84, 4, 6 end
        return 123, "Armor", "Cloth", "INVTYPE_CHEST", 84, 4, 1
    end,
}
Enum = {
    EncounterLootDropRollState = {NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5},
    ItemClass = {Weapon = 2, Armor = 4},
    ItemArmorSubclass = {Cloth = 1, Leather = 2, Mail = 3, Plate = 4, Shield = 6},
    ItemWeaponSubclass = {},
}
local drops = {}
local lootApiReads = 0
local function read(value)
    lootApiReads = lootApiReads + 1
    return value
end
C_LootHistory = {
    GetLootHistoryTime = function() return read(historyTime) end,
    GetAllEncounterInfos = function() return read({{encounterID = 20}}) end,
    GetInfoForEncounter = function() return read({encounterName = "Arcanist Doan"}) end,
    GetSortedInfoForDrop = function(_, key) return read(drops[key]) end,
    GetSortedDropsForEncounter = function() return read(drops) end,
}
function GetLootRollItemLink() return cloth end
LOOT_ROLL_NEED_SELF = "You have selected Need for: %s"
LOOT_ROLL_ROLLED_NEED = "Need Roll - %d for %s by %s"
LOOT_ROLL_YOU_WON = "You won: %s"

local dayKey = date("%Y-%m-%d", wallTime)
LootRollsInspectorDB = {days = {[dayKey] = {{link = cloth, t = wallTime - 20, winner = "AccountWide"}}}}
LootRollsInspectorCharDB = {days = {[dayKey] = {{
    link = cloth, t = wallTime - 10, winner = "LegacyPerson", done = true,
    rolls = {{name = "LegacyPerson", type = "greed", value = "99"}},
}}}}

local latestNS
local settingsCategory
Settings = {
    RegisterCanvasLayoutCategory = function(panel, name) return {panel = panel, name = name} end,
    RegisterAddOnCategory = function(category)
        assert(not settingsCategory, "Settings category registered twice")
        settingsCategory = category
    end,
}
SettingsPanel = newWidget("Frame", UIParent)
SettingsPanel:Hide()
function HideUIPanel(panel) panel:Hide() end

do
    local metadata = {}
    for line in io.lines(root .. "/LootRollsPlus.toc") do
        local key, value = line:match("^## (Category):%s*(.-)%s*$")
        if not key then key, value = line:match("^## (Group):%s*(.-)%s*$") end
        if key then
            assert(metadata[key] == nil, "duplicate TOC " .. key)
            metadata[key] = value
        end
    end
    assert(metadata.Category == "Antrakt92", "the AddOns list must show Loot Rolls Plus under Antrakt92")
    assert(metadata.Group == "LootRollsPlus", "Loot Rolls Plus must have its own AddOns list entry")
end

local function loadAddon(isReload)
    frames, timers = {}, {}
    settingsCategory = nil
    local namespace, count = {}, 0
    latestNS = namespace
    for line in io.lines(root .. "/LootRollsPlus.toc") do
        local file = line:match("^%s*([^#].-%.lua)%s*$")
        if file then
            assert(loadfile(root .. "/" .. file))("LootRollsPlus", namespace)
            count = count + 1
        end
    end
    assert(count >= 4 and LootRollsPlusFrame)
    local before = lootApiReads
    fire("ADDON_LOADED", "LootRollsPlus")
    fire("ZONE_CHANGED_NEW_AREA")
    fire("LOOT_HISTORY_UPDATE_DROP", 20, 1)
    assert(lootApiReads == before, "history APIs were read before PLAYER_ENTERING_WORLD")
    fire("PLAYER_ENTERING_WORLD", not isReload, isReload)
    assert(lootApiReads > before, "loot history was not initialized after entering the world")
end
loadAddon(false)

local legacy = nextVisibleRow(LootRollsPlusFrame)
contains(legacy.right.value, "Greed 99")
contains(legacy.player.value, "LegacyPerson")
do
    local main, options = LootRollsPlusFrame, LootRollsPlusOptions
    local grip = LootRollsPlusResizeGrip
    local originalHeight = main:GetHeight()
    local tab
    for _, child in ipairs(main.children) do
        if child.text and child.text:GetText() == "Options" then tab = child end
    end
    assert(options:GetParent() == main and tab and not options:IsShown())
    tab:GetScript("OnClick")(tab)
    assert(options:IsVisible() and options.events.GLOBAL_MOUSE_DOWN)
    assert(not legacy:IsVisible() and grip:IsVisible() and main:GetHeight() == originalHeight)
    mouseDown("LeftButton", LootRollsPlusShowLiveRolls)
    fire("PLAYER_ENTERING_WORLD", false, false)
    assert(options:IsVisible() and not legacy:IsVisible(), "a refresh exposed the list under Options")
    mouseDown("LeftButton", tab)
    assert(options:IsShown(), "Options must stay open until its button handles the click")
    tab:GetScript("OnClick")(tab)
    assert(not options:IsShown() and legacy:IsVisible())
    tab:GetScript("OnClick")(tab)
    mouseDown("RightButton", UIParent)
    assert(not options:IsShown() and not options.events.GLOBAL_MOUSE_DOWN)
    assert(legacy:IsVisible() and grip:IsVisible() and main:GetHeight() == originalHeight)
    tab:GetScript("OnClick")(tab)
    SlashCmdList.LOOTROLLSPLUS("")
    assert(not options:IsShown() and not main:IsShown())
    SlashCmdList.LOOTROLLSPLUS("config")
    assert(options:IsVisible(), "options must still be accessible when the list is hidden")
    mouseDown("LeftButton", UIParent)
    assert(not options:IsShown() and not main:IsShown(), "closing options must respect the saved visibility")
    SlashCmdList.LOOTROLLSPLUS("")
    assert(main:IsVisible() and legacy:IsVisible())

    local groupState, originalPrint = IsInGroup, print
    IsInGroup = function() return false end
    local recoveryHint
    print = function(message) recoveryHint = message end
    tab:GetScript("OnClick")(tab)
    local solo = LootRollsPlusHideSolo
    solo:SetChecked(true)
    solo:GetScript("OnClick")(solo)
    assert(options:IsVisible() and LootRollsPlusDB.hideSolo)
    contains(recoveryHint, "/lrplus show")
    fire("GROUP_ROSTER_UPDATE")
    assert(options:IsVisible(), "a roster event must not close Options while editing Hide Solo")
    mouseDown("LeftButton", UIParent)
    assert(not main:IsVisible() and not options:IsShown())
    assert(settingsCategory and settingsCategory.name == "Loot Rolls Plus")
    local page = settingsCategory.panel
    assert(page:GetParent() ~= main)
    local toc = assert(io.open(root .. "/LootRollsPlus.toc"))
    local iconPath = assert(toc:read("*a"):match("## IconTexture: ([^\r\n]+)"))
    toc:close()
    local settingsIcon
    for _, child in ipairs(page.children) do
        if child.kind == "Texture" then settingsIcon = child end
    end
    assert(settingsIcon and settingsIcon.texture == iconPath)
    SettingsPanel:Show()
    page:Hide()
    page:Show()
    local settingsSolo, restore
    for _, child in ipairs(page.children) do
        if child.kind == "CheckButton" then settingsSolo = child end
        if child.kind == "Button" then restore = child end
    end
    assert(settingsSolo:GetChecked(), "Blizzard Settings must reflect the hidden state")
    settingsSolo:SetChecked(false)
    settingsSolo:GetScript("OnClick")(settingsSolo)
    assert(main:IsVisible() and not LootRollsPlusDB.hideSolo)
    settingsSolo:SetChecked(true)
    settingsSolo:GetScript("OnClick")(settingsSolo)
    assert(not main:IsVisible())
    LootRollsPlusDB.hidden = true
    restore:GetScript("OnClick")(restore)
    assert(main:IsVisible() and not SettingsPanel:IsShown() and not settingsSolo:GetChecked())
    assert(not LootRollsPlusDB.hidden and not LootRollsPlusDB.hideSolo)
    LootRollsPlusDB.hidden, LootRollsPlusDB.hideSolo = true, true
    SlashCmdList.LOOTROLLSPLUS("show")
    assert(main:IsVisible() and not LootRollsPlusDB.hidden and not LootRollsPlusDB.hideSolo)
    IsInGroup, print = groupState, originalPrint
end
assert(legacy.classUnknown:IsShown() and not legacy.classIcon:IsShown())
SlashCmdList.LOOTROLLSPLUS("history")
local importedHistoryRow = nextVisibleRow(LootRollsPlusHistoryScroll.scrollChild)
assert(importedHistoryRow.entry == legacy.entry and importedHistoryRow.lastPoint[3] == 0,
    "an imported roll should start at the top of History without a heading")
SlashCmdList.LOOTROLLSPLUS("history")
legacy.entry.winnerType, legacy.entry.rolls[1].type = "need", "need"
fire("PLAYER_ENTERING_WORLD", false, false)
assert(not legacy.alert:IsShown(), "unverified imported rolls must not show equipment warnings")
DungeonQuestAtlasCharDB = {runLog = {{
    started = wallTime - 20, last = wallTime,
    loot = {{who = "LegacyPerson", link = cloth}}, party = {LegacyPerson = "PALADIN"},
}}}
fire("ADDON_LOADED", "DungeonQuestAtlas")
assert(legacy.classIcon:IsShown() and not legacy.classUnknown:IsShown())
assert(#LootRollsPlusCharDB.days[dayKey] == 1)
assert(legacy.alert:IsShown() and legacy.alert.vertexColor[2] > 0.5,
    "a verified imported cloth Need by a paladin must show an amber dot")

local fullPaladinName = "PalaOne Longrealm"
local paladin = {playerName = fullPaladinName, playerClass = "PALADIN", state = 0}
wallTime, historyTime = wallTime + 1, historyTime + 1
fire("START_LOOT_ROLL", 100, 30000)
fire("CHAT_MSG_LOOT", "You have selected Need for: " .. cloth)
local provisional = nextVisibleRow(LootRollsPlusFrame)
contains(provisional.player.value, "Self")
assert(#LootRollsPlusCharDB.days[dayKey] == 2)
drops[1] = {lootListKey = 1, itemHyperlink = cloth, startTime = historyTime, rollInfos = {paladin}}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 1)
assert(#LootRollsPlusCharDB.days[dayKey] == 2, "native capture duplicated provisional chat row")
local first = nextVisibleRow(LootRollsPlusFrame)
contains(first.right.value, "Need")
contains(first.player.value, "PalaOne")
contains(first.player.value, "fff58cba")
assert(not first.player.value:find("Longrealm", 1, true))
assert(first.classIcon:IsShown() and not first.classUnknown:IsShown())
contains(first.classIcon.texture, "UI-CharacterCreate-Classes")
assert(first.classIcon.coords[2] == CLASS_ICON_TCOORDS.PALADIN[2])
assert(not first.right.value:find("·", 1, true))
assert(not first.right.value:find("!", 1, true))
assert(LootRollsPlusFrame:GetWidth() <= 320 and first.right:GetWidth() <= 130)
assert(first.alert:IsVisible() and first.alert.mask.texture:find("TempPortraitAlphaMask", 1, true))
assert(first.alert.vertexColor[2] > 0.5)
first:GetScript("OnEnter")(first)
contains(table.concat(tooltip, "\n"), "fff58cba")
assert(not table.concat(tooltip, "\n"):find("Paladin", 1, true))
assert(not table.concat(tooltip, "\n"):find("Class unknown", 1, true))
contains(table.concat(tooltip, "\n"), fullPaladinName)
contains(table.concat(tooltip, "\n"), "common-radiobutton-dot:8:8:0:0:255:160:30")
assert(not table.concat(tooltip, "\n"):find("Lighter armor", 1, true))
assert(tooltip[1] == cloth)
assert(not table.concat(tooltip, "\n"):find("%d%d/%d%d/%d%d%d%d %d%d:%d%d"))
contains(table.concat(tooltip, "\n"), "Scarlet Monastery")
contains(table.concat(tooltip, "\n"), "Arcanist Doan")
local unrelatedTooltip = newWidget("Frame")
GameTooltip:SetOwner(unrelatedTooltip)
GameTooltip:AddLine("Unrelated tooltip")
fire("PLAYER_ENTERING_WORLD", false, false)
assert(tooltipOwner == unrelatedTooltip)
assert(tooltip[1] == "Unrelated tooltip")
first:GetScript("OnLeave")(first)
assert(tooltipOwner == unrelatedTooltip)
shift = true
first:GetScript("OnClick")(first)
assert(insertedLink == cloth)
shift = false

-- Same item, different keys. A late winner after leaving retains the first visit.
wallTime, historyTime = wallTime + 1, historyTime + 1
drops[2] = {lootListKey = 2, itemHyperlink = cloth, startTime = historyTime, rollInfos = {}}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 2)
assert(#LootRollsPlusCharDB.days[dayKey] == 3)
local active = LootRollsPlusCharDB.days[dayKey][2]
local visit = assert(active.visit)
drops[1].itemHyperlink = cloth:gsub("^|cnIQ2:", "|cff00ff00")
loadAddon(true)
assert(#LootRollsPlusCharDB.days[dayKey] == 3, "reload duplicated saved rows")
assert(LootRollsPlusCharDB.currentVisit == visit)
assert(not active.done and not active.closed and not active.stale)
instanceID = nil
fire("ZONE_CHANGED_NEW_AREA")
paladin.roll, paladin.isWinner = 85, true
drops[1].winner = paladin
fire("LOOT_HISTORY_UPDATE_DROP", 20, 1)
assert(active.winnerType == "need" and active.winnerValue == 85 and active.visit == visit)
local resultRow
for _, child in ipairs(LootRollsPlusFrame.children) do
    if child:IsShown() and child.entry == active then resultRow = child end
end
contains(assert(resultRow).right.value, "Need 85")

SlashCmdList.LOOTROLLSPLUS("history")
local content = LootRollsPlusHistoryScroll.scrollChild
local headings = {}
for _, child in ipairs(content.children) do
    if child.kind == "FontString" and child:IsShown() then headings[#headings + 1] = child.value end
end
contains(table.concat(headings, "\n"), "Scarlet Monastery")
assert(not table.concat(headings, "\n"):find("Imported history", 1, true))
assert(LootRollsPlusHistory:GetParent() == LootRollsPlusFrame and not resultRow:IsVisible())
mouseDown("LeftButton", LootRollsPlusHistoryScroll)
assert(LootRollsPlusHistory:IsVisible())
mouseDown("LeftButton", UIParent)
assert(not LootRollsPlusHistory:IsShown() and resultRow:IsVisible())

StaticPopupDialogs.LOOTROLLSPLUS_CLEAR.OnAccept()
fire("LOOT_HISTORY_UPDATE_DROP", 20, 1)
assert(next(LootRollsPlusCharDB.days) == nil)

-- Chat-only drops track their own winners when structured loot history omits them.
function GetLootRollItemLink()
    return "|cff00ff00|Hitem:124::::::::|h[Another Robe]|h|r"
end
local another = GetLootRollItemLink()
fire("START_LOOT_ROLL", 101, 30000)
fire("CHAT_MSG_LOOT", "You have selected Need for: " .. another)
fire("CHAT_MSG_LOOT", ("Need Roll - 97 for %s by Self"):format(another))
fire("CHAT_MSG_LOOT", "You won: " .. another)
contains(nextVisibleRow(LootRollsPlusFrame).right.value, "Need 97")
assert(#LootRollsPlusCharDB.days[dayKey] == 1)

-- A saved open record absent from the game's history cannot still be live.
local missing = "|cff00ff00|Hitem:125::::::::|h[Missing Robe]|h|r"
function GetLootRollItemLink() return missing end
wallTime, historyTime = wallTime + 3, historyTime + 3
fire("START_LOOT_ROLL", 102, 30000)
fire("CHAT_MSG_LOOT", "You have selected Need for: " .. missing)
assert(#LootRollsPlusCharDB.days[dayKey] == 2)
loadAddon(true)
local unavailable = nextVisibleRow(LootRollsPlusFrame)
assert(unavailable.entry.link == missing and unavailable.entry.stale)
contains(unavailable.right.value, "Result unavailable")

-- Ten timely results must not push an older active roll off the main list.
wallTime, historyTime = wallTime + 3, historyTime + 3
local pendingPaladin = {playerName = fullPaladinName, playerClass = "PALADIN", state = 0}
local ongoing = {lootListKey = 3, itemHyperlink = cloth, startTime = historyTime, rollInfos = {pendingPaladin}}
drops[3] = ongoing
fire("LOOT_HISTORY_UPDATE_DROP", 20, 3)
for i = 4, 13 do
    wallTime, historyTime = wallTime + 1, historyTime + 1
    drops[i] = {lootListKey = i, itemHyperlink = cloth, startTime = historyTime, rollInfos = {}, allPassed = true}
    dispatch("LOOT_HISTORY_UPDATE_DROP", 20, i)
end
flushTimers()
loadAddon(true)
local shown = nextVisibleRow(LootRollsPlusFrame)
assert(shown.entry.lootListKey == 3)
contains(shown.right.value, "Need")
shown:GetScript("OnClick")(shown)
local detail = assert(LootRollsPlusDetails)
assert(detail:IsVisible(), "selecting a roll opens the details")
assert(LootRollsPlusDroppedTooltip:IsVisible() and LootRollsPlusDroppedTooltip.tooltipLink == cloth,
    "the first click should open the full dropped-item tooltip")
assert(LootRollsPlusDroppedTooltip.lastPoint[2] == LootRollsPlusFrame)
ongoing.winner = paladin
fire("LOOT_HISTORY_UPDATE_DROP", 20, 3)
assert(nextVisibleRow(LootRollsPlusFrame).entry.lootListKey == 13)
assert(detail:IsVisible(), "details stay on the selected roll after the rows reorder")
assert(LootRollsPlusDroppedTooltip.tooltipLink == cloth)
StaticPopupDialogs.LOOTROLLSPLUS_CLEAR.OnAccept()
assert(not detail:IsVisible(), "clearing history closes the pinned detail")

-- Confirmed class restrictions use a red badge; unrelated Greed has no badge.
wallTime, historyTime = wallTime + 3, historyTime + 3
local mage = {playerName = "MageOne Longrealm", playerClass = "MAGE", state = 0}
drops[14] = {lootListKey = 14, itemHyperlink = shield, startTime = historyTime, rollInfos = {mage}}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 14)
local restricted = nextVisibleRow(LootRollsPlusFrame)
contains(restricted.right.value, "Need")
assert(restricted.alert:IsVisible() and restricted.alert.mask.texture == first.alert.mask.texture)
assert(restricted.alert.vertexColor[2] < 0.3)
restricted:GetScript("OnEnter")(restricted)
contains(table.concat(tooltip, "\n"), "common-radiobutton-dot:8:8:0:0:255:56:76")
assert(not table.concat(tooltip, "\n"):find("cannot equip", 1, true))
restricted:GetScript("OnLeave")(restricted)
mage.state, mage.roll = 3, 90
drops[14].winner = mage
fire("LOOT_HISTORY_UPDATE_DROP", 20, 14)
contains(restricted.right.value, "Greed 90")
assert(not restricted.alert:IsVisible())

-- A confirmed druid gets a separate texture slot, even when the winning name is long.
CLASS_ICON_TCOORDS.DRUID = {0.50, 0.75, 0, 0.25}
wallTime, historyTime = wallTime + 3, historyTime + 3
local druid = {playerName = "Трупосвет Полноеимя", playerClass = "DRUID", state = 3, roll = 88}
drops[15] = {lootListKey = 15, itemHyperlink = cloth, startTime = historyTime, rollInfos = {druid}, winner = druid}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 15)
local druidRow = nextVisibleRow(LootRollsPlusFrame)
contains(druidRow.right.value, "Greed 88")
contains(druidRow.player.value, "Трупосвет")
assert(not druidRow.player.value:find("Полноеимя", 1, true))
assert(druidRow.classIcon:IsShown() and druidRow.classIcon.coords[1] == CLASS_ICON_TCOORDS.DRUID[1])
assert(not druidRow.classUnknown:IsShown())

local frame = LootRollsPlusFrame
local grip = LootRollsPlusResizeGrip
local width = frame:GetWidth()
assert(frame.resizeBounds[1] == width and frame.resizeBounds[3] == width)
grip:GetScript("OnMouseDown")(grip, "LeftButton")
assert(frame.sizingDirection == "BOTTOM")
frame:SetHeight(frame.resizeBounds[4])
frame:GetScript("OnSizeChanged")(frame, width, frame:GetHeight())
grip:GetScript("OnMouseUp")(grip, "LeftButton")
assert(LootRollsPlusDB.windowHeight == frame.resizeBounds[4] and frame:GetHeight() == frame.resizeBounds[4])
loadAddon(true)
frame, grip = LootRollsPlusFrame, LootRollsPlusResizeGrip
assert(frame:GetHeight() == frame.resizeBounds[4] and frame:GetWidth() == width)
grip:GetScript("OnMouseUp")(grip, "RightButton")
assert(not LootRollsPlusDB.windowHeight and frame:GetHeight() < frame.resizeBounds[4])

local equipped = "|cff00ff00|Hitem:4321::::::::|h[Equipped robe]|h|r"
function UnitGUID(unit) if unit == "player" then return "Player-Test" end end
function GetInventorySlotInfo(slot) if slot == "ChestSlot" then return 5 end end
function GetInventoryItemLink(unit, slot)
    assert(unit == "player" and slot == 5)
    return equipped
end
wallTime, historyTime = wallTime + 3, historyTime + 3
local selfRoll = {playerName = "Self", playerClass = "PALADIN", state = 0, roll = 98}
local otherRoll = {playerName = "Other", playerClass = "MAGE", state = 3, roll = 40}
local absentRoll = {playerName = "Absent", playerClass = "MAGE", state = 3, roll = 30}
drops[16] = {lootListKey = 16, itemHyperlink = cloth, startTime = historyTime,
    rollInfos = {selfRoll, otherRoll, absentRoll}, winner = selfRoll}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 16)
local comparisonRow = nextVisibleRow(frame)
UIParent:SetSize(1000, 800)
frame.mockLeft, frame.mockBottom, frame.mockTop = 14, 10, 190
local leftCard, rightCard = LootRollsPlusDroppedTooltip, LootRollsPlusEquippedTooltip
leftCard:SetSize(300, 200)
rightCard:SetSize(280, 180)
C_CurrencyInfo = {GetCoinTextureString = function(copper) return tostring(copper) .. "c" end}
Enum.TooltipDataLineType = { SellPrice = 91 }
local vendorPrice = 1976
C_Item.GetItemInfo = function(link)
    if link == cloth then return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, vendorPrice end
end
local auctionPrice = 7500
Auctionator = {API = {v1 = {GetAuctionPriceByItemLink = function(caller, link)
    assert(caller == "LootRollsPlus" and link == cloth)
    return auctionPrice
end}}}
local mastercraftEnabled = true
local mastercraftLoadingOnly
C_AddOns = {IsAddOnLoaded = function(name)
    local present = name == "Mastercraft" and mastercraftEnabled
    return present, present and not mastercraftLoadingOnly
end}
local mastercraftLabel, mastercraftValue = "Disenchant", "~14s 97c"
local displayedMastercraftItem
local stockSetHyperlink = GameTooltip.SetHyperlink
function GameTooltip:SetHyperlink(link)
    stockSetHyperlink(self, link)
    self.displayedLink = displayedMastercraftItem or link
    local rows = {
        {"Disenchant", "~99g"},
        {"|cff4da6ffMastercraft|r"},
        {"Auction", "~75s"},
        {mastercraftLabel, mastercraftValue},
    }
    for i, row in ipairs(rows) do
        _G["GameTooltipTextLeft" .. i] = {
            GetText = function() return row[1] end,
            GetTextColor = function() return 0.60, 0.63, 0.70 end,
        }
        _G["GameTooltipTextRight" .. i] = {GetText = function() return row[2] end}
    end
end
function GameTooltip:GetItem() return nil, self.displayedLink end
function GameTooltip:NumLines() return 4 end
local loadedItem
Item = {CreateFromItemLink = function(_, link)
    assert(link == cloth)
    return {ContinueOnItemLoad = function(_, onLoad) loadedItem = onLoad end}
end}
displayedMastercraftItem = "|cff1eff00|Hitem:99999::::::::|h[Previous item]|h|r"
leftCard.failNextHyperlink = true
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(leftCard:IsVisible() and not leftCard.tooltipLink)
contains(leftCard.value, "Loading item")
assert(rightCard.tooltipLink == equipped, "cold drop data should not delay the equipped item")
displayedMastercraftItem = nil
local foreignOwner = {}
GameTooltip:SetOwner(foreignOwner, "ANCHOR_RIGHT")
assert(loadedItem, "a cold tooltip must schedule an item-data retry")()
flushTimers()
assert(GameTooltip:IsOwned(foreignOwner), "a delayed price read must not replace another tooltip")
assert(#leftCard.doubleLines == 2, "the comparison should redraw without interrupting the other tooltip")
GameTooltip:Hide()
flushTimers()
Item = nil
assert(leftCard:IsVisible() and leftCard.tooltipLink == cloth)
assert(rightCard:IsVisible() and rightCard.tooltipLink == equipped)
assert(#leftCard.doubleLines == 3 and leftCard.doubleLines[1][1] == "Vendor"
    and leftCard.doubleLines[1][2] == "1976c")
assert(#leftCard.excludedLines == 1 and leftCard.excludedLines[1] == Enum.TooltipDataLineType.SellPrice)
assert(not rightCard.excludedLines)
assert(leftCard.doubleLines[2][1] == "Auction" and leftCard.doubleLines[2][2] == "7500c")
assert(leftCard.doubleLines[3][1] == "Disenchant" and leftCard.doubleLines[3][2] == "~14s 97c")
assert(#rightCard.doubleLines == 0)
contains(rightCard.footer, "Equipped now")
assert(leftCard.lastPoint[1] == "BOTTOMRIGHT" and rightCard.lastPoint[1] == "BOTTOMLEFT")
assert(leftCard.lastPoint[2] == frame and rightCard.lastPoint[2] == frame)
assert(rightCard.lastPoint[4] - leftCard.lastPoint[4] == 8 and leftCard.lastPoint[5] == rightCard.lastPoint[5])
assert(leftCard.lastPoint[4] >= 286, "the pair should stay on screen near the left edge")
UIParent:SetSize(700, 800)
frame.mockLeft = 470
fire("DISPLAY_SIZE_CHANGED")
assert(frame.mockLeft + rightCard.lastPoint[4] + rightCard:GetWidth() <= 700,
    "an open main comparison must reflow when the viewport shrinks")
UIParent:SetSize(550, 800)
frame.mockLeft = 230
fire("DISPLAY_SIZE_CHANGED")
assert(leftCard.lastPoint[1] == "BOTTOMLEFT" and leftCard.lastPoint[2] == UIParent
    and leftCard.lastPoint[3] == "BOTTOMLEFT", "the comparison must stack when the pair cannot fit side by side")
assert(rightCard.lastPoint[1] == "BOTTOMLEFT" and rightCard.lastPoint[2] == UIParent
    and rightCard.lastPoint[3] == "BOTTOMLEFT" and leftCard.lastPoint[4] == rightCard.lastPoint[4])
assert(rightCard.lastPoint[5] > frame.mockTop
    and leftCard.lastPoint[5] >= rightCard.lastPoint[5] + rightCard:GetHeight()
    and leftCard.lastPoint[5] + leftCard:GetHeight() <= UIParent:GetHeight())
assert(leftCard.lastPoint[4] >= 0 and leftCard.lastPoint[4] + leftCard:GetWidth() <= UIParent:GetWidth())
UIParent:SetSize(1000, 800)
frame.mockLeft = 14
fire("DISPLAY_SIZE_CHANGED")
assert(leftCard.lastPoint[1] == "BOTTOMRIGHT" and rightCard.lastPoint[1] == "BOTTOMLEFT"
    and leftCard.lastPoint[2] == frame and rightCard.lastPoint[2] == frame,
    "return to side-by-side when space is restored")
assert(#LootRollsPlusDetails.children == 2, "the comparison should only have two tooltip frames")
assert(comparisonRow.entry.inspections.Self.links[1] == equipped, "opening the roll should inspect its winner")
comparisonRow:GetScript("OnClick")(comparisonRow)
timerNow = timerNow + 16
flushTimers()
mastercraftValue = "|cff5c6373no price|r"
loadedItem = nil
Item = {CreateFromItemLink = function()
    return {ContinueOnItemLoad = function(_, callback) loadedItem = callback end}
end}
leftCard.failNextHyperlink = true
comparisonRow:GetScript("OnClick")(comparisonRow)
leftCard.failHyperlink = true
timerNow = timerNow + 16
flushTimers()
flushTimers()
contains(leftCard.value, "Item data unavailable")
leftCard.failHyperlink = nil
mastercraftValue = "~14s 97c"
assert(loadedItem, "custom card must request cold data even when the stock tooltip has the right item")()
flushTimers()
assert(leftCard.doubleLines[3] and leftCard.doubleLines[3][2] == "~14s 97c",
    "the cold card must re-read Mastercraft even when the stock tooltip recognized the item")
comparisonRow:GetScript("OnClick")(comparisonRow)
timerNow = timerNow + 16
flushTimers()
Item = {CreateFromItemLink = function()
    return {ContinueOnItemLoad = function() error("item no longer exists") end}
end}
leftCard.failNextHyperlink = true
comparisonRow:GetScript("OnClick")(comparisonRow)
contains(leftCard.value, "Item data unavailable")
assert(rightCard.tooltipLink == equipped, "an unavailable drop should still show its saved comparison")
comparisonRow:GetScript("OnClick")(comparisonRow)
local itemMetadata = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function() return nil end
local coldSlotReady
Item = {CreateFromItemLink = function()
    return {ContinueOnItemLoad = function(_, callback) coldSlotReady = callback end}
end}
comparisonRow.entry.inspections.Self = nil
comparisonRow:GetScript("OnClick")(comparisonRow)
contains(rightCard.value, "Loading item")
C_Item.GetItemInfoInstant = itemMetadata
-- The earlier cold tooltip can own the same bounded item request.
local finishColdSlot = assert(coldSlotReady or loadedItem)
finishColdSlot()
flushTimers()
assert(rightCard.tooltipLink == equipped, "loaded slot metadata must resume the selected inspection")
Item = nil
mastercraftLoadingOnly = true
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(#leftCard.doubleLines == 2, "a loading-only price provider must not be used")
mastercraftLoadingOnly = nil
mastercraftLabel = "Распыление (не хватает некоторых цен)"
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(leftCard.doubleLines[3][1] == "Disenchant (partial)")
displayedMastercraftItem = cloth:gsub("item:123:", "item:123:1")
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(#leftCard.doubleLines == 2, "the same item ID with a different link must not reuse another tooltip's estimate")
displayedMastercraftItem = nil
mastercraftValue = "|cff5c6373no price|r"
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(#leftCard.doubleLines == 2, "a missing estimate must not reserve a line")
mastercraftEnabled = false
SlashCmdList.LOOTROLLSPLUS("config")
local positionChoices = {}
for _, child in ipairs(LootRollsPlusOptions.children) do
    if child.position then positionChoices[child.position] = child end
end
assert(positionChoices.auto:GetChecked())
positionChoices.below:GetScript("OnClick")(positionChoices.below)
assert(positionChoices.below:GetChecked() and not positionChoices.auto:GetChecked())
assert(LootRollsPlusDB.playerListPosition == "below" and leftCard.lastPoint[1] == "TOPRIGHT")
positionChoices.above:GetScript("OnClick")(positionChoices.above)
assert(LootRollsPlusDB.playerListPosition == "above" and leftCard.lastPoint[1] == "BOTTOMRIGHT")
positionChoices.auto:GetScript("OnClick")(positionChoices.auto)
assert(LootRollsPlusDB.playerListPosition == "auto" and leftCard.lastPoint[1] == "BOTTOMRIGHT")
SlashCmdList.LOOTROLLSPLUS("config")
local savedEquipment = comparisonRow.entry.inspections.Self
comparisonRow.entry.inspections.Self = {
    class = "PALADIN", count = 1, links = {}, empty = {[1] = true},
}
fire("PLAYER_ENTERING_WORLD", false, false)
assert(leftCard.tooltipLink == cloth and not rightCard.tooltipLink)
contains(rightCard.value, "Equipment slot is empty")
local cachedOffHand = "|cff00ff00|Hitem:4322::::::::|h[Equipped offhand]|h|r"
comparisonRow.entry.inspections.Self = {class = "PALADIN", count = 2, links = {[2] = cachedOffHand}}
fire("PLAYER_ENTERING_WORLD", false, false)
assert(leftCard.tooltipLink == cloth and rightCard.tooltipLink == cachedOffHand)
assert(not rightCard.value, "an available item must replace the unavailable message")
comparisonRow.entry.inspections.Self = {class = "PALADIN", count = 2, links = {equipped, cachedOffHand}}
fire("PLAYER_ENTERING_WORLD", false, false)
assert(rightCard.tooltipLink == equipped)
contains(rightCard.footer, "1/2")
mouseDown("LeftButton", rightCard)
rightCard:GetScript("OnMouseUp")(rightCard, "LeftButton")
assert(leftCard.tooltipLink == cloth and rightCard.tooltipLink == cachedOffHand)
contains(rightCard.footer, "2/2")
fire("PLAYER_ENTERING_WORLD", false, false)
assert(rightCard.tooltipLink == cachedOffHand, "refreshing the same comparison must retain the selected slot")
comparisonRow.entry.inspections.Self = {class = "PALADIN", count = 2, links = {[2] = cachedOffHand}, empty = {true}}
fire("PLAYER_ENTERING_WORLD", false, false)
assert(rightCard.tooltipLink == cachedOffHand, "a populated second slot should be the default over an empty first slot")
rightCard:GetScript("OnMouseUp")(rightCard, "LeftButton")
contains(rightCard.value, "Equipment slot is empty")
contains(rightCard.value, "1/2")
comparisonRow.entry.inspections.Self = savedEquipment
fire("PLAYER_ENTERING_WORLD", false, false)
assert(rightCard.tooltipLink == equipped)
mouseDown("LeftButton", UIParent, rightCard)
assert(leftCard:IsShown() and rightCard:IsShown())
mouseDown("RightButton")
assert(not LootRollsPlusDetails:IsShown(), "clicking the world should dismiss the comparison")
assert(not leftCard:IsShown() and not rightCard:IsShown())
comparisonRow:GetScript("OnClick")(comparisonRow)
auctionPrice = 0
mouseDown("LeftButton", comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(not LootRollsPlusDetails:IsShown(), "clicking the same roll should still toggle it closed")
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(leftCard.tooltipLink == cloth and #leftCard.doubleLines == 1 and leftCard.doubleLines[1][1] == "Vendor")
Auctionator.API.v1.GetAuctionPriceByItemLink = function() error("Auctionator not ready") end
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(leftCard.tooltipLink == cloth and #leftCard.doubleLines == 1 and leftCard.doubleLines[1][1] == "Vendor")
Auctionator = nil
vendorPrice = 0
comparisonRow:GetScript("OnClick")(comparisonRow)
comparisonRow:GetScript("OnClick")(comparisonRow)
assert(#leftCard.doubleLines == 0, "an unsellable item should not show a vendor line")
assert(not leftCard.excludedLines, "keep the native sell price when Vendor cannot replace it")

-- A late result can change the displayed player while retaining the old voter.
comparisonRow.entry.winner, comparisonRow.entry.winnerClass = "Other", "MAGE"
fire("PLAYER_ENTERING_WORLD", false, false)
assert(not leftCard:IsShown() and not rightCard:IsShown(), "do not keep the old player's gear after the displayed winner changes")
comparisonRow.entry.winner, comparisonRow.entry.winnerClass = "Self", "PALADIN"
fire("PLAYER_ENTERING_WORLD", false, false)
comparisonRow:GetScript("OnClick")(comparisonRow)

-- Roster updates cannot leave an equipment card attached to an ambiguous identity.
comparisonRow.entry.rolls[#comparisonRow.entry.rolls + 1] = { name = "Self", class = "PALADIN", type = "greed" }
fire("PLAYER_ENTERING_WORLD", false, false)
assert(leftCard.tooltipLink == cloth and not rightCard.tooltipLink)
contains(rightCard.value, "Several participants have this name")
frame:Hide()
assert(not LootRollsPlusDetails:IsShown() and not LootRollsPlusDroppedTooltip:IsShown())
frame:Show()

wallTime, historyTime = wallTime + 3, historyTime + 3
local winnerOnlyClass = {playerName = "MageOne Longrealm", playerClass = "MAGE", state = 0, roll = 93}
drops[17] = {lootListKey = 17, itemHyperlink = shield, startTime = historyTime,
    rollInfos = {{playerName = winnerOnlyClass.playerName, state = 3}}, winner = winnerOnlyClass}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 17)
local winnerRow = nextVisibleRow(frame)
assert(winnerRow.alert:IsVisible(), "the winner's confirmed Need and class should drive the equipment warning")
contains(winnerRow.right.value, "Need 93")
for _, row in ipairs(frame.children) do
    if row:IsShown() and row.entry and row.entry.lootListKey == 16 then
        row:GetScript("OnClick")(row)
        break
    end
end
assert(LootRollsPlusDetails:IsShown())
mouseDown("LeftButton", winnerRow)
winnerRow:GetScript("OnClick")(winnerRow)
assert(leftCard.tooltipLink == shield, "clicking another roll should switch the dropped item")
assert(not rightCard.tooltipLink, "equipment from the previous winner must not carry over")
contains(rightCard.value, "Player is unavailable in your group")
local oldInspection = time() - 3600
winnerRow.entry.inspections = {[winnerRow.entry.winner] = {at = oldInspection, class = "MAGE", count = 1, links = {equipped}}}
fire("PLAYER_ENTERING_WORLD", false, false)
assert(leftCard.tooltipLink == shield and rightCard.tooltipLink == equipped)
contains(rightCard.footer, "Last inspected gear")
contains(rightCard.footer, date("%H:%M", oldInspection))

local jewel = "|cnIQ2:|Hitem:1529::::::::|h[Jade]|h|r"
local getInfo = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(link)
    if link == jewel then return 1529, "Trade Goods", "Jewelcrafting", "", 84, 7, 4 end
    return getInfo(link)
end
wallTime, historyTime = wallTime + 1, historyTime + 1
drops[18] = {lootListKey = 18, itemHyperlink = jewel, startTime = historyTime,
    rollInfos = {winnerOnlyClass}, winner = winnerOnlyClass}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 18)
SlashCmdList.LOOTROLLSPLUS("history")
local jewelRow = nextVisibleRow(LootRollsPlusHistoryScroll.scrollChild)
assert(jewelRow.entry.link == jewel)
jewelRow:GetScript("OnClick")(jewelRow)
assert(leftCard.tooltipLink == jewel and leftCard.lastPoint[2] == LootRollsPlusHistory)
contains(rightCard.value, "No equipment slot for this drop")
leftCard:AddLine(" ")
leftCard:AddLine("Reward from Find Agmond")
assert(leftCard:NumLines() == 1 and leftCard:GetLeftLine(1):GetText() == "")
leftCard:AddLine(" ")
leftCard:AddLine("|TInterface\\Icons\\INV_Misc_QuestionMark:14:14|t Reward from Find Agmond")
leftCard:AddLine("     Badlands")
leftCard:AddLine("Other tooltip information")
assert(leftCard:NumLines() == 3 and leftCard:GetLeftLine(3):GetText() == "Other tooltip information")
GameTooltip:AddLine("Reward from Find Agmond")
assert(tooltip[#tooltip] == "Reward from Find Agmond", "ordinary tooltips should keep quest reward information")
mouseDown("LeftButton", LootRollsPlusHistory)
assert(not LootRollsPlusDetails:IsShown() and LootRollsPlusHistory:IsShown(),
    "clicking outside a History comparison should close only the comparison")
jewelRow:GetScript("OnClick")(jewelRow)
mouseDown("LeftButton", leftCard)
assert(LootRollsPlusDetails:IsShown() and LootRollsPlusHistory:IsShown())
mouseDown("LeftButton", UIParent)
assert(not LootRollsPlusHistory:IsShown() and not LootRollsPlusDetails:IsShown())

wallTime, historyTime = wallTime + 1, historyTime + 1
local nativeSelf = {playerName = "Self", playerClass = "PALADIN", playerGUID = "Player-Test", state = 0, roll = 97}
drops[19] = {lootListKey = 19, itemHyperlink = cloth, startTime = historyTime, rollInfos = {nativeSelf}, winner = nativeSelf}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 19)
local nativeRow = nextVisibleRow(frame)
nativeRow:GetScript("OnClick")(nativeRow)
assert(rightCard.tooltipLink == equipped)
nativeSelf.playerGUID = "Player-Replacement"
fire("LOOT_HISTORY_UPDATE_DROP", 20, 19)
assert(leftCard.tooltipLink == cloth and not rightCard.tooltipLink,
    "replacing a native GUID must invalidate the equipment despite the same name and class")
nativeRow:GetScript("OnClick")(nativeRow)
nativeRow:GetScript("OnClick")(nativeRow)
assert(not rightCard.tooltipLink, "reopening must not inspect a same-name replacement of the native winner")
contains(rightCard.value, "Player is unavailable in your group")

-- A synchronously loaded Item object can still lack instant gear metadata.
local partial = "|cnIQ2:|Hitem:199::::::::|h[Partially cached robe]|h|r"
local beforePartialInfo = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(link)
    if link == partial then return 199 end
    return beforePartialInfo(link)
end
local partialRequests = 0
Item = {CreateFromItemLink = function(_, link)
    assert(link == partial)
    return {ContinueOnItemLoad = function(_, callback)
        partialRequests = partialRequests + 1
        callback()
    end}
end}
wallTime, historyTime = wallTime + 1, historyTime + 1
drops[20] = {lootListKey = 20, itemHyperlink = partial, startTime = historyTime,
    rollInfos = {nativeSelf}, winner = nativeSelf}
fire("LOOT_HISTORY_UPDATE_DROP", 20, 20)
for _ = 1, 5 do flushTimers() end
assert(partialRequests == 1, "partial metadata must not loop through synchronous item loads and redraws")
Item = nil
C_Item.GetItemInfoInstant = beforePartialInfo

local function historyEntry(timestamp, visit)
    return {link = cloth, t = timestamp, rolls = {}, done = true, allpassed = true, visit = visit}
end

local shortTimestamp, longTimestamp = wallTime, wallTime - 86400
local shortDate, longDate = date("%Y-%m-%d", shortTimestamp), date("%Y-%m-%d", longTimestamp)
local shortEntries = {historyEntry(shortTimestamp)}
local longEntries = {}
for i = 1, 28 do
    longEntries[i] = historyEntry(longTimestamp + i, {id = i, name = "Library", startedAt = longTimestamp})
end

local function openHistory()
    SlashCmdList.LOOTROLLSPLUS("history")
    assert(LootRollsPlusHistory:IsShown())
    return LootRollsPlusHistory, LootRollsPlusDayScroll, LootRollsPlusHistoryScroll
end

-- Reopen a saved day containing advisory and incompatible Need rolls, plus a
-- Greed winner and an unknown class. The new and imported rows use the same
-- independent result, dot, class and name widgets in both windows.
local function savedResult(link, offset, name, class, choice, imported)
    return {link = link, t = wallTime + offset, done = true, legacy = imported, winner = name,
        winnerClass = class, winnerType = choice, winnerValue = 99,
        rolls = {{name = name, class = class, type = choice, value = 99, isWinner = not imported}}}
end
local amber = savedResult(cloth, -4, "OldPaladin Surname", "PALADIN", "need", true)
local red = savedResult(shield, -3, "OldMage Surname", "MAGE", "need", true)
local greed = savedResult(shield, -2, "AnotherMage Surname", "MAGE", "greed", true)
local unknown = savedResult(shield, -1, "Unverified Surname", nil, "need", true)
LootRollsPlusCharDB.days = {[dayKey] = {amber, red, greed, unknown}}
DungeonQuestAtlasCharDB = {runLog = {{
    started = wallTime - 4, last = wallTime,
    loot = {{link = cloth, who = amber.winner}, {link = shield, who = red.winner},
        {link = shield, who = greed.winner}},
    party = {OldPaladin = "PALADIN", OldMage = "MAGE", AnotherMage = "MAGE"},
}}}
loadAddon(true)
local _, _, historyResults = openHistory()
local function checkResultColumns(parent)
    local rows = {}
    for _, row in ipairs(parent.children) do
        if row:IsShown() and row.entry then rows[row.entry] = row end
    end
    for _, entry in ipairs({amber, red, greed, unknown}) do
        local row = assert(rows[entry])
        contains(row.right.value, entry.winnerType == "greed" and "Greed 99" or "Need 99")
        assert(not row.right.value:find("·", 1, true) and not row.right.value:find("|T", 1, true))
        assert(row.right.lastPoint[2] == row.classIcon and row.classIcon.lastPoint[2] == row.player)
        assert(row.player:IsShown() and row.player.lastPoint[2] == -2 and row.player:GetWidth() == 60)
        assert(not row.player.value:find("Surname", 1, true))
        local expectedClass = entry.winnerClass
        assert(row.classIcon:IsShown() == (expectedClass ~= nil))
        assert(row.classUnknown:IsShown() == (expectedClass == nil))
        if expectedClass then
            assert(row.classIcon.coords[1] == CLASS_ICON_TCOORDS[expectedClass][1])
        end
    end
    assert(rows[amber].alert:IsShown() and rows[amber].alert.vertexColor[2] > 0.5)
    assert(rows[red].alert:IsShown() and rows[red].alert.vertexColor[2] < 0.3)
    assert(rows[red].alert:GetWidth() == 8 and rows[red].alert:GetHeight() == 8)
    for _, entry in ipairs({amber, red}) do
        local row = rows[entry]
        local point = row.alert.lastPoint
        local resultWidth = row.right:GetUnboundedStringWidthForText(row.right.value)
        assert(point[2] == row.right and point[3] == "RIGHT" and point[4] == -resultWidth - 5,
            "warning dots should sit next to the visible roll text")
        assert(row.left.lastPoint[2] == row.alert and row.left.lastPoint[4] == -3,
            "item text must stop before the warning dot")
    end
    assert(not rows[greed].alert:IsShown() and not rows[unknown].alert:IsShown())
end
checkResultColumns(historyResults.scrollChild)
SlashCmdList.LOOTROLLSPLUS("history")
checkResultColumns(LootRollsPlusFrame)
DungeonQuestAtlasCharDB = nil
loadAddon(true)
local _, _, restoredResults = openHistory()
checkResultColumns(restoredResults.scrollChild)
SlashCmdList.LOOTROLLSPLUS("history")
checkResultColumns(LootRollsPlusFrame)
LootRollsPlusCharDB.days = {[shortDate] = shortEntries, [longDate] = longEntries}
LootRollsPlusDB.windowHeight = nil
loadAddon(true)

local function selectDate(scroll, dateKey)
    for _, child in ipairs(scroll.scrollChild.children) do
        if child:IsShown() and child.key == dateKey then
            child:GetScript("OnClick")(child)
            return
        end
    end
    error("missing date selection: " .. dateKey)
end

local main = LootRollsPlusFrame
main.mockRight, main.mockTop = 580, 500
local mainListHeight = main:GetHeight()
local history, dateScroll, itemScroll = openHistory()
local shortHeight, shortWidth = history:GetHeight(), itemScroll:GetWidth()
local historyRow = nextVisibleRow(itemScroll.scrollChild)
assert(history:GetWidth() < 465 and main:GetWidth() == history:GetWidth())
assert(main.lastPoint[1] == "TOPRIGHT" and main.lastPoint[2] == UIParent
    and main.lastPoint[3] == "BOTTOMLEFT" and main.lastPoint[4] == 580 and main.lastPoint[5] == 500)
assert(main:GetHeight() == shortHeight and shortHeight == mainListHeight)
assert(dateScroll:GetWidth() < 108 and itemScroll.lastPoint[2] == 8 + dateScroll:GetWidth() + 4)
SlashCmdList.LOOTROLLSPLUS("history")
assert(main:GetWidth() == 305 and LootRollsPlusResizeGrip:IsVisible())
assert(main:GetHeight() == mainListHeight and main.lastPoint[4] == 580 and main.lastPoint[5] == 500)
openHistory()
assert(main:GetWidth() == history:GetWidth() and itemScroll:GetWidth() == shortWidth,
    "opening history should restore its fixed compact width")
for _, child in ipairs(history.children) do
    assert(child.value ~= "Clear", "the history header still contains a Clear button")
end
assert(not dateScroll.ScrollBar:IsShown() and not itemScroll.ScrollBar:IsShown())
assert(historyRow:GetWidth() == shortWidth)
selectDate(dateScroll, longDate)
local longHeight = history:GetHeight()
assert(longHeight == shortHeight)
assert(not dateScroll.ScrollBar:IsShown() and itemScroll.ScrollBar:IsShown())
assert(itemScroll:GetWidth() < shortWidth and historyRow:GetWidth() == itemScroll:GetWidth())
itemScroll:SetVerticalScroll(40)
fire("PLAYER_ENTERING_WORLD", false, false)
assert(itemScroll:GetVerticalScroll() == 40, "ordinary history redraw resets the selected day scroll")
selectDate(dateScroll, shortDate)
assert(history:GetHeight() == shortHeight and itemScroll:GetWidth() == shortWidth)
assert(not itemScroll.ScrollBar:IsShown() and itemScroll:GetVerticalScroll() == 0)
assert(historyRow:GetWidth() == shortWidth, "reused history row did not regain the scrollbar gutter")

do
    local entries = LootRollsPlusCharDB.days[shortDate]
    local own = historyEntry(shortTimestamp)
    own.allpassed, own.winner = nil, "Self"
    local other = historyEntry(shortTimestamp)
    other.allpassed, other.winner = nil, "Self-Other"
    local ambiguous = historyEntry(shortTimestamp)
    ambiguous.allpassed, ambiguous.winner = nil, "Self"
    ambiguous.rolls = {{name = "Self-Other", type = "need", value = 42}}
    local wrongClass = historyEntry(shortTimestamp)
    wrongClass.allpassed, wrongClass.winner, wrongClass.winnerClass = nil, "Self", "MAGE"
    for _, entry in ipairs({own, other, ambiguous, wrongClass}) do entries[#entries + 1] = entry end
    local filter = LootRollsPlusMyWins
    filter:GetScript("OnClick")(filter)
    local rows = {}
    for _, child in ipairs(itemScroll.scrollChild.children) do
        if child.entry and child:IsShown() then rows[#rows + 1] = child.entry end
    end
    assert(#rows == 1 and rows[1] == own, "My wins must display only the confirmed match")
    selectDate(dateScroll, longDate)
    for _, child in ipairs(itemScroll.scrollChild.children) do
        assert(not child.entry or not child:IsShown(), "My wins remains active when changing dates")
    end
    filter:GetScript("OnClick")(filter)
    assert(nextVisibleRow(itemScroll.scrollChild), "turning off My wins restores the selected day's rolls")
    selectDate(dateScroll, shortDate)
    for _ = 1, 4 do table.remove(entries) end
end

for i = 2, 24 do
    local timestamp = shortTimestamp - i * 86400
    LootRollsPlusCharDB.days[date("%Y-%m-%d", timestamp)] = {historyEntry(timestamp)}
end
loadAddon(true)
history, dateScroll, itemScroll = openHistory()
assert(dateScroll.ScrollBar:IsShown() and not itemScroll.ScrollBar:IsShown())
assert(itemScroll.lastPoint[2] == 8 + dateScroll:GetWidth() + 23 + 4,
    "reserve the date scrollbar gutter only when it is visible")
assert(history:GetHeight() == longHeight)

local historyGrip = LootRollsPlusHistoryResizeGrip
local historyWidth = history:GetWidth()
main = LootRollsPlusFrame
historyGrip:GetScript("OnMouseDown")(historyGrip, "LeftButton")
assert(main.sizingDirection == "BOTTOM")
assert(main.resizeBounds[1] == historyWidth and main.resizeBounds[3] == historyWidth)
main:SetHeight(175)
main:GetScript("OnSizeChanged")(main, historyWidth, 175)
historyGrip:GetScript("OnMouseUp")(historyGrip, "LeftButton")
assert(LootRollsPlusDB.windowHeight == 175)
loadAddon(true)
history, dateScroll, itemScroll = openHistory()
assert(history:GetWidth() == historyWidth and history:GetHeight() == 175)
selectDate(dateScroll, longDate)
assert(history:GetHeight() == 175 and dateScroll.ScrollBar:IsShown() and itemScroll.ScrollBar:IsShown())
assert(itemScroll:GetWidth() == historyWidth - dateScroll:GetWidth() - 22 - 46 and itemScroll:GetWidth() >= 256,
    "keep room for item names and roll results with both scrollbars visible")
historyGrip = LootRollsPlusHistoryResizeGrip
historyGrip:GetScript("OnMouseUp")(historyGrip, "RightButton")
assert(not LootRollsPlusDB.windowHeight and history:GetHeight() == longHeight)

SlashCmdList.LOOTROLLSPLUS("config")
local clearHistory = assert(LootRollsPlusClearHistory)
assert(clearHistory.parent == LootRollsPlusOptions and clearHistory:IsVisible())
assert(not history:IsShown() and LootRollsPlusFrame:GetWidth() == 305)
assert(LootRollsPlusFrame:GetHeight() == longHeight, "switching from History to Options changed the height")
clearHistory:GetScript("OnClick")(clearHistory)
assert(popup == "LOOTROLLSPLUS_CLEAR")
assert(next(LootRollsPlusCharDB.days), "opening the confirmation cleared history")
local clearDialog = StaticPopupDialogs[popup]
if clearDialog.OnCancel then clearDialog.OnCancel() end
assert(next(LootRollsPlusCharDB.days), "cancelling confirmation cleared history")
clearHistory:GetScript("OnClick")(clearHistory)
clearDialog.OnAccept()
assert(not next(LootRollsPlusCharDB.days))
history, dateScroll, itemScroll = openHistory()
assert(not LootRollsPlusOptions:IsShown() and not dateScroll:IsShown() and itemScroll.lastPoint[2] == 8)
assert(not dateScroll.ScrollBar:IsShown() and not itemScroll.ScrollBar:IsShown())
assert(history:GetHeight() == LootRollsPlusFrame:GetHeight())
contains(visibleText(history), "No rolls recorded")

LootRollsPlusDB.historyHeight = math.huge
LootRollsPlusDB.maxDays = "invalid"
LootRollsPlusDB.pos = {"wrong point", "CENTER", math.huge, 0}
shortEntries[#shortEntries + 1] = {link = "bad link", rolls = {}}
LootRollsPlusCharDB.days = {[shortDate] = shortEntries, [17] = "invalid"}
loadAddon(true)
local recoveredHeight = LootRollsPlusFrame:GetHeight()
history = openHistory()
assert(not LootRollsPlusDB.historyHeight and not LootRollsPlusDB.windowHeight and history:GetHeight() == recoveredHeight)
assert(LootRollsPlusDB.maxDays == 365 and LootRollsPlusCharDB.days[shortDate] == shortEntries)
assert(nextVisibleRow(LootRollsPlusHistoryScroll.scrollChild).entry == shortEntries[1])
assert(shortEntries[#shortEntries].link ~= "bad link")
assert(LootRollsPlusDB.pos == nil, "invalid position data must not reach SetPoint")
local printDays = print
print = noop
SlashCmdList.LOOTROLLSPLUS("days 1x")
print = printDays
assert(LootRollsPlusDB.maxDays == 365, "malformed days input must not change retention")
fire("PLAYER_LOGOUT")
assert(LootRollsPlusDB.pos[1] == "TOPLEFT" and LootRollsPlusDB.pos[3] == 10)
loadAddon(true)
assert(LootRollsPlusFrame.userPlaced and LootRollsPlusFrame.lastPoint[1] == "TOPLEFT")
history = openHistory()
LootRollsPlusDB.windowHeight = 400
UIParent:SetSize(1000, 281)
fire("DISPLAY_SIZE_CHANGED")
assert(history:GetHeight() == 265 and LootRollsPlusDB.windowHeight == 400)
UIParent:SetSize(1400, 900)
fire("UI_SCALE_CHANGED")
assert(history:GetHeight() == 400, "resizing the screen must preserve the original history height preference")
LootRollsPlusDB.windowHeight = nil
fire("UI_SCALE_CHANGED")
SlashCmdList.LOOTROLLSPLUS("history")

local savedDays = LootRollsPlusCharDB.days
local oldCounts = {}
for day, entries in pairs(savedDays) do oldCounts[day] = #entries end
UIParent:SetSize(1400, 900)
SlashCmdList.LOOTROLLSPLUS("  DEMO RAID  ")
local firstLive, secondLive, thirdLive = LootRollsPlusLiveRoll1, LootRollsPlusLiveRoll2, LootRollsPlusLiveRoll3
assert(firstLive:IsVisible() and secondLive:IsVisible() and thirdLive:IsVisible())
assert(LootRollsPlusLiveDemo1:IsVisible() and LootRollsPlusLiveDemo2.title.value == LootRollsPlusLiveDemo3.title.value)
contains(firstLive.summary.value, "2|r")
contains(firstLive.summary.value, "lootroll-icon-need")
contains(firstLive.summary.value, "lootroll-icon-greed")
contains(firstLive.summary.value, "lootroll-icon-pass")
assert(firstLive:GetHeight() < 50 and firstLive.lastPoint[1] == "RIGHT" and firstLive.lastPoint[3] == "LEFT",
    "live summaries should use the left even when both sides have room")
firstLive.toggle:GetScript("OnClick")()
local liveDetails = LootRollsPlusLiveDetails
assert(liveDetails:IsVisible() and liveDetails.slider:IsVisible() and liveDetails.slider.maxValue == 32)
assert(#liveDetails.rows == 8 and liveDetails.offset == 0)
liveDetails:GetScript("OnMouseWheel")(liveDetails, -1)
assert(liveDetails.offset == 3)
for _ = 1, 17 do
    timerNow = timerNow + 1
    flushTimers()
end
assert(liveDetails.offset == 3, "a roll update must keep the open list at its scroll position")
contains(firstLive.summary.value, "9|r")
contains(firstLive.toggleText.value, "+7")
assert(firstLive.leaders[1].result.value == "|cffff505096|r")
assert(firstLive.leaders[1].name.value == "|cfff58cbaTirion|r")
local clientFace = "Fonts\\FRIZQT__.TTF"
assert(firstLive.leaders[1].name.font == clientFace)
assert(firstLive.summary.font == clientFace)
assert(nextVisibleRow(LootRollsPlusFrame).player.font == clientFace)
assert(firstLive.leaders[1].classIcon:IsVisible() and not firstLive.leaders[1].classUnknown:IsVisible())
assert(firstLive.leaders[1].classIcon.coords[2] == CLASS_ICON_TCOORDS.PALADIN[2])
secondLive.toggle:GetScript("OnClick")()
assert(liveDetails:IsVisible() and liveDetails.offset == 0)
contains(liveDetails.title.value, "Spellsever Crossbow")
mouseDown("LeftButton", liveDetails.slider)
assert(liveDetails:IsVisible(), "scrollbar click must keep live roll details open")
mouseDown("LeftButton", UIParent)
assert(not liveDetails:IsVisible())

UIParent:SetSize(650, 720)
local demoCards = { firstLive, secondLive, thirdLive }
local demoPrompts = { LootRollsPlusLiveDemo1, LootRollsPlusLiveDemo2, LootRollsPlusLiveDemo3 }
for i, card in ipairs(demoCards) do
    local prompt = demoPrompts[i]
    prompt.mockLeft, prompt.mockRight = 186, 463
    card.mockLeft, card.mockRight = 5, 181
    card.mockBottom = 20 + i * 100
    card.mockTop = card.mockBottom + 42
end
fire("DISPLAY_SIZE_CHANGED")
firstLive.toggle:GetScript("OnClick")()
assert(liveDetails.lastPoint[1] == "BOTTOMRIGHT" and liveDetails.lastPoint[2] == thirdLive,
    "the detail view should fit above the other summaries in a narrow stack")
for i, card in ipairs(demoCards) do
    local prompt = demoPrompts[i]
    prompt.mockLeft, prompt.mockRight = nil, nil
    card.mockLeft, card.mockRight, card.mockBottom, card.mockTop = nil, nil, nil, nil
end
UIParent:SetSize(1400, 900)
local demoInstant = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(link)
    if link:find("item:274293:", 1, true) then
        return 274293, "Weapon", "Crossbow", "INVTYPE_RANGEDRIGHT", 84, 2, 18
    end
    return demoInstant(link)
end
SlashCmdList.LOOTROLLSPLUS("demo party")
assert(firstLive:IsVisible() and #firstLive.rows == 5 and firstLive.rows[5]:IsVisible())
assert(not firstLive.toggle:IsVisible() and not liveDetails:IsVisible())
assert(firstLive:GetHeight() < 100, "adjacent party sidecars must fit Blizzard's 100-unit spacing")
assert(firstLive.rows[5].highlight:IsVisible(), "your choice should be easy to find in the party")
assert(firstLive:GetWidth() <= 182, "party rows should not reserve raid-width space")
local demoDropTooltip, demoGearTooltip = LootRollsPlusDroppedTooltip, LootRollsPlusEquippedTooltip
local demoCrossbow = LootRollsPlusLiveRoll2
local bowOwner, shaman
for _, row in ipairs(demoCrossbow.rows) do
    if row.livePlayer and row.livePlayer.class == "ROGUE" then bowOwner = row end
    if row.livePlayer and row.livePlayer.class == "SHAMAN" and row.livePlayer.choice == "need" then
        shaman = row
    end
end
assert(bowOwner and shaman)
contains(shaman.result.value, "common-radiobutton-dot")
bowOwner:GetScript("OnClick")(bowOwner)
assert(not demoDropTooltip:IsVisible(), "live click should not pin the drop")
contains(demoGearTooltip.tooltipLink, "Ranger Bow")
assert(demoGearTooltip.lastPoint[1] == "TOPLEFT" and demoGearTooltip.lastPoint[2] == demoCrossbow
    and demoGearTooltip.lastPoint[3] == "TOPRIGHT")
local demoItem = LootRollsPlusLiveDemo2.item
demoItem:GetScript("OnEnter")(demoItem)
contains(GameTooltip.displayedLink, "Spellsever Crossbow")
contains(demoGearTooltip.tooltipLink, "Ranger Bow")
demoItem:GetScript("OnLeave")(demoItem)
shaman:GetScript("OnClick")(shaman)
contains(demoGearTooltip.tooltipLink, "Totem of Rage")
mouseDown("LeftButton", UIParent)
assert(not demoDropTooltip:IsVisible() and not demoGearTooltip:IsVisible())
local jadeVoter = firstLive.rows[1]
assert(not jadeVoter.mouseEnabled)
jadeVoter:GetScript("OnClick")(jadeVoter)
assert(not demoDropTooltip:IsVisible() and not demoGearTooltip:IsVisible())
C_Item.GetItemInfoInstant = demoInstant
assert(LootRollsPlusCharDB.days == savedDays)
for day, entries in pairs(savedDays) do assert(oldCounts[day] == #entries, "demo polluted saved history") end
fire("START_LOOT_ROLL", 4500, 30000)
assert(not firstLive:IsVisible() and not LootRollsPlusLiveDemo1:IsVisible(), "real rolls supersede mock prompts")
timerNow = timerNow + 1
flushTimers()
assert(not firstLive:IsVisible(), "an old demo tick reopened a dismissed preview")

if not LootRollsPlusOptions:IsShown() then SlashCmdList.LOOTROLLSPLUS("config") end
local liveCheck = LootRollsPlusShowLiveRolls
assert(liveCheck:IsVisible() and liveCheck:GetChecked())
liveCheck:SetChecked(false)
liveCheck:GetScript("OnClick")(liveCheck)
assert(LootRollsPlusDB.liveRolls == false)
loadAddon(true)
SlashCmdList.LOOTROLLSPLUS("config")
assert(not LootRollsPlusShowLiveRolls:GetChecked(), "live-roll preference was lost on reload")
SlashCmdList.LOOTROLLSPLUS("demo raid")
assert(LootRollsPlusLiveDemo1:IsVisible(), "preview should be available with live sidecars disabled")
SlashCmdList.LOOTROLLSPLUS("demo off")
assert(not LootRollsPlusLiveDemo1:IsVisible() and not LootRollsPlusLiveRoll1:IsVisible())

local rollID, lootKey = 12951, 777
local nativeLootFrame = newWidget("Frame", UIParent)
nativeLootFrame.rollID, nativeLootFrame.rollTime = rollID, 30000
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 1040, 1317
GroupLootContainer = {rollFrames = {nativeLootFrame}, waitingRolls = {}}
function GetActiveLootRollIDs() return {rollID} end
function GetLootRollItemLink(id) return id == rollID and cloth or nil end
function GetLootRollTimeLeft() return 30000 end
C_Loot = {GetLootRollDuration = function() return 30000 end}
C_LootHistory.GetSortedDropsForEncounter = function(encounter)
    return read(encounter == 20 and {drops[lootKey]} or {})
end
drops[lootKey] = {lootListKey = lootKey, itemHyperlink = cloth, startTime = historyTime, duration = 30, rollInfos = {
    {playerName = "Other Mage", playerClass = "MAGE", state = 0},
    {playerName = "Self", playerClass = "PALADIN", state = 4, isSelf = true},
}}
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(not LootRollsPlusLiveRoll1:IsVisible(), "the option must suppress the real sidecar")
local printOriginal = print
local previewMessage
print = function(message) previewMessage = message end
SlashCmdList.LOOTROLLSPLUS("demo raid")
print = printOriginal
contains(previewMessage, "active loot rolls")
assert(not LootRollsPlusLiveDemo1:IsVisible(), "a preview cannot cover a real popup with the option off")
LootRollsPlusShowLiveRolls:SetChecked(true)
LootRollsPlusShowLiveRolls:GetScript("OnClick")(LootRollsPlusShowLiveRolls)
tickLiveSource()
local live = LootRollsPlusLiveRoll1
assert(live:IsVisible() and live.lastPoint[1] == "RIGHT" and live.lastPoint[2] == nativeLootFrame,
    "the sidecar should attach to the native popup and use the left when necessary")
contains(live.rows[1].name.value, "Other")
contains(live.rows[1].classIcon.texture, "UI-CharacterCreate-Classes")
assert(live.rows[1].classIcon:IsVisible() and not live.rows[1].classUnknown:IsVisible())
contains(live.rows[1].result.value, "Need")
contains(live.rows[1].result.value, "lootroll-icon-need")
contains(live.rows[1].result.value, "ffff5050")
assert(not live.rows[1].result.value:find("%s%d"), "unknown numbers must stay absent")
assert(live.rows[2].highlight:IsVisible(), "your pending choice is displayed")
assert(nativeLootFrame.lastPoint == nil and next(nativeLootFrame.scripts) == nil,
    "the view must leave the Blizzard popup's handlers and placement alone")

nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 350, 627
tickLiveSource()
assert(live:IsVisible() and live.lastPoint[1] == "RIGHT" and live.lastPoint[3] == "LEFT",
    "party choices should leave the right of the loot popup open when both sides fit")
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 40, 317
tickLiveSource()
assert(live:IsVisible() and live.lastPoint[1] == "LEFT", "use the right side only when the left is too narrow")
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = nil, nil
tickLiveSource()
assert(not live:IsVisible(), "native popup bounds can briefly be unavailable")
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 40, 317
tickLiveSource()
assert(live:IsVisible(), "bounds recovery must render before the next roll event")

drops[lootKey].rollInfos[1].playerClass = nil
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(not live.rows[1].classIcon:IsVisible() and live.rows[1].classUnknown:IsVisible())
contains(live.rows[1].name.value, "ffffffff")
drops[lootKey].rollInfos[1].playerClass = "MAGE"
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(live.rows[1].classIcon:IsVisible() and not live.rows[1].classUnknown:IsVisible())

local liveDrop, liveGear = LootRollsPlusDroppedTooltip, LootRollsPlusEquippedTooltip
local memberItem = "|cff1eff00|Hitem:9123::::::::|h[Party robe]|h|r"
local priorInstant = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function(link)
    if link == cloth then return 123, "Armor", "Cloth", "INVTYPE_CHEST", 84, 4, 1 end
    return priorInstant(link)
end
function IsInRaid() return false end
function GetNumGroupMembers() return 2 end
function UnitGUID(unit) return unit == "player" and "Player-Test" or unit == "party1" and "Player-Mage" or nil end
function UnitClass(unit)
    if unit == "player" then return "Paladin", "PALADIN" end
    if unit == "party1" then return "Mage", "MAGE" end
end
NameUtil = {GetUnmodifiedUnitFullName = function(unit) return unit == "player" and "Self" or "Other Mage" end}
function GetInventoryItemLink(unit, slot)
    if slot == 5 then return unit == "player" and equipped or memberItem end
end
function CanInspect() return true end
function InCombatLockdown() return false end
local inspectedUnit
function NotifyInspect(unit) inspectedUnit = unit end
local liveVotes = drops[lootKey].rollInfos
liveVotes[1].playerGUID, liveVotes[2].playerGUID = "Player-Mage", "Player-Test"
liveVotes[2].state = 0
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(not live.rows[1].result.value:find("common%-radiobutton%-dot"), "a mage may Need cloth")
contains(live.rows[2].result.value, "common-radiobutton-dot")
live.rows[1]:GetScript("OnClick")(live.rows[1])
assert(inspectedUnit == "party1" and not liveDrop:IsVisible())
contains(liveGear.value, "Inspecting")
mouseDown("LeftButton", live.rows[2])
live.rows[2]:GetScript("OnClick")(live.rows[2])
assert(not liveDrop:IsVisible() and liveGear.tooltipLink == equipped)
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 1040, 1317
tickLiveSource()
flushTimers()
assert(liveGear.lastPoint[2] == nativeLootFrame and liveGear.lastPoint[3] == "TOPRIGHT",
    "left-side roll lists should place the equipment after the native loot prompt")
nativeLootFrame.mockBottom = 300
liveGear:SetSize(200, 150)
tickLiveSource()
flushTimers()
assert(liveGear.lastPoint[1] == "TOPRIGHT" and liveGear.lastPoint[2] == UIParent
    and liveGear.lastPoint[5] == 293, "an edge tooltip must use available space below instead of clamping over loot")
nativeLootFrame.mockBottom = nil
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 40, 317
tickLiveSource()
fire("INSPECT_READY", "Player-Mage")
assert(liveGear.tooltipLink == equipped, "a delayed inspect must not replace the newly selected player")
mouseDown("LeftButton", UIParent)
assert(not liveDrop:IsVisible() and not liveGear:IsVisible())
inspectedUnit = nil
live.rows[1]:GetScript("OnClick")(live.rows[1])
assert(not inspectedUnit, "the client inspect throttle must still apply")
timerNow = timerNow + 2
flushTimers()
assert(inspectedUnit == "party1", "the current selection should retry after the throttle")
fire("INSPECT_READY", "Player-Mage")
assert(liveGear.tooltipLink == memberItem)
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 350, 627
nativeLootFrame.mockBottom, nativeLootFrame.mockTop = 400, 500
live.mockLeft, live.mockRight, live.mockBottom, live.mockTop = 180, 345, 395, 505
tickLiveSource()
flushTimers()
local pawnAdvisor = CreateFrame("Frame", "PawnUI_LootUpgradeAdvisor1")
pawnAdvisor.mockLeft, pawnAdvisor.mockRight = 640, 900
pawnAdvisor.mockBottom, pawnAdvisor.mockTop = 425, 550
local geometry = LootRollsPlusLiveGeometry
geometry:GetScript("OnUpdate")(geometry, 0.2)
flushTimers()
local gearX, gearY = liveGear.lastPoint[4], liveGear.lastPoint[5]
assert(liveGear.lastPoint[2] == UIParent and liveGear.lastPoint[3] == "BOTTOMLEFT")
assert(not latestNS.LiveView.RectOverlaps({left = gearX, right = gearX + liveGear:GetWidth(),
    top = gearY, bottom = gearY - liveGear:GetHeight()}, latestNS.LiveView.VisiblePawnRects()),
    "the already-open equipment must move away when Pawn appears")
UIParent:SetSize(1000, 800)
liveGear:SetSize(390, 150)
local secondPrompt = newWidget("Frame", UIParent)
secondPrompt.mockLeft, secondPrompt.mockRight = 350, 627
secondPrompt.mockBottom, secondPrompt.mockTop = 260, 380
local firstRoll, secondRoll = live.entry, {}
for k, v in pairs(firstRoll) do secondRoll[k] = v end
secondRoll.id, secondRoll.anchor = firstRoll.id + 1, secondPrompt
latestNS.LiveView:Render({firstRoll, secondRoll}, false, false)
latestNS.LiveView.OnPlacementChanged()
flushTimers()
gearX, gearY = liveGear.lastPoint[4], liveGear.lastPoint[5]
assert(liveGear.lastPoint[3] == "BOTTOMLEFT" and not latestNS.LiveView.RectOverlaps({left = gearX,
    right = gearX + liveGear:GetWidth(), top = gearY, bottom = gearY - liveGear:GetHeight()},
    latestNS.LiveView.VisiblePromptRects()), "Pawn fallback must leave a second loot prompt clickable")
UIParent:SetSize(1400, 900)
liveGear:SetSize(200, 150)
latestNS.LiveView:Render({firstRoll}, false, false)
pawnAdvisor:Hide()
geometry:GetScript("OnUpdate")(geometry, 0.2)
flushTimers()
assert(liveGear.lastPoint[2] == nativeLootFrame and liveGear.lastPoint[3] == "TOPRIGHT")
secondPrompt.mockLeft, secondPrompt.mockRight = 657, 900
secondPrompt.mockBottom, secondPrompt.mockTop = 425, 550
latestNS.LiveView:Render({firstRoll, secondRoll}, false, false)
latestNS.LiveView.OnPlacementChanged()
flushTimers()
gearX, gearY = liveGear.lastPoint[4], liveGear.lastPoint[5]
assert(liveGear.lastPoint[2] == UIParent and liveGear.lastPoint[3] == "BOTTOMLEFT"
    and not latestNS.LiveView.RectOverlaps({left = gearX, right = gearX + liveGear:GetWidth(),
        top = gearY, bottom = gearY - liveGear:GetHeight()}, latestNS.LiveView.VisiblePromptRects()),
    "equipped gear must avoid another native prompt even without Pawn")
latestNS.LiveView:Render({firstRoll}, false, false)
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 40, 317
nativeLootFrame.mockBottom, nativeLootFrame.mockTop = nil, nil
live.mockLeft, live.mockRight, live.mockBottom, live.mockTop = nil, nil, nil, nil
liveVotes[1].playerGUID = "Player-Replacement"
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(not liveGear:IsVisible(), "equipment must close when the selected participant's GUID changes")
liveVotes[1].playerGUID = "Player-Mage"
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
mouseDown("LeftButton", UIParent)
liveVotes[2].state = 4
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()

IsInRaid = function() return true end
fire("GROUP_ROSTER_UPDATE")
tickLiveSource()
assert(live.toggle:IsVisible() and not live.rows[1]:IsVisible())
live.toggle:GetScript("OnClick")()
liveDetails = LootRollsPlusLiveDetails
assert(liveDetails:IsVisible() and not liveDetails.slider:IsVisible())

UIParent:SetSize(650, 400)
nativeLootFrame.mockLeft, nativeLootFrame.mockRight = 186, 463
live.summary.mockGlyphWidth = 7
liveDetails.counts[2].mockGlyphWidth = 10
Enum.EncounterLootDropRollState.Disenchant = 6
local livePlayers = drops[lootKey].rollInfos
livePlayers[1].roll = 100
livePlayers[3] = {playerName = "Tirion Long Realm", playerClass = "PALADIN", state = 0, roll = 96}
livePlayers[4] = {playerName = "Off Spec Player", playerClass = "PALADIN", state = 1, roll = 98}
livePlayers[5] = {playerName = "Disenchant Player", state = 6}
livePlayers[6] = {playerName = "Transmog Player", state = 2}
livePlayers[7] = {playerName = "Greed Player", state = 3, roll = 80}
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(live:GetWidth() < 185 and live:GetWidth() >= 174)
assert(live.summary:GetUnboundedStringWidthForText(live.summary.value) <= live:GetWidth() - 12)
contains(live.summary.value, "lootroll-icon-need")
contains(live.summary.value, "lootroll-icon-greed")
contains(live.summary.value, "lootroll-icon-pass")
assert(live.toggleText.value == "|cffffd477>|r", "with two visible leaders, keep the disclosure cue narrow")
assert(live.leaders[1].result.value == "|cffff5050100|r")
contains(liveDetails.rows[2].name.value, "Tirion Long Realm")
contains(liveDetails.rows[3].result.value, "Off")
contains(liveDetails.counts[2].value, "Off 1")
contains(liveDetails.counts[2].value, "DE 1")
contains(liveDetails.counts[3].value, "TM 1")
contains(liveDetails.counts[3].value, "Wait 1")
contains(liveDetails.rows[5].result.value, "|cff50ff50Greed 80")
contains(liveDetails.rows[2].result.value, "common-radiobutton-dot")
liveDetails.rows[2]:GetScript("OnClick")(liveDetails.rows[2])
assert(not liveDrop:IsVisible() and liveGear:IsVisible(), "the expanded row should show only equipped gear")
assert(liveGear.lastPoint[2] == liveDetails and liveGear.lastPoint[3] == "TOPRIGHT")
mouseDown("LeftButton", liveGear)
assert(liveDetails:IsVisible() and liveGear:IsVisible(), "clicking the equipment must keep its raid roster open")
mouseDown("LeftButton", UIParent)
assert(not liveGear:IsVisible())

drops[lootKey].rollInfos[1].roll = 87
drops[lootKey].winner = drops[lootKey].rollInfos[1]
fire("LOOT_HISTORY_UPDATE_DROP", 20, lootKey)
tickLiveSource()
assert(not live.toggle:IsVisible() and not liveDetails:IsVisible() and live.winnerRows[1]:IsVisible())
contains(live.summary.value, "Winner")
contains(live.winnerRows[1].result.value, "Need 87")
live.winnerRows[1]:GetScript("OnClick")(live.winnerRows[1])
assert(liveGear:IsVisible() and not liveDrop:IsVisible())
fire("CANCEL_LOOT_ROLL", rollID)
tickLiveSource()
assert(not live:IsVisible() and not liveDrop:IsVisible() and not liveGear:IsVisible())

local auditView = latestNS.LiveView
local auditAnchor = CreateFrame("Frame", nil, UIParent)
auditAnchor.mockLeft, auditAnchor.mockRight = 300, 577
UIParent:SetSize(1400, 800)
local auditPlayer = {name = "Longlongname", choice = "need", roll = 100, warning = "incompatible"}
local function auditEntry(link)
    return {id = 456, link = link, anchor = auditAnchor, players = {auditPlayer}, leaders = {auditPlayer},
        counts = {need = 1}, more = 0, canInspect = true}
end
auditView:Render({auditEntry(cloth)}, true, false)
local auditCard = LootRollsPlusLiveRoll1
auditCard.toggle:GetScript("OnClick")()
assert(LootRollsPlusLiveDetails:IsVisible())
auditView:Render({auditEntry(cloth)}, true, false)
assert(LootRollsPlusLiveDetails:IsVisible(), "same drop keeps open disclosure")
auditView:Render({auditEntry(shield)}, true, false)
assert(not LootRollsPlusLiveDetails:IsVisible(), "reused ID must close previous drop disclosure")
auditPlayer.name, auditPlayer.class, auditPlayer.guid = "Self", "PALADIN", false
auditView:Render({auditEntry(cloth)}, false, false)
auditCard.rows[1]:GetScript("OnClick")(auditCard.rows[1])
assert(not liveGear.tooltipLink, "a restricted GUID must not fall back to inspecting by name")
contains(liveGear.value, "Cannot inspect")
mouseDown("LeftButton", UIParent)
UIParent:SetSize(535, 800)
auditAnchor.mockLeft, auditAnchor.mockRight = 122, 411
auditView:Render({auditEntry(shield)}, false, false)
local auditResult = auditCard.rows[1].result
contains(auditResult.value, "100")
contains(auditResult.value, "common-radiobutton-dot")
assert(auditResult:GetUnboundedStringWidthForText(auditResult.value) <= auditResult:GetWidth(),
    "narrow result must fit")
UIParent:SetSize(420, 800)
auditAnchor.mockLeft, auditAnchor.mockRight = 110, 315
auditAnchor.mockBottom, auditAnchor.mockTop = 360, 415
auditView:Render({auditEntry(shield)}, false, false)
assert(auditCard:IsVisible() and auditCard.lastPoint[2] == UIParent and auditCard.lastPoint[3] == "BOTTOMLEFT",
    "a compact roll panel should use vertical space when neither side can fit")
UIParent:SetSize(650, 800)
local sizeWatcher = LootRollsPlusLiveGeometry
sizeWatcher:GetScript("OnUpdate")(sizeWatcher, 0.2)
assert(auditCard.placement == "right", "widening the screen must let the panel move beside an unchanged prompt")
auditAnchor.mockScale = math.huge
auditView:Render({auditEntry(shield)}, false, false)
assert(not auditCard:IsVisible(), "nonfinite geometry cannot be used as an anchor")

do
    UIParent:SetSize(610, 400)
    local firstPrompt = CreateFrame("Frame", nil, UIParent)
    local secondPrompt = CreateFrame("Frame", nil, UIParent)
    firstPrompt.mockLeft, firstPrompt.mockRight, firstPrompt.mockBottom, firstPrompt.mockTop = 30, 250, 115, 195
    secondPrompt.mockLeft, secondPrompt.mockRight, secondPrompt.mockBottom, secondPrompt.mockTop = 300, 500, 185, 250
    pawnAdvisor.mockLeft, pawnAdvisor.mockRight, pawnAdvisor.mockBottom, pawnAdvisor.mockTop = 255, 560, 110, 200
    pawnAdvisor:Show()
    local function entry(id, anchor)
        return {id = id, link = cloth, anchor = anchor, canInspect = true,
            players = {{name = "LongNameWithMore", choice = "greed", roll = 98}}}
    end
    auditView:Render({entry(2001, firstPrompt), entry(2002, secondPrompt)}, false, false)
    local first, second = LootRollsPlusLiveRoll1, LootRollsPlusLiveRoll2
    assert(first:IsVisible() and second:IsVisible())
    assert(first.placement == "vertical" and second.placement == "vertical"
        and not auditView.RectOverlaps(first.bounds, {second.bounds}),
        "the second roll card must avoid an earlier card that fell back above its prompt")
    local rollFrames = GroupLootContainer.rollFrames
    GroupLootContainer.rollFrames = {firstPrompt, secondPrompt}
    secondPrompt.mockLeft, secondPrompt.mockRight, secondPrompt.mockBottom, secondPrompt.mockTop = 30, 250, 215, 295
    auditView:Render({entry(2001, firstPrompt)}, false, false)
    local prompts = auditView.VisiblePromptRects()
    assert(first:IsVisible() and #prompts == 2 and not auditView.RectOverlaps(first.bounds, prompts),
        "a visible native prompt must keep its space even when its item is unreadable")
    local oldBottom = first.bounds.bottom
    secondPrompt:Hide()
    local watcher = LootRollsPlusLiveGeometry
    watcher:GetScript("OnUpdate")(watcher, 0.2)
    assert(first:IsVisible() and first.bounds.bottom ~= oldBottom, "hiding an unreported prompt must free its space")
    pawnAdvisor:Hide()
    auditView:Hide()

    UIParent:SetSize(1000, 600)
    firstPrompt.mockLeft, firstPrompt.mockRight, firstPrompt.mockBottom, firstPrompt.mockTop = 600, 820, 250, 340
    secondPrompt.mockLeft, secondPrompt.mockRight, secondPrompt.mockBottom, secondPrompt.mockTop = 150, 380, 245, 345
    secondPrompt:Show()
    local raidEntry = entry(2003, firstPrompt)
    raidEntry.counts, raidEntry.leaders, raidEntry.more = {greed = 40}, {}, 0
    for i = 1, 40 do raidEntry.players[i] = {name = "Raider " .. i, choice = "greed", roll = 100 - i} end
    auditView:Render({raidEntry}, true, false)
    first.mockLeft, first.mockRight, first.mockBottom, first.mockTop = 390, 595, 275, 315
    first.toggle:GetScript("OnClick")(first.toggle)
    local roster = LootRollsPlusLiveDetails
    assert(roster:IsVisible() and roster.lastPoint[1] == "BOTTOMRIGHT" and roster.lastPoint[2] == first,
        "the expanded raid list must avoid the neighboring native loot prompt")

    UIParent:SetSize(1000, 280)
    firstPrompt.mockBottom, firstPrompt.mockTop = 107, 197
    secondPrompt.mockBottom, secondPrompt.mockTop = 0, 280
    first.mockBottom, first.mockTop = 133, 171
    auditView:Render({raidEntry}, true, false)
    local shown = 0
    for _, row in ipairs(roster.rows) do if row:IsVisible() then shown = shown + 1 end end
    assert(roster:IsVisible() and shown > 0 and shown < 8 and roster.slider.maxValue == 40 - shown,
        "a shorter roster must remain open and scroll through all raiders when space is tight")
    roster.slider:SetValue(roster.slider.maxValue)
    assert(roster.rows[shown].livePlayer == raidEntry.players[40])

    UIParent:SetSize(1000, 169)
    firstPrompt.mockBottom, firstPrompt.mockTop = 39, 129
    secondPrompt.mockTop = 169
    first.mockBottom, first.mockTop = 65, 103
    auditView:Render({raidEntry}, true, false)
    assert(roster:IsVisible() and roster.visibleRows == 1 and roster.slider.maxValue == 39)
    assert(roster.slider.lastPoint[3] == 7 and roster.slider:GetThumbTexture():GetHeight() <= 11,
        "the scrollbar and thumb must fit a one-row viewport")
    roster.slider:SetValue(39)
    assert(roster.rows[1].livePlayer == raidEntry.players[40])
    first.mockLeft, first.mockRight, first.mockBottom, first.mockTop = nil, nil, nil, nil
    GroupLootContainer.rollFrames = rollFrames
    auditView:Hide()
end

do
    -- A warning on a losing vote belongs to that participant, not the winner's row.
    local record = {
        t = wallTime, link = shield, done = true, winner = "Warrior", winnerClass = "WARRIOR",
        winnerType = "greed", winnerValue = 92,
        rolls = {
            {name = "Mage", class = "MAGE", type = "need", value = 34},
            {name = "Warrior", class = "WARRIOR", type = "greed", value = 92, isWinner = true},
        },
    }
    LootRollsPlusCharDB.days = {[date("%Y-%m-%d", wallTime)] = {record}}
    loadAddon(true)
    local winnerRow = nextVisibleRow(LootRollsPlusFrame)
    assert(winnerRow.entry == record and not winnerRow.alert:IsVisible())
    contains(winnerRow.right.value, "Greed 92")
    winnerRow:GetScript("OnEnter")(winnerRow)
    contains(table.concat(tooltip, "\n"), "common-radiobutton-dot")
    winnerRow:GetScript("OnLeave")(winnerRow)
    record.capture, record.winnerType, record.winnerValue = "history", "need", nil
    record.rolls[2].type, record.rolls[2].value = "need", 96
    winnerRow:GetScript("OnEnter")(winnerRow)
    local breakdown = table.concat(tooltip, "\n")
    contains(breakdown, "(winner)")
    assert(not breakdown:find("Need 96", 1, true),
        "a native winner with no verified score must not borrow a conflicting participant roll")
    winnerRow:GetScript("OnLeave")(winnerRow)
end
do
    UIParent:SetSize(1400, 900)
    LootRollsPlusCharDB.days = {}
    function IsInRaid() return false end
    loadAddon(true)
    local key = 1001
    wallTime, historyTime = wallTime + 1, historyTime + 1
    local mage = {playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0}
    drops[key] = {lootListKey = key, itemHyperlink = cloth, startTime = historyTime, rollInfos = {mage}}
    C_LootHistory.GetSortedDropsForEncounter = function() return {drops[key]} end
    local combat = true
    function InCombatLockdown() return combat end
    inspectedUnit = nil
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    local entry = nextVisibleRow(LootRollsPlusFrame).entry
    assert(entry.lootListKey == key and entry.rolls[1].type == "need", "test must capture a fresh Need vote")
    timerNow = timerNow + 0.5
    flushTimers()
    assert(not inspectedUnit and not entry.inspections, "the background inspection must defer in combat")
    combat = false
    timerNow = timerNow + 0.5
    flushTimers()
    assert(inspectedUnit == "party1", "Need should dispatch inspection without clicking a row")
    fire("INSPECT_READY", "Player-Mage")
    local saved = entry.inspections["Other Mage"]
    assert(saved.atDrop and saved.links[1] == memberItem and saved.guid == "Player-Mage")
    mage.roll, mage.isWinner = 96, true
    drops[key].winner = mage
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    function GetNumGroupMembers() return 1 end
    inspectedUnit = nil
    loadAddon(true)
    openHistory()
    local row = nextVisibleRow(LootRollsPlusHistoryScroll.scrollChild)
    assert(row.entry == entry and row.entry.inspections["Other Mage"] == saved)
    row:GetScript("OnClick")(row)
    local card = LootRollsPlusEquippedTooltip
    assert(card.tooltipLink == memberItem and not inspectedUnit)
    contains(card.footer, "Inspected near the roll")
end
do
    local previous = {
        t = wallTime - 10, link = cloth, done = true, winner = "Other Mage",
        winnerClass = "MAGE", winnerType = "greed",
        rolls = {{name = "Other Mage", class = "MAGE", type = "greed"}},
    }
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    function GetNumGroupMembers() return 2 end
    for index, scenario in ipairs({"close", "expire", "retry"}) do
        LootRollsPlusCharDB.days = {[date("%Y-%m-%d", wallTime)] = {previous}}
        loadAddon(true)
        local key = 1100 + index
        historyTime = historyTime + 1
        inspectedUnit = nil
        drops[key] = {lootListKey = key, itemHyperlink = cloth, startTime = historyTime,
            rollInfos = {{playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0}}}
        fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
        timerNow = timerNow + 0.5
        flushTimers()
        assert(inspectedUnit == "party1", "background inspection must occupy the shared request")
        local oldRow
        for _, candidate in ipairs(LootRollsPlusFrame.children) do
            if candidate.entry == previous then oldRow = candidate end
        end
        assert(oldRow)
        oldRow:GetScript("OnClick")(oldRow)
        fire("INSPECT_READY", "Player-Mage")
        inspectedUnit = nil
        if scenario == "close" then oldRow:GetScript("OnClick")(oldRow) end
        timerNow = timerNow + (scenario == "expire" and 7 or 2)
        flushTimers()
        if scenario ~= "retry" then
            assert(not inspectedUnit, "closing the comparison or expiring its deadline must invalidate the retry")
        else
            assert(inspectedUnit == "party1", "an open comparison must retry when the inspection throttle expires")
            fire("INSPECT_READY", "Player-Mage")
            assert(LootRollsPlusEquippedTooltip.tooltipLink == memberItem)
        end
    end
end
do
    LootRollsPlusCharDB.days = {}
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    function GetNumGroupMembers() return 2 end
    loadAddon(true)
    local key = 1003
    wallTime, historyTime = wallTime + 1, historyTime + 1
    local mage = {playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0}
    drops[key] = {lootListKey = key, itemHyperlink = cloth, startTime = historyTime, rollInfos = {mage}}
    local combat = true
    function InCombatLockdown() return combat end
    inspectedUnit = nil
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    for _ = 1, 41 do
        timerNow = timerNow + 0.5
        flushTimers()
    end
    assert(not inspectedUnit)
    combat = false
    mage.roll, mage.isWinner = 96, true
    drops[key].winner = mage
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    timerNow = timerNow + 0.5
    flushTimers()
    assert(inspectedUnit == "party1", "a confirmed winner gets one attempt after the earlier Need inspection expired")
    fire("INSPECT_READY", "Player-Mage")
    assert(nextVisibleRow(LootRollsPlusFrame).entry.inspections["Other Mage"].links[1] == memberItem)
end
do
    LootRollsPlusCharDB.days = {}
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    loadAddon(true)
    local key = 1006
    wallTime, historyTime = wallTime + 1, historyTime + 1
    local winner = {playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0, roll = 98}
    drops[key] = {lootListKey = key, itemHyperlink = cloth, startTime = historyTime, rollInfos = {winner}, winner = winner}
    local previousCanInspect = CanInspect
    function CanInspect() return false end
    inspectedUnit = nil
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    timerNow = timerNow + 0.5
    flushTimers()
    assert(not inspectedUnit)
    CanInspect = previousCanInspect
    timerNow = timerNow + 0.5
    flushTimers()
    assert(inspectedUnit == "party1", "a recent winner should be inspected when back in range")
    InspectFrame = {IsShown = function() return true end}
    fire("INSPECT_READY", "Player-Mage")
    InspectFrame = nil
    inspectedUnit = nil
    for _ = 1, 4 do timerNow = timerNow + 0.5; flushTimers() end
    assert(inspectedUnit == "party1", "a recent winner should retry after the Blizzard Inspect frame closes")
    fire("INSPECT_READY", "Player-Mage")
    assert(nextVisibleRow(LootRollsPlusFrame).entry.inspections["Other Mage"].links[1] == memberItem)
end
do
    LootRollsPlusCharDB.days = {}
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    function GetLootRollItemLink() return cloth end
    function GetActiveLootRollIDs() return {1900} end
    function GetNumGroupMembers() return 1 end
    loadAddon(true)
    local key = 1002
    wallTime, historyTime = wallTime + 1, historyTime + 1
    fire("START_LOOT_ROLL", 1900, 30000)
    fire("CHAT_MSG_LOOT", "You have selected Need for: " .. cloth)
    local provisional = nextVisibleRow(LootRollsPlusFrame).entry
    timerNow = timerNow + 0.5
    flushTimers()
    local earlier = provisional.inspections and provisional.inspections.Self
    assert(earlier and earlier.links[1] == equipped)
    local laterItem = "|cff1eff00|Hitem:9125::::::::|h[New equipment]|h|r"
    function GetInventoryItemLink() return laterItem end
    local self = { playerName = "Self", playerClass = "PALADIN", playerGUID = "Player-Test", state = 0, roll = 97 }
    drops[key] = { lootListKey = key, itemHyperlink = cloth, startTime = historyTime, rollInfos = {} }
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    local replacement = nextVisibleRow(LootRollsPlusFrame).entry
    assert(replacement ~= provisional and not replacement.inspections,
        "pending transfer must stay out of saved history until the native identity is known")
    drops[key].rollInfos, drops[key].winner = {self}, self
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    timerNow = timerNow + 0.5
    flushTimers()
    assert(nextVisibleRow(LootRollsPlusFrame).entry == replacement and #LootRollsPlusCharDB.days[date("%Y-%m-%d", wallTime)] == 1)
    assert(replacement.inspections and replacement.inspections.Self == earlier,
        "the native record must keep the earlier matching equipment instead of inspecting the new item")
end
do
    LootRollsPlusCharDB.days = {}
    LOOT_ROLL_NEED = "%s need %s"
    function GetNumGroupMembers() return 2 end
    function GetActiveLootRollIDs() return {1901} end
    function GetInventoryItemLink() return memberItem end
    loadAddon(true)
    local key = 1004
    wallTime, historyTime = wallTime + 1, historyTime + 1
    fire("START_LOOT_ROLL", 1901, 30000)
    fire("CHAT_MSG_LOOT", "Other Mage need " .. cloth)
    local provisional = nextVisibleRow(LootRollsPlusFrame).entry
    inspectedUnit = nil
    timerNow = timerNow + 0.5
    flushTimers()
    assert(inspectedUnit == "party1" and not provisional.inspections)
    local mage = {playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0, roll = 88}
    drops[key] = {lootListKey = key, itemHyperlink = cloth, startTime = historyTime, rollInfos = {mage}, winner = mage}
    fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
    local replacement = nextVisibleRow(LootRollsPlusFrame).entry
    assert(replacement ~= provisional)
    fire("INSPECT_READY", "Player-Mage")
    assert(not provisional.inspections and replacement.inspections["Other Mage"].links[1] == memberItem,
        "an in-flight inspection must finish on the verified native replacement")
end
do
    local timestamp = wallTime
    local entries = {}
    for i = 1, 7 do
        entries[i] = historyEntry(timestamp)
        entries[i].legacy = true
    end
    LootRollsPlusCharDB.days = {[date("%Y-%m-%d", timestamp)] = entries}
    LootRollsPlusDB.windowHeight = 159 -- 22px header, 18px footer, seven 17px rows.
    loadAddon(true)
    local _, _, itemScroll = openHistory()
    assert(itemScroll.scrollChild:GetHeight() == itemScroll:GetHeight(), "seven rows should fit exactly")
    assert(not itemScroll.ScrollBar:IsShown(), "History should not scroll through empty bottom space")
end
do
    local when, start = wallTime - 20, historyTime - 20
    local closed = {t = when, startTime = start, encounterID = 20, lootListKey = 39,
        link = cloth, capture = "history", closed = true,
        rolls = {{name = "Other Mage", class = "MAGE", type = "need", value = 94}}}
    local finished = {playerName = "Other Mage", playerClass = "MAGE", state = 0, roll = 94}
    local result = {lootListKey = 39, itemHyperlink = cloth, startTime = start, rollInfos = {finished}}
    LootRollsPlusCharDB.days = {[date("%Y-%m-%d", when)] = {closed}}
    drops[39] = result
    C_LootHistory.GetSortedDropsForEncounter = function() return {result} end
    loadAddon(true)
    assert(closed.closed and not closed.done, "reload must not reopen a closed roll without a final result")
    inspectedUnit = nil
    timerNow = timerNow + 0.5
    flushTimers()
    assert(not inspectedUnit, "rebinding a closed roll must not inspect gear before confirmation")
    result.winner = finished
    fire("LOOT_HISTORY_UPDATE_DROP", 20, 39)
    assert(closed.done and closed.winner == "Other Mage" and closed.winnerValue == 94,
        "an exact closed roll should accept a confirmed native result after reload")
    assert(#LootRollsPlusCharDB.days[date("%Y-%m-%d", when)] == 1, "the late result must update, not duplicate")
end
do
    local ring = "|cnIQ2:|Hitem:2001::::::::|h[Dropped ring]|h|r"
    local firstRing = "|cnIQ2:|Hitem:2002::::::::|h[Earlier ring]|h|r"
    local secondRing = "|cnIQ2:|Hitem:2003::::::::|h[Second ring]|h|r"
    local replacementRing = "|cnIQ2:|Hitem:2004::::::::|h[Changed ring]|h|r"
    local normalInstant = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = function(link)
        if link == ring then return 2001, "Armor", "Miscellaneous", "INVTYPE_FINGER", 84, 4, 0 end
        return normalInstant(link)
    end
    function GetInventorySlotInfo(name)
        if name == "Finger0Slot" then return 11 end
        if name == "Finger1Slot" then return 12 end
    end
    local first, second
    function GetInventoryItemLink(_, slot)
        if slot == 11 then return first end
        if slot == 12 then return second end
    end
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    function GetNumGroupMembers() return 2 end
    function InCombatLockdown() return false end
    for _, changed in ipairs({false, true}) do
        LootRollsPlusCharDB.days = {}
        loadAddon(true)
        first, second = firstRing, nil
        local key = changed and 2052 or 2051
        local player = {playerName = "Other Mage", playerClass = "MAGE", playerGUID = "Player-Mage", state = 0}
        wallTime, historyTime = wallTime + 1, historyTime + 1
        drops[key] = {lootListKey = key, itemHyperlink = ring, startTime = historyTime, rollInfos = {player}}
        fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
        timerNow = timerNow + 0.5
        flushTimers()
        fire("INSPECT_READY", "Player-Mage")
        local entry = nextVisibleRow(LootRollsPlusFrame).entry
        local snapshot = assert(entry.inspections and entry.inspections["Other Mage"])
        assert(snapshot.atDrop and snapshot.links[1] == firstRing and not snapshot.links[2])
        first, second = changed and replacementRing or firstRing, secondRing
        player.roll, drops[key].winner = 96, player
        inspectedUnit = nil
        fire("LOOT_HISTORY_UPDATE_DROP", 20, key)
        for _ = 1, 5 do timerNow = timerNow + 0.5; flushTimers() end
        assert(inspectedUnit == "party1", "a winner with a partial snapshot should be inspected again")
        fire("INSPECT_READY", "Player-Mage")
        local saved = entry.inspections["Other Mage"]
        assert(saved.links[1] == firstRing and saved.links[2] == (not changed and secondRing or nil),
            "fill a partial snapshot only while the previously known equipment still agrees")
    end
end
for _, warmTooltip in ipairs({false, true}) do
    local when = wallTime
    local entries = {}
    for id = 20001, 20100 do
        local link = ("|cnIQ2:|Hitem:%d::::::::|h[Cold gear]|h|r"):format(id)
        entries[#entries + 1] = {link = link, t = when, done = true, winner = "Self",
            winnerClass = "PALADIN", winnerType = "need", rolls = {}}
    end
    local pinned = "|cnIQ2:|Hitem:30001::::::::|h[Cold comparison]|h|r"
    entries[#entries + 1] = {link = pinned, t = when, done = true, rolls = {},
        winner = warmTooltip and "Self" or nil, winnerClass = warmTooltip and "PALADIN" or nil,
        winnerType = warmTooltip and "greed" or nil}
    LootRollsPlusDB.hideSolo = false
    LootRollsPlusCharDB.days = {[date("%Y-%m-%d", when)] = entries}
    C_LootHistory.GetSortedDropsForEncounter = function() return {} end
    C_Item.GetItemInfoInstant = function() return nil end
    local callbacks, pinnedRequests = {}, 0
    Item = {CreateFromItemLink = function(_, link)
        return {ContinueOnItemLoad = function(_, callback)
            callbacks[link] = callback
            if link == pinned then pinnedRequests = pinnedRequests + 1 end
        end}
    end}
    loadAddon(true)
    local _, _, itemScroll = openHistory()
    local row = nextVisibleRow(itemScroll.scrollChild)
    assert(row.entry.link == pinned and not callbacks[pinned])
    local card, gear = LootRollsPlusDroppedTooltip, LootRollsPlusEquippedTooltip
    card.failHyperlink = not warmTooltip
    row:GetScript("OnClick")(row)
    if warmTooltip then assert(card.tooltipLink == pinned) end
    contains((warmTooltip and gear or card).value, "Loading item")
    assert(not callbacks[pinned], "a comparison must respect the item request cap")
    timerNow = timerNow + 15
    flushTimers()
    flushTimers()
    assert(callbacks[pinned], "a pinned card must retry once the item request cap frees up")
    if warmTooltip then
        timerNow = timerNow + 15
        flushTimers()
        flushTimers()
        contains(gear.value, "Item data unavailable")
        assert(pinnedRequests == 1, "a stuck slot request must stop retrying after its timeout")
        C_Item.GetItemInfoInstant = function(link)
            if link == pinned then return 30001, "Armor", "Cloth", "INVTYPE_CHEST", 84, 4, 1 end
        end
        function GetInventorySlotInfo(name) if name == "ChestSlot" then return 5 end end
        function GetInventoryItemLink(unit, slot) if unit == "player" and slot == 5 then return equipped end end
    end
    card.failHyperlink = nil
    callbacks[pinned]()
    flushTimers()
    assert(card.tooltipLink == pinned, "the deferred comparison should show the loaded item")
    if warmTooltip then assert(gear.tooltipLink == equipped, "late slot metadata must resume the selected inspection") end
end
print("Addon TOC, event, and UI integration tests passed")
