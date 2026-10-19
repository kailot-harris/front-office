# WNBA Analytics — Security & Technical Review

**Date:** 2026-09-16
**Reviewer:** independent technical review pass (adversarial/skeptical posture)
**Deliverable status:** investigation + reporting only. **No code in this repo was modified.**

---

## Scope & Method

This is a security and data-integrity review of the WNBA Analytics pipeline: root-level `.R`/`.r`
scripts, `app.R` (Shiny dashboard), `team_embeddings.py`, `tools/`, and the `cache/`/`data/`
artifacts they produce.

**What was actually executed (not just read):**

- Loaded and schema-inspected every production cache in `cache/` and `data/` via `Rscript.exe`
  (`box_scores_cache.rds`, `rapm_ratings.rds`, `active_rosters_cache.rds`,
  `latest_player_props.rds`, `projected_wnba_standings.rds`, `latest_value_bets.rds`,
  `betting_ledger.rds`, `injury_data_cache.rds`, `prediction_accuracy_log.rds`).
- Reproduced `player_props_engine.R`'s RAPM↔roster `left_join()` against the real caches and
  captured the real error.
- Reproduced `market_odds_engine.R`'s `resolve_team_name()` verbatim and fuzzed it with degenerate
  inputs (`""`, `NA`, single characters, non-WNBA team names).
- Built a minimal harness that reproduces `run_full_pipeline.R`'s `run_stage()` sourcing mechanism
  exactly, to measure what `sys.nframe()` actually is inside a sourced stage script.
- Cross-checked every production cache's `mtime` against the 2026-09-16 06:21 pipeline run recorded
  in `pipeline_execution.log`.
- Timed a catastrophic-backtracking regex against the real props data to determine whether the
  `app.R` search box is genuinely ReDoS-exploitable (it is **not** — see M-3; reported honestly
  rather than inflated).
- Rendered `logging_utils.R`'s `.log_format_extra()` against the exact argument list
  `market_odds_engine.R:211` passes, to confirm what reaches disk.
- Grepped and audited every `system()`, `shell()`, `eval()`, `parse()`, `readRDS()`, and
  `Sys.getenv()` call site in the repo.

All scratch scripts (`tools/.tmp_review_*.R`) were deleted after use.

**Explicitly out of scope** — the following are documented in `CLAUDE.md` as already fixed, were
spot-verified as genuinely fixed, and are **not** re-reported as findings: the wehoop
exhibition-row filter, the `CONN`→`CON` Connecticut Sun normalization, `app.R`'s scalar `%||%`
hard-error in the Injury tab, and `market_odds_engine.R::calculate_matchup_delta()`'s
RAPM/roster join. (Note: two of these have **untouched siblings elsewhere in the repo** — see
H-2 and M-6. Those siblings are new findings, not restatements.)

Also out of scope by instruction: generic web-app checklist items (CSRF, session fixation,
TLS config). This runs locally with no auth surface and no public endpoint.

---

## Summary

| Severity | Count |
|---|---|
| Critical | 3 |
| High | 4 |
| Medium | 8 |
| Low | 6 |
| **Total** | **21** |

**Headline:** the dominant risk here is not classical exploitation — it is that
**`run_full_pipeline.R` reports `[COMPLETED]` for stages that never execute a single line of work**
(C-2), while the one number that most directly drives real money — home-court advantage — is
**11.6 points instead of 2.40** (C-1), and the dashboard's accuracy scoreboard is **100% synthetic
diagnostic data** (C-3). A human reading the console output or the dashboard has no way to tell
any of this from a healthy run.

---

## CRITICAL

### C-1. Home-court advantage is 11.6 points in the live betting engine (comment three lines above says 2.40)

**File:** `market_odds_engine.R:416-426`

```r
# WNBA-specific: home-court advantage (2.40) left unchanged from NBA per
# T2's note (not independently re-derived); sigma uses config.R's real
# empirically-derived WNBA_MARGIN_SIGMA (14.0), NOT the NBA original's
# hardcoded 11.2 — WNBA margins run wider (fewer possessions/game).
fair_margin <- (h_net - a_net) + 11.6 + fatigue_drag + calculate_matchup_delta(h_abbr, a_abbr)
p_home <- pnorm(fair_margin / WNBA_MARGIN_SIGMA)
...
hcas[i]         <- 11.6
```

The comment documents `2.40`. The code adds `11.6`. `11.6` appears to be the NBA original's
`11.2`-family sigma constant mistakenly pasted into the HCA slot — `tools/backtest_margin_hyperparams.R:64`
has since enshrined the mistake as ground truth:
`HCA_CONST <- 11.6  # market_odds_engine.R's current live constant (not being re-optimized here)`.

Every other HCA site in the repo uses `2.40`:
`roster_bottom_up_engine.R:304,406,483`, `playoff_simulator.R:98`, `app.R:270,1123`,
`tools/build_calibration_cache.R:64`, `tools/optimize_hca.R:59`.

**Reproduction** — loaded the shipped recommendation cache written by the 2026-09-16 06:22 run:

```
                                   Matchup      Model_Win_Prob predicted_margin contrib_net_diff contrib_hca EV_Percent Bankroll_Rec
1       Washington Mystics vs. Chicago Sky               0.948           22.710           11.110        11.6     127.52            3
2         Las Vegas Aces vs. Seattle Storm               0.441           -2.070          -13.670        11.6      94.04            3
3        Phoenix Mercury vs. Portland Fire               0.641            5.060           -6.540        11.6      29.48            3
4      Los Angeles Sparks vs. Dallas Wings               0.852           14.640            3.040        11.6      15.09            3
5        Connecticut Sun vs. Atlanta Dream               0.970           29.770           18.170        11.6       5.74            3
6          Indiana Fever vs. Toronto Tempo               0.461           -1.360          -12.960        11.6     208.87            3
7 Portland Fire vs. Golden State Valkyries               0.937           21.390            9.790        11.6       7.75            3
8      New York Liberty vs. Minnesota Lynx               0.765           10.095           -1.505        11.6       7.10            3

implied home-prob for two IDENTICAL teams at hca=11.6, sigma=14: 0.796
implied home-prob for two IDENTICAL teams at hca=2.40, sigma=14: 0.568
```

**Impact.** The model believes two evenly-matched teams produce a **79.6%** home win rate. Real WNBA
home win rate is ~55-58%. Consequences, all observable in the table above:

- **All 8** recommendations are the home side. This is a structural artifact, not a read on the slate.
- **All 8** are staked at `Bankroll_Rec = 3`, the `max_cap_pct` ceiling in `calculate_kelly()`
  (`market_odds_engine.R:144-150`). The Kelly sizer is saturated on every single bet.
- `EV_Percent` values of 127%, 208% are not plausible edges against any real book; they are the
  direct arithmetic consequence of a ~9-point phantom margin.
