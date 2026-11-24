local source = arg[1] or "History.lua"
local addon = {}
local secret = {}
issecretvalue = function(value) return value == secret end
assert(loadfile(source))("LootRollsPlus", addon)
local History = addon.History
local day = "2026-11-14"
local link = "|cnIQ2:|Hitem:828::::::::|h[Small Blue Pouch]|h|r"
local function dateKey(timestamp)
    assert(timestamp < 1000)
    return day
end

do
    local oldDay = "2026-11-13"
    local visit = {id = 1, name = "Алый Монастырь"}
    local localized = {
        link = "|cffa335ee|Hitem:998::::::::|h[Épée % (赤龍)]|h|r",
        winner = "Ёж-Тест",
        visit = visit,
        sourceName = "Mograine",
    }
    local newest = {link = link, winner = "Newest"}
    local oldest = {link = link, winner = secret}
    local days = {[oldDay] = {oldest, localized}, [day] = {newest}}
    local keys = {oldDay, day}
    local memo = setmetatable({}, {__mode = "k"})
    local function search(query, first, limit, include)
        return History.SearchPage(days, keys, assert(History.SearchTerms(query)), first or 1, limit or 60, include, memo)
    end
    assert(not History.SearchTerms("  \t\n") and not History.SearchTerms(secret))
    local results, more = search("éPÉE % 赤龍 ёЖ монастырь MOGRAINE")
    assert(not more and #results == 1 and results[1].entry == localized and results[1].day == oldDay)
    assert(search(" [Épée % (赤龍)] ")[1].entry == localized, "the displayed item label can be pasted with its brackets")
    assert(search(" " .. localized.link .. " ")[1].entry == localized, "a copied hyperlink should use its item title")
    assert(#search("[Épée") == 0, "do not strip unmatched punctuation from ordinary queries")
    assert(#search("a335ee") == 0 and #search("item:998") == 0 and #search("secret") == 0)
    assert(#search("small pouch", 1, 60, function(entry) return entry == oldest end) == 1)
    results, more = search("POUCH", 1, 1)
    assert(more and #results == 1 and results[1].entry == newest and results[1].day == day)
    results, more = search("pouch", 2, 1)
    assert(not more and #results == 1 and results[1].entry == oldest and results[1].day == oldDay)
    localized.winner = "Updated"
    assert(#search("ёж") == 0 and search("updated")[1].entry == localized)
    localized.sourceName = "Renault"
    localized.visit.name = "Стратхольм"
    assert(#search("mograine") == 0 and #search("монастырь") == 0)
    assert(search("renault СТРАТ")[1].entry == localized)
    localized.link = link
    assert(#search("épée") == 0 and search("pouch updated")[1].entry == localized)
end

local live = {link = link, t = 20, rolls = {}, done = false}
local charDB = {days = {[day] = {live}}}
assert(not History.Import(charDB, dateKey))
assert(not charDB.importedInspector)

local first = {
    link = link,
    t = 10,
    done = true,
    winner = "Маг-Реалм",
    rolls = {
        {name = "|cff69ccf0|Hplayer:Маг-Реалм:123|h[Маг-Реалм]|h|r", type = "greed", value = "99"},
        {name = "Другой", type = "pass"},
        {name = "Invalid", type = "bad"},
        {name = secret, type = "need", value = 100},
    },
}
local second = {link = link, t = 10, winner = "NobodyKnown", done = true, rolls = {}}
local unclosed = {link = link, t = 21, rolls = {{name = "ClothDude", type = "need"}}}
local upstream = {
    days = {
        [day] = {
            first,
            second,
            unclosed,
            {link = "pasted fake item", t = 22},
            {link = link, t = 0/0},
            {link = link, t = 1001},
        },
        garbage = {{link = link, t = 14}},
    },
}
assert(History.Import(charDB, upstream, dateKey))
local entries = charDB.days[day]
assert(#entries == 4)
assert(entries[1].legacy and entries[1].done and entries[1].winner == "Маг-Реалм")
assert(entries[1].winnerType == "greed" and entries[1].winnerValue == 99)
assert(#entries[1].rolls == 2)
assert(entries[1].rolls[1].name == "Маг-Реалм")
assert(entries[2].winnerType == nil and entries[2].winnerValue == nil)
assert(entries[3] == live)
assert(entries[4].legacy and not entries[4].done and entries[4].rolls[1].type == "need")
entries[1].rolls[1].value = 42
assert(first.rolls[1].value == "99")
assert(not History.Import(charDB, upstream, dateKey))
assert(#charDB.days[day] == 4)

local emptyDB = {days = {}}
assert(not History.Import(emptyDB, {days = {}}, dateKey))
assert(not emptyDB.importedInspector)
assert(not History.Import(emptyDB, {days = {[day] = {{link = "invalid", t = 12}}}}, dateKey))
assert(History.Import(emptyDB, upstream, dateKey))
assert(#emptyDB.days[day] == 3)
local ambigDB = {days = {}}
assert(History.Import(ambigDB, {days = {[day] = {{
    link = link, t = 22, winner = "Same", rolls = {
        {name = "Same", type = "need", value = 100},
        {name = "|cff69ccf0Same|r", type = "pass"},
    },
}}}}, dateKey))
assert(ambigDB.days[day][1].winnerType == nil)
assert(not History.IsPlayerWin(ambigDB.days[day][1], "Same Surname", "Same"),
    "duplicate imported bare names cannot identify the current character")
local linkedDB = {days = {}}
local winnerLink = "|Hplayer:Same-RealmA:123|h[Same]|h"
local otherLink = "|Hplayer:Same-RealmB:124|h[Same]|h"
assert(History.Import(linkedDB, {days = {[day] = {{
    link = link, t = 23, winner = winnerLink,
    rolls = {
        {name = winnerLink, type = "need", value = "97"},
        {name = otherLink, type = "greed", value = "99"},
    },
}}}}, dateKey))
local linkedWin = linkedDB.days[day][1]
assert(linkedWin.winner == "Same-RealmA" and linkedWin.rolls[2].name == "Same-RealmB",
    "import must preserve different player identities even if chat displays the same label")
assert(linkedWin.winnerType == "need" and linkedWin.winnerValue == 97)
assert(History.IsPlayerWin(linkedWin, "Same-RealmA", "Same"))
assert(not History.IsPlayerWin(linkedWin, "Same-RealmB", "Same"))
assert(History.IsPlayerWin(entries[1], "Маг-Реалм", "Маг"),
    "an unambiguous imported full name should match")
assert(History.IsPlayerWin({done = true, legacy = true, winner = "Self"}, "Self Surname", "Self"),
    "a unique bare name remains usable in older imports")
assert(not History.IsPlayerWin({done = true, ambiguous = true, winner = "Self"}, "Self Surname", "Self"))
assert(not History.IsPlayerWin({done = true, allpassed = true, winner = "Self Surname"}, "Self Surname", "Self"))
assert(not History.IsPlayerWin({done = true, winner = "Self Surname", rolls = {
    {name = "Self Surname"}, {name = "Self Surname"},
}}, "Self Surname", "Self"))
assert(History.IsPlayerWin({done = true, winner = "Self Surname", rolls = {
    {name = "Self Surname"}, {name = "Self Other"},
}}, "Self Surname", "Self"), "a distinct full name resolves a first-name collision")
assert(not History.IsPlayerWin({done = true, winner = "Self", rolls = {
    {name = "Self Other"},
}}, "Self Surname", "Self"))
assert(not History.IsPlayerWin({done = true, winner = "Self", winnerClass = "MAGE"},
    "Self Surname", "Self", "PALADIN"), "a known different class rules out a bare-name match")
assert(not History.IsPlayerWin({done = true, winner = "Self", rolls = {{name = "Self", class = "MAGE"}}},
    "Self Surname", "Self", "PALADIN"))
assert(History.IsPlayerWin({done = true, winner = "Self", winnerClass = "PALADIN"},
    "Self Surname", "Self", "PALADIN"))

local sparseDB = {days = {}}
local sparseEntry = {
    link = link, t = 22, winner = "Winner",
    rolls = {[1] = {name = "Other", type = "pass"}, [3] = {name = "Winner", type = "need", value = "94"}},
}
local sparseUpstream = {days = {[day] = {[1] = first, [3] = sparseEntry, junk = second}}}
assert(History.Import(sparseDB, sparseUpstream, dateKey))
assert(#sparseDB.days[day] == 2 and #sparseDB.days[day][2].rolls == 2)
assert(sparseDB.days[day][2].winnerValue == 94 and sparseDB.days[day][2].winnerType == "need")
assert(sparseUpstream.days[day][2] == nil and sparseEntry.rolls[2] == nil)
assert(not History.Import(sparseDB, sparseUpstream, dateKey), "sparse import stays one-time")

local visits = History.NewVisits(charDB)
assert(visits:Get() == nil)
assert(visits:Update(nil, nil, 30, false) == nil)
local library = assert(visits:Update(189, "Library", 31))
assert(visits:Get() == library and library.id == 1 and library.startedAt == 31)
assert(visits:Update(189, "Library", 32) == library)
local reload = History.NewVisits(charDB)
assert(reload:Update(189, "Library", 33, true) == library)
assert(reload:Update(nil, nil, 34) == nil and reload:Get() == nil)
local returned = assert(reload:Update(189, "Library", 35))
assert(returned.id == 2 and returned.startedAt == 35)
local login = History.NewVisits(charDB)
local logged = assert(login:Update(189, "Library", 36, false))
assert(logged.id == 3 and logged.startedAt == 36)
local changed = assert(login:Update(189, "Armory", 37))
assert(changed.id == 4 and changed.name == "Armory")
assert(login:Update(secret, "Cathedral", 38) == nil)
assert(library.name == "Library" and library.startedAt == 31)

local oldState = {currentVisit = {id = 14, instanceID = 189, name = "Library", startedAt = 31}}
assert(History.NewVisits(oldState):Update(189, "Library", 32, true).id == 14)
assert(History.NewVisits(oldState):Update(nil, nil, 33, true) == nil)
assert(History.NewVisits(oldState):Update(189, "Library", 34, false).id == 15)

local archivedVisit = {id = 19, name = "Library", startedAt = 15}
local archivedDays = {[day] = {
    {link = link, t = 20, visit = archivedVisit},
    {link = link, t = 21, visit = {id = "200", name = "Armory", startedAt = 16}},
    {link = link, t = 22, visit = {id = math.huge, name = "Armory", startedAt = 17}},
    {link = link, t = 23, visit = {id = 999, name = "Armory", startedAt = 30}},
    {link = link, t = 24, visit = {id = 1e100, name = "Armory", startedAt = 17}},
}}
local maxArchivedVisit = History.NormalizeDays(archivedDays, dateKey)
assert(maxArchivedVisit == archivedVisit.id, "only valid historical visits can advance the visit counter")
for _, lastID in ipairs({false, 2, 30, 1e100}) do
    local restored = {days = archivedDays, lastVisitID = lastID}
    local resumed = History.NewVisits(restored, maxArchivedVisit):Update(189, "Library", 32, true)
    assert(resumed.id == (lastID == 30 and 31 or 20),
        "a restored history must not reuse an archived dungeon visit ID")
end
local staleVisit = {id = 7, instanceID = 189, name = "Library", startedAt = 10}
assert(History.NewVisits({currentVisit = staleVisit}, maxArchivedVisit):Update(189, "Library", 32, true).id == 20,
    "a restored current visit older than the archive cannot be resumed")
local currentVisit = {id = 20, instanceID = 189, name = "Library", startedAt = 30}
assert(History.NewVisits({currentVisit = currentVisit}, maxArchivedVisit):Update(189, "Library", 32, true) == currentVisit,
    "an intact saved current visit still resumes after reloading")
local exhausted = History.NewVisits({lastVisitID = 2 ^ 53 - 2}, maxArchivedVisit)
assert(exhausted:Update(189, "Library", 31, false).id == 2 ^ 53 - 1)
assert(not exhausted:Update(189, "Armory", 32, false), "allocating past Lua's exact range must not reuse an ID")

local winner = {link = link, winner = "Bear Dillinger", t = 120, legacy = true, rolls = {
    {name = "Bear Dillinger"}, {name = "Other Player"}, {name = "Self"},
    {name = "Same First"}, {name = "Same Second"}, {name = "Self Surname"}, {name = "Cross-Realm"},
}}
local other = {link = link, winner = "Bear Another", t = 120, legacy = true}
local outside = {link = link, winner = "Bear Dillinger", t = 140, legacy = true}
local loot = {link = link, who = winner.winner}
local run = {
    started = 100, last = 119, loot = {loot},
    party = {Bear = "DRUID", Other = "MAGE", Same = "MAGE", Cross = "DRUID"},
}
local savedDays = {[day] = {winner, other, outside}}
local function identity(value) return value:match("|H(item:[^|]+)|h") end
local colors = {DRUID = true, MAGE = true, PRIEST = true}
assert(History.RecoverClasses(savedDays, {runLog = {run, run}}, identity, colors) == 0)
assert(History.RecoverClasses(savedDays, {runLog = {run}}, identity, colors, "Self", "PRIEST", "Self Surname") == 1)
assert(winner.winnerClass == "DRUID" and not other.winnerClass and not outside.winnerClass)
assert(winner.verifiedWinnerClass == "DRUID" and not other.verifiedWinnerClass and not outside.verifiedWinnerClass)
assert(winner.rolls[1].class == "DRUID" and winner.rolls[2].class == "MAGE" and not winner.rolls[3].class)
assert(not winner.rolls[4].class and not winner.rolls[5].class)
assert(winner.rolls[6].class == "PRIEST")
assert(not winner.rolls[7].class)
assert(History.RecoverClasses(savedDays, {runLog = {run}}, identity, colors) == 0)
assert(History.RecoverClasses(savedDays, {runLog = {run, run}}, identity, colors) == 1)
assert(winner.winnerClass == "DRUID" and not winner.verifiedWinnerClass,
    "new positive ambiguity should revoke the warning without erasing the displayed class")

local duplicateA = {link = link, winner = "Bear Dillinger", t = 118, legacy = true}
local duplicateB = {link = link, winner = "Bear Dillinger", t = 119, legacy = true}
assert(History.RecoverClasses({[day] = {duplicateA, duplicateB}}, {runLog = {run}}, identity, colors) == 0)
assert(not duplicateA.winnerClass and not duplicateB.winnerClass)
assert(not duplicateA.verifiedWinnerClass and not duplicateB.verifiedWinnerClass)

local noWinnerRoll = {link = link, winner = "Bear Dillinger", t = 118, legacy = true, rolls = {{name = "Bear Another"}}}
assert(History.RecoverClasses({[day] = {noWinnerRoll}}, {runLog = {run}}, identity, colors) == 0)
assert(not noWinnerRoll.winnerClass and not noWinnerRoll.rolls[1].class)
assert(not noWinnerRoll.verifiedWinnerClass)

local shortWinner = {link = link, winner = "Bear", t = 118, legacy = true,
    rolls = {{name = "Bear"}, {name = "Bear Another"}}}
local shortRun = {started = 100, last = 119, loot = {{link = link, who = "Bear"}}, party = {Bear = "DRUID"}}
assert(History.RecoverClasses({[day] = {shortWinner}}, {runLog = {shortRun}}, identity, colors) == 0)
assert(not shortWinner.verifiedWinnerClass and not shortWinner.rolls[1].class,
    "a bare roster name must be unique even when the roster key matches literally")

local linkedAtlasWinner = {link = link, winner = "Same-RealmA", t = 118, legacy = true,
    rolls = {{name = "Same-RealmA"}, {name = "Same-RealmB"}}}
local linkedAtlasRun = {started = 100, last = 119, party = {["Same-RealmA"] = "DRUID", ["Same-RealmB"] = "MAGE"},
    loot = {{link = link, who = "|cff69ccf0" .. winnerLink .. "|r"}, {link = link, who = otherLink}}}
assert(History.RecoverClasses({[day] = {linkedAtlasWinner}}, {runLog = {linkedAtlasRun}}, identity, colors) == 1,
    "Atlas loot captured from chat can store a player hyperlink rather than a bare name")
assert(linkedAtlasWinner.verifiedWinnerClass == "DRUID" and linkedAtlasWinner.rolls[2].class == "MAGE",
    "identical link labels must not create a duplicate match or change either player identity")

local mismatched = {link = link, winner = "Bear Dillinger", t = 118, legacy = true, winnerClass = "MAGE"}
assert(History.RecoverClasses({[day] = {mismatched}}, {runLog = {run}}, identity, colors) == 0)
assert(not mismatched.verifiedWinnerClass)

local validVisit = {id = 8, name = "Library", startedAt = 8}
local validRoll = {name = "Self", class = "PALADIN", type = "transmog", value = 95}
local savedSnapshot = {at = 9, links = {[1] = link, [2] = false}, empty = {[1] = true, [2] = true}}
local damaged = {
    link = link, t = 11, done = "false", winner = 12, winnerValue = 200, sourceName = "|bad",
    rolls = {"corrupt", {name = "Invalid", type = "bad"}, [6] = validRoll},
    visit = {id = 0, name = "Library", startedAt = 9},
    inspections = {Self = savedSnapshot, Other = 12},
}
local intact = {link = link, t = 12, visit = validVisit, rolls = {{name = "Self", type = "undecided"}}}
local damagedRows = {false, damaged, {link = link, t = 1001}, ["bad"] = {}, [9] = intact}
local damagedDays = {[day] = damagedRows, ["wrong-key"] = {}, ["2026-02-30"] = {intact}, [17] = true}
History.NormalizeDays(damagedDays, dateKey)
assert(damagedDays[day] == damagedRows and #damagedRows == 2)
assert(damagedRows[1] == damaged and damagedRows[2] == intact and intact.visit == validVisit)
assert(not damagedDays["wrong-key"] and not damagedDays["2026-02-30"] and not damagedDays[17])
assert(not damaged.done and not damaged.winner and not damaged.winnerValue and not damaged.sourceName and not damaged.visit)
assert(#damaged.rolls == 1 and damaged.rolls[1] == validRoll and intact.rolls[1].type == "undecided")
assert(damaged.inspections.Self == savedSnapshot and not damaged.inspections.Other)
assert(savedSnapshot.links[1] == link and not savedSnapshot.links[2])
assert(not savedSnapshot.empty[1] and savedSnapshot.empty[2] and savedSnapshot.count == 2)
History.NormalizeDays(damagedDays, dateKey)
assert(damagedDays[day] == damagedRows and damagedRows[1] == damaged and damaged.rolls[1] == validRoll)

local earlier = "2026-11-13"
local movedFirst = {link = link, t = 51, rolls = {}}
local movedLater = {link = link, t = 53, rolls = {}}
local existing = {link = link, t = 52, rolls = {}}
local destination = {existing}
local timezoneDays = {[earlier] = {movedFirst, movedLater}, [day] = destination}
History.NormalizeDays(timezoneDays, dateKey)
assert(not timezoneDays[earlier] and timezoneDays[day] == destination)
assert(destination[1] == movedFirst and destination[2] == existing and destination[3] == movedLater)
local unsorted = {movedLater, existing, movedFirst}
History.NormalizeDays({[day] = unsorted}, dateKey)
assert(unsorted[1] == movedFirst and unsorted[2] == existing and unsorted[3] == movedLater)
assert(not History.IsPlayerWin({done = true, winner = "Self", rolls = {
    {name = "Self", class = "PALADIN"}, {name = "Self Surname", class = "PALADIN"},
}}, "Self Surname", "Self", "PALADIN"), "two matching records cannot identify a bare-name winner")
print("History tests passed")
