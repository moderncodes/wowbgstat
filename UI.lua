local _, T = ...

local mod = {}
T.ui = mod

local FRAME_W, FRAME_H = 760, 520
local ROW_H            = 18
local HEADER_H         = 22

local main_frame
local tabs              = {}
local content_frames    = {}
local active_tab        = 1

-- ============================================================================
-- Helpers
-- ============================================================================

local function fmt(n)
    n = n or 0
    if n >= 1e6 then return string.format("%.1fM", n / 1e6)
    elseif n >= 1e3 then return string.format("%.1fk", n / 1e3)
    elseif n % 1 == 0 then return tostring(n)
    else return string.format("%.1f", n) end
end

local function class_color_hex(token)
    local c = RAID_CLASS_COLORS[token or ""]
    if not c then return "ffffffff" end
    return string.format("ff%02x%02x%02x", c.r * 255, c.g * 255, c.b * 255)
end

local function colored(token, text)
    return string.format("|c%s%s|r", class_color_hex(token), text or "?")
end

local function pct(num, denom)
    if not denom or denom == 0 then return "—" end
    return string.format("%.0f%%", 100 * num / denom)
end

local function format_time(ts)
    if not ts then return "—" end
    return date("%m/%d %H:%M", ts)
end

local function bg_short_name(zone)
    return T.bg_zones[zone or ""] or zone or "Unknown"
end

-- ============================================================================
-- Generic sortable table widget
--
-- Builds a header row of clickable buttons + a scrolling body of text rows.
-- Caller passes:
--   parent, x, y, w, h   - placement
--   columns              - array of { key, label, width, align?, cell? }
--                          cell(value, row) -> string (optional formatter)
--   get_rows()           - returns array of row tables
--   default_sort         - { key = "...", dir = "desc" } (optional)
--
-- Returns: a table with :Refresh() to rebuild after data changes.
-- ============================================================================
local function build_table(parent, x, y, w, h, columns, get_rows, default_sort)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(w, h)
    container:SetPoint("TOPLEFT", x, y)

    -- Header row
    local header = CreateFrame("Frame", nil, container)
    header:SetSize(w, HEADER_H)
    header:SetPoint("TOPLEFT", 0, 0)

    local sort_state = default_sort or { key = columns[1].key, dir = "desc" }
    local header_buttons = {}

    -- Body: scroll frame + content child
    local scroll = CreateFrame("ScrollFrame", nil, container, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -HEADER_H)
    scroll:SetSize(w - 24, h - HEADER_H)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(w - 24, 1)
    scroll:SetScrollChild(content)

    local row_pool = {}

    local function get_row(i)
        local r = row_pool[i]
        if r then return r end
        r = CreateFrame("Frame", nil, content)
        r:SetSize(w - 24, ROW_H)
        r:SetPoint("TOPLEFT", 0, -((i - 1) * ROW_H))
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0)
        r.cells = {}
        local x_off = 0
        for ci, col in ipairs(columns) do
            local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetSize(col.width - 4, ROW_H)
            fs:SetPoint("LEFT", x_off + 2, 0)
            fs:SetJustifyH(col.align or "LEFT")
            fs:SetJustifyV("MIDDLE")
            r.cells[ci] = fs

            -- Faint column divider matching the header
            if ci < #columns then
                local sep = r:CreateTexture(nil, "BORDER")
                sep:SetSize(1, ROW_H)
                sep:SetPoint("LEFT", x_off + col.width - 1, 0)
                sep:SetColorTexture(0.3, 0.3, 0.3, 0.4)
            end

            x_off = x_off + col.width
        end
        row_pool[i] = r
        return r
    end

    local function refresh()
        local rows = get_rows() or {}
        table.sort(rows, function(a, b)
            local av, bv = a[sort_state.key], b[sort_state.key]
            if type(av) == "string" or type(bv) == "string" then
                av = av ~= nil and tostring(av) or ""
                bv = bv ~= nil and tostring(bv) or ""
            else
                if av == nil then av = -math.huge end
                if bv == nil then bv = -math.huge end
            end
            if sort_state.dir == "desc" then return av > bv
            else return av < bv end
        end)

        -- Position after sort, for tabs that render a "#" column.
        for i, r in ipairs(rows) do r._idx = i end

        -- Rebuild header labels with sort indicator
        for ci, col in ipairs(columns) do
            local btn = header_buttons[ci]
            local indicator = ""
            if sort_state.key == col.key then
                indicator = sort_state.dir == "desc" and " v" or " ^"
            end
            btn.label_fs:SetText(col.label .. indicator)
        end

        -- Populate rows
        for i, row in ipairs(rows) do
            local rf = get_row(i)
            for ci, col in ipairs(columns) do
                local raw = row[col.key]
                local txt
                if col.cell then txt = col.cell(raw, row)
                else txt = tostring(raw or "") end
                rf.cells[ci]:SetText(txt)
            end

            -- Tint priority: your row highlight > faction tint > zebra stripe.
            -- Faction: 1 = Alliance (blue), 0 = Horde (red).
            if row._highlight then
                rf.bg:SetColorTexture(1.0, 0.85, 0.2, 0.22)  -- gold-ish for "you"
            elseif row._faction == 1 then
                rf.bg:SetColorTexture(0.2, 0.5, 1.0, 0.12)   -- blue Alliance
            elseif row._faction == 0 then
                rf.bg:SetColorTexture(1.0, 0.2, 0.2, 0.12)   -- red Horde
            elseif i % 2 == 0 then
                rf.bg:SetColorTexture(1, 1, 1, 0.04)
            else
                rf.bg:SetColorTexture(1, 1, 1, 0)
            end
            rf:Show()
        end
        for i = #rows + 1, #row_pool do row_pool[i]:Hide() end
        content:SetHeight(math.max(1, #rows * ROW_H))
    end

    -- Build header buttons. Headers must use the same sizing/positioning
    -- model as rows or columns visually drift apart.
    local x_off = 0
    for ci, col in ipairs(columns) do
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width, HEADER_H)
        btn:SetPoint("TOPLEFT", x_off, 0)

        local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetSize(col.width - 4, HEADER_H)
        fs:SetPoint("LEFT", 2, 0)
        fs:SetJustifyH(col.align or "LEFT")
        fs:SetJustifyV("MIDDLE")
        fs:SetText(col.label)
        btn.label_fs = fs

        local hl = btn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.1)

        -- Faint vertical divider on the right edge of each column (except last)
        if ci < #columns then
            local sep = btn:CreateTexture(nil, "OVERLAY")
            sep:SetSize(1, HEADER_H - 4)
            sep:SetPoint("RIGHT", 0, 0)
            sep:SetColorTexture(0.3, 0.3, 0.3, 0.6)
        end

        if col.tooltip then
            btn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(col.label, 1, 1, 1)
                GameTooltip:AddLine(col.tooltip, nil, nil, nil, true)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
        btn:SetScript("OnClick", function()
            if sort_state.key == col.key then
                sort_state.dir = (sort_state.dir == "desc") and "asc" or "desc"
            else
                sort_state.key, sort_state.dir = col.key, "desc"
            end
            refresh()
        end)
        header_buttons[ci] = btn
        x_off = x_off + col.width
    end

    -- Header underline
    local line = header:CreateTexture(nil, "OVERLAY")
    line:SetColorTexture(0.4, 0.4, 0.4, 1)
    line:SetSize(w, 1)
    line:SetPoint("BOTTOMLEFT", 0, 0)

    return { Refresh = refresh, container = container }
