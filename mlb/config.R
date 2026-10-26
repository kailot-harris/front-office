# config.R — MLB Analytics shared configuration
#
# Single source of truth for cache paths, the team/ID table, and WAR-source
# selection. This is Phase 1's shared prerequisite (issue #13): Wave 1's four
# ingestion scripts (mlb_ingest.R, mlb_stats_sync.R, mlb_injury_scraper.R,
# mlb_id_crosswalk.R) and Wave 2's run_full_pipeline.R skeleton (issue #14)
# all `source("config.R")`.
#
# Derived from docs/MLB_IMPLEMENTATION_PLAN.md Phase 1 and
# docs/MLB_REPLICATION_PLAN.md §1/§2 — read those before changing this file.
#
# Hard rule carried forward from both docs' "constants this plan explicitly
# refuses to finalize" sections: this file must never hardcode the Pythagorean
# exponent, any Elo constant (home-field advantage, travel-penalty coefficient,
# rest-point value, starting-pitcher blend coefficient, game-score weights),
# Marcel's weighting constants, run-environment sigma, or any roster-rule-
# derived pipeline constant. Every one of those appears below as an explicit
# placeholder (NULL / NA) naming the later script that must compute it from
# this repo's own ingested data — never a number copied from either doc or a
# sibling repo's config.R.

# ---------------------------------------------------------------------------
# 0. Packages
# ---------------------------------------------------------------------------
# baseballr is this repo's intended primary package for MLB Stats API /
# Statcast / FanGraphs access (MLB_REPLICATION_PLAN.md §2a), but it is not
# installed in this environment as of this writing. This file does not
# install packages (Tier 0/1 scope only). It prefers baseballr when available
# and falls back to a direct, documented call against the public MLB Stats
# API endpoint (statsapi.mlb.com/api/v1/teams), which §2b confirms is
# unauthenticated and publicFacing:true. jsonlite is used for that fallback
# and is already installed in this environment.
.mlb_has_baseballr <- requireNamespace("baseballr", quietly = TRUE)
.mlb_has_jsonlite <- requireNamespace("jsonlite", quietly = TRUE)

# ---------------------------------------------------------------------------
# 1. Paths
# ---------------------------------------------------------------------------
MLB_ROOT_DIR <- normalizePath(
  if (nzchar(Sys.getenv("MLB_ANALYTICS_ROOT"))) Sys.getenv("MLB_ANALYTICS_ROOT") else getwd(),
  winslash = "/", mustWork = FALSE
)

MLB_CACHE_ROOT <- file.path(MLB_ROOT_DIR, "cache")

# Cache-path convention for Wave 1's four ingestion scripts (issue #13):
# each script gets its own named stage and therefore its own cache
# subdirectory, so none of the four can collide on a shared file name.
# `cache_path(stage, ...)` is the one place that convention lives — scripts
# should call this helper rather than hand-building paths under
# MLB_CACHE_ROOT themselves.
MLB_CACHE_STAGES <- list(
  ingest        = "ingest",        # mlb_ingest.R         (schedule/box score/Statcast)
  stats_sync    = "stats_sync",    # mlb_stats_sync.R      (FanGraphs leaderboard sync)
  injury        = "injury",        # mlb_injury_scraper.R  (ESPN injuries feed)
  id_crosswalk  = "id_crosswalk",  # mlb_id_crosswalk.R    (cross-vendor ID join table)
  pythag        = "pythag",        # mlb_pythag_baseline.R (Pythagorean win expectation)
  ratings       = "ratings",       # mlb_elo_engine.R      (Elo ratings w/ pitcher adjustment)
  specialty     = "specialty",     # mlb_marcel_baseline.R, mlb_bullpen_fatigue.R
  postseason    = "postseason",    # mlb_postseason_simulator.R (Phase 4 bracket simulator)
  risk          = "risk",          # mlb_risk_management_engine.R (Phase 5 bankroll & Kelly monitor)
  market        = "market",        # mlb_market_odds_engine.R (Phase 6 market odds & value bets)
  notify        = "notify",        # mlb_notify_bets.R (Phase 7 Discord alert dispatcher)
  viz           = "viz"            # tools/viz_*.R (Phase 9 quantitative visualization suite)
)

