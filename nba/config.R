# ==============================================================================
# NBA Analytics Pipeline - Global Configuration
# Path: config.R
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

# GIF_RERENDER_DAYS (front-office weekly GIF re-render, 2026-11-21 design): render_weekly_gifs.R
# re-runs tools/gif_*.R in season once the last successful render (cache/gif_render_status.json)
# is this many days old. 6, not 7, so a weekly re-render lands before the landing slideshow's
# 7-day window drops the previous set. Override for manual runs with FO_FORCE_GIF_RENDER=1.
GIF_RERENDER_DAYS <- 6

# Data Horizons
HISTORICAL_SEASONS <- 2019:2025
TEST_SEASON        <- 2026
CURRENT_SEASON     <- 2027
ALL_SEASONS        <- 2019:2027
SIMULATION_SEASON  <- 2027

# hoopR end-year numbering: 2027 === the 2026-27 season. The label is derived from
# CURRENT_SEASON, never typed (front-office#191).
season_label <- function(end_year = CURRENT_SEASON) {
  sprintf("%d-%02d", as.integer(end_year) - 1L, as.integer(end_year) %% 100L)
}

# Derive hoopR end-year season integer from game_date (NBA season runs Oct-Jun;
# month >= 7 belongs to year + 1L, month <= 6 belongs to year).
# Falls back to fallback_season when game_date is missing/NA.
nba_season_end_year <- function(game_date, fallback_season = CURRENT_SEASON) {
  gd <- suppressWarnings(as.Date(game_date))
  yr <- suppressWarnings(as.integer(format(gd, "%Y")))
  mo <- suppressWarnings(as.integer(format(gd, "%m")))
  derived <- yr + ifelse(mo >= 7L, 1L, 0L)
  if (!is.null(fallback_season)) {
    fb <- suppressWarnings(as.integer(fallback_season))
    if (length(fb) == 1L) fb <- rep(fb, length(derived))
    derived <- ifelse(is.na(derived), fb, derived)
  }
  as.integer(derived)
}

# Current-season cache inputs (front-office#191). Missing file => stop(), never a
# fallback to another season.
current_season_cache <- function(kind = c("pbp", "player_box")) {
  kind <- match.arg(kind)
  path <- file.path(CACHE_DIR, sprintf("nba_%s_%d.rds", kind, CURRENT_SEASON))
  if (!file.exists(path)) {
    stop(sprintf("Missing current-season (%s) input: %s", season_label(), path), call. = FALSE)
  }
  path
}

# Latest game_date actually present in a PBP frame, as "YYYY-MM-DD".
pbp_through_date <- function(pbp) {
  d <- suppressWarnings(max(as.Date(pbp$game_date), na.rm = TRUE))
  if (!is.finite(as.numeric(d))) stop("PBP input has no valid game_date; cannot derive throughDate.", call. = FALSE)
  format(d, "%Y-%m-%d")
}

# throughDate for the pbp + player-box builders: the earlier of the two max dates, so the
# stated window is never wider than the data behind it (front-office#191).
data_through_date <- function(pbp, box) {
  p <- pbp_through_date(pbp)
  b <- pbp_through_date(box)
  if (b < p) {
    message(sprintf(">>> [WARN] player box ends %s, behind play-by-play (%s); throughDate = %s.", b, p, b))
  }
  min(p, b)
}

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
CACHE_MATCHUPS_PLAYER_BOX <- function(season) file.path(CACHE_DIR, sprintf("nba_player_box_%d.rds", as.integer(season)))
CACHE_XGBOOST_SHAP_MODEL <- file.path(CACHE_DIR, "xgboost_shap_model.rds")
CACHE_XGBOOST_GAME_SHAP <- function(season = MATCHUPS_HOOPR_SEASON) file.path(CACHE_DIR, sprintf("xgboost_game_shap_%d.rds", as.integer(season)))

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
# (projections_diagnostics.json is written on every run by accuracy_governance.R,
# so it is registered in WEB_DATA_FILES under #194.)
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
#   * momentum_methodology.json -- a frozen research artifact behind the
#     /momentum/methodology page: the momentum measures study's results file
#     plus provenance, copied (never recomputed) by
#     tools/publish_momentum_methodology.R. That script is NOT a
#     run_full_pipeline.R stage; it runs only when the study is re-run, so a
#     run-start mtime assertion over it would be red on a healthy pipeline.
#     data_manifest.json marks it static (tools/write_data_manifest.R).
#   * leader_methodology.json -- a frozen research artifact behind the
#     /players/leaders/methodology page: the leader reliability study's
#     results combined with the owner minimums in config.R, built by
#     tools/build_leader_methodology.R. Not a run_full_pipeline.R stage;
#     data_manifest.json marks it static.
WEB_PUBLIC_DIR <- file.path(PROJECT_DIR, "web", "public")

