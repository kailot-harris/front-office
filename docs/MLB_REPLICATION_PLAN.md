# MLB Replication Plan

Goal: replicate the NBA Analytics → WNBA Analytics → NFL Analytics port pattern into a new sibling
directory, `MLB Analytics`. This document is Phase 0 research/planning only — it synthesizes the six
completed Phase 0 research files in `docs/research/phase0*.md` (GitHub issues #2-#7) into the single
6-section deliverable requested by issue #8, structured on the template used by
`../NFL Analytics/docs/NFL_REPLICATION_PLAN.md`. **No engine code exists or is created here** —
`config.R`, `run_full_pipeline.R`, and any `.R` script are explicitly out of scope for this phase and
this document.

Every factual claim below carries an inline fetch date and is traceable to a source in the closing
"Sources Consulted" section, which aggregates (not re-derives) the URLs already compiled in the six
input research files. All six input files state a single research date of **2026-10-17**; where a
claim's fetch date differs (e.g. a cited paper's own publication date, or the NFL plan's 2026-09-16
research date used only for structural-shape reference), that is called out explicitly.

---

## 1. Porting Strategy Narrative and Failure Modes to Avoid

### Strategy

MLB Analytics mirrors the NBA → WNBA → NFL architecture directly: a `config.R` single source of truth
for sport-specific constants, a staged `run_full_pipeline.R` DAG wrapped in per-stage `run_stage()`
try/catch, and `.claude/skills/` repo tooling conventions (built in parallel, not specified here). None
of that scaffolding exists yet in this repo and this document does not create it — it exists to give a
future build phase a verified factual foundation, the same role `NFL_REPLICATION_PLAN.md` played for
the NFL port (per that document's own framing, read 2026-10-17 for structural shape only).

Unlike the NBA→WNBA port (same vendor family, 1:1 API mirror) and more like the WNBA→NFL port (a
structurally different data ecosystem), MLB sits in its own middle position: it has a dedicated,
actively maintained R package ecosystem (`baseballr`, per `docs/research/phase0a-r-packages.md`,
fetched 2026-10-17) comparable in spirit to NFL's `nflverse`, but MLB's sport-specific modeling
surface — a starting-pitcher rotation, ballpark-to-ballpark run-scoring variation, a 162-game season,
and a tiered best-of-3/5/7 postseason bracket — has **no single analog** in any one prior sibling port.
Porting must therefore borrow NFL's "choose the right one of several independently-good sources per
data type" posture (not WNBA's "there is basically one source" posture), while separately building
several genuinely new modeling components (starting-pitcher Elo adjustment, park-factor normalization,
round-specific postseason series logic) that have zero prior-sibling code to port from at all.

### Failure modes this port must not repeat (synthesized across all six research files)

1. **Trusting a package's or repo's self-reported "Active" status over live commit/CRAN evidence.**
   `docs/research/phase0a-r-packages.md` (fetched 2026-10-17) directly caught this: `mlbgameday`'s own
   GitHub README self-labels the project "Active," but CRAN shows it archived 2020-07-05 and GitHub
   shows no commits since April 2019 — a stale badge directly contradicted by the commit timeline. The
   same file flags `pitchRx` as CRAN-archived 2023-11-21 with no commits since August 2023. Mitigation:
   verify maintenance status from CRAN archival pages and raw commit timestamps, never from a README's
   self-description, exactly as the NFL plan's nflfastR-deprecated-functions note already warned.
2. **Treating a wrapper package's claimed coverage as equal to the raw vendor API's actual coverage.**
   `docs/research/phase0a-vendor-api.md` (fetched 2026-10-17) found that Baseball Savant's own
   `csv-docs` page states Statcast exit-velocity fields are PITCHf/x-adjusted for 2008-16 and
   true-Statcast only from 2017 onward — a methodology seam inside what a wrapper might otherwise
   present as one uniform "Statcast era." A 2026-specific strike-zone reference-point change (front-of-
   plate through 2025, middle-of-plate in 2026 to align with the ABS system) is a second seam a naive
   port could silently straddle. Mitigation: cross-check wrapper-claimed coverage windows against the
   raw vendor doc before assuming uniformity across a feature's full historical range.
3. **Not uniformly trusting one package's maintenance status across all of its functions.**
   `docs/research/phase0a-r-packages.md` flags that `baseballr`'s MLB-Stats-API/Statcast/FanGraphs/
   Retrosheet functions are reliable, but its Baseball-Reference-backed functions (e.g.
   `bref_team_results()`-style) report live HTTP 403 breakage (issue dated Aug 21, 2026), and its ESPN
   free-agents wrapper returns HTTP 500 for every tested season as of a May 2026 report, retained only
   as a non-functional shim. Mitigation: evaluate maintenance status per-function-family, not per-
   package, before depending on any one `baseballr` call site.
4. **Treating two non-interchangeable metrics as interchangeable.** `docs/research/
   phase0b-team-player-stats.md` (fetched 2026-10-17) is explicit that fWAR (FanGraphs, built from FIP)
   and bWAR (Baseball-Reference, built from runs-allowed/9 plus different defensive-metric providers)
   diverge meaningfully for the same player-season, especially for pitchers — and that bWAR's R-sourcing
   path (`baseballr`'s Baseball-Reference functions) is the same one independently flagged as broken in
   finding #3 above. Mitigation: pick one WAR source explicitly in config, do not average the two or
   treat them as redundant.
5. **Scaling a rolling-window size, or any run-environment constant, proportionally from a sibling
   sport's games-count ratio.** `docs/research/phase0e-structural-divergences.md` (fetched 2026-10-17)
   is explicit that MLB's 162-game season cannot have its rolling-window size derived by linearly
   scaling an NBA (82-game) or NFL (17-game) window, because per-game signal-to-noise differs
   qualitatively (a different starting pitcher most games) and because the window size and the
   Pythagorean exponent are coupled unknowns. Mitigation: re-derive empirically against held-out
   prediction accuracy once real data is available, never by arithmetic from a sibling's window.
6. **Fabricating a citation to fill a documented research gap.** `docs/research/
   phase0d-specialty-models.md` (fetched 2026-10-17) ran an explicit, exhaustive, multi-round search for
   a peer-reviewed MLB-specific ML-vs-Pythagorean-baseline citation (the MLB analog of the NFL plan's
   Weirich et al. citation) and found none that qualifies — see §5 below for the full accounting.
   Mitigation, carried forward explicitly in this plan: do not substitute a non-qualifying candidate
   (wrong league, wrong baseline, no peer review, or missing MAE/RMSE/R²) and label it as equivalent to
   the NFL precedent. This gap is named, not silently dropped, in §5 and the closing Summary Judgment.
7. **The four-independent-ID-scheme join problem, worse here than NFL's four-ID problem.** Per this
   project's own issue #1 framing (carried forward via `docs/research/
   phase0e-structural-divergences.md`'s cross-referencing and this plan's own synthesis — not a new
   finding independently re-verified in this pass): MLB data spans MLB Stats API person IDs, Baseball-
   Reference IDs, FanGraphs IDs, and Retrosheet IDs across `baseballr`'s own multi-vendor function
   family (confirmed in `docs/research/phase0a-r-packages.md`), on top of the same ESPN athlete-ID-via-
   Player-Card-href quirk documented below in §2. The NFL plan's §4 Summary Judgment named NFL's
   analogous ID-fragmentation problem (GSIS/ESPN/PFR/NFL.com/NGS) as that port's single biggest risk,
   solved there by consistent use of `nflreadr::load_ff_playerids()`. MLB has no single bundled
   crosswalk package of that kind confirmed in this research pass — see §6 and the Summary Judgment for
   why this is a live candidate for MLB's single biggest named risk, not merely a restatement of NFL's.

---

## 2. Data-Source Decision Table

### 2a. R-package subsection (per `docs/research/phase0a-r-packages.md`, fetched 2026-10-17)

| R package | Serves | Status (2026-10-17) | Verdict |
|---|---|---|---|
| **baseballr** | MLB Stats API (`mlb_game_pks()`, `mlb_pbp()`, `mlb_schedule()`, `mlb_probables()`, `mlb_standings()`, etc.), Statcast/Savant (`statcast_search()`, `statcast_leaderboards()`, `code_barrel()`), FanGraphs (`fg_batter_leaders()`, `fg_pitcher_leaders()`, `fg_projections()`, `fg_park()`), Retrosheet (`retrosheet_data()`) | CRAN v2.0.0 (2026-08-26); GitHub active through 2026-10-09 | **Use as primary package** for MLB-Stats-API/Statcast/FanGraphs/Retrosheet access. Its Baseball-Reference- and ESPN-backed functions specifically (`bref_team_results()`-style, HTTP 403 as of Aug 21, 2026; ESPN free-agents wrapper, HTTP 500 since a May 2026 report) are unreliable — avoid those specific functions, not the package as a whole. |
| **Lahman** | Static historical `People`/`Batting`/`Pitching`/`Fielding` tables, 1871-present | CRAN v14.0-0 (2026-02-12); data covers only through the **2024 season** as of that release | Use for historical backtesting; **do not assume current-season coverage** — confirm the installed snapshot's season ceiling before relying on it for 2025/2026 data. |
| **pitchRx** | Pre-Statcast PITCHf/x scraping/visualization | CRAN-archived 2023-11-21; no GitHub commits since Aug 2023 | **Do not use for new work.** Superseded by `baseballr`'s Statcast functions. |
| **mlbgameday** | Gameday XML (PITCHf/x-era) | CRAN-archived 2020-07-05; no GitHub commits since April 2019, despite the repo's own README self-labeling it "Active" | **Do not use for new work.** The clearest "don't trust the README" trap found in this research pass. |
| **mlbplotR** | Team-logo plotting (`geom_mlb_logos()`, `load_mlb_teams()`), the baseball analog of `nflplotR` | CRAN v1.2.0 (2025-09-02); 228 commits, 4 open issues, no archival signal | Actively maintained; usable for future dashboard/report visualization work. No confirmed player-headshot geom — re-verify before assuming. |
| **retrosheet** (standalone, distinct from `baseballr::retrosheet_data()`) | `get_retrosheet()` event/gamelog/roster/schedule download | CRAN v1.1.7 (2026-04-20); maintained separately by Colin Douglas | Confirms a separately maintained CRAN package exists; evaluate against `baseballr`'s built-in wrapper for event-file robustness in a later build phase — not decided here. |

### 2b. Direct vendor/API subsection (per `docs/research/phase0a-vendor-api.md`, fetched 2026-10-17)

| Source | Verified finding (fetch date 2026-10-17) | Decision |
|---|---|---|
| **MLB Stats API** (`statsapi.mlb.com/api/v1/`) | Live `GET /schedule?sportId=1&date=...` returns a successful, **unauthenticated**, `publicFacing:true` response; no rate-limit headers observed (not proof none are enforced). Endpoint catalog (`/teams`, `/teams/{id}/roster`, `/game/{gamePk}/boxscore`) corroborated via a community wiki, not MLB's own partner-gated doc site. | Use as the primary live-schedule/box-score source; no auth required for the public v1 surface. |
| **Baseball Savant** (`baseballsavant.mlb.com`) | Bulk CSV via `GET /statcast_search/csv?...`. Coverage seam: 2008-16 fields are PITCHf/x-adjusted, true Statcast only from 2017 onward (do not assume a uniform "2015" start). A 2026 strike-zone reference-point change (front-of-plate through 2025 → middle-of-plate in 2026, aligning with ABS) is a second seam. | Use for pitch-level Statcast features; respect both documented seams in any feature spanning those boundaries. |
| **FanGraphs** | Live ToS (`/about/terms-of-service`) has no explicit anti-scraping clause but broadly prohibits non-interface access and reproduction/derivative works (Sections 6, 17). A FanGraphs engineering blog post separately estimates ≥60% of site traffic is non-human. | **ToS risk, not a clean green light** — prefer `baseballr`'s FanGraphs wrapper functions (rate-limited, sanctioned) over raw scraping. |
| **ESPN MLB injuries feed** (`site.web.api.espn.com/.../baseball/mlb/injuries`) | Live-fetched and independently confirmed (not assumed carried over from NFL/WNBA/NBA): the `athlete` object has no top-level `id` field; the numeric ID must be parsed from the `links[].href` "Player Card" URL's trailing path segment (example: Corbin Burnes → `39878`). | Same href-parsing workaround already proven in sibling repos' injury scrapers — reuse the pattern, do not re-invent it. |
| **The Odds API** | Sport key confirmed `baseball_mlb`. Player-prop market keys follow `{batter|pitcher}_{stat}` (e.g. `batter_hits`, `pitcher_strikeouts`). Same two-tier pattern as NFL/WNBA: bulk `/v4/sports/baseball_mlb/odds` for featured markets, per-event `/v4/sports/baseball_mlb/events/{eventId}/odds` for props. Docs state prop coverage is "currently limited to selected bookmakers and sports, and expanding over time." | Use the same two-endpoint pattern already used for NFL/WNBA; do not assume uniform prop-market coverage across all games/books. |

---

## 3. Team/Player Statistics Worth Surfacing

Per `docs/research/phase0b-team-player-stats.md` (fetched 2026-10-17), cross-referenced against §2a's
confirmed-maintained `baseballr` function families:

- **Pythagorean win expectation.** Three live-verified variants: the original James exponent-2 form
  (RMSE ≈ 4.126 runs), Pythagenport's variable exponent `1.50·log10((RS+RA)/G) + 0.45` (RMSE ≈ 3.991),
  and Pythagenpat's variable exponent `((RS+RA)/G)^0.287`, which Davenport himself endorsed as simpler
  and better across a wider range. A fixed exponent of 1.83 is commonly cited (reportedly used by
  Baseball-Reference) but leading sabermetric sources prefer the variable Pythagenpat form in atypical
  run environments. **None of 2, 1.83, or 0.287 should be hardcoded as a final constant — every one
  needs empirical re-derivation on this repo's own data**, consistent with the NFL plan's §3 convention
  for constants like `NFL_MARGIN_SIGMA`/`NFL_HCA`.
- **Run differential** (`Runs Scored − Runs Allowed`). Strongly correlated with win percentage (one
  cited analysis: R² ≈ 0.846; a secondary source's ≈87%-of-variance/10-runs-per-win claim should be
  re-verified against a primary dataset before being hard-coded). Worth retaining as a baseline feature
  alongside, not instead of, the Pythagorean derivation.
- **wOBA**, FanGraphs' event-weighted on-base metric. Coefficients are year-specific (the commonly
  cited 2013 weights are an example, not a permanent constant) — pull current-year weights from the
  FanGraphs source via `baseballr::fg_batter_leaders()` rather than recomputing from a stale snapshot.
- **wRC+**, built from wOBA with park/league adjustments so it is cross-park/cross-era comparable,
  unlike raw wOBA. Sourced from the same `fg_batter_leaders()` family.
- **FIP**, Tom Tango's formula using only HR/BB/HBP/K, with a year-specific constant (≈3.10 typical)
  that must be re-derived each season from that season's league totals, not hardcoded. Sourced via
  `fg_pitcher_leaders()`.
- **xFIP**, replacing actual HR with flyball-rate × league-average HR/FB rate, on the premise that
  flyball rate is a repeatable skill but HR/FB is mostly not. Same `fg_pitcher_leaders()` family.
- **SIERA**, incorporating batted-ball outcomes and nonlinear K%/BB%/GB%-FB% interactions; FanGraphs'
  own library page describes it as "only marginally more predictive than xFIP." **Flagged unconfirmed**
  — not verified present on `baseballr`'s `fg_pitcher_leaders()` return schema in the source research;
  spot-check before assuming availability without a direct (ToS-risky) FanGraphs scrape.
- **BABIP**, `(H − HR)/(AB − K − HR + SF)`. Use as a luck/regression-to-the-mean flag — especially for
  pitchers, who per FanGraphs' library have "almost no control" over balls in play once hit — not as a
  standalone skill metric.
- **fWAR vs. bWAR — not interchangeable.** fWAR (FanGraphs) is built from FIP (fielding-independent);
  bWAR (Baseball-Reference) is built from runs-allowed/9 including team defense, uses different
  defensive-metric providers (DRS/TZR vs. UZR+OAA+FRM), and additionally adjusts for league strength in
  a way fWAR does not. `baseballr::fg_batter_leaders()`/`fg_pitcher_leaders()` reliably source fWAR;
  **no `baseballr` path to bWAR was confirmed reliable** — its Baseball-Reference-backed functions are
  the same ones independently flagged as reporting live HTTP 403 breakage in §2a. Pick one WAR source
  explicitly; do not average or treat the two as redundant.
- **Statcast barrel rate, exit velocity, xBA/xSLG/xwOBA.** Barrel: roughly 98+ mph exit velocity with a
  26-30° launch-angle window that widens as velocity increases above that floor (definition corroborated
  via search-result text only — a direct `mlb.com/glossary` fetch returned HTTP 406 and should be
  re-verified via an alternate path before treating the exact thresholds as final). xBA/xwOBA are
  built from historical outcomes of comparable batted balls (xwOBA additionally uses Sprint Speed for
  certain batted-ball types), per Baseball Savant's own leaderboard page. Treat the actual-vs-expected
  gap as a leading indicator, per Savant's own framing, not either number alone.

---

## 4. Elo Rating Trajectories Specific to Baseball

Per `docs/research/phase0c-elo-methodology.md` (fetched 2026-10-17). FiveThirtyEight's live
methodology URL now 301-redirects to `abcnews.com/politics` (confirmed dead, consistent with 538's
2023+ wind-down); all findings below are sourced from a **Wayback Machine archived snapshot** of the
original article (`web.archive.org/web/20220511191134/...`, last-edited by 538 May 2, 2022, fetched via
the archive 2026-10-17) plus 538's live `mlb-elo` GitHub data-dictionary README (fetched directly and
live, 2026-10-17).

FiveThirtyEight's model adjusts each team's pregame rating for four factors:

- **Home-field advantage**: worth 24 rating points (9.6 for fan-less games, a COVID-era v1.4 tweak
  dated July 21, 2020).
- **Travel penalty**: up to ~4 points, `miles_traveled**(1.0/3.0) * -0.31`.
- **Rest**: 2.3 points per day of rest, capped at 3 days.
- **Starting pitcher**: explicitly called out by 538 as having "a much larger effect... than the other
  three adjustments" — the headline MLB-specific mechanism, with no analog in any sibling pipeline.

**The starting-pitcher adjustment — no NBA/WNBA/NFL analog.** 538 computes a per-start "game score"
(a Tangotiger-modified Bill James formula): `gameScore = 47.4 + strikeouts + (outs*1.5) – (walks*2) –
(hits*2) – (runs*3) – (homeruns*4)`, normalized for era and stadium. Each start updates a pitcher's
rolling game score (rGS); each team separately tracks its own aggregate rGS. The team-rating blend,
quoted verbatim from the archived primary source:

> `ratingAdj = 4.7 * (pitcher_rGS – team_rGS)`

538 reports this layer alone was worth about a 1-percentage-point accuracy improvement in backtests.
**The `4.7` coefficient, and every other numeric constant in this section (24, 9.6, -0.31, 2.3, 47.4,
and the game-score weights 1.5/2/2/3/4), are 538's own tuned values for 538's own model — none should
be hardcoded as final values for this repo's engine. Each needs empirical re-derivation on this repo's
own data**, exactly the caveat the NFL plan applies to its own `NFL_MARGIN_SIGMA`/`NFL_HCA` constants.
Two further wrinkles confirmed in the same source: an "opener" heuristic (≥5 career starts, <2 innings
in the last 10 appearances, opened at least once in the last 20) that substitutes the team's average
pitcher adjustment for an individual opener's; and preseason team rGS computed from FanGraphs depth-
chart projected starts (linking this system to the FanGraphs ToS-risk finding in §2b).

Per this repo-family's known NBA/WNBA/NFL Elo architecture (inferred from this project's own planning
docs, not independently re-fetched from each sibling's internals in this pass), none of those engines
blend a single player's own rolling performance rating directly into the pregame team rating — MLB's
538 methodology is the only one in the family that does this, because a single starting pitcher faces a
large share of a game's plate appearances in a way no single basketball or football player does.

**Park-factor adjustments — also MLB-specific, no sibling analog.** 538's lead paragraph and its own
References footer both name "park and era effects" / "Park factors" as designed-in model inputs; the
pitcher game-score formula itself is "normalized for eras and stadiums." The archived source does not
spell out 538's exact park-factor coefficients or formula — **this remains an open gap**, not asserted
here, flagged for a future design-time follow-up against FanGraphs' or Baseball-Reference's own
published park-factor tables. NBA/WNBA/NFL venues are much closer to standardized by rule, so none of
those sibling Elo engines carry an equivalent park/venue-specific run-scoring normalization term.

---

## 5. Specialty Baseball Models Worth Prototyping

Per `docs/research/phase0d-specialty-models.md` (fetched 2026-10-17):

- **Marcel projections** (Tom Tango). Deliberately minimal, reproducible baseline: 3 years of league +
  player data, recency-weighted 5/4/3 (batters) or 3/2/1 (pitchers); regression to the mean via a fixed
  1200 PA of league-average performance blended in (not a fixed-percentage shrinkage); an age-adjustment
  formula (`AgeAdj = (age-29)*.003` if over 29, `(age-29)*.006` if under 29 — Tango himself later flagged
  a sign error in his own original under-29 term). **Cheap to reproduce exactly and a reasonable minimum
  baseline** to benchmark any homegrown projection system against, per Tango's own stated intent. As
  with the Elo and Pythagorean constants above, Tango's specific weights (5/4/3, 3/2/1, 1200 PA,
  .003/.006) are source constants to replicate as a baseline, not final tunable values for this repo
  without their own empirical check.
- **PECOTA** (Baseball Prospectus). A closed-methodology precedent, not a build target: Wikipedia's own
  sourced statement is that "the detailed formulas are proprietary and have not been shared with the
  baseball research community." Four named components (nearest-neighbor comparable players,
  peripheral/skill-stat emphasis, probability-distribution output, park/league/aging adjustments) are
  public; the weighting/matching math is not. Any PECOTA-inspired prototype must be built from first
  principles and labeled "PECOTA-inspired," not "a PECOTA reimplementation."
- **Bullpen usage/fatigue modeling.** A 2026 analysis (published 2026-06-30, fetched 2026-10-17)
  reconstructing ~33,000 relief appearances (2019 and 2025 seasons) models fatigue from trailing
  2-and-4-day cumulative pitch counts, days of rest, consecutive-appearance streaks, and fastball
  velocity relative to seasonal baseline — finding fatigued relievers throw ~0.5 mph slower but that
  run-scoring outcomes were "largely unchanged" (managers already compensate via deployment choices).
  **No NBA/WNBA/NFL analog, and the NFL "short week" comparison is spiritual, not mechanistic**: MLB
  relief fatigue is a within-roster, per-pitcher, daily-reset arm-stress signal entirely at manager
  discretion, whereas NFL short weeks are a fixed, schedule-determined, whole-team compression applied
  uniformly — and a peer-reviewed NFL study (PMC6676424) found short-rest games actually had *fewer*
  injuries per team-game (1.26 vs. 1.53), the opposite causal shape from MLB's pitch-count-driven
  velocity decay. Treat NFL's rest axis as a useful framing device only, not evidence the mechanisms
  match.
- **Bayesian/hierarchical (partial-pooling) run-scoring models.** Well-established in academic
  sabermetrics as the standard middle ground between no-pooling (noisy for small samples) and
  complete-pooling (ignores real skill variance). Two concrete peer-reviewed examples: Jensen, McShane,
  and Wyner, "Hierarchical Bayesian Modeling of Hitting Performance in Baseball," *Bayesian Analysis*
  Vol. 4 No. 4 (Dec. 2009), pp. 631-652 (batter-side partial pooling with park/league/age/handedness
  layers); and Deshpande and Wyner, "A Hierarchical Bayesian Model of Pitch Framing," *Journal of
  Quantitative Analysis in Sports* Vol. 13 Issue 3 (2017), pp. 95-112 (partially-pooled catcher/pitcher/
  batter effects at the pitch-call level). Both papers' PDFs failed to decode as text in the research
  session's tools, so author/venue/year/scope are corroborated via 2+ independent search-result sources
  each rather than a direct full-text read — a future session should do a full-text read before relying
  on either paper's exact internal equations. **No paper combining partial pooling across pitcher,
  batter, and park simultaneously for direct team-level run-scoring was found**; these two are the
  closest verified building blocks, not a ready-made run-scoring model.

### Unresolved gap: no qualifying MLB ML-vs-Pythagorean-baseline citation (open item, not fabricated)

The research explicitly needed an MLB analog of the NFL plan's Weirich et al. citation (§5 of
`NFL_REPLICATION_PLAN.md`: RF and a neural net beating a Pythagorean baseline on MAE/RMSE/R² for NFL
team win-percentage). **After searching and directly fetching over a dozen candidates, no qualifying
peer-reviewed MLB-specific citation was found** that combines (a) MLB scope, (b) a Pythagorean-
expectation baseline specifically, (c) an RF/GBM/NN model, and (d) real reported MAE/RMSE/R². Specific
candidates checked and why each fails, per `docs/research/phase0d-specialty-models.md`:

| Candidate | Fails because |
|---|---|
| Lo et al., *Applied Sciences* 15(13):7081 (2025) | CPBL (Taiwan), not MLB; no Pythagorean baseline; reports accuracy/AUC only |
| Li, Huang, Li, *Entropy* 24(2):288 (2022) | MLB game-level, but no Pythagorean baseline, no RF/GBM, accuracy/AUC only |
| Elfrink (VU Amsterdam, 2018) | Baseline is "home team always wins," not Pythagorean; not peer-reviewed |
| Cui (Wharton senior thesis, 2020) | Same non-Pythagorean baseline; not peer-reviewed |
| Jia, Wong, Zeng (Stanford CS229, 2013) | Course project, not peer-reviewed; no Pythagorean baseline |
| Farrell (Cal Poly senior project, 2019) | Not peer-reviewed; full PDF metrics undecoded |
| Essery, "mlb-win-forecasting" (GitHub) | Baseline is "last year's win%," not Pythagorean; unreviewed personal project; GBM does not even beat the baseline (R² 0.39 vs 0.40) |
| Allen & Savala, arXiv:2511.02815 (2025) | Baseline is a null model and 538's Elo, not Pythagorean; reports accuracy/AUROC/Brier, not MAE/RMSE/R² |

**This gap must survive into any downstream engine-design decision rather than being silently dropped
or filled with a fabricated citation.** If a future session resolves it, the most promising unexplored
avenue is a dedicated *Journal of Quantitative Analysis in Sports* / *Journal of Sports Analytics*
search via database access tools not available in this research session.

---

## 6. Structural Divergences from NBA/WNBA/NFL

Per `docs/research/phase0e-structural-divergences.md` (fetched 2026-10-17):

1. **Season length and rolling-window sizing cannot be derived by proportional scaling.** Live-verified
   current season lengths: MLB 162 games, NFL 17, WNBA 44, NBA 82. A naive linear games-ratio scale from
   any sibling's empirically-derived window is invalid because (a) MLB's per-game signal-to-noise is
   qualitatively different — a different starting pitcher most games — and (b) the rolling-window size
   and the Pythagorean exponent are coupled unknowns (§3's Pythagenpat exponent is itself run-
   environment-dependent). **Conclusion carried forward unweakened: MLB's rolling-window size must be
   empirically validated against held-out prediction accuracy once real data is available, not assumed
   via proportional scaling** — directly mirroring the caution the NFL plan applies to its own
   window-sizing question in §4.3 of `NFL_REPLICATION_PLAN.md`.
2. **Starting-pitcher rotation effects have no NBA/WNBA/NFL analog.** Which of a team's ~5 starters
   pitches on a given day is a schedule-driven, highly predictable, independent variable with no
   equivalent "which player is starting" structural input anywhere in the sibling family's current
   rating architecture — NFL's closest parallel (starting QB) has no *rotation* structure, and NBA/WNBA
   rotations don't swing single-game win probability on a comparable scale. The actual pitcher-
   adjustment modeling mechanism is Elo-methodology territory (§4 above), not resolved here.
3. **Universal DH, verified current, with a rule-regime boundary.** AL adopted DH in 1973; NL did not
   (except COVID-2020) for 49 years; universal DH became permanent for both leagues in 2022 per the new
   CBA. Any pipeline spanning pre-2022 data crosses this boundary and cannot treat DH rules as uniform
   across all historical seasons.
4. **Extra-innings "ghost runner" rule — verified live, regular-season/postseason split.** The
   automatic-runner-on-second rule (Official Baseball Rules 7.01(b)(2)) remains in effect for regular-
   season extra innings as of the live-verified 2026 season (made permanent February 2023 by unanimous
   competition-committee vote) but **does not apply in the postseason**, where extra innings play under
   traditional rules. A pipeline must know not just "is it extra innings" but "regular season or
   postseason" — this has no sibling-sport analog and affects any run-environment-dependent constant,
   including the Pythagorean exponent.
5. **Postseason bracket shape — tiered best-of-3/5/7, no sibling analog.** 12 teams qualify (6 per
   league: 3 division winners + 3 wild cards). Wild Card Series: best-of-3, hosted entirely by the
   higher seed. Division Series: best-of-5, 2-2-1. Championship Series: best-of-7, 2-3-2. World Series:
   best-of-7. This progressively-longer-series shape has no direct analog in WNBA's best-of-N-throughout
   bracket or NFL's single-elimination-throughout bracket — any MLB postseason win-probability model
   must treat round length as a round-specific parameter (3 vs. 5 vs. 7), not a single imported
   series-length assumption.
6. **Constants flagged for empirical re-derivation, not finalized in any research file:** run-
   environment sigma, home-field advantage, rolling-window size, and any pipeline-internal constant
   derived from the (live-verified) 26-man/28-man-September/40-man roster rules. None of these should be
   copied from a sibling sport's equivalent constant.
7. **The four-independent-ID-scheme problem, worse than NFL's.** Per issue #1's own framing (carried
   forward in this plan's §1 item 7, not independently re-verified in this research pass): MLB Stats API
   IDs, Baseball-Reference IDs, FanGraphs IDs, and Retrosheet IDs are all in active use across
   `baseballr`'s own function families (§2a), stacked on top of the same ESPN Player-Card-href ID quirk
   (§2b) the sibling repos already solved with a regex workaround. Unlike NFL, **no single bundled
   ID-crosswalk package analogous to `nflreadr::load_ff_playerids()` was confirmed to exist for MLB** in
   this research pass — this is a named open risk, not a solved problem, carried into the Summary
   Judgment below.

---

## Summary Judgment

Each prior sibling port named one dominant risk: WNBA's was data scarcity (ESPN as the only real
option); NFL's was data abundance with fragmented identifier schemes, solved by consistently using
`nflreadr::load_ff_playerids()`. **MLB's single biggest risk, named here as the one this plan commits
to, is the combination of (a) a starting-pitcher-driven team rating with no sibling-engine precedent at
all and (b) an identifier-fragmentation problem that is actively worse than NFL's, because no
MLB-equivalent bundled crosswalk package (an `nflreadr::load_ff_playerids()` analog) was confirmed to
exist.** The starting-pitcher Elo adjustment (§4) is not an incremental feature addition the way NFL's
EPA/CPOE features were on top of WNBA's box-score-only features — it requires building and tuning an
entirely new per-player rolling-rating-blend mechanism (538's own `4.7 * (pitcher_rGS – team_rGS)`
formula, itself not reusable as a final constant) from zero prior-sibling code, at the same time a build
phase must also solve a four-ID join problem (MLB Stats API / Baseball-Reference / FanGraphs /
Retrosheet / ESPN-href) without the one piece of tooling (a bundled crosswalk) that made NFL's
equivalent problem tractable. These two risks compound: the pitcher-rating mechanism itself depends on
correctly joining pitcher identity across at least the MLB Stats API and FanGraphs (for preseason rGS
seeding via FanGraphs depth-chart projections, per §4) — so a silent ID-join failure here would not just
corrupt a downstream feature the way it might in NFL, it would corrupt the single most important rating
signal in the entire model, by 538's own account ("most importantly — starting pitchers"). The
unresolved ML-vs-Pythagorean-baseline citation gap (§5) is a real, honestly-documented open item, but it
is a research-literature gap rather than an engineering risk the pipeline itself must solve correctly on
day one — it is named explicitly above but is not the risk this plan designates as MLB's biggest.

---

## Explicit Non-Goals of This Document

Consolidated from the six input research files' own non-goals sections, which this document inherits
rather than relaxes:

- Does not create or modify `config.R`, `run_full_pipeline.R`, or any `.R` engine script — no engine
  code exists in this repo as of this document, and none is created here.
- Does not assert a final numeric value for any constant flagged "needs empirical re-derivation"
  above: the Pythagorean exponent (§3), any 538 Elo constant including the `4.7` pitcher-adjustment
  coefficient (§4), Marcel's weighting constants (§5), or run-environment sigma / home-field advantage
  / rolling-window size / roster-derived constants (§6). All require re-derivation against this
  repo's own data in a future build phase.
- Does not fabricate or substitute a non-qualifying citation for the unresolved MLB ML-vs-Pythagorean
  win-prediction gap (§5) — the gap is named explicitly and left open, not silently dropped.
- Does not sign up for, authenticate against, or use credentials for any vendor (MLB Stats API,
  Baseball Savant, FanGraphs, ESPN, The Odds API) — §2's findings are from public documentation and
  unauthenticated endpoints only.
- Does not independently re-verify NBA/WNBA/NFL sibling-engine internals — comparisons in §1 and §6 are
  drawn from this project's own planning docs and the NFL plan's published structure, not a fresh audit
  of those repos.
- Does not decide between `baseballr`'s built-in Retrosheet wrapper and the standalone `retrosheet`
  package (§2a), nor between fWAR and bWAR as a build-phase default (§3) — both are named open
  decisions for a future phase, not resolved here.
- Does not re-fetch or re-verify the six input research files' own citations beyond the two spot-checks
  logged under "Spot-checks performed during assembly" below — their findings are aggregated, not
  re-derived.

---

## Sources Consulted

All URLs below are aggregated verbatim from the six input research files' own "Sources Consulted"
tables (`docs/research/phase0a-r-packages.md`, `phase0a-vendor-api.md`, `phase0b-team-player-stats.md`,
`phase0c-elo-methodology.md`, `phase0d-specialty-models.md`, `phase0e-structural-divergences.md`), all
fetched 2026-10-17 unless otherwise noted. None were independently re-fetched for this assembly step
except as noted under "Spot-checks performed during assembly" below.

**R packages (phase0a-r-packages.md):**
- https://cran.r-project.org/web/packages/baseballr/index.html
- https://www.r-pkg.org/pkg/baseballr
- https://cran.r-project.org/web/packages/baseballr/baseballr.pdf
- https://github.com/BillPetti/baseballr
- https://github.com/BillPetti/baseballr/commits/master
- https://billpetti.github.io/baseballr/reference/index.html
- https://github.com/BillPetti/baseballr/issues
- https://github.com/BillPetti/baseballr/issues/60
- https://cran.r-project.org/web/packages/Lahman/index.html
- https://cran.r-project.org/web/packages/Lahman/Lahman.pdf
- https://github.com/cran/Lahman
- https://cran.r-project.org/package=pitchRx
- https://github.com/cpsievert/pitchRx/commits/master
- https://github.com/cpsievert/pitchRx
- https://github.com/keberwein/mlbgameday
- https://cran.r-project.org/package=mlbgameday
- https://github.com/keberwein/mlbgameday/commits/master
- https://cran.r-project.org/package=mlbplotR
- https://cran.r-project.org/web/packages/mlbplotR/mlbplotR.pdf
- https://github.com/camdenk/mlbplotR
- https://cran.r-project.org/package=retrosheet
- https://github.com/colindouglas/retrosheet

**Vendor/API (phase0a-vendor-api.md):**
- https://statsapi.mlb.com/api/v1/schedule?sportId=1&date=2026-10-17
- https://github.com/toddrob99/MLB-StatsAPI/wiki/Endpoints
- https://baseballsavant.mlb.com/csv-docs
- https://www.fangraphs.com/about/terms-of-service
- https://blogs.fangraphs.com/the-state-of-fangraphs-2026/
- https://site.web.api.espn.com/apis/site/v2/sports/baseball/mlb/injuries
- https://the-odds-api.com/sports/mlb-odds.html
- https://the-odds-api.com/liveapi/guides/v4/
- https://the-odds-api.com/sports-odds-data/betting-markets.html

**Team/player statistics (phase0b-team-player-stats.md):**
- https://en.wikipedia.org/wiki/Pythagorean_expectation
- https://www.baseball-reference.com/bullpen/Pythagorean_Theorem_of_Baseball
- https://library.fangraphs.com/offense/woba/
- https://library.fangraphs.com/pitching/fip/
- https://library.fangraphs.com/pitching/babip/
- https://library.fangraphs.com/pitching/siera/
- https://library.fangraphs.com/pitching/xfip/
- https://www.baseball-reference.com/about/war_explained_comparison.shtml
- https://www.mlb.com/glossary/statcast/barrel (attempted; HTTP 406, not retrieved)
- https://baseballsavant.mlb.com/leaderboard/expected_statistics
- https://en.wikipedia.org/wiki/Run_differential

**Elo methodology (phase0c-elo-methodology.md):**
- https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/ (dead; 301 to abcnews.com/politics; not cited for content)
- https://web.archive.org/web/20220511191134/https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/ (archived primary source used for all §4 content)
- https://github.com/fivethirtyeight/data/blob/master/mlb-elo/README.md

**Specialty models (phase0d-specialty-models.md):**
- https://tangotiger.net/marcel/
- https://library.fangraphs.com/the-projection-rundown-the-basics-on-marcels-zips-cairo-oliver-and-the-rest/
- https://www.tangotiger.net/archives/stud0346.shtml
- https://en.wikipedia.org/wiki/PECOTA
- https://www.espn.com/mlb/story/_/id/18636729/what-pecota-hate-it
- https://www.baseballprospectus.com/news/article/2659/baseball-prospectus-basics-the-science-of-forecasting/
- https://insidethepen.com/articles/Pitcher-Fatigue-in-the-Modern-Era.html (published 2026-06-30)
- https://fantasy.fangraphs.com/an-introduction-to-fatigue-units-a-new-method-for-evaluating-workloads/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC6676424/
- https://arxiv.org/abs/0902.1360
- https://projecteuclid.org/euclid.ba/1340369815
- https://arxiv.org/pdf/1704.00823
- https://doi.org/10.1515/jqas-2017-0027
- https://ericmjl.github.io/bayesian-analysis-recipes/notebooks/hierarchical-baseball/
- https://doi.org/10.3390/app15137081
- https://pmc.ncbi.nlm.nih.gov/articles/PMC8871522/
- https://www.math.vu.nl/~sbhulai/papers/paper-elfrink.pdf
- https://fisher.wharton.upenn.edu/wp-content/uploads/2020/09/Thesis_Andrew-Cui.pdf
- https://cs229.stanford.edu/proj2013/JiaWongZeng-PredictingTheMajorLeagueBaseballSeason.pdf
- https://digitalcommons.calpoly.edu/cpesp/309/
- https://github.com/samessery/mlb-win-forecasting
- https://arxiv.org/html/2511.02815v1
- https://pmc.ncbi.nlm.nih.gov/articles/PMC12463883/ (NFL precedent citation, re-confirmed as shape to mirror, not reused as an MLB answer)

**Structural divergences (phase0e-structural-divergences.md):**
- https://sports.yahoo.com/articles/mlb-playoffs-extra-innings-rules-110029419.html
- https://www.espn.com/mlb/story/_/id/35652660/source-extra-inning-extra-runner-rule-remain
- https://en.wikipedia.org/wiki/2026_Major_League_Baseball_postseason
- https://www.espn.com/mlb/story/_/id/50022544/2026-mlb-playoffs-schedule-how-watch-postseason-world-series-bracket-standings
- https://www.cbssports.com/mlb/news/2026-mlb-playoff-schedule-bracket/
- https://www.si.com/mlb/2022/02/10/mlb-implement-universal-dh-2022-rob-manfred-press-conference-lockout-negotiations
- https://en.wikipedia.org/wiki/2022_Major_League_Baseball_season
- https://www.mlbtraderumors.com/2022/03/new-cba-officially-introduces-universal-designated-hitter.html
- https://www.nbc.com/nbc-insider/how-many-games-are-in-the-2026-mlb-season-everything-to-know
- https://en.wikipedia.org/wiki/2026_Major_League_Baseball_season
- https://www.cbssports.com/wnba/news/wnba-2026-schedule-release-30th-season-begin-may-8-44-games-per-team/
- https://www.upintherafters.com/nba/how-many-games-are-in-an-nba-season
- https://gamebook.co/guides/how-many-players-on-mlb-team

**Structural-shape reference only (not an MLB factual source):**
- `../NFL Analytics/docs/NFL_REPLICATION_PLAN.md` (read 2026-10-17 for section ordering/heading style only; its NFL-specific facts, including its 2026-09-16 research date, do not transfer to any MLB claim above)

### Spot-checks performed during assembly

No new WebSearch/WebFetch calls were made during the initial assembly step — all six input files' own
fetch dates and URLs were carried forward as-is, per this task's "pure synthesis" scope. One internal
consistency check was performed by re-reading `phase0d-specialty-models.md` §5 in full before drafting
this plan's §5 gap section, to confirm the "no qualifying citation" conclusion and its candidate table
were reproduced accurately rather than summarized loosely.

**Spot-checks added during the issue #9 self-check pass (2026-10-18):** two of this document's claims
were independently re-verified via live `WebFetch`, per issue #9's own checklist requirement to
spot-check 1-2 citations by re-opening the source URL:
1. `https://baseballsavant.mlb.com/csv-docs` — re-fetched live; confirmed the page still states
   verbatim "Values from 2008-16 are via PitchFX, and adjusted to roughly out-of-hand release point.
   All velocities from 2017 and beyond are Statcast, which are reported out-of-hand," matching §2b's
   claim exactly.
2. `https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/` — re-fetched live; confirmed
   it still returns an HTTP 301 redirect to `https://abcnews.com/politics`, matching §4's claim that
   the live URL is dead and all Elo-methodology content is sourced from the archived Wayback snapshot
   instead.

Both spot-checks passed — no correction to this document's claims was needed as a result.
