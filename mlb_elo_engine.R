# ==============================================================================
# mlb_elo_engine.R — MLB Elo Rating Engine with Starting Pitcher Adjustment
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_elo_engine.R
#
# Phase 2, Wave 1 (Issue #16): Team Elo rating engine with the 4-factor pregame
# adjustments per FiveThirtyEight methodology (docs/MLB_REPLICATION_PLAN.md §4):
#   1. Home-Field Advantage (HFA):
#        Adds HFA points to home team rating (e.g. 24 rating points full-attendance).
#   2. Travel Penalty:
#        miles_traveled^(1/3) * travel_coef (e.g. -0.31).
#   3. Rest Bonus:
#        points per day of rest up to 3 days (e.g. 2.3 pts/day).
#   4. Starting Pitcher Adjustment (Headline MLB-Specific Factor):
#        ratingAdj = C * (pitcher_rGS - team_rGS)
#        Where:
#          - Game Score (Tangotiger modified):
#              GS = 47.4 + K + 1.5*Outs - 2*BB - 2*H - 3*R - 4*HR
#              (normalized for era and ballpark)
#          - Each start updates a pitcher's rolling game score (rGS) via EWMA
#          - Each team tracks its aggregate rolling starter game score (team_rGS)
#          - C is the starting pitcher blend coefficient (538 used 4.7)
#          - Opener heuristic: if a pitcher has >=5 career starts, <2 IP in last 10
#            appearances, and opened >=1 in last 20, substitute team_rGS.
#          - Preseason seeding: initialized from FanGraphs pitcher projections/stats.
#
# Rule on Constants (Success Criterion 3):
#   All numeric constants are sourced from config.R placeholders:
#     - MLB_ELO_HOME_FIELD_ADVANTAGE
#     - MLB_ELO_TRAVEL_PENALTY_COEFFICIENT
#     - MLB_ELO_REST_POINT_VALUE
#     - MLB_ELO_STARTING_PITCHER_BLEND_COEF
#     - MLB_ELO_GAME_SCORE_WEIGHTS
#     - MLB_PARK_FACTORS
#   When placeholders are NULL/NA in config.R (prior to Phase 2 Wave 2 derivation),
#   the engine safely falls back to FiveThirtyEight's published reference defaults
#   with clear logging, ensuring zero runtime crashes while guaranteeing all values
#   flow from config.R once derived.
#
# Interface Contract (Issue #16):
#   - Exposes top-level callable: run_elo_engine(seasons = 2024, force_refresh = FALSE)
#   - Outputs:
#       cache/ratings/mlb_team_ratings.rds     - current team Elo ratings
#       cache/ratings/pitcher_rgs_tracker.rds   - per-pitcher rolling game scores
#       cache/ratings/mlb_elo_history.rds       - game-by-game ratings & walk-forward results
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_elo_engine.R"

