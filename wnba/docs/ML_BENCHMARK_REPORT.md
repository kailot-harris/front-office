# ML_BENCHMARK_REPORT.md
### P4 — ML Benchmark Rigor (`wnba_ml_benchmark_agent`) — 2026-09-12

## 1. Scope and what this report is / is not

This report cross-validates the WNBA win-prediction model against **named, citable external
benchmarks**, per `GAP_REMEDIATION_PLAN.md` Spec Item 3 and its "Important Caveat on Spec Item 3."
It is **not** a single lucky train/test split dressed up as a result — every number below is either
a fold-by-fold cross-validated statistic or a pooled out-of-fold statistic with a 95% confidence
interval, computed by `ml_cv_benchmark.R` (new file, this task) against the real
`box_scores_cache.rds` (3,906 real team-game rows, 2019-2026, T1's real data).

This is a **separate, more rigorous exercise** than P3's `cache/model_calibration_input.rds`
(a simple rolling-margin substitute model built for the app's calibration tab). This report instead
re-fits `WNBA_Analysis_Project.Rmd`'s actual candidate architecture (Random Forest via `ranger`) using
the Rmd's own real feature-engineering pipeline, copied verbatim into `ml_cv_benchmark.R`.

## 2. Model selection: verifying the WNBA winner, not assuming the NBA one

Per the brief, the assumption that "RF won on NBA, so it probably wins on WNBA too" was **checked, not
assumed**. `WNBA_Analysis_Project.Rmd`'s own real WNBA re-run (`Model Benchmarking Architecture`
section, window_size=13, method="reset", real 2026-season holdout) reports:

| Model | Accuracy | ROC-AUC | Brier | Log-Loss |
|---|---:|---:|---:|---:|
| Logistic Regression | 0.628 | 0.655 | 0.231 | 0.655 |
| **Random Forest (ranger)** | 0.604 | **0.666** | **0.227** | **0.644** |
| XGBoost (boost_tree) | 0.608 | 0.656 | 0.241 | 0.687 |

Random Forest wins on ROC-AUC, Brier, and Log-Loss on the real WNBA re-run (Logistic Regression
edges it out only on raw accuracy, but is worse-calibrated). This **does** match the NBA baseline's
conclusion, confirmed independently on WNBA data rather than assumed — so RF (`ranger`) is the
architecture carried into the cross-validated benchmark below. This single-split result above is
T2's (not re-derived here); everything from Section 3 onward is this task's own new cross-validated
re-fit of that same architecture.

## 3. Methodology

**Data:** `box_scores_cache.rds`, 3,906 real team-game rows, 2019-2026 (all 8 real WNBA seasons,
including the 2026 season, which is partial/in-progress as of validation time).

**Features:** Identical to `WNBA_Analysis_Project.Rmd`'s `build_feature_df()` — rolling means
(window = `ROLLING_WINDOW_SIZE` = 13 games, `method = "reset"`, both values already re-benchmarked
and set by T2 on real data, not re-tuned here) of points, rebounds, assists, steals, blocks,
turnovers, eFG%, TOV%, FTR, TS%, and days rest, differenced home-minus-away, target =
`target_home_win` (factor `Win`/`Loss`). After dropping each team's first `ROLLING_WINDOW_SIZE`
games per season (no prior in-season history) and non-joinable rows: **1,902 real games** across
the 8 seasons (matches P3's independently-built `model_calibration_input.rds` game count exactly —
a useful cross-check that both agents parsed the same underlying cache consistently).

Season sizes (post-drop): 2019: 214, 2020: 141, 2021: 204, 2022: 234, 2023: 255, 2024: 257,
2025: 304, 2026: 293.

**Model:** `rand_forest(trees = 250, mode = "classification")` / engine `"ranger"`, same
hyperparameters as the Rmd's benchmark chunk, same `step_rm()` / `step_normalize()` recipe.

**Cross-validation design — leave-one-season-out (LOSO), not random k-fold:** per the brief's own
reasoning (WNBA seasons are short; random row-level folds could leak information across games in
the same season via the rolling features' within-season history), each of the 8 real seasons is
held out in turn as the test fold, with the model refit from scratch on the other 7 seasons each
time. This mimics real deployment (predicting a season you have never seen) far better than a random
row split would. Note this is *not* a plain "seasons < 2026 / seasons ≥ 2026" single split (the Rmd's
own single-split result above) — every season, including 2019 and 2026, gets a turn as the held-out
test set.

**Confidence intervals — two methods reported, both documented explicitly:**
1. **Primary: nonparametric bootstrap on pooled out-of-fold predictions.** All 1,902 out-of-fold
   predictions (each game predicted only by the fold where its season was held out) are pooled once;
   2,000 bootstrap resamples (with replacement, row-level) of that pooled table are drawn, each
   metric recomputed per resample, and the 95% CI is the [2.5%, 97.5%] percentile interval of the
   resulting distribution. This treats the 1,902 real games as the effective sample and is the
   headline CI used for the gap verdict below.
2. **Secondary: fold-to-fold t-interval.** Mean ± `qt(0.975, df=7) * (sd/sqrt(8))` across the 8
   per-season fold estimates. Reported only as a sanity check — 8 folds is too few for this to be
   reliable on its own, but it corroborates the bootstrap CI's rough magnitude (see Section 4).

Positive/event class for precision/recall/F1/ROC-AUC = `"Win"` (home team wins), `event_level =
"first"`, consistent with the Rmd's own `roc_auc()` convention.

## 4. Results — Baseline model (Rmd feature set, no new features)

### Fold-by-fold (LOSO, one row per held-out season)

| Season (held out) | n | Accuracy | Precision | Recall | F1 | ROC-AUC |
|---:|---:|---:|---:|---:|---:|---:|
| 2019 | 214 | 0.6542 | 0.7317 | 0.6870 | 0.7087 | 0.6745 |
| 2020 | 141 | 0.6950 | 0.6795 | 0.7465 | 0.7114 | 0.7175 |
| 2021 | 204 | 0.5686 | 0.6071 | 0.6071 | 0.6071 | 0.6181 |
| 2022 | 234 | 0.6752 | 0.6759 | 0.7717 | 0.7206 | 0.6961 |
| 2023 | 255 | 0.6627 | 0.6644 | 0.7333 | 0.6972 | 0.7040 |
| 2024 | 257 | 0.6770 | 0.6792 | 0.7714 | 0.7224 | 0.7137 |
| 2025 | 304 | 0.5987 | 0.6269 | 0.7076 | 0.6648 | 0.6382 |
| 2026 | 293 | 0.6109 | 0.6257 | 0.7267 | 0.6724 | 0.6691 |

Note the real fold-to-fold spread — accuracy ranges from 0.569 (2021) to 0.695 (2020), a ~12.6
percentage-point swing purely from which season is held out. This is exactly the kind of sampling
variance `GAP_REMEDIATION_PLAN.md`'s caveat warned about, and is why a single split (e.g. the Rmd's
2026-only holdout) should never be reported alone as "the" accuracy.

### Pooled out-of-fold metrics with 95% CI (n = 1,902, bootstrap, 2,000 resamples)

| Metric | Estimate | 95% CI (bootstrap) |
|---|---:|---:|
| Accuracy | 0.639 | [0.618, 0.661] |
| Precision | 0.658 | [0.630, 0.686] |
| Recall | 0.719 | [0.693, 0.747] |
| F1 | 0.687 | [0.664, 0.709] |
| ROC-AUC | 0.675 | [0.651, 0.699] |

Fold-to-fold t-interval (secondary check, 8 folds): Accuracy mean 0.643, 95% CI [0.605, 0.680];
ROC-AUC mean 0.679, 95% CI [0.649, 0.709] — consistent in magnitude with the bootstrap CI above,
giving two independent reasons to trust roughly a ±2-3 point CI half-width on accuracy, exactly the
range `GAP_REMEDIATION_PLAN.md` anticipated ("plausibly ±2-3 percentage points just from which
season is held out").

## 5. Named external benchmark — research findings

Web search was used to find a real, checkable, comparable published benchmark (not a remembered
number). Three candidates were evaluated; the most comparable is used as the primary benchmark.

### 5a. Primary benchmark — WNBA-specific academic paper (best match available)

**Alves, J.M.; Barbosa, R.S. "Machine Learning for Basketball Game Outcomes: NBA and WNBA Leagues."
*Computation* 2025, 13(10), 230. DOI: 10.3390/computation13100230.**
(https://www.mdpi.com/2079-3197/13/10/230, mirrored at ResearchGate publication 396095655)

This is a genuinely **WNBA-specific** benchmark, not merely an NBA proxy — the paper trains and
evaluates Logistic Regression, Ridge Classifier, Random Forest, Naive Bayes, KNN, SVM, Stacking,
Bagging, MLP, AdaBoost, XGBoost, LSTM, and CNN architectures separately on NBA and WNBA game logs.
Reported best result: **65.50% accuracy for NBA, 67.48% accuracy for WNBA** (best-performing model
per league; this figure was independently corroborated across three separate web searches returning
the same 67.48% figure, reducing the chance of a search-summary hallucination). **Caveat, stated
honestly rather than glossed over:** direct `WebFetch` access to both the MDPI page and the
ResearchGate mirror returned HTTP 403 in this environment (both blocked automated fetch), so this
agent could **not** independently verify from the primary source whether the paper also reports
precision/recall/F1/ROC-AUC for the WNBA model specifically, nor confirm the exact best-performing
algorithm name, exact season range, or exact WNBA game count beyond what search-engine summaries
surfaced. The 67.48% accuracy figure is used below because it recurred identically across
independent queries and carries a verifiable DOI, but the comparison against our precision/recall/
F1/ROC-AUC is **necessarily accuracy-only** for this benchmark, since those other metrics could not
be confirmed as reported by the source paper in this session.

### 5b. Secondary benchmark — NBA proxy with a comparable architecture (RF, box-score features)

**Zhao, K.; Du, C.; Tan, G. "Enhancing Basketball Game Outcome Prediction through Fused Graph
Convolutional Networks and Random Forest Algorithm." *Entropy* 2023, 25(5), 765 (PMC10217531).**

NBA, 2012-2018 seasons, 14,758 games, 44 features/team/game. Random-Forest-family baselines
(RF combined with Decision Tree/SVM/Linear Regression across six per-season datasets) averaged
**~70.83-71.17% accuracy**; the paper's proposed fused GCN+RF model reached **71.54%** average
accuracy. This is explicitly used here **as an NBA proxy, not a WNBA standard** — flagged per the
brief's instruction not to imply WNBA-specific literature exists where a better one (5a) does. The
paper reports only accuracy; no precision/recall/F1/AUC values are given, so — like 5a — comparison
is accuracy-only.

### 5c. Vegas moneyline baseline — investigated, NOT used as a hard number

The brief asked for the "implied accuracy of closing Vegas moneyline favorites," commonly remembered
as "70-74% for NBA." That exact number was deliberately **not reused from memory**. Searches for a
single, precise, citable moneyline-favorite hit-rate turned up only ranges from secondary/blog
sources (e.g., "medium favorites win 65-70% straight up," "heavy favorites (-300 or worse) win
~80-85%," "closing-line implied probabilities differ from actual outcomes by no more than about 5%
across bins" from a Towards Data Science analysis of ~6,567 games from 2013-2017 seasons) — none of
which is a single peer-reviewed, precisely-stated figure comparable in rigor to 5a/5b. Per this
task's explicit constraint ("do not invent a benchmark number without a real, checkable source"),
**no single Vegas-moneyline percentage is used in the quantitative gap verdict below.** It is
mentioned only as directional context: our model's ~64-68% accuracy range is roughly in the same
neighborhood as "medium favorite" moneyline hit rates, well below "heavy favorite" hit rates — an
informal sanity check, not a benchmark claim.

## 6. Gap analysis — honest verdict

Using the **pooled, bootstrap-CI'd baseline model** (Section 4) against the **primary WNBA-specific
benchmark** (5a, accuracy only, since other metrics were unverifiable from source in this session):

| | Accuracy |
|---|---:|
| This model (pooled LOSO, 95% CI) | 0.639 [0.618, 0.661] |
| Alves & Barbosa (2025) WNBA best model | 0.6748 |
| Raw gap | **3.58 percentage points** (benchmark higher) |

**Verdict on the primary WNBA benchmark: the <1 percentage-point bar is NOT met**, and the gap is
**likely a real gap, not pure noise** — the benchmark's point estimate (67.48%) sits outside this
model's own 95% CI upper bound (66.1%), by 1.4 points. However, that margin (1.4 points beyond our
own CI edge) is itself smaller than half our CI's width (~2.15 points), so this should be stated
precisely rather than overclaimed: we can say with reasonable confidence that this model's accuracy
is a few points below the named WNBA benchmark's reported figure, but we cannot rule out, from our
data alone, that a slightly different real-world sample would narrow (or widen) that gap by a point
or two. It is a **real, if modest, gap** — not the <1% the spec asks for, and not so large as to be
a different tier of model either.

Against the **secondary NBA-proxy benchmark** (5b, ~71.5% RF-family accuracy): the gap widens to
roughly **7.2-7.9 percentage points**, entirely outside this model's 95% CI. This is flagged
explicitly as the *less* comparable benchmark (different league, much larger sample, different
feature set) — the WNBA-specific comparison in 5a is the one that should carry weight for the
official spec-compliance verdict, and it already fails the <1% bar on its own.

**On ROC-AUC/precision/recall/F1 specifically:** neither named benchmark paper was confirmed (in
this session) to report these metrics for their best model, so **no external <1% comparison can
honestly be made for ROC-AUC/precision/recall/F1** — only for accuracy. This model's own
cross-validated values for those metrics (Section 4) are reported for completeness and for any
future agent who finds a benchmark paper that does report them, but they have no external comparator
here. This limitation is stated plainly rather than fabricating a benchmark AUC/F1 figure to fill the
gap.

## 7. Legitimate improvement attempt — real embeddings similarity feature

Per the brief's instruction not to keep tuning against the test set once a gap is found, exactly
**one** documented, principled feature addition was tried, using data confirmed real and available
per `task_assignments_phase2.md`'s P1 Handoff Notes (checked before use, not assumed available):
P1's real-trained `team_embeddings.csv` (retrained on `cache/games_for_embeddings.csv`'s 1,953 real
games, not the old mock-matchup version).

**Feature added:** `emb_similarity` = cosine similarity between the home and away team's 16-dim
embedding vectors (joined via a `team_id -> team_abbreviation` lookup built from
`box_scores_cache.rds`, since `team_embeddings.csv` is keyed by abbreviation string per P1's schema
change, while the Rmd's `model_df` uses the numeric ESPN `team_id`). Computed for all 1,902 games
(0 missing — every team in the model data joined cleanly to the 15-row embeddings table).

**`cache/travel_fatigue_metrics.rds` was considered and explicitly rejected** as a second candidate
feature: inspection showed it contains only **4 illustrative demo rows** (not one row per historical
game), so it cannot supply a real per-game training feature for 1,902 modeled games without
fabricating the other ~1,898 rows — which would itself be a form of the fabrication this whole
remediation round is trying to eliminate. Only the embeddings feature was tried, honestly, per the
brief's "one or two" allowance being satisfied by trying the one real option actually available at
full coverage.

### Before / after (same LOSO procedure, same model, same seed, identical except for the one added feature)

| Metric | Baseline (no embeddings) | + emb_similarity | Δ |
|---|---:|---:|---:|
| Accuracy | 0.639 [0.618, 0.661] | 0.628 [0.606, 0.650] | **-0.011** |
| Precision | 0.658 [0.630, 0.686] | 0.646 [0.619, 0.673] | -0.012 |
| Recall | 0.719 [0.693, 0.747] | 0.719 [0.692, 0.748] | ~0.000 |
| F1 | 0.687 [0.664, 0.709] | 0.681 [0.658, 0.704] | -0.006 |
| ROC-AUC | 0.675 [0.651, 0.699] | 0.671 [0.647, 0.695] | -0.004 |

**Honest result: adding the embeddings-similarity feature did not help, and slightly hurt every
metric**, though every change is well within the overlapping 95% CIs of the two models (i.e., not a
statistically distinguishable regression either — the two models are statistically indistinguishable
from each other, both above and below one another interchangeably within noise). This is reported
as-is, not discarded or re-tried with a different feature to search for a favorable result, per the
brief's explicit no-p-hacking constraint. A plausible explanation, noted honestly rather than
rationalized away: the embeddings were trained on the same 1,953-game outcome-prediction task the
downstream model is also solving, so `emb_similarity` is a fairly redundant, noisy restatement of
information the rolling box-score features already capture more directly — not a source of new
signal. This does **not** close the gap found in Section 6; the model with or without this feature
remains a few points below the named WNBA benchmark.

## 8. Summary verdict

- **Model evaluated:** Random Forest (`ranger`, 250 trees), the architecture independently confirmed
  (not assumed) to win on WNBA real data per `WNBA_Analysis_Project.Rmd`'s own re-run.
- **Cross-validated performance (LOSO, 8 real seasons, pooled, bootstrap 95% CI):** Accuracy 0.639
  [0.618, 0.661], Precision 0.658 [0.630, 0.686], Recall 0.719 [0.693, 0.747], F1 0.687 [0.664,
  0.709], ROC-AUC 0.675 [0.651, 0.699].
- **Named benchmark used:** Alves & Barbosa (2025), *Computation* 13(10):230, DOI
  10.3390/computation13100230 — the best available **WNBA-specific** figure (67.48% accuracy),
  with Zhao et al. (2023, *Entropy* 25(5):765) NBA-proxy figure (~71.5% accuracy, RF-family) reported
  as a secondary, explicitly-labeled proxy.
- **Gap verdict: <1% is NOT met.** Real gap of ~3.6 points vs. the WNBA-specific benchmark (accuracy
  only — no comparable external AUC/precision/recall/F1 figure could be verified to exist). The
  benchmark's point estimate sits just outside this model's own 95% CI, so the gap is more likely
  real than pure sampling noise, but it is a modest gap in absolute terms, not a dramatic one.
- **One legitimate improvement attempt (real embeddings similarity) was tried and honestly reported
  as a small, statistically-insignificant regression, not a fix** — the gap remains open. No further
  tuning was performed to force a different outcome.

## 9. Files

- `ml_cv_benchmark.R` (new) — the full, runnable LOSO CV + bootstrap script producing every number
  in this report. Run via `"C:\Program Files\R\R-4.5.2\bin\Rscript.exe" ml_cv_benchmark.R`.
- `cache/ml_benchmark_cv_results.rds` (new) — saved fold tables, out-of-fold prediction tables, and
  bootstrap CI tables for both the baseline and improved models, for any future agent to re-derive
  additional statistics without re-running the model fits.
- No existing files were modified by this task (file-disjoint from P1/P2/P3/P5 per the assignment
  table).
