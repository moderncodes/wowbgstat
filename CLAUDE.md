# CLAUDE.md

This is `bgstat`, a battleground stats addon for WoW TBC Anniversary 2.5.5.

## Read this first

`SKILL.md` at the repo root documents the Anniversary client's API
quirks, anti-patterns, and addon-naming conventions. Read it before
writing or modifying any Lua. It is authoritative.

## Working agreement

- Do not guess. Verify API claims against Wowpedia, the Vanilla wiki,
  Warcraft Wiki, or production Anniversary addons. Cite sources when
  proposing fixes that depend on API behavior.
- When troubleshooting, do not assume root cause. Provide debug code
  first that confirms the diagnosis. Only propose the fix after the
  user has run the debug and shared results.
- Fix at the source. If saved data has wrong types, fix where it's
  written, not where it's read. Do not add defensive coercion in
  aggregation layers — see SKILL.md anti-pattern #2.
- Show only what changes. Do not paste large unchanged code blocks.
- Match the codebase style: snake_case for Lua locals/functions;
  PascalCase for SavedVariables identifiers and CreateFrame globals.
- Push back on bad design. If a request would create a structural
  problem, say so and propose the better approach.

## File responsibilities

- `Config.lua` — constants only
- `CombatLog.lua` — personal KB tracking, NOT damage/healing aggregation
- `Scoreboard.lua` — reads GetBattlefieldScore, merges into player records
- `SpecScanner.lua` — auto-inspects friendlies for talent data
- `Nameplates.lua` — decorates enemy nameplates with K/D
- `History.lua` — SavedVariables, snapshots, summary aggregations
- `Report.lua` — KB callback, BG-chat broadcast
- `UI.lua` — four-tab window, table widget, refresh logic
- `Core.lua` — event dispatch, BG lifecycle, slash commands

## Debug output

Never use `DEFAULT_CHAT_FRAME:AddMessage` for multi-line debug output —
the chat frame doesn't allow text selection in WoW. Always use a
copyable EditBox window (pattern in SKILL.md anti-pattern #6).

## Confirmed working — don't regress

- GetBattlefieldScore parsing using the 12-slot Vanilla layout
- Honor tracking via CHAT_MSG_COMBAT_HONOR_GAIN parsing
- Spec detection via INSPECT_READY + GetTalentTabInfo slot 5
- Faction-tinted rows, sortable columns, persisted window position