local _, T = ...

T.class_image = {
    WARRIOR = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    ROGUE   = "Interface\\AddOns\\MongoMon\\Res\\Broseph",
    HUNTER  = "Interface\\AddOns\\MongoMon\\Res\\DerpFace",
    MAGE    = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    PRIEST  = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    PALADIN = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    SHAMAN  = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    WARLOCK = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
    DRUID   = "Interface\\AddOns\\MongoMon\\Res\\MadBaby",
}

T.kb_sound = "Interface\\AddOns\\MongoMon\\Res\\Hehhe.mp3"

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
