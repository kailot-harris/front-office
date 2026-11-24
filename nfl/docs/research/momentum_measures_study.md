# NFL momentum measures study

Research only (issue #220). This study changes no production code and is not wired into the pipeline.

- Script: `tools/momentum_measures_study.R` (fixed seeds, not wired into the pipeline)
- Machine-readable results: `docs/research/momentum_measures_study_results.json` (every method tried, with a verdict and a reason)
- Run: 2026-11-24, 200 shuffled-outcome runs, 2,000 bootstrap resamples, one clean R session (`Rscript --vanilla`), 32.7 minutes in total (permutations 28.9 minutes); the 2026 forward test was scored in this run only

Every number below is copied from the run's own output tables. Feature ids are written `series__measure` (for example `tom__streak` is the streak measure applied to turnover margin).

## 1. Question

Does team momentum, measured by 11 momentum measures applied to 11 team stat series, predict how an NFL team plays over its next game and its next 3 games better than team strength alone? Is there a small, stable combination (3 stat series x 3 measures) that does so reliably on seasons it never saw?

"Team strength" is a baseline of the team's Elo after its latest game (its pregame Elo for the next game) plus its season-to-date point margin per game. Every candidate is scored only on what it adds to that baseline. This is the same baseline and protocol as the NBA study (NBA_analytics#245), adapted to a 17-game season.

## 2. Data and seasons

nflreadr play-by-play (`load_pbp()`) and schedules (`load_schedules()`), regular season only (`season_type == "REG"`). 2011 is loaded only to seed the cross-season sensitivity windows. Elo is the production walk-forward (`tools/elo_model.R`, `run_elo_walkforward()`), run over every completed game from 2002 (regular season and playoffs, as production does), using pre-game ratings only.

| Season | Role | Games | Team-games | First | Last | Last week | Ties | QB changes | Byes |
|---|---|---|---|---|---|---|---|---|---|
| 2011 | seed for the cross-season windows only | 256 | 512 | 2011-09-08 | 2012-01-01 | 17 | 0 | 42 | 35 |
| 2012 | LOSO | 256 | 512 | 2012-09-05 | 2012-12-30 | 17 | 1 | 32 | 38 |
| 2013 | LOSO | 256 | 512 | 2013-09-05 | 2013-12-29 | 17 | 1 | 47 | 37 |
| 2014 | LOSO | 256 | 512 | 2014-09-04 | 2014-12-28 | 17 | 1 | 42 | 37 |
| 2015 | LOSO | 256 | 512 | 2015-09-10 | 2016-01-03 | 17 | 0 | 50 | 37 |
| 2016 | LOSO | 256 | 512 | 2016-09-08 | 2017-01-01 | 17 | 2 | 46 | 36 |
| 2017 | LOSO | 256 | 512 | 2017-09-07 | 2017-12-31 | 17 | 0 | 43 | 35 |
| 2018 | LOSO | 256 | 512 | 2018-09-06 | 2018-12-30 | 17 | 2 | 35 | 35 |
| 2019 | LOSO | 256 | 512 | 2019-09-05 | 2019-12-29 | 17 | 1 | 44 | 35 |
| 2020 | LOSO (flagged; dropped in sensitivity run) | 256 | 512 | 2020-09-10 | 2021-01-03 | 17 | 1 | 56 | 36 |
| 2021 | LOSO | 272 | 544 | 2021-09-09 | 2022-01-09 | 18 | 1 | 68 | 34 |
| 2022 | LOSO | 271 | 542 | 2022-09-08 | 2023-01-08 | 18 | 2 | 63 | 41 |
| 2023 | LOSO | 272 | 544 | 2023-09-07 | 2024-01-07 | 18 | 0 | 58 | 36 |
| 2024 | LOSO | 272 | 544 | 2024-09-05 | 2025-01-05 | 18 | 0 | 59 | 37 |
| 2025 | LOSO | 272 | 544 | 2025-09-04 | 2026-01-04 | 18 | 1 | 64 | 35 |
| 2026 | forward test (in progress; scored once) | 163 | 326 | 2026-09-09 | 2026-11-23 | 11 | 1 | 31 | 27 |

Historical team-games: 7326. Team-games without play-by-play: 0.

Notes on the data:

- Every regular-season team-game in 2011-2026 has play-by-play (0 team-games without it).
- Ties are kept in the margin targets (margin 0) and left out of the next-game win target (counted in the table).
- 2020 (no crowds) stays in and is flagged; a sensitivity run drops it.
- 2022 has 271 games: the Buffalo-Cincinnati game was not completed.
- Franchises that moved (OAK to LV, SD to LAC, STL to LA) are keyed by today's abbreviation, so a team-season is never split and its Elo carries over. The production Elo is keyed by the schedule's abbreviation of the time, so in production a relocated franchise restarts at 1500 in its first season under the new abbreviation. This is a note only; production code is not changed here.
- The post-game Elo ("Elo after game k") is the pre-game rating plus the same update `run_elo_walkforward()` applies. Within a season it matched the team's next pre-game rating exactly in every case (largest gap 0).

## 3. Stat series

All per team, per game. Series 2-11 are opponent-adjusted: the game value minus the opponent's season-to-date average of the matching stat, using only the opponent's earlier games that season. A team's first game therefore has no adjusted value (the opponent has no earlier games); those values are missing, not filled.

| Id | Series | Definition |
|---|---|---|
| elo | Elo rating | Production Elo after each game (`tools/elo_model.R`: K 28, home field 48 Elo points, margin-of-victory multiplier, 2/3 season carry-over). |
| margin | Point margin | Point margin minus the opponent's season-to-date average margin allowed. |
| off_epa | Offensive EPA/play | EPA per play over every play with an EPA (the `epa_metrics_engine.R` definition) minus the opponent's season-to-date average allowed. |
| def_epa | Defensive EPA/play | EPA per play allowed minus the opponent's season-to-date average produced; lower is better. |
| off_sr | Offensive success rate | Success rate minus the opponent's season-to-date average allowed. |
| def_sr | Defensive success rate | Success rate allowed minus the opponent's season-to-date average produced; lower is better. |
| pass_epa | Pass EPA/play | EPA per pass play (`pass == 1`: dropbacks, including sacks and scrambles) minus the opponent's season-to-date average allowed. |
| rush_epa | Rush EPA/play | EPA per designed run (`rush == 1`) minus the opponent's season-to-date average allowed. |
| pass_epa_def | Pass EPA/play allowed | Pass EPA per play allowed minus the opponent's season-to-date average produced. |
| rush_epa_def | Rush EPA/play allowed | Rush EPA per play allowed minus the opponent's season-to-date average produced. |
| tom | Turnover margin | Takeaways minus giveaways (interceptions thrown plus fumbles lost, charged to the fumbling team) minus the opponent's season-to-date average turnover margin allowed. |

## 4. The 11 measures, each using only earlier games

Windows are scaled to a 17-game season (the NBA study used short 5 / long 10 and EWMA spans 5 and 15):

| Setting | Value |
|---|---|
| Warm-up | no measure until a team has 3 values of the series that season (Elo: from game 3; adjusted series: from game 4) |
| Short window | 3 games (ROC, Z-score numerator, acceleration lag, growth halves) |
| Long window | 6 games (velocity fit, RSI) |
| EWMA spans | 2 and 6 (MACD); 2 for the EWMA of changes |
| ROC baseline | at least 3 earlier values before the last 3 (adjusted series) |
| Impulse decay | 0.75 per game (half-life about 2.4 games; the NBA study used 0.85, about 4.3 of 82 games) |
| Cross-team z-score | needs at least 10 teams with a value on that date |
| Bye | previous game more than 10 days earlier within the same season |

For Elo the per-game "change" is the Elo change (post-game minus pre-game). For the other series the per-game "surprise" is the game value minus the team's own mean of its earlier values. Every value after a team's game k uses only games 1..k. Measures do not carry across seasons (a sensitivity run lets them; section 8). Values are then z-scored across teams on each date, using each team's latest state on or before that date. Missing values stay missing and are counted; nothing is imputed. 11 series x 11 measures = 121 features.

| Measure | Definition used here | Why it is written this way |
|---|---|---|
| ROC-3 | Elo: (Elo after game k - Elo before game k-2) / 3. Other series: mean of the last 3 values minus the mean of the team's values before them (at least 3 earlier values). | Uses only past games already. |
| MACD | Exponentially weighted mean of the series with span 2 minus the same with span 6, updated game by game from the season's first value. | Uses only past games already. |
| Velocity | Slope of a least-squares line through the trailing 6 values. | A whole-season smooth would use later games; a trailing fit does not. |
| Acceleration | Velocity after game k minus velocity 3 values earlier. | Same reason as velocity. |
| EWMA of changes | Exponentially weighted mean (span 2) of the per-game change or surprise. | Uses only past games already. |
| Z-score | ROC-3 divided by the standard deviation of the team's changes or surprises in games 1..k (expanding window). | A full-season standard deviation would use later games. |
| RSI | Over the last 6 changes or surprises: 100 x average gain / (average gain + average loss). | Uses only past games already. |
| Growth difference | Sum of the last 3 changes or surprises minus the sum of the 3 before them. | A difference, because the ratio is unstable near zero. The NBA study used its long window for both halves; 6 + 6 games would leave almost no rows in a 17-game season, so the short window is used. |
| Kalman slope | Filtered slope of a local linear trend model (level + slope + noise) run forward through games 1..k; its three noise variances are fitted by maximum likelihood on the training seasons only. | A smoothed (two-sided) slope would use later games; the filtered slope does not. |
| Streak | Signed length of the current run: wins/losses for Elo, positive/negative surprises for the other series. | Extended past win/loss to the stat series. |
| Impulse | m[k] = 0.75 x m[k-1] + change or surprise in game k, from the season's first value. | Uses only past games already. |

Missing counts on the 7326 historical team-game rows (missing = before 3 values of the series, warm-up of the measure, or no z-score on that date). The acceleration column is the sparsest: it needs 9 values of a series (6 for the velocity fit plus a lag of 3).

| Measure | Missing (summed over 11 series) |
|---|---|
| roc3 | 28064 |
| macd | 14634 |
| velocity | 29405 |
| acceleration | 44704 |
| ewma_change | 14634 |
| zscore | 28064 |
| rsi | 33795 |
| growth | 33795 |
| kalman | 14634 |
| streak | 14634 |
| impulse | 14634 |

| Series | Missing raw values | Missing features (summed over 11 measures) |
|---|---|---|
| elo | 0 | 16897 |
| margin | 448 | 25410 |
| off_epa | 448 | 25410 |
| def_epa | 448 | 25410 |
| off_sr | 448 | 25410 |
| def_sr | 448 | 25410 |
| pass_epa | 448 | 25410 |
| rush_epa | 448 | 25410 |
| pass_epa_def | 448 | 25410 |
| rush_epa_def | 448 | 25410 |
| tom | 448 | 25410 |

Per feature: min 924, median 2714, max 4107 of 7326 rows.

## 5. Targets

All targets use only games after game k.

| Id | Definition | Primary |
|---|---|---|
| margin3_beyond_elo | Mean over the team's next 3 games of (point margin minus the margin Elo expected). The Elo expectation is the opponent adjustment: (team Elo after game k - opponent's pregame Elo + 48 x home sign) / 25 points, with the `tools/elo_model.R` constants. | yes |
| next_margin_beyond_elo | The same for the next game only. | no |
| next_game_win | Next game won by the home team (one row per game; ties left out). Logistic model on the pregame Elo difference with home field plus the season-to-date margin-per-game difference; scored by log loss and ROC-AUC. | no |

