# ==============================================================================
# Participation / Personnel Feature Engineering (Known Issue #7 pickup)
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/tools/participation_features.R
#
# CLAUDE.md's Known Issue #7 (docs/HANDOFF.md): "load_participation() 2023+ is
# historical-only ... still unstarted, still correctly unused anywhere in the pipeline." This
# file is that pickup - the FIRST real use of nflreadr::load_participation() in this repo.
#
# WHY THIS IS A tools/ SCRIPT, NOT A run_full_pipeline.R STAGE (deliberate, not an oversight):
# nflreadr::load_participation() has a hard data-availability wall that makes it structurally
# unusable for LIVE current-season prediction, unlike every other data source this repo's
# pipeline stages consume:
#   - Starts at PARTICIPATION_MIN_SEASON = 2016 (config.R) - live-verified: seasons < 2016
#     error ("seasons >= 2016 is not TRUE").
#   - RE-VERIFIED LIVE 2026-09-17 (not just re-citing CLAUDE.md's prior claim):
#     load_participation(seasons = CURRENT_SEASON) returns a genuine HTTP 404 / 0 rows against
#     the current in-progress 2026 season - the underlying GitHub release asset
#     (pbp_participation_2026.rds) does not exist yet and won't until after this season's
#     postseason completes. Seasons 2016-2025 (all now-complete) DO return real data (confirmed:
#     2016 = 48,434 rows/20 cols, 2023 = 46,168 rows/26 cols - 2023+'s six extra columns are
#     FTN-added player name/number/position lists, not new team-level stats).
# A run_full_pipeline.R stage that ran this every day would therefore ALWAYS see 0 rows for
# CURRENT_SEASON and could never produce a live prediction feature from it - this is a
# backtest-only research tool by data-availability necessity, not a design choice this repo
# could "fix" by trying harder.
#
# FEATURES (per-team-per-game, offense and defense-allowed sides, rolling ROLLING_WINDOW_SIZE
# trailing average - same convention as epa_metrics_engine.R's .roll_mean_trailing(), reused
# verbatim from that file rather than a second copy):
#   off_personnel_11_rate         - rate of offensive snaps in "11 personnel" (1 RB, 1 TE,
#                                    3 WR) - the modern NFL's single most common grouping and a
#                                    real offensive-tendency signal.
#   off_defenders_in_box_faced    - mean defenders in the box the team's OFFENSE faced.
#   off_pressure_rate_allowed     - mean was_pressure on plays the team's OFFENSE ran.
#   def_pass_rushers_avg          - mean number_of_pass_rushers the team's DEFENSE sent.
#   def_pressure_rate_generated   - mean was_pressure on plays the team's DEFENSE faced.
#   def_defenders_in_box_deployed - mean defenders in the box the team's DEFENSE deployed.
# All six are NA-safe (per-game .safe_mean()-style handling) since was_pressure/
# number_of_pass_rushers/defenders_in_box are only charted on a subset of plays (confirmed
# live: was_pressure NA rate ~61% in a 2020 spot check - only charted on pass plays with a
# recorded rush count, not a parsing gap).
#
# JOIN STRATEGY: participation is play-level with NO posteam/defteam columns of its own (only
# `possession_team`) - joined to CACHE_PBP by (game_id, play_id) to inherit that file's already-
# verified posteam/defteam/season/week/game_date resolution, rather than re-deriving team
# attribution from `possession_team` + schedule lookups a second time.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/participation_features.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/nfl analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(nflreadr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/participation_features.R"
source("epa_metrics_engine.R")  # -> .roll_mean_trailing(), .safe_mean() (reused verbatim)

.PARTICIPATION_COLUMNS <- c(
  "nflverse_game_id", "play_id", "possession_team",
  "offense_formation", "offense_personnel", "defenders_in_box",
  "defense_personnel", "number_of_pass_rushers", "was_pressure"
)

# ------------------------------------------------------------------------------------------
# fetch_participation_history(): bootstrap-or-update, mirroring daily_ingest.R's
# .ingest_one() shape but scoped to PARTICIPATION_MIN_SEASON:(CURRENT_SEASON - 1) - NEVER
# CURRENT_SEASON (see header - it would always 404). force_refresh = TRUE re-pulls everything.
# ------------------------------------------------------------------------------------------
fetch_participation_history <- function(force_refresh = FALSE) {
  seasons <- PARTICIPATION_MIN_SEASON:(CURRENT_SEASON - 1L)

  if (!force_refresh && file.exists(CACHE_PARTICIPATION)) {
    cat(sprintf("Loading existing CACHE_PARTICIPATION cache.\n"))
    return(readRDS(CACHE_PARTICIPATION))
  }

  cat(sprintf("Pulling nflreadr::load_participation() for seasons %d-%d (never CURRENT_SEASON=%d - see header)...\n",
              min(seasons), max(seasons), CURRENT_SEASON))
  raw <- nflreadr::load_participation(seasons = seasons)
  trimmed <- raw |> select(any_of(.PARTICIPATION_COLUMNS)) |> rename(game_id = nflverse_game_id)
  saveRDS(trimmed, CACHE_PARTICIPATION)
  cat(sprintf("Bootstrapped CACHE_PARTICIPATION with %d rows (%d columns).\n", nrow(trimmed), ncol(trimmed)))
  trimmed
}