end

-- ============================================================================
-- Match Report popup
-- ============================================================================
-- A movable, dismissable window auto-shown on match end. Displays five lines
-- matching retail MongoMon's after-action report (minus flavor text). Also
-- offers a "Re-send to Chat" button that respects the standard cooldown.

local popup_frame

local function popup_compute_lines(match)
    -- Returns ordered array of 5 display strings.
    local me = UnitName("player")
    local mine = match.players[me]
    if not mine or not mine.faction then return nil end
    local my_faction = mine.faction

    local team_kills, team_deaths       = 0, 0
    local team_dmg, team_heal           = 0, 0
    local enemy_dmg, enemy_heal         = 0, 0
    local team_total_kills              = 0
    for _, p in pairs(match.players) do
        if p.faction == my_faction then
            team_kills  = team_kills  + (p.kills  or 0)
            team_deaths = team_deaths + (p.deaths or 0)
            team_dmg    = team_dmg    + (p.damage  or 0)
            team_heal   = team_heal   + (p.healing or 0)
            team_total_kills = team_total_kills + (p.kills or 0)
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
    local function pct_of(num, denom)
        if not denom or denom <= 0 then return "0" end
        return string.format("%.0f", num / denom * 100)
    end

    local lines = {}

    -- Line 1: team K/D summary
    table.insert(lines, string.format(
        "Your team went %d - %d.", team_kills, team_deaths))

    -- Line 2: damage comparison
    local dmg_pct = pct_diff(team_dmg, enemy_dmg)
    if dmg_pct then
        if team_dmg >= enemy_dmg then
            table.insert(lines, string.format(
                "Your team outdamaged the enemy by %s%%.", dmg_pct))
        else
            table.insert(lines, string.format(
                "The enemy outdamaged your team by %s%%.", dmg_pct))
        end
    end

    -- Line 3: healing comparison
    local heal_pct = pct_diff(team_heal, enemy_heal)
    if heal_pct then
        if team_heal >= enemy_heal then
            table.insert(lines, string.format(
                "Your team outhealed the enemy team by %s%%.", heal_pct))
        else
            table.insert(lines, string.format(
                "The enemy outhealed your team by %s%%.", heal_pct))
        end
    end

    -- Line 4: personal % contribution
    table.insert(lines, string.format(
        "You did %s%% of your team's damage, and accounted for %s%% of their killing blows.",
        pct_of(mine.damage or 0, team_dmg),
        pct_of(mine.kills  or 0, team_total_kills)))

    -- Line 5: personal healing %
    table.insert(lines, string.format(
        "You did %s%% of your team's healing.",
        pct_of(mine.healing or 0, team_heal)))

    return lines
end

local function popup_build()
    local f = CreateFrame("Frame", "BgStatMatchReportPopup", UIParent,
                          "BasicFrameTemplateWithInset")
    f:SetSize(440, 240)
    f:SetPoint("CENTER", 0, 100)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if BgStatUI then
            local point, _, rel_point, x, y = self:GetPoint()
            BgStatUI.popup_point     = point
            BgStatUI.popup_rel_point = rel_point
            BgStatUI.popup_x         = x
            BgStatUI.popup_y         = y
        end
    end)
    f:SetClampedToScreen(true)
    f.TitleText:SetText("BgStat — Match Report")
    f:Hide()

    -- Restore saved position
    if BgStatUI and BgStatUI.popup_point then
        f:ClearAllPoints()
        f:SetPoint(BgStatUI.popup_point, UIParent,
                   BgStatUI.popup_rel_point or BgStatUI.popup_point,
                   BgStatUI.popup_x or 0, BgStatUI.popup_y or 100)
    end

    f.subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.subtitle:SetPoint("TOPLEFT", 14, -28)
    f.subtitle:SetJustifyH("LEFT")

    f.body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.body:SetPoint("TOPLEFT", 14, -50)
    f.body:SetPoint("TOPRIGHT", -14, -50)
    f.body:SetJustifyH("LEFT")
    f.body:SetJustifyV("TOP")
    f.body:SetSpacing(4)

    local send_btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    send_btn:SetSize(140, 24)
    send_btn:SetText("Re-send to Chat")
    send_btn:SetPoint("BOTTOMRIGHT", -14, 10)
    send_btn:SetScript("OnClick", function()
        T.report.send_to_chat()
    end)
    f.send_btn = send_btn

    return f
