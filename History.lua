local _, addon = ...
local History = {}
addon.History = History

local isSecret = issecretvalue or function() return false end
local rollTypes = {
    need = true,
    greed = true,
    disenchant = true,
    pass = true,
}

local function clean(value, kind)
    if isSecret(value) or type(value) ~= kind then return end
    if kind == "number" and (value ~= value or value == math.huge or value == -math.huge) then return end
    return value
end

local function positiveInteger(value)
    value = clean(value, "number")
    if value and value > 0 and value == math.floor(value) then return value end
end

local function plainText(value)
    value = clean(value, "string")
    if value and value ~= "" and not value:find("[%c|]") then return value end
end

local function stripColor(value)
    return value:match("^|c%x%x%x%x%x%x%x%x(.*)|r$")
        or value:match("^|cn[%w_]+:(.*)|r$")
        or value
end

local function playerName(value)
    value = clean(value, "string")
    if not value then return end
    local uncolored = stripColor(value)
    local linkLabel = uncolored:match("^|Hplayer:[^|]+|h%[([^|%]]+)%]|h$")
    return plainText(linkLabel or uncolored)
end

local function itemLink(value)
    value = clean(value, "string")
    if not value or value:find("%c") then return end
    local uncolored = stripColor(value)
    if uncolored:match("^|Hitem:%d+[^|]*|h%[[^|]+%]|h$") then return value end
end

local function dayLabel(value)
    value = plainText(value)
    if not value then return end
    local year, month, day = value:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    year, month, day = tonumber(year), tonumber(month), tonumber(day)
    if not year or year == 0 or month < 1 or month > 12 or day < 1 then return end
    local maxDay
    if month == 2 then
        maxDay = year % 4 == 0 and (year % 100 ~= 0 or year % 400 == 0) and 29 or 28
    elseif month == 4 or month == 6 or month == 9 or month == 11 then
        maxDay = 30
    else
        maxDay = 31
    end
    if day <= maxDay then return value end
end

local function validTimestamp(value, dateKey)
    value = positiveInteger(value)
    if not value then return end
    local ok, day = pcall(dateKey, value)
    if ok and dayLabel(day) then return value, day end
end

local function compactRows(rows, keep)
    local keys = {}
    for key, row in pairs(rows) do
        if positiveInteger(key) and keep(row) then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for i, key in ipairs(keys) do rows[i] = rows[key] end
    for key in pairs(rows) do
        if not positiveInteger(key) or key > #keys then rows[key] = nil end
    end
end

