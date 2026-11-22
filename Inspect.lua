local _, ns = ...
local isSecret = issecretvalue or function() return false end
local INSPECT_TIMEOUT = 5

local slotsByType = {
    INVTYPE_HEAD = {"HeadSlot"}, INVTYPE_NECK = {"NeckSlot"}, INVTYPE_SHOULDER = {"ShoulderSlot"},
    INVTYPE_CLOAK = {"BackSlot"}, INVTYPE_CHEST = {"ChestSlot"}, INVTYPE_ROBE = {"ChestSlot"},
    INVTYPE_WRIST = {"WristSlot"}, INVTYPE_HAND = {"HandsSlot"}, INVTYPE_WAIST = {"WaistSlot"},
    INVTYPE_LEGS = {"LegsSlot"}, INVTYPE_FEET = {"FeetSlot"}, INVTYPE_BODY = {"ShirtSlot"},
    INVTYPE_TABARD = {"TabardSlot"}, INVTYPE_FINGER = {"Finger0Slot", "Finger1Slot"},
    INVTYPE_TRINKET = {"Trinket0Slot", "Trinket1Slot"},
    INVTYPE_WEAPON = {"MainHandSlot", "SecondaryHandSlot"},
    INVTYPE_2HWEAPON = {"MainHandSlot"}, INVTYPE_WEAPONMAINHAND = {"MainHandSlot"},
    INVTYPE_WEAPONOFFHAND = {"SecondaryHandSlot"}, INVTYPE_SHIELD = {"SecondaryHandSlot"},
    INVTYPE_HOLDABLE = {"SecondaryHandSlot"}, INVTYPE_RELIC = {"RangedSlot"},
    INVTYPE_RANGED = {"RangedSlot"}, INVTYPE_RANGEDRIGHT = {"RangedSlot"}, INVTYPE_THROWN = {"RangedSlot"},
}

local function tryRead(method, ...)
    if type(method) ~= "function" then return false end
    local ok, value = pcall(method, ...)
    if not ok or isSecret(value) then return false end
    return true, value
end

local function read(method, ...)
    local _, value = tryRead(method, ...)
    return value
end

local function slotNames(link)
    local identity = ns.GetItemLinkIdentity(link)
    if not identity or not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return end
    local itemID = tonumber(identity:match("^item:(%d+):") or identity:match("^item:(%d+)$"))
    if not itemID or itemID < 1 or itemID == math.huge then return end
    local ok, actualID, _, _, location = pcall(C_Item.GetItemInfoInstant, link)
    if not ok or isSecret(actualID) or isSecret(location) then return end
    if actualID == nil or (actualID == itemID and location == nil) then return nil, true end
    if actualID == itemID and type(location) == "string" then
        return slotsByType[location]
    end
end

function ns.HasInspectSlot(link)
    local slots, pending = slotNames(link)
    return slots ~= nil, pending
end

local function nameMatch(unit, name)
    local full = NameUtil and read(NameUtil.GetUnmodifiedUnitFullName, unit)
    if type(full) ~= "string" or full == "" then full = ns.GetLootPlayerNames(unit) end
    if full == name then return "exact" end
    local nameMethod = UnitNameUnmodified or UnitName
    local ok, short, surname = pcall(nameMethod, unit)
    if not ok or isSecret(short) or short ~= name or isSecret(surname) then return end
    if (type(full) ~= "string" or full == "") and (surname == nil or surname == "") then return "exact" end
    return "short"
end

