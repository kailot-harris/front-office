# Team Depth/Rotation-Strength Regression: Does `features_cache.rds` Predict Game Margin?

**Date:** 2026-09-17
**Author:** research task, follow-up to `player_metrics.R`'s Tier 1 wiring of
`cache/features_cache.rds` (BPM/minutes-concentration producer).
**Status:** BOTH CANDIDATE TERMS WIRED IN — see "Decision" and "What was wired in" below.

## Research question

`cache/features_cache.rds` (`player_metrics.R::get_player_features()`) ships three per
team-game columns nothing consumes yet: `team_weighted_bpm`, `team_top5_bpm` (mean BPM of
the top-5-by-BPM players that game — a starting-unit-strength proxy), and
`team_minutes_concentration` (Herfindahl-Hirschman Index of that game's minutes distribution
— higher = shorter/more-concentrated rotation). This task asks: do `team_top5_bpm` and/or
`team_minutes_concentration` carry real, forecasting-useful signal for a team's game MARGIN,
beyond what the team's own recent-form baseline already captures? If so, following the same
empirical-derivation template `OPP_DEF_MU_SLOPE`/`SHOT_MIX_PTS_SLOPE` used, should either be
wired into `roster_bottom_up_engine.R`'s production margin formula?

## The circularity trap, and how it was avoided

`team_weighted_bpm`/`team_top5_bpm`/`team_minutes_concentration` for game G are computed FROM
game G's own box stats — the same box stats that mechanically determine game G's score/margin.
Regressing SAME-GAME margin on SAME-GAME `team_top5_bpm` would be near-tautological (a team
that scored a lot that game will mechanically have a high box-score-derived BPM that game) and
would produce a spuriously "significant" result useless for forecasting. **This regression was
never run.**

Instead, a per-team, chronologically-ordered panel was built, and **trailing** (strictly
prior-games-only) rolling averages of `team_top5_bpm`, `team_minutes_concentration`, and the
team's own margin were computed, using ONLY games strictly before the target game — a genuine
leading indicator. The regression tests whether these trailing averages predict the team's
current-row margin (i.e., the "next game" relative to the trailing window), over and above the
team's own trailing-average margin (recent-form/quality baseline).

## Data and join-key verification (done empirically, not assumed)

Two real caches were joined:

- `CACHE_FEATURES` (`cache/features_cache.rds`): 3,906 real team-game rows, `game_id` (chr),
  `team_id` (int), `team_top5_bpm`, `team_minutes_concentration`.
- `CACHE_PLAYER_BOX` (`cache/player_box_scores_cache.rds`): 44,675 real per-player-per-game
  rows, collapsed to one row per (game_id, team_id) for `team_score`/`opponent_team_score`
  (margin), `season`, `game_date`, `team_abbreviation`.

Per CLAUDE.md's caution, `filter_real_franchises()`/`normalize_team_abbreviation()`
(`player_metrics.R`, CONN→CON) were applied defensively before collapsing — confirmed this
had ZERO effect (0 rows dropped): `CACHE_PLAYER_BOX` was already built post-fix, containing
exactly the 15 real `WNBA_TEAMS` abbreviations. Both caches derive from the same
`wehoop::load_wnba_player_box()` pull inside `get_player_features()`, so an EXACT match was
expected and was verified rather than assumed: **all 3,906 `CACHE_FEATURES` (game_id, team_id)
rows matched a `CACHE_PLAYER_BOX` team-game exactly (100.00%)** after casting `game_id` to
character on the box side. Direct join, no bridging layer needed (unlike the RAPM↔roster case
in `rapm_join_utils.R`).

## Panel construction and trailing-average methodology

Team-game panel: 3,906 rows, 15 teams, 1,953 distinct games, seasons 2019–2026.

For each team, ordered chronologically by `game_date`, trailing averages were computed as
`mean(x[i-w .. i-1])` where `w = min(ROLLING_WINDOW_SIZE, i-1)` — i.e. the mean over the prior
up-to-`ROLLING_WINDOW_SIZE` games, **strictly excluding** the target row `i`. `ROLLING_WINDOW_SIZE
= 12` (config.R's existing, empirically re-tested rolling-window constant — reused rather than
re-derived, per the repo's stated convention of reading structural constants from config.R
rather than re-deriving them locally).

