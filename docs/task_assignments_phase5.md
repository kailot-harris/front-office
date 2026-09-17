# Task Assignments: Phase 6 (NFL Market Odds Engine)
Date: 2026-09-16

**Naming note:** sixth entry in this repo's `task_assignments_phaseN.md` file-numbering series.
DAG-wise this is the `market/props` node's odds-line half (`docs/NFL_REPLICATION_PLAN.md` §1).
This wave is now unblocked: the user has provisioned a real `ODDS_API_KEY` (confirmed live and
visible to R in this repo's environment) and a `NFL_DISCORD_WEBHOOK` (provisioned but **not yet
visible to R in this environment** — a separate `.Renviron`/user-environment lookup-path issue,
unrelated to this wave; `notify_bets.R` is a later wave and must treat that as a normal "webhook
not configured" no-op, not an error).

## Overview
Ports WNBA's `market_odds_engine.R` — sharp-book detection/devig math, EV/Kelly-stake math, and
The Odds API integration are all sport-agnostic and port with only the sport-key string changed
(`basketball_wnba` -> `americanfootball_nfl`), exactly like the WNBA port did from
`basketball_nba`. **Deliberate improvement over the WNBA version**: WNBA's `market_odds_engine.R`
re-derives its own model win-probability from standings net-rating + fatigue + HCA/sigma inline,
duplicating logic that also exists (independently) in that repo's rating engine — a second
place the same math can silently drift. This repo already has `team_ratings_engine.R` computing
real per-game model probabilities into `cache/projected_matchups.rds` for every upcoming
`CACHE_SCHEDULES` game. **This wave's engine must consume that cache as its model-probability
source, not re-derive win probability from scratch** — layering only a fatigue adjustment
(from `cache/fatigue_metrics.rds`) on top, recomputed via `pnorm()` with `config.R`'s
`NFL_HCA`/`NFL_MARGIN_SIGMA` (reference the constants; do not restate their derivation).

## Task Tracker

| Task ID | Wave | Owner (agent) | Files Owned | Findings/Requirements Covered | Status |
| :--- | :--- | :--- | :--- | :--- | :--- |
| P6-A | 1 | `nfl_market_agent` | `market_odds_engine.R` | REPLICATION_PLAN §2 (Odds API `americanfootball_nfl`, event-odds vs featured-markets split — h2h only this wave), sport-agnostic devig/Kelly math, single-source-of-truth reuse of `projected_matchups.rds` | PENDING |
| P6-B | 2 | `nfl_pipeline_wire_agent` | `run_full_pipeline.R` | Wire the new stage into the existing 8-stage DAG | PENDING |

## File-ownership disjointness check
`market_odds_engine.R` does not currently exist (verified via `Glob`). `run_full_pipeline.R`
exists and is owned exclusively by P6-B, which runs after P6-A lands.

## Interface contract

| Script | Exposed function | Contract | Reads | Writes |
| :--- | :--- | :--- | :--- | :--- |
| `market_odds_engine.R` | `run_market_odds_engine()` | No required args; fetches live NFL moneyline (`h2h`) odds from The Odds API (`ODDS_API_KEY` via `Sys.getenv()`, **never interpolated into a logged/printed URL string** — same H-1 pattern as WNBA's version: attach the key on the request object immediately before `req_perform()`, log only the keyless base URL) for sport key `americanfootball_nfl`; on API failure or missing key, falls back to a clearly-labeled `SYNTHETIC_FALLBACK` fixture slate built from real current `NFL_TEAMS` (fabricated odds, tagged `market_data_source`); resolves team names against `NFL_TEAMS`; joins each game to `cache/projected_matchups.rds`'s real `model_home_prob`/`predicted_margin` (matching on team + date — do not re-derive win probability independently); layers a fatigue adjustment from `cache/fatigue_metrics.rds` on top (recomputed via `pnorm()` using `NFL_HCA`/`NFL_MARGIN_SIGMA`, referenced not restated); computes devigged consensus, EV%, expected CLV, and Kelly stake (port `calculate_kelly()`/`american_to_prob()`/`prob_to_american()`/`american_to_decimal()` verbatim — sport-agnostic); returns `TRUE`/`FALSE` | `cache/projected_matchups.rds` (`CACHE_PROJECTED_MATCHUPS`), `cache/fatigue_metrics.rds` (`CACHE_FATIGUE_METRICS`), `NFL_TEAMS`, `NFL_HCA`, `NFL_MARGIN_SIGMA` | new constants `CACHE_LATEST_VALUE_BETS`, `CACHE_ODDS_HISTORY` (add to `config.R` as the same narrow documented exception pattern used in prior waves) |

## Constraints
- **Secret handling (H-1, per WNBA's own finding)**: the API key must never appear in a logged
  message, a printed URL, or a `stop()`/condition message that reaches `log_error()`. Verify this
  by grepping the actual log output after a live run for the literal key value — do not just trust
  the code looks right.
- Player-prop markets (event-odds endpoint) are explicitly **out of scope** for this wave — h2h
  moneyline only, per `docs/NFL_REPLICATION_PLAN.md` §2's note that props need a separate
  per-event API call; that's `player_props_engine.R`, a later wave.
- Per `docs/NFL_REPLICATION_PLAN.md` §2: NFL should have deeper sharp-book coverage
  (Pinnacle/Circa/lowvig/betonlineag) than WNBA did — verify empirically whether the sharp-book
  detector actually finds a match on a live run rather than assuming it does or doesn't; report
  what you actually observe.
- Do not loosen the Kelly fraction (0.25) or EV thresholds "to compensate" for anything — port
  verbatim, same discipline WNBA's own header comment insists on.
- No `sys.nframe()`/`!interactive()` auto-run guard — this repo's established convention (all 8
  existing stages) is `call_fn`-style explicit invocation.
- `NFL_DISCORD_WEBHOOK` visibility is a separate, already-flagged environment issue — do not
  attempt to fix it as part of this task; it's irrelevant to this engine anyway (no notification
  logic belongs here, that's `notify_bets.R`).

## Handoff Notes
(Appended by each agent as it completes its wave. Do not mark a Task Tracker row COMPLETED
without a corresponding entry here.)

---
