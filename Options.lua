local _, T = ...

local mod = {}
T.options = mod

-- ============================================================================
-- Settings persistence
-- ============================================================================
local CONFIG_KEYS = {
    "spec_scan_enabled",
    "disable_error_speech",
    "max_history",
    "send_to_chat_cooldown",
}

function mod.load_saved()
    if not BgStatDB then BgStatDB = {} end
    if not BgStatDB.config then BgStatDB.config = {} end
    for _, key in ipairs(CONFIG_KEYS) do
        if BgStatDB.config[key] ~= nil then
            T[key] = BgStatDB.config[key]
        end
    end
end

local function set_config(key, value)
    if not BgStatDB.config then BgStatDB.config = {} end
    BgStatDB.config[key] = value
    T[key] = value
end

-- ============================================================================
-- Panel canvas: a regular Frame populated with widgets. Registered with
-- Blizzard's options system so it appears in Esc → Options → AddOns → bgstat.
-- ============================================================================

local panel
local category_obj   -- holds the registered Settings category for OpenToCategory calls

local function build_checkbox(parent, label, tooltip, get_value, set_value)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb.text:SetText(label)
    cb.tooltipText = label
    cb.tooltipRequirement = tooltip
    cb:SetScript("OnClick", function(self)
        set_value(self:GetChecked())
    end)
    cb.Refresh = function() cb:SetChecked(get_value() and true or false) end
    return cb
end

local function build_slider(parent, label, low, high, step, get_value, set_value)
    local s = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    s:SetWidth(280)
    s:SetMinMaxValues(low, high)
    s:SetValueStep(step)
    s:SetObeyStepOnDrag(true)
    s.Low:SetText(tostring(low))
    s.High:SetText(tostring(high))
    s.Text:SetText(label)
    s:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value / step + 0.5) * step
        self.Text:SetText(string.format("%s: %d", label, value))
        set_value(value)
    end)
    s.Refresh = function()
        local v = get_value()
        s:SetValue(v)
        s.Text:SetText(string.format("%s: %d", label, v))
    end
    return s
end

local function populate(canvas)
    -- Canvas is the parent frame Blizzard provides for our content.
    local title = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("bgstat")

    local subtitle = canvas:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetPoint("RIGHT", canvas, "RIGHT", -32, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText("Settings persist per account. Changes take effect immediately.")

    -- Toggles
    local cb_scanner = build_checkbox(canvas,
        "Enable spec scanner",
        "Auto-inspects friendlies for talent data during BGs. Disable to avoid all inspect calls.",
        function() return T.spec_scan_enabled end,
        function(v) set_config("spec_scan_enabled", v) end)
    cb_scanner:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)

    local cb_speech = build_checkbox(canvas,
        "Suppress 'out of range' voice line",
        "Disables Sound_EnableErrorSpeech on addon load. Takes effect on next /reload.",
        function() return T.disable_error_speech end,
        function(v) set_config("disable_error_speech", v) end)
    cb_speech:SetPoint("TOPLEFT", cb_scanner, "BOTTOMLEFT", 0, -8)

    -- Sliders
    local sl_history = build_slider(canvas,
        "Max matches in history", 50, 500, 50,
        function() return T.max_history end,
        function(v) set_config("max_history", v) end)
    sl_history:SetPoint("TOPLEFT", cb_speech, "BOTTOMLEFT", 6, -28)

    local sl_cooldown = build_slider(canvas,
        "Send-to-chat cooldown (sec)", 30, 300, 30,
        function() return T.send_to_chat_cooldown end,
        function(v) set_config("send_to_chat_cooldown", v) end)
    sl_cooldown:SetPoint("TOPLEFT", sl_history, "BOTTOMLEFT", 0, -38)

    -- Reset history (destructive)
    local divider = canvas:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    divider:SetHeight(1)
    divider:SetPoint("LEFT", 16, 0)
    divider:SetPoint("RIGHT", -32, 0)
    divider:SetPoint("TOP", sl_cooldown, "BOTTOM", 0, -22)

    local reset_label = canvas:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    reset_label:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
    reset_label:SetText("|cffff8888Danger zone|r")

    local reset_btn = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
    reset_btn:SetSize(200, 24)
    reset_btn:SetText("Reset all match history")
    reset_btn:SetPoint("TOPLEFT", reset_label, "BOTTOMLEFT", 0, -6)
    reset_btn:SetScript("OnClick", function()
        StaticPopup_Show("BGSTAT_CONFIRM_RESET")
    end)

    -- Refresh hook called whenever Blizzard's options window shows this panel.
    canvas.refresh = function()
        cb_scanner.Refresh()
        cb_speech.Refresh()
        sl_history.Refresh()
        sl_cooldown.Refresh()
    end
end

StaticPopupDialogs["BGSTAT_CONFIRM_RESET"] = {
    text = "Permanently delete all saved match history?\nThis cannot be undone.",
    button1 = "Yes, delete everything",
    button2 = "Cancel",
    OnAccept = function()
        T.history.delete_all()
        if T.ui and T.ui.refresh_active then T.ui.refresh_active() end
        DEFAULT_CHAT_FRAME:AddMessage("|cff00d606bgstat:|r match history cleared")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- ============================================================================
-- Registration: runtime check for API availability (MaxDps pattern).
-- Source: https://github.com/kaminaris/MaxDps/blob/master/Options.lua#L375-L379
-- ============================================================================
local function register()
    panel = CreateFrame("Frame", "BgStatOptionsPanel")
    panel.name = "bgstat"
    populate(panel)

    if InterfaceOptions_AddCategory then
        -- Legacy Classic clients: TBC Classic 2021, Cata Classic, etc.
        InterfaceOptions_AddCategory(panel)
    elseif Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        -- Modern API: retail, TBC Anniversary 2.5.5, MoP Classic.
        category_obj = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category_obj)
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00d606bgstat:|r no compatible options API on this client; /bgstat config will not open the AddOns panel")
    end
end

-- ============================================================================
-- Public API
-- ============================================================================

function mod.init()
    mod.load_saved()
    if not panel then register() end
end

function mod.open()
    if not panel then register() end
    if Settings and Settings.OpenToCategory and category_obj then
        -- Modern API. Accepts the category object's ID.
        Settings.OpenToCategory(category_obj:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Legacy. Double-call workaround for old quirk.
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel)
    else
        DEFAULT_CHAT_FRAME:AddMessage(
            "|cff00d606bgstat:|r could not open AddOns options panel on this client")
    end
end