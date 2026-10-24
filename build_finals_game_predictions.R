# ==============================================================================
# build_finals_game_predictions.R
#
# GitHub issue #94. Builds CACHE_FINALS_GAME_PREDICTIONS: the current season's
# FINALS decomposed into its seven games, one row per game 1..7, each carrying
#
#   * which side hosts it (and therefore which way home-court advantage points),
#   * the conditional probability the home-court side wins it,
#   * the probability the game is PLAYED AT ALL,
#   * the rest / travel state of both sides going into it,
#   * and, for a game already resolved, the actual result beside the forecast.
#
# Consumed by export_web_json.R, which ships it to
# web/public/data/finals_game_predictions_<season>.json for the Finals section of
# the Next.js /bracket-2026 route (the per-SERIES bracket tree on that page is
# issue #92's and is untouched by this script).
#
# ---- NOTHING HERE IS A NEW MODEL ----
# This script surfaces quantities two existing engines already compute:
#
#   1. Home-court advantage and the per-game win probabilities.
#      series_length_distribution() (tools/series_length_predictor.R) has always
#      computed each game's win probability as
#        pnorm((rating_diff +/- WNBA_HCA) / WNBA_MARGIN_SIGMA)
#      with the sign set by PLAYOFF_FORMATS$bo7$home_flags, and has always
#      enumerated the full (wins_high, wins_low) state space exactly. It now
#      returns that per-game table as attr(., "per_game") instead of discarding
#      it, and this script reads it. No Monte Carlo, no re-derivation: both
#      WNBA_HCA and WNBA_MARGIN_SIGMA are read from config.R and neither value is
#      restated here.
#
#   2. Rest and travel. calculate_travel_fatigue() (fatigue_travel_engine.R) is
#      called unchanged, with the real per-team `days_rest` / `is_back_to_back` /
#      `last_played_at` that daily_schedule_ingest() derives into
#      CACHE_WNBA_SCHEDULE (issue #93) -- including for games not yet played,
#      which is exactly why that schedule cache exists. Its `fatigue_drag_pts`
#      output is in points of margin, the same unit as a net rating, so it is
#      applied by subtracting each side's drag from its net rating and running the
#      SAME pnorm formula. The rest-adjusted probability therefore sits BESIDE the
#      HCA-only one rather than replacing it, so a reader can see what rest moved.
#
# P(game played) is deliberately taken from the HCA-only DP and is NOT
# recomputed under the rest adjustment: it describes the shape of the series, and
# re-running a whole series DP per game under per-game fatigue would be a new
# model, which this ticket explicitly excludes.
#
# ---- RESULT STALENESS, SURFACED RATHER THAN HIDDEN ----
# Two sources disagree about what has been played, and both are shipped:
#   * `resultAvailable` -- a real box-score result exists for this game, read off
#     the resolved half of CACHE_PLAYOFF_BRACKET_CURRENT.
#   * `scheduleCompleted` -- the schedule feed marks the game final.
# The box-score cache lags the schedule while a series is in progress (known and
# expected, see issue #94), so a game can be scheduleCompleted with no result yet.
# The page labels that case instead of pretending the game has not happened.
#
# ---- FAIL-SAFE ----
# Every read is file.exists()-guarded and tryCatch-wrapped. Any miss -- no bracket
# artifact, no Finals row, no determined matchup, no seeds, no schedule -- writes a
# zero-row artifact with a labeled `source_note` (and `rest_applied = FALSE` plus a
# reason when only rest is missing), which the web route renders as an empty state
# rather than inventing a hypothetical pairing. Nothing here hard-crashes the
# pipeline.
# ==============================================================================

if (!exists("CACHE_FINALS_GAME_PREDICTIONS") || !exists("WNBA_HCA") ||
    !exists("WNBA_MARGIN_SIGMA") || !exists("CACHE_WNBA_SCHEDULE")) {
  source("config.R")
}

# Source tools/series_length_predictor.R as a LIBRARY: without this env var it
# auto-runs its demo on source, re-simulating every series and writing the
# archived-forecast file this pipeline treats as frozen.
Sys.setenv(WNBA_SERIES_LENGTH_NO_AUTORUN = "1")
if (!exists("series_length_distribution") || !exists("derive_playoff_seeds")) {
  source("tools/series_length_predictor.R")
}
if (!exists("calculate_travel_fatigue")) source("fatigue_travel_engine.R")

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

