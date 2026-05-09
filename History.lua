local _, T = ...

local mod = {}
T.history = mod

function mod.init()
    if not BgStatDB then BgStatDB = {} end
    if not BgStatDB.matches then BgStatDB.matches = {} end
end

function mod.save_current(zone, honor_delta)
    local snapshot = {
        zone         = zone,
        timestamp    = time(),
        winner       = GetBattlefieldWinner(),
        honor_delta  = honor_delta or 0,
        players      = {},
        kills        = {},
    }

    for name, p in pairs(T.combat_log.get_all_players()) do
        snapshot.players[name] = {
            class           = p.class,
            faction         = p.faction,
            damage          = p.damage,
            healing         = p.healing,
            kills           = p.kills,
            deaths          = p.deaths,
            honor           = p.honor,
            honorable_kills = p.honorable_kills,
            spec_class      = p.spec_class,
            spec_tab        = p.spec_tab,
        }
    end

    for _, k in ipairs(T.combat_log.get_kill_log()) do
        table.insert(snapshot.kills, {
            victim       = k.victim,
            victim_class = k.victim_class,
            spell_id     = k.spell_id,
            spell_name   = k.spell_name,
        })
    end

    table.insert(BgStatDB.matches, snapshot)
    while #BgStatDB.matches > T.max_history do
        table.remove(BgStatDB.matches, 1)
    end
end

function mod.get_all()    return BgStatDB.matches end
function mod.delete_all() BgStatDB.matches = {} end

function mod.get_last() return BgStatDB.matches[#BgStatDB.matches] end

function mod.summary_by_zone()
    local me = UnitName("player")
    local out = {}
    local totals = { games = 0, wins = 0, losses = 0, incomplete = 0,
                     kills = 0, deaths = 0, honor = 0 }

    for _, m in ipairs(BgStatDB.matches) do
        local z = m.zone or "Unknown"
        if not out[z] then
            out[z] = { games = 0, wins = 0, losses = 0, incomplete = 0,
                       kills = 0, deaths = 0, honor = 0 }
        end
        local row = out[z]
        row.games    = row.games    + 1
        totals.games = totals.games + 1

        local honor_for_match = m.honor_delta or 0
        if honor_for_match == 0 and m.players[me] then
            honor_for_match = m.players[me].honor or 0
        end
        row.honor    = row.honor    + honor_for_match
        totals.honor = totals.honor + honor_for_match

        local mine = m.players[me]
        if mine then
            row.kills     = row.kills     + (mine.kills  or 0)
            row.deaths    = row.deaths    + (mine.deaths or 0)
            totals.kills  = totals.kills  + (mine.kills  or 0)
            totals.deaths = totals.deaths + (mine.deaths or 0)

            if m.winner == nil then
                row.incomplete    = row.incomplete    + 1
                totals.incomplete = totals.incomplete + 1
            elseif mine.faction == m.winner then
                row.wins    = row.wins    + 1
                totals.wins = totals.wins + 1
            else
                row.losses    = row.losses    + 1
                totals.losses = totals.losses + 1
            end
        end
    end

    return out, totals
end

function mod.lifetime_class_stats()
    local out = {}
    for _, m in ipairs(BgStatDB.matches) do
        for name, p in pairs(m.players) do
            local c = p.class or "UNKNOWN"
            if not out[c] then
                out[c] = {
                    appearances = 0,
                    damage = 0, healing = 0, kills = 0, deaths = 0,
                    best_damage  = { value = 0, name = nil },
                    best_healing = { value = 0, name = nil },
                    best_kills   = { value = 0, name = nil },
                }
            end
            local row = out[c]
            row.appearances = row.appearances + 1
            row.damage  = row.damage  + (p.damage  or 0)
            row.healing = row.healing + (p.healing or 0)
            row.kills   = row.kills   + (p.kills   or 0)
            row.deaths  = row.deaths  + (p.deaths  or 0)

            if (p.damage or 0) > row.best_damage.value then
                row.best_damage = { value = p.damage,  name = name }
            end
            if (p.healing or 0) > row.best_healing.value then
                row.best_healing = { value = p.healing, name = name }
            end
            if (p.kills or 0) > row.best_kills.value then
                row.best_kills = { value = p.kills, name = name }
            end
        end
    end
    return out
end

function mod.lifetime_spec_stats()
    -- Returns aggregate stats per (class, spec) across all matches that
    -- have spec data on at least one player. Matches with no spec data
    -- on any player are excluded entirely.
    local out = {}
    local matches_with_specs = 0

    for _, m in ipairs(BgStatDB.matches) do
        local has_any_spec = false
        for _, p in pairs(m.players) do
            if p.spec_tab then has_any_spec = true; break end
        end
        if has_any_spec then
            matches_with_specs = matches_with_specs + 1
            for name, p in pairs(m.players) do
                if p.spec_tab and p.class then
                    local key = p.class .. "/" .. p.spec_tab
                    if not out[key] then
                        out[key] = {
                            class       = p.class,
                            spec_tab    = p.spec_tab,
                            appearances = 0,
                            damage = 0, healing = 0, kills = 0, deaths = 0,
                            best_damage  = { value = 0, name = nil },
                            best_healing = { value = 0, name = nil },
                        }
                    end
                    -- Defensive: old saved matches sometimes have non-number
                    -- damage/healing due to a fixed scoreboard alignment bug.
                    local row = out[key]
                    row.appearances = row.appearances + 1
                    row.damage  = row.damage  + (p.damage  or 0)
                    row.healing = row.healing + (p.healing or 0)
                    row.kills   = row.kills   + (p.kills   or 0)
                    row.deaths  = row.deaths  + (p.deaths  or 0)
                    if (p.damage or 0) > row.best_damage.value then
                        row.best_damage = { value = p.damage,  name = name }
                    end
                    if (p.healing or 0) > row.best_healing.value then
                        row.best_healing = { value = p.healing, name = name }
                    end
                end
            end
        end
    end
    return out, matches_with_specs
end
