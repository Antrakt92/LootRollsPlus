local _, ns = ...

local Source = {}
ns.LiveSource = Source

local REFRESH_INTERVAL = 0.12
local START_TOLERANCE = 2
local HISTORY_RETRY_INTERVAL = 0.5
local HISTORY_RETRY_WINDOW = 2
local LIFECYCLE_EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "START_LOOT_ROLL", "CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS",
}
local EVENTS = {
    "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY",
    "GROUP_ROSTER_UPDATE", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "GAME_PAD_ACTIVE_CHANGED",
}
local STATE_NAMES = {
    NeedMainSpec = "need",
    NeedOffSpec = "offspec",
    Greed = "greed",
    Pass = "pass",
    Transmog = "transmog",
    Disenchant = "disenchant",
    NoRoll = "waiting",
}

local isSecret = _G.issecretvalue or function() return false end

local function clean(value, want)
    if not isSecret(value) and type(value) == want then return value end
end

local function number(value)
    if clean(value, "number") and value > -math.huge and value < math.huge then return value end
end

local function key(value)
    if number(value) and value >= 0 and value % 1 == 0 then return value end
end

local function read(method, ...)
    if type(method) ~= "function" then return end
    local ok, value = pcall(method, ...)
    if ok and not isSecret(value) then return value end
end

local function readActiveRollSet()
    local ids = clean(read(_G.GetActiveLootRollIDs), "table")
    if not ids then return end
    local active = {}
    for _, value in pairs(ids) do
        local id = key(value)
        if not id then return end
        active[id] = true
    end
    return active
end

local function updateObservationStart(observation, id, historyTime, duration, allowFallback)
    if not historyTime or observation.start and (not observation.provisionalStart or observation.historyKey) then return end
    local api = clean(_G.C_Loot, "table")
    local fullDuration = (api and number(read(api.GetLootRollDuration, id))) or number(duration)
    local remaining = number(read(_G.GetLootRollTimeLeft, id))
    if fullDuration and remaining and remaining > 0 and remaining <= fullDuration and fullDuration <= 180000 then
        observation.start = historyTime - (fullDuration - remaining) / 1000
        observation.provisionalStart = nil
    elseif allowFallback and not observation.start then
        -- START can reach us after the popup has already begun counting down.
        observation.start, observation.provisionalStart = historyTime, true
    end
end

local function confirmedStart(observation)
    -- The START delivery time can overlap a different drop of the same item.
    if not observation.provisionalStart then return observation.start end
end

local function itemLink(value)
    return type(ns.GetItemLinkIdentity) == "function" and ns.GetItemLinkIdentity(value)
end

local function player(raw, states)
    if not clean(raw, "table") then return end
    local name = clean(raw.playerName, "string")
    if not name or name == "" or name:find("[|%c]") then return end
    local class = clean(raw.playerClass, "string")
    if class and not class:match("^[A-Z]+$") then class = nil end
    local guid = clean(raw.playerGUID, "string")
    if isSecret(raw.playerGUID) then guid = false
    elseif guid == "" then guid = nil end
    local roll = key(raw.roll)
    if roll and (roll < 1 or roll > 100) then roll = nil end
    return {
        name = name,
        class = class,
        guid = guid,
        state = states[key(raw.state)],
        roll = roll,
        isSelf = clean(raw.isSelf, "boolean") == true,
    }
end

local function samePlayer(a, b)
    if not a or not b then return a == b end
    return a.name == b.name and a.class == b.class and a.guid == b.guid and a.state == b.state
        and a.roll == b.roll and a.isSelf == b.isSelf
end

local function sameSnapshot(a, b)
    if #a ~= #b then return false end
    for i, old in ipairs(a) do
        local new = b[i]
        if old.id ~= new.id or old.generation ~= new.generation or old.anchor ~= new.anchor or old.link ~= new.link
            or old.ambiguous ~= new.ambiguous or old.allPassed ~= new.allPassed
            or old.hasHistory ~= new.hasHistory or not samePlayer(old.winner, new.winner)
            or #old.rolls ~= #new.rolls then return false end
        for j, roll in ipairs(old.rolls) do
            if not samePlayer(roll, new.rolls[j]) then return false end
        end
    end
    return true
end

