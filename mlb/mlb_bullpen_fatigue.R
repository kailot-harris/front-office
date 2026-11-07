# ==============================================================================
# mlb_bullpen_fatigue.R — Relief-Pitcher Fatigue & Workload Signal Engine
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_bullpen_fatigue.R
#
# Phase 3: Specialty Models (Issue #18)
#
# Context & Sabermetric Research (docs/MLB_REPLICATION_PLAN.md §5):
#   - Public research analyzing ~33,000 relief appearances (2019/2025) models
#     fatigue as a trailing workload accumulation function:
#       1. Trailing 2-day cumulative pitch count (high arm-stress threshold >= 30)
#       2. Trailing 4-day cumulative pitch count (high arm-stress threshold >= 55)
#       3. Days of rest since last appearance (0 = back-to-back, 1 = 1 day off)
#       4. Consecutive-day appearance streaks (back-to-back or 3 in 3 days)
#       5. Fastball release velocity deviation from seasonal baseline (~0.5 mph drop)
#   - Key Finding: While fatigued relievers measurably throw ~0.5 mph slower,
#     run-scoring outcomes are largely moderated by manager deployment choices.
#     Hence, this engine produces a diagnostic/monitoring signal and bullpen
#     vulnerability index rather than heavily distorting win probabilities directly.
#
# Interface Contract:
#   - Exposes top-level callable: run_bullpen_fatigue(season = 2024, force_refresh = FALSE)
#   - Writes outputs to cache_path("specialty", ...):
#       cache/specialty/bullpen_fatigue_daily.rds
#       cache/specialty/bullpen_team_status.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_bullpen_fatigue.R"

# Fatigue thresholds from sabermetric research
FATIGUE_THRESHOLDS <- list(
  pitch_count_2day_warn = 30L,
  pitch_count_2day_high = 45L,
  pitch_count_4day_warn = 55L,
  pitch_count_4day_high = 75L,
  back_to_back_penalty  = 15.0, # Fatigue index penalty points
  three_in_three_penalty= 35.0, # High risk penalty points
  velo_drop_mph         = 0.5   # Measurable velocity decay indicator
)

