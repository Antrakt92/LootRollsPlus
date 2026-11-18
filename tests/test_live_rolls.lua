local root = arg[1] or "."
local ns = {}
local restricted = {}
function issecretvalue(value) return value == restricted end
function GetLocale() return "enUS" end
assert(loadfile(root .. "/LiveRolls.lua"))("LootRollsPlus", ns)

local raw = {
    id = 901, anchor = {}, rolls = {
        {name = "Greed", state = "greed", roll = 100},
        {name = "Offspec", state = "offspec", roll = 99},
        {name = "First", state = "need", roll = 41, class = "MAGE", isSelf = true},
        {name = "Second", state = "need", roll = 41},
        {name = "Pending", state = "need"},
        {name = "Undecided", state = "waiting"},
        {name = "Pass", state = "pass"},
    },
}
local view = ns.BuildLiveRolls({raw})[1]
assert(view.id == raw.id and view.anchor == raw.anchor and not view.winner)
assert(view.counts.need == 3 and view.counts.offspec == 1 and view.counts.waiting == 1)
assert(view.counts.greed == 1 and view.counts.pass == 1)
assert(view.players[1].name == "First" and view.players[2].name == "Second")
assert(view.players[1].class == "MAGE" and view.players[1].isSelf)
assert(view.players[3].name == "Pending" and view.players[3].roll == nil)
assert(view.players[4].name == "Offspec" and view.players[7].name == "Undecided")
assert(view.leaders[1].name == "First" and view.leaders[2].name == "Second" and view.more == 1)
local offspec = ns.BuildLiveRolls({{id = 900, rolls = {{name = "Offspec", state = "offspec", roll = 99}}}})[1]
assert(#offspec.leaders == 0 and offspec.more == 0 and offspec.counts.offspec == 1)
assert(raw.rolls[1].order == nil and raw.rolls[1].name == "Greed", "the display must not mutate source records")

raw.winner = {name = "Offspec", state = "offspec", roll = 99}
view = ns.BuildLiveRolls({raw})[1]
assert(view.winner.name == "Offspec" and view.winner.choice == "offspec" and view.winner.roll == 99)

view = ns.BuildLiveRolls({{id = 902, rolls = {}, ambiguous = true}})[1]
assert(view.ambiguous and next(view.counts) == nil and #view.players == 0 and view.more == 0)
view = ns.BuildLiveRolls({{id = 903, rolls = {}, allPassed = true}})[1]
assert(view.allPassed)
view = ns.BuildLiveRolls({{id = 904, rolls = {{name = "Need", state = "need"}}}})[1]
assert(#view.leaders == 0 and view.more == 1 and view.counts.need == 1)

local start = ns.BuildLiveRolls(ns.LiveRollDemo(true, 0))
assert(#start == 3 and #start[1].players == 40 and #start[1].leaders == 0)
assert(start[1].counts.need == 2 and start[1].counts.waiting == 38)
local raid = ns.BuildLiveRolls(ns.LiveRollDemo(true, 34))
assert(#raid == 3 and raid[2].name == raid[3].name and raid[2].id ~= raid[3].id)
for _, entry in ipairs(raid) do
    assert(#entry.players == 40 and entry.more == 7 and #entry.leaders == 2)
    assert(entry.counts.need == 9 and entry.counts.greed == 17 and entry.counts.pass == 8 and entry.counts.waiting == 6)
end
assert(raid[1].leaders[1].name ~= raid[2].leaders[1].name, "demo copies must have independent roll data")
local party = ns.BuildLiveRolls(ns.LiveRollDemo(false, 4))
assert(#party[1].players == 5 and party[1].counts.waiting == 1 and party[1].counts.pass == 1)
assert(not party[1].canInspect and party[2].canInspect and party[3].canInspect)
local checked
local function hasSlot(link)
    checked = link
    return true
end
view = ns.BuildLiveRolls({{id = 905, link = "equippable", rolls = {}}}, nil, hasSlot)[1]
assert(view.canInspect and checked == "equippable")
checked = nil
view = ns.BuildLiveRolls({{id = 906, link = "equippable", rolls = {}, ambiguous = true}}, nil, hasSlot)[1]
assert(not view.canInspect and not checked)
view = ns.BuildLiveRolls({{id = 907, rolls = {}}}, nil, hasSlot)[1]
assert(not view.canInspect and not checked)

local rosterScans, levelReads = 0, 0
local guids = { player = "Self-GUID", party1 = "First-GUID", party2 = "Second-GUID", party3 = restricted,
    party4 = "Restricted-Level-GUID" }
local levels = { player = 39, party1 = 40, party2 = 32, party4 = restricted }
function UnitGUID(unit) return guids[unit] end
function UnitLevel(unit) levelReads = levelReads + 1; return levels[unit] end
function IsInRaid() return false end
function GetNumGroupMembers() rosterScans = rosterScans + 1; return 5 end
local function classify(_, player)
    return player.level and player.level >= 40 and "atypical" or nil
end
local function vote(guid, state)
    return {name = "Same Name", class = "PALADIN", state = state or "need", guid = guid}
end
ns.BuildLiveRolls({{rolls = {vote("First-GUID", "greed"), vote(restricted), vote(false)}}}, classify)
assert(rosterScans == 0 and levelReads == 0, "unrelated or restricted choices should not trigger roster reads")

local first, second = vote("First-GUID"), vote("Second-GUID", "offspec")
local entries = ns.BuildLiveRolls({
    {rolls = {first, second, vote("Unknown-GUID"), vote("Restricted-Level-GUID"), vote("Self-GUID")}, winner = first},
    {rolls = {first}},
}, classify)
assert(rosterScans == 1 and levelReads == 4, "one roster pass should serve all rolls and the winner, reading each level once")
local players = entries[1].players
assert(players[1].level == 40 and players[1].warning == "atypical" and entries[1].winner.warning == "atypical")
assert(players[2].level == nil and players[3].level == nil, "unknown GUIDs and restricted levels must not borrow a level by name")
assert(players[4].level == 39 and players[5].level == 32 and not players[5].warning,
    "different players of the same class can have different armor tiers")
assert(first.level == nil and second.level == nil, "roster metadata belongs to view copies")

function IsInRaid() return true end
function GetNumGroupMembers() return 40 end
guids.raid40, levels.raid40 = "Last-Raid-GUID", 42
guids.raid12, levels.raid12 = "Self-GUID", 55
view = ns.BuildLiveRolls({{rolls = {vote("Last-Raid-GUID"), vote("Self-GUID")}}}, classify)[1]
assert(view.players[1].level == 42 and view.players[2].level == 39,
    "inspect the last raid slot and prefer the player token for self")

function IsInRaid() return false end
function GetNumGroupMembers() return 5 end
function UnitLevel(unit)
    guids[unit] = "Replacement-GUID"
    return 40
end
view = ns.BuildLiveRolls({{rolls = {first}}}, classify)[1]
assert(not view.players[1].level and not view.players[1].warning,
    "a recycled unit token may not supply another player's level")
print("live roll model and party/raid previews passed")
