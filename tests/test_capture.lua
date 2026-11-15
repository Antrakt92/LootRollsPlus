local addonPath = arg[1] or "."
local ns = {}
local wall = 100000
function time() return wall end
local clock = 500
local secret = {}
function issecretvalue(v) return v == secret end
local link = "|cnIQ3:|Hitem:42:0|h[Test]|h|r"
local otherLink = "|cff0070dd|Hitem:43:0|h[Other]|h|r"
local row = {}
local notices = {}
local removed = {}
local oldEntry
local function new()
    row, notices, removed = {}, {}, {}
    return ns.NewCapture({
        onDrop = function(drop, isNew)
            if isNew then row[#row + 1] = drop end
            notices[#notices + 1] = { entry = drop, new = isNew }
        end,
        onRemove = function(drop)
            for i, entry in ipairs(row) do
                if entry == drop then table.remove(row, i) break end
            end
            removed[#removed + 1] = drop
        end,
        getExisting = function(e, k, t, value)
            if oldEntry and e == oldEntry.encounterID and k == oldEntry.lootListKey
                and t == oldEntry.startTime and value == oldEntry.link then
                return oldEntry
            end
        end,
    })
end

local drops = {}
local function setDrops(...)
    drops = { ... }
end
Enum = { EncounterLootDropRollState = {
    NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5,
} }
C_LootHistory = {
    GetLootHistoryTime = function() return clock end,
    GetAllEncounterInfos = function() return { { encounterID = 7 } } end,
    GetInfoForEncounter = function(k)
        assert(k == 7)
        return { encounterName = "Named encounter" }
    end,
    GetSortedDropsForEncounter = function(k)
        assert(k == 7)
        return drops
    end,
    GetSortedInfoForDrop = function(e, k)
        assert(e == 7)
        for _, drop in ipairs(drops) do
            if drop.lootListKey == k then return drop end
        end
    end,
}
local function drop(key, start, rolls, winner)
    return { lootListKey = key, itemHyperlink = link, startTime = start, rollInfos = rolls or {},
        winner = winner, allPassed = false }
end
local function roll(name, class, state, value)
    return { playerName = name, playerClass = class, state = state, roll = value }
end

local timer = {}
C_Timer = { After = function(delay, callback) timer[#timer + 1] = { wall + delay, callback } end }
local function advance(seconds)
    clock, wall = clock + seconds, wall + seconds
    for i = #timer, 1, -1 do
        local pending = timer[i]
        if wall >= pending[1] then
            table.remove(timer, i)
            pending[2]()
        end
    end
end
local links = {}
function GetLootRollItemLink(rollID) return links[rollID] end
local roster = {
    player = { "Myself", "", "WARRIOR", 45, "Player-Self" },
    party1 = { "Somebody", "Realm", "PALADIN", 50, "Player-Member" },
    party2 = { "Priest", "", "PRIEST", 30, "Player-Priest" },
}
function GetNumGroupMembers() return 3 end
function UnitName(unit)
    if roster[unit] then return roster[unit][1], roster[unit][2] end
end
function UnitNameUnmodified(unit)
    if roster[unit] then return roster[unit][1], roster[unit][2] end
end
function UnitClass(unit)
    if roster[unit] then return roster[unit][3], roster[unit][3] end
end
function UnitLevel(unit) return roster[unit] and roster[unit][4] end
function UnitGUID(unit) return roster[unit] and roster[unit][5] end
LOOT_ROLL_NEED = "|HlootHistory:%d|h[Loot]|h: %s need %s"
LOOT_ROLL_NEED_SELF = "You need %s"
LOOT_ROLL_GREED = "%2$s greed by %1$s"
LOOT_ROLL_ROLLED_GREED = "Greed %d on %s by %s"
LOOT_ROLL_WON = "%s won %s"
LOOT_ROLL_YOU_WON = "You won %s"
LOOT_ROLL_WON_NO_SPAM_GREED = "|HlootHistory:%d|h[Loot]|h: %s (Greed %d) won: %s"
LOOT_ROLL_ALL_PASSED = "Everyone passed %s"
YOU = "You"

assert(loadfile(addonPath .. "/Capture.lua"))("LootRollsPlus", ns)
local function emitDrop(engine, key)
    engine:HandleEvent("LOOT_HISTORY_UPDATE_DROP", 7, key)
end

local preexisting = drop(1, 498)
setDrops(preexisting)
local engine = new()
engine:Start()
emitDrop(engine, 1)
assert(#row == 0, "bootstrap and updates must skip preexisting records")

advance(5)
local needs = roll("Somebody", "PALADIN", 0)
needs.playerGUID = "Player-Member"
local left = drop(2, clock - 1, { needs, roll("Priest", "PRIEST", 4), roll("Masked", "MAGE", secret) })
local right = drop(3, clock - 1, { roll("Priest", "PRIEST", 3) })
setDrops(preexisting, left, right)
emitDrop(engine, 2)
emitDrop(engine, 3)
assert(#row == 2 and row[1].t == wall - 1)
assert(row[1].lootListKey ~= row[2].lootListKey and row[1].link == row[2].link)
assert(row[1].sourceName == "Named encounter" and #row[1].rolls == 2)
assert(row[1].rolls[1].type == "need" and row[1].rolls[1].level == 50
    and row[1].rolls[1].playerGUID == nil)
assert(row[1].rolls[2].type == "undecided" and row[2].rolls[1].type == "greed")
local n = #notices
emitDrop(engine, 2)
assert(#notices == n, "repeat snapshots should not refresh unchanged rows")

roster.party1[4] = 51
left.winner = roll("Somebody", "PALADIN", 1, 96)
left.rollInfos[1] = left.winner
emitDrop(engine, 2)
assert(#row == 2 and row[1].winnerValue == 96 and row[1].winnerClass == "PALADIN")
assert(row[1].winnerType == "need" and row[1].done and row[1].rolls[1].level == 50)
assert(not row[2].done)
right.rollInfos = secret
right.allPassed = true
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
assert(row[2].allpassed and row[2].done and #row[2].rolls == 1)
emitDrop(engine, secret)
emitDrop(engine, 0/0)

local pending = drop(4, clock)
setDrops(preexisting, left, right, pending)
emitDrop(engine, 4)
setDrops()
engine:HandleEvent("LOOT_HISTORY_CLEAR_HISTORY")
assert(row[3].closed and not row[3].done)
setDrops(drop(4, clock, { roll("Priest", "PRIEST", 5) }))
emitDrop(engine, 4)
assert(#row == 4)
engine:Reset()
emitDrop(engine, 4)
assert(#row == 4, "already existing client history is not added after clearing")

oldEntry = row[1]
setDrops(left)
left.winner = roll("Somebody", "PALADIN", 1, 97)
engine = new()
engine:Start()
assert(#row == 0 and #notices == 1 and notices[1].entry == oldEntry and oldEntry.winnerValue == 97)
oldEntry = nil

local function start(which, itemLink)
    links[which] = itemLink or link
    engine:HandleEvent("START_LOOT_ROLL", which, 10000)
end
local function chat(message)
    engine:HandleEvent("CHAT_MSG_LOOT", message)
end

setDrops()
engine = new()
engine:Start()
chat("Greed 99 on " .. link .. " by Priest")
assert(#row == 0, "chat without START does not create a row")
start(10)
chat("|HlootHistory:1|h[Loot]|h: |Hplayer:Somebody-Realm:1|h[Somebody-Realm]|h need " .. link)
chat(link .. " greed by Priest")
chat("Greed 99 on " .. link .. " by Priest")
chat("Priest won " .. link)
assert(#row == 1 and row[1].done and row[1].rolls[1].name == "Somebody-Realm")
assert(row[1].rolls[1].class == "PALADIN" and row[1].rolls[1].level == 51)
assert(row[1].winnerClass == "PRIEST" and row[1].winnerType == "greed" and row[1].winnerValue == 99)
start(18)
chat("You need " .. link)
assert(row[2].rolls[1].type == "need", "a completed chat roll does not block a new same-item roll")
chat("Everyone passed " .. link)
engine = new()
engine:Start()
advance(3)

start(11)
chat("You need " .. link)
assert(row[1].rolls[1].name == "Myself")
start(12)
assert(row[1].ambiguous and row[2].ambiguous and #row[1].rolls == 0)
chat("You won " .. link)
assert(not row[1].winner and not row[2].winner)
engine:HandleEvent("CANCEL_LOOT_ROLL", 11)
assert(row[1].closed and not row[2].closed)
chat("Everyone passed " .. link)
assert(not row[2].done)
advance(20)

start(13)
local both = drop(5, clock)
setDrops(both)
emitDrop(engine, 5)
assert(#removed == 1 and removed[1].capture == "chat")
assert(row[#row].capture == "history")
advance(3)
start(14)
chat("You need " .. link)
assert(row[#row].capture == "chat" and row[#row].ambiguous and #row[#row].rolls == 0)

both.winner = roll("Priest", "PRIEST", 3, 77)
emitDrop(engine, 5)
assert(row[#row].capture == "chat" and #removed == 1, "late native winner cannot remove new START")
advance(20)
start(17)
chat("You need " .. link)
assert(row[#row].capture == "chat" and row[#row].rolls[1].type == "need",
    "resolved older native drop does not suppress a new chat roll")
engine:Reset()
advance(3)
setDrops(drop(6, clock))
emitDrop(engine, 6)
start(15)
assert(row[#row].capture == "history", "structured event immediately before START is not duplicated")
start(16, otherLink)
chat("You need " .. otherLink)
engine:HandleEvent("CANCEL_ALL_LOOT_ROLLS")
assert(row[#row].closed)

setDrops()
engine = new()
engine:Start()
start(20)
local distinctColor = link:gsub("^|cnIQ3:", "|cff0070dd")
chat("|HlootHistory:5|h[Loot]|h: |cfff58cba|Hplayer:Somebody-Realm:1|h[Somebody-Realm]|h|r need " .. distinctColor)
assert(row[1].rolls[1] and row[1].rolls[1].class == "PALADIN",
    "player and item color encodings do not change identity")
chat("Somebody-Realm won " .. distinctColor)
assert(row[1].done and row[1].winnerType == "need")
setDrops(drop(7, clock, { roll("Somebody-Realm", "PALADIN", 0, 93) }, roll("Somebody-Realm", "PALADIN", 0, 93)))
emitDrop(engine, 7)
assert(#row == 1 and #removed == 1 and row[1].winnerValue == 93,
    "a structured result arriving after a chat winner replaces the provisional row")

setDrops()
engine = new()
engine:Start()
local timed = drop(9, clock, { roll("Priest", "PRIEST", 0) })
timed.duration = 3
setDrops(timed)
emitDrop(engine, 9)
assert(not row[1].closed)
advance(6)
assert(row[1].closed and not row[1].done and #row[1].rolls == 1,
    "an unresolved native roll closes when its timer elapses")
timed.winner = roll("Priest", "PRIEST", 0, 40)
emitDrop(engine, 9)
assert(row[1].done and not row[1].closed and row[1].winnerValue == 40,
    "native result can still update an expired roll")

setDrops()
engine = new()
engine:Start()
start(23)
links[24] = distinctColor
function GetActiveLootRollIDs() return { 23, 24 } end
chat("You need " .. distinctColor)
assert(row[1].ambiguous and #row[1].rolls == 0, "visible concurrent rolls are ambiguous before START delivery")
GetActiveLootRollIDs = nil

setDrops()
engine = new()
engine:Start()
start(30)
chat("|HlootHistory:7|h[Loot]|h: Priest (Greed 82) won: " .. link)
assert(row[1].winner == "Priest" and row[1].winnerType == "greed" and row[1].winnerValue == 82)
start(31)
chat("You need " .. link)
assert(row[2].rolls[1].type == "need", "a terminal provisional row is not a target or competitor")
local variant = link:gsub("42:0", "42:1")
links[32] = secret
function GetActiveLootRollIDs() return { 31, 32 } end
chat(link .. " greed by Priest")
assert(#row[2].rolls == 1 and not row[2].ambiguous,
    "skip a report while another active roll's item is unreadable")
function GetActiveLootRollIDs() return { 31, secret } end
chat(link .. " greed by Priest")
assert(#row[2].rolls == 1 and not row[2].ambiguous,
    "skip a report while another active roll's ID is unreadable")
function GetActiveLootRollIDs() return secret end
chat(link .. " greed by Priest")
assert(#row[2].rolls == 1 and not row[2].ambiguous, "skip a report while the native ID list is unreadable")
links[32] = variant
function GetActiveLootRollIDs() return { 31, 32 } end
chat(link .. " greed by Priest")
assert(row[2].rolls[2].type == "greed", "distinct serialized item variants remain independent")
GetActiveLootRollIDs = nil

local expired = drop(10, clock - 21, { roll("Priest", "PRIEST", 0) })
expired.duration = 4
oldEntry = { encounterID = 7, lootListKey = 10, startTime = expired.startTime, link = link, rolls = {} }
setDrops(expired)
engine = new()
engine:Start()
assert(#row == 0 and oldEntry.closed and not oldEntry.done, "reload closes expired saved native drops")
oldEntry = nil

setDrops()
engine = new()
engine:Start()
local sameNameA = roll("Mirror", "PALADIN", 0)
sameNameA.playerGUID = "Player-Member"
local sameNameB = roll("Mirror", "PALADIN", 3)
sameNameB.playerGUID = "Player-Other"
local sameNameDrop = drop(11, clock, { sameNameA, sameNameB })
setDrops(sameNameDrop)
emitDrop(engine, 11)
assert(row[1].rolls[1].level == 51 and row[1].rolls[2].level == nil)
sameNameDrop.rollInfos = { sameNameB, sameNameA }
emitDrop(engine, 11)
assert(row[1].rolls[1].level == nil and row[1].rolls[2].level == 51,
    "same rendered player identities never borrow a level when structured GUIDs differ")

assert(ns.GetItemLinkIdentity(link) == ns.GetItemLinkIdentity(distinctColor))
assert(ns.GetItemLinkIdentity(link) ~= ns.GetItemLinkIdentity(variant))
assert(ns.GetItemLinkIdentity(secret) == nil)

setDrops()
engine = new()
engine:Start()
local partial = drop(12, clock, {roll("Priest", "PRIEST", 3, 83)}, {playerName = "Priest", roll = secret})
local duplicate = drop(13, clock, {roll("Mirror", "MAGE", 0, 40), roll("Mirror", "PALADIN", 3, 60)},
    {playerName = "Mirror"})
local flag = roll("Somebody", "PALADIN", 0, 95)
flag.isWinner = true
flag.playerGUID = "Player-Member"
local flagged = drop(14, clock, {flag}, {playerName = secret, playerGUID = "Player-Member"})
local conflict = drop(15, clock, {flag}, {playerName = "Somebody", playerGUID = "Player-Other"})
local masked = drop(16, clock, {roll("Priest", "PRIEST", 3, 86), roll(secret, "PALADIN", 0, 96)},
    {playerName = "Priest"})
local flagOnly = drop(17, clock, {flag})
flagOnly.winner = secret
setDrops(partial, duplicate, flagged, conflict, masked, flagOnly)
for key = 12, 17 do emitDrop(engine, key) end
assert(row[1].winnerClass == "PRIEST" and row[1].winnerType == "greed" and row[1].winnerValue == 83)
assert(row[1].rolls[1].isWinner, "the identified native winner must not appear twice in details")
assert(row[2].winner == "Mirror" and not row[2].winnerClass and not row[2].winnerType and not row[2].winnerValue)
assert(row[3].winner == "Somebody" and row[3].winnerClass == "PALADIN"
    and row[3].winnerType == "need" and row[3].winnerValue == 95)
assert(not row[4].winnerClass and not row[4].winnerValue, "a marked roll with a conflicting GUID cannot enrich")
assert(not row[4].rolls[1].isWinner, "a contradictory marker must not label another participant the winner")
assert(not row[5].winnerClass and not row[5].winnerValue, "a hidden participant prevents an exact-name inference")
assert(row[6].done and row[6].winner == "Somebody" and row[6].winnerValue == 95)
flagOnly.winner = {playerGUID = "Player-Member", state = 0, roll = 97}
flagOnly.rollInfos = {}
emitDrop(engine, 17)
assert(row[6].winner == "Somebody" and row[6].winnerValue == 97,
    "an exact in-memory winner GUID can receive a late score even while its name is restricted")
flagOnly.winner = {playerGUID = "Player-Other", playerName = "Somebody"}
emitDrop(engine, 17)
assert(row[6].winner == "Somebody" and not row[6].winnerClass and not row[6].winnerValue,
    "a different player with the same rendered name must not inherit prior winner evidence")
local noClass = roll("Mirror", nil, 3, 81)
noClass.playerGUID = "Player-Member"
local inferredClass = drop(18, clock, {noClass}, noClass)
setDrops(inferredClass)
emitDrop(engine, 18)
assert(row[7].winnerClass == "PALADIN" and row[7].rolls[1].class == "PALADIN")

setDrops()
engine = new()
engine:Start()
local currentSlot = drop(22, clock, { roll("Priest", "PRIEST", 0) })
setDrops(currentSlot)
emitDrop(engine, 22)
local unknownGeneration = drop(22, secret, {flag}, flag)
setDrops(unknownGeneration)
emitDrop(engine, 22)
assert(#row == 1 and not row[1].winner, "a restricted start cannot overwrite a retained same-key result")
advance(1)
unknownGeneration.startTime = clock
emitDrop(engine, 22)
assert(#row == 2 and row[2].winner == "Somebody", "a clean start identifies a recycled key")
assert(row[1].closed, "reusing a history key retires the earlier active row immediately")

setDrops()
engine = new()
engine:Start()
roster.player[2] = "Ember"
roster.party1[2] = "Ashwood"
roster.party2 = { "Somebody", "Stone", "PRIEST", 30, "Player-Other" }
NameUtil = {
    GetUnmodifiedUnitFullName = function(unit)
        local first, surname = UnitNameUnmodified(unit)
        if first and surname and surname ~= "" then return first .. " " .. surname end
        return first
    end,
}
start(41)
chat("|HlootHistory:1|h[Loot]|h: Somebody Ashwood need " .. link)
chat("|HlootHistory:1|h[Loot]|h: Somebody need " .. link)
chat("You need " .. link)
chat("Myself won " .. link)
local fullNames = row[1]
assert(fullNames.rolls[1].name == "Somebody Ashwood" and fullNames.rolls[1].class == "PALADIN"
    and fullNames.rolls[1].level == 51, "Forever's surname separator must be recognized")
assert(fullNames.rolls[2].name == "Somebody" and not fullNames.rolls[2].class,
    "a shared short label cannot inherit a class")
assert(fullNames.rolls[3].name == "Myself Ember" and fullNames.winner == "Myself Ember"
    and fullNames.winnerType == "need" and fullNames.winnerClass == "WARRIOR",
    "self and named announcements should use the same canonical identity")

setDrops()
engine = new()
engine:Start()
local quickWinner = roll("Somebody Ashwood", "PALADIN", 3, 42)
setDrops(drop(19, clock, {quickWinner}, quickWinner))
emitDrop(engine, 19)
advance(1)
start(42)
chat("You need " .. link)
assert(#row == 2 and row[1].done and row[2].rolls[1].type == "need",
    "a completed native roll must not suppress the next identical-item START")

setDrops()
engine = new()
engine:Start()
local resolvedImmediately = drop(20, clock, {quickWinner})
setDrops(resolvedImmediately)
emitDrop(engine, 20)
resolvedImmediately.winner = quickWinner
emitDrop(engine, 20)
advance(1)
start(43)
assert(#row == 2 and row[1].done and not row[2].ambiguous,
    "a formerly active native marker cannot suppress START after the roll resolves")

setDrops()
engine = new()
engine:Start()
local known = roll("Unique", "MAGE", 0)
known.playerGUID = "Player-Known"
local otherParticipant = roll("Other Person", "PRIEST", 3)
otherParticipant.playerGUID = "Player-Other-Native"
local bound = drop(21, clock, {known, otherParticipant})
setDrops(bound)
emitDrop(engine, 21)
local remembered = row[1]
assert(engine:GetParticipantGUID(remembered, "Unique") == "Player-Known")
assert(engine:GetParticipantGUID(remembered, "Other Person") == "Player-Other-Native")
assert(not remembered.playerGUID and not remembered.rolls[1].playerGUID)
assert(not engine:GetParticipantGUID(remembered, secret))
assert(not engine:GetParticipantGUID({}, "Unique"))
bound.rollInfos = secret
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false, "restricted roll arrays must block name-only fallback")
bound.rollInfos = {known, otherParticipant}

otherParticipant.playerName = "Unique"
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false, "duplicate names must block name-only fallback")
otherParticipant.playerName = "Other Person"
known.playerGUID = secret
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false, "a restricted binding must block name-only fallback")
assert(engine:GetParticipantGUID(remembered, "Other Person") == "Player-Other-Native")

bound.rollInfos = {otherParticipant}
bound.winner = known
known.playerGUID = "Player-Known"
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == "Player-Known",
    "an authoritative winner with a unique name can be identified even when omitted from participants")
otherParticipant.playerName = secret
emitDrop(engine, 21)
assert(not engine:GetParticipantGUID(remembered, "Unique"), "a hidden participant cannot establish unique name ownership")
otherParticipant.playerName = "Other Person"
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == "Player-Known")
engine:Reset()
assert(not engine:GetParticipantGUID(remembered, "Unique"), "fresh state must not retain old bindings")
print("Capture tests passed")
