---
name: empirical-signal-integration
description: Extends a WNBA Analytics model with a new granular data source or derived feature by researching feasibility, empirically deriving a real regression coefficient with a significance-gated decision rule, and wiring it into the live model additively with fail-safe/clamp discipline. Use when asked to "extend the model", "add a new signal", "use more granular data" (e.g. play-by-play), or to empirically validate a candidate feature before it influences ratings/props. Not for pure bug fixes or refactors with no new predictive claim.
---

# Empirical Signal Integration

## Why this exists

This repo has now done this exact workflow three times: real play-by-play data → `pbp_engine.R` →
an empirically-validated `SHOT_MIX_PTS_SLOPE` in `player_props_engine.R`; a long-orphaned
`cache/features_cache.rds` → an empirically-validated pair of team-depth coefficients in
`roster_bottom_up_engine.R`; and, earlier, the RAPM opponent adjustment's own `OPP_DEF_MU_SLOPE`.
Each time, the same shape of mistake was possible and had to be actively avoided: wiring in a
plausible-sounding signal without checking whether the "predictor" and the "outcome" are actually
the same event in disguise (circularity), skipping the join-key verification and silently getting
zero real matches (the RAPM<->roster ID mismatch this repo already has one CLAUDE.md warning
about), or forcing in a coefficient that didn't actually clear significance because the research
effort already went into computing it. This skill exists to make the disciplined version of this
process repeatable instead of reinvented (and re-risked) each time.

## When to use

- User asks to extend a model/rating/pricing engine to use a new, more granular data source
  (e.g. "use play-by-play data", "add shot-location detail", "use lineup data").
