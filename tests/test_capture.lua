local addonPath = arg[1] or "."
local ns = {}
local wall = 100000
function time() return wall end
function GetTime() return wall end
local clock = 500
local secret = {}
function issecretvalue(v) return v == secret end
local link = "|cnIQ3:|Hitem:42:0|h[Test]|h|r"
local otherLink = "|cff0070dd|Hitem:43:0|h[Other]|h|r"
local row = {}
local notices = {}
local removed = {}
local replacements = {}
local oldEntry
local function new()
    row, notices, removed, replacements = {}, {}, {}, {}
    return ns.NewCapture({
        onDrop = function(drop, isNew)
            if isNew then row[#row + 1] = drop end
            notices[#notices + 1] = { entry = drop, new = isNew }
        end,
        onRemove = function(drop, replacement)
            for i, entry in ipairs(row) do
                if entry == drop then table.remove(row, i) break end
            end
            removed[#removed + 1] = drop
            replacements[drop] = replacement and { entry = replacement, winnerValue = replacement.winnerValue }
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
assert(row[2].allpassed, "an earlier winner cannot be the source of a delayed all-pass result")
engine = new()
engine:Start()
advance(3)

setDrops()
engine = new()
engine:Start()
start(181)
chat(link .. " greed by Priest")
chat("Greed 99 on " .. link .. " by Priest")
chat("Priest won " .. link)
advance(1)
start(182)
chat("You need " .. link)
chat("Greed 99 on " .. link .. " by Priest")
assert(#row[2].rolls == 1, "a repeated old roll score must not be assigned to the next drop")
chat("Priest won " .. link)
assert(not row[2].done, "a repeated old winner must not finish the next drop")
chat("You won " .. link)
assert(row[2].done and row[2].winner == "Myself", "a distinct winner can finish the next drop")

setDrops()
engine = new()
engine:Start()
start(183)
chat("Everyone passed " .. link)
advance(1)
start(184)
chat("Everyone passed " .. link)
assert(not row[2].done, "an indistinguishable all-pass report must not finish the next drop")
advance(2)
chat("Everyone passed " .. link)
assert(row[2].allpassed, "a later all-pass report can finish the next drop")

setDrops()
engine = new()
engine:Start()
start(185)
chat("|HlootHistory:7|h[Loot]|h: Priest (Greed 82) won: " .. link)
advance(1)
start(186)
chat("|HlootHistory:8|h[Loot]|h: Priest (Greed 83) won: " .. link)
assert(row[2].done and row[2].winnerValue == 83, "a different score can distinguish the same winner")

setDrops()
engine = new()
engine:Start()
start(187)
chat("|HlootHistory:7|h[Loot]|h: Priest (Greed 82) won: " .. link)
advance(1)
start(188)
chat("|HlootHistory:8|h[Loot]|h: Priest (Greed 82) won: " .. link)
assert(row[2].done and row[2].winnerValue == 82, "a different chat line is not an exact replay")

setDrops()
engine = new()
engine:Start()
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
local delayedPrompt = drop(30, clock)
setDrops(delayedPrompt)
emitDrop(engine, 30)
advance(4)
C_Loot = { GetLootRollDuration = function() return 10000 end }
GetLootRollTimeLeft = function() return 6000 end
start(70)
assert(#row == 1 and row[1].capture == "history", "a delayed START for the same popup must not add an overlapping row")
start(70)
assert(#row == 1, "a repeated START must not recreate a suppressed popup")
delayedPrompt.winner = quickWinner
emitDrop(engine, 30)
assert(#row == 1 and row[1].winnerValue == 42)
GetLootRollTimeLeft = function() return 10000 end
start(71)
assert(#row == 2 and row[2].capture == "chat", "a new identical popup after the winner is still a separate roll")

setDrops()
engine = new()
engine:Start()
local historicalStart = clock
advance(4)
GetLootRollTimeLeft = function() return 6000 end
start(72)
setDrops(drop(31, historicalStart))
emitDrop(engine, 31)
assert(#row == 1 and row[1].capture == "history" and #removed == 1,
    "a delayed provisional row must be replaced when the native record arrives later")
C_Loot, GetLootRollTimeLeft = nil, nil

setDrops()
engine = new()
engine:Start()
local firstCopy = drop(32, clock)
setDrops(firstCopy)
emitDrop(engine, 32)
start(73)
advance(1)
start(74)
assert(#row == 2 and row[2].capture == "chat", "one native record cannot cover two overlapping popups")
local secondCopy = drop(33, clock)
setDrops(firstCopy, secondCopy)
emitDrop(engine, 33)
firstCopy.winner, secondCopy.winner = quickWinner, roll("Priest", "PRIEST", 3, 69)
emitDrop(engine, 32)
emitDrop(engine, 33)
assert(#row == 2 and row[1].winnerValue == 42 and row[2].winnerValue == 69,
    "each identical drop retains its own native result")

setDrops()
engine = new()
engine:Start()
local firstStart = clock
start(75)
advance(4)
local secondStart = clock
start(76)
assert(row[1].ambiguous and row[2].ambiguous, "chat alone cannot disambiguate the overlapping item")
local firstChat, secondChat = row[1], row[2]
setDrops(drop(34, firstStart, { quickWinner }, quickWinner), drop(35, secondStart, { quickWinner }, quickWinner))
emitDrop(engine, 34)
emitDrop(engine, 35)
assert(#row == 2 and #removed == 2 and replacements[firstChat].entry == row[1]
    and replacements[secondChat].entry == row[2] and replacements[firstChat].winnerValue == 42,
    "distinct starts can reconcile both provisional rows with populated native results")

setDrops()
engine = new()
engine:Start()
start(77)
setDrops(drop(36, clock, { quickWinner }, quickWinner), drop(37, clock, { quickWinner }, quickWinner))
emitDrop(engine, 36)
emitDrop(engine, 37)
assert(#removed == 0, "a provisional row cannot be linked arbitrarily to either of two simultaneous native drops")

setDrops()
engine = new()
engine:Start()
start(81)
setDrops(drop(38, clock, { quickWinner }, quickWinner), drop(39, secret))
emitDrop(engine, 38)
assert(#removed == 0, "a hidden start time cannot rule out a competing native drop")

setDrops()
engine = new()
engine:Start()
local resolvedStart = clock
start(82)
chat("You won " .. link)
advance(1)
start(83)
setDrops(drop(40, resolvedStart, { quickWinner }, quickWinner))
emitDrop(engine, 40)
assert(row[1].done and not row[1].ambiguous,
    "uncertain native attribution must not erase a completed chat winner")

setDrops()
engine = new()
engine:Start()
start(78)
engine:HandleEvent("CANCEL_LOOT_ROLL", 78)
advance(3)
start(79)
chat("You need " .. link)
chat("You won " .. link)
assert(row[1].closed and not row[1].done and row[2].done and row[2].winnerType == "need",
    "a closed popup must not shadow a new roll for the same item")

setDrops()
engine = new()
engine:Start()
start(80)
engine:HandleEvent("CANCEL_LOOT_ROLL", 80)
chat("You won " .. link)
assert(row[1].done and not row[1].closed, "a lone closed popup can still receive its late winner message")

setDrops()
engine = new()
engine:Start()
start(84)
chat("You need " .. link)
engine:HandleEvent("CANCEL_LOOT_ROLL", 84)
advance(1)
start(85)
chat("You won " .. link)
assert(not row[2].done, "a late unkeyed winner must not complete the new popup")
advance(2)
chat("You need " .. link)
chat("You won " .. link)
assert(row[2].done and row[2].winnerType == "need", "the old popup stops blocking results after a short grace")

setDrops()
engine = new()
engine:Start()
start(86)
chat(link .. " greed by Priest")
engine:HandleEvent("CANCEL_LOOT_ROLL", 86)
advance(1)
start(87)
chat("You need " .. link)
chat("You won " .. link)
assert(row[2].done and row[2].winnerType == "need", "a new vote with distinct ownership can settle during the grace")

setDrops()
engine = new()
engine:Start()
start(89)
engine:HandleEvent("CANCEL_LOOT_ROLL", 89)
advance(1)
start(90)
chat("Greed 99 on " .. link .. " by Priest")
chat("Priest won " .. link)
assert(#row[2].rolls == 0 and not row[2].done,
    "a trailing score and winner cannot establish ownership for the newer identical popup")
advance(2)
chat("Greed 95 on " .. link .. " by Priest")
chat("Priest won " .. link)
assert(row[2].winnerValue == 95, "numbered votes remain available when the grace expires")

setDrops()
engine = new()
engine:Start()
start(91)
chat("You need " .. link)
engine:HandleEvent("CANCEL_LOOT_ROLL", 91)
advance(1)
start(92)
chat(link .. " greed by Myself")
chat("Greed 97 on " .. link .. " by Myself")
chat("|HlootHistory:7|h[Loot]|h: Myself (Greed 97) won: " .. link)
assert(row[2].winnerType == "greed" and row[2].winnerValue == 97,
    "an earlier matching choice and distinct predecessor keep a proven score usable during the grace")

setDrops()
engine = new()
engine:Start()
start(93)
local previousVote = roll("Priest", "PRIEST", 3, 86)
previousVote.playerGUID = "Player-Priest"
local previousNative = drop(243, clock, {previousVote})
previousNative.duration = 60
setDrops(previousNative)
emitDrop(engine, 243)
assert(#row == 1 and row[1].capture == "history" and #removed == 1)
previousNative.winner = previousVote
emitDrop(engine, 243)
engine:HandleEvent("CANCEL_LOOT_ROLL", 93)
advance(1)
start(94)
chat("Greed 86 on " .. link .. " by Priest")
chat("Priest won " .. link)
assert(not row[2].winner and #row[2].rolls == 0,
    "a completed native predecessor still competes after its provisional row was removed")
local nextVote = roll("Another", "ROGUE", 0, 92)
local nextNative = drop(244, clock, {nextVote}, nextVote)
setDrops(previousNative, nextNative)
emitDrop(engine, 244)
assert(#row == 2 and row[1].winner == "Priest" and row[2].winner == "Another",
    "a uniquely matched native result can still resolve the newer drop during the grace")
advance(2)
emitDrop(engine, 243)
emitDrop(engine, 244)
advance(1)
start(95)
chat("Greed 86 on " .. link .. " by Priest")
chat("Priest won " .. link)
assert(row[3].winner == "Priest" and row[3].winnerValue == 86,
    "replaying a terminal native snapshot does not extend the grace into an unrelated later roll")

setDrops()
engine = new()
engine:Start()
local cleanClock = C_LootHistory.GetLootHistoryTime
C_LootHistory.GetLootHistoryTime = function() return secret end
start(88)
local clockRecovery = drop(41, clock)
setDrops(clockRecovery)
emitDrop(engine, 41)
assert(#row == 2 and #removed == 0, "a restricted clock cannot prove that two rows represent the same drop")
advance(1)
C_LootHistory.GetLootHistoryTime = cleanClock
clockRecovery.winner = quickWinner
emitDrop(engine, 41)
assert(#row == 1 and #removed == 1 and row[1].winnerValue == 42,
    "the native winner can reconcile the provisional row once the clock recovers")

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
bound.winner = { playerName = "Unique", playerGUID = secret }
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false,
    "a winner's restricted GUID must not authorize an inspection by name when the participant array omits them")
bound.rollInfos = {known, otherParticipant}
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false,
    "an unmarked same-name participant cannot bypass a winner's restricted GUID")
bound.winner = nil
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == false,
    "an update that omits the winner cannot restore a restricted binding")
bound.winner = known
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == "Player-Known",
    "a clean authoritative winner update can restore the participant binding")
otherParticipant.playerName = secret
emitDrop(engine, 21)
assert(not engine:GetParticipantGUID(remembered, "Unique"), "a hidden participant cannot establish unique name ownership")
otherParticipant.playerName = "Other Person"
emitDrop(engine, 21)
assert(engine:GetParticipantGUID(remembered, "Unique") == "Player-Known")
engine:Reset()
assert(not engine:GetParticipantGUID(remembered, "Unique"), "fresh state must not retain old bindings")

setDrops()
engine = new()
engine:Start()
local scored = roll("Visible", "MAGE", 0, 83)
scored.playerGUID = "Player-Visible"
local scoredDrop = drop(42, clock, {scored})
setDrops(scoredDrop)
emitDrop(engine, 42)
local current = roll("Visible", "MAGE", 0, secret)
current.playerGUID = "Player-Visible"
scoredDrop.rollInfos = {current, secret}
emitDrop(engine, 42)
assert(row[1].rolls[1].value == 83, "retain the exact known score while it is unreadable")
current.roll = 89
emitDrop(engine, 42)
assert(row[1].rolls[1].value == 89)
current.state, current.roll = 1, nil
emitDrop(engine, 42)
assert(row[1].rolls[1].value == nil, "another native Need type cannot inherit a score")
current.roll = 92
emitDrop(engine, 42)
current.playerGUID, current.roll = "Player-Replacement", nil
emitDrop(engine, 42)
assert(row[1].rolls[1].value == nil, "the same rendered name cannot inherit another GUID's score")
current.playerGUID = "Player-Visible"
local conflicting = roll("Other", "MAGE", 1, nil)
conflicting.playerGUID = current.playerGUID
scoredDrop.rollInfos = {current, conflicting}
emitDrop(engine, 42)
assert(row[1].rolls[1].value == nil and row[1].rolls[2].value == nil,
    "a duplicated GUID cannot inherit a cached score")

setDrops()
engine = new()
engine:Start()
local finishedVote = roll("Confirmed", "MAGE", 0, 86)
finishedVote.playerGUID = "Player-Confirmed"
local finishedDrop = drop(43, clock, {finishedVote})
setDrops(finishedDrop)
emitDrop(engine, 43)
finishedVote.roll = secret
finishedDrop.winner = {playerName = "Confirmed", playerClass = "MAGE", playerGUID = "Player-Confirmed", state = 0}
emitDrop(engine, 43)
assert(row[1].winnerValue == 86 and row[1].rolls[1].value == 86,
    "the confirmed winner uses the earlier score for the same GUID and native state")

setDrops()
engine = new()
engine:Start()
finishedVote.roll = 87
finishedDrop = drop(44, clock, {finishedVote})
setDrops(finishedDrop)
emitDrop(engine, 44)
finishedVote.roll = secret
finishedDrop.winner = {playerName = "Confirmed", playerClass = "MAGE", playerGUID = "Player-Confirmed", state = 1}
emitDrop(engine, 44)
assert(row[1].done and not row[1].winnerValue, "a different terminal native state cannot borrow an old score")

local function knownWinner(key)
    setDrops()
    engine = new()
    engine:Start()
    local vote = roll("Confirmed", "MAGE", 0, 86)
    vote.playerGUID = "Player-Confirmed"
    local tracked = drop(key, clock, {vote}, vote)
    setDrops(tracked)
    emitDrop(engine, key)
    assert(row[1].winnerType == "need" and row[1].winnerValue == 86)
    return vote
end

local correctedWinner = knownWinner(45)
correctedWinner.state, correctedWinner.roll = secret, secret
emitDrop(engine, 45)
assert(row[1].winnerType == "need" and row[1].winnerValue == 86,
    "a masked winner choice and value do not invalidate previously confirmed data")
correctedWinner.state, correctedWinner.roll = 3, nil
emitDrop(engine, 45)
assert(row[1].winnerType == "greed" and row[1].winnerValue == nil,
    "a confirmed Greed winner cannot inherit a previous Need score")

correctedWinner = knownWinner(46)
correctedWinner.state, correctedWinner.roll = 1, nil
emitDrop(engine, 46)
assert(row[1].winnerType == "need" and row[1].winnerValue == nil,
    "different native Need states cannot share a previously confirmed score")

correctedWinner = knownWinner(47)
correctedWinner.playerClass, correctedWinner.roll = "PRIEST", nil
emitDrop(engine, 47)
assert(row[1].winnerClass == "PRIEST" and row[1].winnerValue == nil,
    "a corrected winner class cannot inherit a previous score")

correctedWinner = knownWinner(48)
correctedWinner.roll = 0
emitDrop(engine, 48)
assert(row[1].winnerValue == nil, "an explicit invalid score is different from a masked score")

setDrops()
engine = new()
engine:Start()
local terminalVote = roll("Priest", "PRIEST", 3, 87)
local terminalDrop = drop(250, clock, {terminalVote})
setDrops(terminalDrop)
emitDrop(engine, 250)
assert(#row == 1 and not row[1].done)
terminalDrop.winner = terminalVote
local readDrop = C_LootHistory.GetSortedInfoForDrop
C_LootHistory.GetSortedInfoForDrop = function() error("history temporarily unavailable") end
emitDrop(engine, 250)
assert(not row[1].done)
C_LootHistory.GetSortedInfoForDrop = readDrop
setDrops(drop(250, clock - 1))
emitDrop(engine, 250)
setDrops(terminalDrop)
advance(1)
assert(row[1].done and row[1].winnerValue == 87,
    "a transient read failure must recover the final result even if an older generation is replayed first")

advance(1)
local previousDrop = drop(251, clock)
setDrops(previousDrop)
emitDrop(engine, 251)
local attempts = 0
C_LootHistory.GetSortedInfoForDrop = function()
    attempts = attempts + 1
    return nil
end
emitDrop(engine, 251)
emitDrop(engine, 251)
for _ = 1, 8 do advance(0.5) end
assert(attempts == 6, "repeated failed events must share a bounded retry")
emitDrop(engine, 251)
local recycledDrop = drop(251, clock, {terminalVote}, terminalVote)
setDrops(recycledDrop)
C_LootHistory.GetSortedInfoForDrop = readDrop
advance(0.5)
assert(#row == 2 and not row[2].done, "an old retry must not ingest a recycled key's new generation")
emitDrop(engine, 251)
assert(#row == 3 and row[3].winnerValue == 87, "a new event can confirm the recycled key")

setDrops()
engine = new()
engine:Start()
local incompleteDrop = drop(252, clock, {terminalVote})
setDrops(incompleteDrop)
emitDrop(engine, 252)
local originalStart = incompleteDrop.startTime
incompleteDrop.winner, incompleteDrop.startTime = terminalVote, nil
emitDrop(engine, 252)
incompleteDrop.startTime = originalStart
setDrops(drop(252, clock - 1))
advance(0.5)
assert(not row[1].done, "a stale native revision cannot finish the current roll")
setDrops(incompleteDrop)
advance(0.5)
assert(row[1].done and row[1].winnerValue == 87, "a partially populated update must retry the same tracked roll")

for _, staleSnapshot in ipairs({"older start", "different item at the same start"}) do
    setDrops()
    engine = new()
    engine:Start()
    local activeDrop = drop(253, clock, {terminalVote})
    setDrops(activeDrop)
    emitDrop(engine, 253)
    local staleDrop = drop(253, clock)
    if staleSnapshot == "older start" then
        staleDrop.startTime = clock - 1
    else
        staleDrop.itemHyperlink = "|cff0070dd|Hitem:456:0|h[Different Item]|h|r"
    end
    activeDrop.winner = terminalVote
    setDrops(staleDrop)
    emitDrop(engine, 253)
    advance(0.5)
    assert(#row == 1 and not row[1].done, "a mismatched snapshot must not replace the active drop")
    setDrops(activeDrop)
    advance(0.5)
    assert(row[1].done and row[1].winnerValue == 87, "an update must recover from a " .. staleSnapshot)
end

setDrops()
engine = new()
engine:Start()
local lateFirstDrop = drop(254, clock, {terminalVote}, terminalVote)
emitDrop(engine, 254)
assert(#row == 0)
advance(0.5)
setDrops(lateFirstDrop)
advance(0.5)
assert(#row == 1 and row[1].winnerValue == 87,
    "a drop missed on its first event must recover without a second event")

for _, boundary in ipairs({"reset", "clear", "future key"}) do
    setDrops()
    engine = new()
    engine:Start()
    local missed = drop(255, clock, {terminalVote}, terminalVote)
    emitDrop(engine, 255)
    if boundary == "reset" then
        engine:Reset()
    elseif boundary == "clear" then
        engine:HandleEvent("LOOT_HISTORY_CLEAR_HISTORY")
    else
        missed.startTime = clock + 0.25
    end
    setDrops(missed)
    advance(0.5)
    assert(#row == 0, "an unbound retry must not cross " .. boundary)
    emitDrop(engine, 255)
    assert(#row == 1 and row[1].winnerValue == 87, "a fresh event can confirm the drop after " .. boundary)
end

setDrops()
engine = new()
engine:Start()
local untrackedReads = 0
C_LootHistory.GetSortedInfoForDrop = function()
    untrackedReads = untrackedReads + 1
end
emitDrop(engine, 256)
emitDrop(engine, 256)
for _ = 1, 8 do advance(0.5) end
C_LootHistory.GetSortedInfoForDrop = readDrop
assert(untrackedReads == 6, "repeated unreadable first reads share a bounded retry")

setDrops()
engine = new()
engine:Start()
local readEncounter = C_LootHistory.GetSortedDropsForEncounter
local encounterReads = 0
C_LootHistory.GetSortedDropsForEncounter = function(...)
    encounterReads = encounterReads + 1
    if encounterReads <= 3 then return secret end
    return readEncounter(...)
end
local missedEncounterDrop = drop(257, clock)
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
advance(0.5)
setDrops(missedEncounterDrop, drop(258, clock))
advance(0.5)
C_LootHistory.GetSortedDropsForEncounter = readEncounter
assert(encounterReads == 4 and #row == 1 and row[1].lootListKey == 257,
    "encounter retries must share a window and ignore drops newer than the failed event")

local olderEncounterRow = drop(257, missedEncounterDrop.startTime - 1)
setDrops(olderEncounterRow)
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
assert(not row[1].done)
missedEncounterDrop.winner, missedEncounterDrop.rollInfos = terminalVote, {terminalVote}
setDrops(missedEncounterDrop)
advance(0.5)
assert(row[1].done and row[1].winnerValue == 87 and #row == 1,
    "an older row in an encounter scan must retry only the matching tracked drop")

setDrops()
engine = new()
engine:Start()
local revised = drop(260, clock, {terminalVote}, terminalVote)
local sibling = drop(261, clock)
C_LootHistory.GetSortedDropsForEncounter = function() return nil end
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
setDrops(revised)
emitDrop(engine, 260)
C_LootHistory.GetSortedDropsForEncounter = readEncounter
local staleVote = roll("Priest", "PRIEST", 3, 3)
setDrops(drop(260, revised.startTime, {staleVote}, staleVote), sibling)
advance(0.5)
assert(#row == 2 and row[1].winnerValue == 87 and row[2].lootListKey == 261,
    "a direct event supersedes only its own row during the older encounter retry")

for _, revoke in ipairs({"world", "reset", "clear", "expiry", "delayed wake"}) do
    setDrops()
    engine = new()
    engine:Start()
    local nextDrop = drop(259, clock, {terminalVote}, terminalVote)
    local refreshes = 0
    C_LootHistory.GetSortedDropsForEncounter = function() refreshes = refreshes + 1 end
    engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
    if revoke == "world" then
        engine:CancelPendingReads()
    elseif revoke == "reset" then
        engine:Reset()
    elseif revoke == "clear" then
        engine:HandleEvent("LOOT_HISTORY_CLEAR_HISTORY")
    elseif revoke == "expiry" then
        for _ = 1, 8 do advance(0.5) end
        assert(refreshes == 5, "an unreadable encounter stops after four retries")
    end
    C_LootHistory.GetSortedDropsForEncounter = readEncounter
    setDrops(nextDrop)
    advance(revoke == "delayed wake" and 3 or 0.5)
    assert(#row == 0, "an encounter retry cannot outlive " .. revoke)
    engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
    assert(#row == 1 and row[1].winnerValue == 87)
end

for _, event in ipairs({"LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER"}) do
    setDrops()
    engine = new()
    engine:Start()
    local firstVote = roll("Priest", "PRIEST", 3, 36)
    local partial = drop(262, clock, {firstVote})
    setDrops(partial)
    emitDrop(engine, 262)
    partial.rollInfos, partial.winner = secret, terminalVote
    engine:HandleEvent(event, 7, 262)
    assert(row[1].done and #row[1].rolls == 1 and row[1].rolls[1].value == 36,
        "an unreadable list must preserve known votes and readable winner evidence")
    partial.rollInfos = {terminalVote}
    advance(0.5)
    assert(#row == 1 and row[1].rolls[1].value == 87,
        "an unreadable roll list must retry " .. event)
end

setDrops()
engine = new()
engine:Start()
local maskedKey = drop(263, clock, {terminalVote}, terminalVote)
maskedKey.lootListKey = secret
setDrops(maskedKey)
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
assert(#row == 0)
maskedKey.lootListKey = 263
advance(0.5)
assert(#row == 1 and row[1].lootListKey == 263 and row[1].winnerValue == 87,
    "an encounter with a masked key must recover after the key becomes readable")

setDrops()
engine = new()
engine:Start()
local limited = drop(264, clock, {terminalVote})
setDrops(limited)
emitDrop(engine, 264)
local onlyPartial = drop(264, clock)
onlyPartial.startTime = secret
C_LootHistory.GetSortedDropsForEncounter = function() return nil end
engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
for _ = 1, 3 do advance(0.5) end
C_LootHistory.GetSortedDropsForEncounter = readEncounter
setDrops(onlyPartial)
advance(0.5)
limited.winner = terminalVote
setDrops(limited)
advance(0.5)
assert(not row[1].done, "a per-key retry spawned by an encounter cannot extend the original deadline")
emitDrop(engine, 264)
assert(row[1].done and row[1].winnerValue == 87)

for _, event in ipairs({"LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER"}) do
    for _, expire in ipairs({false, true}) do
        setDrops()
        engine = new()
        engine:Start()
        C_LootHistory.GetSortedDropsForEncounter = function() return nil end
        engine:HandleEvent(event, 7, 265)
        advance(0.25)
        local newer = drop(265, clock, {terminalVote}, terminalVote)
        engine:HandleEvent(event, 7, 265)
        C_LootHistory.GetSortedDropsForEncounter = readEncounter
        setDrops(newer)
        advance(expire and 2 or 0.25)
        if expire then
            assert(#row == 0, "a later event must not renew an existing retry's absolute deadline")
        else
            assert(#row == 1 and row[1].winnerValue == 87,
                "a newer explicit event must allow an unseen row that started before it")
        end
    end
end

for _, scenario in ipairs({"same-generation update", "recycled key", "stale first read"}) do
    setDrops()
    engine = new()
    engine:Start()
    local original = drop(270, clock)
    advance(0.25)
    local sibling = drop(271, clock)
    sibling.lootListKey = secret
    setDrops(original, sibling)
    engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
    assert(#row == 1 and not row[1].done)
    if scenario ~= "stale first read" then
        advance(0.25)
        C_LootHistory.GetSortedDropsForEncounter = function() return nil end
        engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
        C_LootHistory.GetSortedDropsForEncounter = readEncounter
    end

    local newStart = scenario == "same-generation update" and original.startTime or clock
    local updated = drop(270, newStart, {terminalVote}, terminalVote)
    sibling.lootListKey = 271
    setDrops(updated, sibling)
    advance(0.5)
    if newStart == original.startTime then
        assert(#row == 2 and row[1].winnerValue == 87, "a new event authorizes a newer result for the same generation")
    else
        assert(#row == 3 and row[1].closed and row[2].winnerValue == 87,
            "a confirmed older generation must not hide a recycled key after " .. scenario)
    end
end

for _, route in ipairs({"drop", "drop while retrying", "encounter", "encounter retry", "ignored previous"}) do
    local original = drop(280, clock)
    if route == "ignored previous" then setDrops(original) else setDrops() end
    engine = new()
    engine:Start()
    setDrops(original)
    emitDrop(engine, 280)
    local oldCount = #row
    advance(1)
    if route == "drop while retrying" then
        setDrops()
        emitDrop(engine, 280)
    end

    local newDrop = drop(280, clock, {terminalVote}, terminalVote)
    local fullLink = newDrop.itemHyperlink
    newDrop.itemHyperlink = secret
    setDrops(newDrop)
    if route == "encounter retry" then
        C_LootHistory.GetSortedDropsForEncounter = function() return secret end
        engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
        C_LootHistory.GetSortedDropsForEncounter = readEncounter
        advance(0.5)
    elseif route == "encounter" then
        engine:HandleEvent("LOOT_HISTORY_UPDATE_ENCOUNTER", 7)
    else
        emitDrop(engine, 280)
    end
    setDrops(original)
    advance(0.5)
    assert(#row == oldCount and (oldCount == 0 or not row[1].done), "an older generation cannot consume a newer retry")
    newDrop.itemHyperlink = fullLink
    setDrops(newDrop)
    advance(0.5)
    assert(#row == oldCount + 1 and row[#row].winnerValue == 87,
        "recover the readable generation start after a temporarily masked item via " .. route)
end

setDrops()
engine = new()
engine:Start()
local waitingForLink = drop(281, clock)
waitingForLink.itemHyperlink = secret
setDrops(waitingForLink)
emitDrop(engine, 281)
local unrelatedStart = drop(281, clock + 0.25, {terminalVote}, terminalVote)
setDrops(unrelatedStart)
advance(0.5)
assert(#row == 0, "a clean start with a masked link cannot authorize a further generation")
emitDrop(engine, 281)
assert(#row == 1 and row[1].winnerValue == 87, "a fresh event can confirm the further generation")

for _, event in ipairs({"LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER"}) do
    setDrops()
    engine = new()
    engine:Start()
    local previous = drop(282, clock)
    setDrops(previous)
    emitDrop(engine, 282)
    advance(1)

    local replacement = drop(282, clock, {terminalVote}, terminalVote)
    local fullLink = replacement.itemHyperlink
    replacement.itemHyperlink = secret
    setDrops(replacement)
    emitDrop(engine, 282)

    previous.winner = terminalVote
    setDrops(previous)
    engine:HandleEvent(event, 7, 282)
    assert(#row == 1 and not row[1].done, "a stale explicit event cannot replace pending newer generation evidence")

    replacement.itemHyperlink = fullLink
    setDrops(replacement)
    advance(0.5)
    assert(#row == 2 and row[1].closed and row[2].winnerValue == 87,
        "a stale explicit event must leave the newer retry pending")
end

setDrops()
engine = new()
engine:Start()
local uncertain = drop(283, clock)
uncertain.itemHyperlink = secret
setDrops(uncertain)
emitDrop(engine, 283)
advance(0.25)
local confirmedNewer = drop(283, clock, {terminalVote}, terminalVote)
setDrops(confirmedNewer)
emitDrop(engine, 283)
advance(0.5)
assert(#row == 1 and row[1].startTime == confirmedNewer.startTime and row[1].winnerValue == 87,
    "a newer fully readable explicit event can supersede pending generation evidence")

print("Capture tests passed")