local function mergeEntries(rows, added)
    local merged = {}
    for _, list in ipairs({rows, added}) do
        for _, entry in ipairs(list) do
            merged[#merged + 1] = {entry = entry, order = #merged + 1}
        end
    end
    table.sort(merged, function(a, b)
        if a.entry.t ~= b.entry.t then return a.entry.t < b.entry.t end
        return a.order < b.order
    end)
    for i, row in ipairs(merged) do rows[i] = row.entry end
    return rows
end

local function resultValue(value)
    value = positiveInteger(value)
    if value and value <= 100 then return value end
end

local function knownRollType(value)
    value = plainText(value)
    if rollTypes[value] or value == "transmog" or value == "undecided" then return value end
end

local function normalizeRoll(roll)
    if not clean(roll, "table") or not plainText(roll.name) then return false end
    roll.type = knownRollType(roll.type)
    if not roll.type then return false end
    roll.class, roll.level = plainText(roll.class), positiveInteger(roll.level)
    roll.value, roll.isWinner = resultValue(roll.value), clean(roll.isWinner, "boolean")
    return true
end

local function normalizeInspections(inspections)
    for name, snapshot in pairs(inspections) do
        if not plainText(name) or not clean(snapshot, "table") then
            inspections[name] = nil
        else
            snapshot.class, snapshot.at = plainText(snapshot.class), positiveInteger(snapshot.at)
            snapshot.atDrop = clean(snapshot.atDrop, "boolean") == true or nil
            snapshot.guid = snapshot.atDrop and plainText(snapshot.guid) or nil
            snapshot.links, snapshot.empty = clean(snapshot.links, "table") or {}, clean(snapshot.empty, "table") or {}
            for slot, link in pairs(snapshot.links) do
                if not positiveInteger(slot) or slot > 2 or not itemLink(link) then snapshot.links[slot] = nil end
            end
            for slot, empty in pairs(snapshot.empty) do
                if not positiveInteger(slot) or slot > 2 or clean(empty, "boolean") ~= true or snapshot.links[slot] then
                    snapshot.empty[slot] = nil
                end
            end
            if not next(snapshot.links) and not next(snapshot.empty) then
                inspections[name] = nil
            elseif snapshot.links[2] or snapshot.empty[2] then
                snapshot.count = 2
            else
                snapshot.count = clean(snapshot.count, "number") == 2 and 2 or 1
            end
        end
    end
end

local entryFlags = {"legacy", "done", "allpassed", "closed", "stale", "ambiguous"}

function History.NormalizeDays(days, dateKey)
    local function normalizeEntry(entry)
        if not clean(entry, "table") or not itemLink(entry.link) then return end
        local timestamp, day = validTimestamp(entry.t, dateKey)
        if not timestamp then return end
        entry.winner, entry.winnerClass = plainText(entry.winner), plainText(entry.winnerClass)
        entry.verifiedWinnerClass = plainText(entry.verifiedWinnerClass)
        entry.winnerType, entry.winnerValue = knownRollType(entry.winnerType), resultValue(entry.winnerValue)
        entry.sourceName = plainText(entry.sourceName)
        for _, field in ipairs(entryFlags) do entry[field] = clean(entry[field], "boolean") end
        local visit = clean(entry.visit, "table")
        local started = visit and validTimestamp(visit.startedAt, dateKey)
        if not started or started > timestamp or not positiveInteger(visit.id) or not plainText(visit.name) then entry.visit = nil end
        entry.inspections = clean(entry.inspections, "table")
        if entry.inspections then normalizeInspections(entry.inspections) end
        entry.rolls = clean(entry.rolls, "table") or {}
        compactRows(entry.rolls, normalizeRoll)
        return day
    end
    local moved = {}
    for day, entries in pairs(days) do
        if not dayLabel(day) or not clean(entries, "table") then
            days[day] = nil
        else
            compactRows(entries, function(entry)
                local expectedDay = normalizeEntry(entry)
                if not expectedDay then return false end
                if expectedDay == day then return true end
                local target = moved[expectedDay] or {}
                moved[expectedDay] = target
                target[#target + 1] = entry
                return false
            end)
            if #entries == 0 then
                days[day] = nil
            else
                for index = 2, #entries do
                    if entries[index - 1].t > entries[index].t then
                        mergeEntries(entries, {})
                        break
                    end
                end
            end
        end
    end
    for day, entries in pairs(moved) do
        days[day] = mergeEntries(days[day] or {}, entries)
    end
end

local function copyRoll(original)
    if not clean(original, "table") then return end
    local name = playerName(original.name)
    local rollType = clean(original.type, "string")
    if not name or not rollTypes[rollType] then return end
    local value = original.value
    -- Inspector stores numbers matched by its chat parser as digit strings.
    local digits = clean(value, "string")
    if digits and digits:match("^%d%d?%d?$") then value = tonumber(digits) end
    return {name = name, type = rollType, value = resultValue(value)}
end

local function copyEntry(original)
    if not clean(original, "table") then return end
    local link, timestamp = itemLink(original.link), positiveInteger(original.t)
    if not link or not timestamp then return end
    local winner = playerName(original.winner)
    local entry = {link = link, t = timestamp, rolls = {}, winner = winner, legacy = true}
    entry.allpassed = not winner and clean(original.allpassed, "boolean") == true
    entry.done = winner ~= nil or entry.allpassed or clean(original.done, "boolean") == true

    if clean(original.rolls, "table") then
        local winningRoll, ambiguousWinner
        for _, rawRoll in ipairs(original.rolls) do
            local roll = copyRoll(rawRoll)
            if roll then
                entry.rolls[#entry.rolls + 1] = roll
                if roll.name == winner then
                    ambiguousWinner = ambiguousWinner or winningRoll ~= nil
                    winningRoll = roll
                end
            end
        end
        if winningRoll and winningRoll.type ~= "pass" and not ambiguousWinner then
            entry.winnerType = winningRoll.type
            entry.winnerValue = winningRoll.value
        end
    end
    return entry
end

function History.Import(charDB, upstreamCharDB, dateKey)
    if charDB.importedInspector or not clean(upstreamCharDB, "table") then return false end
    local upstreamDays = clean(upstreamCharDB.days, "table")
    if not upstreamDays then return false end

    -- The old account-wide history had no owner. Only import records the
    -- upstream addon already assigned to this character.
    local pending = {}
    for key, entries in pairs(upstreamDays) do
        if dayLabel(key) and clean(entries, "table") then
            for _, original in ipairs(entries) do
                local entry = copyEntry(original)
                if entry then
                    local _, day = validTimestamp(entry.t, dateKey)
                    if day then
                        pending[day] = pending[day] or {}
                        local list = pending[day]
                        list[#list + 1] = entry
                    end
                end
            end
        end
    end

    if not next(pending) then return false end
    for day, imports in pairs(pending) do
        charDB.days[day] = mergeEntries(clean(charDB.days[day], "table") or {}, imports)
    end
    charDB.importedInspector = true
    return true
end

function History.NewVisits(charDB)
    local current
    local initialized = false
    local previous = clean(charDB.currentVisit, "table")
    local previousID = previous and positiveInteger(previous.id) or 0
    local lastID = math.max(positiveInteger(charDB.lastVisitID) or 0, previousID)
    charDB.lastVisitID = lastID
    local controller = {}

    function controller:Update(instanceID, name, now, isReload)
        instanceID, name, now = positiveInteger(instanceID), plainText(name), positiveInteger(now)
        local candidate = current
        if not initialized and isReload == true then candidate = previous end
        initialized, previous = true, nil
        if not (instanceID and name and now) then
            current = nil
        elseif candidate and positiveInteger(candidate.id) and positiveInteger(candidate.startedAt)
            and candidate.startedAt <= now and clean(candidate.instanceID, "number") == instanceID
            and plainText(candidate.name) == name then
            current = candidate
        else
            lastID = lastID + 1
            charDB.lastVisitID = lastID
            current = {id = lastID, instanceID = instanceID, name = name, startedAt = now}
        end
        charDB.currentVisit = current
        return current
    end

    function controller:Get()
        return current
    end

    return controller
end

local function firstName(name)
    return name:match("^[^%s%-]+")
end

local function classFromParty(party, name, classColors, unique)
    local short = firstName(name)
    if short == name and not unique then return end
    local class = plainText(party[name])
    -- Atlas records UnitName's short label. A realm suffix is an identity
    -- qualifier, unlike the optional display surname seen on Forever.
    if not class and unique and not name:find("-", 1, true) then
        class = plainText(party[short])
    end
    if class and classColors[class] then return class end
end

local function atlasLootByItem(runs, itemIdentity)
    local byItem = {}
    for _, run in ipairs(runs) do
        if clean(run, "table") then
            local started, last = positiveInteger(run.started), positiveInteger(run.last)
            local loot, party = clean(run.loot, "table"), clean(run.party, "table")
            if started and last and last >= started and loot then
                for _, drop in ipairs(loot) do
                    local winner = clean(drop, "table") and plainText(drop.who)
                    local item = winner and itemIdentity(drop.link)
                    if item then
                        local byWinner = byItem[item] or {}
                        byItem[item] = byWinner
                        local matches = byWinner[winner] or {}
                        byWinner[winner] = matches
                        matches[#matches + 1] = {started = started, last = last, party = party, matchedRows = 0}
                    end
                end
            end
        end
    end
    return byItem
end

local function findLegacyMatches(days, byItem, itemIdentity)
    local pairsFound = {}
    for _, entries in pairs(days) do
        for _, entry in ipairs(clean(entries, "table") or {}) do
            local name = entry.legacy and plainText(entry.winner)
            local timestamp = name and positiveInteger(entry.t)
            local item = timestamp and itemIdentity(entry.link)
            local candidates = item and byItem[item] and byItem[item][name]
            if candidates then
                local only, count = nil, 0
                for _, candidate in ipairs(candidates) do
                    if timestamp >= candidate.started and timestamp <= candidate.last + 5 then
                        candidate.matchedRows = candidate.matchedRows + 1
                        only, count = candidate, count + 1
                    end
                end
                if count > 0 then
                    pairsFound[#pairsFound + 1] = {entry = entry, loot = count == 1 and only or nil}
                end
            end
        end
    end
    return pairsFound
end

function History.RecoverClasses(days, atlas, itemIdentity, classColors, selfName, selfClass, selfFullName)
    local runs = clean(atlas, "table") and clean(atlas.runLog, "table")
    if not runs or not classColors then return 0 end
    selfName, selfClass, selfFullName = plainText(selfName), plainText(selfClass), plainText(selfFullName)
    local recovered = 0
    local byItem = atlasLootByItem(runs, itemIdentity)
    for _, match in ipairs(findLegacyMatches(days, byItem, itemIdentity)) do
        local entry, loot = match.entry, match.loot
        local name, party = entry.winner, loot and loot.party
        -- Either side can be ambiguous when more than one copy drops.
        if not loot or loot.matchedRows ~= 1 then
            if entry.verifiedWinnerClass then
                entry.verifiedWinnerClass = nil
                recovered = recovered + 1
            end
        elseif party then
            local counts, changed, winnerInRolls = {}, false, false
            for _, roll in ipairs(entry.rolls or {}) do
                local key = firstName(roll.name)
                if key then counts[key] = (counts[key] or 0) + 1 end
                if roll.name == name then winnerInRolls = true end
            end
            local winnerKey = firstName(name)
            if winnerKey and not winnerInRolls then counts[winnerKey] = (counts[winnerKey] or 0) + 1 end
            local winnerClass = classFromParty(party, name, classColors, counts[winnerKey] == 1)
            if not entry.winnerClass then
                entry.winnerClass = winnerClass
                changed = entry.winnerClass ~= nil
            end
            -- The matched Atlas loot record identifies the winner. Other party
            -- members can only be matched by name within the run.
            local verifiedClass = winnerClass == entry.winnerClass and winnerClass or nil
            if entry.verifiedWinnerClass ~= verifiedClass then
                entry.verifiedWinnerClass, changed = verifiedClass, true
            end
            for _, roll in ipairs(entry.rolls or {}) do
                if not roll.class then
                    local class = classFromParty(party, roll.name, classColors, counts[firstName(roll.name)] == 1)
                    if not class and selfClass and classColors[selfClass]
                        and (roll.name == selfFullName or (roll.name == selfName and counts[firstName(roll.name)] == 1)) then
                        class = selfClass
                    end
                    if class then roll.class, changed = class, true end
                    if class and roll.name == name and not entry.winnerClass then entry.winnerClass = class end
                end
            end
            if changed then recovered = recovered + 1 end
        end
    end
    return recovered
end
