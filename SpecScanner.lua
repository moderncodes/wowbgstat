local _, T = ...

local mod = {}
T.spec_scanner = mod

-- ============================================================================
-- Class -> tab index -> spec name. Static map for TBC (no dual-spec).
-- ============================================================================
local SPEC_NAMES = {
    DRUID   = { "Balance",       "Feral",         "Restoration" },
    HUNTER  = { "Beast Mastery", "Marksmanship",  "Survival"    },
    MAGE    = { "Arcane",        "Fire",          "Frost"       },
    PALADIN = { "Holy",          "Protection",    "Retribution" },
    PRIEST  = { "Discipline",    "Holy",          "Shadow"      },
    ROGUE   = { "Assassination", "Combat",        "Subtlety"    },
    SHAMAN  = { "Elemental",     "Enhancement",   "Restoration" },
    WARLOCK = { "Affliction",    "Demonology",    "Destruction" },
    WARRIOR = { "Arms",          "Fury",          "Protection"  },
}

function mod.spec_name(class_token, tab_index)
    if not class_token or not tab_index then return nil end
    local list = SPEC_NAMES[class_token]
    return list and list[tab_index] or nil
end

-- ============================================================================
-- Scanner state
-- ============================================================================
local scanner_frame
local enabled         = true
local pending_unit    = nil   -- name we last issued NotifyInspect for
local pending_started = 0     -- GetTime() when we issued
local INSPECT_TIMEOUT = 3     -- seconds before giving up on a target
local SCAN_INTERVAL   = 2     -- seconds between scans

-- Map name -> { tab_index, points } once detected. Cleared on match start.
local detected = {}
local attempted = {}    -- name -> true once we've tried (success OR failure)
local recently_failed = {}    -- name -> GetTime() of last failed inspect
local FAILURE_COOLDOWN = 10   -- seconds before retrying a failed inspect

-- Friendly-unit iteration: in a BG you're auto-grouped. raid1..raid40
-- covers your entire team. party1..party4 is fallback for very small groups.
local function iter_friendly_units()
    local units = {}
    local n = GetNumGroupMembers and GetNumGroupMembers() or 0
    if IsInRaid and IsInRaid() then
        for i = 1, n do table.insert(units, "raid" .. i) end
    else
        for i = 1, n - 1 do table.insert(units, "party" .. i) end
    end
    return units
end

local function unit_name_short(unit)
    local name = UnitName(unit)
    if not name then return nil end
    return (name:match("^([^%-]+)")) or name
end

-- Pick the next friendly we can inspect and don't yet have spec for.
local function pick_target()
    for _, unit in ipairs(iter_friendly_units()) do
        if not UnitIsUnit(unit, "player")
           and UnitExists(unit) and UnitIsConnected(unit) and CanInspect(unit) then
            -- UnitIsVisible(unit) returns true when the unit is rendered in
            -- your view, roughly equivalent to inspect range (~30 yards).
            -- We use it instead of CheckInteractDistance, which is protected
            -- in BG instances on TBC Anniversary 2.5.5 and produces
            -- ADDON_ACTION_BLOCKED Lua errors.
            -- Source: https://wowpedia.fandom.com/wiki/API_UnitIsVisible
            if UnitIsVisible(unit) then
                local name = unit_name_short(unit)
                if name and not detected[name] and not attempted[name] then
                    return unit, name
                end
            end
        end
    end
    return nil, nil
end

local function clear_pending()
    pending_unit, pending_started = nil, 0
end

local function tick()
    if not enabled then return end
    if not T.combat_log then return end

    if pending_unit and (GetTime() - pending_started) > INSPECT_TIMEOUT then
        clear_pending()
    end

    if pending_unit then return end

    local unit, name = pick_target()
    if not unit then return end

    attempted[name] = true   -- Mark BEFORE the call. Never retry, even on failure.
    pending_unit, pending_started = name, GetTime()
    NotifyInspect(unit)
end

-- INSPECT_READY fires with the inspected target's GUID on TBC Anniversary.
-- Source: https://wowpedia.fandom.com/wiki/INSPECT_READY (event renamed from
-- INSPECT_TALENT_READY in patch 5.0.4 and applies to Anniversary's modern engine).
local function on_inspect_ready(guid)
    if not pending_unit or not guid then return end

    local pending_guid
    for _, unit in ipairs(iter_friendly_units()) do
        if unit_name_short(unit) == pending_unit then
            pending_guid = UnitGUID(unit)
            break
        end
    end

    if pending_guid ~= guid then
        clear_pending()
        return
    end

    local best_tab, best_points = nil, -1
    for tab = 1, 3 do
        local _, _, _, _, points_spent = GetTalentTabInfo(tab, true)
        points_spent = points_spent or 0
        if type(points_spent) ~= "number" then points_spent = 0 end
        if points_spent > best_points then
            best_tab, best_points = tab, points_spent
        end
    end

    if best_points > 0 then
        detected[pending_unit] = { tab = best_tab, points = best_points }
        local p = T.combat_log.get_player(pending_unit)
        if p then
            p.spec_class = p.class
            p.spec_tab   = best_tab
        else
            mod._pending_specs = mod._pending_specs or {}
            mod._pending_specs[pending_unit] = best_tab
        end
    end

    clear_pending()
    if ClearInspectPlayer then ClearInspectPlayer() end
end

-- ============================================================================
-- Public API
-- ============================================================================

function mod.merge_pending_into_player(name)
    -- Called from Scoreboard.refresh after it inserts a player record.
    if not mod._pending_specs then return end
    local tab = mod._pending_specs[name]
    if not tab then return end
    local p = T.combat_log.get_player(name)
    if p then
        p.spec_class = p.class
        p.spec_tab   = tab
        mod._pending_specs[name] = nil
    end
end

function mod.start()
    if not enabled then return end
    wipe(detected)
    wipe(attempted)
    if mod._pending_specs then wipe(mod._pending_specs) end
    clear_pending()

    if not scanner_frame then
        scanner_frame = CreateFrame("Frame")
        scanner_frame:RegisterEvent("INSPECT_READY")
        scanner_frame:SetScript("OnEvent", function(self, event, guid)
            on_inspect_ready(guid)
        end)
    end

    scanner_frame.elapsed = 0
    scanner_frame:SetScript("OnUpdate", function(self, e)
        self.elapsed = self.elapsed + e
        if self.elapsed >= SCAN_INTERVAL then
            self.elapsed = 0
            tick()
        end
    end)
end

function mod.stop()
    if scanner_frame then
        scanner_frame:SetScript("OnUpdate", nil)
    end
    clear_pending()
end

function mod.set_enabled(v)
    enabled = v
    if not v then mod.stop() end
end

function mod.is_enabled() return enabled end

function mod.get_detected_count()
    local c = 0
    for _ in pairs(detected) do c = c + 1 end
    return c
end