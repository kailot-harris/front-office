# NBA momentum measures study

Research only. This study changes no production code; the Momentum Board's weights stay as they are and the owner decides.

- Script: `tools/momentum_measures_study.R` (fixed seeds, not wired into the pipeline)
- Machine-readable results: `docs/research/momentum_measures_study_results.json` (every method tried, with a verdict and a reason)
- Run: 2026-11-24, 200 shuffled-outcome runs, 2,000 bootstrap resamples, 15.3 minutes in total (permutations 10.1 minutes)

Every number below is copied from the run's own output tables. Feature ids are written `series__measure` (for example `orb_def__impulse` is the impulse measure applied to offensive rebound % allowed).

## 1. Question

Do momentum measures, applied to team stats, predict how an NBA team plays over its next 5-10 games better than team strength alone? Is there a small, stable combination (3 stat series x 3 measures) that does so reliably on seasons it never saw?

And, as part B: are the Momentum Board's blend weights (0.7 form / 0.1 trend / 0.1 residual / 0.1 Elo change, at windows 5, 10 and 18) the right ones?

"Team strength" is a baseline of pregame Elo plus season-to-date net rating. Every candidate is scored only on what it adds to that baseline.

## 2. Data and seasons

Regular-season hoopR team boxes and schedules. 2017-18 is loaded only to seed 2018-19 Elo.

| Season | Role | Games | Team-games | First | Last |
|---|---|---|---|---|---|
| 2018-19 | LOSO | 1230 | 2460 | 2018-10-16 | 2019-04-10 |
| 2019-20 | LOSO (flagged; dropped in sensitivity run) | 1059 | 2118 | 2019-10-22 | 2020-08-14 |
| 2020-21 | LOSO (flagged; dropped in sensitivity run) | 1080 | 2160 | 2020-12-22 | 2021-05-16 |
| 2021-22 | LOSO | 1230 | 2460 | 2021-10-19 | 2022-04-10 |
| 2022-23 | LOSO | 1230 | 2460 | 2022-10-18 | 2023-04-09 |
| 2023-24 | LOSO | 1231 | 2462 | 2023-10-24 | 2024-04-14 |
| 2024-25 | LOSO | 1231 | 2462 | 2024-10-22 | 2025-04-13 |
| 2025-26 | LOSO | 1231 | 2462 | 2025-10-21 | 2026-04-12 |
| 2026-27 | final holdout (in progress) | 258 | 516 | 2026-10-20 | 2026-11-23 |

2019-20 (hiatus and Orlando bubble) and 2020-21 (72 games, no crowds) stay in and are flagged; a sensitivity run drops them (section 7). Features were computed on 19044 historical team-game rows.

### Note: one row per game for Elo (neutral-site games)

The study keeps one row per game when it runs Elo. The production board's `elo_games_from_panel` (`build_momentum_dataset.R`) keeps the home row, or the row of the alphabetically first team at a neutral site. At a neutral site hoopR still marks one side "home", so both rows of a game can pass that filter, and the game can then be processed twice. The study drops the second row per game id.

Neutral-site games per season in this run (these are the games exposed to the double count; the run did not separately count how many of them were actually duplicated by the production filter):

| Season | Neutral-site games |
|---|---|
| 2018-19 | 3 |
| 2019-20 | 91 |
| 2020-21 | 0 |
| 2021-22 | 0 |
| 2022-23 | 1 |
| 2023-24 | 3 |
| 2024-25 | 6 |
| 2025-26 | 6 |
| 2026-27 | 1 |

The 2019-20 count includes the bubble games, which hoopR does not flag as neutral; the study marks every game from 2020-07-30 on as neutral. This is a note only; production code is not changed here.

## 3. Stat series

All per team, per game. Box-stat series are opponent-adjusted: the game value minus the opponent's season-to-date average, using only the opponent's earlier games. Possessions are estimated as FGA - ORB + TOV + 0.44 x FTA (both teams averaged).

