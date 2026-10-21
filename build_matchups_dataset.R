# ==============================================================================
# build_matchups_dataset.R
# Builds the per-game Matchups dataset that backs web/app/matchups.
#
# Sources (all repo-internal, nothing invented):
#   CACHE_PREDICTION_LOG (cache/prediction_accuracy_log.rds)
#     - one row per game with the model's PRE-GAME prediction. RESOLVED rows carry
#       `correct` (already graded by prediction_accuracy_logger.R); PENDING rows are
#       future-dated games that have a logged win probability but no outcome yet.
#   CACHE_TEAM_BOX (box_scores_cache.rds)
#     - two rows per completed game (home + away) from hoopR::load_nba_team_box();
#       the ONLY source of real final scores. Joined on game_id.
#
# Exports CACHE_MATCHUPS (.rds) and CACHE_MATCHUPS_JSON (web/public/data).
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 1 - SLATE GRANULARITY: week-of-season buckets.
# ------------------------------------------------------------------------------
# Issue #16 asks for a "week selector ribbon spanning every week in the season".
# The NBA plays daily, so a per-day slate would be ~170 selector entries for one
# season and a ~8-game sample per "X / Y correct (Z%)" accuracy stat. We therefore
# bucket games into fixed 7-day windows measured from the season's first game date
# (`slate = floor((game_date - season_start) / 7) + 1`), which keeps the ribbon
# navigable (~40 entries), matches the issue's week language and the ported NFL
# ribbon pattern, and gives each slate a large enough graded sample for a stable
# accuracy figure. This is the ONLY granularity used anywhere in this file and in
# the web components; no per-day slate exists.
#
# ------------------------------------------------------------------------------
# DESIGN DECISION 2 - WHERE FUTURE-GAME PROJECTIONS COME FROM.
# ------------------------------------------------------------------------------
# Future (not-yet-played) games come from the PENDING rows that
# prediction_accuracy_logger.R already writes into CACHE_PREDICTION_LOG before
# tip-off. Those rows carry a real model-produced `predicted_home_win_prob` but
# leave `predicted_margin` NA, so the projected margin for a pending game is
# reconstructed from that same logged probability using this repo's own documented
# margin -> win-probability relation (config.R MARGIN_SIGMA, win_prob =
# pnorm(margin / MARGIN_SIGMA)), inverted as margin = qnorm(p) * MARGIN_SIGMA.
# Every game therefore records a `projection_basis` of either
# "logged_model_margin" (margin came straight from the log) or
# "margin_from_logged_win_prob" (margin inverted from the logged probability).
# Nothing is simulated, imputed from team strength, or otherwise invented: if a
# pending row has no logged win probability, its projection fields are emitted as
# null rather than filled in.
#
# hoopR::load_nba_schedule(seasons = 2027) was checked against the live API and
# does return a usable 1,206-row schedule for the in-progress 2026-27 season, but
# it is deliberately NOT used here: its games are keyed by ESPN game_id while the
# accuracy log's pending rows are keyed by their own hash ids, so unioning the two
# would duplicate the same matchups under two ids, and the graded history this
# page needs (accuracy log + box scores) stops in June 2026. Using the accuracy log
# as the single source keeps slate, projection and grading consistent.
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

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
if (!dir.exists(dirname(CACHE_MATCHUPS_JSON))) {
  dir.create(dirname(CACHE_MATCHUPS_JSON), recursive = TRUE)
}

# Every path this script reads or writes is config-derived, i.e. under
# PROJECT_DIR; nothing outside this checkout is touched. `cache/` is gitignored,
# so the two input caches must already have been produced in THIS checkout by the
# earlier pipeline stages (prediction_accuracy_logger.R for the prediction log,
# daily_ingest.R for the team box scores) before this stage runs.
resolve_input <- function(path, label) {
  if (!file.exists(path)) {
    stop(sprintf(
      "%s not found at %s - run the pipeline stage that produces it first.",
      label, path
    ))
  }
  path
}

cat(">>> [PHASE 1] Building NBA per-game Matchups dataset...\n")

# ------------------------------------------------------------------------------
# 1. Load the prediction log (slate + projection + grading) and team box (scores)
# ------------------------------------------------------------------------------
pred_log <- as.data.frame(readRDS(resolve_input(CACHE_PREDICTION_LOG, "prediction accuracy log")))
team_box <- as.data.frame(readRDS(resolve_input(CACHE_TEAM_BOX, "team box scores")))