.LOG_SCRIPT <- "build_finals_game_predictions.R"
message(">>> [FINALS GAMES] Building Finals per-game predictions (HCA + rest + P(played))...")

# The Finals is a best-of-7. The key is a lookup into playoff_simulator.R's
# PLAYOFF_FORMATS, whose home_flags / win_threshold / label are read from there and
# never restated in this file.
FINALS_FORMAT_KEY <- "bo7"

# jsonlite/rlang-style null coalescing, defined locally so this script does not
# depend on which `%||%` happens to be in scope (CLAUDE.md flags app.R's scalar
# redefinition as vector-unsafe).
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# ------------------------------------------------------------------------------
# Empty artifact, written (not skipped) so downstream readers always find real
# data with a stated reason.
# ------------------------------------------------------------------------------
write_empty_finals_artifact <- function(out_path, note, season, rest_note = "") {
  empty <- tibble()
  attr(empty, "season") <- season
  attr(empty, "generated_at") <- Sys.time()
  attr(empty, "matchup") <- NULL
  attr(empty, "rest_applied") <- FALSE
  attr(empty, "rest_note") <- rest_note
  attr(empty, "source_note") <- note
  saveRDS(empty, out_path)
  message(sprintf(">>> [FINALS GAMES] FALLBACK: %s", note))
  invisible(empty)
}

# ------------------------------------------------------------------------------
# Rest / travel inputs for the two Finals sides, per game, from the #93 schedule.
#
# Returns a tibble keyed on (game, team_abbreviation), or NULL on any miss. The
# schedule is long-form (one row per team per scheduled game), which is already
# the shape needed: each side's own days_rest / is_back_to_back / last_played_at
# (the previous game's venue = this trip's travel origin).
#
# Game numbers come from the feed's own `notes_headline` ("WNBA Finals - Game 3",
# "WNBA Finals - Game 6 If Necessary") when it is parseable, and otherwise from
# chronological order within the matchup -- parsed rather than assumed, so a
# reordered or renamed feed degrades to date order instead of mislabeling a game.
# ------------------------------------------------------------------------------
load_finals_schedule_rest <- function(abbr_high, abbr_low, season,
                                      schedule_path = CACHE_WNBA_SCHEDULE) {
  if (!file.exists(schedule_path)) {
    return(list(data = NULL, note = sprintf("Schedule cache not found at %s.", schedule_path)))
  }
  sched <- tryCatch(readRDS(schedule_path), error = function(e) NULL)
  if (is.null(sched) || !is.data.frame(sched) || nrow(sched) == 0) {
    return(list(data = NULL, note = sprintf("Schedule cache %s is unreadable or empty.", basename(schedule_path))))
  }

  needed <- c("game_id", "game_date", "season", "season_type", "is_completed",
              "team_abbreviation", "opponent_team_abbreviation", "is_home",
              "days_rest", "is_back_to_back", "last_played_at")
  if (!all(needed %in% names(sched))) {
    return(list(data = NULL, note = paste(
      "Schedule cache is missing the rest columns this section needs:",
      paste(setdiff(needed, names(sched)), collapse = ", "))))
  }

  rows <- sched %>%
    filter(.data$season == !!season, .data$season_type == 3L,
           .data$team_abbreviation %in% c(abbr_high, abbr_low),
           .data$opponent_team_abbreviation %in% c(abbr_high, abbr_low))

  if (nrow(rows) == 0) {
    return(list(data = NULL, note = sprintf(
      "Schedule cache holds no %d postseason %s-vs-%s games.", season, abbr_high, abbr_low)))
  }

  headline <- if ("notes_headline" %in% names(rows)) as.character(rows$notes_headline) else rep("", nrow(rows))
  parsed_game <- suppressWarnings(as.integer(sub(".*[Gg]ame\\s*([1-7]).*", "\\1", headline)))
  parsed_game[!grepl("[Gg]ame\\s*[1-7]", headline)] <- NA_integer_

  rows <- rows %>% mutate(game = parsed_game)

  # Fall back to chronological order when the headline did not name a game number.
  if (any(is.na(rows$game))) {
    date_order <- rows %>%
      distinct(.data$game_id, .data$game_date) %>%
      arrange(.data$game_date, .data$game_id) %>%
      mutate(game_by_date = row_number())
    rows <- rows %>%
      left_join(date_order, by = c("game_id", "game_date")) %>%
      mutate(game = dplyr::coalesce(.data$game, .data$game_by_date)) %>%
      select(-"game_by_date")
  }

  rows <- rows %>% filter(!is.na(.data$game), .data$game >= 1, .data$game <= 7)
  if (nrow(rows) == 0) {
    return(list(data = NULL, note = "No Finals game number could be resolved from the schedule."))
  }

  out <- rows %>%
    mutate(
      # Destination = the venue of the scheduled game, i.e. its home team's arena.
      venue_code = if_else(.data$is_home, .data$team_abbreviation, .data$opponent_team_abbreviation),
      # days_rest NA (a team's first game of the season) is treated as rested for the
      # model argument only; is_back_to_back stays as the feed reports it, so no
      # penalty is invented. Same treatment fatigue_travel_engine.R's own real-slate
      # caller applies.
      model_days_rest = dplyr::coalesce(as.numeric(.data$days_rest), 1)
    ) %>%
    rowwise() %>%
    mutate(
      .metrics = list(calculate_travel_fatigue(
        .data$venue_code, .data$last_played_at, .data$model_days_rest, .data$is_back_to_back)),
      travel_miles     = as.numeric(.metrics$travel_miles %||% 0),
      fatigue_drag_pts = as.numeric(.metrics$fatigue_drag_pts %||% 0)
    ) %>%
    ungroup() %>%
    select("game", "game_id", "game_date", "team_abbreviation", "is_home", "is_completed",
           "venue_code", "days_rest", "model_days_rest", "is_back_to_back", "last_played_at",
           "travel_miles", "fatigue_drag_pts") %>%
    arrange(.data$game, desc(.data$is_home))

  list(data = out, note = "")
}