| Id | Series | Definition |
|---|---|---|
| elo | Elo rating | Shared Elo rating after each game (`R/elo.R`: K 20, home court 100, margin-of-victory multiplier, 0.75 season carry-over). |
| margin | Point margin | Point margin minus the opponent's season-to-date average margin allowed. |
| ortg | Offensive rating | Points per 100 possessions minus the opponent's season-to-date average allowed. |
| drtg | Defensive rating | Points allowed per 100 possessions minus the opponent's season-to-date average scored. |
| net | Net rating | Net rating (ORtg - DRtg) minus the opponent's season-to-date average allowed. |
| pace | Pace | Possessions minus the opponent's season-to-date average. |
| efg | Effective FG% | Effective FG% minus the opponent's season-to-date average allowed. |
| tov | Turnover % | Turnover % minus the opponent's season-to-date average forced. |
| orb | Offensive rebound % | Offensive rebound % minus the opponent's season-to-date average allowed. |
| ftr | Free-throw rate | FTA/FGA minus the opponent's season-to-date average allowed. |
| efg_def | Effective FG% allowed | Effective FG% allowed minus the opponent's season-to-date average. |
| tov_def | Turnover % forced | Turnover % forced minus the opponent's season-to-date average committed. |
| orb_def | Offensive rebound % allowed | Offensive rebound % allowed minus the opponent's season-to-date average. |
| ftr_def | Free-throw rate allowed | FTA/FGA allowed minus the opponent's season-to-date average. |

## 4. The 11 measures, each using only earlier games

For Elo the per-game "change" is the Elo change. For box series the per-game "surprise" is the game value minus the team's own mean of its earlier games. Every value after a team's game k uses only games 1..k; no value exists before a team's 10th game. Values are then z-scored across teams on each date, using each team's latest state on or before that date. Missing values stay missing and are counted; nothing is imputed. 14 series x 11 measures = 154 features.

| Measure | Definition used here | Why it is written this way |
|---|---|---|
| ROC-10 | Elo: (Elo after game k - Elo 10 games earlier) / 10. Box series: mean of the last 10 games minus the mean of the team's games before them (at least 5 earlier games). | Uses only past games already. |
| MACD | Exponentially weighted mean of the series with span 5 minus the same with span 15, updated game by game from the season's first game. | Uses only past games already. |
| Velocity | Slope of a least-squares line through the trailing 10 games. | A whole-season smooth would use later games; a trailing fit does not. |
| Acceleration | Velocity after game k minus velocity after game k-5. | Same reason as velocity. |
| EWMA of changes | Exponentially weighted mean (span 5) of the per-game change or surprise. | Uses only past games already. |
| Z-score | ROC-10 divided by the standard deviation of the team's changes or surprises in games 1..k (expanding window). | A full-season standard deviation would use later games. |
| RSI | Over the last 10 changes or surprises: 100 x average gain / (average gain + average loss); recent gains vs losses on a 0-100 scale. | Uses only past games already. |
| Growth difference | Sum of the last 10 changes or surprises minus the sum of the 10 before them. | A difference, because the ratio is unstable near zero. |
| Kalman slope | Filtered slope of a local linear trend model (level + slope + noise) run forward through games 1..k; its three noise variances are fitted by maximum likelihood on the training seasons only. | A smoothed (two-sided) slope would use later games; the filtered slope does not. |
| Streak | Signed length of the current run: wins/losses for Elo, positive/negative surprises for box series. | Extended past win/loss to box series. |
| Impulse | m[k] = 0.85 x m[k-1] + change or surprise in game k, from the season's first game. | Uses only past games already. |

Missing count per measure, summed over the 14 series (missing = before game 10, warm-up of the measure, or no z-score on that date): roc10 49790, macd 33969, velocity 33969, acceleration 51006, ewma_change 33969, zscore 49790, rsi 37180, growth 70999, kalman 33969, streak 33969, impulse 33969. Per feature: min 2200, median 2445, max 5108 of 19044 rows.