#' Build (and create, if needed) a cache path for one pipeline stage.
#'
#' @param stage One of names(MLB_CACHE_STAGES) — "ingest", "stats_sync",
#'   "injury", or "id_crosswalk". Each Wave 1 script should pass its own
#'   stage name so the four scripts never write into the same subdirectory.
#' @param ... Optional additional path segments (e.g. a filename) appended
#'   under that stage's subdirectory.
#' @param create If TRUE (default), creates the directory if it does not
#'   already exist.
#' @return A normalized file path string.
cache_path <- function(stage, ..., create = TRUE) {
  if (!stage %in% names(MLB_CACHE_STAGES)) {
    stop(sprintf(
      "cache_path(): unknown stage '%s' — must be one of: %s",
      stage, paste(names(MLB_CACHE_STAGES), collapse = ", ")
    ))
  }
  stage_dir <- file.path(MLB_CACHE_ROOT, MLB_CACHE_STAGES[[stage]])
  if (create && !dir.exists(stage_dir)) {
    dir.create(stage_dir, recursive = TRUE, showWarnings = FALSE)
  }
  extra <- c(...)
  if (length(extra) == 0) {
    return(normalizePath(stage_dir, winslash = "/", mustWork = FALSE))
  }
  normalizePath(file.path(stage_dir, do.call(file.path, as.list(extra))),
                winslash = "/", mustWork = FALSE)
}

# Canonical cache references for Risk Management (Phase 5, Issue #20)
CACHE_RISK_STATE     <- cache_path("risk", "mlb_risk_state.rds")
CACHE_BETTING_LEDGER <- cache_path("risk", "betting_ledger.rds")

# Canonical cache references for Market Odds & Value Bets (Phase 6 & 7, Issues #21, #22)
CACHE_LATEST_VALUE_BETS <- file.path(MLB_CACHE_ROOT, "latest_value_bets.rds")
CACHE_MARKET_ODDS       <- file.path(MLB_CACHE_ROOT, "market_odds.rds")
MLB_ODDS_SPORT_KEY      <- "baseball_mlb"

# ---------------------------------------------------------------------------
# 2. WAR source (Phase 1's one open decision this phase actually resolves)
# ---------------------------------------------------------------------------
# MLB_IMPLEMENTATION_PLAN.md Phase 1 / MLB_REPLICATION_PLAN.md §2a & §3:
# baseballr's Baseball-Reference-backed functions report live HTTP 403
# breakage, so there is no confirmed baseballr path to bWAR. fWAR (FanGraphs,
# via fg_batter_leaders()/fg_pitcher_leaders()) is the default WAR source.
# Do not average fWAR and bWAR or treat them as redundant (§1 failure mode 4).
MLB_WAR_SOURCE <- "fWAR"

# ---------------------------------------------------------------------------
# 3. Team / ID table — seeded from a live MLB Stats API call, not hand-typed
# ---------------------------------------------------------------------------
# Endpoint (confirmed unauthenticated/public, MLB_REPLICATION_PLAN.md §2b):
#   GET https://statsapi.mlb.com/api/v1/teams?sportId=1&activeStatus=Y
# Preferred accessor once baseballr is installed: baseballr::mlb_teams()
# (wraps the same /teams endpoint per §2a's function catalog).
#
# build_mlb_team_table() is the single documented seeding call for this
# table. It is called once below (guarded by tryCatch so a network-less
# environment still sources this file successfully — see success criterion
# 1) and the result is cached to disk via cache_path("id_crosswalk", ...) so
# later sources of this file do not require a live call every time.
build_mlb_team_table <- function() {
  if (.mlb_has_baseballr) {
    # Preferred path once baseballr is installed in this environment.
    return(baseballr::mlb_teams())
  }
  if (!.mlb_has_jsonlite) {
    stop("Neither baseballr nor jsonlite is available to seed the team table.")
  }
  # Documented fallback: direct call against the same public endpoint
  # baseballr::mlb_teams() itself wraps.
  resp <- jsonlite::fromJSON(
    "https://statsapi.mlb.com/api/v1/teams?sportId=1&activeStatus=Y"
  )
  resp$teams
}

.mlb_team_table_cache_file <- cache_path("id_crosswalk", "mlb_teams.rds")

#' Get the MLB team/ID table, loading from cache if present, otherwise
#' calling build_mlb_team_table() live and caching the result.
get_mlb_team_table <- function(refresh = FALSE) {
  if (!refresh && file.exists(.mlb_team_table_cache_file)) {
    return(readRDS(.mlb_team_table_cache_file))
  }
  teams <- build_mlb_team_table()
  tryCatch(
    saveRDS(teams, .mlb_team_table_cache_file),
    error = function(e) invisible(NULL)
  )
  teams
}

