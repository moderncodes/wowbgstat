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
    SendChatMessage("== bgstat After-Action ==", "BATTLEGROUND")
    if mine then
        SendChatMessage(string.format(
            "%s: %d kills / %d deaths / %s damage / %s healing",
            me, mine.kills or 0, mine.deaths or 0,
            format_number(mine.damage or 0),
            format_number(mine.healing or 0)), "BATTLEGROUND")
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
            i, list[i].name, format_number(list[i].damage)), "BATTLEGROUND")
    end
end