# ------------------------------------------------------------------------------
# Main entry point.
# ------------------------------------------------------------------------------
build_finals_game_predictions <- function(season = CURRENT_SEASON,
                                          out_path = CACHE_FINALS_GAME_PREDICTIONS) {

  # ---- 1. The matchup, off the resolved half of the #92 bracket artifact ----
  if (!file.exists(CACHE_PLAYOFF_BRACKET_CURRENT)) {
    return(write_empty_finals_artifact(out_path, sprintf(
      "%s not found — no Finals matchup is determined, so no per-game forecast is produced.",
      basename(CACHE_PLAYOFF_BRACKET_CURRENT)), season))
  }
  bracket <- tryCatch(readRDS(CACHE_PLAYOFF_BRACKET_CURRENT), error = function(e) NULL)
  if (is.null(bracket) || !is.data.frame(bracket) || nrow(bracket) == 0 ||
      !"round" %in% names(bracket)) {
    return(write_empty_finals_artifact(out_path, sprintf(
      "%s is unreadable or holds no series — no Finals matchup is determined.",
      basename(CACHE_PLAYOFF_BRACKET_CURRENT)), season))
  }

  fin <- bracket[!is.na(bracket$round) & bracket$round == "Finals", ]
  if (nrow(fin) != 1) {
    return(write_empty_finals_artifact(out_path, sprintf(
      paste("No single Finals series is present in %s (%d candidate rows). The Finals matchup is",
            "not yet determined; no hypothetical pairing is invented."),
      basename(CACHE_PLAYOFF_BRACKET_CURRENT), nrow(fin)), season))
  }
  fin <- fin[1, ]

  # ---- 2. Seeds: who holds home court, and both sides' net ratings ----
  # season_type == 2 only, so the postseason games being decomposed here do not
  # feed the ratings used to decompose them (the same leak-free basis #92's Round 1
  # reconstruction uses).
  seeds <- tryCatch(derive_playoff_seeds(season_yr = season, season_type_filter = 2L),
                    error = function(e) NULL)
  if (is.null(seeds) || nrow(seeds) == 0) {
    return(write_empty_finals_artifact(out_path, paste(
      "Regular-season seeds could not be derived, so neither side's net rating nor",
      "home-court holder is known — no per-game forecast is produced."), season))
  }

  s_a <- seeds %>% filter(.data$abbr == fin$team_a_abb)
  s_b <- seeds %>% filter(.data$abbr == fin$team_b_abb)
  if (nrow(s_a) == 0 || nrow(s_b) == 0) {
    return(write_empty_finals_artifact(out_path, sprintf(
      "No derived regular-season seed for %s or %s — no per-game forecast is produced.",
      fin$team_a_abb, fin$team_b_abb), season))
  }

  high <- if (s_a$seed[1] <= s_b$seed[1]) s_a else s_b
  low  <- if (s_a$seed[1] <= s_b$seed[1]) s_b else s_a
  abbr_high <- as.character(high$abbr[1]); abbr_low <- as.character(low$abbr[1])
  net_high  <- as.numeric(high$net_adj[1]); net_low <- as.numeric(low$net_adj[1])

  # ---- 3. Per-game HCA table, read off the exact DP ----
  dist <- series_length_distribution(high$team[1], low$team[1], net_high, net_low,
                                     format = FINALS_FORMAT_KEY)
  per_game <- attr(dist, "per_game")
  if (is.null(per_game) || nrow(per_game) == 0) {
    return(write_empty_finals_artifact(out_path, paste(
      "series_length_distribution() returned no per-game breakdown — the Finals",
      "per-game section cannot be built."), season))
  }

  fmt <- PLAYOFF_FORMATS[[FINALS_FORMAT_KEY]]

  # ---- 4. Rest, per game, from the #93 schedule ----
  rest <- load_finals_schedule_rest(abbr_high, abbr_low, season)
  rest_applied <- !is.null(rest$data)
  rest_note <- if (rest_applied) "" else paste(
    "Rest and travel are NOT applied: ", rest$note,
    " The per-game numbers below are home-court-advantage only.", sep = "")
  if (!rest_applied) message(sprintf(">>> [FINALS GAMES] %s", rest_note))

  # ---- 5. Actual results, from the resolved half of the bracket artifact ----
  # Ordered by date and indexed to game number, which is how a best-of-7's games
  # are numbered. Scores are re-keyed from the artifact's team_a/team_b onto
  # high/low so every row of the output speaks one orientation.
  games_raw <- fin$games[[1]]
  played <- tibble(game = integer(0), game_date = as.Date(character(0)),
                   score_high = integer(0), score_low = integer(0))
  if (is.list(games_raw) && length(games_raw) > 0) {
    pg <- lapply(games_raw, function(gm) {
      a_is_high <- identical(as.character(gm$team_a), as.character(high$team[1]))
      tibble(
        game_date  = as.Date(gm$game_date),
        score_high = as.integer(if (a_is_high) gm$score_a else gm$score_b),
        score_low  = as.integer(if (a_is_high) gm$score_b else gm$score_a)
      )
    })
    played <- bind_rows(pg) %>% arrange(.data$game_date) %>% mutate(game = row_number())
  }

  # ---- 6. Assemble one row per game 1..7 ----
  rows <- lapply(seq_len(nrow(per_game)), function(g) {
    pgrow <- per_game[g, ]
    host_is_high <- isTRUE(pgrow$host_is_high_seed)
    host_abbr <- if (host_is_high) abbr_high else abbr_low
    host_name <- if (host_is_high) as.character(high$team[1]) else as.character(low$team[1])

    # Rest inputs for each side of THIS game.
    r_high <- if (rest_applied) rest$data %>% filter(.data$game == g, .data$team_abbreviation == abbr_high) else NULL
    r_low  <- if (rest_applied) rest$data %>% filter(.data$game == g, .data$team_abbreviation == abbr_low)  else NULL
    have_rest <- !is.null(r_high) && nrow(r_high) == 1 && !is.null(r_low) && nrow(r_low) == 1

    drag_high <- if (have_rest) as.numeric(r_high$fatigue_drag_pts[1]) else 0
    drag_low  <- if (have_rest) as.numeric(r_low$fatigue_drag_pts[1])  else 0

    # Rest-adjusted probability: the SAME formula the DP uses, with each side's
    # fatigue drag (in points of margin) taken off its net rating. WNBA_HCA and
    # WNBA_MARGIN_SIGMA come from config.R; the HCA sign is the host flag's.
    hca_signed <- pgrow$hca_sign_for_high_seed * WNBA_HCA
    diff_rest  <- (net_high - drag_high) - (net_low - drag_low)
    p_rest     <- pnorm((diff_rest + hca_signed) / WNBA_MARGIN_SIGMA)

    actual <- played %>% filter(.data$game == g)
    has_actual <- nrow(actual) == 1

    sched_date <- if (have_rest) as.character(r_high$game_date[1]) else ""
    sched_done <- if (have_rest) isTRUE(r_high$is_completed[1]) else NA

    list(
      game = as.integer(g),
      game_date = if (has_actual) as.character(actual$game_date[1]) else sched_date,
      host_abbr = host_abbr,
      host_name = host_name,
      host_is_high_seed = host_is_high,
      hca_sign_for_high_seed = as.integer(pgrow$hca_sign_for_high_seed),
      p_high_seed_win_hca = round(as.numeric(pgrow$p_high_seed_win), 6),
      p_low_seed_win_hca  = round(as.numeric(pgrow$p_low_seed_win), 6),
      p_game_played       = round(as.numeric(pgrow$p_game_played), 6),
      rest_applied = have_rest,
      days_rest_high = if (have_rest) as.numeric(r_high$model_days_rest[1]) else NA_real_,
      days_rest_low  = if (have_rest) as.numeric(r_low$model_days_rest[1])  else NA_real_,
      b2b_high = if (have_rest) isTRUE(r_high$is_back_to_back[1]) else NA,
      b2b_low  = if (have_rest) isTRUE(r_low$is_back_to_back[1])  else NA,
      travel_miles_high = if (have_rest) as.numeric(r_high$travel_miles[1]) else NA_real_,
      travel_miles_low  = if (have_rest) as.numeric(r_low$travel_miles[1])  else NA_real_,
      fatigue_drag_high = if (have_rest) round(drag_high, 3) else NA_real_,
      fatigue_drag_low  = if (have_rest) round(drag_low, 3)  else NA_real_,
      p_high_seed_win_rest = if (have_rest) round(p_rest, 6) else NA_real_,
      p_low_seed_win_rest  = if (have_rest) round(1 - p_rest, 6) else NA_real_,
      result_available = has_actual,
      schedule_completed = sched_done,
      score_high = if (has_actual) as.integer(actual$score_high[1]) else NA_integer_,
      score_low  = if (has_actual) as.integer(actual$score_low[1])  else NA_integer_,
      # Prediction vs. result for THIS game. Three-state, like #92's series-level
      # resultStatus: a game not yet resolved has no verdict, and a FALSE there
      # would read as a miss when the game simply has not been played.
      result_status = if (!has_actual) "pending"
        else if ((actual$score_high[1] > actual$score_low[1]) == (pgrow$p_high_seed_win >= 0.5)) "correct"
        else "incorrect"
    )
  })

  out <- bind_rows(lapply(rows, function(r) as_tibble(r)))

  attr(out, "season") <- season
  attr(out, "generated_at") <- Sys.time()
  attr(out, "format_key") <- FINALS_FORMAT_KEY
  attr(out, "format_label") <- fmt$label
  attr(out, "rest_applied") <- rest_applied
  attr(out, "rest_note") <- rest_note
  attr(out, "matchup") <- list(
    team_high = as.character(high$team[1]), team_high_abbr = abbr_high,
    team_low  = as.character(low$team[1]),  team_low_abbr  = abbr_low,
    seed_high = as.integer(high$seed[1]),   seed_low       = as.integer(low$seed[1]),
    net_high_adj = round(net_high, 4),      net_low_adj    = round(net_low, 4),
    wins_high = as.integer(if (identical(fin$team_a_abb, abbr_high)) fin$wins_a else fin$wins_b),
    wins_low  = as.integer(if (identical(fin$team_a_abb, abbr_high)) fin$wins_b else fin$wins_a),
    series_complete = isTRUE(fin$series_complete),
    win_threshold = as.integer(fmt$win_threshold),
    expected_games = round(sum(dist$length * dist$probability), 3)
  )
  attr(out, "length_distribution") <- dist
  attr(out, "source_note") <- sprintf(paste(
    "Live Finals forecast. Matchup and played results derived from %s; per-game",
    "home-court win probabilities and P(game played) read from the exact series-length",
    "DP (no simulation); %s"),
    basename(CACHE_PLAYOFF_BRACKET_CURRENT),
    if (rest_applied) sprintf("rest and travel applied per game from %s.",
                              basename(CACHE_WNBA_SCHEDULE))
    else rest_note)

  saveRDS(out, out_path)
  message(sprintf(">>> [FINALS GAMES] Saved %s (%d games, %s vs %s, rest_applied = %s).",
                  out_path, nrow(out), abbr_high, abbr_low, rest_applied))
  invisible(out)
}

if (!interactive()) {
  invisible(build_finals_game_predictions())
}
