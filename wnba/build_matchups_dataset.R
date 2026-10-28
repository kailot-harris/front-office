# ==============================================================================
# build_matchups_dataset.R
# Builds the per-game Matchups dataset that backs web/app/matchups (WNBA #74).
# Path: build_matchups_dataset.R
#
# ---- NOTHING HERE IS A NEW MODEL ----
# This stage joins artifacts three existing pipeline stages already produce and
# emits them per game. It fits no model, grades no prediction of its own, and
# restates no constant: WNBA_HCA and WNBA_MARGIN_SIGMA are read from config.R,
# and every grade is copied verbatim from the accuracy log.
#
# Sources (all read-only):
#   CACHE_WNBA_SCHEDULE  cache/wnba_schedule_cache.rds   - the season spine.
#                        Written by daily_ingest.R's daily_schedule_ingest()
#                        from wehoop::load_wnba_schedule(seasons = CURRENT_SEASON),
#                        so it is single-season BY CONSTRUCTION - see SEASON
#                        SCOPE below. LONG format: one row per team per game.
#   CACHE_TEAM_BOX       data/box_scores_cache.rds       - final scores.
#                        NOTE the path: team box scores live under data/, not
#                        cache/ (config.R:221). Multi-season, back to 2019, so
#                        it MUST be filtered to the target season.
#   PRED_LOG_RDS         cache/prediction_accuracy_log.rds - model predictions
#                        and their grades.
#   cache/projected_wnba_standings.rds                  - Net_Rating, for the
#                        fallback projection basis (see PROJECTION BASES).
#
# Exports CACHE_MATCHUPS (.rds) and WEB_JSON_MATCHUPS_SLATES (web/public/data).
#
# ------------------------------------------------------------------------------
# SEASON SCOPE
# ------------------------------------------------------------------------------
# The dataset covers EXACTLY ONE season: config.R's CURRENT_SEASON.
#
# Unlike the NBA sibling - whose equivalent builder needs its own
# MATCHUPS_HOOPR_SEASON switch because hoopR numbers a split-year season by its
# END year, so "2026" is ambiguous - the WNBA season is contained in one
# calendar year and wehoop numbers it by that year. CURRENT_SEASON is therefore
# unambiguous here and is used directly. There is deliberately no
# WNBA_MATCHUPS_SEASON override: the schedule cache only ever holds
# CURRENT_SEASON, so an override would select a season whose spine is absent.
#
# The box score cache is the one multi-season input and is filtered explicitly;
# a game from another season must never enter this dataset.
#
# ------------------------------------------------------------------------------
# JOIN KEYS - two different ones, for two different reasons
# ------------------------------------------------------------------------------
#   Spine <-> box scores:  ESPN `game_id` (e.g. "401856890"), an exact key match.
#       Both artifacts come from ESPN via wehoop, so no crosswalk is involved.
#
#   Spine <-> accuracy log: game date + home abbreviation + away abbreviation.
#       The log does NOT carry the ESPN game_id. Its `game_id` is this repo's
#       own content hash (e.g. "e1345bc3242e9236f8524205bb759ad3"), assigned by
#       prediction_accuracy_logger.R, so it cannot be joined to the spine at
#       all and a natural key is the only option.
#       Measured on 2026-10-28: 44 of 45 real logged predictions join. The
#       realised rate is recomputed and printed on every run and recorded in
#       the dataset - it is never assumed.
#
# Team abbreviations need NO fixup table. The schedule cache, the box scores and
# the log all use the same ESPN abbreviations (GS, LA, LV, NY, WSH ...), and all
# 15 map exactly onto the standings table's full `Team` names via the crosswalk
# built from the box scores below. This is the main structural simplification
# over the NBA builder, which needs an ESPN_ABBR_FIXUPS table because its web
# app's canonical set (GSW/NYK/WAS) differs from ESPN's.
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 1 - SLATE GRANULARITY: week-of-season buckets.
# ------------------------------------------------------------------------------
# Issue #74 asks for a "week selector ribbon spanning every week in the season".
# The WNBA plays most days across a ~25-week season, so games are bucketed into
# fixed 7-day windows measured from the season's first game date:
#   slate = floor((game_date - season_start) / 7) + 1
# That keeps the ribbon navigable (~26 entries for 355 games), matches the
# issue's week language, and gives each week a large enough sample for a stable
# "X / Y correct (Z%)" figure. This is the ONLY granularity used in this file or
# in the web components; no per-day slate exists.
#
# Unlike the NBA spine, WNBA week indices are NOT guaranteed contiguous: the
# regular season and the postseason are separated by a break, so a week with
# zero games is possible. Empty weeks are omitted from the ribbon rather than
# emitted as zero-game slates, and the week index is therefore a label, not a
# position - the UI must not assume `available_weeks` is a dense 1..N range.
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 2 - PROJECTION BASES, AND WHY THERE ARE TWO.
# ------------------------------------------------------------------------------
# TWO DIFFERENT MODELS PRODUCE THE NUMBERS ON THIS PAGE. They are kept apart,
# never averaged, never compared, and every game declares which it used via
# `projection_basis`:
#
#   (A) LOGGED MODEL PREDICTION - the real one. `predicted_home_win_prob` /
#       `predicted_margin` written per game into PRED_LOG_RDS by
#       prediction_accuracy_logger.R before the game was played. This is the
#       model the accuracy log grades, so it is the ONLY basis that is EVER
#       graded, and it always wins: a logged projection is never overwritten or
#       adjusted here.
#         basis "logged_model"            - margin came straight from the log.
#         basis "logged_model_prob_only"  - the log left `predicted_margin` NA,
#           so the margin is that same logged probability inverted through this
#           repo's documented margin -> win-probability map
#           (margin = qnorm(p) * WNBA_MARGIN_SIGMA). Same model, derived field.
#
#   (B) TEAM RATING DIFFERENTIAL - the weaker one, used ONLY to fill games the
#       log never predicted, and NEVER graded. It is not a new model: it is the
#       same formula build_finals_game_predictions.R:23 and
#       tools/series_length_predictor.R already use -
#         pred_margin = (home_net - away_net) + WNBA_HCA
#         pred_prob   = pnorm(pred_margin / WNBA_MARGIN_SIGMA)
#       - reading Net_Rating from cache/projected_wnba_standings.rds.
#       basis "team_rating_differential".
#
#       NO fatigue / rest / travel adjustment is applied to basis (B), even
#       though this repo CAN compute one (calculate_travel_fatigue() in
#       fatigue_travel_engine.R, and the schedule cache carries the per-team
#       days_rest / is_back_to_back / last_played_at it needs for unplayed games
#       too, per issue #93). That is deliberate: basis (A) already contains a
#       `contrib_fatigue` term, so fatigue-adjusting (B) would make the two
#       bases differ in two dimensions at once instead of one, and the per-game
#       `projection_basis` label would no longer isolate what changed. If a
#       rest-adjusted projection is wanted on this page later, add it as a
#       THIRD field beside the HCA-only one - the way
#       build_finals_game_predictions.R sits its rest-adjusted probability
#       beside the HCA-only one - rather than folding it into (B).
#
# These two are NOT interchangeable and must never be presented as one number:
# (A) is a full model output with injury, shot-quality and fatigue inputs, (B)
# is a season-long rating difference plus a flat home-court constant. The UI
# labels every card with its basis and never ranks or aggregates across the two.
#
# A game whose teams are absent from the ratings table emits NULL for every
# projection field and `projection_basis: null` - never a placeholder number.
#
# ------------------------------------------------------------------------------
# GRADING - and why most of this season is ungraded
# ------------------------------------------------------------------------------
# A game is GRADED (`prediction_correct` non-null) only when the accuracy log
# has actually RESOLVED it (status "RESOLVED" with a non-NA `correct`). The
# grade is copied verbatim from the log's `correct` column and is NEVER
# recomputed, so this stage cannot disagree with the accuracy page.
#
# A game is PLAYED (`is_completed`) on a different and independent test: the box
# score cache has a real final score for it. These two are deliberately NOT the
# same flag, because for this season they differ enormously - measured
# 2026-10-28: 352 games have final scores, but only 44 have a logged, resolved
# prediction, because prediction_accuracy_logger.R only began writing real rows
# on 2026-09-17.
#
# So ~308 games correctly show a final score with NO grade and NO model
# prediction. That is a true statement about this repo's history, not a gap to
# be filled: the payload distinguishes the two cases explicitly via
# `has_prediction`, so the UI can say "no prediction was recorded" instead of
# implying the model got it wrong. Nothing here back-fills a prediction for a
# game whose result is already known - that would manufacture a track record
# rather than report one.
#
# `actual_winner` and the scores come from the box score (observed fact, from
# the same artifact, not an inference); the GRADE never does.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

