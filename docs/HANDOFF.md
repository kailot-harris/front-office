# NFL Analytics — Handoff Document

**Last updated**: 2026-10-05, after commit `dd136a0` ("Merge issue #15: wire playoff_odds_engine.R
into run_full_pipeline.R"). `git status --short` shows 11 modified `cache/*.rds` files plus one
new untracked `cache/playoff_odds.rds` — real output of a real full-pipeline run done this session
to verify issue #15 (see "Known issues" item 8 below) — **not committed/pushed yet**, a deliberate
decision point left for the next session, not an oversight. Written for a future LLM/agent picking
this repo back up cold — read this before touching anything, then read `CLAUDE.md` for
environment/data-quirk details this doc doesn't repeat.

## What this repo is

A port of the sibling `WNBA Analytics` repo's architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, `.claude/skills/` tooling, phased
`docs/task_assignments_phaseN.md` build tracking) to NFL game predictions, built on `nflverse`
(`nflreadr`) data. Real git repo, remote `origin` =
`https://github.com/kailot-harris/NFL_analytics.git` (private). The pipeline runs against real
live data throughout. `risk_management_engine.R` reports `SYNTHETIC_FALLBACK` because the real bet
ledger (`CACHE_BETTING_LEDGER`, written by `bet_tracker.r`) is genuinely empty — no staked value
bet has cleared the early-season `MIN_SAMPLE_GAMES_FOR_STAKE` gate yet this season, not a bug.
Three live Discord dispatch paths are now confirmed working against the real `NFL_DISCORD_WEBHOOK`:
`notify_bets.R`, `accuracy_tracker.R` (both HTTP 204, prior session), and as of this session
`playoff_odds_engine.R` (HTTP 204, 2026-10-05, during a real full-pipeline run — see below).

**Read `docs/NFL_REPLICATION_PLAN.md` first** if you haven't — it's the live-verified (not
memorized) Phase 0 research foundation this repo was built from. Re-verify anything
date-sensitive before trusting it blindly for new work; nflverse/vendor details shift over time.

**The playoff-clinching probability feature (issues #11-#16) shipped in full this session** — see
"Playoff-clinching probability table — SHIPPED" below for what's actually live. The only issue
still open in the whole tracker is **#10** (an observational/calendar-dependent validation, not a
coding task) — see "Accuracy-trajectory monitoring" below.

## Current state: 13-stage pipeline (12 numbered `run_stage()` calls + stages 7.5 and 9.5)

Runs end-to-end against real data. `run_full_pipeline.R`'s `run_stage()` sources each stage
in-process (`call_fn`-style, no auto-run guards) and asserts every declared output's mtime
advanced (`.check_stage_output()`, WARN not fatal, `gc()` after every stage). **New this session**:
stage 7.5 (`playoff_odds_engine.R`), added by issue #15.

