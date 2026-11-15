-- Loot chat format parsing adapted from Loot Rolls Inspector by Carlos (MIT).
local _, ns = ...

ns.CaptureEvents = {
    "LOOT_HISTORY_UPDATE_DROP",
    "LOOT_HISTORY_UPDATE_ENCOUNTER",
    "LOOT_HISTORY_CLEAR_HISTORY",
    "START_LOOT_ROLL",
    "CANCEL_LOOT_ROLL",
    "CANCEL_ALL_LOOT_ROLLS",
    "CHAT_MSG_LOOT",
}

local isSecret = _G.issecretvalue or function() return false end

local function clean(value, expectedType)
    if isSecret(value) or type(value) ~= expectedType then return nil end
    if expectedType == "number" and (value ~= value or value == math.huge or value == -math.huge) then
        return nil
    end
    return value
end

local function read(method, ...)
    if type(method) ~= "function" then return nil end
    local ok, value = pcall(method, ...)
    if ok and not isSecret(value) then return value end
end

local function nonempty(value)
    local s = clean(value, "string")
    if s and s ~= "" then return s end
end

local function id(value)
    local n = clean(value, "number")
    if n and n >= 0 and n % 1 == 0 then return n end
end

local function rollValue(value)
    local n = id(value)
    if n and n >= 1 and n <= 100 then return n end
end

local function stripColor(value)
    return value:match("^|c%x%x%x%x%x%x%x%x(.*)|r$")
        or value:match("^|cn[%w_]+:(.*)|r$") or value
end

local function itemLink(value)
    local link = nonempty(value)
    if not link or link:find("%c") then return nil end
    local identity = stripColor(link):match("^|H(item:%d+[^|]*)|h%[[^|]+%]|h$")
    if identity then return link, identity end
end

function ns.GetItemLinkIdentity(value)
    local _, identity = itemLink(value)
    return identity
end

local STATE_NAMES = {
    { "NeedMainSpec", "need" },
    { "NeedOffSpec", "need" },
    { "Greed", "greed" },
    { "Disenchant", "disenchant" },
    { "Transmog", "transmog" },
    { "Pass", "pass" },
    { "NoRoll", "undecided" },
}

local groupMember

local function readRoll(raw, stateTypes)
    if not clean(raw, "table") then return nil end
    local state = id(raw.state)
    local rollType = state and stateTypes[state]
    if not rollType then return nil end
    return {
        name = nonempty(raw.playerName),
        class = nonempty(raw.playerClass),
        type = rollType,
        value = rollValue(raw.roll),
    }
end

