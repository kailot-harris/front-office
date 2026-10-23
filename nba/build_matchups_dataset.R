# ==============================================================================
# build_matchups_dataset.R
# Builds the per-game Matchups dataset that backs web/app/matchups.
#
# ------------------------------------------------------------------------------
# SEASON SCOPE - the dataset covers EXACTLY ONE NBA season, and which one is
# determined here, not by config.R's CURRENT_SEASON.
# ------------------------------------------------------------------------------
# `MATCHUPS_HOOPR_SEASON` below is the single switch. It is expressed in hoopR's
# season numbering, which is the season's END year: hoopR season 2027 is the
# 2026-27 season (verified live - hoopR::load_nba_schedule(seasons = 2027)
# returns games dated 2026-10-20 .. 2027-04-11, and seasons = 2026 returns
# 2025-10 .. 2026-06, i.e. the 2025-26 season).
#
# This builder deliberately does NOT read config.R's `CURRENT_SEASON` (2026) and
# does NOT filter on the accuracy log's `season` column, for two reasons:
#   1. CURRENT_SEASON is shared by every other pipeline stage and uses a
#      different convention; changing or reusing it here would be wrong in one
#      direction or the other. This stage therefore takes its target season
#      explicitly (overridable with the NBA_MATCHUPS_SEASON env var).
#   2. cache/prediction_accuracy_log.rds labels BOTH the 2025-26 and the 2026-27
#      games `season = 2026`, so that column cannot separate the two seasons.
#      Scoping is done by hoopR season (for the schedule spine) and by game DATE
#      (for everything joined onto it) - never by the log's `season`.
# Before this scoping existed the page glued the finished 2025-26 season's
# graded games to 2026-27's upcoming ones, leaving a four-month offseason gap in
# the middle of the week ribbon. Everything emitted below is inside one season.
#
# Sources:
#   hoopR::load_nba_schedule(seasons = MATCHUPS_HOOPR_SEASON)  [SPINE]
#     - full-season schedule with real ESPN game_ids. This, not the accuracy
#       log, defines which games and which weeks exist, so the ribbon spans the
#       whole season instead of stopping wherever the log happens to end.
#   CACHE_PREDICTION_LOG (cache/prediction_accuracy_log.rds)   [PROJECTIONS + GRADES]
#     - the model's PRE-GAME prediction per game, plus the grade on RESOLVED
#       rows. Joined onto the spine by date + team name (see JOIN KEY below).
#   hoopR::load_nba_team_box(seasons = MATCHUPS_HOOPR_SEASON)  [REAL SCORES]
#     - two rows per completed game; the ONLY source of final scores. Joined on
#       the ESPN game_id the spine already carries.
#
# Exports CACHE_MATCHUPS (.rds) and CACHE_MATCHUPS_JSON (web/public/data).
#
# ------------------------------------------------------------------------------
# JOIN KEY - game date + team short display name.
# ------------------------------------------------------------------------------
# The accuracy log's rows for this season are keyed by the repo's own hash
# game_ids (e.g. 26b036ff107f3c658258eaf4a6f26228) while the hoopR schedule is
# keyed by ESPN numeric ids, so the two cannot be joined on id. They are joined
# on game_date plus the team SHORT DISPLAY NAME on each side ("Pistons",
# "Celtics", "Thunder"), which is the convention
# prediction_accuracy_logger.R:160 and its .resolve_team_name helper
# (prediction_accuracy_logger.R:53) already write into the log, and which the
# schedule carries as home_short_display_name / away_short_display_name. The
# schedule's local `game_date` is used, not the UTC `date` field, because a late
# tip-off rolls over midnight UTC and would mis-date the game by a day. The
# realised match rate is measured and printed on every run, and recorded in the
# dataset - it is never assumed.
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 1 - SLATE GRANULARITY: week-of-season buckets.
# ------------------------------------------------------------------------------
# Issue #16 asks for a "week selector ribbon spanning every week in the season".
# The NBA plays daily, so a per-day slate would be ~170 selector entries for one
# season and a ~8-game sample per "X / Y correct (Z%)" accuracy stat. We therefore
# bucket games into fixed 7-day windows measured from the season's first game date
# (`slate = floor((game_date - season_start) / 7) + 1`), which keeps the ribbon
# navigable (~25 entries), matches the issue's week language and the ported NFL
# ribbon pattern, and gives each slate a large enough graded sample for a stable
# accuracy figure. This is the ONLY granularity used anywhere in this file and in
# the web components; no per-day slate exists. Because the spine is a single
# season's full schedule and the NBA plays in every week of it, the resulting
# week indices are contiguous from 1 with no gap.
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 2 - WHERE PROJECTIONS COME FROM, AND WHY THERE ARE TWO BASES.
# ------------------------------------------------------------------------------
# TWO DIFFERENT MODELS PRODUCE THE NUMBERS ON THIS PAGE. They are kept apart,
# never averaged, never compared against each other, and every game says which
# one it used via `projection_basis`:
#
#   (A) LOGGED MODEL PREDICTION - the richer one. The daily slate engine's
#       `Model_Win_Prob`, written per game into CACHE_PREDICTION_LOG by
#       prediction_accuracy_logger.R:253-268 before tip-off. This is the model
#       the accuracy log grades, so it is the ONLY basis that is ever graded,
#       and it always wins: a logged projection is never overwritten or adjusted
#       here. The logger only runs a few days ahead, so it covers a few dozen
#       games out of a full season.
#         basis "logged_model_margin"          - margin came straight from the log.
#         basis "margin_from_logged_win_prob"  - the log left `predicted_margin`
#           NA, so the margin is the inversion of that same logged probability
#           through this repo's documented margin -> win-probability map
#           (margin = qnorm(p) * MARGIN_SIGMA). Same model, derived field.
#
#   (B) TEAM RATING DIFFERENTIAL - the simpler one, used only to fill games the
#       log has not predicted. It is NOT a new model: it is verbatim the
#       computation prediction_accuracy_logger.R:142-172 already performs when
#       it backfills games, reading the same ratings file -
#       cache/projected_30_team_standings.rds, column `Net_Rating`, keyed by its
#       `Team` short names - and the same arithmetic:
#         pred_margin = (home_rating - away_rating) + HCA_POINTS
#         pred_prob   = pnorm(pred_margin / MARGIN_SIGMA)
#       No rest, travel, injury or roster adjustment is applied, because the
#       logger applies none. basis "team_rating_differential".
#
# These two bases are NOT interchangeable and must never be presented as one
# number: (A) is a full model output, (B) is a season-long rating difference
# plus a flat home-court constant. NBA issue #14 is open against exactly this
# class of defect - a card implying a relationship between numbers computed from
# unrelated inputs - so the UI labels every card with its basis and never ranks
# or aggregates across the two (see web/components/MatchupCard.tsx and
# web/components/MatchupsClient.tsx).
#
# A game whose teams are absent from the ratings table (only ESPN's TBD NBA Cup
# placeholders, which are dropped earlier anyway) still emits NULL for every
# projection field and `projection_basis: null` - never a placeholder number.
#
# ------------------------------------------------------------------------------
# GRADING, AND THE "NOTHING GRADED YET" STATE.
# ------------------------------------------------------------------------------
# A game counts as graded (`is_completed = TRUE`) only when the accuracy log has
# actually RESOLVED it (status RESOLVED with a non-NA `correct`) AND a real team
# box score for it exists. Grades are copied verbatim from the log's `correct`
# column, never recomputed, and a winner is never inferred from any other
# source: a game that has been played in reality but that the logger has not
# resolved stays pending, with null score and result fields.
# Early in a season that legitimately means ZERO graded games. That is a correct
# state, not an error, so the dataset carries it explicitly
# (`graded_games_available = FALSE`, `grading_state = "no_games_graded_yet"`)
# and the UI renders a "Not yet graded" state from it rather than 0/0, NaN% or a
# misleading 0% (see web/components/MatchupsClient.tsx). As the logger resolves
# games, the same code starts reporting real graded weeks with no change here.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(hoopR)
})

