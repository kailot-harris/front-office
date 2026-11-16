# NFL Matchup Game Detail Plan (v2) — Baseline Verification & Decision D2 Findings

**Date:** 2026-11-15  
**Repository:** `kailot-harris/NFL_analytics` (`origin/main`)  
**Companion Spec:** `NFL_MATCHUP_GAME_DETAIL_PLAN.md` (v2)

---

## 1. Resolution of Open Section 1 Baseline Checks

### 1.1 Where the Zero-Betting Term Guard Lives
- **Finding:** `web/tests/drift/content-drift.test.ts` checks hardcoded numeric literals in UI source files against published JSON datasets (`margin_sigma`, `home_field_adv`, `n_simulations`, `cap_ceiling`, `ensemble_weights`, `brier_baseline`). It does **not** contain a forbidden-term list.
- **Actual Guard Locations:**
  1. **Platform Pre-Flight Gate (`front-office-gate` — `scripts/fo_gate.ps1:113-146`):** Scans `web/**/*.{ts,tsx,js,json}` (excluding `package-lock.json`, `node_modules`, `.next`, `out`, `test-results`) against:
     `value_bets\.json`, `The Odds API`, `odds_api`, `fractional Kelly`, `closing line value`, `sportsbook`, `sharp_book`.
  2. **Repository PR Governance Checklist (`.github/PULL_REQUEST_TEMPLATE.md:6-8`):** Explicitly bans `odds`, `spreads`, `moneyline`, `books`, `staking`, `Kelly`, `sportsbook`.
- **Gap & Remediation:** Unlike `NBA Analytics`, `NFL Analytics/web/tests/` currently has no Vitest test scanning published payloads for betting vocabulary, which is how `projected_spread`, `projected_total`, and `key_number_flag` survived in `matchups_current_week.json`. Phase 0 removes those fields, and Phase 1 Issue **3b** (`web/tests/contracts/game-detail.test.ts`) will add an in-repo Vitest term guard.

---

### 1.2 Ridge-Massey Coefficient Decomposition (`tools/ridge_massey_model.R`)
- **Finding:** Confirmed in `tools/ridge_massey_model.R:46-74`. `build_ridge_features()` constructs exactly four predictors (`diff_raw`, `diff_prior`, `diff_raw_gp`, `diff_prior_gp`) and `fit_ridge_massey()` fits a pure $L_2$ ridge regression (`glmnet::cv.glmnet(x, y, alpha = 0, nfolds = 5)`) with a deterministic local seed (`set.seed(20260917)`).
- **2026 Walk-Forward Fit (`train_games` = `2003–2025`, `N = 5,535`, `lambda.min = 0.4203382`):**

| Term | Feature Definition | Learned Coefficient (`s = "lambda.min"`) |
|---|---|---:|
| `(Intercept)` | Learned Home-Field Advantage ($\beta_0$) | `+2.242771` |
| `diff_raw` | $\text{home\_raw} - \text{away\_raw}$ | `+0.191125` |
| `diff_prior` | $\text{home\_prior} - \text{away\_prior}$ | `+0.090944` |
| `diff_raw_gp` | $(\text{home\_raw} - \text{away\_raw}) \cdot \overline{gp}$ | `+0.010141` |
| `diff_prior_gp` | $(\text{home\_prior} - \text{away\_prior}) \cdot \overline{gp}$ | `+0.000352` |

- **Exactness Check on All 2026 Games:**
  Decomposing `predict(fit, newx, s = "lambda.min")` into:
  $$\underbrace{\beta_0}_{\text{Ridge HFA}} + \underbrace{(\beta_{\text{raw}} + \beta_{\text{raw\_gp}} \cdot \overline{gp})(\text{home\_raw} - \text{away\_raw})}_{\text{Current-Season EPA Step}} + \underbrace{(\beta_{\text{prior}} + \beta_{\text{prior\_gp}} \cdot \overline{gp})(\text{home\_prior} - \text{away\_prior})}_{\text{Pre-Season Prior Step}}$$
  matches `predict(fit, newx, s = "lambda.min")` across all `145` 2026 games to **`1.78e-15`** (IEEE-754 double precision).

