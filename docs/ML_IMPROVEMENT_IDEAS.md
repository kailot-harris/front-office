# ML_IMPROVEMENT_IDEAS.md
### Research + empirical prototyping pass — 2026-09-12

## 0. Scope

This is a research/exploration document, **not** a production change. It does not modify
`ml_cv_benchmark.R`, `ML_BENCHMARK_REPORT.md`, or `roster_bottom_up_engine.R`/the production model.
Part 1 is a ranked, sourced list of ideas for improving on the current baseline (`ML_BENCHMARK_REPORT.md`:
LOSO-CV Accuracy 0.639 [0.618, 0.661], ROC-AUC 0.675 [0.651, 0.699], n=1,902 real games, RF/`ranger`,
13-game rolling box-score differentials) against the named WNBA-specific benchmark (Alves & Barbosa 2025,
67.48% accuracy). Part 2 empirically tests the 3 most promising, cheapest-to-test ideas using the exact
same LOSO CV methodology as `ml_cv_benchmark.R`, via a new standalone script, `tools/ml_feature_experiments.R`.

---

## Part 1: Ranked improvement ideas

Each idea states: what it is, why it might help (grounded in literature or a specific real data asset
already in this repo), what data it needs (available now vs. needs new work), and effort/risk.

### 1. Elo-style continuously-updated team rating differential — **HIGH priority, LOW effort**

**What:** A single scalar team-strength rating per team, updated game-by-game via a logistic
win/loss update (`elo_new = elo_old + K*(actual - expected)`, `expected = 1/(1+10^(-diff/400))`),
with a partial regression-to-mean between seasons. The home-minus-away pre-game rating differential
is used as a model feature.

**Why it might help:** Elo-family ratings are one of the best-documented "strong simple baseline"
results in basketball analytics — a from-scratch Elo implementation "outperformed every individual
[ML] model with an accuracy of 65.3%, despite not utilizing any boxscore data" in one NBA study
(Josh Weiner, "Predicting the outcome of NBA games with Machine Learning," Towards Data Science).
FiveThirtyEight's NBA forecasting methodology is built around a similarly continuously-updated Elo/
RAPTOR-blend system (FiveThirtyEight, "How Our NBA Predictions Work"). Critically for WNBA: Elo
updates every single game and needs **no minimum rolling-window history** — a team's rating on game 1
of a new season already reflects everything known through the end of last season (with a mean-regress
haircut), unlike a flat 12/13-game rolling window, which needs ~13 games of *current-season* data
before it has any signal (roughly 30% of a 44-game season). This directly targets the brief's own
question: does a WNBA season this short favor a rating that doesn't need a long window?

**Data needed:** None beyond `data/box_scores_cache.rds` (already used for everything else) — Elo is
computable purely from historical game results (team_id, game_date, winner). No new real-data
dependency.

**Effort/risk:** Low effort (a few dozen lines, no new package). Low risk — it's a well-understood,
widely-replicated technique, and it's an *additive* feature (doesn't replace anything), so worst case
it's redundant with existing rolling features, not actively harmful. **Tested empirically — see Part 2.**

### 2. RAPM-derived team-strength differential — **HIGH priority, MEDIUM effort**

