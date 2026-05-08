local _, T = ...

local mod = {}
T.nameplates = mod

local plate_to_unit = {}
local overlays      = {}

local function is_eligible(unit)
    if not unit then return false end
    if UnitIsUnit(unit, "player") then return false end
    if not UnitIsPlayer(unit) then return false end
    if not UnitCanAttack("player", unit) then return false end
    return true
end

local function build_text(name)
    local p = T.combat_log.get_player(name)
    if not p then return nil end
    local k, d = p.kills or 0, p.deaths or 0
    if k == 0 and d == 0 then return nil end
    return string.format("|cffffff00%d|r/|cffff0000%d|r", k, d)
end

local function attach(plate, unit)
    local name = UnitName(unit)
    if not name then return end

    local fs = overlays[plate]
    if not fs then
        fs = plate:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("BOTTOM", plate, "TOP", 0, 4)
        overlays[plate] = fs
    end

    local txt = build_text(name)
    if txt then fs:SetText(txt); fs:Show()
    else fs:Hide() end
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
    if overlays[plate] then overlays[plate]:Hide() end
end

function mod.refresh_all()
    for plate, unit in pairs(plate_to_unit) do
        attach(plate, unit)
    end
end

function mod.clear_all()
    for plate, fs in pairs(overlays) do fs:Hide() end
    wipe(plate_to_unit)
end
