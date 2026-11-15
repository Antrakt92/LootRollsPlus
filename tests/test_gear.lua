local source = arg[1] or "local-addons/LootRollsPlus/Gear.lua"
local link = "|cffffffff|Hitem:12345::::::::|h[Test gear]|h|r"
local privateValue = {}
issecretvalue = function(value) return value == privateValue end

local _, namespace = "LootRollsPlus", {}
local itemClass, itemSubclass, slot
local reads = 0
local instant = function(itemLink)
    assert(itemLink == link)
    reads = reads + 1
    return 12345, "Item", "Item subclass", slot, 123, itemClass, itemSubclass
end
C_Item = {GetItemInfoInstant = instant}
assert(loadfile(source))("LootRollsPlus", namespace)
local classify = namespace.Gear.Classify

local function setItem(newClass, subclass, equipLocation)
    itemClass, itemSubclass, slot = newClass, subclass, equipLocation
end

local function expect(class, level, expected)
    local kind, pending = classify(link, class, "need", level)
    assert(kind == expected, ("Unexpected kind for %s at %s: %s"):format(class, tostring(level), tostring(kind)))
    assert(pending == nil, "Unexpected pending result")
end

setItem(4, 1, "INVTYPE_ROBE")
expect("PALADIN", 30, "atypical")
expect("PALADIN", 40, "atypical")
expect("PALADIN", nil, "atypical")
expect("DRUID", 60, "atypical")
expect("PRIEST", 60)
expect("MAGE", 60)
expect("WARLOCK", 60)

setItem(4, 2, "INVTYPE_CHEST")
expect("WARRIOR", 39, "atypical")
expect("WARRIOR", 40, "atypical")
expect("WARRIOR", nil, "atypical")
expect("HUNTER", 39)
expect("SHAMAN", 39)
expect("HUNTER", 40, "atypical")
expect("SHAMAN", nil)
expect("SHAMAN", 0)
expect("SHAMAN", math.huge)
expect("SHAMAN", 39.5)
expect("SHAMAN", privateValue)
expect("ROGUE", 60)
expect("MAGE", 60, "incompatible")

setItem(4, 3, "INVTYPE_WRIST")
expect("WARRIOR", 39)
expect("WARRIOR", 40, "atypical")
expect("PALADIN", nil)
expect("SHAMAN", 39)
expect("HUNTER", 60)
expect("DRUID", 60, "incompatible")
setItem(4, 4, "INVTYPE_HEAD")
expect("PALADIN", 39)
expect("PALADIN", 40)
expect("SHAMAN", 60, "incompatible")

setItem(4, 1, "INVTYPE_CLOAK")
expect("PALADIN", 60)
setItem(4, 1, "INVTYPE_BODY")
expect("PALADIN", 60)
setItem(4, 0, "INVTYPE_HOLDABLE")
expect("MAGE", 60)
setItem(4, 6, "INVTYPE_SHIELD")
expect("MAGE", 60, "incompatible")
expect("PALADIN", 20)
expect("WARRIOR", 20)
expect("SHAMAN", 20)
setItem(4, 7, "INVTYPE_RELIC")
expect("PALADIN", 60)
expect("DRUID", 60, "incompatible")
setItem(4, 8, "INVTYPE_RELIC")
expect("DRUID", 60)
expect("PALADIN", 60, "incompatible")
setItem(4, 9, "INVTYPE_RELIC")
expect("SHAMAN", 60)
expect("PRIEST", 60, "incompatible")

setItem(2, 0, "INVTYPE_WEAPON")
expect("ROGUE", 30)
expect("MAGE", 60, "incompatible")
expect("PALADIN", 30)
setItem(2, 0, "INVTYPE_WEAPONOFFHAND")
expect("PALADIN", 30, "incompatible")
expect("MAGE", 60, "incompatible")
expect("WARRIOR", 5)
expect("HUNTER", 5)
expect("ROGUE", 5)
expect("SHAMAN", 5)
setItem(2, 1, "INVTYPE_2HWEAPON")
expect("ROGUE", 60, "incompatible")
expect("SHAMAN", 60)
setItem(2, 4, "INVTYPE_WEAPON")
expect("HUNTER", 60, "incompatible")
expect("DRUID", 15)
setItem(2, 5, "INVTYPE_2HWEAPON")
expect("DRUID", 15)
expect("SHAMAN", 15)
setItem(2, 6, "INVTYPE_2HWEAPON")
expect("DRUID", 15)
expect("PRIEST", 60, "incompatible")
setItem(2, 13, "INVTYPE_WEAPON")
expect("DRUID", 15)
setItem(2, 18, "INVTYPE_RANGEDRIGHT")
expect("PALADIN", 60, "incompatible")
expect("ROGUE", 60)
expect("HUNTER", 60)
setItem(2, 19, "INVTYPE_RANGEDRIGHT")
expect("HUNTER", 60, "incompatible")
expect("WARLOCK", 10)
setItem(2, 20, "INVTYPE_2HWEAPON")
expect("MAGE", 60)
setItem(2, 14, "INVTYPE_WEAPON")
expect("MAGE", 60)
setItem(2, 14, "INVTYPE_WEAPONOFFHAND")
expect("MAGE", 60)
setItem(2, 8, "INVTYPE_NON_EQUIP")
expect("MAGE", 60)
setItem(9, 1, "")
expect("WARRIOR", 60)