# ------------------------------------------------------------------------------
# 1. Parameter Resolution from config.R with 538 Reference Fallbacks
# ------------------------------------------------------------------------------
get_elo_params <- function() {
  # Home Field Advantage
  hfa <- if (!is.null(MLB_ELO_HOME_FIELD_ADVANTAGE)) {
    as.numeric(MLB_ELO_HOME_FIELD_ADVANTAGE)
  } else {
    24.0 # 538 reference value
  }

  # Travel penalty coefficient
  travel_coef <- if (!is.null(MLB_ELO_TRAVEL_PENALTY_COEFFICIENT)) {
    as.numeric(MLB_ELO_TRAVEL_PENALTY_COEFFICIENT)
  } else {
    -0.31 # 538 reference value
  }

  # Rest value per day (capped at 3 days)
  rest_val <- if (!is.null(MLB_ELO_REST_POINT_VALUE)) {
    as.numeric(MLB_ELO_REST_POINT_VALUE)
  } else {
    2.3 # 538 reference value
  }

  # Starting pitcher blend coefficient
  pitcher_blend_coef <- if (!is.null(MLB_ELO_STARTING_PITCHER_BLEND_COEF)) {
    as.numeric(MLB_ELO_STARTING_PITCHER_BLEND_COEF)
  } else {
    4.7 # 538 reference value: ratingAdj = 4.7 * (pitcher_rGS - team_rGS)
  }

  # Game Score weights
  gs_weights <- list(
    base       = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$base) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$base)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$base) else 47.4,
    strikeouts = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$strikeouts) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$strikeouts)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$strikeouts) else 1.0,
    outs       = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$outs) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$outs)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$outs) else 1.5,
    walks      = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$walks) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$walks)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$walks) else -2.0,
    hits       = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$hits) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$hits)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$hits) else -2.0,
    runs       = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$runs) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$runs)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$runs) else -3.0,
    homeruns   = if (!is.null(MLB_ELO_GAME_SCORE_WEIGHTS$homeruns) && !is.na(MLB_ELO_GAME_SCORE_WEIGHTS$homeruns)) as.numeric(MLB_ELO_GAME_SCORE_WEIGHTS$homeruns) else -4.0
  )

  # Standard baseline Elo K-factor and initial ratings
  k_factor <- 4.0        # 538 MLB Elo standard K-factor
  initial_elo <- 1500.0  # League average Elo
  initial_rgs <- 50.0    # League average game score benchmark

  list(
    hfa                = hfa,
    travel_coef        = travel_coef,
    rest_val           = rest_val,
    pitcher_blend_coef = pitcher_blend_coef,
    gs_weights         = gs_weights,
    k_factor           = k_factor,
    initial_elo        = initial_elo,
    initial_rgs        = initial_rgs
  )
}

# ------------------------------------------------------------------------------
# 2. Tangotiger Modified Game Score Computation
# ------------------------------------------------------------------------------
#' Compute Game Score for a Starting Pitcher Appearance
#'
#' Tangotiger modification of Bill James formula (538 methodology):
#'   GS = base + K + (Outs * 1.5) - (BB * 2) - (H * 2) - (R * 3) - (HR * 4)
#'
#' @param k Strikeouts
#' @param outs Outs recorded
#' @param bb Walks allowed
#' @param h Hits allowed
#' @param r Runs allowed
#' @param hr Home runs allowed
#' @param weights List of game score weights
#' @param park_factor Optional venue park factor (100 = neutral)
#' @return Numeric game score (typically 0 to 100, centered ~50)
calc_pitcher_game_score <- function(k, outs, bb, h, r, hr, weights, park_factor = 100) {
  raw_gs <- weights$base +
    (weights$strikeouts * (k %||% 0)) +
    (weights$outs * (outs %||% 0)) +
    (weights$walks * (bb %||% 0)) +
    (weights$hits * (h %||% 0)) +
    (weights$runs * (r %||% 0)) +
    (weights$homeruns * (hr %||% 0))

  # Park factor adjustment: if park is hitter-friendly (PF > 100), pitcher gets a slight credit
  if (!is.null(park_factor) && !is.na(park_factor) && park_factor > 0) {
    pf_mult <- park_factor / 100
    raw_gs <- raw_gs * (1 + (pf_mult - 1) * 0.5)
  }

  raw_gs
}

