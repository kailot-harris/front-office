# Feature Wishlist & Roadmap — MLB Analytics

This is **not a commitment list**. Every entry here is a candidate to be
scoped into its own GitHub issue/slice when someone actually picks it up
(see `docs/HANDOFF.md` for the issue/phase pattern this repo uses). Items
move out of this file once they ship (they live in git history / HANDOFF's
phase table instead) or once they're explicitly rejected (see §3 below).

## 1. New capability ideas

Roughly ordered by value-to-effort, not a strict priority queue.

### Specific models to try (from 2026-10-18 academic literature review)

Sourced from a deep-research pass across Google Scholar/arXiv/JQAS covering
win-probability, player projection, pitching/Statcast, postseason simulation,
and betting-market methodology. Full report:
`reports/Baseball analytics model comparison.md`; raw per-topic notes in
`research_notes/Baseball analytics model comparison/`. Headline finding:
fancier architectures rarely beat this project's existing baselines by more
than single digits — targeted correction layers are better-evidenced than
wholesale swaps.

**Small, well-evidenced correction layers (do these first):**
- **Team-quality-adjusted in-game win probability.** Carleton (Baseball
  Prospectus) found standard WP tables need a median ~3-point correction
  (up to 26 points for lopsided teams) when team run-scoring/allowing rates
  are ignored. Fold team-level rates into `mlb_elo_engine.R`'s win-probability
  output. Effort: Small.
- **Logistic-regression meta-model stacked on Elo/Pythagenpat outputs.** The
  one rigorous multi-metric benchmark found (arXiv:2511.02815) had plain
  logistic regression beat Elo, SVM, XGBoost, and a neural net on every
  metric. Don't replace Elo/Pythagenpat — add a logistic-regression layer
  that takes their outputs as features. Effort: Small.
- **Position/park-adjusted or mixture-aware prior for empirical Bayes
  shrinkage.** Jensen/McShane/Wyner (arXiv:0902.1360) found the single
  highest-leverage addition to hierarchical shrinkage is letting the amount
  of shrinkage vary by a latent elite/non-elite subgroup, not adding more
  covariates — stays closed-form, no MCMC needed. Extends
  `mlb_bayes_pooling.R`. Effort: Small, but needs care per-stat (K%/BB% are
  more ability-driven than batting average and would be over-shrunk by
  batting-calibrated priors).
- **SIERA/xFIP-style formula swap for the ERA estimator.** Baseball
  Prospectus's comparison ranked DRA (.26) > cFIP (.25) > xwOBA/xERA (.23) >
  xFIP (.19) ≈ FIP (.19) > SIERA (.18) on year-ahead predictive correlation —
  a pure formula change over existing leaderboard stats, no new data.
  Effort: Trivial-small.
- **Shin's method or power-method devigging** in place of proportional
  devigging in `mlb_market_odds_engine.R`. Štrumbelj (2014) found Shin beat
  proportional normalization "for all bookmaker/sport pairs tested"
  (tennis/racing/greyhound — no MLB-specific study found). Drop-in: R
  `implied` package or a single-parameter numerical solve. Effort: Small.
- **Uncertainty-aware Kelly shrinkage.** Baker & McHale (2013) derive a
  stake-shrinkage factor based on the *measured* uncertainty of each
  win-probability estimate, replacing a constant fractional multiplier.
  Needs the probability model to expose a variance estimate per bet.
  Effort: Moderate.
- **Bullpen-fatigue win-probability penalty in the postseason simulator.**
  A SABR study (27 best-of-7 series, 2014-2022) found a .076 wOBA-against
  gap between rested and fatigued relievers — track reliever rest/usage
  state across series games in `mlb_postseason_simulator.R` and apply as a
  penalty. Effort: Moderate (additive state-tracking, not a redesign).

