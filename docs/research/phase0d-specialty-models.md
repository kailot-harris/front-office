# Phase 0d Research: Specialty Baseball Model Landscape

**Research date (all fetches below): 2026-10-17**

This file is a live-verified companion to `docs/PHASE0_RESEARCH_PLAN.md` section 5, produced for
GitHub issue #6. It does **not** edit or create `docs/MLB_REPLICATION_PLAN.md` — that document is
assembled later (issue #8) from this and sibling research files. It builds on the verified
R-package/vendor landscape from issue #2 (`docs/research/phase0a-r-packages.md`) and issue #3
(`docs/research/phase0a-vendor-api.md`), both closed as of this writing.

Scope: Marcel projections, PECOTA, bullpen usage/fatigue modeling, and Bayesian/hierarchical
run-scoring models, plus the hard-requirement search for a real ML-vs-baseline MLB win-prediction
citation. Every factual claim below is tied to a source URL and fetch date (2026-10-17 for all,
single research session).

---

## 1. Marcel projections (Tom Tango)

Marcel ("the Monkey Forecasting System") is Tom Tango's deliberately minimal projection baseline —
explicitly designed as "the minimum level of competence that you should expect from any
forecaster," not a sophisticated model
([tangotiger.net/marcel/](https://tangotiger.net/marcel/), fetched 2026-10-17). Tango's own summary:
"It uses 3 years of MLB data, with the most recent data weighted heavier. It regresses towards the
mean. And it has an age factor." ([tangotiger.net/marcel/](https://tangotiger.net/marcel/), fetched
2026-10-17; this exact framing is also echoed by FanGraphs' library writeup,
[library.fangraphs.com — "The Projection Rundown"](https://library.fangraphs.com/the-projection-rundown-the-basics-on-marcels-zips-cairo-oliver-and-the-rest/),
fetched 2026-10-17).

The three named mechanisms, with Tango's own numeric specifics, verified via his original archived
writeup ([tangotiger.net/archives/stud0346.shtml](https://www.tangotiger.net/archives/stud0346.shtml),
fetched 2026-10-17):

- **Recency weighting.** "Weight each season as 5/4/3" — the most recent of the three seasons used
  gets weight 5, the middle season weight 4, the oldest season weight 3 (quoting Tango's own
  example years: "2003 counts as '5' and 2001 counts as '3'"). For pitchers, the weighting scheme is
  lighter-recency-skewed: 3/2/1 instead of 5/4/3 (same source).
- **Regression to the league mean.** Tango's exact mechanism: weight the player's league-average
  rate using that same 5/4/3 process and the player's own PA for each season, then add in a fixed
  1200 PA of league-average performance ("I then forced in that player's league average to come in
  at a total of 1200 PA for each player (2 weights x 600 PA)") — i.e., the blend is weighted-player-
  data vs. 1200 PA of pure league-average data, not a fixed-percentage shrinkage.
- **Age adjustment.** Tango's original piecewise formula: "If over 29, AgeAdj = (age - 29) * .003.
  If under 29, AgeAdj = (age - 29) * .006." Tango later flagged and corrected a sign error in his own
  original write-up, noting the under-29 term "should be 29 - age" rather than "age - 29" (same
  source, same fetch) — worth noting as a documented self-correction, not a fact to silently
  "fix" without citing Tango's own correction.
- Marcel also projects playing time with its own simple formula: "projected PA = 0.5 * 2004PA + 0.1
  * 2003PA + 200" (same source) — i.e., playing-time projection is a separate weighted-recency +
  fixed-offset formula, not derived from the rate-stat weighting above.

**Implication for this repo's eventual build phase:** Marcel is cheap to reproduce exactly (three
years of league + player PA-weighted rate data, one age-curve formula) and is a reasonable minimum
baseline to benchmark any homegrown projection system against, per Tango's own stated intent.

## 2. PECOTA (Baseball Prospectus) — closed-methodology precedent, not reproducible

PECOTA was developed by Nate Silver in 2002–2003 and introduced publicly in the book *Baseball
Prospectus 2003*; Baseball Prospectus has owned it since 2003, with Silver managing it through 2009
([en.wikipedia.org/wiki/PECOTA](https://en.wikipedia.org/wiki/PECOTA), fetched 2026-10-17). Per that
same source, PECOTA's publicly described methodology rests on four components: (1) a **comparable-
players** approach — nearest-neighbor matching against "a database of roughly 20,000 major league
batter seasons since World War II" to find statistically similar historical players; (2) emphasis on
**peripheral/skill statistics** (e.g., strikeout and walk rate for pitchers) rather than noisier
outcome stats; (3) **probability-distribution output** rather than a single point estimate; and (4)
**park, league, and aging adjustments** layered on top.

Critically — and this is the reason PECOTA belongs in this file as a precedent rather than a
build target — Wikipedia's own sourced statement is explicit: "The logic and methodology underlying
PECOTA have been described in several publications, but the detailed formulas are proprietary and
have not been shared with the baseball research community"
([en.wikipedia.org/wiki/PECOTA](https://en.wikipedia.org/wiki/PECOTA), fetched 2026-10-17). PECOTA
has not been discontinued; it continues to operate under Baseball Prospectus with annual updates and
is currently published behind Baseball Prospectus's subscription paywall (same source; also
corroborated by [ESPN's "What is PECOTA, and should you hate it?"](https://www.espn.com/mlb/story/_/id/18636729/what-pecota-hate-it)
and [Baseball Prospectus's own "Basics of Forecasting" explainer](https://www.baseballprospectus.com/news/article/2659/baseball-prospectus-basics-the-science-of-forecasting/),
both surfaced in this research session's search results, fetch date 2026-10-17).

**No implementation detail beyond the above four named components and their general description
should be treated as fact** — the nearest-neighbor similarity-score weighting, the comparable-player
pool construction, and the exact aging-curve math are not publicly published. Any future prototyping
inspired by PECOTA must be built from first principles (e.g., our own comparable-players /
nearest-neighbor system) and explicitly labeled as "PECOTA-inspired," not "a PECOTA reimplementation."

## 3. Bullpen usage/fatigue modeling

Current public research models relief-pitcher fatigue as a function of **recent workload**, not a
single isolated outing. A 2026 analysis reconstructing fatigue states for roughly 33,000 MLB relief
appearances (2019 and 2025 seasons) used: cumulative pitch count over the trailing two and four days,
days of rest since the last appearance, consecutive-day appearance streaks, and each pitcher's
fastball velocity relative to his own seasonal baseline
([insidethepen.com — "What 33,000 Relief Appearances Tell Us About Pitcher Fatigue in the Modern
Era"](https://insidethepen.com/articles/Pitcher-Fatigue-in-the-Modern-Era.html), published
2026-06-30, fetched 2026-10-17). That analysis's own finding is a useful caution against overfitting
a fatigue signal to outcomes: fatigued relievers measurably throw roughly 0.5 mph slower, but the
analysis found actual run-scoring outcomes "largely unchanged" — attributed to managers already
compensating via deployment choices (same source). A separate FanGraphs piece
([fantasy.fangraphs.com — "An Introduction to Fatigue Units"](https://fantasy.fangraphs.com/an-introduction-to-fatigue-units-a-new-method-for-evaluating-workloads/),
fetched 2026-10-17) independently corroborates the pitch-count-driven velocity-decay shape: velocity
decline becomes measurable above roughly 15 pitches in an outing and compounds past 20, with
roughly half the velocity deficit recovering per day of rest thereafter.

**No NBA/WNBA/NFL analog — and why the NFL "short week" comparison is spiritual, not mechanistic.**
NBA/WNBA back-to-backs and NFL short-week (Thursday night) scheduling are the closest surface-level
parallels (a team/player returning to competition on unusually short rest), but the underlying
fatigue mechanism in MLB bullpen usage is structurally different in two ways: (1) MLB relief fatigue
is a **within-roster, per-pitcher arm-stress accumulation signal reset daily by the next day's
workload decision** (a reliever can pitch zero, one, or two games in any given 2–4 day window,
entirely at the manager's discretion), whereas NFL short weeks are a **fixed, schedule-determined,
whole-team recovery-window compression** applied uniformly to all ~46 active players regardless of
individual workload the prior game. (2) The NFL short-week injury literature's own finding cuts
against a naive "less rest = more fatigue-driven risk" story: a peer-reviewed study of four NFL
seasons (2013–2016) found short-rest (Thursday) games had *fewer* reported injuries per team-game
(1.26) than regular-rest games (1.53), not more
([pmc.ncbi.nlm.nih.gov/articles/PMC6676424/ — "Does Short Rest with Thursday Night Games Influence
Injury Rates in the NFL?"](https://pmc.ncbi.nlm.nih.gov/articles/PMC6676424/), fetched 2026-10-17).
That is the opposite causal shape from MLB bullpen fatigue (where accumulated individual pitch-count
load *does* measurably degrade velocity, per the sources above) — so the NFL short-week axis is a
useful "rest-compression" framing device but must not be cited as mechanistic evidence that MLB
bullpen fatigue works the same way. No comparable rested-vs-fatigued relief-pitcher-usage framework
exists in NBA/WNBA public research as of this fetch date; none was found in this session's searches.

## 4. Bayesian/hierarchical run-scoring models (partial pooling)

Partial pooling is well-established in academic sabermetrics as the standard alternative to both
"no pooling" (every player/park estimated independently, noisy for small samples) and "complete
pooling" (one league-wide number for everyone, ignoring real skill variance): each player's rate
parameter is drawn from a shared distribution, and the degree of shrinkage toward the league mean
scales automatically with how much data that player has contributed — players with few batted balls
get pulled harder toward league average than players with large samples
(general mechanism corroborated across multiple sources surfaced in this session, including
[Eric Ma's "Hierarchical baseball" Bayesian Analysis Recipes notebook](https://ericmjl.github.io/bayesian-analysis-recipes/notebooks/hierarchical-baseball/),
fetched 2026-10-17).

Two concrete, dated, peer-reviewed examples of this approach applied to the batter/pitcher/park-type
effects this issue asks about:

- **Jensen, McShane, and Wyner, "Hierarchical Bayesian Modeling of Hitting Performance in
  Baseball," *Bayesian Analysis*, Vol. 4, No. 4, December 2009, pp. 631–652**
  ([arxiv.org/abs/0902.1360](https://arxiv.org/abs/0902.1360);
  journal version at [projecteuclid.org/euclid.ba/1340369815](https://projecteuclid.org/euclid.ba/1340369815);
  both links fetched 2026-10-17, confirmed via search-result metadata since the PDF itself did not
  decode as text in this session's fetch tool). The model places player-level hitting-component rates
  (e.g., strikeout rate, home run rate) in a hierarchy with shared priors, and explicitly incorporates
  park effects, league effects, and player physical attributes (e.g., age, handedness) as adjustment
  layers on top of the pooled player estimates — i.e., partial pooling across players with park/league
  effects layered in, directly matching this issue's "pitcher/batter/park effects" framing (batter
  side; the paper does not model pitchers as its unit of partial pooling).
- **Deshpande and Wyner, "A Hierarchical Bayesian Model of Pitch Framing," *Journal of Quantitative
  Analysis in Sports*, Vol. 13, Issue 3, 2017, pp. 95–112**
  ([arxiv.org/pdf/1704.00823](https://arxiv.org/pdf/1704.00823); journal DOI
  [10.1515/jqas-2017-0027](https://doi.org/10.1515/jqas-2017-0027); fetched 2026-10-17, author/venue
  confirmed via search-result metadata — this paper's PDF also did not decode as text in this
  session's fetch tool). This model estimates an umpire's probability of calling a strike as a
  function of partially-pooled catcher, pitcher, and batter effects plus pitch location and count —
  the pitcher/batter/catcher side of the same partial-pooling family, oriented at the pitch-call
  level rather than full run-scoring, but directly reusable as a template for a run-scoring
  hierarchical model that pools pitcher and batter effects together.

**Caveat on this section:** both PDFs returned corrupted/binary content when fetched directly by this
session's tools, so the author/venue/year/structural-description claims above are sourced from
consistent search-result metadata (arXiv abstract pages, Project Euclid/De Gruyter DOI listings,
and the Deshpande personal publications page) rather than a direct full-text read. These are treated
as live-verified citation metadata (title, authors, venue, year, DOI/arXiv ID all independently
corroborated across 2+ sources each), but the detailed internal model equations were not
independently re-derived from the primary text in this session — flag for a follow-up full-text read
before relying on specific formula details from either paper.

No current academic paper combining partial pooling across *all three* of pitcher, batter, and park
simultaneously for direct team-level run-scoring (rather than a single-side hitting or
pitch-framing model) was found in this session's searches; the two citations above are the closest
verified building blocks.

---

## 5. Hard requirement: ML-vs-baseline MLB win-prediction citation — SEARCH EXHAUSTED, NO QUALIFYING CITATION FOUND

**This is flagged prominently as unresolved, per this issue's own instructions not to fabricate a
citation if a genuine search comes up empty.** This section documents what a thorough, multi-round
live search did and did not find, so a future session does not have to repeat the same dead ends.

**What was searched (2026-10-17, this session):** over a dozen distinct web searches plus direct
fetches of the following candidate papers/preprints, specifically checking each for (a) MLB scope
(not another sport), (b) an explicit Pythagorean-expectation or regression baseline, (c) an
RF/GBM/neural-net model, and (d) real reported MAE/RMSE/R² or equivalent:

| Candidate | Why it does not qualify |
|---|---|
| Lo, Lee, Chen, Hsieh, Chen, Lin, "Application of Machine Learning Models for Baseball Outcome Prediction," *Applied Sciences* 15(13):7081, 2025 (peer-reviewed, MDPI; [doi.org/10.3390/app15137081](https://doi.org/10.3390/app15137081), abstract fetched via Semantic Scholar API 2026-10-17) | Studies the **Chinese Professional Baseball League (CPBL)**, not MLB (859 games, 2021–2023 regular seasons). No Pythagorean baseline — compares decision tree/logistic regression/ANN/RF/XGBoost against each other only. Reports accuracy (0.89–0.93) and AUC-ROC (0.97–0.98), not MAE/RMSE/R². |
| Li, Huang, Li, "Exploring and Selecting Features to Predict the Next Outcomes of MLB Games," *Entropy* 24(2):288, 2022 (peer-reviewed; [pmc.ncbi.nlm.nih.gov/articles/PMC8871522/](https://pmc.ncbi.nlm.nih.gov/articles/PMC8871522/), fetched 2026-10-17) | Game-level MLB (2015–2019), but compares 1DCNN/ANN/SVM/logistic regression to each other, not to a Pythagorean/regression baseline. No RF/GBM. Reports accuracy/AUC only, no MAE/RMSE/R². |
| Elfrink, "Predicting the outcomes of MLB games with a machine learning approach," VU University Amsterdam business-analytics paper, dated 2018-06-13 ([math.vu.nl/~sbhulai/papers/paper-elfrink.pdf](https://www.math.vu.nl/~sbhulai/papers/paper-elfrink.pdf), fetched 2026-10-17) | Game-level MLB (Retrosheet 1930–2016, tested on 2016). Compares XGBoost/Random Forest/GLM, but baseline is "home team always wins" (53.0% accuracy), not Pythagorean. Not peer-reviewed (university course/business-analytics paper, not a journal). Does report RMSE for the regression variant (XGBoost RMSE 4.29 "runs"), but with no Pythagorean comparator. |
| Cui, "Forecasting Outcomes of Major League Baseball Games Using Machine Learning," Wharton (Univ. of Pennsylvania) undergraduate senior thesis, submitted 2020-04-29 ([fisher.wharton.upenn.edu/wp-content/uploads/2020/09/Thesis_Andrew-Cui.pdf](https://fisher.wharton.upenn.edu/wp-content/uploads/2020/09/Thesis_Andrew-Cui.pdf), fetched 2026-10-17) | Game-level MLB (2000–2019). Compares logistic regression/RF/XGBoost/SVM/KNN against a naive "home team always wins" baseline (53.16% accuracy), not Pythagorean. Reports accuracy/AUC/Brier score, not MAE/RMSE/R². Undergraduate thesis, not peer-reviewed. |
| Jia, Wong, Zeng, "Predicting the Major League Baseball Season," Stanford CS229 course final project, Autumn 2013 ([cs229.stanford.edu/proj2013/JiaWongZeng-PredictingTheMajorLeagueBaseballSeason.pdf](https://cs229.stanford.edu/proj2013/JiaWongZeng-PredictingTheMajorLeagueBaseballSeason.pdf)) | Course final project, not peer-reviewed or independently published. 59.6% accuracy after feature selection; no Pythagorean baseline comparison found, no MAE/RMSE/R². |
| Farrell, "Machine Learning Algorithm for Predicting Major League Baseball Team Wins," Cal Poly SLO computer-engineering senior project, June 2019 ([digitalcommons.calpoly.edu/cpesp/309/](https://digitalcommons.calpoly.edu/cpesp/309/), fetched 2026-10-17) | Season-level team win totals (matches this issue's framing), but undergraduate senior project, not peer-reviewed. Abstract available; could not confirm a Pythagorean baseline or specific MAE/RMSE/R² metrics without the full PDF, which this session's tools could not decode. |
| Essery, "mlb-win-forecasting" GitHub repo (personal portfolio project, no stated publication date) ([github.com/samessery/mlb-win-forecasting](https://github.com/samessery/mlb-win-forecasting), fetched 2026-10-17) | Season-level (next-season win% forecast), 2015–2025 data, 150 out-of-sample team-seasons. Reports real RMSE/R² for gradient boosting (RMSE 0.0647, R² 0.39) vs. ridge regression (RMSE 0.0641, R² 0.40) vs. a "last year's win%" baseline (RMSE 0.0737, R² 0.21) — closest candidate found on metrics, but (1) the baseline is "last year's win%," not Pythagorean expectation; (2) it is an unreviewed personal GitHub analysis with no publication venue or explicit date, not "peer-reviewed or reputable" in the sense this issue requires; (3) gradient boosting does not actually outperform the ridge-regression baseline here (R² 0.39 vs 0.40) — illustrative of the broader pattern below, not a clean win for ML. |
| Allen and Savala, "Assessing win strength in MLB win prediction models," arXiv:2511.02815, dated 2025-11-04 ([arxiv.org/html/2511.02815v1](https://arxiv.org/html/2511.02815v1), fetched 2026-10-17) | Game-level MLB (46,159 games, 2001–2019). Compares XGBoost/neural network/logistic regression against a home-team-always-wins null model and FiveThirtyEight's Elo — not Pythagorean. Reports accuracy/AUROC/log-loss/Brier score, not MAE/RMSE/R² (R² ≈ 0.1 reported only for win-probability-vs-score-differential, not a win-total regression). Preprint, not yet confirmed peer-reviewed as of this fetch. |

**Pattern observed across the search:** a clean MLB-specific, peer-reviewed, RF/GBM/NN-vs-Pythagorean
citation with MAE/RMSE/R² — the exact shape of the NFL plan's Weirich et al. citation (Weirich, Kim,
Yoon, Jeong, "Advancing NFL win prediction: from Pythagorean formulas to machine learning algorithms,"
*Frontiers in Sports and Active Living*, September 12, 2025, PMC12463883 — re-confirmed in this
session via direct fetch of
[pmc.ncbi.nlm.nih.gov/articles/PMC12463883/](https://pmc.ncbi.nlm.nih.gov/articles/PMC12463883/),
fetched 2026-10-17, as the shape to mirror, not re-used as the MLB answer) — does not appear to exist
in the publicly indexed literature as of this fetch date. Season-level MLB ML-vs-Pythagorean studies
that were found either lack peer review (personal/student projects) or use a non-Pythagorean baseline
("last year's win%" or "home team wins"); peer-reviewed MLB studies that were found either study a
different league (CPBL) or skip the Pythagorean baseline entirely in favor of comparing ML models to
each other.

**Recommendation:** do not present any of the above as "the" required citation. If a future Phase 0
or build-phase session needs to satisfy this requirement, the most promising next step is checking
*Journal of Quantitative Analysis in Sports* and *Journal of Sports Analytics* issues not surfaced by
general web search (these venues were identified as topically relevant but no MLB-specific
RF/GBM/NN-vs-Pythagorean article from them was found by search), or running a dedicated Google
Scholar / database search with direct access tools not available in this session.

---

## Sources Consulted

| # | Source | URL | Fetch date |
|---|---|---|---|
| 1 | tangotiger.net — Marcel 2012 landing page (Tango's own one-paragraph summary) | https://tangotiger.net/marcel/ | 2026-10-17 |
| 2 | FanGraphs library — "The Projection Rundown" (Marcel/ZiPS/CAIRO/Oliver overview) | https://library.fangraphs.com/the-projection-rundown-the-basics-on-marcels-zips-cairo-oliver-and-the-rest/ | 2026-10-17 |
| 3 | tangotiger.net archives — stud0346.shtml (Tango's original numeric Marcel write-up: 5/4/3 weights, 1200 PA regression, age formula, PA-projection formula) | https://www.tangotiger.net/archives/stud0346.shtml | 2026-10-17 |
| 4 | Wikipedia — PECOTA (ownership history, 4-component methodology summary, proprietary-formula statement) | https://en.wikipedia.org/wiki/PECOTA | 2026-10-17 |
| 5 | ESPN — "What is PECOTA, and should you hate it?" | https://www.espn.com/mlb/story/_/id/18636729/what-pecota-hate-it | 2026-10-17 |
| 6 | Baseball Prospectus — "Baseball Prospectus Basics: The Science of Forecasting" | https://www.baseballprospectus.com/news/article/2659/baseball-prospectus-basics-the-science-of-forecasting/ | 2026-10-17 |
| 7 | InsideThePen — "What 33,000 Relief Appearances Tell Us About Pitcher Fatigue in the Modern Era" (published 2026-06-30) | https://insidethepen.com/articles/Pitcher-Fatigue-in-the-Modern-Era.html | 2026-10-17 |
| 8 | FanGraphs Fantasy — "An Introduction to Fatigue Units: A New Method for Evaluating Workloads" | https://fantasy.fangraphs.com/an-introduction-to-fatigue-units-a-new-method-for-evaluating-workloads/ | 2026-10-17 |
| 9 | PMC — "Does Short Rest with Thursday Night Games Influence Injury Rates in the NFL?" (PMC6676424) | https://pmc.ncbi.nlm.nih.gov/articles/PMC6676424/ | 2026-10-17 |
| 10 | arXiv abstract — Jensen, McShane, Wyner, "Hierarchical Bayesian Modeling of Hitting Performance in Baseball" (0902.1360) | https://arxiv.org/abs/0902.1360 | 2026-10-17 |
| 11 | Project Euclid — same paper, *Bayesian Analysis* Vol 4 No 4 (2009), journal version | https://projecteuclid.org/euclid.ba/1340369815 | 2026-10-17 |
| 12 | arXiv PDF listing — Deshpande & Wyner, "A Hierarchical Bayesian Model of Pitch Framing" (1704.00823) | https://arxiv.org/pdf/1704.00823 | 2026-10-17 |
| 13 | DOI / De Gruyter — same paper, *JQAS* Vol 13 Issue 3 (2017) | https://doi.org/10.1515/jqas-2017-0027 | 2026-10-17 |
| 14 | Eric Ma — "Hierarchical baseball," Bayesian Analysis Recipes (partial-pooling mechanism explainer) | https://ericmjl.github.io/bayesian-analysis-recipes/notebooks/hierarchical-baseball/ | 2026-10-17 |
| 15 | MDPI / Semantic Scholar API — Lo et al., "Application of Machine Learning Models for Baseball Outcome Prediction," *Applied Sciences* 15(13):7081 (2025) — abstract | https://doi.org/10.3390/app15137081 | 2026-10-17 |
| 16 | PMC — Li, Huang, Li, "Exploring and Selecting Features to Predict the Next Outcomes of MLB Games," *Entropy* 24(2):288 (2022) | https://pmc.ncbi.nlm.nih.gov/articles/PMC8871522/ | 2026-10-17 |
| 17 | VU Amsterdam — Elfrink, "Predicting the outcomes of MLB games with a machine learning approach" (2018-06-13) | https://www.math.vu.nl/~sbhulai/papers/paper-elfrink.pdf | 2026-10-17 |
| 18 | Wharton (UPenn) — Cui, "Forecasting Outcomes of Major League Baseball Games Using Machine Learning" senior thesis (2020-04-29) | https://fisher.wharton.upenn.edu/wp-content/uploads/2020/09/Thesis_Andrew-Cui.pdf | 2026-10-17 |
| 19 | Stanford CS229 — Jia, Wong, Zeng, "Predicting the Major League Baseball Season" (Autumn 2013) | https://cs229.stanford.edu/proj2013/JiaWongZeng-PredictingTheMajorLeagueBaseballSeason.pdf | 2026-10-17 |
| 20 | Cal Poly Digital Commons — Farrell, "Machine Learning Algorithm for Predicting Major League Baseball Team Wins" senior project (June 2019) | https://digitalcommons.calpoly.edu/cpesp/309/ | 2026-10-17 |
| 21 | GitHub — Essery, "mlb-win-forecasting" (season-level RF/GBM vs. ridge/last-year's-win% baseline) | https://github.com/samessery/mlb-win-forecasting | 2026-10-17 |
| 22 | arXiv — Allen & Savala, "Assessing win strength in MLB win prediction models" (2511.02815, dated 2025-11-04) | https://arxiv.org/html/2511.02815v1 | 2026-10-17 |
| 23 | PMC — Weirich, Kim, Yoon, Jeong, "Advancing NFL win prediction: from Pythagorean formulas to machine learning algorithms," *Frontiers in Sports and Active Living* (2025-09-12, PMC12463883) — re-confirmed as the citation-shape precedent, not an MLB answer | https://pmc.ncbi.nlm.nih.gov/articles/PMC12463883/ | 2026-10-17 |

## Explicit non-goals of this file

- Does not create or edit `docs/MLB_REPLICATION_PLAN.md`.
- Does not implement, prototype, or reimplement Marcel, PECOTA, any bullpen fatigue score, or any
  Bayesian hierarchical model — this is research only, no `.R` files created or modified.
- Does not invent or substitute a fabricated citation for the Section 5 hard requirement — that
  requirement is explicitly left open per the instructions governing this issue, with the search
  trail documented above so a future session can pick up where this one left off rather than
  repeating the same searches.
- Does not assert the Jensen/McShane/Wyner or Deshpande/Wyner papers' internal model equations as
  independently re-derived fact — both PDFs failed to decode as text in this session's tools; the
  citation metadata (title/authors/venue/year/scope) is corroborated across 2+ independent sources
  each, but a future session should do a direct full-text read before relying on exact formula
  details from either paper.
