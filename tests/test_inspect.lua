local root = arg[1] or "."
local ns = {}
local drop = "|cff00ff00|Hitem:123::::::::|h[Drop]|h|r"
local weapon = "|cff00ff00|Hitem:456::::::::|h[Weapon]|h|r"
local offhand = "|cff00ff00|Hitem:457::::::::|h[Off hand]|h|r"
local restricted = {}
function issecretvalue(value) return value == restricted end
local members = { player = {"Self", "P", "MAGE"}, party1 = {"Other Mage", "A", "MAGE"} }
local location, combat, requests, clock = "INVTYPE_WEAPON", false, 0, 10
local timers, reads = {}, {}
function UnitGUID(unit) return members[unit] and members[unit][2] end
function UnitName(unit) return members[unit] and members[unit][1]:match("^%S+") end
function UnitClass(unit) return "", members[unit] and members[unit][3] end
function GetNumGroupMembers() return 2 end
function IsInRaid() return false end
function InCombatLockdown() return combat end
function CanInspect() return true end
function NotifyInspect(unit) assert(unit == "party1"); requests = requests + 1 end
function GetTime() return clock end
function time() return 3000 end
function GetInventorySlotInfo(name)
    return ({ MainHandSlot = 16, SecondaryHandSlot = 17, Finger0Slot = 11, Finger1Slot = 12 })[name]
end
function GetInventoryItemLink(unit, slot)
    reads[#reads + 1] = {unit, slot}
    return slot == 16 and weapon or slot == 17 and offhand or nil
end
NameUtil = {GetUnmodifiedUnitFullName = function(unit) return members[unit] and members[unit][1] end}
C_Item = {GetItemInfoInstant = function() return 123, nil, nil, location end}
C_Timer = {After = function(_, callback) timers[#timers + 1] = callback end}
assert(loadfile(root .. "/Capture.lua"))("LootRollsPlus", ns)
assert(loadfile(root .. "/Inspect.lua"))("LootRollsPlus", ns)
local inspect = ns.NewInspect()
local status, result, resultGUID
local function receive(state, items, guid) status, result, resultGUID = state, items, guid end

assert(ns.HasInspectSlot(drop))
location = ""
assert(not ns.HasInspectSlot(drop), "trade goods must not offer an inspect action")
location = nil
local hasSlot, pendingSlot = ns.HasInspectSlot(drop)
assert(not hasSlot and pendingSlot, "cold metadata can become equippable")
location = "INVTYPE_WEAPON"

assert(inspect:Request(drop, "Other", "MAGE", receive) == "absent")
assert(inspect:Request(drop, "Other Mage", "ROGUE", receive) == "absent")
assert(inspect:Request(drop, "Self", "MAGE", receive) == nil and status == "ready")
assert(result.at == 3000 and result.links[1] == weapon and result.links[2] == offhand and requests == 0)
assert(resultGUID == "P" and not result.guid, "the identity is returned separately from the snapshot")

assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "loading" and requests == 1)
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "busy")
local whilePending
assert(inspect:Request(drop, "Self", "MAGE", function(state, snapshot)
    assert(state == "ready")
    whilePending = snapshot
end) == nil)
assert(whilePending.links[1] == weapon and requests == 1)
inspect:Ready("wrong")
inspect:Ready(restricted)
assert(#reads == 4)
inspect:Ready("A")
assert(#reads == 6 and reads[5][1] == "party1" and status == "ready" and result.count == 2)
assert(resultGUID == "A" and not result.guid)
timers[1]()
assert(status == "ready")

clock = 13
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "loading")
members.party1[2] = "B"
inspect:Ready("A")
assert(status == "unavailable" and not result and #reads == 6)
assert(not resultGUID)
clock = 16
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "loading")
timers[3]()
assert(status == "timeout" and not result)
inspect:Ready("B")
assert(#reads == 6)

combat = true
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "combat")
combat = false
InspectFrame = {IsShown = function() return true end}
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "inspectOpen")
location = "INVTYPE_NON_EQUIP"
assert(inspect:Request(drop, "Self", "MAGE", receive) == "unsupported")

InspectFrame = nil
PlayerSpellsFrame = {GetInspectUnit = function() return "target" end}
location = "INVTYPE_WEAPON"
clock = 19
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "inspectOpen")
PlayerSpellsFrame = nil
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "loading")
PlayerSpellsFrame = {GetInspectUnit = function() return "target" end}
inspect:Ready("B")
assert(status == "unavailable" and not result and #reads == 6)
PlayerSpellsFrame = nil

local priorItemInfo = C_Item.GetItemInfoInstant
C_Item.GetItemInfoInstant = function() return 999, nil, nil, "INVTYPE_WEAPON" end
assert(inspect:Request(drop, "Self", "MAGE", receive) == "unsupported")
C_Item.GetItemInfoInstant = priorItemInfo

-- Camelot's namespace must work without deprecated global slot APIs.
C_PaperDollInfo, GetInventorySlotInfo = {GetInventorySlotInfo = GetInventorySlotInfo}, nil
function GetInventoryItemLink(_, slot) if slot == 16 then return weapon end end
function GetInventoryItemID(_, slot) if slot == 16 then return 456 end end
assert(inspect:Request(drop, "Self", "MAGE", receive) == nil and status == "ready")
assert(result.links[1] == weapon and result.links[2] == nil and result.empty[2] == true)
function GetInventoryItemID() return 456 end
inspect:Request(drop, "Self", "MAGE", receive)
assert(status == "ready" and result.empty[2] == nil, "an equipped item with an uncached link is unknown")
function GetInventoryItemID() error("Inventory ID unavailable") end
inspect:Request(drop, "Self", "MAGE", receive)
assert(status == "ready" and result.empty[2] == nil)
function GetInventoryItemID() return nil end
function GetInventoryItemLink(_, slot) return slot == 16 and weapon or restricted end
inspect:Request(drop, "Self", "MAGE", receive)
assert(status == "ready" and result.empty[2] == nil, "a restricted item link must stay unknown")
function GetInventoryItemLink(_, slot) if slot == 16 then return weapon end end
clock = 22
assert(inspect:Request(drop, "Other Mage", "MAGE", receive) == "loading")
inspect:Ready("B")
assert(status == "ready" and result.empty[2] == nil, "remote nil must remain unknown")

members.player[1] = "Self Player"
assert(inspect:Request(drop, "Self", "MAGE", receive) == nil and status == "ready")
members.party1[1] = "Self Other"
assert(inspect:Request(drop, "Self", "MAGE", receive) == "absent")
assert(inspect:Request(drop, "Self Player", "MAGE", receive) == nil and status == "ready")

-- Known native identities cannot fall back to a different character, even
-- when the replacement has exactly the same name and class.
members.party1[1], members.party1[2] = "Other Mage", "B"
clock = 25
local before = requests
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, "A") == "absent")
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, restricted) == "absent")
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, "") == "absent")
assert(inspect:Request(drop, "Other Mage", "WARRIOR", receive, "B") == "absent")
assert(inspect:Request(drop, "Different Name", "MAGE", receive, "B") == "absent")
assert(inspect:Request(drop, "Self", "MAGE", receive, "B") == "absent")
assert(requests == before)