**What:** Aggregate the real possession-level RAPM ratings (`cache/rapm_ratings.rds` / the underlying
`cache/wnba_pbp_cache.rds`, 430 real players, 292,569 real possessions from
`wehoop::load_wnba_stats_possessions()`, per P2's work) up to a team-strength number, and use the
home-minus-away differential as a model feature.

**Why it might help:** This is the single most explicitly flagged opportunity in this repo per
`docs/task_assignments_phase2.md`'s P2 Handoff Notes: real possession-level RAPM exists and is
currently used **nowhere** in the win-prediction model. RAPM is designed to isolate player skill
controlling for teammates/opponents, which raw box-score rolling averages cannot do (a player's box
counting stats are confounded by pace, role, and who else is on the floor). The literature is
explicit that raw (unregularized) plus-minus is a poor *predictor* of future games with limited data,
but "adding regularization greatly improves accuracy," which is exactly what RAPM (vs. raw APM) does
(emergentmind.com / Sill 2010, MIT Sloan Sports Analytics Conference — RAPM "nearly doubl[ed] the
accuracy of traditional APM"). FiveThirtyEight's own model (RAPTOR) is built on a broadly similar
premise: player-level plus-minus-style ratings aggregated to team strength as a predictive signal
alongside box-score features.

**Important caveat found and addressed, not glossed over:** `cache/rapm_ratings.rds` as it currently
exists is a **single rating pooled across all 8 seasons (2019-2026)**. Using it directly as a static
per-team feature for every historical game would leak future information into the past — e.g. a
2019 game's prediction would be informed by a rating partly estimated from that same team's 2024-2026
possessions. This is exactly the kind of look-ahead leakage `GAP_REMEDIATION_PLAN.md`'s no-p-hacking
discipline warns about. **Fix used in Part 2's empirical test:** re-solve the RAPM ridge regression
per LOSO fold, using only the training seasons' possessions (the held-out season's possessions are
excluded entirely before fitting) — this mirrors exactly how the classifier itself is refit per fold.

**Data needed:** Available now — `cache/wnba_pbp_cache.rds` (real, already pulled, no live network
call needed to re-derive fold-safe ratings).

**Effort/risk:** Medium effort (re-solving an 800-900-dimension sparse ridge regression 8 times, one
per fold — computationally cheap in practice, seconds per fold, but requires re-implementing the
team-aggregation logic with a per-fold seasons filter, which `rapm_engine.R`'s existing
`estimate_rapm_ratings()` does not support out of the box — its cache-read path ignores the `seasons`
argument once a cache file exists). Medium risk: it's a static, once-per-season-per-fold rating
(coarser than a true in-season-updating signal), and 2 of 15 teams (Portland Fire, Toronto Tempo) have
zero possession history before their 2026 debut season, requiring a documented league-mean fallback
for those team-fold combinations. **Tested empirically — see Part 2.**

### 3. Recency-weighted (EWMA) rolling averages instead of a flat window — **MEDIUM-HIGH priority, LOW effort**

**What:** Replace the existing flat-window rolling mean (`slide_dbl(x, mean, .before=13, .after=-1)`)
with an exponentially-weighted moving average (EWMA) of the same underlying box-score stats, so more
recent games count more than games from weeks ago, and (unlike the flat window) the average is
well-defined from a team's 2nd game of the season onward rather than needing a long history to fill
the window.

**Why it might help:** This is exactly the brief's own research question: does WNBA's short season
favor a continuously-updating average over a flat window? EWMA/recency-weighting for exactly this
purpose is a documented technique in nearby sports-ML literature — e.g. tennis "momentum" models
combine win probability signals via EWMA feeding an XGBoost classifier (MDPI *AppliedMath* 2025,
"Tennis Game Dynamic Prediction Model Based on Players' Momentum"), and a soccer injury-forecasting
study found recency-weighting (EWMA of training load) measurably improved on flat windows, explicitly
naming "weighting aggregated data by recency" as valuable future work for team-sport outcome models
generally (arXiv:1705.08079 and the *Applications of Fluids* 2021 basketball-adjacent "Improving
Sports Outcome Prediction Process Using Integrating Adaptive Weighted Features," MDPI). Also directly
relevant: `config.R`'s own real, already-run window-size sweep (`window_sweep_3_25_results.rds`) found
the accuracy/AUC curve **non-monotonic** across window sizes 3-25 with no window dominating past
size ~12 — a pattern consistent with the flat window being a genuinely suboptimal shape for this data,
not just an untuned constant.

**Data needed:** None — same underlying box-score columns already used, just a different aggregation.

**Effort/risk:** Low effort (one function, reuses the existing per-team-season grouping). Low risk —
it's a methodology swap on an already-used feature set, not a new/unverified data source; worst case
it under/over-weights recent noise relative to the current tuned window. **Tested empirically — see
Part 2.**

### 4. Opponent-adjusted / strength-of-schedule-adjusted rolling stats — **MEDIUM-HIGH priority, MEDIUM effort**

**What:** Instead of a team's raw rolling box-score averages, adjust them for the quality of the
opponents faced during that window (analogous to Sports-Reference's Simple Rating System, SRS: team
rating = average point differential + strength of schedule, solved iteratively/via least squares).

**Why it might help:** Directly documented in the literature this repo would be competing against: "a
team's schedule-adjusted metrics are generally more predictive of future performance than their raw
metrics" (sports-reference.com SRS methodology; ESPN's BPI explicitly "account[s] for opponent
strength, pace of play, site, travel distance, day's rest"). The current model's rolling features are
entirely unadjusted for opponent quality — a team on a hot 13-game stretch against weak opponents
looks identical to one on a hot stretch against strong opponents.

**Data needed:** Available now (`data/box_scores_cache.rds` alone is sufficient — SRS-style adjustment
is self-referential, no external data needed) but requires either an iterative solve or bootstrapping
off a proxy like Elo (idea #1) as the opponent-strength weight.

**Effort/risk:** Medium — not algorithmically hard, but easy to get subtly wrong (e.g. using
current, not point-in-time, opponent strength would reintroduce the exact leakage problem flagged in
idea #2). Not tested in Part 2 due to the combined effort of getting the point-in-time discipline
right within this pass's time budget; a natural next step once idea #1 (Elo) is validated, since Elo
itself could supply the opponent-strength weight.

### 5. Regularized logistic regression (ElasticNet) with engineered interaction terms — **MEDIUM priority, LOW effort**

**What:** An ElasticNet (`glmnet`)-regularized logistic regression, cross-validated for the
regularization strength (`lambda`)/mix (`alpha`), potentially with a handful of interaction terms
(e.g. `diff_roll_efg × diff_roll_tovp`).

**Why it might help:** This may be genuinely close to what the named benchmark paper itself did.
Independent web search corroborated across queries that Alves & Barbosa's paper explicitly compares
a **Ridge Regression Classifier** among its architectures, and — notably — states that **"WNBA
datasets are considerably smaller than NBA datasets, requiring increased regularization for
ElasticNet models to converge"** (search-engine summary of the paper, MDPI *Computation* 13(10):230).
This is a concrete, WNBA-specific methodological detail about how the benchmark paper likely handled
its own small-sample problem — proper regularization tuning for a small dataset, not necessarily a
fancier architecture. `WNBA_Analysis_Project.Rmd`'s own single-split benchmark already shows plain
Logistic Regression **beating RF on raw accuracy** (0.628 vs. 0.604) despite RF winning on AUC/Brier —
suggesting a properly regularized linear model is not a strictly worse starting point here and may be
underexplored relative to RF.

**Data needed:** None — same feature set already in use.

**Effort/risk:** Low effort, low risk. Not tested in Part 2 (the 3 picks below were judged higher-value
given real, currently-unused data assets), but flagged as a strong, cheap next candidate — especially
paired with idea #1/#2's new features, since linear models often benefit more from well-chosen
low-dimensional features (like a single Elo or RAPM differential) than tree ensembles do.

### 6. Four Factors computed on a true per-possession (pace-adjusted) basis — **MEDIUM priority, LOW-MEDIUM effort**

**What:** The model already includes rate-based Four-Factor-style stats (eFG%, a TOV%-like ratio,
FTR, TS%) — but the *counting* stats (points, rebounds, assists, steals, blocks, turnovers fed into
`roll_pts_scored`, `roll_oreb`, etc.) are raw per-game totals, not adjusted for pace (estimated
possessions = `FGA - OREB + TOV + 0.44*FTA`). Two teams with identical per-possession efficiency but
different pace would show different raw rolling stats today.

**Why it might help:** Dean Oliver's Four Factors are widely cited as explaining "approximately 96%
of the variance in team wins" when computed correctly (Squared Statistics / *Basketball on Paper*,
Oliver 2004) — but that framework is explicitly a **per-possession** rate framework; pace-confounded
inputs dilute the signal the Four Factors are designed to isolate.

**Data needed:** None — possessions can be estimated from existing `data/box_scores_cache.rds`
columns (no new data source).

**Effort/risk:** Low-medium (needs one new possession-estimate column, then re-deriving several rolling
features off it). Not tested empirically in this pass; a good, cheap follow-up.

### 7. Real shot-quality "luck" residual as a regression-to-mean signal — **MEDIUM priority, HIGH effort (blocked on a real join problem)**

**What:** `cache/team_shot_quality.rds` already computes real `shooting_luck_pts` (actual vs.
expected points, from 265,912 real shots in `cache/wnba_shots_cache.rds`) — teams shooting well above
their shot-quality-implied expectation tend to regress toward it, a classic "buy low / sell high" signal.

**Why it might help:** This is real, already-computed WNBA data, and shooting-luck regression is a
well-established concept in basketball analytics (see also research confirming NBA three-point
shooting percentages take roughly 750 attempts to stabilize — Sports Analytics literature on shot
metric stabilization, causeweb.org "Modeling Shot Probability in the NBA" and related work) — a team
on an unsustainable hot streak is a good target for a "expect regression" feature.

**Why it was NOT tested in Part 2 (honest limitation, not hidden):** `cache/team_shot_quality.rds` is
a **single static 15-row snapshot** (one row per team, "current" as of the pull date), not a per-game
or per-season historical series — using it as-is for all 1,902 historical games (2019-2026) would be
both non-varying (same number for every year of a team's history) and leaky (it reflects "now," which
includes the future relative to a 2019 game). The underlying real shot data
(`cache/wnba_shots_cache.rds`) *could* support a proper season-level or rolling recomputation, but P2's
own investigation found its `game_id` uses the WNBA-Stats-API namespace with **no `game_date` column
and no shared key with `box_scores_cache.rds`'s ESPN-namespace `game_id`** — exactly the join problem
that made P2 resort to a string-sort-on-`game_id` recency approximation rather than a true date join.
Building a reliable per-game or point-in-time-safe shot-quality feature would require first solving
that ID-bridging problem (e.g. via team+date-window score matching) as a real prerequisite task, not a
five-minute join. Flagged as real, valuable, but genuinely blocked work — not skipped for convenience.

**Data needed:** Real data exists (`cache/wnba_shots_cache.rds`) but needs a new ID-bridging step
before it can be used safely.

**Effort/risk:** High effort for the reasons above; risk of a subtly wrong join producing a plausible-
looking but incorrect feature is real, which is exactly why it wasn't rushed in this pass.

### 8. Roster continuity / availability-adjusted rating — **MEDIUM priority, LOW-MEDIUM effort**

**What:** `roster_dynamics.R::get_roster_continuity()` already computes real season-over-season
`returning_minutes_pct`/`roster_stability_score` per team from `cache/player_box_scores_cache.rds`,
and `apply_continuity_adjustment()` already implements a shrink-toward-league-mean adjustment for
low-continuity teams — but neither is wired into the win-prediction model at all today.

**Why it might help:** A team that lost most of its rotation minutes to free agency/trades is a
plausible source of "this team's rolling stats from a wholly different roster shouldn't be trusted at
full weight yet" signal, particularly relevant to WNBA's 12-player active rosters (higher per-player
share of team minutes than NBA's 15-man rosters, per `config.R::WNBA_ROSTER_MAX`) where turnover has
an outsized effect. Injury-scraper literature corroborates the general idea: NBA prediction write-ups
describe "availability-adjusted ratings ... reflect who is actually expected to play" as a real,
useful signal class (nbainsights.substack.com).

**Data needed:** Available now — real function, real underlying data, just not called by
`build_feature_df()`.

**Effort/risk:** Low-medium effort (the function already exists; needs season-boundary joining care to
avoid the same look-ahead issue as idea #2). Not tested in Part 2 due to time budget; a strong next
candidate given it's the *least* new code required of any idea on this list.

### 9. Bayesian hierarchical / state-space team-strength model — **HIGH conceptual value, HIGH effort**

**What:** Treat team strength as a latent variable that evolves game-by-game (e.g. a random walk),
estimated jointly across all teams with partial pooling, rather than as a fixed set of engineered
features fed to a generic classifier. Directly descended from Glickman & Stern's 1998 Bayesian
state-space paired-comparison model (originally for NFL, since extended); basketball-specific
hierarchical variants exist too (SciTePress 2023, "Bayesian Hierarchical Modelling of Basketball Team
Performance").

**Why it might help:** This class of model is specifically well-suited to *small* samples because
partial pooling ("shrink noisy teams toward the league") is baked into the model rather than bolted on
after the fact, and it naturally handles the "short season, few games per team" problem the brief
raises without needing an arbitrary rolling-window or decay-rate choice — the model's own posterior
uncertainty does that job. This is the most literature-grounded answer to the brief's explicit question
about whether a different *methodology*, not just a different feature, might suit WNBA's data volume
better than a static-feature tree ensemble.

**Data needed:** None beyond existing box scores, but requires a genuinely different modeling stack
(e.g. `brms`/Stan in R, MCMC fitting, convergence diagnostics) not currently used anywhere in this repo.

**Effort/risk:** High effort (new dependency, new methodology, meaningfully more implementation and
validation time than any other idea here — likely a multi-day undertaking done properly, including
posterior-predictive checks) and correspondingly higher risk of getting something subtly wrong (e.g.
convergence issues on a small dataset) without it being obvious from a single accuracy number. Not
attempted in this pass; recommended as the best *big swing* candidate for a future dedicated task,
explicitly not squeezed into this one.

### 10. Better-tuned gradient boosting (proper hyperparameter search) or LightGBM/CatBoost — **LOW-MEDIUM priority, MEDIUM effort**

**What:** `WNBA_Analysis_Project.Rmd` already tries XGBoost but with largely default-ish settings
(200-300 trees, depth 4, no systematic search); a proper nested-CV hyperparameter search (learning
rate, depth, min child weight, subsample) or trying LightGBM/CatBoost (both confirmed available as R
packages) could plausibly close some gap.

**Why it might help less than it sounds:** Un-tuned XGBoost already underperformed RF on this exact
WNBA data (`ML_BENCHMARK_REPORT.md` §2: XGBoost 0.608 accuracy / 0.656 AUC vs. RF's 0.666 AUC on the
single-split benchmark) — tree-ensemble choice/tuning is a second-order lever compared to feature
quality on a dataset this size (1,902 games, ~20 features); general ML literature agrees hyperparameter
tuning "improved model performance significantly" but usually a few points at most, not the 3.6-point
gap in question.

**Data needed:** None new.

**Effort/risk:** Medium effort for a properly *nested* CV search (an improperly nested one risks
exactly the p-hacking this whole exercise is trying to avoid — tuning against the same folds used for
the final reported number). Not tested in Part 2; lower priority than feature-side ideas given the
above reasoning, but flagged for completeness per the brief's explicit ask.

### 11. Stacking/ensembling multiple models — **LOW-MEDIUM priority, LOW-MEDIUM effort**

**What:** A meta-learner (e.g. logistic regression) combining RF + regularized logistic regression +
XGBoost out-of-fold predictions.

**Why it might help:** Standard technique, modest-but-real gains typically (the Alves & Barbosa paper
itself includes a Stacking Classifier among its compared architectures, suggesting the benchmark paper
authors considered it worthwhile too). Unlikely alone to close a 3.6-point gap on a dataset this size,
where the binding constraint looks more like feature richness than model-family choice.

**Data needed:** None new (reuses existing feature set + newly tested features).

**Effort/risk:** Low-medium; main risk is CV-leakage in how out-of-fold stacking predictions are
generated (must respect the same LOSO structure). Not tested in Part 2.

### 12. Calibration post-processing (Platt scaling / isotonic regression) — **LOW priority for accuracy, but real value for betting use**

**What:** Post-hoc recalibration of the RF's predicted probabilities.

**Why it might help:** Won't move accuracy or ROC-AUC (rank-based metrics are calibration-invariant),
but this repo's actual end use is a betting pipeline (`market_odds_engine.R`, Kelly staking) where
well-calibrated *probabilities*, not just correct classifications, directly determine bet sizing and
EV. "Platt Scaling is one of the most common methods in sports betting ... especially effective for
models that output raw scores [tree ensembles]," while isotonic regression "works better ... when
enough training data is available" but "may overfit on smaller datasets" — given WNBA's small sample,
Platt scaling is the more defensible of the two here. Directly relevant: `app.R`'s Tab 6 calibration
curve is currently a hardcoded fake curve despite `live_calibration.R::calibration_analysis()` already
existing and working (`REPO_MAP.md` §9) — wiring a real Platt/isotonic step in would fix two known
issues (calibration quality *and* that dead/fake dashboard tab) at once.

**Data needed:** None new — post-processes existing model output.

**Effort/risk:** Low effort, low risk (well-understood technique, doesn't touch the underlying model).
Not tested in Part 2 (out of scope: this pass is about accuracy/AUC-moving features, and calibration by
design won't move either), but flagged as a clear, cheap, low-risk production candidate independent of
whether any accuracy-improving idea above pans out.

---

## Part 2: Empirical Results

**Script:** `tools/ml_feature_experiments.R` (new, does not modify `ml_cv_benchmark.R`). Reuses
`ml_cv_benchmark.R`'s `build_feature_df()` verbatim, the same RF (`ranger`, 250 trees) architecture,
the same leave-one-season-out (LOSO) cross-validation loop, and the same pooled-out-of-fold
nonparametric bootstrap (2,000 resamples, percentile 95% CI) methodology — no new evaluation protocol
was invented. `window_size` is pinned to 13 explicitly (not read from `config.R`, whose
`ROLLING_WINDOW_SIZE` was re-swept to 12 the same day `ML_BENCHMARK_REPORT.md` was written) so results
stay strictly comparable to the published baseline.

**Sanity check (this script's own fresh baseline refit, same data/seed/architecture):** reproduced
**Accuracy 0.639 [0.618, 0.661], ROC-AUC 0.675 [0.651, 0.699]** — bit-for-bit identical to
`ML_BENCHMARK_REPORT.md`'s published numbers, including every one of the 8 fold-level accuracy/AUC
values. This confirms the pipeline reproduction is exact before any new feature is layered on, so every
delta below is a clean apples-to-apples comparison, not an artifact of a subtly different re-derivation.

Three ideas were tested — picked as the most promising *and* cheapest to test given real data already
computed in this repo, per the brief's own steer toward the RAPM/shot-quality/fatigue/continuity data:

1. **Idea #1 — Elo differential** (added feature, zero new data dependency, zero look-ahead by
   construction).
2. **Idea #2 — RAPM differential** (added feature, real possession data, re-solved per LOSO fold to
   eliminate look-ahead leakage — see Part 1 for why the raw cached rating can't be used directly).
3. **Idea #3 — EWMA recency-weighted rolling averages** (methodology swap on the existing box-score
   features, testing the short-season/continuous-update hypothesis directly).

`cache/travel_fatigue_metrics.rds` (still only 4 demo rows — re-confirmed by direct inspection in this
task, unchanged since P4's report) and a proper point-in-time shot-quality feature (blocked on the real
ID-namespace join problem — see Part 1 idea #7) were both considered and **not** tested, for the same
honest reasons P4 rejected travel-fatigue data the first time: no real, non-fabricated per-game (or
fold-safe per-season) signal could be constructed from them in this pass without either inventing rows
or accepting a same-season lookahead leak.

**Marginal bootstrap results** (each model's own pooled LOSO out-of-fold predictions, 2,000-resample
95% CI — identical methodology to `ML_BENCHMARK_REPORT.md`, from `cache/ml_feature_experiments_results.rds`):

| Model | Accuracy | Accuracy 95% CI | ROC-AUC | ROC-AUC 95% CI |
|---|---:|---|---:|---|
| **Baseline** (published, reproduced bit-for-bit) | 0.6393 | [0.6183, 0.6614] | 0.6748 | [0.6513, 0.6995] |
| + Elo differential | **0.6509** | [0.6304, 0.6719] | **0.6998** | [0.6784, 0.7230] |
| + RAPM differential (fold-safe) | 0.6351 | [0.6130, 0.6577] | 0.6750 | [0.6514, 0.6991] |
| + EWMA recency weighting | 0.6204 | [0.5994, 0.6425] | 0.6604 | [0.6356, 0.6841] |

**Paired bootstrap results** (a tighter, more sensitive test: same 1,902 held-out games under both
models, per-game delta resampled together — cancels out game-level difficulty noise that widens the two
marginal CIs above independently; `n_boot = 2000`, from `cache/ml_feature_experiments_paired_ci.rds`,
computed 2026-09-12 after the original research pass was interrupted mid-write-up by a session rate
limit — the LOSO experiments themselves had already finished and were not re-run):

| Candidate | Metric | Delta vs. baseline | 95% CI | % of bootstrap draws > 0 |
|---|---|---:|---|---:|
| **Elo** | Accuracy | +0.0116 | [-0.0058, +0.0294] | 89.6% |
| **Elo** | ROC-AUC | **+0.0250** | **[+0.0128, +0.0381]** | **100%** |
| RAPM | Accuracy | -0.0042 | [-0.0189, +0.0110] | 28.4% |
| RAPM | ROC-AUC | +0.0002 | [-0.0095, +0.0108] | 52.5% |
| EWMA | Accuracy | -0.0189 | [-0.0384, 0.0000] | 2.5% |
| EWMA | ROC-AUC | -0.0144 | [-0.0306, +0.0017] | 3.8% |

### Honest verdict per idea

**Elo — real, and the standout result.** The paired ROC-AUC CI is entirely positive
(`[+0.0128, +0.0381]`, 100% of resampled deltas favor Elo) — this is about as clean a "genuinely better,
not noise" signal as a ~1,900-game dataset can produce. Accuracy points the same direction (+1.16 pts)
but is less decisive (89.6% of paired draws positive, marginal CI still overlaps baseline) — treat the
AUC/ranking improvement as the well-supported claim and the accuracy gain as directionally consistent
but not independently conclusive. Against the named external benchmark (Alves & Barbosa, 67.48%
accuracy), adding Elo moves the observed gap from ~3.6 points (baseline) to **~2.4 points** — a real
improvement, not a full closure of the gap, and still inside the kind of CI width `GAP_REMEDIATION_PLAN.md`
already cautioned isn't safe to over-interpret at `<1%` precision. **Recommendation: strongest candidate
for a real production change**, but should go through the same LOSO discipline (not a single split) if
promoted, and the benchmark comparison should stay honestly hedged.

**RAPM — no real effect, do not pursue further right now.** Both paired deltas straddle zero
(28-53% of draws positive — indistinguishable from a coin flip), despite the real, substantial
engineering effort of re-solving an 800+ dimension ridge regression per fold to avoid leakage. This is a
genuinely informative negative result, not a failed attempt: a plausible explanation is that RAPM is a
*player*-level skill signal and this model already has team-level box-score momentum covering similar
ground, so the marginal information added at the team-differential level is small once you're already
using recent scoring/rebounding/assist differentials. A finer-grained use (e.g., RAPM-weighted expected
lineup strength accounting for that day's actual available roster/injuries) might still have signal —
untested here, flagged as a possible future idea, not a next step to prioritize.

**EWMA recency weighting — actively hurts, reject.** This is the clearest negative result of the three:
97.5% of paired accuracy-delta draws are negative and the CI's upper bound sits at exactly 0.0000.
This **rejects** the hypothesis (raised in Part 1 and in `GAP_REMEDIATION_PLAN.md`'s own speculation)
that a short WNBA season should favor heavier recency-weighting over the existing flat rolling window —
at least for this specific decay implementation. A plausible read: WNBA per-game box-score noise is high
enough relative to real week-to-week team-strength change that down-weighting older-but-still-current-
season games mostly discards signal rather than removing stale information. Do not carry this forward
without a materially different decay design (e.g., only down-weighting across the *season boundary*,
which is closer to what Elo's between-season regression already does well, rather than within-season).

### Overall recommendation

Of the three tested, **only Elo shows a statistically credible improvement**, concentrated in ranking
quality (ROC-AUC) more than raw accuracy. It is cheap, additive, needs no new data dependency, and
degrades gracefully (worst case, redundant with existing features). **It is the one candidate from this
pass worth a real production proposal** — as an added feature to the existing rolling-differential
model, evaluated with the same LOSO methodology before being adopted, not a single-split decision.
RAPM and EWMA are both honestly negative results and should not be pursued further in their current form;
Platt-scaling calibration (Part 1, idea covered above) remains a separate, low-risk, low-effort
recommendation independent of this accuracy work, since it targets bet-sizing quality rather than
classification accuracy.