#' Extract Relief Pitcher Appearances from Ingested Box Scores
#'
#' @param season Season integer (e.g. 2024)
#' @param force_refresh If TRUE, recomputes from source data
#' @return Tibble of relief appearances with pitch counts and dates
extract_bullpen_appearances <- function(season = 2024, force_refresh = FALSE) {
  cache_file <- cache_path("specialty", sprintf("bullpen_appearances_%d.rds", season))
  if (!force_refresh && file.exists(cache_file)) {
    log_info(sprintf("Loading cached bullpen appearances for %d", season), script = .LOG_SCRIPT)
    return(readRDS(cache_file))
  }

  log_info(sprintf("Extracting bullpen appearances for season %d", season), script = .LOG_SCRIPT)

  sched_file <- cache_path("ingest", sprintf("mlb_schedule_%d.rds", season))
  starters_file <- cache_path("ratings", sprintf("pitcher_starts_%d.rds", season))

  if (!file.exists(sched_file) || !file.exists(starters_file)) {
    log_error("Schedule or starters cache missing for bullpen extraction", script = .LOG_SCRIPT)
    return(tibble::tibble())
  }

  sched <- readRDS(sched_file)
  starters <- readRDS(starters_file)

  completed_games <- sched %>%
    dplyr::filter(game_type == "R", !is.na(away_score), !is.na(home_score)) %>%
    dplyr::transmute(
      game_pk = as.integer(game_pk),
      game_date = as.Date(substr(game_date, 1, 10)),
      home_team_id = as.integer(home_team_id),
      away_team_id = as.integer(away_team_id),
      home_team_name = as.character(home_team_name),
      away_team_name = as.character(away_team_name)
    )

  starter_keys <- paste(starters$game_pk, starters$pitcher_id, sep = "_")

  # Build player ID to name lookup from crosswalk and starter records
  cw_file <- cache_path("id_crosswalk", "mlb_id_crosswalk.rds")
  id_map <- list()
  if (file.exists(cw_file)) {
    cw <- tryCatch(readRDS(cw_file), error = function(e) NULL)
    if (!is.null(cw) && all(c("mlb_id", "full_name") %in% names(cw))) {
      valid_cw <- cw[!is.na(cw$mlb_id) & !is.na(cw$full_name), ]
      id_map <- setNames(as.character(valid_cw$full_name), as.character(valid_cw$mlb_id))
    }
  }
  starter_map <- if ("pitcher_id" %in% names(starters) && "pitcher_name" %in% names(starters)) {
    setNames(as.character(starters$pitcher_name), as.character(starters$pitcher_id))
  } else {
    character(0)
  }

  # Ingest official boxscore pitching lines if present
  box_file <- cache_path("ingest", sprintf("mlb_boxscores_%d.rds", season))
  box_pitchers <- tibble::tibble()
  if (file.exists(box_file)) {
    box_raw <- tryCatch(as.data.frame(readRDS(box_file)), error = function(e) NULL)
    if (!is.null(box_raw)) {
      pid_col <- intersect(c("pitcher_id", "pitcher"), names(box_raw))
      if (length(pid_col) > 0 && "pitches_thrown" %in% names(box_raw)) {
        p_col <- pid_col[1]
        box_pitchers <- box_raw %>%
          dplyr::transmute(
            game_pk        = as.integer(game_pk),
            pitcher_id     = as.character(.data[[p_col]]),
            pitches_thrown = as.integer(pitches_thrown),
            pitcher_name   = if ("pitcher_name" %in% names(box_raw)) as.character(pitcher_name) else NA_character_,
            team           = if ("team_name" %in% names(box_raw)) as.character(team_name) else if ("team" %in% names(box_raw)) as.character(team) else NA_character_
          )
      }
    }
  }

  # Ingest Statcast pitch-level tracking files
  statcast_files <- list.files(cache_path("ingest"), pattern = "^statcast_pitches_.*\\.rds$", full.names = TRUE)
  season_statcast <- grep(as.character(season), statcast_files, value = TRUE)
  files_to_load <- if (length(season_statcast) > 0) season_statcast else statcast_files

  pitches_list <- list()
  for (sf in files_to_load) {
    pdf <- tryCatch(as.data.frame(readRDS(sf)), error = function(e) NULL)
    if (!is.null(pdf) && nrow(pdf) > 0) {
      pitches_list[[length(pitches_list) + 1]] <- pdf
    }
  }
  pitches <- if (length(pitches_list) > 0) dplyr::bind_rows(pitches_list) else tibble::tibble()

  relief_rows <- list()

  if (nrow(pitches) > 0) {
    # Compute empirical seasonal baseline fastball velocity per pitcher (FF = 4-seam, SI = sinker)
    fb_pitches <- pitches %>%
      dplyr::filter(pitch_type %in% c("FF", "SI"), !is.na(release_speed)) %>%
      dplyr::group_by(pitcher) %>%
      dplyr::summarise(
        baseline_velo = mean(release_speed, na.rm = TRUE),
        .groups = "drop"
      ) %>%
      dplyr::mutate(pitcher = as.character(pitcher))

    baseline_map <- setNames(fb_pitches$baseline_velo, fb_pitches$pitcher)

    # Aggregate pitch tracking per game outing
    p_games <- pitches %>%
      dplyr::mutate(
        game_pk_val = as.integer(game_pk),
        pitcher_val = as.character(pitcher),
        side_topbot = as.character(inning_topbot)
      ) %>%
      dplyr::group_by(game_pk_val, pitcher_val) %>%
      dplyr::summarise(
        pitches_thrown = dplyr::n(),
        avg_velo       = mean(release_speed[pitch_type %in% c("FF", "SI")], na.rm = TRUE),
        is_home        = (sum(side_topbot == "Top", na.rm = TRUE) >= sum(side_topbot == "Bot", na.rm = TRUE)),
        home_team_sc   = dplyr::first(home_team),
        away_team_sc   = dplyr::first(away_team),
        game_date      = dplyr::first(game_date),
        .groups        = "drop"
      )

    for (i in seq_len(nrow(p_games))) {
      pg <- p_games[i, ]
      match_key <- paste(pg$game_pk_val, pg$pitcher_val, sep = "_")
      if (match_key %in% starter_keys) next # Skip starting pitchers

      # Fastball velocity deviation vs seasonal baseline
      b_velo <- if (pg$pitcher_val %in% names(baseline_map)) baseline_map[[pg$pitcher_val]] else NA_real_
      if (!is.na(b_velo) && !is.na(pg$avg_velo)) {
        velo_diff <- round(pg$avg_velo - b_velo, 2)
      } else {
        velo_diff <- 0.0
        log_info(sprintf("Statcast fastball velocity tracking unavailable for pitcher %s in game %d; defaulting velo_delta to 0.0",
                         pg$pitcher_val, pg$game_pk_val), script = .LOG_SCRIPT)
      }

      # Resolve official team name and game date from schedule
      gm <- completed_games[completed_games$game_pk == pg$game_pk_val, ]
      team_name <- if (nrow(gm) > 0) {
        if (pg$is_home) gm$home_team_name else gm$away_team_name
      } else {
        if (pg$is_home) pg$home_team_sc else pg$away_team_sc
      }
      g_date <- if (nrow(gm) > 0) gm$game_date else as.Date(pg$game_date)

      # Resolve pitcher name
      pname <- if (pg$pitcher_val %in% names(id_map)) id_map[[pg$pitcher_val]] else NA_character_
      if (is.na(pname) || pname == "") {
        pname <- if (pg$pitcher_val %in% names(starter_map)) starter_map[[pg$pitcher_val]] else NA_character_
      }
      if (is.na(pname) || pname == "") {
        pname <- sprintf("Pitcher %s", pg$pitcher_val)
      }

      relief_rows[[length(relief_rows) + 1]] <- tibble::tibble(
        game_pk        = pg$game_pk_val,
        game_date      = g_date,
        pitcher_id     = pg$pitcher_val,
        pitcher_name   = pname,
        team           = team_name,
        pitches_thrown = as.integer(pg$pitches_thrown),
        velo_delta     = velo_diff
      )
    }
  }

  # Ingest any relief appearances from official boxscores not already covered by Statcast
  if (nrow(box_pitchers) > 0) {
    existing_keys <- if (length(relief_rows) > 0) {
      existing_df <- dplyr::bind_rows(relief_rows)
      paste(existing_df$game_pk, existing_df$pitcher_id, sep = "_")
    } else {
      character(0)
    }

    box_relievers <- box_pitchers %>%
      dplyr::filter(!paste(game_pk, pitcher_id, sep = "_") %in% starter_keys) %>%
      dplyr::filter(!paste(game_pk, pitcher_id, sep = "_") %in% existing_keys)

    if (nrow(box_relievers) > 0) {
      log_info(sprintf("Ingesting %d relief appearances from official boxscores", nrow(box_relievers)),
               script = .LOG_SCRIPT)
      for (k in seq_len(nrow(box_relievers))) {
        br <- box_relievers[k, ]
        gm <- completed_games[completed_games$game_pk == br$game_pk, ]
        g_date <- if (nrow(gm) > 0) gm$game_date else as.Date(NA)
        tm <- if (!is.na(br$team) && br$team != "") br$team else if (nrow(gm) > 0) gm$home_team_name else "Unknown"

        pname <- br$pitcher_name
        if (is.na(pname) || pname == "") pname <- if (br$pitcher_id %in% names(id_map)) id_map[[br$pitcher_id]] else NA_character_
        if (is.na(pname) || pname == "") pname <- if (br$pitcher_id %in% names(starter_map)) starter_map[[br$pitcher_id]] else NA_character_
        if (is.na(pname) || pname == "") pname <- sprintf("Pitcher %s", br$pitcher_id)

        # Outing lacks Statcast tracking; default velo_delta to 0.0 with diagnostic log
        log_info(sprintf("Statcast pitch velocity tracking unavailable for boxscore outing (pitcher %s, game %d); defaulting velo_delta to 0.0",
                         br$pitcher_id, br$game_pk), script = .LOG_SCRIPT)

        relief_rows[[length(relief_rows) + 1]] <- tibble::tibble(
          game_pk        = br$game_pk,
          game_date      = g_date,
          pitcher_id     = br$pitcher_id,
          pitcher_name   = pname,
          team           = tm,
          pitches_thrown = as.integer(br$pitches_thrown),
          velo_delta     = 0.0
        )
      }
    }
  }

  relief_df <- if (length(relief_rows) > 0) {
    dplyr::bind_rows(relief_rows) %>%
      dplyr::arrange(pitcher_id, game_date)
  } else {
    tibble::tibble(
      game_pk        = integer(),
      game_date      = as.Date(character()),
      pitcher_id     = character(),
      pitcher_name   = character(),
      team           = character(),
      pitches_thrown = integer(),
      velo_delta     = numeric()
    )
  }

  saveRDS(relief_df, cache_file)
  log_info(sprintf("Extracted %d relief appearances across %d distinct relievers",
                   nrow(relief_df), length(unique(relief_df$pitcher_id))),
           script = .LOG_SCRIPT)

  relief_df
}

