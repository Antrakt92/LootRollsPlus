-- Based on Loot Rolls Inspector by Carlos (mr_mirror), MIT. See LICENSE.
local ADDON, ns = ...
local display = ns.RollDisplay

local DEFAULT_VISIBLE, MAX_VISIBLE = 10, 25
local DEFAULT_MAX_DAYS = 365
local MAX_RETENTION_DAYS = 3650
local ROW_H = 17
local WINDOW_PADDING = 34
local MIN_WINDOW_HEIGHT, MAX_WINDOW_HEIGHT = 153, WINDOW_PADDING + MAX_VISIBLE * ROW_H

local db    -- LootRollsPlusDB: ajustes de la cuenta (posicion, opciones)
local days  -- LootRollsPlusCharDB.days: historial de este personaje
local charDB, visits, capture
local refresh, queueRefresh, toggleDetails, UpdateVisibility
local RenderLiveRolls, PlaceComparison
local hoverRow
local worldReady
local comparisonNeedsItem
local activeEntries = {}
local nextActiveOrder = 0
local isSecret = issecretvalue or function() return false end
local pendingItems = {}
local MAIN_WIDTH, HISTORY_WIDTH = 305, 430
local STATUS_WIDTH = 137
local ALERT_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local ALERT_SIZE, ALERT_GAP = 8, 3
local ALERT_STATUS_GAP = 5
local ALERT_COLORS = display.WarningColors
local MAX_PENDING_ITEMS = 100
local pendingItemCount = 0
local Label = display.Label
local UNKNOWN = Label("Result unavailable", "Результат неизвестен")
local OUTSIDE = Label("No dungeon recorded", "Подземелье не записано")
local WAITING = Label("Waiting", "Ожидание")
local AMBIGUOUS = Label("Overlapping rolls", "Совпавшие розыгрыши")
local NEED_SUMMARY = Label("Need", "Нужда")
local SHORT_CHOICES = {
    greed = Label("Greed", "Алчность"),
    pass = Label("Pass", "Отказ"),
    disenchant = "DE",
    transmog = "TM",
}
local OTHER_CHOICES = { "greed", "pass", "disenchant", "transmog" }
local MarkupText = display.Escape

local function finite(value)
    return not isSecret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

---------------------------------------------------------------------------
-- Localizacion (se adapta al idioma del cliente; por defecto ingles)
---------------------------------------------------------------------------
local STRINGS = {
    enUS = { history = "History", clear = "Clear", rolling = "Rolling...", allPassed = "Everyone passed",
             noRolls = "No rolls recorded", winner = "winner",
             confirmClear = "Clear all recorded rolls for this character? This cannot be undone.", dateFmt = "%m/%d/%Y" },
    esES = { history = "Historial", clear = "Borrar", rolling = "Tirando...", allPassed = "Todos pasaron",
             noRolls = "Sin tiradas registradas", winner = "ganador",
             confirmClear = "¿Borrar todo el historial de Loot Rolls Plus?", dateFmt = "%d/%m/%Y" },
    deDE = { history = "Verlauf", clear = "Löschen", rolling = "Würfeln...", allPassed = "Alle haben gepasst",
             noRolls = "Keine Würfe aufgezeichnet", winner = "Gewinner",
             confirmClear = "Gesamten Loot-Rolls-Plus-Verlauf löschen?", dateFmt = "%d.%m.%Y" },
    frFR = { history = "Historique", clear = "Effacer", rolling = "Jets en cours...", allPassed = "Tout le monde a passé",
             noRolls = "Aucun jet enregistré", winner = "gagnant",
             confirmClear = "Effacer tout l'historique de Loot Rolls Plus ?", dateFmt = "%d/%m/%Y" },
    ptBR = { history = "Histórico", clear = "Limpar", rolling = "Rolando...", allPassed = "Todos passaram",
             noRolls = "Nenhuma rolagem registrada", winner = "vencedor",
             confirmClear = "Apagar todo o histórico do Loot Rolls Plus?", dateFmt = "%d/%m/%Y" },
}
STRINGS.esMX = STRINGS.esES
STRINGS.ruRU = { history = "История", clear = "Очистить", rolling = "Идёт розыгрыш",
    allPassed = "Все отказались", noRolls = "Голосов пока нет", winner = "победитель",
    confirmClear = "Удалить все записанные розыгрыши этого персонажа? Отменить удаление нельзя.", dateFmt = "%d.%m.%Y" }

local L = STRINGS[GetLocale()] or STRINGS.enUS

local DAYS_SET = {
    ruRU = "История хранится до %d дней.",
    enUS = "History keeps up to %d days.",
    esES = "El historial guarda hasta %d días.",
    esMX = "El historial guarda hasta %d días.",
    deDE = "Der Verlauf speichert bis zu %d Tage.",
    frFR = "L'historique conserve jusqu'à %d jours.",
    ptBR = "O histórico guarda até %d dias.",
}
L.daysSet = DAYS_SET[GetLocale()] or DAYS_SET.enUS

local OPT_STRINGS = {
    ruRU = { options = "Настройки", hideSolo = "Скрывать окно вне группы",
             soloHidden = "Окно скрыто вне группы. Настройки открываются командой /lrplus config." },
    enUS = { options = "Options", hideSolo = "Hide window when not in a group",
             soloHidden = "The window is hidden because you are not in a group (see /lrplus config)." },
    esES = { options = "Opciones", hideSolo = "Ocultar la ventana si no estás en grupo",
             soloHidden = "La ventana está oculta porque no estás en grupo (ver /lrplus config)." },
    deDE = { options = "Optionen", hideSolo = "Fenster ausblenden, wenn nicht in einer Gruppe",
             soloHidden = "Das Fenster ist ausgeblendet, da du in keiner Gruppe bist (siehe /lrplus config)." },
    frFR = { options = "Options", hideSolo = "Masquer la fenêtre hors groupe",
             soloHidden = "La fenêtre est masquée car vous n'êtes pas en groupe (voir /lrplus config)." },
    ptBR = { options = "Opções", hideSolo = "Ocultar a janela fora de grupo",
             soloHidden = "A janela está oculta porque você não está em grupo (veja /lrplus config)." },
}
OPT_STRINGS.esMX = OPT_STRINGS.esES
for k, v in pairs(OPT_STRINGS[GetLocale()] or OPT_STRINGS.enUS) do L[k] = v end

local TYPE_INFO = display.Choices
local UNDECIDED_ORDER = 6
local needPriority = { incompatible = 1, atypical = 2 }

---------------------------------------------------------------------------
-- Datos
---------------------------------------------------------------------------
-- days["YYYY-MM-DD"] = { entradas cronologicas }; dayKeys = claves ordenadas (antigua -> reciente)
local dayKeys = {}
local BuildDayList -- definido en la UI

local function DayKey(t) return date("%Y-%m-%d", t) end

local function DayLabel(key)
    local y, m, d = key:match("(%d+)-(%d+)-(%d+)")
    return date(L.dateFmt, time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }))
end