pred_log$game_id <- as.character(pred_log$game_id)
team_box$game_id <- as.character(team_box$game_id)
pred_log$game_date <- as.Date(pred_log$game_date)
team_box$game_date <- as.Date(team_box$game_date)

season <- CURRENT_SEASON
games <- pred_log %>%
  filter(.data$season == !!season) %>%
  arrange(.data$game_date, .data$game_id)

if (nrow(games) == 0) stop(sprintf("No games logged for season %s", season))

cat(sprintf(">>> %d logged games for season %s (%s .. %s)\n",
            nrow(games), season,
            min(games$game_date), max(games$game_date)))

# ESPN abbreviations in the box scores differ from the web app's canonical set
# (lib/teams.ts): normalize so <TeamLogo team=...> resolves.
ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                      NO = "NOP", WSH = "WAS")
canonical_abbr <- function(x) ifelse(x %in% names(ESPN_ABBR_FIXUPS),
                                     ESPN_ABBR_FIXUPS[x], x)

# team nickname -> canonical abbreviation, learned from the box scores themselves
# (the prediction log stores nicknames like "Trail Blazers", never abbreviations).
abbr_map <- team_box %>%
  filter(!is.na(.data$team_name), !is.na(.data$team_abbreviation)) %>%
  distinct(.data$team_name, .data$team_abbreviation) %>%
  group_by(.data$team_name) %>%
  slice(1) %>%
  ungroup()
nickname_to_abbr <- setNames(canonical_abbr(abbr_map$team_abbreviation), abbr_map$team_name)

to_abbr <- function(nickname) {
  out <- unname(nickname_to_abbr[nickname])
  ifelse(is.na(out), nickname, out)
}

# ------------------------------------------------------------------------------
# 2. Real final scores, joined from CACHE_TEAM_BOX on game_id
# ------------------------------------------------------------------------------
box_wide <- team_box %>%
  filter(.data$game_id %in% games$game_id) %>%
  select(game_id, team_home_away, team_score, team_abbreviation) %>%
  mutate(team_score = suppressWarnings(as.numeric(.data$team_score))) %>%
  group_by(.data$game_id, .data$team_home_away) %>%
  slice(1) %>%
  ungroup()

home_box <- box_wide %>%
  filter(.data$team_home_away == "home") %>%
  transmute(game_id, box_home_score = .data$team_score,
            box_home_abbr = canonical_abbr(.data$team_abbreviation))
away_box <- box_wide %>%
  filter(.data$team_home_away == "away") %>%
  transmute(game_id, box_away_score = .data$team_score,
            box_away_abbr = canonical_abbr(.data$team_abbreviation))

games <- games %>%
  left_join(home_box, by = "game_id") %>%
  left_join(away_box, by = "game_id")

cat(sprintf(">>> Joined real final scores for %d of %d games from %s\n",
            sum(!is.na(games$box_home_score) & !is.na(games$box_away_score)),
            nrow(games), basename(CACHE_TEAM_BOX)))

# ------------------------------------------------------------------------------
# 3. Slate assignment (see DESIGN DECISION 1)
# ------------------------------------------------------------------------------
season_start <- min(games$game_date)
games$slate <- as.integer(floor(as.numeric(games$game_date - season_start) / 7) + 1)

slate_bounds <- games %>%
  group_by(.data$slate) %>%
  summarise(start_date = min(.data$game_date), end_date = max(.data$game_date),
            .groups = "drop")

# "%-d" is not portable on Windows, so the day number is formatted by hand.
slate_label <- function(s, start_date, end_date) {
  fmt <- function(d) sprintf("%s %d", format(d, "%b"), as.integer(format(d, "%d")))
  sprintf("Week %d · %s – %s", s, fmt(start_date), fmt(end_date))
}