# ------------------------------------------------------------------------------
# 0. Configuration + path resolution
# ------------------------------------------------------------------------------
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

# The one season switch (hoopR end-year numbering; see SEASON SCOPE above).
MATCHUPS_HOOPR_SEASON <- {
  env <- Sys.getenv("NBA_MATCHUPS_SEASON", unset = "")
  if (nzchar(env)) as.integer(env) else 2027L
}
# Human-facing label: hoopR season 2027 -> "2026-2027".
MATCHUPS_SEASON_LABEL <- sprintf("%d-%d", MATCHUPS_HOOPR_SEASON - 1L,
                                 MATCHUPS_HOOPR_SEASON)

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
if (!dir.exists(dirname(CACHE_MATCHUPS_JSON))) {
  dir.create(dirname(CACHE_MATCHUPS_JSON), recursive = TRUE)
}

cat(sprintf(">>> [PHASE 1] Building NBA Matchups dataset for the %s season (hoopR season %d)...\n",
            MATCHUPS_SEASON_LABEL, MATCHUPS_HOOPR_SEASON))

resolve_input <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf(
      "%s not found at %s - run the pipeline stage that produces it first.",
      label, path
    ))
  }
  path
}

# Read-only hoopR pull, cached per season so a later run works offline. Falls
# back to the cached pull on a network failure and hard-stops if neither exists:
# there is no fallback to a different season, because a different season's games
# must never enter this dataset.
fetch_or_cache <- function(label, cache_path, pull) {
  got <- tryCatch(as.data.frame(pull()), error = function(e) {
    cat(sprintf(">>> [WARN] live %s pull failed: %s\n", label, conditionMessage(e)))
    NULL
  })
  if (!is.null(got) && nrow(got) > 0) {
    saveRDS(got, cache_path)
    cat(sprintf(">>> Pulled %d rows of %s live from hoopR (cached to %s)\n",
                nrow(got), label, basename(cache_path)))
    return(got)
  }
  if (file.exists(cache_path)) {
    got <- as.data.frame(readRDS(cache_path))
    cat(sprintf(">>> Using cached %s (%d rows) from %s\n",
                label, nrow(got), basename(cache_path)))
    return(got)
  }
  if (!is.null(got)) return(got)  # reachable but genuinely empty (e.g. no box scores yet)
  stop(sprintf(
    "Could not obtain %s for season %d: the live hoopR pull failed and no cache exists at %s.",
    label, MATCHUPS_HOOPR_SEASON, cache_path
  ))
}