The issue words the primary target as an "opponent-adjusted point margin ... minus what Elo expected". The study reads the Elo expectation as the opponent adjustment (it already includes the opponent's rating and home field), so the margin is not adjusted a second time.

## 6. Protocol

- **Leave-one-season-out (LOSO)** over 2012-2025 (14 folds), with pooled out-of-fold predictions. The score is the out-of-fold R^2 gain over the baseline; for the next-game win target it is the log-loss gain divided by the null log loss.
- **Team-season block bootstrap**: paired, 2,000 resamples of whole team-seasons, because next-3 targets overlap from one game to the next.
- **False discovery rate**: Benjamini-Hochberg across the 121 features per target, at q < 0.05. A single feature is `kept` only if its 95% interval is above zero and it survives the correction; `discarded` if its out-of-fold gain is zero or negative; otherwise `inconclusive`.
- **Redundancy families**: correlation clusters across measures and across series (mean |r| >= 0.5).
- **Nested 3x3 combination search**: in each outer fold, the top 6 series and top 6 measures are ranked on the training seasons only, giving C(6,3)^2 = 400 combinations of 3 series x 3 measures; each is fitted as a ridge regression (alpha 0.01, 0.1 or 1) and the best is chosen by inner LOSO, then scored on the held-out season. It uses the rows where all 121 features exist, so every candidate is scored on the same rows. Comparisons: an elastic net over all 121 features and greedy forward selection. (The NBA study also compared its Momentum Board's score; the NFL has no momentum board.)
- **Permutation baseline**: the whole nested search rerun 200 times with the target shuffled among teams within each date. This shows how good pure chance looks.
- **Stability**: how often the same series and measures are chosen across folds, the sign by season, and how many combinations tie with the final choice within its interval.
- **Flags**: starting-QB change, coming off a bye, and week 18, each reported as its own rows (section 9). No row is dropped because of a flag.
- **Sensitivity runs**: without 2020; and with windows that span the previous season's last 6 games (flagged).
- **Reliable** means all four hold: the held-out gain's 95% interval is above zero; it beats the 95th percentile of the permutation runs; the same series and measures (or the same families) are picked in at least half the outer folds; and the gain is positive in most seasons.
- **Forward test**: 2026 to date, scored once after every choice was fixed (section 10).

## 7. Single-feature results

Each of the 121 features was added on its own to the baseline (Elo after the latest game plus season-to-date margin per game) and scored out of fold, season by season. **No feature is kept on any target.** None has a 95% interval above zero, and every q value is 1.0000 after the false discovery correction.

| Target | kept | inconclusive | discarded |
|---|---|---|---|
| margin3_beyond_elo | 0 | 19 | 102 |
| next_margin_beyond_elo | 0 | 27 | 94 |
| next_game_win | 0 | 33 | 88 |

"Gain" is the pooled out-of-fold R^2 gain over the baseline (for next_game_win, the log-loss gain as a share of the null log loss). "IC / AUC change" is the rank correlation of the feature with the target beyond Elo, or for next_game_win the change in ROC-AUC. "n" is the number of rows where the feature exists; "Missing" is the count of historical rows where it does not.

### Primary target: point margin over the next 3 games beyond Elo

| Feature | Gain | 95% CI | IC / AUC change | q | n | Missing | Verdict |
|---|---|---|---|---|---|---|---|
| tom__acceleration | +0.00319 | [-0.00392, +0.01030] | +0.07243 | 1.0000 | 1875 | 4107 | inconclusive |
| elo__acceleration | +0.00196 | [-0.00407, +0.00781] | +0.04767 | 1.0000 | 2348 | 3634 | inconclusive |
| tom__growth | +0.00139 | [-0.00318, +0.00567] | +0.04301 | 1.0000 | 2829 | 3153 | inconclusive |
| margin__velocity | +0.00124 | [-0.00261, +0.00494] | +0.02786 | 1.0000 | 3268 | 2714 | inconclusive |
| off_epa__velocity | +0.00081 | [-0.00311, +0.00439] | +0.02919 | 1.0000 | 3268 | 2714 | inconclusive |
| pass_epa__velocity | +0.00077 | [-0.00274, +0.00436] | +0.03040 | 1.0000 | 3268 | 2714 | inconclusive |
| margin__streak | +0.00075 | [-0.00188, +0.00346] | +0.02427 | 1.0000 | 4611 | 1371 | inconclusive |
| pass_epa__zscore | +0.00056 | [-0.00315, +0.00425] | +0.02571 | 1.0000 | 3268 | 2714 | inconclusive |
| off_sr__rsi | +0.00049 | [-0.00433, +0.00509] | +0.03838 | 1.0000 | 2829 | 3153 | inconclusive |
| tom__velocity | +0.00033 | [-0.00276, +0.00322] | +0.02432 | 1.0000 | 3268 | 2714 | inconclusive |

### Next game: point margin beyond Elo

| Feature | Gain | 95% CI | IC / AUC change | q | n | Missing | Verdict |
|---|---|---|---|---|---|---|---|
| off_epa__rsi | +0.00148 | [-0.00136, +0.00438] | +0.03772 | 1.0000 | 3725 | 3153 | inconclusive |
| pass_epa__rsi | +0.00115 | [-0.00163, +0.00401] | +0.03372 | 1.0000 | 3725 | 3153 | inconclusive |
| rush_epa_def__acceleration | +0.00100 | [-0.00218, +0.00381] | +0.02984 | 1.0000 | 2771 | 4107 | inconclusive |
| off_epa__zscore | +0.00072 | [-0.00129, +0.00283] | +0.02294 | 1.0000 | 4164 | 2714 | inconclusive |
| elo__acceleration | +0.00071 | [-0.00187, +0.00318] | +0.02814 | 1.0000 | 3244 | 3634 | inconclusive |
| def_epa__acceleration | +0.00065 | [-0.00181, +0.00289] | +0.02478 | 1.0000 | 2771 | 4107 | inconclusive |
| off_epa__roc3 | +0.00052 | [-0.00138, +0.00242] | +0.02180 | 1.0000 | 4164 | 2714 | inconclusive |
| pass_epa__zscore | +0.00051 | [-0.00136, +0.00254] | +0.02154 | 1.0000 | 4164 | 2714 | inconclusive |
| margin__rsi | +0.00044 | [-0.00152, +0.00250] | +0.02069 | 1.0000 | 3725 | 3153 | inconclusive |
| rush_epa_def__growth | +0.00044 | [-0.00148, +0.00216] | +0.02119 | 1.0000 | 3725 | 3153 | inconclusive |

### Next game: win (home team)

| Feature | Gain | 95% CI | IC / AUC change | q | n | Missing | Verdict |
|---|---|---|---|---|---|---|---|
| off_epa__rsi | +0.00241 | [-0.00194, +0.00665] | +0.00188 | 1.0000 | 1816 | 1612 | inconclusive |
| off_sr__ewma_change | +0.00211 | [-0.00116, +0.00533] | +0.00166 | 1.0000 | 2750 | 678 | inconclusive |
| off_sr__rsi | +0.00205 | [-0.00275, +0.00685] | +0.00182 | 1.0000 | 1816 | 1612 | inconclusive |
| off_sr__impulse | +0.00203 | [-0.00124, +0.00526] | +0.00178 | 1.0000 | 2750 | 678 | inconclusive |
| pass_epa__rsi | +0.00201 | [-0.00237, +0.00629] | +0.00199 | 1.0000 | 1816 | 1612 | inconclusive |
| off_sr__kalman | +0.00200 | [-0.00118, +0.00522] | +0.00174 | 1.0000 | 2750 | 678 | inconclusive |
| off_sr__roc3 | +0.00168 | [-0.00186, +0.00507] | +0.00070 | 1.0000 | 2045 | 1383 | inconclusive |
| off_sr__zscore | +0.00163 | [-0.00189, +0.00491] | +0.00058 | 1.0000 | 2045 | 1383 | inconclusive |
| rush_epa_def__acceleration | +0.00153 | [-0.00262, +0.00558] | +0.00167 | 1.0000 | 1395 | 2033 | inconclusive |
| off_sr__macd | +0.00147 | [-0.00146, +0.00428] | +0.00113 | 1.0000 | 2750 | 678 | inconclusive |

The largest gains are about 0.3% of the variance of the target, and each interval is wide on both sides of zero. The acceleration and growth features at the top of the primary list exist only from about game 10 of a season, so they are scored on fewer rows (1,875 to 2,829 of 7,326).

## 8. Families, combination search and checks

### Redundancy families

Measure families (mean |r| across series >= 0.5):

- roc3, macd, ewma_change, zscore, rsi, kalman, streak, impulse
- velocity, acceleration, growth

Series families (mean |r| across measures >= 0.5):

- elo
- margin, off_epa, off_sr, pass_epa
- def_epa, def_sr, pass_epa_def
- rush_epa
- rush_epa_def
- tom

Feature clusters with every pair |r| >= 0.7: 48 clusters, 36 with more than one feature.

Most measures describe one thing: the recent level of a series against its own past. Velocity, acceleration and growth form a second family. The offense series (margin, offense EPA, offense success rate, pass EPA) move together, as do the three defense series.

### Nested 3x3 combination search (primary target)

The search is scored on the 1,875 rows where all 121 features exist, so every combination is judged on the same rows.

| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |
|---|---|---|---|---|---|---|
| 2012 | tom, margin, elo | streak, growth, acceleration | 1 | +0.00246 | +0.00745 | 122 |
| 2013 | tom, def_sr, off_epa | streak, velocity, growth | 1 | +0.00274 | +0.01184 | 120 |
| 2014 | tom, off_sr, off_epa | streak, acceleration, growth | 1 | +0.00585 | -0.01387 | 120 |
| 2015 | tom, elo, margin | streak, growth, acceleration | 1 | +0.00410 | -0.00792 | 122 |
| 2016 | tom, elo, off_epa | streak, growth, acceleration | 1 | +0.00375 | -0.00175 | 120 |
| 2017 | tom, off_epa, def_sr | streak, growth, acceleration | 1 | +0.00700 | -0.03845 | 120 |
| 2018 | tom, margin, def_sr | streak, growth, acceleration | 1 | +0.00553 | -0.02521 | 120 |
| 2019 | tom, off_sr, off_epa | streak, growth, acceleration | 1 | +0.00360 | +0.00334 | 120 |
| 2020 | tom, off_epa, off_sr | streak, growth, velocity | 1 | +0.00478 | -0.00437 | 120 |
| 2021 | tom, off_sr, off_epa | streak, kalman, velocity | 1 | +0.00382 | -0.01246 | 159 |
| 2022 | tom, margin, def_sr | streak, acceleration, macd | 1 | +0.00261 | +0.00381 | 156 |
| 2023 | tom, off_epa, pass_epa | streak, velocity, growth | 1 | +0.00300 | +0.00450 | 159 |
| 2024 | tom, elo, margin | streak, growth, acceleration | 1 | +0.00286 | +0.00516 | 158 |
| 2025 | tom, off_epa, pass_epa_def | streak, velocity, impulse | 1 | +0.00564 | -0.02716 | 159 |

The inner gain (on the training seasons) is positive in all 14 folds, but the held-out gain is positive in only 6. This is the usual sign of a search that fits noise in the training seasons.

| Model | Rows | Pooled OOF R^2 gain | 95% CI |
|---|---|---|---|
| Nested 3x3 combination | 1875 | -0.00613 | [-0.01357, +0.00108] |
| elastic_net | 1875 | -0.00112 | [-0.00247, +0.00024] |
| greedy_forward | 1875 | -0.03972 | [-0.05703, -0.02313] |
| Sensitivity without 2020: nested 3x3 combination | 1755 | -0.00831 | [-0.01724, +0.00048] |
| Sensitivity without 2020: elastic_net | 1755 | -0.00342 | [-0.00617, -0.00073] |
| Sensitivity without 2020: greedy_forward | 1755 | -0.02716 | [-0.04552, -0.00932] |
| Sensitivity cross-season windows: nested 3x3 combination | 4611 | -0.00089 | [-0.00611, +0.00487] |
| Sensitivity cross-season windows: elastic_net | 4611 | -0.00468 | [-0.00784, -0.00145] |
| Sensitivity cross-season windows: greedy_forward | 4611 | -0.01237 | [-0.02207, -0.00242] |

Permutation baseline: 200 runs, 95th percentile -0.00006, mean -0.00593, max +0.00962; share of runs at or above the real gain 0.5400; runtime 28.9 min.
Stability: 11 distinct combinations in 14 folds; series counts tom 14, off_epa 9, margin 5, def_sr 4, elo 4, off_sr 4, pass_epa 1, pass_epa_def 1; measure counts streak 14, growth 11, acceleration 9, velocity 5, impulse 1, kalman 1, macd 1; seasons with positive held-out gain 6 of 14.
Final choice on all 14 seasons: tom, off_epa, off_sr x streak, growth, acceleration (ridge alpha 1); 350 of 399 other combinations tie with it within the bootstrap interval.
Reliability checks: ci_above_zero = FALSE; beats_permutation_p95 = FALSE; stable_selection = FALSE; sign_holds_most_seasons = FALSE. Verdict: none found: fails ci_above_zero, beats_permutation_p95, stable_selection, sign_holds_most_seasons.

### Permutation baseline

The whole nested search was rerun 200 times with the target shuffled among teams on the same date. The 95th percentile of those runs is -0.00006, their mean -0.00593 and their maximum +0.00962. The real search scored -0.00613, and 54% of the shuffled runs did at least as well. In plain terms, the real search did no better than chance.

### Stability

- 11 different combinations were chosen in 14 folds.
- Series chosen: tom 14, off_epa 9, margin 5, def_sr 4, elo 4, off_sr 4, pass_epa 1, pass_epa_def 1.
- Measures chosen: streak 14, growth 11, acceleration 9, velocity 5, impulse 1, kalman 1, macd 1.
- Final choice on all 14 seasons: tom, off_epa, off_sr x streak, growth, acceleration (ridge alpha 1). 350 of the 399 other combinations tie with it within the bootstrap interval, so the choice is not clearly better than most alternatives.

### Reliability checks

| Check | Result |
|---|---|
| Held-out gain's 95% interval above zero | no (-0.00613 [-0.01357, +0.00108]) |
| Beats the 95th percentile of the permutation runs | no (-0.00613 vs -0.00006) |
| Same series and measures picked in at least half the folds | no (11 distinct combinations in 14 folds) |
| Gain positive in most seasons | no (6 of 14) |

**Verdict: none found.** The search fails all four checks.

### Sensitivity runs

**Without 2020** (13 seasons). The combination scored -0.00831 [-0.01724, +0.00048] on 1,755 rows and was positive in 4 of 13 seasons. The elastic net scored -0.00342 [-0.00617, -0.00073]. No single feature is kept (19 inconclusive, 102 discarded); the best is elo__acceleration at +0.00266 [-0.00445, +0.00946].

| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |
|---|---|---|---|---|---|---|
| 2012 | tom, elo, rush_epa | velocity, acceleration, zscore | 1 | +0.00249 | -0.00196 | 122 |
| 2013 | tom, def_sr, off_epa | streak, growth, velocity | 1 | +0.00397 | +0.01230 | 120 |
| 2014 | tom, off_sr, off_epa | streak, growth, velocity | 1 | +0.00736 | -0.01324 | 120 |
| 2015 | tom, margin, pass_epa_def | growth, velocity, streak | 1 | +0.00477 | -0.00906 | 122 |
| 2016 | tom, elo, off_epa | growth, velocity, acceleration | 1 | +0.00478 | -0.00445 | 120 |
| 2017 | margin, def_sr, pass_epa_def | streak, velocity, growth | 0.1 | +0.00945 | -0.09474 | 120 |
| 2018 | tom, margin, def_sr | streak, velocity, growth | 1 | +0.00696 | -0.02941 | 120 |
| 2019 | tom, margin, off_sr | streak, growth, acceleration | 1 | +0.00457 | -0.00063 | 120 |
| 2021 | tom, off_sr, off_epa | streak, velocity, growth | 1 | +0.00749 | -0.01273 | 159 |
| 2022 | tom, margin, def_sr | streak, growth, acceleration | 1 | +0.00303 | +0.01565 | 156 |
| 2023 | tom, off_epa, off_sr | velocity, streak, growth | 1 | +0.00378 | +0.00850 | 159 |
| 2024 | elo, tom, off_epa | growth, velocity, acceleration | 1 | +0.00369 | +0.00699 | 158 |
| 2025 | tom, def_sr, off_epa | streak, velocity, growth | 1 | +0.00703 | -0.01308 | 159 |

Stability: 9 distinct combinations in 13 folds; series counts tom 12, off_epa 7, def_sr 5, margin 5, off_sr 4, elo 3, pass_epa_def 2, rush_epa 1; measure counts growth 12, velocity 11, streak 10, acceleration 5, zscore 1; seasons with positive held-out gain 4 of 13.

**Windows that span the previous season's last 6 games** (flagged, because a team changes over the off-season). Far fewer values are missing (median 476 per feature, against 2,714 in the main run), so the search uses 4,611 rows. The combination scored -0.00089 [-0.00611, +0.00487] and was positive in 8 of 14 seasons. The elastic net scored -0.00468 [-0.00784, -0.00145]. No single feature is kept (20 inconclusive, 101 discarded); the best is off_sr__kalman at +0.00197 [-0.00217, +0.00631]. The selection is steadier here (off_sr, tom and kalman in every fold), but the held-out gain still does not clear zero.

| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |
|---|---|---|---|---|---|---|
| 2012 | off_sr, tom, off_epa | kalman, impulse, acceleration | 1 | +0.00444 | +0.00690 | 318 |
| 2013 | off_sr, tom, off_epa | kalman, rsi, impulse | 1 | +0.00444 | -0.00162 | 318 |
| 2014 | off_sr, tom, off_epa | kalman, impulse, rsi | 1 | +0.00437 | -0.00051 | 318 |
| 2015 | tom, off_sr, off_epa | kalman, rsi, velocity | 1 | +0.00470 | +0.00383 | 318 |
| 2016 | tom, off_sr, off_epa | kalman, impulse, velocity | 0.1 | +0.00569 | -0.01278 | 318 |
| 2017 | pass_epa_def, off_sr, tom | kalman, rsi, streak | 1 | +0.00668 | -0.02622 | 319 |
| 2018 | tom, off_epa, off_sr | kalman, impulse, acceleration | 1 | +0.00495 | +0.00352 | 318 |
| 2019 | off_sr, tom, off_epa | kalman, impulse, acceleration | 1 | +0.00373 | +0.01403 | 318 |
| 2020 | off_sr, off_epa, tom | kalman, impulse, velocity | 1 | +0.00380 | +0.01167 | 318 |
| 2021 | off_sr, pass_epa, tom | kalman, rsi, streak | 1 | +0.00450 | +0.00016 | 350 |
| 2022 | pass_epa, tom, off_sr | kalman, rsi, streak | 1 | +0.00469 | -0.00234 | 348 |
| 2023 | off_sr, off_epa, tom | kalman, impulse, rsi | 1 | +0.00375 | +0.00552 | 350 |
| 2024 | off_sr, tom, pass_epa_def | kalman, rsi, impulse | 1 | +0.00547 | -0.01808 | 350 |
| 2025 | off_epa, off_sr, tom | kalman, impulse, velocity | 0.1 | +0.00487 | +0.00012 | 350 |

Stability: 7 distinct combinations in 14 folds; series counts off_sr 14, tom 14, off_epa 10, pass_epa 2, pass_epa_def 2; measure counts kalman 14, impulse 10, rsi 8, velocity 4, acceleration 3, streak 3; seasons with positive held-out gain 8 of 14.

Neither sensitivity run changes the verdict.

## 9. Flags

Each flag is reported as its own rows. No row was dropped because of a flag.

- **qb_change_last**: the team's starting QB in its latest game differs from the game before.
- **bye**: one of the next 3 games (for next-game targets, the next game) comes more than 10 days after the team's previous game of the season.
- **week18**: one of the next 3 games (or the next game) is in week 18.
- **final_week**: supplementary flag for the last regular-season week in any season (week 17 before 2021).
- **qb_change_in_window**: descriptive only. A QB change in the latest game or in any of the next 3 games. It uses later games, so it is never added to a model.

"Added to baseline" is the out-of-fold gain from adding the flag to the baseline. For week18 and final_week the model also adds the flag times the team's Elo, because every team plays in that week and the plain flag averages to zero.

| Flag | Target | Rows | Flagged | Mean beyond Elo: flagged | not flagged | Difference [95% CI] | Added to baseline: gain [95% CI] | Verdict |
|---|---|---|---|---|---|---|---|---|
| qb_change_last | margin3_beyond_elo | 5534 | 514 | -1.62 | +0.17 | -1.79 [-2.54, -0.99] | +0.00497 [+0.00093, +0.00892] | kept |
| qb_change_last | next_margin_beyond_elo | 6430 | 615 | -1.79 | +0.20 | -1.99 [-3.13, -0.88] | +0.00241 [-0.00013, +0.00499] | inconclusive |
| qb_change_last | next_game_win | 3205 | 535 |  |  |  | +0.00317 [-0.00052, +0.00680] | inconclusive |
| bye | margin3_beyond_elo | 5982 | 1480 | +0.48 | -0.16 | +0.64 [-0.01, +1.31] | +0.00054 [-0.00172, +0.00285] | inconclusive |
| bye | next_margin_beyond_elo | 6878 | 509 | +0.59 | -0.05 | +0.64 [-0.42, +1.78] | -0.00007 [-0.00066, +0.00055] | discarded |
| bye | next_game_win | 3428 | 420 |  |  |  | -0.00041 [-0.00128, +0.00040] | discarded |
| week18 | margin3_beyond_elo | 5982 | 160 | +0.00 | +0.00 | -0.00 [-1.16, +1.26] | -0.00010 [-0.00031, +0.00011] | discarded |
| week18 | next_margin_beyond_elo | 6878 | 160 | +0.00 | -0.00 | +0.00 [-2.02, +2.18] | +0.00015 [-0.00122, +0.00160] | inconclusive |
| week18 | next_game_win | 3428 | 80 |  |  |  | +0.00089 [-0.00140, +0.00366] | inconclusive |
| final_week | margin3_beyond_elo | 5982 | 448 | +0.00 | +0.00 | -0.00 [-0.77, +0.79] | -0.00009 [-0.00047, +0.00029] | discarded |
| final_week | next_margin_beyond_elo | 6878 | 448 | +0.00 | -0.00 | +0.00 [-1.33, +1.32] | -0.00010 [-0.00116, +0.00102] | discarded |
| final_week | next_game_win | 3428 | 224 |  |  |  | -0.00021 [-0.00161, +0.00127] | discarded |
| qb_change_in_window | margin3_beyond_elo | 5982 | 1397 | -2.89 | +0.88 | -3.77 [-4.45, -3.11] | n/a | descriptive |
| qb_change_in_window | next_margin_beyond_elo | 6878 | 707 | -3.10 | +0.35 | -3.45 [-4.54, -2.41] | n/a | descriptive |

The plain flagged means for week18 and final_week are zero by construction: every team plays, so the margins cancel. The split by team strength shows what happens instead:

week18, margin3_beyond_elo: flagged rows of teams with Elo above 1500 -0.83, below 1500 +0.83; difference -1.67 [-4.21, +0.84].

week18, next_margin_beyond_elo: flagged rows of teams with Elo above 1500 -1.54, below 1500 +1.66; difference -3.20 [-7.35, +0.89].

final_week, margin3_beyond_elo: flagged rows of teams with Elo above 1500 -0.21, below 1500 +0.22; difference -0.43 [-1.87, +1.09].

final_week, next_margin_beyond_elo: flagged rows of teams with Elo above 1500 -0.90, below 1500 +0.93; difference -1.84 [-4.42, +0.65].

Robustness: tom__acceleration on the primary target, all rows +0.00319 [-0.00392, +0.01030] (n 1875); clean rows +0.00519 [-0.01029, +0.02072] (n 879). Clean rows: no QB change in the latest game or in the next 3 games, no bye and no final-week game in the next 3 games.

What the flags show:

- **A change of starting QB is the clearest signal in the study, and it is not momentum.** After a QB change, teams do about 1.8 points per game worse than Elo expects over the next 3 games, -1.79 [-2.54, -0.99]. Adding the flag to the baseline gives +0.00497 [+0.00093, +0.00892] on the primary target. This is a single planned test, not one of the 121 features, so the false discovery correction does not apply to it. On the next-game targets the gain is positive but the interval touches zero.
- **Coming off a bye** is worth about +0.6 points per game beyond Elo, but the interval reaches zero and adding the flag does not help.
- **Week 18**: stronger teams fall short of Elo and weaker teams beat it, by 1.7 points over 3 games and 3.2 points in the next game. Both intervals cross zero. This fits stronger teams resting starters, but the evidence is weak.
- **Robustness**: the top single feature, tom__acceleration, scores +0.00519 [-0.01029, +0.02072] on clean rows (879) against +0.00319 on all rows (1,875). Removing the flagged rows does not uncover a momentum signal.

## 10. Forward test: 2026 to date

The 2026 season was scored **once**, in the final run, after the combination and every setting were fixed on 2012-2025. The scoring sits behind the `MOMENTUM_STUDY_SCORE_HOLDOUT=1` setting, which only the final run used. The two test runs before it did not score 2026.

| Item | Value |
|---|---|
| Season to date | 163 games, 326 team-games, through week 11 (2026-11-23) |
| Fixed choice | tom, off_epa, off_sr x streak, growth, acceleration (ridge alpha 1); not reliable |
| Primary target | 0 rows with all 9 chosen features (230 rows have a target): too few to score (needs at least 20) |
| Next game (margin beyond Elo) | 6 rows from 6 teams (294 rows have a target): too few to score |

The chosen features need acceleration, which exists only from about game 10 of a season. The primary target also needs 3 later games, and teams have played about 11. So 2026 cannot test the choice yet. Since the choice already failed the reliability checks, the verdict does not depend on the forward test.

## 11. Limits

- An NFL season has only 17 games (16 before 2021), so the windows are short. Each feature is missing for a team's first 3 to 9 games, and the full-feature rows used by the combination search are only 1,875 of 7,326.
- The next-3-games target overlaps from one row to the next. The team-season block bootstrap allows for that, but the intervals are still wide.
- The baseline is the production Elo, which already reacts to recent results. Any momentum effect is judged beyond what Elo has already absorbed.
- The QB-change flag takes the starting QB from play-by-play (the passer with the most dropbacks), not from an injury report.
- 2020 was played with few or no fans; the run without 2020 gives the same verdict.
- `blend_weights` in the JSON is null. Nothing reliable was found, so there is nothing to blend.
- The 2026 forward test could not be scored yet (section 10).

## 12. Recommendation

**None found.** No single momentum measure and no small combination of them explains the point margin beyond Elo over the next 3 games, the next game's margin, or the next game's result in a reliable way. The best combination did no better than shuffled outcomes, picked different features in most seasons, and fell short of the baseline in 8 of 14 held-out seasons. Do not add momentum features to the NFL models.

The one finding worth a separate follow-up is a flag, not momentum: a change of starting QB is followed by about 1.8 points per game below Elo over the next 3 games. Any use of that flag should be tested on its own, with forward logging, before it is considered.

