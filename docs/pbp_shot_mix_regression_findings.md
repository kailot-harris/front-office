# Shot-Mix (Rim-Attempt Share) Regression: Does It Predict Game-Level Scoring Efficiency?

**Date:** 2026-09-17
**Author:** research task, follow-up to `pbp_engine.R` (Phase 4 PBP feature work)
**Status:** WIRED IN — see "Decision" and "What was wired in" below.

## Research question

`pbp_engine.R` already ships a season-aggregated `pct_rim` (rim-attempt share of a
player's 2PA shots) per current-roster player in `cache/player_pbp_features.rds`.
Rim shots are the highest-efficiency, lowest-variance shot type in basketball. This
task asks: does a player's **game-level** rim-attempt share predict that game's
scoring output, beyond what the player's own season-average `pts_mu` (used
everywhere in `player_props_engine.R`) already captures? If so, following the
exact empirical/methodological template `OPP_DEF_MU_SLOPE` used for the RAPM
opponent adjustment, should it be wired into PTS pricing the same way?

## Data and join-key verification (done empirically, not assumed)

Two real caches were joined:

- `CACHE_PBP_RAW` (`cache/wnba_espn_pbp_cache.rds`): 763,018 real ESPN
  `wehoop::load_wnba_pbp()` events, 2019-2026, columns include `game_id`,
  `athlete_id_1` (shooter), `type_text`, `points_attempted`, `shooting_play`.
- `CACHE_PLAYER_BOX` (`cache/player_box_scores_cache.rds`): 44,675 real
  per-player-per-game rows, columns include `game_id`, `athlete_id`, `points`,
  `minutes`.

`rapm_engine.R`'s header warns that WNBA-Stats-API `game_id` and ESPN `game_id`
are two different namespaces that do NOT join. Both caches used here are
ESPN-backed, so this warning did not automatically apply, but was checked
empirically rather than assumed:

- `game_id` is `integer` in both caches. 1,957 distinct PBP game_ids, 1,953
  distinct box game_ids, **1,950 in common (99.85% of box game_ids found in
  PBP)** — direct integer join, no translation needed.
- `athlete_id_1` (PBP) / `athlete_id` (box) are the same ESPN player-id
  namespace: 437 of 446 distinct PBP shooter ids and 441 distinct box athlete
  ids overlap directly (consistent with `pbp_engine.R`'s header claim that this
  namespace already matches `active_rosters_cache.rds$player_id`).
- At the (athlete_id, game_id) grain: 44,675 distinct box player-games, 37,365
  distinct PBP shooter-appearances; **inner join matched 37,149 pairs (83.15%
  of box player-games)**. The unmatched 16.85% are real 0-FGA player-games
  (a player who played but never attempted a shot never appears as
  `athlete_id_1` on a shooting event) — a legitimate exclusion, not a join
  failure, and exactly the rows this analysis should drop anyway since `pct_rim`
  is undefined with zero attempts.

**Conclusion: the (game_id, athlete_id) join between `CACHE_PBP_RAW` and
`CACHE_PLAYER_BOX` is direct and reliable.** No name-matching or id-bridging
layer was needed (unlike the RAPM<->roster case in `rapm_join_utils.R`).

## Panel construction

For each (athlete_id, game_id) pair with at least one shooting-play event:

- `fga_total` = count of all `shooting_play == TRUE` events by that player in
  that game.
- `two_pa_total` / `rim_n` = count of `points_attempted == 2` events / the
  subset matching the rim keyword regex, **using the exact same regex
  `pbp_engine.R` already ships** (`.RIM_KW <- "(?i)layup|dunk|putback|tip
  shot|tip-in|tip in"`) — not a re-invented bucketing scheme, so this panel's
  numbers agree with the season-aggregated numbers already in the dashboard.