# ------------------------------------------------------------------------------
# 1. SPINE: the target season's full schedule
# ------------------------------------------------------------------------------
schedule <- fetch_or_cache(
  sprintf("schedule (season %d)", MATCHUPS_HOOPR_SEASON),
  CACHE_MATCHUPS_SCHEDULE(MATCHUPS_HOOPR_SEASON),
  function() hoopR::load_nba_schedule(seasons = MATCHUPS_HOOPR_SEASON)
)
if (nrow(schedule) == 0) {
  stop(sprintf("hoopR returned no schedule rows for season %d - no season spine.",
               MATCHUPS_HOOPR_SEASON))
}

# `game_date` is the local calendar date; `date` is UTC and mis-dates late games.
schedule$game_date <- as.Date(as.character(schedule$game_date))

# Guard the whole point of this stage: every spine row must belong to the target
# hoopR season. Anything else is dropped loudly rather than silently emitted.
if ("season" %in% names(schedule)) {
  off_season <- sum(as.integer(schedule$season) != MATCHUPS_HOOPR_SEASON, na.rm = TRUE)
  if (off_season > 0) {
    cat(sprintf(">>> [WARN] dropping %d schedule rows not in hoopR season %d\n",
                off_season, MATCHUPS_HOOPR_SEASON))
    schedule <- schedule[as.integer(schedule$season) == MATCHUPS_HOOPR_SEASON, ]
  }
}

# ESPN ships NBA Cup knockout placeholders as TBD vs TBD before the groups
# finish. They have no teams to show or project, so they are not games yet.
placeholder <- schedule$home_short_display_name == "TBD" |
  schedule$away_short_display_name == "TBD"
if (any(placeholder, na.rm = TRUE)) {
  cat(sprintf(">>> Dropping %d TBD placeholder fixtures (unseeded NBA Cup knockout slots)\n",
              sum(placeholder, na.rm = TRUE)))
  schedule <- schedule[!placeholder, ]
}

schedule <- schedule %>%
  transmute(
    espn_game_id = as.character(.data$game_id),
    game_date = .data$game_date,
    home_name = as.character(.data$home_short_display_name),
    away_name = as.character(.data$away_short_display_name),
    home_abbr_raw = as.character(.data$home_abbreviation),
    away_abbr_raw = as.character(.data$away_abbreviation)
  ) %>%
  arrange(.data$game_date, .data$espn_game_id)

season_start <- min(schedule$game_date)
season_end <- max(schedule$game_date)
cat(sprintf(">>> Season spine: %d games, %s .. %s\n",
            nrow(schedule), format(season_start), format(season_end)))

# ESPN abbreviations differ from the web app's canonical set (lib/teams.ts).
ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                      NO = "NOP", WSH = "WAS")
canonical_abbr <- function(x) ifelse(x %in% names(ESPN_ABBR_FIXUPS),
                                     ESPN_ABBR_FIXUPS[x], x)
schedule$home_team <- unname(canonical_abbr(schedule$home_abbr_raw))
schedule$away_team <- unname(canonical_abbr(schedule$away_abbr_raw))

# ------------------------------------------------------------------------------
# 2. PROJECTIONS + GRADES: join the accuracy log on date + team name
# ------------------------------------------------------------------------------
pred_log <- as.data.frame(readRDS(resolve_input(CACHE_PREDICTION_LOG, "prediction accuracy log")))
pred_log$game_date <- as.Date(pred_log$game_date)

# DATE scoping, not `season` scoping - the log labels both seasons 2026.
log_season <- pred_log %>%
  filter(.data$game_date >= season_start, .data$game_date <= season_end) %>%
  mutate(join_key = paste(format(.data$game_date), .data$home_team, .data$away_team)) %>%
  arrange(.data$game_date) %>%
  distinct(.data$join_key, .keep_all = TRUE)

cat(sprintf(">>> %d logged predictions fall inside the %s season window\n",
            nrow(log_season), MATCHUPS_SEASON_LABEL))

schedule$join_key <- paste(format(schedule$game_date), schedule$home_name, schedule$away_name)

games <- schedule %>%
  left_join(
    log_season %>% transmute(
      join_key = .data$join_key,
      log_game_id = as.character(.data$game_id),
      log_status = as.character(.data$status),
      predicted_home_win_prob = suppressWarnings(as.numeric(.data$predicted_home_win_prob)),
      predicted_margin = suppressWarnings(as.numeric(.data$predicted_margin)),
      log_correct = .data$correct
    ),
    by = "join_key"
  )

n_with_pred <- sum(!is.na(games$log_game_id))
n_without_pred <- nrow(games) - n_with_pred
n_log_matched <- sum(log_season$join_key %in% schedule$join_key)
n_log_unmatched <- nrow(log_season) - n_log_matched
log_match_pct <- if (nrow(log_season) > 0) round(100 * n_log_matched / nrow(log_season), 1) else 0
sched_match_pct <- round(100 * n_with_pred / nrow(games), 1)

