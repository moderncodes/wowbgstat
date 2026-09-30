local addon_name, T = ...

local frame = CreateFrame("Frame", "BgStatCore", UIParent)

local in_bg           = false
local current_zone    = nil
local winner          = nil   -- PVP_MATCH_COMPLETE payload; nil while the match runs
local saved_match_ref = nil
local refresh_until   = 0

-- ============================================================================
-- Options that have nothing to drive on retail: no inspect scanner, no
-- nameplate badges (UnitName on a player unit is secret in PvP, so a nameplate
-- can't be joined to a scoreboard row), no live ranks.
-- ============================================================================
for _, key in ipairs({
    "spec_scan_enabled", "disable_error_speech",
    "nameplates_header", "nameplate_friendly", "nameplate_enemy", "rank_scope",
}) do T.options.args[key] = nil end

-- ============================================================================
-- Identity. UnitName is SecretWhenUnitNameIdentityRestricted and UnitGUID is
-- SecretWhenUnitIdentityRestricted (12.1 UnitDocumentation.lua), so neither is
-- read inside a match. Both are cached at login; the per-character
-- SavedVariables copy covers a /reload in the middle of a BG.
-- ============================================================================
local my_name

function T.me() return my_name end

local function cache_identity()
    BgStatUI = BgStatUI or {}
    local name, guid = UnitName("player"), UnitGUID("player")
    if hasanysecretvalues(name, guid) then
        name, guid = BgStatUI.character, BgStatUI.guid
    end
    my_name, T.my_guid = name, guid
    BgStatUI.character, BgStatUI.guid = name, guid
end

-- ============================================================================
-- Killing blows. 12.0 removed COMBAT_LOG_EVENT_UNFILTERED for addons and
-- brought PARTY_KILL back as a standalone event: (attackerGUID, targetGUID),
-- flagged SecretWhenUnitIdentityRestricted. That leaves who-killed-whom but
-- no spell and no damage, so retail kill rows carry neither.
-- ============================================================================
local function on_party_kill(attacker, target)
    if hasanysecretvalues(attacker, target) then return end

    local pet = UnitGUID("pet")
    local mine = attacker == T.my_guid
        or (not issecretvalue(pet) and attacker == pet)
    if not mine or target:sub(1, 7) ~= "Player-" then return end

    local _, class, _, _, _, name, realm = GetPlayerInfoByGUID(target)
    if hasanysecretvalues(class, name, realm) then
        class, name, realm = nil, nil, nil
    end
    -- Scoreboard names use the normalized realm (no spaces or hyphens), so
    -- "Area 52" has to become "Area52" for the victim to match their row.
    local full = (realm and realm ~= "") and (name .. "-" .. realm:gsub("[%s%-]", "")) or name

    T.store.add_kill({
        victim       = full,
        victim_full  = full,
        victim_class = class,
        at           = time(),
    })
    T.on_killing_blow(full, class)
end

-- ============================================================================
-- BG lifecycle
-- ============================================================================
local function bg_state()
    local in_instance, instance_type = IsInInstance()
    if not in_instance or instance_type ~= "pvp" then return false, nil end
    local name = GetInstanceInfo()
    return true, name or "Unknown BG"
end

local function on_match_start(zone)
    in_bg, current_zone = true, zone
    winner, saved_match_ref, refresh_until = nil, nil, 0
    T.store.reset()
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606BgStat:|r tracking %s", zone))
end

-- Leaving before the match completes saves nothing: the scoreboard never
-- left its secret state, so there are no numbers to record.
local function on_leave()
    if winner ~= nil and not saved_match_ref then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00d606BgStat:|r the scoreboard never unlocked -- match not saved")
    end
    in_bg, winner, saved_match_ref = false, nil, nil
end

-- Runs on every UPDATE_BATTLEFIELD_SCORE once the match is complete. The
-- first successful read saves the match; reads during the following 30s fold
-- late credits (win bonus, last-second HKs) into the saved rows.
local function snapshot()
    if not T.scoreboard.read() then return end

    if not saved_match_ref then
        local mine = T.store.get_player(T.me())
        T.history.save_current(current_zone, mine and mine.honor or 0, nil, winner)
        saved_match_ref = BgStatDB.matches[#BgStatDB.matches]
        refresh_until   = GetTime() + 30
        T.ui.show(1)
        C_Timer.After(1, function() T.report.send_end_of_match() end)
        return
    end

    if GetTime() > refresh_until then return end
    for name, p in pairs(T.store.get_all_players()) do
        local sp = saved_match_ref.players[name]
        if sp then
            sp.kills,  sp.deaths,  sp.honorable_kills = p.kills,  p.deaths,  p.honorable_kills
            sp.damage, sp.healing, sp.honor           = p.damage, p.healing, p.honor
        end
    end
    local mine = saved_match_ref.players[T.me()]
    if mine then saved_match_ref.honor_delta = mine.honor end
    T.ui.refresh_active()
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addon_name then
            T.history.init()
            T.options.init()
        end

    elseif event == "PLAYER_LOGIN" then
        cache_identity()

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local is_bg, zone = bg_state()
        if is_bg and not in_bg then on_match_start(zone)
        elseif not is_bg and in_bg then on_leave() end

    elseif event == "PVP_MATCH_COMPLETE" then
        if in_bg then
            winner = ...
            RequestBattlefieldScoreData()
        end

    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        -- The PvPMatch restriction ("active and incomplete PvP match") drops
        -- when the match completes. Ask for a fresh scoreboard the moment it
        -- does; the reply arrives as UPDATE_BATTLEFIELD_SCORE with plain values.
        local kind, state = ...
        if in_bg and winner ~= nil
           and kind  == Enum.AddOnRestrictionType.PvPMatch
           and state == Enum.AddOnRestrictionState.Inactive then
            RequestBattlefieldScoreData()
        end

    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if in_bg and winner ~= nil then snapshot() end

    elseif event == "PARTY_KILL" then
        if in_bg then on_party_kill(...) end
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "PVP_MATCH_COMPLETE", "ADDON_RESTRICTION_STATE_CHANGED",
    "UPDATE_BATTLEFIELD_SCORE", "PARTY_KILL",
}) do frame:RegisterEvent(e) end