| # | Stage script | Exposed function | Real output |
|---|---|---|---|
| 1 | `daily_ingest.R` | `run_daily_ingest()` | `CACHE_PBP` (23-column whitelist), `CACHE_SCHEDULES` |
| 2 | `sync_rosters.R` | `run_sync_rosters()` | `CACHE_ROSTERS` |
| 3 | `injury_scraper.R` | `run_injury_scraper()` | `CACHE_INJURY_DATA` — cross-source-ID-crosswalk enriched |
| 4 | `epa_metrics_engine.R` | `run_epa_metrics()` | `CACHE_EPA_METRICS` — full-game EPA/success/CPOE plus 14 situational splits |
| 5 | `team_ratings_engine.R` | `run_team_ratings()` | `CACHE_TEAM_RATINGS`, `CACHE_PROJECTED_MATCHUPS` — ridge+Elo ensemble, QB-adjusted, market-blended `home_win_prob` |
| 6 | `fatigue_engine.R` | `run_fatigue_engine()` | `CACHE_FATIGUE_METRICS` |
| 7 | `playoff_simulator.R` | `run_playoff_simulator()` | `CACHE_PLAYOFF_SIMULATION` — bracket-only Monte Carlo (Wild Card→Super Bowl) for the 14 teams in the real current field, using the NFL's real tiebreaker procedure to seed that field |
| 7.5 | `playoff_odds_engine.R` | `run_playoff_odds_engine()` | `CACHE_PLAYOFF_ODDS` — **NEW (issue #15, this session)**. All-32-team make-the-playoffs probability (not round-by-round odds — that stays exclusive to stage 7). `N_SEASON_SIMULATIONS`=1000 trials/run, ~244s real measured runtime in the full-pipeline context. Discord dispatch live-verified (HTTP 204). See "Playoff-clinching probability table — SHIPPED" below |
| 8 | `market_odds_engine.R` | `run_market_odds_engine()` | `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` — real Odds API odds; staking gated by `MIN_SAMPLE_GAMES_FOR_STAKE` and `LONGSHOT_DECIMAL_ODDS_CAP` |
| 9 | `bet_tracker.r` | `run_bet_tracker()` | `CACHE_BETTING_LEDGER` — real bet ledger, writer+grader (currently 0 rows) |
| 9.5 | `risk_management_engine.R` | `run_risk_management()` | `CACHE_RISK_STATE` — reads the real ledger when it has RESOLVED bets, else `SYNTHETIC_FALLBACK` (currently the latter — ledger is empty). **Reordered this session (closes Known Issue #3)** — moved from old stage 8 (before market_odds_engine.R/bet_tracker.r) to after bet_tracker.r so a bet graded earlier in the same run is reflected immediately, not one cycle behind |
| 10 | `notify_bets.R` | `run_notify_bets()` | No cache output. Discord dispatch live-verified (HTTP 204) |
| 11 | `accuracy_tracker.R` | `run_accuracy_tracker()` | `CACHE_ACCURACY_HISTORY` — no `output` declared in its `run_stage()` call deliberately (a no-new-games day is a clean no-op, not a staleness warning). Discord dispatch live-verified (HTTP 204) |

Stage 7.5 sits immediately after stage 7 (same `CACHE_TEAM_RATINGS`/`CACHE_SCHEDULES` dependency
shape, no dependency between the two playoff-related stages on each other — grouped together in
the file per `docs/SPEC_playoff_odds_table.md` decision #6's framing). Stage 9.5
(`risk_management_engine.R`) now runs after stage 9 (`bet_tracker.r`) — see the reorder note above
— but before stage 10. Stage 11 (`accuracy_tracker.R`) runs last. Note: GitHub issue text and spec
docs for the accuracy-tracker feature call it "stage 12" in prose; the file's own sequential
comment numbering says "11." (doesn't count 7.5/9.5 as whole numbers) — don't be surprised by the
mismatch.
**Ordering gap fixed in code this session, not yet live-verified** (Known Issue #3): `risk_management_engine.R` now runs
after `bet_tracker.r` grades new bets within the same pipeline invocation, so risk state reflects
same-run grading instead of being one cycle behind. No other stage reads `CACHE_RISK_STATE`, so
the reorder has no other dependency impact. Not yet verified with a real full-pipeline run (see
Known Issue #3 below) — the reorder is syntax-checked (`parse()` succeeded) but not run live.

**Real full-pipeline run this session (verifying issue #15)**: completed in 392.58 total seconds;
stage 7.5 alone took 244.46s of that. Every stage ran cleanly; `.check_stage_output()` reported
`[FRESH]` for `CACHE_PLAYOFF_ODDS`. This left 11 `cache/*.rds` files modified plus one new
`cache/playoff_odds.rds`, **currently uncommitted** — see header note and "Suggested next steps."

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
| `125d1ef` | — | Spec'd the playoff-clinching probability table feature (`docs/SPEC_playoff_odds_table.md`) and filed it as 6 GitHub issues (#11-#16). |
| `45bcea8`…`dd136a0` | Playoff Odds #11-#16 | This session: implemented the full feature end-to-end via 5 waves of parallel `subagent-brief` dispatch — constants, single-trial sim, Monte Carlo loop + cache write, Discord dispatch ‖ timing/tuning (parallel), pipeline wiring. Real full-pipeline run confirms it live end-to-end (HTTP 204, 392.58s total run). |

## Recent work

### Playoff-clinching probability table — SHIPPED end-to-end this session (issues #11-#16, `45bcea8`…`dd136a0`, 2026-10-05)

Spec'd last session via `/spec-interview` (`125d1ef`, `docs/SPEC_playoff_odds_table.md`), fully
implemented and pipeline-verified this session via 5 waves of `subagent-brief` dispatch (the
established pattern — each wave's subagent ran in its own isolated git worktree, was independently
re-verified against its brief's evidence before merge, then the worktree was cleaned up):

- **Wave 1 (#11)**: `config.R` constants — `N_SEASON_SIMULATIONS` (started as an explicit
  placeholder, 1000) and `CACHE_PLAYOFF_ODDS <- file.path(CACHE_DIR, "playoff_odds.rds")`.
- **Wave 2 (#12)**: new file `playoff_odds_engine.R`, `.simulate_one_season()` — simulates every
  remaining `CURRENT_SEASON` REG game once (same `power_rating`/`NFL_HCA`/`NFL_MARGIN_SIGMA` via
  `pnorm()` formula `playoff_simulator.R` uses for bracket games, reused not duplicated), combines
  with real completed games into one hypothetical full season, feeds it through
  `nfl_tiebreakers.R`'s `build_tiebreak_data()` and `playoff_simulator.R`'s `.seed_conference()`
  (both sourced, not copied) to get that trial's resulting 14-team field. Verified stochastic
  (210 remaining games this season) and non-destructive of real completed-game scores.
- **Wave 3 (#13)**: `run_playoff_odds_engine()` — runs `N_SEASON_SIMULATIONS` trials of the above,
  tallies each of the 32 real teams' field-appearance rate into `playoff_prob`, writes
  `season`/`generated_at`/`n_simulations`/`field` (32-row `team`/`conference`/`division`/
  `playoff_prob`) to `CACHE_PLAYOFF_ODDS`. First real measured timing: 1000 trials = 362.58s.
- **Wave 4, dispatched in parallel (#14 ‖ #16)**:
  - **#14**: Discord dispatch — reuses `notify_bets.R`'s exact webhook/payload/fallback pattern.
    Two embed fields only (AFC, NFC — 16 teams each, sorted descending by `playoff_prob`), not 32,
    to stay well under Discord's field-count/char limits (measured 661 total chars for the real
    32-team payload). **Caution for future dispatches in this repo**: `NFL_DISCORD_WEBHOOK` is a
    real live webhook read from `~/.Renviron` at every fresh `Rscript` process start — any
    subagent testing Discord-dispatch code here must either stub `httr::POST()` or
    `Sys.setenv(NFL_DISCORD_WEBHOOK = "")` inside its own R session before calling the function
    under test, or it will silently post a real message to the real channel mid-development.
  - **#16**: timed `run_playoff_odds_engine()` against real data (n=30/50 direct; n=1000 measured
    twice, 204.94s/308.54s — consistent with #13's own 362.58s prior point; n=200/500/2000
    extrapolated linearly, labeled as such). Stability check: two n=1000 runs on the identical
    cache, max abs `playoff_prob` diff 0.052 (DEN), mean 0.009 — within a stated ±0.06 tolerance,
    consistent with binomial-SE Monte Carlo noise at n=1000. **Kept `N_SEASON_SIMULATIONS` at
    1000** (re-confirmed by evidence, not changed by default) and rewrote its `config.R` comment
    to the `NFL_MARGIN_SIGMA`/`NFL_HCA` documentation-density standard — no "placeholder" language
    remains. Added `tools/time_playoff_odds_engine.R` as a re-runnable reference.
- **Wave 5 (#15)**: wired `run_stage("playoff_odds_engine.R", ..., call_fn = "run_playoff_odds_engine", output = CACHE_PLAYOFF_ODDS)`
  into `run_full_pipeline.R` immediately after stage 7 (`playoff_simulator.R`). **Verified with a
  real, complete `run_full_pipeline.R` execution** (user explicitly authorized live Discord
  dispatch + full real run for this verification) — 392.58s total, stage 7.5 itself 244.46s,
  `CACHE_PLAYOFF_ODDS` freshly rewritten (`[FRESH]` per `.check_stage_output()`), Discord embed
  posted successfully (HTTP 204).

**Result**: live in the pipeline (stage 7.5, see table above). Real current output (from the
392.58s run): JAX and MIN both at 100.0% playoff_prob, SEA 99.8%, BUF 99.3%, KC 96.6% — face
validity confirmed against the real provisional 14-team field from stage 7 throughout development.
**`playoff_simulator.R` itself was never modified** — only sourced/reused for `.seed_conference()`.
**Full detail**: `docs/SPEC_playoff_odds_table.md` (frozen spec, still accurate), `git log 45bcea8..dd136a0`,
and each closed issue's GitHub comments (closing comments cite the real verification evidence —
read those, not just the commit messages, for the actual numbers).

### Everything before this session

Compressed further than usual since it's now several rewrites old and none of it is active work —
see `git show <hash>` for any of the commits in the Build history table above for full narrative,
or the previous version of this doc (`git log -p -- docs/HANDOFF.md`) if you need the
previously-written compressed summaries of the ridge-determinism fix, situational EPA/Kalman
model comparisons, market-blend Sharpe re-derivation, the real playoff-tiebreaker implementation,
player-ID crosswalk hardening, the participation-data debunking, the market-disagreement project
(home-backup-QB finding, HOLD recommendation), the `games_played`-freeze bug fix, and the
Windows Task Scheduler automation. None of that changed this session.

## Playoff-clinching probability table — all 6 issues CLOSED

See "Recent work" above for the full implementation summary. `docs/SPEC_playoff_odds_table.md`
remains the accurate frozen spec (no changes needed during implementation). All of #11-#16 are
closed on GitHub with real verification evidence in each issue's closing comment — read those for
exact numbers (timings, stability-check deltas, char counts) rather than re-deriving them.

## Accuracy-trajectory monitoring (issues #1-#9 shipped, #10 remains — now partially evidenced)

Full spec: `docs/SPEC_accuracy_trajectory_monitoring.md`. Summary: track the model's
season-to-date prediction accuracy over time via a persisted history cache plus Discord posts,
triggered idempotently whenever new games complete. Explicitly does NOT touch the staking gate and
explicitly does NOT build a dashboard (both deferred non-goals).

**#1-#9 closed.** **#10 still open** — observational, not a coding task, but now has real partial
evidence (added as a GitHub comment on #10 this session, not closed): the real Task Scheduler job
(`NFL_analytics_task_01`) fired successfully at **2026-10-05 05:15:01** (`schtasks /Query` shows
`Last Result: 0`, next run 2026-10-06 05:15 AM) and ran a full, real pipeline invocation —
confirmed via `logs/nfl_pipeline.log`: `accuracy_tracker.R` detected 1 newly-completed game,
appended row 3 of `cache/accuracy_history.rds` (accuracy=0.651, brier=0.2282, logloss=0.6485, 63
total graded games), and dispatched to Discord successfully (HTTP 204). **This satisfies scenario
1** of #10's acceptance criteria (a day with newly completed games).

**Scenario 2 is still unevidenced**: a day with *zero* newly-completed games, confirming the stage
no-ops cleanly (no duplicate history row, no duplicate/empty Discord post). All 3 rows currently
in `cache/accuracy_history.rds` are from days that had new completions — there is no off/bye-day
data point yet. This is genuinely calendar-dependent (can't be forced/simulated credibly — the
whole point is observing the real scheduled job on a real day with nothing new to report) and must
wait for the task to fire again on such a day. **Next session: re-run the `schtasks /Query` check
above** — if `Last Run Time` has advanced again since 2026-10-05 and the history file's row count
is unchanged from that run (i.e. it genuinely no-opped), close #10 with that evidence.

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
   stay paused.
2. **Home-backup-QB market bias: DROPPED (2026-10-05), not pursued further.** Gate-aware Sharpe
   improved (0.0911 → 0.1066, n=217) so it wasn't a staking-gate artifact, but the corrected
   bucket-screening count was 14 (not an earlier loose estimate of "~8"), and at that count the raw
   p=0.00615 did NOT survive Bonferroni/BH correction at alpha=0.05. User made the deliberate call
   to treat the multiple-comparisons failure as disqualifying rather than invest in a depth-chart
   cache to pursue a true holdout — this finding is closed, not a hold-for-later. No code changes
   resulted; `load_depth_charts()` remains called live, never persisted, and no cache for it should
   be built on the strength of this finding alone.
3. **Stage 8/9.5 pipeline ordering gap — FIXED this session, not yet live-verified.**
   `risk_management_engine.R` moved from old stage 8 (ran before `market_odds_engine.R`/
   `bet_tracker.r`) to new stage 9.5 (runs after `bet_tracker.r` grades new bets) in
   `run_full_pipeline.R`. Confirmed via `grep` that `CACHE_RISK_STATE` has no other reader, so the
   reorder carries no other dependency risk. Syntax-checked with `parse()` only — **has not been
   exercised with a real `run_full_pipeline.R` invocation yet**; since the real ledger is still
   empty (0 rows), the behavioral fix (same-run grading reflected in risk state) can't be
   demonstrated live until there's a real RESOLVED bet to grade. Next session: re-run the full
   pipeline once there's ledger activity and confirm `risk_management_engine.R`'s log output
   reflects that run's own `bet_tracker.r` grading, not the prior run's.
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
   `Ready`, and now confirmed to have fired successfully at least once for real (2026-10-05
   05:15 AM). Issue #10 (the off-day idempotency half of real-world validation) remains open — see
   "Accuracy-trajectory monitoring" above for exactly what's still missing.
8. **Playoff-odds feature (issues #11-#16) shipped this session — but the verification run left
   uncommitted cache state.** The real full-pipeline run done to verify issue #15 modified 11
   existing `cache/*.rds` files and created a new `cache/playoff_odds.rds`, all currently
   uncommitted (`git status --short` shows them). Prior sessions' convention (see `a5d592f`) was
   to commit+push regenerated caches after a manual verification run — decide whether to follow
   that convention here (commit them) or discard, rather than letting them sit indefinitely;
   either way this is a deliberate decision point left for the next session, not an accident.
   `N_SEASON_SIMULATIONS` is fully tuned now (not a placeholder) — see issue #16's closing comment
   for the real timing/stability numbers.

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
  isolated worktree) still reads/writes the ONE real shared `cache/` directory. Confirmed again
  this session dispatching issues #11-#16's parallel waves (#14 ‖ #16 both called
  `run_playoff_odds_engine()` for real against the shared cache around the same time — benign for
  both, since neither cared about exclusive ownership of the file, only its own run's timing/
  payload) — same hazard that bit the accuracy-tracker subagent dispatch before it.
- **`NFL_DISCORD_WEBHOOK` is a REAL live webhook, read from `~/.Renviron` at every fresh `Rscript`
  process start.** Any subagent (or you) testing Discord-dispatch code in this repo
  (`notify_bets.R`, `accuracy_tracker.R`, `playoff_odds_engine.R`) must either stub `httr::POST()`
  or `Sys.setenv(NFL_DISCORD_WEBHOOK = "")` inside the SAME R session before calling the function
  under test — a shell-level unset does nothing, since a fresh `Rscript` process re-reads
  `~/.Renviron` regardless. Confirmed this session briefing issue #14's subagent explicitly on
  this point before dispatch; worth repeating in any future Discord-dispatch-touching brief in
  this repo. A genuine real-pipeline verification run (as done for issue #15, with the user's
  explicit go-ahead) is the one case where firing real messages is the correct, intended outcome.

## Suggested next steps, roughly in priority order

1. **Known Issue #8 (uncommitted cache state) — DONE 2026-10-05.** Committed and pushed
   (`7b43185`), following the `a5d592f` precedent.
2. **Issue #10 (accuracy-tracker end-to-end scheduled validation) is observational, not a coding
   task, and still only half-evidenced** (see "Accuracy-trajectory monitoring" above). Re-checked
   2026-10-05: `Last Run Time` had not advanced past the already-evidenced 2026-10-05 05:15:01 run
   (next run 2026-10-06 05:15 AM) — no new evidence yet, left open. Check
   `schtasks /Query /TN NFL_analytics_task_01 /V`'s `Last Run Time`/`Last Result` next time this
   repo is picked up — if it fired again on a day with zero newly-completed games and the history
   row count didn't grow, close #10 with that evidence.
3. **Home-backup-QB market-bias finding (Known Issue #2) — DROPPED 2026-10-05, closed.** User
   made the deliberate call: the Bonferroni/BH correction failure is disqualifying, don't invest in
   a depth-chart cache to pursue it further. Nothing left to do here.
4. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data angle
   needs an explicit user decision (paid vendor or scraping project) before pursuing.
5. **Known Issue #3 (ordering gap) — fixed in code this session, needs live verification.**
   `risk_management_engine.R` was moved after `bet_tracker.r` in `run_full_pipeline.R`. Re-run the
   full pipeline once the real ledger has a RESOLVED bet to grade, and confirm
   `risk_management_engine.R`'s run reflects that same-run grading rather than the prior run's.
6. `player_props_engine.R`, team embeddings, a live dashboard, and a true rstan/cmdstanr install for
   the Kalman state-space model remain explicitly deferred non-goals — only start if there's a
   concrete pull for them.
7. No new feature is currently spec'd and queued the way playoff-odds was — the next feature needs
   a `/spec-interview` pass before implementation, same as every feature shipped so far.