local function readRolls(rawRolls, stateTypes, previous, resolveLevels, playerLevels, winningRoll)
    if not clean(rawRolls, "table") then return nil end
    local rolls = {}
    for _, raw in ipairs(rawRolls) do
        local roll = readRoll(raw, stateTypes)
        if roll and roll.name then
            roll.isWinner = winningRoll ~= nil and rawequal(raw, winningRoll)
            local guid = nonempty(raw.playerGUID)
            if guid then
                local known = playerLevels[guid]
                if known and (not roll.class or known.class == roll.class) then
                    roll.class, roll.level = known.class, known.level
                end
            else
                local matched
                for _, old in ipairs(previous) do
                    if old.name == roll.name and old.class == roll.class then
                        if matched then
                            matched = nil
                            break
                        end
                        matched = old
                    end
                end
                roll.level = matched and matched.level
            end
            if not roll.level and resolveLevels then
                local class, level = groupMember(roll.name, guid)
                if class and (class == roll.class or (guid and not roll.class)) then
                    roll.class, roll.level = class, level
                end
            end
            if guid and roll.class then playerLevels[guid] = { class = roll.class, level = roll.level } end
            rolls[#rolls + 1] = roll
        end
    end
    return rolls
end

local function sameRolls(a, b)
    if #a ~= #b then return false end
    for i, lhs in ipairs(a) do
        local rhs = b[i]
        if lhs.name ~= rhs.name or lhs.class ~= rhs.class or lhs.type ~= rhs.type
            or lhs.value ~= rhs.value or lhs.isWinner ~= rhs.isWinner or lhs.level ~= rhs.level then
            return false
        end
    end
    return true
end

function ns.FindWinningLootRoll(rawRolls, winnerName, winnerGUID, winnerClass)
    if not clean(rawRolls, "table") then return nil end
    local marked, matched
    local duplicateName, hiddenName
    for _, raw in ipairs(rawRolls) do
        if clean(raw, "table") then
            local name = nonempty(raw.playerName)
            local guid = nonempty(raw.playerGUID)
            if clean(raw.isWinner, "boolean") == true then
                if marked then return nil, true end
                marked = raw
            end
            if (winnerGUID and guid == winnerGUID)
                or (name and name == winnerName and (not winnerGUID or not guid)) then
                duplicateName = duplicateName or matched ~= nil
                matched = raw
            elseif not name and (not winnerGUID or not guid) then
                hiddenName = true
            end
        else
            hiddenName = true
        end
    end
    local candidate = marked or (not duplicateName and not hiddenName and matched)
    if not candidate then return nil end
    local name = nonempty(candidate.playerName)
    local class = nonempty(candidate.playerClass)
    local guid = nonempty(candidate.playerGUID)
    if winnerGUID and guid and guid ~= winnerGUID then return nil, marked ~= nil end
    if winnerName and name and winnerName ~= name then return nil, marked ~= nil end
    if winnerClass and class and winnerClass ~= class then return nil, marked ~= nil end
    return candidate, marked ~= nil
end

local function bindParticipantGUIDs(rawRolls, winnerName, winnerGUID)
    if isSecret(rawRolls) then return false end
    if not clean(rawRolls, "table") then
        if winnerName and winnerGUID then return { [winnerName] = winnerGUID } end
        return nil
    end
    local bindings, names = {}, {}
    for _, raw in ipairs(rawRolls) do
        if not clean(raw, "table") then return false end
        local name = nonempty(raw.playerName)
        if not name then return false end
        if names[name] or isSecret(raw.playerGUID) then
            bindings[name] = false
        else
            bindings[name] = nonempty(raw.playerGUID)
        end
        names[name] = true
    end
    if winnerName and winnerGUID then
        local current = bindings[winnerName]
        if current == nil then
            bindings[winnerName] = winnerGUID
        elseif current ~= winnerGUID then
            bindings[winnerName] = false
        end
    end
    return next(bindings) and bindings or nil
end

local function sameBindings(a, b)
    if a == b then return true end
    if not a or not b then return false end
    for name, guid in pairs(a) do if b[name] ~= guid then return false end end
    for name in pairs(b) do if a[name] == nil then return false end end
    return true
end

local CHAT_FORMATS = {
    { "LOOT_ROLL_NEED", "need", { "player", "link" } },
    { "LOOT_ROLL_NEED_SELF", "need", { "link" } },
    { "LOOT_ROLL_GREED", "greed", { "player", "link" } },
    { "LOOT_ROLL_GREED_SELF", "greed", { "link" } },
    { "LOOT_ROLL_DISENCHANT", "disenchant", { "player", "link" } },
    { "LOOT_ROLL_DISENCHANT_SELF", "disenchant", { "link" } },
    { "LOOT_ROLL_PASSED", "pass", { "player", "link" } },
    { "LOOT_ROLL_PASSED_SELF", "pass", { "link" } },
    { "LOOT_ROLL_PASSED_AUTO", "pass", { "player", "link" } },
    { "LOOT_ROLL_PASSED_AUTO_FEMALE", "pass", { "player", "link" } },
    { "LOOT_ROLL_PASSED_SELF_AUTO", "pass", { "link" } },
    { "LOOT_ROLL_ROLLED_NEED", "need", { "value", "link", "player" } },
    { "LOOT_ROLL_ROLLED_GREED", "greed", { "value", "link", "player" } },
    { "LOOT_ROLL_ROLLED_DE", "disenchant", { "value", "link", "player" } },
    { "LOOT_ROLL_WON_NO_SPAM_NEED", "won", { "player", "value", "link" }, "need" },
    { "LOOT_ROLL_WON_NO_SPAM_GREED", "won", { "player", "value", "link" }, "greed" },
    { "LOOT_ROLL_WON_NO_SPAM_DE", "won", { "player", "value", "link" }, "disenchant" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_NEED", "won", { "value", "link" }, "need" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_GREED", "won", { "value", "link" }, "greed" },
    { "LOOT_ROLL_YOU_WON_NO_SPAM_DE", "won", { "value", "link" }, "disenchant" },
    { "LOOT_ROLL_WON", "won", { "player", "link" } },
    { "LOOT_ROLL_YOU_WON", "won", { "link" } },
    { "LOOT_ROLL_ALL_PASSED", "allpassed", { "link" } },
}

local function compileChatRules()
    local rules = {}
    for _, spec in ipairs(CHAT_FORMATS) do
        local fmt = nonempty(_G[spec[1]])
        if fmt then
            local pattern, positions = { "^" }, {}
            local offset, nextArgument = 1, 1
            while offset <= #fmt do
                local remaining = fmt:sub(offset)
                local index, kind, after = remaining:match("^%%(%d+)%$([sd])()")
                if not index then
                    kind, after = remaining:match("^%%([sd])()")
                    index = nextArgument
                end
                if kind then
                    positions[#positions + 1] = tonumber(index)
                    nextArgument = nextArgument + 1
                    pattern[#pattern + 1] = kind == "d" and "(%d+)" or "(.-)"
                    offset = offset + after - 1
                else
                    local char = fmt:sub(offset, offset)
                    if remaining:sub(1, 2) == "%%" then offset = offset + 1 end
                    pattern[#pattern + 1] = char:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
                    offset = offset + 1
                end
            end
            pattern[#pattern + 1] = "$"
            rules[#rules + 1] = {
                pattern = table.concat(pattern), positions = positions, fields = spec[3], kind = spec[2],
                winnerType = spec[4],
            }
        end
    end
    return rules
end

local function playerName(raw)
    local name = nonempty(raw)
    if not name then return nil end
    local plain = stripColor(name)
    local target, label = plain:match("^|Hplayer:([^:|]+)[^|]*|h%[([^|%]]+)%]|h$")
    name = target or label or plain
    if not name:find("[%c|]") then return name end
end

local function unitNames(unit)
    local nameUtil = _G.NameUtil
    local fullNameMethod = nameUtil and nameUtil.GetUnmodifiedUnitFullName
    local full = playerName(read(fullNameMethod, unit))
    local unitName = _G.UnitNameUnmodified or _G.UnitName
    if type(unitName) ~= "function" then return full end
    local ok, first, suffix = pcall(unitName, unit)
    if not ok then return full end
    first, suffix = playerName(first), playerName(suffix)
    if not full and first then
        local separator = _G.Constants and _G.Constants.CharacterNameSeparatorConsts
        local surnameSeparator = separator and nonempty(separator.CHARACTERNAME_SURNAME_SEPARATOR)
        if suffix and surnameSeparator then
            full = first .. surnameSeparator .. suffix
        elseif suffix and type(fullNameMethod) ~= "function" then
            full = first .. "-" .. suffix
        end
    end
    return full, first
end

local function parseChat(rules, message)
    if not nonempty(message) then return end
    for _, rule in ipairs(rules) do
        local matches = { message:match(rule.pattern) }
        if #matches > 0 then
            local result = { kind = rule.kind, winnerType = rule.winnerType }
            local extra = #rule.positions - #rule.fields
            for i, position in ipairs(rule.positions) do
                local field = rule.fields[position - extra]
                if field then result[field] = matches[i] end
            end
            local link, identity = itemLink(result.link)
            if link then
                result.identity = identity
                local name = result.player
                if not name or name == _G.YOU or name == "you" or name == "You" then
                    local full, first = unitNames("player")
                    name = full or first
                end
                result.player = playerName(name)
                result.value = rollValue(tonumber(result.value))
                return result
            end
        end
    end
end

groupMember = function(name, guid)
    if not name and not guid then return end
    local size = id(read(_G.GetNumGroupMembers)) or 0
    local raid = clean(read(_G.IsInRaid), "boolean") == true
    local seenUnit, seenName
    local function consider(unit)
        if guid then
            if nonempty(read(_G.UnitGUID, unit)) == guid then
                seenUnit = unit
                return true
            end
            return
        end
        local fullName, short = unitNames(unit)
        if name == short or name == fullName then
            if seenUnit then
                seenUnit = false
                return true
            end
            seenUnit, seenName = unit, fullName or short
        end
    end
    local found = not raid and consider("player")
    if not found then
        local count = raid and size or math.max(0, size - 1)
        for index = 1, math.min(count, 40) do
            if consider((raid and "raid" or "party") .. index) then break end
        end
    end
    if seenUnit and type(_G.UnitClass) == "function" then
        local ok, _, class = pcall(_G.UnitClass, seenUnit)
        if ok then
            local level = id(read(_G.UnitLevel, seenUnit))
            return nonempty(class), level and level > 0 and level or nil, seenName
        end
    end
end

function ns.NewCapture(callbacks)
    local engine = {}
    local api = _G.C_LootHistory or {}
    local enum = _G.Enum and _G.Enum.EncounterLootDropRollState or {}
    local states = {}
    for _, entry in ipairs(STATE_NAMES) do
        local state = id(enum[entry[1]])
        if state then states[state] = entry[2] end
    end
    local available = next(states) ~= nil
        and type(api.GetSortedInfoForDrop) == "function"
        and type(api.GetSortedDropsForEncounter) == "function"
    local seen = {}
    local participantGUIDs = setmetatable({}, { __mode = "k" })
    local captureStart
    local started = false
    local chatRules = compileChatRules()
    local chatByID = {}
    local chatByLink = {}
    local nativeStarts = {}
    local nativeActive = {}
    local canSchedule = type(_G.C_Timer) == "table" and type(_G.C_Timer.After) == "function"
    local fallbackAvailable = type(_G.GetLootRollItemLink) == "function"
        and canSchedule and #chatRules > 0

    local function removeChatSlot(slot)
        if chatByID[slot.id] ~= slot then return end
        chatByID[slot.id] = nil
        local group = chatByLink[slot.identity]
        if group then
            group[slot.id] = nil
            if not next(group) then chatByLink[slot.identity] = nil end
        end
    end

    local function closeChatSlot(slot)
        local entry = slot.entry
        if not entry.done and not entry.closed then
            entry.closed = true
            callbacks.onDrop(entry, false)
        end
    end

    local function suppressChatSlot(slot)
        removeChatSlot(slot)
        if callbacks.onRemove then
            callbacks.onRemove(slot.entry)
        else
            local entry = slot.entry
            entry.rolls = {}
            entry.winner, entry.winnerClass, entry.winnerType, entry.winnerValue = nil, nil, nil, nil
            entry.done, entry.allpassed, entry.closed, entry.ambiguous = false, false, true, true
            callbacks.onDrop(entry, false)
        end
    end

    local function markAmbiguous(slot)
        local entry = slot.entry
        if entry.ambiguous then return end
        entry.ambiguous = true
        entry.rolls = {}
        entry.winner, entry.winnerClass, entry.winnerType, entry.winnerValue = nil, nil, nil, nil
        entry.done, entry.allpassed = false, false
        callbacks.onDrop(entry, false)
    end

    local function stopNativeActivity(slot)
        slot.expiry = nil
        local entries = nativeActive[slot.identity]
        if entries then
            entries[slot] = nil
            if not next(entries) then nativeActive[slot.identity] = nil end
        end
    end

    local function observeNativeActivity(slot, raw, terminal)
        if terminal then
            stopNativeActivity(slot)
            return false
        end
        local identity = slot.identity
        if slot.entry.closed or slot.entry.done then return false end

        local duration = clean(raw.duration, "number")
        if duration and duration > 0 then slot.duration = duration end
        local margin = slot.duration or 120
        local historyTime = clean(read(api.GetLootHistoryTime), "number")
        local remaining = margin
        if historyTime and historyTime >= slot.startTime then
            remaining = margin - (historyTime - slot.startTime)
        end
        if remaining <= -2 then
            stopNativeActivity(slot)
            slot.entry.closed = true
            return true
        end
        if not canSchedule then return false end
        local delay = math.min(180, math.max(0, remaining + 2))
        local expires = time() + delay
        if slot.expiry and slot.expires <= expires then return false end
        local entries = nativeActive[identity] or {}
        nativeActive[identity] = entries
        entries[slot] = true
        local expiry = {}
        slot.expiry, slot.expires = expiry, expires
        _G.C_Timer.After(delay, function()
            if slot.expiry ~= expiry or nativeActive[identity] ~= entries then return end
            stopNativeActivity(slot)
            if not slot.entry.done and not slot.entry.closed then
                slot.entry.closed = true
                callbacks.onDrop(slot.entry, false)
            end
        end)
        return false
    end

    local function blockChatForNative(identity, startedAt, nativeSlot)
        local active = nativeActive[identity]
        if active and active[nativeSlot] then
            local marker = { t = startedAt, slot = nativeSlot }
            nativeStarts[identity] = marker
            _G.C_Timer.After(2, function()
                if nativeStarts[identity] == marker then nativeStarts[identity] = nil end
            end)
        end
        local slots = chatByLink[identity]
        if not slots then return end
        local candidate, multiple
        for _, slot in pairs(slots) do
            if math.abs(slot.entry.t - startedAt) <= 1 then
                multiple = multiple or candidate ~= nil
                candidate = slot
            end
        end
        if multiple then
            for _, slot in pairs(slots) do
                if math.abs(slot.entry.t - startedAt) <= 1 then markAmbiguous(slot) end
            end
        elseif candidate and not candidate.entry.ambiguous then
            suppressChatSlot(candidate)
        end
        if nativeActive[identity] then
            local otherSlots = chatByLink[identity]
            if otherSlots then
                for _, slot in pairs(otherSlots) do
                    if not slot.entry.done then markAmbiguous(slot) end
                end
            end
        end
    end

    local function startChatRoll(rollID, rollTime)
        if not fallbackAvailable then return end
        local rollID = id(rollID)
        local duration = clean(rollTime, "number")
        if not rollID or not duration or duration <= 0 then return end
        local link, identity = itemLink(read(_G.GetLootRollItemLink, rollID))
        if not link then return end
        local observedAt = time()
        local nativeStart = nativeStarts[identity]
        local active = nativeActive[identity]
        if nativeStart and active and active[nativeStart.slot] and math.abs(observedAt - nativeStart.t) <= 1 then
            return
        end
        if chatByID[rollID] then return end

        local lifetime = math.min(180, math.ceil(duration / 1000) + 5)
        local entry = { link = link, t = observedAt, rolls = {}, capture = "chat" }
        if active then entry.ambiguous = true end
        local slot = { id = rollID, identity = identity, entry = entry, expires = observedAt + lifetime }
        local group = chatByLink[identity] or {}
        chatByLink[identity] = group
        for _, other in pairs(group) do
            if not other.entry.done and not other.entry.closed and observedAt <= other.expires then
                entry.ambiguous = true
                markAmbiguous(other)
            end
        end
        group[rollID], chatByID[rollID] = slot, slot
        callbacks.onDrop(entry, true)
        _G.C_Timer.After(lifetime, function()
            if chatByID[rollID] ~= slot then return end
            closeChatSlot(slot)
            removeChatSlot(slot)
        end)
    end

    local function handleLootChat(message)
        local parsed = parseChat(chatRules, message)
        if not parsed then return end
        local slots = chatByLink[parsed.identity]
        if not slots then return end
        local target
        local observedAt = time()
        for _, slot in pairs(slots) do
            if observedAt <= slot.expires and not slot.entry.done then
                -- An overlapping identical item leaves later chat lines ambiguous
                -- too, even if one of its roll popups has already closed.
                if target or slot.entry.ambiguous then return end
                target = slot
            end
        end
        if not target then return end
        local entry = target.entry
        local getActiveRollIDs = _G.GetActiveLootRollIDs
        if type(getActiveRollIDs) == "function" then
            local activeIDs = clean(read(getActiveRollIDs), "table")
            if not activeIDs then return end
            for _, rawID in ipairs(activeIDs) do
                local rollID = id(rawID)
                if not rollID then return end
                if rollID ~= target.id then
                    local _, identity = itemLink(read(_G.GetLootRollItemLink, rollID))
                    if not identity then return end
                    if identity == parsed.identity then
                        markAmbiguous(target)
                        return
                    end
                end
            end
        end
        if parsed.kind == "allpassed" then
            entry.done, entry.allpassed, entry.closed = true, true, nil
        elseif not parsed.player then
            return
        else
            local class, level, fullName = groupMember(parsed.player)
            parsed.player = fullName or parsed.player
            local roll
            for _, candidate in ipairs(entry.rolls) do
                if candidate.name == parsed.player then
                    roll = candidate
                    break
                end
            end
            if parsed.kind == "won" then
                entry.done, entry.closed = true, nil
                entry.winner = parsed.player
                entry.winnerClass = roll and roll.class or class
                entry.winnerType = parsed.winnerType or (roll and roll.type ~= "pass" and roll.type or nil)
                entry.winnerValue = parsed.value or (entry.winnerType and roll and roll.value or nil)
                if parsed.winnerType and roll and roll.type ~= parsed.winnerType then
                    roll.type, roll.value = parsed.winnerType, parsed.value
                end
                if roll then roll.isWinner = true end
            elseif roll then
                if roll.type == parsed.kind and (not parsed.value or parsed.value == roll.value) then return end
                if roll.type ~= parsed.kind then roll.value = nil end
                roll.type = parsed.kind
                roll.value = parsed.value or roll.value
            else
                entry.rolls[#entry.rolls + 1] = {
                    name = parsed.player,
                    class = class,
                    level = level,
                    type = parsed.kind,
                    value = parsed.value,
                }
            end
        end
        if entry.done then
            target.expires = math.min(target.expires, observedAt + 2)
            _G.C_Timer.After(3, function()
                if chatByID[target.id] == target then removeChatSlot(target) end
            end)
        end
        callbacks.onDrop(entry, false)
    end

    local function bucket(encounterID)
        if not seen[encounterID] then seen[encounterID] = {} end
        return seen[encounterID]
    end

    local function getSourceName(encounterID)
        local info = clean(read(api.GetInfoForEncounter, encounterID), "table")
        return info and nonempty(info.encounterName)
    end

    local function snapshotDrop(encounterID, lootListKey, raw, sourceName, baseline)
        if not clean(raw, "table") then return end
        local link, identity = itemLink(raw.itemHyperlink)
        local startTime = clean(raw.startTime, "number")
        -- An encounter/key can be recycled. Without its start we cannot tell
        -- whether a same-item result belongs to the current drop.
        if not link or not startTime then return end

        local drops = bucket(encounterID)
        local slot = drops[lootListKey]
        if slot and startTime < slot.startTime then return end
        if slot and (slot.identity ~= identity or slot.startTime ~= startTime) then
            if slot.startTime == startTime then return end
            stopNativeActivity(slot)
            local replaced = slot.entry
            if replaced and not replaced.done and not replaced.closed then
                replaced.closed = true
                callbacks.onDrop(replaced, false)
            end
            slot = nil
        end
        if not slot then
            slot = { startTime = startTime, identity = identity, playerLevels = {} }
            drops[lootListKey] = slot
            if callbacks.getExisting then
                slot.entry = callbacks.getExisting(encounterID, lootListKey, startTime, link)
            end
            slot.ignored = not slot.entry and (baseline
                or (captureStart and startTime < captureStart))
        end
        if slot.ignored then return end
        local previous = slot.entry
        local isNew = previous == nil
        local entry = previous
        local knownStartedAt
        if isNew then
            local observedAt = time()
            local historyTime = clean(read(api.GetLootHistoryTime), "number")
            local t = observedAt
            if historyTime and historyTime >= startTime then
                local candidate = observedAt - math.floor(historyTime - startTime)
                if candidate > 0 then t, knownStartedAt = candidate, candidate end
            end
            entry = {
                encounterID = encounterID,
                lootListKey = lootListKey,
                link = link,
                t = t,
                rolls = {},
                capture = "history",
            }
            slot.entry = entry
        end

        local winnerInfo = clean(raw.winner, "table")
        local allpassed = clean(raw.allPassed, "boolean") == true
        local winnerName = winnerInfo and nonempty(winnerInfo.playerName)
        local winnerClass = winnerInfo and nonempty(winnerInfo.playerClass)
        local winningRoll
        if winnerInfo or not allpassed then
            winningRoll = ns.FindWinningLootRoll(raw.rollInfos, winnerName,
                winnerInfo and nonempty(winnerInfo.playerGUID), winnerClass)
        end
        local presentationWinner = winningRoll
        if not presentationWinner and not winnerInfo and not allpassed and entry.winner then
            presentationWinner = ns.FindWinningLootRoll(raw.rollInfos, entry.winner, slot.winnerGUID, entry.winnerClass)
        end
        local changed = observeNativeActivity(slot, raw, winnerInfo ~= nil or winningRoll ~= nil or allpassed) or isNew
        if knownStartedAt and fallbackAvailable then blockChatForNative(identity, knownStartedAt, slot) end
        if sourceName and sourceName ~= entry.sourceName then
            entry.sourceName = sourceName
            changed = true
        end
        if entry.startTime ~= slot.startTime then
            entry.startTime = slot.startTime
            changed = true
        end
        local rolls = readRolls(raw.rollInfos, states, entry.rolls,
            not entry.done and not entry.closed and not baseline, slot.playerLevels, presentationWinner)
        if rolls and not sameRolls(entry.rolls, rolls) then
            entry.rolls = rolls
            changed = true
        end

        local winner = readRoll(winnerInfo, states)
        local winnerValue = winnerInfo and rollValue(winnerInfo.roll)
        local winnerGUID
        if winnerInfo or winningRoll then
            local winnerType = winner and winner.type
            winnerGUID = (winnerInfo and nonempty(winnerInfo.playerGUID))
                or (winningRoll and nonempty(winningRoll.playerGUID))
            if winningRoll then
                local fallback = readRoll(winningRoll, states)
                winnerName = winnerName or nonempty(winningRoll.playerName)
                winnerClass = winnerClass or nonempty(winningRoll.playerClass)
                winnerType = winnerType or (fallback and fallback.type)
                winnerValue = winnerValue or rollValue(winningRoll.roll)
            end
            if winnerGUID and not winnerClass then
                local known = slot.playerLevels[winnerGUID]
                winnerClass = known and known.class
                if not winnerClass and not baseline then winnerClass = groupMember(winnerName, winnerGUID) end
            end
            if winnerType == "undecided" or winnerType == "pass" then winnerType = nil end
            local priorWinnerGUID = slot.winnerGUID
            local sameIdentity = winnerGUID and winnerGUID == priorWinnerGUID
            local changedIdentity = winnerGUID and priorWinnerGUID and not sameIdentity
            if winnerGUID then slot.winnerGUID = winnerGUID end
            if changedIdentity or (winnerName and winnerName ~= entry.winner) then
                entry.winner = winnerName
                entry.winnerClass = winnerClass
                entry.winnerType = winnerType
                entry.winnerValue = winnerValue
                changed = true
            elseif sameIdentity or not entry.winner or (winnerName and winnerName == entry.winner) then
                if winnerClass and winnerClass ~= entry.winnerClass then
                    entry.winnerClass = winnerClass
                    changed = true
                end
                if winnerType and winnerType ~= entry.winnerType then
                    entry.winnerType = winnerType
                    changed = true
                end
                if winnerValue and winnerValue ~= entry.winnerValue then
                    entry.winnerValue = winnerValue
                    changed = true
                end
            end
            if not entry.done or entry.allpassed or entry.closed then changed = true end
            entry.done, entry.allpassed, entry.closed = true, false, nil
        elseif allpassed and not entry.done then
            entry.done, entry.allpassed, entry.closed = true, true, nil
            changed = true
        end

        -- Store current player identities on the capture engine, outside SavedVariables.
        local bindings = false
        if not isSecret(raw.winner) then
            bindings = bindParticipantGUIDs(raw.rollInfos, winnerName, winnerGUID)
        end
        local bindingsChanged = not sameBindings(participantGUIDs[entry], bindings)
        participantGUIDs[entry] = bindings
        if changed or bindingsChanged then callbacks.onDrop(entry, isNew, baseline) end
    end

    local function scanEncounter(encounterID, baseline)
        local drops = clean(read(api.GetSortedDropsForEncounter, encounterID), "table")
        if not drops then return end
        local sourceName = getSourceName(encounterID)
        for _, raw in ipairs(drops) do
            local drop = clean(raw, "table")
            local lootListKey = drop and id(drop.lootListKey)
            if lootListKey then snapshotDrop(encounterID, lootListKey, drop, sourceName, baseline) end
        end
    end

    local function baseline()
        captureStart = clean(read(api.GetLootHistoryTime), "number")
        local encounters = clean(read(api.GetAllEncounterInfos), "table")
        if not encounters then return end
        for _, raw in ipairs(encounters) do
            local encounter = clean(raw, "table")
            local encounterID = encounter and id(encounter.encounterID)
            if encounterID then scanEncounter(encounterID, true) end
        end
    end

    function engine:Start()
        if started then return end
        started = true
        if available then baseline() end
    end

    function engine:Reset()
        seen = {}
        participantGUIDs = setmetatable({}, { __mode = "k" })
        chatByID, chatByLink, nativeStarts, nativeActive = {}, {}, {}, {}
        if available and started then
            -- Suppress rows still in the game's history after an addon history reset.
            baseline()
        end
    end

    function engine:GetParticipantGUID(entry, name)
        if not clean(entry, "table") or not nonempty(name) then return nil end
        local bindings = participantGUIDs[entry]
        if bindings then return bindings[name] end
        return bindings
    end

    function engine:HandleEvent(event, arg1, arg2)
        if not started then return end
        if event == "START_LOOT_ROLL" then
            startChatRoll(arg1, arg2)
            return
        elseif event == "CHAT_MSG_LOOT" then
            handleLootChat(arg1)
            return
        elseif event == "CANCEL_LOOT_ROLL" then
            local rollID = id(arg1)
            local slot = rollID and chatByID[rollID]
            if slot then closeChatSlot(slot) end
            return
        elseif event == "CANCEL_ALL_LOOT_ROLLS" then
            for _, slot in pairs(chatByID) do closeChatSlot(slot) end
            return
        end
        if not available then return end
        if event == "LOOT_HISTORY_CLEAR_HISTORY" then
            local previous = seen
            seen = {}
            nativeStarts, nativeActive = {}, {}
            participantGUIDs = setmetatable({}, { __mode = "k" })
            captureStart = clean(read(api.GetLootHistoryTime), "number")
            for _, drops in pairs(previous) do
                for _, slot in pairs(drops) do
                    local entry = slot.entry
                    if entry and not entry.done and not entry.closed then
                        entry.closed = true
                        callbacks.onDrop(entry, false)
                    end
                end
            end
            return
        end
        local encounterID = id(arg1)
        if not encounterID then return end
        if event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
            scanEncounter(encounterID, false)
        elseif event == "LOOT_HISTORY_UPDATE_DROP" then
            local lootListKey = id(arg2)
            if not lootListKey then return end
            local drop = clean(read(api.GetSortedInfoForDrop, encounterID, lootListKey), "table")
            if not drop or id(drop.lootListKey) ~= lootListKey then return end
            snapshotDrop(encounterID, lootListKey, drop, getSourceName(encounterID), false)
        end
    end

    return engine
end
