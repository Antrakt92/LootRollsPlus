local root = arg[1] or "."
local ns = {}
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
print("live roll model and party/raid previews passed")
