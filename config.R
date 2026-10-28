# ==============================================================================
# NBA Analytics Pipeline - Global Configuration
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/config.R
# ==============================================================================

# Working and Cache Directories
#   Derived from this file's own location rather than hardcoded, so the repo works
#   from any checkout path (it has been relocated once already) and so a git
#   worktree stays self-contained. Falls back to the working directory when the
#   source file's path is unavailable (e.g. pasted into a console).
PROJECT_DIR <- local({
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (is.null(ofile)) getwd() else dirname(ofile)
  normalizePath(base, winslash = "/", mustWork = FALSE)
})
CACHE_DIR   <- file.path(PROJECT_DIR, "cache")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# Public web data directory served by the Next.js app. Pipeline stages publish
# their frontend JSON here directly -- there is no manual copy step (issue #18).
WEB_DATA_DIR <- file.path(PROJECT_DIR, "web", "public", "data")
if (!dir.exists(WEB_DATA_DIR)) dir.create(WEB_DATA_DIR, recursive = TRUE)

# Data Horizons
HISTORICAL_SEASONS <- 2019:2025
TEST_SEASON        <- 2026
CURRENT_SEASON     <- 2027
ALL_SEASONS        <- 2019:2027
SIMULATION_SEASON  <- 2027

# Rolling Window & Modeling Hyperparameters
ROLLING_WINDOW_SIZE <- 18
OFFSEASON_METHOD    <- "reset"  # "reset", "mean_regress", or "decay"
REST_DAYS_CAP       <- 7
N_SIMULATIONS       <- 10000

# Margin-to-Win-Probability Scale Factor (Conditional Standard Deviation)
# In modern NBA basketball (higher pace, ~112-115 possessions per 48 min), the empirical residual
# standard deviation of final score margin conditional on expected spread is ~11.8 (documented in
# Wayne Winston, Hal Stern, and FiveThirtyEight CARMELO/RAPTOR literature).
# Used across models for margin -> win probability conversion via pnorm(margin / MARGIN_SIGMA).
MARGIN_SIGMA        <- 11.8

# Cache Filepaths
CACHE_TEAM_BOX     <- file.path(PROJECT_DIR, "box_scores_cache.rds")
CACHE_PLAYER_BOX   <- file.path(CACHE_DIR, "player_box_scores_cache.rds")
CACHE_FEATURES     <- file.path(CACHE_DIR, "features_cache.rds")
CACHE_EMBEDDINGS   <- file.path(PROJECT_DIR, "team_embeddings.csv")
CACHE_SIMILARITY   <- file.path(PROJECT_DIR, "team_similarity_matrix.csv")
CACHE_INJURY_DATA  <- file.path(CACHE_DIR, "injury_data_cache.rds")
CACHE_ACTIVE_ROSTERS <- file.path(CACHE_DIR, "active_rosters_cache.rds")
CACHE_PREDICTION_LOG <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
CACHE_COACHING_REGISTRY <- file.path(CACHE_DIR, "coaching_staff_registry.rds")
CACHE_COACHING_METRICS  <- file.path(CACHE_DIR, "coaching_metrics.rds")
CACHE_PLAYOFF_SERIES    <- file.path(CACHE_DIR, "playoff_series_cache.rds")
CACHE_CBA_CAP_SHEET     <- file.path(CACHE_DIR, "cba_cap_sheet_cache.rds")
CACHE_MATCHUPS          <- file.path(CACHE_DIR, "matchups_cache.rds")
# Target season for the Matchups page, in hoopR's season numbering (the season's
# END year: 2027 is the 2026-27 season). Deliberately SEPARATE from
# CURRENT_SEASON, and that separation is load-bearing -- build_matchups_dataset.R
# documents at length why the matchups spine must not follow CURRENT_SEASON's
# numbering convention. Moved here from that builder on 2026-10-26 because
# tools/publish_web.R has to read the same schedule cache to cross-check the
# published slate, and a switch that lives inside the script under test is not
# something a gate can read without sourcing it.
# The NBA_MATCHUPS_SEASON environment override is preserved.
MATCHUPS_HOOPR_SEASON <- {
  env <- Sys.getenv("NBA_MATCHUPS_SEASON", unset = "")
  if (nzchar(env)) as.integer(env) else 2027L
}
# Human-facing label: hoopR season 2027 -> "2026-2027".
MATCHUPS_SEASON_LABEL <- sprintf("%d-%d", MATCHUPS_HOOPR_SEASON - 1L,
                                 MATCHUPS_HOOPR_SEASON)

# Season-keyed hoopR pulls backing the Matchups page. The season number is hoopR's
# (end-year) numbering, which is NOT the same as CURRENT_SEASON's - see the
# SEASON SCOPE note at the top of build_matchups_dataset.R.
CACHE_MATCHUPS_SCHEDULE <- function(season) file.path(CACHE_DIR, sprintf("matchups_schedule_%d.rds", season))
CACHE_MATCHUPS_TEAM_BOX <- function(season) file.path(CACHE_DIR, sprintf("matchups_team_box_%d.rds", season))

# Pipeline run log. schedule_daily.bat redirects run_full_pipeline.R's stdout and
# stderr here, so it is where the ">>> NBA QUANTITATIVE ENGINE ... STARTED: <ts>"
# banner lands. tools/publish_web.R parses that banner to find the run start it
# asserts against -- this repo has no structured logger (no logging_utils.R, unlike
# its MLB and WNBA siblings), so the banner is the only machine-readable run marker
# there is. Named here rather than rebuilt in the gate and in the .bat separately.
LOG_FILE <- file.path(PROJECT_DIR, "pipeline_execution.log")

