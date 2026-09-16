# WNBA Analytics — Testing & Verification Plan

## Execution Log (2026-09-12, post-T5)

**This document has been re-executed against the real, complete T0–T5 codebase** (all six tasks
`done` per `task_assignments.md`, including T5's final "Overall Build Status" summary). Every
section below that was previously tagged `[FROM PLAN/BRIEF — NOT YET BUILT]` has been reconciled
against the actual code/Handoff Notes and the stale tags removed. Where the plan's guessed
filenames/constants turned out to differ from reality (they mostly didn't, by this point — T2–T5
followed the naming conventions T0/T1 established), the text below has been corrected in place.

**Overall pass/fail by section, from an actual execution pass in this session (not re-derived from
the plan document alone):**

| § | Topic | Status | Notes |
|---|---|---|---|
| 1 | Pipeline liveness (`run_full_pipeline.R`) | **PASS** | Ran live: exit 0, 10.44s, 12/13 stages logged `[COMPLETED]`, 1 (`rapm_engine.R`) correctly skipped via a `warning()` (file-not-found guard), 0 `[FAILED]`. Real log line pattern is `[STAGE]`/`[COMPLETED]`/`[FAILED]`, **not** the plan's originally-guessed `STAGE OK`/`STAGE FAILED` string — corrected below. All 13 downstream cache files' `mtime` advanced to the run timestamp, confirming no stage silently no-opped. |
| 2.1 | wehoop box scores | **PASS** | Re-verified live: 3,906 rows, 0 exhibition-abbreviation rows, 0 `CONN` rows, 203 pre-2024 `CON` rows preserved, 15 distinct teams, 0 duplicate `(game_id, team_id)` pairs, 2020 bubble season = 294 rows (present, not dropped), player-feature/box row counts match exactly (3,906 = 3,906). |
| 2.2 | ESPN rosters | **PASS** | 209 rows, 15/15 teams, roster sizes 12–15 (non-uniform — consistent with real churn, not a fabricated fixture), 0 `NA` player IDs. |
| 2.3 | ESPN injuries | **PASS** | `data_source` is uniformly `"LIVE_ESPN"`, n=42, 0% NA player_id, all team names resolve into `WNBA_TEAMS`, player set is not the 6-name synthetic fallback. |
| 2.4 | Odds API | **PARTIAL / EXPECTED FALLBACK** | `ODDS_API_KEY` confirmed empty in this environment. Live run of `market_odds_engine.R` (via the full pipeline) correctly took the `SYNTHETIC_FALLBACK` fixture-slate branch, matching T4's Handoff Notes exactly. A live in-season API ground-truth comparison (test 2.4.2/2.4.5/2.4.6, and smoke-test step 10) **could not be executed** — no key available in this sandboxed environment. This is a genuine, disclosed gap, not a fabricated pass. |
| 2.5 | Shot-location source | **PASS (by design)** | `shot_quality_engine.R`'s header explicitly and repeatedly discloses synthetic-by-design status; confirmed no "live" mislabeling anywhere in the file. |
| 3 | WNBA-specific regressions | **PASS** | Rotation cap (`WNBA_ROTATION_SIZE <- 8`, centralized in `config.R`, used identically by `roster_bottom_up_engine.R` and `player_props_engine.R`); grepped all `.R` files for `2880`/NBA's `240`-team-minutes/`11.2`/`11.8` — every surviving hit is in a comment referencing the NBA original, none live; zero-sum standings invariant holds (330.1 ≈ 330); team count is 15 everywhere checked (config, ARENA_DB, `team_embeddings.py`'s `WNBA_TEAM_COUNT=15`); `load_wnba_team_box`/`load_wnba_player_box` are called only from `daily_ingest.R`/`player_metrics.R`; `WNBA_MARGIN_SIGMA` is a real empirically-derived constant (14.0, `sd()` of 1,953 real home-margin rows), not a bare TODO. |
| 4 | Off-season handling | **PASS (code-level only)** | `app.R`'s `is_wnba_in_season()` and the season-window guard in `schedule_daily.bat` were verified by direct code reading (both are pure local-date checks, May–Oct window, matches confirmed 2026 season dates). Actually toggling the system clock to force the off-season branch and re-observing the UI was **not performed** (would require mocking `Sys.Date()` inside a live Shiny session — out of scope for a non-interactive check); the branch logic itself was read and is unambiguous. |
| 5 | Dashboard (`app.R`) | **PASS on 7/8 tabs, 1 confirmed-still-broken** | Verified by direct code reading (no browser available in this environment) that every tab's reactive reads the real cache path it claims (`cache/latest_value_bets.rds`, `cache/odds_history.rds`, `cache/injury_data_cache.rds`, `cache/risk_state.rds`/`cache/betting_ledger.rds`, `team_embeddings.csv`/`team_similarity_matrix.csv`, `cache/projected_wnba_standings.rds`, `latest_player_props.rds`). Tab 5 (Team Embeddings) is confirmed genuinely fixed — reads `team_embeddings.csv`'s real 16-D vectors via `prcomp()`, not the old shot-quality mislabeling bug. **Tab 6 (Model Calibration) is confirmed still the known NBA-inherited bug** — `plot_calibration_curve` generates a hardcoded `seq()` + `rnorm()` cosmetic curve, never touches `live_calibration.R`'s real `calibration_analysis()` function; the file's own comment at that block says as much. Zero-live-API-on-load invariant holds (every reactive's live-network fallback (`source("market_odds_engine.R")`) only fires if the cache is missing, which it wasn't during this check). Interactive browser rendering was **not tested** (no display available). |
| 6 | Runnable smoke tests | **EXECUTED — see per-item results in §2/§3 above and inline in §6 below** | All of Phase A, B (T2), and D (T5) were actually run via `Rscript.exe` in this session with real output captured. Phase C (steps 9–11, live Odds API) could not be executed — no `ODDS_API_KEY`. |
| 7 | Synthetic-data audit table | **UPDATED** | See the reconciled table below — classifications confirmed against real, executed T0–T5 output rather than the plan's pre-build guesses. One real, previously-undocumented gap found in this pass: `risk_management_engine.R` still points at the dead `cache/bet_log.rds` path (not `cache/betting_ledger.rds`, which `bet_tracker.r` actually writes) — confirmed by grep, not just inherited by assumption. This is a known, disclosed, not-yet-fixed gap per T4's own Handoff Notes (explicitly out of scope for T4's brief), reconfirmed still present here. |

**What genuinely could not be executed in this environment (stated explicitly, not glossed over):**
- Any live `ODDS_API_KEY` round-trip (no key set anywhere in this sandbox).
- `app.R` as an actual rendered browser session (no display/browser available to this agent).
- `schedule_daily.bat` as a registered live Windows Task Scheduler trigger (requires a human/operator
  action on the host).
- Forcing `Sys.Date()` to an off-season value inside a live interactive Shiny session to visually
  confirm the banner swap (the underlying date-comparison logic was read and is unambiguous, but this
  is not the same as watching the UI actually re-render).
- Knitting `WNBA_Analysis_Project.Rmd` (no Pandoc install in this environment either, same blocker T2
  hit).

**Bugs/gaps found in this verification pass that were not already flagged by T0–T5:** none new of
real substance — every discrepancy found while re-executing (rotation-cap constant location, dead
`bet_log.rds` path, Tab 6 calibration bug, `run_full_pipeline.R`'s actual `[COMPLETED]`/`[FAILED]` log
strings differing from this plan's original guess) was already disclosed somewhere in T2/T4/T5's own
Handoff Notes; this pass's job was independent re-verification against running code, which it passed
in every case it could check.

---

**Purpose.** This document is a testing/verification plan, not pipeline code. It exists because the
NBA original (see `REPO_MAP.md`) has a deliberate fail-safe design: almost every ingestion/engine
script checks for a live source or cache and silently falls back to fabricated data
(`set.seed(42)`, `rnorm`/`rpois`/`runif`, hardcoded fixtures) rather than crashing. **"The pipeline
ran without errors" does not mean real data was used.** The single job of this test plan is to give a
human or agent a mechanical way to tell the difference, specifically for the WNBA port, where the
risk is worse than the NBA original because of longer off-season dead time, thinner betting markets,
shorter historical depth, no real RAPM stint data, an actively-changing team count, and sparser
injury reports (`WNBA_REPLICATION_PLAN.md` §(e)).

**Provenance note (superseded — kept for history, see Execution Log above for current status).**
This plan was originally written on 2026-09-12 with only T0/T1 complete; Sections 2–7 were drafted
from `WNBA_REPLICATION_PLAN.md`/`agent3.md`–`agent6.md` briefs rather than code inspection, and were
tagged `[FROM PLAN/BRIEF — NOT YET BUILT]` accordingly. **T2–T5 are now complete** (per
`task_assignments.md`'s Handoff Notes, all statuses `done`), this whole document has been
re-executed against the real, running code in this same session, and every stale tag below has been
removed and reconciled — see the Execution Log at the top of this file for the pass/fail summary.

Real constants used throughout (from `config.R` as it stands post-T4, do not substitute the plan
document's earlier placeholder guesses — several changed again after T0 wrote its first draft):
- `WNBA_TEAMS` — 15 entries: `ATL, CHI, CON, DAL, GS, IND, LV, LA, MIN, NY, PHX, POR, SEA, TOR, WSH`
  (not 13 as the original plan draft guessed before T0's validation).
- `WNBA_TEAM_COUNT <- 15`, `WNBA_ROSTER_MAX <- 12`, `WNBA_GAME_MINUTES <- 40`,
  `WNBA_SEASON_GAMES <- 44`, `HISTORICAL_SEASONS <- 2019:2025`, `CURRENT_SEASON <- 2026`,
  `ALL_SEASONS <- 2019:2026`.
- `ROLLING_WINDOW_SIZE <- 13` — **changed from T0's original placeholder of 9** by T2, after actually
  re-running the NBA Rmd's window-size sweep (5/7/9/11/13) on real 2026-season holdout data; 13 won on
  ROC-AUC (0.673) and Brier (0.226), monotonically better than 9 (0.644/0.233). Not confirmed to be a
  global optimum (the sweep didn't test beyond 13) — treat as current-best-of-tested, not final.
- `WNBA_MARGIN_SIGMA <- 14.0` — new in T2, empirically derived (`sd()` of 1,953 real home-team-game
  margins, 2019–2026), replacing the NBA original's hardcoded 11.8/11.2. Used by
  `roster_bottom_up_engine.R`, `market_odds_engine.R`, `playoff_simulator.R`, `live_game_listener.R`,
  and `app.R`'s Tab 7 matchup calculator — verified via grep that no live inline `11.2`/`11.8` survives
  anywhere outside a comment.
- `WNBA_ROTATION_SIZE <- 8` — new in T4, centralized in `config.R` (originally defined only inside
  `roster_bottom_up_engine.R` by T2; T4 moved it to `config.R` when `player_props_engine.R` also needed
  it). Not yet empirically validated against real per-player minutes distributions — flagged as future
  work by both T2 and T5.
- Standings cache: `cache/projected_wnba_standings.rds` (T2's real filename, confirmed — NOT the NBA
  name `projected_30_team_standings.rds`).
- Playoff format: **not** a blanket best-of-7. `playoff_simulator.R` implements a `PLAYOFF_FORMATS`
  registry — First Round bo3 (1-1-1), Semifinals bo5 (2-2-1), Finals bo7 (2-2-1-1-1) — verified via
  web search by T5 against the real 2025+ WNBA postseason format change.
- R install: **`C:\Program Files\R\R-4.5.2\bin\Rscript.exe`** (not on `PATH` — T0 found this; use the
  full path in every command below).
- Working directory: `C:\Users\kailo\kayceeslices\WNBA Analytics`.

---

## 1. Pipeline Liveness Tests (`run_full_pipeline.R`)

**Status: RECONCILED AND EXECUTED (2026-09-12, post-T5).** `run_full_pipeline.R` exists and was run
live in this session (`Rscript.exe run_full_pipeline.R`, exit code 0, 10.44s total). It reproduces the
NBA original's `run_stage(script_name, description)` wrapper: each stage is `source()`d inside a
`tryCatch`, and a missing-file stage (`rapm_engine.R`, never ported) is caught by a separate
`file.exists()` guard that emits a `warning()` and returns `FALSE` rather than stopping the run.

**Real log-line pattern (corrects the plan's original guess):** the wrapper does NOT print
`[STAGE OK]`/`[STAGE FAILED]` — the actual strings are `>>> [STAGE] <description> (<script_name>)...`,
`>>> [COMPLETED] <script_name> in <N> seconds.` on success, and a `warning(">>> [FAILED] <script_name>: <message>")`
on a caught error (or a plain `warning("Script ... not found ... Skipping.")` for a missing file).
**Actual run result:** 12 `[COMPLETED]` lines, 0 `[FAILED]` lines, 1 expected skip-warning
(`rapm_engine.R`) — matches all 13 wired stages exactly (12 real + 1 documented-absent).

Tests below, now executed:

1. **Per-stage exit evidence, not just overall exit code.** DONE — grepped `pipeline_execution_test.log`
   for `\[COMPLETED\]`/`\[FAILED\]`: 12/0. Confirmed against the real log strings above, not the plan's
   original `STAGE OK`/`STAGE FAILED` guess (updated here so a future re-run's grep pattern is correct).
2. **Cache-freshness cross-check per stage.** DONE — `ls -la` on all 13 stage-owned cache files
   post-run showed every one advanced to the run's own timestamp (~01:10 in this session), including
   `cache/latest_value_bets.rds`, `cache/copula_wilson_pra.rds`, `cache/risk_state.rds`,
   `cache/rolling_bet_metrics.rds`, `cache/playoff_series_wnba_demo.rds` — no stage's cache was left
   stale while its stage logged `[COMPLETED]`.
3. **Row-count delta check for accumulating caches.** `box_scores_cache.rds` and
   `cache/player_box_scores_cache.rds` should never shrink between two successive daily runs during
   the season, and should grow by a plausible number of new team-game rows (0–30, i.e. at most the
   number of games played across all 15 teams since the prior run) — not by hundreds (would suggest a
   duplicate historical re-bootstrap silently re-triggered) and not by zero every single day during the
   season (would suggest the incremental-update branch is broken and always falling through to
   "no records returned").
4. **Deliberate stage-failure injection.** Temporarily rename one dependency (e.g. rename `config.R`'s
   `WNBA_TEAMS` variable in a scratch copy, or point `CACHE_TEAM_BOX` at a nonexistent path) and
   confirm the full-pipeline run (a) does NOT silently produce a "success" summary line for that stage,
   and (b) does NOT crash the entire orchestrator — i.e., verify both halves of the fail-safe contract,
   not just that it doesn't crash.
5. **Total-elapsed-time sanity.** The NBA original prints elapsed time per stage and total. A stage
   that always completes in <0.5s during the season (e.g. `sync_rosters.R`, which should take several
   seconds for 15 sequential network calls with `Sys.sleep(0.05)` between them) is a red flag that it
   short-circuited to a cached/synthetic path instead of doing real I/O — cross-reference against
   §2's timing checks below.

---

## 2. Per-Data-Source "Real vs. Synthetic" Verification Tests

### 2.1 wehoop team/player box scores (`daily_ingest.R`, `player_metrics.R`) — `[VERIFIED AGAINST CODE]`

Real functions: `daily_box_ingest()`, `get_player_box_scores_chunked()`, `filter_real_franchises()`,
`normalize_team_abbreviation()`. Real caches: `box_scores_cache.rds` (root, `CACHE_TEAM_BOX`),
`cache/player_box_scores_cache.rds` (`CACHE_PLAYER_BOX`).

There is no synthetic fallback in these two scripts today (unlike the NBA original's other engines) —
the failure mode here is not "fabricated data" but "silent exhibition-row contamination" or "stale
cache never refreshed." Tests:

1. **Exhibition-row leak check.** `readRDS(CACHE_TEAM_BOX) |> filter(!(team_abbreviation %in%
   names(WNBA_TEAMS))) |> nrow()` must be exactly `0`. Repeat for `opponent_team_abbreviation`. Repeat
   for `cache/player_box_scores_cache.rds`. A nonzero result means `filter_real_franchises()` was
   bypassed, is out of date against a new season's exhibition codes, or someone read raw
   `wehoop::load_wnba_team_box()` output directly without going through `daily_ingest.R`.
2. **CONN normalization regression check.** `readRDS(CACHE_TEAM_BOX) |> filter(team_abbreviation ==
   "CONN") |> nrow()` must be `0` (should always be normalized to `CON`), AND
   `readRDS(CACHE_TEAM_BOX) |> filter(team_abbreviation == "CON", season <= 2023) |> nrow()` must be
   `> 0` (i.e. pre-2024 Connecticut Sun rows must still be present after normalization, not
   accidentally dropped by an over-eager filter). This specifically guards against a future agent
   "fixing" the exhibition filter and reintroducing the bug T1 found and fixed.
3. **Team-count / row-count sanity bounds.** `readRDS(CACHE_TEAM_BOX)$team_abbreviation |> unique() |>
   length()` must equal exactly `WNBA_TEAM_COUNT` (15) for the current season's rows — not 13 (the
   plan's outdated guess), not 30 (an NBA leftover), not more (unfiltered exhibitions) or fewer
   (broken franchise, e.g. a merger/relocation not yet reflected in `WNBA_TEAMS`).
4. **No duplicate `(game_id, team_id)` pairs**: `readRDS(CACHE_TEAM_BOX) |> count(game_id, team_id) |>
   filter(n > 1) |> nrow() == 0`. A violation indicates the dedupe step in `daily_box_ingest()` broke.
5. **Freshness during season.** During the WNBA season window (~May–Oct), `max(game_date)` in
   `box_scores_cache.rds` should be within the last ~4 days of "today" if games have been played (cross
   check against ESPN's WNBA scoreboard for whether games actually occurred in that window before
   flagging staleness as a bug — a legitimate 3-day all-star-break gap is not a failure).
6. **Player/team row-count internal consistency.** `nrow(get_player_features())` (team-game
   aggregation from player box) should equal `nrow(box_scores_cache.rds)` exactly, as it did at T1
   validation (3,906 = 3,906). A divergence signals the two loaders are silently seeing different game
   universes (e.g. one still has an un-filtered exhibition code the other caught).
7. **2020 bubble season is not silently dropped.** `readRDS(CACHE_TEAM_BOX) |> filter(season == 2020) |>
   nrow()` should be materially smaller than other seasons (T1 observed 294 rows / ~22-game bubble
   schedule) but nonzero — a shortened real season should not be mistaken for a broken/empty pull and
   silently excluded from `HISTORICAL_SEASONS`.

### 2.2 ESPN WNBA rosters (`sync_rosters.R`) — `[VERIFIED AGAINST CODE]`

Real function: `sync_active_rosters()`. Real cache: `cache/active_rosters_cache.rds`. No synthetic
fallback exists in this script (it `stop()`s on team-endpoint failure rather than fabricating a
roster) — so the failure mode to test for is a **partial** roster sync silently passing as complete.

1. **Team coverage.** `readRDS(...) |> distinct(team_abbreviation) |> nrow()` must equal
   `WNBA_TEAM_COUNT` (15). Fewer means some per-team roster call in the `for` loop hit its `tryCatch`
   `NULL` branch (`next`) and was silently skipped — check the console log for the corresponding
   "0 athletes" or timeout gap.
2. **Roster size distribution.** `readRDS(...) |> count(team_name) |> pull(n) |> range()` — T1's real
   run showed ~13.9 average (some teams >12 due to in-season churn), which is expected, not a bug.
   Flag as suspicious: any team with 0 players (dropped roster call), or **every** team showing exactly
   the same round number (e.g. all exactly 12) — a suspiciously uniform count across all 15 teams is
   more consistent with a fabricated fixture than real roster churn.
3. **Unknown-abbreviation warning check.** Grep the run's console/log output for the
   `"ESPN returned team abbreviation(s) not in config.R's WNBA_TEAMS"` warning string emitted by
   `sync_active_rosters()`. Its presence means a new/renamed franchise appeared and `WNBA_TEAMS` in
   `config.R` needs a manual update — treat this warning as a build-breaking signal in CI/smoke-test
   context, not just an informational log line.
4. **Player-ID join validity for downstream consumers.** `readRDS(...)$player_id |> is.na() |> any()`
   should be `FALSE`; every row's `player_id` should be a plausible ESPN athlete ID (positive integer,
   typically 6–7 digits for current players).
5. **Timestamp/staleness.** Compare `file.mtime("cache/active_rosters_cache.rds")` to the last pipeline
   run time; a roster cache older than a few days during the season (when trades/signings occur) with
   no re-sync attempted is a staleness bug, not a source-availability bug (the endpoint is public and
   keyless, so failures here are almost always transient network issues, not off-season dead time).

### 2.3 ESPN WNBA injuries (`injury_scraper.R`) — `[VERIFIED AGAINST CODE]`

Real function: `fetch_live_wnba_injuries()`. Real cache: `cache/injury_data_cache.rds`, which
(unlike the NBA original) has an explicit **`data_source` column** (`"LIVE_ESPN"` vs
`"SYNTHETIC_FALLBACK"`) — this is the single cleanest real-vs-synthetic signal in the entire repo and
every test below should key off it first before falling back to heuristic signature-matching.

1. **Primary check — trust the label, but verify it isn't lying.** `readRDS(...)$data_source |>
   unique()` should be a single value per run (`"LIVE_ESPN"` or `"SYNTHETIC_FALLBACK"`), never mixed
   (the code either takes the live branch or the fallback branch, not both) and never missing/`NA`
   (would mean an older/broken version of the script ran). If `"LIVE_ESPN"`, proceed to check 2; if
   `"SYNTHETIC_FALLBACK"`, proceed to check 3.
2. **If labeled LIVE_ESPN, verify it is not accidentally the fallback content mislabeled.** Assert
   `nrow() >= MIN_PLAUSIBLE_INJURY_ROWS` (5) — this should be true by construction of the code path,
   but a direct assertion catches a future refactor bug. Assert the row set is **not** exactly the
   6-player fallback roster (`setequal(player_name, c("A'ja Wilson","Caitlin Clark","Breanna Stewart",
   "Napheesa Collier","Brittney Griner","Angel Reese"))` must be `FALSE`, or at minimum the row count
   must differ from exactly 6 with exactly those 6 names — a coincidental partial overlap is fine, an
   exact-set match is a red flag that the label and content have desynced). Assert `player_id` values
   are plausible extracted-from-URL integers (not the 6 hardcoded IDs `3149391, 4433403, 2998928,
   3917450, 2490553, 4433402` verbatim as the entire set).
3. **If labeled SYNTHETIC_FALLBACK, verify the trigger was legitimate.** Cross-reference with §1's
   `[STAGE OK]` log line and the console output for either the `"[OFFSEASON INFO]"` or
   `"[FEED WARNING] Live feed returned only N row(s)"` message — one of these two must be present. If
   neither appears in the log alongside a `SYNTHETIC_FALLBACK` cache, something is wrong with the
   logging, not just the data. During the confirmed in-season window (May–Oct), a `SYNTHETIC_FALLBACK`
   result should be treated as a **live incident to investigate**, not a normal daily occurrence — alert
   on this condition rather than silently accepting it (see §4 for the broader off-season-vs-in-season
   distinction).
4. **Athlete-ID extraction regression check.** Because the WNBA injuries feed has no top-level
   `athlete$id` (a genuine schema difference from NBA, fixed via
   `extract_athlete_id_from_links()` regex-parsing the "Player Card" href), assert
   `readRDS(...) |> filter(data_source == "LIVE_ESPN") |> pull(player_id) |> is.na() |> mean()` is
   `0` (or very close to it) — a nonzero rate of `NA` player IDs on live rows means the href regex
   broke (e.g. ESPN changed its link URL format), which would silently degrade downstream join quality
   against rosters/box scores without failing the pipeline.
5. **Cross-source consistency.** Every `team_name` in a `LIVE_ESPN`-labeled injury cache should appear
   in `WNBA_TEAMS` values (`unname(WNBA_TEAMS)`) — `setdiff(readRDS(...)$team_name,
   unname(WNBA_TEAMS))` should be empty. Every `player_name` should ideally also appear in
   `cache/active_rosters_cache.rds$player_name` for the same team (allow a small mismatch rate for
   recently-waived/signed players, but a majority mismatch indicates broken team resolution).

### 2.4 The Odds API — betting lines (`market_odds_engine.R`) — RECONCILED, PARTIALLY EXECUTED

T4 built this exactly per `agent5.md`: sport key `basketball_wnba`, env var `ODDS_API_KEY` (not the
NBA original's `THE_ODDS_API_KEY`), fixture fallback rewritten with real 2026 WNBA teams (Storm/Lynx,
Sparks/Aces, Mystics/Liberty, Sky/Dream, Wings/Mercury, Sun/Fever). **Executed in this session:**
`Sys.getenv("ODDS_API_KEY","")` confirmed empty; ran the full pipeline live and confirmed
`market_odds_engine.R` printed `[FEED NOTICE] ODDS_API_KEY not set` and took the
`SYNTHETIC_FALLBACK`-labeled branch, producing real computed EV/CLV/Kelly numbers on top of the
fabricated odds slate, written to `cache/latest_value_bets.rds`/`cache/odds_history.rds` (both files'
mtimes advanced with the run). **Not executed — genuinely cannot be in this environment:** any test
requiring a real key (direct API smoke test, live-vs-fixture comparison, sharp-book detection rate).
Tests below, updated to reflect what was actually checked:

1. **Env var presence check, independent of any network call.** DONE — confirmed empty in this
   environment; the fallback branch firing is therefore expected/correct behavior, not a bug.
2. **Direct API smoke test, bypassing the pipeline.** Independently curl/`httr2::request()` 
   `https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=$ODDS_API_KEY&regions=us&markets=h2h`
   and assert HTTP 200 AND `length(bookmakers) > 0` for at least one event, during the WNBA season.
   Compare this ground truth against what `cache/latest_value_bets.rds` actually contains for the same
   date — if the direct call succeeds with real data but the cache shows the fixture slate's known
   signature (see #3), the pipeline's call is failing silently (bad header, wrong param, quota
   exhausted) even though the key is valid.
3. **Fixture-signature negative check.** Identify the exact hardcoded fallback matchups/odds T4 writes
   (record them once T4's code exists) and assert, during the season, that `cache/latest_value_bets.rds`
   does NOT exactly equal that fixture's team pairs/odds/timestamps. Off-season, the fixture appearing
   is expected and should instead be checked against §4 (transparent labeling), not treated as a bug.
4. **Team-abbreviation cross-consistency.** Every team name appearing in `latest_value_bets.rds` /
   `odds_history.rds` must resolve to a `WNBA_TEAMS` entry (join or `%in%` check) — a team name that
   doesn't match indicates either a devigged-fixture leak or an unmapped ESPN/Odds-API naming variant
   (e.g. "LA Sparks" vs "Los Angeles Sparks").
5. **Sharp-book detection rate, expected to be low.** Log and track, across days, what fraction of
   games have zero sharp books (`pinnacle`/`circa`/`lowvig`/`betonlineag`) present in `bookmakers[]`.
   Per the plan, expect this to be **materially higher** than the NBA original — treat a persistently
   100% zero-sharp-book rate as expected market thinness, not a parsing bug, but verify at least
   occasionally that some non-zero rate exists by manually inspecting a raw API response during a
   marquee game (e.g. Finals) to confirm the parsing key names themselves are still correct.
6. **Timestamp freshness of `odds_history.rds` snapshots.** Each pipeline run during the season should
   append a new timestamped snapshot; two consecutive snapshots with byte-identical odds for every game
   is not automatically a bug (lines can be genuinely static) but two consecutive snapshots with
   **identical `fetched_at` timestamps** would indicate the append step isn't running the network call
   at all.

### 2.5 Shot-location source — CONFIRMED SYNTHETIC-BY-DESIGN (verified against real `shot_quality_engine.R`)

Per the replication plan §(e) risk #7, there is **no real, free, keyless WNBA shot-chart API** — the
plan explicitly keeps `xpoints_engine.R`/`shot_quality_engine.R`'s WNBA versions synthetic-only by
design, same as the NBA original's already-synthetic state. **No "real vs synthetic" test applies
here** — this is a designed-permanent-synthetic case (see §7's classification table). The only test
that matters: confirm the code comments in the ported `shot_quality_engine.R` explicitly state this is
synthetic-by-design (per `agent4.md`'s constraint), so a future maintainer doesn't mistake its output
for validated shot-location analytics. Flag as a FAIL only if a future agent claims/labels this
output as "live" or removes the synthetic-disclosure comment.

---

## 3. Regression/Edge-Case Tests Specific to WNBA Differences

These verify WNBA-specific constants actually took effect where they are load-bearing, not just
present in `config.R`.

1. **Roster cap enforcement in modeling, not just raw cache.** `roster_bottom_up_engine.R`'s
   `compute_team_live_rating()` (once T2 exists) should select at most the chosen rotation depth
   (top-7 or top-8 per `agent3.md` — check T2's actual Handoff Notes for which was picked) — assert
   programmatically that the function never allocates minutes to more than that many players per team,
   even though `active_rosters_cache.rds` itself legitimately has up to ~14 players/team (roster churn,
   see §2.2 #2) — the cap applies to the *rotation selection*, not the raw roster size.
2. **40-minute game clock took effect everywhere it should.** Grep every WNBA `.R` file for the literal
   `2880` (NBA's 48×60 seconds) and `240` (NBA's 48×5 team-minutes) — any surviving occurrence outside
   of a comment referencing the NBA original is a porting miss. Confirm `live_game_listener.R`'s
   `calc_live_win_prob()` uses `2400`, and `roster_bottom_up_engine.R`'s `tot_proj_min` uses `200`, not
   the NBA values.
3. **Season-game-count / zero-sum invariant.** Once `roster_bottom_up_engine.R`'s
   `project_all_wnba_teams()`-equivalent runs, assert `sum(standings$wins) == WNBA_SEASON_GAMES *
   WNBA_TEAM_COUNT / 2` exactly (44 × 15 / 2 = 330) — NOT the NBA's 1230. A leftover `82` or `30`
   anywhere in this formula will silently produce a standings table that looks plausible but is
   numerically wrong (odd totals, non-zero-sum wins).
4. **Team count is 15, not 13 or 30, everywhere it's checked.** Any script/cache that enumerates teams
   (`ARENA_DB`, synthetic roster generators in `player_props_engine.R`/`shot_quality_engine.R`,
   `team_embeddings.py`'s embedding table dimension) must have exactly 15 rows/entries. This directly
   catches the specific documented risk that the plan's early draft guessed 13 teams before T0's
   empirical validation found 15 (including the 2026 Toronto Tempo/Portland Fire expansion franchises)
   — grep for the literal `13` as a team-count constant anywhere outside historical commentary/comments
   as a specific regression signature of this exact mistake recurring.
5. **Exhibition-row filter is applied by every consumer, not just `daily_ingest.R`/`player_metrics.R`.**
   Any *new* script written in T2–T5 that reads `box_scores_cache.rds` or
   `cache/player_box_scores_cache.rds` directly (rather than through the two ingestion functions) should
   be checked for its own redundant `team_abbreviation %in% names(WNBA_TEAMS)` guard, or at minimum
   verified that it only ever consumes the already-filtered cache and never re-pulls raw wehoop data
   independently. Concrete test: `grep -rn "load_wnba_team_box\|load_wnba_player_box" *.R` should show
   these functions called **only** from `daily_ingest.R` and `player_metrics.R` — any other file calling
   them directly is a new, unfiltered entry point for exhibition-row contamination and should fail
   review.
6. **CONN/CON normalization applied consistently.** Since T1 found and fixed this in exactly two files
   (`daily_ingest.R`, `player_metrics.R`), any future script that independently loads/re-derives team
   abbreviations from raw box data (rather than reading the already-normalized cache) needs the same
   `normalize_team_abbreviation()` call — audit for this specifically if T2–T5 ever bypass the cached,
   normalized data.
7. **`WNBA_MARGIN_SIGMA` is not silently treated as validated.** Per `agent3.md`, T2 is expected to add
   a `WNBA_MARGIN_SIGMA` constant with an explicit `# TODO: re-derive via sd() of real WNBA home-margin
   residuals` comment rather than reusing NBA's 11.2/11.8. Test: grep for `11.2` and `11.8` (the NBA
   sigma values) anywhere in WNBA `.R` files — any survival outside a comparison/comment is a silent
   reuse of an NBA-fit constant presented as WNBA-appropriate. Separately, confirm the TODO comment is
   still present (i.e., no one has silently "resolved" it by picking an arbitrary number without an
   actual `sd()` computation against real margin data — check for evidence of an actual empirical
   derivation, e.g. a comment citing an `n=` sample size and a computed value, versus a bare number).

---

## 4. Off-Season / Low-Data-Availability Handling Tests

The WNBA season runs roughly May–October; the rest of the year should produce transparent, clearly
labeled degraded behavior — never data that looks live but isn't.

1. **Dashboard banner presence (once `app.R`/T5 exists).** During a simulated or actual off-season
   date, load `app.R` and assert a visible banner/message state (e.g. "WNBA season inactive") is
   rendered — per `agent6.md` item 6, this is an explicit deliverable, not optional. Test by
   temporarily faking `Sys.Date()` (via a wrapper/mock, or by checking the off-season detection logic's
   date-range condition directly) to fall outside the season window and confirming the UI element
   appears; then faking an in-season date and confirming it does NOT appear.
2. **No masking of synthetic/stale data as live during the banner state.** When the off-season banner
   is showing, cross check that any concurrently displayed numbers (e.g. standings, odds) are explicitly
   labeled as "last completed season" or similarly dated — not presented with the same styling as live
   in-season data. This should be a code-level check (grep `app.R` for whether the off-season branch
   reuses the exact same render function/CSS class as the live branch, which would defeat the purpose
   of the banner) in addition to a visual check.
3. **`injury_scraper.R`'s off-season fallback message differentiation.** Confirm the console/log output
   distinguishes `"[OFFSEASON INFO]"` (literal 0 rows — true off-season) from
   `"[FEED WARNING] ... unreliable/partial snapshot"` (in-season but sparse feed) — these are
   semantically different failure modes (§2.3) and a monitoring/alerting layer should treat them
   differently: the former is expected 6+ months a year, the latter should raise attention during a
   confirmed in-season window.
4. **`market_odds_engine.R` off-season fixture behavior.** During the off-season, confirm the fixture
   fallback is clearly tagged (e.g. a `data_source`/`is_fixture` column analogous to the injury cache's
   pattern — recommend T4 add one if not already present, per the injury cache's superior labeling
   precedent) rather than silently indistinguishable from a live pull once written to
   `cache/latest_value_bets.rds`.
5. **Season-boundary transition test.** Pick a date range spanning the actual WNBA season start/end
   (verify current-season dates via the same method T5 used) and confirm the pipeline's behavior
   changes at the boundary — no live data appearing before the season starts, and no abrupt masking of
   real end-of-season data as "off-season" while playoffs are still live (the plan notes playoffs run
   into October, so "off-season" detection must account for the playoff tail, not just the labeled
   regular-season window).
6. **`schedule_daily.bat` seasonal guard, if implemented.** Per `agent6.md` item 4, verify (once T5
   exists) that running the `.bat` outside the season window either skips the pipeline with a clear log
   entry, or runs it but the downstream off-season detection (items 1–2 above) correctly labels the
   result — either is acceptable, but silent full-cost daily execution against dead off-season data with
   no differentiation from an in-season run is the failure mode to catch.

---

## 5. Dashboard / `app.R` Verification

**Status: RECONCILED AND VERIFIED BY DIRECT CODE READ (2026-09-12).** `app.R` exists (T5, 8 tabs).
No interactive browser session was run (no display in this environment), so this section's checks
were done by reading `app.R`'s actual `server`/`ui` code end-to-end rather than clicking through a
live UI — every claim below traces to a specific line/block in the real file, not the plan document.

Confirmed: **Tab 5 "Team Embeddings" is genuinely fixed** — reads `team_embeddings.csv` (real 16-D
`emb_1..emb_16` columns), PCA-projects via `prcomp()`, and separately renders
`team_similarity_matrix.csv` as a cosine-similarity heatmap; the old NBA bug (plotting
`team_shot_quality.rds` mislabeled as embeddings) is not present. **Tab 6 "Model Calibration" is
confirmed STILL the known NBA-inherited bug** — `output$plot_calibration_curve` builds its curve from
`probs <- seq(0.35, 0.75, by = 0.08); actual <- probs + rnorm(...)`, a hardcoded fake curve with a
comment in the file itself acknowledging this is "not wired to real model predictions ... out of
scope for this port per the T5 brief." `live_calibration.R`'s real `calibration_analysis()` exists in
the repo but Tab 6 never calls it. This matches T5's own Handoff Notes, which explicitly said the
brief never asked for this fix — reconfirmed here against the actual file, not assumed.

Checklist to run against the finished `app.R` (per tab, mapping to the NBA original's 8 tabs):

1. **Tab 1 (Daily Actionable Edges)** — confirm the reactive reads `cache/latest_value_bets.rds` and
   that the rendered table's row count/content changes when that file's mtime/content changes (not a
   static example table). Kill the cache file temporarily and confirm the tab shows an explicit
   "no data" state, not a hardcoded example row set masquerading as live.
2. **Tab 2 (Steam Radar & Line Movement)** — confirm it derives from `cache/odds_history.rds`
   timestamps, not a fixed synthetic drift curve; verify by appending a synthetic new snapshot with a
   distinctive test value and confirming the chart updates.
3. **Tab 3 (Injury & Load Monitor)** — confirm it reads `cache/injury_data_cache.rds` **and displays
   the `data_source` column** (or at least visually differentiates LIVE_ESPN vs SYNTHETIC_FALLBACK rows)
   — this is a natural, cheap place to surface the real-vs-synthetic signal directly to a human user,
   and its absence should be flagged as a missed opportunity given the cache already carries the label.
4. **Tab 4 (Bet Tracker & Performance Audit)** — confirm KPI boxes derive from
   `cache/risk_state.rds`/`cache/betting_ledger.rds` and change when the ledger changes (append a test
   PENDING row via a scratch script and confirm the rolling metrics shift accordingly, then remove it).
5. **Tab 5 (Team Embeddings & Similarity)** — **specifically verify this is NOT the NBA bug**: the plot
   must be generated from `team_embeddings.csv`'s actual 16-D (or whatever T3 chose) vectors — e.g. a
   PCA/t-SNE 2D projection or a `team_similarity_matrix.csv`-derived heatmap — not a shot-quality
   scatter. Concrete test: perturb one team's embedding vector in the CSV by a large, distinctive
   amount and confirm that team's plotted position/similarity visibly changes; a tab that doesn't react
   to this change is still reading from the wrong source.
6. **Tab 6 (Model Calibration & Reliability)** — **specifically check whether this is still the NBA
   bug**: confirm the curve is generated from `live_calibration.R`'s `calibration_analysis()` function
   applied to real model-vs-outcome data, not a hardcoded/simulated curve. If T5's Handoff Notes don't
   mention touching this tab, assume it's still broken and flag it explicitly in any status report
   rather than silently assuming it was fixed as a side effect of the general port.
7. **Tab 7 (Standings & Matchup Calc)** — confirm it reads T2's actual standings-cache filename (check
   Handoff Notes — plan suggests `cache/projected_wnba_standings.rds`) and that the interactive
   home/away picker's computed spread/win-prob uses `WNBA_MARGIN_SIGMA` (§3 item 7), not a leftover NBA
   sigma constant re-implemented inline (the NBA original independently re-implements
   `get_fair_spread()`'s math inline in `app.R` — check the WNBA port didn't copy the NBA sigma into
   that inline copy while correctly updating the source engine file).
8. **Tab 8 (Player Props Terminal)** — confirm it reads `latest_player_props.rds`/
   `cache/latest_player_props.rds` and that ZINB density plots respond to real roster changes (once
   the roster-filename mismatch bug from `REPO_MAP.md` §6/§9 is fixed per `agent5.md`'s T4 task —
   verify this fix actually landed by checking whether `player_props_engine.R` reads the exact same
   filename `sync_rosters.R` writes, `cache/active_rosters_cache.rds`, not a mismatched
   `active_rosters.rds`).
9. **Off-season banner** — see §4 item 1; re-list here as a dashboard-specific checklist item since it's
   part of `app.R`'s own rendering logic.
10. **Zero-live-API-on-load invariant.** Per `REPO_MAP.md` §8 (ADR-08/T7 principle, explicitly
    preserved by the plan), confirm no reactive in the WNBA `app.R` performs a live HTTP call on
    startup/render — instrument or code-review every `reactive()`/`render*()` block for `httr`/`httr2`
    calls; any found is a regression from the NBA original's documented invariant.

---

## 6. Concrete, Runnable Smoke-Test Checklist

Ordered, literal commands. Use the confirmed R path throughout. Run from
`C:\Users\kailo\kayceeslices\WNBA Analytics` (adjust working directory as shown).

```powershell
$R = "C:\Program Files\R\R-4.5.2\bin\Rscript.exe"
$WD = "C:\Users\kailo\kayceeslices\WNBA Analytics"
```

**Phase A — EXECUTED in this session, real results (all read-only cache checks + one live full-pipeline
network run, no separate standalone T1-script re-runs beyond what the pipeline already triggers):**

1. Config sanity — EXECUTED. Real output: `15 15 44 12 40 14 13 8` (team count, team count constant,
   season games, roster max, game minutes, `WNBA_MARGIN_SIGMA`, `ROLLING_WINDOW_SIZE`,
   `WNBA_ROTATION_SIZE` — the last three constants didn't exist when this checklist item was first
   drafted; added here since they're now load-bearing). **PASS.**

2. Box-score cache exhibition/CONN checks — EXECUTED. Real output: `rows=3906`, `bad_teams=0`,
   `bad_opp_teams=0`, `CONN_rows=0`, `CON_pre2024_rows=203` (pre-2024 Sun data confirmed preserved,
   not dropped), `teams=15`, `dupe_game_team_pairs=0`, `season_2020_rows=294`,
   `max_game_date=2026-08-30`. Per-season counts: 2019=440, 2020=294, 2021=420, 2022=480, 2023=522,
   2024=526, 2025=622, 2026=602. **PASS.**

3. Player box internal-consistency check — EXECUTED. `player_feat_rows=3906`, `box_rows=3906`,
   `match=TRUE`. **PASS.**

4. Roster sync liveness + coverage — EXECUTED (read from the current on-disk cache, refreshed by this
   session's live `run_full_pipeline.R` run, which re-invokes `sync_rosters.R`). Real per-team counts:
   Atlanta 13, Chicago 14, Connecticut 14, Dallas 15, Golden State 15, Indiana 14, Las Vegas 14, LA 12,
   Minnesota 14, New York 14, Phoenix 14, Portland 15, Seattle 13, Toronto 14, Washington 14 — 15/15
   teams, range 12–15 (non-uniform, consistent with real churn), 0 `NA` player IDs. **PASS.**

5. Injury cache label + fallback-signature check — EXECUTED. Real output: `source=LIVE_ESPN`, `n=42`,
   `na_player_id_rate=0`, all 42 team names resolve into `WNBA_TEAMS`, and the 42-name player list is
   not the 6-name synthetic fallback set. **PASS** (in-season live path confirmed, not the fallback).

6. Fresh live re-run of T1 scripts — EXECUTED as part of the full `run_full_pipeline.R` run (steps 1–2
   of the DAG are `sync_rosters.R`/`injury_scraper.R`; `daily_ingest.R` itself is not part of the
   current DAG — `box_scores_cache.rds`'s mtime reflects T1's original ingestion run, not this
   session's pipeline run, since no stage re-triggers a full historical re-ingest). All cache mtimes
   for the stages that did run advanced to this run's timestamp. **PASS** for the stages actually wired
   into the DAG.

**Phase B — EXECUTED (T2 rating engine is complete):**

7. Standings zero-sum invariant — EXECUTED against the real filename
   `cache/projected_wnba_standings.rds` (confirmed correct, not a guess) using the real column name
   `Proj_Wins` (not `wins`, which doesn't exist in this schema — corrected here). Real output:
   `nrow=15`, `sum_wins=330.1`, `expected=330`. **PASS** (0.1 float/rounding noise, as T2's own Handoff
   Notes anticipated).

8. Rotation-depth cap check — VERIFIED BY CODE READ (not a live behavioral probe): grepped
   `roster_bottom_up_engine.R` and confirmed `slice_head(n = WNBA_ROTATION_SIZE)` (8) is the only
   rotation-selection call, and `WNBA_ROTATION_SIZE` is centrally defined in `config.R` (8) and
   consistently reused by `player_props_engine.R` (confirmed via its own live run: "120 players across
   15 teams" = 15 × 8). **PASS.**

**Phase C — T4 (market/odds) is complete, but this environment has no `ODDS_API_KEY` — steps 9–11
below could NOT be executed as live network tests, only as the "confirm the fallback fired correctly"
check that doesn't require a key:**

9. `ODDS_API_KEY` presence — EXECUTED. Real result: length 0 (confirmed empty via both `Sys.getenv()`
   in R and the shell env directly). Per the test's own logic, any "live-looking" odds output in this
   environment is guaranteed-fixture — confirmed true via the pipeline's console output (`[FEED NOTICE]
   ODDS_API_KEY not set`). **PASS on the presence-check itself; the "live" branch is untestable here.**

10. Direct API ground-truth check — **NOT EXECUTED.** No `ODDS_API_KEY` exists in this environment to
    make the call with; running this would just be a 401/missing-key error, not a meaningful test.
    Genuinely deferred to a future session/human with a real key, not fabricated as passed.

11. Pipeline-vs-ground-truth comparison — **NOT EXECUTED** for the same reason as #10 (nothing to
    diff against without a live key). `cache/latest_value_bets.rds` was inspected and confirmed to
    contain the expected `SYNTHETIC_FALLBACK`-derived rows (6 fixture games, real WNBA teams, e.g.
    Atlanta Dream Home +110 / EV +41.75%), consistent with T4's Handoff Notes.

**Phase D — T5 (orchestration/dashboard) is complete, EXECUTED:**

12. Full pipeline run with per-stage log check — EXECUTED for real. Real command run:
    `Rscript.exe run_full_pipeline.R > pipeline_execution_test.log 2>&1`, exit code 0. **Corrected log
    pattern** (the actual strings, not the plan's original `STAGE OK`/`STAGE FAILED` guess):
    ```
    Select-String -Path pipeline_execution_test.log -Pattern "\[COMPLETED\]|\[FAILED\]"
    ```
    Real result: 12 `[COMPLETED]` lines, 0 `[FAILED]` lines, plus 1 expected skip-warning for
    `rapm_engine.R` (never ported) — 12 completed + 1 documented-skip = all 13 wired DAG stages
    accounted for. **PASS.**

13. Shiny app cold-start, zero-live-call check — **PARTIALLY EXECUTED.** Could not launch an actual
    interactive Shiny session (no browser/display in this sandboxed environment) or monitor real
    outbound connections. Instead, `app.R` was fully read end-to-end: every `reactive()`/`render*()`
    block's data path was traced, and each one reads a local `cache/*.rds`/`.csv` file first, only
    falling through to `source("<engine>.R")` + a direct function call if that cache is missing (which
    it wasn't, in this session's state) — no reactive performs an unconditional `httr`/`httr2` call on
    load. This is a code-level verification of the same invariant the plan asked for, not a live
    network-monitor observation — flagged as the weaker of the two verification methods, not claimed
    as a full pass of "launched and watched no network activity."

---

## 7. Synthetic-Data Audit — Script Classification Table

Classification key: **(a)** must be verified live in-season (real failure mode this plan targets);
**(b)** legitimately synthetic-by-design, no real data source exists — acceptable permanently;
**(c)** synthetic-until-a-later-phase — real data path is known/possible but explicitly out of scope
for the current port. Pulled directly from `REPO_MAP.md`'s NBA-original analysis and
`WNBA_REPLICATION_PLAN.md`'s Tier 1/2/3 classification, not re-derived.

| Script | Class | Rationale |
|---|---|---|
| `daily_ingest.R` | (a) | Real `wehoop::load_wnba_team_box()`; verified live at T1, filtered/normalized. |
| `player_metrics.R` | (a) | Real `wehoop::load_wnba_player_box()`; verified live at T1. |
| `sync_rosters.R` | (a) | Real ESPN WNBA site-API rosters; verified live at T1, no synthetic fallback exists (hard `stop()` on total failure). |
| `injury_scraper.R` | (a) with labeled (b) fallback | Live ESPN WNBA injuries feed is primary and was verified live at T1 (`data_source=="LIVE_ESPN"`); its offseason/sparse-feed fallback is an explicitly labeled synthetic sample of real players — acceptable *as a labeled fallback*, but the live path must be verified in-season per §2.3. |
| `lineup_synergy.R` | (a) | Pure aggregation over real `player_metrics.R` output; no synthetic path (Tier 1 in plan, "no changes needed"). |
| `roster_dynamics.R` | (a) | Same as above — derived from real box/roster data. |
| `roster_bottom_up_engine.R` | (a) | The plan's "single most load-bearing script" — reads real player/roster/injury caches; core rating math is real, not synthetic. `WNBA_MARGIN_SIGMA` is now (a), not (c) — T2 actually empirically derived it (14.0, `sd()` of 1,953 real home-margin rows), confirmed by grep that no NBA 11.2/11.8 survives live anywhere. Re-verified live: real 2026 standings output (Minnesota Lynx / New York Liberty tied at top, ~34.9 proj wins), zero-sum invariant 330.1 ≈ 330. |
| `market_odds_engine.R` | (a) with labeled fixture fallback, currently running the fallback | Confirmed built and executed live in this session: with no `ODDS_API_KEY` in this environment, it correctly took the `SYNTHETIC_FALLBACK` fixture-slate path (real WNBA teams, fabricated odds), producing real EV/CLV/Kelly math on top. Would use the real `basketball_wnba` endpoint automatically if a key were ever set — no code change needed (confirmed by reading the fetch logic, not just asserted). |
| `live_game_listener.R` | (c) | Per `REPO_MAP.md` §9, even the NBA original never actually wires `ODDS_API_KEY` into live in-play polling — it polls one hardcoded fake game. The WNBA port (per `agent6.md`) keeps this pattern; real live in-play integration is out of scope for this build, same as NBA. |
| `bet_tracker.r` | (a) | Grades real bets against real box scores once a real ledger accumulates; the NBA original's synthetic-ledger-seed fallback only fires on a cold/empty ledger — acceptable bootstrap behavior, not a standing synthetic state. |
| `notify_bets.R` | (a) | Reads real `latest_value_bets.rds`; Discord dispatch either fires for real or is a documented no-op if `DISCORD_WEBHOOK` is unset — not synthetic data, a configuration gate. |
| `risk_management_engine.R` | (b), confirmed NOT fixed | Bankroll/Kelly-tier math is sport-agnostic and real. **Confirmed via grep in this session: the dead `cache/bet_log.rds` path was carried over unfixed** — the file still reads `cache/bet_log.rds` (line 38-39), which nothing in this repo ever writes; `bet_tracker.r` instead writes `cache/betting_ledger.rds` (a different path). This means `risk_management_engine.R` always falls through to its cold-start synthetic 120-bet seed ledger every run, never actually reading the real accumulating ledger `bet_tracker.r` produces. T4's own Handoff Notes explicitly disclosed this as a known, deliberately-not-fixed gap (not in scope per `agent5.md`'s item list) — reconfirmed still present here, not a newly-discovered bug, but worth fixing before this repo's risk numbers are trusted as reflecting real bet history. |
| `player_props_engine.R` | (a), confirmed fixed | ZINB math is real. **Confirmed fixed, not just claimed**: reads `cache/active_rosters_cache.rds` (verified live: "Loaded REAL WNBA rotation ... 120 players across 15 teams" = 15 teams × `WNBA_ROTATION_SIZE` 8), the NBA original's roster-filename mismatch bug is gone. 2/209 real roster players correctly flagged `SYNTHETIC_NO_BOX_DATA` at the per-player level (rookies with no box history) rather than the whole table being synthetic. |
| `copula_props_engine.R` | (b) | Sport-agnostic math demonstrated on one hardcoded example player (A'ja Wilson replacing Jokic) — this is by design per the plan, "not run across the full roster," acceptable as a math demonstration, not meant to be a live pricing engine yet. |
| `shot_quality_engine.R` | (b) | No real, free WNBA shot-location data source exists (plan §e risk #7); synthetic by design, explicitly acknowledged, permanent unless a future data source is found. |
| `xpoints_engine.R` | (b) | Explicitly dropped/kept synthetic-only per the plan — no WNBA equivalent of `stats.nba.com`'s shot-chart endpoint. |
| `rapm_engine.R` | **never built, pipeline gracefully skips it** | Confirmed via directory listing: this file does not exist anywhere in the repo — no T0-T5 agent was ever assigned to build it (not a missed task, never in scope). `run_full_pipeline.R` deliberately still lists a DAG stage for it (mirroring the NBA's exact 13-stage structure per T5's brief) and its `file.exists()` guard correctly no-ops with a documented warning (`Script rapm_engine.R not found ... Skipping.`) — confirmed live in this session's pipeline run. `wehoop::load_wnba_pbp()` remains a known, concrete future path to real RAPM, not yet attempted. |
| `fatigue_travel_engine.R` | (a) core math / (b) demo slate | `haversine_dist_miles()`/`calculate_travel_fatigue()` operate on real, hand-verified `ARENA_DB` coordinates (a) — but `evaluate_slate_fatigue()`'s demonstration run is over a hardcoded sample slate (b), same pattern as the NBA original; not meant to reflect live upcoming games unless separately wired to a real schedule feed (which nothing in the plan currently does). |
| `team_embeddings.py` | (c) | Depends on `cache/games_for_embeddings.csv`, which nothing in the current DAG populates from real WNBA game outcomes; the NBA original's own fallback (a 1,000-row random mock if the CSV is missing) is preserved by design for the WNBA port too — real embeddings require a games-CSV generation step not yet specified in the plan's Phase list. |
| `load_embeddings.R` | (a)/(c) | Trivial loader — its output is only as real as whatever `team_embeddings.py` actually produced; inherits that script's classification. |
| `playoff_simulator.R` | (a) format logic / (b) rating dependency, confirmed correct | **Confirmed via code read + live re-run**: implements a `PLAYOFF_FORMATS` registry (bo3 First Round 1-1-1, bo5 Semifinals 2-2-1, bo7 Finals 2-2-1-1-1) — NOT a blanket bo7, verified via T5's web-sourced 2025+ format-change research. `rapm_engine.R` doesn't exist, so `get_playoff_adjusted_rating()` always falls through to a hand-set contender-leverage table (b), same fail-safe spirit as the NBA original. Live re-run in this session's pipeline: real demo matchups derived from T2's actual current standings (e.g. Finals Bo7 Minnesota Lynx vs New York Liberty), not a live 2026 bracket (postseason hadn't started as of 2026-09-12). |
| `enhanced_model.R` | (a), manual/offline | One-off retraining script, not part of the daily DAG; real when run against real `box_scores_cache.rds`, simply not automated. |
| `WNBA_Analysis_Project.Rmd` | (a) methodology / knit artifact still pending | **Confirmed**: T2 actually re-ran the window-size (5/7/9/11/13), offseason-method, and model-architecture comparisons as plain R against real `box_scores_cache.rds` (not placeholders) — results embedded verbatim in the Rmd and reflected in `config.R`'s updated `ROLLING_WINDOW_SIZE`/`OFFSEASON_METHOD`. The `.Rmd` file itself was still never knit to PDF (`rmarkdown::pandoc_available()` returned `FALSE` in T2's session; same Pandoc gap confirmed still present — not independently re-checked for Pandoc availability in this session, but no evidence it was installed since). |
| `app.R` | (a) for data plumbing, confirmed by direct code read | Every tab's reactive was traced in this session and confirmed to read the real cache path it claims. **Tab 5 (embeddings): confirmed fixed** (reads real `team_embeddings.csv`, PCA + heatmap). **Tab 6 (calibration): confirmed still broken** — hardcoded `seq()`/`rnorm()` curve, never calls `live_calibration.R`'s real `calibration_analysis()`. Not launched as a live browser session in this environment. |

---

## Summary of Gaps Found at Write Time (2026-09-12, superseded by the Execution Log at the top)

*(Kept for history — this was the state of knowledge before T2–T5 landed and before this document was
re-executed against the finished pipeline. See the Execution Log at the very top of this file for the
current, ground-truth status.)*

- T2–T5 (rating engine, fatigue/shot-quality/embeddings, betting/market, live/dashboard/orchestration)
  had not been built yet at first-draft time. **Now complete** — re-verified against real running code
  in this session; see the Execution Log.
- T0/T1 code is real, live-validated, and matches the plan closely, with three genuine WNBA-specific
  discoveries not anticipated by the plan document: (1) the real team count is 15, not the plan's
  earlier guess of 13; (2) the `CONN`→`CON` Connecticut Sun abbreviation change (2019–2023 vs 2024+)
  would have silently dropped 5 seasons of real data if not caught; (3) the WNBA ESPN injuries feed has
  no top-level `athlete$id` field, requiring URL-regex extraction instead of a direct field read. All
  three were re-confirmed still correctly handled in this session's live re-checks (§2.1, §2.3).
- The injury cache's `data_source` column (`LIVE_ESPN`/`SYNTHETIC_FALLBACK`) pattern was **not**
  extended to `market_odds_engine.R` by T4 — the odds fallback is only distinguishable by its console
  log line and by diffing against the known fixture signature, not by an explicit column in
  `cache/latest_value_bets.rds` itself. This recommendation from the original plan draft was not acted
  on; still a legitimate future improvement, not a bug.
- **Newly confirmed in this execution pass** (both already disclosed in T4/T5's own Handoff Notes, not
  newly discovered, but independently re-verified against the actual code rather than taken on faith):
  `risk_management_engine.R` still points at the dead `cache/bet_log.rds` path instead of
  `cache/betting_ledger.rds`, so its risk-state numbers are always computed from a cold-start synthetic
  seed ledger, never the real accumulating one `bet_tracker.r` writes; and `app.R`'s Tab 6 (Model
  Calibration) is still the NBA-inherited hardcoded-curve bug, not addressed by T5's brief.
