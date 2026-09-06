local _, T = ...

local mod = {}
T.history = mod

function mod.init()
    if not BgStatDB then BgStatDB = {} end
    if not BgStatDB.matches then BgStatDB.matches = {} end
end

function mod.save_current(zone, honor_delta, honor_capped)
    local snapshot = {
        character    = UnitName("player"),
        zone         = zone,
        timestamp    = time(),
        winner       = GetBattlefieldWinner(),
        honor_delta  = honor_delta or 0,
        honor_capped = honor_capped or nil,
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
            victim_full  = k.victim_full,
            victim_class = k.victim_class
                           or (T.combat_log.get_player(k.victim) or {}).class,
            spell_id     = k.spell_id,
            spell_name   = k.spell_name,
            damage       = k.damage,
            at           = k.at,
        })
    end

    table.insert(BgStatDB.matches, snapshot)
    while #BgStatDB.matches > T.max_history do
        table.remove(BgStatDB.matches, 1)
    end
end

-- Only this character's matches. Old snapshots lack `character`; fall back
-- to presence in the roster (your own alts can't share a BG).
local function is_mine(m, me)
    return (m.character == me)
        or (m.character == nil and m.players[me] ~= nil)
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
      if is_mine(m, me) then
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
    end

    return out, totals
end

function mod.lifetime_class_stats()
    local me = UnitName("player")
    local out = {}
    for _, m in ipairs(BgStatDB.matches) do
        -- Match context: size + totals across ALL players (self included).
        -- Index = player's metric vs the average player of that same match.
        local match_size, match_dmg, match_heal = 0, 0, 0
        for _, p in pairs(m.players) do
            match_size = match_size + 1
            match_dmg  = match_dmg  + (p.damage  or 0)
            match_heal = match_heal + (p.healing or 0)
        end

        for name, p in pairs(m.players) do
            if name ~= me then
                local c = p.class or "UNKNOWN"
            if not out[c] then
                out[c] = {
                    appearances = 0,
                    damage = 0, healing = 0, kills = 0, deaths = 0,
                    best_damage  = { value = 0, name = nil },
                    best_healing = { value = 0, name = nil },
                    best_kills   = { value = 0, name = nil },
                    dmg_per_head   = 0, heal_per_head  = 0,
                    dmg_index_sum  = 0, dmg_index_n    = 0,
                    heal_index_sum = 0, heal_index_n   = 0,
                    best_index     = { value = 0, name = nil },
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
            row.dmg_per_head  = row.dmg_per_head  + (p.damage  or 0) / match_size
            row.heal_per_head = row.heal_per_head + (p.healing or 0) / match_size

            if match_dmg > 0 then
                local idx = (p.damage or 0) * match_size / match_dmg
                row.dmg_index_sum = row.dmg_index_sum + idx
                row.dmg_index_n   = row.dmg_index_n + 1
                if idx > row.best_index.value then
                    row.best_index = { value = idx, name = name }
                end
            end
            if match_heal > 0 then
                row.heal_index_sum = row.heal_index_sum + (p.healing or 0) * match_size / match_heal
                row.heal_index_n   = row.heal_index_n + 1
            end
        end
        end
    end
    return out
end

function mod.lifetime_spec_stats()
    -- Returns aggregate stats per (class, spec) across all matches that
    -- have spec data on at least one player. Matches with no spec data
    -- on any player are excluded entirely.
    --
    -- Self is split into a separate `you` table (same shape, keyed by
    -- class/spec) so the UI can render self rows highlighted without
    -- skewing the aggregated population averages.
    local me = UnitName("player")
    local out = {}
    local you = {}
    local matches_with_specs = 0

    for _, m in ipairs(BgStatDB.matches) do
        local has_any_spec = false
        local match_size, match_dmg, match_heal = 0, 0, 0
        for _, p in pairs(m.players) do
            match_size = match_size + 1
            match_dmg  = match_dmg  + (p.damage  or 0)
            match_heal = match_heal + (p.healing or 0)
            if p.spec_tab then has_any_spec = true end
        end
        if has_any_spec then
            matches_with_specs = matches_with_specs + 1
            for name, p in pairs(m.players) do
                if p.spec_tab and p.class then
                    local key = p.class .. "/" .. p.spec_tab
                    local target = (name == me) and you or out
                    if not target[key] then
                        target[key] = {
                            class       = p.class,
                            spec_tab    = p.spec_tab,
                            appearances = 0,
                            damage = 0, healing = 0, kills = 0, deaths = 0,
                            best_damage  = { value = 0, name = nil },
                            best_healing = { value = 0, name = nil },
                            dmg_per_head   = 0, heal_per_head  = 0,
                            dmg_index_sum  = 0, dmg_index_n    = 0,
                            heal_index_sum = 0, heal_index_n   = 0,
                        }
                    end
                    local row = target[key]
                    row.appearances = row.appearances + 1
                    row.damage  = row.damage  + (p.damage  or 0)
                    row.healing = row.healing + (p.healing or 0)
                    row.kills   = row.kills   + (p.kills   or 0)
                    row.deaths  = row.deaths  + (p.deaths  or 0)
                    if (p.damage or 0) > row.best_damage.value then
                        row.best_damage = { value = p.damage,  name = name }
                    end
                    row.dmg_per_head  = row.dmg_per_head  + (p.damage  or 0) / match_size
                    row.heal_per_head = row.heal_per_head + (p.healing or 0) / match_size
                    if match_dmg > 0 then
                        row.dmg_index_sum = row.dmg_index_sum + (p.damage or 0) * match_size / match_dmg
                        row.dmg_index_n   = row.dmg_index_n + 1
                    end
                    if match_heal > 0 then
                        row.heal_index_sum = row.heal_index_sum + (p.healing or 0) * match_size / match_heal
                        row.heal_index_n   = row.heal_index_n + 1
                    end
                end
            end
        end
    end
    return out, matches_with_specs, you
end

function mod.recent_kills(limit)
    -- Newest first, across matches. Kills within a match are chronological,
    -- so walk matches newest->oldest and each match's kills back-to-front.
    local me = UnitName("player")
    local out = {}
    for mi = #BgStatDB.matches, 1, -1 do
        local m = BgStatDB.matches[mi]
        if is_mine(m, me) then
        for ki = #(m.kills or {}), 1, -1 do
            local k = m.kills[ki]
            table.insert(out, {
                victim       = k.victim_full or k.victim,
                victim_class = k.victim_class,
                spell_name   = k.spell_name,
                damage       = k.damage,
                at           = k.at or m.timestamp,  -- old kills: match time
                zone         = m.zone,
            })
            if #out >= limit then return out end
        end
        end
    end
    return out
end

function mod.trend_series(limit)
    -- Last `limit` matches for the current character, oldest -> newest.
    -- Each point: your kills/deaths/damage/healing + your team's per-player
    -- average of the same, from the saved snapshot (fully retroactive).
    local me = UnitName("player")
    local out = {}
    for mi = #BgStatDB.matches, 1, -1 do
        local m = BgStatDB.matches[mi]
        local mine = m.players[me]
        if is_mine(m, me) and mine and mine.faction ~= nil then
            local n, tk, td, tdmg, theal = 0, 0, 0, 0, 0
            for _, p in pairs(m.players) do
                if p.faction == mine.faction then
                    n    = n + 1
                    tk   = tk   + (p.kills   or 0)
                    td   = td   + (p.deaths  or 0)
                    tdmg = tdmg + (p.damage  or 0)
                    theal= theal+ (p.healing or 0)
                end
            end
            if n > 0 then
                local win
                if m.winner ~= nil then win = (mine.faction == m.winner) end
                table.insert(out, 1, {
                    at          = m.timestamp,
                    zone        = m.zone,
                    win         = win,
                    kills       = mine.kills   or 0,
                    deaths      = mine.deaths  or 0,
                    damage      = mine.damage  or 0,
                    healing     = mine.healing or 0,
                    avg_kills   = tk    / n,
                    avg_deaths  = td    / n,
                    avg_damage  = tdmg  / n,
                    avg_healing = theal / n,
                })
                if #out >= limit then break end
            end
        end
    end
    return out
end