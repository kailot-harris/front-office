# NFL Analytics — Handoff Document

**Last updated**: 2026-10-13, after commit `e561171` ("Add Elo visualization report; refresh
caches from Week 5 pipeline run") — that commit is already on `main` and resolved the previous
revision's "uncommitted Elo report work" item (the `.qmd`/`.html`/`elo_*.png`/animation GIF/
`elo_model.R` diff/refreshed-cache items are now all committed; verified via `git status` showing
none of them untracked anymore). Everything below the "Recent work" section's newest entry is
**this session's uncommitted work on top of `e561171`** — purely planning/scaffolding artifacts,
zero code changes, zero pipeline runs. `git status --short` shows only untracked files, no
modified tracked files: 9 new agent-brief files under `agents/`, one new
`docs/task_assignments_phase8.md`, plus three files `git status` has flagged as untracked for
multiple sessions now and still nobody has decided their fate (`tools/_inspect_week5.R`,
`tools/plot_week5_projections.R`, `tools/run_week5_refresh.R`) and one more from that same
undecided batch (`cache/week5_projections.png`, `cache/elo_anim_frames/` — the latter is
intermediate per-frame PNGs from the now-committed animation GIF, likely safe to delete/gitignore
whenever someone gets to it). Written for a future LLM/agent picking this repo back up cold — read
this before touching anything, then read `CLAUDE.md` for environment/data-quirk details this doc
doesn't repeat.