---

### 1.3 Silent Bug Discovered in `grade_walkforward_games()` (`tools/backtest_common.R:304,344`)
- **What Happens Today:**
  - In `team_ratings_engine.R:430-434` (upcoming games), the pipeline builds `hist_games` across all historical seasons `< 2026` (`N = 5,535`) and fits `fit_ridge_massey(hist_games)`.
  - In `tools/backtest_common.R:304` (`grade_walkforward_games()`, called by `accuracy_tracker.R` to grade completed 2026 games), it builds `games` with `calibration_seasons = season` (`2026` only, `145` rows) and passes that single-season table to `predict_ridge_massey_walkforward(games)` (`tools/backtest_common.R:344`).
  - Inside `predict_ridge_massey_walkforward()` (`tools/ridge_massey_model.R:89-98`), `train_idx <- which(games$season < s)` finds **`0` rows** (`length(train_idx) < 100`), so it silently falls back to `fallback_margin()` (`RATING_SHRINKAGE_GAMES_K = 3.6` hand-picked shrinkage blend) for every completed 2026 game!
- **Impact on 2026 Completed Games (`N = 145`, Weeks 1–10):**
  - Current `grade_walkforward_games()` (`K = 3.6` fallback + Prob-Avg + Fatigue): `91/145` (`62.759%`), **`Brier = 0.228413`**, **`LogLoss = 0.644762`**.
  - True `< 2026` Ridge-Massey + Elo (`Margin-Avg, No Fatigue`): `89/145` (`61.379%`), **`Brier = 0.224160`** (`-0.00425` better), **`LogLoss = 0.637886`** (`-0.00688` better).
- **Resolution:** Extracting the single shared forecast function in Phase 2 Issue **2-1** eliminates this bug automatically.

---

## 2. Four-Variant Walk-Forward Evaluation for Decision D2 (Section 5.1)

### 2.1 Out-of-Sample Summary Table (`2003–2025`, `N = 5,535` Non-Tied Regular-Season Games)

All four variants use identical strictly pre-week EPA snapshots (`game_date < min(week_games$gameday)`), out-of-sample seasonal Ridge-Massey fits (`season < s`), sequential pre-game Elo ratings (`ELO_K_FACTOR = 20`), and pre-week QB-backup flags (`QB_INJURY_RATING_PENALTY_PTS = 1.60`, `NFL_MARGIN_SIGMA = 14.60`), where `ridge_m = ridge_base + qb_shift` and `elo_m = elo_margin_pts + qb_shift`:

| Variant | Formula | N (`2003–2025`) | Accuracy | Brier Score (↓) | Log Loss (↓) |
|---|---|---:|---:|---:|---:|
| **1. Margin-Avg (No Fatigue)** | `pnorm((0.5 * ridge_m + 0.5 * elo_m) / 14.60)` | 5,535 | **64.083%** | **0.222670** | 0.636073 |
| **2. Margin-Avg (+ Fatigue)** | `pnorm((0.5 * ridge_m + 0.5 * (elo_m + fat)) / 14.60)` | 5,535 | 64.047% | 0.222843 | 0.636437 |
| **3. Prob-Avg (No Fatigue)** | `0.5 * pnorm(ridge_m / 14.60) + 0.5 * pnorm(elo_m / 14.60)` | 5,535 | **64.083%** | 0.222710 | **0.636057** |
| **4. Prob-Avg (+ Fatigue)** | `0.5 * pnorm(ridge_m / 14.60) + 0.5 * pnorm((elo_m + fat) / 14.60)` | 5,535 | 64.047% | 0.222867 | 0.636382 |

