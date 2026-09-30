local _, T = ...

local mod = {}
T.scoreboard = mod

-- Retail's scoreboard names the spec outright (PVPScoreInfo.talentSpec, a
-- localized string such as "Frost"), so the value saved in `spec_tab` IS the
-- display name. Anniversary saves a talent-tab index in the same field and maps
-- it through SpecScanner. One field, one History aggregation, two meanings --
-- the two flavors never share a SavedVariables file.
T.spec_name = function(_, spec) return spec end

-- C_PvP.GetScoreInfo is flagged SecretInActivePvPMatch: while the PvPMatch
-- addon restriction is up, every field of PVPScoreInfo except name / faction /
-- raceName / className / classToken comes back as a secret value, and a secret
-- can't be compared, added, or written to SavedVariables.
-- Source: Blizzard_APIDocumentationGenerated/PvpInfoDocumentation.lua (12.1),
--         SecretPredicatesDocumentation.lua ("SecretInActivePvPMatch").
--
-- So there is no live scoreboard on retail. read() is called after
-- PVP_MATCH_COMPLETE and either fills the store with plain numbers and returns
-- true, or touches nothing and returns false so the caller can wait for the
-- next UPDATE_BATTLEFIELD_SCORE.
--
-- GetNumBattlefieldScores is not in the generated docs but is still what
-- Blizzard's own scoreboard iterates with (12.1 Blizzard_PVPMatch/PVPMatchUtil.lua).
function mod.read()
    local n = GetNumBattlefieldScores()
    local first = n > 0 and C_PvP.GetScoreInfo(1)
    if not first or issecretvalue(first.damageDone) then return false end

    for i = 1, n do
        local s = C_PvP.GetScoreInfo(i)
        if s then
            -- Retail BGs are fully cross-realm, so the key keeps its -Realm
            -- suffix (two "Bob"s in one match is normal). Your own row is
            -- matched by GUID and filed under T.me() so every
            -- `players[T.me()]` lookup in History/UI/Report finds it.
            local name = (s.guid == T.my_guid) and T.me() or s.name
            T.store.set_player(name, {
                name            = name,
                class           = s.classToken,
                faction         = s.faction,
                kills           = s.killingBlows,
                deaths          = s.deaths,
                honor           = s.honorGained,
                honorable_kills = s.honorableKills,
                damage          = s.damageDone,
                healing         = s.healingDone,
                spec_tab        = s.talentSpec ~= "" and s.talentSpec or nil,
            })
        end
    end
    return true
end