- This propagates downstream into `cache/odds_history.rds`, `notify_bets.R`'s Discord dispatch
  filter (`EV >= 3.0%` — which now passes essentially everything), and
  `prediction_accuracy_logger.R`'s logged `contrib_hca`.

**Severity: Critical.** This is the single highest-consequence defect found. It silently converts a
betting model into a "always bet the home team at max stake" machine, with confident-looking EV
numbers attached.

**Fix direction.** Promote HCA to a single `config.R` constant (`WNBA_HCA <- 2.40`) and have
`market_odds_engine.R`, `roster_bottom_up_engine.R`, `playoff_simulator.R`, `app.R`, and the
`tools/` backtests all read it — the same centralization treatment `WNBA_ROTATION_SIZE` already
received. Then re-run `tools/optimize_hca.R` to derive the real WNBA value empirically and record
it in the constant's comment. Reset `tools/backtest_margin_hyperparams.R:64`'s `HCA_CONST` to read
from config rather than restating `11.6`. **Every cached artifact produced under `11.6`
(`latest_value_bets.rds`, `odds_history.rds`, and the non-`DIAG_` rows of
`prediction_accuracy_log.rds`) should be considered invalid and regenerated.**

---

### C-2. Four pipeline stages are silent no-ops that log `[COMPLETED]`

**Files:** `run_full_pipeline.R:58-113` (the `run_stage()` sourcing mechanism) interacting with
`sync_rosters.R:133`, `injury_scraper.R:193`, `roster_bottom_up_engine.R:506`,
`playoff_simulator.R:248`

`run_stage()` executes a stage via `source(script_name, local = FALSE)` **from inside a function**.
Four stage scripts gate their main entry point on `sys.nframe() == 0`, which is only true when a
file is the top-level script of an `Rscript` invocation — never when it is `source()`d.

**Reproduction** — harness replicating `run_stage()`'s exact call shape:

```
=== A) Rscript file.R directly (top level) ===
   (this script itself: sys.nframe() = 0 )
=== B) source() from top level ===
   [sourced file] sys.nframe() = 4  interactive() = FALSE
   [sourced file] >>> MAIN FUNCTION SKIPPED
=== C) source() from inside a function, i.e. run_stage()'s exact call ===
   [sourced file] sys.nframe() = 10  interactive() = FALSE
   [sourced file] >>> MAIN FUNCTION SKIPPED
```

Guard audit across the repo:

```
  copula_props_engine.R            line 137   if (!interactive()) {              <- RUNS
  daily_ingest.R                   line 130   if (sys.nframe() == 0) {           <- (not in the DAG at all, see L-4)
  fatigue_travel_engine.R          line 168   if (!interactive()) {              <- RUNS
  injury_scraper.R                 line 193   if (sys.nframe() == 0 || interactive()) {   <- NO-OP
  player_props_engine.R            line 438   if (!interactive()) {              <- RUNS
  playoff_simulator.R              line 248   if (!interactive() && sys.nframe() == 0) {  <- NO-OP
  rapm_engine.R                    line 453   if (!interactive()) {              <- RUNS
  risk_management_engine.R         line 197   if (!interactive()) {              <- RUNS
  roster_bottom_up_engine.R        line 506   if (sys.nframe() == 0) {           <- NO-OP
  sync_rosters.R                   line 133   if (sys.nframe() == 0 || interactive()) {   <- NO-OP
```

**Confirmed against the real 2026-09-16 run** (`pipeline_execution.log:879+`) — note the absence of
any of these scripts' own progress output, and the sub-second timings:

```
>>> [STAGE] Sync Active WNBA Rosters (12-Player Cap) & Mid-Season Signings (sync_rosters.R)...
>>> [COMPLETED] sync_rosters.R in 0.23 seconds.
>>> [STAGE] Scrape Official WNBA Injury Scratches & Availability Updates (injury_scraper.R)...
>>> [COMPLETED] injury_scraper.R in 0.24 seconds.
>>> [STAGE] Generate 15-Team WNBA Bottom-Up Standings & Fair Spreads (roster_bottom_up_engine.R)...
>>> [COMPLETED] roster_bottom_up_engine.R in 0.05 seconds.
>>> [STAGE] Execute WNBA Playoff Series Monte Carlo (...) (playoff_simulator.R)...
>>> [COMPLETED] playoff_simulator.R in 0.02 seconds.
```

0.23s is a `library()` load and function definitions — not an ESPN roster scrape.

**Confirmed by `mtime`** — the outputs these four stages claim to produce are frozen four days
before the run that reported success:

```
  data/box_scores_cache.rds                2026-09-12 00:22:45
  cache/player_box_scores_cache.rds        2026-09-12 00:23:16
  cache/active_rosters_cache.rds           2026-09-12 00:23:24   <- sync_rosters.R
  cache/injury_data_cache.rds              2026-09-12 00:25:21   <- injury_scraper.R
  cache/projected_wnba_standings.rds       2026-09-12 00:30:14   <- roster_bottom_up_engine.R
  cache/team_shot_quality.rds              2026-09-16 06:22:09   <- (!interactive() guard, genuinely ran)
  cache/latest_value_bets.rds              2026-09-16 06:22:25   <- (!interactive() guard, genuinely ran)
```

**Impact.** `market_odds_engine.R` runs *fresh* every night on top of *four-day-stale* rosters,
injuries, and team ratings, and emits live-looking bet recommendations. Injury data in particular
is time-critical: a player ruled out on 09-15 is still shown as active. The pipeline's own
`[COMPLETED]` log line and the dashboard both present this as a healthy, current run.

This also **directly contradicts** `docs/TESTING_PLAN.md`'s Execution Log §1, which states "All 13
downstream cache files' `mtime` advanced to the run timestamp, confirming no stage silently
no-opped." That claim does not hold against the current code.

Note that the repo already contains a purpose-built workaround for exactly this problem — the
`call_fn` parameter added to `run_stage()` (`run_full_pipeline.R:58,75-81`) for
`prediction_accuracy_logger.R` — but it was applied to only that one file.

**Severity: Critical.** Silent staleness in a pipeline whose entire value proposition is freshness,
with an affirmative "COMPLETED" signal masking it.

**Fix direction.** Standardize the auto-run guard across all stage scripts. `!interactive()` works
correctly under `run_stage()`; `sys.nframe() == 0` does not. Either convert the four stragglers to
`!interactive()`, or preferably extend the existing `call_fn` pattern so each stage's entry point
is invoked explicitly by name — that makes the DAG's contract visible in `run_full_pipeline.R`
instead of hidden in each file's footer. Additionally, `run_stage()` should assert that the stage's
declared output file's `mtime` advanced, and log a `WARN` when it did not; that single check would
have caught this class of bug automatically.

---

### C-3. The dashboard's model-accuracy scoreboard is 100% synthetic diagnostic data

**Files:** `cache/prediction_accuracy_log.rds`, consumed by `app.R`'s Tab 8 reactive
`r_diagnostics_df()` (`app.R:1175-1206`); written by `tools/generate_diagnostic_data.R`

