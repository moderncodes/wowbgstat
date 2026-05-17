local addon_name, T = ...

local frame = CreateFrame("Frame", "BgStatCore", UIParent)

local in_bg            = false
local last_winner      = nil
local current_zone     = nil
local honor_listen_until = 0
local saved_match_ref    = nil
local report_pending     = false

-- Build patterns from Blizzard's localized format strings.
-- Source: https://warcraft.wiki.gg/wiki/Parsing_event_messages
-- COMBATLOG_HONORGAIN  = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
-- COMBATLOG_HONORAWARD = "You have been awarded %d honor points."
-- Both arrive via CHAT_MSG_COMBAT_HONOR_GAIN
-- (https://wowpedia.fandom.com/wiki/CHAT_MSG_COMBAT_HONOR_GAIN).
-- This is the production approach used by HonorSpy on Classic/TBC.
local honor_gain_pattern, honor_award_pattern
do
    local function build_pattern(template)
        local p = template:gsub("([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
        p = p:gsub("%%%%s", "(.+)")    -- %s -> capture string
        p = p:gsub("%%%%d", "(%%d+)")  -- %d -> capture number
        return p
    end
    if COMBATLOG_HONORGAIN  then honor_gain_pattern  = build_pattern(COMBATLOG_HONORGAIN)  end
    if COMBATLOG_HONORAWARD then honor_award_pattern = build_pattern(COMBATLOG_HONORAWARD) end
end

local honor_match_total = 0   -- accumulator for current BG

-- Returns (gained, kind) where kind is "gain" (per-kill, COMBATLOG_HONORGAIN)
-- or "award" (bonus/objective/win, COMBATLOG_HONORAWARD). The win bonus at
-- match end is always an "award" message, which we use to trigger the
-- end-of-match report at the right moment.
local function parse_honor_message(msg)
    if not msg then return 0, nil end
    if honor_gain_pattern then
        local _, _, est = msg:match(honor_gain_pattern)
        if est then return tonumber(est) or 0, "gain" end
    end
    if honor_award_pattern then
        local awarded = msg:match(honor_award_pattern)
        if awarded then return tonumber(awarded) or 0, "award" end
    end
    return 0, nil
end

local function bg_state()
    local in_instance, instance_type = IsInInstance()
    if not in_instance or instance_type ~= "pvp" then return false, nil end
    local name = GetInstanceInfo()
    return true, name or "Unknown BG"
end

local function on_match_start(zone)
    in_bg, last_winner, current_zone = true, nil, zone
    honor_match_total = 0
    saved_match_ref   = nil
    T.combat_log.reset()

    -- Seed our own player record with current spec. The scanner skips self
    -- (only inspects friendlies); we read directly via GetTalentTabInfo for
    -- ourselves. Scoreboard.refresh later merges BG numbers in without
    -- overwriting these fields. isInspect=false reads the player's own talents.
    -- Source: https://wowpedia.fandom.com/wiki/API_GetTalentTabInfo
    local me = UnitName("player")
    local _, my_class = UnitClass("player")
    if me and my_class then
        local best_tab, best_points = nil, -1
        for tab = 1, 3 do
            local _, _, _, _, points_spent = GetTalentTabInfo(tab, false)
            points_spent = points_spent or 0
            if type(points_spent) ~= "number" then points_spent = 0 end
            if points_spent > best_points then
                best_tab, best_points = tab, points_spent
            end
        end
        if best_tab and best_points > 0 then
            T.combat_log.set_player(me, {
                class      = my_class,
                spec_class = my_class,
                spec_tab   = best_tab,
            })
        end
    end

    -- Start the spec scanner if enabled.
    if T.spec_scanner and T.spec_scan_enabled then
        T.spec_scanner.set_enabled(true)
        T.spec_scanner.start()
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606bgstat:|r tracking %s", zone))
end

local function on_match_end()
    if not in_bg then return end
    in_bg = false
    T.scoreboard.refresh()

    local _, fresh_zone = bg_state()
    local zone_to_save = current_zone
    if fresh_zone and fresh_zone ~= "Unknown BG" then zone_to_save = fresh_zone end

    -- honor_match_total accumulated from CHAT_MSG_COMBAT_HONOR_GAIN messages
    -- during the BG. This captures every "+X honor" event including bonus,
    -- objective, and per-kill honor.
    T.history.save_current(zone_to_save or "Unknown BG", honor_match_total)
    saved_match_ref = BgStatDB.matches[#BgStatDB.matches]

    if T.spec_scanner then T.spec_scanner.stop() end
    T.nameplates.clear_all()
    T.ui.show(1)

    -- Listen 30s after match end for trailing credits (final win bonus,
    -- last-second HK honor that lands after the winner is announced).
    honor_listen_until = GetTime() + 30
    report_pending     = true

    -- Fallback: if no award message arrives within 8 seconds (e.g. a draw
    -- where no team won the BG, or some edge case where the award message
    -- gets swallowed), send the report anyway with whatever honor we have.
    -- The normal path is the CHAT_MSG_COMBAT_HONOR_GAIN handler, which fires
    -- the report immediately on the first "award" message after match end --
    -- typically 1-3 seconds after the winner resolves.
    C_Timer.After(8, function()
        if report_pending then
            report_pending = false
            T.report.send_end_of_match()
        end
    end)
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addon_name then
            T.history.init()
            if T.disable_error_speech then
                SetCVar("Sound_EnableErrorSpeech", "0")
            end
        end

    elseif event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
        local is_bg, zone = bg_state()
        if is_bg and not in_bg then on_match_start(zone)
        elseif not is_bg and in_bg then on_match_end() end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if in_bg then T.combat_log.handle_event() end

    elseif event == "UPDATE_BATTLEFIELD_SCORE" then
        if in_bg then
            T.scoreboard.refresh()
            T.nameplates.refresh_all()
            local winner = GetBattlefieldWinner()
            if winner ~= nil and last_winner == nil then
                last_winner = winner
                on_match_end()
            end
        elseif GetTime() < honor_listen_until and saved_match_ref then
            -- Late scoreboard refresh after match end: bonus honor field [5]
            -- updates as final credits land. Re-poll and update the saved match.
            -- Source: https://wowpedia.fandom.com/wiki/API_GetBattlefieldScore
            T.scoreboard.refresh()
            for name, p in pairs(T.combat_log.get_all_players()) do
                local sp = saved_match_ref.players[name]
                if sp and (p.honor or 0) > (sp.honor or 0) then
                    sp.honor = p.honor
                end
            end
            T.ui.refresh_active()
        end

    elseif event == "NAME_PLATE_UNIT_ADDED" then
        if in_bg then T.nameplates.on_unit_added(...) end

    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        if in_bg then T.nameplates.on_unit_removed(...) end

    elseif event == "CHAT_MSG_COMBAT_HONOR_GAIN" then
        local raw_msg = ...
        local gained, kind = parse_honor_message(raw_msg)

        if gained > 0 then
            if in_bg then
                honor_match_total = honor_match_total + gained
            elseif GetTime() < honor_listen_until and saved_match_ref then
                saved_match_ref.honor_delta = (saved_match_ref.honor_delta or 0) + gained
                T.ui.refresh_active()

                -- The win bonus is an "award" message that lands 1-3 seconds
                -- after match end. Fire the report immediately when we see it,
                -- so chat audience is still in the BG.
                if kind == "award" and report_pending then
                    report_pending = false
                    -- Tiny grace period for any second simultaneous award
                    -- (e.g. quest credit + faction bonus), then send.
                    C_Timer.After(0.5, function() T.report.send_end_of_match() end)
                end
            end
        end
    end
end)

for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA",
    "COMBAT_LOG_EVENT_UNFILTERED", "UPDATE_BATTLEFIELD_SCORE",
    "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "CHAT_MSG_COMBAT_HONOR_GAIN",
}) do frame:RegisterEvent(e) end