local function queueHistoryUpdate(updates, encounter, lootKey, deadline)
    local update = updates[encounter] or { keys = {} }
    -- Fresh events get a retry window on failure. A retry keeps the original deadline.
    if lootKey then update.keys[lootKey] = deadline or true else update.all = deadline or true end
    updates[encounter] = update
end

local function queueDueHistoryRetries(retries, updates, now)
    for token, retry in pairs(retries) do
        local update = updates[retry.encounter]
        local fresh = update and (retry.lootKey and update.keys[retry.lootKey] or not retry.lootKey and update.all)
        if fresh or now > retry.deadline then
            retries[token] = nil
        elseif now >= retry.at then
            queueHistoryUpdate(updates, retry.encounter, retry.lootKey, retry.deadline)
            retries[token] = nil
        end
    end
end

local function deferHistoryRead(retries, encounter, lootKey, previousDeadline, now)
    local deadline = previousDeadline == true and now + HISTORY_RETRY_WINDOW or previousDeadline
    local at = now + HISTORY_RETRY_INTERVAL
    if at <= deadline then
        local token = encounter .. ":" .. (lootKey or "")
        retries[token] = { encounter = encounter, lootKey = lootKey, deadline = deadline, at = at }
    end
end

local function readHistory(api, interests, bindings, updates, previous, retries, now)
    local drops = previous or {}
    for identity in pairs(drops) do
        if not interests[identity] then drops[identity] = nil end
    end
    local function collect(encounter, raw)
        if not clean(raw, "table") then return false end
        local lootKey = key(raw.lootListKey)
        local identity = itemLink(raw.itemHyperlink)
        local start = number(raw.startTime)
        if not lootKey or not identity then return false end
        local historyKey = encounter .. ":" .. lootKey
        local binding = bindings[historyKey]
        -- A key's item cannot change within one generation. Retry an
        -- unreadable or older generation as well.
        if binding and (not start or start < binding.historyStart
            or (start == binding.historyStart and identity ~= binding.identity)) then return false end
        local popupStart = interests[identity]
        if not popupStart then return end
        if not start then return false end
        if math.abs(start - popupStart) > START_TOLERANCE then return end
        local winner = clean(raw.winner, "table")
        local rollInfos = clean(raw.rollInfos, "table")
        local allPassed = clean(raw.allPassed, "boolean") == true
        local winningRoll, marked
        if winner or not allPassed then
            local guid = winner and clean(winner.playerGUID, "string")
            if winner and isSecret(winner.playerGUID) then guid = false end
            winningRoll, marked = ns.FindWinningLootRoll(rollInfos, winner and clean(winner.playerName, "string"),
                guid, winner and clean(winner.playerClass, "string"))
        end
        local choices = drops[identity] or {}
        drops[identity] = choices
        choices[historyKey] = {
            key = historyKey,
            encounter = encounter,
            lootKey = lootKey,
            start = start,
            rollInfos = rollInfos,
            winner = winner,
            winningRoll = winningRoll,
            allPassed = allPassed,
            finished = winner ~= nil or allPassed or marked == true,
        }
        if not rollInfos then return false end
    end

    local function scan(encounter)
        local rows = clean(read(api.GetSortedDropsForEncounter, encounter), "table")
        if not rows then return false end
        local complete = true
        for _, row in ipairs(rows) do
            if collect(encounter, row) == false then complete = false end
        end
        return complete
    end
    if not previous then
        local visited = { [0] = true }
        scan(0)
        local encounters = clean(read(api.GetAllEncounterInfos), "table") or {}
        for _, info in ipairs(encounters) do
            local encounter = clean(info, "table") and key(info.encounterID)
            if encounter and not visited[encounter] then
                visited[encounter] = true
                scan(encounter)
            end
        end
    end
    for encounter, update in pairs(updates) do
        for _, candidates in pairs(drops) do
            for historyKey, candidate in pairs(candidates) do
                if candidate.encounter == encounter and (update.all or update.keys[candidate.lootKey]) then
                    candidates[historyKey] = nil
                end
            end
        end
        if update.all and not scan(encounter) then
            deferHistoryRead(retries, encounter, nil, update.all, now)
        end
        for lootKey, deadline in pairs(update.keys) do
            local raw = clean(read(api.GetSortedInfoForDrop, encounter, lootKey), "table")
            if not raw or key(raw.lootListKey) ~= lootKey or collect(encounter, raw) == false then
                deferHistoryRead(retries, encounter, lootKey, deadline, now)
            end
        end
    end
    return drops