# ------------------------------------------------------------------------------
# 4. Per-game projection + grading
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
  is_completed <- identical(as.character(g$status), "RESOLVED") &&
    !is.na(g$box_home_score) && !is.na(g$box_away_score) && !is.na(g$correct)

  home_abbr <- if (!is.na(g$box_home_abbr)) g$box_home_abbr else to_abbr(g$home_team)
  away_abbr <- if (!is.na(g$box_away_abbr)) g$box_away_abbr else to_abbr(g$away_team)

  win_prob <- suppressWarnings(as.numeric(g$predicted_home_win_prob))
  margin <- suppressWarnings(as.numeric(g$predicted_margin))
  basis <- NULL
  if (!is.na(margin)) {
    basis <- "logged_model_margin"
  } else if (!is.na(win_prob)) {
    # Inverse of this repo's documented margin -> win-prob map (config.R MARGIN_SIGMA).
    margin <- qnorm(min(max(win_prob, 1e-6), 1 - 1e-6)) * MARGIN_SIGMA
    basis <- "margin_from_logged_win_prob"
  }

  entry <- list(
    game_id = as.character(g$game_id),
    slate = as.integer(g$slate),
    game_date = format(g$game_date, "%Y-%m-%d"),
    weekday = format(g$game_date, "%a"),
    season = as.integer(g$season),
    home_team = home_abbr,
    away_team = away_abbr,
    home_team_name = as.character(g$home_team),
    away_team_name = as.character(g$away_team),
    is_completed = is_completed,
    projection_basis = basis,
    predicted_margin = num_or_null(margin, 2),
    predicted_home_win_prob = num_or_null(win_prob, 4),
    predicted_away_win_prob = if (is.na(win_prob)) NULL else round(1 - win_prob, 4),
    predicted_winner = if (is.na(win_prob)) NULL else if (win_prob >= 0.5) home_abbr else away_abbr,
    # Result fields are populated for completed games ONLY; pending games emit null.
    home_score = if (is_completed) as.integer(g$box_home_score) else NULL,
    away_score = if (is_completed) as.integer(g$box_away_score) else NULL,
    actual_margin = if (is_completed) as.integer(g$box_home_score - g$box_away_score) else NULL,
    actual_winner = if (is_completed) {
      if (g$box_home_score >= g$box_away_score) home_abbr else away_abbr
    } else NULL,
    # Taken verbatim from the accuracy log's own `correct` column, never regraded.
    prediction_correct = if (is_completed) as.logical(g$correct) else NULL
  )
  matchups[[i]] <- entry
}

n_completed <- sum(vapply(matchups, function(m) isTRUE(m$is_completed), logical(1)))
n_pending <- length(matchups) - n_completed
cat(sprintf(">>> %d completed (graded) games, %d pending games\n", n_completed, n_pending))

# ------------------------------------------------------------------------------
# 5. Slate summaries, including per-slate accuracy over GRADED games only
# ------------------------------------------------------------------------------
slate_ids <- sort(unique(vapply(matchups, function(m) m$slate, integer(1))))
active_slate <- {
  in_today <- slate_bounds$slate[slate_bounds$start_date <= today & slate_bounds$end_date >= today]
  if (length(in_today) > 0) {
    as.integer(min(in_today))
  } else {
    pending_slates <- vapply(
      Filter(function(m) !isTRUE(m$is_completed), matchups),
      function(m) m$slate, integer(1)
    )
    if (length(pending_slates) > 0) as.integer(min(pending_slates)) else as.integer(max(slate_ids))
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
    graded_total = as.integer(n_graded),
    correct_total = as.integer(n_correct),
    accuracy_pct = if (n_graded > 0) round(100 * n_correct / n_graded, 1) else NULL
  )
})

dataset <- list(
  season = as.integer(season),
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
  slate_granularity = "week_of_season",
  season_start_date = format(season_start, "%Y-%m-%d"),
  active_slate = active_slate,
  available_slates = as.integer(slate_ids),
  total_games = as.integer(length(matchups)),
  completed_games = as.integer(n_completed),
  pending_games = as.integer(n_pending),
  slates = slates,
  matchups = matchups
)

# ------------------------------------------------------------------------------
# 6. Export
# ------------------------------------------------------------------------------
cat(sprintf(">>> Saving matchups cache to: %s\n", CACHE_MATCHUPS))
saveRDS(dataset, CACHE_MATCHUPS)

cat(sprintf(">>> Exporting public JSON for Next.js to: %s\n", CACHE_MATCHUPS_JSON))
write_json(dataset, CACHE_MATCHUPS_JSON, pretty = TRUE, auto_unbox = TRUE, null = "null",
           digits = NA)

cat(sprintf(">>> [SUCCESS] %d games across %d slates (active slate %d); %d graded, %d pending.\n",
            length(matchups), length(slate_ids), active_slate, n_completed, n_pending))