end

function mod.show_match_popup(match)
    if not match then return end
    if match.winner == nil then return end   -- skip incomplete matches

    if not popup_frame then popup_frame = popup_build() end

    local lines = popup_compute_lines(match)
    if not lines or #lines == 0 then return end

    -- Header: BG name + result
    local me = UnitName("player")
    local mine = match.players[me]
    local result = ""
    if match.winner ~= nil and mine then
        result = (mine.faction == match.winner)
            and "|cff00ff00WIN|r" or "|cffff0000LOSS|r"
    end
    popup_frame.subtitle:SetText(string.format("%s — %s",
        bg_short_name(match.zone or "Unknown"), result))
    popup_frame.body:SetText(table.concat(lines, "\n\n"))

    popup_frame:Show()
end

function mod.hide_match_popup()
    if popup_frame then popup_frame:Hide() end
end

-- ============================================================================
-- Tab content: Last Match
-- ============================================================================

local last_match_table

local function build_last_match_tab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    frame.header = header

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    subtitle:SetPoint("TOPLEFT", 12, -32)
    frame.subtitle = subtitle

    local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText("No matches saved yet.\nFinish a battleground to see results here.")
    frame.empty = empty

    -- Faction filter buttons. Saved per-character.
    -- BgStatUI.faction_filter: "all" | "alliance" | "horde"
    local filter_buttons = {}
    local function set_filter(value)
        BgStatUI.faction_filter = value
        for v, btn in pairs(filter_buttons) do
            if v == value then
                btn:LockHighlight()
            else
                btn:UnlockHighlight()
            end
        end
        if last_match_table then last_match_table.Refresh() end
    end

    local function make_filter_btn(label, value, anchor_to)
        local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        btn:SetSize(80, 22)
        btn:SetText(label)
        if anchor_to then
            btn:SetPoint("LEFT", anchor_to, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPRIGHT", -12, -10)
        end
        btn:SetScript("OnClick", function() set_filter(value) end)
        filter_buttons[value] = btn
        return btn
    end

    -- Build right-to-left so [All] ends up rightmost as anchor
    local btn_horde    = make_filter_btn("Horde",    "horde")
    local btn_alliance = make_filter_btn("Alliance", "alliance")
    local btn_all      = make_filter_btn("All",      "all")
    -- Re-anchor so they appear left-to-right: All | Alliance | Horde
    btn_all:ClearAllPoints();      btn_all:SetPoint("TOPRIGHT", -260, -10)
    btn_alliance:ClearAllPoints(); btn_alliance:SetPoint("LEFT", btn_all, "RIGHT", 4, 0)
    btn_horde:ClearAllPoints();    btn_horde:SetPoint("LEFT", btn_alliance, "RIGHT", 4, 0)

    local columns = {
        { key = "_idx",    label = "#",        width = 28,  align = "CENTER",
          tooltip = "Row position under the current sort. Re-numbers whenever you change the sort column or direction." },
        { key = "name",    label = "Name",     width = 130,
          tooltip = "Player name (realm stripped). Gold row = you. Blue rows = Alliance, red rows = Horde." },
        { key = "class",   label = "Class",    width = 80,
          tooltip = "Class from the BG scoreboard, shown in its class color.",
          cell = function(c) return colored(c, c or "?") end },
        { key = "kills",   label = "K",        width = 40,  align = "CENTER",
          tooltip = "Killing blows this match, from the BG scoreboard." },
        { key = "deaths",  label = "D",        width = 40,  align = "CENTER",
          tooltip = "Deaths this match, from the BG scoreboard." },
        { key = "hks",     label = "HKs",      width = 50,  align = "CENTER",
          tooltip = "Honorable kills: enemy deaths this player or their nearby group was credited for. Always much higher than killing blows." },
        { key = "damage",  label = "Damage",   width = 90,  align = "CENTER",
          tooltip = "Total damage done this match, from the BG scoreboard.",
          cell = function(v) return fmt(v) end },
        { key = "healing", label = "Healing",  width = 90,  align = "CENTER",
          tooltip = "Total healing done this match, from the BG scoreboard.",
          cell = function(v) return fmt(v) end },
        { key = "honor",   label = "Honor",    width = 70,  align = "CENTER",
          tooltip = "Bonus honor from the BG scoreboard (objectives and win bonus). Does NOT include per-kill honor — your true total for the match is the honor line above the table, parsed from chat." },
    }

    local function get_rows()
        local match = T.history.get_last()
        if not match then return {} end
        local me = UnitName("player")
        local filter = (BgStatUI and BgStatUI.faction_filter) or "all"
        local rows = {}
        for name, p in pairs(match.players) do
            local include = (filter == "all")
                or (filter == "alliance" and p.faction == 1)
                or (filter == "horde"    and p.faction == 0)
            if include then
                table.insert(rows, {
                    name       = name,
                    class      = p.class,
                    kills      = p.kills or 0,
                    deaths     = p.deaths or 0,
                    hks        = p.honorable_kills or 0,
                    damage     = p.damage or 0,
                    healing    = p.healing or 0,
                    honor      = p.honor or 0,
                    _faction   = p.faction,
                    _highlight = (name == me),
                })
            end
        end
        return rows
    end

    last_match_table = build_table(frame, 12, -76, FRAME_W - 30, FRAME_H - 130,
        columns, get_rows, { key = "damage", dir = "desc" })

    function frame:Refresh()
        local match = T.history.get_last()
        if not match then
            header:SetText("Last Match")
            subtitle:SetText("")
            empty:Show()
            last_match_table.container:Hide()
            for _, b in pairs(filter_buttons) do b:Hide() end
            return
        end
        empty:Hide()
        last_match_table.container:Show()
        for _, b in pairs(filter_buttons) do b:Show() end

        -- Sync the highlighted button to the saved filter
        local current = (BgStatUI and BgStatUI.faction_filter) or "all"
        for v, btn in pairs(filter_buttons) do
            if v == current then btn:LockHighlight() else btn:UnlockHighlight() end
        end

        local me = UnitName("player")
        local mine = match.players[me]
        local result = "—"
        if match.winner ~= nil and mine then
            result = (mine.faction == match.winner) and "|cff00ff00WIN|r" or "|cffff0000LOSS|r"
        elseif match.winner == nil then
            result = "|cffaaaaaaINCOMPLETE|r"
        end
        header:SetText(string.format("Last Match: %s — %s",
            bg_short_name(match.zone), result))

        local your_line = "—"
        if mine then
            local honor_text = match.honor_capped and "honor capped" or string.format("%d honor gained", match.honor_delta or 0)
            your_line = string.format(
                "You: %d kills / %d deaths / %s damage / %s healing / %s",
                mine.kills or 0, mine.deaths or 0,
                fmt(mine.damage or 0), fmt(mine.healing or 0),
                honor_text)
        end
        subtitle:SetText(string.format("%s — %s\n%s",
            format_time(match.timestamp), match.zone or "?", your_line))
        last_match_table.Refresh()
    end

    return frame
end

-- ============================================================================
-- Tab content: History
-- ============================================================================

local history_table

local function build_history_tab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Battleground History")

    local totals_text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    totals_text:SetPoint("TOPLEFT", 12, -32)
    totals_text:SetJustifyH("LEFT")
    frame.totals_text = totals_text

    local columns = {
        { key = "zone",       label = "Battleground", width = 160,
          tooltip = "Battleground zone. One row per BG type across your saved history." },
        { key = "games",      label = "Games", width = 60,  align = "CENTER",
          tooltip = "Total saved matches in this battleground." },
        { key = "wins",       label = "W",     width = 40,  align = "CENTER",
          tooltip = "Matches where your faction won." },
        { key = "losses",     label = "L",     width = 40,  align = "CENTER",
          tooltip = "Matches where the enemy faction won." },
        { key = "incomplete", label = "Inc",   width = 40,  align = "CENTER",
          tooltip = "Matches with no recorded winner — you left or zoned out before the game resolved. Excluded from Win%." },
        { key = "win_pct",    label = "Win%",  width = 60,  align = "CENTER",
          tooltip = "Wins / (wins + losses). Incomplete matches don't count.",
          cell = function(v)
              if not v or v < 0 then return "—" end
              return string.format("%.0f%%", v)
          end },
        { key = "kills",      label = "Kills",  width = 70,  align = "CENTER",
          tooltip = "Your total killing blows across all saved matches in this BG." },
        { key = "deaths",     label = "Deaths", width = 70,  align = "CENTER",
          tooltip = "Your total deaths across all saved matches in this BG." },
        { key = "honor",      label = "Honor",  width = 90,  align = "CENTER",
          tooltip = "Your total honor earned in this BG, parsed from chat messages (includes per-kill, objective, and win-bonus honor).",
          cell = function(v) return fmt(v) end },
    }

    local function get_rows()
        local by_zone = T.history.summary_by_zone()
        local rows = {}
        for zone, r in pairs(by_zone) do
            table.insert(rows, {
                zone       = zone,
                games      = r.games,
                wins       = r.wins,
                losses     = r.losses,
                incomplete = r.incomplete,
                win_pct    = (r.wins + r.losses) > 0
                             and 100 * r.wins / (r.wins + r.losses) or -1,
                kills      = r.kills,
                deaths     = r.deaths,
                honor      = r.honor,
            })
        end
        return rows
    end

    history_table = build_table(frame, 12, -76, FRAME_W - 30, FRAME_H - 130,
        columns, get_rows, { key = "games", dir = "desc" })

    function frame:Refresh()
        local _, totals = T.history.summary_by_zone()
        local decided = totals.wins + totals.losses
        totals_text:SetText(string.format(
            "Career: %d games  |  %d W / %d L  (%s win rate)  |  %d kills / %d deaths  |  %s honor earned",
            totals.games, totals.wins, totals.losses,
            pct(totals.wins, decided),
            totals.kills, totals.deaths, fmt(totals.honor)))
        history_table.Refresh()
    end

    return frame
end

-- ============================================================================
-- Tab content: Classes
-- ============================================================================

local classes_table

local function build_classes_tab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Classes Seen Across All Matches")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 12, -32)
    sub:SetText("Aggregated from every saved match (both factions). Click a column to sort.")

    local columns = {
        { key = "class",        label = "Class",    width = 80,
          tooltip = "Class, aggregated across every player of that class you've ever seen (both factions, all saved matches). You are excluded from this tab.",
          cell = function(c) return colored(c, c or "?") end },
        { key = "appearances",  label = "Seen",     width = 50, align = "CENTER",
          tooltip = "Total appearances: each player of this class in each match counts once. The same person across 5 matches counts 5 times." },
        { key = "avg_damage",   label = "Dmg/P",    width = 75, align = "CENTER",
          tooltip = "Damage per participant: each appearance's damage divided by that match's player count, averaged across appearances. Normalizes 10-man WSG vs 40-man AV.",
          cell = function(v) return fmt(v) end },
        { key = "avg_healing",  label = "Heal/P",   width = 75, align = "CENTER",
          tooltip = "Healing per participant: each appearance's healing divided by that match's player count, averaged across appearances.",
          cell = function(v) return fmt(v) end },
        { key = "dmg_index",    label = "D-Idx",    width = 55, align = "CENTER",
          tooltip = "Damage index: damage vs the average player of the same match (damage / (match total / players)). 1.00 = exactly average, 2.00 = double. Comparable across BG sizes and durations.",
          cell = function(v) return string.format("%.2f", v or 0) end },
        { key = "heal_index",   label = "H-Idx",    width = 55, align = "CENTER",
          tooltip = "Healing index: healing vs the average player of the same match. 1.00 = match average.",
          cell = function(v) return string.format("%.2f", v or 0) end },
        { key = "kills",        label = "Total K",  width = 60, align = "CENTER",
          tooltip = "Total killing blows by this class across all appearances." },
        { key = "deaths",       label = "Total D",  width = 60, align = "CENTER",
          tooltip = "Total deaths by this class across all appearances." },
        { key = "kd_ratio",     label = "K/D",      width = 50, align = "CENTER",
          tooltip = "Total kills / total deaths (deaths floored at 1 to avoid division by zero).",
          cell = function(v) return string.format("%.2f", v or 0) end },
        { key = "best_value",   label = "Best (Index)", width = 165,
          tooltip = "Highest single-match damage index ever recorded for this class, and who did it. Sorts by the index value.",
          cell = function(_, row)
              if not row.best_player then return "—" end
              return string.format("%s (%.2fx)",
                  colored(row.class, row.best_player), row.best_value or 0)
          end },
    }

    local function get_rows()
        local stats = T.history.lifetime_class_stats()
        local rows = {}
        for class, r in pairs(stats) do
            table.insert(rows, {
                class       = class,
                appearances = r.appearances,
                kills       = r.kills,
                deaths      = r.deaths,
                kd_ratio    = (r.kills or 0) / math.max(r.deaths or 0, 1),
                avg_damage  = r.appearances > 0 and (r.dmg_per_head  / r.appearances) or 0,
                avg_healing = r.appearances > 0 and (r.heal_per_head / r.appearances) or 0,
                dmg_index   = r.dmg_index_n  > 0 and (r.dmg_index_sum  / r.dmg_index_n)  or 0,
                heal_index  = r.heal_index_n > 0 and (r.heal_index_sum / r.heal_index_n) or 0,
                best_player = r.best_index.name,
                best_value  = r.best_index.value,
            })
        end
        return rows
    end

    classes_table = build_table(frame, 12, -76, FRAME_W - 30, FRAME_H - 130,
        columns, get_rows, { key = "appearances", dir = "desc" })

    function frame:Refresh()
        classes_table.Refresh()
    end

    return frame
end

-- ============================================================================
-- Main window assembly
-- ============================================================================

local specs_table

local function build_specs_tab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Specs (friendlies only — auto-scanned)")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 12, -32)
    frame.sub = sub

    local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText("No matches with spec data yet.\nFinish a battleground to populate this tab.")
    frame.empty = empty

    -- Widths total 720 (table width is FRAME_W - 30 = 730, leaving 10px slack).
    local columns = {
        { key = "_idx",         label = "#",        width = 28,  align = "CENTER",
          tooltip = "Row position under the current sort. Re-numbers whenever you change the sort column or direction." },
        { key = "label",        label = "Spec + Class", width = 170,
          tooltip = "Dominant talent tree detected by the auto-scanner (friendly faction only, must have been within ~28 yards during a BG). Gold rows marked (YOU) are your own characters, tracked separately from the population.",
          cell = function(_, row)
              local spec = T.spec_scanner.spec_name(row.class, row.spec_tab) or "?"
              local base = string.format("%s %s", spec, colored(row.class, row.class or "?"))
              if row._is_self then base = base .. " (YOU)" end
              return base
          end },
        { key = "appearances",  label = "Seen",     width = 50, align = "CENTER",
          tooltip = "Total appearances of this class+spec: each scanned player in each match counts once." },
        { key = "avg_damage",   label = "Dmg/P",    width = 80, align = "CENTER",
          tooltip = "Damage per participant: each appearance's damage divided by that match's player count, averaged across appearances. Normalizes 10-man WSG vs 40-man AV.",
          cell = function(v) return fmt(v) end },
        { key = "avg_healing",  label = "Heal/P",   width = 80, align = "CENTER",
          tooltip = "Healing per participant: each appearance's healing divided by that match's player count, averaged across appearances.",
          cell = function(v) return fmt(v) end },
        { key = "dmg_index",    label = "D-Idx",    width = 55, align = "CENTER",
          tooltip = "Damage index: damage vs the average player of the same match (damage / (match total / players)). 1.00 = exactly average, 2.00 = double. Comparable across BG sizes and durations.",
          cell = function(v) return string.format("%.2f", v or 0) end },
        { key = "heal_index",   label = "H-Idx",    width = 55, align = "CENTER",
          tooltip = "Healing index: healing vs the average player of the same match. 1.00 = match average.",
          cell = function(v) return string.format("%.2f", v or 0) end },
        { key = "kills",        label = "Total K",  width = 70, align = "CENTER",
          tooltip = "Total killing blows by this class+spec across all appearances." },
        { key = "deaths",       label = "Total D",  width = 70, align = "CENTER",
          tooltip = "Total deaths by this class+spec across all appearances." },
        { key = "kd_ratio",     label = "K/D",      width = 50, align = "CENTER",
          tooltip = "Total kills / total deaths (deaths floored at 1 to avoid division by zero).",
          cell = function(v) return string.format("%.2f", v or 0) end },
    }

    local function get_rows()
        local stats, _, you = T.history.lifetime_spec_stats()
        local rows = {}

        -- Self rows: same shape as aggregated rows, with "(YOU)" suffix and
        -- _highlight set so build_table tints them gold via its existing logic.
        -- Inline placement so they sort naturally with the rest.
        for _, r in pairs(you or {}) do
            local spec = T.spec_scanner.spec_name(r.class, r.spec_tab) or "?"
            table.insert(rows, {
                class       = r.class,
                spec_tab    = r.spec_tab,
                label       = string.format("%s %s", spec, r.class or "?"),
                appearances = r.appearances,
                kills       = r.kills,
                deaths      = r.deaths,
                kd_ratio    = (r.kills or 0) / math.max(r.deaths or 0, 1),
                avg_damage  = r.appearances > 0 and (r.dmg_per_head  / r.appearances) or 0,
                avg_healing = r.appearances > 0 and (r.heal_per_head / r.appearances) or 0,
                dmg_index   = r.dmg_index_n  > 0 and (r.dmg_index_sum  / r.dmg_index_n)  or 0,
                heal_index  = r.heal_index_n > 0 and (r.heal_index_sum / r.heal_index_n) or 0,
                _highlight  = true,
                _is_self    = true,
            })
        end

        for _, r in pairs(stats) do
            table.insert(rows, {
                class       = r.class,
                spec_tab    = r.spec_tab,
                label       = (T.spec_scanner.spec_name(r.class, r.spec_tab) or "?")
                              .. " " .. (r.class or "?"),
                appearances = r.appearances,
                kills       = r.kills,
                deaths      = r.deaths,
                kd_ratio    = (r.kills or 0) / math.max(r.deaths or 0, 1),
                avg_damage  = r.appearances > 0 and (r.dmg_per_head  / r.appearances) or 0,
                avg_healing = r.appearances > 0 and (r.heal_per_head / r.appearances) or 0,
                dmg_index   = r.dmg_index_n  > 0 and (r.dmg_index_sum  / r.dmg_index_n)  or 0,
                heal_index  = r.heal_index_n > 0 and (r.heal_index_sum / r.heal_index_n) or 0,
            })
        end
        return rows
    end

    specs_table = build_table(frame, 12, -76, FRAME_W - 30, FRAME_H - 130,
        columns, get_rows, { key = "avg_damage", dir = "desc" })

    function frame:Refresh()
        local stats, count, you = T.history.lifetime_spec_stats()
        local has_any = next(stats) ~= nil or next(you or {}) ~= nil
        if not has_any then
            empty:Show()
            specs_table.container:Hide()
            sub:SetText("")
            return
        end
        empty:Hide()
        specs_table.container:Show()
        sub:SetText(string.format(
            "Aggregated from %d match%s with spec data. Click a column to sort.",
            count, count == 1 and "" or "es"))
        specs_table.Refresh()
    end

    return frame
end

-- ============================================================================
-- Tab content: Kills (your last 100 killing blows)
-- ============================================================================

local kills_table

local function build_kills_tab(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Your Killing Blows")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 12, -32)
    sub:SetText("Last 500 killing blows across saved matches. Older kills may lack damage/realm data.")

    local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText("No killing blows recorded yet.")
    frame.empty = empty

    local columns = {
        { key = "_idx",         label = "#",       width = 28,  align = "CENTER",
          tooltip = "Row position under the current sort. Re-numbers whenever you change the sort column or direction." },
        { key = "victim",       label = "Victim",  width = 160,
          tooltip = "Who you killed, including realm for cross-realm players. Kills saved before this feature show the short name only.",
          cell = function(v, row) return colored(row.victim_class, v or "?") end },
        { key = "victim_class", label = "Class",   width = 80,
          tooltip = "The victim's class, if the scoreboard had been read before the kill landed.",
          cell = function(c) return colored(c, c or "?") end },
        { key = "damage",       label = "Damage",  width = 80,  align = "CENTER",
          tooltip = "Damage of the hit that killed them (the killing blow itself, not your total damage on that target). Kills saved before this feature show a dash.",
          cell = function(v) return v and fmt(v) or "—" end },
        { key = "spell_name",   label = "Killed With", width = 160,
          tooltip = "The spell or melee swing that landed the killing blow." },
        { key = "zone",         label = "BG",      width = 60,  align = "CENTER",
          tooltip = "Which battleground the kill happened in.",
          cell = function(v) return bg_short_name(v) end },
        { key = "at",           label = "When",    width = 110, align = "CENTER",
          tooltip = "Date and time of the kill. Kills saved before this feature fall back to the match's end time.",
          cell = function(v) return format_time(v) end },
    }

    local function get_rows()
        return T.history.recent_kills(500)
    end

    kills_table = build_table(frame, 12, -56, FRAME_W - 30, FRAME_H - 110,
        columns, get_rows, { key = "at", dir = "desc" })

    function frame:Refresh()
        local rows = T.history.recent_kills(1)
        if #rows == 0 then
            empty:Show()
            kills_table.container:Hide()
            return
        end
        empty:Hide()
        kills_table.container:Show()
        kills_table.Refresh()
    end

    return frame
end

-- ============================================================================
-- Tab content: Trends (4 stacked line charts, you vs team average)
-- ============================================================================

local TREND_METRICS = {
    { key = "kills",   avg = "avg_kills",   label = "Kills",   r = 1,    g = 1,    b = 0    },
    { key = "deaths",  avg = "avg_deaths",  label = "Deaths",  r = 1,    g = 0,    b = 0    },
    { key = "damage",  avg = "avg_damage",  label = "Damage",  r = 1,    g = 0.5,  b = 0    },
    { key = "healing", avg = "avg_healing", label = "Healing", r = 0.25, g = 1,    b = 0.25 },
}

local function build_trends_tab(frame_parent)
    local frame = CreateFrame("Frame", nil, frame_parent)
    frame:SetAllPoints()

    local header = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetPoint("TOPLEFT", 12, -10)
    header:SetText("Trends — You vs Team Average")

    local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    sub:SetPoint("TOPLEFT", 12, -32)

    local empty = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    empty:SetPoint("CENTER", 0, 0)
    empty:SetText("Need at least 2 saved matches on this character\nto draw trend lines.")
    frame.empty = empty

    -- Layout: 2x2 grid (Kills | Deaths / Damage | Healing). Clicking a
    -- chart expands it over the full plot area; clicking again restores.
    local Y_LABEL_W  = 46
    local TITLE_H    = 12
    local PANEL_GAP  = 10
    local cell_w     = math.floor((FRAME_W - 30 - PANEL_GAP) / 2)
    local grid_w     = cell_w - Y_LABEL_W
    local GRID_H     = 150
    local top_off    = -52
    local full_w     = FRAME_W - 30 - Y_LABEL_W
    local full_h     = 2 * GRID_H + PANEL_GAP + TITLE_H

    local panels   = {}
    local expanded = nil   -- panel currently maximized, or nil

    for pi, metric in ipairs(TREND_METRICS) do
        local panel = { metric = metric, row = math.floor((pi - 1) / 2), col = (pi - 1) % 2 }

        panel.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        panel.title:SetText(metric.label)
        panel.title:SetTextColor(metric.r, metric.g, metric.b)

        panel.plot = CreateFrame("Frame", nil, frame)

        local bg = panel.plot:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)

        panel.grid_lines, panel.grid_labels = {}, {}
        for gi = 0, 4 do
            local gl = panel.plot:CreateTexture(nil, "BORDER")
            gl:SetColorTexture(0.4, 0.4, 0.4, gi == 0 and 0.8 or 0.25)
            panel.grid_lines[gi] = gl
            local fs = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetJustifyH("RIGHT")
            panel.grid_labels[gi] = fs
        end

        panel.you_lines, panel.avg_lines, panel.hovers = {}, {}, {}
        panels[pi] = panel
    end

    -- Position one panel's title, plot, gridlines, and labels for a given
    -- geometry. Called for both grid cells and the expanded layout.
    local function layout_panel(panel, x, y, w, h)
        panel.w, panel.h = w, h
        panel.title:ClearAllPoints()
        panel.title:SetPoint("TOPLEFT", x, y)
        panel.plot:SetSize(w, h)
        panel.plot:ClearAllPoints()
        panel.plot:SetPoint("TOPLEFT", x, y - TITLE_H)
        for gi = 0, 4 do
            local frac = gi / 4
            panel.grid_lines[gi]:SetSize(w, 1)
            panel.grid_lines[gi]:ClearAllPoints()
            panel.grid_lines[gi]:SetPoint("BOTTOMLEFT", 0, (h - 1) * frac)
            panel.grid_labels[gi]:ClearAllPoints()
            panel.grid_labels[gi]:SetPoint("RIGHT", panel.plot, "BOTTOMLEFT", -4, (h - 1) * frac)
        end
    end

    local function set_panel_shown(panel, shown)
        if shown then panel.title:Show(); panel.plot:Show()
        else panel.title:Hide(); panel.plot:Hide() end
        for gi = 0, 4 do
            if shown then panel.grid_labels[gi]:Show()
            else panel.grid_labels[gi]:Hide() end
        end
    end

    local draw   -- forward declaration; toggle needs it

    local function apply_layout()
        if expanded then
            for _, panel in ipairs(panels) do
                set_panel_shown(panel, panel == expanded)
            end
            layout_panel(expanded, 12 + Y_LABEL_W, top_off, full_w, full_h)
        else
            for _, panel in ipairs(panels) do
                set_panel_shown(panel, true)
                local x = 12 + panel.col * (cell_w + PANEL_GAP) + Y_LABEL_W
                local y = top_off - panel.row * (TITLE_H + GRID_H + PANEL_GAP)
                layout_panel(panel, x, y, grid_w, GRID_H)
            end
        end
        draw()
    end

    local function toggle_expand(panel)
        if expanded == panel then
            expanded = nil
        else
            expanded = panel
        end
        apply_layout()
    end

    local function get_line(panel, pool, i, r, g, b, a)
        local l = pool[i]
        if not l then
            l = panel.plot:CreateLine(nil, "ARTWORK")
            l:SetThickness(0.7)
            l:SetColorTexture(r, g, b, a)
            pool[i] = l
        end
        return l
    end

    local function get_hover(panel, i)
        local h = panel.hovers[i]
        if not h then
            h = CreateFrame("Frame", nil, panel.plot)
            h:EnableMouse(true)
            h:SetScript("OnLeave", function() GameTooltip:Hide() end)
            h:SetScript("OnMouseDown", function() toggle_expand(panel) end)
            panel.hovers[i] = h
        end
        return h
    end

    local function draw_panel(panel, data)
        local metric = panel.metric
        local max_v = 1
        for _, d in ipairs(data) do
            if d[metric.key] > max_v then max_v = d[metric.key] end
            if d[metric.avg] > max_v then max_v = d[metric.avg] end
        end
        for gi = 0, 4 do
            panel.grid_labels[gi]:SetText(fmt(max_v * gi / 4))
        end

        local n = #data
        local spacing = panel.w / (n - 1)
        local function px(i) return (i - 1) * spacing end
        local function py(v) return (v / max_v) * (panel.h - 1) end

        for i = 1, n - 1 do
            local a, b = data[i], data[i + 1]
                        local l1 = get_line(panel, panel.you_lines, i, metric.r, metric.g, metric.b, 0.7)
            l1:SetStartPoint("BOTTOMLEFT", panel.plot, px(i),     py(a[metric.key]))
            l1:SetEndPoint("BOTTOMLEFT",   panel.plot, px(i + 1), py(b[metric.key]))
            l1:Show()
            local l2 = get_line(panel, panel.avg_lines, i, 0.6, 0.6, 0.6, 0.9)
            l2:SetStartPoint("BOTTOMLEFT", panel.plot, px(i),     py(a[metric.avg]))
            l2:SetEndPoint("BOTTOMLEFT",   panel.plot, px(i + 1), py(b[metric.avg]))
            l2:Show()
        end
        for i = n, #panel.you_lines do panel.you_lines[i]:Hide() end
        for i = n, #panel.avg_lines do panel.avg_lines[i]:Hide() end

        for i = 1, n do
            local d = data[i]
            local h = get_hover(panel, i)
            h:SetSize(math.max(spacing, 8), panel.h)
            h:ClearAllPoints()
            h:SetPoint("BOTTOMLEFT", px(i) - spacing / 2, 0)
            h:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                local result = d.win == nil and "|cffaaaaaaINCOMPLETE|r"
                    or (d.win and "|cff00ff00WIN|r" or "|cffff0000LOSS|r")
                GameTooltip:SetText(string.format("%s — %s",
                    bg_short_name(d.zone), result), 1, 1, 1)
                GameTooltip:AddLine(format_time(d.at), 0.8, 0.8, 0.8)
                GameTooltip:AddDoubleLine("Your " .. metric.label:lower() .. ":",
                    fmt(d[metric.key]), metric.r, metric.g, metric.b, 1, 1, 1)
                GameTooltip:AddDoubleLine("Team avg:",
                    fmt(d[metric.avg]), 0.6, 0.6, 0.6, 1, 1, 1)
                GameTooltip:Show()
            end)
            h:Show()
        end
        for i = n + 1, #panel.hovers do panel.hovers[i]:Hide() end
    end

    draw = function()
        local data = T.history.trend_series(T.max_history)
        sub:SetText(string.format(
            "Colored — you   |cff999999— team avg|r   (up to %d matches; click a chart to expand)",
            T.max_history))
        if #data < 2 then
            empty:Show()
            for _, panel in ipairs(panels) do set_panel_shown(panel, false) end
            return
        end
        empty:Hide()
        for _, panel in ipairs(panels) do
            if not expanded or panel == expanded then
                draw_panel(panel, data)
            end
        end
    end

    function frame:Refresh()
        apply_layout()
    end

    return frame
