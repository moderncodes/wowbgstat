local _, T = ...

local mod = {}
T.scoreboard = mod

local class_loc_to_token = {
    Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE",
    Priest  = "PRIEST",  Shaman  = "SHAMAN",  Mage   = "MAGE",   Warlock = "WARLOCK",
    Druid   = "DRUID",
}

-- TBC Anniversary GetBattlefieldScore signature (Vanilla/TBC layout):
--   1 name, 2 killingBlows, 3 honorKills, 4 deaths, 5 honorGained,
--   6 faction, 7 rank, 8 race, 9 class (localized), 10 filename (classToken),
--   11 damageDone, 12 healingDone
-- Source: https://vanilla-wow-archive.fandom.com/wiki/API_GetBattlefieldScore
-- Confirmed empirically via /mmscore: returns 13 values where [7]=rank,
-- [8]=race, [9]=Warlock, [10]=WARLOCK, [11]=damage, [12]=healing
function mod.refresh()
    RequestBattlefieldScoreData()
    local n = GetNumBattlefieldScores()
    for i = 1, n do
        local name, kills, hks, deaths, honor, faction,
              _rank, _race, _class_loc, class_token,
              damage, healing = GetBattlefieldScore(i)
        if name then
            local short = name:match("^([^%-]+)") or name

            -- Merge into existing record so scanner-set fields (spec_class,
            -- spec_tab) survive scoreboard refreshes.
            local existing = T.combat_log.get_player(short) or {}
            existing.class           = class_token
            existing.faction         = faction
            existing.kills           = kills           or 0
            existing.deaths          = deaths          or 0
            existing.honor           = honor           or 0
            existing.honorable_kills = hks             or 0
            existing.damage          = damage          or 0
            existing.healing         = healing         or 0
            T.combat_log.set_player(short, existing)
        end
    end
end

function mod.is_match_over()
    return GetBattlefieldWinner() ~= nil
end