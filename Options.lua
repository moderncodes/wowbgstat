local _, T = ...

local mod = {}
T.options = mod

-- ============================================================================
-- AceConfig-driven settings panel
--
-- AceConfig is declarative: we describe the settings as a table, and
-- AceConfigDialog auto-renders them into a polished panel with proper
-- sliders, toggles, and confirmation dialogs. The panel registers into
-- Blizzard's Interface Options under "BgStat".
-- ============================================================================

local CONFIG_KEYS = {
    "spec_scan_enabled",
    "disable_error_speech",
    "max_history",
    "send_to_chat_cooldown",
}

local function load_saved()
    if not BgStatDB then BgStatDB = {} end
    if not BgStatDB.config then BgStatDB.config = {} end
    for _, key in ipairs(CONFIG_KEYS) do
        if BgStatDB.config[key] ~= nil then
            T[key] = BgStatDB.config[key]
        end
    end
end

local function get(key)
    return T[key]
end

local function set(key, value)
    if not BgStatDB.config then BgStatDB.config = {} end
    BgStatDB.config[key] = value
    T[key] = value
end

local options_table = {
    type = "group",
    name = "BgStat",
    args = {
        general_header = {
            type = "header",
            name = "General",
            order = 1,
        },
        spec_scan_enabled = {
            type = "toggle",
            name = "Enable spec scanner",
            desc = "Auto-inspects friendlies for talent data during BGs. Disable to avoid all inspect calls.",
            get = function() return get("spec_scan_enabled") end,
            set = function(_, v) set("spec_scan_enabled", v) end,
            order = 2,
            width = "full",
        },
        disable_error_speech = {
            type = "toggle",
            name = "Suppress 'out of range' voice line",
            desc = "Disables WoW's 'I'm out of range' voice for all sources (inspect, your own casts, follow, trade). Takes effect on next /reload.",
            get = function() return get("disable_error_speech") end,
            set = function(_, v) set("disable_error_speech", v) end,
            order = 3,
            width = "full",
        },
        limits_header = {
            type = "header",
            name = "Limits",
            order = 10,
        },
        max_history = {
            type = "range",
            name = "Max matches in history",
            desc = "How many past matches to keep in saved variables.",
            min = 50,
            max = 500,
            step = 50,
            get = function() return get("max_history") end,
            set = function(_, v) set("max_history", v) end,
            order = 11,
            width = "full",
        },
        send_to_chat_cooldown = {
            type = "range",
            name = "Send-to-chat cooldown (seconds)",
            desc = "Minimum time between /bgstat send broadcasts.",
            min = 30,
            max = 300,
            step = 30,
            get = function() return get("send_to_chat_cooldown") end,
            set = function(_, v) set("send_to_chat_cooldown", v) end,
            order = 12,
            width = "full",
        },
        danger_header = {
            type = "header",
            name = "Danger zone",
            order = 20,
        },
        reset_history = {
            type = "execute",
            name = "Reset all match history",
            desc = "Permanently deletes every saved match. This cannot be undone.",
            confirm = true,
            confirmText = "Permanently delete all saved match history?\nThis cannot be undone.",
            func = function()
                T.history.delete_all()
                if T.ui and T.ui.refresh_active then T.ui.refresh_active() end
                DEFAULT_CHAT_FRAME:AddMessage("|cff00d606BgStat:|r match history cleared")
            end,
            order = 21,
        },
    },
}

function mod.init()
    load_saved()

    -- Ace3 is OptionalDeps in the TOC. If it isn't installed, skip panel
    -- registration entirely and let /bgstat config print a helpful error.
    if not LibStub then
        return
    end

    local ok_ac, AceConfig = pcall(LibStub, "AceConfig-3.0")
    local ok_acd, AceConfigDialog = pcall(LibStub, "AceConfigDialog-3.0")
    if not (ok_ac and ok_acd) then
        return
    end

    AceConfig:RegisterOptionsTable("BgStat", options_table)
    AceConfigDialog:AddToBlizOptions("BgStat", "BgStat")
    mod._registered = true
end

function mod.open()
    if not mod._registered then
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00d606BgStat:|r options panel requires Ace3. Install it via CurseForge.")
        return
    end
    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("BgStat")
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory("BgStat")
        InterfaceOptionsFrame_OpenToCategory("BgStat")
    end
end