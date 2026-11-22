local _, ns = ...

local view = {}
ns.LiveView = view
local display = ns.RollDisplay

local ROW_HEIGHT, MAX_ROWS, PARTY_ROWS = 15, 8, 5
local PADDING, GAP, WIDTH, MIN_WIDTH = 5, 5, 205, 174
local DETAIL_HEADER = 24
local isSecret = issecretvalue or function() return false end
local cards, demoAnchors = {}, {}
local layoutObstacles = {}
local details
local geometryWatch = CreateFrame("Frame", "LootRollsPlusLiveGeometry", UIParent)
geometryWatch:Hide()

local label, tint = display.Label, display.Tint
local shortChoices = {
    need = label("Need", "Нужда"), greed = label("Greed", "Алчн."), pass = label("Pass", "Отказ"),
    offspec = label("Off", "Доп."), disenchant = label("DE", "Расп."), transmog = label("TM", "Обл."),
    waiting = label("Wait", "Ждут"),
}
local countOrder = { "need", "greed", "pass", "offspec", "disenchant", "transmog", "waiting" }
local noResponses = label("No responses yet", "Пока нет ответов")
local waitingForData = label("Waiting for roll data", "Ожидание данных")
local allPassed = label("Everyone passed", "Все отказались")
local overlapping = label("Overlapping rolls", "Совпавшие розыгрыши")
local winnerLabel = label("Winner", "Победитель")
local playersLabel = label("Players", "Игроки")
local demoLabel = label("Demo", "Демо")
local noPlayers = {}

