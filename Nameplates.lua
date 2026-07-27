local _, T = ...

local mod = {}
T.nameplates = mod

local plate_to_unit = {}
local overlays      = {}   -- plate -> { kd = FontString, rank = FontString }

local function is_eligible(unit)
    if not unit then return false end
    if UnitIsUnit(unit, "player") then return false end
    if not UnitIsPlayer(unit) then return false end
    return true
end

-- Enemy/friendly gating lives here rather than in is_eligible so both plate
-- types stay registered in plate_to_unit. Gating at registration time would
-- mean toggling the option only took effect after a re-zone, since
-- NAME_PLATE_UNIT_ADDED has already fired for every plate on screen.
local function should_show(unit)
    if UnitCanAttack("player", unit) then return T.nameplate_enemy end
    return T.nameplate_friendly
end

local function build_kd_text(p)
    local k, d = p.kills or 0, p.deaths or 0
    if k == 0 and d == 0 then return nil end
    return string.format("|cffffff00%d|r/|cffff0000%d|r", k, d)
end

local function build_rank_text(p)
    if not p.rank_kills then return nil end
    return string.format(
        "|cffffff00K%d|r |cffff8000Dmg%d|r |cffff0000D%d|r |cff40ff40H%d|r",
        p.rank_kills, p.rank_damage, p.rank_deaths, p.rank_healing)
end

local function get_overlay(plate)
    local o = overlays[plate]
    if o then return o end
    o = {}
    o.kd = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.kd:SetPoint("BOTTOM", plate, "TOP", 0, 4)
    o.rank = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    o.rank:SetPoint("TOPRIGHT", plate, "BOTTOMRIGHT", 0, -2)
    o.rank:SetJustifyH("RIGHT")
    overlays[plate] = o
    return o
end

local function hide(o)
    o.kd:Hide()
    o.rank:Hide()
end

local function attach(plate, unit)
    local o = get_overlay(plate)
    if not should_show(unit) then hide(o); return end

    local name = UnitName(unit)
    local p = name and T.combat_log.get_player(name)
    if not p then hide(o); return end

    local kd = build_kd_text(p)
    if kd then o.kd:SetText(kd); o.kd:Show() else o.kd:Hide() end

    local rank = build_rank_text(p)
    if rank then o.rank:SetText(rank); o.rank:Show() else o.rank:Hide() end
end

function mod.on_unit_added(unit)
    if not is_eligible(unit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    plate_to_unit[plate] = unit
    attach(plate, unit)
end

function mod.on_unit_removed(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    plate_to_unit[plate] = nil
    if overlays[plate] then hide(overlays[plate]) end
end

function mod.refresh_all()
    for plate, unit in pairs(plate_to_unit) do
        attach(plate, unit)
    end
end

function mod.clear_all()
    for _, o in pairs(overlays) do hide(o) end
    wipe(plate_to_unit)
end