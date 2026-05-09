local _, T = ...

T.class_image = {
    WARRIOR = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    ROGUE   = "Interface\\AddOns\\BgStat\\Res\\Broseph",
    HUNTER  = "Interface\\AddOns\\BgStat\\Res\\DerpFace",
    MAGE    = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    PRIEST  = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    PALADIN = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    SHAMAN  = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    WARLOCK = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
    DRUID   = "Interface\\AddOns\\BgStat\\Res\\MadBaby",
}

T.kb_sound = "Interface\\AddOns\\BgStat\\Res\\Hehhe.mp3"

T.bg_zones = {
    ["Warsong Gulch"]    = "WSG",
    ["Arathi Basin"]     = "AB",
    ["Alterac Valley"]   = "AV",
    ["Eye of the Storm"] = "EotS",
}

T.max_history           = 100
T.send_to_chat_cooldown = 60
-- Spec auto-scanner toggle. Set to false here to disable scanning entirely.
T.spec_scan_enabled = true