**Reproduction:**

```
=== prediction_accuracy_log.rds ===
 rows: 114
 status table:   PENDING 14   RESOLVED 100

=== RESOLVED prediction rows: provenance ===
 date range: 2026-01-02 .. 2026-07-16
 n with game_date outside the May-Oct WNBA season window: 68
 distinct game_id prefixes: DIAG_
 sample game_ids: DIAG_1, DIAG_2, DIAG_3, DIAG_4
 injury_data_source values: DIAGNOSTIC
 accuracy reported: 0.83  Brier: 0.131
 contrib_hca distinct: 2.4

=== does a real box-cache game_id look like these? ===
 real box game_id sample: 401165811, 401165810, 401165809, 401165808
 overlap resolved game_id vs real box game_id: 0
```

Every one of the 100 `RESOLVED` rows is a `DIAG_*` fixture: `injury_data_source == "DIAGNOSTIC"`,
**zero** `game_id` overlap with the 3,906 real games in `data/box_scores_cache.rds`, and 68 of them
dated outside the WNBA's May–October season entirely (e.g. `2026-01-02`). The "83% accuracy /
0.131 Brier" figure is fabricated.

Meanwhile the only non-`DIAG_` rows — the 14 real pipeline predictions — are all `PENDING` and
structurally unresolvable (see M-5).

A repo-wide grep confirms **nothing filters these out**:

```
=== DIAGNOSTIC filters anywhere? ===
(no hits outside tools/generate_diagnostic_data.R itself)
```

`app.R:1179` selects `filter(status == "RESOLVED")` with no provenance predicate, so the diagnostic
seed rows are the *only* thing the accuracy tab can ever display.