# ------------------------------------------------------------------------------
# 0. Configuration + path resolution
# ------------------------------------------------------------------------------
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

stopifnot(exists("CURRENT_SEASON"), exists("WNBA_HCA"), exists("WNBA_MARGIN_SIGMA"),
          exists("CACHE_WNBA_SCHEDULE"), exists("CACHE_TEAM_BOX"),
          exists("CACHE_MATCHUPS"), exists("WEB_JSON_MATCHUPS_SLATES"))

# PRED_LOG_RDS is defined in prediction_accuracy_logger.R:90, not config.R, and
# that logger is out of scope for this stage (sourcing it would pull in its
# ingestion machinery for a path string). The path is therefore DELIBERATELY
# duplicated here as a named constant - so the duplication is visible and
# attributed rather than pasted as a bare string - instead of being hoisted into
# a competing config.R constant. If the logger's line changes, change this with it.
MATCHUPS_PRED_LOG <- file.path(CACHE_DIR, "prediction_accuracy_log.rds")

MATCHUPS_RATINGS <- file.path(CACHE_DIR, "projected_wnba_standings.rds")

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
if (!dir.exists(dirname(WEB_JSON_MATCHUPS_SLATES))) {
  dir.create(dirname(WEB_JSON_MATCHUPS_SLATES), recursive = TRUE)
}

