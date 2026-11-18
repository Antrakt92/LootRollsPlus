local _, ns = ...

local priority = { need = 1, offspec = 2, disenchant = 3, greed = 4, transmog = 5, pass = 6, waiting = 7 }
local isSecret = issecretvalue or function() return false end

local function read(method, ...)
    if type(method) ~= "function" then return end
    local ok, value = pcall(method, ...)
    if ok and not isSecret(value) then return value end
end

local function groupUnitsByGUID()
    local units = {}
    local function add(unit)
        local guid = read(UnitGUID, unit)
        if type(guid) == "string" and guid ~= "" and not units[guid] then units[guid] = unit end
    end
    add("player")
    local raid, count = read(IsInRaid), read(GetNumGroupMembers)
    if type(raid) == "boolean" and type(count) == "number" and count >= 1 and count <= 40 and count % 1 == 0 then
        local prefix = raid and "raid" or "party"
        for i = 1, raid and count or count - 1 do add(prefix .. i) end
    end
    return units
end

local function copyPlayer(raw)
    return { name = raw.name, class = raw.class, choice = raw.state, roll = raw.roll, isSelf = raw.isSelf,
        guid = raw.guid, demoEquipped = raw.demoEquipped }
end

function ns.BuildLiveRolls(rolls, warning, hasSlot)
    local entries = {}
    local units, levels
    local function applyWarning(link, player, demo)
        local guid = player.guid
        if not demo and player.class and (player.choice == "need" or player.choice == "offspec")
            and not isSecret(guid) and type(guid) == "string" and guid ~= "" then
            if not units then units, levels = groupUnitsByGUID(), {} end
            if levels[guid] == nil then
                local unit = units[guid]
                local level = unit and read(UnitLevel, unit)
                if type(level) == "number" and level > 0 and level < math.huge and level % 1 == 0
                    and read(UnitGUID, unit) == guid then
                    levels[guid] = level
                else
                    levels[guid] = false
                end
            end
            player.level = levels[guid] or nil
        end
        player.warning = warning(link, player)
    end
    for i, raw in ipairs(rolls) do
        local players, counts, leaders = {}, {}, {}
        for j, player in ipairs(raw.rolls) do
            local row = copyPlayer(player)
            if warning then applyWarning(raw.link, row, raw.demo) end
            row.order = j
            players[j] = row
            counts[row.choice] = (counts[row.choice] or 0) + 1
        end
        table.sort(players, function(a, b)
            if a.choice ~= b.choice then return priority[a.choice] < priority[b.choice] end
            local rollA, rollB = a.roll or 0, b.roll or 0
            if rollA ~= rollB then return rollA > rollB end
            return a.order < b.order
        end)
        local needs = counts.need or 0
        for j = 1, needs do
            if players[j].roll then leaders[#leaders + 1] = players[j] end
            if #leaders == 2 then break end
        end
        local winner = raw.winner and copyPlayer(raw.winner)
        if winner and warning then applyWarning(raw.link, winner, raw.demo) end
        local canInspect = false
        if not raw.ambiguous and raw.link then
            if raw.demo then
                canInspect = raw.demoHasSlot == true
            elseif hasSlot then
                canInspect = hasSlot(raw.link) == true
            end
        end
        entries[i] = {
            id = raw.id, anchor = raw.anchor, link = raw.link, name = raw.name, icon = raw.icon,
            players = players, counts = counts, leaders = leaders, more = needs - #leaders,
            winner = winner, allPassed = raw.allPassed, ambiguous = raw.ambiguous,
            hasHistory = raw.hasHistory, demo = raw.demo, canInspect = canInspect,
        }
    end
    return entries
end

local demoNames = {
    "Tirion", "Bear", "Geba", "Treesus", "Arlen", "Briar", "Celan", "Dara", "Edda", "Fen",
    "Galen", "Hale", "Iris", "Jora", "Kelan", "Luma", "Mira", "Neri", "Orin", "Pella",
    "Quill", "Rhea", "Soren", "Tala", "Ulric", "Vela", "Wren", "Xara", "Yara", "Zara",
    "Aster", "Bran", "Cora", "Dain", "Elin", "Fara", "Gwen", "Harlan", "Iola",
}
local demoClasses = { "PALADIN", "DRUID", "ROGUE", "SHAMAN", "MAGE", "WARRIOR", "HUNTER", "PRIEST", "WARLOCK" }
local demoBow = "|cff0070dd|Hitem:3021::::::::|h[Ranger Bow]|h|r"
local demoWand = "|cff1eff00|Hitem:5212::::::::|h[Blazing Wand]|h|r"
local demoGear = {
    HUNTER = demoBow, ROGUE = demoBow, WARRIOR = demoBow,
    MAGE = demoWand, PRIEST = demoWand, WARLOCK = demoWand,
    PALADIN = "|cff0070dd|Hitem:22400::::::::|h[Libram of Truth]|h|r",
    DRUID = "|cff0070dd|Hitem:22397::::::::|h[Idol of Ferocity]|h|r",
    SHAMAN = "|cff0070dd|Hitem:22395::::::::|h[Totem of Rage]|h|r",
}

local function demoItem(name, icon, id, color, equipped)
    return {
        name = name,
        icon = "Interface\\Icons\\" .. icon,
        link = ("|c%s|Hitem:%d::::::::|h[%s]|h|r"):format(color, id, name),
        equipped = equipped,
    }
end

local jade = demoItem("Jade", "INV_Misc_Gem_Stone_01", 1529, "ff1eff00")
local crossbow = demoItem("Spellsever Crossbow", "INV_Weapon_Crossbow_01", 274293, "ff0070dd", demoGear)
local demoItems = { jade, crossbow, crossbow }

function ns.LiveRollDemo(raid, step)
    local rolls = {}
    local size = raid and 40 or 5
    local selfName = GetLocale() == "ruRU" and "Вы" or "You"
    local needLimit, greedLimit, passLimit = 2, 3, 4
    if raid then needLimit, greedLimit, passLimit = 9, 26, 34 end
    for i, item in ipairs(demoItems) do
        local players = {}
        for j = 1, size do
            local rank = (j - 1 + (i - 1) * 3) % size + 1
            local state, roll = "waiting"
            if rank <= step + 2 then
                if rank <= needLimit then
                    state = "need"
                    if rank <= step then roll = 100 - 4 * rank end
                elseif rank <= greedLimit then
                    state = "greed"
                    if rank < step then roll = (19 * rank) % 100 + 1 end
                elseif rank <= passLimit then
                    state = "pass"
                end
            end
            local class = demoClasses[(j - 1) % #demoClasses + 1]
            players[j] = { name = j == size and selfName or demoNames[j], class = class, state = state,
                roll = roll, isSelf = j == size, demoEquipped = item.equipped and item.equipped[class] }
        end
        rolls[i] = { id = i, name = item.name, icon = item.icon, link = item.link,
            rolls = players, hasHistory = true, demo = true, demoHasSlot = item.equipped ~= nil }
    end
    return rolls
end