#' Compute Bullpen Fatigue States Across Calendar
#'
#' @param relief_df Tibble of relief appearances
#' @return Tibble of daily relief appearances with trailing fatigue metrics
compute_daily_fatigue_metrics <- function(relief_df) {
  log_info("Computing daily trailing workload and fatigue indicators", script = .LOG_SCRIPT)

  if (nrow(relief_df) == 0) return(tibble::tibble())

  # Order chronologically per pitcher
  ordered_df <- relief_df %>%
    dplyr::arrange(pitcher_id, game_date)

  fatigue_rows <- list()
  pitcher_groups <- split(ordered_df, ordered_df$pitcher_id)

  for (pid in names(pitcher_groups)) {
    p_df <- pitcher_groups[[pid]]
    n_apps <- nrow(p_df)
    if (n_apps == 0) next

    for (j in seq_len(n_apps)) {
      curr_date <- p_df$game_date[j]
      curr_pitches <- p_df$pitches_thrown[j]

      # Trailing 2-day pitches (prior to today)
      hist_2d <- p_df %>% dplyr::filter(game_date >= (curr_date - 2) & game_date < curr_date)
      pitches_2d <- sum(hist_2d$pitches_thrown, na.rm = TRUE)

      # Trailing 4-day pitches (prior to today)
      hist_4d <- p_df %>% dplyr::filter(game_date >= (curr_date - 4) & game_date < curr_date)
      pitches_4d <- sum(hist_4d$pitches_thrown, na.rm = TRUE)

      # Days of rest since last appearance
      rest_days <- if (j > 1) as.numeric(curr_date - p_df$game_date[j - 1]) - 1 else 3
      is_back_to_back <- (rest_days == 0)
      is_3_in_3 <- (nrow(hist_2d) >= 2)

      # Composite Fatigue Score (0 to 100, where 0 = fully fresh, 100 = extreme fatigue)
      raw_score <- (pitches_2d * 1.2) + (pitches_4d * 0.4) +
        (if (is_back_to_back) FATIGUE_THRESHOLDS$back_to_back_penalty else 0) +
        (if (is_3_in_3) FATIGUE_THRESHOLDS$three_in_three_penalty else 0) -
        (pmin(3, max(0, rest_days)) * 8.0)

      fatigue_score <- round(pmax(0, pmin(100, raw_score)), 1)
      status_label <- if (fatigue_score >= 65) "Exhausted" else if (fatigue_score >= 40) "Fatigued" else if (fatigue_score >= 20) "Moderate" else "Fresh"

      fatigue_rows[[length(fatigue_rows) + 1]] <- tibble::tibble(
        game_pk        = p_df$game_pk[j],
        game_date      = curr_date,
        pitcher_id     = pid,
        pitcher_name   = p_df$pitcher_name[j],
        team           = p_df$team[j],
        pitches_today  = curr_pitches,
        pitches_2d     = pitches_2d,
        pitches_4d     = pitches_4d,
        rest_days      = rest_days,
        back_to_back   = is_back_to_back,
        three_in_three = is_3_in_3,
        velo_delta     = p_df$velo_delta[j],
        fatigue_score  = fatigue_score,
        fatigue_status = status_label
      )
    }
  }

  res_df <- dplyr::bind_rows(fatigue_rows) %>%
    dplyr::arrange(desc(game_date), desc(fatigue_score))

  res_df
}

