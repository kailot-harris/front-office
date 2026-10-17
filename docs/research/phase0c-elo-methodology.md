# Phase 0c — Elo Rating Methodology Specific to Baseball (GitHub Issue #5)

**Scope**: Live-verify and cite (dated) baseball-specific Elo rating methodology per
`docs/PHASE0_RESEARCH_PLAN.md` §4 — FiveThirtyEight's public MLB Elo methodology, the
starting-pitcher adjustment wrinkle, and park-factor adjustments. Unblocked by issues #2 and #3
(closed); see `docs/research/phase0a-r-packages.md` and `docs/research/phase0a-vendor-api.md` for
the verified data landscape this section's inputs would draw from.

**Non-goal**: this file does not assemble or edit `docs/MLB_REPLICATION_PLAN.md` (does not yet
exist) — that is a later assembly step. This file also does not propose final numeric constants for
an MLB Elo engine; it documents FiveThirtyEight's published approach as a research reference, to be
weighed (and likely re-derived/re-tuned) during any future engine-design phase.

## 1. Live-URL status of FiveThirtyEight's methodology page

Re-verified live on **2026-10-17**: `GET https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/`
returns an HTTP **301 redirect to `https://abcnews.com/politics`**. This confirms the prior run's
finding independently — the canonical FiveThirtyEight methodology URL is no longer live on the
fivethirtyeight.com domain (consistent with 538's broader 2023+ wind-down/absorption into ABC News).
No claim below is sourced from this dead URL.

**Archived substitute actually used**: a Wayback Machine snapshot,
`https://web.archive.org/web/20220511191134/https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/`,
was fetched successfully on **2026-10-17** via `curl` through the Bash tool (the WebFetch tool itself
could not reach `web.archive.org` directly in this environment — same limitation the prior run hit —
but the raw HTML was retrievable via `curl -L` and then parsed for text). **This is an archived
primary source** — the original FiveThirtyEight methodology article as published (dated internally
"Last Edit May 2, 2022" with version history back to 2015), not a secondary summary. All formulas and
figures below marked "[538 archive]" are direct quotes/extractions from that fetched HTML.

Supplementary primary source, fetched live and directly (no archive needed):
`https://github.com/fivethirtyeight/data/blob/master/mlb-elo/README.md`, FiveThirtyEight's own public
data-dictionary README for the `mlb-elo` dataset, fetched 2026-10-17. It independently corroborates
the pitcher-adjustment columns described below.

## 2. FiveThirtyEight's public MLB Elo methodology

**[538 archive, fetched 2026-10-17]** FiveThirtyEight states its model uses Retrosheet game results
and box scores back to 1871 to build "an Elo-based rating system and predictive model for baseball
that accounts for home-field advantage, margin of victory, park and era effects, travel, rest and —
most importantly — starting pitchers." The article's own "References" footer explicitly lists among
its source concepts: *Baseball Prospectus, Baseball-Reference.com, Clay Davenport, FanGraphs,
Retrosheet, Tangotiger / Deadball era, Elo rating, Game Score, Monte Carlo simulations, **Park
factors**, PECOTA* — i.e., park factors is one of the named conceptual building blocks of the model
per 538 itself, not an inference.

Per-game, before simulating, the model adjusts each team's rating for four factors:

- **Home-field advantage**: worth **24 rating points**; reduced to **9.6 rating points** for games
  played without fans in attendance (a COVID-era-specific tweak, version 1.4, dated July 21, 2020 in
  the article's own version history — flagged here as a historical rule change, not necessarily
  current-season behavior).
- **Travel penalty**: "worth up to about 4 points," calculated as `miles_traveled**(1.0/3.0) * -0.31`.
- **Rest**: each day of rest (capped at 3 days) is worth **2.3 points**.
- **Starting pitcher** (see §3 below) — explicitly called out by 538 as having "a much larger effect
  on pregame team ratings and win probabilities than the other three adjustments," with a worked
  example: in June 2000, Pedro Martínez was worth about 109 rating points to the Red Sox each time he
  started — "the equivalent of about a 15 percentage point boost to Boston's chances of winning."

Team Elo ratings themselves carry over between seasons with regression to the mean (reversion
magnitude not reproduced verbatim here — needs re-verification if used, since it was not the focus
excerpt captured), and version 1.3 (dated March 27, 2019) changed the rate at which team ratings move
within a season to three-quarters of their prior speed. 538 also maintains a **simplified** long-run
historical Elo series (visible in their "Complete History of MLB" interactive, back to 1871) that
explicitly **does not** incorporate pitchers, travel, or rest — only the full current-era model
layers those three adjustments on top of a baseline team Elo.

538's companion **"rating" columns** (distinct from the raw Elo columns) are described in the GitHub
data dictionary as using "preseason team projections from several projection systems and account[ing]
for starting pitchers," whereas the plain Elo columns are simpler and only reverted to the mean
between seasons — i.e., 538 runs two parallel rating systems side by side, and the pitcher-aware
layer described in §3 applies most directly to the "rating" system, with Elo itself adjusted similarly
per the methodology article's prose.

## 3. The starting-pitcher adjustment — MLB-specific, no sibling-engine analog

**[538 archive, fetched 2026-10-17]** This is the model's own stated headline differentiator
("most importantly — starting pitchers"). The mechanism, quoted/extracted directly from the archived
article:

> "To generate our pitcher adjustments, we're using a version of Bill James's game scores proposed by
> Tangotiger (and slightly modified by us) to isolate pitching performances. A pitcher's game score
> for each start is calculated with:
> `gameScore = 47.4 + strikeouts + (outs*1.5) – (walks*2) – (hits*2) – (runs*3) – (homeruns*4)`
> ... Like our team ratings, these game scores are normalized for eras and stadiums, so pitchers from
> throughout history can be directly compared with one another. They're also adjusted to take the
> opposing team's offensive strength into account..."

Each start updates the pitcher's **rolling game score (rGS)** — "the model's best guess as to [how a
pitcher] would perform in a typical start" (new/unproven starters are seeded with a below-average rGS
that is more volatile early on). Separately, each **team** maintains its own rGS, aggregating every
game score any of its starters has produced. The team-rating blend is then, verbatim:

> **`ratingAdj = 4.7 * (pitcher_rGS – team_rGS)`**

This is a direct, live-verified citation of the exact weighting formula flagged as an unverified
WebSearch lead in the prior attempt — it is confirmed here against the primary archived 538 source
itself, not merely a secondary mention. A pitcher above his team's own rGS gives the team a bonus that
day; a pitcher below it gives a penalty. 538 reports this pitcher-adjustment layer alone was worth
about a 1-percentage-point improvement in game-call accuracy and a corresponding MSE improvement in
their backtests.

Two further wrinkles confirmed in the same source:
- **Openers** (version 1.5, added April 6, 2022): a starter is projected as an "opener" (expected to
  face only a few batters) via a three-part heuristic (≥5 career appearances as a starter; <2 innings
  in prior 10 appearances; has opened at least once in the last 20 appearances). When a starter is
  projected as an opener, the team uses its **average** pitcher adjustment instead of that individual
  opener's adjustment.
- **Preseason team rGS**: computed as an average of a team's starters' individual rGS values,
  weighted by each pitcher's **projected starts from FanGraphs' depth charts** — directly linking
  this Elo-adjacent system to FanGraphs as an external projections input (consistent with the
  FanGraphs ToS/scraping-risk findings already documented in `docs/research/phase0a-vendor-api.md`,
  which this file does not re-verify).
- In-season game simulations "account for starting pitching matchups," assuming the most-rested
  regular-rotation pitcher starts when a probable starter isn't yet announced, and assuming a
  four-man rotation during the postseason.

**Contrast with sibling NBA/WNBA/NFL Elo engines**: per this repo family's existing NBA/WNBA/NFL Elo
implementations (per the research-plan framing in `docs/PHASE0_RESEARCH_PLAN.md` and this task's
brief), those engines rate team strength only — there is no equivalent "blend a single player's own
rolling performance rating directly into the pregame team rating" step anywhere in that family. MLB's
538 methodology is the only one in the sibling family that does this, and it does so precisely because
a single starting pitcher faces a large share of that game's plate appearances in a way no single
player does in basketball or football — 538's own framing ("most importantly — starting pitchers,"
and the Pedro Martínez example showing a ~109-point / ~15-percentage-point single-player swing) is the
primary-source backing for why this wrinkle has no NBA/WNBA/NFL analog. No NBA/WNBA/NFL methodology
page was found (or expected to exist) with an equivalent per-player rolling-rating blend into team
Elo; this absence is inferred from the sibling repos' known architecture as described in this
project's own planning docs, not from a separate live fetch of each sibling's methodology (out of
scope for this task — this file does not re-verify NBA/WNBA/NFL internals).

## 4. Park-factor adjustments — MLB-specific input, no sibling analog

**[538 archive, fetched 2026-10-17]** Two independent pieces of direct textual evidence from the
primary archived source:

1. The methodology's lead paragraph states the Elo-based system "accounts for home-field advantage,
   margin of victory, **park and era effects**, travel, rest and — most importantly — starting
   pitchers" — park effects are named in the same sentence as the other explicit rating adjustments.
