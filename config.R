# ==============================================================================
# NBA Analytics Pipeline - Global Configuration
# Path: c:/Users/kailo/kayceeslices/NBA Analytics/config.R
# ==============================================================================

# Working and Cache Directories
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NBA Analytics"
CACHE_DIR   <- file.path(PROJECT_DIR, "cache")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# Data Horizons
HISTORICAL_SEASONS <- 2019:2025
TEST_SEASON        <- 2026
CURRENT_SEASON     <- 2026
ALL_SEASONS        <- 2019:2026
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

# API Throttling & Rate-Limiting
RATE_LIMIT_SLEEP_SEC <- 1.5
MAX_RETRIES          <- 3

# DISCORD_WEBHOOK is read from the environment (set via .Renviron, not committed to git).
# See .Renviron.example for the expected format.