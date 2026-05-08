MongoMon - TBC Anniversary Edition (2.5.5)
v2.0.0 - Native UI release
============================================

Built for TBC Anniversary, build 2.5.5.67157
Interface: 20505

WHAT'S NEW IN v2.0
------------------
* Real native UI window with three tabs (Last Match, History, Classes)
* Sortable columns - click any column header to sort
* All numbers come from Blizzard's official BG scoreboard (kills, deaths,
  damage, healing) instead of trying to compute them from the combat log
* Honor tracking now uses real total-honor delta, so it correctly captures
  objective honor and end-of-match win bonuses
* Window auto-opens to Last Match tab when a BG ends
* Window position is saved per character

INSTALLATION
------------
1. Extract MongoMon folder into:
     <WoW>\_anniversary_\Interface\AddOns\

   The folder is `_anniversary_`, NOT `_classic_` (TBC Classic 2021)
   and NOT `_classic_era_` (vanilla servers).

2. Copy your retail Res files into MongoMon\Res\:
     - Hehhe.mp3       (KB sound)
     - MadBaby.blp     (most classes)
     - Broseph.blp     (Rogue)
     - DerpFace.blp    (Hunter)

3. Restart WoW. Confirm "MongoMon" appears in the AddOns list.

SLASH COMMANDS
--------------
  /mm           - toggle the window
  /mm last      - open to Last Match tab
  /mm history   - open to History tab
  /mm classes   - open to Classes tab
  /mm send      - broadcast brief summary to BG chat (60s cooldown)
  /mm clear     - wipe all saved match history
  /mm help      - show command list

THE THREE TABS
--------------
Last Match
  Shows the most recent BG: result, your stats line, and a sortable table
  of every player in the match with kills, deaths, HKs, damage, healing,
  honor. Your row is highlighted blue. Click any column to sort.

History
  Career summary at top: total games, W/L, win %, total honor, total K/D.
  Below: per-BG breakdown (WSG, AB, AV, EotS) with games, wins, losses,
  win %, kills, deaths, honor earned for that BG specifically.

Classes
  Aggregated stats per class across every match you've saved. Shows how
  many times you've seen each class, their cumulative damage/healing/K/D,
  average damage per appearance, and the single biggest performer of that
  class you've ever encountered. Useful for spotting which classes
  consistently dominate your bracket.

DATA SOURCES
------------
  Kills, deaths, HKs, damage, healing : Blizzard's BG scoreboard
  Honor gained per match              : delta of GetHonorCurrency()
  Win/Loss                            : GetBattlefieldWinner()
  Your personal KBs (with spell name) : combat log PARTY_KILL events

NOTES
-----
  - History capped at last 100 matches (configurable in Config.lua).
  - "Incomplete" matches: you left or zoned out before the game resolved.
  - Pre-v2.0 saved matches lacked the honor delta field and will fall
    back to scoreboard honor (which under-counts). New matches use delta.
