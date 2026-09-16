# Phase 0 Validation Notes — wehoop / WNBA Data Coverage

Written by `wnba_scaffold_agent` (T0) on 2026-09-12. This documents what was actually run and
observed in this environment, not assumptions from `WNBA_REPLICATION_PLAN.md`.

## Environment

- R was **not** on `PATH`, but a full R installation was found at
  `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (R 4.5.2, ucrt build). Live validation **was**
  possible in this environment once that full path was used.
- `wehoop` was not pre-installed. Installed successfully via
  `install.packages("wehoop", repos = "https://cloud.r-project.org")` — no errors, package
  downloaded as a prebuilt binary (`wehoop_3.0.0.zip`, built under R 4.5.3, ~3.2 MB).
  **`wehoop` package version confirmed: 3.0.0.**
- Internet access was available and functioned normally for both CRAN and the live ESPN-backed
  data pulls below.

## Commands run

Two temporary R scripts (`_phase0_validate.R`, `_phase0_validate2.R`, `_phase0_validate3.R`,
now deleted after use — this repo's convention is not to leave scratch files around) called:
`wehoop::load_wnba_team_box(seasons = <year>)` and `wehoop::load_wnba_player_box(seasons = <year>)`
for seasons 2019–2026, then inspected `nrow()`, `ncol()`, and distinct `team_abbreviation` values.

(Note: running the multi-line `Rscript -e "..."` form directly through the Bash tool's heredoc
caused a segfault on this Windows box — likely a quoting/encoding interaction between Git Bash
and `Rscript.exe`. Writing the R code to a `.R` file and invoking
`Rscript.exe path\to\file.R` via PowerShell worked reliably. Future agents on this environment
should prefer that pattern over inline `-e` multi-line strings.)

## Findings — row counts and schema

| Season | team_box rows | team_box cols | player_box rows | Distinct team_abbreviation values |
|---|---|---|---|---|
| 2019 | 442 | 54 | (not captured) | 14 incl. **DEL, WIL** (non-franchise) |
| 2020 | 294 | 54 | (not captured) | 12 (clean — bubble season, short 22-game schedule) |
| 2021 | 422 | 54 | (not captured) | 14 incl. **ALL, USA** (non-franchise) |
| 2022 | 482 | 54 | 5,307 | 14 incl. **STE, WIL** (non-franchise) |
| 2023 | 524 | 57 | 5,796 | 14 incl. **STE, WIL** (non-franchise) |
| 2024 | 528 | 57 | 5,929 | 14 incl. **USA, WNBASTARS** (non-franchise) |
| 2025 | 624 | 57 | 7,140 | 15 incl. **CLA, COL** (non-franchise) — 13 real franchises |
| 2026 (partial) | 604 | 59 | (not captured) | 17 incl. **COOP, SPO** (non-franchise) — 15 real franchises |

**Key finding / caveat that changes downstream code:** every season's raw `team_box`/`player_box`
data includes extra rows for non-franchise "teams" — All-Star-game draft squads (captain-named,
e.g. `STE`/`WIL`/`CLA`/`COL`/`COOP`/`SPO` for Stewart/Wilson/Clark/Collier/Cooper/etc.) and
Team USA Olympic exhibition games (`USA`, `ALL`, `WNBASTARS`). **This did not exist in the NBA/
hoopR data and is a real WNBA-specific behavioral difference, not a copy-paste bug.** Any ingestion
script (`daily_ingest.R`, `player_metrics.R`, etc.) must filter rows to
`team_abbreviation %in% names(WNBA_TEAMS)` (see `config.R`) before aggregating team-level stats,
or these exhibition rows will corrupt rolling features and standings.

After filtering out those non-franchise rows, the **real franchise counts per season** matched
publicly known WNBA history exactly:
- 2019–2024: 12 real franchises (stable, pre-expansion era)
- 2025: 13 real franchises (Golden State Valkyries joined)
- 2026: 15 real franchises (Toronto Tempo + Portland Fire joined)

This cross-validates `WNBA_TEAMS`/`WNBA_TEAM_COUNT` in `config.R` against two independent
sources (web search + actual wehoop data), and they agree.

## 2026 (current) season completeness

`season_type` column for the 2026 pull returned only value `2` (regular season) across all 604
rows, with `max(game_date) == 2026-08-30`. No playoff rows (`season_type == 3`) were present in
the ESPN-backed feed at validation time (2026-09-12), i.e., the 2026 regular season is captured
but the in-progress/upcoming playoffs are not yet reflected in this data source as pulled.
`CURRENT_SEASON <- 2026` in `config.R` should be treated as "regular season complete-ish, live
data still trickling in" rather than a fully closed season.

## Conclusion / what `config.R` was set to

- `HISTORICAL_SEASONS <- 2019:2025` — data is present and structurally usable for all of these
  seasons (after the non-franchise-row filter above). 2020 is a real anomaly (COVID bubble,
  22-game season) but is not corrupted data, just short — downstream rolling-window code should
  be aware a 22-game season exists inside this range.
- `CURRENT_SEASON <- 2026`, `TEST_SEASON <- 2026` — matches the NBA config's pattern of using the
  active season for both; 2026 data is live/partial per above.
- `ALL_SEASONS <- 2019:2026`, `SIMULATION_SEASON <- 2027` — direct analog of the NBA layout.
- **This is a materially better result than the replication plan's risk section anticipated**
  (§(e) risk #3 speculated wehoop's WNBA depth might have real gaps vs. hoopR's NBA depth) — in
  practice, `wehoop` 3.0.0 returned clean, complete-looking team/player box data back to 2019 with
  no missing seasons, only the (filterable) All-Star/exhibition noise described above. Future
  agents should still spot-check individual columns they depend on (e.g. advanced/tracking stats)
  since only `nrow`/`ncol`/team-list were checked here, not full column-by-column completeness.

## What was NOT validated (out of scope for T0 / needs a future agent)

- Full column-by-column schema completeness/NA rates were not checked — only row/column counts
  and team lists.
- `wehoop::load_wnba_pbp()` (play-by-play, relevant to a future real RAPM engine) was not tested.
- No check was done for whether ESPN's WNBA injuries/rosters JSON endpoints (`sync_rosters.R`,
  `injury_scraper.R` targets) are reachable/well-formed — that's T1's job.
