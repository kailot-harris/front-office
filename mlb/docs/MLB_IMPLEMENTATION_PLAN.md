# MLB Implementation Plan — Phase 1 through N

**Status**: planning document only. **Writes no code.** Per the Phase 0 hard-boundary rule, this
repo still has no `config.R`, `run_full_pipeline.R`, or any engine script as of this writing — this
document specifies what Phase 1 onward will build, it does not build it. Phase 0 (research,
issues #1–#10) is the sole prerequisite and is complete: `docs/MLB_REPLICATION_PLAN.md` is the
single source of truth every phase below cites back to; re-read it (not this document) for the
underlying evidence, dates, and sources.

**Numbering note**: this repo's Phase 0 was the research epic (issues #1–#10). Phases 1–N below are
the *engine-build* epic that starts only after a human confirms Phase 0's deliverable is accepted.
This mirrors the NFL Analytics repo's own history, where its own "Phase 0" (scaffold/config/research)
was followed by `docs/task_assignments_phase0.md` through `_phase8.md` — each of those files' own
*titles* use a one-ahead numbering ("Phase 1" through "Phase 9") because that repo's first
task-assignments file predates a scaffolding skill's "start counting from 0" convention. This
document uses **plain sequential numbering starting at Phase 1** for the first engine-build wave, to
avoid repeating that off-by-one naming confusion here.

## How to use this document

Each phase below is a roadmap entry, not a dispatch-ready brief: goal, scope, which
`MLB_REPLICATION_PLAN.md` section(s) it must build from, which prior-sibling script (if any) it
ports versus builds new, and the specific open risks/constants that phase inherits and must not
silently resolve by copying a number from this document or a sibling repo. When a phase is actually
about to start, write that phase's own `docs/task_assignments_phaseN.md` (wave breakdown, file
ownership, interface contracts, per the `subagent-brief`-adjacent convention used in the sibling
repos) — do not treat this document's phase descriptions as a substitute for that per-phase
dispatch-level detail.

## Dependency graph

```
Phase 1: Data foundation — ingestion scripts + ID-crosswalk utility + pipeline skeleton
   |
Phase 2: Rating engine — Pythagorean baseline + Elo (starting-pitcher adjustment, park factors)
   |
   +-- Phase 3: Specialty models — Marcel baseline, bullpen fatigue signal     [parallel with Phase 4 once Phase 2 lands]
   |
Phase 4: Postseason bracket simulator (best-of-3/5/7, regular/postseason ghost-runner split)
   |
Phase 5: Risk management engine        (sport-agnostic port — no hard dependency on Phase 2-4 math,
   |                                     but needs Phase 1's config/cache conventions in place)
Phase 6: Market odds engine            (depends on Phase 2's win-probability output + Phase 1's
   |                                     Odds API credential)
Phase 7: Discord alert dispatcher      (depends on Phase 6's value-bet cache)
   |
Phase 8: Early-season calibration review (decision point, not a guaranteed build — see below)
   |
Phase 9+: Deferred / idea-stage (visualizations, dashboards — not scoped until Phase 1-8 ship)
```

Phases 3 and 4 are parallelizable once Phase 2 lands (disjoint files, both read Phase 2's rating
output, neither writes to it). Phases 5-7 are the sport-agnostic/mostly-port chain and can start
as soon as Phase 1's config/cache scaffolding exists, in parallel with Phases 2-4, **except** Phase 6
needs Phase 2's win-probability output before it can compute real EV (it can be scaffolded against a
stub earlier, per the NFL Phase 1 precedent of writing `run_full_pipeline.R` as a skeleton before all
stages exist).

---

## Phase 1 — Data Foundation: Ingestion Scripts + ID-Crosswalk Utility + Pipeline Skeleton

**Goal**: stand up `config.R`, the first real ingestion scripts, and the pipeline-orchestration
skeleton — the same role NFL's Phase 1 played, per `docs/research/...` precedent reviewed in Phase 0.

