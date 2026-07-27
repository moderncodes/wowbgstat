local _, T = ...

local res = "Interface\\AddOns\\BgStat\\Res\\"

-- KB sounds. One picked at random per killing blow.
T.kb_sounds = {
    res.."AllClear.mp3",    res.."AufWiedersehen.mp3", res.."EnemyWeakened.MP3",
    res.."Excellent.mp3",   res.."GoodGame.mp3",       res.."GreatShot.mp3",
    res.."Halo.mp3",        res.."Hehhe.mp3",          res.."Jahahaha.mp3",
    res.."JaWohl.mp3",      res.."JaWohl2.mp3",        res.."Nein.mp3",
    res.."PathCleared.mp3", res.."Sorry.mp3",          res.."Wunderbar.mp3",
}

T.kb_sound = "Interface\\AddOns\\BgStat\\Res\\Hehhe.mp3"

-- KB image popup placement, anchored to UIParent.
-- TOPRIGHT sits under the minimap; BOTTOMRIGHT sits above the bag bar.
T.kb_image_point = "TOPRIGHT"
T.kb_image_x     = -20
T.kb_image_y     = -220
T.kb_image_size  = 192

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

-- Nameplate rank badges.
T.nameplate_friendly = false   -- WoW's friendly nameplates are off by default
T.nameplate_enemy    = true

-- "global"  = rank every player in the BG together
-- "faction" = rank each team separately
T.rank_scope = "global"