# ------------------------------------------------------------------------------------------
# build_participation_features(): joins participation to CACHE_PBP (game_id/play_id), computes
# the six per-team-per-game features above (offense side keyed by posteam, defense side by
# defteam), then rolling trailing averages - same shape as epa_metrics_engine.R's team_game
# table. Returns the full per-team-per-game table (not just the latest row).
# ------------------------------------------------------------------------------------------
build_participation_features <- function(participation, pbp) {
  pbp_keys <- pbp |> select(game_id, play_id, season, week, game_date, posteam, defteam) |>
    mutate(game_date = as.Date(game_date))

  joined <- participation |>
    inner_join(pbp_keys, by = c("game_id", "play_id")) |>
    filter(!is.na(posteam), !is.na(defteam))

  is_11_personnel <- joined$offense_personnel == "1 RB, 1 TE, 3 WR"
  is_11_personnel[is.na(is_11_personnel)] <- FALSE
  joined$.is_11_personnel <- is_11_personnel

  off_stats <- joined |>
    group_by(season, game_id, game_date, week, team = posteam) |>
    summarise(
      off_personnel_11_rate     = .safe_mean(as.numeric(.is_11_personnel)),
      off_defenders_in_box_faced = .safe_mean(defenders_in_box),
      off_pressure_rate_allowed  = .safe_mean(as.numeric(was_pressure)),
      .groups = "drop"
    )

  def_stats <- joined |>
    group_by(season, game_id, game_date, week, team = defteam) |>
    summarise(
      def_pass_rushers_avg          = .safe_mean(number_of_pass_rushers),
      def_pressure_rate_generated   = .safe_mean(as.numeric(was_pressure)),
      def_defenders_in_box_deployed = .safe_mean(defenders_in_box),
      .groups = "drop"
    )

  team_game <- full_join(off_stats, def_stats, by = c("season", "game_id", "game_date", "week", "team")) |>
    arrange(team, game_date, week)

  team_game |>
    group_by(team) |>
    mutate(
      off_personnel_11_rate_roll         = .roll_mean_trailing(off_personnel_11_rate),
      off_defenders_in_box_faced_roll    = .roll_mean_trailing(off_defenders_in_box_faced),
      off_pressure_rate_allowed_roll     = .roll_mean_trailing(off_pressure_rate_allowed),
      def_pass_rushers_avg_roll          = .roll_mean_trailing(def_pass_rushers_avg),
      def_pressure_rate_generated_roll   = .roll_mean_trailing(def_pressure_rate_generated),
      def_defenders_in_box_deployed_roll = .roll_mean_trailing(def_defenders_in_box_deployed)
    ) |>
    ungroup()
}

# ------------------------------------------------------------------------------------------
# run_participation_features(): the sole callable - NOT invoked by run_full_pipeline.R (see
# header). A future agent wanting these features in a backtest should call this once (or after
# a new season's participation data is finally released) rather than re-deriving inline.
# ------------------------------------------------------------------------------------------
run_participation_features <- function(force_refresh = FALSE) {
  if (!file.exists(CACHE_PBP)) stop("CACHE_PBP missing - run daily_ingest.R's run_daily_ingest() first.")
  pbp <- readRDS(CACHE_PBP)

  participation <- fetch_participation_history(force_refresh = force_refresh)
  features <- build_participation_features(participation, pbp)

  saveRDS(features, CACHE_PARTICIPATION_FEATURES)
  cat(sprintf("Wrote %d team-game participation-feature rows (seasons %d-%d) to CACHE_PARTICIPATION_FEATURES.\n",
              nrow(features), min(features$season), max(features$season)))
  invisible(features)
}

if (sys.nframe() == 0) {
  # This script IS occasionally run directly as a one-off derivation (per its tools/ home,
  # unlike a pipeline stage file) - a direct-run guard is appropriate here, unlike the
  # sys.nframe()==0 anti-pattern CLAUDE.md warns pipeline STAGE scripts away from.
  run_participation_features()
}
