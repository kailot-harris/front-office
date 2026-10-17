# Plan: MLB Analytics Phase 0 Research Deliverable (`docs/MLB_REPLICATION_PLAN.md`)

## Context

The user maintains a family of sibling sports-analytics repos (`NBA Analytics` → `WNBA Analytics` →
`NFL Analytics`), each later port built on an R architecture (`config.R` single-source-of-truth
constants, `run_full_pipeline.R` staged DAG, Elo/ridge rating engines, fatigue/market/risk/notify
stages, Discord dispatch, `docs/HANDOFF.md`, phased `task_assignments_phaseN.md` build tracking).
Each port was preceded by a **Phase 0 research-only document**, `docs/<SPORT>_REPLICATION_PLAN.md`,
written *before* any engine code, that does live-verified (WebSearch/WebFetch, dated) research into
data sources, constants needing empirical re-derivation, structural divergences from the prior sport,
and modern modeling approaches — so later implementation work has a verified factual foundation
instead of guessed/memorized assumptions. `NFL Analytics/docs/NFL_REPLICATION_PLAN.md` is the clearest
template (330 lines, 6 sections + sources-consulted list).

`MLB Analytics` is a brand-new sibling directory, currently empty except for a `.git/` folder (see
Discrepancy note below). The user's ask this session — investigate team/player statistics for W/L
prediction, Elo rating trajectories, and baseball-specific specialty models, **confirmed to be an R
project** — is exactly the substance of an `MLB_REPLICATION_PLAN.md`. This plan scopes that research
task: what it must cover, how to execute it, and what "done" looks like. It does **not** scope writing
any engine code.

**Discrepancy to flag, not resolve unilaterally**: `MLB Analytics/.git/` already exists (created
today, empty — no commits, no index), despite the environment reminder stating "Is a git repository:
false." Likely a leftover/incomplete `git init` from earlier. Confirm with the user whether this is
intentional before any commit decision; this plan does not run `git init` or assume the repo's
intended state.

## Scope

**In scope**: produce `MLB Analytics/docs/MLB_REPLICATION_PLAN.md` — live-verified research across six
sections (below). **Out of scope**: `config.R`, `run_full_pipeline.R`, any engine `.R` script,
`.claude/skills/`, `task_assignments_phaseN.md`, `git init`, any credential/vendor signup. Those are
later-phase decisions for the user to make after reviewing this research.

## Deliverable structure (6 sections, mirroring the NFL plan template, filled with MLB substance)

**1. Porting strategy narrative + failure modes to avoid** — frame MLB as a potential 4th sibling port;
carry forward the NFL plan's three documented failure modes (constants drifting from `config.R`;
`sys.nframe()==0` stage no-ops under `source()`; incompatible player-ID join schemes) and flag that MLB
has *at least* four independent ID schemes (MLBAM, Baseball-Reference, FanGraphs, Retrosheet) — worse
than NFL's four.

**2. Data-source decision table — R-package-first** (hard requirement per user: this is an R project).
Live-verify each of the following, with current CRAN/GitHub maintenance status (don't trust a stale
README):
- **`baseballr`** — scope of its MLB Stats API / Baseball Savant (Statcast) / FanGraphs / Retrosheet
  wrapper functions; CRAN vs. GitHub-only status; current maintenance activity.
- **`Lahman`** — historical season-level batting/pitching/fielding database package; coverage years;
  update cadence (typically lags current season).
- **`pitchRx` / `mlbgameday`** — pitch-level Statcast/PITCHf/x access; verify live whether these are
  stale/archived (name a trap analogous to the NFL plan's nflfastR `fast_scraper_*()` deprecation note
  if found).
- **Retrosheet-adjacent R tooling** vs. `baseballr`'s own Retrosheet wrapper, for historical play-by-play.
- **`mlbplotR`** — team-logo/plotting helper package, the baseball analog of `nflplotR`, for future
  visualization work.
- **MLB Stats API** (`statsapi.mlb.com`) and **Baseball Savant** (`baseballsavant.mlb.com`) directly —
  confirm current endpoints/coverage even though `baseballr` wraps them, since the wrapper's coverage
  may lag the raw API.
- **FanGraphs** — advanced stats (wOBA, wRC+, FIP, xFIP, SIERA, WAR) source/scraping ToS constraints.
- **`pybaseball`** — note only as a cross-language fallback (Python), not primary, given this is an R
  project; flag as a last resort if an R package gap is found.
- **ESPN injuries feed** — verify live whether MLB's ESPN site-API feed has the same "`athlete.id`
  missing, must parse Player Card href" quirk already confirmed for NFL/WNBA/NBA.
- **The Odds API** — verify MLB sport key (expect `baseball_mlb`) and player-prop market-key conventions.

Produce a table: data need → R package + function(s) → verified coverage window → maintenance status,
parallel to the NFL plan's `nflreadr` function table.

**3. Team/player statistics worth surfacing** — Pythagorean win expectation (verify current
best-practice exponent/variant, e.g. Pythagenport/Pythagenpat, live rather than from memory), run
differential, wOBA/wRC+, FIP/xFIP/SIERA, BABIP, WAR variants (fWAR vs. bWAR — different methodologies,
not interchangeable), Statcast barrel rate/exit velocity/expected stats (xBA/xSLG/xwOBA).

**4. Elo rating trajectories specific to baseball** — cite FiveThirtyEight's public MLB Elo methodology
(live-verified, not memorized) and explicitly address the **starting-pitcher adjustment** wrinkle
(blending team Elo with a pitcher-matchup rating) — no analog in NBA/WNBA/NFL Elo. Also note park
factors as an MLB-specific rating input.