### 2.2 2026 Out-of-Sample Season-to-Date (`Weeks 1–10`, `N = 145` Completed Games)

| Variant | N (`2026`) | Correct | Accuracy | Brier Score (↓) | Log Loss (↓) |
|---|---:|---:|---:|---:|---:|
| `0. Current Buggy Walk-Forward (K = 3.6 Fallback)` | 145 | 91 | 62.759% | 0.228413 | 0.644762 |
| **1. Margin-Avg (No Fatigue)** | 145 | 89 | 61.379% | **0.224160** | **0.637886** |
| **2. Margin-Avg (+ Fatigue)** | 145 | 89 | 61.379% | 0.224973 | 0.639533 |
| **3. Prob-Avg (No Fatigue)** | 145 | 89 | 61.379% | 0.224333 | 0.638335 |
| **4. Prob-Avg (+ Fatigue)** | 145 | 89 | 61.379% | 0.225214 | 0.640151 |

### 2.3 10-Bin Calibration Tables (`2003–2025`, `N = 5,535`)

#### Variant 1: Margin-Avg (No Fatigue) — *Current Live Upcoming Formula*
| Probability Bin | Games (`N`) | Mean Predicted | Realized Win Rate | Abs Calibration Gap |
|---|---:|---:|---:|---:|
| `(0.1, 0.2]` | 19 | 0.1721 | 0.3158 | 0.1437 |
| `(0.2, 0.3]` | 170 | 0.2625 | 0.2235 | 0.0390 |
| `(0.3, 0.4]` | 501 | 0.3591 | 0.3313 | 0.0278 |
| `(0.4, 0.5]` | 1,124 | 0.4555 | 0.4244 | 0.0311 |
| `(0.5, 0.6]` | 1,547 | 0.5507 | 0.5598 | 0.0091 |
| `(0.6, 0.7]` | 1,339 | 0.6458 | 0.6580 | 0.0122 |
| `(0.7, 0.8]` | 673 | 0.7411 | 0.7905 | 0.0494 |
| `(0.8, 0.9]` | 159 | 0.8354 | 0.8742 | 0.0388 |
| `(0.9, 1.0]` | 3 | 0.9225 | 0.6667 | 0.2558 |

#### Variant 2: Margin-Avg (+ Fatigue)
| Probability Bin | Games (`N`) | Mean Predicted | Realized Win Rate | Abs Calibration Gap |
|---|---:|---:|---:|---:|
| `(0.1, 0.2]` | 18 | 0.1704 | 0.3889 | 0.2185 |
| `(0.2, 0.3]` | 165 | 0.2618 | 0.2182 | 0.0436 |
| `(0.3, 0.4]` | 490 | 0.3592 | 0.3224 | 0.0368 |
| `(0.4, 0.5]` | 1,103 | 0.4555 | 0.4243 | 0.0312 |
| `(0.5, 0.6]` | 1,540 | 0.5505 | 0.5623 | 0.0118 |
| `(0.6, 0.7]` | 1,356 | 0.6456 | 0.6534 | 0.0078 |
| `(0.7, 0.8]` | 694 | 0.7409 | 0.7723 | 0.0314 |
| `(0.8, 0.9]` | 164 | 0.8349 | 0.8902 | 0.0553 |
| `(0.9, 1.0]` | 5 | 0.9166 | 0.8000 | 0.1166 |

#### Variant 3: Prob-Avg (No Fatigue)
| Probability Bin | Games (`N`) | Mean Predicted | Realized Win Rate | Abs Calibration Gap |
|---|---:|---:|---:|---:|
| `(0.1, 0.2]` | 15 | 0.1771 | 0.4000 | 0.2229 |
| `(0.2, 0.3]` | 161 | 0.2641 | 0.2236 | 0.0405 |
| `(0.3, 0.4]` | 502 | 0.3590 | 0.3267 | 0.0323 |
| `(0.4, 0.5]` | 1,136 | 0.4555 | 0.4234 | 0.0321 |
| `(0.5, 0.6]` | 1,556 | 0.5506 | 0.5585 | 0.0079 |
| `(0.6, 0.7]` | 1,353 | 0.6460 | 0.6630 | 0.0170 |
| `(0.7, 0.8]` | 661 | 0.7407 | 0.7897 | 0.0490 |
| `(0.8, 0.9]` | 149 | 0.8315 | 0.8725 | 0.0410 |
| `(0.9, 1.0]` | 2 | 0.9025 | 1.0000 | 0.0975 |