WEB_JSON_PROJECTIONS_SEASON_TEAMS    <- file.path(WEB_DATA_DIR, "projections_season_teams.json")
WEB_JSON_PROJECTIONS_SEASON_PLAYERS  <- file.path(WEB_DATA_DIR, "projections_season_players.json")
WEB_JSON_PROJECTIONS_MODELS_METADATA <- file.path(WEB_DATA_DIR, "projections_models_metadata.json")
WEB_JSON_PROJECTIONS_DIAGNOSTICS     <- file.path(WEB_DATA_DIR, "projections_diagnostics.json")
WEB_JSON_OFFSEASON_TEAMS             <- file.path(WEB_DATA_DIR, "offseason_teams.json")
WEB_JSON_OFFSEASON_DRAFT             <- file.path(WEB_DATA_DIR, "offseason_draft.json")
WEB_JSON_COACHING_METRICS            <- file.path(WEB_DATA_DIR, "coaching_metrics.json")
WEB_JSON_CBA_CAP_SHEET               <- file.path(WEB_DATA_DIR, "cba_cap_sheet.json")
WEB_JSON_PLAYER_DNA_PROFILES         <- file.path(WEB_DATA_DIR, "player_dna_profiles.json")
WEB_JSON_DEFENSIVE_METRICS           <- file.path(WEB_DATA_DIR, "defensive_metrics.json")
WEB_JSON_CLUTCH_LEVERAGE_METRICS     <- file.path(WEB_DATA_DIR, "clutch_leverage_metrics.json")
WEB_JSON_MATCHUPS_SLATES             <- file.path(WEB_DATA_DIR, "matchups_slates.json")
WEB_GAMES_DIR                        <- file.path(WEB_DATA_DIR, "games")
WEB_JSON_PLAYOFF_SERIES_MATCHUPS     <- file.path(WEB_DATA_DIR, "playoff_series_matchups.json")
WEB_JSON_LANDING_DIGEST              <- file.path(WEB_DATA_DIR, "landing_digest.json")
WEB_JSON_MOMENTUM_BOARD              <- file.path(WEB_DATA_DIR, "momentum_board.json")
# League leaders panel on /players (NBA_analytics#254), written by build_player_leaders.R
# and patched with new box scores by tools/refresh_live_results.R.
WEB_JSON_PLAYER_LEADERS              <- file.path(WEB_DATA_DIR, "player_leaders.json")
# Weekly momentum rank snapshots (NBA_analytics#237), tracked in git like
# data/history/ratings_history.csv; written by build_momentum_dataset.R.
MOMENTUM_RANK_HISTORY <- file.path(PROJECT_DIR, "data", "history", "momentum_rank_history.csv")
# Forward log of the Momentum Board (append-only, tracked in git, never gitignored);
# written by tools/log_momentum_forward.R, scored by tools/score_forward_log.R.
MOMENTUM_FORWARD_LOG <- file.path(PROJECT_DIR, "data", "history", "momentum_forward_log.csv")
# Non-members (see above), named so no caller re-types them.
WEB_JSON_OFFSEASON_TRANSACTIONS      <- file.path(WEB_DATA_DIR, "offseason_transactions.json")
WEB_JSON_SHOTS_INDEX                 <- file.path(WEB_DATA_DIR, "shots_index.json")
WEB_JSON_SHOTS_METADATA              <- file.path(WEB_DATA_DIR, "shots_metadata.json")
WEB_JSON_MOMENTUM_METHODOLOGY        <- file.path(WEB_DATA_DIR, "momentum_methodology.json")
WEB_JSON_LEADER_METHODOLOGY          <- file.path(WEB_DATA_DIR, "leader_methodology.json")

WEB_DATA_FILES <- c(
  WEB_JSON_PROJECTIONS_SEASON_TEAMS,
  WEB_JSON_PROJECTIONS_SEASON_PLAYERS,
  WEB_JSON_PROJECTIONS_MODELS_METADATA,
  WEB_JSON_PROJECTIONS_DIAGNOSTICS,
  WEB_JSON_OFFSEASON_TEAMS,
  WEB_JSON_OFFSEASON_DRAFT,
  WEB_JSON_COACHING_METRICS,
  WEB_JSON_CBA_CAP_SHEET,
  WEB_JSON_PLAYER_DNA_PROFILES,
  WEB_JSON_DEFENSIVE_METRICS,
  WEB_JSON_CLUTCH_LEVERAGE_METRICS,
  WEB_JSON_MATCHUPS_SLATES,
  WEB_JSON_PLAYOFF_SERIES_MATCHUPS,
  WEB_JSON_LANDING_DIGEST,
  WEB_JSON_MOMENTUM_BOARD,
  WEB_JSON_PLAYER_LEADERS
)