(Note the `contrib_hca = 2.4` in the diagnostic rows versus `11.6` in the live engine — independent
corroboration of C-1's drift.)

**Severity: Critical.** A scoreboard that reports fabricated 83% accuracy as if it were measured
performance is worse than no scoreboard: it actively builds false confidence in a model that C-1
shows is structurally broken.

**Fix direction.** Add a `data_source`/`is_synthetic` column to the prediction-log schema (the
schema already carries `schema_version`, so this is a clean versioned migration) and have
`tools/generate_diagnostic_data.R` stamp its rows. Filter them out of `app.R`'s Tab 8 reactive and
`summarize_prediction_accuracy()`, or better, write diagnostic fixtures to a separate
`cache/prediction_accuracy_log_DIAG.rds` and never mix them into the production log. Surface an
explicit "N real resolved predictions" count on the tab so an empty real sample is visible rather
than silently backfilled with fixtures.

---

## HIGH

### H-1. `ODDS_API_KEY` is written in cleartext to the log file and log database on any API error

**Files:** `market_odds_engine.R:195-213` (construction + logging), `logging_utils.R:64-105` (sink)

```r
url <- paste0(
  "https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?",
  "apiKey=", api_key,
  "&regions=us,us2,eu&markets=h2h&oddsFormat=american"
)
...
}, error = function(e) {
  log_error("Odds API request failed.", condition = e, call = "fetch_market_odds()", url = url)
```

The secret is embedded in `url` as a query parameter, and `url` is passed straight into
`log_error()`'s `...`. `logging_utils.R:.log_format_extra()` stringifies every `...` element with no
redaction, and `.log_write()` sends the result to **three** destinations: the console (line 82),
`logs/wnba_pipeline.log` (line 85), and the `logs` table in `logs/logs.duckdb` (lines 96-97).

**Reproduction** — rendered `.log_format_extra()` against the exact argument list line 211 passes:

```
would write -> [ERROR] [market_odds_engine.R] Odds API request failed. | url: https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?apiKey=SUPERSECRET123&regions=us,us2,eu&markets=h2h&oddsFormat=american
```

This does not fire today only because `ODDS_API_KEY` is empty in this environment — the `nchar(api_key) > 0`
branch is never entered. It will fire on the **first transient network error after a key is
provisioned**, which is precisely the setup `docs/ODDS_API_SETUP.md` instructs a human to perform.
`req_retry(max_tries = 3)` means a brief outage produces an error whose own condition message may
also embed the URL, logged alongside via `extra$condition_message`.

**Impact.** The key lands in an append-only plaintext file and a DuckDB database that are not
gitignored (no git here, but these are exactly the artifacts that get zipped/shared/attached to a
bug report). `logs/wnba_pipeline.log` is already 77 KB and `logs/logs.duckdb` is 1 MB of retained
history. This directly violates the repo's own stated convention (`CLAUDE.md`: "No secrets are ever
hardcoded in this repo… never… embed a real secret in a file") — the convention was enforced
against *literals* in source, but not against *runtime values reaching the log sink*.

**Severity: High.** A real credential-disclosure path, latent but guaranteed to trigger, in a
codebase that explicitly treats webhook/key hygiene as a ground rule.

**Fix direction.** Two layers. (1) At the call site, log a redacted URL: build the URL from a
separate base-path variable and log that, or `sub("apiKey=[^&]*", "apiKey=***REDACTED***", url)`.
Better still, pass the key via `httr2::req_url_query()` on a keyless base URL so the secret is never
interpolated into a string that gets passed around. (2) Defensively, add a redaction pass in
`logging_utils.R:.log_format_extra()` and the DuckDB `extra_json` builder that scrubs
`apiKey`/`api_key`/`token`/`webhook`/`secret` query params and Discord webhook paths from *any*
value before it is written — the logger is the right chokepoint, since every future call site
inherits the protection.

---

### H-2. RAPM↔roster join by `player_id` is re-implemented (unfixed) in two more files; one hard-fails the props stage nightly

**Files:** `player_props_engine.R:136-137`, `roster_bottom_up_engine.R:83-84`

`CLAUDE.md` documents that `rapm_ratings.rds` and `active_rosters_cache.rds` use incompatible player
identifiers, and that `market_odds_engine.R::calculate_matchup_delta()` was fixed to join on
`(team full name, normalized last name)`. **That fix was applied to exactly one of the three sites.**
Both remaining sites still do the naive join:

```r
# player_props_engine.R:136-137
team_def <- active_rosters |>
  left_join(rapm_df, by = "player_id") |>

# roster_bottom_up_engine.R:83-84
team_rapms <- active_rosters |>
  left_join(rapm_df, by = "player_id") |>
```

**Reproduction** — loaded both real caches and ran the join:

```
rapm$player_id class: character  sample: 201496,203399,1628917,1631002
roster$player_id class: integer  sample: 869,5208983,3142250,3058901
raw ID overlap (as character): 0

-- reproduce player_props_engine.R:137 --
  JOIN ERROR: Can't join `x$player_id` with `y$player_id` due to incompatible types.
              ℹ `x$player_id` is a <integer>. ℹ `y$player_id` is a <character>.
```

The two caches now differ not just in ID scheme (0 overlap even coerced to a common type) but in
**R type**, so dplyr refuses the join outright instead of silently returning all-`NA`.

**This is a live, nightly production failure.** From `pipeline_execution.log`, the 2026-09-16 06:22 run:

```
[2026-09-16 06:22:17] [ERROR] [run_full_pipeline.R] Stage failed: player_props_engine.R
  (Price ZINB Overdispersed WNBA Player Props) | ... |
  condition_message: Can't join `x$player_id` with `y$player_id` due to incompatible types.
  ℹ `x$player_id` is a <integer>. ℹ `y$player_id` is a <character>.
  | call: left_join(active_rosters, rapm_df, by = "player_id")
```

The failure is caught by `run_stage()`'s fail-safe `tryCatch` and downgraded to a `warning()`, so
the pipeline continues and the operator sees a successful overall run. `data/latest_player_props.rds`
has therefore not been regenerated since **2026-09-14 09:51** — the dashboard's Props Terminal tab
(`app.R:444`) has been serving two-day-stale props ever since.

`roster_bottom_up_engine.R:84` carries the identical defect and is currently masked **only** because
that entire script is a no-op (C-2). Fixing C-2 without fixing this line will convert a silent
no-op into a second nightly hard failure.

**Severity: High.** A known, documented bug class that was fixed in one location and left in two,
one of which breaks a production stage every night behind a fail-safe that hides it.

**Fix direction.** Extract the fixed join from `market_odds_engine.R:104-115` into a single shared
helper (e.g. `join_rapm_to_roster()` in `config.R` or a new `rapm_join_utils.R`) and call it from
all three sites, so the next schema change has one place to break rather than three. Separately,
`rapm_engine.R` should write `player_id` with a consistent, documented type — the `<character>` vs
`<integer>` divergence is itself worth pinning down. Add the `(team, last_name)` overlap count as an
assertion in `tools/data_health_probe.R` so a future schema drift fails loudly at stage 0.

---

### H-3. `app.R` Tab 8 (Model Diagnostics) reads a path that does not exist, and columns that do not exist

**File:** `app.R:1184-1197`

```r
box_path <- "cache/box_scores_cache.rds"
if (!file.exists(box_path)) return(NULL)
box_scores <- readRDS(box_path)
...
  select(game_date, home_team_short = team_short_display_name,
         home_score = score, away_score = opponent_score)
```

**Reproduction:**

```
exists cache/box_scores_cache.rds : FALSE
exists data/box_scores_cache.rds  : TRUE
  column score                      present: FALSE
  column opponent_score             present: FALSE
  column team_score                 present: TRUE
  column opponent_team_score        present: TRUE
  column team_short_display_name    present: TRUE
```

Two independent defects stacked:

1. **Stale path.** The 2026-09-12 tidy-up moved this artifact to `data/` and repointed `config.R`'s
   `CACHE_TEAM_BOX` accordingly (`config.R:167`). `app.R:1184` is the one reference that was missed.
   A repo-wide sweep confirms it is the *only* straggler:

   ```
     app.R:1184  box_path <- "cache/box_scores_cache.rds"
     config.R:167  CACHE_TEAM_BOX  <- file.path(PROJECT_DIR, "data", "box_scores_cache.rds")
     tools/build_calibration_cache.R:61  ... file.path(PROJECT_DIR, "data", "box_scores_cache.rds")
     tools/ml_cv_benchmark.R:53  ... file.path(PROJECT_DIR, "data", "team_embeddings.csv")
   ```

2. **Wrong column names.** Even with the path corrected, `select(home_score = score,
   away_score = opponent_score)` would error — the real columns are `team_score` /
   `opponent_team_score`.

**Impact.** `file.exists()` is `FALSE`, so the reactive takes the `return(NULL)` early exit on every
render. Tab 8's MAE and RMSE value boxes fall through to their `else 0.0` defaults
(`app.R:1210-1213`) and display a confident **"0 pts Mean Absolute Error"** — a perfect-model
reading produced by a missing file. The residual-histogram and per-team-bias plots
(`output$plot_team_bias`, `app.R:1263`) render empty. Nothing in the UI distinguishes this from a
genuinely flawless model.

This also means H-3 masks C-3: even the fabricated `DIAG_` rows never reach the plots, because the
join they feed is short-circuited before it runs.

**Severity: High.** A user-facing metric that reports a perfect score when its data source is
absent. This is the same "fail-safe default that looks like a pass" pattern as C-2.

**Fix direction.** Change line 1184 to use `CACHE_TEAM_BOX` (sourced at `app.R:57-58`) rather than a
bare literal, and correct the `select()` to `team_score`/`opponent_team_score`. More importantly,
make the failure visible: return a labeled "diagnostics unavailable — box score cache not found"
notice instead of `NULL`, and have the value boxes render `"—"` rather than `0.0` when `df` is
`NULL`. A zero should never be the fallback for an unmeasurable metric.

---

### H-4. `resolve_team_name()` silently maps empty and one-character inputs to real franchises

**File:** `market_odds_engine.R:157-178`

```r
hit <- full_names[sapply(tolower(full_names), function(fn) grepl(fn, s, fixed = TRUE) || grepl(s, fn, fixed = TRUE))]
if (length(hit) >= 1) return(hit[1])
```

The second clause, `grepl(s, fn, fixed = TRUE)`, tests whether the *input* is a substring of the
*franchise name*. For a short or empty `s` this matches everything, and the function returns
`hit[1]` — the first alphabetically-abbreviated team.

**Reproduction** — function copied verbatim and fuzzed:

```
  input=""                       -> Atlanta Dream
  input="a"                      -> Atlanta Dream
  input="s"                      -> Chicago Sky
  input="Las Vegas Aces"         -> Las Vegas Aces
  input="Toronto Raptors"        -> Toronto Raptors
  input="Unknown FC"             -> Unknown FC
  input="Golden State Warriors"  -> Golden State Warriors
```

`""` → **Atlanta Dream**. There is no sentinel, no `NA`, no warning.

**Impact.** This function is the canonicalization boundary between The Odds API's untrusted
`home_team`/`away_team` fields and the internal standings lookup (`market_odds_engine.R:383-389`).
If the live feed ever returns an empty string, a truncated name, or a `NULL` that stringifies short
— all realistic for a thinly-covered WNBA slate, which `WNBA_REPLICATION_PLAN.md` §(b) risk #2
already flags as expected — the odds for that game are silently attributed to **Atlanta Dream's**
net rating, and an EV/Kelly recommendation is produced from it. There is no downstream check that
would catch a plausible-but-wrong team assignment.

Note the asymmetry that makes this hard to spot: genuinely *unrecognized* inputs
(`"Toronto Raptors"`, `"Unknown FC"`) correctly pass through unchanged and then fail the
`nrow(h_row) > 0` standings check at line 391, falling back to devigged consensus. Only
*degenerate* inputs produce a confident wrong answer.

**Severity: High.** Untrusted external input silently resolving to a valid-looking internal entity,
on the path that produces money recommendations.

**Fix direction.** Require a minimum input length before attempting substring matching (e.g.
`if (nchar(trimws(s)) < 3) return(NA_character_)`), and drop the reverse-containment clause
`grepl(s, fn, fixed = TRUE)` entirely — matching a franchise name *inside* the input is the
meaningful direction; the reverse only helps for prefixes and is what creates the degenerate case.
Return `NA_character_` rather than the raw input on no-match so callers must handle it explicitly,
and log a `WARN` with the unresolved value.

---

## MEDIUM

### M-1. `system()` exit status is never checked; `python` is resolved from `PATH`

**File:** `run_full_pipeline.R:70-71`

```r
if (grepl("\\.py$", script_name)) {
  system(sprintf("python %s", script_name))
}
```

**On injection specifically — this is not exploitable, and I verified why.** `script_name` reaches
`run_stage()` only from hardcoded string literals in the DAG (`run_full_pipeline.R:121-214`); the
only `.py` value is the literal `"team_embeddings.py"`. There is no path by which user input,
network data, or filesystem enumeration reaches this `sprintf`. The same holds for the two other
`system()` calls in the repo, both hardcoded: `tools/test_pipeline_db.R:17`
(`system("Rscript run_full_pipeline.R")`) and `tools/test_db_embeddings.R:16`
(`system("python team_embeddings.py")`). I also audited the two `eval()`/`parse()` sites —
`tools/test_logging_fault_injection.R:123-137,233-236` — which parse *this repo's own* source files
to extract function definitions for testing. No untrusted input reaches any of them.

The real problems are operational:

1. **Exit status is discarded.** `system()` returns the child's exit code; it is neither captured nor
   checked. A Python traceback — missing `torch`, a corrupt `games_for_embeddings.csv`, a DuckDB
   lock on `logs/analytics.duckdb` — exits non-zero, and `run_stage()` proceeds straight to its
   `[COMPLETED]` branch. This is the same false-success shape as C-2, via a different mechanism.
2. **Unqualified `python`.** Resolved from `PATH` at runtime. On Windows this may hit a different
   interpreter than the Python 3.11.9 environment where `torch`/`numpy`/`pandas` are installed
   (including the App Execution Alias stub that opens the Microsoft Store), and it is a
   PATH-precedence hijack surface for any writable directory earlier in `PATH`.

**Fix direction.** Capture and check the status: `status <- system(...); if (status != 0)
stop(sprintf("Python stage %s exited with status %d", script_name, status))` — letting the existing
`tryCatch` log it as a genuine `[FAILED]`. Use `system2()` with a vector argument list rather than a
`sprintf`-built command string, and resolve the interpreter explicitly (a `PYTHON_BIN` constant in
`config.R`, defaulting to `Sys.which("python")` with a startup check).

### M-2. `run_full_pipeline.R` never sources `config.R`; it depends on stage 0 leaking globals

**File:** `run_full_pipeline.R:26, 125-126`

The master script sources only `logging_utils.R` (line 26), then at line 125 uses `CACHE_DIR`:

```r
if (file.exists(file.path(CACHE_DIR, "player_box_scores_cache.rds"))) {
```

`logging_utils.R` defines `PROJECT_DIR` and the `LOG_*` constants but **not** `CACHE_DIR`. The only
reason line 125 works is that stage 0, `tools/data_health_probe.R:13`, calls `source("config.R")`,
and `run_stage()` sources with `local = FALSE` so the constants land in `.GlobalEnv` as a side effect.

This is fragile in a specific, reachable way: `run_stage()`'s `tryCatch` *deliberately swallows* a
stage failure and continues. So if `tools/data_health_probe.R` ever errors (a corrupt cache is
exactly what it exists to detect), `CACHE_DIR` is never defined, and line 125 — which sits at top
level, **outside** any `run_stage()` protection — throws `object 'CACHE_DIR' not found` and kills
the entire pipeline. The fail-safe design is inverted: the health probe failing takes down
everything downstream instead of being reported and stepped over.

**Fix direction.** Add an explicit `source("config.R")` at `run_full_pipeline.R:26` alongside
`logging_utils.R`. Constants should be an explicit dependency of the orchestrator, not an emergent
property of stage ordering.

### M-3. `app.R` props search box passes raw user input to `grepl()` as a regex — a crash bug, not ReDoS

**File:** `app.R:1300-1301`

```r
if (nzchar(input$props_search_player)) {
  df <- df %>% filter(grepl(input$props_search_player, player, ignore.case = TRUE))
}
```

**I tested the ReDoS hypothesis directly and it does not hold.** R's default `grepl()` uses the TRE
engine, which is not backtracking-based for this class of pattern:

```
=== ReDoS: single-threaded Shiny blocked by a user-typed regex (app.R:1301) ===
  pattern (a+)+$     on a 28-char subject -> 0.00 seconds of blocked CPU
```

The real, reproducible issue is an **unhandled hard error on any malformed pattern**:

```
  pattern "Wilson" -> OK, 6 matches
  pattern "("      -> ERROR: invalid regular expression '(', reason 'Missing ')''
  pattern "a{1,"   -> ERROR: invalid regular expression 'a{1,', reason 'Missing '}''
  pattern "["      -> ERROR: invalid regular expression '[', reason 'Missing ']''
```

`filtered_props()` is a reactive with no `tryCatch`, and it feeds three outputs
(`tbl_props_terminal`, `plot_prop_zinb_curve`, and the EV filter). A user typing a single `(` while
searching for a player — a completely natural keystroke mid-typing, since Shiny `textInput` fires on
every character — throws, and all three outputs render Shiny's opaque error state. Since these are
partial inputs, the tab breaks *while the user is typing normally*, not only under adversarial input.

There is no information-disclosure angle: the pattern is matched only against the `player` column of
an already-loaded cache, never against a filesystem path, SQL, or shell command. Severity is bounded
at Medium because the impact is a broken tab for the one local user, with no privilege boundary
crossed.

**Fix direction — with a caveat worth flagging.** The obvious fix, adding `fixed = TRUE`, is subtly
wrong: R silently discards `ignore.case` when `fixed = TRUE`, which changes search behavior without
any error. Verified:

```
  fixed=TRUE  "Wilson" -> 6 matches   (Warning: argument 'ignore.case = TRUE' will be ignored)
```

Use `stringr::str_detect(player, stringr::fixed(input$props_search_player, ignore_case = TRUE))`,
which preserves case-insensitive substring search correctly — `stringr` is already a dependency via
`tidyverse`, and `word()` from it is used throughout this repo. If regex search is a desired
feature, keep `grepl()` but wrap the reactive in `tryCatch(..., error = function(e) df)` so an
in-progress pattern degrades to "no filter applied" rather than breaking the tab.

### M-4. `adjust_mu_for_opponent()` ships a formula its own comment says is backwards, over an unstable denominator

**File:** `player_props_engine.R:151-159`

```r
adjust_mu_for_opponent <- function(base_mu, opp_def_rapm, league_avg_def) {
  # Note: In RAPM, a higher defensive rating usually means BETTER defense (lower points allowed).
  # If opp_def_rapm > league_avg, the opponent is more defensive -> mu should decrease.
  # So we use (league_avg / opp_def) or similar.
  # However, the prompt explicitly says: base_mu * (opp_def_rapm / league_avg_def_rapm).
  # I will follow the prompt's formula exactly.
  base_mu * (opp_def_rapm / league_avg_def)
}
```

The comment states the sign is inverted and then implements the inverted version anyway, deferring to
a prompt rather than to the math. As written, facing a **better** defense **increases** a player's
projected mean.

Compounding this, the denominator is unstable. `league_avg_def` comes from
`mean(rapm_df$drapm, na.rm = TRUE)` (`player_props_engine.R:144`), and the real distribution is:

```
 mean(drapm) = 7.12186   min = -0.7   max = 15.75
 n drapm < 0 : 3 of 430
```

The multiplier `opp_def_rapm / league_avg_def` therefore ranges roughly 0 to 2.2 across teams — a
player's projected points can swing by more than 2× purely from opponent adjustment, and a negative
team aggregate would flip the projection's sign outright. There is no clamp.

This currently has no production effect only because the enclosing stage hard-fails at H-2. It will
become live the moment H-2 is fixed.

**Fix direction.** Resolve the sign question against real data before re-enabling: regress actual
player scoring against opponent `def_rapm` on `player_box_scores_cache.rds` and let the observed
slope decide, rather than either the comment or the prompt. Clamp the multiplier to a defensible
range (e.g. `pmin(pmax(ratio, 0.85), 1.15)`) and centre the adjustment additively rather than
multiplicatively to avoid the near-zero-denominator blowup. Delete the "I will follow the prompt's
formula exactly" rationale — it is not a modeling justification.

### M-5. Predictions are logged against synthetic fixture games that can never reconcile

**Files:** `prediction_accuracy_logger.R:340-366`, fed by `market_odds_engine.R:243-257`

With `ODDS_API_KEY` unset, `fetch_market_odds()` returns the clearly-labeled `SYNTHETIC_FALLBACK`
fixture slate — six fabricated matchups on fabricated dates. `log_todays_predictions()` then logs
model predictions for those fabricated games into the **production** accuracy log, with no marker
that the underlying slate was synthetic.

**Reproduction:**

```
 pending rows: 14
 pending game_dates: 2026-09-14, 2026-09-15, 2026-09-16, 2026-09-17, 2026-09-18
 max home game_date in box cache: 2026-08-30
 any pending date present in box cache? FALSE
```

These games do not exist, so `reconcile_predictions()`'s `inner_join` (line 359-360) can never match
them. Confirmed in the live log:

```
[2026-09-16 06:22:00] [INFO] [prediction_accuracy_logger.R] No PENDING rows matched a completed
  game in box_scores_cache.rds yet. | call: reconcile_predictions() | pending_rows: 14
```

Note the log message — "yet" — frames a permanent condition as a transient one. The count will grow
by ~6 rows per pipeline run indefinitely.

I did verify the join key derivation itself is **correct** (`WNBA_TEAMS[home_team]` is indexed by
abbreviation and `home_team` genuinely stores abbreviations like `CHI`/`DAL`, yielding
`Sky`/`Wings`, which match `team_short_display_name` exactly) — the failure is the data, not the key.

The schema already records `injury_data_source` and `shot_quality_data_source` provenance but has no
equivalent field for the odds/slate source, which is why `SYNTHETIC_FALLBACK` provenance is lost.

**Fix direction.** Propagate a `market_data_source` column from `fetch_market_odds()` through
`log_todays_predictions()` (mirroring the existing `injury_data_source` pattern), and either skip
logging entirely when the slate is `SYNTHETIC_FALLBACK` or mark those rows so they are excluded from
accuracy aggregation. Add an age-based sweep that moves `PENDING` rows older than ~7 days past their
`game_date` to an `UNRESOLVABLE` status, so the stuck-row count is visible instead of silently
accumulating.

### M-6. The scalar `%||%` landmine exists in `market_odds_engine.R` too, not just `app.R`

**Files:** `market_odds_engine.R:60`, `app.R:50`, vs. `logging_utils.R:23`

`CLAUDE.md` documents `app.R`'s `%||%` as a scalar-only operator that hard-errors on vectors. The
identical definition is also in `market_odds_engine.R`, which the documentation does not mention:

```
  app.R:              `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b
  market_odds_engine: `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b
  logging_utils:      `%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)[1]) a else b
