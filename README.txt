BgStat - TBC Anniversary Edition (2.5.5)
============================================

Built for TBC Anniversary, build 2.5.5.67157
Interface: 20505

INSTALLATION
------------
1. Extract the BgStat folder into:
     <WoW>\_anniversary_\Interface\AddOns\

   The folder is `_anniversary_`, NOT `_classic_` (TBC Classic 2021)
   and NOT `_classic_era_` (vanilla servers).

2. Copy your asset files into BgStat\Res\:
     - Hehhe.mp3       (KB sound)
     - MadBaby.blp     (most classes)
     - Broseph.blp     (Rogue)
     - DerpFace.blp    (Hunter)

3. Restart WoW. Confirm "BgStat" appears in the AddOns list.

SLASH COMMANDS
--------------
  /bgstat           - toggle the window (also /bgs)
  /bgstat last      - open to Last Match tab
  /bgstat history   - open to History tab
  /bgstat classes   - open to Classes tab
  /bgstat specs     - open to Specs tab
  /bgstat send      - broadcast brief summary to BG chat (60s cooldown)
  /bgstat clear     - wipe all saved match history
  /bgstat help      - show command list

THE FOUR TABS
-------------
Last Match
  Most recent BG: result, your stats line, sortable per-player table
  with kills, deaths, HKs, damage, healing, honor. Faction-tinted rows
  (blue Alliance, red Horde). Your row highlighted gold. Faction filter
  buttons (All / Alliance / Horde). Click any column to sort.

History
  Career summary at top: total games, W/L, win %, total honor, total
  K/D. Below: per-BG breakdown (WSG, AB, AV, EotS) with games, wins,
  losses, win %, kills, deaths, honor for that BG specifically.

Classes
  Aggregated stats per class across every saved match (both factions
  pooled). How many times you've seen each class, their cumulative
  damage/healing/K/D, average damage per appearance, and the single
  biggest performer of that class you've ever encountered.

Specs
  Aggregated stats per (class, spec) for friendly-faction players whose
  talents the auto-scanner inspected during BGs. The scanner tries each
  friendly within 28 yards every 2 seconds and stores the dominant
  talent tab. Specs only shows entries for matches where at least one
  inspect succeeded.

DATA SOURCES
------------
  Kills, deaths, HKs, damage, healing : Blizzard's BG scoreboard
                                        (GetBattlefieldScore, 12-slot
                                        Vanilla layout)
  Honor gained per match              : parsed CHAT_MSG_COMBAT_HONOR_GAIN
                                        events (captures bonus, objective,
                                        and per-kill honor including the
                                        post-match win bonus)
  Win/Loss                            : GetBattlefieldWinner()
  Your personal KBs (with spell name) : combat log PARTY_KILL events
  Friendly specs                      : INSPECT_READY + GetTalentTabInfo

NOTES
-----
  - History capped at last 100 matches (configurable in Config.lua).
  - "Incomplete" matches: you left or zoned out before the game resolved.
  - Spec scanner respects the global inspect lock; other addons doing
    inspects can briefly compete with it.