cat(sprintf(">>> [PHASE 1] Building WNBA Matchups dataset for the %d season...\n",
            CURRENT_SEASON))

resolve_input <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf(
      "%s not found at %s - run the pipeline stage that produces it first.",
      label, path
    ))
  }
  path
}

# The whole stage is one function so pipeline_stages.R can register it by
# `entry_fn`, and the self-run guard at the bottom keeps `Rscript
# build_matchups_dataset.R` working. entry_fn (not call_fn) is deliberate: the
# guard means a call_fn registration would execute the stage TWICE - the
# double-execution trap documented in run_stage().
build_matchups_dataset <- function() {

# ------------------------------------------------------------------------------
# 1. SPINE: the season schedule, collapsed from long to one row per game
# ------------------------------------------------------------------------------
sched_long <- as.data.frame(readRDS(
  resolve_input(CACHE_WNBA_SCHEDULE, "WNBA schedule cache")
))
if (nrow(sched_long) == 0) {
  stop("The schedule cache is empty - no season spine. Run daily_ingest.R first.")
}
sched_long$game_date <- as.Date(as.character(sched_long$game_date))

# Season guard. The cache is written single-season, so an off-season row means
# the ingest contract broke; drop loudly rather than silently emitting it.
if ("season" %in% names(sched_long)) {
  off <- sum(as.integer(sched_long$season) != CURRENT_SEASON, na.rm = TRUE)
  if (off > 0) {
    cat(sprintf(">>> [WARN] dropping %d schedule rows not in season %d\n",
                off, CURRENT_SEASON))
    sched_long <- sched_long[as.integer(sched_long$season) == CURRENT_SEASON, ]
  }
}

# LONG -> WIDE. The cache carries one row per team per game with `is_home`; the
# home row alone names both sides (team + opponent_team), so it IS the game row.
# Taking only the home rows is what collapses the 2x duplication.
is_home_flag <- !is.na(sched_long$is_home) & sched_long$is_home
home_rows <- sched_long[is_home_flag, ]

# Contract: exactly one home row per game. A neutral-site or mis-ingested game
# could yield zero or two, which would silently drop or duplicate a fixture.
n_games_long <- length(unique(sched_long$game_id))
dup <- home_rows$game_id[duplicated(home_rows$game_id)]
if (length(dup) > 0) {
  stop(sprintf(paste0(
    "%d game(s) have more than one home row in the schedule cache (%s). The ",
    "long->wide collapse assumes exactly one; fix daily_schedule_ingest()'s ",
    "is_home derivation before publishing."),
    length(unique(dup)), paste(utils::head(unique(dup), 5), collapse = ", ")))
}
missing_home <- setdiff(unique(sched_long$game_id), home_rows$game_id)
if (length(missing_home) > 0) {
  stop(sprintf(paste0(
    "%d game(s) have NO home row in the schedule cache (%s) - they would be ",
    "dropped from the spine entirely. Likely a neutral-site fixture; decide ",
    "explicitly how to orient it rather than losing it."),
    length(missing_home), paste(utils::head(missing_home, 5), collapse = ", ")))
}

spine <- home_rows %>%
  transmute(
    espn_game_id = as.character(.data$game_id),
    game_date    = .data$game_date,
    season_type  = suppressWarnings(as.integer(.data$season_type)),
    scheduled_completed = !is.na(.data$is_completed) & .data$is_completed,
    home_team    = as.character(.data$team_abbreviation),
    away_team    = as.character(.data$opponent_team_abbreviation)
  ) %>%
  arrange(.data$game_date, .data$espn_game_id)

season_start <- min(spine$game_date)
season_end   <- max(spine$game_date)
cat(sprintf(">>> Season spine: %d games (%d team-rows collapsed), %s .. %s\n",
            nrow(spine), nrow(sched_long), format(season_start), format(season_end)))

# ESPN season_type: 2 = regular season, 3 = postseason. Labelled rather than
# leaked as a bare integer, and anything unexpected is passed through as-is so
# an unknown type is visible on the page instead of being silently relabelled.
SEASON_TYPE_LABELS <- c("2" = "regular", "3" = "postseason")
spine$season_type_label <- unname(ifelse(
  as.character(spine$season_type) %in% names(SEASON_TYPE_LABELS),
  SEASON_TYPE_LABELS[as.character(spine$season_type)],
  paste0("unknown_", spine$season_type)
))

# Week-of-season buckets (DESIGN DECISION 1).
spine$week <- as.integer(
  floor(as.numeric(spine$game_date - season_start) / 7) + 1L
)

# ------------------------------------------------------------------------------
# 2. SCORES: box scores for this season only
# ------------------------------------------------------------------------------
box_all <- as.data.frame(readRDS(resolve_input(CACHE_TEAM_BOX, "team box scores")))
box <- box_all[!is.na(box_all$season) & as.integer(box_all$season) == CURRENT_SEASON, ]
cat(sprintf(">>> Box scores: %d team-rows for season %d (of %d rows, %d seasons)\n",
            nrow(box), CURRENT_SEASON, nrow(box_all),
            length(unique(box_all$season))))

# The crosswalk the ratings join needs: ESPN abbreviation -> full display name.
# Built from the box scores rather than hardcoded, so a franchise rename or
# expansion team (Portland Fire and Toronto Tempo both joined for 2026) needs no
# edit here.
crosswalk <- unique(box[, c("team_abbreviation", "team_display_name")])
crosswalk <- crosswalk[!is.na(crosswalk$team_abbreviation), ]
abbr_to_name <- setNames(as.character(crosswalk$team_display_name),
                         as.character(crosswalk$team_abbreviation))
cat(sprintf(">>> Team crosswalk: %d abbreviations -> display names\n", length(abbr_to_name)))

# One score row per game, oriented home/away by the box score's OWN
# team_home_away field rather than by the schedule's is_home, so a disagreement
# between the two artifacts surfaces as a missing join instead of a silently
# flipped scoreline.
box_home <- box[!is.na(box$team_home_away) & box$team_home_away == "home", ]
scores <- data.frame(
  espn_game_id = as.character(box_home$game_id),
  box_home_team = as.character(box_home$team_abbreviation),
  home_score = suppressWarnings(as.integer(box_home$team_score)),
  away_score = suppressWarnings(as.integer(box_home$opponent_team_score)),
  stringsAsFactors = FALSE
)
scores <- scores[!duplicated(scores$espn_game_id), ]

games <- spine %>% left_join(scores, by = "espn_game_id")

# Orientation contract: where a score joined, the two artifacts must agree on
# which side was at home. A flip here would show every score backwards.
flipped <- !is.na(games$box_home_team) & games$box_home_team != games$home_team
if (any(flipped)) {
  stop(sprintf(paste0(
    "%d game(s) disagree on home/away between the schedule cache and the box ",
    "scores (e.g. game %s: schedule says %s is home, box score says %s). Every ",
    "score for those games would render backwards; reconcile the two artifacts ",
    "before publishing."),
    sum(flipped), games$espn_game_id[flipped][1],
    games$home_team[flipped][1], games$box_home_team[flipped][1]))
}

# PLAYED is decided by the box score having a real final, NOT by the schedule's
# is_completed flag (see GRADING above).
games$is_completed <- !is.na(games$home_score) & !is.na(games$away_score)
n_played <- sum(games$is_completed)

# Report where the schedule flag and the box scores disagree. Not fatal: the
# schedule flag flips when ESPN marks a game final, and the box score can lag
# it by minutes, which is a normal transient rather than a defect.
disagree <- sum(games$scheduled_completed != games$is_completed)
cat(sprintf(">>> Played: %d of %d games have a final score (%d disagree with the schedule's is_completed flag)\n",
            n_played, nrow(games), disagree))
if (disagree > 0) {
  d <- games[games$scheduled_completed != games$is_completed, ]
  for (i in seq_len(min(nrow(d), 5))) {
    cat(sprintf(">>>   %s %s v %s: schedule=%s, box score=%s\n",
                format(d$game_date[i]), d$home_team[i], d$away_team[i],
                d$scheduled_completed[i], d$is_completed[i]))
  }
}

games$actual_margin <- ifelse(games$is_completed,
                              games$home_score - games$away_score, NA_integer_)
# Observed fact from the box score, not a grade. A tie is impossible in
# basketball (overtime is played), so no tie branch is needed - but assert it
# rather than assuming it, because a 0 margin would otherwise pick the away team.
if (any(games$is_completed & games$actual_margin == 0, na.rm = TRUE)) {
  stop("A completed game has a 0-point margin, which basketball cannot produce - the scores are wrong.")
}
games$actual_winner <- ifelse(
  games$is_completed,
  ifelse(games$actual_margin > 0, games$home_team, games$away_team),
  NA_character_
)

# ------------------------------------------------------------------------------
# 3. PREDICTIONS + GRADES: join the accuracy log on date + home + away
# ------------------------------------------------------------------------------
pred_log <- as.data.frame(readRDS(
  resolve_input(MATCHUPS_PRED_LOG, "prediction accuracy log")
))
pred_log$game_date <- as.Date(as.character(pred_log$game_date))

# Synthetic rows are dropped. market_odds_engine.R emits a placeholder slate
# with fabricated ids ("WNBA_GAME_2") when The Odds API quota is exhausted;
# those are not predictions about real fixtures and must never reach the page.
n_log_raw <- nrow(pred_log)
if ("is_synthetic" %in% names(pred_log)) {
  pred_log <- pred_log[!(!is.na(pred_log$is_synthetic) & pred_log$is_synthetic), ]
}
cat(sprintf(">>> Accuracy log: %d rows, %d real (%d synthetic placeholders dropped)\n",
            n_log_raw, nrow(pred_log), n_log_raw - nrow(pred_log)))

log_season <- pred_log %>%
  filter(.data$game_date >= season_start, .data$game_date <= season_end) %>%
  mutate(join_key = paste(format(.data$game_date), .data$home_team, .data$away_team)) %>%
  arrange(.data$game_date) %>%
  distinct(.data$join_key, .keep_all = TRUE)

games$join_key <- paste(format(games$game_date), games$home_team, games$away_team)

games <- games %>%
  left_join(
    log_season %>% transmute(
      join_key = .data$join_key,
      log_game_id = as.character(.data$game_id),
      log_status  = as.character(.data$status),
      logged_home_win_prob = suppressWarnings(as.numeric(.data$predicted_home_win_prob)),
      logged_margin        = suppressWarnings(as.numeric(.data$predicted_margin)),
      logged_winner        = as.character(.data$predicted_winner),
      log_correct = .data$correct
    ),
    by = "join_key"
  )

n_with_log   <- sum(!is.na(games$log_game_id))
n_log_match  <- sum(log_season$join_key %in% games$join_key)
n_log_unmatch <- nrow(log_season) - n_log_match
log_match_pct <- if (nrow(log_season) > 0) round(100 * n_log_match / nrow(log_season), 1) else 0

cat(sprintf(paste0(
  ">>> JOIN RATE (date + home abbr + away abbr):\n",
  ">>>   logged predictions matched to a scheduled game: %d of %d (%.1f%%); %d unmatched\n",
  ">>>   scheduled games carrying a logged prediction:   %d of %d (%.1f%%)\n"),
  n_log_match, nrow(log_season), log_match_pct, n_log_unmatch,
  n_with_log, nrow(games), round(100 * n_with_log / nrow(games), 1)))
if (n_log_unmatch > 0) {
  cat(">>>   unmatched logged predictions (log date/teams absent from the spine):\n")
  for (k in setdiff(log_season$join_key, games$join_key)) cat(sprintf(">>>     %s\n", k))
}

# JOIN RATE CONTRACT. An unmatched prediction for a game near today is an ACTIVE
# SLATE row: the model priced a fixture the spine does not have, which is a
# team-naming or home/away-orientation bug in the logger, and the page would
# silently show the weaker basis (B) for a game the model actually predicted.
# That is a hard error. Older unmatched rows only warn above: the log also
# legitimately carries games the spine does not (postponed or moved fixtures -
# the 2026-10-03 ATL/NY row is exactly this, logged then never played, and it
# is correctly left UNRESOLVABLE).
PRED_LOG_ACTIVE_WINDOW_DAYS <- 2L
active_unmatched <- log_season[
  !(log_season$join_key %in% games$join_key) &
    abs(as.numeric(log_season$game_date - Sys.Date())) <= PRED_LOG_ACTIVE_WINDOW_DAYS, ]
if (nrow(active_unmatched) > 0) {
  stop(sprintf(paste0(
    "%d active-slate logged prediction(s) within %d day(s) of today failed to ",
    "join the schedule spine on date + home/away abbreviation: %s. Fix the team ",
    "resolver / home-away orientation in prediction_accuracy_logger.R before publishing."),
    nrow(active_unmatched), PRED_LOG_ACTIVE_WINDOW_DAYS,
    paste(active_unmatched$join_key, collapse = "; ")))
}

# ------------------------------------------------------------------------------
# 4. RATINGS FALLBACK PROJECTION - basis (B). Same formula as
#    build_finals_game_predictions.R:23; no new model, no new constant.
# ------------------------------------------------------------------------------
ratings_df <- as.data.frame(readRDS(
  resolve_input(MATCHUPS_RATINGS, "projected WNBA standings (Net_Rating)")
))
if (!all(c("Team", "Net_Rating") %in% names(ratings_df))) {
  stop(sprintf("%s does not carry the expected `Team` / `Net_Rating` columns.",
               basename(MATCHUPS_RATINGS)))
}
net_by_name <- setNames(suppressWarnings(as.numeric(ratings_df$Net_Rating)),
                        as.character(ratings_df$Team))
cat(sprintf(">>> Ratings: %d rated teams from %s (column Net_Rating)\n",
            length(net_by_name), basename(MATCHUPS_RATINGS)))

.net_for <- function(abbr) unname(net_by_name[unname(abbr_to_name[abbr])])
games$home_net <- .net_for(games$home_team)
games$away_net <- .net_for(games$away_team)

n_rated <- sum(!is.na(games$home_net) & !is.na(games$away_net))
rated_pct <- round(100 * n_rated / nrow(games), 1)
cat(sprintf(">>> Both teams rated for %d of %d games (%.1f%%)\n",
            n_rated, nrow(games), rated_pct))
if (rated_pct < 90) {
  unrated <- sort(unique(c(games$home_team[is.na(games$home_net)],
                           games$away_team[is.na(games$away_net)])))
  stop(sprintf(paste0(
    "Only %.1f%% of games have both teams in %s - the abbreviation -> display ",
    "name crosswalk or the standings `Team` naming has drifted. Unrated: %s"),
    rated_pct, basename(MATCHUPS_RATINGS), paste(unrated, collapse = ", ")))
}

rating_margin <- (games$home_net - games$away_net) + WNBA_HCA
rating_prob   <- pnorm(rating_margin / WNBA_MARGIN_SIGMA)

# ------------------------------------------------------------------------------
# 5. RESOLVE THE BASIS PER GAME. (A) always wins over (B); see DESIGN DECISION 2.
# ------------------------------------------------------------------------------
has_logged_prob   <- !is.na(games$logged_home_win_prob)
has_logged_margin <- !is.na(games$logged_margin)

games$projected_margin <- ifelse(
  has_logged_margin, games$logged_margin,
  ifelse(has_logged_prob,
         # Same model, derived field: invert the logged probability through this
         # repo's documented margin -> probability map.
         qnorm(pmin(pmax(games$logged_home_win_prob, 1e-6), 1 - 1e-6)) * WNBA_MARGIN_SIGMA,
         rating_margin)
)
games$home_win_prob <- ifelse(
  has_logged_prob, games$logged_home_win_prob,
  ifelse(has_logged_margin, pnorm(games$logged_margin / WNBA_MARGIN_SIGMA),
         rating_prob)
)
games$projection_basis <- ifelse(
  has_logged_margin, "logged_model",
  ifelse(has_logged_prob, "logged_model_prob_only", "team_rating_differential")
)

# A game with neither a logged prediction nor two rated teams gets NOTHING, not
# a placeholder number.
no_basis <- !has_logged_prob & !has_logged_margin &
  (is.na(games$home_net) | is.na(games$away_net))
games$projected_margin[no_basis] <- NA_real_
games$home_win_prob[no_basis]    <- NA_real_
games$projection_basis[no_basis] <- NA_character_

games$has_prediction <- !no_basis
games$has_logged_prediction <- has_logged_prob | has_logged_margin

# Predicted winner: the log's own value where it has one (never recomputed),
# otherwise read off the basis (B) margin.
games$predicted_winner <- ifelse(
  !is.na(games$logged_winner), games$logged_winner,
  ifelse(is.na(games$projected_margin), NA_character_,
         ifelse(games$projected_margin > 0, games$home_team, games$away_team))
)

# ------------------------------------------------------------------------------
# 6. GRADES - verbatim from the log, and only for basis (A).
# ------------------------------------------------------------------------------
is_resolved <- !is.na(games$log_status) & games$log_status == "RESOLVED" &
  !is.na(games$log_correct)
games$is_graded <- is_resolved & games$is_completed
games$prediction_correct <- ifelse(games$is_graded, as.logical(games$log_correct), NA)

n_graded <- sum(games$is_graded)
n_correct <- sum(games$prediction_correct, na.rm = TRUE)
cat(sprintf(">>> Graded: %d of %d played games (%d correct, %s)\n",
            n_graded, n_played, n_correct,
            if (n_graded > 0) sprintf("%.1f%%", 100 * n_correct / n_graded) else "n/a"))

# A resolved grade for a game with no final score means the log resolved
# something the box scores do not have. Surfaced, not silently dropped.
orphan_grade <- sum(is_resolved & !games$is_completed)
if (orphan_grade > 0) {
  cat(sprintf(">>> [WARN] %d resolved grade(s) have no box score and are left ungraded\n",
              orphan_grade))
}

# The "nothing graded yet" state is legitimate (a season can be early, or - as
# in 2026 - the logger can have started late), so it is carried explicitly
# rather than left for the UI to infer from a 0/0 division.
grading_state <- if (n_graded == 0) "no_games_graded_yet" else "partial"
if (n_graded > 0 && n_graded == n_played) grading_state <- "complete"

# ------------------------------------------------------------------------------
# 7. ASSEMBLE THE PAYLOAD
# ------------------------------------------------------------------------------
games <- games %>% arrange(.data$game_date, .data$espn_game_id)

# `active_week` is the week the site should open on: the last week containing a
# played game, or week 1 before the season starts. For a finished season that is
# the final week, which is the correct landing page.
played_weeks <- sort(unique(games$week[games$is_completed]))
active_week <- if (length(played_weeks) > 0) max(played_weeks) else min(games$week)

matchups <- lapply(seq_len(nrow(games)), function(i) {
  g <- games[i, ]
  list(
    game_id        = g$espn_game_id,
    game_date      = format(g$game_date),
    week           = as.integer(g$week),
    season_type    = g$season_type_label,
    home_team      = g$home_team,
    away_team      = g$away_team,
    home_team_name = unname(abbr_to_name[g$home_team]),
    away_team_name = unname(abbr_to_name[g$away_team]),
    is_completed   = as.logical(g$is_completed),
    # ABSENT VALUES ARE TYPED NA, NEVER NULL. jsonlite RETAINS a NULL list
    # element and serialises it as `{}`, not `null` - so `home_score = NULL`
    # would emit an empty OBJECT where the web types declare `number | null`,
    # and React then fails to render it ("Objects are not valid as a React
    # child"). The `na = "null"` argument at the write_json call below is what
    # turns these NAs into real JSON nulls; the NA must stay TYPED so the
    # column's JSON type is preserved.
    home_score     = as.integer(g$home_score),
    away_score     = as.integer(g$away_score),
    actual_margin  = as.integer(g$actual_margin),
    actual_winner  = as.character(g$actual_winner),
    has_prediction = as.logical(g$has_prediction),
    # TRUE only for basis (A). The UI uses this to distinguish "the model got
    # this wrong" from "no prediction was ever recorded for this game".
    has_logged_prediction = as.logical(g$has_logged_prediction),
    projection_basis = as.character(g$projection_basis),
    projected_margin = if (is.na(g$projected_margin)) NA_real_ else round(g$projected_margin, 2),
    home_win_prob    = if (is.na(g$home_win_prob)) NA_real_ else round(g$home_win_prob, 4),
    predicted_winner = as.character(g$predicted_winner),
    is_graded        = as.logical(g$is_graded),
    prediction_correct = as.logical(g$prediction_correct)
  )
})

# Per-week summaries. Accuracy is NULL rather than 0 when a week graded nothing,
# so the UI can never render a misleading 0%.
week_ids <- sort(unique(games$week))
weeks <- lapply(week_ids, function(w) {
  wg <- games[games$week == w, ]
  gr <- sum(wg$is_graded)
  co <- sum(wg$prediction_correct, na.rm = TRUE)
  list(
    week = as.integer(w),
    start_date = format(min(wg$game_date)),
    end_date   = format(max(wg$game_date)),
    # A week can legitimately span both: the postseason break does not always
    # align to a 7-day boundary.
    #
    # I() IS LOAD-BEARING. `auto_unbox = TRUE` collapses a length-1 vector to a
    # JSON scalar, so a week containing only regular-season games would emit
    # "regular" instead of ["regular"] - a type change the web contract rejects
    # and the UI would crash iterating. I() marks it AsIs so it always stays an
    # array. Same reason for available_weeks below.
    season_types = I(sort(unique(wg$season_type_label))),
    total_games     = nrow(wg),
    completed_games = sum(wg$is_completed),
    pending_games   = sum(!wg$is_completed),
    graded_games    = gr,
    # Typed NA, not NULL - see the note in the matchups block above.
    correct_games   = if (gr > 0) as.integer(co) else NA_integer_,
    accuracy_pct    = if (gr > 0) round(100 * co / gr, 1) else NA_real_
  )
})

payload <- list(
  season = as.integer(CURRENT_SEASON),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  season_start = format(season_start),
  season_end   = format(season_end),
  active_week  = as.integer(active_week),
  # A LABEL list, not a dense range - see DESIGN DECISION 1. Weeks with no
  # games are absent, so the UI must iterate this and never 1..max().
  # I() keeps it an array even for a one-week season; see season_types below.
  available_weeks = I(as.integer(week_ids)),
  summary = list(
    total_games     = nrow(games),
    completed_games = n_played,
    pending_games   = sum(!games$is_completed),
    graded_games    = n_graded,
    # Typed NA, not NULL - see the note in the matchups block below.
    correct_games   = if (n_graded > 0) as.integer(n_correct) else NA_integer_,
    accuracy_pct    = if (n_graded > 0) round(100 * n_correct / n_graded, 1) else NA_real_,
    graded_games_available = n_graded > 0,
    grading_state   = grading_state,
    # Games that were played but carry no logged model prediction. Published so
    # the page can state the coverage honestly instead of implying the model
    # forecast every game. See GRADING above.
    played_without_logged_prediction = sum(games$is_completed & !games$has_logged_prediction)
  ),
  # The measured join rate, recorded rather than assumed (see JOIN KEYS).
  provenance = list(
    logged_predictions_in_window = nrow(log_season),
    logged_predictions_matched   = n_log_match,
    logged_predictions_unmatched = n_log_unmatch,
    log_match_pct                = log_match_pct,
    games_with_logged_prediction = n_with_log,
    hca_points    = WNBA_HCA,
    margin_sigma  = WNBA_MARGIN_SIGMA,
    ratings_source = basename(MATCHUPS_RATINGS),
    basis_counts = as.list(table(factor(
      ifelse(is.na(games$projection_basis), "none", games$projection_basis),
      levels = c("logged_model", "logged_model_prob_only",
                 "team_rating_differential", "none")
    )))
  ),
  weeks = weeks,
  matchups = matchups
)

# ------------------------------------------------------------------------------
# 8. WRITE
# ------------------------------------------------------------------------------
saveRDS(games, CACHE_MATCHUPS)
cat(sprintf(">>> Wrote %s (%d games)\n", CACHE_MATCHUPS, nrow(games)))

write_json(payload, WEB_JSON_MATCHUPS_SLATES, pretty = TRUE, auto_unbox = TRUE,
           na = "null", digits = NA)
cat(sprintf(">>> Wrote %s (%d games, %d weeks)\n",
            WEB_JSON_MATCHUPS_SLATES, nrow(games), length(weeks)))

cat(sprintf(paste0(
  ">>> [DONE] Matchups dataset: %d games | %d played | %d graded (%s) | ",
  "%d basis(A) / %d basis(B) | active week %d of %d\n"),
  nrow(games), n_played, n_graded,
  if (n_graded > 0) sprintf("%.1f%%", 100 * n_correct / n_graded) else "not yet graded",
  sum(games$has_logged_prediction),
  sum(!games$has_logged_prediction & games$has_prediction),
  active_week, length(week_ids)))

  invisible(list(games = games, payload = payload))
}

# Self-run guard, matching build_playoff_bracket_2026.R and
# build_finals_game_predictions.R. NOTE what this does and does not mean: under
# Rscript `interactive()` is FALSE, so the stage runs on source() - it is NOT
# merely defined. That is exactly why pipeline_stages.R registers this stage
# with `entry_fn` and a NULL `call_fn`: entry_fn only verifies the symbol
# exists, so the stage is not invoked a second time after the source() already
# ran it (the double-execution trap documented in run_stage()).
if (!interactive()) {
  build_matchups_dataset()
}