assert(inspect:Request(drop, "Self", "MAGE", receive, "P") == nil and status == "ready")
assert(inspect:Request(drop, "Other", "MAGE", receive) == "absent")
assert(inspect:Request(drop, "Other", "MAGE", receive, "B") == "loading")
inspect:Ready("A")
assert(status == "ready" and result.empty[2] == true, "a different GUID must not replace the self inspection")
inspect:Ready("B")
assert(status == "ready" and result.links[1] == weapon and result.empty[2] == nil)
assert(requests == before + 1)

clock = 28
local normalCanInspect = CanInspect
function CanInspect()
    members.party1[2] = "B-Replacement"
    return true
end
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, "B") == "unavailable")
assert(requests == before + 1, "a recycled unit token must not reach NotifyInspect")
CanInspect, members.party1[2] = normalCanInspect, "B"
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, "B") == "loading")
inspect:Ready("B")
assert(status == "ready")

clock = 31
local cancelledResults = 0
local function receiveCancelled() cancelledResults = cancelledResults + 1 end
assert(inspect:Request(drop, "Other Mage", "MAGE", receiveCancelled, "B") == "loading")
inspect:CancelPending()
inspect:Ready("B")
timers[#timers]()
assert(cancelledResults == 0, "leaving the world must discard both inspect results and timeouts")
assert(inspect:Request(drop, "Other Mage", "MAGE", receiveCancelled, "B") == "busy",
    "cancellation still respects the global inspect throttle")

clock = 34
local standardNotifyInspect = NotifyInspect
function NotifyInspect(unit)
    standardNotifyInspect(unit)
    inspect:Ready("B")
end
assert(inspect:Request(drop, "Other Mage", "MAGE", receive, "B") == nil and status == "ready",
    "a result delivered by a NotifyInspect hook must not be replaced with a loading status")
NotifyInspect = standardNotifyInspect
print("Inspect tests passed")