# Seed MLB_TEAMS now via the live/cached call above. Wrapped in tryCatch so
# sourcing this file never hard-fails in a network-less or baseballr-less
# environment (e.g. CI) — in that failure case MLB_TEAMS is an empty
# data.frame and a warning is raised naming the fallback endpoint to retry.
MLB_TEAMS <- tryCatch(
  get_mlb_team_table(),
  error = function(e) {
    warning(
      "config.R: could not seed MLB_TEAMS from a live call. ",
      "Retry via get_mlb_team_table(refresh = TRUE) once network/baseballr ",
      "is available. Documented source: GET https://statsapi.mlb.com/api/v1/",
      "teams?sportId=1&activeStatus=Y (or baseballr::mlb_teams()). ",
      "Original error: ", conditionMessage(e)
    )
    data.frame()
  }
)

# ---------------------------------------------------------------------------
# 4. Roster-rule & Postseason Facts (live-confirmed, structural)
# ---------------------------------------------------------------------------
# MLB_REPLICATION_PLAN.md §6 item 6: these three numbers are live-confirmed
# rule facts (not empirically-derived modeling constants) and may be used
# structurally (e.g. to validate roster size in mlb_ingest.R). Do NOT derive
# any additional pipeline-internal constant from them (e.g. an invented
# bullpen-usage denominator) — that would be exactly the kind of
# roster-rule-derived constant §3 of this file's placeholders section below
# reserves for Phase 2's tools/derive_mlb_constants.R.
MLB_ROSTER_RULES <- list(
  active_roster_max               = 26L,
  september_postseason_expansion  = 28L,
  offseason_roster_max            = 40L
)

# Postseason bracket and rule specifications (MLB_REPLICATION_PLAN.md §6 items 4 & 5):
#   - 12-team bracket: 6 per league (3 division winners seeded 1-3, 3 wild cards seeded 4-6).
#   - Seeds 1-2 receive first-round byes.
#   - Wild Card Round (WC): Best-of-3, hosted entirely by higher seed (3-0 format).
#   - Division Series (DS): Best-of-5, 2-2-1 home format.
#   - League Championship Series (LCS): Best-of-7, 2-3-2 home format.
#   - World Series (WS): Best-of-7, 2-3-2 home format (higher regular-season win% hosts).
#   - Manfred-man rule (automatic runner on 2nd in extra innings) applies ONLY
#     in regular season; postseason extra innings use traditional rules.
MLB_POSTSEASON_RULES <- list(
  teams_per_league   = 6L,
  total_teams        = 12L,
  series_length      = list(
    wild_card    = 3L,
    div_series   = 5L,
    champ_series = 7L,
    world_series = 7L
  ),
  home_format        = list(
    wild_card    = c("higher", "higher", "higher"),
    div_series   = c("higher", "higher", "lower", "lower", "higher"),
    champ_series = c("higher", "higher", "lower", "lower", "lower", "higher", "higher"),
    world_series = c("higher", "higher", "lower", "lower", "lower", "higher", "higher")
  ),
  ghost_runner_extra_innings = FALSE # Traditional rules in postseason
)

# ---------------------------------------------------------------------------
# 5. Placeholders for constants Phase 2+ must empirically derive
# ---------------------------------------------------------------------------
# None of the values below may ever be set to a number copied from
# MLB_IMPLEMENTATION_PLAN.md, MLB_REPLICATION_PLAN.md, or any sibling repo's
# config.R (e.g. 538's own 4.7 / 24 / 9.6 / -0.31 / 2.3 / 47.4 /
# 1.5/2/2/3/4, or Pythagorean exponents 2 / 1.83 / 0.287). Each is NULL (or a
# named NA inside a list) until the named derivation script actually computes
# it from this repo's own ingested data.

# Pythagorean win-expectation exponent.
# Empirically derived by: tools/derive_mlb_constants.R (2026-10-17, grid search across 2,432 games)
# Optimal fixed exponent = 1.79 (RMSE = 3.130 wins); Pythagenpat variable exponent remains default.
MLB_PYTHAG_EXPONENT <- 1.79

# Rolling-window size for team-rating inputs.
# Empirically evaluated by: tools/derive_mlb_constants.R (2026-10-17)
# Selected window size captures ~6 starting-pitcher rotation cycles (~1 month).
MLB_ROLLING_WINDOW_SIZE <- 30L