**Source**: `MLB_REPLICATION_PLAN.md` §2 (data-source decision table — `baseballr` function
families, MLB Stats API, Baseball Savant, FanGraphs, ESPN injuries, The Odds API), §1 failure modes
1–3 (don't trust README "Active" labels; don't assume wrapper coverage matches raw-vendor coverage;
evaluate `baseballr` maintenance per-function-family, not per-package).

**Deliverables**:
- `config.R` — cache paths, team/ID tables (seeded from live `baseballr`/MLB Stats API calls, not
  hand-typed), and placeholders for constants Phase 2+ will empirically derive (do not fill these
  with a number from this document, `MLB_REPLICATION_PLAN.md`, or any sibling repo's `config.R` —
  see "Carried-forward open items" below).
- `mlb_ingest.R` — schedule/box-score ingestion via MLB Stats API (`statsapi.mlb.com/api/v1/`,
  confirmed unauthenticated/public in §2b) and Statcast pitch-level data via `baseballr`'s
  `statcast_search()` family, respecting both documented coverage seams (PITCHf/x-vs-Statcast
  2008-16/2017+ boundary; the 2026 strike-zone reference-point change).
- `mlb_stats_sync.R` — FanGraphs leaderboard sync (`fg_batter_leaders()`, `fg_pitcher_leaders()`,
  `fg_projections()`, `fg_park()`) for wOBA/wRC+/FIP/xFIP/BABIP/fWAR, per §3. Pick fWAR over bWAR as
  the default WAR source at this step (per §3's "no confirmed `baseballr` path to bWAR" finding) —
  this is the one open decision from Phase 0 this phase is expected to actually resolve, not defer
  again.
- `mlb_injury_scraper.R` — ESPN injuries feed, reusing the same Player-Card-href ID-parsing
  workaround already proven in the sibling repos (§2b) — do not re-derive this from scratch.
- **`mlb_id_crosswalk.R`** — a new utility with no sibling-repo analog. Builds and persists a
  join table across MLB Stats API person IDs, FanGraphs IDs, Baseball-Reference IDs, Retrosheet IDs,
  and ESPN athlete IDs (via the href-parsing workaround). This is called out as its own deliverable,
  not folded silently into another script, because the Summary Judgment in `MLB_REPLICATION_PLAN.md`
  names the four-ID-scheme problem (worse than NFL's, with no `nflreadr::load_ff_playerids()`-style
  bundled analog confirmed to exist) as half of MLB's single biggest named risk. Every later phase
  that joins player-level data across sources must use this table, not an ad hoc per-script join.
- `run_full_pipeline.R` — skeleton only, per the sibling convention: wires the above via
  `run_stage()` try/catch, extensible for Phase 2+ stages, not a folder of stubs.

**Port vs. new build**: ingestion/injury scripts follow an established sibling pattern (new code,
familiar shape). The ID-crosswalk utility is **entirely new** — no sibling repo needed one this
explicit, because NFL's four-ID problem had a bundled-package solution and NBA/WNBA didn't have a
comparable fragmentation problem at all.

**Carried-forward open items this phase must not silently resolve**:
- Does not assert a final Pythagorean exponent, Elo constant, or rolling-window size — those are
  Phase 2's job, against real ingested data, not this phase's.
- Does not decide between `baseballr`'s built-in Retrosheet wrapper and the standalone `retrosheet`
  CRAN package (§2a) unless a concrete ingestion need forces the choice; if forced, document the
  choice and why in this phase's own `task_assignments_phase1.md`, not here.
- Lahman package data (if used for historical backtesting) covers only through the 2024 season as
  of its CRAN release (§2a) — do not assume it has current-season rows.

---

## Phase 2 — Rating Engine: Pythagorean Baseline + Elo (Starting-Pitcher Adjustment, Park Factors)

**Goal**: the repo's first real modeling signal — mirrors NFL's Phase 2 (EPA/ratings), but MLB's
version has no sibling precedent for its headline mechanism.

**Source**: `MLB_REPLICATION_PLAN.md` §3 (Pythagorean/Pythagenpat/Pythagenport baseline, run
differential, wOBA/wRC+/FIP/xFIP as feature inputs) and §4 (Elo methodology, starting-pitcher
adjustment, park factors) in full — this phase's single largest source section.

**Deliverables**:
- `mlb_pythag_baseline.R` — Pythagorean win-expectation baseline. Build **the variable-exponent
  Pythagenpat form** as the default (per §3's note that Davenport himself endorsed it as simpler and
  better across a wider run-environment range than a fixed exponent), with the fixed exponent-2 and
  Pythagenport forms available for comparison/backtesting, not deleted.
- `mlb_elo_engine.R` — team Elo rating with the four-factor pregame adjustment from §4: home-field
  advantage, travel penalty, rest, and the **starting-pitcher adjustment**
  (`ratingAdj = C * (pitcher_rGS − team_rGS)`, game score formula per §4) — the mechanism §4 and the
  Summary Judgment both flag as having zero analog anywhere in the NBA/WNBA/NFL rating-engine family.
  This is the phase's hardest build: it requires its own per-pitcher rolling game-score tracker fed
  by Phase 1's ingestion, not just a team-level rating update.
- `tools/derive_mlb_constants.R` — the MLB analog of NFL's `tools/derive_nfl_constants.R`. Empirically
  derives every constant §3/§4 flag as "needs empirical re-derivation" (Pythagorean exponent, HCA
  rating points, travel-penalty coefficient, rest-point value, the starting-pitcher blend coefficient,
  game-score weights) from this repo's own ingested data — **538's own tuned values (4.7, 24, 9.6,
  -0.31, 2.3, 47.4, 1.5/2/2/3/4) are reference starting points for this script's search space, not
  values to hardcode into `config.R` directly.**
- Park-factor normalization: §4 flags 538's exact park-factor coefficients as an unresolved open gap
  (not published in the archived primary source). This phase must either (a) source park factors from
  FanGraphs' or Baseball-Reference's own published tables (§4's suggested follow-up) and document
  that choice, or (b) explicitly defer park-factor normalization to a later phase with a dated note —
  do not silently ship a model with no park adjustment and no note explaining why.

**Port vs. new build**: the Pythagorean baseline is conceptually similar to prior ratings work but
MLB's exponent/form choice is new. The Elo engine's starting-pitcher layer is **entirely new** — flag
it for extra review time in planning, it is not a quick port.

**Carried-forward open items**: the opener-heuristic wrinkle (≥5 career starts, <2 innings in last 10
appearances, opened at least once in last 20 — substitutes team-average pitcher adjustment for an
individual opener's) and preseason rGS seeding from FanGraphs depth-chart projections (linking this
engine to Phase 1's FanGraphs ToS-risk finding) are both named in §4 and must be implemented, not
dropped as edge cases.

---

## Phase 3 — Specialty Models: Marcel Baseline, Bullpen Fatigue Signal

**Goal**: prototype the specialty models §5 flags as worth building, as feature inputs to Phase 2's
rating engine or standalone diagnostic signals — not a replacement for Phase 2's core rating.

**Source**: `MLB_REPLICATION_PLAN.md` §5.

**Deliverables**:
- `mlb_marcel_baseline.R` — Tom Tango's Marcel projection system, reproduced faithfully (3-year
  recency-weighted 5/4/3 batters / 3/2/1 pitchers, 1200 PA regression-to-mean blend, age-adjustment
  formula). Per §5, this is "cheap to reproduce exactly" and valuable specifically *as a benchmark*
  to compare any other projection system against — build it for that role, not as the repo's primary
  projection source.
- `mlb_bullpen_fatigue.R` — relief-pitcher fatigue signal (trailing 2-/4-day cumulative pitch counts,
  days of rest, consecutive-appearance streaks, velocity-vs-seasonal-baseline). Per §5's own finding,
  the underlying 2026 analysis found fatigue measurably slows velocity (~0.5 mph) but run-scoring
  outcomes were "largely unchanged" because managers already compensate via deployment — **this
  script should be built as a diagnostic/monitoring signal, not assumed a priori to be a strong
  predictive feature for win probability**; let backtesting decide its actual feature weight rather
  than assuming it must matter because it exists.

**Explicitly deferred, not a Phase 3 deliverable**: a Bayesian/hierarchical partial-pooling
run-scoring model. §5 names two real peer-reviewed building blocks (Jensen/McShane/Wyner 2009 on
batter-side partial pooling; Deshpande/Wyner 2017 on pitch-framing) but also notes neither paper was
confirmed full-text-readable in the Phase 0 research pass and that no paper combining pitcher/batter/
park pooling for direct team-level run-scoring was found. Treat this as a Phase 3+ research spike if
pursued, not a scheduled deliverable — don't let it block Phase 3's two concrete scripts above.

**Carried-forward open items**: PECOTA is explicitly a closed-methodology precedent only (§5) — any
PECOTA-*inspired* prototype must be built from first principles and labeled as such, never presented
as a PECOTA reimplementation.

**Does not resolve**: the unresolved ML-vs-Pythagorean-baseline citation gap (§5's dedicated
subsection) is a research-literature gap, not an engineering task — it is not this phase's job to
close it, and it must continue to be named (not fabricated) in any future document that references
§5.

---

## Phase 4 — Postseason Bracket Simulator

**Goal**: simulate MLB's postseason, mirroring the role WNBA's and NFL's bracket simulators play in
those repos, but with MLB-specific round-length and rule-regime logic neither prior simulator has.

**Source**: `MLB_REPLICATION_PLAN.md` §6 items 4 and 5.

**Deliverables**:
- `mlb_postseason_simulator.R` — 12-team bracket (6 per league: 3 division winners + 3 wild cards).
  **Round length varies by round** (Wild Card best-of-3, Division Series best-of-5, Championship
  Series best-of-7, World Series best-of-7) — per §6 item 5, this has no direct analog in WNBA's
  best-of-N-*throughout* bracket or NFL's single-elimination-*throughout* bracket, so round length
  must be a round-specific parameter in this simulator's design, not a single imported series-length
  constant from either sibling.
- Regular-season/postseason rule-regime split: the Manfred-man extra-innings rule (automatic runner on
  second) applies in the regular season but **not** in the postseason, per §6 item 4 — any simulated
  extra-inning postseason game must use traditional extra-innings rules, and any run-environment
  constant (e.g. the Pythagorean exponent) that is sensitive to extra-innings frequency must account
  for this split rather than treating "extra innings" as a single uniform state across the season.

**Port vs. new build**: structurally closer to WNBA's best-of-N simulator than NFL's
single-elimination one, but the per-round length variation and the regular/postseason rule split are
both new logic, not a straight port of either prior simulator.

---

## Phase 5 — Risk Management Engine

**Goal**: port the bankroll drawdown monitor / dynamic Kelly-multiplier stop-loss logic.

**Source**: no MLB-specific research needed — per the NFL-repo precedent (its own Phase 5 ported
WNBA's `risk_management_engine.R` "AS-IS," since it is sport-agnostic, operating on bankroll units
only). Confirm this still holds for MLB before porting (bankroll-unit math should not depend on
sport), but expect no MLB-specific changes beyond file/path headers.

**Deliverables**: `mlb_risk_management_engine.R`, ported with no logic changes expected.

---

## Phase 6 — Market Odds Engine

**Goal**: sharp-book detection/devig math, EV/Kelly-stake math, and The Odds API integration.

**Source**: `MLB_REPLICATION_PLAN.md` §2b (The Odds API section — sport key `baseball_mlb` confirmed,
prop market keys follow `{batter|pitcher}_{stat}` e.g. `batter_hits`/`pitcher_strikeouts`, same
two-tier bulk/per-event endpoint pattern already used for NFL/WNBA).

**Deliverables**: `mlb_market_odds_engine.R`, porting the sport-agnostic devig/EV/Kelly math
unchanged, with the sport key and prop-market-key strings updated to MLB's, and a dependency on
Phase 2's win-probability output (do not re-derive win probability inline inside this engine — the
NFL plan's own Phase 6 flagged that anti-pattern in the WNBA version as something to specifically
avoid repeating). Requires a human-provisioned Odds API key — no credential work happens in Phase 1
through 5, so this is the first phase that actually needs one.

**Carried-forward open item**: Odds API's own docs state prop-market coverage is "currently limited
to selected bookmakers and sports, and expanding over time" (§2b) — do not assume uniform prop
coverage across all games/books when wiring this up.

---

## Phase 7 — Discord Alert Dispatcher

**Goal**: port the Discord embed formatting/dispatch logic.

**Source**: no new MLB-specific research needed; sport-agnostic per sibling precedent.

**Deliverables**: `mlb_notify_bets.R`, reading Phase 6's value-bet cache and posting formatted
alerts, wrapped in this repo's `call_fn`-style exposed-function convention (not a bare top-level
auto-run script, per the NFL-repo Phase 7 finding about the WNBA original's missing wrapper).

---

## Phase 8 — Early-Season Calibration Review (decision point, not a guaranteed build)

**Goal**: decide whether MLB needs an early-season rating-shrinkage / staking-gate mechanism
analogous to the NFL repo's own Phase 8, which addressed real observed miscalibration (implausible
+200%+ "value bets") from noisy early-season ratings.