# API Throttling & Rate-Limiting
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# DISCORD_WEBHOOK is read from the environment (set via .Renviron, not committed to git).
# See .Renviron.example for the expected format.

# ---------------------------------------------------------------------------
# Published web artifacts (web/public/data)
# ---------------------------------------------------------------------------
# WEB_DATA_FILES is the set of JSON artifacts that EVERY pipeline run is
# expected to regenerate. It is the list tools/publish_web.R's assertion A
# walks. Added 2026-10-26 with that gate; before it, these paths were built
# ad hoc at each writer -- several as bare relative strings
# ("web/public/data/clutch_leverage_metrics.json" in build_clutch_dataset.R,
# build_defense_dataset.R and build_player_dna_dataset.R), which is the
# constant duplication CLAUDE.md treats as a bug rather than a style nit. Each
# writer now names its output from here.
#
# Membership rule: written by a stage that run_full_pipeline.R actually runs.
# Deliberate NON-members, each for a stated reason:
#   * offseason_transactions.json -- an INPUT, not an output. It is the
#     canonical hand-curated transaction catalog that
#     build_offseason_dataset.R reads and validates (and refuses to shrink,
#     build_offseason_dataset.R:70). Asserting that a run rewrites it would be
#     asserting the opposite of the contract.
#   * shots_index.json, shots_metadata.json and the shots/ tree -- written by
#     build_shot_chart_dataset.R, which is NOT one of run_full_pipeline.R's
#     stages. They are refreshed out of band, so a run-start mtime assertion
#     over them would be red on a healthy pipeline.
#   * projections_diagnostics.json -- present in web/public/data but written by
#     nothing in this repo (checked 2026-10-26: no writer, in any stage or
#     tool). It appears to have arrived as a copy from a sibling sport. Left in
#     place rather than deleted, since the web app may read it, but it is not
#     something a run can be expected to refresh.
WEB_PUBLIC_DIR <- file.path(PROJECT_DIR, "web", "public")

WEB_JSON_PROJECTIONS_SEASON_TEAMS    <- file.path(WEB_DATA_DIR, "projections_season_teams.json")
WEB_JSON_PROJECTIONS_SEASON_PLAYERS  <- file.path(WEB_DATA_DIR, "projections_season_players.json")
WEB_JSON_PROJECTIONS_MODELS_METADATA <- file.path(WEB_DATA_DIR, "projections_models_metadata.json")
WEB_JSON_OFFSEASON_TEAMS             <- file.path(WEB_DATA_DIR, "offseason_teams.json")
WEB_JSON_OFFSEASON_DRAFT             <- file.path(WEB_DATA_DIR, "offseason_draft.json")
WEB_JSON_COACHING_METRICS            <- file.path(WEB_DATA_DIR, "coaching_metrics.json")
WEB_JSON_CBA_CAP_SHEET               <- file.path(WEB_DATA_DIR, "cba_cap_sheet.json")
WEB_JSON_PLAYER_DNA_PROFILES         <- file.path(WEB_DATA_DIR, "player_dna_profiles.json")
WEB_JSON_DEFENSIVE_METRICS           <- file.path(WEB_DATA_DIR, "defensive_metrics.json")
WEB_JSON_CLUTCH_LEVERAGE_METRICS     <- file.path(WEB_DATA_DIR, "clutch_leverage_metrics.json")
WEB_JSON_MATCHUPS_SLATES             <- file.path(WEB_DATA_DIR, "matchups_slates.json")
WEB_JSON_PLAYOFF_SERIES_MATCHUPS     <- file.path(WEB_DATA_DIR, "playoff_series_matchups.json")
# Non-members (see above), named so no caller re-types them.
WEB_JSON_OFFSEASON_TRANSACTIONS      <- file.path(WEB_DATA_DIR, "offseason_transactions.json")
WEB_JSON_SHOTS_INDEX                 <- file.path(WEB_DATA_DIR, "shots_index.json")
WEB_JSON_SHOTS_METADATA              <- file.path(WEB_DATA_DIR, "shots_metadata.json")

WEB_DATA_FILES <- c(
  WEB_JSON_PROJECTIONS_SEASON_TEAMS,
  WEB_JSON_PROJECTIONS_SEASON_PLAYERS,
  WEB_JSON_PROJECTIONS_MODELS_METADATA,
  WEB_JSON_OFFSEASON_TEAMS,
  WEB_JSON_OFFSEASON_DRAFT,
  WEB_JSON_COACHING_METRICS,
  WEB_JSON_CBA_CAP_SHEET,
  WEB_JSON_PLAYER_DNA_PROFILES,
  WEB_JSON_DEFENSIVE_METRICS,
  WEB_JSON_CLUTCH_LEVERAGE_METRICS,
  WEB_JSON_MATCHUPS_SLATES,
  WEB_JSON_PLAYOFF_SERIES_MATCHUPS
)

# CACHE_COACHING_JSON, CACHE_CBA_JSON, CACHE_MATCHUPS_JSON and
# CACHE_PLAYOFF_MATCHUPS are the ORIGINAL names for four of the paths listed
# here, kept as aliases so existing call sites keep working. They are
# misnamed -- they are published web artifacts, not caches -- and the WEB_JSON_*
# names are the ones new code should use. Defined as aliases rather than
# duplicated literals so the two names can never point at different files.
CACHE_COACHING_JSON    <- WEB_JSON_COACHING_METRICS
CACHE_CBA_JSON         <- WEB_JSON_CBA_CAP_SHEET
CACHE_MATCHUPS_JSON    <- WEB_JSON_MATCHUPS_SLATES
CACHE_PLAYOFF_MATCHUPS <- WEB_JSON_PLAYOFF_SERIES_MATCHUPS