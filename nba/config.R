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
CACHE_PLAYER_PROPS <- file.path(CACHE_DIR, "latest_player_props.rds")
CACHE_BETTING_LEDGER <- file.path(CACHE_DIR, "betting_ledger.rds")
CACHE_RISK_STATE     <- file.path(CACHE_DIR, "risk_state.rds")
CACHE_PREDICTION_LOG <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")
CACHE_COACHING_REGISTRY <- file.path(CACHE_DIR, "coaching_staff_registry.rds")
CACHE_COACHING_METRICS  <- file.path(CACHE_DIR, "coaching_metrics.rds")
CACHE_COACHING_JSON     <- file.path(PROJECT_DIR, "web", "public", "data", "coaching_metrics.json")
CACHE_PLAYOFF_SERIES    <- file.path(CACHE_DIR, "playoff_series_cache.rds")
CACHE_PLAYOFF_MATCHUPS  <- file.path(PROJECT_DIR, "web", "public", "data", "playoff_series_matchups.json")
CACHE_CBA_CAP_SHEET     <- file.path(CACHE_DIR, "cba_cap_sheet_cache.rds")
CACHE_CBA_JSON          <- file.path(PROJECT_DIR, "web", "public", "data", "cba_cap_sheet.json")
CACHE_MATCHUPS          <- file.path(CACHE_DIR, "matchups_cache.rds")
CACHE_MATCHUPS_JSON     <- file.path(PROJECT_DIR, "web", "public", "data", "matchups_slates.json")
# Season-keyed hoopR pulls backing the Matchups page. The season number is hoopR's
# (end-year) numbering, which is NOT the same as CURRENT_SEASON's - see the
# SEASON SCOPE note at the top of build_matchups_dataset.R.
CACHE_MATCHUPS_SCHEDULE <- function(season) file.path(CACHE_DIR, sprintf("matchups_schedule_%d.rds", season))
CACHE_MATCHUPS_TEAM_BOX <- function(season) file.path(CACHE_DIR, sprintf("matchups_team_box_%d.rds", season))

# API Throttling & Rate-Limiting
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# DISCORD_WEBHOOK is read from the environment (set via .Renviron, not committed to git).
# See .Renviron.example for the expected format.