**Large architectural bets (separate track — require new data infrastructure,
not just a model swap):**
- **Tree-ensemble (LightGBM/XGBoost) projection model on Statcast features.**
  The most rigorously controlled result found: a chronological LightGBM
  backtest beat Marcel's batter wOBA MAE by 12.1% and pitcher xFIP MAE by
  4.0%. Lower risk than it sounds (model-library swap on existing rolling
  features) but full Statcast contact-quality ingestion needed to get the
  real gain. Effort: Small-to-moderate for the model itself, moderate for the
  new Statcast ingestion.
- **Player-level, plate-appearance-driven postseason simulation** (Rudelius
  2012, JQAS) — log5 matchup formula over per-PA multinomial outcomes
  instead of team-level win probabilities. The academic gold standard for
  bracket simulation, but needs lineup data, a log5 engine, and per-PA
  sampling — a full rebuild of `mlb_postseason_simulator.R`'s core, not an
  extension. Effort: Large.
- **Pitch-sequence / Stuff+-family pitch-quality models.** Caution: raw
  Stuff+ correlates with next-year run prevention at 0.41 for pitchers
  staying on the same team but only 0.14 for pitchers who switched teams —
  it conflates team/park/catcher context with portable skill. Any adoption
  needs full pitch-by-pitch Statcast ingestion the project doesn't have.
  Effort: Large.
- **Drawdown-constrained dynamic Kelly** (Busseti/Ryu/Boyd) — embeds the
  drawdown constraint inside a convex sizing optimization solved per bet,
  replacing the current fixed-fraction-Kelly-plus-stop-loss control flow in
  `mlb_risk_management_engine.R`. No MLB-specific validation exists (all
  evidence borrowed from tennis/basketball/soccer/football). Effort: Large.

**Explicitly not recommended:** wiring Closing Line Value (CLV) into
automated bet sizing — it's industry terminology with no peer-reviewed
validation; the one rigorous independent check found 3 of 5 positive-CLV
deciles actually lost money. Log it as a diagnostic only if added at all.

- **[SHIPPED 2026-10-18] Recurring/automated calibration re-check.** Implemented
  `tools/evaluate_season_calibration.R` and `tests/testthat/test-calibration.R`.
  Evaluates walk-forward Brier scores (0.2447 vs 0.2500 coin-flip), log loss (0.6824),
  7 probability bin reliability checks (weighted calib error = 1.82%), chronological
  progression (Early/Mid/Late), and automated flags for extreme outliers or drift.
- **Bankroll P&L dashboard over time.** `mlb_risk_management_engine.R`
  already tracks a bankroll ledger; there's no visualization of drawdown/
  growth history yet. Would reuse `tools/viz_theme.R` for styling.
  Effort: Small-medium.
- **Multi-book odds aggregation.** `mlb_market_odds_engine.R` (Phase 6)
  currently devigs against a single Odds API feed. Aggregating multiple
  books would sharpen the devig and EV estimate, but depends on the
  existing Phase 6 architecture and may need rework of the devig math.
  Effort: Medium.

## 2. Process / infra items

- **[SHIPPED 2026-10-18] Live scheduling of full pipeline.** Operationalized via
  `scripts/run_pipeline_task.ps1` and registered under Windows Task Scheduler
  (`MLB_Analytics_Scheduled_Pipeline`) on a twice-daily cadence (11:00 AM morning
  slate, 5:00 PM pre-game lineups) logging to `logs/scheduled_runs.log`.
- **[SHIPPED 2026-10-18] Automated `testthat` suite & GitHub Actions CI.**
  Implemented formal unit test suite under `tests/testthat/` (54 assertions covering
  Pythagorean win expectation, Elo updates, Tangotiger game score math, market odds
  devigging & Kelly staking, 5-way player crosswalk, empirical Bayes shrinkage
  monotonicity, and season calibration). Integrated with GitHub Actions CI workflow
  (`.github/workflows/ci.yml`).
- **[SHIPPED 2026-10-18] Add a root `README.md`.** Complete orientation guide with
  badges, architecture table, quickstart setup, testing commands, and documentation links.



## 3. Explicitly out of scope

Nothing has been proposed and rejected yet — this section stays empty
until an idea is raised and deliberately declined, so it doesn't get
re-litigated.