local function RebuildDayKeys()
    wipe(dayKeys)
    for key, entries in pairs(days) do
        if type(key) == "string" and key:match("^%d%d%d%d%-%d%d%-%d%d$") and type(entries) == "table" then
            dayKeys[#dayKeys + 1] = key
        end
    end
    table.sort(dayKeys)
end

local function PruneDays()
    while #dayKeys > db.maxDays do
        local key = dayKeys[1]
        for _, entry in ipairs(days[key]) do activeEntries[entry] = nil end
        days[key] = nil
        table.remove(dayKeys, 1)
    end
end

local function EnsureDay(key)
    local d = days[key]
    if type(d) ~= "table" then
        d = {}
        days[key] = d
        dayKeys[#dayKeys + 1] = key
        table.sort(dayKeys)
        PruneDays()
    end
    return d
end

local function IsActive(e)
    return not (e.done or e.closed or e.stale or e.legacy or e.ambiguous)
end

local function Latest(n)
    local out = {}
    for entry in pairs(activeEntries) do out[#out + 1] = entry end
    table.sort(out, function(a, b)
        if a.t ~= b.t then return a.t > b.t end
        return activeEntries[a] > activeEntries[b]
    end)
    while #out > n do out[#out] = nil end
    if #out == n then return out end
    for k = #dayKeys, 1, -1 do
        local list = days[dayKeys[k]]
        for i = #list, 1, -1 do
            local entry = list[i]
            if not activeEntries[entry] then
                out[#out + 1] = entry
                if #out == n then return out end
            end
        end
    end
    return out
end

local function ItemLine(e)
    local source = e.sourceName
    return source and (not e.visit or source ~= e.visit.name) and source or nil
end

local function ContextText(e)
    local visit = e.visit and e.visit.name
    local source = ItemLine(e)
    if visit and source then return MarkupText(visit) .. " · " .. MarkupText(source) end
    if visit or source then return MarkupText(visit or source) end
end

local function HasRoll(entry)
    local list = days[DayKey(entry.t)]
    if not list then return false end
    for i = #list, 1, -1 do
        if list[i] == entry then return true end
    end
    return false
end

local NewFrame = display.NewPanel

local function ClearItemRequest(link)
    if pendingItems[link] then
        pendingItems[link] = nil
        pendingItemCount = pendingItemCount - 1
    end
end

local function RequestItemData(link)
    if pendingItems[link] then return pendingItems[link] end
    if pendingItemCount >= MAX_PENDING_ITEMS then return nil, true end
    if Item and type(Item.CreateFromItemLink) == "function" then
        local created, item = pcall(Item.CreateFromItemLink, Item, link)
        if created and not isSecret(item) and type(item) == "table" and type(item.ContinueOnItemLoad) == "function" then
            local request = {}
            pendingItems[link] = request
            pendingItemCount = pendingItemCount + 1
            local ok = pcall(item.ContinueOnItemLoad, item, function()
                if pendingItems[link] == request or (comparisonNeedsItem and comparisonNeedsItem(link, request)) then
                    request.loaded = true
                    -- Keep the marker through redraw when instant metadata is still incomplete.
                    queueRefresh(nil, true)
                end
            end)
            if not ok then
                ClearItemRequest(link)
            else
                C_Timer.After(15, function()
                    if pendingItems[link] ~= request then return end
                    ClearItemRequest(link)
                    if comparisonNeedsItem and (comparisonNeedsItem(link, request) or comparisonNeedsItem()) then
                        queueRefresh()
                    end
                end)
            end
        end
    end
    return pendingItems[link]
end

local function ClassifyGear(link, class, rollType, level)
    local kind, pending = ns.Gear.Classify(link, class, rollType, level)
    if pending then RequestItemData(link) end
    return kind
end

local function CheckGear(e, r, class, rollType)
    class = class or r.class
    rollType = rollType or r.type
    if e.ambiguous or rollType ~= "need" or not class then return end
    if e.legacy and (r.name ~= e.winner or e.winnerType ~= "need" or class ~= e.verifiedWinnerClass) then return end
    return ClassifyGear(e.link, class, rollType, r.level)
end

local function RollText(rollType, value)
    return display.ChoiceText(rollType, value) or UNKNOWN
end

local function ParticipantLines(e)
    local sorted = {}
    for _, r in ipairs(e.rolls) do sorted[#sorted + 1] = r end
    if e.winner then
        local found
        for _, r in ipairs(sorted) do
            if r.isWinner or (e.legacy and e.winner == r.name) then found = true break end
        end
        if not found then
            sorted[#sorted + 1] = {
                name = e.winner, class = e.winnerClass, type = e.winnerType,
                value = e.winnerValue, isWinner = true,
            }
        end
    end
    table.sort(sorted, function(a, b)
        local oa = TYPE_INFO[a.type] and TYPE_INFO[a.type].order or UNDECIDED_ORDER
        local ob = TYPE_INFO[b.type] and TYPE_INFO[b.type].order or UNDECIDED_ORDER
        if oa ~= ob then return oa < ob end
        if (a.value or 0) ~= (b.value or 0) then return (a.value or 0) > (b.value or 0) end
        return a.name < b.name
    end)
    local lines = {}
    for _, r in ipairs(sorted) do
        local winner = r.isWinner or (e.legacy and e.winner == r.name)
        local classFile = (winner and e.winnerClass) or r.class
        local left = display.PlayerText(r.name, classFile)
        if winner then left = left .. "  |cffffd100(" .. L.winner .. ")|r" end
        local rollType = winner and (e.winnerType or r.type) or r.type
        local value = r.value
        if winner and (e.winnerValue ~= nil or e.capture == "history") then value = e.winnerValue end
        local right = RollText(rollType, value)
        if rollType == "undecided" and IsActive(e) then right = WAITING end
        local kind = CheckGear(e, r, classFile, rollType)
        lines[#lines + 1] = { player = left, choice = right, warning = kind }
    end
    return lines
end

local function EmptyResult(e)
    if e.ambiguous then return AMBIGUOUS end
    if e.allpassed then return L.allPassed end
    if IsActive(e) then return L.noRolls end
    return UNKNOWN
end

local function ShowTooltip(owner, e)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(e.link)
    GameTooltip:AddLine(" ")
    local context = ContextText(e)
    if context then GameTooltip:AddLine(context, 0.8, 0.8, 0.8, true) end
    local lines = ParticipantLines(e)
    if #lines == 0 then GameTooltip:AddLine(EmptyResult(e), 0.6, 0.6, 0.6) end
    for _, line in ipairs(lines) do
        GameTooltip:AddDoubleLine(display.WarningDot(line.warning) .. line.player, line.choice, 1, 1, 1)
    end
    GameTooltip:Show()
end

local function ReleaseTooltip(owner)
    if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

local function MakeRow(parent, width, compact)
    local b = CreateFrame("Button", nil, parent)
    b.compact = compact
    b:SetSize(width, ROW_H)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(ROW_H - 4, ROW_H - 4)
    b.icon:SetPoint("LEFT", 2, 0)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.right = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.right:SetPoint("RIGHT", -2, 0)
    b.right:SetJustifyH("RIGHT")
    b.right:SetWidth(STATUS_WIDTH)
    b.right:SetWordWrap(false)
    b.player = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.player:SetPoint("RIGHT", -2, 0)
    b.player:SetWidth(60)
    b.player:SetJustifyH("LEFT")
    b.player:SetWordWrap(false)
    b.classIcon = b:CreateTexture(nil, "ARTWORK")
    b.classIcon:SetSize(14, 14)
    b.classIcon:SetPoint("RIGHT", b.player, "LEFT", -3, 0)
    b.classUnknown = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.classUnknown:SetPoint("CENTER", b.classIcon, "CENTER")
    b.classUnknown:SetText("?")
    b.player:Hide()
    b.classIcon:Hide()
    b.classUnknown:Hide()
    b.alert = b:CreateTexture(nil, "ARTWORK")
    b.alert:SetSize(ALERT_SIZE, ALERT_SIZE)
    b.alert:SetTexture("Interface\\Buttons\\WHITE8X8")
    local mask = b:CreateMaskTexture()
    mask:SetTexture(ALERT_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(b.alert)
    b.alert:AddMaskTexture(mask)
    b.alert:Hide()
    b.left = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.left:SetJustifyH("LEFT")
    b.left:SetWordWrap(false)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    b:SetScript("OnEnter", function(self)
        hoverRow = self
        if self.entry then ShowTooltip(self, self.entry) end
    end)
    b:SetScript("OnLeave", function(self)
        if hoverRow == self then hoverRow = nil end
        ReleaseTooltip(self)
    end)
    b:SetScript("OnHide", function(self)
        if hoverRow == self then hoverRow = nil end
        ReleaseTooltip(self)
    end)
    b:SetScript("OnClick", function(self)
        if not self.entry then return end
        if IsShiftKeyDown() then
            ChatEdit_InsertLink(self.entry.link)
        else
            toggleDetails(self.entry, self.compact, self)
        end
    end)
    return b
end

local function StatusText(e)
    if e.ambiguous then return AMBIGUOUS end
    local counts, needCount = {}, 0
    local firstNeed, firstRank, warning, winnerWarning
    local winnerClass = e.winnerClass
    local winnerInRolls
    for _, r in ipairs(e.rolls) do
        if r.isWinner then
            winnerClass = winnerClass or r.class
            winnerInRolls = true
        end
        local rollType = r.isWinner and e.winnerType or r.type
        if rollType then counts[rollType] = (counts[rollType] or 0) + 1 end
        if rollType == "need" then
            local kind = CheckGear(e, r, r.isWinner and winnerClass or nil, rollType)
            if r.isWinner then winnerWarning = kind end
            needCount = needCount + 1
            local rank = needPriority[kind] or 3
            if not firstNeed or rank < firstRank or (rank == firstRank and r.name < firstNeed.name) then
                firstNeed, firstRank, warning = r, rank, kind
            end
        end
    end
    if e.winner or e.winnerType then
        if not winnerInRolls and e.winnerType == "need" then
            winnerWarning = CheckGear(e, { name = e.winner, type = "need", class = winnerClass })
        end
        return RollText(e.winnerType, e.winnerValue), winnerWarning, e.winner, winnerClass
    end
    if e.allpassed then return "|cff909090" .. L.allPassed .. "|r" end
    if not IsActive(e) then return UNKNOWN, warning end
    if firstNeed then
        local more = needCount > 1 and (" +" .. (needCount - 1)) or ""
        return "|c" .. TYPE_INFO.need.color .. NEED_SUMMARY .. more .. "|r", warning, firstNeed.name, firstNeed.class
    end

    local parts = {}
    for _, rollType in ipairs(OTHER_CHOICES) do
        local count = counts[rollType]
        if count then
            local info = TYPE_INFO[rollType]
            parts[#parts + 1] = "|c" .. info.color .. SHORT_CHOICES[rollType] .. " " .. count .. "|r"
        end
    end
    return #parts > 0 and table.concat(parts, "  ") or L.rolling
end

local function SetResult(row, status, name, class)
    row.right:ClearAllPoints()
    if name then
        row.right:SetPoint("RIGHT", row.classIcon, "LEFT", -4, 0)
        row.right:SetWidth(STATUS_WIDTH - 81)
        row.player:SetText(display.ColoredName(display.ShortName(name), class))
    else
        row.right:SetPoint("RIGHT", -2, 0)
        row.right:SetWidth(STATUS_WIDTH)
    end
    display.SetClassIcon(row.classIcon, row.classUnknown, name, class)
    row.player:SetShown(name ~= nil)
    row.right:SetText(status)
end

local function ItemIcon(link)
    local id = tonumber(link:match("|Hitem:(%d+)"))
    if id and C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, id)
        if ok and not isSecret(icon) and type(icon) == "number" and icon > 0 then return icon end
    end
end

local function FillRow(row, e)
    row.entry = e
    local icon = ItemIcon(e.link)
    row.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
    row.icon:Show()
    row.left:SetText(e.link)
    local status, warning, name, class = StatusText(e)
    SetResult(row, status, name, class)
    local alertColor = ALERT_COLORS[warning]
    if alertColor then
        local width = row.right.GetUnboundedStringWidthForText
            and row.right:GetUnboundedStringWidthForText(status) or row.right:GetStringWidth()
        local available = row.right:GetWidth()
        local offset = (finite(width) and width > 0 and math.min(math.ceil(width), available) or available)
            + ALERT_STATUS_GAP
        if row.alertOffset ~= offset then
            row.alertOffset = offset
            row.alert:ClearAllPoints()
            row.alert:SetPoint("RIGHT", row.right, "RIGHT", -offset, 0)
        end
        row.alert:SetVertexColor(unpack(alertColor))
    end
    local showAlert = alertColor ~= nil
    if row.showAlert ~= showAlert then
        row.showAlert = showAlert
        row.left:ClearAllPoints()
        row.left:SetPoint("LEFT", row.icon, "RIGHT", 4, 0)
        if showAlert then
            row.left:SetPoint("RIGHT", row.alert, "LEFT", -ALERT_GAP, 0)
        else
            row.left:SetPoint("RIGHT", row, "RIGHT", -STATUS_WIDTH - 5, 0)
        end
        row.alert:SetShown(showAlert)
    end
    row:Show()
end

local function CreateResizeGrip(frame, name)
    local grip = CreateFrame("Button", name, frame)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetSize(15, 15)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:EnableMouse(true)
    return grip
end

-- Ventana principal --------------------------------------------------------
local main = NewFrame("LootRollsPlusFrame", nil, MAIN_WIDTH, WINDOW_PADDING + ROW_H)
main:SetMovable(true)
main:SetResizable(true)
main:SetResizeBounds(MAIN_WIDTH, MIN_WINDOW_HEIGHT, MAIN_WIDTH, MAX_WINDOW_HEIGHT)
main:EnableMouse(true)
main:RegisterForDrag("LeftButton")
main:SetClampedToScreen(true)
main:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
main:SetScript("OnDragStart", main.StartMoving)
local function SaveMainPosition()
    local p, _, rp, x, y = main:GetPoint()
    if db and p and rp and finite(x) and finite(y) then db.pos = { p, rp, x, y } end
end

local anchorPoints = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}

local function RestoreMainPosition()
    local pos = db.pos
    if type(pos) ~= "table" or not anchorPoints[pos[1]] or not anchorPoints[pos[2]]
        or not finite(pos[3]) or not finite(pos[4]) then
        db.pos = nil
        return
    end
    main:ClearAllPoints()
    main:SetPoint(pos[1], UIParent, pos[2], pos[3], pos[4])
    main:SetUserPlaced(true)
end

local function KeepMainTopRight()
    local right, top = main:GetRight(), main:GetTop()
    if finite(right) and finite(top) then
        main:ClearAllPoints()
        main:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", right, top)
    end
end

main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if self.history:IsShown() or self.options:IsShown() then KeepMainTopRight() end
    SaveMainPosition()
end)

local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
title:SetPoint("TOPLEFT", 6, -5)
title:SetText("|cff80c0ffLoot Rolls Plus|r")

local function PaintButton(button)
    local highlighted = button.active or button.hovered
    if button.active then
        button.bg:SetColorTexture(0.16, 0.29, 0.42, 0.95)
    elseif button.hovered then
        button.bg:SetColorTexture(0.18, 0.22, 0.27, 0.95)
    else
        button.bg:SetColorTexture(0.09, 0.12, 0.16, 0.95)
    end
    if highlighted then
        button.text:SetTextColor(1, 1, 1)
    elseif button.destructive then
        button.text:SetTextColor(1, 0.57, 0.52)
    else
        button.text:SetTextColor(1, 0.85, 0.52)
    end
end

local function TextButton(label, parent, name, destructive)
    local b = CreateFrame("Button", name, parent or main)
    b:SetHeight(17)
    b.destructive = destructive
    local edge = b:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0.27, 0.34, 0.41, 0.9)
    b.bg = b:CreateTexture(nil, "BORDER")
    b.bg:SetPoint("TOPLEFT", 1, -1)
    b.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 14)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintButton(self)
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = nil
        PaintButton(self)
    end)
    PaintButton(b)
    return b
end

local histBtn = TextButton(L.history)
histBtn:SetPoint("TOPRIGHT", -4, -3)

local optBtn = TextButton(L.options)
optBtn:SetPoint("RIGHT", histBtn, "LEFT", -4, 0)

local mainRows = {}
local sizing, dragRows

local function FitRows(height)
    return math.max(1, math.min(MAX_VISIBLE, math.floor((height - WINDOW_PADDING) / ROW_H)))
end

local function WindowHeightLimit()
    local screen = UIParent:GetHeight()
    return finite(screen) and math.max(MIN_WINDOW_HEIGHT, math.min(screen - 16, MAX_WINDOW_HEIGHT)) or MAX_WINDOW_HEIGHT
end

local function ApplyWindowHeight()
    local height = db.windowHeight or WINDOW_PADDING + math.max(1, #Latest(DEFAULT_VISIBLE)) * ROW_H
    main:SetHeight(math.max(MIN_WINDOW_HEIGHT, math.min(height, WindowHeightLimit())))
end

local function DrawMain()
    if main.options and main.options:IsShown() or main.history and main.history:IsShown() then return end
    if not sizing then ApplyWindowHeight() end
    local latest = Latest(sizing and dragRows or FitRows(main:GetHeight()))
    for i, entry in ipairs(latest) do
        local row = mainRows[i]
        if not row then
            row = MakeRow(main, MAIN_WIDTH - 8, true)
            row:SetPoint("TOPLEFT", 4, -20 - (i - 1) * ROW_H)
            mainRows[i] = row
        end
        FillRow(row, entry)
    end
    for i = #latest + 1, #mainRows do
        mainRows[i].entry = nil
        mainRows[i]:Hide()
    end
end

local grip = CreateResizeGrip(main, "LootRollsPlusResizeGrip")
local function HideMainList()
    grip:Hide()
    for _, row in ipairs(mainRows) do row:Hide() end
end

local function DismissOutside(panel, keepOpen)
    for _, focus in ipairs(GetMouseFoci()) do
        while focus do
            if focus == main or keepOpen and keepOpen(focus) then return end
            focus = focus:GetParent()
        end
    end
    panel:Hide()
end

grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not db then return end
    sizing, dragRows = true, FitRows(main:GetHeight())
    main:StartSizing("BOTTOM")
end)
local function StopSizing()
    if not sizing then return end
    main:StopMovingOrSizing()
    db.windowHeight = main:GetHeight()
    sizing, dragRows = nil, nil
    refresh()
    SaveMainPosition()
end
grip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
        StopSizing()
    elseif button == "RightButton" and db and not sizing then
        db.windowHeight = nil
        ApplyWindowHeight()
        refresh()
    end
end)
grip:SetScript("OnHide", StopSizing)
grip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Label("Drag to change height", "Перетащи, чтобы изменить высоту"))
    GameTooltip:AddLine(Label("Right-click for automatic height", "ПКМ возвращает автоматическую высоту"))
    GameTooltip:Show()