2. The article's own "References" footer explicitly lists **"Park factors"** as one of the named
   underlying concepts (alongside Elo rating, Game Score, PECOTA, etc.), confirming park factors is a
   designed-in input to the model's team-rating normalization, not an incidental mention.
3. Separately, the pitcher game-score formula itself is stated to be "normalized for eras **and
   stadiums**" — i.e., park normalization is applied at the individual-pitcher game-score layer as
   well as at the team-rating layer, so that pitchers (and by extension teams) from different ballparks
   and run-scoring eras can be compared on equal footing before Elo updates are applied.

538's archived article does not spell out the exact park-factor formula/coefficients (e.g., which
specific park-factor source or run-scaling formula is used) in the excerpted methodology text
retrieved here — this should be treated as a gap, not asserted. A deeper design-time follow-up could
search FanGraphs' or Baseball-Reference's own published park-factor methodologies (both maintain
public multi-year park-factor tables) if an actual re-implementation is attempted; that is out of
scope for this Phase 0 citation task, which only needed to confirm that park-factor normalization is
a real, named, MLB-specific rating input per a primary source — which it now is.

**Contrast with sibling engines**: NBA, WNBA, and NFL are each played in a much smaller, closer-to-
standardized set of venues per sport (basketball/football field and court dimensions are
league-mandated to tight tolerances), and none of this family's existing sibling Elo engines (per the
project's own planning docs) carry a park/venue-specific run- or scoring-environment normalization
term. MLB ballparks vary meaningfully in dimensions, altitude, and other park-specific run-scoring
effects (well-documented baseball-analytics phenomenon, reflected in the mere existence of long-running
FanGraphs/Baseball-Reference park-factor tables), which is why 538 built this into both its team-level
and pitcher-level normalization and why no equivalent step exists in the sibling NBA/WNBA/NFL family.

## 5. Summary of what is and isn't settled here

- FiveThirtyEight's full published MLB Elo methodology (home-field, travel, rest, pitcher adjustment,
  park/era normalization, openers, preseason rGS seeding) is confirmed via an **archived primary
  source** (Wayback Machine snapshot of the original 538 article), since the live fivethirtyeight.com
  URL now 301s away from the content entirely.
- The exact starting-pitcher blending formula `ratingAdj = 4.7 * (pitcher_rGS – team_rGS)` is
  confirmed verbatim from that same primary archived source — this was a search-engine-sourced,
  unverified lead in the prior run; it is now a verified citation.
- Park factors are confirmed as a real, named, designed-in MLB-specific input (both in the article's
  lead-paragraph prose and its own references list), but the exact park-factor coefficients/formula
  538 uses were not present in the excerpted methodology text and are flagged as an open gap for any
  future engine-design phase, not fabricated here.
- No numeric constant in this file should be treated as a final tuned value for an MLB Analytics Elo
  engine — these are 538's own published constants for 538's own model, documented here for research
  reference per Phase 0's research-only, no-engine-code scope.

## Sources Consulted

| # | Source | URL | Fetch date | Notes |
|---|---|---|---|---|
| 1 | FiveThirtyEight — live methodology URL (confirms dead/redirected) | `https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/` | 2026-10-17 | Returns HTTP 301 to `https://abcnews.com/politics`; confirmed live via WebFetch, not cited for content. |
| 2 | FiveThirtyEight "How Our MLB Predictions Work" — **archived primary source** | `https://web.archive.org/web/20220511191134/https://fivethirtyeight.com/methodology/how-our-mlb-predictions-work/` | 2026-10-17 (fetch); article itself last-edited by 538 on May 2, 2022 per its own byline | Fetched via `curl` (Bash tool) after direct WebFetch tool access to web.archive.org failed in this environment; HTML parsed to text locally. Primary source for all of §2, §3, §4 except where noted. |
| 3 | FiveThirtyEight `mlb-elo` dataset README (GitHub, public data repo) | `https://github.com/fivethirtyeight/data/blob/master/mlb-elo/README.md` | 2026-10-17 | Fetched live and directly. Corroborates `pitcher1_rgs`/`pitcher2_rgs` and `pitcher1_adj`/`pitcher2_adj` columns, and the Elo-vs-"rating" dual-system distinction. |

**Reused context (not independently re-verified by this file)**: `docs/research/phase0a-vendor-api.md`
and `docs/research/phase0a-r-packages.md` (both fetched/dated 2026-10-17 by prior, already-closed
issues #2 and #3) were read for framing only, per this task's scope — their own findings are not
restated as this file's citations.