**Minimum trailing-games threshold: `MIN_TRAILING_GAMES = 5`** — the full 12-game window would
exclude a large fraction of each team's early-season games; relaxed to 5, matching the exact
`>= 5-games` threshold already used for `OPP_DEF_MU_SLOPE`/`SHOT_MIX_PTS_SLOPE` elsewhere in
this repo (same documented precedent, not a new arbitrary number).

**Resulting qualifying panel: 3,831 team-games across all 15 teams**, seasons 2019–2026.

## Collinearity check

`trailing_avg_team_top5_bpm` and `trailing_avg_margin` are plausibly correlated (a strong
recent starting five usually accompanies recent winning margins):

| pair | correlation |
|---|---|
| `trailing_avg_team_top5_bpm` vs `trailing_avg_margin` | 0.613 |
| `trailing_avg_team_minutes_concentration` vs `trailing_avg_margin` | 0.199 |
| `trailing_avg_team_minutes_concentration` vs `trailing_avg_team_top5_bpm` | 0.754 |

Manual VIFs (auxiliary regression of each regressor on the other two, no `car` package
dependency): `trailing_avg_margin` = 2.16, `trailing_avg_team_minutes_concentration` = 3.12,
`trailing_avg_team_top5_bpm` = 4.80. All below the VIF > 5 rule-of-thumb ceiling, though
`trailing_avg_team_top5_bpm`'s VIF (4.80) sits close to it — flagged here for transparency,
but not disqualifying: none of the three pairwise correlations exceed 0.8, and (per Section
below) both new terms retain independently significant, correctly-signed coefficients even
with all three regressors in the same model.

## Regression methodology and results

Within-team fixed effects (team-level scoring quality differenced out), mirroring
`OPP_DEF_MU_SLOPE`/`SHOT_MIX_PTS_SLOPE`'s exact approach: each team's `margin`,
`trailing_avg_margin`, `trailing_avg_team_minutes_concentration`, and
`trailing_avg_team_top5_bpm` de-meaned by their own team-level mean over the qualifying panel,
then OLS on the de-meaned variables (cross-checked against an explicit
`lm(margin ~ ... + factor(team_id))`, which reproduces the identical coefficients to 4 decimal
places — confirming the demeaning shortcut is not a biased approximation).

**Model 1 — margin ~ trailing_avg_margin only (recent-form baseline):**
```
trailing_avg_margin: +0.5187  SE 0.0384  t = 13.52  p < 2e-16
R^2 = 0.0456, n = 3,831
```

**Model 2 — + trailing_avg_team_minutes_concentration (alone):**
```
trailing_avg_margin:                     +0.5139  SE 0.0390  t = 13.16  p < 2e-16
trailing_avg_team_minutes_concentration: +19.89   SE 30.09   t =  0.661 p = 0.509  (NOT significant alone)
```

**Model 3 — + trailing_avg_team_top5_bpm (alone):**
```
trailing_avg_margin:        +0.4499  SE 0.0478  t =  9.41  p < 2e-16
trailing_avg_team_top5_bpm: +0.4878  SE 0.2028  t =  2.41  p = 0.0162
```

**Model 4 (full, primary model) — margin ~ trailing_avg_margin + trailing_avg_team_minutes_concentration + trailing_avg_team_top5_bpm:**
```
trailing_avg_margin:                     +0.3848   SE 0.0556  t = +6.93  p = 5.06e-12
trailing_avg_team_minutes_concentration: -120.82   SE 52.59   t = -2.30  p = 0.0217
trailing_avg_team_top5_bpm:               +1.1563  SE 0.3546  t = +3.26  p = 0.00112
R^2 = 0.0483, n = 3,831 team-games, 15 teams
```

**Model 5 — explicit `lm(margin ~ trailing_avg_margin + trailing_avg_team_minutes_concentration + trailing_avg_team_top5_bpm + factor(team_id))` sanity check:**
```
trailing_avg_margin:                     +0.3848  p = 5.5e-12
trailing_avg_team_minutes_concentration: -120.82  p = 0.0219
trailing_avg_team_top5_bpm:               +1.1563 p = 0.00114
```
Reproduces Model 4's coefficients to 4 decimal places — confirms the demeaning shortcut is
equivalent to a true fixed-effects regression.