**This session's work was planning/orchestration only: brainstormed 30 team-level visualization
ideas, the user picked 14 of them across three groups, and the session (1) filed all 14 plus 3
necessary data-infra prerequisites as real GitHub issues (#17-#33), then (2) scaffolded a 9-agent,
2-wave parallel build plan for them. No implementation has started — every task is `PENDING`. See
"Recent work: Week 1-5 visualization GIFs — planning only" below.**

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

**The playoff-clinching probability feature (issues #11-#16) shipped 2026-10-05** — see
"Playoff-clinching probability table — SHIPPED" below for what's actually live. The only issue
still open in the whole tracker is **#10** (an observational/calendar-dependent validation, not a
coding task) — **real evidence for both of its acceptance scenarios now exists as of 2026-10-13,
just not yet closed on GitHub** — see "Accuracy-trajectory monitoring" below.

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

### This session (2026-10-13, later): Week 1-5 visualization GIFs — planning only, nothing built

Follow-up to the Elo visualization report below (same day, later session) — user liked the
`elo_scatter_animation.gif` and asked for several more team-level GIFs summarizing weeks 1-5.
Pure planning/orchestration work, no code written, no scripts run:

1. **Brainstormed 30 team-level visualization ideas** (Elo-based, standings/scores, playoff-odds/
   EPA/turnovers), ranked by rough visual-power/effort. User picked 14 across three groups:
   - **Group A (Elo)**: rank bump chart, Elo heatmap, delta bar race, volatility bar race.
   - **Group B (standings/scores)**: upset timeline, point-diff race, PF/PA-vs-Elo scatter,
     division-standings race, SOS-adjusted win race.
   - **Group C (playoff odds/EPA/turnovers)**: playoff-prob bump, playoff-odds heatmap, EPA
     quadrant scatter, EPA net race, turnover-margin race.
2. **Investigated real data availability before scoping anything** (avoided the trap of scoping
   issues against assumed data): confirmed `CACHE_PLAYOFF_ODDS` is a point-in-time snapshot with
   **no week dimension** (so 2 of the Group-C picks need a historical backfill, not just
   plotting), and confirmed no turnover data (interceptions/fumbles) is cached anywhere in this
   repo at all — `.PBP_CACHE_COLUMNS` in `daily_ingest.R` doesn't include them. This surfaced 3
   infra prerequisites the user hadn't explicitly asked for but the 14 visualizations structurally
   need.
3. **Filed 17 real GitHub issues** (`gh issue create`, confirmed with the user first): **#17-#19**
   are the infra prerequisites (Elo-history-builder extraction/refactor, playoff-odds-history
   backfill, turnover-data ingestion+aggregation); **#20-#33** are the 14 visualizations, each
   referencing which infra issue (if any) it depends on. All currently `OPEN`, label
   `enhancement`, repo `kailot-harris/NFL_analytics`.
4. **Scaffolded `docs/task_assignments_phase8.md`** via the `remediation-phase-scaffold` skill —
   titled "Phase 9" internally, continuing this repo's established off-by-one convention where the
   filename index runs one behind the in-file title number (confirmed by checking every prior
   `task_assignments_phaseN.md`'s first line: `phase0.md` is titled "Phase 1" ... `phase7.md` is
   titled "Phase 8" — this file follows the same pattern, don't "fix" it to match in a later pass).
   Structure: 9-task Task Tracker (all `PENDING`), a Wave 0 orchestrator-only step (2 new
   `config.R` constants, added by the orchestrator, not by either Wave-1 agent who needs one —
   `config.R` is a shared file no two agents may edit in the same wave), a 2-wave dependency graph,
   and an Interface Contracts table fixing the exact `get_elo_history(max_week = NULL)` signature
   and both new cache schemas (`CACHE_PLAYOFF_ODDS_HISTORY`, `CACHE_TURNOVER_HISTORY`) before any
   Wave-2 agent needs to consume them.
5. **Wrote 9 agent briefs** under `agents/` (`agent_elo_infra`, `agent_playoff_infra`,
   `agent_turnover_infra`, `agent_viz_b_schedule`, `agent_viz_c_epa` — Wave 1; `agent_viz_a_rank`,
   `agent_viz_a_delta`, `agent_viz_b_upsets_sos`, `agent_viz_c_playoff_turnover` — Wave 2), each
   with exact file ownership, the specific GitHub issue(s) it closes, concrete per-task
   instructions (not just a paraphrased issue restatement), the interface contracts it must honor,
   a runnable test suite, and a definition of done — matching this repo's established
   `subagent-brief`-dispatch pattern (same pattern used for the playoff-odds #11-#16 and accuracy-
   tracker #1-#9 builds).

**Nothing has been executed.** All 9 Task Tracker rows in `docs/task_assignments_phase8.md` are
`PENDING`. No Wave has been dispatched. `config.R` has NOT yet received its 2 new constants (that
is Wave 0, orchestrator-only, and hasn't happened). Next session should dispatch Wave 1's 5 agents
(see "Suggested next steps" below) — read `docs/task_assignments_phase8.md` in full before doing
so, it has the authoritative task/file/contract breakdown; this summary is a pointer to it, not a
replacement for reading it.

### This session (2026-10-13): Elo visualization report — ad hoc, NOT a pipeline stage

User asked for a standalone Elo-rating analysis/report, not a build task on the issue tracker —
unrelated to the playoff-odds/accuracy-tracker threads below except for the Issue #10 evidence
found along the way (see "Accuracy-trajectory monitoring" above). Sequence:

1. **Ran a real, full `run_full_pipeline.R`** (user's explicit instruction — "Week 5's last game
   just ended") to refresh all caches before analysis. Completed cleanly, 439.23s, exit 0. One
   pre-existing WARN fired (`bet_tracker.r`'s `betting_ledger.rds` stale — expected, see Known
   Issue #9/#8, no real bets staked this slate, not a new problem). This is the run that produced
   the 12 modified `cache/*.rds` files currently uncommitted.
2. **Additive change to `tools/elo_model.R`**: `run_elo_walkforward()`'s per-game output row now
   also includes `home_elo_pre`/`away_elo_pre` (the two teams' PRE-game Elo ratings, i.e. the
   exact inputs already used internally to compute `elo_diff`/`elo_prob_pure` — just newly
   exposed as output columns). Every existing caller either doesn't care about extra columns or
   explicitly `select()`s a subset already, so this is non-breaking — confirmed by grepping every
   call site (`team_ratings_engine.R`, `accuracy_tracker.R`, `tools/model_backtest_harness.R`,
   `tools/backtest_common.R`, and 6 other `tools/derive_*`/`investigate_*` scripts) before making
   the change. Needed because "average opponent Elo, no hindsight" requires each team's
   opponent's rating *at the time that specific game was played*, which wasn't previously exposed.
3. **New file `docs/week5_elo_analysis.qmd`** (400 lines) — a self-contained Quarto report, NOT
   wired into `run_full_pipeline.R` and not meant to be (it's a point-in-time analysis artifact,
   re-run manually when wanted, same category as `tools/derive_*.R` scripts). Six sections:
   current Elo by team (bar, faceted by conference, colored/grouped by division), week-to-week
   Elo trajectory (line, faceted by division), average opponent Elo / strength-of-schedule (bar),
   team-strength-vs-SOS scatter (static + **animated GIF**, see below), early-season upsets table,
   and overperforming/underperforming-vs-schedule tables. All figures use real team logos
   (`nflplotR::geom_nfl_logos()`/`element_nfl_logo()`) instead of color-only legends — user
   feedback mid-session ("impossible to distinguish teams") drove this. Dark theme + a custom
   blue→green division palette, also user-requested.
4. **Animated scatter (`cache/elo_scatter_animation.gif`)**: per-week cumulative snapshot
   (current Elo × average pre-game opponent Elo through that week), each team's own history
   rendered as a fading grey trail behind its logo. Built manually frame-by-frame with `ggplot2`
   + `magick::image_animate()` (NOT `gganimate`/`transformr` — never installed, untested whether
   `nflplotR`'s image-based geoms tween cleanly under `gganimate`, so this avoided that question
   entirely by hand-rendering each frame). **Real lesson learned mid-build**: a global cubic
   spline (`stats::spline()`, then tried `splinefun(method="monoH.FC")`) through only 2-5 noisy
   per-team points overshoots badly and produces visible loops that misrepresent the real path —
   switched to piecewise-linear interpolation (`approx()`, finely subdivided only for a smooth
   *rendering* fade, not shape-smoothing) instead. If animating any other noisy-few-point team
   trajectory in this repo later, start with `approx()`, not a spline.
5. **New R packages installed** (user-level library, not pinned anywhere — this repo has no
   `renv.lock`/`DESCRIPTION`): `nflplotR` + its dependencies `ggpath`, `gt`, `magick`, `V8`,
   `bigD`, `bitops`, `juicyjuice`. `nflplotR` is the standard nflverse package for team logos in
   `ggplot2` — fits the existing `nflreadr`/`nflfastR` stack already in use here.
6. **Found and worked around a real quarto bug**: this doc's `embed-resources: true` YAML setting
   is silently not honored by the local quarto 1.10.18 binary for this `.qmd` — plain
   `quarto render` leaves a non-self-contained HTML (relative links to a `*_files/` sidecar
   folder, confirmed via zero `base64` matches in the output). Rendering with the explicit CLI
   flag `quarto render docs/week5_elo_analysis.qmd --to html --embed-resources` DOES embed
   correctly (verified: all figures + the GIF inline as base64, no sidecar folder, 2.3MB
   self-contained file). A note to this effect is left at the top of the `.qmd` itself — **always
   use the explicit flag when re-rendering this doc** until the YAML-only behavior is re-verified
   against a newer quarto version.
7. **Not committed.** `docs/week5_elo_analysis.{qmd,html}`, `cache/elo_*.png`,
   `cache/elo_scatter_animation.gif`, `cache/elo_anim_frames/` (intermediate per-frame PNGs, could
   be `.gitignore`d or deleted — they're a build artifact of the GIF, not needed once the GIF
   exists), and the `tools/elo_model.R` diff are all currently untracked/unstaged. Left as a
   decision point for the next session (see "Suggested next steps").

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

## Accuracy-trajectory monitoring (issues #1-#9 shipped, #10 remains — now fully evidenced, not yet closed)

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

**Scenario 2 — FOUND this session (2026-10-13), real evidence now exists, #10 not yet closed on
GitHub.** `logs/nfl_pipeline.log` shows the real scheduled task fired cleanly at both
**2026-10-10 05:15:03** and **2026-10-11 05:15:03** with zero newly-completed games each time:

```
[2026-10-10 05:18:42] [INFO] [accuracy_tracker.R] Starting accuracy tracker for season 2026.
[2026-10-10 05:19:05] [INFO] [accuracy_tracker.R] No new completed games since the last recorded
  run (season 2026, 65 game(s) graded total, all already recorded).
[2026-10-10 05:19:05] [INFO] [run_full_pipeline.R] Pipeline run finished in 242.33 seconds.

[2026-10-11 05:15:03] [INFO] [run_full_pipeline.R] Pipeline run started.
[2026-10-11 05:19:17] [INFO] [accuracy_tracker.R] No new completed games since the last recorded
  run (season 2026, 65 game(s) graded total, all already recorded).
[2026-10-11 05:19:17] [INFO] [run_full_pipeline.R] Pipeline run finished in 253.64 seconds.
```

Verified both ways the acceptance criteria asks for: (1) no duplicate/extra row —
`cache/accuracy_history.rds` stayed at 65 total graded games across both days (confirmed by
reading the cache directly: row for 2026-10-09 shows 65, next row jumps straight to 2026-10-12
with 78 — no 10-10/10-11 rows exist), and (2) no duplicate/empty Discord post — neither run's log
has a "Broadcasted…Discord webhook" line, just the clean no-op message above. **This satisfies
Scenario 2 in full.** Combined with the already-evidenced Scenario 1 (2026-10-05), both of #10's
acceptance-criteria scenarios now have real evidence — **recommend closing #10 on GitHub with
this log excerpt as the closing comment**, but it was left open this session since closing a
tracked issue is a visible action the project owner should take deliberately, not something a
handoff-writing pass does on its own.

Side observation while digging through the log (not a bug, just worth knowing): the scheduled
task doesn't always fire at exactly 05:15 — several runs started late (`2026-10-05 11:47:17`,
`2026-10-08 07:47:53`, `2026-10-12 07:55:14`), consistent with Windows Task Scheduler's
run-ASAP-after-a-missed-start behavior (e.g. machine asleep at 05:15). Didn't affect correctness
of either no-op evidenced above (both of those happened to fire on time), but if a future session
is hunting for a *specific* calendar day's behavior, check the actual "Pipeline run started"
timestamp in the log rather than assuming it ran at 05:15.

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
8. **Playoff-odds feature (issues #11-#16) shipped 2026-10-05.** `N_SEASON_SIMULATIONS` is fully
   tuned (not a placeholder) — see issue #16's closing comment for the real timing/stability
   numbers. The cache state from that session's verification run was committed+pushed (`7b43185`,
   following the `a5d592f` precedent) — **this item is closed**. See item 9 below for the *current*
   uncommitted cache state (a different, later run).
9. **Uncommitted cache state from the 2026-10-13 full-pipeline run — RESOLVED, committed in
   `e561171`.** The 12 modified `cache/*.rds` files plus the Elo-report artifacts (`docs/
   week5_elo_analysis.{qmd,html}`, `cache/elo_*.png`, `cache/elo_scatter_animation.gif`, the
   `tools/elo_model.R` diff) are all now on `main`. Confirmed via `git status` showing none of
   them untracked anymore. This item is closed; recorded here only so a future reader doesn't
   re-flag it as still-pending.
10. **Three untracked scratch files from an undocumented 2026-10-08 session — STILL UNRESOLVED,
    now 2 sessions old.** (`tools/_inspect_week5.R`, `tools/plot_week5_projections.R`,
    `tools/run_week5_refresh.R`, plus `cache/week5_projections.png` which the previous doc revision
    didn't separately call out). Read: small, clearly-scoped ad hoc helpers for a Week 5
    projections visualization (`run_week5_refresh.R` re-runs pipeline stages 1-5 only to regenerate
    `CACHE_PROJECTED_MATCHUPS` without live Discord/Odds-API side effects; `_inspect_week5.R` is a
    one-off cache-inspection snippet; `plot_week5_projections.R` is a larger plotting script, not
    reviewed in detail in any session so far). Not part of any pipeline stage, not referenced by
    `docs/week5_elo_analysis.qmd`. Two sessions have now passed without anyone deciding whether to
    commit or delete these — next session should actually make the call rather than deferring a
    third time.
11. **`cache/elo_anim_frames/` — intermediate build artifact, likely safe to discard.** Per-frame
    PNGs from building `cache/elo_scatter_animation.gif` (now committed). Not needed once the GIF
    exists; candidate for `.gitignore` or deletion, bundled with item 10's cleanup decision since
    both are "leftover untracked files nobody has triaged yet."
12. **Week 1-5 visualization GIF phase (issues #17-#33) — PLANNED, nothing executed.** See
    "Recent work: Week 1-5 visualization GIFs — planning only" above and
    `docs/task_assignments_phase8.md` for the full plan. `config.R` has not yet received its 2
    Wave-0 constants; no Wave-1 agent has been dispatched. This is the largest open item in this
    doc — prioritize accordingly in "Suggested next steps" below.

## Environment specifics a fresh agent needs

- R: `C:\Program Files\R\R-4.5.2\bin\Rscript.exe` (not on PATH). Installed and confirmed working:
  `nflreadr`, `dplyr`, `duckdb`, `httr2`, `glmnet`, `xgboost`, `ggplot2`, `knitr`, `rmarkdown`,
  `tinytex`, and as of 2026-10-13: `nflplotR` (+ deps `ggpath`, `gt`, `magick`, `V8`, `bigD`,
  `bitops`, `juicyjuice`) for team-logo plotting. NOT installed: `lightgbm`,
  `rstan`/`cmdstanr`/`brms`/`rjags`, `kableExtra`, `gganimate`/`gifski`/`transformr` (animated
  GIFs in this repo so far are hand-built frame-by-frame with `magick::image_animate()` instead —
  see `docs/week5_elo_analysis.qmd`'s animated-scatter chunk — specifically to avoid the untested
  question of whether `nflplotR`'s image-based geoms tween cleanly under `gganimate`). No
  `renv.lock`/`DESCRIPTION` tracks any of this — package installs are ad hoc to whatever machine
  runs the code.
- Quarto: **not on PATH** — a working binary was found this session at
  `C:\Program Files\Quarto\bin\quarto.exe` (earlier sessions used a different RStudio-bundled path
  at `C:\Program Files\RStudio\resources\app\bin\quarto\bin\quarto.exe` — both may exist on this
  machine; the standalone one worked for the 2026-10-13 session). Invoke via full path either way.
  **`embed-resources: true` in a `.qmd`'s YAML is not reliably honored by quarto 1.10.18 locally**
  — confirmed on `docs/week5_elo_analysis.qmd`: plain `quarto render` produced a non-self-contained
  HTML (relative links to a `*_files/` sidecar folder) despite the YAML setting. Always pass the
  explicit CLI flag too: `quarto render <file>.qmd --to html --embed-resources`. Not yet checked
  whether this affects `docs/profitability_remediation_report.qmd` or is specific to the newer doc
  — worth a quick check if that older report is ever re-rendered and sent somewhere expecting a
  truly standalone file.
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

1. **Dispatch Wave 1 of the visualization-GIF phase (issues #17-#33, `docs/
   task_assignments_phase8.md`).** This is the freshest and largest-scoped open item. Steps:
   (a) orchestrator appends the 2 Wave-0 `config.R` constants (`CACHE_PLAYOFF_ODDS_HISTORY`,
   `CACHE_TURNOVER_HISTORY` — exact lines in the phase file's Interface Contracts table) — this
   must happen before Wave 1 starts since both Wave-1 agents who need one of these names them but
   do not edit `config.R` themselves; (b) dispatch the 5 Wave-1 agents (`agent_elo_infra`,
   `agent_playoff_infra`, `agent_turnover_infra`, `agent_viz_b_schedule`, `agent_viz_c_epa`) in
   parallel via the established `subagent-brief` pattern (isolated worktrees per agent, re-verify
   each against its brief's Definition of Done before merge — same process used for issues
   #11-#16 and the accuracy-tracker build); (c) only after Wave 1 is fully merged, dispatch Wave
   2's 4 agents. Read the phase file's "Constraints" section before dispatching
   `agent_playoff_infra` specifically — its backfill is `(latest completed week)`x the normal
   Monte Carlo simulation cost, confirm that's practical before running it unattended.
2. **Close Issue #10 on GitHub — real evidence for both acceptance scenarios now exists** (see
   "Accuracy-trajectory monitoring" above, found 2026-10-13). `gh issue close 10` with the
   2026-10-10/2026-10-11 log excerpt as the closing comment, matching how #1-#9 were each closed
   with real evidence rather than just marked done in this doc.
3. **Decide the fate of the undocumented 2026-10-08 scratch files** (`tools/_inspect_week5.R`,
   `tools/plot_week5_projections.R`, `tools/run_week5_refresh.R`, `cache/week5_projections.png`)
   — commit if the Week 5 projections visualization they support is still wanted, delete
   otherwise. Two sessions have now deferred this; make the call next time. Bundle
   `cache/elo_anim_frames/`'s cleanup into the same pass (Known Issue #11).
4. **Home-backup-QB market-bias finding (Known Issue #2) — DROPPED 2026-10-05, closed.** User
   made the deliberate call: the Bonferroni/BH correction failure is disqualifying, don't invest in
   a depth-chart cache to pursue it further. Nothing left to do here.
5. If continuing the market-disagreement project: Phase 2's public-bet-percentage/handle data angle
   needs an explicit user decision (paid vendor or scraping project) before pursuing.
6. **Known Issue #3 (ordering gap) — fixed in code 2026-10-05, still needs live verification.**
   `risk_management_engine.R` was moved after `bet_tracker.r` in `run_full_pipeline.R`. Still
   unverified as of the 2026-10-13 pipeline run — the real ledger still has 0 RESOLVED bets
   (confirmed: `risk_management_engine.R` logged "0 RESOLVED bets (of 0 total rows)" and fell
   through to `SYNTHETIC_FALLBACK`). Re-run the full pipeline once the real ledger has a RESOLVED
   bet to grade, and confirm `risk_management_engine.R`'s run reflects that same-run grading
   rather than the prior run's.
7. `player_props_engine.R`, team embeddings, a live dashboard, and a true rstan/cmdstanr install for
   the Kalman state-space model remain explicitly deferred non-goals — only start if there's a
   concrete pull for them.
8. No other new feature is currently spec'd and queued the way playoff-odds was — any feature
   beyond the visualization-GIF phase above needs a `/spec-interview` pass before implementation,
   same as every feature shipped so far.