setItem(4, 1, "INVTYPE_CHEST")
local readsBefore = reads
for _, choice in ipairs({"greed", "pass", "disenchant", "transmog", privateValue}) do
    assert(classify(link, "PALADIN", choice) == nil)
end
assert(classify(link, nil, "need") == nil)
assert(classify(link, privateValue, "need") == nil)
assert(classify(link, "UNKNOWN", "need") == nil)
assert(classify(privateValue, "PALADIN", "need") == nil)
assert(classify("item:12345", "PALADIN", "need") == nil)
assert(classify("|Hitem:0::::::::|h[Invalid item]|h", "PALADIN", "need") == nil)
assert(reads == readsBefore, "Filtered rows must avoid the item API")

C_Item.GetItemInfoInstant = function() return end
local kind, pending = classify(link, "PALADIN", "need")
assert(kind == nil and pending == true)
C_Item.GetItemInfoInstant = function() return 12345, nil, nil, "INVTYPE_CHEST", 123, 4 end
kind, pending = classify(link, "PALADIN", "need")
assert(kind == nil and pending == true)
C_Item.GetItemInfoInstant = function() return 12345, nil, nil, "INVTYPE_CHEST", 123, 4, privateValue end
expect("PALADIN", 60)
C_Item.GetItemInfoInstant = function() return 23456, nil, nil, "INVTYPE_CHEST", 123, 4, 1 end
expect("PALADIN", 60)
C_Item.GetItemInfoInstant = function() return 23456 end
expect("PALADIN", 60)
C_Item.GetItemInfoInstant = function() error("Unusable API") end
expect("PALADIN", 60)
C_Item = nil
expect("PALADIN", 60)

local localizedReads = 0
C_Item = {
    GetItemInfoInstant = instant,
    GetItemSubClassInfo = function()
        localizedReads = localizedReads + 1
        return "Ткань"
    end,
}
GetLocale = function() return "ruRU" end
assert(loadfile(source))("LootRollsPlus", namespace)
classify = namespace.Gear.Classify
expect("PALADIN", 40, "atypical")
assert(localizedReads == 0, "colored dots do not need a localized explanation")

local classes = {"WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID"}
local ranged = " WARRIOR HUNTER ROGUE "
local proficiencies = {
    [0] = " WARRIOR PALADIN HUNTER ROGUE SHAMAN ",
    [1] = " WARRIOR PALADIN HUNTER SHAMAN ",
    [2] = ranged, [3] = ranged,
    [4] = " WARRIOR PALADIN ROGUE PRIEST SHAMAN DRUID ",
    [5] = " WARRIOR PALADIN SHAMAN DRUID ",
    [6] = " WARRIOR PALADIN HUNTER DRUID ",
    [7] = " WARRIOR PALADIN HUNTER ROGUE MAGE WARLOCK ",
    [8] = " WARRIOR PALADIN HUNTER ",
    [10] = " WARRIOR HUNTER PRIEST SHAMAN MAGE WARLOCK DRUID ",
    [13] = " WARRIOR HUNTER ROGUE SHAMAN DRUID ",
    [15] = " WARRIOR HUNTER ROGUE PRIEST SHAMAN MAGE WARLOCK DRUID ",
    [16] = ranged, [18] = ranged, [19] = " PRIEST MAGE WARLOCK ",
}
for subclass, allowed in pairs(proficiencies) do
    setItem(2, subclass, "INVTYPE_WEAPON")
    for _, class in ipairs(classes) do
        local expected
        if not allowed:find(" " .. class .. " ", 1, true) then expected = "incompatible" end
        expect(class, 60, expected)
    end
end

print("Gear tests passed")