- A cache/feature/column already exists in this repo but has no real consumer, and you're asked to
  find one (or determine there genuinely isn't one).
- Before adding ANY new multiplier/additive term to `player_props_engine.R`'s pricing,
  `roster_bottom_up_engine.R`'s margin formula, `market_odds_engine.R`'s adjustments, or similar —
  if the term's weight isn't already a real, cited regression result, this skill's Step 3 applies
  before Step 4.

Not for: pure bug fixes, refactors, or wiring that carries no new predictive claim (use normal
editing for those — this skill's overhead is for claims that could be wrong in a way that costs
real money in this repo's betting-facing outputs).

## Procedure

### 1. Research feasibility (before writing any production code)

Write a throwaway or (better) reusable script under `tools/` (e.g.
`tools/research_<topic>.R` — follow this repo's `tools/` convention: `setwd()` to the absolute
project root, `source()` dependencies by bare filename) that:
- Confirms the new data source actually returns real, non-empty data (don't assume a
  `wehoop`/`hoopR` function works as documented — pull a real sample and inspect it, per this
  repo's own "confirmed empirically, not assumed" convention throughout `rapm_engine.R`/
  `shot_quality_engine.R`'s headers).
- Dumps the real schema (column names/types, categorical vocabulary if relevant).
- **Explicitly checks the join key against every existing cache you intend to combine it with.**
  Never assume two caches share an ID namespace just because they look like they should — this
  repo has a documented, real bug class here (`rapm_ratings.rds` vs. `active_rosters_cache.rds`'s
  incompatible player IDs, per CLAUDE.md) that has recurred (RAPM/roster names, WNBA-Stats-API vs.
  ESPN `game_id` namespaces, `CONN` vs `CON` team codes). Report the actual overlap percentage, not
  an assumption.
- Prototypes ONE candidate derived feature and sanity-checks it against known-good real values
  (e.g. do recognizable star players / real historical facts show up where expected).

Report the finding honestly, including if the data source turns out unreliable, low-coverage, or
not worth pursuing — a documented "not worth it" is a legitimate research outcome.

### 2. Spec and scope, in writing, before building

State explicitly: the research question, what's in scope, and what's explicitly deferred. In
particular, name any existing production files whose formulas/weights this work will NOT touch —
past work here always added new terms/functions ALONGSIDE existing ones
(`adjust_mu_for_opponent()`, the `0.4/0.4/0.2 + hca` margin blend) rather than modifying them, and
said so explicitly up front. If the user hasn't said whether to fold this into the live pipeline
yet, ask or default to a `tools/`-only research artifact first (see the "do not fold into pipeline
yet" pattern already used once in this repo's history) rather than assuming production wiring is
wanted immediately.

### 3. Identify the circularity/endogeneity trap before regressing anything

Before writing the regression, ask explicitly: **is the candidate predictor computed from the same
underlying event as the outcome it's supposed to predict?** If a per-game feature is built from
that same game's box stats, and you regress that same game's outcome (margin, points) on it, the
result will be spuriously "significant" because it's partly a mechanical identity, not a forecast.
The fix used twice in this repo: use a **trailing/lagged** version of the predictor (a rolling
average over strictly prior games — this repo already has `ROLLING_WINDOW_SIZE` in `config.R` for
exactly this purpose) to predict a **later** outcome, never the same-event outcome. Write down in
the eventual findings doc which trap you checked for and how you avoided it, even if the answer is
"not applicable here" — this is the single most likely way this class of work silently produces a
worthless result while looking rigorous.

### 4. Derive the coefficient empirically — mirror `OPP_DEF_MU_SLOPE`'s methodology exactly

- Build a real data panel (player-game, team-game, etc.) from existing caches — never simulate or
  bootstrap a distribution to "fill in" a data gap in this step.
- Use a **within-entity fixed-effects** regression (demean by player/team, or an explicit
  `factor(id)` — do both and cross-check they agree to several decimal places, catching a biased
  demeaning shortcut before it ships) so the entity's own baseline quality is differenced out and
  you're measuring genuine within-entity signal, not a cross-sectional confound (a real example:
  this repo's shot-mix work found a between-player correlation with the OPPOSITE sign of the
  within-player one, due to usage/role confounding — report both if you compute both, but only the
  within-entity one is causally relevant for adjusting an individual's own projection).
- Apply a documented minimum-sample threshold (this repo has used >= 5 qualifying games per entity
  more than once — reuse that unless you have a specific reason not to).
- Report coefficient, SE, t-stat, p-value, and sample size (both n and distinct entities). Check
  for collinearity between multiple candidate terms (correlation and/or VIF) if wiring in more than
  one at once, and say explicitly whether it's disqualifying.

**Decision rule — apply this before writing a single line into a production file:**
- Statistically significant (p < 0.05, or explicitly justify a looser bar in the writeup) AND
- Sign is theoretically sensible, OR the sign was genuinely ambiguous a priori and you say so
  explicitly rather than motivated-reasoning a direction after seeing the result.
- If either condition fails: **do not wire it in.** Document the null/ambiguous result honestly in
  the findings doc (see Step 6) and stop — a documented null result is a valid, useful deliverable,
  not a failure to hide. Never force a non-significant or wrong-signed coefficient into a
  production formula because the research effort already went into computing it.
- When testing multiple candidate terms together, decide EACH independently — it's expected and
  fine for only some (or none) of them to clear the bar.

### 5. Wire in (only if Step 4's decision rule passed)

- Add new constants/functions, never edit the existing ones they sit alongside. Constants used by
  exactly one consuming file live as local constants in that file with a full derivation comment
  (this repo's convention — see `OPP_DEF_MU_SLOPE`, `SHOT_MIX_PTS_SLOPE`,
  `TOP5_BPM_MARGIN_SLOPE`), not promoted into `config.R` unless genuinely multi-consumer.
  Derivation comments should include: the research question, the circularity check, methodology,
  full regression output, the decision, and — for a clamp — the REAL observed range of the
  adjustment across current data, showing the clamp is non-binding by design (a rail against a
  future degenerate cache, not a hyperparameter that's expected to bind).
- Additive/multiplicative composition alongside existing terms, matching the scale the regression
  was actually fit on (points-scale coefficient → additive points term; fractional/ratio estimand →
  multiplicative centred-on-1.0 ratio, clamped).
- **Fail-safe, no exceptions**: missing cache, missing entity, non-finite input, or any other
  degenerate case must resolve to a neutral no-op (0 additive / 1.0 multiplicative), never an
  error or an NA that poisons a downstream sum. Check every call site, including a code path that
  recomputes the same formula independently elsewhere (this repo's real trap:
  `roster_bottom_up_engine.R`'s `project_all_wnba_teams()` recomputes `expected_margin` inline
  rather than calling `predict_live_matchup()` — both had to be updated, or the new signal would
  silently never reach the actual output cache).
- If the new engine/producer script could collide with an existing function name or cache-literal
  path, grep for both before finalizing names — this repo has multiple similarly-scoped engines
  (RAPM possessions vs. PBP events vs. shot locations) and nothing enforces uniqueness
  automatically.

### 6. Verify for real, not hypothetically

- Re-run the specific script standalone (`Rscript.exe <file>.R`) and confirm it completes and
  produces plausible values — spot-check real, recognizable entities (players/teams), not just
  "no error".
- If this touched or added a `run_full_pipeline.R` stage, check its contract with
  `tools/verify_pipeline_stage.R <script.R> --entry_fn|--call_fn <fn> <output_path>` before paying
  for a full pipeline run.
- Run the full pipeline at least once (`Rscript.exe run_full_pipeline.R`) and confirm every
  declared output is `[FRESH]`, zero `[FAILED]` stages. Before doing so on Windows, check real free
  memory (`(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory`) if adding a stage to an
  existing `future_lapply`/`multisession` parallel group — each worker is a full separate R
  process, and this repo has genuinely OOM-killed itself doing this. Prefer running a new stage
  sequentially unless you've confirmed headroom.
- If this touched `app.R`, use `tools/headless_dashboard_probe.R` (see its own usage comment;
  `--screenshot` gives per-tab row/header/screenshot detail) to confirm the tab actually renders
  with real data and zero browser console errors — code review alone does not verify a Shiny UI.

### 7. Document and fold cleanup

- Write `docs/<topic>_regression_findings.md` following the structure in
  `templates/regression_findings_template.md` in this skill folder (mirrors
  `docs/pbp_shot_mix_regression_findings.md` / `docs/team_depth_signal_regression_findings.md`).
  Write this doc even for a null/not-wired-in result.
- Consolidate every exploratory/scratch script written along the way into ONE reproducible
  `tools/research_<topic>.R` (join-check → panel → regression → clamp sanity → live spot-check
  sections), runnable end-to-end via a single `Rscript.exe` call. Do not leave a trail of
  numbered/suffixed one-off scripts (`_v2`, `2`, `_check`) sitting in `tools/` — this has already
  had to be cleaned up once in this repo and should not recur.
- Update or create a `docs/HANDOFF.md`-style note (or append to the current one if it's recent and
  still relevant) summarizing what shipped, root causes found, and open items — see this repo's
  existing `docs/HANDOFF.md` for the expected level of detail.

## Known pitfalls (all previously hit for real in this repo — do not rediscover the hard way)

- **Same-game/same-event circularity** (Step 3) — the single most likely way to produce a
  spuriously significant, useless result.
- **Assumed ID namespace match** — verify every cross-cache join's overlap percentage empirically;
  this repo has at least three documented cases (RAPM/roster names, `CONN`/`CON`, WNBA-Stats-API vs
  ESPN `game_id`) where two caches that "should" share a key silently don't.
- **Function/cache-name collisions** between similarly-scoped engines — grep before naming.
- **A formula recomputed inline in more than one place** — wiring a new term into only one copy
  silently no-ops it everywhere else.
- **`future_lapply`/`multisession` memory** — each parallel worker is a full R process; check real
  free memory before assuming more parallelism is free.
- **Forcing in a non-significant result** because the research work is already done — the decision
  rule in Step 4 exists precisely to prevent this pressure from winning.