local function buildCounts(entry, first, last, compact)
    local counts = {}
    for i = first, last do
        local choice = countOrder[i]
        local count = entry.counts[choice] or 0
        if i <= 3 or count > 0 then
            local icon = display.ChoiceIcon(choice)
            local text = compact and icon ~= "" and tostring(count) or shortChoices[choice] .. " " .. count
            counts[#counts + 1] = icon .. tint(text, display.Choices[choice].color)
        end
    end
    return table.concat(counts, " · ")
end

local function font(parent, justification)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH(justification or "LEFT")
    text:SetWordWrap(false)
    text:SetMaxLines(1)
    return text
end

local function newPanel(name)
    local frame = display.NewPanel(name, nil, nil, nil, 0.86)
    frame:SetFrameStrata("DIALOG")
    frame:Hide()
    return frame
end

local function playerFields(row)
    row.classIcon = row:CreateTexture(nil, "ARTWORK")
    row.classIcon:SetSize(13, 13)
    row.classIcon:SetPoint("LEFT", 1, 0)
    row.classUnknown = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.classUnknown:SetPoint("CENTER", row.classIcon, "CENTER")
    row.classUnknown:SetText("?")
    row.result = font(row, "RIGHT")
    row.result:SetPoint("RIGHT", -1, 0)
    row.name = font(row)
    row.name:SetPoint("LEFT", row.classIcon, "RIGHT", 4, 0)
    row.name:SetPoint("RIGHT", row.result, "LEFT", -4, 0)
end

local function drawPlayer(row, player, short)
    display.SetClassIcon(row.classIcon, row.classUnknown, player and player.name, player and player.class)
    if player then
        local name = short and display.ShortName(player.name) or player.name
        row.name:SetText(display.ColoredName(name, player.class))
    else
        row.name:SetText("")
    end
end

local function measuredWidth(fontString, text)
    if not fontString.GetUnboundedStringWidthForText then return end
    local measured = fontString:GetUnboundedStringWidthForText(text)
    if not isSecret(measured) and type(measured) == "number" and measured >= 0 and measured < math.huge then
        return measured
    end
end

local function fits(fontString, text, width)
    local measured = measuredWidth(fontString, text)
    return not measured or measured <= width
end

local function rowResult(text, player, width)
    local choice = player.choice
    local full = display.ChoiceText(choice, player.roll, true)
    local warning = display.WarningDot(player.warning)
    if not full then return "" end
    full = warning .. full
    if fits(text, full, width) then return full end
    local icon = display.ChoiceIcon(choice)
    local number = player.roll and " " .. player.roll or ""
    local color = display.Choices[choice].color
    local abbreviated = warning .. icon .. tint(shortChoices[choice] .. number, color)
    if fits(text, abbreviated, width) then return abbreviated end
    local shortText = warning .. tint(shortChoices[choice] .. number, color)
    if fits(text, shortText, width) then return shortText end
    local value = player.roll and tint(tostring(player.roll), color) or ""
    if icon ~= "" and fits(text, warning .. icon .. value, width) then return warning .. icon .. value end
    return player.roll and warning .. value or shortText
end

local function playerButton(row)
    row:RegisterForClicks("LeftButtonUp")
    row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    row:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    row:SetScript("OnClick", function(self)
        local card, player = self.liveCard, self.livePlayer
        if card and card.entry and card.entry.canInspect and player and view.OnPlayerClick then
            view.OnPlayerClick(card, card.entry, player, self)
        end
    end)
end

local function newRows(parent, count, top)
    local rows = {}
    for i = 1, count do
        local row = CreateFrame("Button", nil, parent)
        row:SetPoint("TOPLEFT", PADDING, -top - (i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", -PADDING, -top - (i - 1) * ROW_HEIGHT)
        row:SetHeight(ROW_HEIGHT)
        row.highlight = row:CreateTexture(nil, "BACKGROUND")
        row.highlight:SetAllPoints()
        row.highlight:SetColorTexture(0.18, 0.25, 0.38, 0.65)
        playerFields(row)
        playerButton(row)
        rows[i] = row
    end
    return rows
end

local function drawRows(rows, players, offset, inset, width, card, short, panel, visibleRows)
    local resultWidth = math.floor((width - 2 * PADDING - inset) * 0.49)
    for i, row in ipairs(rows) do
        local player = (not visibleRows or i <= visibleRows) and players[i + offset] or nil
        row.liveCard, row.livePlayer = card, player
        row.livePanel = panel or card
        row:EnableMouse(player ~= nil and card.entry.canInspect == true)
        row:SetShown(player ~= nil)
        if player then
            row.result:SetPoint("RIGHT", -1 - inset, 0)
            local result = rowResult(row.result, player, resultWidth)
            local measured = measuredWidth(row.result, result)
            row.result:SetWidth(measured and math.min(resultWidth, math.max(24, math.ceil(measured) + 2)) or resultWidth)
            row.result:SetText(result)
            drawPlayer(row, player, short)
            row.highlight:SetShown(player.isSelf == true)
        end
    end
end

local function finite(value)
    return not isSecret(value) and type(value) == "number" and value > -math.huge and value < math.huge
end

local function scalePosition(frame, method)
    if isSecret(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata")
        or type(frame[method]) ~= "function" or type(frame.GetEffectiveScale) ~= "function" then return end
    local value = frame[method](frame)
    local scale, parentScale = frame:GetEffectiveScale(), UIParent:GetEffectiveScale()
    if not finite(value) or not finite(scale) or scale <= 0 or not finite(parentScale) or parentScale <= 0 then return end
    local coordinate = value * scale / parentScale
    if finite(coordinate) then return coordinate end
end
view.ScreenCoordinate = scalePosition

local function frameRect(frame)
    local left, right = scalePosition(frame, "GetLeft"), scalePosition(frame, "GetRight")
    local bottom, top = scalePosition(frame, "GetBottom"), scalePosition(frame, "GetTop")
    if left and right and left < right and bottom and top and bottom < top then
        return { left = left, right = right, bottom = bottom, top = top }
    end
end

function view.VisiblePawnRects()
    local rectangles = {}
    local function addVisible(frame)
        if isSecret(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata")
            or type(frame.IsVisible) ~= "function" then return end
        local visible = frame:IsVisible()
        if isSecret(visible) or visible ~= true then return end
        local bounds = frameRect(frame)
        if bounds then rectangles[#rectangles + 1] = bounds end
        return true
    end
    for i = 1, 4 do
        local advisor = _G["PawnUI_LootUpgradeAdvisor" .. i]
        if addVisible(advisor) then addVisible(advisor.arrow) end
    end
    return rectangles
end

function view.VisiblePromptRects()
    local rectangles, seen = {}, {}
    local function addVisible(anchor)
        if isSecret(anchor) or (type(anchor) ~= "table" and type(anchor) ~= "userdata")
            or seen[anchor] or type(anchor.IsVisible) ~= "function" then return end
        seen[anchor] = true
        local ok, visible = pcall(anchor.IsVisible, anchor)
        if not ok or isSecret(visible) or visible ~= true then return end
        local readable, box = pcall(frameRect, anchor)
        if readable and box then rectangles[#rectangles + 1] = box end
    end

    -- The source omits rolls whose item cannot be read. Their buttons still need space.
    local container = _G.GroupLootContainer
    if not isSecret(container) and type(container) == "table" then
        local frames = container.rollFrames
        if not isSecret(frames) and type(frames) == "table" then
            for _, anchor in pairs(frames) do addVisible(anchor) end
        end
    end
    for _, entry in ipairs(geometryWatch.entries or {}) do
        addVisible(entry.anchor)
    end
    return rectangles
end

local function overlaps(rect, obstacle)
    return rect.left < obstacle.right and obstacle.left < rect.right
        and rect.bottom < obstacle.top and obstacle.bottom < rect.top
end

function view.RectOverlaps(rect, obstacles)
    for _, obstacle in ipairs(obstacles) do
        if overlaps(rect, obstacle) then return true end
    end
    return false
end

local function rectAt(left, bottom, width, height)
    return { left = left, right = left + width, bottom = bottom, top = bottom + height }
end

local function sideRect(left, anchor, width, height, screenHeight)
    if not anchor or not finite(screenHeight) or screenHeight < height then return end
    local bottom = (anchor.top + anchor.bottom - height) / 2
    return rectAt(left, math.max(0, math.min(bottom, screenHeight - height)), width, height)
end

local function verticalRect(anchor, width, height, screenWidth, screenHeight)
    if not finite(screenHeight) or screenHeight < height + 2 * GAP then return end
    local left = math.max(GAP, math.min(anchor.left, screenWidth - width - GAP))
    local function find(above)
        local start = above and anchor.top + GAP or anchor.bottom - height - GAP
        local bottom = start
        while bottom >= GAP and bottom + height <= screenHeight - GAP do
            local rect = rectAt(left, bottom, width, height)
            local previous = bottom
            for _, obstacle in ipairs(layoutObstacles) do
                if overlaps(rect, obstacle) then
                    bottom = above and math.max(bottom, obstacle.top + GAP)
                        or math.min(bottom, obstacle.bottom - height - GAP)
                end
            end
            if bottom == previous then return rect, math.abs(bottom - start) end
        end
    end
    local above, aboveGap = find(true)
    local below, belowGap = find(false)
    if not below or (above and aboveGap <= belowGap) then return above end
    return below
end

local function fitCard(card, anchor, entry, raid, height, pawnRects)
    local left = scalePosition(anchor, "GetLeft")
    local right = scalePosition(anchor, "GetRight")
    local screenWidth, screenHeight = UIParent:GetWidth(), UIParent:GetHeight()
    if not left or not right or left >= right or not finite(screenWidth) or screenWidth <= 0 then return false end
    local preferred, minimum = WIDTH, MIN_WIDTH
    if not raid and #entry.players <= PARTY_ROWS then
        minimum = 108
        local names, choices = 0, 0
        for _, player in ipairs(entry.winner and { entry.winner } or entry.players) do
            local name = display.ShortName(player.name)
            local result = display.WarningDot(player.warning) .. (display.ChoiceText(player.choice, player.roll, true) or "")
            names = math.max(names, math.min(86, measuredWidth(card.summary, name) or 50))
            choices = math.max(choices, math.min(90, measuredWidth(card.summary, result) or 75))
        end
        preferred = math.min(182, math.max(minimum, math.ceil(names + choices + 36)))
    end
    local anchorRect = frameRect(anchor)
    local rightWidth = math.floor(math.min(preferred, screenWidth - right - 2 * GAP))
    local leftWidth = math.floor(math.min(preferred, left - 2 * GAP))
    local placement, width, bounds
    if leftWidth >= minimum then
        local candidate = sideRect(left - GAP - leftWidth, anchorRect, leftWidth, height, screenHeight)
        if not candidate or not view.RectOverlaps(candidate, layoutObstacles) then
            placement, width, bounds = "left", leftWidth, candidate
        end
    end
    if not placement and rightWidth >= minimum then
        local candidate = sideRect(right + GAP, anchorRect, rightWidth, height, screenHeight)
        if (candidate and not view.RectOverlaps(candidate, layoutObstacles)) or (not candidate and #pawnRects == 0) then
            placement, width, bounds = "right", rightWidth, candidate
        end
    end
    if not placement and anchorRect then
        width = math.floor(math.min(preferred, screenWidth - 2 * GAP))
        if width >= minimum then
            bounds = verticalRect(anchorRect, width, height, screenWidth, screenHeight)
            if bounds then placement = "vertical" end
        end
    end
    if not placement then return false end
    if bounds then layoutObstacles[#layoutObstacles + 1] = bounds end
    if card.anchor ~= anchor or card.placement ~= placement or card:GetWidth() ~= width
        or (placement == "vertical" and (card.bounds.left ~= bounds.left or card.bounds.bottom ~= bounds.bottom)) then
        card.placement = placement
        card.onRight = placement == "right"
        card.anchor = anchor
        card:SetWidth(width)
        card:ClearAllPoints()
        if placement == "vertical" then
            card:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.left, bounds.bottom)
        elseif card.onRight then
            card:SetPoint("LEFT", anchor, "RIGHT", GAP, 0)
        else
            card:SetPoint("RIGHT", anchor, "LEFT", -GAP, 0)
        end
    end
    card.bounds = bounds
    return true
end

local function hideDetails()
    if details then
        details:Hide()
        details.card, details.entry, details.players = nil, nil, nil
    end
end

local function isExpanded(entry)
    local current = details and details:IsShown() and details.entry
    return current and current.id == entry.id and current.link == entry.link and current.demo == entry.demo
end

local function hideCard(card)
    card:Hide()
    card.entry, card.anchor, card.bounds = nil, nil, nil
end

local function drawDetailsRows(frame)
    drawRows(frame.rows, frame.players, frame.offset, frame.slider:IsShown() and 12 or 0, frame:GetWidth(),
        frame.card, false, frame, frame.visibleRows)
end

local function closeOnOutsideClick(frame, _, button)
    if button ~= "LeftButton" and button ~= "RightButton" and button ~= "MiddleButton" then return end
    local toggle = frame.card and frame.card.toggle
    for _, focus in ipairs(GetMouseFoci()) do
        while focus do
            if focus == frame or focus == toggle or (view.KeepRosterOpen and view.KeepRosterOpen(frame, focus)) then return end
            focus = focus:GetParent()
        end
    end
    hideDetails()
end

local function newDetails()
    local frame = newPanel("LootRollsPlusLiveDetails")
    frame:SetWidth(WIDTH)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame.title = font(frame)
    frame.title:SetPoint("TOPLEFT", PADDING + 2, -PADDING - 1)
    frame.title:SetPoint("TOPRIGHT", -PADDING, -PADDING - 1)
    frame.counts = {}
    for i = 1, 3 do
        local line = font(frame)
        line:SetPoint("TOPLEFT", PADDING + 2, -DETAIL_HEADER - (i - 1) * ROW_HEIGHT)
        line:SetPoint("TOPRIGHT", -PADDING, -DETAIL_HEADER - (i - 1) * ROW_HEIGHT)
        frame.counts[i] = line
    end
    frame.body = CreateFrame("Frame", nil, frame)
    frame.body:SetPoint("BOTTOMLEFT")
    frame.body:SetPoint("BOTTOMRIGHT")
    frame.rows = newRows(frame.body, MAX_ROWS, 0)

    local slider = CreateFrame("Slider", nil, frame.body)
    slider:SetOrientation("VERTICAL")
    slider:SetWidth(9)
    slider:SetValueStep(1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouse(true)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(0.35, 0.37, 0.43, 0.32)
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    frame.slider = slider
    slider:SetScript("OnValueChanged", function(_, value)
        local offset = math.floor(value + 0.5)
        if frame.players and offset ~= frame.offset then
            frame.offset = offset
            drawDetailsRows(frame)
        end
    end)
    frame:SetScript("OnMouseWheel", function(self, delta)
        if self.slider:IsShown() then self.slider:SetValue(self.offset - delta * 3) end
    end)
    frame:SetScript("OnShow", function(self) self:RegisterEvent("GLOBAL_MOUSE_DOWN") end)
    frame:SetScript("OnHide", function(self) self:UnregisterEvent("GLOBAL_MOUSE_DOWN") end)
    frame:SetScript("OnEvent", closeOnOutsideClick)
    return frame
end

local function attachVertically(frame, anchor, onRight, above)
    local side = onRight and "LEFT" or "RIGHT"
    if above then
        frame:SetPoint("BOTTOM" .. side, anchor, "TOP" .. side, 0, GAP)
    else
        frame:SetPoint("TOP" .. side, anchor, "BOTTOM" .. side, 0, -GAP)
    end
end

local function positionDetails(frame, card)
    local left = scalePosition(card, "GetLeft")
    local right = scalePosition(card, "GetRight")
    local screenWidth = UIParent:GetWidth()
    if not finite(screenWidth) or screenWidth <= 0 then return end
    local popupLeft = card.onRight and scalePosition(card.anchor, "GetLeft")
    frame:ClearAllPoints()
    local width = frame:GetWidth()
    local cardRect = card.placement == "vertical" and card.bounds or frameRect(card) or card.bounds
    local screenHeight, height = UIParent:GetHeight(), frame:GetHeight()
    if not finite(screenHeight) or screenHeight < height then return false end
    local function canAlign(leftEdge, top)
        if not top then return true end
        -- The roster clamps on both axes, including when it anchors to a narrower card.
        local left = math.max(0, math.min(leftEdge, screenWidth - width))
        local bottom = math.max(0, math.min(top - height, screenHeight - height))
        return not view.RectOverlaps(rectAt(left, bottom, width, height), layoutObstacles)
    end
    local function tryVertical(anchor, above)
        local bounds = frameRect(anchor) or anchor.bounds
        if bounds then
            local leftEdge = card.onRight and bounds.left or bounds.right - width
            local bottom = above and bounds.top + GAP or bounds.bottom - height - GAP
            if bottom < 0 or bottom + height > screenHeight or not canAlign(leftEdge, bottom + height) then return false end
        end
        attachVertically(frame, anchor, card.onRight, above)
        return true
    end
    if card.placement == "vertical" and cardRect then
        local bounds = verticalRect(cardRect, width, height, screenWidth, screenHeight)
        if bounds then
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.left, bounds.bottom)
            return true
        end
    end
    if card.onRight and right and screenWidth - right >= width + 2 * GAP and canAlign(right + GAP, cardRect and cardRect.top) then
        frame:SetPoint("TOPLEFT", card, "TOPRIGHT", GAP, 0)
    elseif not card.onRight and left and left >= width + 2 * GAP and canAlign(left - width - GAP, cardRect and cardRect.top) then
        frame:SetPoint("TOPRIGHT", card, "TOPLEFT", -GAP, 0)
    elseif popupLeft and popupLeft >= width + 2 * GAP
        and canAlign(popupLeft - width - GAP, scalePosition(card.anchor, "GetTop")) then
        frame:SetPoint("TOPRIGHT", card.anchor, "TOPLEFT", -GAP, 0)
    else
        -- Keep the disclosure clear of the native buttons when both horizontal options are full.
        local below = scalePosition(card, "GetBottom")
        local top = scalePosition(card, "GetTop")
        local above = top and screenHeight - top
        local cardBottom = below
        local requiredHeight = height + GAP
        local lowest, highest = card, card
        for _, neighbor in pairs(cards) do
            if neighbor ~= card and neighbor:IsShown() and neighbor.onRight == card.onRight then
                local bottom, ceiling = scalePosition(neighbor, "GetBottom"), scalePosition(neighbor, "GetTop")
                if bottom and (not below or bottom < below) then lowest, below = neighbor, bottom end
                if ceiling and (not top or ceiling > top) then highest, top = neighbor, ceiling end
            end
        end
        local aboveStack = top and screenHeight - top
        if aboveStack and aboveStack >= requiredHeight and tryVertical(highest, true) then return true end
        if below and below >= requiredHeight and tryVertical(lowest, false) then return true end
        if not cardRect then
            local fitsAbove = above and above > (cardBottom or 0) and (not cardBottom or cardBottom < requiredHeight)
            return tryVertical(card, fitsAbove)
        end
        local bounds = verticalRect(cardRect, width, height, screenWidth, screenHeight)
        if not bounds then return false end
        frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", bounds.left, bounds.bottom)
    end
    return true
end

local function showDetails(card, reset)
    details = details or newDetails()
    local entry = card.entry
    details.card, details.entry, details.players = card, entry, entry.players
    details.title:SetText(entry.link or display.Escape(entry.name or ""))
    details:SetWidth(card:GetWidth())
    local available = details:GetWidth() - 2 * PADDING - 2
    local counts = buildCounts(entry, 1, 3)
    if not fits(details.counts[1], counts, available) then
        counts = buildCounts(entry, 1, 3, true)
    end
    local extras, rest = buildCounts(entry, 4, #countOrder), ""
    if not fits(details.counts[2], extras, available) then
        extras, rest = buildCounts(entry, 4, 5), buildCounts(entry, 6, #countOrder)
        if extras == "" then extras, rest = rest, "" end
    end
    local header = DETAIL_HEADER + ROW_HEIGHT
    for i, text in ipairs({ counts, extras, rest }) do
        details.counts[i]:SetText(text)
        details.counts[i]:SetShown(text ~= "")
        if i > 1 and text ~= "" then header = header + ROW_HEIGHT end
    end
    details.body:SetPoint("TOPLEFT", 0, -header)
    details.body:SetPoint("TOPRIGHT", 0, -header)
    local visibleRows = math.min(#entry.players, MAX_ROWS)
    while visibleRows > 0 do
        details:SetHeight(header + visibleRows * ROW_HEIGHT + PADDING)
        if positionDetails(details, card) then break end
        visibleRows = visibleRows - 1
    end
    if visibleRows == 0 then
        hideDetails()
        return
    end
    local extra = #entry.players - visibleRows
    local offset = reset and 0 or math.min(details.offset, extra)
    if details.visibleRows ~= visibleRows then
        local inset = visibleRows == 1 and 2 or 8
        local slider = details.slider
        slider:ClearAllPoints()
        slider:SetPoint("TOPRIGHT", -PADDING, -inset)
        slider:SetPoint("BOTTOMRIGHT", -PADDING, PADDING + inset)
        slider:GetThumbTexture():SetSize(9, math.min(19, visibleRows * ROW_HEIGHT - 2 * inset))
    end
    details.offset, details.visibleRows = offset, visibleRows
    details.slider:SetShown(extra > 0)
    details:EnableMouseWheel(extra > 0)
    if extra > 0 then
        details.slider:SetMinMaxValues(0, extra)
        details.slider:SetValue(offset)
    end
    drawDetailsRows(details)
    details:Show()
end

local function newCard(index)
    local card = newPanel("LootRollsPlusLiveRoll" .. index)
    card:SetClampedToScreen(true)
    card.rows = newRows(card, PARTY_ROWS, PADDING)
    card.winnerRows = newRows(card, 1, PADDING + ROW_HEIGHT)
    card.summary = font(card)
    card.summary:SetPoint("TOPLEFT", PADDING, -PADDING)
    card.summary:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    card.toggle = CreateFrame("Button", nil, card)
    card.toggle:SetAllPoints()
    local hover = card.toggle:CreateTexture(nil, "HIGHLIGHT")
    hover:SetPoint("BOTTOMLEFT", 3, 3)
    hover:SetPoint("BOTTOMRIGHT", -3, 3)
    hover:SetHeight(18)
    hover:SetColorTexture(1, 1, 1, 0.08)
    card.toggleText = font(card.toggle, "RIGHT")
    card.toggleText:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    local mid = CreateFrame("Frame", nil, card.toggle)
    mid:SetPoint("BOTTOMLEFT", PADDING, 3)
    mid:SetPoint("BOTTOMRIGHT", card.toggleText, "BOTTOMLEFT", -5, -3)
    mid:SetHeight(18)
    card.leaders = {}
    for i = 1, 2 do
        local leader = CreateFrame("Button", nil, mid)
        leader:SetPoint("LEFT", mid, i == 1 and "LEFT" or "CENTER", i == 1 and 0 or 3, 0)
        leader:SetPoint("RIGHT", mid, i == 1 and "CENTER" or "RIGHT", i == 1 and -3 or 0, 0)
        leader:SetHeight(18)
        playerFields(leader)
        playerButton(leader)
        leader.result:SetWidth(22)
        card.leaders[i] = leader
    end
    card.toggle:SetScript("OnClick", function()
        if not card.entry then return end
        if isExpanded(card.entry) then
            hideDetails()
        else
            showDetails(card, true)
        end
    end)
    return card
end

local function fitCounts(card, entry)
    local text = buildCounts(entry, 1, 3)
    local available = card:GetWidth() - 2 * PADDING
    if not fits(card.summary, text, available) then
        return buildCounts(entry, 1, 3, true)
    end
    for i = 4, #countOrder do
        local extra = buildCounts(entry, i, i)
        if extra ~= "" then
            local extendedText = text .. " · " .. extra
            if fits(card.summary, extendedText, available) then text = extendedText end
        end
    end
    return text
end

local function cardPresentation(entry, raid)
    local winner = not entry.ambiguous and entry.winner
    local status
    if entry.ambiguous then
        status = overlapping
    elseif winner then
        status = tint(winnerLabel, "ffffd100")
    elseif entry.allPassed then
        status = allPassed
    elseif #entry.players == 0 then
        status = entry.hasHistory and noResponses or waitingForData
    end

    local party = not status and not raid and #entry.players <= PARTY_ROWS
    local canExpand = not status and not party
    local height = party and (#entry.players * ROW_HEIGHT + 2 * PADDING) or 2 * PADDING + ROW_HEIGHT
    if canExpand or winner then height = 2 * PADDING + 2 * ROW_HEIGHT end
    return { winner = winner, status = status, party = party, canExpand = canExpand, height = height }
end

local function drawCard(card, entry, presentation)
    card.entry = entry
    local winner, status, party, canExpand = presentation.winner, presentation.status, presentation.party, presentation.canExpand
    card.summary:SetShown(not party)
    card.summary:SetText(status or (canExpand and fitCounts(card, entry)) or "")
    card.toggle:SetShown(canExpand)
    if canExpand then
        for i, leader in ipairs(card.leaders) do
            local player = entry.leaders[i]
            leader.liveCard, leader.livePlayer = card, player
            leader.livePanel = card
            leader:EnableMouse(player ~= nil and entry.canInspect == true)
            leader:SetShown(player ~= nil)
            drawPlayer(leader, player, true)
            if player then
                local dot = display.WarningDot(player.warning)
                leader.result:SetWidth(dot ~= "" and 34 or 22)
                leader.result:SetText(dot .. tint(tostring(player.roll), display.Choices.need.color))
            end
        end
        local disclosure = entry.more > 0 and "+" .. entry.more or (#entry.leaders == 2 and ">" or playersLabel)
        card.toggleText:SetText(tint(disclosure, "ffffd477"))
    end
    drawRows(card.rows, party and entry.players or noPlayers, 0, 0, card:GetWidth(), card, true)
    drawRows(card.winnerRows, winner and { winner } or noPlayers, 0, 0, card:GetWidth(), card, true)
    card:SetHeight(presentation.height)
    card:Show()
    return canExpand
end

local function demoAnchor(index, entry)
    local anchor = demoAnchors[index]
    if not anchor then
        anchor = newPanel("LootRollsPlusLiveDemo" .. index)
        anchor:SetSize(208, 54)
        anchor:SetPoint("CENTER", UIParent, "BOTTOM", 0, 155 + (index - 1) * 100)
        local tag = font(anchor, "RIGHT")
        tag:SetPoint("TOPRIGHT", -PADDING, -PADDING)
        tag:SetText(tint(demoLabel, "ffadadad"))
        anchor.icon = anchor:CreateTexture(nil, "ARTWORK")
        anchor.icon:SetSize(27, 27)
        anchor.icon:SetPoint("LEFT", 9, 0)
        local item = CreateFrame("Frame", nil, anchor)
        item:SetAllPoints(anchor.icon)
        item:EnableMouse(true)
        item:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:SetHyperlink(anchor.link)
            GameTooltip:Show()
        end)
        local function hideItemTooltip(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end
        item:SetScript("OnLeave", hideItemTooltip)
        item:SetScript("OnHide", hideItemTooltip)
        anchor.item = item
        anchor.title = font(anchor)
        anchor.title:SetPoint("LEFT", anchor.icon, "RIGHT", 8, 0)
        anchor.title:SetPoint("RIGHT", -PADDING, 0)
        demoAnchors[index] = anchor
    end
    anchor.link = entry.link
    anchor.icon:SetTexture(entry.icon or 134400)
    anchor.title:SetText(display.Escape(entry.name))
    anchor:Show()
    return anchor
end

local function render(entries, raid, demo, pawnRects, promptRects)
    local anchors = {}
    layoutObstacles = {}
    for _, obstacle in ipairs(pawnRects) do layoutObstacles[#layoutObstacles + 1] = obstacle end
    for _, obstacle in ipairs(promptRects) do layoutObstacles[#layoutObstacles + 1] = obstacle end
    for i, entry in ipairs(entries) do
        local anchor = demo and demoAnchor(i, entry) or entry.anchor
        if anchor and anchor:IsVisible() then
            anchors[i] = anchor
            if demo then
                local bounds = frameRect(anchor)
                if bounds then layoutObstacles[#layoutObstacles + 1] = bounds end
            end
        end
    end

    local expanded
    for i, entry in ipairs(entries) do
        local anchor = anchors[i]
        local card = cards[i]
        if anchor then
            card = card or newCard(i)
            cards[i] = card
            local presentation = cardPresentation(entry, raid)
            if fitCard(card, anchor, entry, raid, presentation.height, pawnRects) then
                local canExpand = drawCard(card, entry, presentation)
                if canExpand and isExpanded(entry) then expanded = card end
            else
                hideCard(card)
            end
        elseif card then
            hideCard(card)
        end
    end
    for i, card in pairs(cards) do
        if i > #entries then hideCard(card) end
    end
    for i = demo and #entries + 1 or 1, #demoAnchors do demoAnchors[i]:Hide() end
    if expanded then
        showDetails(expanded, false)
    else
        hideDetails()
    end
end

function view:Render(entries, raid, demo)
    local watch = not demo and #entries > 0
    if watch and not geometryWatch:IsShown() then geometryWatch.elapsed = 0 end
    geometryWatch.entries = watch and entries or nil
    geometryWatch.raid = watch and raid or nil
    if watch then
        local width, height = UIParent:GetWidth(), UIParent:GetHeight()
        geometryWatch.width = finite(width) and width or nil
        geometryWatch.height = finite(height) and height or nil
    end
    geometryWatch:SetShown(watch)
    local pawnRects = watch and view.VisiblePawnRects() or {}
    local promptRects = watch and view.VisiblePromptRects() or {}
    geometryWatch.pawnRects, geometryWatch.promptRects = pawnRects, promptRects
    render(entries, raid, demo, pawnRects, promptRects)
end

local function sameRectangles(before, after)
    if #before ~= #after then return false end
    for i, a in ipairs(before) do
        local b = after[i]
        if a.left ~= b.left or a.right ~= b.right or a.bottom ~= b.bottom or a.top ~= b.top then return false end
    end
    return true
end

geometryWatch:SetScript("OnUpdate", function(self, elapsed)
    if not self.entries or not finite(elapsed) or elapsed < 0 then return end
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < 0.2 then return end
    self.elapsed = 0
    local width, height = UIParent:GetWidth(), UIParent:GetHeight()
    if not finite(width) or not finite(height) then return end
    local pawnRects = view.VisiblePawnRects()
    local promptRects = view.VisiblePromptRects()
    if self.width == width and self.height == height
        and sameRectangles(self.pawnRects, pawnRects) and sameRectangles(self.promptRects, promptRects) then return end
    self.width, self.height = width, height
    self.pawnRects, self.promptRects = pawnRects, promptRects
    render(self.entries, self.raid, false, pawnRects, promptRects)
    if view.OnPlacementChanged then view.OnPlacementChanged() end
end)

function view:Hide()
    self:Render({}, false, false)
end

function view:FindCard(id, link)
    for _, card in pairs(cards) do
        if card.entry and card.entry.id == id and card.entry.link == link then return card end
    end
end

function view:EquippedAnchor(card, roster)
    local panel = roster and roster:IsShown() and roster.card == card and roster or card
    local popupRight = card.anchor and scalePosition(card.anchor, "GetRight")
    local panelRight = scalePosition(panel, "GetRight")
    if popupRight and panelRight and popupRight > panelRight then return card.anchor end
    return panel
end