**Note on Model 2/3 vs Model 4**: `trailing_avg_team_minutes_concentration` alone (Model 2) is
NOT significant (p = 0.509), but becomes significant once `trailing_avg_team_top5_bpm` is also
in the model (Model 4, p = 0.022). This is expected given the 0.75 correlation between the two
depth features noted above — `trailing_avg_team_top5_bpm` was soaking up shared variance in
Model 2's omission; the full model (4) is the one used for the significance decision, per the
task's specified regression.

## Decision (each term judged independently)

**`trailing_avg_team_top5_bpm`**: coefficient +1.1563, p = 0.00112 — clears p < 0.05, and the
sign is theory-sensible (a stronger recent starting unit should predict a better upcoming
margin, and it does). **WIRE IN.**

**`trailing_avg_team_minutes_concentration`**: coefficient -120.82, p = 0.0217 — clears p <
0.05. The sign was explicitly flagged a priori as ambiguous (a short/concentrated rotation
could mean "reliance on stars = good when healthy" OR "thin bench = fatigue/foul-trouble risk
= bad"). The empirical sign came out NEGATIVE: a more concentrated recent rotation predicts a
WORSE next-game margin, consistent with the "thin bench fragility" reading over the "star
reliance" reading. No motivated reasoning was applied to pick this sign after the fact — it is
reported exactly as it came out, and it clears the significance bar. **WIRE IN.**

It was not guaranteed both terms would clear the bar (the task explicitly anticipated zero, one,
or both qualifying) — both happened to, independently, in Model 4.

## What was wired in

Added to `roster_bottom_up_engine.R`, alongside (never modifying) the existing
`rating_diff`/`rapm_diff`/`elo_margin`/`hca`/0.4/0.4/0.2 terms:

- **`TOP5_BPM_MARGIN_SLOPE <- 1.1563`** and **`MINUTES_CONCENTRATION_MARGIN_SLOPE <- -120.8159`**
  — the Model 4 coefficients above. Unlike `OPP_DEF_MU_SLOPE`/`SHOT_MIX_PTS_SLOPE` (which scale
  a per-player projected mean and needed a fractional/multiplicative re-expression), this
  regression was fit directly on margin in points, so the raw coefficients ARE the
  points-per-unit scale used — no ratio/multiplier re-derivation needed.
- **`DEPTH_ADJ_CLAMP <- c(-6.0, 6.0)`** — the real depth adjustment across all 15×14 ordered
  current-team pairs (computed from each team's actual current trailing-12-game signal as of
  this cache snapshot) ranges only -4.14 to +4.14 points (the two terms are positively
  correlated across teams in practice and partially offset each other) — the clamp does not
  bind on real data, same non-binding-by-design rationale as `OPP_DEF_MU_CLAMP`/
  `SHOT_MIX_PTS_CLAMP`; it exists purely as a rail against a future degenerate
  `features_cache.rds`.
- **`get_team_depth_signal()`** — loads `cache/features_cache.rds` +
  `cache/player_box_scores_cache.rds` (+ `active_rosters_cache.rds` for the `team_id` →
  `team_name` key `compute_team_live_rating()` already uses) and returns each team's CURRENT
  trailing-`ROLLING_WINDOW_SIZE`-game average `team_top5_bpm`/`team_minutes_concentration` —
  the same quantity the regression was fit on, evaluated at "today." Fail-safe: returns an
  empty tibble (never errors) if any of the three caches is missing, or a 0-row team if it has
  fewer than 5 qualifying trailing games.
- **`adjust_margin_for_depth(home_top5_bpm, home_minutes_concentration, away_top5_bpm,
  away_minutes_concentration)`** — additive points-scale delta:
  `TOP5_BPM_MARGIN_SLOPE * (home_top5 - away_top5) + MINUTES_CONCENTRATION_MARGIN_SLOPE *
  (home_conc - away_conc)`, clamped to `DEPTH_ADJ_CLAMP`. Any non-finite input (a team missing
  from `get_team_depth_signal()`'s output) resolves to a 0.0 no-op, never NA/error.
- **`.depth_signal_scalar()`** — small helper to pull a single team's signal value out of
  `get_team_depth_signal()`'s output, `NA_real_` if absent.
- Wired into `predict_live_matchup()`'s `expected_margin`:
  `expected_margin <- (0.4 * rating_diff) + (0.4 * rapm_diff) + (0.2 * elo_margin) + hca +
  depth_adjustment` — `rating_diff`, `rapm_diff`, `elo_margin`, `hca`, and the 0.4/0.4/0.2
  weights are UNCHANGED.
- Also wired into `project_all_wnba_teams()`'s round-robin simulation loop (`margin_home`/
  `margin_away`), which computes the same formula inline for all 15×14 team pairs rather than
  calling `predict_live_matchup()` — `depth_adj` is added for the home team and subtracted for
  the away team, mirroring exactly how `hca` itself already flips sign between
  `margin_home`/`margin_away` in that loop. This was necessary for the depth signal to actually
  reach `cache/projected_wnba_standings.rds` (the production standings/spread output), since
  that loop does not call `predict_live_matchup()`.

### Verification

`Rscript.exe roster_bottom_up_engine.R` was re-run after wiring and completed without error,
producing plausible standings (`cache/projected_wnba_standings.rds`, all 15 teams, win totals
summing to 327.7/330.0 expected league total — the same zero-sum-ish invariant as before,
unaffected by the added term since depth adjustments cancel across the full round robin).

Direct spot-check via `predict_live_matchup()`, using the two teams with the most extreme
current trailing top5-BPM signal (Atlanta Dream: `depth_top5_bpm` = 11.90,
`depth_minutes_concentration` = 0.142; Connecticut Sun: `depth_top5_bpm` = 5.76,
`depth_minutes_concentration` = 0.113):

```
adjust_margin_for_depth(ATL as home, CON as away) = +3.64 points
predict_live_matchup("Atlanta Dream", "Connecticut Sun", ...)$Proj_Margin = 16.0
```

The +3.64-point depth contribution moves in the expected direction (Atlanta, the team with the
stronger recent starting five, gets a positive margin boost as home team against a team with a
markedly weaker recent top-5 signal) and stays well inside the ±6.0 clamp, consistent with the
non-binding-clamp analysis above.

`Rscript.exe tools/verify_pipeline_stage.R roster_bottom_up_engine.R --entry_fn
project_all_wnba_teams cache/projected_wnba_standings.rds` confirmed the pipeline-stage
contract still holds: `project_all_wnba_teams` exists in `.GlobalEnv` after sourcing, and
`cache/projected_wnba_standings.rds`'s mtime advanced past the verification run's start (no
silent no-op).

### Reproducing this derivation

`tools/research_team_depth_regression.R` reproduces the full derivation end-to-end (join-key
verification, panel build, trailing-average construction, collinearity check, all 5 regression
models, decision logic, and a live current-signal-per-team printout) via a single
`Rscript.exe tools/research_team_depth_regression.R` run. Re-run whenever
`cache/features_cache.rds`/`cache/player_box_scores_cache.rds` are refreshed with more seasons
to confirm the coefficients in `roster_bottom_up_engine.R` are still current.

## Addendum (2026-09-19) — re-derived after BPM weight recalibration

`player_metrics.R::calculate_bpm_components()`'s `steals` weight changed from 1.40 to 0.875
(`docs/bpm_recalibration_findings.md`), which changes `raw_bpm_rate` and therefore
`team_top5_bpm`/`team_weighted_bpm` — this doc's own "re-run whenever coefficients change"
instruction, followed. `cache/features_cache.rds` was regenerated
(`compute_and_cache_player_features()`, mtime-verified fresh) and
`tools/research_team_depth_regression.R` re-run against it. Both terms stayed significant with
the same sign; magnitudes moved modestly:

| term | prior (2026-09-17) | current (2026-09-19) |
|---|---|---|
| `trailing_avg_team_top5_bpm` | +1.1563, p=0.00112 | +1.0509, p=0.00345 |
| `trailing_avg_team_minutes_concentration` | -120.82, p=0.0217 | -102.17, p=0.0470 |
| real depth-adjustment spread (15×14 ordered pairs) | -4.14 to +4.14 | -3.80 to +3.80 |

`roster_bottom_up_engine.R`'s `TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE`
constants were updated to the current values above; `DEPTH_ADJ_CLAMP` (±6.0) remains
comfortably non-binding and was left unchanged. Original 2026-09-17 numbers above are kept
as-is (historical record, not rewritten) per this repo's append-only documentation convention.
