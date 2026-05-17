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
-- Computes team-vs-team damage and healing percentages and emits two messages:
--   1) Private (print to chat frame, only you see): your personal stats line
--   2) Public (INSTANCE_CHAT channel): team-vs-team comparison
--
-- Algorithm matches retail MongoMon: percent = (larger - smaller) / smaller * 100.
-- E.g. team 8M vs enemy 6M -> "outdamaged the enemy by 33%".
function mod.send_end_of_match()
    local match = T.history.get_last()
    if not match then return end
    if match.winner == nil then return end   -- skip incomplete matches

    local me = UnitName("player")
    local mine = match.players[me]

    -- Private line: your stats. Print only, no SendChatMessage.
    if mine then
        print(string.format(
            "|cff00d606bgstat:|r You: %d kills / %d deaths / %s damage / %s healing / %d honor",
            mine.kills or 0, mine.deaths or 0,
            format_number(mine.damage or 0),
            format_number(mine.healing or 0),
            match.honor_delta or 0))
    end

    -- Aggregate team totals from saved match. Faction: 1 = Alliance, 0 = Horde.
    local my_faction = mine and mine.faction
    if not my_faction then return end

    local team_dmg, team_heal = 0, 0
    local enemy_dmg, enemy_heal = 0, 0
    for _, p in pairs(match.players) do
        if p.faction == my_faction then
            team_dmg  = team_dmg  + (p.damage  or 0)
            team_heal = team_heal + (p.healing or 0)
        else
            enemy_dmg  = enemy_dmg  + (p.damage  or 0)
            enemy_heal = enemy_heal + (p.healing or 0)
        end
    end

    local function pct_diff(a, b)
        -- Returns rounded integer percent by which the larger exceeds the smaller.
        local lo = math.min(a, b)
        if lo <= 0 then return nil end
        return math.floor((math.max(a, b) - lo) / lo * 100 + 0.5)
    end

    local dmg_pct  = pct_diff(team_dmg,  enemy_dmg)
    local heal_pct = pct_diff(team_heal, enemy_heal)

    if dmg_pct then
        if team_dmg >= enemy_dmg then
            SendChatMessage(string.format(
                "Your team outdamaged the enemy by %d%%.", dmg_pct), "INSTANCE_CHAT")
        else
            SendChatMessage(string.format(
                "The enemy outdamaged your team by %d%%.", dmg_pct), "INSTANCE_CHAT")
        end
    end

    if heal_pct then
        if team_heal >= enemy_heal then
            SendChatMessage(string.format(
                "Your team outhealed the enemy by %d%%.", heal_pct), "INSTANCE_CHAT")
        else
            SendChatMessage(string.format(
                "The enemy outhealed your team by %d%%.", heal_pct), "INSTANCE_CHAT")
        end
    end
end

-- Brief BG-chat broadcast for /bgstat send. Pulls top-3 dmg from this match.
function mod.send_to_chat()
    local now = GetTime()
    if now - last_chat_send < T.send_to_chat_cooldown then
        DEFAULT_CHAT_FRAME:AddMessage("bgstat: chat cooldown active")
        return
    end
    last_chat_send = now

    local me = UnitName("player")
    local mine = T.combat_log.get_player(me)
    SendChatMessage("== bgstat After-Action ==", "INSTANCE_CHAT")
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
