# Prediction-Market Divergence Measurement — Kalshi vs. this repo's model

**Status:** Next Steps #2 and #4 from `docs/prediction_market_alpha_research_plan.md`, executed with
real data 2026-09-17. **Covers all four hypotheses with a testable market: game moneyline (#1/#2),
player props (#3), and season win totals (#4).** MVP/DPOY/ROY/COY/championship futures were checked
and have zero settled Kalshi markets as of this date — not testable yet, no model exists to compare
against anyway.

## Summary verdict across all three measurements

| Hypothesis | N (clustered) | Model Brier | Market Brier | Model favored-side accuracy | Verdict |
|---|---|---|---|---|---|
| #1/#2 Game moneyline | 52 | 0.2047 | **0.1963** | 37–44% vs market's 67–71% | **No edge** |
| #3 Player props (PTS/REB/AST) | 198 | 0.1977 | **0.1931** | 54–66% vs market's 53–69% (mixed, mostly market-favored) | **No edge** |
| #4 Season win totals (v1, single snapshot, plug-in binomial) | 26 | **0.1276** | 0.2482 | **84%** vs market's 60% | superseded by v2, see below |
| #4 Season win totals (v2, multi-snapshot, Beta-Binomial, EARLY regime only) | 53 markets / 668 snapshots | **0.0775** | 0.1122 | 75.5% vs market's **96.2%** | **No confirmed edge — market's directional calls are decisively better once the trivial late-market-convergence effect is removed** |

**Verdict across all four tests: no confirmed edge on any of them.** #4's v1 result (model
favored-side right 84% vs market 60%) looked promising but did not survive two follow-up fixes: a
larger, better-calibrated re-test (below) shows the model's Brier score is still nominally lower,
but the market's favored side is right far more often (96.2% vs 75.5%) in the genuinely predictive
early-season window — Brier and win-rate disagreeing is itself informative (see "How Brier and
win-rate can disagree" below), and the win-rate gap is the more decision-relevant number for "would
following this signal have picked the right side."

---

## #1/#2 — Game moneyline (`KXWNBAGAME`)

See prior version of this doc / `tools/research_prediction_market_divergence.R` for full method.
N=52 real games (2026-07-13 to 2026-08-30). Model Brier (0.2047) worse than market's (0.1963); at
every divergence threshold the market's favored side won substantially more often (≈67-71% vs
≈37-44%). **Recommendation unchanged: closed as "tested, no edge found."**

---

## #3 — Player props (`KXWNBAPTS`/`KXWNBAREB`/`KXWNBAAST`)

**Method** (`tools/research_prediction_market_props_divergence.R`): pulled ALL 5,695 settled
single-player prop markets across the three series (2,971 PTS + 2,265 REB + 628 AST — Kalshi's real
WNBA player-prop coverage is far deeper than the original feasibility check anticipated). Parsed
player name + the real scheduled game date directly from each market's ticker (avoids the
UTC-crossover ambiguity the game-market script had to work around), joined to the real per-player
box score in `data/player_box_scores_cache.rds` — 5,515/5,695 matched, with a **0-mismatch sanity
check** between Kalshi's real settlement and the matched box-score outcome (confirms the join key is
sound, not a coincidence).

"Model" probability = normal-approximated retrospective trailing mean/sd of that player's own
season stat (`ROLLING_WINDOW_SIZE` prior games, leakage-free, same convention as the game-market
script), requiring ≥5 prior games with nonzero variance (3,967/5,515 qualified). **Disclosed
simplification**: this is NOT `copula_props_engine.R`'s real Wilson/ZINB copula math — that cache is
a single current-day snapshot with no historical reconstruction capability, so using it on a past
game would silently leak today's fitted parameters into a historical comparison. This trailing
mean/sd is an honest, leakage-free proxy for "what a no-lookahead version of the model's mu/sigma
would have said," not a reproduction of the live engine.

Of the qualifying markets, priced 200 via a reproducible random sample (`set.seed(20260917)`) — full
population of ~4,000 candlestick pulls was judged not worth the API load for a first-pass
measurement; 198/200 got a usable pre-tip-off price.

**Result (N=198, 2026-07-12 to 2026-08-30, 102 PTS / 72 REB / 24 AST):**
- Mean divergence (model − market) = **+0.048, significant** (t=5.75, p<0.0001, 95% CI
  [0.032, 0.064]) — the model is systematically MORE bullish on the "over"/yes side than the market
  across props. A real, non-noise directional bias, not itself a trading edge.
- Model Brier (0.1977) slightly worse than market's (0.1931).
- Threshold analysis is mixed but tilts toward the market: at |divergence| ≥ 0.05/0.08/0.10 the
  market's favored side was right more often (66-69% vs model's 54-57%); only at the highest,
  smallest-N bucket (≥0.15, N=32) did the model edge ahead (65.6% vs 53.1%).