cat(sprintf(paste0(
  ">>> JOIN RATE (date + team short name):\n",
  ">>>   logged predictions matched to a scheduled game: %d of %d (%.1f%%); %d unmatched\n",
  ">>>   scheduled games that have a logged prediction:  %d of %d (%.1f%%); %d without\n"),
  n_log_matched, nrow(log_season), log_match_pct, n_log_unmatched,
  n_with_pred, nrow(games), sched_match_pct, n_without_pred))
if (n_log_unmatched > 0) {
  cat(">>>   unmatched logged predictions (log date/teams absent from the ESPN schedule):\n")
  for (k in setdiff(log_season$join_key, schedule$join_key)) cat(sprintf(">>>     %s\n", k))
}

# JOIN RATE CONTRACT. A logged prediction for a game near today is an ACTIVE
# SLATE row: it was written off live bookmaker odds, so if it fails to join the
# ESPN spine the page silently shows the weaker ensemble baseline for a game the
# model has actually priced. That is a team-naming or home/away-orientation bug
# in market_odds_engine.R / prediction_accuracy_logger.R, not a data gap, so it
# is a hard error here. Older unmatched rows only warn above: the log also
# carries games the spine legitimately does not (preseason, moved fixtures).
PRED_LOG_ACTIVE_WINDOW_DAYS <- 2L
active_unmatched <- log_season[
  !(log_season$join_key %in% schedule$join_key) &
    abs(as.numeric(log_season$game_date - Sys.Date())) <= PRED_LOG_ACTIVE_WINDOW_DAYS, ]
if (nrow(active_unmatched) > 0) {
  stop(sprintf(paste0(
    "%d active-slate logged prediction(s) within %d day(s) of today failed to ",
    "join the ESPN schedule spine on date + short team name: %s. Fix the team ",
    "resolver / home-away orientation in the logger before publishing."),
    nrow(active_unmatched), PRED_LOG_ACTIVE_WINDOW_DAYS,
    paste(active_unmatched$join_key, collapse = "; ")))
}

# ------------------------------------------------------------------------------
# 2b. RATINGS FALLBACK PROJECTION for games the log has not predicted
#     (see DESIGN DECISION 2, basis (B)). This is the SAME computation as
#     prediction_accuracy_logger.R:142-172, not a new model.
# ------------------------------------------------------------------------------

# Home-court advantage in points.
# SOURCE OF TRUTH: prediction_accuracy_logger.R:169 (`hca <- 2.40`), where it is
# a bare literal inside a function this stage must not modify (that logger is
# out of scope). The value is therefore DELIBERATELY DUPLICATED here as a named
# constant - so that the duplication is visible and attributed rather than
# pasted as an unexplained magic number - instead of being hoisted into a
# competing config.R constant. If the logger's literal ever changes, change this
# line with it.
HCA_POINTS <- 2.40

# RATINGS SOURCE - the primary 4-model ensemble blend, and nothing else.
# season_simulator.R writes cache/ensemble_team_ratings.rds as a pipeline stage,
# carrying each team's blended net rating
#   0.35 * BPM + 0.25 * RAPM + 0.20 * ShotQuality/Fatigue + 0.20 * Embeddings.
# The older single-model fallback (cache/projected_30_team_standings.rds,
# `Net_Rating`, emitted as projection_basis "team_rating_differential") is gone:
# it produced a second, weaker and non-comparable number for the same games, so
# this stage now refuses to run rather than quietly emitting it.
ENSEMBLE_PATH <- file.path(CACHE_DIR, "ensemble_team_ratings.rds")
if (!file.exists(ENSEMBLE_PATH)) {
  stop(sprintf(paste0(
    "Primary ensemble ratings not found at %s - run season_simulator.R first ",
    "(it writes cache/ensemble_team_ratings.rds). This stage no longer falls ",
    "back to the single-model projected_30_team_standings.rds ratings."),
    ENSEMBLE_PATH))
}
ens_df <- as.data.frame(readRDS(ENSEMBLE_PATH))
if (!all(c("team", "team_name", "ensemble_net_rating", "rating_disagreement_sd")
         %in% names(ens_df))) {
  stop(sprintf(paste0(
    "%s does not carry the expected `team` / `team_name` / `ensemble_net_rating` / ",
    "`rating_disagreement_sd` columns. If the artifact predates the ",
    "rating-scale disagreement SD, re-run season_simulator.R to rewrite it ",
    "rather than projecting games at a fixed sigma."),
    ENSEMBLE_PATH))
}
team_ratings <- setNames(suppressWarnings(as.numeric(ens_df$ensemble_net_rating)),
                         as.character(ens_df$team_name))
abbr_ratings <- setNames(suppressWarnings(as.numeric(ens_df$ensemble_net_rating)),
                         as.character(ens_df$team))
cat(sprintf(">>> Primary ensemble ratings: %d rated teams from %s (column ensemble_net_rating)\n",
            length(team_ratings), basename(ENSEMBLE_PATH)))

# Key ratings by both short display name and 3-letter abbreviation
games$home_rating <- unname(ifelse(!is.na(team_ratings[games$home_name]),
                                   team_ratings[games$home_name],
                                   abbr_ratings[games$home_team]))
