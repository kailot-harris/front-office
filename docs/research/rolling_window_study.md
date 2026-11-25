# NFL rolling-window study (issue #227)

Research only. This study changes no production code, no `config.R` setting and no published data. Script: `tools/rolling_window_study.R` (fixed seeds; not wired into the pipeline). Results: `docs/research/rolling_window_study_results.json`. It answers issue #227 and supplies the settings the NFL Momentum Board (#226) waits on.

## Short answer

- **Replication arm (the NBA window test translated to football):** a 6-game window scores the highest ROC-AUC on the 2025 test season (0.697, accuracy 0.647, kappa 0.288). But one season is only 272 games, and every window from 2 to 14 (and 17) falls inside the 95% interval of that best score. The replication cannot tell the windows apart.
- **Stronger arm (leave-one-season-out over 2012-2025):** on the raw targets, longer windows predict better, up to the full 16-17 games. Under the shortest-window-inside-the-interval rule, the answer is **9 games for next-game margin** and **6-7 games for next-game win**, under both carry-over methods. **Beyond Elo, no window adds anything.** For every window, method and feature, the 95% interval of the gain over Elo includes zero, so the rule falls back to window 1 only because no window can be told apart from any other. Recent opponent-adjusted EPA per play tells you what Elo already knows.
- **Opponent-adjusted point margin** gives the same results as opponent-adjusted EPA per play, to within the intervals.
- **Season boundaries:** carrying last season's games across the boundary (`mean_regress` or `decay`) lets every team-game in weeks 1-6 have a value (2,580 of 2,580). Under `reset`, 1,234 have a value for a 3-game window and none for a 6-game window. On the rows `reset` leaves blank, the carried windows predict about as well as anywhere else, which is to say almost nothing beyond Elo. `mean_regress` and `decay` cannot be told apart.
- **Combined-score weights:** the held-out score surface is completely flat. All 1,771 grid weightings sit inside the 95% interval of the best one, at every board window, and the best held-out R² beyond Elo is 0.002 or less, with an interval that includes zero. The 0.7/0.1/0.1/0.1 weighting is not measurably worse than the best.
- **Flags:** at the board's windows (3, 6, 9 and season-to-date), no candidate flag reaches 80% simulated detection of a plausible effect. Only "key players missing" gets there, from 12 games on.
- **Availability data:** injury reports cover every season from 2012 to 2025 (at least 99.4% of team-weeks). Snap counts cover 2013-2025 fully and 2012 not at all. A "key players missing" value can be computed from 2013.

## 1. Data and shared definitions

- **Games:** regular season only, 2012-2025 (7,326 team-games; 13 tied games in 2010-2025). Seasons 2010-2011 only feed windows carried into 2012 and the replication's training data. 2026 is not scored. Play-by-play and schedules come from `nflreadr` (every team-game 2010-2025 has play-by-play).
- **Elo:** the production walk-forward (`tools/elo_model.R`, `ELO_K_FACTOR`), run on every completed game from 2002, using pregame ratings only. Elo's expected margin for a game is (Elo minus opponent Elo plus 48 for the listed home team, minus 48 for the away team) / 25 points. Elo's win probability is the walk-forward's pure Elo probability. The setup is the same as the merged momentum study (#221), whose helpers this script copies.
- **Opponent-adjusted EPA per play (the form measure):** offense EPA/play minus the opponent's mean EPA/play allowed in its earlier games, minus (defense EPA/play allowed minus the opponent's mean EPA/play produced in its earlier games). The opponent's baseline uses only its earlier games that season. Before an opponent's first game of a season, the baseline is its whole previous season. That fallback is new relative to the momentum study, which left week 1 blank; it gives week 1 a value under every method without using any later game. **Opponent-adjusted point margin:** margin plus the opponent's earlier mean margin.
- **Windows:** the mean over the team's last k games, k = 1..17, starting at the previous game (`tools/rolling_window_study.R`, `window_value()`). Season-to-date is the mean of the team's earlier games that season. A look-ahead guard checks that every lag points to an earlier game.
- **Season-boundary methods** (named by `OFFSEASON_METHOD` in `config.R`; no code in the repo defines `mean_regress` or `decay`, so this study defines them):
  - `reset`: windows start fresh each season. A team with fewer than k games that season has no value.
  - `mean_regress`: windows run across the boundary. Each carried game's value is pulled 50% toward the league average of its own season, once per boundary crossed.
  - `decay`: windows run across the boundary. Each carried game keeps its value but gets weight 0.5 per boundary crossed (0.5 last season, 0.25 two seasons back); current-season games weigh 1. This is an exponential weight in seasons, stated here because nothing in the repo defines decay.
  - Season-to-date under `mean_regress` and `decay`: a team's first game uses its whole previous season (regressed 50%, or at equal weights). After that it is the same as `reset`.
  - Where a team has at least k games this season, all three methods give the same value. They differ only where a window reaches into an earlier season.
- **No imputation:** missing values stay missing and are counted (table 1).

### Table 1. Team-games 2012-2025 with a value for both teams (opponent-adjusted EPA), all games and weeks 1-6

| Window | reset: scorable team-games | reset: weeks 1-6 | mean_regress: scorable | mean_regress: weeks 1-6 | decay: scorable | decay: weeks 1-6 |
|---|---|---|---|---|---|---|
| 1 | 6876 | 2130 | 7326 | 2580 | 7326 | 2580 |
| 2 | 6428 | 1682 | 7326 | 2580 | 7326 | 2580 |
| 3 | 5980 | 1234 | 7326 | 2580 | 7326 | 2580 |
| 4 | 5514 | 768 | 7326 | 2580 | 7326 | 2580 |
| 5 | 5032 | 286 | 7326 | 2580 | 7326 | 2580 |
| 6 | 4560 | 0 | 7326 | 2580 | 7326 | 2580 |
| 7 | 4098 | 0 | 7326 | 2580 | 7326 | 2580 |
| 8 | 3642 | 0 | 7326 | 2580 | 7326 | 2580 |
| 9 | 3220 | 0 | 7326 | 2580 | 7326 | 2580 |
| 10 | 2798 | 0 | 7326 | 2580 | 7326 | 2580 |
| 11 | 2370 | 0 | 7326 | 2580 | 7326 | 2580 |
| 12 | 1934 | 0 | 7326 | 2580 | 7326 | 2580 |
| 13 | 1502 | 0 | 7326 | 2580 | 7326 | 2580 |
| 14 | 1054 | 0 | 7326 | 2580 | 7326 | 2580 |
| 15 | 606 | 0 | 7326 | 2580 | 7326 | 2580 |
| 16 | 156 | 0 | 7326 | 2580 | 7326 | 2580 |
| 17 | 0 | 0 | 7326 | 2580 | 7326 | 2580 |
| std | 6876 | 2130 | 7326 | 2580 | 7326 | 2580 |
Totals: 7326 team-games 2012-2025, 2580 in weeks 1-6.

Opponent-adjusted point margin has the same counts.

## 2. Replication arm: the NBA window test in football

