# BPM Weight Recalibration: `calculate_bpm_components()` Against Real WNBA Data

**Date:** 2026-09-19
**Author:** research task, addressing `player_metrics.R::calculate_bpm_components()`'s
long-standing `TODO(recalibrate)` ("the -2.0 replacement-level anchor (and the per-stat weights
below) were hand-tuned against NBA per-36 distributions... do not silently change this number
without real WNBA data behind it").
**Status:** PARTIAL — one weight (`steals`) recalibrated and wired in; the other eight weights
were NOT significant and were left unchanged; the replacement-level anchor recalibration attempt
produced an implausible result and was NOT wired in (deferred).

## Research question

`calculate_bpm_components()`'s 9 per-stat weights (`points=0.60, rebounds=0.70, assists=1.05,
steals=1.40, blocks=1.15, turnovers=-1.20, missed_fg=-0.45, missed_ft=-0.35, made_3pm=0.30`) and
its `-2.0` replacement-level anchor were ported unchanged from the NBA original repo. Does real
WNBA data support different values for any of them?

## The circularity trap, and how it was avoided

A team-game's own box stats mechanically determine that same game's own margin — `team_score`
(the box's "points" column) literally equals `margin + opponent_team_score`, so regressing
same-game margin on same-game box categories would make the `points` weight trivially close to
1.0 (a mechanical identity, not a real finding) and everything else noise. This regression was
never run. Instead, following `tools/research_team_depth_regression.R`'s exact established
pattern, a per-team chronologically-ordered panel was built and **trailing** (strictly
prior-games-only) rolling averages of each of the 9 raw box categories were regressed against
the team's current-row margin, within-team fixed effects, controlling for the team's own
trailing-average margin (recent-form baseline).

## Why team-level (not player-level) regression is valid for these weights

A per-stat weight (e.g. "1 rebound is worth 0.70 margin-points") is a linear coefficient that is
identical whether estimated from team-total stats or from summing player-level contributions,
since `team_total_stat = sum_players(player_stat)` and an additive linear model's coefficient on
that sum is the same coefficient that would apply per-player. The existing formula's per-36-minute
scaling and `-2.0` replacement-level anchor are separate playing-time-normalization mechanics
applied AFTER the weight is chosen — untouched by recalibrating the weight values themselves.

## Data and panel

`data/box_scores_cache.rds` (`CACHE_TEAM_BOX`), already exhibition-filtered at ingest
(`daily_ingest.R::filter_real_franchises()`) — verified again here (0 non-franchise rows after
`normalize_team_abbreviation()`). 3,916 team-game rows, 15 teams, seasons 2019–2026. Categories
used, matching `calculate_bpm_components()`'s inputs exactly: `points` (`team_score`),
`rebounds` (`total_rebounds`), `assists`, `steals`, `blocks`, `turnovers` (`total_turnovers` —
the repo's documented L-3 convention, not the raw `turnovers` column), `missed_fg`
(`field_goals_attempted - field_goals_made`), `missed_ft` (`free_throws_attempted -
free_throws_made`), `made_3pm` (`three_point_field_goals_made`).

Trailing averages: `ROLLING_WINDOW_SIZE = 12` (config.R), `MIN_TRAILING_GAMES = 5` (same
precedent as the shot-mix and team-depth regressions). Qualifying panel: 3,841 team-games, all
15 teams.

## Regression results (within-team FE, demeaned; explicit `factor(team_id)` sanity check
reproduces identical coefficients)

```
margin ~ trailing_avg_margin + trailing_avg_points + trailing_avg_rebounds +
         trailing_avg_assists + trailing_avg_steals + trailing_avg_blocks +
         trailing_avg_turnovers + trailing_avg_missed_fg + trailing_avg_missed_ft +
         trailing_avg_made_3pm

term                    old weight   new estimate   p-value    decision
trailing_avg_margin     (control)    +0.329         0.00024    n/a (recent-form control)
points                  +0.60        +0.012         0.877      NOT significant -> KEEP OLD
rebounds                +0.70        +0.273         0.159      NOT significant -> KEEP OLD
assists                 +1.05        +0.227         0.196      NOT significant -> KEEP OLD
steals                  +1.40        +0.875         0.00406    SIGNIFICANT -> USE NEW
blocks                  +1.15        +0.430         0.145      NOT significant -> KEEP OLD
turnovers               -1.20        -0.042         0.851      NOT significant -> KEEP OLD
missed_fg               -0.45        -0.224         0.260      NOT significant -> KEEP OLD
missed_ft               -0.35        -0.341         0.230      NOT significant -> KEEP OLD
made_3pm                +0.30        +0.215         0.306      NOT significant -> KEEP OLD

