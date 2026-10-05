# Spec: Playoff-Clinching Probability Table

**Status:** Spec'd via `/spec-interview` on 2026-10-05. Not yet implemented — tracked as GitHub
issues (see repo Issues tab). This doc is the frozen source of truth for what was agreed; update
it only if the spec itself changes (re-run the interview or get explicit sign-off), not silently
during implementation.

## Background

`playoff_simulator.R` already Monte Carlo-simulates the playoff *bracket* (Wild Card through
Super Bowl) for the 14 teams currently in the real, provisional 14-team field — see that file's
header for the live-verified reseeding-bracket rules. It does not estimate anything for the other
18 teams, and it does not answer "what is this team's probability of making the playoffs at all" —
only "given you're already in the field, how far do you go." This spec covers a new, separate
feature: a probability, for **all 32 teams**, of clinching a playoff spot.

## Scope

Estimate P(team makes the playoffs) for all 32 NFL teams via Monte Carlo simulation of the
remaining regular-season schedule, then surface it as (a) a new cache artifact and (b) a Discord
message, on the existing daily pipeline cadence.

**Explicitly out of scope for this effort** (deferred to separate future tickets if pursued):
- Round-by-round advancement odds (wild card/divisional/conf champ/Super Bowl) for all 32 teams.
  `playoff_simulator.R`'s existing output remains the only source of round-by-round odds, and
  stays scoped to the 14 teams in the real current field.
- Any rendered dashboard or Quarto doc. Output surfaces are a cache `.rds` file and a Discord
  message only, matching every other pipeline stage's existing pattern.
- Cadence throttling beyond "once per pipeline run" (the pipeline itself runs once daily via the
  existing Windows Task Scheduler job, `NFL_analytics_task_01`).

## Design decisions (from the interview)

1. **What "playoff probability" means here:** probability of making the playoffs (in/out) for all
   32 teams — not round-by-round advancement odds, and not limited to the 14 teams already in the
   real provisional field.
2. **Simulation fidelity:** each of `N_SEASON_SIMULATIONS` trials re-runs the **real**
   `nfl_tiebreakers.R` procedure (`resolve_division_ties`/`resolve_wildcard_ties`) to seed that
   simulated season — not a simplified win-pct-only tiebreak. Per-game win probabilities for
   remaining (not-yet-played) games reuse the same approach `playoff_simulator.R` already uses:
   `team_ratings_engine.R`'s `power_rating` + `config.R`'s `NFL_HCA`/`NFL_MARGIN_SIGMA` via
   `pnorm()`.
3. **New constant, not a reused one:** `N_SEASON_SIMULATIONS` (new `config.R` constant), separate
   from the existing `N_SIMULATIONS` (10000, used by the bracket-only sim). Each trial here is far
   heavier (simulate every remaining game for all 32 teams, then run the real tiebreaker
   procedure) than a bracket-only trial, so it gets its own, independently-tunable count. Proposed
   starting value: 1000 — to be timed against real data during implementation and adjusted if too
   slow/fast. Document the derivation/timing the same way other `config.R` constants are
   documented (value, why, date, what was measured).
4. **New script, not an extension:** `playoff_odds_engine.R` (new file, repo root), following this
   repo's one-script-per-concern convention. Sources `playoff_simulator.R` (or `nfl_tiebreakers.R`
   directly) to reuse seeding helpers rather than duplicating that logic. `playoff_simulator.R`
   itself is untouched by this effort.
5. **Output cache:** new `config.R` constant `CACHE_PLAYOFF_ODDS`. Contents: `season`,
   `generated_at`, `n_simulations`, and a 32-row data.frame (`team`, `conference`, `division`,
   `playoff_prob`).
6. **Pipeline wiring:** new `run_stage()` call in `run_full_pipeline.R`, positioned after the
   team-ratings and schedule-ingest stages it depends on (same dependency shape as
   `playoff_simulator.R`'s existing stage). Runs every pipeline execution — no cadence gate.
7. **Discord dispatch:** same webhook/pattern as `notify_bets.R`/`accuracy_tracker.R` — reads
   `NFL_DISCORD_WEBHOOK` (no new/separate webhook), POSTs an embed, falls back to a console-only
   preview if the env var is unset. To stay within Discord's per-embed field limits and keep it
   readable, format as **two fields (AFC, NFC)**, each a compact multi-line list of that
   conference's 16 teams sorted by descending `playoff_prob` — not 32 individual fields.

## Open parameters implementation should settle empirically

- Exact value of `N_SEASON_SIMULATIONS` (starting guess 1000) — time it for real before locking
  it in.
