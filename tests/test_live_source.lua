local addonPath = arg[1] or "."
local secret = {}
function issecretvalue(value) return value == secret end

local link = "|cff0070dd|Hitem:42:0|h[One]|h|r"
local equivalent = "|cnIQ3:|Hitem:42:0|h[Other display name]|h|r"
local different = "|cff0070dd|Hitem:42:1|h[Other suffix]|h|r"
local separate = "|cff1eff00|Hitem:43:0|h[Two]|h|r"

local frames, timers, rolls, encounters, drops, historyFailure, clock
local function schedule(delay, callback)
    local timer = { at = clock + delay, callback = callback }
    function timer:Cancel() self.cancelled = true end
    timers[#timers + 1] = timer
    return timer
end
C_Timer = { After = schedule, NewTimer = schedule }
function GetTime() return clock end
function IsInRaid() return false end
function IsInGroup() return true end
function GetNumGroupMembers() return 5 end
function GetActiveLootRollIDs()
    local list = {}
    for id in pairs(rolls) do list[#list + 1] = id end
    return list
end
function GetLootRollItemLink(id)
    local roll = rolls[id]
    return roll and roll.link
end
function GetLootRollItemInfo(id)
    if rolls[id] then return 134943, "Test drop" end
end
function GetLootRollTimeLeft(id)
    local roll = rolls[id]
    return roll and math.max(0, 1000 * (roll.finish - clock)) or 0
end
C_Loot = { GetLootRollDuration = function(id) return rolls[id] and 60000 end }
Enum = { EncounterLootDropRollState = {
    NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5,
} }
C_LootHistory = {
    GetLootHistoryTime = function() return clock end,
    GetAllEncounterInfos = function()
        if historyFailure then error("history unavailable") end
        return encounters
    end,
    GetSortedDropsForEncounter = function(id)
        if historyFailure then error("history unavailable") end
        return drops[id]
    end,
    GetSortedInfoForDrop = function(encounterID, lootListKey)
        if historyFailure then error("history unavailable") end
        for _, raw in ipairs(drops[encounterID] or {}) do
            if type(raw) == "table" and raw.lootListKey == lootListKey then return raw end
        end
    end,
}

local function newFrame()
    local frame = { events = {}, scripts = {}, shown = true }
    function frame:RegisterEvent(event) self.events[event] = true end
    function frame:UnregisterEvent(event) self.events[event] = nil end
    function frame:UnregisterAllEvents() self.events = {} end
    function frame:SetScript(script, callback) self.scripts[script] = callback end
    function frame:HookScript(script, callback)
        local previous = self.scripts[script]
        self.scripts[script] = function(...)
            if previous then previous(...) end
            callback(...)
        end
    end
    function frame:IsVisible() return self.shown end
    function frame:IsShown() return self.shown end
    function frame:Show() self.shown = true end
    function frame:Hide() self.shown = false end
    return frame
end
function CreateFrame()
    local frame = newFrame()
    frames[#frames + 1] = frame
    return frame
end

local function emit(event, ...)
    for _, frame in ipairs(frames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

local function advance(seconds)
    local stop = clock + (seconds or 0.3)
    local executed = 0
    while true do
        local earliest, index
        for i, timer in ipairs(timers) do
            if timer.at <= stop and (not earliest or timer.at < earliest.at) then
                earliest, index = timer, i
            end
        end
        if not earliest then break end
        clock = earliest.at
        table.remove(timers, index)
        if not earliest.cancelled then earliest.callback() end
        executed = executed + 1
        assert(executed < 500, "timer work did not settle")
    end
    local elapsed = stop - clock
    clock = stop
    for _, frame in ipairs(frames) do
        if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, elapsed) end
    end
end

local function reset()
    frames, timers, rolls, drops = {}, {}, {}, {}
    encounters = { { encounterID = 0 }, { encounterID = 77 } }
    historyFailure, clock = false, 500
    GroupLootContainer = newFrame()
    GroupLootContainer.rollFrames, GroupLootContainer.waitingRolls = {}, {}
end

local function popup(id, slot, item, started)
    rolls[id] = { link = item, finish = (started or clock) + 60 }
    if not slot then
        table.insert(GroupLootContainer.waitingRolls, { rollID = id, rollTime = 60000 })
        return
    end
    local frame = newFrame()
    frame.rollID, frame.rollTime = id, 60000
    GroupLootContainer.rollFrames[slot] = frame
    return frame
end

local function player(name, class, state, roll, isSelf)
    return {
        playerName = name, playerGUID = type(name) == "string" and "Player-" .. name or secret,
        playerClass = class, state = state, roll = roll, isSelf = isSelf or false,
    }
end

local function drop(key, start, item, players, winner, allPassed)
    return {
        lootListKey = key, startTime = start, duration = 60, itemHyperlink = item,
        rollInfos = players, winner = winner, allPassed = allPassed or false,
    }
end

local function newSource()
    local ns = {}
    assert(loadfile(addonPath .. "/Capture.lua"))("LootRollsPlus", ns)
    assert(loadfile(addonPath .. "/LiveSource.lua"))("LootRollsPlus", ns)
    assert(ns.LiveSource, "expected a separate live source")
    local notices = { count = 0 }
    ns.LiveSource:Start(function() notices.count = notices.count + 1 end)
    ns.LiveSource:SetEnabled(true)
    advance()
    return ns.LiveSource, notices
end

local function lookup(source, id)
    for _, row in ipairs(source:GetRolls()) do
        if row.id == id then return row end
    end
end

local function expect(source, id)
    local row = lookup(source, id)
    assert(row, "missing popup " .. id)
    return row
end

local need = player("Mage", "MAGE", 0)
local offspec = player("Paladin", "PALADIN", 1, 94)
local waiting = player("Waiting", "DRUID", 4)

-- Start a real roll with no history yet; the event can beat Blizzard creating its popup.
reset()
local source, notices = newSource()
emit("START_LOOT_ROLL", 123, 60000)
local started = clock
local first = popup(123, 3, link)
advance()
local pending = expect(source, 123)
assert(pending.anchor == first and #pending.rolls == 0, "no history must not invent responses")
assert(notices.count > 0)

local current = drop(19, started, equivalent, { need, offspec, waiting })
local old = drop(20, started - 120, equivalent, { player("Old", "ROGUE", 0, 100) })
local wrong = drop(21, started, different, { player("WrongSuffix", "SHAMAN", 3, 100) })
drops[77] = { old, wrong, current }
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
local live = expect(source, 123)
assert(#live.rolls == 3, "the current exact-item history should match despite old and wrong-suffix rows")
assert(live.rolls[1].name == "Mage" and live.rolls[1].state == "need" and live.rolls[1].roll == nil)
assert(live.rolls[2].state == "offspec" and live.rolls[2].roll == 94)
assert(live.rolls[3].state == "waiting" and live.winner == nil)

current.rollInfos = secret
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
local restricted = expect(source, 123)
assert(not restricted.hasHistory and #restricted.rolls == 0,
    "an unreadable response list must not be presented as a verified empty list")

local winner = player("Mage", "MAGE", 0, 96)
local protectedGUID = player("ProtectedGUID", "HUNTER", 3, 75)
protectedGUID.playerGUID = secret
current.rollInfos = { winner, offspec, waiting, player(secret, secret, 0, 100),
    player("BadState", "HUNTER", secret, 100), player("BadRoll", secret, 3, secret), protectedGUID }
current.winner = winner
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
local final = expect(source, 123)
assert(final.winner and final.winner.name == "Mage" and final.winner.roll == 96)
local protectedNumberSeen
local protectedGUIDSeen
for _, participant in ipairs(final.rolls) do
    assert(participant.name ~= secret and participant.class ~= secret and participant.roll ~= secret)
    if participant.name == "BadRoll" then
        protectedNumberSeen = participant.roll == nil and participant.state == "greed"
    elseif participant.name == "ProtectedGUID" then
        protectedGUIDSeen = participant.guid == false and participant.state == "greed"
    end
end
assert(protectedNumberSeen, "a known choice should survive a secret roll number")
assert(protectedGUIDSeen, "restricted identities must block name-only inspection without losing the vote")

current.rollInfos = {winner, offspec}
current.winner = player("Mage", "MAGE", 1)
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
local offspecWinner = expect(source, 123).winner
assert(offspecWinner and offspecWinner.state == "offspec" and not offspecWinner.roll,
    "the winner must not inherit a main-spec score for an off-spec choice")
current.winner = player("Mage", "MAGE")
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
assert(expect(source, 123).winner.state == "need" and expect(source, 123).winner.roll == 96,
    "a uniquely matched native vote can fill both fields when the winner omits the choice")
current.winner = {playerName = "Mage", playerGUID = secret}
emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
advance()
local protectedWinner = expect(source, 123).winner
assert(protectedWinner and protectedWinner.guid == false and not protectedWinner.roll and not protectedWinner.state,
    "an unmarked same-name participant cannot enrich a winner whose identity is explicitly restricted")

-- A different popup can immediately reuse the same Blizzard frame object.
emit("CANCEL_LOOT_ROLL", 123)
rolls[123] = nil
rolls[124] = { link = separate, finish = clock + 60 }
first.rollID = 124
emit("START_LOOT_ROLL", 124, 60000)
advance()
assert(not lookup(source, 123) and expect(source, 124).anchor == first)
assert(#expect(source, 124).rolls == 0, "frame reuse leaked another item's data")

-- Ambiguous identical copies, including one on Blizzard's waiting queue, never steal another copy's response.
reset()
local anchor = popup(201, 1, link)
popup(202, nil, equivalent)
local twinsStart = clock
drops[77] = { drop(30, twinsStart, link, { need }) }
source = newSource()
assert(not lookup(source, 202), "queued item has no visible anchor")
local twin = expect(source, 201)
assert(twin.anchor == anchor and twin.ambiguous and #twin.rolls == 0)
local shownTwin = popup(202, 2, equivalent, twinsStart)
GroupLootContainer.waitingRolls = {}
emit("START_LOOT_ROLL", 202, 60000)
advance()
assert(expect(source, 202).anchor == shownTwin and expect(source, 202).ambiguous
    and #expect(source, 202).rolls == 0)
emit("CANCEL_LOOT_ROLL", 202)
rolls[202], GroupLootContainer.rollFrames[2] = nil, nil
advance()
assert(expect(source, 201).ambiguous and #expect(source, 201).rolls == 0,
    "canceling a twin must not authorize its history on the survivor")
emit("START_LOOT_ROLL", 201, 60000)
advance()
assert(expect(source, 201).ambiguous and #expect(source, 201).rolls == 0,
    "a duplicate START must preserve a known twin ambiguity")
source:SetEnabled(false)
source:SetEnabled(true)
advance()
assert(expect(source, 201).ambiguous and #expect(source, 201).rolls == 0,
    "toggling the view must preserve a known twin ambiguity")

-- Reload with visible rolls and history already available, including trash under encounter 0.
reset()
popup(301, 4, separate, clock - 4)
local existing = drop(12, clock - 4, separate, { player("Me", "WARRIOR", 3, 88, true) })
drops[0] = { existing }
source = newSource()
assert(expect(source, 301).rolls[1].isSelf and expect(source, 301).rolls[1].roll == 88)

historyFailure = true
drops[0] = {}
emit("LOOT_HISTORY_CLEAR_HISTORY")
advance()
assert(#expect(source, 301).rolls == 0, "cleared or unreadable history leaked a stale response")
historyFailure = false
local nextStart = clock
local newAnchor = popup(302, 4, separate)
rolls[301] = nil
emit("CANCEL_LOOT_ROLL", 301)
emit("START_LOOT_ROLL", 302, 60000)
local everyonePassed = drop(12, nextStart, separate, { player("Pass", "ROGUE", 5) })
local terminalOnly = drop(13, nextStart, separate, { player("Ghost", "MAGE", 5) }, nil, true)
drops[0] = { terminalOnly }
emit("LOOT_HISTORY_UPDATE_ENCOUNTER", 0)
advance()
assert(#expect(source, 302).rolls == 0, "a terminal-only history entry can belong to a previous item")
local flagOnly = player("Flagged", "MAGE", 0, 100)
flagOnly.isWinner = true
drops[0] = { drop(14, nextStart, separate, { flagOnly }) }
emit("LOOT_HISTORY_UPDATE_ENCOUNTER", 0)
advance()
assert(#expect(source, 302).rolls == 0, "a winner flag alone also makes a terminal-only entry unsafe")
drops[0] = { everyonePassed }
emit("LOOT_HISTORY_UPDATE_ENCOUNTER", 0)
advance()
everyonePassed.allPassed = true
emit("LOOT_HISTORY_UPDATE_DROP", 0, 12)
advance()
local nextRoll = expect(source, 302)
assert(nextRoll.anchor == newAnchor and nextRoll.allPassed and nextRoll.winner == nil)
assert(nextRoll.rolls[1].state == "pass")

source:SetEnabled(false)
advance()
assert(#source:GetRolls() == 0, "disabled source should release live rows")
source:SetEnabled(true)
advance()
assert(lookup(source, 302), "reenabling should adopt an already-visible popup")
emit("CANCEL_ALL_LOOT_ROLLS")
GroupLootContainer.rollFrames, rolls = {}, {}
advance()
assert(#source:GetRolls() == 0, "cancel-all must stop showing live rows")

reset()
local initial = drop(15, clock, link, { need, offspec })
drops[77] = { initial }
popup(401, 1, link)
source = newSource()
assert(#expect(source, 401).rolls == 2)
initial.rollInfos = { flagOnly }
emit("LOOT_HISTORY_UPDATE_DROP", 77, 15)
advance()
assert(expect(source, 401).winner.name == "Flagged", "a unique native winner flag resolves a bound roll")
local conflicting = player("Conflicting", "MAGE", 0, 99)
conflicting.isWinner = true
initial.rollInfos = { flagOnly, conflicting }
emit("LOOT_HISTORY_UPDATE_DROP", 77, 15)
advance()
assert(not expect(source, 401).winner, "conflicting native winner flags do not authorize a winner")
initial.winner = { playerName = flagOnly.playerName, playerGUID = flagOnly.playerGUID }
initial.rollInfos = { flagOnly }
emit("LOOT_HISTORY_UPDATE_DROP", 77, 15)
advance()
local enrichedWinner = expect(source, 401).winner
assert(enrichedWinner.state == "need" and enrichedWinner.roll == 100 and enrichedWinner.class == "MAGE",
    "the exact participant can fill missing winner metadata")

reset()
GroupLootContainer.rollFrames[1] = newFrame()
source = newSource()
assert(not source.frame.shown and #source:GetRolls() == 0, "a bonus-roll panel must not keep the loot ticker awake")

reset()
popup(501, 1, link)
local hiddenSibling = popup(502, 2, equivalent)
hiddenSibling:Hide()
local activeIDs = GetActiveLootRollIDs
function GetActiveLootRollIDs() return secret end
drops[77] = { drop(16, clock, link, {need}) }
source = newSource()
GetActiveLootRollIDs = activeIDs
assert(expect(source, 501).ambiguous and #expect(source, 501).rolls == 0,
    "a registered but hidden twin must remain a competitor while the active ID list is restricted")

reset()
popup(601, 1, link)
drops[77] = { drop(17, clock, link, {need}) }
source = newSource()
assert(#expect(source, 601).rolls == 1)
advance(3)
historyFailure = true
emit("LOOT_HISTORY_UPDATE_DROP", 77, 17)
advance()
assert(#expect(source, 601).rolls == 0, "an unreadable update must hide previously published votes")
historyFailure = false
encounters = {} -- The recovery can use the specific encounter/key from the event.
advance(1)
assert(#expect(source, 601).rolls == 1, "a late transient read failure must recover without another event")
historyFailure = true
emit("LOOT_HISTORY_UPDATE_DROP", 77, 17)
for _ = 1, 7 do advance(0.55) end
historyFailure = false
advance(1)
assert(#expect(source, 601).rolls == 0, "persistent failures must exhaust the bounded retry window")
emit("LOOT_HISTORY_UPDATE_DROP", 77, 17)
advance()
assert(#expect(source, 601).rolls == 1, "a later event can recover after the retry window")

for _, event in ipairs({"LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER"}) do
    reset()
    local startedAt = clock
    local originalAnchor = popup(607, 1, link)
    popup(608, 2, separate)
    local currentDrop = drop(17, startedAt, link, {need})
    local otherDrop = drop(18, startedAt, separate, {offspec})
    drops[77] = {currentDrop, otherDrop}
    source = newSource()
    assert(#expect(source, 607).rolls == 1)
    advance(3)
    drops[77] = {drop(17, startedAt - 1, link, {offspec}), otherDrop}
    emit(event, 77, 17)
    advance()
    local stale = expect(source, 607)
    assert(not stale.ambiguous and #stale.rolls == 0, "an older generation must not change the live binding")
    drops[77] = {currentDrop, otherDrop}
    advance(0.6)
    assert(expect(source, 607).rolls[1].name == "Mage", "a stale history update must recover on retry")

    for _, field in ipairs({"itemHyperlink", "startTime"}) do
        local restrictedDrop = drop(17, startedAt, link, {offspec})
        restrictedDrop[field] = secret
        drops[77] = {restrictedDrop, otherDrop}
        emit(event, 77, 17)
        advance()
        local restricted = expect(source, 607)
        assert(not restricted.ambiguous and #restricted.rolls == 0, "hide votes from an unreadable bound drop")
        drops[77] = {currentDrop, otherDrop}
        advance(0.6)
        local recovered = expect(source, 607)
        assert(#recovered.rolls == 1 and recovered.rolls[1].name == "Mage", "retry a bound drop with unreadable " .. field)
    end

    if event == "LOOT_HISTORY_UPDATE_ENCOUNTER" then originalAnchor:Hide() end
    drops[77] = {drop(17, startedAt, separate, {need}), otherDrop}
    emit(event, 77, 17)
    advance()
    local unaffected = expect(source, 608)
    assert(not unaffected.ambiguous and #unaffected.rolls == 1 and unaffected.rolls[1].name == "Paladin",
        "a mismatched read of a bound key must not interfere with a different active item")
    drops[77] = {currentDrop, otherDrop}
    originalAnchor:Show()
    advance(0.6)
    assert(expect(source, 607).rolls[1].name == "Mage", "retry a bound key when its item changes without a new start")

    drops[77] = {drop(17, startedAt + 1, link, {offspec}), otherDrop}
    emit(event, 77, 17)
    advance()
    drops[77] = {currentDrop, otherDrop}
    emit(event, 77, 17)
    advance()
    local conflict = expect(source, 607)
    assert(conflict.ambiguous and #conflict.rolls == 0, "a newer conflicting generation must stay quarantined")
end

reset()
popup(701, 1, link)
popup(702, 2, separate)
local firstDrop = drop(18, clock, link, {need})
local secondDrop = drop(19, clock, separate, {offspec})
drops[77] = { firstDrop, secondDrop }
source = newSource()
advance(3)
local readDrop = C_LootHistory.GetSortedInfoForDrop
local failedReads = 0
C_LootHistory.GetSortedInfoForDrop = function(encounterID, lootListKey)
    if lootListKey == 18 then
        failedReads = failedReads + 1
        error("first drop history unavailable")
    end
    return readDrop(encounterID, lootListKey)
end
emit("LOOT_HISTORY_UPDATE_DROP", 77, 18)
advance()
assert(failedReads == 1 and #expect(source, 701).rolls == 0)
for i = 1, 20 do
    secondDrop.rollInfos = {player("Paladin", "PALADIN", 1, 60 + i)}
    emit("LOOT_HISTORY_UPDATE_DROP", 77, 19)
    advance(0.25)
    if i == 1 then assert(failedReads == 1, "a different key cannot accelerate a pending read") end
    assert(expect(source, 702).rolls[1].roll == 60 + i, "unaffected drops must keep updating")
end
assert(failedReads > 1 and failedReads <= 5, "unrelated updates must not extend another key's retry deadline")
assert(#expect(source, 701).rolls == 0)
C_LootHistory.GetSortedInfoForDrop = readDrop
emit("LOOT_HISTORY_UPDATE_DROP", 77, 18)
advance()
assert(#expect(source, 701).rolls == 1)

reset()
source = newSource()
local delayedStart = clock
advance(4)
popup(901, 1, link, delayedStart)
drops[77] = { drop(24, delayedStart, link, {need}) }
emit("START_LOOT_ROLL", 901, 56000)
emit("LOOT_HISTORY_UPDATE_DROP", 77, 24)
advance()
assert(#expect(source, 901).rolls == 1, "a delayed START must use the popup timer to bind the correct native drop")

reset()
source = newSource()
delayedStart = clock
advance(4)
popup(902, 1, link, delayedStart)
drops[77] = { drop(25, delayedStart, link, {need}), drop(26, clock, link, {offspec}) }
local readTimeLeft = GetLootRollTimeLeft
GetLootRollTimeLeft = function() return secret end
emit("START_LOOT_ROLL", 902, 60000)
emit("LOOT_HISTORY_UPDATE_DROP", 77, 26)
advance()
assert(#expect(source, 902).rolls == 0, "delivery-time fallback must not bind votes from another same-item drop")
GetLootRollTimeLeft = readTimeLeft
advance()
assert(expect(source, 902).rolls[1].name == "Mage", "a readable timer must bind the actual earlier drop")

for _, ordering in ipairs({"start", "cancel", "prune", "restricted", "restrictedCancel"}) do
    reset()
    local recycled = popup(903, 1, link)
    local oldDrop = drop(27, clock, link, {need})
    drops[77] = {oldDrop}
    source = newSource()
    assert(#expect(source, 903).rolls == 1)
    oldDrop.winner = player("Old winner", "MAGE", 0, 96)
    emit("LOOT_HISTORY_UPDATE_DROP", 77, 27)
    advance()
    assert(expect(source, 903).winner and expect(source, 903).winner.name == "Old winner")
    rolls[903] = nil
    if ordering == "cancel" or ordering == "restrictedCancel" then
        emit("CANCEL_LOOT_ROLL", 903)
        recycled:Hide()
        advance()
    elseif ordering == "prune" then
        GroupLootContainer.rollFrames[1] = nil
        advance()
    end
    recycled.rollID = 904
    recycled:Show()
    GroupLootContainer.rollFrames[1] = recycled
    rolls[904] = {link = link, finish = clock + 60}
    drops[77][2] = drop(28, clock, link, {offspec})
    local getActive = GetActiveLootRollIDs
    local restricted = ordering == "restricted" or ordering == "restrictedCancel"
    if restricted then GetActiveLootRollIDs = function() return secret end end
    emit("START_LOOT_ROLL", 904, 60000)
    emit("LOOT_HISTORY_UPDATE_DROP", 77, 28)
    advance()
    GetActiveLootRollIDs = getActive
    local latest = expect(source, 904)
    assert(not lookup(source, 903))
    if not restricted then
        assert(not latest.ambiguous and not latest.winner and #latest.rolls == 1 and latest.rolls[1].name == "Paladin",
            "the finished popup must not taint or supply the next same-item roll")
    else
        assert(latest.ambiguous and #latest.rolls == 0,
            "a restricted active roll list cannot prove the old popup is gone")
    end
end

reset()
source = newSource()
local cancelledFrame = popup(905, 1, link)
drops[77] = {drop(29, clock, link, {need})}
emit("CANCEL_ALL_LOOT_ROLLS")
advance()
assert(not lookup(source, 905), "cancel-all must cover a popup not yet observed by the refresh loop")
popup(906, 2, link)
rolls[905] = nil
drops[77] = {drop(30, clock, link, {offspec})}
emit("START_LOOT_ROLL", 906, 60000)
emit("LOOT_HISTORY_UPDATE_DROP", 77, 30)
advance()
assert(not lookup(source, 905) and expect(source, 906).rolls[1].name == "Paladin",
    "a later START must neither resurrect a still-visible cancelled frame nor let it spoil the new attribution")
cancelledFrame:Hide()

for _, cancelEvent in ipairs({"CANCEL_LOOT_ROLL", "CANCEL_ALL_LOOT_ROLLS"}) do
    for _, cancelWhileDisabled in ipairs({false, true}) do
        reset()
        popup(907, 1, link)
        drops[77] = {drop(31, clock, link, {need})}
        source = newSource()
        assert(lookup(source, 907))
        if cancelWhileDisabled then source:SetEnabled(false) end
        emit(cancelEvent, 907)
        advance()
        assert(not lookup(source, 907))
        if not cancelWhileDisabled then source:SetEnabled(false) end
        source:SetEnabled(true)
        advance()
        assert(not lookup(source, 907), "settings must not resurrect a known canceled popup")

        source:SetEnabled(false)
        emit("START_LOOT_ROLL", secret, 60000)
        popup(907, 1, separate)
        drops[77] = {drop(32, clock, separate, {offspec})}
        emit("START_LOOT_ROLL", 907, 60000)
        assert(not lookup(source, 907), "fresh START must not display choices while disabled")
        source:SetEnabled(true)
        advance()
        assert(expect(source, 907).rolls[1].name == "Paladin", "fresh START must retire an older cancellation")

        emit(cancelEvent, 907)
        source:SetEnabled(false)
        emit("PLAYER_LEAVING_WORLD")
        emit("PLAYER_ENTERING_WORLD")
        source:SetEnabled(true)
        advance()
        assert(expect(source, 907).rolls[1].name == "Paladin", "cancellation must not cross the world boundary")
    end
end

print("Live source timing, attribution, privacy, and lifecycle tests passed")
