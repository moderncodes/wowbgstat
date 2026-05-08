local addon_name, T = ...

local frame = CreateFrame("Frame", "MongoMonCore", UIParent)

local in_bg            = false
local last_winner      = nil
local current_zone     = nil
local honor_listen_until = 0
local saved_match_ref    = nil

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

local function parse_honor_message(msg)
    if not msg then return 0 end
    if honor_gain_pattern then
        local _, _, est = msg:match(honor_gain_pattern)
        if est then return tonumber(est) or 0 end
    end
    if honor_award_pattern then
        local awarded = msg:match(honor_award_pattern)
        if awarded then return tonumber(awarded) or 0 end
    end
    return 0
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

    -- Start the spec scanner if enabled.
    if T.spec_scanner and T.spec_scan_enabled then
        T.spec_scanner.set_enabled(true)
        T.spec_scanner.start()
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606MongoMon:|r tracking %s", zone))
end

local function on_match_end()
    if not in_bg then return end
    in_bg = false
    T.scoreboard.refresh()

    local _, fresh_zone = bg_state()
    local zone_to_save = current_zone
    if fresh_zone and fresh_zone ~= "Unknown BG" then zone_to_save = fresh_zone end

    -- DEBUG: snapshot what we're about to save
    local me_data = T.combat_log.get_player(UnitName("player")) or {}
    if not _G.MM_honor_log then _G.MM_honor_log = {} end
    table.insert(_G.MM_honor_log, string.format(
        "[%s] SAVE: damage=%s healing=%s honor=%s total_match=%s",
        date("%H:%M:%S"),
        tostring(me_data.damage), tostring(me_data.healing),
        tostring(me_data.honor), tostring(honor_match_total)))

    -- honor_match_total accumulated from CHAT_MSG_COMBAT_HONOR_GAIN messages
    -- during the BG. This captures every "+X honor" event including bonus,
    -- objective, and per-kill honor.
    T.history.save_current(zone_to_save or "Unknown BG", honor_match_total)
    saved_match_ref = mongo_mon_db.matches[#mongo_mon_db.matches]

    if T.spec_scanner then T.spec_scanner.stop() end
    T.nameplates.clear_all()
    T.ui.show(1)

    -- Listen 30s after match end for trailing credits (final win bonus,
    -- last-second HK honor that lands after the winner is announced).
    honor_listen_until = GetTime() + 30
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        if (...) == addon_name then
            T.history.init()
            if not mongo_mon_ui then mongo_mon_ui = {} end
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
        local gained = parse_honor_message(raw_msg)

        -- DEBUG: log every honor message so we can see what's matching/missing
        if not _G.MM_honor_log then _G.MM_honor_log = {} end
        table.insert(_G.MM_honor_log, string.format(
            "[%s] msg=%s | parsed=%d | in_bg=%s",
            date("%H:%M:%S"), tostring(raw_msg), gained, tostring(in_bg)))

        if gained > 0 then
            if in_bg then
                honor_match_total = honor_match_total + gained
            elseif GetTime() < honor_listen_until and saved_match_ref then
                saved_match_ref.honor_delta = (saved_match_ref.honor_delta or 0) + gained
                T.ui.refresh_active()
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

SLASH_MONGOMON1, SLASH_MONGOMON2 = "/mm", "/mongomon"
SlashCmdList.MONGOMON = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "" then
        T.ui.toggle()
    elseif msg == "help" then
        DEFAULT_CHAT_FRAME:AddMessage("MongoMon: /mm (toggle window) | /mm last | /mm history | /mm classes | /mm specs | /mm send | /mm clear")
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
        DEFAULT_CHAT_FRAME:AddMessage("MongoMon: history cleared")
        T.ui.refresh_active()
    else
        DEFAULT_CHAT_FRAME:AddMessage("MongoMon: unknown command - try /mm help")
    end
end

SLASH_MMSCORE1 = "/mmscore"
SlashCmdList.MMSCORE = function()
    RequestBattlefieldScoreData()
    local n = GetNumBattlefieldScores()
    local me = UnitName("player")
    local lines = { "scores=" .. n, "looking for: " .. me, "" }

    for i = 1, n do
        local r = { GetBattlefieldScore(i) }
        local short = r[1] and r[1]:match("^([^%-]+)") or r[1]
        if short == me then
            table.insert(lines, "FOUND YOU at row " .. i)
            table.insert(lines, "  name        [1]  = " .. tostring(r[1]))
            table.insert(lines, "  kills       [2]  = " .. tostring(r[2]))
            table.insert(lines, "  hks         [3]  = " .. tostring(r[3]))
            table.insert(lines, "  deaths      [4]  = " .. tostring(r[4]))
            table.insert(lines, "  honor       [5]  = " .. tostring(r[5]))
            table.insert(lines, "  faction     [6]  = " .. tostring(r[6]))
            table.insert(lines, "  rank/spec   [7]  = " .. tostring(r[7]))
            table.insert(lines, "  race        [8]  = " .. tostring(r[8]))
            table.insert(lines, "  class_loc   [9]  = " .. tostring(r[9]))
            table.insert(lines, "  class_token [10] = " .. tostring(r[10]))
            table.insert(lines, "  damage      [11] = " .. tostring(r[11]))
            table.insert(lines, "  healing     [12] = " .. tostring(r[12]))
            table.insert(lines, "  unknown     [13] = " .. tostring(r[13]))
            break
        end
    end

    if not MMScoreFrame then
        local f = CreateFrame("Frame", "MMScoreFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(660); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    MMScoreFrame.eb:SetText(table.concat(lines, "\n"))
    MMScoreFrame:Show()
    MMScoreFrame.eb:HighlightText()
    MMScoreFrame.eb:SetFocus()
end

SLASH_MMINSPECT1 = "/mminspect"
SlashCmdList.MMINSPECT = function()
    local m = mongo_mon_db.matches[#mongo_mon_db.matches]
    if not m then
        DEFAULT_CHAT_FRAME:AddMessage("no matches saved")
        return
    end

    local lines = {}
    table.insert(lines, "=== Last saved match ===")
    table.insert(lines, "zone=" .. tostring(m.zone))
    table.insert(lines, "winner=" .. tostring(m.winner))
    table.insert(lines, "honor_delta=" .. tostring(m.honor_delta))
    table.insert(lines, "")
    table.insert(lines, "=== First 5 player records (raw) ===")

    local count = 0
    for name, p in pairs(m.players) do
        count = count + 1
        if count > 5 then break end
        table.insert(lines, string.format("--- %s ---", name))
        for k, v in pairs(p) do
            table.insert(lines, string.format("  %s = %s (%s)",
                tostring(k), tostring(v), type(v)))
        end
    end

    -- Reuse the debug window pattern. Build it fresh every call.
    if not MMInspectFrame then
        local f = CreateFrame("Frame", "MMInspectFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(660); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    MMInspectFrame.eb:SetText(table.concat(lines, "\n"))
    MMInspectFrame:Show()
    MMInspectFrame.eb:HighlightText()
    MMInspectFrame.eb:SetFocus()
end

SLASH_MMRENDER1 = "/mmrender"
SlashCmdList.MMRENDER = function()
    local m = mongo_mon_db.matches[#mongo_mon_db.matches]
    if not m then return end
    local lines = { "=== What Last Match would render ===" }
    local count = 0
    for name, p in pairs(m.players) do
        count = count + 1
        if count > 5 then break end
        local class_val = p.class
        local would_show = string.format("|c%s%s|r",
            (RAID_CLASS_COLORS[class_val or ""] and "ffXXXXXX") or "ffffffff",
            class_val or "?")
        table.insert(lines, string.format(
            "name=%s | p.class=%s (%s) | RAID_CLASS_COLORS[p.class]=%s | would render: %s",
            name, tostring(class_val), type(class_val),
            tostring(RAID_CLASS_COLORS[class_val or ""]),
            would_show))
    end

    if not MMRenderFrame then
        local f = CreateFrame("Frame", "MMRenderFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(800, 400); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(760); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    MMRenderFrame.eb:SetText(table.concat(lines, "\n"))
    MMRenderFrame:Show()
    MMRenderFrame.eb:HighlightText()
    MMRenderFrame.eb:SetFocus()
end

SLASH_MMLOG1 = "/mmlog"
SlashCmdList.MMLOG = function()
    if not MMLogFrame then
        local f = CreateFrame("Frame", "MMLogFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(800, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(760); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    local txt = _G.MM_log and #_G.MM_log > 0 and table.concat(_G.MM_log, "\n") or "(log empty)"
    MMLogFrame.eb:SetText(txt)
    MMLogFrame:Show()
    MMLogFrame.eb:HighlightText()
    MMLogFrame.eb:SetFocus()
    _G.MM_log = {}  -- clear after read
end

SLASH_MMSPECLOG1 = "/mmspeclog"
SlashCmdList.MMSPECLOG = function()
    if not MMSpecLogFrame then
        local f = CreateFrame("Frame", "MMSpecLogFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(800, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(760); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    local log = _G.MM_spec_log or {}
    local txt = (#log > 0) and table.concat(log, "\n") or "(spec log is empty)"
    MMSpecLogFrame.eb:SetText(txt)
    MMSpecLogFrame:Show()
    MMSpecLogFrame.eb:HighlightText()
    MMSpecLogFrame.eb:SetFocus()
end

SLASH_MMSCRUB1 = "/mmscrub"
SlashCmdList.MMSCRUB = function()
    if not mongo_mon_db or not mongo_mon_db.matches then
        DEFAULT_CHAT_FRAME:AddMessage("MM scrub: no database")
        return
    end

    local class_loc_to_token = {
        Warrior = "WARRIOR", Paladin = "PALADIN", Hunter = "HUNTER",
        Rogue   = "ROGUE",   Priest  = "PRIEST",  Shaman = "SHAMAN",
        Mage    = "MAGE",    Warlock = "WARLOCK", Druid  = "DRUID",
    }

    local fixed = 0
    for _, m in ipairs(mongo_mon_db.matches) do
        for _, p in pairs(m.players or {}) do
            if type(p.damage)  ~= "number" then p.damage  = 0; fixed = fixed + 1 end
            if type(p.healing) ~= "number" then p.healing = 0; fixed = fixed + 1 end
            if type(p.kills)   ~= "number" then p.kills   = 0 end
            if type(p.deaths)  ~= "number" then p.deaths  = 0 end
            if type(p.honor)   ~= "number" then p.honor   = 0 end
            if type(p.honorable_kills) ~= "number" then p.honorable_kills = 0 end
            if type(p.class) == "string" then
                local mapped = class_loc_to_token[p.class]
                if mapped then p.class = mapped end
            end
        end
    end

    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606MongoMon scrub:|r repaired %d corrupted fields", fixed))
end

SLASH_MMHONORLOG1 = "/mmhonorlog"
SlashCmdList.MMHONORLOG = function()
    if not MMHonorLogFrame then
        local f = CreateFrame("Frame", "MMHonorLogFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(900, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(860); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    local log = _G.MM_honor_log or {}
    local txt = (#log > 0) and table.concat(log, "\n") or "(honor log empty)"
    MMHonorLogFrame.eb:SetText(txt)
    MMHonorLogFrame:Show()
    MMHonorLogFrame.eb:HighlightText()
    MMHonorLogFrame.eb:SetFocus()
end

SLASH_MMSPECDIAG1 = "/mmspecdiag"
SlashCmdList.MMSPECDIAG = function()
    local lines = { "=== Specs aggregation diagnostic ===" }
    local total_recs = 0
    local recs_with_spec = 0
    local recs_with_damage = 0
    local recs_with_both = 0

    for i, m in ipairs(mongo_mon_db.matches) do
        for name, p in pairs(m.players) do
            total_recs = total_recs + 1
            if p.spec_tab then recs_with_spec = recs_with_spec + 1 end
            if (p.damage or 0) > 0 then recs_with_damage = recs_with_damage + 1 end
            if p.spec_tab and (p.damage or 0) > 0 then
                recs_with_both = recs_with_both + 1
            end
        end
    end

    table.insert(lines, string.format("Total player records across all matches: %d", total_recs))
    table.insert(lines, string.format("Records with spec_tab populated: %d", recs_with_spec))
    table.insert(lines, string.format("Records with damage > 0: %d", recs_with_damage))
    table.insert(lines, string.format("Records with BOTH spec and damage: %d (these contribute to Specs tab)", recs_with_both))
    table.insert(lines, "")
    table.insert(lines, "=== Per-match breakdown ===")

    for i, m in ipairs(mongo_mon_db.matches) do
        local with_spec = 0
        local with_damage = 0
        local with_both = 0
        for _, p in pairs(m.players) do
            if p.spec_tab then with_spec = with_spec + 1 end
            if (p.damage or 0) > 0 then with_damage = with_damage + 1 end
            if p.spec_tab and (p.damage or 0) > 0 then with_both = with_both + 1 end
        end
        table.insert(lines, string.format(
            "Match %d (%s): spec=%d damage=%d both=%d",
            i, m.zone or "?", with_spec, with_damage, with_both))
    end

    if not MMSpecDiagFrame then
        local f = CreateFrame("Frame", "MMSpecDiagFrame", UIParent, "BasicFrameTemplateWithInset")
        f:SetSize(700, 500); f:SetPoint("CENTER")
        f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
        eb:SetWidth(660); eb:SetAutoFocus(false)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
    end
    MMSpecDiagFrame.eb:SetText(table.concat(lines, "\n"))
    MMSpecDiagFrame:Show()
    MMSpecDiagFrame.eb:HighlightText()
    MMSpecDiagFrame.eb:SetFocus()
end

SLASH_MMPURGEBROKEN1 = "/mmpurgebroken"
SlashCmdList.MMPURGEBROKEN = function()
    if not mongo_mon_db or not mongo_mon_db.matches then return end
    local before = #mongo_mon_db.matches
    local kept = {}

    for _, m in ipairs(mongo_mon_db.matches) do
        -- Keep matches that have at least one player with damage > 0,
        -- OR that have no spec data at all (older but otherwise intact).
        -- Drop matches that have spec data but all-zero damage (the broken
        -- middle generation from the scoreboard-position bug).
        local has_damage = false
        local has_spec = false
        for _, p in pairs(m.players or {}) do
            if (p.damage or 0) > 0 then has_damage = true end
            if p.spec_tab then has_spec = true end
        end
        local broken = has_spec and not has_damage
        if not broken then
            table.insert(kept, m)
        end
    end

    mongo_mon_db.matches = kept
    DEFAULT_CHAT_FRAME:AddMessage(string.format(
        "|cff00d606MongoMon:|r purged %d broken matches (%d -> %d)",
        before - #kept, before, #kept))
end