games$away_rating <- unname(ifelse(!is.na(team_ratings[games$away_name]),
                                   team_ratings[games$away_name],
                                   abbr_ratings[games$away_team]))

# PER-TEAM RATING UNCERTAINTY, keyed the same two ways. A team missing from the
# artifact has no rating either and is caught by the coverage contract below; a
# present team with a non-finite SD contributes nothing extra to the game's
# sigma, which collapses that game to the plain MARGIN_SIGMA rather than
# dropping it.
team_rating_sd <- setNames(suppressWarnings(as.numeric(ens_df$rating_disagreement_sd)),
                           as.character(ens_df$team_name))
abbr_rating_sd <- setNames(suppressWarnings(as.numeric(ens_df$rating_disagreement_sd)),
                           as.character(ens_df$team))
.sd_for <- function(name, abbr) {
  v <- ifelse(!is.na(team_rating_sd[name]), team_rating_sd[name], abbr_rating_sd[abbr])
  v <- unname(as.numeric(v))
  ifelse(is.finite(v) & v > 0, v, 0)
}
games$home_rating_sd <- .sd_for(games$home_name, games$home_team)
games$away_rating_sd <- .sd_for(games$away_name, games$away_team)
.sigma_preview <- sqrt(MARGIN_SIGMA^2 + games$home_rating_sd^2 + games$away_rating_sd^2)
cat(sprintf(paste0(
  ">>> Rating disagreement SD: %d of %d teams non-zero (mean %.2f pts); ",
  "per-game sigma %.2f .. %.2f vs flat %.1f\n"),
  sum(abbr_rating_sd > 0, na.rm = TRUE), nrow(ens_df),
  mean(abbr_rating_sd, na.rm = TRUE),
  min(.sigma_preview), max(.sigma_preview), MARGIN_SIGMA))
n_rated <- sum(!is.na(games$home_rating) & !is.na(games$away_rating))
rated_pct <- round(100 * n_rated / nrow(games), 1)
cat(sprintf(">>> Both teams rated for %d of %d scheduled games (%.1f%%)\n",
            n_rated, nrow(games), rated_pct))
if (rated_pct < 90) {
  unmatched <- sort(unique(c(games$home_name[is.na(games$home_rating)],
                             games$away_name[is.na(games$away_rating)])))
  stop(sprintf(paste0(
    "Only %.1f%% of scheduled games have both teams present in %s - the ratings ",
    "table's `Team` naming does not match the schedule's short display names. ",
    "Unmatched: %s"),
    rated_pct, basename(ENSEMBLE_PATH), paste(unmatched, collapse = ", ")))
}

# ------------------------------------------------------------------------------
# 2c. SCHEDULE CONTEXT: rest, back-to-backs, travel and altitude, per side.
# ------------------------------------------------------------------------------
# The ensemble net ratings are season-long team strength and carry no schedule
# context, so each game's margin is adjusted by the DIFFERENCE in the two
# sides' fatigue drag. Both the drag model and the arena coordinates come from
# fatigue_travel_engine.R (haversine distance, eastward-biased circadian tax,
# DEN/UTA altitude tax, back-to-back tax) - they are not re-derived here, so the
# altitude handling the plan calls for is that engine's, applied to every game
# instead of to a 4-game sample slate. cache/travel_fatigue_metrics.rds is NOT
# read: it only ever holds the active slate, while this spine needs all 1,200.
#
# Rest and the previous venue are read off the spine itself: for each team, the
# game that precedes this one in date order, and the arena it was played in.
FATIGUE_ENGINE_LIBRARY_ONLY <- TRUE
source("fatigue_travel_engine.R")

# One row per team per game, in date order, carrying the arena played in.
appearances <- rbind(
  data.frame(team = games$home_team, game_date = games$game_date,
             venue = games$home_team, stringsAsFactors = FALSE),
  data.frame(team = games$away_team, game_date = games$game_date,
             venue = games$home_team, stringsAsFactors = FALSE)
)
appearances <- appearances[order(appearances$team, appearances$game_date), ]

# Previous appearance per team: venue played in, and days between the two dates.
prev_venue <- character(nrow(appearances))
prev_gap   <- rep(NA_real_, nrow(appearances))
for (j in seq_len(nrow(appearances))) {
  if (j > 1 && identical(appearances$team[j], appearances$team[j - 1])) {
    prev_venue[j] <- appearances$venue[j - 1]
    prev_gap[j]   <- as.numeric(difftime(appearances$game_date[j],
                                         appearances$game_date[j - 1], units = "days"))
  } else {
    # Season opener: treat the team as rested and already at the venue's origin.
    prev_venue[j] <- appearances$venue[j]
    prev_gap[j]   <- NA_real_
  }
}
ctx_key <- paste(appearances$team, format(appearances$game_date, "%Y-%m-%d"), sep = "|")
ctx_prev_venue <- setNames(prev_venue, ctx_key)
ctx_prev_gap   <- setNames(prev_gap, ctx_key)