**Recommendation: no edge found, close as tested.** The systematic positive-divergence bias is worth
noting for anyone extending the trailing-mean/sd proxy (it may indicate the proxy itself is
miscalibrated high, e.g. not accounting for regression-to-mean/blowout garbage-time minutes the way
Kalshi's price implicitly does) but does not by itself indicate tradeable value.

---

## #4 — Season win totals (`KXWNBAWINS`)

### v1 (single open-time snapshot, plug-in binomial) — superseded, kept for the record

First pass: N=26 priced markets, one snapshot each (price at `open_time`), model probability from a
plug-in binomial (estimated win-rate treated as certain). Result looked promising (model Brier
0.1276 vs market's 0.2482, model favored-side right 84% vs market's 60%) but was flagged with three
caveats: tiny N, likely-overconfident probabilities (several were ~0 or ~1), and no correction for
the fact these markets close early once decided. All three caveats turned out to matter — see v2.

### v2 (multi-snapshot, Beta-Binomial, early/late regime split) — the real result

**Sample-size fix** (`tools/research_prediction_market_futures_divergence.R`, rewritten): instead of
one price-at-open-time observation per market, pulled each of the 53 settled markets' FULL daily
candlestick history in one API call (`open_time` → `close_time`), then took one snapshot every 5
days (`SNAPSHOT_STEP_DAYS`, capped at 20/market) — 907 total (market, day) snapshots across the same
53 real markets (~17/market). Each snapshot recomputes the model probability AS OF that exact date
(leakage-free — only games strictly before it). These snapshots are NOT independent within a market
(today's price correlates with tomorrow's, and every snapshot from one market shares the same
eventual outcome), so this doc reports both **pooled** (all 907 rows as if independent — labeled
explicitly as anti-conservative, descriptive only) and **market-clustered** (one number per real
market, N=53 — the number that should actually be trusted for inference) statistics.

**Calibration fix**: replaced the plug-in binomial with a **Beta-Binomial**. Each team's true win
probability gets a `Beta(alpha0, beta0)` prior seeded from that team's real prior-season win rate at
a tunable pseudo-sample-size (`PRIOR_STRENGTH`), updated with real observed wins/losses as of the
snapshot date; the final-win-total distribution over remaining games is the analytically exact
Beta-Binomial, which integrates out win-rate uncertainty instead of treating the point estimate as
truth (the source of v1's near-0/near-1 overconfidence). `PRIOR_STRENGTH` was swept over
{11, 22, 44, 88, 176} pseudo-games rather than asserted — lower values (less trust in the prior,
faster adaptation to real current-season evidence) won on clustered Brier at every value tested, with
11 lowest (clustered model Brier 0.0624 vs market 0.0998) — reported as directional given only ~53
real markets to select from, not a validated hyperparameter (full sweep table saved to
`tools/research_output/prediction_market_futures_divergence_prior_sweep.csv`).

**Critical finding made during THIS run**: at the selected `PRIOR_STRENGTH`, the market's favored
side was right **100%** of the time at every divergence threshold — an implausibly perfect number
that was a red flag, not a result to report at face value. Cause: `KXWNBAWINS` threshold markets
close early the moment the outcome becomes mathematically locked (see method note above), so
snapshots taken close to a market's real `close_time` are close to a trivially certain outcome for
BOTH series — both the model and the market converge toward 0/1 as the answer becomes obvious, which
inflates "who called it right" without testing real forecasting skill. **Fixed** by splitting every
snapshot into EARLY (≥30 days before that market's real close) vs LATE (<30 days before close) and
reporting them separately instead of one blended number.

**Result, EARLY regime only (668 snapshots / 53 markets, the genuine forecasting test):**
- Clustered model Brier **0.0775** vs. market's **0.1122** — model nominally better-calibrated.
- Model's favored side right **75.5%** of the time vs. the market's **96.2%**.

**Result, LATE regime (239 snapshots / 53 markets, sanity check only, NOT a forecasting test):**
Both series are highly accurate (92.5% model, 100% market) as expected once the outcome is
essentially locked — this confirms both series converge correctly, nothing more.

### How Brier score and win-rate can disagree here, and which one to trust

The Beta-Binomial model's probabilities are more moderate (less extreme) than the market's, so on
average it takes a smaller squared-error hit when wrong — hence the lower Brier score. But the
market picks the actually-correct side far more often (96.2% vs 75.5%) even in the early regime.
**For "would following this signal have picked the right team," the win-rate gap is the
decision-relevant number, and it decisively favors the market, not the model.** The Brier-score
edge is real but is a calibration/moderation artifact, not evidence the model knows more than the
market about which team will hit its win total.

**Recommendation: reversed from v1 — no confirmed edge.** The methodologically stronger, larger-N,
better-calibrated re-test does not support hypothesis #4 either. Do not build backtest/staking
infrastructure on this.

---

## What Next Steps #3 (backtest/P&L infra) should do with this

Per the plan's explicit discipline (do not build staking/P&L logic before a real, defensible
divergence is shown): **do not build it for any of #1/#2, #3, or #4.** All four tested game/player
hypotheses close as "no confirmed edge" after appropriately rigorous measurement — including one
(#4) that looked promising on a first pass and did not survive a harder, more honest re-test. That
reversal is itself the most useful finding in this thread: it is a concrete demonstration of why
this repo's own discipline (measure before building staking infra; re-test before trusting a
promising-looking first pass) is load-bearing, not bureaucratic. Any future work on this thread
should stay hypothesis-specific and re-apply the same rigor (real settled outcomes, leakage-free
model probabilities, clustered/regime-aware statistics) rather than assuming a blanket edge from any
single positive-looking number.
