local _, T = ...

local mod = {}
T.combat_log = mod

local players  = {}   -- name -> stats (populated from scoreboard)
local kill_log = {}   -- list of YOUR KBs this match
local last_dmg     = {}   -- victim -> {spell_id, spell_name, amount} from your last hit
local pending_kill = {}   -- victim -> kill_log entry waiting for its fatal damage event

local FILTER_PLAYER = COMBATLOG_OBJECT_TYPE_PLAYER
local FILTER_MINE   = COMBATLOG_OBJECT_AFFILIATION_MINE

local function is_player(flags) return bit.band(flags or 0, FILTER_PLAYER) ~= 0 end
local function is_mine(flags)   return bit.band(flags or 0, FILTER_MINE)   ~= 0 end

local function record_hit(dst, spell_id, spell_name, amount)
    local k = pending_kill[dst]
    if k then
        k.spell_id, k.spell_name, k.damage = spell_id, spell_name, amount
        pending_kill[dst] = nil
    else
        last_dmg[dst] = { spell_id = spell_id, spell_name = spell_name, amount = amount }
    end
end

local function strip_realm(name)
    if not name then return nil end
    return (name:match("^([^%-]+)")) or name
end

function mod.handle_event()
    -- arg1..arg4 = payload positions 12-15. SWING_DAMAGE: arg1 = amount.
    -- Spell events: arg1 = spellId, arg2 = spellName, arg4 = amount.
    -- Source: https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT
    --
    -- Event order on Anniversary, verified from a CLEU capture (2026-09-05):
    --   PARTY_KILL -> fatal *_DAMAGE -> UNIT_DIED, same frame.
    -- The kill is opened at PARTY_KILL, its spell/damage filled by the next
    -- damage event to that victim, and closed at UNIT_DIED (falling back to
    -- the previous hit if no damage event arrived in between).
    local _, event, _, _, source_name, source_flags, _,
                    _, dest_name, dest_flags, _,
                    arg1, arg2, arg3, arg4 = CombatLogGetCurrentEventInfo()

    local dst = strip_realm(dest_name)
    if not dst then return end

    if event == "UNIT_DIED" then
        local k = pending_kill[dst]
        if k then
            local hit = last_dmg[dst]
            k.spell_id   = hit and hit.spell_id
            k.spell_name = hit and hit.spell_name or "Unknown"
            k.damage     = hit and hit.amount
            pending_kill[dst] = nil
        end
        last_dmg[dst] = nil
        return
    end

    if not (is_mine(source_flags) and is_player(dest_flags)) then return end

    if event == "SWING_DAMAGE" then
        record_hit(dst, 0, "Melee", arg1)

    elseif event == "SPELL_DAMAGE" or event == "SPELL_PERIODIC_DAMAGE"
        or event == "RANGE_DAMAGE" or event == "DAMAGE_SHIELD" then
        record_hit(dst, arg1, arg2, arg4)

    elseif event == "PARTY_KILL" then
        local victim_class = players[dst] and players[dst].class
        local k = {
            victim       = dst,
            victim_full  = dest_name,   -- keeps -Realm suffix if present
            victim_class = victim_class,
            spell_name   = "Unknown",
            timestamp    = GetTime(),
            at           = time(),      -- wall clock for history display
        }
        table.insert(kill_log, k)
        pending_kill[dst] = k
        if T.on_killing_blow then T.on_killing_blow(dst, victim_class) end
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
    wipe(pending_kill)
end