# fatigue_travel_engine.R's convention: days_rest 0 == back-to-back.
.side_drag <- function(team, game_date, dest) {
  k <- paste(team, format(game_date, "%Y-%m-%d"), sep = "|")
  gap <- ctx_prev_gap[[k]]
  origin <- ctx_prev_venue[[k]]
  if (is.null(gap) || is.na(gap)) return(0)              # season opener
  days_rest <- max(0, as.integer(round(gap)) - 1L)
  fm <- calculate_travel_fatigue(dest, origin,
                                 days_rest = days_rest,
                                 is_back_to_back = days_rest == 0L)
  as.numeric(fm$fatigue_drag_pts)
}

games$home_fatigue_drag <- vapply(seq_len(nrow(games)), function(i) {
  .side_drag(games$home_team[i], games$game_date[i], games$home_team[i])
}, numeric(1))
games$away_fatigue_drag <- vapply(seq_len(nrow(games)), function(i) {
  .side_drag(games$away_team[i], games$game_date[i], games$home_team[i])
}, numeric(1))
# Positive helps the home side: the visitor's drag minus the host's own.
games$schedule_adjustment <- round(games$away_fatigue_drag - games$home_fatigue_drag, 2)

cat(sprintf(paste0(
  ">>> Schedule context: %d of %d games carry a non-zero fatigue differential ",
  "(mean %+.2f, range %+.2f .. %+.2f points to the home side)\n"),
  sum(games$schedule_adjustment != 0), nrow(games),
  mean(games$schedule_adjustment), min(games$schedule_adjustment),
  max(games$schedule_adjustment)))

ratings_source_desc <- sprintf(paste0(
  "Primary 4-Model Ensemble Blend (35%% BPM, 25%% RAPM, 20%% Shot Quality/Fatigue, ",
  "20%% Embeddings) + %.2f HCA + fatigue_travel_engine.R schedule drag ",
  "(rest, back-to-backs, haversine travel, circadian shift, DEN/UTA altitude), ",
  "pnorm(margin / sqrt(%.1f^2 + home rating-disagreement SD^2 + away SD^2))"),
  HCA_POINTS, MARGIN_SIGMA)

# ------------------------------------------------------------------------------
# 3. REAL SCORES: the target season's team box scores, joined on ESPN game_id
# ------------------------------------------------------------------------------
team_box <- fetch_or_cache(
  sprintf("team box scores (season %d)", MATCHUPS_HOOPR_SEASON),
  CACHE_MATCHUPS_TEAM_BOX(MATCHUPS_HOOPR_SEASON),
  function() hoopR::load_nba_team_box(seasons = MATCHUPS_HOOPR_SEASON)
)

if (nrow(team_box) > 0) {
  team_box$espn_game_id <- as.character(team_box$game_id)
  box_wide <- team_box %>%
    filter(.data$espn_game_id %in% games$espn_game_id) %>%
    select(espn_game_id, team_home_away, team_score) %>%
    mutate(team_score = suppressWarnings(as.numeric(.data$team_score))) %>%
    group_by(.data$espn_game_id, .data$team_home_away) %>%
    slice(1) %>%
    ungroup()
  home_box <- box_wide %>% filter(.data$team_home_away == "home") %>%
    transmute(espn_game_id, box_home_score = .data$team_score)
  away_box <- box_wide %>% filter(.data$team_home_away == "away") %>%
    transmute(espn_game_id, box_away_score = .data$team_score)
  games <- games %>%
    left_join(home_box, by = "espn_game_id") %>%
    left_join(away_box, by = "espn_game_id")
} else {
  cat(sprintf(">>> No team box scores exist yet for season %d - no game can be graded.\n",
              MATCHUPS_HOOPR_SEASON))
  games$box_home_score <- NA_real_
  games$box_away_score <- NA_real_
}

n_with_box <- sum(!is.na(games$box_home_score) & !is.na(games$box_away_score))
cat(sprintf(">>> Real final scores available for %d of %d games\n", n_with_box, nrow(games)))

# ------------------------------------------------------------------------------
# 4. Slate assignment (see DESIGN DECISION 1)
# ------------------------------------------------------------------------------
games$slate <- as.integer(floor(as.numeric(games$game_date - season_start) / 7) + 1)

slate_bounds <- games %>%
  group_by(.data$slate) %>%
  summarise(start_date = min(.data$game_date), end_date = max(.data$game_date),
            .groups = "drop") %>%
  arrange(.data$slate)

missing_slates <- setdiff(seq_len(max(games$slate)), unique(games$slate))
if (length(missing_slates) > 0) {
  stop(sprintf("Week indices are not contiguous - no games in week(s) %s.",
               paste(missing_slates, collapse = ", ")))
}

# "%-d" is not portable on Windows, so the day number is formatted by hand.
slate_label <- function(s, start_date, end_date) {
  fmt <- function(d) sprintf("%s %d", format(d, "%b"), as.integer(format(d, "%d")))
  sprintf("Week %d · %s – %s", s, fmt(start_date), fmt(end_date))
}

# ------------------------------------------------------------------------------
# 5. Per-game projection + grading
# ------------------------------------------------------------------------------
today <- Sys.Date()