## 5. Targets

All targets use only games after game k.

| Id | Definition | Primary |
|---|---|---|
| net10_beyond_elo | Mean over the team's next 10 games of (point margin minus the margin Elo expected); the expectation uses the team's Elo after game k, the opponent's pregame Elo and home court: (Elo - opp Elo + 100 x home sign) / 28 points. | yes |
| net5_beyond_elo | Same over the next 5 games. | no |
| ortg10_adj | Mean opponent-adjusted offensive rating over the next 10 games. | no |
| drtg10_adj | Mean opponent-adjusted defensive rating over the next 10 games (lower is better). | no |
| win10_beyond_elo | Win share over the next 10 games minus the mean Elo win probability for those games. | no |
| next_game_win | Next game won by the home side (one row per game); logistic model on the pregame Elo difference with home court plus the season-to-date net-rating difference; scored by log loss and ROC-AUC. | no |

## 6. Protocol

- **Leave-one-season-out (LOSO)** over 2018-19 to 2025-26, with pooled out-of-fold predictions. The score is the out-of-fold R^2 gain over the baseline (Elo after the game plus season-to-date net rating); for the next-game target it is the log-loss gain.
- **Team-season block bootstrap**: paired, 2,000 resamples of whole team-seasons, because next-10 targets overlap from one game to the next.
- **False discovery rate**: Benjamini-Hochberg across the 154 features per target, at q < 0.05. A single feature is `kept` only if its 95% interval is above zero and it survives the correction; `discarded` if its out-of-fold gain is zero or negative; otherwise `inconclusive`.
- **Redundancy families**: correlation clusters across measures and across series (mean |r| >= 0.5).
- **Nested 3x3 combination search**: in each outer fold, the top 6 series and top 6 measures are ranked on the training seasons only, giving C(6,3)^2 = 400 combinations of 3 series x 3 measures; each is fitted as a ridge regression (alpha 0.01, 0.1 or 1) and the best is chosen by inner LOSO, then scored on the held-out season. Comparisons: an elastic net over all 154 features, greedy forward selection, and the board's current momentum score.
- **Permutation baseline**: the whole nested search rerun 200 times with the targets shuffled among teams within each date. This shows how good pure chance looks.
- **Stability**: how often the same combination is chosen across folds, sign by season, and how many combinations tie with the final choice within its interval.
- **Sensitivity run**: parts A and B repeated without 2019-20 and 2020-21 (6 seasons).
- **Reliable** means all four hold: the held-out gain's 95% interval is above zero; it beats the 95th percentile of the permutation runs; the same series and measures (or the same families) are picked in at least half the outer folds; and the gain is positive in most seasons.
- **Holdout**: 2026-27 to date, scored once after every choice was fixed (section 9).

## 7. Part A results: momentum measures

### Single features: verdicts by target

| Target | kept | inconclusive | discarded |
|---|---|---|---|
| net10_beyond_elo | 0 | 35 | 119 |
| net5_beyond_elo | 0 | 59 | 95 |
| ortg10_adj | 0 | 41 | 113 |
| drtg10_adj | 0 | 43 | 111 |
| win10_beyond_elo | 0 | 28 | 126 |
| next_game_win | 0 | 24 | 130 |

No feature is kept on any target. Every FDR q-value in the top tables is 1.0000.

### Top 10 single features: primary target (net10_beyond_elo)