```

`logging_utils.R` has the hardened `[1]`-subscripted variant; the other two do not. Since
`logging_utils.R` is sourced by nearly every script, **which definition wins depends on source
order** — a script sourcing `config.R` → `logging_utils.R` → then defining its own gets the unsafe
one; a different order gets the safe one. This is a latent, order-dependent behavior difference for
the same operator name.

Current uses in `market_odds_engine.R` are genuinely scalar and safe
(`game$commence_time %||% ...` at line 273, `sq_db$shooting_luck_pts[...][1] %||% 0.0` at
lines 398-399), so this is a latent hazard rather than an active bug — but it is the exact shape
that already produced one real production incident per `CLAUDE.md`.

**Fix direction.** Define `%||%` **once**, in `config.R` or `logging_utils.R`, using the hardened
`is.na(a)[1]` form, and delete the local redefinitions in `app.R` and `market_odds_engine.R`. One
definition removes the source-order ambiguity entirely. Consider renaming it (`%|s|%`) to signal
scalar-only semantics and avoid collision with `rlang`/base R's vector-safe `%||%`.

### M-7. Parallel stages use unsafe RNG and serialize log writes through a single-writer DuckDB file

**File:** `run_full_pipeline.R:156-174, 190-200`

The pipeline runs two stage groups under `future_lapply` with `plan(multisession)`. Two problems, the
first confirmed by a real warning in the run log:

**1. Non-reproducible Monte Carlo.** `future_lapply` is called without `future.seed`:

```
3: UNRELIABLE VALUE: One of the 'future.apply' iterations ('future_lapply-2') unexpectedly
   generated random numbers without declaring so. There is a risk that those random numbers are
   not statistically sound and the overall results might be invalid. To fix this, specify
   'future.seed=TRUE'.
