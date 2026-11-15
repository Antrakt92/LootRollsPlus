local _, addon = ...
local Gear = {}
addon.Gear = Gear

local isSecret = issecretvalue or function() return false end

-- Item subclasses and class masks from Forever 1.60.1.70938 client data.
-- Sources: ItemSubClass, SkillLine, SkillRaceClassInfo and SkillLineAbility.
local weaponClass, armorClass = 2, 4
local dualWieldClasses = 77 -- Includes Shamans who can learn Dual Wield as a talent.
local classBits = {
    WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
    SHAMAN = 64, MAGE = 128, WARLOCK = 256, DRUID = 1024,
}
local weapons = {
    [0] = 79, -- One-handed axe
    [1] = 71, -- Two-handed axe
    [2] = 13, -- Bow
    [3] = 13, -- Gun
    [4] = 1115, -- One-handed mace
    [5] = 1091, -- Two-handed mace
    [6] = 1031, -- Polearm
    [7] = 399, -- One-handed sword
    [8] = 7, -- Two-handed sword
    [10] = 1493, -- Staff
    [13] = 1101, -- Fist weapon
    [15] = 1501, -- Dagger
    [16] = 13, -- Thrown weapon
    [18] = 13, -- Crossbow
    [19] = 400, -- Wand
}
local specialArmor = {
    [6] = 67, -- Shield
    [7] = 2, -- Libram
    [8] = 1024, -- Idol
    [9] = 64, -- Totem
}
local nativeArmor = {
    WARRIOR = 4, PALADIN = 4, HUNTER = 3, SHAMAN = 3, DRUID = 2, ROGUE = 2,
    MAGE = 1, PRIEST = 1, WARLOCK = 1,
}
local armorAfterTraining = {WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true}
local materialSlots = {
    INVTYPE_HEAD = true, INVTYPE_SHOULDER = true, INVTYPE_CHEST = true, INVTYPE_ROBE = true,
    INVTYPE_WAIST = true, INVTYPE_LEGS = true, INVTYPE_FEET = true, INVTYPE_WRIST = true,
    INVTYPE_HAND = true,
}
local weaponSlots = {
    INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true,
    INVTYPE_WEAPONOFFHAND = true, INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true,
    INVTYPE_THROWN = true,
}

local function clean(value, expectedType)
    if isSecret(value) or type(value) ~= expectedType then return end
    if expectedType == "number" and (value ~= value or value == math.huge or value == -math.huge) then return end
    return value
end

local function hasClass(mask, classBit)
    return math.floor(mask / classBit) % 2 == 1
end

local function classifyArmor(classFile, classBit, equipLocation, subclass, level)
    if equipLocation == "INVTYPE_SHIELD" and subclass == 6
        or (equipLocation == "INVTYPE_RELIC" or equipLocation == "INVTYPE_RANGEDRIGHT")
            and subclass >= 7 and subclass <= 9
    then
        if not hasClass(specialArmor[subclass], classBit) then return "incompatible" end
        return
    end
    if not materialSlots[equipLocation] or subclass < 1 or subclass > 4 then return end

    local usual = nativeArmor[classFile]
    if subclass > usual then return "incompatible" end
    -- A learnable armor type is a possible future upgrade. When the player's
    -- level is unknown use the lower leveling tier for the advisory threshold.
    if armorAfterTraining[classFile] and (not level or level < 40) then
        usual = usual - 1
    end
    if subclass < usual then return "atypical" end
end

function Gear.Classify(link, classFile, rollType, playerLevel)
    if clean(rollType, "string") ~= "need" then return end
    classFile = clean(classFile, "string")
    local classBit = classBits[classFile]
    if not classBit then return end
    link = clean(link, "string")
    if not link then return end
    local linkedID = tonumber(link:match("|Hitem:(%d+)[:|]"))
    if not clean(linkedID, "number") or linkedID < 1 then return end
    if not C_Item or type(C_Item.GetItemInfoInstant) ~= "function" then return end

    local ok, id, _, _, equipLocation, _, itemClass, subclass = pcall(C_Item.GetItemInfoInstant, link)
    if not ok then return end
    -- Secret metadata is deliberately left unresolved. Only missing metadata
    -- asks the caller to reclassify after the normal item-data callback.
    if isSecret(id) or isSecret(equipLocation) or isSecret(itemClass) or isSecret(subclass) then return end
    if id ~= nil and (not clean(id, "number") or id ~= linkedID) then return end
    if id == nil or equipLocation == nil or itemClass == nil or subclass == nil then return nil, true end
    if not clean(itemClass, "number") or not clean(subclass, "number") or subclass % 1 ~= 0 then return end
    equipLocation = clean(equipLocation, "string")
    if not equipLocation then return end

    if itemClass == weaponClass and weaponSlots[equipLocation] then
        local proficiency = weapons[subclass]
        if not proficiency then return end
        if not hasClass(proficiency, classBit) then return "incompatible" end
        if equipLocation == "INVTYPE_WEAPONOFFHAND" and not hasClass(dualWieldClasses, classBit) then
            return "incompatible"
        end
    end
    if itemClass == armorClass then
        playerLevel = clean(playerLevel, "number")
        if playerLevel and (playerLevel < 1 or playerLevel ~= math.floor(playerLevel)) then playerLevel = nil end
        return classifyArmor(classFile, classBit, equipLocation, subclass, playerLevel)
    end
end