| Feature | Gain | 95% CI | IC change | q | n | Missing | Verdict |
|---|---|---|---|---|---|---|---|
| orb_def__impulse | +0.00367 | [-0.00202, +0.00933] | +0.05990 | 1.0000 | 14096 | 2443 | inconclusive |
| orb_def__kalman | +0.00318 | [-0.00350, +0.00971] | +0.05234 | 1.0000 | 14096 | 2443 | inconclusive |
| orb_def__roc10 | +0.00296 | [-0.00294, +0.00844] | +0.04871 | 1.0000 | 12879 | 3660 | inconclusive |
| orb_def__zscore | +0.00293 | [-0.00281, +0.00865] | +0.04904 | 1.0000 | 12879 | 3660 | inconclusive |
| orb_def__ewma_change | +0.00239 | [-0.00112, +0.00583] | +0.04797 | 1.0000 | 14096 | 2443 | inconclusive |
| orb_def__rsi | +0.00194 | [-0.00283, +0.00647] | +0.04341 | 1.0000 | 13849 | 2690 | inconclusive |
| net__ewma_change | +0.00115 | [-0.00184, +0.00384] | +0.02601 | 1.0000 | 14096 | 2443 | inconclusive |
| net__macd | +0.00115 | [-0.00117, +0.00312] | +0.03060 | 1.0000 | 14096 | 2443 | inconclusive |
| margin__ewma_change | +0.00113 | [-0.00180, +0.00380] | +0.02534 | 1.0000 | 14096 | 2443 | inconclusive |
| margin__macd | +0.00112 | [-0.00119, +0.00309] | +0.03028 | 1.0000 | 14096 | 2443 | inconclusive |

### Top 5 single features on the other targets

net5_beyond_elo:

| Feature | Gain | 95% CI | IC change | q | n | Verdict |
|---|---|---|---|---|---|---|
| orb_def__impulse | +0.00277 | [-0.00087, +0.00647] | +0.05119 | 1.0000 | 15286 | inconclusive |
| orb_def__kalman | +0.00273 | [-0.00145, +0.00686] | +0.05016 | 1.0000 | 15286 | inconclusive |
| net__impulse | +0.00235 | [-0.00133, +0.00577] | +0.04277 | 1.0000 | 15286 | inconclusive |
| margin__impulse | +0.00233 | [-0.00129, +0.00578] | +0.04235 | 1.0000 | 15286 | inconclusive |
| orb_def__roc10 | +0.00210 | [-0.00146, +0.00557] | +0.04115 | 1.0000 | 14069 | inconclusive |

ortg10_adj:

| Feature | Gain | 95% CI | IC change | q | n | Verdict |
|---|---|---|---|---|---|---|
| ortg__impulse | +0.00155 | [-0.00250, +0.00605] | +0.06225 | 1.0000 | 14077 | inconclusive |
| tov__zscore | +0.00151 | [-0.00222, +0.00541] | +0.04936 | 1.0000 | 12871 | inconclusive |
| tov__roc10 | +0.00146 | [-0.00210, +0.00518] | +0.04848 | 1.0000 | 12871 | inconclusive |
| ortg__kalman | +0.00135 | [-0.00421, +0.00740] | +0.05835 | 1.0000 | 14077 | inconclusive |
| tov__impulse | +0.00117 | [-0.00211, +0.00452] | +0.04575 | 1.0000 | 14077 | inconclusive |

drtg10_adj:

| Feature | Gain | 95% CI | IC change | q | n | Verdict |
|---|---|---|---|---|---|---|
| ortg__kalman | +0.00426 | [-0.00258, +0.01171] | +0.06791 | 1.0000 | 14077 | inconclusive |
| orb_def__roc10 | +0.00410 | [-0.00181, +0.00950] | +0.05818 | 1.0000 | 12871 | inconclusive |
| orb_def__zscore | +0.00394 | [-0.00205, +0.00939] | +0.05793 | 1.0000 | 12871 | inconclusive |
| orb_def__kalman | +0.00373 | [-0.00443, +0.01141] | +0.05486 | 1.0000 | 14077 | inconclusive |
| orb_def__impulse | +0.00341 | [-0.00218, +0.00854] | +0.05245 | 1.0000 | 14077 | inconclusive |

win10_beyond_elo:

