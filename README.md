# BgStat — TBC Anniversary Edition (2.5.5)

Battleground stats, killing-blow tracking, and a four-tab post-match window.

Built for **TBC Anniversary**, patch 2.5.6 (Interface `20506`).

## Installation

1. Extract the `BgStat` folder into:
```
   <WoW>\_anniversary_\Interface\AddOns\
```

   The folder is `_anniversary_`, **not** `_classic_` (TBC Classic 2021)
   and **not** `_classic_era_` (vanilla servers).

2. Restart WoW and confirm **BgStat** appears in the AddOns list.
All assets (killing-blow sounds and class images) ship with the addon in
`BgStat\Res\` — no manual asset setup is needed.

## Slash commands

| Command           | Effect                                            |
|-------------------|---------------------------------------------------|
| `/bgstat`         | Toggle the window (also `/bgs`)                   |
| `/bgstat last`    | Open to Last Match tab                            |
| `/bgstat history` | Open to History tab                               |
| `/bgstat classes` | Open to Classes tab                               |
| `/bgstat specs`   | Open to Specs tab                                 |
| `/bgstat config`  | Open the options panel (requires Ace3)            |
| `/bgstat send`    | Broadcast brief summary to BG chat (60s cooldown) |
| `/bgstat clear`   | Wipe all saved match history                      |
| `/bgstat help`    | Show command list                                 |

## The four tabs

### Last Match
Most recent BG: result, your stats line, sortable per-player table with
kills, deaths, HKs, damage, healing, honor. Faction-tinted rows (blue
Alliance, red Horde). Your row highlighted gold. Faction filter buttons
(All / Alliance / Horde). Click any column to sort.

### History
Career summary at top: total games, W/L, win %, total honor, total K/D.
Below: per-BG breakdown (WSG, AB, AV, EotS) with games, wins, losses,
win %, kills, deaths, honor for that BG specifically.

### Classes
Aggregated stats per class across every saved match (both factions
pooled). How many times you've seen each class, their cumulative
damage/healing/K/D, average damage per appearance, and the single
biggest performer of that class you've ever encountered.

### Specs
Aggregated stats per (class, spec) for friendly-faction players whose
talents the auto-scanner inspected during BGs. The scanner tries each
friendly within 28 yards every 2 seconds and stores the dominant talent
tab. Specs only shows entries for matches where at least one inspect
succeeded.

## Data sources

| Data                                | Source                                                                                                                        |
|-------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Kills, deaths, HKs, damage, healing | Blizzard's BG scoreboard (`GetBattlefieldScore`, 12-slot Vanilla layout)                                                      |
| Honor gained per match              | Parsed `CHAT_MSG_COMBAT_HONOR_GAIN` events (captures bonus, objective, and per-kill honor including the post-match win bonus) |
| Win/Loss                            | `GetBattlefieldWinner()`                                                                                                      |
| Your personal KBs (with spell name) | Combat log `PARTY_KILL` events                                                                                                |
| Friendly specs                      | `INSPECT_READY` + `GetTalentTabInfo`                                                                                          |

## Notes

- History is capped at the last 100 matches (configurable via
  `/bgstat config` or `Config.lua`).
- "Incomplete" matches: you left or zoned out before the game resolved.
- The spec scanner respects the global inspect lock; other addons doing
  inspects can briefly compete with it.
- The options panel requires **Ace3** (optional dependency). Everything
  else works without it.