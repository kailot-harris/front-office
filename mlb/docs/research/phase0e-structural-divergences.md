# Phase 0e Research: Structural Divergences — MLB vs. NBA/WNBA/NFL Sibling Pipelines

**Research date (all fetches below): 2026-10-17**

This file is a live-verified companion to `docs/PHASE0_RESEARCH_PLAN.md` section 6, produced for
GitHub issue #7. It was blocked on issue #4 (team/player statistics), now closed, whose findings
(`docs/research/phase0b-team-player-stats.md`) are cross-referenced below for the rolling-window-sizing
question. This file does **not** create or edit `docs/MLB_REPLICATION_PLAN.md` — that document is
assembled later from this and sibling research files. It does not re-verify issue #4's own file, and
does not cover Elo methodology (issue #5) or specialty/ML models (issue #6).

## (a) Season length vs. NFL/WNBA/NBA, and why rolling-window sizing cannot be assumed via proportional scaling

Live-verified current season lengths:

| League | Regular-season games | Source |
|---|---|---|
| MLB | 162 | 2026 season confirmed live — Opening Day March 26, 2026, last day of regular season September 27, 2026 |
| NFL | 17 | confirmed live |
| WNBA | 44 | 2026 season confirmed live — 30th season, begins May 8, 2026, runs through September 24, 2026 |
| NBA | 82 | 2026-27 season confirmed live — runs Oct 20, 2026 to Apr 11, 2027 |

A naive proportional-scaling approach would take whatever rolling-window size (in games) was
empirically derived for the NBA (82-game season) or NFL (17-game season) sibling pipeline and scale it
linearly by the games-ratio (e.g., 162/82 × NBA's window, or 162/17 × NFL's window) to get an MLB
window. Per issue #7's own framing (which this file carries forward, not re-derives), that scaling
cannot be assumed valid in either direction, for reasons specific to MLB's schedule structure:

- **Game-to-game noise differs qualitatively, not just in count.** MLB's per-game run-scoring
  variance is driven by a different starting pitcher roughly every game (see section (b)) — a single
  game is a noisier signal of team strength than an NFL game (one game ≈ a much larger share of the
  season) or an NBA/WNBA game (10-12 players rotating, lower single-game variance from any one
  player). A window that linearly scales games-count does not account for this shift in per-game
  signal-to-noise.
- **162 games already supports a longer natural stabilization point for rate stats** (wOBA, FIP, etc.
  — see `docs/research/phase0b-team-player-stats.md`) than a 17-game NFL season could ever reach; that
  asymmetry means the "right" window for MLB might legitimately be a larger absolute number of games
  without being the same *fraction* of the season as NFL's or NBA's windows, or it might be smaller as
  a fraction precisely because 162 games gives enough raw sample size that a shorter recency-weighted
  window out-predicts a longer one on held-out data — the direction is not knowable a priori.
- **The Pythagorean-exponent framing from issue #4 is the direct dependency named in issue #7's body.**
  `docs/research/phase0b-team-player-stats.md` found that the Pythagorean exponent itself is run-environment-dependent
  (Pythagenpat's variable-exponent form, `exponent = ((RS+RA)/G)^0.287`, is preferred over a fixed
  exponent specifically because a fixed exponent distorts in atypical run environments) and explicitly
  declined to assign a final exponent value. Because any rolling-window choice for an MLB win-prediction
  pipeline would be evaluated in part against how well it feeds a Pythagorean-style run-environment
  calculation, the window size and the exponent are coupled unknowns — picking one via sibling-sport
  proportional scaling while the other is still flagged "needs empirical re-derivation" would silently
  bake an unverified assumption into the pipeline.

**Conclusion carried forward from issue #7, not weakened**: MLB's rolling-window size must be
established by empirical validation against held-out prediction accuracy once real MLB data is
available in Phase 1+, not assumed via proportional scaling from any sibling sport's games-count ratio.
This file does not propose a window value.

## (b) Starting-pitcher rotation effects — no analog in NBA/WNBA/NFL

MLB uses a starting-pitcher rotation (commonly five starters, though teams have experimented with
six-man rotations and "bullpen games" in recent seasons) in which a different individual player
dominates the outcome-relevant skill input for a given game far more than any single skater/player does
in the sibling sports:

- **NFL**: a single game is already a large fraction of a 17-game season and already has an
  analogous "who starts at QB" effect, but no per-game *rotation* structure — the same starters play
  most games unless injured.
- **NBA/WNBA**: rotations exist (bench minutes, resting starters) but no single player's per-game
  presence/absence swings win probability on the scale that an elite vs. replacement-level starting
  pitcher does in MLB, and there is no fixed multi-day cyclical schedule analogous to a rotation turn.
- **MLB-specific structural fact**: which of a team's ~5 starters is pitching on a given day is
  itself a schedule-driven, highly predictable, independent variable that has no equivalent "which
  player is starting" structural input in any sibling pipeline's current Elo/rating architecture. Any
  MLB team-strength rating that ignores starting-pitcher identity is missing a signal the sibling
  pipelines never needed to model. (Issue #7 flags this as a question for this file to document, not
  to resolve with a modeling approach — the actual pitcher-adjustment mechanism is Elo-methodology
  territory, scoped separately to issue #5, which this file does not touch.)

## (c) Universal DH — history

Live-verified via WebSearch (2026-10-17):

- The designated hitter was adopted by the American League in **1973**; the National League did not
  use it (except temporarily) for 49 years.
- In **2020**, the COVID-19-shortened season temporarily applied the DH to both leagues as a health/
  roster-flexibility measure.
- In **2021**, the NL reverted to no-DH when the season returned to its normal format.
- In **2022**, as part of the new Collective Bargaining Agreement (announced by Commissioner Rob
  Manfred in February 2022), the universal DH was adopted permanently for both leagues, ending the
  49-year AL/NL split. This is the current, standing rule as of the 2026 season (no reversal found in
  live search).

Structural implication flagged, not resolved here: because the universal DH is uniform across all 30
teams since 2022, any MLB pipeline does not need an AL/NL-conditional DH-adjustment branch for seasons
2022-present — but any historical data spanning pre-2022 seasons crosses this rule boundary and must
not be treated as a single uniform rule regime.

## (d) Current extra-innings rule status — Manfred-man / "ghost runner" — verified live, not assumed

This was explicitly flagged in issue #7 as a live-verification requirement, since the rule's status has
changed across recent seasons and must not be assumed to persist unchanged from any earlier reference
point.

**Regular season (verified live, 2026-10-17, article dated September 29, 2026, referring to the 2026
season)**: the automatic-runner-on-second-base rule **remains in effect** for regular-season extra
innings. Formally, each half-inning after the ninth begins with no outs and a runner placed on second
base, per the Official Baseball Rules (cited live as Rule 7.01(b)(2) in the 2026 rules). The rule has
been in continuous effect since its 2020 pandemic-era introduction and was made **permanent** (i.e., no
longer a temporary/annually-revisited rule) in **February 2023**, per a unanimous vote of MLB's
11-person competition committee.

**Postseason (verified live, same source, same date)**: the automatic-runner rule **does not apply**.
Postseason extra innings are played under traditional rules — innings continue, with no runner placed on
base automatically, until a winner is determined.

This regular-season/postseason split is itself a structural wrinkle with no sibling-sport analog
flagged in this research pass: an MLB pipeline must know not just "is it extra innings" but "is this a
regular-season or postseason game" to apply the correct extra-innings rule, which affects scoring-rate
dynamics (and therefore any run-environment-dependent constant, including the Pythagorean exponent from
section (a)) differently between the two contexts.

## (e) Current postseason bracket format — verified live, not assumed to match WNBA or NFL shapes

Verified live (2026-10-17) against the 2026 MLB postseason specifically — not assumed to match the
2020-era three-wild-card-team-per-league single-game format, nor WNBA's best-of-N series conventions,
nor NFL's single-elimination bracket:

- **12 teams qualify** total — 6 per league (3 division winners + 3 wild-card teams per league). This
  is a larger postseason field than the pre-2022 10-team format and differs structurally from both
  WNBA's best-of-N-series-only bracket (no single-elimination/short-series round) and NFL's
  single-elimination-from-round-one shape.
  - Note: one live search result's wording ("seeds 3 through 6") and another ("two wild card teams per
    league face the third-seeded division winner") were not perfectly consistent on exact seeding
    language across sources — flagged here rather than smoothed over; the series format and round
    counts below were corroborated consistently across all live-fetched sources and are the
    load-bearing facts for this section.
- **Wild Card Series**: best-of-3, hosted entirely by the higher seed (no travel back to the lower
  seed's park within the series).
- **Division Series (ALDS/NLDS)**: best-of-5, 2-2-1 home-field format.
- **League Championship Series (ALCS/NLCS)**: best-of-7, 2-3-2 home-field format.
- **World Series**: best-of-7 between the AL and NL pennant winners.

This bracket shape — a short best-of-3 round feeding into progressively longer best-of-5/best-of-7
rounds — has no direct structural analog in either sibling pipeline's current postseason-modeling logic
(WNBA uses best-of-N series throughout with no single round shorter than best-of-3 at the very start of
its format either, so the early rounds are closer in shape than the later ones; NFL is single-elimination
throughout with no series-within-a-round concept at all). Any MLB postseason win-probability model must
treat round length as a round-specific parameter (3 vs. 5 vs. 7 games) rather than importing a single
series-length assumption from a sibling sport.

## Constants flagged as needing empirical re-derivation (not finalized here)

Per issue #7's explicit instruction and `docs/PHASE0_RESEARCH_PLAN.md`'s constants list, the following
are named only — no final numeric value is assigned in this research pass:

- **Run-environment sigma** (the standard-deviation-of-runs parameter that would feed any
  Pythagorean-style or normal-approximation win-probability calculation) — needs empirical
  re-derivation from live MLB run-scoring data, consistent with section (a)'s and
  `docs/research/phase0b-team-player-stats.md`'s finding that the Pythagorean exponent itself is
  run-environment-dependent and not a fixed historical constant.
- **Home-field advantage** — needs empirical re-derivation from live MLB data; no value is assumed
  from any sibling sport's HFA constant, and this file does not assert one.
- **Rolling-window size** — needs empirical re-derivation against held-out prediction accuracy, per
  section (a) above; explicitly not derivable via proportional scaling from NFL/WNBA/NBA window sizes.
- **Active-roster / 40-man roster constants** — the current *rule values* were verified live (26-man
  active roster from Opening Day through August 31 and in the postseason, expanding to 28 players from
  September 1 through the end of the regular season, with a 40-man reserve/40-man roster as the pool
  from which active-roster players must be drawn) — but any pipeline-internal constant derived *from*
  these rules (e.g., an assumed bullpen-usage denominator, an assumed bench-depth feature) still needs
  empirical re-derivation specific to this pipeline's modeling use, not a value copied from a sibling
  sport's roster-size constant.

## Explicit non-goals of this file

- Does not create or edit `docs/MLB_REPLICATION_PLAN.md`.
- Does not assign final numeric values to run-environment sigma, home-field advantage, rolling-window
  size, or active/40-man roster constants.
- Does not cover Elo methodology (issue #5) or specialty/ML models (issue #6).
- Does not re-verify issue #4's own file (`docs/research/phase0b-team-player-stats.md`); its Pythagorean
  findings are cross-referenced, not re-researched.

## Sources Consulted

| # | Source | URL | Fetch date |
|---|---|---|---|
| 1 | WebSearch — MLB extra innings rule 2026, runner on second, Manfred rule status | (search aggregation; primary corroboration fetched as #2) | 2026-10-17 |
| 2 | Yahoo Sports — MLB playoffs extra innings rules: Is there a ghost runner? (article dated Sept 29, 2026, 2026 postseason) | https://sports.yahoo.com/articles/mlb-playoffs-extra-innings-rules-110029419.html | 2026-10-17 |
| 3 | ESPN — Source: Extra-inning, extra-runner rule to remain (Feb 2023, rule made permanent) | https://www.espn.com/mlb/story/_/id/35652660/source-extra-inning-extra-runner-rule-remain | 2026-10-17 |
| 4 | WebSearch — MLB 2026 postseason format, wild card/division series/LCS/World Series | (search aggregation; primary pages fetched as #5) | 2026-10-17 |
| 5 | Wikipedia — 2026 Major League Baseball postseason | https://en.wikipedia.org/wiki/2026_Major_League_Baseball_postseason | 2026-10-17 |
| 6 | ESPN — 2026 MLB playoffs: Schedule, postseason bracket, standings | https://www.espn.com/mlb/story/_/id/50022544/2026-mlb-playoffs-schedule-how-watch-postseason-world-series-bracket-standings | 2026-10-17 |
| 7 | CBS Sports — 2026 MLB playoff schedule: Dates set for full postseason bracket | https://www.cbssports.com/mlb/news/2026-mlb-playoff-schedule-bracket/ | 2026-10-17 |
| 8 | WebSearch — universal designated hitter MLB history, 2022 National League adoption | (search aggregation; primary pages fetched as #9, #10) | 2026-10-17 |
| 9 | SI.com — Rob Manfred Announces MLB Will Implement Universal DH in 2022 | https://www.si.com/mlb/2022/02/10/mlb-implement-universal-dh-2022-rob-manfred-press-conference-lockout-negotiations | 2026-10-17 |
| 10 | Wikipedia — 2022 Major League Baseball season (universal DH context) | https://en.wikipedia.org/wiki/2022_Major_League_Baseball_season | 2026-10-17 |
| 11 | MLB Trade Rumors — New CBA Officially Introduces Universal Designated Hitter | https://www.mlbtraderumors.com/2022/03/new-cba-officially-introduces-universal-designated-hitter.html | 2026-10-17 |
| 12 | WebSearch — MLB 162-game season vs. NFL 17 / NBA 82 season lengths, 2026 | (search aggregation; primary page fetched as #13) | 2026-10-17 |
| 13 | NBC Insider — How Many Games are in the 2026 MLB Season? Why Baseball Has Longest Season in Pro Sports | https://www.nbc.com/nbc-insider/how-many-games-are-in-the-2026-mlb-season-everything-to-know | 2026-10-17 |
| 14 | Wikipedia — 2026 Major League Baseball season | https://en.wikipedia.org/wiki/2026_Major_League_Baseball_season | 2026-10-17 |
| 15 | WebSearch — 2026 WNBA season game count | (search aggregation; primary page fetched as #16) | 2026-10-17 |
| 16 | CBS Sports — WNBA 2026 schedule: 30th season, 44 games per team | https://www.cbssports.com/wnba/news/wnba-2026-schedule-release-30th-season-begin-may-8-44-games-per-team/ | 2026-10-17 |
| 17 | WebSearch — NBA 2026-27 season length, 82 games | (search aggregation; primary page fetched as #18) | 2026-10-17 |
| 18 | Up In The Rafters — How Many Games in an NBA Season? 2026-27 Length & Dates | https://www.upintherafters.com/nba/how-many-games-are-in-an-nba-season | 2026-10-17 |
| 19 | WebSearch — MLB active roster 26-man / 40-man roster rules 2025-2026 | (search aggregation; primary page fetched as #20) | 2026-10-17 |
| 20 | Gamebook — MLB Roster Size in 2026: 26 Players, 28 in September | https://gamebook.co/guides/how-many-players-on-mlb-team | 2026-10-17 |
| 21 | `docs/PHASE0_RESEARCH_PLAN.md` (local repo file, framing reference, not re-fetched) | n/a (local repo file) | 2026-10-17 |
| 22 | `docs/research/phase0b-team-player-stats.md` (issue #4 findings, cross-referenced for Pythagorean-exponent dependency, not re-researched) | n/a (local repo file) | 2026-10-17 (file's own stated research date) |