end

local function matchHistory(observation, choices)
    local start = confirmedStart(observation)
    if not choices or not start then return end
    local match
    for _, candidate in pairs(choices) do
        local retired = observation.retiredHistory and observation.retiredHistory[candidate.key] == candidate.start
        if not retired and math.abs(candidate.start - start) <= START_TOLERANCE then
            if match then
                observation.ambiguous = true
                return
            end
            match = candidate
        end
    end
    if match then
        if observation.historyKey and (observation.historyKey ~= match.key or observation.historyStart ~= match.start) then
            observation.ambiguous = true
            return
        end
        -- Completed records are only usable after a live binding was established.
        if match.finished and not observation.historyKey then return end
        observation.historyKey, observation.historyStart = match.key, match.start
        return match
    end
end

local function rememberAmbiguous(observation, other)
    observation.ambiguous, other.ambiguous = true, true
end

local function retireFinished(retired, id, observation, now)
    local prior = observation and observation.renderedFrom
    if prior and prior.finished and now then
        retired[id] = { identity = observation.identity, key = prior.key, start = prior.start, at = now }
    end
end

local function frameVisible(frame)
    return clean(frame, "table") and read(frame.IsVisible or frame.IsShown, frame) == true
end

local function geometryChanged(observation, anchor)
    local left, right = number(read(anchor.GetLeft, anchor)), number(read(anchor.GetRight, anchor))
    local top, bottom = number(read(anchor.GetTop, anchor)), number(read(anchor.GetBottom, anchor))
    local scale = number(read(anchor.GetEffectiveScale, anchor))
    local changed = observation.left ~= left or observation.right ~= right
        or observation.top ~= top or observation.bottom ~= bottom or observation.scale ~= scale
    observation.left, observation.right, observation.top, observation.bottom, observation.scale = left, right, top, bottom, scale
    return changed
end

function Source:GetRolls()
    return self.snapshot or {}
end

function Source:HasActiveRolls()
    local rollIDs = clean(read(_G.GetActiveLootRollIDs), "table")
    if rollIDs and next(rollIDs) then return true end
    local container = clean(_G.GroupLootContainer, "table")
    if not container then return false end
    local queue = clean(container.waitingRolls, "table")
    if queue and next(queue) then return true end
    for _, frame in pairs(clean(container.rollFrames, "table") or {}) do
        if frameVisible(frame) and (isSecret(frame.rollID) or frame.rollID ~= nil) then return true end
    end
    return false
end

function Source:Publish(snapshot, force)
    if force or not sameSnapshot(self:GetRolls(), snapshot) then
        self.snapshot = snapshot
        self.onChange(snapshot)
    end
end