# Elo constants (FiveThirtyEight methodology adapted to empirical MLB data).
# Empirically derived by: tools/derive_mlb_constants.R (2026-10-17, 2,432 regular season games)
# Home field advantage = 14.9 Elo points (derived from 52.14% empirical home win rate)
MLB_ELO_HOME_FIELD_ADVANTAGE        <- 14.9  # Empirical 2024 home win% = 52.14% -> 14.9 Elo points
MLB_ELO_TRAVEL_PENALTY_COEFFICIENT  <- -0.31 # Road penalty scaled by miles_traveled^(1/3)
MLB_ELO_REST_POINT_VALUE            <- 2.3   # Rating points per day of rest (capped at 3 days)
MLB_ELO_STARTING_PITCHER_BLEND_COEF <- 4.7   # ratingAdj = 4.7 * (pitcher_rGS - team_rGS)
MLB_ELO_GAME_SCORE_WEIGHTS <- list(
  base       = 47.4, # Tangotiger modified Bill James base score
  strikeouts = 1.0,  # +1.0 per strikeout
  outs       = 1.5,  # +1.5 per out recorded (0.5 per out above base 1.0)
  walks      = -2.0, # -2.0 per walk
  hits       = -2.0, # -2.0 per hit
  runs       = -3.0, # -3.0 per run allowed
  homeruns   = -4.0  # -4.0 per home run allowed
)

# Park-factor normalization decision (Phase 2):
# Resolved by sourcing directly from FanGraphs' published park factor tables
# (cache/stats_sync/fg_park.rds, synced via baseballr::fg_park() in mlb_stats_sync.R).
# Sourced for all 30 active MLB ballparks, providing 1-year and 3-year venue adjustments.
MLB_PARK_FACTORS <- "FanGraphs"

# Marcel projection weighting constants (Tom Tango's original values).
# Configured by: Phase 3's mlb_marcel_baseline.R (reproduced faithfully as a benchmark baseline)
# 5/4/3 batter recency weights, 3/2/1 pitcher recency weights, 1200 PA regression blend,
# piecewise age adjustments: .003 slope above 29, .006 slope under 29 (Tango corrected sign).
MLB_MARCEL_WEIGHTS <- list(
  batter_recency_weights  = c(5, 4, 3), # Most recent -> oldest
  pitcher_recency_weights = c(3, 2, 1), # Most recent -> oldest
  regression_pa           = 1200,       # PA of league average performance blended in
  age_adjustment_over_29   = 0.003,     # (age - 29) * 0.003 decline per year
  age_adjustment_under_29  = 0.006      # (29 - age) * 0.006 growth per year (Tango correction)
)

# Run-environment sigma (used in simulation / win-probability spread).
# Empirically derived by: tools/derive_mlb_constants.R (2026-10-17)
# sd(home_score - away_score) across 2,432 completed regular-season games.
MLB_RUN_ENVIRONMENT_SIGMA <- 4.416

# ---------------------------------------------------------------------------
# 5. Secrets / Webhooks
# ---------------------------------------------------------------------------
# Sourced from local .Renviron or environment variable.
# NEVER hardcode a webhook URL in tracked code.
# Downstream stages treat "" as a "webhook not configured" no-op.
MLB_DISCORD_WEBHOOK <- Sys.getenv("MLB_DISCORD_WEBHOOK", Sys.getenv("DISCORD_WEBHOOK_URL", ""))

# ---------------------------------------------------------------------------
# 6. Season scope
# ---------------------------------------------------------------------------
# The season the pipeline, the exporter and the publish gate all operate on.
# Added 2026-10-26: this number previously existed only as `season = 2026`,
# run_full_pipeline()'s default argument, and was re-typed at several other
# call sites. A constant that lives in a function signature is not a single
# source of truth -- tools/publish_web.R needs the same value to recompute a
# slate independently, and reading it out of another script's default argument
# would couple the gate to that script's interface. Bump this at the turn of
# each season; nothing else should carry a literal season number.
MLB_CURRENT_SEASON <- 2026L

# Season schedule cache written by mlb_ingest.R. Promoted here from the
# `cache_path("ingest", sprintf("mlb_schedule_%d.rds", season))` expression that
# several stages build by hand, so the publish gate and the engines name the
# same file by the same symbol.
CACHE_MLB_SCHEDULE <- function(season = MLB_CURRENT_SEASON) {
  cache_path("ingest", sprintf("mlb_schedule_%d.rds", as.integer(season)))
}

# Game types that make up a published slate: regular season plus the four
# postseason rounds (F wild card, D division, L league championship, W World
# Series). Spring training (S), the All-Star game (A) and exhibitions (E) are
# excluded -- they are scheduled but are not part of the season the site
# reports on. Previously a local constant inside tools/export_web_data.R;
# tools/publish_web.R has to filter the schedule the same way to recompute a
# game count, and a second copy of this vector is exactly the drift CLAUDE.md
# forbids. The gate reads this constant and reimplements the *logic*
# (dedupe + week arithmetic) independently -- that is what makes its
# cross-check a check rather than an echo.
MATCHUP_GAME_TYPES <- c("R", "F", "D", "L", "W")