#' Aggregate Current Team Bullpen Vulnerability Index
#'
#' @param daily_fatigue Tibble of daily reliever fatigue states
#' @return Tibble summarizing team bullpen status for upcoming games
summarise_team_bullpen_status <- function(daily_fatigue) {
  if (nrow(daily_fatigue) == 0) return(tibble::tibble())

  latest_date <- max(daily_fatigue$game_date, na.rm = TRUE)

  # Relievers active in last 5 days
  recent_relievers <- daily_fatigue %>%
    dplyr::filter(game_date >= (latest_date - 5)) %>%
    dplyr::group_by(team, pitcher_id, pitcher_name) %>%
    dplyr::slice_max(game_date, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup()

  team_status <- recent_relievers %>%
    dplyr::group_by(team) %>%
    dplyr::summarise(
      active_relievers   = dplyr::n(),
      relievers_fatigued = sum(fatigue_score >= 40),
      relievers_exhausted= sum(fatigue_score >= 65),
      avg_bullpen_fatigue= round(mean(fatigue_score), 1),
      max_reliever_fatigue= max(fatigue_score),
      b2b_relievers_count = sum(back_to_back),
      .groups            = "drop"
    ) %>%
    dplyr::mutate(
      bullpen_vulnerability = round(avg_bullpen_fatigue * 0.7 + (relievers_exhausted * 12.0), 1),
      vulnerability_grade   = if_else(bullpen_vulnerability >= 45, "High Vulnerability",
                               if_else(bullpen_vulnerability >= 25, "Elevated Workload", "Well Rested"))
    ) %>%
    dplyr::arrange(desc(bullpen_vulnerability))

  team_status
}

#' Master Stage Runner for Relief-Pitcher Fatigue Engine
#'
#' @param season Season integer (defaults to 2024)
#' @param force_refresh If TRUE, recomputes from source data
#' @return Named list of daily reliever metrics and current team bullpen statuses
run_bullpen_fatigue <- function(season = 2024, force_refresh = FALSE) {
  log_info("Starting bullpen usage and fatigue engine stage", script = .LOG_SCRIPT,
           season = season, force_refresh = force_refresh)

  daily_cache <- cache_path("specialty", sprintf("bullpen_fatigue_daily_%d.rds", season))
  team_cache  <- cache_path("specialty", sprintf("bullpen_team_status_%d.rds", season))

  if (!force_refresh && file.exists(daily_cache) && file.exists(team_cache)) {
    log_info("Loading cached bullpen fatigue states from disk", script = .LOG_SCRIPT)
    return(list(
      daily = readRDS(daily_cache),
      team  = readRDS(team_cache)
    ))
  }

  appearances <- extract_bullpen_appearances(season = season, force_refresh = force_refresh)
  daily_df    <- compute_daily_fatigue_metrics(appearances)
  team_df     <- summarise_team_bullpen_status(daily_df)

  saveRDS(daily_df, daily_cache)
  saveRDS(team_df, team_cache)

  # Canonical cache files
  saveRDS(daily_df, cache_path("specialty", "bullpen_fatigue_daily.rds"))
  saveRDS(team_df, cache_path("specialty", "bullpen_team_status.rds"))

  log_info(sprintf("Saved bullpen fatigue signals: %d reliever-game states, %d team bullpen summaries",
                   nrow(daily_df), nrow(team_df)),
           script = .LOG_SCRIPT)

  invisible(list(
    daily = daily_df,
    team  = team_df
  ))
}

if (sys.nframe() == 0) {
  run_bullpen_fatigue()
}

