# Spec: NFL Accuracy-Trajectory Monitoring

**Status:** Spec'd via `/spec-interview` on 2026-10-04. Not yet implemented — tracked as GitHub
issues (see repo Issues tab). This doc is the frozen source of truth for what was agreed; update
it only if the spec itself changes (re-run the interview or get explicit sign-off), not silently
during implementation.

## Background

`notify_bets.R`'s Discord dispatch was fixed this session (`NFL_DISCORD_WEBHOOK` env-var
visibility bug — see `docs/HANDOFF.md` Known Issues #1). That surfaced a real gap: there is no
way to watch the model's prediction accuracy evolve over the course of a season. The existing
`tools/weekly_accuracy_report.R` recomputes a full walk-forward accuracy table from scratch every
time it's manually run, but overwrites `cache/weekly_accuracy_report.rds` each run — there is no
persisted history across runs, and no automated trigger.

## Scope

Track the model's season-to-date prediction accuracy over time and surface it via a persisted
history cache + Discord posts.

**Explicitly out of scope for this effort** (deferred to separate future tickets if pursued):
- A Shiny dashboard (`app.R` does not exist in this repo at all yet — building one is a
  materially bigger, separate piece of work, not a tab addition).
- Any coupling to the staking/`MIN_SAMPLE_GAMES_FOR_STAKE` gate. That gate is computed **per
  game** (`pmin(home_games_played, away_games_played) < MIN_SAMPLE_GAMES_FOR_STAKE` in
  `market_odds_engine.R`), not as a single season-wide on/off event, so there is no single
  "gate cleared" moment to react to. This feature is intentionally independent of staking status
  — treat it as if live betting will never occur.

## Design decisions (from the interview)

1. **Output surfaces:** (a) persisted history cache across runs, (b) Discord webhook summary
   posts. No dashboard for now.
2. **Shared grading logic:** Extract the walk-forward grading + production-formula logic
   currently inline in `tools/weekly_accuracy_report.R` into a reusable function in
   `tools/backtest_common.R`, so both the existing standalone tool and the new pipeline stage call
   one implementation — avoids a second/third copy of the ensemble formula (the exact class of
   drift `CLAUDE.md` warns about for constants, applied here to formulas).
3. **New pipeline stage:** `accuracy_tracker.R`, exposing `run_accuracy_tracker()` via the
   existing `call_fn` stage convention (no auto-run guard), added as **stage 12** in
   `run_full_pipeline.R`, after `notify_bets.R`.
4. **Trigger condition:** Idempotent, not calendar-based. The new stage compares the current set
   of completed/graded games for `CURRENT_SEASON` against what's already recorded in the
   persisted history cache. If nothing new → no-op (no history append, no Discord post). If new
   completed games exist → append + post. This means the stage is safe to invoke daily
   unconditionally (including on bye/off days) without spamming duplicate reports, and requires
   no separate "is today a game day" schedule lookup.
5. **History granularity:** One row per **run that detects new completed games** (not one row per
   NFL week). This can capture partial weeks — e.g. a row appears right after Thursday Night
   Football finishes, before the rest of that week's games are final. Choppier than week-level
   granularity but more immediate.
6. **History cache:** New constant `CACHE_ACCURACY_HISTORY` in `config.R`, alongside the other
   `CACHE_*` constants. Each row stores: run timestamp, season, the newly-graded game(s) detail
   (matchup, predicted winner, actual winner, correct/miss, predicted win probability), and the
   updated cumulative accuracy/Brier/log-loss across all graded games so far this season as of
   that run (the actual "trajectory" line — cumulative, not just the incremental delta).
7. **Discord content:** Each post includes both the incremental detail (which specific game(s)
   just got graded, prediction vs. actual) and the updated cumulative season-to-date metrics (e.g.
   "Season accuracy: 62% over 14 games, Brier 0.21").
8. **Discord channel:** Reuses the existing `NFL_DISCORD_WEBHOOK` env var/channel — same one
   `notify_bets.R` already dispatches bet alerts to. No new secret/env var.
9. **Scheduling:** A new Windows Task Scheduler job runs the **entire `run_full_pipeline.R`**
   (all 12 stages, not just the new one) once daily, guaranteeing EPA/schedules/ratings data is
   fresh before the new stage grades anything. No separate game-day calendar gate is needed
   because the stage's own idempotency (point 4) makes daily unconditional firing safe.

## Open implementation details (not blocking, resolve during build)

- Exact history cache schema (data.frame column names/types).
- Exact Task Scheduler trigger time (default: once daily in the evening/late night, to catch all
  of that day's completed games — confirm or adjust during the scheduling issue's implementation).

## Formula-parity constraint

Any pipeline-stage or tool that grades predictions against the production formula must call the
shared function from `tools/backtest_common.R` (per decision #2) — never re-derive or copy the
ridge+Elo ensemble formula a second time. If `team_ratings_engine.R`'s production formula ever
changes, the shared function is the only place that needs updating.
