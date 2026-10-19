# Phase 0a Research: R Package Maintenance Status & Function Inventory

**Research date (all fetches below): 2026-10-17**

This file is a live-verified companion to `docs/PHASE0_RESEARCH_PLAN.md` section 2's R-package
subsection, produced for GitHub issue #2. It does **not** edit or create
`docs/MLB_REPLICATION_PLAN.md` — that document is assembled later from this and sibling research
files.

Scope: `baseballr`, `Lahman`, `pitchRx`, `mlbgameday`, `mlbplotR`, and the question of a separate
maintained Retrosheet-adjacent R package. Every claim below is tied to a source URL and fetch date
(2026-10-17 for all, since this file was produced in a single research session).

## Findings table

| R package | Function(s) | Data need served | Verified coverage window | Maintenance status (as of 2026-10-17) |
|---|---|---|---|---|
| **baseballr** | `mlb_game_pks()`, `mlb_pbp()`, `mlb_schedule()`, `mlb_probables()`, `mlb_batting_orders()`, `mlb_stats()`, `mlb_stats_leaders()`, `mlb_people()`, `mlb_player_game_stats()`, `mlb_teams()`, `mlb_team_stats()`, `mlb_team_leaders()`, `mlb_standings()` (MLB Stats API wrappers); `statcast_search()`, `statcast_leaderboards()`, `code_barrel()`, `linear_weights_savant()` (Baseball Savant/Statcast); `fg_batter_leaders()`, `fg_batter_game_logs()`, `fg_pitcher_leaders()`, `fg_pitcher_game_logs()`, `fg_projections()`, `fg_park()` (FanGraphs); `retrosheet_data()` (Retrosheet) | MLB Stats API game/player/team data, Statcast pitch-level data, FanGraphs advanced leaderboards/projections, Retrosheet event/roster files — single package covering nearly all §2 data needs | CRAN v2.0.0 published 2026-08-26; GitHub `master` actively committed through 2026-10-09 (103-day active window verified) | **Actively maintained.** CRAN current, GitHub shows merged PRs as recently as Oct 9, 2026 (docs/feature commits by maintainer `saiemgilani`). However, 7 open GitHub issues as of fetch date include real scraper breakage: Baseball-Reference-backed functions (e.g. `bref_team_results()`) reportedly returning HTTP 403 (issue dated Aug 21, 2026), Baseball-Reference HTTP 429 rate-limiting with no built-in retry in `xml2::read_html()`, and the ESPN free-agents endpoint wrapper returning HTTP 500 for every season tested as of a May 2026 report (function retained as a no-op shim, not removed) — these are Baseball-Reference/ESPN-sourced functions, not the MLB-Stats-API/Statcast/FanGraphs/Retrosheet functions listed above, which were not reported broken. |
| **Lahman** | Historical tables: `People`, `Batting`, `Pitching`, `Fielding`, plus team/season/award/postseason tables, exposed as R data frames (no scraping functions — static bundled data) | Season-level batting/pitching/fielding historical database, 1871–present, for backtesting and feature engineering | CRAN v14.0-0, published per CRAN index 2026-02-12 (also reported as 2026-02-11 in the PDF manual header — within 1 day, likely timezone/build artifact); data covers seasons **1871 through 2024** per the current package's stated coverage | **Actively maintained**, but with an inherent lag: the installed CRAN version's underlying Lahman database snapshot covers only through the 2024 season as of the 2026-02-12 release — i.e., even the latest CRAN release trails the current season by at least one full year. Confirm current season coverage before relying on it for 2025/2026 data. |
| **pitchRx** | `scrapeFX()` and related PITCHf/x scraping/visualization functions (author Carson Sievert) | Pitch-level PITCHf/x data acquisition and visualization (pre-Statcast era) | GitHub commit history runs 2014-10-31 through last commit 2023-08-05 (per `github.com/cpsievert/pitchRx/commits/master`); no commits in the ~3 years since | **Archived-avoid.** CRAN page (`cran.r-project.org/package=pitchRx`) confirms the package "was removed from the CRAN repository," archived **2023-11-21**, reason given: "issues were not corrected in time." GitHub repo is not formally archived/locked but has had no commits since Aug 2023 and 27 open issues with no apparent maintainer response. `baseballr`'s own documentation confirms `baseballr` has effectively superseded `pitchRx` for current Statcast access. **Do not use for new MLB port work.** |
| **mlbgameday** | Tools to gather/parse MLB Advanced Media Gameday XML data (PITCHf/x-era), designed for parallel processing of larger-than-memory datasets | Pitch-level/Gameday XML data acquisition, overlapping with `pitchRx`'s historical niche | GitHub commit history (`github.com/keberwein/mlbgameday/commits/master`) shows last commits April 12–13, 2019; no activity since — over 7 years stale as of fetch date | **Archived-avoid.** CRAN page (`cran.r-project.org/package=mlbgameday`) confirms the package "was removed from the CRAN repository," archived **2020-07-05**, reason given: "frequent issues with connectivity (yet again)" — i.e., CRAN removed it for the same functional reason flagged in the research plan (unreliable scraping), not a packaging technicality. GitHub repo README self-describes status as "Active" but this is stale self-labeling contradicted by the actual commit timeline (last commit 2019). **Do not use for new MLB port work** — this is the mirror of the NFL plan's deprecated-function trap: trusting a README's self-reported "Active" badge over live commit/CRAN evidence would have been a mistake here. |
| **mlbplotR** | `geom_mlb_logos()` (ggplot2 geom for team logos), `load_mlb_teams()` (team abbreviations/colors/logos lookup), plus `gt`-table logo rendering helpers | Team-logo plotting/visualization for future dashboard/report work (baseball analog of `nflplotR`) | CRAN v1.2.0, published 2025-09-02; authored by Sebastian Carl and Camden Kay, maintained by Camden Kay; GitHub repo shows 228 total commits and 4 open issues as of fetch date | **Actively maintained.** Current CRAN release is just over a year old as of fetch date (2025-09-02 release vs. 2026-10-17 fetch) with no archival notice; GitHub remains the canonical dev repo (`camdenk/mlbplotR`) with open issues but no stale/abandoned signal found. README/docs describe only team-logo coverage (no confirmed player-headshot geom at time of this check — do not assume headshot support without re-verifying against the live reference index before relying on it). |
| **retrosheet** (separate Retrosheet-adjacent package, distinct from `baseballr::retrosheet_data()`) | `get_retrosheet()` and related functions to download/parse single-season event (play-by-play), gamelog, roster, and schedule files from retrosheet.org into R objects | Historical play-by-play / event-file access as an alternative or supplement to `baseballr`'s built-in Retrosheet wrapper | CRAN v1.1.7, published 2026-04-20; maintained by Colin Douglas (GitHub: `colindouglas/retrosheet`); package listed in the CRAN Sports Analytics task view | **Actively maintained, separate from baseballr.** Confirms the research plan's open question: yes, a separate maintained CRAN package (`retrosheet`) exists independently of `baseballr::retrosheet_data()`, with its own recent (2026-04-20) release. Worth evaluating against `baseballr`'s built-in wrapper for event-file parsing robustness/coverage before committing to one in the eventual build phase — that comparison is out of scope for this research file. |

