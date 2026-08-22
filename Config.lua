local _, T = ...

local res = "Interface\\AddOns\\BgStat\\Res\\"

-- KB sounds. One picked at random per killing blow.
T.kb_sounds = {
    res.."BarelyFelt.mp3",    res.."CorpseRun.mp3",  res.."Deleted.mp3",
    res.."Deprioritized.mp3", res.."ForFree.mp3",    res.."KillLogged.mp3",
    res.."ResTimer.mp3",      res.."SitDown.mp3",    res.."ThePile.mp3",
}

-- Killing-blow voice lines. Set false here (or via /bgstat config) to
-- silence them without touching the rest of the addon.
T.kb_sound_enabled = true

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