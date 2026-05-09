---
name: tbc-anniversary-addon
description: Build and modify WoW addons targeting TBC Anniversary 2.5.5 (build 67157). This is NOT TBC Classic 2021 and NOT retail. The Anniversary client uses a hybrid engine — modern features like C_NamePlate, C_Timer, C_AddOns coexist with Vanilla/TBC-era API signatures (e.g. GetBattlefieldScore returns the 12-slot Vanilla layout, not the 16-slot retail layout). Use this skill when writing or debugging any Lua, .toc, or SavedVariables code for the Anniversary client. Primary project using this skill: bgstat (https://github.com/moderncodes/wowbgstat).
---

# TBC Anniversary Addon Development

## Hard facts about the environment

These are verified from primary sources. Do not assume retail behavior.

### Client identifiers
- **Folder**: `_anniversary_` (NOT `_classic_`, NOT `_classic_era_`, NOT `_retail_`)
- **Build**: 2.5.5.67157, released February 5, 2026
- **Interface version (TOC)**: `20505`
- **Engine**: Modern retail-derived engine running TBC content. Many APIs migrated to namespaced versions.

### Addon naming conventions
- **Folder name and TOC filename must match exactly**, including case, for the client to recognize the addon. Source: https://wowpedia.fandom.com/wiki/TOC_format ("The .toc file and addon folder name need to match"). `MyAddOn/` → `MyAddOn.toc`. A mismatched TOC is silently ignored.
- **Folder name shows in `Interface/AddOns/` and is the default in-game display name.** Override the in-game display via the `## Title:` TOC directive — it can differ from folder casing (e.g. folder `BgStat` with `## Title: bgstat` shows lowercase in the AddOns list).
- **Addon name lookups in WoW APIs are case-insensitive** (`EnableAddOn`, `IsAddOnLoaded`, `LoadAddOn`, etc.), so case in API call sites doesn't matter — only the filesystem match does. Source: https://wowpedia.fandom.com/wiki/API_EnableAddOn
- **Slash command identifiers** follow `SLASH_NAME1`, `SLASH_NAME2`, etc. globals; `SlashCmdList.NAME` for the handler. The `NAME` part is uppercase by convention (it's a Lua global). The slash text itself (`"/foo"`) is conventionally lowercase. Slash text matching at runtime is case-insensitive.
- **Convention across the WoW addon ecosystem is PascalCase folder names** (`WeakAuras`, `Details`, `BigWigs`, `ElvUI`, `HonorSpy`). All-lowercase folders work but stand out. SavedVariables identifiers conventionally match the folder casing (`BgStatDB`, not `bgstat_db`), even when internal Lua locals follow snake_case.
- **Texture/sound paths are filesystem paths** that must match the folder name exactly: `Interface\\AddOns\\BgStat\\Res\\Foo.blp`. After a rename, every such string in `Config.lua` (and elsewhere) must be updated or the texture silently fails to load.

### API namespace migrations (Anniversary-specific)
Functions that exist as globals on retail/older clients but moved to `C_*` namespaces on Anniversary:
- `GetAddOnMetadata(name, key)` → **`C_AddOns.GetAddOnMetadata(name, key)`** (global is nil)
- `InterfaceOptions_AddCategory` → migrated to `Settings` API
- Container functions migrated to `C_Container`
- Quest gossip via `C_GossipInfo.GetAvailableQuests`

If a global is `nil`, check for the `C_*` equivalent before assuming the function doesn't exist.

### Combat log (modern style)
- `COMBAT_LOG_EVENT_UNFILTERED` carries **no payload**.
- Read data via `CombatLogGetCurrentEventInfo()` (post-8.0.1 signature).
- This is unchanged from retail.

### Nameplates
- `C_NamePlate.GetNamePlateForUnit(unit)` works.
- `NAME_PLATE_UNIT_ADDED` and `NAME_PLATE_UNIT_REMOVED` events fire.
- The **personal nameplate exists** (Legion-era feature). Filter `unit == "player"` or `UnitIsUnit(unit, "player")` to skip it.
- Always also filter for `UnitIsPlayer(unit)` and `UnitCanAttack("player", unit)` if you only want enemy player nameplates.

### Inspect system
- Event is **`INSPECT_READY`** (NOT `INSPECT_TALENT_READY`). Source: Examiner addon changelog.
- Event payload: `(guid)` — the inspected target's GUID.
- Function: `NotifyInspect(unit)` → wait for event → call `GetTalentTabInfo(tab, true)`.
- Range gate: `CheckInteractDistance(unit, 1)` returns true within ~28 yards.
- Without range gate, `NotifyInspect` produces "out of range" voice spam on failures.
- Inspect lock is **global** — only one outstanding inspect at a time. Other addons can compete for it.
- Inspect can fail silently (no `INSPECT_READY` ever fires). Always implement a 3-second timeout.

### `GetTalentTabInfo(tabIndex, isInspect)` return signature
Documented at: https://wowpedia.fandom.com/wiki/API_GetTalentTabInfo

Returns: `id, name, description, icon, pointsSpent, background, previewPointsSpent, isUnlocked`

**Position 5 is `pointsSpent`** (the integer). Position 3 is `description` (a string). Reading the wrong position causes "attempt to compare number with string" errors when used with arithmetic.

```lua
-- CORRECT
local _, _, _, _, points_spent = GetTalentTabInfo(tab, true)

-- WRONG (reads description as if it were points)
local _, _, points = GetTalentTabInfo(tab, true)
```

### `GetBattlefieldScore(index)` return signature on Anniversary
**This is the Vanilla/TBC layout, NOT retail.** Source: https://vanilla-wow-archive.fandom.com/wiki/API_GetBattlefieldScore

Returns 12 values:
1. `name` (string, may include realm "Name-Realm")
2. `killingBlows` (number)
3. `honorKills` (number)
4. `deaths` (number)
5. `honorGained` (number — bonus honor only, NOT total honor; see honor section)
6. `faction` (number — 0 = Horde, 1 = Alliance)
7. **`rank`** (number — does NOT exist in retail's signature; this is the slot retail uses for `race`)
8. `race` (string — e.g. "Human", "Orc")
9. `class` (string — localized, e.g. "Warlock", "Druid")
10. `filename` / `classToken` (string — uppercase, e.g. "WARLOCK", "DRUID")
11. `damageDone` (number)
12. `healingDone` (number)

```lua
-- CORRECT for Anniversary
local name, kills, hks, deaths, honor, faction,
      _rank, _race, _class_loc, class_token,
      damage, healing = GetBattlefieldScore(i)

-- WRONG (retail layout — produces damage="WARLOCK", healing=damage_value)
local name, kills, hks, deaths, honor, faction, _race,
      class_loc, class_token, damage, healing = GetBattlefieldScore(i)
```

This is the single most important fact in this skill. Misreading it corrupts saved data with class tokens stored in damage fields.

### `GetBattlefieldScore` field caveats
- **`honorGained` (slot 5) is BONUS HONOR ONLY**, not total honor for the match. Source: Wowpedia's GetBattlefieldScore page explicitly states this.
- For per-match real honor totals (bonus + per-kill + objectives), parse `CHAT_MSG_COMBAT_HONOR_GAIN` (see honor section).
- `damageDone` and `healingDone` populate during the BG, but may be incomplete at exact match-end. A delayed re-fetch (`UPDATE_BATTLEFIELD_SCORE` after `GetBattlefieldWinner()` returns non-nil) catches the final values.

### BG detection
- `IsInInstance()` returning `"pvp"` is the reliable check. Zone-name matching alone is unreliable because WSG/AB are real outdoor zones too.
- Use `GetInstanceInfo()` for the BG's name, not `GetRealZoneText()`. The realm zone string is unreliable during PEW transitions on Anniversary.

### Honor tracking
- **`GetHonorCurrency()` exists** but doesn't reliably reflect freshly-earned honor during a BG. Snapshot-delta approaches MISS most of the actual honor gained.
- **The reliable approach**: parse `CHAT_MSG_COMBAT_HONOR_GAIN` chat messages.
- Build patterns from Blizzard's own localized format strings (locale-portable):
  ```lua
  -- COMBATLOG_HONORGAIN  = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
  -- COMBATLOG_HONORAWARD = "You have been awarded %d honor points."
  ```
- Both messages arrive via `CHAT_MSG_COMBAT_HONOR_GAIN`.
- This is the production approach used by HonorSpy on Classic/TBC.
- Listen for ~30 seconds after match end to catch the post-match win bonus that arrives slightly after `GetBattlefieldWinner()` returns.

### Spec inference (talent tree → spec name)
TBC has no spec API. Map the dominant talent tab to a static spec name table:

```lua
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
```

No dual-spec on TBC, so `talentGroup` parameter is `nil` or `1`.

### UI building
- `BasicFrameTemplateWithInset` works for windows. Use `f.TitleText:SetText(...)`.
- `CharacterFrameTabButtonTemplate` works for tabs. Use with `PanelTemplates_SetNumTabs` and `PanelTemplates_SelectTab/DeselectTab`.
- `HybridScrollFrame` template is unreliable across patches; use plain `ScrollFrame` + content child + a row pool for large tables.
- `RAID_CLASS_COLORS` exists and is keyed by class token (uppercase: "WARRIOR", "DRUID", etc.).
- **`SimpleHTML` widget is broken** on Anniversary. Avoid.
- **No localStorage / no persistent state inside artifacts.** Use SavedVariables for everything.
- **`addon_name` is provided as the first vararg in every Lua file**: `local addon_name, T = ...`. WoW sets it to the literal folder name. This is the canonical way to gate `ADDON_LOADED`: `if event == "ADDON_LOADED" and (...) == addon_name then ...`. Renaming the folder automatically updates `addon_name` — no code change needed for the gate.

### SavedVariables behavior
- `## SavedVariables: name` for shared across characters.
- `## SavedVariablesPerCharacter: name` for per-character.
- A debug log written to a global-like variable (`_G.MY_LOG`) does NOT persist across `/reload` unless declared in the TOC SavedVariables. This bites every time you forget.
- **SavedVariables identifier conventionally matches folder casing** (`BgStatDB`, not `bgstat_db`). It's a Lua global declared by the TOC, and matching the addon's display identity makes it easy to find in `WTF/Account/<acct>/SavedVariables/<Addon>.lua` on disk. Internal Lua locals can still be snake_case; the SavedVariables global is the user-facing exception.
- **Renaming SavedVariables identifiers breaks data continuity.** A user upgrading from `OldName/` with `OldNameDB` to `NewName/` with `NewNameDB` will have their old data sitting on disk at `WTF/.../SavedVariables/OldName.lua` and the new addon won't see it. Three migration options: (a) load old global in `ADDON_LOADED` and copy fields if both exist briefly; (b) document a manual file rename in the README; (c) accept fresh-start. Option (a) only works while both addon folders coexist on disk, since SavedVariables only load for installed/enabled addons. For private/single-user addons, (c) is usually fine.

### Common UI gotchas verified during this build
- **Headers and rows must use the same sizing model** (`SetSize` + `SetJustifyH`) or columns visually drift. `SetText` alone on header buttons doesn't size correctly relative to row cells.
- **Mixed-type sort comparators crash**. If a column may have nil, number, and string values across rows, coerce types before comparing or the sort throws "attempt to compare number with string".
- **Row cell text doesn't auto-update** when refreshing a table. Iterate the row pool, hide unused rows beyond `#data`, otherwise leftover content from a prior refresh shows.
- **`PanelTemplates_TabResize(tab, 0)`** is required for tabs to size correctly.

## Universal anti-patterns to avoid

These caused real bugs over many hours of build work. Avoid them.

### 1. Trusting positional unpacks across client versions
The `GetBattlefieldScore` retail-vs-Anniversary mismatch took multiple debugging rounds to find. **Always look up the documented signature for the specific client version** (Vanilla wiki for vanilla/TBC, Wowpedia for retail). Empirical `/print` testing inside the live game confirms which signature is in use.

### 2. Adding "defensive" coercion in aggregation layers to mask data corruption
If `damage` arrives as the string `"WARLOCK"`, do not write `(type(p.damage) == "number") and p.damage or 0` in History.lua. **Fix the source** (Scoreboard.lua reading the wrong position). Defensive code in aggregation hides bugs and creates a layer of "is the data actually right or just papered over" uncertainty.

### 3. Polling `GetHonorCurrency` for per-BG honor totals
Doesn't work reliably. The function reflects spendable honor which lags real-time credits. Parse chat messages instead.

### 4. Refreshing scoreboard data after match end without a delay
`GetBattlefieldScore` may return stale or partially-populated data immediately at match end. Listen for late `UPDATE_BATTLEFIELD_SCORE` events for ~30 seconds afterwards and merge any larger values into the saved record.

### 5. Overwriting player records on every scoreboard refresh
If module A (scanner) stores `spec_tab` on a player record and module B (scoreboard refresh) does `players[name] = {...new data...}`, A's contribution is wiped. **Merge** scoreboard refreshes into existing records rather than replacing them.

### 6. Outputting debug data to `DEFAULT_CHAT_FRAME:AddMessage`
The chat frame doesn't allow text selection in WoW. Users can't copy multi-line debug output for support. **Always write debug captures to a copyable EditBox window** with `BasicFrameTemplateWithInset`. Pattern that works:

```lua
local f = CreateFrame("Frame", "MyDebugFrame", UIParent, "BasicFrameTemplateWithInset")
f:SetSize(800, 500); f:SetPoint("CENTER")
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
f:SetScript("OnDragStart", f.StartMoving)
f:SetScript("OnDragStop", f.StopMovingOrSizing)
local sf = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
sf:SetPoint("TOPLEFT", 10, -30); sf:SetPoint("BOTTOMRIGHT", -30, 10)
local eb = CreateFrame("EditBox", nil, sf)
eb:SetMultiLine(true); eb:SetFontObject(ChatFontNormal)
eb:SetWidth(760); eb:SetAutoFocus(false)
eb:SetScript("OnEscapePressed", function() f:Hide() end)
sf:SetScrollChild(eb)
eb:SetText(my_text)
f:Show()
eb:HighlightText()
eb:SetFocus()
```

### 7. Persisting debug logs without adding them to SavedVariables
A debug accumulator at `_G.MM_log = {}` is wiped on `/reload`. Add it to the TOC if it needs to survive a reload.

## Verification approach when ported behavior breaks

When something works on retail/TBC Classic 2021 but not on Anniversary:

1. Look up the function on **Wowpedia** AND **Vanilla wiki** AND **wowwiki-archive**. Compare signatures across eras.
2. Check if a `C_*` namespaced version exists.
3. Run a live test inside the game: `/run print(...)` with multi-line capture window if multiple values.
4. Check production addons targeting Anniversary specifically (CurseForge "TBC Anniversary" filter) for working examples.
5. Cross-reference the `Ketho/wow-ui-source-bcc` repository when looking at how Blizzard's own UI uses an API.

Do not assume retail signatures apply. Do not assume TBC Classic 2021 signatures apply. Anniversary is its own thing.

## Locale considerations

- Format strings like `COMBATLOG_HONORGAIN` are pre-localized. Build regex patterns from them to be portable across locales.
- Class tokens (`"WARRIOR"`, `"DRUID"`) are locale-invariant. Class localized names (`"Warrior"`, `"Druid"`) are not. Use tokens as keys, localized strings only for display.

## Performance considerations

- `GetTalentTabInfo` is cheap. Calling it three times per inspect is fine.
- `GetBattlefieldScore` for 40 players in AV is fine (~1ms).
- Table sort on 80 rows on every UI refresh is fine. Don't add caching machinery prematurely.
- Lua tables with thousands of entries are fine. SavedVariables capped at ~100 matches × 40 players keeps file size negligible.

### 8. Hardcoding the addon's own name in code or texture paths

Don't write `"MyAddOn"` as a string literal anywhere code can avoid it. Texture paths like `Interface\\AddOns\\MyAddOn\\Res\\Foo.blp` are unavoidable, but the addon's own identity in `ADDON_LOADED` gates, frame names, and chat output should derive from `addon_name` (the vararg) where reasonable, or live in `Config.lua` as a single constant the rest of the code references. Otherwise, a future rename touches dozens of files.

When the addon is renamed, the work is mostly mechanical search-and-replace, but the surfaces that need attention are: folder name, TOC filename, TOC `## Title:` directive, `## SavedVariables:` and `## SavedVariablesPerCharacter:` identifier names, the SavedVariables identifiers themselves wherever they appear in `.lua` files, slash command globals (`SLASH_NAME1/2`, `SlashCmdList.NAME`), `CreateFrame` named globals, texture path strings in `Config.lua`, chat output strings, and the README. Missing any one of these produces a silent partial-rename state.