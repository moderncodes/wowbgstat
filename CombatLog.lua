local _, T = ...

local mod = {}
T.combat_log = mod

local players  = {}   -- name -> stats (populated from scoreboard)
local kill_log = {}   -- list of YOUR KBs this match
local last_dmg = {}   -- victim -> {spell_id, spell_name} from your last hit

local FILTER_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local FILTER_MINE   = COMBATLOG_OBJECT_AFFILIATION_MINE

local function is_player(flags) return bit.band(flags or 0, FILTER_PLAYER) ~= 0 end
local function is_mine(flags)   return bit.band(flags or 0, FILTER_MINE)   ~= 0 end

local function strip_realm(name)
    if not name then return nil end
    return (name:match("^([^%-]+)")) or name
end

function mod.handle_event()
    -- arg1..arg4 = payload positions 12-15. SWING_DAMAGE: arg1 = amount.
    -- Spell events: arg1 = spellId, arg2 = spellName, arg4 = amount.
    -- Source: https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT
    local _, event, _, _, source_name, source_flags, _,
                    _, dest_name, dest_flags, _,
                    arg1, arg2, arg3, arg4 = CombatLogGetCurrentEventInfo()

    if event == "SWING_DAMAGE" and is_mine(source_flags) and is_player(dest_flags) then
        local dst = strip_realm(dest_name)
        if dst then last_dmg[dst] = { spell_id = 0, spell_name = "Melee", amount = arg1 } end

    elseif (event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE" or event == "RANGE_DAMAGE")
           and is_mine(source_flags) and is_player(dest_flags) then
        local dst = strip_realm(dest_name)
        if dst then last_dmg[dst] = { spell_id = arg1, spell_name = arg2, amount = arg4 } end

    elseif event == "PARTY_KILL" and is_mine(source_flags) and is_player(dest_flags) then
        local dst = strip_realm(dest_name)
        if dst then
            local hit = last_dmg[dst]
            local victim_class = players[dst] and players[dst].class
            table.insert(kill_log, {
                victim       = dst,
                victim_full  = dest_name,   -- keeps -Realm suffix if present
                victim_class = victim_class,
                spell_id     = hit and hit.spell_id   or nil,
                spell_name   = hit and hit.spell_name or "Unknown",
                damage       = hit and hit.amount     or nil,
                timestamp    = GetTime(),
                at           = time(),      -- wall clock for history display
            })
            last_dmg[dst] = nil
            if T.on_killing_blow then T.on_killing_blow(dst, victim_class) end
        end
    end
end

function mod.set_player(name, data)
    players[name] = data
end

function mod.get_player(name)     return players[name] end
function mod.get_all_players()    return players end
function mod.get_kill_log()       return kill_log end

function mod.reset()
    wipe(players)
    wipe(kill_log)
    wipe(last_dmg)
end