**What the original does** (`rolling-window-expt` chunk and `evaluate_rolling_window()` in the NBA project's original Rmd): trailing means with `slider::slide_dbl(x, mean, .before = k, .after = -1)` grouped by team only, so windows cross seasons and are partial at the very start of a team's history. It takes home minus away differences, drops NA rows, fits `rand_forest(trees = 300)` with ranger for home win on seasons before the test season, tests on one season, and chooses the k with the highest ROC-AUC, also reporting accuracy and kappa.

**Football version:** the same pipeline (recipe, `step_rm`, `step_normalize`, parsnip `rand_forest(trees = 300)` with ranger, workflow, yardstick metrics). It trains on 2010-2024 and tests on 2025, for k = 1..17. Stats per team-game: points, first downs, rushing yards, net passing yards, sacks taken, giveaways, takeaways, penalty yards, yards per play, third-down conversion rate, offensive EPA/play and defensive EPA/play allowed, plus days of rest. The study checked that its window code matches `slider::slide_dbl()` exactly (largest difference 9e-16). The "original" variant uses the NBA rule. The other three variants recompute every window under each season-boundary method.

### Table 2. Replication: 2025 test season (ROC-AUC [95% game-bootstrap interval] / accuracy / kappa)

| k | original: AUC [95%] / acc / kappa | reset | mean_regress | decay |
|---|---|---|---|---|
| 1 | 0.549 [0.482, 0.617] / 0.537 / 0.053 | 0.560 [0.490, 0.628] / 0.535 / 0.053 | 0.568 [0.500, 0.636] / 0.540 / 0.063 | 0.550 [0.482, 0.620] / 0.522 / 0.026 |
| 2 | 0.653 [0.590, 0.715] / 0.599 / 0.187 | 0.625 [0.555, 0.692] / 0.600 / 0.185 | 0.668 [0.605, 0.729] / 0.618 / 0.225 | 0.643 [0.577, 0.706] / 0.618 / 0.223 |
| 3 | 0.639 [0.574, 0.706] / 0.614 / 0.220 | 0.633 [0.560, 0.706] / 0.612 / 0.218 | 0.658 [0.594, 0.724] / 0.629 / 0.250 | 0.650 [0.587, 0.716] / 0.618 / 0.227 |
| 4 | 0.651 [0.586, 0.713] / 0.592 / 0.172 | 0.632 [0.556, 0.708] / 0.615 / 0.226 | 0.649 [0.586, 0.711] / 0.610 / 0.211 | 0.655 [0.588, 0.716] / 0.588 / 0.169 |
| 5 | 0.689 [0.626, 0.751] / 0.632 / 0.258 | 0.672 [0.595, 0.748] / 0.626 / 0.247 | 0.687 [0.621, 0.750] / 0.640 / 0.275 | 0.680 [0.615, 0.744] / 0.643 / 0.282 |
| 6 | 0.697 [0.630, 0.759] / 0.647 / 0.288 | 0.674 [0.593, 0.754] / 0.642 / 0.276 | 0.705 [0.639, 0.765] / 0.688 / 0.370 | 0.689 [0.621, 0.752] / 0.651 / 0.297 |
| 7 | 0.674 [0.609, 0.735] / 0.647 / 0.287 | 0.683 [0.595, 0.765] / 0.633 / 0.260 | 0.679 [0.615, 0.742] / 0.636 / 0.268 | 0.686 [0.622, 0.749] / 0.647 / 0.286 |
| 8 | 0.676 [0.612, 0.739] / 0.636 / 0.266 | 0.677 [0.582, 0.764] / 0.633 / 0.261 | 0.679 [0.614, 0.745] / 0.643 / 0.282 | 0.664 [0.599, 0.726] / 0.632 / 0.260 |
| 9 | 0.676 [0.614, 0.742] / 0.629 / 0.250 | 0.661 [0.565, 0.753] / 0.621 / 0.235 | 0.682 [0.617, 0.746] / 0.640 / 0.272 | 0.693 [0.629, 0.756] / 0.643 / 0.280 |
| 10 | 0.666 [0.599, 0.730] / 0.632 / 0.257 | 0.609 [0.502, 0.710] / 0.615 / 0.217 | 0.664 [0.600, 0.728] / 0.636 / 0.265 | 0.657 [0.590, 0.721] / 0.636 / 0.265 |
| 11 | 0.643 [0.575, 0.710] / 0.647 / 0.287 | 0.578 [0.466, 0.691] / 0.600 / 0.193 | 0.656 [0.590, 0.723] / 0.640 / 0.272 | 0.671 [0.604, 0.735] / 0.643 / 0.277 |
| 12 | 0.635 [0.564, 0.703] / 0.621 / 0.233 | 0.524 [0.400, 0.649] / 0.532 / 0.050 | 0.651 [0.582, 0.719] / 0.647 / 0.284 | 0.655 [0.586, 0.722] / 0.640 / 0.268 |
| 13 | 0.636 [0.570, 0.699] / 0.603 / 0.194 | 0.497 [0.348, 0.639] / 0.516 / 0.010 | 0.663 [0.599, 0.725] / 0.629 / 0.246 | 0.649 [0.584, 0.713] / 0.621 / 0.232 |
| 14 | 0.633 [0.566, 0.698] / 0.599 / 0.187 | 0.474 [0.305, 0.648] / 0.479 / -0.042 | 0.665 [0.600, 0.728] / 0.625 / 0.241 | 0.661 [0.597, 0.725] / 0.647 / 0.284 |
| 15 | 0.624 [0.560, 0.688] / 0.585 / 0.157 | 0.528 [0.322, 0.733] / 0.500 / -0.032 | 0.652 [0.587, 0.714] / 0.629 / 0.248 | 0.644 [0.575, 0.707] / 0.621 / 0.231 |
| 16 | 0.622 [0.556, 0.688] / 0.577 / 0.141 | - (test games 16) | 0.662 [0.595, 0.724] / 0.610 / 0.210 | 0.652 [0.585, 0.716] / 0.651 / 0.292 |
| 17 | 0.636 [0.570, 0.700] / 0.588 / 0.167 | - (test games 0) | 0.661 [0.598, 0.725] / 0.614 / 0.217 | 0.645 [0.580, 0.708] / 0.607 / 0.203 |

### Table 3. Replication: best window by ROC-AUC

| Variant | Best k | ROC-AUC [95%] | Accuracy | Kappa | Test games | Windows inside the best's interval |
|---|---|---|---|---|---|---|
| original | 6 | 0.697 [0.630, 0.759] | 0.647 | 0.288 | 272 | 2,3,4,5,6,7,8,9,10,11,12,13,14,17 |
| reset | 7 | 0.683 [0.595, 0.765] | 0.633 | 0.260 | 158 | 2,3,4,5,6,7,8,9,10 |
| mean_regress | 6 | 0.705 [0.639, 0.765] | 0.688 | 0.370 | 272 | 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17 |
| decay | 9 | 0.693 [0.629, 0.756] | 0.643 | 0.280 | 272 | 2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17 |

**Answer:** under the original rule, the best window is 6 games (ROC-AUC 0.697). Under `mean_regress` it is also 6 (0.705), under `decay` 9 (0.693), and under `reset` 7 (0.683, on only 158 test games). In every variant, most windows fall inside the best one's interval, so a single test season cannot choose a window. That is the main weakness of the original design, and the reason for the stronger arm.

### Deviations from the original (every one)

1. **Sport and stats.** Football team stats replace basketball box scores: points, first downs, rushing yards, net passing yards, sacks taken, giveaways, takeaways and penalty yards stand in for the counting stats (rebounds, assists, steals, blocks, turnovers). Yards per play, third-down rate and offensive and defensive EPA/play stand in for the rate stats (eFG%, TOV%, FTr, TS%). Total yards difference stands in for the total-rebound difference.
2. **Predictor set mirrors `step_rm`.** As in the original, the levels of points and of the rate stats are removed and their home-minus-away differences kept. Home and away levels of the counting stats and days of rest are kept, along with all differences. `season` stays in as a numeric predictor, as it does in the original (its `step_rm` does not remove it).
3. **Window range** is k = 1..17 (a 17-game season), not 3..25.
4. **Test season** is 2025 (the last complete season), not 2026. Training covers 2010-2024 (the original trains on every season before its test season).
5. **Fixed seed per window** (`STUDY_SEED + 100 x variant + k`). The original set no seed, so its results are not reproducible run to run. ranger runs on 4 threads instead of all cores.
6. **Ties** (13 games in 2010-2025) count as "not a home win", which is what the original's `home_win == TRUE` rule does. Neutral-site games use the listed home team.
7. **Days of rest** cross seasons, as in the original (`lag(game_date)` within team), so week 1 carries the offseason gap.
8. **Franchise moves** (OAK/LV, SD/LAC, STL/LA) are keyed to today's abbreviation, so windows follow the franchise.
9. **Added, not in the original:** a 95% game-bootstrap interval on each test-season ROC-AUC (2,000 resamples), and the three season-boundary variants. Under `reset`, windows need k games that season, so test rows shrink and k = 16-17 cannot be scored.
10. **Data start:** 2010. As in the original, a team's first game (empty window) is dropped by `drop_na()`. Sixteen 2010 week-1 home games are dropped in every variant.

## 3. Stronger arm

**Design:** leave-one-season-out over 2012-2025, so each season is predicted by a model fitted on the other 13. Feature: the team's window value minus the opponent's (opponent-adjusted EPA per play; opponent-adjusted point margin as the comparison). Targets:

- **Margin, raw:** next-game point margin regressed on the difference and home sign. Score: pooled out-of-fold R².
- **Margin beyond Elo:** (margin minus Elo's expected margin) regressed on the difference. Score: out-of-fold R².
- **Win, raw:** home win from a logistic model on the difference, one row per game, ties left out. Scores: ROC-AUC and log loss.
- **Win beyond Elo:** a logistic model on Elo's win probability (logit) plus the difference, against Elo alone refit on the same rows. Scores: the reduction in log loss and the change in ROC-AUC.

**Intervals:** 95% intervals come from 2,000 team-season block bootstrap resamples. **Selection rule:** take the best window's 95% interval; the answer is the shortest window (1..17, with season-to-date treated as longest) whose score lies inside it.

**Reading `reset` across windows:** under `reset`, a k-game window exists only from a team's (k+1)-th game, so longer windows are scored only on later-season games, which are easier to predict. Its own-rows column therefore mixes window length with time of season. The "same rows" column fixes this. It scores `reset` windows 1-8 and season-to-date on the same games (both teams past 8 games that season), where all three methods give the same values. The carry methods score every window on the same 7,326 team-games.

### Table 4. Next-game margin, raw: out-of-fold R² [95%] (opponent-adjusted EPA)

| Window | reset (own rows) | mean_regress | decay | reset, same rows (both teams past 8 games) |
|---|---|---|---|---|
| 1 | 0.0500 [0.0390, 0.0600] | 0.0469 [0.0365, 0.0564] | 0.0459 [0.0355, 0.0553] | 0.0591 [0.0435, 0.0732] |
| 2 | 0.0785 [0.0642, 0.0920] | 0.0724 [0.0586, 0.0850] | 0.0699 [0.0564, 0.0821] | 0.0956 [0.0748, 0.1146] |
| 3 | 0.0992 [0.0825, 0.1147] | 0.0909 [0.0761, 0.1043] | 0.0886 [0.0737, 0.1022] | 0.1161 [0.0937, 0.1372] |
| 4 | 0.1283 [0.1101, 0.1451] | 0.1091 [0.0938, 0.1231] | 0.1057 [0.0901, 0.1200] | 0.1393 [0.1164, 0.1602] |
| 5 | 0.1449 [0.1259, 0.1633] | 0.1212 [0.1054, 0.1361] | 0.1176 [0.1017, 0.1325] | 0.1537 [0.1300, 0.1753] |
| 6 | 0.1556 [0.1361, 0.1741] | 0.1278 [0.1125, 0.1431] | 0.1239 [0.1078, 0.1395] | 0.1574 [0.1344, 0.1785] |
| 7 | 0.1575 [0.1360, 0.1767] | 0.1301 [0.1140, 0.1445] | 0.1264 [0.1098, 0.1412] | 0.1574 [0.1343, 0.1786] |
| 8 | 0.1575 [0.1342, 0.1790] | 0.1317 [0.1163, 0.1459] | 0.1286 [0.1124, 0.1436] | 0.1575 [0.1342, 0.1790] |
| 9 | 0.1749 [0.1493, 0.1988] | 0.1358 [0.1199, 0.1507] | 0.1326 [0.1162, 0.1482] | - |
| 10 | 0.1845 [0.1566, 0.2114] | 0.1377 [0.1214, 0.1533] | 0.1344 [0.1175, 0.1505] | - |
| 11 | 0.1865 [0.1572, 0.2151] | 0.1433 [0.1266, 0.1593] | 0.1401 [0.1228, 0.1563] | - |
| 12 | 0.1938 [0.1607, 0.2259] | 0.1440 [0.1274, 0.1600] | 0.1410 [0.1238, 0.1570] | - |
| 13 | 0.1976 [0.1605, 0.2334] | 0.1463 [0.1296, 0.1620] | 0.1434 [0.1260, 0.1597] | - |
| 14 | 0.1848 [0.1403, 0.2257] | 0.1491 [0.1325, 0.1647] | 0.1464 [0.1294, 0.1628] | - |
| 15 | 0.2058 [0.1438, 0.2650] | 0.1494 [0.1330, 0.1650] | 0.1472 [0.1304, 0.1638] | - |
| 16 | - | 0.1500 [0.1341, 0.1653] | 0.1484 [0.1319, 0.1645] | - |
| 17 | - | 0.1504 [0.1341, 0.1654] | 0.1486 [0.1317, 0.1647] | - |
| std | 0.0988 [0.0828, 0.1150] | 0.0959 [0.0803, 0.1109] | 0.0975 [0.0818, 0.1127] | 0.1698 [0.1443, 0.1933] |
Rows at window 3: reset 5980, mean_regress 7326, decay 7326, reset same rows 3642.

### Table 5. Next-game margin beyond Elo: out-of-fold R² [95%] (opponent-adjusted EPA)

| Window | reset (own rows) | mean_regress | decay | reset, same rows (both teams past 8 games) |
|---|---|---|---|---|
| 1 | 0.0011 [-0.0010, 0.0027] | 0.0013 [-0.0009, 0.0030] | 0.0015 [-0.0008, 0.0034] | 0.0007 [-0.0021, 0.0029] |
| 2 | 0.0011 [-0.0010, 0.0029] | 0.0015 [-0.0007, 0.0035] | 0.0019 [-0.0007, 0.0042] | 0.0006 [-0.0020, 0.0024] |
| 3 | 0.0010 [-0.0013, 0.0029] | 0.0013 [-0.0009, 0.0032] | 0.0015 [-0.0008, 0.0037] | 0.0007 [-0.0021, 0.0028] |
| 4 | -0.0001 [-0.0016, 0.0008] | 0.0007 [-0.0011, 0.0023] | 0.0010 [-0.0011, 0.0029] | 0.0004 [-0.0019, 0.0021] |
| 5 | 0.0000 [-0.0016, 0.0011] | 0.0008 [-0.0010, 0.0023] | 0.0010 [-0.0010, 0.0028] | 0.0004 [-0.0019, 0.0019] |
| 6 | -0.0003 [-0.0021, 0.0009] | 0.0007 [-0.0010, 0.0022] | 0.0010 [-0.0010, 0.0028] | 0.0004 [-0.0020, 0.0020] |
| 7 | 0.0010 [-0.0017, 0.0032] | 0.0013 [-0.0008, 0.0031] | 0.0016 [-0.0007, 0.0037] | 0.0012 [-0.0018, 0.0036] |
| 8 | 0.0019 [-0.0016, 0.0049] | 0.0019 [-0.0006, 0.0039] | 0.0020 [-0.0005, 0.0043] | 0.0019 [-0.0016, 0.0049] |
| 9 | 0.0006 [-0.0025, 0.0029] | 0.0019 [-0.0006, 0.0040] | 0.0021 [-0.0006, 0.0043] | - |
| 10 | 0.0006 [-0.0026, 0.0031] | 0.0019 [-0.0005, 0.0041] | 0.0021 [-0.0005, 0.0045] | - |
| 11 | 0.0004 [-0.0031, 0.0029] | 0.0014 [-0.0008, 0.0033] | 0.0016 [-0.0008, 0.0037] | - |
| 12 | -0.0002 [-0.0044, 0.0026] | 0.0015 [-0.0008, 0.0034] | 0.0016 [-0.0008, 0.0037] | - |
| 13 | 0.0009 [-0.0050, 0.0051] | 0.0014 [-0.0008, 0.0032] | 0.0015 [-0.0008, 0.0035] | - |
| 14 | 0.0038 [-0.0074, 0.0122] | 0.0012 [-0.0009, 0.0029] | 0.0013 [-0.0009, 0.0031] | - |
| 15 | 0.0015 [-0.0139, 0.0123] | 0.0013 [-0.0008, 0.0030] | 0.0013 [-0.0008, 0.0031] | - |
| 16 | - | 0.0013 [-0.0008, 0.0031] | 0.0013 [-0.0008, 0.0030] | - |
| 17 | - | 0.0014 [-0.0007, 0.0031] | 0.0013 [-0.0008, 0.0031] | - |
| std | 0.0015 [-0.0011, 0.0038] | 0.0014 [-0.0010, 0.0035] | 0.0014 [-0.0011, 0.0035] | 0.0011 [-0.0020, 0.0036] |
Rows at window 3: reset 5980, mean_regress 7326, decay 7326, reset same rows 3642.

### Table 6. Next-game win, raw: ROC-AUC [95%] (opponent-adjusted EPA)

| Window | reset (own rows) | mean_regress | decay | reset, same rows (both teams past 8 games) |
|---|---|---|---|---|
| 1 | 0.5870 [0.5664, 0.6067] | 0.5830 [0.5631, 0.6019] | 0.5817 [0.5621, 0.6005] | 0.6048 [0.5775, 0.6294] |
| 2 | 0.6212 [0.6014, 0.6406] | 0.6149 [0.5965, 0.6330] | 0.6130 [0.5946, 0.6312] | 0.6362 [0.6090, 0.6627] |
| 3 | 0.6400 [0.6204, 0.6592] | 0.6306 [0.6126, 0.6483] | 0.6296 [0.6115, 0.6473] | 0.6534 [0.6268, 0.6799] |
| 4 | 0.6628 [0.6426, 0.6830] | 0.6457 [0.6275, 0.6636] | 0.6448 [0.6268, 0.6627] | 0.6731 [0.6467, 0.6972] |
| 5 | 0.6806 [0.6600, 0.7009] | 0.6580 [0.6401, 0.6744] | 0.6569 [0.6390, 0.6729] | 0.6824 [0.6568, 0.7049] |
| 6 | 0.6870 [0.6651, 0.7096] | 0.6641 [0.6449, 0.6815] | 0.6624 [0.6433, 0.6800] | 0.6858 [0.6611, 0.7094] |
| 7 | 0.6871 [0.6633, 0.7095] | 0.6675 [0.6488, 0.6848] | 0.6657 [0.6478, 0.6828] | 0.6871 [0.6631, 0.7105] |
| 8 | 0.6857 [0.6614, 0.7086] | 0.6694 [0.6508, 0.6858] | 0.6683 [0.6499, 0.6853] | 0.6857 [0.6614, 0.7086] |
| 9 | 0.6974 [0.6717, 0.7207] | 0.6711 [0.6527, 0.6881] | 0.6702 [0.6520, 0.6876] | - |
| 10 | 0.6940 [0.6666, 0.7204] | 0.6720 [0.6535, 0.6891] | 0.6717 [0.6535, 0.6892] | - |
| 11 | 0.6965 [0.6664, 0.7255] | 0.6743 [0.6556, 0.6921] | 0.6739 [0.6557, 0.6915] | - |
| 12 | 0.7067 [0.6753, 0.7364] | 0.6767 [0.6577, 0.6942] | 0.6765 [0.6580, 0.6939] | - |
| 13 | 0.7067 [0.6707, 0.7393] | 0.6793 [0.6608, 0.6968] | 0.6793 [0.6612, 0.6970] | - |
| 14 | 0.6786 [0.6342, 0.7208] | 0.6803 [0.6620, 0.6979] | 0.6804 [0.6614, 0.6979] | - |
| 15 | 0.6849 [0.6230, 0.7445] | 0.6818 [0.6630, 0.6992] | 0.6817 [0.6632, 0.6991] | - |
| 16 | - | 0.6822 [0.6635, 0.6993] | 0.6824 [0.6635, 0.6994] | - |
| 17 | - | 0.6818 [0.6633, 0.6989] | 0.6818 [0.6632, 0.6989] | - |
| std | 0.6475 [0.6283, 0.6663] | 0.6484 [0.6294, 0.6667] | 0.6501 [0.6316, 0.6683] | 0.6939 [0.6691, 0.7176] |
Rows at window 3: reset 2982, mean_regress 3650, decay 3650, reset same rows 1817.

### Table 7. Next-game win beyond Elo: log-loss reduction vs Elo alone [95%] (opponent-adjusted EPA)

| Window | reset (own rows) | mean_regress | decay | reset, same rows (both teams past 8 games) |
|---|---|---|---|---|
| 1 | -0.0002 [-0.0003, -0.0000] | -0.0001 [-0.0003, 0.0001] | -0.0001 [-0.0004, 0.0003] | -0.0000 [-0.0012, 0.0011] |
| 2 | -0.0001 [-0.0004, 0.0001] | -0.0001 [-0.0002, 0.0000] | -0.0001 [-0.0003, 0.0002] | -0.0002 [-0.0013, 0.0008] |
| 3 | -0.0002 [-0.0005, 0.0002] | -0.0001 [-0.0003, 0.0000] | -0.0001 [-0.0003, 0.0001] | -0.0002 [-0.0015, 0.0010] |
| 4 | 0.0005 [-0.0009, 0.0018] | -0.0002 [-0.0005, 0.0002] | -0.0002 [-0.0005, 0.0001] | 0.0006 [-0.0016, 0.0027] |
| 5 | 0.0006 [-0.0010, 0.0021] | -0.0000 [-0.0007, 0.0006] | -0.0001 [-0.0007, 0.0004] | 0.0007 [-0.0019, 0.0031] |
| 6 | 0.0004 [-0.0018, 0.0025] | -0.0001 [-0.0009, 0.0008] | -0.0001 [-0.0009, 0.0005] | 0.0003 [-0.0023, 0.0028] |
| 7 | 0.0002 [-0.0017, 0.0018] | 0.0000 [-0.0008, 0.0008] | -0.0000 [-0.0007, 0.0006] | 0.0004 [-0.0018, 0.0025] |
| 8 | 0.0000 [-0.0014, 0.0014] | -0.0001 [-0.0006, 0.0004] | -0.0001 [-0.0006, 0.0004] | 0.0000 [-0.0014, 0.0014] |
| 9 | -0.0000 [-0.0020, 0.0017] | -0.0002 [-0.0007, 0.0003] | -0.0002 [-0.0006, 0.0002] | - |
| 10 | -0.0006 [-0.0020, 0.0006] | -0.0003 [-0.0006, 0.0001] | -0.0003 [-0.0006, 0.0001] | - |
| 11 | 0.0001 [-0.0032, 0.0030] | -0.0002 [-0.0009, 0.0005] | -0.0002 [-0.0008, 0.0004] | - |
| 12 | 0.0018 [-0.0036, 0.0071] | -0.0001 [-0.0010, 0.0007] | -0.0001 [-0.0009, 0.0006] | - |
| 13 | -0.0007 [-0.0033, 0.0018] | -0.0000 [-0.0010, 0.0010] | -0.0000 [-0.0009, 0.0009] | - |
| 14 | -0.0014 [-0.0026, -0.0001] | 0.0001 [-0.0010, 0.0012] | 0.0002 [-0.0009, 0.0013] | - |
| 15 | -0.0019 [-0.0041, 0.0004] | 0.0002 [-0.0010, 0.0014] | 0.0003 [-0.0010, 0.0015] | - |
| 16 | - | 0.0002 [-0.0010, 0.0014] | 0.0004 [-0.0009, 0.0017] | - |
| 17 | - | 0.0001 [-0.0011, 0.0012] | 0.0003 [-0.0010, 0.0015] | - |
| std | -0.0002 [-0.0005, 0.0001] | -0.0002 [-0.0005, 0.0001] | -0.0002 [-0.0004, -0.0000] | 0.0006 [-0.0023, 0.0032] |
Rows at window 3: reset 2982, mean_regress 3650, decay 3650, reset same rows 1817.

The raw log loss and the ROC-AUC change beyond Elo, plus the same six tables for opponent-adjusted point margin, are in the results JSON (`stronger_arm.table`).

### Table 8. Selections under the shortest-window-inside-the-interval rule

| Feature | Method | Target | Best window | Best score [95% interval] | Chosen (shortest inside) | Chosen score |
|---|---|---|---|---|---|---|
| epa | reset | margin_raw | 15 | 0.2058 [0.1438, 0.2650] | 5 | 0.1449 |
| epa | reset | margin_beyond_elo | 14 | 0.0038 [-0.0074, 0.0122] | 1 | 0.0011 |
| epa | reset | win_raw_auc | 13 | 0.7067 [0.6707, 0.7393] | 5 | 0.6806 |
| epa | reset | win_raw_logloss | 12 | 0.6219 [0.5998, 0.6451] | 5 | 0.6373 |
| epa | reset | win_beyond_elo_logloss_gain | 12 | 0.0018 [-0.0036, 0.0071] | 1 | -0.0002 |
| epa | mean_regress | margin_raw | 17 | 0.1504 [0.1341, 0.1654] | 9 | 0.1358 |
| epa | mean_regress | margin_beyond_elo | 10 | 0.0019 [-0.0005, 0.0041] | 1 | 0.0013 |
| epa | mean_regress | win_raw_auc | 16 | 0.6822 [0.6635, 0.6993] | 6 | 0.6641 |
| epa | mean_regress | win_raw_logloss | 16 | 0.6375 [0.6269, 0.6488] | 6 | 0.6466 |
| epa | mean_regress | win_beyond_elo_logloss_gain | 16 | 0.0002 [-0.0010, 0.0014] | 1 | -0.0001 |
| epa | decay | margin_raw | 17 | 0.1486 [0.1317, 0.1647] | 9 | 0.1326 |
| epa | decay | margin_beyond_elo | 10 | 0.0021 [-0.0005, 0.0045] | 1 | 0.0015 |
| epa | decay | win_raw_auc | 16 | 0.6824 [0.6635, 0.6994] | 7 | 0.6657 |
| epa | decay | win_raw_logloss | 16 | 0.6372 [0.6265, 0.6487] | 6 | 0.6478 |
| epa | decay | win_beyond_elo_logloss_gain | 16 | 0.0004 [-0.0009, 0.0017] | 1 | -0.0001 |
| epa | reset_same_rows | margin_raw | std | 0.1698 [0.1443, 0.1933] | 5 | 0.1537 |
| epa | reset_same_rows | margin_beyond_elo | 8 | 0.0019 [-0.0016, 0.0049] | 1 | 0.0007 |
| epa | reset_same_rows | win_raw_auc | std | 0.6939 [0.6691, 0.7176] | 4 | 0.6731 |
| epa | reset_same_rows | win_raw_logloss | std | 0.6294 [0.6135, 0.6463] | 4 | 0.6410 |
| epa | reset_same_rows | win_beyond_elo_logloss_gain | 5 | 0.0007 [-0.0019, 0.0031] | 1 | -0.0000 |
| margin | reset | margin_raw | 15 | 0.2045 [0.1422, 0.2642] | 5 | 0.1444 |
| margin | reset | margin_beyond_elo | 14 | 0.0036 [-0.0074, 0.0121] | 1 | 0.0013 |
| margin | reset | win_raw_auc | 13 | 0.7080 [0.6722, 0.7404] | 5 | 0.6810 |
| margin | reset | win_raw_logloss | 12 | 0.6208 [0.5984, 0.6440] | 5 | 0.6369 |
| margin | reset | win_beyond_elo_logloss_gain | 12 | 0.0022 [-0.0036, 0.0076] | 1 | -0.0002 |
| margin | mean_regress | margin_raw | 17 | 0.1520 [0.1358, 0.1675] | 9 | 0.1372 |
| margin | mean_regress | margin_beyond_elo | 10 | 0.0020 [-0.0006, 0.0042] | 1 | 0.0014 |
| margin | mean_regress | win_raw_auc | 16 | 0.6827 [0.6639, 0.6998] | 6 | 0.6662 |
| margin | mean_regress | win_raw_logloss | 16 | 0.6367 [0.6260, 0.6481] | 6 | 0.6456 |
| margin | mean_regress | win_beyond_elo_logloss_gain | 15 | 0.0003 [-0.0010, 0.0016] | 1 | -0.0001 |
| margin | decay | margin_raw | 17 | 0.1501 [0.1331, 0.1664] | 9 | 0.1341 |
| margin | decay | margin_beyond_elo | 10 | 0.0021 [-0.0006, 0.0045] | 1 | 0.0016 |
| margin | decay | win_raw_auc | 16 | 0.6827 [0.6639, 0.6998] | 6 | 0.6642 |
| margin | decay | win_raw_logloss | 16 | 0.6365 [0.6257, 0.6482] | 6 | 0.6468 |
| margin | decay | win_beyond_elo_logloss_gain | 16 | 0.0005 [-0.0009, 0.0019] | 1 | -0.0000 |
| margin | reset_same_rows | margin_raw | std | 0.1710 [0.1453, 0.1948] | 5 | 0.1523 |
| margin | reset_same_rows | margin_beyond_elo | 8 | 0.0019 [-0.0017, 0.0048] | 1 | 0.0008 |
| margin | reset_same_rows | win_raw_auc | std | 0.6942 [0.6699, 0.7184] | 4 | 0.6706 |
| margin | reset_same_rows | win_raw_logloss | std | 0.6286 [0.6128, 0.6453] | 4 | 0.6420 |
| margin | reset_same_rows | win_beyond_elo_logloss_gain | std | 0.0007 [-0.0024, 0.0033] | 1 | -0.0002 |

**Answer:**
- **Raw targets.** Prediction improves steadily with window length; under the carry methods it peaks at 16-17 games. The shortest window inside the best one's interval is 9 games for margin and 6-7 games for win (6 under `mean_regress`). On the same rows under `reset` (windows up to 8 games and season-to-date), season-to-date is best and the shortest window inside its interval is 5 for margin and 4 for win. A 3-game window is clearly worse than the longer ones. Under `mean_regress`, window 3 scores R² 0.091 [0.076, 0.104] against 0.150 [0.134, 0.165] for the best, and ROC-AUC 0.631 against 0.682.
- **Beyond Elo.** No window, method or feature adds a measurable amount. The largest margin gains are about 0.002 in R², and every interval includes zero. The win log-loss reductions are within ±0.0004 of zero under the carry methods. The rule returns window 1 here only because every window, window 1 included, sits inside the best one's interval.
- **Opponent-adjusted point margin** matches opponent-adjusted EPA per play to within the intervals on every target.

**Replication answer compared with stronger answer:** the replication's 6 games agrees with the stronger arm's win-target answer (6-7) and is shorter than its margin answer (9). The stronger arm adds two things the replication could not show: a single season's interval spans nearly every window, and none of the windows adds to Elo.

### Table 9. Carry methods on the rows `reset` cannot score (margin beyond Elo, out-of-fold R² [95%])

| Window | Method | Rows reset cannot score | R^2 beyond Elo [95%] |
|---|---|---|---|
| 3 | mean_regress | 1346 | 0.0026 [-0.0024, 0.0058] |
| 3 | decay | 1346 | 0.0035 [-0.0034, 0.0087] |
| 6 | mean_regress | 2766 | 0.0021 [-0.0009, 0.0042] |
| 6 | decay | 2766 | 0.0027 [-0.0014, 0.0060] |
| 9 | mean_regress | 4106 | 0.0031 [0.0001, 0.0057] |
| 9 | decay | 4106 | 0.0032 [-0.0005, 0.0066] |
| std | mean_regress | 450 | 0.0001 [-0.0110, 0.0022] |
| std | decay | 450 | -0.0004 [-0.0127, 0.0044] |

On the early-season rows that `reset` leaves blank, the carried windows predict about as well beyond Elo as they do elsewhere, which is close to zero. Only `mean_regress` at 9 games has an interval just above zero. They do no harm, and they give the board a value for every team from week 1. `mean_regress` and `decay` cannot be told apart anywhere in this study.

## 4. Combined-score weights for the board

**Components** for each team, window and game, all from earlier games:
- **form:** opponent-adjusted EPA/play over the window;
- **trend:** form minus the team's season-to-date form;
- **residual:** mean of (actual margin minus Elo's expected margin) over the window;
- **Elo change:** the sum of the team's Elo updates over the window.

Each is computed under the given season-boundary method and standardised across teams within each season-week. The study used season-week, the NFL's league date, rather than calendar date, and required at least 10 teams. Where every team's trend is exactly zero (the window equals season-to-date), trend is set to 0 rather than left missing.

**Fitting:** a 0.05-step grid of the four weights summing to 1 (1,771 weightings), plus a non-negative regression (exact, by enumerating all active sets). Within each leave-one-season-out fold, the linear map from combined score to target is fitted on training seasons only. The score is the pooled held-out R² of next-game margin beyond Elo. The mean of the next 3 games' margin beyond Elo (same season) is the sensitivity target. "Nested" means the weighting chosen on the training seasons alone in each fold, then scored on the held-out season: an honest estimate of fitting weights at all. Intervals are 95% team-season block bootstrap.

### Table 10. Weights: held-out R² of margin beyond Elo, every method and board window

| Method | Window | Target | Rows | Best grid weights (form/trend/resid/elo) | Best R^2 [95%] | 0.7/0.1/0.1/0.1 R^2 [95%] | Best minus 0.7/0.1/0.1/0.1 [95%] | Equal weights R^2 | Form only R^2 | Nested (chosen on training) R^2 [95%] | Non-negative regression R^2 [95%] | Grid weightings inside best's interval |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| reset | 3 | next_game | 5982 | 0.65/0.00/0.00/0.35 | 0.0006 [-0.0011, 0.0019] | 0.0004 [-0.0011, 0.0015] | 0.0002 [-0.0001, 0.0005] | 0.0001 | 0.0006 | 0.0002 [-0.0016, 0.0015] | -0.0001 [-0.0009, 0.0001] | 1771 of 1771 |
| reset | 3 | next3 | 5086 | 0.00/0.00/1.00/0.00 | 0.0007 [-0.0028, 0.0026] | -0.0003 [-0.0035, 0.0007] | 0.0011 [-0.0024, 0.0046] | -0.0005 | -0.0001 | -0.0006 [-0.0041, 0.0014] | 0.0007 [-0.0028, 0.0026] | 1771 of 1771 |
| reset | 6 | next_game | 4638 | 0.00/0.00/1.00/0.00 | 0.0002 [-0.0015, 0.0014] | -0.0004 [-0.0017, -0.0000] | 0.0006 [-0.0011, 0.0023] | -0.0006 | -0.0002 | -0.0006 [-0.0023, 0.0007] | 0.0002 [-0.0015, 0.0014] | 1771 of 1771 |
| reset | 6 | next3 | 3742 | 1.00/0.00/0.00/0.00 | 0.0004 [-0.0051, 0.0034] | -0.0001 [-0.0053, 0.0023] | 0.0006 [-0.0004, 0.0015] | -0.0011 | 0.0004 | -0.0047 [-0.0106, -0.0018] | -0.0004 [-0.0049, 0.0015] | 1771 of 1771 |
| reset | 9 | next_game | 3242 | 0.25/0.45/0.00/0.30 | 0.0010 [-0.0019, 0.0029] | 0.0004 [-0.0020, 0.0020] | 0.0006 [-0.0006, 0.0017] | 0.0002 | 0.0005 | 0.0000 [-0.0029, 0.0020] | -0.0002 [-0.0020, 0.0004] | 1771 of 1771 |
| reset | 9 | next3 | 2346 | 0.30/0.40/0.00/0.30 | 0.0006 [-0.0066, 0.0045] | -0.0001 [-0.0066, 0.0026] | 0.0007 [-0.0017, 0.0030] | -0.0006 | 0.0001 | -0.0044 [-0.0120, -0.0003] | -0.0001 [-0.0068, 0.0029] | 1771 of 1771 |
| reset | std | next_game | 6878 | 0.45/0.15/0.00/0.40 | 0.0008 [-0.0009, 0.0020] | 0.0005 [-0.0010, 0.0015] | 0.0003 [-0.0001, 0.0007] | 0.0001 | 0.0006 | 0.0004 [-0.0013, 0.0017] | -0.0000 [-0.0010, 0.0004] | 1771 of 1771 |
| reset | std | next3 | 5982 | 0.00/0.95/0.05/0.00 | 0.0009 [-0.0027, 0.0031] | 0.0002 [-0.0032, 0.0021] | 0.0006 [-0.0038, 0.0053] | -0.0004 | 0.0007 | -0.0031 [-0.0072, -0.0005] | 0.0009 [-0.0027, 0.0031] | 1771 of 1771 |
| mean_regress | 3 | next_game | 7326 | 0.45/0.00/0.00/0.55 | 0.0010 [-0.0008, 0.0025] | 0.0007 [-0.0009, 0.0020] | 0.0003 [-0.0002, 0.0008] | 0.0004 | 0.0008 | 0.0007 [-0.0012, 0.0021] | 0.0000 [-0.0008, -0.0000] | 1771 of 1771 |
| mean_regress | 3 | next3 | 6430 | 0.80/0.00/0.00/0.20 | 0.0004 [-0.0031, 0.0022] | 0.0000 [-0.0031, 0.0014] | 0.0004 [-0.0002, 0.0010] | -0.0004 | 0.0004 | -0.0000 [-0.0034, 0.0019] | -0.0001 [-0.0027, 0.0008] | 1771 of 1771 |
| mean_regress | 6 | next_game | 7326 | 0.40/0.00/0.00/0.60 | 0.0008 [-0.0008, 0.0020] | 0.0004 [-0.0009, 0.0013] | 0.0004 [-0.0002, 0.0010] | 0.0000 | 0.0005 | 0.0004 [-0.0013, 0.0016] | -0.0003 [-0.0011, -0.0001] | 1771 of 1771 |
| mean_regress | 6 | next3 | 6430 | 0.50/0.20/0.00/0.30 | 0.0018 [-0.0026, 0.0047] | 0.0011 [-0.0031, 0.0037] | 0.0007 [-0.0001, 0.0015] | 0.0004 | 0.0012 | -0.0002 [-0.0047, 0.0027] | -0.0003 [-0.0028, 0.0002] | 1771 of 1771 |
| mean_regress | 9 | next_game | 7326 | 0.25/0.25/0.00/0.50 | 0.0020 [-0.0003, 0.0038] | 0.0012 [-0.0007, 0.0027] | 0.0008 [-0.0002, 0.0018] | 0.0010 | 0.0011 | 0.0012 [-0.0010, 0.0031] | 0.0000 [-0.0008, -0.0000] | 1771 of 1771 |
| mean_regress | 9 | next3 | 6430 | 0.40/0.30/0.00/0.30 | 0.0035 [-0.0017, 0.0075] | 0.0022 [-0.0026, 0.0056] | 0.0013 [-0.0005, 0.0032] | 0.0015 | 0.0021 | 0.0016 [-0.0040, 0.0056] | -0.0002 [-0.0026, -0.0001] | 1771 of 1771 |
| mean_regress | std | next_game | 7326 | 0.10/0.45/0.00/0.45 | 0.0010 [-0.0008, 0.0024] | 0.0005 [-0.0010, 0.0015] | 0.0005 [-0.0003, 0.0014] | 0.0002 | 0.0006 | 0.0007 [-0.0011, 0.0021] | -0.0001 [-0.0009, 0.0002] | 1771 of 1771 |
| mean_regress | std | next3 | 6430 | 0.25/0.60/0.00/0.15 | 0.0008 [-0.0029, 0.0030] | 0.0003 [-0.0030, 0.0021] | 0.0005 [-0.0002, 0.0011] | -0.0003 | 0.0006 | -0.0025 [-0.0060, -0.0002] | 0.0006 [-0.0025, 0.0024] | 1771 of 1771 |
| decay | 3 | next_game | 7326 | 0.45/0.00/0.00/0.55 | 0.0010 [-0.0008, 0.0025] | 0.0007 [-0.0009, 0.0020] | 0.0004 [-0.0001, 0.0008] | 0.0003 | 0.0008 | 0.0006 [-0.0012, 0.0021] | 0.0000 [-0.0008, -0.0000] | 1771 of 1771 |
| decay | 3 | next3 | 6430 | 0.80/0.00/0.00/0.20 | 0.0004 [-0.0031, 0.0022] | 0.0000 [-0.0031, 0.0014] | 0.0004 [-0.0002, 0.0009] | -0.0004 | 0.0004 | -0.0000 [-0.0034, 0.0019] | -0.0000 [-0.0026, 0.0010] | 1771 of 1771 |
| decay | 6 | next_game | 7326 | 0.40/0.00/0.00/0.60 | 0.0008 [-0.0008, 0.0020] | 0.0004 [-0.0009, 0.0013] | 0.0004 [-0.0002, 0.0010] | 0.0001 | 0.0005 | 0.0004 [-0.0014, 0.0016] | -0.0002 [-0.0009, 0.0000] | 1771 of 1771 |
| decay | 6 | next3 | 6430 | 0.45/0.25/0.00/0.30 | 0.0018 [-0.0026, 0.0048] | 0.0011 [-0.0031, 0.0037] | 0.0007 [-0.0003, 0.0017] | 0.0005 | 0.0012 | -0.0002 [-0.0047, 0.0029] | -0.0003 [-0.0029, 0.0002] | 1771 of 1771 |
| decay | 9 | next_game | 7326 | 0.20/0.30/0.00/0.50 | 0.0021 [-0.0002, 0.0040] | 0.0012 [-0.0007, 0.0027] | 0.0009 [-0.0002, 0.0020] | 0.0011 | 0.0011 | 0.0013 [-0.0010, 0.0033] | -0.0000 [-0.0008, -0.0000] | 1771 of 1771 |
| decay | 9 | next3 | 6430 | 0.30/0.35/0.00/0.35 | 0.0041 [-0.0015, 0.0083] | 0.0023 [-0.0026, 0.0057] | 0.0018 [-0.0005, 0.0042] | 0.0019 | 0.0021 | 0.0021 [-0.0037, 0.0064] | -0.0002 [-0.0027, -0.0001] | 1771 of 1771 |
| decay | std | next_game | 7326 | 0.10/0.45/0.00/0.45 | 0.0010 [-0.0008, 0.0024] | 0.0005 [-0.0010, 0.0015] | 0.0005 [-0.0003, 0.0014] | 0.0002 | 0.0006 | 0.0007 [-0.0011, 0.0021] | -0.0001 [-0.0009, 0.0002] | 1771 of 1771 |
| decay | std | next3 | 6430 | 0.25/0.60/0.00/0.15 | 0.0008 [-0.0029, 0.0030] | 0.0003 [-0.0030, 0.0021] | 0.0005 [-0.0002, 0.0011] | -0.0003 | 0.0006 | -0.0025 [-0.0060, -0.0002] | 0.0006 [-0.0025, 0.0024] | 1771 of 1771 |

**How flat the top is:** at every method, window and target, all 1,771 grid weightings lie inside the 95% interval of the best one. At every window, the best weighting minus 0.7/0.1/0.1/0.1 has an interval that includes zero. The nested procedure (weights chosen on training seasons) scores at or below the fixed weightings. The full-sample non-negative regression puts all its weight on the residual, or on nothing, which is what fitting looks like when there is no signal. **No weighting predicts margin beyond Elo better than zero with any confidence**, which matches the stronger arm's finding that recent form adds nothing to Elo.

**Recommended weights (best held-out score, `mean_regress`, next-game target):**
- 3 games: form 0.45, trend 0, residual 0, Elo change 0.55, R² 0.0010 [-0.0008, 0.0025]
- 6 games: 0.40/0/0/0.60, R² 0.0008 [-0.0008, 0.0020]
- 9 games: 0.25/0.25/0/0.50, R² 0.0020 [-0.0003, 0.0038]

0.7/0.1/0.1/0.1 scores 0.0007, 0.0004 and 0.0012 at the same windows, and the differences have intervals that include zero. These "best" weights are the top of a flat surface, not a measured improvement. Keeping the NBA board's 0.7/0.1/0.1/0.1 at all three windows is equally supported by the data, and it is simpler to explain.

## 5. Flag detection check (SIMULATED detection rates)

**These rates are simulations, a methods check, not published data.** For each candidate flag in #227, the test is the one the board would run at the window's typical count: the league rate per game times the window's games. The "plausible effect" is the 90th percentile of the flag's absolute deviation across team-seasons 2012-2025. That range includes sampling noise, so the effect sizes are generous and the detection rates are optimistic. Each cell is the share of 10,000 simulated windows, drawn with that effect, in which the test is significant at two-sided p < 0.05. Season-to-date uses its typical count, the median team's 8 earlier games.

### Table 11. Flag tests, plausible effects and simulated detection rates (n = typical count)

| Flag | Test | Plausible effect (90th pct team-season deviation) | Count per game | Simulated detection: 3 | 6 | 9 | season-to-date (8) | 17 |
|---|---|---|---|---|---|---|---|---|
| One-score record vs expected | binomial z: wins in one-score games (|margin| <= 8, ties half) vs 0.5 | 0.333 | 0.52 | 0.00 (n=2) | 0.00 (n=3) | 0.40 (n=5) | 0.49 (n=4) | 0.54 (n=9) |
| Pythagorean vs actual | binomial z: wins vs the Pythagorean expectation (exponent 2.37; tested at p0 = 0.5) | 0.136 | 1.00 | 0.00 (n=3) | 0.07 (n=6) | 0.11 (n=9) | 0.16 (n=8) | 0.20 (n=17) |
| Fumble-recovery rate | binomial z: share of all fumbles in the team's games recovered by the team vs 0.5 | 0.157 | 2.43 | 0.05 (n=7) | 0.19 (n=15) | 0.33 (n=22) | 0.32 (n=19) | 0.57 (n=41) |
| Opponent field-goal % | binomial z: opponents' field goals made vs the league rate (0.846) | 0.106 | 1.95 | 0.00 (n=6) | 0.00 (n=12) | 0.00 (n=18) | 0.00 (n=16) | 0.53 (n=33) |
| Turnover margin vs season level | Poisson z: window takeaways minus giveaways vs the team's season level (variance 2 x league giveaways per game) | 0.875 | 1.00 | 0.16 (n=3) | 0.29 (n=6) | 0.37 (n=9) | 0.29 (n=8) | 0.58 (n=17) |
| Blowout skew | binomial z: share of games decided by 17+ points vs the league rate (0.259) | 0.179 | 1.00 | 0.08 (n=3) | 0.24 (n=6) | 0.34 (n=9) | 0.24 (n=8) | 0.49 (n=17) |
| Opponent strength | z: mean opponent pregame Elo vs the league mean that season, game-to-game SD within team-seasons | 35.4 | 1.00 | 0.08 (n=3) | 0.12 (n=6) | 0.15 (n=9) | 0.14 (n=8) | 0.23 (n=17) |
| Home share | binomial z: home games vs 0.5 | 0.0294 | 1.00 | 0.00 (n=3) | 0.03 (n=6) | 0.04 (n=9) | 0.07 (n=8) | 0.05 (n=17) |
| Rest / bye share | z: mean rest-day difference (team minus opponent, within season) vs 0, game-to-game SD within team-seasons | 0.738 | 1.00 | 0.08 (n=3) | 0.11 (n=6) | 0.14 (n=9) | 0.13 (n=8) | 0.22 (n=17) |
| Key players missing | binomial z: key player-games missed vs the league rate (0.093); key = the team-season's 22 players with most snaps | 0.0539 | 22.00 | 0.38 (n=66) | 0.57 (n=132) | 0.69 (n=198) | 0.67 (n=176) | 0.91 (n=374) |

Notes:
- **Opponent field-goal %:** with a league make rate of 0.846, a binomial test cannot reach significance until about 22 attempts, even if every kick is made. Its detection is zero below a full-season window.
- **Home share and rest/bye:** these are schedule facts, not noisy outcomes, and team-seasons barely differ (home share deviation 0.03). A significance test adds nothing; they are context.
- **Key players missing:** this check defines key players as the team-season's 22 players with the most snaps, with a missed game meaning no snaps recorded. That is simpler than #226's definition (top snap share at the position, "Out" or no snaps). Player-games are not independent (one injury spans several games), so this binomial test overstates detection.

**Lowest window where simulated detection reaches 80% (and 50%):**

- one_score: first window >= 0.8: none; >= 0.5: 15
- pythagorean: first window >= 0.8: none; >= 0.5: none
- fumble_recovery: first window >= 0.8: none; >= 0.5: 15
- opp_fg_pct: first window >= 0.8: none; >= 0.5: 17
- turnover_margin: first window >= 0.8: none; >= 0.5: 15
- blowout_skew: first window >= 0.8: none; >= 0.5: none
- opponent_strength: first window >= 0.8: none; >= 0.5: none
- home_share: first window >= 0.8: none; >= 0.5: none
- rest_bye: first window >= 0.8: none; >= 0.5: none
- key_players_missing: first window >= 0.8: 12; >= 0.5: 6

## 6. Availability data check

Share of regular-season team-weeks with any rows: injury reports (`nflreadr::load_injuries()`) by season, week and team; snap counts (`nflreadr::load_snap_counts()`) by game and team.

### Table 12. Coverage by season

| Season | Team-weeks | Injury reports: with rows (share) | Snap counts: with rows (share) |
|---|---|---|---|
| 2012 | 512 | 512 (1.000) | 0 (0.000) |
| 2013 | 512 | 511 (0.998) | 512 (1.000) |
| 2014 | 512 | 512 (1.000) | 512 (1.000) |
| 2015 | 512 | 512 (1.000) | 512 (1.000) |
| 2016 | 512 | 512 (1.000) | 512 (1.000) |
| 2017 | 512 | 511 (0.998) | 512 (1.000) |
| 2018 | 512 | 512 (1.000) | 512 (1.000) |
| 2019 | 512 | 512 (1.000) | 512 (1.000) |
| 2020 | 512 | 511 (0.998) | 512 (1.000) |
| 2021 | 544 | 544 (1.000) | 544 (1.000) |
| 2022 | 542 | 539 (0.994) | 542 (1.000) |
| 2023 | 544 | 543 (0.998) | 544 (1.000) |
| 2024 | 544 | 543 (0.998) | 544 (1.000) |
| 2025 | 544 | 544 (1.000) | 544 (1.000) |

- **Injury reports:** at least 99.4% of team-weeks from 2012 to 2025. A team-week with no row can simply mean nobody was listed, so this study counts 99% or more as covered.
- **Snap counts:** none for 2012 (`nflreadr` returns no rows); 100% from 2013 to 2025.
- **The pipeline's own caches** (`CACHE_INJURY_DATA`, `CACHE_SNAP_COUNTS`, copied into this checkout) hold the 2026 season only. They cover every completed 2026 team-week in weeks 1-10. Week 11 snap counts cover 24 of 26 team-weeks (92%), probably games not yet loaded when the cache was written.
- **Verdict:** a "key players missing" value is supportable from **2013** on, and for the current season, using both sources. Per section 5, though, its significance test reaches 80% detection only from 12 games, and that test overstates detection. The flag can ship as a raw value, without a significance badge at the board's windows.

## 7. Recommendations

1. **Board windows:** **3, 6 and 9 games**, with 9 rather than season-to-date as the third. The study supports 6 (the shortest window inside the best one's interval for next-game win) and 9 (the same for next-game margin). It does not support 3 on predictive grounds: 3 is clearly less predictive than 6 or 9. Keep 3 only as the board's short "recent games" view and label it the noisiest. Season-to-date scores below 9 overall because it is short early in the season.
2. **Season start:** **carry last season's games across the boundary, using `mean_regress`, labelled on the page.** It scores every team from week 1 (2,580 of 2,580 weeks 1-6 team-games, against 0 under `reset` for a 6-game window) and loses nothing in accuracy. `decay` is statistically identical. Do not leave teams unranked.
3. **Combined-score weights:** the held-out surface is flat and no weighting beats zero beyond Elo. The best held-out weightings are 0.45/0/0/0.55 (3 games), 0.40/0/0/0.60 (6) and 0.25/0.25/0/0.50 (9), in form/trend/residual/Elo-change order. Each is indistinguishable from 0.7/0.1/0.1/0.1. Recommendation: fix the best held-out weights above in `config.R` with this study's commit, as #226 decision 4 asks, and state in the methods panel that the surface is flat and the combined score does not predict beyond Elo. Keeping 0.7/0.1/0.1/0.1 is an equally supported choice if the owner prefers parity with the NBA board.
4. **Flags per window:**
   - **3, 6, 9 and season-to-date:** no significance badge for any flag. None reaches 80% simulated detection.
   - **Raw values:** opponent strength, home share and rest/bye are context only, at every window. "Key players missing" is supportable from 2013 data; ship it as a raw value without a badge at the board's windows.
   - **Full-season (17-game) views:** turnover margin, fumble recovery, one-score record and opponent FG% reach only 49-58%, so even there they are not supported at 80%. Pythagorean, blowout skew, opponent strength and home/rest never reach 50%.
5. **`ROLLING_WINDOW_SIZE` (now 4):** **9**, paired with `OFFSEASON_METHOD = "mean_regress"`. Nine is the shortest window inside the best one's interval for next-game margin, and carrying over gives it a value from week 1. If `reset` is kept instead, 4-5 is what the same-rows comparison supports, so 4 can stay.
6. **`OFFSEASON_METHOD` (now `reset`):** **`mean_regress`**. Other models read both settings, so this study does not change them. Changing them is a separate PR, and those models should be re-checked by their own backtests when it is made.

## Reproducibility

- `Rscript tools/rolling_window_study.R` (seed 20261125; 2,000 bootstrap resamples; 10,000 simulations per flag and window). Missing data files are downloaded into `cache/` with `nflreadr`.
- The final run started from a clean R session (`Rscript --vanilla`) and finished with exit code 0 in 3.8 minutes. Outputs: `docs/research/rolling_window_study_results.json` and `cache/rolling_window_study_results.rds`.
- Main code locations in `tools/rolling_window_study.R`:
  - per-game features: lines 261-266;
  - window engine and the three methods: `window_value()` and `std_value()`, lines 273-320;
  - stronger-arm window loop: line 420;
  - replication: `run_replication()`, line 503;
  - weights: `fit_weights()`, line 584;
  - flags: line 728;
  - availability: line 659.