#### Variant 4: Prob-Avg (+ Fatigue)
| Probability Bin | Games (`N`) | Mean Predicted | Realized Win Rate | Abs Calibration Gap |
|---|---:|---:|---:|---:|
| `(0.1, 0.2]` | 15 | 0.1775 | 0.4000 | 0.2225 |
| `(0.2, 0.3]` | 162 | 0.2653 | 0.2222 | 0.0431 |
| `(0.3, 0.4]` | 483 | 0.3598 | 0.3188 | 0.0410 |
| `(0.4, 0.5]` | 1,116 | 0.4554 | 0.4238 | 0.0316 |
| `(0.5, 0.6]` | 1,554 | 0.5505 | 0.5624 | 0.0119 |
| `(0.6, 0.7]` | 1,356 | 0.6456 | 0.6556 | 0.0100 |
| `(0.7, 0.8]` | 695 | 0.7401 | 0.7755 | 0.0354 |
| `(0.8, 0.9]` | 153 | 0.8328 | 0.8824 | 0.0496 |
| `(0.9, 1.0]` | 1 | 0.9079 | 1.0000 | 0.0921 |

---

## 3. Key Takeaways for Owner Decision D2

1. **Margin-Averaging vs. Probability-Averaging Have Identical Winner Picks:**
   By symmetry of the normal CDF $\Phi(x)$ around $0$ ($\Phi(-x) = 1 - \Phi(x)$), $\frac{a+b}{2} > 0 \iff \frac{\Phi(a/\sigma) + \Phi(b/\sigma)}{2} > 0.5$. Thus `Margin-Avg` and `Prob-Avg` agree on the predicted winner on **100% of games** (`64.083%` without fatigue; `64.047%` with fatigue).
2. **`Margin-Avg (No Fatigue)` Achieves the Best Brier Score Both Historically (`0.222670`) and in 2026 (`0.224160`):**
   - Adding `fatigue_adj` inside `elo_margin` degrades accuracy (`-2` games on `2003–2025`), Brier score (`0.222670` → `0.222843` on `2003–2025`; `0.224160` → `0.224973` on `2026`), and log loss (`0.636073` → `0.636437` on `2003–2025`; `0.637886` → `0.639533` on `2026`).
   - Why: `calculate_travel_fatigue_vec()` (`fatigue_engine.R:210-241`) uses ported heuristic weights (`0.35`/`0.15` circadian, `0.40` per 1,000 miles, `1.2`/`2.1` altitude, `1.85` short week from WNBA) rather than coefficients empirically calibrated on NFL point margins for the Ridge+Elo ensemble.
3. **Implication for the Section 5.2 Points Waterfall:**
   - Selecting **Variant 1 (`Margin-Avg, No Fatigue`)** keeps the exact formula already running in `team_ratings_engine.R` for upcoming games, achieves the lowest Brier score across both `2003–2025` and `2026`, and yields a **5-step exact additive points waterfall** (`ridge_current_epa`, `ridge_prior_epa`, `elo_rating`, `home_field`, `qb_adj` + `rounding`) with zero uncalibrated fatigue noise.
   - Selecting **Variant 2 (`Margin-Avg, + Fatigue`)** adds the 6th `schedule_fatigue` step (`0.5 * fatigue_adj`), at a cost of `+0.000173` Brier on `2003–2025` and `+0.000813` Brier on `2026`.