end)
grip:SetScript("OnLeave", ReleaseTooltip)
main:SetScript("OnSizeChanged", function(_, _, height)
    if main.history and main.history:IsShown() then
        main.history:SetHeight(height)
        return
    end
    if PlaceComparison then PlaceComparison(main) end
    if not sizing then return end
    local rows = FitRows(height)
    if rows == dragRows then return end
    dragRows = rows
    DrawMain()
end)

local HISTORY_TOP, HISTORY_BOTTOM = 22, 18
local hist = CreateFrame("Frame", "LootRollsPlusHistory", main)
main.history = hist
hist:SetPoint("TOPLEFT")
hist:SetSize(HISTORY_WIDTH, MIN_WINDOW_HEIGHT)
hist:Hide()
tinsert(UISpecialFrames, "LootRollsPlusHistory")

StaticPopupDialogs["LOOTROLLSPLUS_CLEAR"] = {
    text = L.confirmClear,
    button1 = L.clear, button2 = CANCEL or "Cancel",
    OnAccept = function()
        wipe(days)
        wipe(dayKeys)
        wipe(activeEntries)
        if capture then capture:Reset() end
        charDB.importedInspector = true
        refresh()
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Izquierda: lista de dias. Derecha: loot del dia seleccionado.
local DAY_W = 88
local SCROLL_GUTTER = 23

local dayScroll = CreateFrame("ScrollFrame", "LootRollsPlusDayScroll", hist, "UIPanelScrollFrameTemplate")
dayScroll:SetPoint("TOPLEFT", 8, -HISTORY_TOP)
dayScroll.scrollBarHideable = true
local dayContent = CreateFrame("Frame", nil, dayScroll)
dayContent:SetSize(DAY_W, 1)
dayScroll:SetScrollChild(dayContent)

local scroll = CreateFrame("ScrollFrame", "LootRollsPlusHistoryScroll", hist, "UIPanelScrollFrameTemplate")
scroll.scrollBarHideable = true
local content = CreateFrame("Frame", nil, scroll)
content:SetSize(HISTORY_WIDTH - DAY_W - 24, 1)
scroll:SetScrollChild(content)

local selectedDay
local dayButtons, histRows, visitHeaders = {}, {}, {}
local historyEmpty = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
historyEmpty:SetPoint("TOPLEFT", 3, -3)
historyEmpty:SetText(L.noRolls)

local function LayoutHistory()
    local viewport = math.max(1, hist:GetHeight() - HISTORY_TOP - HISTORY_BOTTOM)
    local datesOverflow = math.floor(dayContent:GetHeight() - viewport) > 0
    local itemOverflow = math.floor(content:GetHeight() - viewport) > 0
    local dateWidth = #dayKeys > 0 and dayContent:GetWidth() or 0
    local itemsLeft = 8 + dateWidth + (datesOverflow and SCROLL_GUTTER or 0) + (dateWidth > 0 and 4 or 0)
    local itemWidth = hist:GetWidth() - itemsLeft - 10 - (itemOverflow and SCROLL_GUTTER or 0)
    dayScroll:SetSize(math.max(1, dateWidth), viewport)
    dayScroll:SetShown(dateWidth > 0)
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", itemsLeft, -HISTORY_TOP)
    scroll:SetSize(itemWidth, viewport)
    content:SetWidth(itemWidth)
    if dayScroll.ScrollBar then dayScroll.ScrollBar:SetShown(datesOverflow) end
    if scroll.ScrollBar then scroll.ScrollBar:SetShown(itemOverflow) end
    if not datesOverflow then dayScroll:SetVerticalScroll(0) end
    if not itemOverflow then scroll:SetVerticalScroll(0) end
    for _, header in ipairs(visitHeaders) do
        if header:IsShown() then header:SetWidth(itemWidth - 4) end
    end
    for _, row in ipairs(histRows) do
        if row:IsShown() then row:SetWidth(itemWidth) end
    end
end

local function FitHistory()
    hist:SetHeight(main:GetHeight())
    LayoutHistory()
end

local function ApplyHistorySize()
    main:SetResizeBounds(HISTORY_WIDTH, MIN_WINDOW_HEIGHT, HISTORY_WIDTH, WindowHeightLimit())
    main:SetWidth(HISTORY_WIDTH)
    hist:SetWidth(HISTORY_WIDTH)
end
local historyGrip = CreateResizeGrip(hist, "LootRollsPlusHistoryResizeGrip")
historyGrip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not db then return end
    hist.sizing = true
    main:StartSizing("BOTTOM")
end)
local function StopHistorySizing()
    if not hist.sizing then return end
    main:StopMovingOrSizing()
    if hist:IsVisible() then KeepMainTopRight() end
    hist.sizing = nil
    db.windowHeight = main:GetHeight()
    SaveMainPosition()
end
historyGrip:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then
        StopHistorySizing()
    elseif button == "RightButton" and db and not hist.sizing then
        db.windowHeight = nil
        ApplyWindowHeight()
        FitHistory()
    end
end)
historyGrip:SetScript("OnHide", StopHistorySizing)
historyGrip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(Label("Drag to adjust History height", "Перетащи, чтобы изменить высоту истории"))
    GameTooltip:AddLine(Label("Right-click for automatic height", "ПКМ возвращает автоматическую высоту"))
    GameTooltip:Show()
end)
historyGrip:SetScript("OnLeave", ReleaseTooltip)

local function DayText(key, color)
    return DayLabel(key) .. (color and " |cff808080(" or " (") .. #days[key] .. (color and ")|r" or ")")
end

local function FitDates()
    local maxWidth = 1
    for _, b in ipairs(dayButtons) do
        if b:IsShown() then
            local width = b.text.GetUnboundedStringWidthForText and b.text:GetUnboundedStringWidthForText(DayText(b.key))
            maxWidth = math.max(maxWidth, finite(width) and math.ceil(width) + 8 or DAY_W)
        end
    end
    maxWidth = math.min(106, maxWidth)
    dayContent:SetWidth(maxWidth)
    for _, b in ipairs(dayButtons) do
        if b:IsShown() then b:SetWidth(maxWidth) end
    end
end