num_or_null <- function(x, digits = NULL) {
  if (length(x) != 1 || is.na(x)) return(NULL)
  if (!is.null(digits)) x <- round(as.numeric(x), digits)
  as.numeric(x)
}

matchups <- vector("list", nrow(games))
for (i in seq_len(nrow(games))) {
  g <- games[i, ]

  # Graded ONLY when the log resolved it AND a real box score exists.
  is_completed <- identical(as.character(g$log_status), "RESOLVED") &&
    !is.na(g$log_correct) &&
    !is.na(g$box_home_score) && !is.na(g$box_away_score)

  home_abbr <- g$home_team
  away_abbr <- g$away_team

  win_prob <- as.numeric(g$predicted_home_win_prob)
  margin <- as.numeric(g$predicted_margin)
  basis <- NULL
  # PRECEDENCE: a logged model prediction always wins and is never overwritten
  # or adjusted by the ratings fallback (see DESIGN DECISION 2).
  if (!is.na(margin)) {
    basis <- "logged_model_margin"
  } else if (!is.na(win_prob)) {
    # Inverse of this repo's documented margin -> win-prob map (config.R MARGIN_SIGMA).
    margin <- qnorm(min(max(win_prob, 1e-6), 1 - 1e-6)) * MARGIN_SIGMA
    basis <- "margin_from_logged_win_prob"
  } else if (!is.na(g$home_rating) && !is.na(g$away_rating)) {
    # Tier 2: the full ensemble baseline, carried by every scheduled game the
    # 48-hour logged slate has not reached. Blended net-rating differential,
    # home-court advantage, then the two sides' fatigue differential (2c).
    margin <- (as.numeric(g$home_rating) - as.numeric(g$away_rating)) +
      HCA_POINTS + as.numeric(g$schedule_adjustment)
    # SIGMA IS PER GAME, not the flat MARGIN_SIGMA. Two independent sources of
    # error stack on the game's own outcome noise: how far apart the four models
    # put the home team, and how far apart they put the visitor. Added in
    # quadrature because they are separate teams' disagreements, not one shared
    # one. The effect is to pull the win probability toward 0.5 for matchups the
    # ensemble is least sure about, while a game between two teams the models
    # agree on still prices at essentially MARGIN_SIGMA.
    sigma_game <- sqrt(MARGIN_SIGMA^2 +
                         as.numeric(g$home_rating_sd)^2 +
                         as.numeric(g$away_rating_sd)^2)
    win_prob <- pnorm(margin / sigma_game)
    basis <- "primary_ensemble"
  }

  matchups[[i]] <- list(
    game_id = as.character(g$espn_game_id),
    slate = as.integer(g$slate),
    game_date = format(g$game_date, "%Y-%m-%d"),
    weekday = format(g$game_date, "%a"),
    season = as.integer(MATCHUPS_HOOPR_SEASON),
    home_team = home_abbr,
    away_team = away_abbr,
    home_team_name = as.character(g$home_name),
    away_team_name = as.character(g$away_name),
    is_completed = is_completed,
    # TRUE when the game carries a projection from EITHER basis; which one it is
    # is always readable from `projection_basis`.
    has_projection = !is.null(basis),
    projection_basis = basis,
    predicted_margin = num_or_null(margin, 2),
    predicted_home_win_prob = num_or_null(win_prob, 4),
    predicted_away_win_prob = if (is.na(win_prob)) NULL else round(1 - win_prob, 4),
    predicted_winner = if (is.na(win_prob)) NULL else if (win_prob >= 0.5) home_abbr else away_abbr,
    # Result fields are populated for graded games ONLY; everything else emits null.
    home_score = if (is_completed) as.integer(g$box_home_score) else NULL,
    away_score = if (is_completed) as.integer(g$box_away_score) else NULL,
    actual_margin = if (is_completed) as.integer(g$box_home_score - g$box_away_score) else NULL,
    actual_winner = if (is_completed) {
      if (g$box_home_score >= g$box_away_score) home_abbr else away_abbr
    } else NULL,
    # Taken verbatim from the accuracy log's own `correct` column, never regraded.
    prediction_correct = if (is_completed) as.logical(g$log_correct) else NULL
  )
}

n_completed <- sum(vapply(matchups, function(m) isTRUE(m$is_completed), logical(1)))
n_pending <- length(matchups) - n_completed
n_projected <- sum(vapply(matchups, function(m) isTRUE(m$has_projection), logical(1)))
basis_vec <- vapply(matchups,
                    function(m) if (is.null(m$projection_basis)) NA_character_ else m$projection_basis,
                    character(1))
n_logged_basis <- sum(basis_vec %in% c("logged_model_margin", "margin_from_logged_win_prob"))
n_ensemble_basis <- sum(basis_vec == "primary_ensemble", na.rm = TRUE)
n_ratings_basis <- sum(basis_vec == "team_rating_differential", na.rm = TRUE)
n_unlogged_basis <- n_ensemble_basis + n_ratings_basis
cat(sprintf(">>> %d graded games, %d pending; %d games carry a model projection, %d carry none\n",
            n_completed, n_pending, n_projected, length(matchups) - n_projected))
cat(sprintf(">>> projection_basis: %d from the logged model, %d from primary ensemble, %d from team rating differential\n",
            n_logged_basis, n_ensemble_basis, n_ratings_basis))