```

This affects `copula_props_engine.R` (Gaussian copula simulation) and `player_props_engine.R`, both
in parallel group 2. Their `set.seed()`-based reproducibility guarantees do not hold across worker
processes, so props pricing is not reproducible run-to-run — which undermines any attempt to
attribute a change in output to a code change rather than to RNG drift.

**2. Log writes contend for an exclusive lock.** `logging_utils.R:.log_write()` opens a fresh
`dbConnect(duckdb(), LOG_DB_FILE)` for **every single log line** (line 89), writes one row, and
disconnects. DuckDB permits only one writing process per database file. With three concurrent
workers logging, connections will be refused — and the `tryCatch` at lines 99-102 swallows the
failure into a console `[LOG DB ERROR]` line, so those log records are silently dropped from
`logs.duckdb` while still appearing in the text log.

In fairness, I checked and **no `[LOG DB ERROR]` has occurred yet** (`grep -c` returns 0 in both
`pipeline_execution.log` and `logs/wnba_pipeline.log`) — the parallel stages currently log little
enough, and finish fast enough, to avoid collision. This is a race that has not yet been lost, not a
manifest failure. The concurrent `cat(..., append = TRUE)` to the shared text log (line 85) is
likewise interleaving-prone for lines exceeding the OS atomic-write size — and the stack traces this
logger emits are multi-kilobyte.

**Fix direction.** Pass `future.seed = TRUE` to both `future_lapply` calls. For logging, hold one
DuckDB connection for the process lifetime rather than reconnecting per line, and have worker
processes buffer log rows in memory and return them to the parent for a single serialized write —
or simply write per-worker text logs (`wnba_pipeline_<pid>.log`) and merge afterward. At minimum,
promote the swallowed `[LOG DB ERROR]` to something that surfaces in the run summary, since a
logging subsystem that silently loses records defeats its own purpose.

### M-8. `projected_wnba_standings.rds` stores `Win_Pct` as a formatted string

**File:** `roster_bottom_up_engine.R` (standings writer), consumed by `app.R:409`,
`market_odds_engine.R:368`, `playoff_simulator.R:188`

```
 Win_Pct class: character   values: 79.3%,79.3%,73.2%
 as.numeric(Win_Pct) -> NA,NA,NA