## Key traps flagged (parallel to the NFL plan's nflfastR-deprecated-functions note)

1. **`pitchRx` — CRAN-archived 2023-11-21, GitHub-stale since Aug 2023.** Superseded by `baseballr`'s
   Statcast functions. Do not use for new MLB engine work.
2. **`mlbgameday` — CRAN-archived 2020-07-05, GitHub-stale since April 2019** despite the GitHub
   repo's own README self-labeling the project "Active" — a stale badge, not live evidence. This is
   the clearest "don't trust the README" trap in this set: the CRAN archival page and actual commit
   timeline directly contradict the repo's self-description.
3. **`baseballr`'s Baseball-Reference- and ESPN-backed functions** (not its MLB-Stats-API/Statcast/
   FanGraphs/Retrosheet functions) have live-reported breakage as of 2026: `bref_team_results()`-style
   functions hitting HTTP 403, and the ESPN free-agents wrapper returning HTTP 500 for every season
   tested as of a May 2026 report, retained only as a non-functional shim. Treat these specific
   Baseball-Reference/ESPN functions as unreliable even though the package overall is actively
   maintained — maintenance status is not uniform across all functions in one package.

## Sources Consulted

| # | Source | URL | Fetch date |
|---|---|---|---|
| 1 | CRAN package page — baseballr | https://cran.r-project.org/web/packages/baseballr/index.html | 2026-10-17 |
| 2 | WebSearch — baseballr CRAN package page (version/maintainer corroboration) | https://www.r-pkg.org/pkg/baseballr ; https://cran.r-project.org/web/packages/baseballr/baseballr.pdf | 2026-10-17 |
| 3 | GitHub repo — BillPetti/baseballr (main page, description, lifecycle badge, stars/forks) | https://github.com/BillPetti/baseballr | 2026-10-17 |
| 4 | GitHub commits — BillPetti/baseballr master branch (recent commit dates) | https://github.com/BillPetti/baseballr/commits/master | 2026-10-17 |
| 5 | baseballr pkgdown reference index (function inventory by category) | https://billpetti.github.io/baseballr/reference/index.html | 2026-10-17 |
| 6 | WebSearch — baseballr GitHub issues / broken scraper reports (bref 403, ESPN 500, 429 rate-limiting, install issue) | https://github.com/BillPetti/baseballr/issues ; https://github.com/BillPetti/baseballr/issues/60 | 2026-10-17 |
| 7 | CRAN package page — Lahman | https://cran.r-project.org/web/packages/Lahman/index.html | 2026-10-17 |
| 8 | WebSearch — Lahman CRAN package details (version, coverage years, maintainer) | https://cran.r-project.org/web/packages/Lahman/Lahman.pdf ; https://github.com/cran/Lahman | 2026-10-17 |
| 9 | WebSearch — pitchRx CRAN archival status | https://cran.r-project.org/package=pitchRx | 2026-10-17 |
| 10 | CRAN package page — pitchRx (direct fetch confirming archival date/reason) | https://cran.r-project.org/package=pitchRx | 2026-10-17 |
| 11 | GitHub commits — cpsievert/pitchRx master branch (recent commit dates) | https://github.com/cpsievert/pitchRx/commits/master | 2026-10-17 |
| 12 | GitHub repo — cpsievert/pitchRx (open issues count, README) | https://github.com/cpsievert/pitchRx | 2026-10-17 |
| 13 | WebSearch — mlbgameday R package GitHub status | https://github.com/keberwein/mlbgameday ; https://cran.r-project.org/package=mlbgameday | 2026-10-17 |
| 14 | CRAN package page — mlbgameday (direct fetch confirming archival date/reason) | https://cran.r-project.org/package=mlbgameday | 2026-10-17 |
| 15 | GitHub commits — keberwein/mlbgameday master branch (recent commit dates) | https://github.com/keberwein/mlbgameday/commits/master | 2026-10-17 |
| 16 | GitHub repo — keberwein/mlbgameday (README self-labeled status) | https://github.com/keberwein/mlbgameday | 2026-10-17 |
| 17 | WebSearch — mlbplotR CRAN package | https://cran.r-project.org/package=mlbplotR ; https://cran.r-project.org/web/packages/mlbplotR/mlbplotR.pdf | 2026-10-17 |
| 18 | GitHub repo — camdenk/mlbplotR (commit count, open issues, functions) | https://github.com/camdenk/mlbplotR | 2026-10-17 |
| 19 | WebSearch — Retrosheet-adjacent R package distinct from baseballr | https://cran.r-project.org/package=retrosheet ; https://github.com/colindouglas/retrosheet | 2026-10-17 |

## Explicit non-goals of this file

- Does not create or edit `docs/MLB_REPLICATION_PLAN.md`.
- Does not assert final numeric constants or make a build-commitment decision between `baseballr`'s
  built-in Retrosheet wrapper and the standalone `retrosheet` package — that comparison belongs to a
  later implementation-phase decision.
- Does not cover vendor/API-level verification (MLB Stats API, Baseball Savant, FanGraphs ToS, ESPN,
  The Odds API) — that is issue #3's scope, not this file's.