local function EnsureSelected()
    if not (selectedDay and days[selectedDay]) then
        local nextDay = dayKeys[#dayKeys]
        if nextDay ~= selectedDay then
            selectedDay = nextDay
            scroll:SetVerticalScroll(0)
            return true
        end
    end
end

local function BuildEntries()
    local entries = selectedDay and days[selectedDay]
    local groups, byVisit = {}, {}
    local fullName, firstName, playerClass
    if hist.myWins.active then
        fullName, firstName = ns.GetLootPlayerNames("player")
        local _, class = UnitClass("player")
        playerClass = class
    end
    for i = entries and #entries or 0, 1, -1 do
        local e = entries[i]
        if not hist.myWins.active or ns.History.IsPlayerWin(e, fullName, firstName, playerClass) then
            local key = e.visit and e.visit.id or (e.legacy and "legacy" or "outside")
            local group = byVisit[key]
            if not group then
                group = { visit = e.visit, imported = e.legacy, entries = {} }
                byVisit[key] = group
                groups[#groups + 1] = group
            end
            group.entries[#group.entries + 1] = e
        end
    end

    local rowIndex, headerIndex, offset = 0, 0, 0
    for groupIndex, group in ipairs(groups) do
        if groupIndex > 1 then offset = offset + 4 end
        if group.visit or not group.imported then
            headerIndex = headerIndex + 1
            local header = visitHeaders[headerIndex]
            if not header then
                header = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                header:SetJustifyH("LEFT")
                header:SetWidth(content:GetWidth() - 4)
                header:SetWordWrap(false)
                visitHeaders[headerIndex] = header
            end
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", 3, -offset)
            header:SetText(group.visit and (MarkupText(group.visit.name) .. " · " .. date("%H:%M", group.visit.startedAt))
                or OUTSIDE)
            header:Show()
            offset = offset + ROW_H + 4
        end
        for _, e in ipairs(group.entries) do
            rowIndex = rowIndex + 1
            local row = histRows[rowIndex]
            if not row then
                row = MakeRow(content, content:GetWidth())
                histRows[rowIndex] = row
            end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -offset)
            FillRow(row, e)
            local item = "|cff9a9a9a" .. date("%H:%M", e.t) .. "|r " .. e.link
            local source = ItemLine(e)
            if source then item = item .. " |cff9a9a9a· " .. MarkupText(source) .. "|r" end
            row.left:SetText(item)
            offset = offset + ROW_H
        end
    end
    for index = rowIndex + 1, #histRows do
        histRows[index].entry = nil
        histRows[index]:Hide()
    end
    for index = headerIndex + 1, #visitHeaders do visitHeaders[index]:Hide() end
    historyEmpty:SetText(hist.myWins.active and Label("No wins on this date", "В этот день выигрышей нет") or L.noRolls)
    historyEmpty:SetShown(rowIndex == 0)
    content:SetHeight(math.max(offset, ROW_H))
end

hist.myWins = TextButton(Label("My wins", "Мои выигрыши"), hist, "LootRollsPlusMyWins")
hist.myWins:SetPoint("RIGHT", optBtn, "LEFT", -4, 0)
hist.myWins:SetScript("OnClick", function(self)
    self.active = not self.active
    PaintButton(self)
    scroll:SetVerticalScroll(0)
    BuildEntries()
    FitHistory()
end)

local function SelectDay(key)
    selectedDay = key
    BuildDayList()
    BuildEntries()
    FitHistory()
    scroll:SetVerticalScroll(0)
end

BuildDayList = function()
    if not hist:IsShown() then return end
    for _, b in ipairs(dayButtons) do b:Hide() end
    for i = #dayKeys, 1, -1 do
        local idx = #dayKeys - i + 1
        local b = dayButtons[idx]
        if not b then
            b = CreateFrame("Button", nil, dayContent)
            b:SetSize(DAY_W, ROW_H)
            b:RegisterForClicks("LeftButtonUp")
            b:SetPoint("TOPLEFT", 0, -(idx - 1) * ROW_H)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b.sel = b:CreateTexture(nil, "BACKGROUND")
            b.sel:SetAllPoints()
            b.sel:SetColorTexture(0.2, 0.5, 1, 0.3)
            b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            b:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
            b:SetScript("OnClick", function(self) SelectDay(self.key) end)
            dayButtons[idx] = b
        end
        b.key = dayKeys[i]
        b.text:SetText(DayText(b.key, true))
        b.sel:SetShown(b.key == selectedDay)
        b:Show()
    end
    FitDates()
    dayContent:SetHeight(math.max(#dayKeys * ROW_H, 1))
end

-- Al llegar una tirada solo se actualiza el contador de ese dia
local function UpdateDayCount(key)
    for _, b in ipairs(dayButtons) do
        if b:IsShown() and b.key == key then
            b.text:SetText(DayText(key, true))
            FitDates()
            return
        end
    end
end

histBtn:SetScript("OnClick", function()
    main.options:Hide()
    if hist:IsShown() then
        hist:Hide()
    else
        main:Show()
        KeepMainTopRight()
        hist:Show()
        ApplyHistorySize()
        EnsureSelected()
        BuildDayList()
        BuildEntries()
        FitHistory()
    end
end)

local details = CreateFrame("Frame", "LootRollsPlusDetails", UIParent)
local detailAnchor
details:Hide()
tinsert(UISpecialFrames, "LootRollsPlusDetails")

local function TooltipText(fontString)
    local value = fontString and fontString:GetText()
    if not isSecret(value) and type(value) == "string" then return value end
end

local function ComparisonTooltip(name)
    local tooltip = CreateFrame("GameTooltip", name, details, "GameTooltipTemplate")
    tooltip:SetClampedToScreen(true)
    tooltip:EnableMouse(true)
    local addLine = tooltip.AddLine
    local suppressRewardLocation
    tooltip.AddLine = function(self, text, ...)
        if not isSecret(text) and type(text) == "string" then
            local label = text:gsub("^|T[^|]+|t ", ""):gsub("^|A[^|]+|a ", "")
            -- Dungeon Assistant appends a spacer, the reward, and sometimes a dungeon name.
            if label:match("^Reward from .") then
                local count = self:NumLines()
                local previous = count > 0 and self:GetLeftLine(count)
                if TooltipText(previous) == " " then previous:SetText("") end
                suppressRewardLocation = label ~= text
                return
            end
            if suppressRewardLocation and text:match("^     %S") then
                suppressRewardLocation = nil
                return
            end
        end
        suppressRewardLocation = nil
        return addLine(self, text, ...)
    end
    tooltip:Hide()
    return tooltip
end

local droppedTooltip = ComparisonTooltip("LootRollsPlusDroppedTooltip")
local equippedTooltip = ComparisonTooltip("LootRollsPlusEquippedTooltip")

local disenchantLabels = {
    ["Disenchant"] = true, ["Распыление"] = true, ["Désenchanter"] = true,
    ["Desencantar"] = true, ["Entzaubern"] = true, ["마력 추출"] = true, ["分解"] = true,
}

local function ReadMastercraftDisenchant(owner, link)
    local isLoaded = C_AddOns and C_AddOns.IsAddOnLoaded
    if type(isLoaded) ~= "function" then return end
    local ok, _, loaded = pcall(isLoaded, "Mastercraft")
    if not ok or isSecret(loaded) or loaded ~= true then return end
    local identity = ns.GetItemLinkIdentity(link)
    if not identity then return end
    local _, displayed = GameTooltip:GetItem()
    if not GameTooltip:IsOwned(owner) or ns.GetItemLinkIdentity(displayed) ~= identity then
        GameTooltip:SetOwner(owner, "ANCHOR_NONE")
        GameTooltip:SetHyperlink(link)
        _, displayed = GameTooltip:GetItem()
        if ns.GetItemLinkIdentity(displayed) ~= identity then return nil, "uncached" end
    end

    -- Inspect only the Mastercraft section of the matching stock tooltip.
    local lastLine
    local lineCount = GameTooltip:NumLines()
    if not finite(lineCount) then return end
    for i = 1, lineCount do
        local left = _G["GameTooltipTextLeft" .. i]
        local label = TooltipText(left)
        if label == "|cff4da6ffMastercraft|r" then
            lastLine = i + 5
        elseif lastLine and i <= lastLine and label then
            local base = label:match("^(.-) %([^()]+%)$") or label:match("^(.-)（.+）$") or label
            if disenchantLabels[base] then
                local value = TooltipText(_G["GameTooltipTextRight" .. i])
                local r, g, b = left:GetTextColor()
                if not (isSecret(r) or isSecret(g) or isSecret(b)) and type(r) == "number"
                    and type(g) == "number" and type(b) == "number" and math.abs(r - 0.60) < 0.015
                    and math.abs(g - 0.63) < 0.015 and math.abs(b - 0.70) < 0.015
                    and value and value:match("^~%s*%d") and #value <= 256 and not value:find("[%c]")
                    and not value:find("|H", 1, true) then
                    return { value = value, partial = label ~= base }
                end
            end
        end
    end
    return nil, "unpriced"
end

local function CoinPrice(copper)
    if isSecret(copper) or type(copper) ~= "number" or not (copper >= 1 and copper < math.huge) then return end
    local formatCoins = C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString
    if not formatCoins then return end
    local ok, coins = pcall(formatCoins, math.floor(copper))
    if ok and not isSecret(coins) and type(coins) == "string" and coins ~= "" then
        return coins
    end
end

local function AddSalePrices(tooltip, link, vendor)
    if vendor then tooltip:AddDoubleLine(Label("Vendor", "Торговец"), vendor) end
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    local getPrice = api and api.GetAuctionPriceByItemLink
    if type(getPrice) ~= "function" then return end
    local ok, copper = pcall(getPrice, ADDON, link)
    local auction = ok and CoinPrice(copper)
    if auction then tooltip:AddDoubleLine(Label("Auction", "Аукцион"), auction) end
end

local function ShowComparisonTooltip(tooltip, link, status, disenchant)
    if tooltip:IsShown() and tooltip.shownLink == link and tooltip.shownStatus == status
        and tooltip.shownDisenchant == disenchant then return end
    tooltip.shownLink, tooltip.shownStatus, tooltip.shownDisenchant = link, status, disenchant
    tooltip:SetOwner(details, "ANCHOR_NONE")
    tooltip:ClearLines()
    local loaded
    if link and (status or tooltip == droppedTooltip) then
        local vendor
        if tooltip == droppedTooltip and C_Item and C_Item.GetItemInfo then
            vendor = CoinPrice(select(11, C_Item.GetItemInfo(link)))
        end
        local sellPrice = Enum and Enum.TooltipDataLineType and Enum.TooltipDataLineType.SellPrice
        loaded = tooltip:ProcessInfo({
            getterName = "GetHyperlink",
            getterArgs = { link },
            excludeLines = vendor and sellPrice and { sellPrice } or nil,
            tooltipPostCall = function(self)
                if self == droppedTooltip then AddSalePrices(self, link, vendor) end
                if disenchant then
                    local label = disenchant.partial and Label("Disenchant (partial)", "Распыление (частично)")
                        or Label("Disenchant", "Распыление")
                    self:AddDoubleLine(label, disenchant.value)
                end
                if status then self:AddLine(status, 0.72, 0.72, 0.72, true) end
            end,
        })
    elseif link then
        loaded = tooltip:SetHyperlink(link)
    else
        tooltip:SetText(status, 1, 1, 1, 1, true)
    end
    if loaded == false then
        tooltip.shownLink = nil
        if tooltip.requestedLink ~= link or tooltip.waitingForCapacity then
            tooltip.requestedLink = link
            local _, full = RequestItemData(link)
            tooltip.waitingForCapacity = full
        end
        tooltip:SetOwner(details, "ANCHOR_NONE")
        local message = (pendingItems[link] or tooltip.waitingForCapacity) and Label("Loading item…", "Загрузка предмета…")
            or Label("Item data unavailable", "Данные предмета недоступны")
        tooltip:SetText(message, 1, 1, 1, 1, true)
    else
        tooltip.requestedLink, tooltip.waitingForCapacity = nil, nil
    end
    tooltip:Show()
end

local detailEntry, detailDisenchant, detailPriceRetry, liveComparison
local inspector = ns.NewInspect()
local selectedPlayer, selectedClass, inspectionState, inspectionAttempt
comparisonNeedsItem = function(link, request)
    if not details:IsShown() then return false end
    if not link then
        return droppedTooltip.waitingForCapacity or equippedTooltip.waitingForCapacity
            or detailPriceRetry == "uncached"
            or (inspectionAttempt and inspectionAttempt.waitingForCapacity)
    end
    return detailPriceRetry == request
        or droppedTooltip.requestedLink == link or equippedTooltip.requestedLink == link
        or (inspectionState == "itemPending" and detailEntry and detailEntry.link == link)
end
local inspectedGUIDs = setmetatable({}, { __mode = "k" })
local inspectionReplacements = setmetatable({}, {__mode = "k"})
local StageInspectionTransfer
details:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
end)
details:SetScript("OnHide", function(self)
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    detailEntry, selectedPlayer, selectedClass, inspectionState = nil, nil, nil, nil
    inspectionAttempt = nil
    detailDisenchant, detailPriceRetry = nil, nil
    liveComparison = nil
    droppedTooltip:Hide()
    equippedTooltip:Hide()
    droppedTooltip.requestedLink, equippedTooltip.requestedLink = nil, nil
    droppedTooltip.waitingForCapacity, equippedTooltip.waitingForCapacity = nil, nil
    equippedTooltip.snapshot, equippedTooltip.slot, equippedTooltip.canSwitchSlot = nil, nil, nil
end)

local inspectionMessages = {
    loading = Label("Inspecting…", "Осмотр…"),
    itemPending = Label("Loading item…", "Загрузка предмета…"),
    absent = Label("Player is unavailable in your group", "Игрок недоступен в текущей группе"),
    unsupported = Label("No equipment slot for this drop", "Для предмета нет подходящего слота"),
    unavailable = Label("Cannot inspect this player right now", "Игрок сейчас недоступен для осмотра"),
    combat = Label("Try again after combat", "Повтори после боя"),
    timeout = Label("No inspect response. Click to try again.", "Игра не ответила на осмотр. Нажми ещё раз."),
    busy = Label("Inspection in progress. Try again shortly.", "Идёт осмотр. Повтори через несколько секунд."),
    inspectOpen = Label("Close the WoW Inspect window first", "Сначала закрой стандартное окно осмотра"),
    noData = Label("No item data for these slots", "Нет данных о предметах в этих слотах"),
    ambiguous = Label("Several participants have this name", "У нескольких участников одинаковое имя"),
}
local function PlayerListPosition()
    local position = db and db.playerListPosition
    if position == "above" or position == "below" then return position end
    return "auto"
end

local function PlaceLiveEquipped(anchor, card, roster)
    local view = ns.LiveView
    local obstacles = view.VisiblePawnRects()
    local pawnVisible = #obstacles > 0
    for _, prompt in ipairs(view.VisiblePromptRects()) do obstacles[#obstacles + 1] = prompt end
    if #obstacles == 0 then return false end
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    local width, height = equippedTooltip:GetWidth(), equippedTooltip:GetHeight()
    local coordinate = view.ScreenCoordinate
    local right, top = coordinate(anchor, "GetRight"), coordinate(anchor, "GetTop")
    if not (finite(screenWidth) and finite(screenHeight) and finite(width) and finite(height)
        and width > 0 and height > 0 and width <= screenWidth and height <= screenHeight
        and finite(right) and finite(top)) then return false end

    local gap = 7
    local rightTop = math.max(height + gap, math.min(top, screenHeight - gap))
    local bottom = coordinate(anchor, "GetBottom")
    local function Rect(x, y)
        return {left = x, right = x + width, bottom = y - height, top = y}
    end
    if not pawnVisible then
        local x = math.max(0, math.min(right + gap, screenWidth - width))
        local y = math.max(height, math.min(top, screenHeight))
        if right + gap + width > screenWidth and bottom and bottom >= height + 2 * gap then
            x, y = screenWidth - width - gap, bottom - gap
        end
        if not view.RectOverlaps(Rect(x, y), obstacles) then return false end
    end
    local function Try(x, y)
        if x < gap or x + width > screenWidth - gap or y > screenHeight - gap or y - height < gap then return false end
        if view.RectOverlaps(Rect(x, y), obstacles) then return false end
        equippedTooltip:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
        return true
    end
    if Try(right + gap, rightTop) then return true end

    local left, highest = coordinate(anchor, "GetLeft"), top
    local function Extend(frame)
        if not frame or not frame:IsShown() then return end
        local x, low, high = coordinate(frame, "GetLeft"), coordinate(frame, "GetBottom"), coordinate(frame, "GetTop")
        if finite(x) then left = left and math.min(left, x) or x end
        if finite(low) then bottom = bottom and math.min(bottom, low) or low end
        if finite(high) then highest = math.max(highest, high) end
    end
    Extend(card and card.anchor)
    Extend(card)
    Extend(roster)
    if left and Try(left - gap - width, rightTop) then return true end
    local x = math.max(gap, math.min(right + gap, screenWidth - width - gap))
    if bottom and Try(x, bottom - gap) then return true end
    if Try(x, highest + gap + height) then return true end

    local beyond = right + gap
    for _, obstacle in ipairs(obstacles) do
        if obstacle.top > rightTop - height and obstacle.bottom < rightTop then
            beyond = math.max(beyond, obstacle.right + gap)
        end
    end
    if Try(beyond, rightTop) then return true end
    for _, rect in ipairs(obstacles) do
        if x < rect.right and rect.left < x + width then
            highest = math.max(highest, rect.top)
            bottom = bottom and math.min(bottom, rect.bottom) or rect.bottom
        end
    end
    return Try(x, highest + gap + height) or (bottom and Try(x, bottom - gap))
end

PlaceComparison = function(anchor)
    if not detailAnchor or (anchor and detailAnchor ~= anchor) or not details:IsShown() then return end
    if liveComparison then
        local screenCoordinate = ns.LiveView.ScreenCoordinate
        local right = screenCoordinate(detailAnchor, "GetRight")
        local bottom = screenCoordinate(detailAnchor, "GetBottom")
        local screenWidth, width = UIParent:GetWidth(), equippedTooltip:GetWidth()
        local height = equippedTooltip:GetHeight()
        equippedTooltip:ClearAllPoints()
        if not liveComparison.demo and PlaceLiveEquipped(detailAnchor, liveComparison.card, liveComparison.roster) then return end
        if finite(right) and finite(screenWidth) and finite(width) and right + width + 7 > screenWidth
            and finite(bottom) and finite(height) and bottom >= height + 14 then
            equippedTooltip:SetPoint("TOPRIGHT", UIParent, "BOTTOMRIGHT", -7, bottom - 7)
        else
            equippedTooltip:SetPoint("TOPLEFT", detailAnchor, "TOPRIGHT", 7, 0)
        end
        return
    end
    local offset = detailAnchor:GetWidth() / 2
    local left, screenWidth = detailAnchor:GetLeft(), UIParent:GetWidth()
    local leftWidth, rightWidth = droppedTooltip:GetWidth(), equippedTooltip:GetWidth()
    leftWidth, rightWidth = finite(leftWidth) and leftWidth or 0, finite(rightWidth) and rightWidth or 0
    local position = PlayerListPosition()
    local below, top, screenHeight = detailAnchor:GetBottom(), detailAnchor:GetTop(), UIParent:GetHeight()
    local dropHeight, equippedHeight = droppedTooltip:GetHeight(), equippedTooltip:GetHeight()
    if finite(left) and finite(screenWidth) and leftWidth + rightWidth + 16 <= screenWidth then
        offset = math.max(leftWidth + 8 - left, math.min(screenWidth - rightWidth - 8 - left, offset))
    elseif finite(left) and finite(screenWidth) and leftWidth > 0 and rightWidth > 0
        and finite(below) and finite(top) and finite(screenHeight)
        and finite(dropHeight) and dropHeight > 0 and finite(equippedHeight) and equippedHeight > 0 then
        local stackWidth = math.max(leftWidth, rightWidth)
        local stackHeight = dropHeight + equippedHeight + 8
        if stackWidth <= screenWidth and stackHeight <= screenHeight then
            local roomAbove, roomBelow = screenHeight - top - 5, below - 5
            local stackAbove = position == "above"
                or (position == "auto" and roomBelow < stackHeight and roomAbove > roomBelow)
            if stackAbove and roomAbove < stackHeight and roomBelow >= stackHeight then
                stackAbove = false
            elseif not stackAbove and roomBelow < stackHeight and roomAbove >= stackHeight then
                stackAbove = true
            end
            local x = math.max(0, math.min(screenWidth - stackWidth, left + offset - stackWidth / 2))
            local y = stackAbove and top + 5 or below - 5 - stackHeight
            y = math.max(0, math.min(screenHeight - stackHeight, y))
            droppedTooltip:ClearAllPoints()
            equippedTooltip:ClearAllPoints()
            droppedTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y + equippedHeight + 8)
            equippedTooltip:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            return
        end
    end
    local above = position == "above"
    if position == "auto" then
        local height = math.max(finite(dropHeight) and dropHeight or 0, finite(equippedHeight) and equippedHeight or 0)
        above = finite(below) and finite(top) and finite(screenHeight) and below < height + 5 and screenHeight - top > below
    end
    local edge, gap = above and "TOPLEFT" or "BOTTOMLEFT", above and 5 or -5
    droppedTooltip:ClearAllPoints()
    equippedTooltip:ClearAllPoints()
    droppedTooltip:SetPoint(above and "BOTTOMRIGHT" or "TOPRIGHT", detailAnchor, edge, offset - 4, gap)
    equippedTooltip:SetPoint(above and "BOTTOMLEFT" or "TOPLEFT", detailAnchor, edge, offset + 4, gap)
end

local placementQueued
local function QueueComparisonPlacement()
    if placementQueued then return end
    placementQueued = true
    C_Timer.After(0, function()
        placementQueued = nil
        PlaceComparison()
    end)
end
droppedTooltip:SetScript("OnSizeChanged", QueueComparisonPlacement)
equippedTooltip:SetScript("OnSizeChanged", QueueComparisonPlacement)

hist:SetScript("OnSizeChanged", function(self)
    if not self:IsShown() then return end
    LayoutHistory()
    if detailAnchor == hist then PlaceComparison() end
end)
local function ComparisonParticipant(entry, name)
    if entry.ambiguous then return false, "ambiguous" end
    local found, class
    for _, roll in ipairs(entry.rolls) do
        if roll.name == name then
            if found then return false, "ambiguous" end
            found, class = true, roll.class
        end
    end
    if entry.winner == name then
        if class and entry.winnerClass and class ~= entry.winnerClass then return false, "ambiguous" end
        return true, class or entry.winnerClass
    end
    return found == true, class
end

local function DrawEquipped(snapshot, status, state, historical)
    local links = snapshot and snapshot.links
    local empty = snapshot and snapshot.empty
    local firstKnown = (links and links[1]) or (empty and empty[1])
    local secondKnown = (links and links[2]) or (empty and empty[2])
    if equippedTooltip.snapshot ~= snapshot then
        equippedTooltip.snapshot = snapshot
        if links and not links[1] and links[2] then
            equippedTooltip.slot = 2
        else
            equippedTooltip.slot = not firstKnown and secondKnown and 2 or 1
        end
    end
    local slot = equippedTooltip.slot or 1
    equippedTooltip.canSwitchSlot = firstKnown and secondKnown and snapshot.count == 2
    local equipped = links and links[slot]
    local equippedStatus = status
    if equipped then
        equippedStatus = nil
        if snapshot.atDrop or historical or state ~= "ready" then
            if snapshot.atDrop then
                equippedStatus = Label("Inspected near the roll", "Осмотрено около времени розыгрыша")
            elseif state == "ready" then
                equippedStatus = Label("Equipped now", "Надето сейчас")
            else
                equippedStatus = Label("Last inspected gear", "Экипировка при последнем осмотре")
            end
            local at = snapshot.at
            if type(at) == "number" and at > 0 and at < math.huge then
                local ok, timestamp = pcall(date, L.dateFmt .. " %H:%M", at)
                if ok and timestamp then equippedStatus = equippedStatus .. " · " .. timestamp end
            end
        end
    elseif empty and empty[slot] then
        equippedStatus = Label("Equipment slot is empty", "Слот экипировки пуст")
    elseif not equippedStatus then
        equippedStatus = inspectionMessages.noData
    end
    if equippedTooltip.canSwitchSlot then
        local changeSlot = Label("Slot %d/2 · Click to switch", "Слот %d/2 · Нажми, чтобы сменить"):format(slot)
        equippedStatus = equippedStatus and (equippedStatus .. "\n" .. changeSlot) or changeSlot
    end
    ShowComparisonTooltip(equippedTooltip, equipped, equippedStatus)
end

local function SavedInspection(entry, name, class, guid)
    local snapshot = entry.inspections and entry.inspections[name]
    if snapshot and snapshot.class == class and guid ~= false
        and (not guid or guid == (inspectedGUIDs[snapshot] or snapshot.guid)) then return snapshot end
end

local function SnapshotSlot(snapshot, slot)
    local link = snapshot.links and snapshot.links[slot]
    if link then return link end
    if snapshot.empty and snapshot.empty[slot] then return false end
end

local function CompleteDropInspection(snapshot)
    return snapshot and snapshot.atDrop
        and (snapshot.count ~= 2 or (SnapshotSlot(snapshot, 1) ~= nil and SnapshotSlot(snapshot, 2) ~= nil))
end

local function CompletesDropInspection(previous, current)
    if CompleteDropInspection(previous) or not CompleteDropInspection(current) or current.count ~= previous.count then
        return false
    end
    -- Keep the earlier observation if the player changed any known slot.
    for slot = 1, previous.count do
        local before = SnapshotSlot(previous, slot)
        if before ~= nil and before ~= SnapshotSlot(current, slot) then return false end
    end
    return true
end

local function SaveInspection(entry, name, class, expectedGUID, snapshot, inspectedGUID, atDrop)
    local unique, actualClass = ComparisonParticipant(entry, name)
    local currentGUID = capture:GetParticipantGUID(entry, name)
    local matches = unique and actualClass == class and currentGUID ~= false
        and (not expectedGUID or currentGUID == expectedGUID)
        and (not snapshot or not currentGUID or inspectedGUID == currentGUID)
    if snapshot and matches then
        snapshot.class, snapshot.atDrop = class, atDrop
        snapshot.guid = atDrop and inspectedGUID or nil
        inspectedGUIDs[snapshot] = inspectedGUID
        if HasRoll(entry) then
            local existing = SavedInspection(entry, name, class, currentGUID)
            if not existing or not existing.atDrop or CompletesDropInspection(existing, snapshot) then
                entry.inspections = entry.inspections or {}
                entry.inspections[name] = snapshot
            end
        elseif snapshot.guid then
            local replacement = inspectionReplacements[entry]
            if replacement and HasRoll(replacement) then StageInspectionTransfer(replacement, name, snapshot) end
        end
    end
    return matches
end

local function DrawComparison()
    if not details:IsShown() then return end
    if liveComparison then
        local result = liveComparison
        DrawEquipped(result.snapshot, inspectionMessages[result.state], result.state)
        PlaceComparison()
        return
    end
    if not detailEntry then return end
    if not HasRoll(detailEntry) then
        details:Hide()
        return
    end
    local _, _, displayedPlayer, displayedClass = StatusText(detailEntry)
    if displayedPlayer ~= selectedPlayer or displayedClass ~= selectedClass then
        details:Hide()
        return
    end
    local snapshot
    local status = Label("No player to compare", "Нет игрока для сравнения")
    if selectedPlayer then
        local unique, class = ComparisonParticipant(detailEntry, selectedPlayer)
        local expectedGUID = capture:GetParticipantGUID(detailEntry, selectedPlayer)
        snapshot = unique and class == selectedClass and SavedInspection(detailEntry, selectedPlayer, class, expectedGUID)
        status = inspectionMessages[inspectionState]
        if inspectionState == "itemPending" and not pendingItems[detailEntry.link]
            and not (inspectionAttempt and inspectionAttempt.waitingForCapacity) then
            status = Label("Item data unavailable", "Данные предмета недоступны")
        end
        if not unique or class ~= selectedClass or expectedGUID == false then
            status = inspectionMessages[class == "ambiguous" and "ambiguous" or "unavailable"]
        end
    end
    if type(detailPriceRetry) == "table" and detailPriceRetry.loaded and not GameTooltip:IsShown() then
        detailPriceRetry = nil
        detailDisenchant = ReadMastercraftDisenchant(details, detailEntry.link)
        ReleaseTooltip(details)
    end
    ShowComparisonTooltip(droppedTooltip, detailEntry.link, nil, detailDisenchant)
    if detailPriceRetry == "unpriced" and not droppedTooltip.waitingForCapacity then
        detailPriceRetry = droppedTooltip.requestedLink and pendingItems[droppedTooltip.requestedLink] or nil
    end
    DrawEquipped(snapshot, status, inspectionState, true)
    PlaceComparison()
end

GameTooltip:HookScript("OnHide", function()
    if type(detailPriceRetry) == "table" and detailPriceRetry.loaded then queueRefresh() end
end)

equippedTooltip:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.canSwitchSlot then return end
    self.slot = 3 - self.slot
    DrawComparison()
end)

local function ComparePlayer(name, class, attempt)
    if not detailEntry or not name then return end
    local entry = detailEntry
    attempt = attempt or {expires = GetTime() + 6}
    inspectionAttempt = attempt
    selectedPlayer, selectedClass = name, class
    local unique, currentClass = ComparisonParticipant(entry, name)
    local expectedGUID = capture:GetParticipantGUID(entry, name)
    local saved = SavedInspection(entry, name, class, expectedGUID)
    if not unique or currentClass ~= class then
        inspectionState = currentClass == "ambiguous" and "ambiguous" or "unavailable"
    elseif expectedGUID == false then
        inspectionState = "unavailable"
    elseif saved and saved.atDrop then
        inspectionState = "ready"
    else
        local _, pending = ns.HasInspectSlot(entry.link)
        if pending then
            inspectionState = "itemPending"
            local _, full = RequestItemData(entry.link)
            attempt.waitingForCapacity = full
            DrawComparison()
            return
        end
        inspectionState = nil
        local requestState = inspector:Request(entry.link, name, class, function(status, snapshot, inspectedGUID)
            local matches = SaveInspection(entry, name, class, expectedGUID, snapshot, inspectedGUID)
            if inspectionAttempt == attempt then
                inspectionState = matches and status or "unavailable"
                DrawComparison()
            end
        end, expectedGUID)
        if not requestState then return end
        inspectionState = requestState
        if requestState == "busy" and GetTime() + 0.5 <= attempt.expires then
            C_Timer.After(0.5, function()
                if inspectionAttempt ~= attempt or GetTime() > attempt.expires then return end
                DrawComparison()
                if inspectionAttempt == attempt then ComparePlayer(name, class, attempt) end
            end)
        end
    end
    DrawComparison()
end

toggleDetails = function(entry, fromMain, owner)
    local anchor = fromMain and main or hist
    if details:IsShown() and detailEntry == entry and detailAnchor == anchor then
        details:Hide()
    else
        if liveComparison then details:Hide() end
        detailAnchor = anchor
        detailEntry, selectedPlayer, selectedClass, inspectionState = entry, nil, nil, nil
        inspectionAttempt = nil
        local priceState
        detailDisenchant, priceState = ReadMastercraftDisenchant(owner, entry.link)
        if priceState == "uncached" then
            local request, full = RequestItemData(entry.link)
            detailPriceRetry = full and "uncached" or request
        else
            detailPriceRetry = priceState
        end
        ReleaseTooltip(owner)
        details:Show()
        if hoverRow then ReleaseTooltip(hoverRow) end
        local _, _, name, class = StatusText(entry)
        if name then ComparePlayer(name, class) else DrawComparison() end
    end
end

local function LiveComparisonCard(comparison)
    local card = ns.LiveView:FindCard(comparison.id, comparison.link)
    if not card or not card.entry.canInspect or card.entry.demo ~= comparison.demo then return end
    local entry = card.entry
    if entry.allPassed then return end
    local matches = 0
    for _, player in ipairs(entry.winner and {entry.winner} or entry.players) do
        if player.name == comparison.name and (not comparison.guid or player.guid == comparison.guid) then
            if player.class ~= comparison.class or player.guid ~= comparison.guid then return end
            matches = matches + 1
        end
    end
    if matches == 1 then return card end
end

local function InspectLivePlayer(comparison, player, retries)
    if liveComparison ~= comparison then return end
    if not LiveComparisonCard(comparison) then details:Hide() return end
    if player.guid == false then
        comparison.state = "unavailable"
        DrawComparison()
        return
    end
    local state = inspector:Request(comparison.link, player.name, player.class, function(result, snapshot)
        if liveComparison ~= comparison then return end
        if not LiveComparisonCard(comparison) then details:Hide() return end
        comparison.state, comparison.snapshot = result, snapshot
        DrawComparison()
    end, player.guid)
    if not state then return end
    if state == "busy" and retries > 0 then
        comparison.state = "loading"
        C_Timer.After(0.5, function() InspectLivePlayer(comparison, player, retries - 1) end)
    else
        comparison.state = state
    end
    DrawComparison()
end

ns.LiveView.OnPlayerClick = function(card, entry, player, owner)
    if not entry.canInspect then return end
    local previous = liveComparison
    details:Hide()
    if previous and previous.id == entry.id and previous.link == entry.link
        and previous.name == player.name and previous.guid == player.guid and previous.class == player.class then return end

    local panel = owner.livePanel
    local comparison = { id = entry.id, link = entry.link, name = player.name, guid = player.guid, class = player.class, demo = entry.demo,
        card = card, roster = panel ~= card and panel or nil }
    liveComparison = comparison
    detailAnchor = ns.LiveView:EquippedAnchor(card, comparison.roster)
    details:Show()
    if entry.demo then
        if player.demoEquipped then
            comparison.snapshot = { links = { player.demoEquipped } }
            comparison.state = "ready"
        else
            comparison.snapshot = { empty = { true }, count = 1 }
            comparison.state = "ready"
        end
    else
        if not player.guid then
            local count = 0
            for _, candidate in ipairs(entry.players) do
                if candidate.name == player.name then count = count + 1 end
            end
            if count > 1 then
                comparison.state = "ambiguous"
                DrawComparison()
                return
            end
        end
        InspectLivePlayer(comparison, player, 14)
        return
    end
    DrawComparison()
end

details:SetScript("OnEvent", function(self, _, button)
    if button ~= "LeftButton" and button ~= "RightButton" and button ~= "MiddleButton" then return end
    local rollClick = button == "LeftButton" and not IsShiftKeyDown()
    for _, focus in ipairs(GetMouseFoci()) do
        while focus do
            if focus == self then return end
            local parent = focus:GetParent()
            -- Roll rows handle switching or closing on mouse-up.
            if rollClick and (parent == main or parent == content) and focus.entry then return end
            if rollClick and focus.livePlayer and focus.liveCard and focus.liveCard.entry
                and focus.liveCard.entry.canInspect then return end
            focus = parent
        end
    end
    self:Hide()
end)

local function HideAttachedDetails(anchor)
    if detailAnchor == anchor then details:Hide() end
end
main:SetScript("OnHide", function(self)
    self.options:Hide()
    hist:Hide()
    HideAttachedDetails(self)
end)
hist:SetScript("OnShow", function(self)
    self:RegisterEvent("GLOBAL_MOUSE_DOWN")
    histBtn.active = true
    PaintButton(histBtn)
    HideAttachedDetails(main)
    HideMainList()
end)
hist:SetScript("OnHide", function(self)
    if self:IsShown() then self:Hide() end
    self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
    StopHistorySizing()
    HideAttachedDetails(self)
    histBtn.active = nil
    PaintButton(histBtn)
    main:SetResizeBounds(MAIN_WIDTH, MIN_WINDOW_HEIGHT, MAIN_WIDTH, WindowHeightLimit())
    main:SetWidth(MAIN_WIDTH)
    grip:Show()
    DrawMain()
    if main:IsShown() then UpdateVisibility() end
end)
hist:SetScript("OnEvent", function(self)
    DismissOutside(self, function(focus) return detailAnchor == self and focus == details end)
end)

refresh = function(key)
    -- Give a pinned tooltip first use of a freed request slot before redrawing the history rows.
    if comparisonNeedsItem() then
        if inspectionAttempt and inspectionAttempt.waitingForCapacity then
            local _, full = RequestItemData(detailEntry.link)
            inspectionAttempt.waitingForCapacity = full
        end
        if detailPriceRetry == "uncached"
            or (detailPriceRetry == "unpriced" and droppedTooltip.waitingForCapacity) then
            local request, full = RequestItemData(detailEntry.link)
            if not full then detailPriceRetry = request end
        end
        if droppedTooltip.waitingForCapacity then RequestItemData(droppedTooltip.requestedLink) end
        if equippedTooltip.waitingForCapacity then RequestItemData(equippedTooltip.requestedLink) end
    end
    DrawMain()
    if hist:IsShown() then
        local changedDay = EnsureSelected()
        if key and not changedDay then
            if key == selectedDay then BuildEntries() end
            UpdateDayCount(key)
        else
            BuildDayList()
            BuildEntries()
        end
        FitHistory()
    end
    if hoverRow then
        if hoverRow:IsVisible() and hoverRow.entry and GameTooltip:IsOwned(hoverRow) then
            ShowTooltip(hoverRow, hoverRow.entry)
        else
            ReleaseTooltip(hoverRow)
            hoverRow = nil
        end
    end
    DrawComparison()
    if inspectionState == "itemPending" and detailEntry then
        local _, pending = ns.HasInspectSlot(detailEntry.link)
        if not pending then
            ComparePlayer(selectedPlayer, selectedClass)
        end
    end
end

local refreshQueued, dirtyDay, dirtyLive
queueRefresh = function(key, withLive)
    dirtyLive = dirtyLive or withLive
    if refreshQueued then
        if dirtyDay ~= key then dirtyDay = nil end
        return
    end
    dirtyDay, refreshQueued = key, true
    C_Timer.After(0, function()
        local day, live = dirtyDay, dirtyLive
        dirtyDay, dirtyLive, refreshQueued = nil, nil, false
        refresh(day)
        if live and RenderLiveRolls then RenderLiveRolls() end
    end)
end

-- Visibilidad ---------------------------------------------------------------
-- db.hidden = ocultada a mano (/lrplus); db.hideSolo = ocultar fuera de grupo
local function SoloHidden()
    if not db.hideSolo then return false end
    local grouped = IsInGroup()
    return not isSecret(grouped) and grouped == false
end

UpdateVisibility = function()
    main:SetShown(not db.hidden and (main.options:IsShown() or not SoloHidden()))
end

local liveDemo
local function LiveItemHasSlot(link)
    local hasSlot, pending = ns.HasInspectSlot(link)
    if pending then RequestItemData(link) end
    return hasSlot
end

local function RefreshLiveComparisonAnchor()
    if not liveComparison then return end
    local card = LiveComparisonCard(liveComparison)
    if not card then details:Hide() return end
    liveComparison.card = card
    detailAnchor = ns.LiveView:EquippedAnchor(card, liveComparison.roster)
    QueueComparisonPlacement()
end
ns.LiveView.OnPlacementChanged = RefreshLiveComparisonAnchor
ns.LiveView.KeepRosterOpen = function(roster, focus)
    return liveComparison and liveComparison.roster == roster and focus == equippedTooltip
end

RenderLiveRolls = function()
    local rolls = ns.LiveSource:GetRolls()
    if #rolls > 0 then liveDemo = nil end
    local warnings = {}
    local function warning(link, player)
        if not link or not player.class or (player.choice ~= "need" and player.choice ~= "offspec") then return end
        local byClass = warnings[link]
        if not byClass then
            byClass = {}
            warnings[link] = byClass
        end
        local byLevel = byClass[player.class]
        if not byLevel then
            byLevel = {}
            byClass[player.class] = byLevel
        end
        local level = player.level or 0
        if byLevel[level] == nil then
            byLevel[level] = ClassifyGear(link, player.class, "need", player.level) or false
        end
        return byLevel[level] or nil
    end
    if liveDemo then
        local demo = liveDemo
        ns.LiveView:Render(ns.BuildLiveRolls(ns.LiveRollDemo(demo.raid, demo.step), warning), demo.raid, true)
    elseif db.liveRolls ~= false and #rolls > 0 then
        local raid = IsInRaid()
        ns.LiveView:Render(ns.BuildLiveRolls(rolls, warning, LiveItemHasSlot), not isSecret(raid) and raid == true, false)
    else
        ns.LiveView:Hide()
    end
    RefreshLiveComparisonAnchor()
end

local function AdvanceLiveDemo(demo)
    if liveDemo ~= demo then return end
    RenderLiveRolls()
    if liveDemo == demo and demo.step < (demo.raid and 34 or 4) then
        C_Timer.After(0.65, function()
            demo.step = demo.step + (demo.raid and 2 or 1)
            AdvanceLiveDemo(demo)
        end)
    end
end

local function ToggleOptions()
    if main.options:IsShown() then
        main.options:Hide()
    else
        hist:Hide()
        main:Show()
        main.options:Show()
    end
end

do
    local opts = CreateFrame("Frame", "LootRollsPlusOptions", main)
    main.options = opts
    opts:SetPoint("TOPLEFT", 4, -22)
    opts:SetPoint("BOTTOMRIGHT", -4, 6)
    opts:Hide()
    tinsert(UISpecialFrames, "LootRollsPlusOptions")

    local section = opts:CreateTexture(nil, "BACKGROUND")
    section:SetPoint("TOPLEFT", 2, -52)
    section:SetPoint("TOPRIGHT", -2, -52)
    section:SetHeight(48)
    section:SetColorTexture(0.09, 0.13, 0.18, 0.85)

    local soloCheck = CreateFrame("CheckButton", "LootRollsPlusHideSolo", opts, "UICheckButtonTemplate")
    soloCheck:SetSize(24, 24)
    soloCheck:SetPoint("TOPLEFT", 3, -1)
    soloCheck.label = soloCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    soloCheck.label:SetPoint("LEFT", soloCheck, "RIGHT", 2, 0)
    soloCheck.label:SetText(L.hideSolo)
    soloCheck:SetHitRectInsets(0, -soloCheck.label:GetStringWidth() - 2, 0, 0)
    soloCheck:SetScript("OnClick", function(self)
        db.hideSolo = self:GetChecked() and true or false
        if SoloHidden() then
            print(Label("Loot Rolls Plus: type /lrplus show to restore the window.",
                "Loot Rolls Plus: команда /lrplus show вернёт окно."))
        end
    end)

    local liveCheck = CreateFrame("CheckButton", "LootRollsPlusShowLiveRolls", opts, "UICheckButtonTemplate")
    liveCheck:SetSize(24, 24)
    liveCheck:SetPoint("TOPLEFT", 3, -25)
    liveCheck.label = liveCheck:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    liveCheck.label:SetPoint("LEFT", liveCheck, "RIGHT", 2, 0)
    liveCheck.label:SetText(Label("Show choices next to loot rolls", "Показывать выбор рядом с розыгрышем"))
    liveCheck:SetHitRectInsets(0, -liveCheck.label:GetStringWidth() - 2, 0, 0)
    liveCheck:SetScript("OnClick", function(self)
        db.liveRolls = self:GetChecked() and true or false
        liveDemo = nil
        if worldReady then ns.LiveSource:SetEnabled(db.liveRolls) end
        RenderLiveRolls()
    end)

    local positionHeading = opts:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    positionHeading:SetPoint("TOPLEFT", 10, -58)
    positionHeading:SetText(Label("Show comparison on roll click", "Сравнение по клику на бросок"))
    local positionChoices = {
        { value = "auto", label = Label("Auto", "Авто") },
        { value = "above", label = Label("Above", "Сверху") },
        { value = "below", label = Label("Below", "Снизу") },
    }
    local function UpdatePositionOptions()
        local position = PlayerListPosition()
        for _, choice in ipairs(positionChoices) do choice.button:SetChecked(choice.value == position) end
    end
    for i, choice in ipairs(positionChoices) do
        local button = CreateFrame("CheckButton", nil, opts, "UIRadioButtonTemplate")
        button:SetSize(18, 18)
        button:SetPoint("TOPLEFT", 9 + (i - 1) * 86, -77)
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("LEFT", button, "RIGHT", 3, 0)
        label:SetText(choice.label)
        button:SetHitRectInsets(0, -label:GetStringWidth() - 3, 0, 0)
        button.position = choice.value
        button:SetScript("OnClick", function(self)
            db.playerListPosition = self.position
            UpdatePositionOptions()
            if details:IsShown() then DrawComparison() end
        end)
        choice.button = button
    end

    local clearHistory = TextButton(Label("Clear History...", "Очистить историю..."), opts, "LootRollsPlusClearHistory", true)
    clearHistory:SetPoint("TOPLEFT", 3, -108)
    clearHistory:SetScript("OnClick", function()
        StaticPopup_Show("LOOTROLLSPLUS_CLEAR")
    end)

    opts:SetScript("OnShow", function(self)
        self:RegisterEvent("GLOBAL_MOUSE_DOWN")
        optBtn.active = true
        PaintButton(optBtn)
        HideMainList()
        grip:Show()
        KeepMainTopRight()
        soloCheck:SetChecked(db.hideSolo)
        liveCheck:SetChecked(db.liveRolls ~= false)
        UpdatePositionOptions()
    end)

    opts:SetScript("OnHide", function(self)
        -- A hidden parent can trigger OnHide without clearing the child's shown flag.
        if self:IsShown() then self:Hide() end
        self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        optBtn.active = nil
        PaintButton(optBtn)
        grip:Show()
        DrawMain()
        if main:IsShown() then UpdateVisibility() end
    end)

    opts:SetScript("OnEvent", function(self) DismissOutside(self) end)
end
optBtn:SetScript("OnClick", ToggleOptions)

local function RestoreRollWindow()
    db.hidden, db.hideSolo = false, false
    main.options:Hide()
    hist:Hide()
    UpdateVisibility()
end

if Settings and type(Settings.RegisterCanvasLayoutCategory) == "function"
    and type(Settings.RegisterAddOnCategory) == "function" then
    local page = CreateFrame("Frame")
    local logo = page:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("TOPLEFT", 16, -16)
    logo:SetTexture("Interface\\AddOns\\LootRollsPlus\\media\\addon-icon.png")
    local heading = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    heading:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    heading:SetText("Loot Rolls Plus")

    local hideSolo = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    hideSolo:SetSize(24, 24)
    hideSolo:SetPoint("TOPLEFT", logo, "BOTTOMLEFT", 0, -14)
    local label = hideSolo:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", hideSolo, "RIGHT", 4, 0)
    label:SetText(L.hideSolo)
    hideSolo:SetHitRectInsets(0, -label:GetStringWidth() - 4, 0, 0)
    hideSolo:SetScript("OnClick", function(self)
        if not db then return end
        db.hideSolo = not not self:GetChecked()
        main.options:Hide()
        UpdateVisibility()
    end)

    local restore = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    restore:SetSize(180, 26)
    restore:SetPoint("TOPLEFT", hideSolo, "BOTTOMLEFT", 0, -14)
    restore:SetText(Label("Show Roll Window", "Показать окно роллов"))
    restore:SetScript("OnClick", function()
        if not db then return end
        RestoreRollWindow()
        hideSolo:SetChecked(false)
        if SettingsPanel and SettingsPanel:IsShown() and HideUIPanel then HideUIPanel(SettingsPanel) end
    end)

    page:SetScript("OnShow", function() hideSolo:SetChecked(db and not not db.hideSolo or false) end)
    Settings.RegisterAddOnCategory(Settings.RegisterCanvasLayoutCategory(page, "Loot Rolls Plus"))
end

---------------------------------------------------------------------------
-- Eventos
---------------------------------------------------------------------------
local function UpdateVisit(isReload)
    local name, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
    if issecretvalue and issecretvalue(instanceType) then return end
    if instanceType == "party" or instanceType == "raid" then
        visits:Update(instanceID, name, time(), isReload)
    else
        visits:Update(nil, nil, time(), isReload)
    end
end

local function TryImport()
    if not db then return end
    local imported = ns.History.Import(charDB, LootRollsInspectorCharDB, DayKey)
    if imported then
        RebuildDayKeys()
        PruneDays()
    end
    local _, playerClass = UnitClass("player")
    local playerName = UnitNameUnmodified and UnitNameUnmodified("player") or UnitName("player")
    local fullName = NameUtil and NameUtil.GetUnmodifiedUnitFullName and NameUtil.GetUnmodifiedUnitFullName("player")
    local recovered = ns.History.RecoverClasses(days, DungeonQuestAtlasCharDB,
        ns.GetItemLinkIdentity, RAID_CLASS_COLORS, playerName, playerClass, fullName)
    if imported or recovered > 0 then refresh() end
end

local QueueDropInspections, ResetDropInspections
do
    local jobs, seen, timer = {}, setmetatable({}, { __mode = "k" }), nil
    local function Schedule()
        if timer or #jobs == 0 then return end
        local token = {}
        timer = token
        C_Timer.After(0.5, function()
            if timer ~= token then return end
            timer = nil
            local job = table.remove(jobs, 1)
            local entry, name, class = job.entry, job.name, job.class
            local unique, currentClass = ComparisonParticipant(entry, name)
            local saved = SavedInspection(entry, name, class, job.guid)
            if worldReady and not entry.closed and GetTime() < job.expires and HasRoll(entry) and unique and currentClass == class
                and (job.phase ~= "winner" or (entry.done and entry.winner == name))
                and capture:GetParticipantGUID(entry, name) == job.guid and not CompleteDropInspection(saved) then
                local hasSlot, pending = ns.HasInspectSlot(entry.link)
                if pending then
                    RequestItemData(entry.link)
                    jobs[#jobs + 1] = job
                elseif hasSlot then
                    local function RetryWinner()
                        local current = seen[entry] and seen[entry][name]
                        if worldReady and entry.done and entry.winner == name
                            and current and current.winner == job.token
                            and GetTime() < job.expires and #jobs < 40 then
                            jobs[#jobs + 1] = job
                            Schedule()
                        end
                    end
                    local status = inspector:Request(entry.link, name, class, function(result, snapshot, guid)
                        if snapshot and SaveInspection(entry, name, class, job.guid, snapshot, guid, true)
                            and detailEntry == entry then DrawComparison() end
                        if result == "unavailable" then RetryWinner() end
                    end, job.guid)
                    if status == "busy" or status == "combat" or status == "inspectOpen" then
                        table.insert(jobs, 1, job)
                    elseif status == "unavailable" or (status == "absent" and job.guid) then
                        RetryWinner()
                    end
                end
            end
            Schedule()
        end)
    end

    QueueDropInspections = function(entry)
        if entry.legacy or entry.ambiguous or entry.stale or entry.closed or time() - entry.t > 180 then return end
        local tried = seen[entry] or {}
        seen[entry] = tried
        local function Add(name, class, phase)
            if not name or not class then return end
            local guid = capture:GetParticipantGUID(entry, name)
            local unique, currentClass = ComparisonParticipant(entry, name)
            local saved = SavedInspection(entry, name, class, guid)
            if not unique or currentClass ~= class or guid == false
                or (saved and saved.atDrop and (phase ~= "winner" or CompleteDropInspection(saved))) then return end
            local previous = tried[name]
            local identity = guid or class
            if not previous or previous.identity ~= identity then
                previous = {identity = identity}
                tried[name] = previous
            end
            if previous[phase] then return end
            if phase == "winner" then
                local queuedNeed, lastNeed
                for index, job in ipairs(jobs) do
                    if job.phase == "need" then
                        lastNeed = index
                        if job.entry == entry and job.name == name and job.guid == guid then queuedNeed = index end
                    end
                end
                local replaceIndex = queuedNeed or (#jobs >= 40 and lastNeed)
                if replaceIndex then table.remove(jobs, replaceIndex) end
            end
            if #jobs >= 40 then return end
            local job = { entry = entry, name = name, class = class, guid = guid, phase = phase,
                expires = GetTime() + 20, token = {} }
            previous[phase] = job.token
            if phase == "winner" then table.insert(jobs, 1, job) else jobs[#jobs + 1] = job end
        end
        if entry.done then
            Add(entry.winner, entry.winnerClass, "winner")
        else
            for _, roll in ipairs(entry.rolls) do
                if roll.type == "need" then Add(roll.name, roll.class, "need") end
            end
        end
        Schedule()
    end

    ResetDropInspections = function()
        wipe(jobs)
        wipe(seen)
        timer = nil
    end
end

local pendingInspectionTransfers = setmetatable({}, {__mode = "k"})
local function TransferConfirmedInspections(entry)
    local candidates = pendingInspectionTransfers[entry]
    if not candidates then return end
    for name, snapshot in pairs(candidates) do
        local guid = capture:GetParticipantGUID(entry, name)
        if type(guid) == "string" then
            local unique, class = ComparisonParticipant(entry, name)
            if guid == snapshot.guid and unique and class == snapshot.class then
                local existing = SavedInspection(entry, name, class, guid)
                if not existing or not existing.atDrop or (snapshot.at and existing.at and snapshot.at < existing.at) then
                    entry.inspections = entry.inspections or {}
                    entry.inspections[name] = snapshot
                end
            end
            if guid ~= snapshot.guid or (unique and class) then candidates[name] = nil end
        end
    end
    if not next(candidates) then pendingInspectionTransfers[entry] = nil end
end

StageInspectionTransfer = function(entry, name, snapshot)
    if not snapshot.atDrop or not snapshot.guid then return end
    local pending = pendingInspectionTransfers[entry]
    local candidates = pending or {}
    local previous = candidates[name]
    if not previous or (snapshot.at and previous.at and snapshot.at < previous.at) then candidates[name] = snapshot end
    pendingInspectionTransfers[entry] = candidates
    TransferConfirmedInspections(entry)
    if not pending and pendingInspectionTransfers[entry] then
        C_Timer.After(180, function()
            if pendingInspectionTransfers[entry] == candidates then pendingInspectionTransfers[entry] = nil end
        end)
    end
end

local function RecordDrop(entry, isNew, baseline)
    local key = DayKey(entry.t)
    local newDay
    if isNew then
        local visit = visits:Get()
        if visit and entry.t >= visit.startedAt then entry.visit = visit end
        newDay = type(days[key]) ~= "table"
        local list = EnsureDay(key)
        if days[key] ~= list then return end
        local index = #list + 1
        while index > 1 and list[index - 1].t > entry.t do
            list[index] = list[index - 1]
            index = index - 1
        end
        list[index] = entry
    end
    if IsActive(entry) and (isNew or HasRoll(entry)) then
        if not activeEntries[entry] then
            nextActiveOrder = nextActiveOrder + 1
            activeEntries[entry] = nextActiveOrder
        end
    else
        activeEntries[entry] = nil
    end
    TransferConfirmedInspections(entry)
    if worldReady and not baseline then QueueDropInspections(entry) end
    if newDay then queueRefresh() else queueRefresh(key) end
end

local function RemoveDrop(entry, replacement)
    activeEntries[entry] = nil
    local key = DayKey(entry.t)
    local list = days[key]
    if not list then return end
    for i, candidate in ipairs(list) do
        if candidate == entry then
            if replacement and not replacement.ambiguous then
                inspectionReplacements[entry] = replacement
                for name, snapshot in pairs(entry.inspections or {}) do
                    StageInspectionTransfer(replacement, name, snapshot)
                end
            end
            table.remove(list, i)
            if #list == 0 then
                days[key] = nil
                RebuildDayKeys()
                queueRefresh()
            else
                queueRefresh(key)
            end
            return
        end
    end
end

local function FindSavedDrop(encounterID, lootListKey, startTime, link)
    local itemIdentity = ns.GetItemLinkIdentity(link)
    if not itemIdentity then return end
    for i = #dayKeys, math.max(#dayKeys - 1, 1), -1 do
        local list = days[dayKeys[i]]
        for j = #list, 1, -1 do
            local entry = list[j]
            if not entry.done and entry.capture == "history" and entry.encounterID == encounterID
                and entry.lootListKey == lootListKey and entry.startTime == startTime
                and ns.GetItemLinkIdentity(entry.link) == itemIdentity
                and math.abs(time() - entry.t) < 600 then
                entry.stale = nil
                RecordDrop(entry, false, true)
                return entry
            end
        end
    end
end

local function MarkPendingHistoryStale()
    for _, key in ipairs(dayKeys) do
        for _, entry in ipairs(days[key]) do
            if not entry.done then entry.stale = true end
        end
    end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_LEAVING_WORLD")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("INSPECT_READY")
for _, event in ipairs(ns.CaptureEvents) do ev:RegisterEvent(event) end

ev:SetScript("OnEvent", function(_, event, a1, a2, ...)
    if event == "ADDON_LOADED" then
        if a1 == "LootRollsInspector" or a1 == "DungeonQuestAtlas" then
            C_Timer.After(0, TryImport)
        elseif a1 == ADDON then
            if type(LootRollsPlusDB) ~= "table" then LootRollsPlusDB = {} end
            if type(LootRollsPlusCharDB) ~= "table" then LootRollsPlusCharDB = {} end
            db, charDB = LootRollsPlusDB, LootRollsPlusCharDB
            local maxDays = db.maxDays
            if type(maxDays) ~= "number" or not (maxDays >= 1 and maxDays <= MAX_RETENTION_DAYS and maxDays % 1 == 0) then
                db.maxDays = DEFAULT_MAX_DAYS
            end
            if not finite(db.windowHeight) or db.windowHeight < MIN_WINDOW_HEIGHT or db.windowHeight > MAX_WINDOW_HEIGHT then
                local rows = db.visibleRows
                db.windowHeight = finite(rows) and rows >= 1 and rows <= MAX_VISIBLE
                    and math.max(MIN_WINDOW_HEIGHT, WINDOW_PADDING + math.floor(rows) * ROW_H) or nil
            end
            db.visibleRows, db.historyHeight = nil, nil
            if type(charDB.days) ~= "table" then charDB.days = {} end
            days = charDB.days
            ns.History.NormalizeDays(days, DayKey)
            visits = ns.History.NewVisits(charDB)
            capture = ns.NewCapture({ onDrop = RecordDrop, onRemove = RemoveDrop, getExisting = FindSavedDrop })
            RebuildDayKeys()
            TryImport()
            PruneDays()
            MarkPendingHistoryStale()
            RestoreMainPosition()
            UpdateVisibility()
            refresh()
        end
    elseif db then
        if event == "PLAYER_ENTERING_WORLD" then
            UpdateVisit(not worldReady and a2)
            if not worldReady then
                ns.LiveSource:Start(RenderLiveRolls, db.liveRolls ~= false)
            end
            worldReady = true
            capture:Start()
            UpdateVisibility()
            refresh()
        elseif event == "PLAYER_LEAVING_WORLD" then
            worldReady = false
            liveDemo = nil
            ns.LiveView:Hide()
            inspector:CancelPending()
            ResetDropInspections()
            details:Hide()
        elseif event == "PLAYER_LOGOUT" then
            SaveMainPosition()
        elseif event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
            if liveDemo then C_Timer.After(0, RenderLiveRolls) end
            if hist:IsShown() and not hist.sizing then
                ApplyHistorySize()
                ApplyWindowHeight()
                FitHistory()
                if detailAnchor == hist then PlaceComparison() end
            elseif not sizing then
                main:SetResizeBounds(MAIN_WIDTH, MIN_WINDOW_HEIGHT, MAIN_WIDTH, WindowHeightLimit())
                ApplyWindowHeight()
                DrawMain()
                PlaceComparison(main)
            end
        elseif event == "ZONE_CHANGED_NEW_AREA" then
            if worldReady then UpdateVisit(false) end
        elseif event == "GROUP_ROSTER_UPDATE" then
            UpdateVisibility()
        elseif event == "INSPECT_READY" then
            if worldReady then inspector:Ready(a1) end
        elseif worldReady then
            if event == "START_LOOT_ROLL" and liveDemo then
                liveDemo = nil
                RenderLiveRolls()
            end
            capture:HandleEvent(event, a1, a2, ...)
        end
    end
end)

---------------------------------------------------------------------------
-- Comandos: /lrplus, /lrplus historial, /lrplus config, /lrplus reset, /lrplus days N, /lrplus pos
---------------------------------------------------------------------------
SLASH_LOOTROLLSPLUS1 = "/lrplus"
SLASH_LOOTROLLSPLUS2 = "/lootrollsplus"
SlashCmdList.LOOTROLLSPLUS = function(msg)
    if not db then return end
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "demo raid" or msg == "demo party" then
        if not ns.LiveSource:HasActiveRolls() then
            if liveComparison then details:Hide() end
            ns.LiveView:Hide()
            liveDemo = { raid = msg == "demo raid", step = 0 }
            AdvanceLiveDemo(liveDemo)
        else
            print(Label("Loot Rolls Plus: close the active loot rolls before starting the preview.",
                "Loot Rolls Plus: завершите активные розыгрыши перед запуском предпросмотра."))
        end
    elseif msg == "demo off" then
        liveDemo = nil
        RenderLiveRolls()
    elseif msg == "import" then
        TryImport()
    elseif msg == "historial" or msg == "history" or msg == "h" then
        histBtn:GetScript("OnClick")()
    elseif msg == "config" or msg == "options" or msg == "opciones" then
        ToggleOptions()
    elseif msg == "show" then
        RestoreRollWindow()
    elseif msg == "reset" then
        StaticPopup_Show("LOOTROLLSPLUS_CLEAR")
    elseif msg == "days" or msg:match("^days%s") then
        local n = tonumber(msg:match("^days%s+(%d+)$"))
        if n and n >= 1 and n <= MAX_RETENTION_DAYS then
            db.maxDays = n
            PruneDays()
            refresh()
        end
        print("|cff80c0ffLoot Rolls Plus|r: " .. L.daysSet:format(db.maxDays))
    elseif msg == "pos" then
        db.pos = nil
        main:ClearAllPoints()
        main:SetPoint("CENTER", UIParent, "CENTER", 400, 0)
    else
        db.hidden = not db.hidden
        UpdateVisibility()
        if not db.hidden and SoloHidden() then
            print("|cff80c0ffLoot Rolls Plus|r: " .. L.soloHidden)
        end
    end
end