| Feature | Gain | 95% CI | IC change | q | n | Verdict |
|---|---|---|---|---|---|---|
| orb_def__kalman | +0.00306 | [-0.00335, +0.00937] | +0.06202 | 1.0000 | 14096 | inconclusive |
| orb_def__impulse | +0.00304 | [-0.00267, +0.00854] | +0.06478 | 1.0000 | 14096 | inconclusive |
| orb_def__roc10 | +0.00247 | [-0.00358, +0.00807] | +0.06122 | 1.0000 | 12879 | inconclusive |
| orb_def__zscore | +0.00229 | [-0.00355, +0.00776] | +0.05981 | 1.0000 | 12879 | inconclusive |
| orb_def__rsi | +0.00187 | [-0.00348, +0.00681] | +0.05340 | 1.0000 | 13849 | inconclusive |

next_game_win (gain = log-loss gain; the IC column is the ROC-AUC change, a point estimate without an interval):

| Feature | Gain | 95% CI | AUC change | q | n | Verdict |
|---|---|---|---|---|---|---|
| orb_def__kalman | +0.00094 | [-0.00047, +0.00236] | +0.00138 | 1.0000 | 8030 | inconclusive |
| orb_def__impulse | +0.00086 | [-0.00043, +0.00216] | +0.00126 | 1.0000 | 8030 | inconclusive |
| orb_def__rsi | +0.00079 | [-0.00045, +0.00194] | +0.00101 | 1.0000 | 7908 | inconclusive |
| orb_def__roc10 | +0.00057 | [-0.00052, +0.00165] | +0.00073 | 1.0000 | 7418 | inconclusive |
| orb_def__ewma_change | +0.00057 | [-0.00047, +0.00158] | +0.00095 | 1.0000 | 8030 | inconclusive |

The full top-10 lists for every target and all 924 rows are in the results JSON.

### Redundancy families

Measure families (mean |r| across series >= 0.5):

- roc10, macd, ewma_change, zscore, rsi, kalman, streak, impulse
- velocity, acceleration
- growth

Series families (mean |r| across measures >= 0.5): margin, drtg, net and efg_def form one family; ortg and efg form another; elo, pace, tov, orb, ftr, tov_def, orb_def and ftr_def each stand alone. Feature clusters with every pair |r| >= 0.7: 63 clusters, 43 with more than one feature.

So most of the 11 measures say nearly the same thing about a series; the useful choice is the series, not the measure.

### Combination search by outer fold (primary target)

| Held-out season | Series | Measures | Ridge alpha | Inner gain | Held-out gain | Rows |
|---|---|---|---|---|---|---|
| 2018-19 | orb_def, margin, elo | kalman, roc10, zscore | 0.01 | +0.01107 | -0.01415 | 1526 |
| 2019-20 | orb_def, net, margin | impulse, roc10, zscore | 0.01 | +0.00844 | -0.01210 | 1175 |
| 2020-21 | orb_def, tov_def, ortg | impulse, macd, kalman | 1 | +0.00440 | +0.00924 | 1224 |
| 2021-22 | orb_def, net, margin | ewma_change, impulse, kalman | 0.1 | +0.00611 | -0.00598 | 1519 |
| 2022-23 | orb_def, margin, elo | impulse, roc10, zscore | 0.01 | +0.01108 | -0.02047 | 1522 |
| 2023-24 | orb_def, margin, tov | impulse, roc10, zscore | 0.01 | +0.00534 | +0.01285 | 1525 |
| 2024-25 | orb_def, net, margin | impulse, roc10, zscore | 0.01 | +0.00678 | +0.00438 | 1524 |
| 2025-26 | orb_def, ortg, tov_def | impulse, kalman, ewma_change | 1 | +0.00638 | +0.00321 | 1421 |

The inner gain is positive in every fold; the held-out gain is positive in only 4 of 8. That gap is what overfitting looks like.

### Combination search summary

