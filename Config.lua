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

-- When true, BgStat disables WoW's "I'm out of range" / "I'm too far away"
-- voice lines (the Sound_EnableErrorSpeech CVar) on addon load and never
-- re-enables it. This affects ALL sources of error speech, not just inspect:
-- your own out-of-range casts, follow attempts, trade attempts, etc.
T.disable_error_speech = true