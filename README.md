# BgStat — TBC Anniversary Edition (2.5.6)

Battleground stats, killing-blow tracking, and a six-tab post-match window.

Built for **TBC Anniversary**, patch 2.5.6 (Interface `20506`).

## Installation

1. Extract the `BgStat` folder into:
```
   <WoW>\_anniversary_\Interface\AddOns\
```

   The folder is `_anniversary_`, **not** `_classic_` (TBC Classic 2021)
   and **not** `_classic_era_` (vanilla servers).

2. Restart WoW and confirm **BgStat** appears in the AddOns list.
Killing-blow sounds ship with the addon in `BgStat\Res\` — no manual
asset setup is needed.

## Slash commands

| Command           | Effect                                            |
|-------------------|---------------------------------------------------|
| `/bgstat`         | Toggle the window (also `/bgs`)                   |
| `/bgstat last`    | Open to Last Match tab                            |
| `/bgstat history` | Open to History tab                               |
| `/bgstat classes` | Open to Classes tab                               |
| `/bgstat specs`   | Open to Specs tab                                 |
| `/bgstat kills`   | Open to Kills tab                                 |
| `/bgstat trends`  | Open to Trends tab                                |
| `/bgstat config`  | Open the options panel (requires Ace3)            |
| `/bgstat send`    | Broadcast brief summary to BG chat (60s cooldown) |
| `/bgstat clear`   | Wipe all saved match history                      |
| `/bgstat help`    | Show command list                                 |

## The six tabs

### Last Match
Most recent BG: result, your stats line, sortable per-player table with
row number, kills, deaths, HKs, damage, healing, honor. Faction-tinted
rows (blue Alliance, red Horde). Your row highlighted gold. Faction
filter buttons (All / Alliance / Horde). Click any column to sort; hover
any column header for a description of what it measures.

Note: the Honor column is the scoreboard's bonus honor only. Your true
per-match total (including per-kill honor) is the honor line above the
table, parsed from chat.

### History
Career summary at top: total games, W/L, win %, total honor, total K/D.\
Below: per-BG breakdown (WSG, AB, AV, EotS) with games, wins, losses, win %, kills, deaths, honor for that BG specifically.

### Classes
Aggregated stats per class across every saved match (both factions pooled).\
Damage and healing are size-normalized so 10-man WSG and 40-man AV games are comparable:

- **Dmg/P, Heal/P** — damage/healing per participant: each appearance's value divided by that match's player count, averaged across appearances.
- **D-Idx, H-Idx** — performance index vs the average player of the same match. 1.00 = exactly match average, 2.00 = double.\
  Comparable across BG sizes and durations.
- **Best (Index)** — the highest single-match damage index ever recorded for that class, and who did it. Sorts by the index value.

### Specs
Aggregated stats per (class, spec) for friendly-faction players whose talents the auto-scanner inspected during BGs.\
Same size-normalized columns as Classes.\
Your own characters appear as separate gold rows marked (YOU), tracked apart from the population averages.\
The scanner tries each friendly within 28 yards every 2 seconds and stores the dominant talent tab.

### Kills
Your last 500 killing blows across saved matches, for the character you're logged in as.\
Each row: victim (with realm for cross-realm players), victim class, the damage of the hit that killed them, the spell or melee swing that landed it, the battleground, and date/time.\
Kills saved before this feature lack the damage/realm/time fields and show dashes or the match's end time instead.

### Trends
Four line charts in a 2x2 grid — Kills, Deaths, Damage, Healing — each plotting you (colored: yellow/red/orange/green) against your team's per-player average (grey) across your saved matches, oldest to newest.\
Each chart auto-scales independently.\
Hover any point for that match's BG, result, date, and exact values.\
Click a chart to expand it over the full tab; click again to return to the grid.\
Chart depth follows the "Max matches in history" setting.

## Data sources
| Data                                                     | Source                                                                                                                        |
|----------------------------------------------------------|-------------------------------------------------------------------------------------------------------------------------------|
| Kills, deaths, HKs, damage, healing                      | Blizzard's BG scoreboard (`GetBattlefieldScore`, 12-slot Vanilla layout)                                                      |
| Honor gained per match                                   | Parsed `CHAT_MSG_COMBAT_HONOR_GAIN` events (captures bonus, objective, and per-kill honor including the post-match win bonus) |
| Win/Loss                                                 | `GetBattlefieldWinner()`                                                                                                      |
| Your personal KBs (spell, killing-hit damage, timestamp) | Combat log `PARTY_KILL` + damage events                                                                                       |
| Friendly specs                                           | `INSPECT_READY` + `GetTalentTabInfo`                                                                                          |

## Notes
- History is capped at the last 100 matches (configurable via `/bgstat config` or `Config.lua`).
- Match history is account-wide, but the Kills and Trends tabs show only the logged-in character's matches.\
  Matches saved before the per-character stamp was added are attributed by whether your character appears in the match's player list.
- The spec scanner respects the global inspect lock; other addons doing inspects can briefly compete with it.
- The options panel requires **Ace3** (optional dependency).\
  Everything else works without it.

## License
MIT — see `LICENSE`. 
Voice lines are locally generated TTS output; see `PROVENANCE.md` for the full asset provenance chain.