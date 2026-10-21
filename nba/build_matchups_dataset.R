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
# Human-facing label: hoopR season 2027 -> "2026-27".
MATCHUPS_SEASON_LABEL <- sprintf("%d-%02d", MATCHUPS_HOOPR_SEASON - 1L,
                                 MATCHUPS_HOOPR_SEASON %% 100L)

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

# Resolved from CACHE_DIR (config.R), never from another checkout. The file is a
# gitignored artifact of an earlier pipeline stage (roster_bottom_up_engine.R),
# so a fresh worktree will not have it until that stage has run.
RATINGS_PATH <- file.path(CACHE_DIR, "projected_30_team_standings.rds")
if (!file.exists(RATINGS_PATH)) {
  stop(sprintf(paste0(
    "Team ratings not found at %s - run the earlier pipeline stage first ",
    "(roster_bottom_up_engine.R writes cache/projected_30_team_standings.rds). ",
    "Without it the scheduled games the accuracy log has not predicted cannot be ",
    "projected, and this stage refuses to emit a dataset with invented numbers."),
    RATINGS_PATH))
}
ratings_df <- as.data.frame(readRDS(RATINGS_PATH))
if (!all(c("Team", "Net_Rating") %in% names(ratings_df))) {
  stop(sprintf("%s does not carry the expected `Team` / `Net_Rating` columns.", RATINGS_PATH))
}
team_ratings <- setNames(suppressWarnings(as.numeric(ratings_df$Net_Rating)),
                         as.character(ratings_df$Team))
team_ratings <- team_ratings[!is.na(team_ratings)]
cat(sprintf(">>> Team ratings: %d rated teams from %s (column Net_Rating)\n",
            length(team_ratings), basename(RATINGS_PATH)))

# Ratings are keyed by the same team SHORT display names the spine carries, so
# the match rate is measured, not assumed.
games$home_rating <- unname(team_ratings[games$home_name])
games$away_rating <- unname(team_ratings[games$away_name])
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
    rated_pct, basename(RATINGS_PATH), paste(unmatched, collapse = ", ")))
}

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
    # Verbatim prediction_accuracy_logger.R:142-172. A DIFFERENT, simpler model
    # than the logged one above - labelled as such, never blended with it.
    margin <- (as.numeric(g$home_rating) - as.numeric(g$away_rating)) + HCA_POINTS
    win_prob <- pnorm(margin / MARGIN_SIGMA)
    basis <- "team_rating_differential"
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
n_ratings_basis <- sum(basis_vec == "team_rating_differential", na.rm = TRUE)
cat(sprintf(">>> %d graded games, %d pending; %d games carry a model projection, %d carry none\n",
            n_completed, n_pending, n_projected, length(matchups) - n_projected))
cat(sprintf(">>> projection_basis: %d from the logged model, %d from team rating differential\n",
            n_logged_basis, n_ratings_basis))
# Invariant: a projection must never be both bases, and every projected game
# must name one.
stopifnot(n_logged_basis + n_ratings_basis == n_projected)

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
      identical(m$projection_basis, "team_rating_differential")
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
  # The two bases, counted separately and never summed into one "model" figure.
  games_logged_basis = as.integer(n_logged_basis),
  games_ratings_basis = as.integer(n_ratings_basis),
  ratings_source = sprintf("%s (Net_Rating) + %.2f HCA, pnorm(margin / %.1f)",
                           basename(RATINGS_PATH), HCA_POINTS, MARGIN_SIGMA),
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