```

A presentation-formatted percentage is persisted into a cache that is an *input* to three downstream
consumers. Any consumer that treats it numerically gets silent `NA`s (with only a coercion warning),
and `NA` flows through `mean()`/`sort()`/comparison operations in ways that are easy to miss.

Today's consumers happen to read `Net_Rating` rather than `Win_Pct`, so nothing is broken right now —
but this is a trap laid for the next person to touch the standings cache. The adjacent columns
(`Proj_Wins = 34.9`, `Proj_Losses = 9.1`) are correctly stored as numerics, which makes the
inconsistency easy to trip over.

**Fix direction.** Store `Win_Pct` as a numeric proportion (`0.793`) and format it with
`scales::percent()` at the point of display in `app.R`. Keep caches typed for computation; formatting
belongs in the view layer.

---

## LOW

### L-1. `resolve_team_name()` passes a length-15 vector as a `grepl` pattern

**File:** `market_odds_engine.R:173-174`

```r
nick <- tolower(word(full_names, -1))
hit_nick <- full_names[grepl(paste0("\\b", nick, "\\b"), s) | mapply(function(n) grepl(n, s, fixed = TRUE), nick)]
```

`paste0("\\b", nick, "\\b")` is length 15; `grepl()` uses only the first element and warns. Confirmed
in the fuzz run:

```
   [R warning] argument 'pattern' has length > 1 and only the first element will be used