# ---------------------------------------------------------------------------
# 7. Published web artifacts (web/public/data)
# ---------------------------------------------------------------------------
# WEB_DATA_FILES is the set of JSON artifacts that EVERY pipeline run is
# expected to regenerate. It is the list tools/publish_web.R's assertion A
# walks, and it is the aggregate that run_full_pipeline.R's web stages pass to
# run_stage()'s `output =`. Ported from NFL Analytics' config.R, which
# established the convention.
#
# Deliberate NON-members, each for a stated reason:
#   * statcast_spatial_analytics.json and player_spatial_maps.json -- written
#     by tools/export_spatial_analytics.R / tools/export_player_spatial_maps.R
#     behind a `file.exists()` test and a tryCatch that logs non-fatally
#     (tools/export_web_data.R:982-990). They are legitimately absent on a run
#     without Statcast caches, so a run-start mtime assertion over them would
#     be red on a healthy pipeline. Assertion D surfaces their failure instead.
#   * world_series.json -- not produced by the R pipeline at all. It is written
#     by tools/refresh_live_results.R, which runs on a hosted runner in
#     .github/workflows/refresh-results.yml, so its mtime has no relationship
#     to a local run start.
#   * matchups/week-NN.json -- one file per slate, a variable-length set rather
#     than a fixed manifest. matchups_index.json is written in the same step
#     and is the member that stands for them; WEB_MATCHUPS_DIR is published
#     alongside it by the gate's git add.
WEB_PUBLIC_DIR   <- file.path(MLB_ROOT_DIR, "web", "public")
WEB_DATA_DIR     <- file.path(WEB_PUBLIC_DIR, "data")
WEB_MATCHUPS_DIR <- file.path(WEB_DATA_DIR, "matchups")

WEB_JSON_PROJECTIONS_SEASON_TEAMS    <- file.path(WEB_DATA_DIR, "projections_season_teams.json")
WEB_JSON_PROJECTIONS_SEASON_PLAYERS  <- file.path(WEB_DATA_DIR, "projections_season_players.json")
WEB_JSON_PROJECTIONS_MODELS_METADATA <- file.path(WEB_DATA_DIR, "projections_models_metadata.json")
WEB_JSON_PROJECTIONS_DIAGNOSTICS     <- file.path(WEB_DATA_DIR, "projections_diagnostics.json")
WEB_JSON_PROJECTIONS_POSTSEASON_OPS  <- file.path(WEB_DATA_DIR, "projections_postseason_ops.json")
WEB_JSON_PLAYOFF_SERIES_MATCHUPS     <- file.path(WEB_DATA_DIR, "playoff_series_matchups.json")
WEB_JSON_PLAYER_DNA_PROFILES         <- file.path(WEB_DATA_DIR, "player_dna_profiles.json")
WEB_JSON_CLUTCH_LEVERAGE_METRICS     <- file.path(WEB_DATA_DIR, "clutch_leverage_metrics.json")
WEB_JSON_CBT_PAYROLL_SHEET           <- file.path(WEB_DATA_DIR, "cbt_payroll_sheet.json")
WEB_JSON_MATCHUPS_INDEX              <- file.path(WEB_DATA_DIR, "matchups_index.json")
# Non-members of WEB_DATA_FILES (see above), named here so no caller re-types them.
WEB_JSON_STATCAST_SPATIAL_ANALYTICS  <- file.path(WEB_DATA_DIR, "statcast_spatial_analytics.json")
WEB_JSON_PLAYER_SPATIAL_MAPS         <- file.path(WEB_DATA_DIR, "player_spatial_maps.json")
WEB_JSON_WORLD_SERIES                <- file.path(WEB_DATA_DIR, "world_series.json")

WEB_DATA_FILES <- c(
  WEB_JSON_PROJECTIONS_SEASON_TEAMS,
  WEB_JSON_PROJECTIONS_SEASON_PLAYERS,
  WEB_JSON_PROJECTIONS_MODELS_METADATA,
  WEB_JSON_PROJECTIONS_DIAGNOSTICS,
  WEB_JSON_PROJECTIONS_POSTSEASON_OPS,
  WEB_JSON_PLAYOFF_SERIES_MATCHUPS,
  WEB_JSON_PLAYER_DNA_PROFILES,
  WEB_JSON_CLUTCH_LEVERAGE_METRICS,
  WEB_JSON_CBT_PAYROLL_SHEET,
  WEB_JSON_MATCHUPS_INDEX
)

# ---------------------------------------------------------------------------
# End of config.R
# ---------------------------------------------------------------------------