SLASH_BGSTAT1, SLASH_BGSTAT2 = "/bgstat", "/bgs"
SLASH_BGSTATSCAN1 = "/bgstatscan"
SlashCmdList.BGSTATSCAN = function()
    local fr = T.spec_scanner
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    local in_range, total = 0, 0
    if IsInRaid() then
        for i = 1, n do
            if UnitExists("raid"..i) then
                total = total + 1
                if CheckInteractDistance("raid"..i, 1) then in_range = in_range + 1 end
            end
        end
    end
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606bgstat scan:|r enabled=%s detected=%d friendlies=%d in_range=%d",
        tostring(fr.is_enabled()), fr.get_detected_count(), total, in_range))
end
SlashCmdList.BGSTAT = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        T.ui.toggle()
    elseif msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("bgstat: /bgstat (toggle window) | /bgstat last | /bgstat history | /bgstat classes | /bgstat specs | /bgstat send | /bgstat clear")
    elseif msg == "last" or msg == "report" then
        T.ui.show(1)
    elseif msg == "history" then
        T.ui.show(2)
    elseif msg == "classes" then
        T.ui.show(3)
    elseif msg == "specs" then
        T.ui.show(4)
    elseif msg == "send" then
        T.report.send_to_chat()
    elseif msg == "clear" then
        T.history.delete_all()
        DEFAULT_CHAT_FRAME:AddMessage("bgstat: history cleared")
        T.ui.refresh_active()
    else
        DEFAULT_CHAT_FRAME:AddMessage("bgstat: unknown command - try /bgstat help")
    end
end