```

So the first clause effectively only ever tests the nickname `"dream"`, and its length-1 result is
recycled across all 15 positions by the `|`. The bug is currently **harmless by coincidence**:
`nick[1]` is `"dream"` and `full_names[1]` is `"Atlanta Dream"`, so when it does fire it returns the
right answer. It becomes wrong the moment `WNBA_TEAMS`' ordering changes — and `config.R:45-46`
explicitly anticipates that ("the WNBA has publicly announced further expansion (Cleveland 2028,
Detroit 2029, Philadelphia 2030) — re-verify this vector"). Alphabetical insertion of a Cleveland
entry would place it first and silently break this.

**Fix direction.** Vectorize properly: `vapply(nick, function(n) grepl(paste0("\\b", n, "\\b"), s), logical(1))`.

### L-2. Comment-vs-code drift on `ROLLING_WINDOW_SIZE` and the window-sweep artifact path

**Files:** `config.R:111`, `tools/ml_cv_benchmark.R:62`

`config.R:121` sets `ROLLING_WINDOW_SIZE <- 12` (correctly updated after the 3-25 sweep), but:

- `tools/ml_cv_benchmark.R:62` still says *"window_size default overridden by caller to
  ROLLING_WINDOW_SIZE = 13"*. The code reads the constant so behavior is correct; only the comment
  is stale.
- `config.R:111` cites the sweep result as living in `cache/window_sweep_3_25_results.rds`. The file
  that actually exists is `data/window_sweep_3_25_results.csv` — different directory *and* different
  extension. (`cache/window_sweep_3_25_results.rds` does also exist, so this one is merely confusing
  rather than dangling.)
- `config.R:127-134` describes the offseason-method re-benchmark as run at `window_size=13`, which
  is no longer the live value — the `"reset"` conclusion may or may not survive at 12, and nothing
  records whether that was rechecked.

Per `CLAUDE.md`'s own guidance ("read the value from `config.R` itself rather than trusting a
specific number restated elsewhere"), these restatements are exactly the hazard that rule exists for.

**Fix direction.** Update the three comments; where a comment must cite a constant's value, cite the
constant's *name* instead.

### L-3. Rolling feature builder mixes `turnovers` and `total_turnovers` for the same concept

**Files:** `tools/ml_cv_benchmark.R:72,82`, `tools/ml_feature_experiments.R` (same block)

```r
tov      = total_turnovers / pmax(1, field_goals_attempted + 0.44 * free_throws_attempted + total_turnovers),
roll_tov = slide_dbl(turnovers, mean, .before = window_size, .after = -1),
```

The four-factors turnover *rate* uses `total_turnovers`; the rolling turnover *count* feature uses
`turnovers`. These are genuinely different columns in the cache:

```
turnovers-ish cols: team_turnovers, total_turnovers, turnovers, turnover_points
mean turnovers: 13.17   mean total_turnovers: 14.09   identical? FALSE
```

(`total_turnovers` ≈ `turnovers` + `team_turnovers`.) Both end up as model features named similarly
(`diff_roll_tov` and `diff_roll_tovp`), so the mix is plausibly unintentional. Impact is limited —
it is a defensible feature either way, and the model is fit on whatever it is given — but it should
be a deliberate choice rather than an accident.

**On leakage specifically, which I checked carefully: the rolling-window logic is correct.** Every
`slide_dbl()` call uses `.before = window_size, .after = -1`, which ends the window at row *i-1* and
genuinely excludes the current game. `days_rest` uses `lag(game_date)`. The `group_by(season, team_id)`
in `build_feature_df()` correctly prevents windows from spanning teams or seasons, and
`tools/build_calibration_cache.R:94` similarly uses `lag(margin)`. I found **no lookahead leakage** in
the feature pipeline.

**Fix direction.** Pick one column for both, and note the choice in a comment.

### L-4. `daily_ingest.R` is not in the pipeline DAG

**Files:** `run_full_pipeline.R:119-214`, `daily_ingest.R:130`

`daily_ingest.R` — the script whose header describes it as the "Automated Daily Box Score Ingestion
Pipeline" — is never invoked by `run_full_pipeline.R`. It is not among the 17 `run_stage()` calls.

In practice box-score ingestion still happens, because `prediction_accuracy_logger.R` sources
`daily_ingest.R` and calls `daily_box_ingest()` as a side effect of reconciliation — visible in the
log, where the ingestion messages are attributed to the wrong script:

```
[2026-09-16 06:21:57] [INFO] [prediction_accuracy_logger.R] Starting daily WNBA box score ingestion...
[2026-09-16 06:21:59] [INFO] [prediction_accuracy_logger.R] Fetched 602 new-season team box rows.
```

So the data is fresh, but the dependency is implicit and the logs misattribute it. If
`prediction_accuracy_logger.R` were ever reordered or removed, box ingestion would stop with no
corresponding stage failure. Note also that `daily_ingest.R:130` uses the `sys.nframe() == 0` guard
from C-2, so adding it to the DAG naively would produce a no-op.

**Fix direction.** Add `daily_ingest.R` as an explicit early stage using the `call_fn =
"daily_box_ingest"` mechanism, and have `prediction_accuracy_logger.R` consume the cache rather than
trigger the ingest.

### L-5. Scratch files committed at repo root

**Files:** `temp_check_rapm.R`, `temp_derive_copula.R`, `temp_derive_props.R`,
`temp_derive_props_rot.R`, `.Rhistory`

Four `temp_*.R` derivation scratch files sit in the root alongside production scripts, in a repo whose
convention is that *everything* at root is a pipeline script sourced by bare filename. They are not
sourced by anything, but they are indistinguishable from production files to a newcomer, and
`temp_derive_props_rot.R` duplicates rotation-selection logic that belongs to
`player_props_engine.R`.

Separately, `.Rhistory` (23 KB) contains a verbatim transcript of past sessions, including a full
copy of `fetch_market_odds()` with the `Sys.getenv("ODDS_API_KEY", "")` block (line 220). It contains
no secret today, but an interactive session in which someone pastes a key would capture it there.

**Fix direction.** Move the four `temp_*.R` files into `tools/` with descriptive names, or delete
them. Add `.Rhistory` to a `.gitignore` in anticipation of this repo ever being versioned.

### L-6. Two `latest_player_props.rds` copies are written, with a silent precedence rule

**Files:** `player_props_engine.R:427-428`, `app.R:444-447`, `config.R:173`

```r
saveRDS(all_props, "data/latest_player_props.rds")
saveRDS(all_props, "cache/latest_player_props.rds")
```

Two full copies are written. `app.R` prefers `data/`, falling back to `cache/`. `config.R:173`'s
`CACHE_PLAYER_PROPS` constant — used by `tools/data_health_probe.R:39` for its health check — points
at `cache/`. They are byte-identical today (verified: `identical(pp1, pp2)` is `TRUE`, both 720 rows,
both `2026-09-14 09:51`), so nothing is wrong right now.

The hazard is that any future partial write, or any path that updates one location only, produces a
split-brain where the dashboard reads one file and the health probe validates the other — and the
health probe would report green on a file nobody displays.

**Fix direction.** Write one canonical location (`CACHE_PLAYER_PROPS`) and have `app.R` read that
constant rather than two bare literals.

---

## What I Checked That Was Clean

Recording negative results so the next reviewer doesn't re-spend effort here:

- **No command or code injection.** All three `system()` call sites take hardcoded literals; no
  user/network/filesystem input reaches them (detail in M-1). The two `eval(parse(...))` sites in
  `tools/test_logging_fault_injection.R` parse this repo's own source files.
- **No hardcoded secrets.** Every `Sys.getenv()` call has a safe `""` default:
  `market_odds_engine.R:192`, `live_game_listener.R:38,43`, `notify_bets.R:34`, `config.R:195`,
  `tools/headless_dashboard_probe.R:20,24`. Empty values are handled as explicit "not configured"
  no-ops rather than producing malformed requests. The NBA original's hardcoded Discord webhook was
  correctly **not** carried over. The only secrets issue found is the runtime log leak (H-1).
- **No lookahead leakage in the rolling-window or CV logic** — verified across
  `tools/ml_cv_benchmark.R`, `tools/ml_feature_experiments.R`,
  `tools/backtest_margin_hyperparams.R`, and `tools/build_calibration_cache.R` (detail in L-3).
- **No ReDoS** in the Shiny regex path — measured, not assumed (detail in M-3).
- **No path traversal.** All `readRDS()`/`file.path()` targets are built from `config.R` constants or
  string literals; no `input$` value reaches a filesystem path.
- **The four `CLAUDE.md` fixes are genuinely in place** at the locations documented — the exhibition
  filter and `CONN`→`CON` normalization in `daily_ingest.R:37-58` (confirmed live in the run log:
  *"Filtered out 2 non-franchise exhibition/All-Star rows (abbreviations: COOP, SPO)"*, and the cache
  contains exactly the 15 canonical abbreviations with `CON` present), and the RAPM join fix at
  `market_odds_engine.R:104-115`. Their un-fixed siblings are reported separately as H-2 and M-6.

---

## Suggested Remediation Order

1. **C-1** (HCA `11.6` → `2.40`, centralized in `config.R`) — smallest diff, largest correctness
   impact, and every cached artifact produced under the wrong value needs regenerating anyway.
2. **C-2** (auto-run guards) — until this lands, nothing else can be verified end-to-end, because
   four stages don't run. Fix **H-2** in the same pass: repairing C-2 un-masks
   `roster_bottom_up_engine.R:84`'s latent join failure.
3. **H-1** (key redaction in the logger) — must land **before** anyone provisions a real
   `ODDS_API_KEY` per `docs/ODDS_API_SETUP.md`, or the first network blip burns the key.
4. **C-3 / H-3** (accuracy tab: synthetic-row filtering and the stale path/columns) — these two
   together are the difference between a dashboard that reports measured performance and one that
   reports fiction.
5. **H-4, M-1, M-2, M-4, M-5** — correctness and observability hardening.
6. Remaining Medium/Low items as cleanup.

A useful structural follow-up, independent of any individual finding: the recurring failure mode in
this codebase is **a fail-safe fallback that is indistinguishable from success**. C-2, H-2, H-3, and
M-1 are four instances of the same pattern. The existing design principle ("never hard-crash the
pipeline") is sound, but it needs a counterweight — a post-run summary that asserts each stage's
declared output actually advanced, and reports `STALE`/`SYNTHETIC`/`FAILED` counts alongside the
`[COMPLETED]` lines. `tools/data_health_probe.R` already exists and runs as stage 0; running the same
probe again as a final stage, comparing `mtime`s against the run's start time, would have surfaced
C-2, H-2, and H-3 automatically.
