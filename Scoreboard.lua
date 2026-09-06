local _, T = ...

local mod = {}
T.scoreboard = mod

local class_loc_to_token = {
    Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER", Rogue = "ROGUE",
    Priest  = "PRIEST",  Shaman  = "SHAMAN",  Mage   = "MAGE",   Warlock = "WARLOCK",
    Druid   = "DRUID",
}

-- ============================================================================
-- Rank passes.
--
-- Rank 1 = highest value of the metric. For deaths that means rank 1 died the
-- most -- the metric name says what it measures, the ordinal says nothing about
-- whether high is good.
--
-- Ties break on name. Without it, the ~30 players sitting at 0 healing in an AV
-- get reshuffled by every table.sort and their rank digit flickers on every
-- scoreboard update.
--
-- Ranks are computed live and deliberately NOT persisted. History.save_current
-- already snapshots kills/damage/deaths/healing; storing the derived ordinal
-- alongside would record the same fact twice and let the copies drift.
-- ============================================================================
local RANK_METRICS = {
    { key = "kills",   rank = "rank_kills"   },
    { key = "damage",  rank = "rank_damage"  },
    { key = "deaths",  rank = "rank_deaths"  },
    { key = "healing", rank = "rank_healing" },
}

local function assign_ranks(players)
    local groups = {}
    if T.rank_scope == "faction" then
        for _, p in pairs(players) do
            local f = p.faction or -1
            groups[f] = groups[f] or {}
            table.insert(groups[f], p)
        end
    else
        local all = {}
        for _, p in pairs(players) do table.insert(all, p) end
        groups.all = all
    end

    for _, group in pairs(groups) do
        for _, m in ipairs(RANK_METRICS) do
            table.sort(group, function(a, b)
                local av, bv = a[m.key] or 0, b[m.key] or 0
                if av == bv then return (a.name or "") < (b.name or "") end
                return av > bv
            end)
            for i, p in ipairs(group) do p[m.rank] = i end
        end
    end
end

-- TBC Anniversary GetBattlefieldScore signature (Vanilla/TBC layout):
--   1 name, 2 killingBlows, 3 honorKills, 4 deaths, 5 honorGained,
--   6 faction, 7 rank, 8 race, 9 class (localized), 10 filename (classToken),
--   11 damageDone, 12 healingDone
-- Source: https://vanilla-wow-archive.fandom.com/wiki/API_GetBattlefieldScore
-- Verified empirically: returns 13 values where [7]=rank,
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
            existing.name            = short
            existing.class           = class_token
            existing.faction         = faction
            existing.kills           = kills           or 0
            existing.deaths          = deaths          or 0
            existing.honor           = honor           or 0
            existing.honorable_kills = hks             or 0
            existing.damage          = damage          or 0
            existing.healing         = healing         or 0
            T.combat_log.set_player(short, existing)
            T.spec_scanner.merge_pending_into_player(short)
        end
    end

    assign_ranks(T.combat_log.get_all_players())
end

function mod.is_match_over()
    return GetBattlefieldWinner() ~= nil
end