| Model | Pooled OOF R^2 gain | 95% CI |
|---|---|---|
| Nested 3x3 combination | -0.00110 | [-0.01069, +0.00786] |
| elastic_net | +0.00200 | [-0.00212, +0.00604] |
| greedy_forward | -0.01486 | [-0.02805, -0.00135] |
| board_current_score_w10 | +0.00017 | [-0.00418, +0.00422] |
| Sensitivity: nested 3x3 combination (6 seasons) | -0.00389 | [-0.01299, +0.00467] |
| Sensitivity: elastic_net | -0.00069 | [-0.00295, +0.00151] |
| Sensitivity: greedy_forward | -0.02069 | [-0.03506, -0.00774] |
| Sensitivity: board_current_score_w10 | +0.00013 | [-0.00533, +0.00532] |

### Permutation baseline

200 runs, 95th percentile +0.00007, mean -0.00116, max +0.00086; share of runs at or above the real gain 0.4650; runtime 10.1 min. The real search does no better than the shuffled-outcome runs: about half of the chance runs match or beat it.

### Stability

7 distinct combinations in 8 folds; series counts orb_def 8, margin 6, net 3, elo 2, ortg 2, tov_def 2, tov 1; measure counts impulse 7, roc10 5, zscore 5, kalman 4, ewma_change 2, macd 1; seasons with positive held-out gain 4 of 8.

Final choice on all 8 seasons: orb_def, net, margin x impulse, roc10, zscore (ridge alpha 0.01); 97 of 399 other combinations tie with it within the bootstrap interval.

### Reliability checks

ci_above_zero = FALSE; beats_permutation_p95 = FALSE; stable_selection = FALSE; sign_holds_most_seasons = FALSE. Verdict: none found: fails ci_above_zero, beats_permutation_p95, stable_selection, sign_holds_most_seasons.

### Sensitivity run without 2019-20 and 2020-21 (primary target)

| Feature | Gain | 95% CI | q | Verdict |
|---|---|---|---|---|
| orb_def__impulse | +0.00460 | [-0.00312, +0.01199] | 1.0000 | inconclusive |
| orb_def__kalman | +0.00384 | [-0.00509, +0.01261] | 1.0000 | inconclusive |
| orb_def__ewma_change | +0.00323 | [-0.00175, +0.00799] | 1.0000 | inconclusive |
| orb_def__zscore | +0.00300 | [-0.00426, +0.00987] | 1.0000 | inconclusive |
| orb_def__rsi | +0.00298 | [-0.00389, +0.00932] | 1.0000 | inconclusive |
| orb_def__roc10 | +0.00289 | [-0.00408, +0.00955] | 1.0000 | inconclusive |
| orb_def__macd | +0.00189 | [-0.00096, +0.00458] | 1.0000 | inconclusive |
| orb_def__streak | +0.00182 | [-0.00108, +0.00459] | 1.0000 | inconclusive |
| net__macd | +0.00141 | [-0.00115, +0.00401] | 1.0000 | inconclusive |
| margin__macd | +0.00139 | [-0.00115, +0.00397] | 1.0000 | inconclusive |

Dropping the two unusual seasons does not change the picture: the same offensive-rebound-allowed features lead, every interval still includes zero, and the nested combination's pooled gain is -0.00389 [-0.01299, +0.00467].

## 8. Part B results: the board's blend weights

The board is 0.7 z(form) + 0.1 z(trend) + 0.1 z(residual) + 0.1 z(Elo change). The residual exists only for 2026-27, so the historical test uses the three components that exist in every season (form, trend, Elo change); the current weights for those three, rescaled to sum to 1, are 0.78/0.11/0.11. Each window is searched on a 0.05-step grid over the three weights (231 points), on the primary target, LOSO over 8 seasons. A window's weights would change only if the LOSO-selected weights beat the current ones with a 95% interval above zero.

### Best weights versus current (primary target)

