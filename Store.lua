local _, T = ...

-- Per-match working set. Filled during a BG, snapshotted into BgStatDB by
-- History.save_current, wiped at the next match start.
--
-- Lives in its own file because every module reads it. It used to sit inside
-- CombatLog.lua, which made the combat log a hard dependency of the whole
-- addon -- and retail has no combat log to load.
local mod = {}
T.store = mod

local players  = {}   -- name -> stats (populated from the scoreboard)
local kill_log = {}   -- list of YOUR KBs this match

function mod.set_player(name, data) players[name] = data end
function mod.get_player(name)       return players[name] end
function mod.get_all_players()      return players end

function mod.add_kill(k)            table.insert(kill_log, k) end
function mod.get_kill_log()         return kill_log end

function mod.reset()
    wipe(players)
    wipe(kill_log)
end