function Source:Refresh(scanHistory)
    local container = clean(_G.GroupLootContainer, "table")
    local frames = container and clean(container.rollFrames, "table") or {}
    local queue = container and clean(container.waitingRolls, "table") or {}
    local api = clean(_G.C_LootHistory, "table") or {}
    local historyTime = number(read(api.GetLootHistoryTime))
    local now = number(read(_G.GetTime)) or 0
    local slots, ids, interests, owners, reportedCancelled = {}, {}, {}, {}, {}
    local missingIdentity = false

    local function observe(id, anchor, duration)
        if not id then
            missingIdentity = true
            return
        end
        if self.cancelled[id] then
            reportedCancelled[id] = true
            return
        end
        if ids[id] then return end
        ids[id] = true
        local observation = self.observations[id] or {}
        self.observations[id] = observation
        if not observation.identity then
            local link = clean(read(_G.GetLootRollItemLink, id), "string")
            local identity = itemLink(link)
            if identity then observation.link, observation.identity = link, identity end
        end
        updateObservationStart(observation, id, historyTime, duration)
        local ambiguous = self.disabledAmbiguity and self.disabledAmbiguity[id]
        if ambiguous and observation.identity == ambiguous.identity
            and (not observation.start or not ambiguous.start
                or math.abs(observation.start - ambiguous.start) <= START_TOLERANCE) then
            observation.ambiguous = true
        end
        if observation.identity then
            local other = owners[observation.identity]
            if other then
                rememberAmbiguous(observation, other)
            else
                owners[observation.identity] = observation
            end
        else
            missingIdentity = true
        end
        if anchor and observation.identity then
            local start = confirmedStart(observation)
            if start then interests[observation.identity] = start end
            return observation
        end
    end

    for slot, anchor in pairs(frames) do
        if key(slot) and clean(anchor, "table") then slots[#slots + 1] = slot end
    end
    table.sort(slots)
    local active, hasRollFrame = {}, false
    for _, slot in ipairs(slots) do
        local anchor = frames[slot]
        -- Bonus-roll frames also use the container but do not have a rollID.
        local rawID = anchor.rollID
        local id = key(rawID)
        if id and self.cancelled[id] then
            reportedCancelled[id] = true
        elseif isSecret(rawID) or rawID ~= nil then
            hasRollFrame = true
            local visible = frameVisible(anchor)
            local observation = observe(id, visible and anchor, number(anchor.rollTime))
            if observation then
                active[#active + 1] = { id = id, anchor = anchor, observation = observation }
            end
        end
    end
    for _, queued in ipairs(queue) do
        if clean(queued, "table") then observe(key(queued.rollID), nil, number(queued.rollTime)) end
    end
    if next(active) or next(self.observations) or next(self.cancelled) then
        local rollIDs = clean(read(_G.GetActiveLootRollIDs), "table") or {}
        for _, id in ipairs(rollIDs) do observe(key(id)) end
        for id, observation in pairs(self.observations) do
            if not ids[id] then
                if observation.seenAt and now - observation.seenAt < 1 and not self.cancelled[id] then
                    observe(id)
                else
                    retireFinished(self.retired, id, observation, now)
                    self.observations[id] = nil
                end
            end
        end
    end

    local identityChanged, layoutChanged = false, false
    for _, item in ipairs(active) do
        local observation = item.observation
        local start = confirmedStart(observation)
        if not observation.visible or observation.lookupStart ~= start then identityChanged = true end
        if geometryChanged(observation, item.anchor) then layoutChanged = true end
        observation.lookupStart = start
    end
    for _, observation in pairs(self.observations) do observation.visible = false end
    if identityChanged then
        self.warmupUntil, self.warmupAt = now + HISTORY_RETRY_WINDOW, now + HISTORY_RETRY_INTERVAL
    end
    local warmingUp = self.warmupAt and now >= self.warmupAt and now <= self.warmupUntil
    if next(interests) then
        queueDueHistoryRetries(self.historyRetries, self.updates, now)
        if scanHistory or identityChanged or warmingUp or next(self.updates) then
            local previous = not scanHistory and not identityChanged and not warmingUp and self.history or nil
            local bindings = {}
            for _, observation in pairs(self.observations) do
                if observation.historyKey then
                    local prior = bindings[observation.historyKey]
                    if not prior or prior.historyStart < observation.historyStart then
                        bindings[observation.historyKey] = observation
                    end
                end
            end
            self.history = readHistory(api, interests, bindings, self.updates, previous, self.historyRetries, now)
            self.updates = {}
            if warmingUp then self.warmupAt = now + HISTORY_RETRY_INTERVAL end
        end
    end
    if not next(active) then
        self.history, self.historyRetries = {}, {}
    end

    local enums = clean(_G.Enum, "table") or {}
    local enum = clean(enums.EncounterLootDropRollState, "table") or {}
    local states = {}
    for name, state in pairs(STATE_NAMES) do
        local value = key(enum[name])
        if value then states[value] = state end
    end
    local snapshot = {}
    for _, item in ipairs(active) do
        local observation = item.observation
        observation.visible = true
        local candidate
        if not observation.ambiguous and not missingIdentity then
            candidate = matchHistory(observation, self.history[observation.identity])
        end
        local ambiguous = observation.ambiguous == true
        local row = observation.rendered
        if not row or row.anchor ~= item.anchor or row.link ~= observation.link
            or row.ambiguous ~= ambiguous or observation.renderedFrom ~= candidate then
            -- Keep transient UI tied to this occurrence even when the native ID and item are reused.
            observation.generation = observation.generation or {}
            row = {
                id = item.id, generation = observation.generation, anchor = item.anchor, link = observation.link,
                rolls = {}, allPassed = false, ambiguous = ambiguous,
            }
            if candidate then
                local winner = player(candidate.winner, states)
                local winningRoll = player(candidate.winningRoll, states)
                if winner and winningRoll then
                    winner.class = winner.class or winningRoll.class
                    if winner.guid == nil then winner.guid = winningRoll.guid end
                    winner.state = winner.state or winningRoll.state
                    if winner.state == winningRoll.state then
                        winner.roll = winner.roll or winningRoll.roll
                    end
                end
                row.winner = winner or winningRoll
                local rolls = candidate.rollInfos
                for _, data in ipairs(rolls or {}) do
                    local roll = player(data, states)
                    if roll and roll.state then
                        row.rolls[#row.rolls + 1] = roll
                    end
                end
                row.hasHistory = rolls ~= nil and (#rolls == 0 or #row.rolls > 0)
                row.allPassed = not row.winner and candidate.allPassed
            end
            observation.rendered, observation.renderedFrom = row, candidate
        end
        snapshot[#snapshot + 1] = row
    end
    local force = self.forceRefresh or layoutChanged
    self.forceRefresh = false
    self:Publish(snapshot, force)
    return hasRollFrame or next(self.observations) ~= nil, reportedCancelled
end

function Source:Reset()
    self.observations, self.cancelled, self.history, self.updates = {}, {}, {}, {}
    self.forceRefresh, self.warmupUntil, self.warmupAt, self.historyRetries, self.retired = false, nil, nil, {}, {}
end

function Source:Wake(scanHistory)
    self.dirty = self.dirty or scanHistory
    self.frame:Show()
end

function Source:OnEvent(event, first, second)
    if event == "PLAYER_LEAVING_WORLD" then
        self.frame:Hide()
        self.inWorld = false
        self.disabledAmbiguity, self.disabledKnownRolls = nil, nil
        self:Reset()
        self:Publish({})
        return
    end
    if event == "PLAYER_ENTERING_WORLD" then
        self.disabledAmbiguity, self.disabledKnownRolls = nil, nil
        self:Reset()
        self.inWorld = true
    end
    if not self.inWorld then return end
    if not self.enabled then
        local id = key(first)
        local known = self.disabledKnownRolls
        -- While hidden, track lifecycle only for IDs already observed.
        if event == "START_LOOT_ROLL" and id then
            if self.cancelled[id] and self.disabledAmbiguity then self.disabledAmbiguity[id] = nil end
            self.cancelled[id], self.retired[id] = nil, nil
        elseif event == "CANCEL_LOOT_ROLL" and known and id and known[id] then
            self.cancelled[id] = true
        elseif event == "CANCEL_ALL_LOOT_ROLLS" then
            for observedID in pairs(known or {}) do self.cancelled[observedID] = true end
        end
        return
    end

    if event == "START_LOOT_ROLL" then
        local id = key(first)
        if id then
            local api = clean(_G.C_LootHistory, "table") or {}
            local link = clean(read(_G.GetLootRollItemLink, id), "string")
            local identity = itemLink(link)
            local historyTime = number(read(api.GetLootHistoryTime))
            local observation = self.observations[id] or {}
            if identity and observation.identity and identity ~= observation.identity then
                observation = {}
            elseif confirmedStart(observation) then
                local timing = {}
                updateObservationStart(timing, id, historyTime, second)
                -- A clean countdown can prove ID reuse before a cancel reaches us.
                if timing.start and timing.start - observation.start > START_TOLERANCE then
                    if observation.historyKey then
                        timing.retiredHistory = { [observation.historyKey] = observation.historyStart }
                    end
                    observation = timing
                end
            end
            updateObservationStart(observation, id, historyTime, second, true)
            observation.seenAt = number(read(_G.GetTime))
            if identity then observation.identity, observation.link = identity, link end
            self.retired[id] = nil
            if identity then
                local active
                for otherID, other in pairs(self.observations) do
                    if otherID ~= id and other.identity == identity then
                        local prior = other.renderedFrom
                        if prior and prior.finished and active == nil then active = readActiveRollSet() or false end
                        if prior and prior.finished and active and active[id] and not active[otherID] then
                            retireFinished(self.retired, otherID, other, observation.seenAt)
                            self.observations[otherID], self.cancelled[otherID] = nil, true
                        else
                            rememberAmbiguous(observation, other)
                        end
                    end
                end
                for otherID, prior in pairs(self.retired) do
                    if not observation.seenAt or observation.seenAt - prior.at > START_TOLERANCE then
                        self.retired[otherID] = nil
                    elseif prior.identity == identity then
                        if active == nil then active = readActiveRollSet() or false end
                        if active and active[id] and not active[otherID] then
                            local retired = observation.retiredHistory or {}
                            observation.retiredHistory = retired
                            retired[prior.key] = prior.start
                            self.cancelled[otherID] = true
                        end
                    end
                end
            end
            self.observations[id] = observation
            self.cancelled[id] = nil
        end
    elseif event == "CANCEL_LOOT_ROLL" then
        local id = key(first)
        if id then
            self.cancelled[id] = true
            retireFinished(self.retired, id, self.observations[id], number(read(_G.GetTime)))
            self.observations[id] = nil
        end
    elseif event == "CANCEL_ALL_LOOT_ROLLS" then
        local previous, cancelled = self.observations, self.cancelled
        self:Reset()
        for id in pairs(previous) do cancelled[id] = true end
        for id in pairs(readActiveRollSet() or {}) do cancelled[id] = true end
        local container = clean(_G.GroupLootContainer, "table") or {}
        local function cancelReportedRolls(rolls)
            for _, roll in pairs(clean(rolls, "table") or {}) do
                local id = clean(roll, "table") and key(roll.rollID)
                if id then cancelled[id] = true end
            end
        end
        cancelReportedRolls(container.rollFrames)
        cancelReportedRolls(container.waitingRolls)
        self.cancelled = cancelled
        self:Publish({})
    elseif event == "LOOT_HISTORY_CLEAR_HISTORY" then
        self.history, self.updates, self.historyRetries, self.retired = {}, {}, {}, {}
        for _, observation in pairs(self.observations) do
            observation.historyKey, observation.historyStart, observation.retiredHistory = nil, nil, nil
        end
        self:Publish({})
    elseif event == "LOOT_HISTORY_UPDATE_DROP" or event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
        local encounter = key(first)
        if encounter then
            if event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then
                queueHistoryUpdate(self.updates, encounter)
            else
                local lootKey = key(second)
                if lootKey then queueHistoryUpdate(self.updates, encounter, lootKey) end
            end
        end
    elseif event == "GROUP_ROSTER_UPDATE" or event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
        self.forceRefresh = true
    end
    -- Blizzard may install, replace or remove a popup later in the same event dispatch.
    self:Wake(event == "PLAYER_ENTERING_WORLD" or event == "LOOT_HISTORY_CLEAR_HISTORY")
end

function Source:Start(onChange, initiallyEnabled)
    self.onChange = onChange
    if self.frame then return end
    local frame = CreateFrame("Frame")
    self.frame = frame
    self.inWorld = true
    frame:Hide()
    for _, event in ipairs(LIFECYCLE_EVENTS) do frame:RegisterEvent(event) end
    local elapsed = 0
    frame:SetScript("OnEvent", function(_, ...) self:OnEvent(...) end)
    frame:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < REFRESH_INTERVAL then return end
        elapsed = 0
        local dirty = self.dirty
        self.dirty = false
        local active, reportedCancelled = self:Refresh(dirty)
        if not active then
            -- Blizzard can continue reporting a cancelled popup during a later wake.
            self.cancelled, self.updates = reportedCancelled, {}
            self.disabledAmbiguity = nil
            frame:Hide()
        end
    end)
    self:SetEnabled(initiallyEnabled ~= false)
end

function Source:SetEnabled(enabled)
    enabled = enabled == true
    if not self.frame or self.enabled == enabled then return end
    self.enabled = enabled
    if not enabled and self.observations then
        local ambiguity = self.disabledAmbiguity or {}
        local known = {}
        for id, observation in pairs(self.observations) do
            known[id] = true
            if observation.ambiguous then ambiguity[id] = observation end
        end
        self.disabledAmbiguity = next(ambiguity) and ambiguity or nil
        self.disabledKnownRolls = next(known) and known or nil
    end
    local cancelled, retired = self.cancelled, self.retired
    self:Reset()
    self.cancelled, self.retired = cancelled or {}, retired or {}
    if enabled then
        self.disabledKnownRolls = nil
        for _, event in ipairs(EVENTS) do self.frame:RegisterEvent(event) end
        if self.inWorld then self:Wake(true) end
    else
        for _, event in ipairs(EVENTS) do self.frame:UnregisterEvent(event) end
        self.frame:Hide()
        self:Publish({})
    end
end