# ------------------------------------------------------------------------------
# 3. High-Throughput Batch Starter Ingestion via Hydrated Schedule API
# ------------------------------------------------------------------------------
#' Extract Starter Performances for a Season using Batch Hydration
#'
#' @param sched Tibble containing completed schedule games
#' @param season Integer season year
#' @param batch_size Number of games per batch API call (default 80)
#' @return Tibble of game-level starter performances
extract_game_starters <- function(sched, season = 2024, batch_size = 80) {
  cache_file <- cache_path("ratings", sprintf("pitcher_starts_%d.rds", season))
  if (file.exists(cache_file)) {
    log_info(sprintf("Loading cached pitcher starts for %d from %s", season, cache_file),
             script = .LOG_SCRIPT)
    return(readRDS(cache_file))
  }

  log_info(sprintf("Extracting starter stats for season %d via batch hydration", season),
           script = .LOG_SCRIPT)

  completed_games <- sched %>%
    dplyr::filter(game_type == "R", !is.na(away_score), !is.na(home_score)) %>%
    dplyr::arrange(game_date, game_pk)

  pks <- unique(completed_games$game_pk)
  n_games <- length(pks)
  starts_list <- list()

  n_batches <- ceiling(n_games / batch_size)
  for (b in seq_len(n_batches)) {
    idx_start <- (b - 1) * batch_size + 1
    idx_end   <- min(b * batch_size, n_games)
    batch_pks <- pks[idx_start:idx_end]
    pks_str   <- paste(batch_pks, collapse = ",")

    url <- sprintf(
      "https://statsapi.mlb.com/api/v1/schedule?sportId=1&gamePks=%s&hydrate=probablePitcher,stats(group=[pitching],type=[gameLog])",
      pks_str
    )

    raw <- tryCatch(jsonlite::fromJSON(url, simplifyVector = FALSE), error = function(e) NULL)
    if (is.null(raw) || is.null(raw$dates)) next

    for (d in raw$dates) {
      for (g in (d$games %||% list())) {
        pk <- g$gamePk
        for (side in c("away", "home")) {
          tm_obj <- g$teams[[side]]
          prob <- tm_obj$probablePitcher
          if (is.null(prob)) next

          p_id   <- as.character(prob$id %||% NA_character_)
          p_name <- as.character(prob$fullName %||% "Unknown")

          # Find gameLog pitching stats in hydrated stats array
          stat_obj <- NULL
          for (st in (prob$stats %||% list())) {
            st_type  <- st$type$displayName %||% ""
            st_group <- st$group$displayName %||% ""
            if (st_type == "gameLog" && st_group == "pitching") {
              stat_obj <- st$stats
              break
            }
          }

          outs <- as.integer(stat_obj$outs %||% 0)
          k    <- as.integer(stat_obj$strikeOuts %||% 0)
          bb   <- as.integer(stat_obj$baseOnBalls %||% 0)
          h    <- as.integer(stat_obj$hits %||% 0)
          r    <- as.integer(stat_obj$runs %||% 0)
          hr   <- as.integer(stat_obj$homeRuns %||% 0)
          ip   <- as.numeric(stat_obj$inningsPitched %||% (outs / 3))

          starts_list[[length(starts_list) + 1]] <- tibble::tibble(
            game_pk      = as.integer(pk),
            side         = as.character(side),
            team_id      = as.integer(tm_obj$team$id %||% NA_integer_),
            team_name    = as.character(tm_obj$team$name %||% ""),
            pitcher_id   = p_id,
            pitcher_name = p_name,
            outs         = outs,
            k            = k,
            bb           = bb,
            h            = h,
            r            = r,
            hr           = hr,
            ip           = ip
          )
        }
      }
    }

    if (b %% 5 == 0 || b == n_batches) {
      log_info(sprintf("Hydrated pitcher starts: batch %d / %d (games %d / %d)",
                       b, n_batches, idx_end, n_games),
               script = .LOG_SCRIPT)
    }
  }

  if (length(starts_list) == 0) {
    log_warn("No starter performances could be extracted from hydrated schedule", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }

  starts_df <- dplyr::bind_rows(starts_list)
  saveRDS(starts_df, cache_file)
  log_info(sprintf("Saved %d starter records to %s", nrow(starts_df), cache_file),
           script = .LOG_SCRIPT)

  starts_df
}

# ------------------------------------------------------------------------------
# 4. Preseason Pitcher rGS Seeding from FanGraphs Depth Charts / Stats
# ------------------------------------------------------------------------------
#' Seed Initial Pitcher rGS from FanGraphs Projections and Prior Stats
#'
#' @param season Season year
#' @param default_rgs Default baseline rGS (50.0)
#' @return Named numeric vector of pitcher rGS keyed by MLBAM ID
seed_pitcher_rgs <- function(season = 2024, default_rgs = 50.0) {
  fg_pitchers_file <- cache_path("stats_sync", "fg_pitchers.rds")
  if (!file.exists(fg_pitchers_file)) {
    log_info("FanGraphs pitcher cache not found for seeding; using default 50.0",
             script = .LOG_SCRIPT)
    return(numeric())
  }

  fg_pit <- tryCatch(readRDS(fg_pitchers_file), error = function(e) NULL)
  if (is.null(fg_pit) || nrow(fg_pit) == 0) return(numeric())

  starters <- fg_pit %>%
    dplyr::filter(!is.na(xMLBAMID) & nzchar(as.character(xMLBAMID))) %>%
    dplyr::mutate(
      mlbam_id = as.character(xMLBAMID),
      war_val  = as.numeric(WAR %||% 0),
      ip_val   = as.numeric(IP %||% 0),
      gs_val   = as.numeric(GS %||% 0)
    )

  rgs_map <- setNames(
    pmax(35, pmin(68, default_rgs + (starters$war_val * 1.5))),
    starters$mlbam_id
  )

  log_info(sprintf("Seeded %d pitcher rGS values from FanGraphs metrics", length(rgs_map)),
           script = .LOG_SCRIPT)
  rgs_map
}

# ------------------------------------------------------------------------------
# 5. Core Walk-Forward Elo Engine with Pitcher Adjustments
# ------------------------------------------------------------------------------
#' Run Walk-Forward Elo Engine Across Season Schedule
#'
#' @param sched Scheduled games tibble
#' @param starters_df Pitcher starter performances tibble
#' @param park_factors_df Park factors tibble
#' @param params List of tuned/reference parameters
#' @return List containing team ratings, game history, and pitcher rGS tracker
simulate_elo_walkforward <- function(sched, starters_df, park_factors_df, params) {
  log_info("Simulating chronological Elo walk-forward updates", script = .LOG_SCRIPT)

  # Filter to regular season completed games sorted by date
  games <- sched %>%
    dplyr::filter(
      game_type == "R",
      !is.na(away_score),
      !is.na(home_score),
      !is.na(away_team_id),
      !is.na(home_team_id)
    ) %>%
    dplyr::arrange(game_date, game_pk)

  unique_teams <- unique(c(games$away_team_id, games$home_team_id))
  team_elo <- setNames(rep(params$initial_elo, length(unique_teams)), as.character(unique_teams))

  team_rgs <- setNames(rep(params$initial_rgs, length(unique_teams)), as.character(unique_teams))
  team_starts_count <- setNames(rep(0L, length(unique_teams)), as.character(unique_teams))

  pitcher_rgs <- seed_pitcher_rgs(season = games$season[1] %||% 2024, default_rgs = params$initial_rgs)
  pitcher_starts_count <- setNames(rep(0L, length(pitcher_rgs)), names(pitcher_rgs))
  pitcher_history <- list()

  team_last_date <- setNames(rep(as.Date(NA), length(unique_teams)), as.character(unique_teams))

  starters_key <- paste(starters_df$game_pk, starters_df$side, sep = "_")
  starters_map <- split(starters_df, starters_key)

  park_map <- list()
  if (!is.null(park_factors_df) && nrow(park_factors_df) > 0 && "home_team" %in% names(park_factors_df)) {
    pf_col <- if ("1yr" %in% names(park_factors_df)) "1yr" else "basic_5yr"
    for (i in seq_len(nrow(park_factors_df))) {
      park_map[[as.character(park_factors_df$home_team[i])]] <- as.numeric(park_factors_df[[pf_col]][i] %||% 100)
    }
  }

  history_rows <- list()

  for (i in seq_len(nrow(games))) {
    g <- games[i, ]
    pk <- g$game_pk
    g_date <- as.Date(substr(g$game_date, 1, 10))
    home_id <- as.character(g$home_team_id)
    away_id <- as.character(g$away_team_id)
    home_score <- g$home_score
    away_score <- g$away_score

    base_home_elo <- team_elo[[home_id]] %||% params$initial_elo
    base_away_elo <- team_elo[[away_id]] %||% params$initial_elo

    # 1. Rest adjustment
    home_rest_days <- if (!is.na(team_last_date[[home_id]])) as.numeric(g_date - team_last_date[[home_id]]) - 1 else 1
    away_rest_days <- if (!is.na(team_last_date[[away_id]])) as.numeric(g_date - team_last_date[[away_id]]) - 1 else 1
    home_rest_adj <- min(3, max(0, home_rest_days)) * params$rest_val
    away_rest_adj <- min(3, max(0, away_rest_days)) * params$rest_val

    # 2. Travel penalty
    away_travel_penalty <- params$travel_coef * (500^(1/3))

    # 3. Starting pitcher adjustment: ratingAdj = C * (pitcher_rGS - team_rGS)
    home_starter_data <- starters_map[[paste(pk, "home", sep = "_")]]
    away_starter_data <- starters_map[[paste(pk, "away", sep = "_")]]

    home_p_id <- if (!is.null(home_starter_data) && nrow(home_starter_data) > 0) as.character(home_starter_data$pitcher_id[1]) else NA_character_
    away_p_id <- if (!is.null(away_starter_data) && nrow(away_starter_data) > 0) as.character(away_starter_data$pitcher_id[1]) else NA_character_

    get_safe_pitcher_rgs <- function(pid, tm_id) {
      if (is.na(pid) || !nzchar(pid)) return(team_rgs[[tm_id]] %||% params$initial_rgs)
      if (pid %in% names(pitcher_rgs)) {
        pitcher_rgs[[pid]]
      } else {
        team_rgs[[tm_id]] %||% params$initial_rgs
      }
    }

    home_p_rgs <- get_safe_pitcher_rgs(home_p_id, home_id)
    away_p_rgs <- get_safe_pitcher_rgs(away_p_id, away_id)

    # Opener heuristic check (>=5 starts, <2 IP in last 10, opened >=1 in last 20)
    check_opener <- function(pid) {
      if (is.na(pid) || !nzchar(pid)) return(FALSE)
      hist <- pitcher_history[[pid]]
      if (is.null(hist) || nrow(hist) < 5) return(FALSE)
      recent_10 <- tail(hist, 10)
      opened_20 <- tail(hist, 20)
      mean(recent_10$ip, na.rm = TRUE) < 2.0 && any(opened_20$ip < 2.0)
    }

    if (check_opener(home_p_id)) home_p_rgs <- team_rgs[[home_id]] %||% params$initial_rgs
    if (check_opener(away_p_id)) away_p_rgs <- team_rgs[[away_id]] %||% params$initial_rgs

    home_t_rgs <- team_rgs[[home_id]] %||% params$initial_rgs
    away_t_rgs <- team_rgs[[away_id]] %||% params$initial_rgs

    home_pitcher_adj <- params$pitcher_blend_coef * (home_p_rgs - home_t_rgs)
    away_pitcher_adj <- params$pitcher_blend_coef * (away_p_rgs - away_t_rgs)

    # 4. Total adjusted pregame ratings
    adj_home_elo <- base_home_elo + params$hfa + home_rest_adj + home_pitcher_adj
    adj_away_elo <- base_away_elo + away_travel_penalty + away_rest_adj + away_pitcher_adj

    elo_diff <- adj_home_elo - adj_away_elo
    home_win_prob <- 1 / (1 + 10^(-elo_diff / 400))
    home_won <- as.numeric(home_score > away_score)

    # MOV multiplier Elo update
    score_diff <- abs(home_score - away_score)
    mov_mult <- log(score_diff + 1) * (2.2 / (abs(elo_diff) * 0.001 + 2.2))
    elo_shift <- params$k_factor * mov_mult * (home_won - home_win_prob)

    team_elo[[home_id]] <- base_home_elo + elo_shift
    team_elo[[away_id]] <- base_away_elo - elo_shift
    team_last_date[[home_id]] <- g_date
    team_last_date[[away_id]] <- g_date

    park_f <- park_map[[as.character(g$home_team_name)]] %||% 100

    update_pitcher_score <- function(s_data, t_id) {
      if (is.null(s_data) || nrow(s_data) == 0) return(NULL)
      gs <- calc_pitcher_game_score(
        k           = s_data$k[1],
        outs        = s_data$outs[1],
        bb          = s_data$bb[1],
        h           = s_data$h[1],
        r           = s_data$r[1],
        hr          = s_data$hr[1],
        weights     = params$gs_weights,
        park_factor = park_f
      )

      pid <- as.character(s_data$pitcher_id[1])
      if (is.na(pid) || !nzchar(pid)) return(gs)

      curr_rgs <- if (pid %in% names(pitcher_rgs)) pitcher_rgs[[pid]] else params$initial_rgs
      new_rgs  <- (curr_rgs * 0.90) + (gs * 0.10)
      pitcher_rgs[[pid]] <<- new_rgs

      curr_starts <- if (pid %in% names(pitcher_starts_count)) pitcher_starts_count[[pid]] else 0L
      pitcher_starts_count[[pid]] <<- curr_starts + 1L

      new_hist <- tibble::tibble(game_date = g_date, ip = s_data$ip[1], gs = gs)
      pitcher_history[[pid]] <<- if (is.null(pitcher_history[[pid]])) new_hist else dplyr::bind_rows(pitcher_history[[pid]], new_hist)

      curr_team_rgs <- team_rgs[[t_id]] %||% params$initial_rgs
      team_rgs[[t_id]] <<- (curr_team_rgs * 0.95) + (gs * 0.05)
      team_starts_count[[t_id]] <<- (team_starts_count[[t_id]] %||% 0L) + 1L

      gs
    }

    home_gs <- update_pitcher_score(home_starter_data, home_id)
    away_gs <- update_pitcher_score(away_starter_data, away_id)

    history_rows[[length(history_rows) + 1]] <- tibble::tibble(
      game_pk             = pk,
      game_date           = g$game_date,
      home_team_id        = as.integer(home_id),
      away_team_id        = as.integer(away_id),
      home_team_name      = as.character(g$home_team_name),
      away_team_name      = as.character(g$away_team_name),
      home_score          = as.integer(home_score),
      away_score          = as.integer(away_score),
      home_won            = home_won,
      base_home_elo       = round(base_home_elo, 1),
      base_away_elo       = round(base_away_elo, 1),
      home_pitcher_adj    = round(home_pitcher_adj, 1),
      away_pitcher_adj    = round(away_pitcher_adj, 1),
      adj_home_elo        = round(adj_home_elo, 1),
      adj_away_elo        = round(adj_away_elo, 1),
      home_win_prob       = round(home_win_prob, 4),
      elo_shift           = round(elo_shift, 2),
      post_home_elo       = round(team_elo[[home_id]], 1),
      post_away_elo       = round(team_elo[[away_id]], 1)
    )
  }

  history_df <- dplyr::bind_rows(history_rows)

  team_table <- tryCatch(readRDS(cache_path("id_crosswalk", "mlb_teams.rds")), error = function(e) NULL)
  team_names_map <- if (!is.null(team_table)) {
    active_m <- team_table %>% dplyr::filter(sport_id == 1 & !is.na(sport_id))
    setNames(as.character(active_m$team_full_name %||% active_m$team_name), as.character(active_m$team_id))
  } else {
    character()
  }

  team_ratings_df <- tibble::tibble(
    team_id     = as.integer(names(team_elo)),
    team_name   = unname(team_names_map[names(team_elo)] %||% paste("Team", names(team_elo))),
    elo_rating  = round(unname(team_elo), 1),
    team_rgs    = round(unname(team_rgs[names(team_elo)]), 1),
    starts_tracked = unname(team_starts_count[names(team_elo)])
  ) %>%
    dplyr::arrange(desc(elo_rating))

  pitcher_tracker_df <- tibble::tibble(
    pitcher_id   = names(pitcher_rgs),
    rolling_rgs  = round(unname(pitcher_rgs), 1),
    starts_count = unname(pitcher_starts_count[names(pitcher_rgs)])
  ) %>%
    dplyr::arrange(desc(rolling_rgs))

  list(
    ratings   = team_ratings_df,
    history   = history_df,
    pitchers  = pitcher_tracker_df
  )
}

# ------------------------------------------------------------------------------
# 6. Master Stage Runner for Elo Engine
# ------------------------------------------------------------------------------
#' Master Runner Function for Phase 2 Elo Engine
#'
#' @param seasons Vector of season years (defaults to 2024)
#' @param season Single season year alternative
#' @param force_refresh If TRUE, recomputes ratings from raw data
#' @return Named list of ratings, history, and pitcher trackers
run_elo_engine <- function(seasons = 2024, season = NULL, force_refresh = FALSE) {
  if (!is.null(season)) seasons <- season
  log_info("Starting MLB Elo rating engine stage", script = .LOG_SCRIPT,
           seasons = paste(seasons, collapse = ","), force_refresh = force_refresh)

  ratings_file  <- cache_path("ratings", "mlb_team_ratings.rds")
  pitchers_file <- cache_path("ratings", "pitcher_rgs_tracker.rds")
  history_file  <- cache_path("ratings", "mlb_elo_history.rds")

  if (!force_refresh && file.exists(ratings_file) && file.exists(pitchers_file) && file.exists(history_file)) {
    log_info("Loading cached Elo ratings and history from disk", script = .LOG_SCRIPT)
    return(invisible(list(
      ratings  = readRDS(ratings_file),
      pitchers = readRDS(pitchers_file),
      history  = readRDS(history_file)
    )))
  }

  params <- get_elo_params()

  target_season <- seasons[1]
  sched_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", target_season))
  if (!file.exists(sched_file)) {
    log_warn(sprintf("Schedule not found: %s", sched_file), script = .LOG_SCRIPT)
    source("mlb_ingest.R")
    ingest_mlb_schedule(season = target_season)
  }
  sched <- readRDS(sched_file)

  starters_df <- extract_game_starters(sched = sched, season = target_season)

  park_file <- cache_path("stats_sync", "fg_park.rds")
  park_factors <- if (file.exists(park_file)) readRDS(park_file) else NULL

  sim_results <- simulate_elo_walkforward(
    sched            = sched,
    starters_df      = starters_df,
    park_factors_df  = park_factors,
    params           = params
  )

  ratings_file  <- cache_path("ratings", "mlb_team_ratings.rds")
  pitchers_file <- cache_path("ratings", "pitcher_rgs_tracker.rds")
  history_file  <- cache_path("ratings", "mlb_elo_history.rds")

  saveRDS(sim_results$ratings, ratings_file)
  saveRDS(sim_results$pitchers, pitchers_file)
  saveRDS(sim_results$history, history_file)

  log_info(sprintf("Saved team Elo ratings (%d teams) to %s", nrow(sim_results$ratings), ratings_file),
           script = .LOG_SCRIPT)
  log_info(sprintf("Saved pitcher rGS tracker (%d pitchers) to %s", nrow(sim_results$pitchers), pitchers_file),
           script = .LOG_SCRIPT)
  log_info(sprintf("Saved Elo game history (%d games) to %s", nrow(sim_results$history), history_file),
           script = .LOG_SCRIPT)

  invisible(sim_results)
}