end

local function show_tab(idx)
    active_tab = idx
    for i, tab in ipairs(tabs) do
        if i == idx then
            content_frames[i]:Show()
            PanelTemplates_SelectTab(tab)
        else
            content_frames[i]:Hide()
            PanelTemplates_DeselectTab(tab)
        end
    end
    if content_frames[idx] and content_frames[idx].Refresh then
        content_frames[idx]:Refresh()
    end
end

local function build_main_frame()
    if main_frame then return main_frame end

    local f = CreateFrame("Frame", "BgStatMainFrame", UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        if BgStatUI then
            local point, _, rel_point, x, y = self:GetPoint()
            BgStatUI.point     = point
            BgStatUI.rel_point = rel_point
            BgStatUI.x         = x
            BgStatUI.y         = y
        end
    end)
    f:SetClampedToScreen(true)
    f.TitleText:SetText("BgStat")
    f:Hide()

    -- Restore saved position
    if BgStatUI and BgStatUI.point then
        f:ClearAllPoints()
        f:SetPoint(BgStatUI.point, UIParent, BgStatUI.rel_point,
                   BgStatUI.x, BgStatUI.y)
    end

    local content_parent = CreateFrame("Frame", nil, f)
    content_parent:SetPoint("TOPLEFT", 4, -28)
    content_parent:SetPoint("BOTTOMRIGHT", -4, 4)

    content_frames[1] = build_last_match_tab(content_parent)
    content_frames[2] = build_history_tab(content_parent)
    content_frames[3] = build_classes_tab(content_parent)
    content_frames[4] = build_specs_tab(content_parent)
    content_frames[5] = build_kills_tab(content_parent)
    content_frames[6] = build_trends_tab(content_parent)

    -- Build tabs at the bottom of the main frame
    local tab_names = { "Last Match", "History", "Classes", "Specs", "Kills", "Trends" }
    for i, name in ipairs(tab_names) do
        local tab = CreateFrame("Button", "BgStatTab" .. i, f, "CharacterFrameTabButtonTemplate")
        tab:SetID(i)
        tab:SetText(name)
        tab:SetScript("OnClick", function() show_tab(i) end)
        if i == 1 then
            tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 8, 2)
        else
            tab:SetPoint("LEFT", tabs[i - 1], "RIGHT", -16, 0)
        end
        PanelTemplates_TabResize(tab, 0)
        tabs[i] = tab
    end
    PanelTemplates_SetNumTabs(f, 6)

    main_frame = f
    show_tab(1)
    return f
end

-- ============================================================================
-- Public API
-- ============================================================================

function mod.show(tab_index)
    if not BgStatUI then BgStatUI = {} end
    local f = build_main_frame()
    f:Show()
    show_tab(tab_index or active_tab)
end

function mod.hide()
    if main_frame then main_frame:Hide() end
end

function mod.toggle(tab_index)
    if main_frame and main_frame:IsShown() then
        main_frame:Hide()
    else
        mod.show(tab_index)
    end
end

function mod.refresh_active()
    if main_frame and main_frame:IsShown() and content_frames[active_tab]
       and content_frames[active_tab].Refresh then
        content_frames[active_tab]:Refresh()
    end
end