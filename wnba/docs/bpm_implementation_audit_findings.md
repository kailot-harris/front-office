# Audit: `get_player_bpm_ratings()` vs. `calculate_bpm_components()` — 2026-09-17

**Trigger:** `docs/HANDOFF.md` (2026-09-17) open item #1 — two independent, differently-weighted
BPM implementations feed the live margin formula through separate paths and were never checked
against each other.

## What each one actually computes

| | `get_player_bpm_ratings()` (`roster_bottom_up_engine.R:212`) | `calculate_bpm_components()` (`player_metrics.R:94`) |
|---|---|---|
| Granularity | One row per player, aggregated across a player's **entire season history** (season-recency-weighted 1.5x/1.0x) | One row per **player-game**, no cross-game aggregation inside the function itself |
| Box-score weights | `0.55*pts36 + 0.60*reb36 + 1.10*ast36 + 1.40*stl36 + 1.20*blk36 - 1.25*tov36` | `0.60*pts + 0.70*reb + 1.05*ast + 1.40*stl + 1.15*blk - 1.20*tov - 0.45*(FGA-FGM) - 0.35*(FTA-FTM) + 0.30*3PM`, scaled to per-36 via `*(minutes/36)`, minus a `-2.0` replacement-level anchor |
| Real plus-minus | Yes — 50/50 blend of the box-score component with real, Empirical-Bayes-shrunk (`total_min/(total_min+500)`) `plus_minus` per 36 | No — box-score formula only, no plus-minus input |
| Centering | Both components centered at minutes-weighted league average (0.00) before blending | Not centered — `-2.0` is a fixed anchor, not a computed league mean |
| Output | `bpm` clamped to `[-5.0, 12.0]`, one value per player | `raw_bpm_rate`, one value per player-game, immediately aggregated by `get_player_features()` into **team-game** features (`team_weighted_bpm`, `team_top5_bpm`, `team_minutes_concentration`) |

These are not a duplicated formula with a typo — they are two deliberately different metrics
(season player rating with real on-court plus-minus vs. a per-game box proxy aggregated to
team-level depth signals). Both inherit their box-score weights from the original NBA repo and
carry the same never-recalibrated-for-WNBA `TODO(recalibrate)` caveat (`player_metrics.R:118-125`,
mirrored in `roster_bottom_up_engine.R:244-246`).

## Where each is actually consumed (traced, not assumed)

- `get_player_bpm_ratings()` → `player_ratings` → `compute_team_live_rating()` → the `rating_diff`
  term already baked into `expected_margin`'s existing `0.4/0.4/0.2` blend
  (`roster_bottom_up_engine.R:586`). Not touched by this audit.
- `calculate_bpm_components()` → `get_player_features()` → `cache/features_cache.rds`
  (`team_weighted_bpm`/`team_top5_bpm`/`team_minutes_concentration`) → `get_team_depth_signal()` →
  `adjust_margin_for_depth()` → the separate, additive `depth_signal` term
  (`roster_bottom_up_engine.R:399`, `:643`), clamped `±6` via `DEPTH_ADJ_CLAMP`.

**Finding: no single call site mixes raw values from both functions.** They feed two structurally
separate, independently-scaled terms that are summed together in `expected_margin`, not
concatenated or compared directly — so there is no live bug from the two disagreeing on a given
player's or team's BPM value. The collinearity check already run for
`TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE` controlled for
`trailing_avg_margin` (a team's own actual recent scoring margin) — a stricter, more conservative
control than `rating_diff` would have been, since real margin already reflects the net effect of
everything including whatever `get_player_bpm_ratings()`-driven quality edge a team actually had.
VIFs of 2.16/3.12/4.80 were already disclosed as "close but not disqualifying" in
`docs/team_depth_signal_regression_findings.md`; this audit does not find a stronger collinearity
concern than what's already documented there.

## Recommendation: do not merge the two formulas

`TOP5_BPM_MARGIN_SLOPE` (+1.1563) and `MINUTES_CONCENTRATION_MARGIN_SLOPE` (-120.82) were
empirically fit specifically against `calculate_bpm_components()`'s exact weights and per-game
granularity (see `tools/research_team_depth_regression.R`). Changing that formula — including to
"reconcile" it with `get_player_bpm_ratings()`'s weights, or to fold in real plus-minus the way the
other function does — would silently invalidate both wired-in coefficients without any code error,
because `team_top5_bpm`/`team_minutes_concentration`'s underlying values would shift while the
regression-derived slopes stay hardcoded at their old values. The same applies in reverse: do not
change `get_player_bpm_ratings()`'s weights without checking whether `compute_team_live_rating()`'s
existing `0.4/0.4/0.2` blend is still sensibly scaled afterward.

**If a genuine WNBA recalibration of the underlying box-score weights is ever done** (per both
functions' shared `TODO(recalibrate)`), it must be followed by re-running
`tools/research_team_depth_regression.R` and re-deriving `TOP5_BPM_MARGIN_SLOPE`/
`MINUTES_CONCENTRATION_MARGIN_SLOPE` before the recalibrated weights ship — not treated as a
drop-in replacement.

## Action taken

Added a short cross-reference comment at each function's definition
(`roster_bottom_up_engine.R:212`, `player_metrics.R:94`) pointing to this doc and to each other, so
a future edit to either doesn't unknowingly break the other's empirical calibration. No formula,
weight, or consumer was changed — this audit closes `docs/HANDOFF.md`'s open item #1 as
"deliberately decoupled, safe as-is," not as a defect requiring a code fix.