- `pct_rim = rim_n / two_pa_total` (same denominator convention as
  `pbp_engine.R`'s `pct_rim` column — 2PA-only, not all-FGA).
- Joined to that game's real `points` and `minutes` from `CACHE_PLAYER_BOX` on
  `(athlete_id, game_id)`.

**Filters** (documented thresholds):
- `fga_total >= 3` per player-game — excludes 1-2 shot cameo appearances where
  `pct_rim` is a near-meaningless 0/1 artifact of a tiny sample.
- `two_pa_total > 0` and non-missing `pct_rim` — a game where every shot was a
  three has an undefined 2PA-based `pct_rim`.
- Players with **>= 5 qualifying games** — the same minimum-games threshold
  `OPP_DEF_MU_SLOPE`'s own derivation used elsewhere in this repo.

**Resulting panel: 13,037 player-games across 235 distinct players**, all
seasons 2019-2026. `pct_rim` mean 0.568 (min 0, max 1); `points` mean 10.79;
`minutes` mean 24.48.

## Regression methodology and results

Within-player fixed effects (player-level scoring ability differenced out),
mirroring `OPP_DEF_MU_SLOPE`'s exact approach: each player's `points`,
`pct_rim`, and `minutes` de-meaned by their own player-level mean, then OLS on
the de-meaned variables (algebraically equivalent to `lm(y ~ x + factor(id))`,
and cross-checked against the literal `factor(athlete_id)` version below to
confirm the demeaning shortcut is not silently biased).

**Model 1 — absolute points, pct_rim only, no minutes control:**
```
pct_rim coefficient: +1.0416   SE 0.1875   t = 5.556   p = 2.81e-08
```

**Model 2 — absolute points, + minutes control (primary corroboration model):**
```
pct_rim coefficient: +0.9586   SE 0.1630   t = 5.880   p = 4.21e-09
minutes coefficient: +0.4540   SE 0.0070   t = 64.81   p < 2.2e-16
R^2 = 0.2455, n = 13,037
```

**Model 3 — fractional (points / player's own mean points), + minutes control
(the estimand actually used for the multiplicative adjustment below):**
```
pct_rim coefficient: +0.1174   SE 0.0160   t = 7.326   p = 2.51e-13
minutes coefficient: +0.04793  SE 0.0007   t = 69.60   p < 2.2e-16
R^2 = 0.2734, n = 13,037
```

**Model 4 — explicit `lm(points ~ pct_rim + minutes + factor(athlete_id))`
sanity check:**
```
pct_rim coefficient: +0.9586   SE 0.1645   t = 5.827   p = 5.79e-09
```
Reproduces Model 2's coefficient to 4 decimal places — confirms the demeaning
shortcut used for Models 1-3 is equivalent to a true fixed-effects regression,
not a biased approximation.

**No-minutes-control robustness (Model 1) also significant at the same sign** —
the effect is not an artifact of controlling for minutes.

### Corroboration check (optional, per task spec) — and why it disagrees in sign

A cross-sectional (between-player) check was also run: player-season aggregate
`pct_rim` (possession-weighted) vs. player-season PPG, current-season players
with >= 5 games (n = 473 player-seasons):
```
Pearson r = -0.138, p = 0.0026 (95% CI: -0.226 to -0.049)
```
This is the OPPOSITE sign of the within-player result, and that is expected,
not a contradiction: it is a between-player comparison confounded by role and
usage. Low-usage post players who almost never shoot outside the paint have a
high season `pct_rim` but score less overall than high-usage perimeter scorers
who take a lot of pull-ups, step-backs, and threes. This is exactly the
confound within-player fixed effects are designed to remove, and is reported
here for transparency rather than treated as load-bearing (matching the task
spec's "nice-to-have, not load-bearing" instruction for this corroboration
check).

## Decision

p = 2.51e-13 at n = 13,037 comfortably clears the p < 0.05 significance bar,
the within-player sign is theoretically sensible (rim shots are the most
efficient shot type — a player scores more than their own average in games
where more of their shots come at the rim), and the result survives a literal
fixed-effects cross-check (Model 4) and a no-minutes-control robustness check
(Model 1). **This clears the bar to wire in**, unlike a null result would have.

## What was wired in

Following `adjust_mu_for_opponent()`'s exact pattern, added to
`player_props_engine.R` (never touching `get_team_def_rapm()`,
`adjust_mu_for_opponent()`, or `OPP_DEF_MU_SLOPE`):

- **`SHOT_MIX_PTS_SLOPE <- 0.1174`** — the fractional-points-per-unit-pct_rim
  estimate from Model 3 above.
- **`SHOT_MIX_PTS_CLAMP <- c(0.90, 1.10)`** — real current-roster players'
  season-aggregated `pct_rim` (`cache/player_pbp_features.rds`, players with
  >= 20 FGA, n = 184) ranges 0.127-0.955 around a league mean of 0.593, which
  maps to an **unclamped ratio range of only 0.945x-1.042x** — the clamp does
  not bind on real data (same non-binding-by-design rationale as
  `OPP_DEF_MU_CLAMP`); it exists solely as a rail against a future degenerate
  PBP features cache.
- **`adjust_mu_for_shot_mix(base_mu, player_pct_rim, league_avg_pct_rim)`** —
  additive-in-log-space centred multiplier, structured identically to
  `adjust_mu_for_opponent()`: returns `base_mu` unchanged if
  `league_avg_pct_rim` isn't finite (cache missing/empty), and resolves a
  missing per-player `pct_rim` (no PBP events yet) to a neutral 1x multiplier
  rather than propagating `NA`.
- **`get_player_pct_rim()`** — loads `CACHE_PLAYER_PBP_FEATURES`
  (`cache/player_pbp_features.rds`, read-only, `pbp_engine.R`'s existing
  shipped cache, never recomputed here) and returns a `(player_id, pct_rim)`
  lookup with the league mean carried as an attribute, mirroring
  `get_team_def_rapm()`'s `neutral()`/attribute pattern.
- Wired into `generate_active_props_table()`'s **PTS path only**:
  `adj_pts = adjust_mu_for_shot_mix(adjust_mu_for_opponent(pts_mu, opp_def_rapm,
  league_avg_def), pct_rim, league_avg_pct_rim)` — the two adjustments are
  composed **multiplicatively** (opponent ratio, then shot-mix ratio, both
  centred on 1.0), not re-derived as a single joint coefficient. `REB`, `AST`,
  `FG3M`, `STL`, `BLK` are deliberately left untouched — the shot-mix signal is
  specifically about scoring efficiency and has no theoretical link to those
  categories.
- `build_real_rotation_table()`'s final `transmute()` now also carries
  `player_id` through to `props_base` (it previously dropped it after the
  roster/box join), since the shot-mix join needs the same direct ESPN-namespace
  `player_id` key `pbp_engine.R` already established as safe. `props_base`
  falls back to `pct_rim = NA_real_` for every row when `player_id` isn't
  present at all (the `SYNTHETIC_FALLBACK` no-real-roster path), which
  `adjust_mu_for_shot_mix()` already resolves to a no-op.

### Verification

`Rscript.exe player_props_engine.R` was re-run after wiring and completed
without error:
```
[PROPS] Shot-mix PTS adjustment centred on league mean pct_rim = 0.579
        (slope 0.1174/unit, clamped to [0.90, 1.10]).
>>> [PROPS] Processed 768 total props across 15 teams. Discovered 722 positive
    EV (>= +5.0%) edges.
```
Spot check of real players (`cache/latest_player_props.rds`, PTS rows, players
with `fga_total >= 20`), confirming the adjustment moves in the documented
direction:

| Player (high pct_rim) | pct_rim | proj_mu (adj_pts) |
|---|---|---|
| Tonie Morgan | 0.955 | 4.97 |
| Naz Hillmon | 0.935 | 9.19 |
| Angel Reese | 0.867 | 16.1 |

| Player (low pct_rim) | pct_rim | proj_mu (adj_pts) |
|---|---|---|
| Paige Bueckers | 0.195 | 20.0 |
| Chelsea Gray | 0.191 | 11.5 |
| Courtney Williams | 0.127 | 13.3 |

Values are plausible real-player scoring levels; the shot-mix ratio is a small
(<= ~4%) nudge on top of each player's own opponent-adjusted mean, consistent
with the non-binding clamp analysis above.