stopifnot(n_logged_basis + n_unlogged_basis == n_projected)

# ------------------------------------------------------------------------------
# 6. Slate summaries, including per-slate accuracy over GRADED games only
# ------------------------------------------------------------------------------
slate_ids <- sort(unique(vapply(matchups, function(m) m$slate, integer(1))))
active_slate <- {
  in_today <- slate_bounds$slate[slate_bounds$start_date <= today & slate_bounds$end_date >= today]
  if (length(in_today) > 0) {
    as.integer(min(in_today))
  } else if (today < season_start) {
    as.integer(min(slate_ids))
  } else {
    as.integer(max(slate_ids))
  }
}

slates <- lapply(slate_ids, function(s) {
  in_slate <- Filter(function(m) m$slate == s, matchups)
  graded <- Filter(function(m) isTRUE(m$is_completed), in_slate)
  n_graded <- length(graded)
  n_correct <- sum(vapply(graded, function(m) isTRUE(m$prediction_correct), logical(1)))
  b <- slate_bounds[slate_bounds$slate == s, ]
  list(
    slate = as.integer(s),
    label = slate_label(s, b$start_date[1], b$end_date[1]),
    start_date = format(b$start_date[1], "%Y-%m-%d"),
    end_date = format(b$end_date[1], "%Y-%m-%d"),
    status = if (s < active_slate) "past" else if (s == active_slate) "active" else "future",
    games_total = as.integer(length(in_slate)),
    # Per-basis counts, so the UI can state the week's mix of projection
    # sources instead of implying one model produced all of them.
    logged_projection_total = as.integer(sum(vapply(in_slate, function(m) {
      !is.null(m$projection_basis) &&
        m$projection_basis %in% c("logged_model_margin", "margin_from_logged_win_prob")
    }, logical(1)))),
    ratings_projection_total = as.integer(sum(vapply(in_slate, function(m) {
      !is.null(m$projection_basis) &&
        m$projection_basis %in% c("primary_ensemble", "team_rating_differential")
    }, logical(1)))),
    ensemble_projection_total = as.integer(sum(vapply(in_slate, function(m) {
      identical(m$projection_basis, "primary_ensemble")
    }, logical(1)))),
    graded_total = as.integer(n_graded),
    correct_total = as.integer(n_correct),
    # NULL, not 0, when nothing in the week is graded - the UI must render a
    # "not yet graded" state rather than 0/0 or 0%.
    accuracy_pct = if (n_graded > 0) round(100 * n_correct / n_graded, 1) else NULL
  )
})

dataset <- list(
  season = as.integer(MATCHUPS_HOOPR_SEASON),
  season_label = MATCHUPS_SEASON_LABEL,
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  slate_granularity = "week_of_season",
  season_start_date = format(season_start, "%Y-%m-%d"),
  season_end_date = format(season_end, "%Y-%m-%d"),
  schedule_source = sprintf("hoopR::load_nba_schedule(seasons = %d)", MATCHUPS_HOOPR_SEASON),
  active_slate = active_slate,
  available_slates = as.integer(slate_ids),
  total_games = as.integer(length(matchups)),
  completed_games = as.integer(n_completed),
  pending_games = as.integer(n_pending),
  games_with_projection = as.integer(n_projected),
  games_without_projection = as.integer(length(matchups) - n_projected),
  # Basis counts: logged active slate vs. primary ensemble / ratings
  games_logged_basis = as.integer(n_logged_basis),
  games_ratings_basis = as.integer(n_unlogged_basis),
  games_ensemble_basis = as.integer(n_ensemble_basis),
  ratings_source = ratings_source_desc,
  rating_match_rate_pct = rated_pct,
  # Measured on every run, never assumed (see JOIN KEY above).
  logged_predictions_in_season = as.integer(nrow(log_season)),
  logged_predictions_matched = as.integer(n_log_matched),
  join_match_rate_pct = log_match_pct,
  # Explicit record of the zero-graded state, so the UI never has to infer it.
  graded_games_available = n_completed > 0,
  grading_state = if (n_completed > 0) "graded" else "no_games_graded_yet",
  slates = slates,
  matchups = matchups
)

# ------------------------------------------------------------------------------
# 7. Export
# ------------------------------------------------------------------------------
cat(sprintf(">>> Saving matchups cache to: %s\n", CACHE_MATCHUPS))
saveRDS(dataset, CACHE_MATCHUPS)

cat(sprintf(">>> Exporting public JSON for Next.js to: %s\n", CACHE_MATCHUPS_JSON))
write_json(dataset, CACHE_MATCHUPS_JSON, pretty = TRUE, auto_unbox = TRUE, null = "null",
           digits = NA)

cat(sprintf(paste0(
  ">>> [SUCCESS] %s season: %d games across %d weeks (%s .. %s), active week %d;\n",
  ">>>           %d graded, %d pending, %d with a projection. Grading state: %s.\n"),
  MATCHUPS_SEASON_LABEL, length(matchups), length(slate_ids),
  format(season_start), format(season_end), active_slate,
  n_completed, n_pending, n_projected, dataset$grading_state))