| Window | Rows | Current (0.78/0.11/0.11) gain | Best weights | Best gain | Best - current [95% CI] | Grid points within CI of best | LOSO-selected - current [95% CI] | Non-negative regression - current [95% CI] |
|---|---|---|---|---|---|---|---|---|
| 5 | 14375 | +0.00185 | form 0.50 / trend 0.50 / elo 0.00 | +0.00234 | +0.00049 [-0.00028, +0.00116] | 172 of 231 | +0.00008 [-0.00075, +0.00083] | +0.00007 [-0.00069, +0.00077] |
| 10 | 13170 | +0.00091 | form 0.60 / trend 0.40 / elo 0.00 | +0.00127 | +0.00036 [-0.00054, +0.00116] | 231 of 231 | -0.00041 [-0.00154, +0.00063] | -0.00032 [-0.00121, +0.00052] |
| 18 | 11255 | +0.00045 | form 0.45 / trend 0.45 / elo 0.10 | +0.00056 | +0.00011 [-0.00096, +0.00112] | 231 of 231 | -0.00195 [-0.00324, -0.00077] | -0.00127 [-0.00215, -0.00039] |

The "best weights" are the in-sample best on the grid; the fair comparison is the LOSO-selected column, where weights are picked on training seasons only. Its interval includes zero at windows 5 and 10 and is below zero at window 18. The top of the surface is flat: at windows 10 and 18 every grid point is within the interval of the best.

### Each component alone, and the next-5 target

| Window | Form alone | Trend alone | Elo change alone | Next-5: current gain | Next-5: best weights | Next-5: best - current [95% CI] |
|---|---|---|---|---|---|---|
| 5 | +0.00217 | +0.00223 | -0.00033 | +0.00178 | form 0.10 / trend 0.90 / elo 0.00 | +0.00059 [-0.00038, +0.00150] |
| 10 | +0.00113 | +0.00117 | -0.00075 | +0.00201 | form 0.05 / trend 0.95 / elo 0.00 | +0.00090 [-0.00065, +0.00236] |
| 18 | +0.00011 | +0.00049 | -0.00019 | +0.00104 | form 0.00 / trend 1.00 / elo 0.00 | +0.00049 [-0.00092, +0.00180] |

### Trend swap / join with the best part-A feature

The best single part-A feature on the primary target is orb_def__impulse. It either replaces the trend component (swap) or joins it as a fourth component (join).

| Window | Rows | Best 3-component gain (same rows) | Swap: best weights | Swap - best 3 [95% CI] | Join: best weights | Join - best 3 [95% CI] |
|---|---|---|---|---|---|---|
| 5 | 14096 | +0.00224 | form 0.00 / x 1.00 / elo 0.00 | +0.00142 [-0.00473, +0.00733] | form 0.00 / trend 0.00 / x 1.00 / elo 0.00 | +0.00142 [-0.00473, +0.00733] |
| 10 | 13170 | +0.00127 | form 0.00 / x 1.00 / elo 0.00 | +0.00330 [-0.00362, +0.01013] | form 0.00 / trend 0.00 / x 1.00 / elo 0.00 | +0.00330 [-0.00362, +0.01013] |
| 18 | 11255 | +0.00056 | form 0.00 / x 1.00 / elo 0.00 | +0.00539 [-0.00299, +0.01355] | form 0.00 / trend 0.00 / x 1.00 / elo 0.00 | +0.00539 [-0.00299, +0.01355] |

Every interval includes zero, and orb_def__impulse is itself inconclusive in part A. It should not feed the trend component on this evidence.

### Sensitivity run without 2019-20 and 2020-21