n = 3,841 team-games, 15 teams. R^2 = 0.051 (low — expected: single-game margin is noisy and
this model deliberately excludes same-game information to avoid circularity).
```

Collinearity (VIF, auxiliary-regression method, no `car` dependency): all 9 category VIFs are
below 3.5 (max: `t_points_dm` = 3.18), well under the 5.0 rule-of-thumb ceiling — collinearity is
not a concern for this result; the low significance is a genuine power/signal limitation, not a
multicollinearity artifact.

## Decision: only `steals` recalibrated

Per this repo's established significance-gated discipline (`SHOT_MIX_PTS_SLOPE`,
`TOP5_BPM_MARGIN_SLOPE`, etc. — never move a number without it independently clearing p < 0.05),
**8 of 9 weights do not clear the bar and were left at their original NBA-ported values.** This
is an honest, mostly-negative result: a team-level, trailing-average, single-game-margin
regression has limited power to isolate 9 correlated box-score categories' individual marginal
values — real BPM-family methodologies (including the NBA original this was ported from) fit
against a season-aggregated, multi-year, much larger and less noisy target (regularized
adjusted plus-minus), not single-game score margin. This finding does not mean the other 8
weights are "correct" — only that this specific test did not produce strong enough evidence to
justify moving them away from the values `calculate_bpm_components()` has always used, and
fabricating an untested-but-plausible-looking replacement would be strictly worse than an honest
"insufficient evidence" per this repo's own stated convention (CLAUDE.md, `AGENTS.md`).

**`steals` weight changed: 1.40 → 0.875** (p = 0.004, correctly signed positive). Applied in
`player_metrics.R::calculate_bpm_components()`.

## Replacement-level anchor: attempted, found implausible, NOT wired in

The TODO also asked to re-derive the `-2.0` replacement-level anchor. Attempted method: compute
`calculate_bpm_components()`'s weighted-sum-per-36 (using the new weights) across all real
player-games with `minutes >= 10` (a rotation-minutes floor), then set the anchor to the 10th
percentile of that distribution — a common BPM-family convention ("replacement level = worse
than ~90% of real rotation minutes").

**Result: 10th percentile = +3.51** (n = 30,917 player-games; distribution mean 12.73, median
12.48). This is implausible against the BPM-family convention, where replacement level should be
deeply *negative* (the current `-2.0`, or the NBA original's similar-magnitude constant) — a
"replacement player" is meant to represent a freely-available, below-average player, not the
10th-worst game among an already-filtered set of players who cleared a 10-minutes-played bar.
**Root cause (diagnosed, not fixed here):** filtering to `minutes >= 10` selects players who are
already established rotation contributors; a genuine "replacement level" proxy needs to reach
further down the roster (end-of-bench/deep-reserve minutes, or a lower minutes floor, or an
explicit "players who only appeared in a handful of games that season" definition) — this
script's `minutes >= 10` floor was too permissive for what "replacement level" is supposed to
represent. **Deferred, not wired in** — `calculate_bpm_components()`'s anchor remains the
original `-2.0`. A future attempt should re-derive the replacement-level population definition
first (this is a real, separate, well-scoped follow-up — see `docs/future-work.md`).

## Downstream re-derivation (required, and done)

Per `docs/bpm_implementation_audit_findings.md`'s explicit warning ("do not change these weights
without re-running `tools/research_team_depth_regression.R` and re-deriving those slopes"):

1. `cache/features_cache.rds` regenerated via `compute_and_cache_player_features()` (mtime
   verified fresh: 05:30 → 07:59 same day).
2. `tools/research_team_depth_regression.R` re-run against the updated cache.
   `TOP5_BPM_MARGIN_SLOPE`/`MINUTES_CONCENTRATION_MARGIN_SLOPE` both stayed significant with the
   same sign, magnitudes moved modestly (+1.1563→+1.0509, -120.82→-102.17) — updated in
   `roster_bottom_up_engine.R`. Full before/after table in
   `docs/team_depth_signal_regression_findings.md`'s 2026-09-19 addendum.
3. `DEPTH_ADJ_CLAMP` (±6.0) re-checked against the new real depth-adjustment spread (±3.80,
   previously ±4.14) — still comfortably non-binding, left unchanged.

`tools/research_shot_mix_regression.R`'s `SHOT_MIX_PTS_SLOPE` does NOT depend on
`calculate_bpm_components()` (it uses PBP shot-mix data, not BPM), so it was not affected and was
not re-run.

## Reproducing this derivation

`Rscript.exe tools/research_bpm_recalibration.R` reproduces the full derivation end-to-end (load
+ verify, panel build, trailing averages, regression + FE sanity check, VIF, weight decision,
replacement-level anchor attempt). Re-run periodically as more seasons accumulate in
`data/box_scores_cache.rds` — given the low R² and single-weight result here, more data (more
seasons, or a season-aggregated rather than single-game-margin target) is the most likely path
to a stronger future result for the remaining 8 weights and for a genuine replacement-level
anchor.