local function findMember(name, class, expectedGUID)
    if isSecret(name) or type(name) ~= "string" or name == "" then return end
    if isSecret(class) or (class ~= nil and type(class) ~= "string") then return end
    if isSecret(expectedGUID) or (expectedGUID ~= nil
        and (type(expectedGUID) ~= "string" or expectedGUID == "")) then return end
    local result, guid, multiple, selfShortGUID, unverifiedMatch
    local selfGUID = read(UnitGUID, "player")
    local function consider(unit)
        local candidate = unit == "player" and selfGUID or read(UnitGUID, unit)
        if unit ~= "player" and selfGUID and candidate == selfGUID then return end
        if expectedGUID and candidate ~= expectedGUID then return end
        local match = nameMatch(unit, name)
        if not match then return end
        if class then
            local ok, _, classFile = pcall(UnitClass, unit)
            if not ok or isSecret(classFile) or type(classFile) ~= "string" or classFile == "" then
                unverifiedMatch = true
                return
            end
            if classFile ~= class then return end
        end
        if type(candidate) ~= "string" or candidate == "" then
            unverifiedMatch = true
            return
        end
        if match == "short" and not expectedGUID then
            if unit == "player" then
                selfShortGUID = candidate
            else
                unverifiedMatch = true
            end
            return
        end
        if guid and guid ~= candidate then multiple = true end
        result, guid = unit, candidate
    end
    local raid = read(IsInRaid) == true
    consider("player")
    local count = read(GetNumGroupMembers)
    if type(count) == "number" and count >= 1 and count <= 40 and count % 1 == 0 then
        for i = 1, raid and count or count - 1 do
            consider((raid and "raid" or "party") .. i)
        end
    end
    if multiple or unverifiedMatch or (selfShortGUID and guid) then return end
    if selfShortGUID then return "player", selfShortGUID end
    return result, guid
end

local function equipment(unit, names, canProveEmpty)
    local slotInfo = C_PaperDollInfo and C_PaperDollInfo.GetInventorySlotInfo or GetInventorySlotInfo
    local links, empty = {}, {}
    for i, name in ipairs(names) do
        local slot = read(slotInfo, name)
        if type(slot) == "number" and slot > 0 and slot < math.huge and slot % 1 == 0 then
            local known, link = tryRead(GetInventoryItemLink, unit, slot)
            if ns.GetItemLinkIdentity(link) then
                links[i] = link
            elseif known and link == nil and canProveEmpty then
                local idKnown, id = tryRead(GetInventoryItemID, unit, slot)
                if idKnown and (id == nil or id == 0) then empty[i] = true end
            end
        end
    end
    if next(links) or next(empty) then
        return { at = time(), links = links, count = #names, empty = empty }
    end
end

local function blizzardInspectActive()
    if InspectFrame and (read(InspectFrame.IsShown, InspectFrame) == true
        or type(read(InspectFrame.GetInspectUnit, InspectFrame)) == "string") then return true end
    -- The unit popup uses NotifyInspect for talent inspection as well.
    return PlayerSpellsFrame and type(read(PlayerSpellsFrame.GetInspectUnit, PlayerSpellsFrame)) == "string"
end

function ns.NewInspect()
    local pending, lastRequest
    local inspect = {}

    function inspect:Request(item, name, class, onResult, expectedGUID)
        local names = slotNames(item)
        if not names then return "unsupported" end
        local unit, guid = findMember(name, class, expectedGUID)
        if not unit then return "absent" end
        if guid == read(UnitGUID, "player") then
            local result = equipment("player", names, true)
            onResult(result and "ready" or "noData", result, result and guid)
            return
        end
        if pending then return "busy" end
        if blizzardInspectActive() then return "inspectOpen" end
        if read(InCombatLockdown) ~= false then return "combat" end
        if read(CanInspect, unit, true) ~= true then return "unavailable" end
        local now = GetTime()
        if lastRequest and now - lastRequest < 2 then return "busy" end
        if read(UnitGUID, unit) ~= guid then return "unavailable" end
        local request = { unit = unit, guid = guid, slots = names, onResult = onResult,
            deadline = now + INSPECT_TIMEOUT }
        pending, lastRequest = request, now
        local sent = pcall(NotifyInspect, unit)
        if pending ~= request then return end
        if not sent then
            pending = nil
            return "unavailable"
        end
        C_Timer.After(INSPECT_TIMEOUT, function()
            if pending ~= request then return end
            pending = nil
            onResult("timeout")
        end)
        return "loading"
    end

    function inspect:Ready(guid)
        local request = pending
        if not request or isSecret(guid) or type(guid) ~= "string" or guid ~= request.guid then return end
        pending = nil
        if GetTime() >= request.deadline then
            request.onResult("timeout")
            return
        end
        if read(UnitGUID, request.unit) ~= guid or blizzardInspectActive() then
            request.onResult("unavailable")
            return
        end
        local result = equipment(request.unit, request.slots)
        request.onResult(result and "ready" or "noData", result, result and guid)
    end

    function inspect:CancelPending()
        pending = nil
    end

    return inspect
end