**5. Specialty baseball models worth prototyping** — Marcel projections (cite Tom Tango's actual
weighting scheme), PECOTA (flag as documented-but-closed-methodology precedent, not reproducible),
bullpen usage/fatigue modeling, Bayesian/hierarchical run-scoring models. **Hard requirement**: find at
least one real, dated, correctly-scoped (season- vs. game-level, stated explicitly) peer-reviewed or
reputable citation comparing an ML approach (RF/GBM/NN) to a Pythagorean/regression baseline for
baseball win prediction, with real reported metrics — mirrors the NFL plan's Weirich et al. citation.

**6. Structural divergences from NBA/WNBA/NFL** — 162-game season (rolling-window sizing can't be
assumed via proportional scaling); starting-pitcher rotation effects (no analog elsewhere in the
family); universal DH and extra-innings rule status (verify current, e.g. Manfred-man rule status —
don't assume 2020-era rules persist); wild-card/division-series/LCS/World Series bracket shape (verify
current format, don't assume it matches WNBA's or NFL's bracket shape).

**Constants to flag as "needs empirical re-derivation," not assign final values**: run-environment
sigma, home-field advantage, rolling-window size, active/40-man roster constants.

## Execution approach

**Direct research in the main session via WebSearch/WebFetch, single document, single pass** —
mirrors exactly how `NFL_REPLICATION_PLAN.md` was built (sequential live fetches, inline dated
citations). Not delegated to subagents: the six sections are cross-referential (e.g. §4's Elo work
depends on §2's data-source findings; §6's rolling-window note depends on §3's Pythagorean research),
and this is read/research-only work with no file-fan-out parallelism benefit. Total scope (~15-25 live
fetches) is comparable to the NFL plan's own single-pass research effort.

## Sequencing

1. Flag the `.git` discrepancy to the user (informational, doesn't block research).
2. R-package research first (§2): `baseballr`, `Lahman`, `pitchRx`/`mlbgameday`, `mlbplotR`,
   Retrosheet-R tooling — confirm current CRAN/GitHub status for each before anything else, since this
   determines what's realistically buildable in R.
3. Direct-API research (§2 cont'd): MLB Stats API, Baseball Savant, FanGraphs ToS, ESPN injuries quirk
   check, The Odds API MLB sport key.
4. Stats landscape research (§3): Pythagorean exponent, wOBA/wRC+/FIP/xFIP/SIERA/BABIP/WAR definitions.
5. Elo methodology research (§4): 538 methodology, starting-pitcher adjustment, park factors.
6. Specialty-model research (§5): Marcel, PECOTA, bullpen fatigue, Bayesian run-scoring models, and the
   hard-requirement ML-vs-baseline citation search (keep searching until a real one is found).
7. Structural-divergence research (§6): current playoff/wild-card format, DH/extra-innings rule status,
   roster-size constants.
8. Draft `MLB Analytics/docs/MLB_REPLICATION_PLAN.md` following the NFL plan's section structure, every
   claim tagged with fetch date, closing "Sources Consulted" list with real URLs.
9. Self-check: confirm no section asserts a final numeric constant — all flagged "needs re-derivation."
10. Present the drafted document to the user before proposing any follow-on engine-building work.

## Definition of done

- All six sections populated with MLB-specific, live-verified substance (no placeholder text, no
  unverified memory-recalled numbers presented as fact).
- §2's R-package sub-table completed for all five named packages (`baseballr`, `Lahman`,
  `pitchRx`/`mlbgameday`, `mlbplotR`, Retrosheet-R tooling) with verified maintenance status.
- At least one real, dated, correctly-scoped ML-vs-baseline win-prediction citation with real metrics.
- Elo section explicitly covers the starting-pitcher-adjustment wrinkle with a real cited source.
- Constants list names run-sigma, HFA, rolling-window size, roster-size constants as "needs
  re-derivation" — no fabricated final values.
- "Sources Consulted" section with real URLs and fetch dates.
- Document states its own non-goals so a future reader doesn't mistake Phase 0 research for a build
  commitment.

## Explicitly out of scope

`config.R` / `run_full_pipeline.R` / any engine script, `git init`, credential/vendor signup,
`.claude/skills/` tooling, `task_assignments_phaseN.md` docs, any commitment to a full MLB port.

## Critical files

- `C:\Users\kailo\kayceeslices\MLB Analytics\docs\MLB_REPLICATION_PLAN.md` — new deliverable to create.
- `C:\Users\kailo\kayceeslices\NFL Analytics\docs\NFL_REPLICATION_PLAN.md` — structural/content template.
- `C:\Users\kailo\kayceeslices\NFL Analytics\docs\HANDOFF.md`, `WNBA Analytics\docs\HANDOFF.md` —
  secondary architecture references for framing §1's porting-strategy narrative.
- `C:\Users\kailo\kayceeslices\MLB Analytics\.git` — flagged discrepancy, not to be resolved
  unilaterally.

## Verification

This is a research/documentation task, not code — "testing" means reviewing the finished
`MLB_REPLICATION_PLAN.md` for: (a) every factual claim has an inline fetch date and corresponding
entry in Sources Consulted, (b) the R-package table is complete and matches each package's actual
current CRAN/GitHub state (spot-check 1-2 citations by re-opening the URL), (c) no section smuggles in
an unverified final constant, (d) structure matches the NFL plan's section shape closely enough to be
a recognizable sibling document.
