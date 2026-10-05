# NFL Analytics — Handoff Document

**Last updated**: 2026-10-05, after commit `125d1ef` ("Add spec doc for playoff-clinching
probability table feature"). `git status --short` is clean; local `main` matches `origin/main`
(pushed this session). Written for a future LLM/agent picking this repo back up cold — read this
before touching anything, then read `CLAUDE.md` for environment/data-quirk details this doc
doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout. `risk_management_engine.R` reports `SYNTHETIC_FALLBACK` because the real bet
ledger (`CACHE_BETTING_LEDGER`, written by `bet_tracker.r`) is genuinely empty — no staked value
bet has cleared the early-season `MIN_SAMPLE_GAMES_FOR_STAKE` gate yet this season, not a bug.
Both live Discord dispatch paths (`notify_bets.R`, `accuracy_tracker.R`) are confirmed working
against the real `NFL_DISCORD_WEBHOOK` (HTTP 204, 2026-10-05).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

**If you're picking up the new playoff-odds work**, read `docs/SPEC_playoff_odds_table.md` next,
then jump to "Playoff-clinching probability table (spec'd, issues #11-#16 filed, none started)"
below — this is the next active feature, spec'd this session but with zero implementation yet.

## Current state: 12-stage pipeline (11 numbered `run_stage()` calls + stage 9.5)

Runs end-to-end against real data. `run_full_pipeline.R`'s `run_stage()` sources each stage
in-process (`call_fn`-style, no auto-run guards) and asserts every declared output's mtime
advanced (`.check_stage_output()`, WARN not fatal, `gc()` after every stage). Unchanged this
session — no pipeline code shipped, only a spec doc + GitHub issues for a not-yet-started feature.

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (23-column whitelist), `CACHE_SCHEDULES` |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` — cross-source-ID-crosswalk enriched |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` — full-game EPA/success/CPOE plus 14 situational splits |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — ridge+Elo ensemble, QB-adjusted, market-blended `home_win_prob` |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — bracket-only Monte Carlo (Wild Card→Super Bowl) for the 14 teams in the real current field, using the NFL's real tiebreaker procedure to seed that field |
| 8 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — reads the real ledger when it has RESOLVED bets, else `SYNTHETIC_FALLBACK` (currently the latter — ledger is empty) |
| 9 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real Odds API odds; staking gated by `MIN_SAMPLE_GAMES_FOR_STAKE` and `LONGSHOT_DECIMAL_ODDS_CAP` |
| 9.5 | `bet_tracker.r` | `run_bet_tracker()` | `CACHE_BETTING_LEDGER` — real bet ledger, writer+grader (currently 0 rows) |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch live-verified (HTTP 204) |
| 11 | `accuracy_tracker.R` | `run_accuracy_tracker()` | `CACHE_ACCURACY_HISTORY` — no `output` declared in its `run_stage()` call deliberately (a no-new-games day is a clean no-op, not a staleness warning). Discord dispatch live-verified (HTTP 204) |

Stage 9.5 runs after stage 9 (needs its output to record today's picks) but before stage 10.
Stage 11 (`accuracy_tracker.R`) runs last. Note: GitHub issue text and spec docs for the
accuracy-tracker feature call it "stage 12" in prose; the file's own sequential comment numbering
says "11." (doesn't count stage 9.5 as a whole number) — don't be surprised by the mismatch.
**Known ordering gap, unchanged**: stage 8 still runs *before* stage 9.5 grades new bets within
the same pipeline invocation — one cycle behind. Not urgent while the ledger is empty.

**Once `playoff_odds_engine.R` lands (see below), it will add a 12th numbered stage** reading
`CACHE_TEAM_RATINGS`/`CACHE_SCHEDULES` and writing a new `CACHE_PLAYOFF_ODDS` — positioned next to
`playoff_simulator.R`'s existing stage 7. Not yet wired in; this table doesn't include it yet
because issue #15 (the wiring slice) hasn't been picked up.

## Build history (chronological, one row per phase/effort)

| Commit | Phase | What it added |
|---|---|---|
| `9155ad1`…`105eb8e` | Phases 1-7 | Ingestion, EPA/ratings engines, fatigue engine, playoff sim, risk engine, market odds engine, Discord dispatcher. |
| `d1c90aa`, `83682a5` | Phase 8 | Early-season rating shrinkage + minimum-sample staking gate, then backtested (found Sharpe negative at every threshold — the finding that triggered all model-quality remediation since). |
| `7092bad`…`050aebe` | Remediation A-4 | Market blend, QB-injury penalty, ridge Massey rating, MOV-weighted Elo, ridge+Elo ensemble (deployed), GBM stacking (negative result, not deployed). |
| `bb1cd99` | — | Fixed two `run_full_pipeline.R` OS-kills (`CACHE_PBP` column trim + inter-stage `gc()`). |
| `aa990e4` | — | Added `write-handoff-doc` skill. |
| `4f3c9d3`…`872b4b6` | Remediation continuation | Ridge determinism fix, long-shot EV mitigation, real bet ledger, situational EPA features (Phase 4), Kalman state-space model (Phase 5), market-blend Sharpe re-derivation, real NFL playoff tiebreakers, player-ID crosswalk hardening, participation-data pickup (debunked), market-disagreement project (one credible positive finding). |
| `461fdb4` | — | Fixed a real data-freshness bug in `daily_ingest.R`'s incremental merge that had silently frozen every team's current-season `games_played` at 1 since Week 1. |
| `4b90b40` | — | Added `tools/weekly_accuracy_report.R` — walk-forward grading of the in-progress season. |
| `63b2185`…`61e2a90` | Accuracy Tracker #1-#7 | Spec'd and implemented the accuracy-trajectory monitoring feature end-to-end via parallel subagents: shared grading function, history cache, `accuracy_tracker.R` + Discord dispatch, pipeline wiring. |
| `a5d592f` | — | Created the real Windows Task Scheduler job (`NFL_analytics_task_01`, daily 5:15 AM ET); live-verified both Discord dispatch paths against the real webhook; committed+pushed regenerated caches. |
| `6cba4de`, `7019f28` | — | Closed issues #8/#9 on GitHub with evidence; backfilled two prior-session findings this doc had failed to record (home-backup-QB market-bias gate-check, shrinkage-calibration check). |
| `125d1ef` | — | This session: spec'd the playoff-clinching probability table feature (`docs/SPEC_playoff_odds_table.md`) and filed it as 6 GitHub issues (#11-#16). No implementation yet. |

## Recent work

### Playoff-clinching probability table — spec'd via `/spec-interview`, filed as issues #11-#16 (`125d1ef`, 2026-10-05)

User asked for a new feature: a table of playoff probabilities for each NFL team. Investigation
found `playoff_simulator.R` already Monte Carlo-simulates the playoff *bracket* for the 14 teams
already in the real provisional field (round-by-round advancement odds), but nothing in the repo
estimates whether any of the other 18 teams will make the playoffs at all. Ran the
`/spec-interview` skill to pin down scope before writing code.

Key decisions (full detail in `docs/SPEC_playoff_odds_table.md`):
- Scope is strictly **make-the-playoffs probability for all 32 teams** (in/out), not round-by-round
  odds — those stay exclusive to `playoff_simulator.R`'s existing 14-team output.
- Each Monte Carlo trial simulates the *remaining* regular-season schedule (same
  `power_rating`/`NFL_HCA`/`NFL_MARGIN_SIGMA` approach `playoff_simulator.R` already uses for
  bracket games), then re-seeds using the **real** `nfl_tiebreakers.R` procedure per trial — not a
  simplified win-pct shortcut.
- New dedicated constant `N_SEASON_SIMULATIONS` (separate from the existing `N_SIMULATIONS`=10000,
  since each trial here is far heavier: full-season sim + real tiebreakers vs. just an 11-game
  bracket). Starting value 1000, explicitly flagged as an unverified placeholder pending real
  timing data (issue #16).
- New file `playoff_odds_engine.R` (not an extension of `playoff_simulator.R`), new cache constant
  `CACHE_PLAYOFF_ODDS`, wired into `run_full_pipeline.R` as a new stage running every pipeline
  invocation (no cadence gate).
- Discord dispatch reuses the same `NFL_DISCORD_WEBHOOK` channel as `notify_bets.R`/
  `accuracy_tracker.R`, formatted as 2 embed fields (AFC/NFC, 16 teams each sorted by descending
  probability) rather than 32 individual fields, to stay within Discord's per-embed field limits.
- **Result**: no code yet — spec doc + 6 GitHub issues only. See table below for the dependency
  graph and current status.
- **Status**: spec'd, not started. `playoff_simulator.R` itself is untouched.
- **Full detail**: `docs/SPEC_playoff_odds_table.md`, `git show 125d1ef`.

### Everything before this session

Compressed further than usual since it's now several rewrites old and none of it is active work —
see `git show <hash>` for any of the commits in the Build history table above for full narrative,
or the previous version of this doc (`git log -p -- docs/HANDOFF.md`) if you need the
previously-written compressed summaries of the ridge-determinism fix, situational EPA/Kalman
model comparisons, market-blend Sharpe re-derivation, the real playoff-tiebreaker implementation,
player-ID crosswalk hardening, the participation-data debunking, the market-disagreement project
(home-backup-QB finding, HOLD recommendation), the `games_played`-freeze bug fix, and the
Windows Task Scheduler automation. None of that changed this session.

## Playoff-clinching probability table (spec'd, issues #11-#16 filed, none started)

Full spec: `docs/SPEC_playoff_odds_table.md`. Dependency waves for parallel dispatch: **Wave 1**
#11 → **Wave 2** #12 → **Wave 3** #13 → **Wave 4** #14 ‖ #16 (independent of each other) →
**Wave 5** #15.

| Issue | Title | Depends on | Status |
|---|---|---|---|
| [#11](https://github.com/kailot-harris/NFL_analytics/issues/11) | Add `N_SEASON_SIMULATIONS` + `CACHE_PLAYOFF_ODDS` constants to `config.R` | — | OPEN |
| [#12](https://github.com/kailot-harris/NFL_analytics/issues/12) | Single-trial remaining-season simulation + real-tiebreaker reseed function | #11 | OPEN |
| [#13](https://github.com/kailot-harris/NFL_analytics/issues/13) | Monte Carlo loop + `run_playoff_odds_engine()` cache write (no Discord yet) | #12 | OPEN |
| [#14](https://github.com/kailot-harris/NFL_analytics/issues/14) | Add Discord dispatch (AFC/NFC two-field embed) | #13 | OPEN |
| [#15](https://github.com/kailot-harris/NFL_analytics/issues/15) | Wire `playoff_odds_engine.R` into `run_full_pipeline.R` | #14 | OPEN |
| [#16](https://github.com/kailot-harris/NFL_analytics/issues/16) | Time and tune `N_SEASON_SIMULATIONS` against real data | #13 (parallel with #14) | OPEN |

Each issue has its own "Vertical slice / what 'done' looks like" and "Testable independently"
section — read the issue body, this table only summarizes. None have been picked up by a subagent
yet; next session's natural first move is dispatching #11 (no dependencies).

## Accuracy-trajectory monitoring (issues #1-#9 shipped, #10 remains)

Full spec: `docs/SPEC_accuracy_trajectory_monitoring.md`. Summary: track the model's
season-to-date prediction accuracy over time via a persisted history cache plus Discord posts,
triggered idempotently whenever new games complete. Explicitly does NOT touch the staking gate and
explicitly does NOT build a dashboard (both deferred non-goals).

**#1-#9 closed.** **#10 genuinely remains open** — observational, not a coding task: requires
observing the real Task Scheduler job (`NFL_analytics_task_01`, daily 5:15 AM ET) actually fire on
at least one real game day and one real off day, then confirming idempotency (no duplicate Discord
posts when no new games completed) via `schtasks /Query /TN NFL_analytics_task_01 /V`'s `Last Run
Time`/`Last Result` fields. Not checked yet this session — no evidence either way has been
gathered since the task was created 2026-10-05.

**Key design facts worth re-reading from the spec before implementing anything adjacent**:
- The staking-sample gate (`market_odds_engine.R`) is computed **per game**
  (`pmin(home_games_played, away_games_played) < MIN_SAMPLE_GAMES_FOR_STAKE`), not once per
  season — re-verify the line number before citing it, source drifts.
- The accuracy-tracker stage's trigger is idempotency (compare current completed-game set against
  `CACHE_ACCURACY_HISTORY`), NOT a calendar/schedule lookup.
- History granularity is one row per **run that finds new completed games**, not one row per NFL
  week.

## Known issues / unfinished business

1. **Staking is not validated as profitable at the ensemble/portfolio level.** Sharpe is negative
   for every deployed-formula candidate across every parameter grid tested so far (long-shot cap,
   market-blend weight, situational/Kalman/participation features) — real-money staking should
   stay paused. The one exception (home-backup-QB market bias, item 2 below) is a narrow,
   single-signal result not validated to a deployment bar.
2. **Home-backup-QB market bias: HOLD, not "needs more validation."** Gate-aware Sharpe actually
   improves (0.0911 → 0.1066, n=217) so it's not a staking-gate artifact, but the corrected
   bucket-screening count is 14 (not an earlier loose estimate of "~8"), and at that count the raw
   p=0.00615 does NOT survive Bonferroni/BH correction at alpha=0.05. A true 2025-2026 holdout
   remains blocked — no depth-chart cache exists in this repo (`load_depth_charts()` is called
   live, never persisted). Revisit only via (a) persisting a depth-chart cache to enable a genuine
   out-of-discovery-window holdout, or (b) treating the Bonferroni failure as disqualifying and
   dropping it.
3. **Stage 8/9.5 pipeline ordering gap.** `risk_management_engine.R` (stage 8) runs before
   `bet_tracker.r` (stage 9.5) grades new bets within the same invocation — one cycle behind. Not
   urgent while the ledger is empty.
4. **Four competing NFL player-ID schemes** — hardened via `player_id_crosswalk.R`, but remains
   something any *future* player-level join must use rather than a fresh unverified
   `load_ff_playerids()` call.
5. **`load_participation()`** — the underlying data-availability limitation (never populated for
   `CURRENT_SEASON`) is permanent, not a bug to fix. Its Sharpe hypothesis was debunked; not
   promoted.
6. **Public bet-percentage/handle data** does not exist anywhere in this repo. A real, explicit,
   deferred paid-vendor decision for the market-disagreement project's "fade the public" angle —
   not pursued without user sign-off on cost/ToS.
7. **Windows Task Scheduler automation (issues #8/#9) — DONE 2026-10-05.** Task created, confirmed
   `Ready`. Issue #10 (real-world validation) remains genuinely open — see above.
8. **New this session: `playoff_odds_engine.R` doesn't exist yet.** Issues #11-#16 are all OPEN,
   none started. `N_SEASON_SIMULATIONS`'s proposed value (1000) is explicitly an unverified
   placeholder — do not treat it as tuned until issue #16 closes.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed working:
  `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`, `ggplot2`, `knitr`, `rmarkdown`,
  `tinytex`. NOT installed: `lightgbm`, `rstan`/`cmdstanr`/`brms`/`rjags`, `kableExtra`.
- Quarto: **not on PATH** — the real binary is bundled with RStudio at
  `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe`. Invoke via full path.
- Real credentials confirmed working: `ODDS_API_KEY`, `NFL_DISCORD_WEBHOOK` (both read from
  `C:\Users\kailo\.Renviron` — NOT `C:\Users\kailo\Documents\.Renviron`, which is where R's
  user-Renviron lookup does *not* resolve on this machine).
- Inline multi-line `Rscript -e '...'` has segfaulted before on this machine — write ad hoc R to a
  temp `.R` file under `tools/` (delete it after) rather than inlining. Separately, a *relative*
  path to a user-level skill's `.R` script (e.g. `.claude/skills/<name>/scripts/foo.R` from this
  repo's root) also segfaults rather than erroring cleanly, because repo-local `.claude/` has no
  `skills/` subfolder — user-level skills live under `C:\Users\<user>\.claude\skills\`. Always use
  the absolute path for those.
- `glmnet::cv.glmnet()` calls anywhere in this repo need an explicit local seed — R's global RNG
  state is not reliable for reproducibility across separate script invocations here.
- `nflreadr`'s `dictionary_*` objects (e.g. `dictionary_schedules`) are lazy-loaded package
  *data*, not namespace functions — `nflreadr:::dictionary_schedules` fails; use
  `data(dictionary_schedules, package = "nflreadr")` first.
- `isTRUE()` is not vectorized in base R — using it inside `dplyr::case_when()`/`mutate()` over a
  vector column silently collapses every row to the fallback branch with no error. Use
  `x %in% TRUE` instead.
- `bind_rows(A, B) |> distinct(key, .keep_all = TRUE)` keeps the FIRST row per key — if `A` is a
  stale cache and `B` is a fresh fetch, put `B` first or you'll silently keep discarding real
  updates forever (bit `daily_ingest.R`'s `.ingest_one()` once already). Re-check any NEW
  incremental-cache-merge code against this trap before trusting it.
- **`schtasks /Create`'s `/TR` argument needs literal backslash-quote sequences from PowerShell,**
  not plain embedded double-quotes or backtick-escaped ones. Build the string single-quoted (so
  PowerShell doesn't touch the backslashes) with literal `\"..\"` pairs, then pass it as the `/TR`
  value. Also: Git Bash mangles `schtasks /Create` (rewrites `/Create` as a path) — use the
  PowerShell tool for `schtasks`, not Bash.
- **Git-worktree isolation does NOT isolate `cache/*.rds` writes.** Every script in this repo
  `setwd()`s to the hardcoded absolute repo root rather than wherever it's actually being invoked
  from, so a script run from inside a git worktree (e.g. a `subagent-brief`-dispatched subagent's
  isolated worktree) still reads/writes the ONE real shared `cache/` directory. If dispatching
  parallel subagents against issues #11-#16 that run `playoff_odds_engine.R` or
  `run_playoff_odds_engine()` against real cache state, either point test harnesses at scratch
  copies of the specific `.rds` file, or verify the real cache's content before and after merging
  each subagent's work — same hazard that bit the accuracy-tracker subagent dispatch.

## Suggested next steps, roughly in priority order

1. **Dispatch issue #11 (playoff-odds constants) — no dependencies, the natural first move.** Then
   follow the wave graph in "Playoff-clinching probability table" above: #12 → #13 → (#14 ‖ #16) →
   #15. The `subagent-brief` skill is the established pattern for this (used successfully for the
   accuracy-tracker issues) — remember the cache-isolation hazard above when briefing subagents.
2. **Issue #10 (accuracy-tracker end-to-end scheduled validation) is observational, not a coding
   task.** Check `schtasks /Query /TN NFL_analytics_task_01 /V`'s `Last Run Time`/`Last Result`
   next time this repo is picked up — if it's fired at least once since 2026-10-05, confirm
   idempotency and close #10 with that evidence.
3. **Decide what to do with the home-backup-QB market-bias finding (Known Issue #2).** Already has
   a HOLD recommendation from a gate-aware, multiple-comparisons-corrected check — needs a
   deliberate decision (depth-chart-cache investment to enable a true holdout, or drop it) rather
   than more passive accumulation of data.
4. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data angle
   needs an explicit user decision (paid vendor or scraping project) before pursuing.
5. Consider fixing the stage 8/9.5 ordering gap (Known Issue #3) if a same-run-fresh ledger read
   ever becomes important — not urgent today since the ledger is empty anyway.
6. `player_props_engine.R`, team embeddings, a live dashboard, and a true rstan/cmdstanr install for
   the Kalman state-space model remain explicitly deferred non-goals — only start if there's a
   concrete pull for them.