| Window | Current gain | Best weights | Best - current [95% CI] | LOSO-selected - current [95% CI] |
|---|---|---|---|---|
| 5 | +0.00187 | form 0.35 / trend 0.65 / elo 0.00 | +0.00063 [-0.00047, +0.00175] | -0.00006 [-0.00134, +0.00116] |
| 10 | +0.00057 | form 0.00 / trend 1.00 / elo 0.00 | +0.00080 [-0.00127, +0.00294] | +0.00030 [-0.00162, +0.00230] |
| 18 | -0.00033 | form 0.00 / trend 1.00 / elo 0.00 | +0.00107 [-0.00108, +0.00327] | -0.00025 [-0.00215, +0.00169] |

### Residual check (small sample, 2026-27 only, in-sample, next-5 target)

The residual uses the board's logged pregame margins, which exist only for 2026-27 (190 of 258 games resolved). Rows without a residual are left out, never filled.

| Window | Rows | Teams | IC current 4-part | IC 3-part (no residual) | IC residual alone | 4 - 3 [95% CI] |
|---|---|---|---|---|---|---|
| 5 | 96 | 30 | -0.2194 | -0.2166 | -0.1904 | -0.00284 [-0.02877, +0.02485] |
| 10 | 0 | 0 | too few rows | | | |
| 18 | 0 | 0 | too few rows | | | |

This is far too small to judge the residual weight. An Elo-expectation proxy for the residual was not run.

## 9. The 2026-27 holdout

The part A combination and the part B weights were fixed on 2018-19 to 2025-26 before the holdout was scored, and the final run scored it once.

**Disclosure:** the holdout code ran during test runs before the final run. No selection logic changed after that.

2026-27 currently has too few games per team for the primary next-10 target: the season so far has 258 games (516 team-games over 30 teams), features need a team's 10th game and the next-10 target needs 10 later games. A holdout score needs at least 20 rows. Real row counts from the run:

| Choice | Target | 2026-27 rows | Result |
|---|---|---|---|
| Part A: orb_def, net, margin x impulse, roc10, zscore | net10_beyond_elo (primary) | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part A: same | net5_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part B window 5 | net10_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part B window 5 | net5_beyond_elo | 96 | scored (current gain -0.01540, best-weights gain -0.02603) |
| Part B window 10 | net10_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part B window 10 | net5_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part B window 18 | net10_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |
| Part B window 18 | net5_beyond_elo | 0 | too few 2026-27 rows to score yet (needs at least 20) |

The only scored holdout row set (window 5, next-5, 96 rows) shows both the current and the best weights doing worse than the baseline, with the best weights worse than the current ones. 96 rows is a very small sample. The holdout can be scored properly later in the season with the same fixed choices.

## 10. Limits

- Effects are small: regression to the mean dominates NBA results over 5-10 games.
- The combination search uses rows where all 154 features exist (from about a team's 21st game) so every candidate is scored on the same rows; single features use all rows where they exist.
- Kalman variances are fitted on the outer training seasons and reused in the inner loop.
- Bootstrap intervals for the incremental IC hold the ranks at their full-sample values.
- The next-game target is scored by log loss; its ROC-AUC change is a point estimate without an interval.
- The board residual exists only for 2026-27 (190 of 258 games with a resolved logged pregame margin); its check is in-sample and small.
- 2026-27 is early: teams have played too few games for most holdout rows (features need 10 games, targets 5 or 10 later games).
- Possession estimates and four-factor rates are noisy over 5-10 games.
- The Elo-expectation residual proxy for part B was not run.
- The holdout code ran during test runs before the final run (section 9).
- The neutral-site Elo note (section 2) reports neutral-site games per season, not a separate count of rows the production filter actually duplicated.

## 11. Recommendations

**(A) Momentum measures: none found.** No small combination of momentum measures predicts the next 5-10 games reliably beyond Elo plus season net rating. The nested 3x3 search fails all four checks (interval above zero, beating chance, stable picks, positive in most seasons), and no single feature is kept on any target.

**(B) Board blend weights: keep 0.7/0.1/0.1/0.1** at window 5, window 10 and window 18. No window's LOSO-selected weights beat the current ones with an interval above zero, and the best part-A measure should not replace or join the trend component.
