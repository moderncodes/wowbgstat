local _, T = ...

local mod = {}
T.report = mod

local last_chat_send = 0
local image_frame

T.on_killing_blow = function(victim_name, victim_class)
    PlaySoundFile(T.kb_sound, "Master")

    if not image_frame then
        image_frame = CreateFrame("Frame", "BgStatKBOverlay", UIParent)
        image_frame:SetSize(256, 256)
        image_frame:SetPoint("CENTER", 0, 100)
        image_frame.tex = image_frame:CreateTexture(nil, "OVERLAY")
        image_frame.tex:SetAllPoints()
        image_frame:Hide()
    end

    local path = T.class_image[victim_class] or T.class_image.WARRIOR
    image_frame.tex:SetTexture(path)
    image_frame:Show()
    C_Timer.After(3, function() image_frame:Hide() end)
end

local function format_number(n)
    if n >= 1e6 then return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.1fk", n / 1e3)
    else return tostring(n) end
end
T.format_number = format_number

-- ============================================================================
-- End-of-match auto report
-- ============================================================================
-- Public: ONE line to INSTANCE_CHAT (BG chat) in retail MongoMon's format:
--   "[BgStat vX.Y.Z] Your team went K - D. <dmg compare>. <heal compare>."
-- Private: print to chat frame, only you see, with your personal stats.
-- Popup: visual report window via T.ui.show_match_popup (Phase B).
function mod.send_end_of_match()
    local match = T.history.get_last()
    if not match then return end
    if match.winner == nil then return end   -- skip incomplete matches

    local me = UnitName("player")
    local mine = match.players[me]

    -- Private line: your stats. Print only.
    if mine then
        print(string.format(
            "|cff00d606BgStat:|r You: %d kills / %d deaths / %s damage / %s healing / %d honor",
            mine.kills or 0, mine.deaths or 0,
            format_number(mine.damage or 0),
            format_number(mine.healing or 0),
            match.honor_delta or 0))
    end

    -- Aggregate team totals. Faction: 1 = Alliance, 0 = Horde.
    local my_faction = mine and mine.faction
    if not my_faction then
        if T.ui and T.ui.show_match_popup then T.ui.show_match_popup(match) end
        return
    end

    local team_kills, team_deaths       = 0, 0
    local team_dmg, team_heal           = 0, 0
    local enemy_dmg, enemy_heal         = 0, 0
    for _, p in pairs(match.players) do
        if p.faction == my_faction then
            team_kills  = team_kills  + (p.kills  or 0)
            team_deaths = team_deaths + (p.deaths or 0)
            team_dmg    = team_dmg    + (p.damage  or 0)
            team_heal   = team_heal   + (p.healing or 0)
        else
            enemy_dmg   = enemy_dmg   + (p.damage  or 0)
            enemy_heal  = enemy_heal  + (p.healing or 0)
        end
    end

    local function pct_diff(a, b)
        local lo = math.min(a, b)
        if lo <= 0 then return nil end
        return string.format("%.2f", (math.max(a, b) - lo) / lo * 100)
    end

    local team_kd_clause = string.format("Your team went %d - %d.", team_kills, team_deaths)

    local dmg_clause
    local dmg_pct = pct_diff(team_dmg, enemy_dmg)
    if dmg_pct then
        if team_dmg >= enemy_dmg then
            dmg_clause = string.format("Your team outdamaged the enemy by %s%%.", dmg_pct)
        else
            dmg_clause = string.format("The enemy outdamaged your team by %s%%.", dmg_pct)
        end
    end

    local heal_clause
    local heal_pct = pct_diff(team_heal, enemy_heal)
    if heal_pct then
        if team_heal >= enemy_heal then
            heal_clause = string.format("Your team outhealed the enemy team by %s%%.", heal_pct)
        else
            heal_clause = string.format("The enemy outhealed your team by %s%%.", heal_pct)
        end
    end

    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata("BgStat", "Version") or "?"
    local parts = { string.format("[BgStat v%s]", version), team_kd_clause }
    if dmg_clause  then table.insert(parts, dmg_clause)  end
    if heal_clause then table.insert(parts, heal_clause) end

    local message = table.concat(parts, " ")
    if #message > 255 then message = message:sub(1, 255) end
    SendChatMessage(message, "INSTANCE_CHAT")

    -- Auto-show the visual popup. The popup also has its own re-send button.
    if T.ui and T.ui.show_match_popup then
        T.ui.show_match_popup(match)
    end
end

-- Brief BG-chat broadcast for /bgstat send. Pulls top-3 dmg from this match.
function mod.send_to_chat()
    local now = GetTime()
    if now - last_chat_send < T.send_to_chat_cooldown then
        DEFAULT_CHAT_FRAME:AddMessage("BgStat: chat cooldown active")
        return
    end
    last_chat_send = now

    local me = UnitName("player")
    local mine = T.combat_log.get_player(me)
    SendChatMessage("== BgStat After-Action ==", "INSTANCE_CHAT")
    if mine then
        SendChatMessage(string.format(
            "%s: %d kills / %d deaths / %s damage / %s healing",
            me, mine.kills or 0, mine.deaths or 0,
            format_number(mine.damage or 0),
            format_number(mine.healing or 0)), "INSTANCE_CHAT")
    end

    local list = {}
    for n, p in pairs(T.combat_log.get_all_players()) do
        if (p.damage or 0) > 0 then
            table.insert(list, { name = n, damage = p.damage })
        end
    end
    table.sort(list, function(a, b) return a.damage > b.damage end)
    for i = 1, math.min(3, #list) do
        SendChatMessage(string.format("  %d. %s - %s",
            i, list[i].name, format_number(list[i].damage)), "INSTANCE_CHAT")
    end
end