# ---------------------------------------------------------------------------
# League leaders qualifying minimums (NBA_analytics#254)
# ---------------------------------------------------------------------------
# The owner set every number below after reviewing the reliability curves of the
# leader reliability study (NBA_analytics#253, draft PR #256); the study measured
# reliability only and did not choose them. Each is the FULL-SEASON (82-game) bar
# and scales linearly with the player's current team's games played:
#   required = minimum * team_games_played / LEADERS_FULL_SEASON_GAMES
# Do not edit a minimum without a new owner decision. The RAPM leaderboard rule in
# rapm_engine.R (RAPM_LEADERBOARD_MIN_POSS_PER_SIDE) is separate and unchanged.
LEADERS_STUDY_SOURCE_COMMIT <- "d340cfdf247cb4876228d7a5f917cac0cba60de9"
LEADERS_FULL_SEASON_GAMES   <- 82L
# Counting stats, by games played.
LEADERS_MIN_GAMES_PTS  <- 10L
LEADERS_MIN_GAMES_REB  <- 10L
LEADERS_MIN_GAMES_AST  <- 10L
LEADERS_MIN_GAMES_TOV  <- 20L
# Turnovers per game also need minutes, so low-minute players with 0 turnovers
# don't lead the card (owner decision, 2026-11-25): 1,000 minutes, scaled.
LEADERS_MIN_MINUTES_TOV_PER_GAME <- 1000L
LEADERS_MIN_GAMES_FG3M <- 20L
LEADERS_MIN_GAMES_OREB <- 20L
LEADERS_MIN_GAMES_BLK  <- 20L
LEADERS_MIN_GAMES_STL  <- 30L
# Shooting, by attempts of that shot type.
LEADERS_MIN_FTA_FT_PCT   <- 250L
LEADERS_MIN_FGA_FG_PCT   <- 250L
LEADERS_MIN_FG3A_FG3_PCT <- 150L
# Rates, by minutes.
LEADERS_MIN_MINUTES_USG_PCT <- 250L
LEADERS_MIN_MINUTES_AST_PCT <- 250L
LEADERS_MIN_MINUTES_ORB_PCT <- 400L
LEADERS_MIN_MINUTES_DRB_PCT <- 400L
LEADERS_MIN_MINUTES_TOV_PCT <- 1000L
LEADERS_MIN_MINUTES_EFG_PCT <- 1000L
LEADERS_MIN_MINUTES_TS_PCT  <- 1000L
# RAPM (offensive, defensive, total), by possessions on EACH side.
LEADERS_MIN_POSS_PER_SIDE_RAPM <- 2000L
# The RAPM cards use their own current-season fit, written here by
# build_player_leaders.R. The ensemble's cache/rapm_ratings.rds (fit by
# rapm_engine.R, RAPM_SEASON) is separate and unchanged.
LEADERS_RAPM_CACHE_FILE <- "rapm_ratings_leaders.rds"

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

# ---------------------------------------------------------------------------
# Data-file lifecycle (NBA_analytics#235, shared four-sport design)
# ---------------------------------------------------------------------------
# Every top-level web/public/data/*.json entry in data_manifest.json carries
# `lifecycle`, one of WEB_DATA_LIFECYCLES ("live", "season_final", "archived").
# In season, every published payload is "live"; freeze and off-season scoping
# arrive at season end via the shared freeze_season.R design.
WEB_DATA_LIFECYCLES <- c("live", "season_final", "archived")

# Lifecycle per file name: a named list mapping basename -> list(lifecycle = "live")
# for every file in season.
nba_data_lifecycle <- function(files) {
  files <- basename(files)
  out <- lapply(files, function(f) list(lifecycle = "live"))
  names(out) <- files
  out
}

# Content hash used for frozen_sha256: sha256 of the file's bytes with CRLF
# normalised to LF, so a checkout with a different core.autocrlf does not read
# as a changed file.
nba_lifecycle_sha256 <- function(path) {
  if (!file.exists(path)) return(NA_character_)
  sz <- file.info(path)$size
  b <- if (is.na(sz) || sz == 0) raw(0) else readBin(path, "raw", n = sz)
  cr <- which(b == as.raw(13L))
  if (length(cr)) {
    crlf <- cr[cr < length(b) & b[pmin(cr + 1L, length(b))] == as.raw(10L)]
    if (length(crlf)) b <- b[-crlf]
  }
  unname(as.character(tools::sha256sum(bytes = b)))
}