**This is explicitly a decision point, not a pre-committed deliverable**: NFL needed this fix because
its 17-game season gives each team only 1-2 games of current-season signal by Week 2 — a severe
small-sample problem. MLB's 162-game season is the opposite case per §6 item 1 (season-length and
rolling-window-size cannot be scaled proportionally between sports) — MLB will accumulate many more
early-season games per team than NFL does, which may substantially reduce (though not eliminate) this
specific failure mode. **Do not assume MLB needs an identical fix just because NFL did** — this phase
should start with a real backtest of Phase 2's rating engine's early-season behavior on real data,
and only build a shrinkage/gate mechanism if that backtest actually reproduces NFL's implausible-EV
symptom. If it doesn't, document that finding and skip the build — that is a valid Phase 8 outcome.

---

## Phase 9+ — Deferred / Idea-Stage

Not scoped in this document. Candidates surfaced during Phase 0/1-8 planning (visualizations,
dashboards, additional specialty-model research per Phase 3's deferred Bayesian item) should go
through this repo's own wishlist/roadmap process once Phases 1-8 are far enough along to know what's
actually worth building next — mirroring how NFL's own Phase 9 (visualization GIFs) was scoped from
a user brainstorm long after Phases 1-8 shipped, not planned upfront alongside them.

---

## Constants this plan explicitly refuses to finalize

Consistent with `MLB_REPLICATION_PLAN.md`'s own "Explicit Non-Goals" section, this implementation
plan does not assert a final value for: the Pythagorean exponent, any Elo constant (home-field
advantage, travel-penalty coefficient, rest-point value, the starting-pitcher blend coefficient,
game-score weights), Marcel's weighting constants, run-environment sigma, or any roster-rule-derived
constant. Every one of these is explicitly assigned to Phase 2's `tools/derive_mlb_constants.R` (or,
for Marcel, Phase 3's faithful-reproduction script) to compute from this repo's own real data — no
phase above should be read as license to copy a number from `MLB_REPLICATION_PLAN.md`, this document,
or any sibling repo's `config.R` directly into MLB's `config.R`.

## Non-goals of this document

- Does not write `config.R`, any engine script, or any `.R` file — this is a planning document only.
- Does not create GitHub issues for Phases 1-9 — if you want this roadmap tracked as real GitHub
  sub-issues (mirroring Phase 0's issue structure), that is a separate, explicit next step.
- Does not decide whether Phase 1 should be dispatched via the `subagent-brief` skill's `full`
  template (as Phase 0's sub-issues were) or driven directly — that is an execution-time decision for
  whoever starts Phase 1, not fixed here.
