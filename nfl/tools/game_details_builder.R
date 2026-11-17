# ==============================================================================
# Game Details JSON Builder (NFL)
# Path: tools/game_details_builder.R
#
# Generates per-game JSON files under web/public/data/games/{game_id}.json
# adhering to GameDetailEnvelope schema (web/tests/contracts/schemas.ts).
# Implements 7-day churn control and byte-identical idempotency.
# ==============================================================================

suppressWarnings(suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
}))

if (!exists("PROJECT_DIR")) {
  source("config.R")
}
if (!exists("log_info")) {
  source("logging_utils.R")
}
.LOG_SCRIPT <- "game_details_builder.R"

# Ensure target directory exists
if (!dir.exists(WEB_GAMES_DIR)) {
  dir.create(WEB_GAMES_DIR, recursive = TRUE)
}

.build_efficiency_factors <- function(pbp_game, away_tm, home_tm) {
  if (is.null(pbp_game) || nrow(pbp_game) == 0) {
    return(NULL)
  }

  calc_team_eff <- function(tm) {
    off_plays <- pbp_game |> filter(posteam == tm, play_type %in% c("pass", "run") | !is.na(epa))
    off_epa <- off_plays |> filter(!is.na(epa))
    pass_plays <- off_plays |> filter(pass == 1, !is.na(epa))
    rush_plays <- off_plays |> filter(pass == 0, !is.na(epa))
    early_plays <- off_plays |> filter(down %in% c(1, 2), !is.na(epa))
    late_plays <- off_plays |> filter(down %in% c(3, 4), !is.na(success))

    list(
      epa_per_play = if (nrow(off_epa) > 0) round(mean(off_epa$epa), 3) else NULL,
      success_rate = if (nrow(off_epa) > 0) round(mean(off_epa$success == 1) * 100, 1) else NULL,
      dropback_epa = if (nrow(pass_plays) > 0) round(mean(pass_plays$epa), 3) else NULL,
      rush_epa = if (nrow(rush_plays) > 0) round(mean(rush_plays$epa), 3) else NULL,
      cpoe = if (any(!is.na(off_plays$cpoe))) round(mean(off_plays$cpoe, na.rm = TRUE), 2) else NULL,
      yards_per_play = if (nrow(off_plays) > 0) round(sum(off_plays$yards_gained, na.rm = TRUE) / nrow(off_plays), 1) else NULL,
      early_down_epa = if (nrow(early_plays) > 0) round(mean(early_plays$epa), 3) else NULL,
      late_down_success_rate = if (nrow(late_plays) > 0) round(mean(late_plays$success == 1) * 100, 1) else NULL
    )
  }

  away_eff <- calc_team_eff(away_tm)
  home_eff <- calc_team_eff(home_tm)

  factors <- list(
    list(
      key = "epa_per_play",
      label = "EPA / Play",
      away_value = away_eff$epa_per_play,
      home_value = home_eff$epa_per_play,
      unit = "epa",
      higher_is_better = TRUE,
      description = "Expected Points Added per offensive play"
    ),
    list(
      key = "success_rate",
      label = "Success Rate",
      away_value = away_eff$success_rate,
      home_value = home_eff$success_rate,
      unit = "pct",
      higher_is_better = TRUE,
      description = "Percentage of plays with positive Expected Points Added"
    ),
    list(
      key = "dropback_epa",
      label = "Dropback EPA",
      away_value = away_eff$dropback_epa,
      home_value = home_eff$dropback_epa,
      unit = "epa",
      higher_is_better = TRUE,
      description = "Expected Points Added per dropback pass play"
    ),
    list(
      key = "rush_epa",
      label = "Rush EPA",
      away_value = away_eff$rush_epa,
      home_value = home_eff$rush_epa,
      unit = "epa",
      higher_is_better = TRUE,
      description = "Expected Points Added per rushing play"
    ),
    list(
      key = "cpoe",
      label = "CPOE",
      away_value = away_eff$cpoe,
      home_value = home_eff$cpoe,
      unit = "pct",
      higher_is_better = TRUE,
      description = "Completion Percentage Over Expected on pass attempts"
    ),
    list(
      key = "yards_per_play",
      label = "Yards / Play",
      away_value = away_eff$yards_per_play,
      home_value = home_eff$yards_per_play,
      unit = "yards",
      higher_is_better = TRUE,
      description = "Total offensive yards gained per play"
    ),
    list(
      key = "early_down_epa",
      label = "Early Down EPA",
      away_value = early_eff <- away_eff$early_down_epa,
      home_value = home_eff$early_down_epa,
      unit = "epa",
      higher_is_better = TRUE,
      description = "Expected Points Added on 1st and 2nd downs"
    ),
    list(
      key = "late_down_success_rate",
      label = "Late Down Success Rate",
      away_value = away_eff$late_down_success_rate,
      home_value = home_eff$late_down_success_rate,
      unit = "pct",
      higher_is_better = TRUE,
      description = "Percentage of 3rd and 4th down plays converted successfully"
    )
  )

  factors
}

.build_team_stats <- function(away_ts, home_ts) {
  if (nrow(away_ts) == 0 && nrow(home_ts) == 0) {
    return(NULL)
  }

  get_stat <- function(ts, stat_name, default = 0) {
    if (nrow(ts) > 0 && stat_name %in% names(ts) && !is.na(ts[[stat_name]][1])) {
      ts[[stat_name]][1]
    } else {
      default
    }
  }

  away_pass_yd <- get_stat(away_ts, "passing_yards")
  away_rush_yd <- get_stat(away_ts, "rushing_yards")
  home_pass_yd <- get_stat(home_ts, "passing_yards")
  home_rush_yd <- get_stat(home_ts, "rushing_yards")

  away_tot_yd <- away_pass_yd + away_rush_yd
  home_tot_yd <- home_pass_yd + home_rush_yd

  away_comp <- get_stat(away_ts, "completions")
  away_att <- get_stat(away_ts, "attempts")
  home_comp <- get_stat(home_ts, "completions")
  home_att <- get_stat(home_ts, "attempts")

  away_to <- get_stat(away_ts, "passing_interceptions") + get_stat(away_ts, "fumbles_lost_total")
  home_to <- get_stat(home_ts, "passing_interceptions") + get_stat(home_ts, "fumbles_lost_total")

  away_pen <- get_stat(away_ts, "penalties")
  away_pen_yd <- get_stat(away_ts, "penalty_yards")
  home_pen <- get_stat(home_ts, "penalties")
  home_pen_yd <- get_stat(home_ts, "penalty_yards")

  away_fd <- get_stat(away_ts, "passing_first_downs") + get_stat(away_ts, "rushing_first_downs")
  home_fd <- get_stat(home_ts, "passing_first_downs") + get_stat(home_ts, "rushing_first_downs")

  away_sacks <- get_stat(away_ts, "sacks_suffered")
  away_sack_yd <- abs(get_stat(away_ts, "sack_yards_lost"))
  home_sacks <- get_stat(home_ts, "sacks_suffered")
  home_sack_yd <- abs(get_stat(home_ts, "sack_yards_lost"))

  list(
    list(stat_key = "total_yards", label = "Total Yards", away_value = away_tot_yd, home_value = home_tot_yd),
    list(stat_key = "passing_yards", label = "Passing Yards", away_value = away_pass_yd, home_value = home_pass_yd),
    list(stat_key = "rushing_yards", label = "Rushing Yards", away_value = away_rush_yd, home_value = home_rush_yd),
    list(stat_key = "completions_attempts", label = "Comp / Att", away_value = sprintf("%d/%d", away_comp, away_att), home_value = sprintf("%d/%d", home_comp, home_att)),
    list(stat_key = "turnovers", label = "Turnovers", away_value = away_to, home_value = home_to),
    list(stat_key = "penalties_yards", label = "Penalties - Yards", away_value = sprintf("%d-%d", away_pen, away_pen_yd), home_value = sprintf("%d-%d", home_pen, home_pen_yd)),
    list(stat_key = "first_downs", label = "First Downs", away_value = away_fd, home_value = home_fd),
    list(stat_key = "sacks_yards_lost", label = "Sacks - Yards Lost", away_value = sprintf("%d-%d", away_sacks, away_sack_yd), home_value = sprintf("%d-%d", home_sacks, home_sack_yd))
  )
}

.build_leaders <- function(players_df, away_tm, home_tm) {
  if (is.null(players_df) || nrow(players_df) == 0) {
    return(NULL)
  }

  leaders <- list()

  for (tm in c(away_tm, home_tm)) {
    p_tm <- players_df |> filter(team == tm)
    if (nrow(p_tm) == 0) next

    # 1. Passing
    passers <- p_tm |> filter(attempts > 0 | passing_yards > 0) |>
      arrange(desc(passing_yards), desc(completions), player_name)
    if (nrow(passers) > 0) {
      top_p <- passers[1, ]
      display_name <- if (!is.na(top_p$player_display_name) && nzchar(top_p$player_display_name)) top_p$player_display_name else top_p$player_name
      leaders[[length(leaders) + 1]] <- list(
        category = "passing",
        teamAbbr = tm,
        playerId = top_p$player_id,
        playerName = display_name,
        stat_line = sprintf("%d/%d, %d YDS, %d TD", top_p$completions, top_p$attempts, top_p$passing_yards, top_p$passing_tds)
      )
    }

    # 2. Rushing
    rushers <- p_tm |> filter(carries > 0 | rushing_yards > 0) |>
      arrange(desc(rushing_yards), desc(rushing_tds), desc(carries), player_name)
    if (nrow(rushers) > 0) {
      top_r <- rushers[1, ]
      display_name <- if (!is.na(top_r$player_display_name) && nzchar(top_r$player_display_name)) top_r$player_display_name else top_r$player_name
      leaders[[length(leaders) + 1]] <- list(
        category = "rushing",
        teamAbbr = tm,
        playerId = top_r$player_id,
        playerName = display_name,
        stat_line = sprintf("%d CAR, %d YDS, %d TD", top_r$carries, top_r$rushing_yards, top_r$rushing_tds)
      )
    }

    # 3. Receiving
    receivers <- p_tm |> filter(targets > 0 | receptions > 0 | receiving_yards > 0) |>
      arrange(desc(receiving_yards), desc(receiving_tds), desc(receptions), player_name)
    if (nrow(receivers) > 0) {
      top_rec <- receivers[1, ]
      display_name <- if (!is.na(top_rec$player_display_name) && nzchar(top_rec$player_display_name)) top_rec$player_display_name else top_rec$player_name
      leaders[[length(leaders) + 1]] <- list(
        category = "receiving",
        teamAbbr = tm,
        playerId = top_rec$player_id,
        playerName = display_name,
        stat_line = sprintf("%d REC, %d YDS, %d TD", top_rec$receptions, top_rec$receiving_yards, top_rec$receiving_tds)
      )
    }

    # 4. Defense: sacks then interceptions then solo tackles as tie-breakers. Ties broken by playerName.
    defenders <- p_tm |> filter((def_tackles_solo + def_tackle_assists + def_sacks + def_interceptions) > 0) |>
      arrange(desc(def_sacks), desc(def_interceptions), desc(def_tackles_solo), player_name)
    if (nrow(defenders) > 0) {
      top_def <- defenders[1, ]
      display_name <- if (!is.na(top_def$player_display_name) && nzchar(top_def$player_display_name)) top_def$player_display_name else top_def$player_name
      parts <- c()
      if (top_def$def_sacks > 0) parts <- c(parts, sprintf("%.1f SCK", top_def$def_sacks))
      if (top_def$def_interceptions > 0) parts <- c(parts, sprintf("%d INT", top_def$def_interceptions))
      if (top_def$def_tackles_solo > 0) parts <- c(parts, sprintf("%d TKL", top_def$def_tackles_solo))
      if (length(parts) == 0) parts <- c(sprintf("%d TKL", top_def$def_tackle_assists))
      leaders[[length(leaders) + 1]] <- list(
        category = "defense",
        teamAbbr = tm,
        playerId = top_def$player_id,
        playerName = display_name,
        stat_line = paste(parts, collapse = ", ")
      )
    }
  }

  if (length(leaders) == 0) NULL else leaders
}

.build_player_box_rows <- function(players_df, tm, snaps_df, gsis_to_pfr = list()) {
  if (is.null(players_df) || nrow(players_df) == 0) {
    return(I(list()))
  }

  p_tm <- players_df |> filter(team == tm)
  if (nrow(p_tm) == 0) {
    return(I(list()))
  }

  # Build snap percentage lookup for this game and team
  snap_map <- list()
  if (!is.null(snaps_df) && nrow(snaps_df) > 0) {
    s_tm <- snaps_df |> filter(team == tm)
    for (i in seq_len(nrow(s_tm))) {
      row_s <- s_tm[i, ]
      # pct on 0-100 scale
      raw_pct <- max(c(row_s$offense_pct, row_s$defense_pct, row_s$st_pct), na.rm = TRUE)
      if (is.finite(raw_pct)) {
        pct_val <- round(raw_pct * 100, 1)
        if (pct_val > 100) pct_val <- 100
        if (pct_val < 0) pct_val <- 0
        if (!is.na(row_s$pfr_player_id) && nzchar(row_s$pfr_player_id)) {
          snap_map[[paste0("pfr_", row_s$pfr_player_id)]] <- pct_val
        }
        if (!is.na(row_s$player) && nzchar(row_s$player)) {
          snap_map[[paste0("name_", tolower(trimws(row_s$player)))]] <- pct_val
        }
      }
    }
  }

  box_rows <- list()

  for (i in seq_len(nrow(p_tm))) {
    p <- p_tm[i, ]
    pid <- as.character(p$player_id)
    pname <- if (!is.na(p$player_display_name) && nzchar(p$player_display_name)) {
      as.character(p$player_display_name)
    } else {
      as.character(p$player_name)
    }

    if (is.na(pid) || !nzchar(pid) || pid == "NA" || is.na(pname) || !nzchar(pname) || pname == "NA") {
      next
    }

    # Resolve snap_pct
    pfr_id <- gsis_to_pfr[[pid]]
    snap_pct <- NULL
    if (!is.null(pfr_id) && !is.null(snap_map[[paste0("pfr_", pfr_id)]])) {
      snap_pct <- snap_map[[paste0("pfr_", pfr_id)]]
    } else if (!is.null(snap_map[[paste0("name_", tolower(trimws(pname)))]])) {
      snap_pct <- snap_map[[paste0("name_", tolower(trimws(pname)))]]
    } else if (!is.null(snap_map[[paste0("name_", tolower(trimws(p$player_name)))]])) {
      snap_pct <- snap_map[[paste0("name_", tolower(trimws(p$player_name)))]]
    }

    # Determine categories
    has_pass <- (p$attempts > 0 || p$completions > 0 || p$passing_yards != 0 || p$passing_tds > 0 || p$sacks_suffered > 0)
    has_rush <- (p$carries > 0 || p$rushing_yards != 0 || p$rushing_tds > 0)
    has_rec  <- (p$targets > 0 || p$receptions > 0 || p$receiving_yards != 0 || p$receiving_tds > 0)
    def_sum  <- (p$def_tackles_solo + p$def_tackle_assists + p$def_sacks + p$def_interceptions +
                 p$def_pass_defended + p$def_qb_hits + p$def_fumbles_forced + p$def_tackles_for_loss)
    has_def  <- (def_sum > 0)
    has_kick <- (p$fg_att > 0 || p$pat_att > 0 || p$fg_made > 0 || p$pat_made > 0)

    cats <- character(0)
    if (has_pass) cats <- c(cats, "passing")
    if (has_rush) cats <- c(cats, "rushing")
    if (has_rec)  cats <- c(cats, "receiving")
    if (has_def)  cats <- c(cats, "defense")
    if (has_kick) cats <- c(cats, "kicking")

    row_data <- list(
      playerId   = pid,
      playerName = pname,
      teamAbbr   = tm,
      position   = if (!is.na(p$position) && nzchar(p$position)) as.character(p$position) else NULL,
      categories = I(cats),
      snap_pct   = snap_pct
    )

    # Passing fields
    if (has_pass || "passing" %in% cats) {
      row_data$completions           <- as.integer(p$completions)
      row_data$attempts              <- as.integer(p$attempts)
      row_data$passing_yards         <- as.integer(p$passing_yards)
      row_data$passing_tds           <- as.integer(p$passing_tds)
      row_data$passing_interceptions <- as.integer(p$passing_interceptions)
      row_data$sacks_suffered        <- as.integer(p$sacks_suffered)
      row_data$sack_yards_lost       <- as.integer(p$sack_yards_lost)
      row_data$passing_epa           <- if (!is.na(p$passing_epa)) round(p$passing_epa, 2) else NULL
      row_data$passing_cpoe          <- if (!is.na(p$passing_cpoe)) round(p$passing_cpoe, 2) else NULL
    }

    # Rushing fields
    if (has_rush || "rushing" %in% cats) {
      row_data$carries              <- as.integer(p$carries)
      row_data$rushing_yards        <- as.integer(p$rushing_yards)
      row_data$rushing_tds          <- as.integer(p$rushing_tds)
      row_data$rushing_fumbles      <- as.integer(p$rushing_fumbles)
      row_data$rushing_fumbles_lost <- as.integer(p$rushing_fumbles_lost)
      row_data$rushing_first_downs  <- as.integer(p$rushing_first_downs)
      row_data$rushing_epa          <- if (!is.na(p$rushing_epa)) round(p$rushing_epa, 2) else NULL
    }

    # Receiving fields
    if (has_rec || "receiving" %in% cats) {
      row_data$receptions            <- as.integer(p$receptions)
      row_data$targets               <- as.integer(p$targets)
      row_data$receiving_yards       <- as.integer(p$receiving_yards)
      row_data$receiving_tds         <- as.integer(p$receiving_tds)
      row_data$receiving_fumbles     <- as.integer(p$receiving_fumbles)
      row_data$receiving_fumbles_lost<- as.integer(p$receiving_fumbles_lost)
      row_data$receiving_first_downs <- as.integer(p$receiving_first_downs)
      row_data$receiving_epa         <- if (!is.na(p$receiving_epa)) round(p$receiving_epa, 2) else NULL
    }

    # Defense fields
    if (has_def || "defense" %in% cats) {
      row_data$def_tackles_solo     <- as.integer(p$def_tackles_solo)
      row_data$def_tackle_assists   <- as.integer(p$def_tackle_assists)
      row_data$def_tackles_for_loss <- as.integer(p$def_tackles_for_loss)
      row_data$def_sacks            <- as.numeric(p$def_sacks)
      row_data$def_qb_hits          <- as.integer(p$def_qb_hits)
      row_data$def_interceptions    <- as.integer(p$def_interceptions)
      row_data$def_pass_defended    <- as.integer(p$def_pass_defended)
      row_data$def_fumbles_forced   <- as.integer(p$def_fumbles_forced)
    }

    # Kicking fields
    if (has_kick || "kicking" %in% cats) {
      row_data$fg_made  <- as.integer(p$fg_made)
      row_data$fg_att   <- as.integer(p$fg_att)
      row_data$fg_long  <- if (!is.na(p$fg_long) && p$fg_long > 0) as.integer(p$fg_long) else NULL
      row_data$pat_made <- as.integer(p$pat_made)
      row_data$pat_att  <- as.integer(p$pat_att)
    }

    box_rows[[length(box_rows) + 1]] <- row_data
  }

  I(box_rows)
}

.build_injury_designations <- function(inj_df, week_num, season_num, away_tm, home_tm, players_df, snaps_df) {
  if (is.null(inj_df) || nrow(inj_df) == 0) {
    return(NULL)
  }

  g_inj <- inj_df |>
    filter(season == season_num, week == week_num, team %in% c(away_tm, home_tm),
           status %in% c("Out", "IR", "Doubtful", "Questionable"))

  if (nrow(g_inj) == 0) {
    return(NULL)
  }

  # Build set of players who played (had stats or snaps)
  played_ids <- character(0)
  played_names <- character(0)

  if (!is.null(players_df) && nrow(players_df) > 0) {
    played_ids <- c(played_ids, as.character(players_df$player_id))
    played_names <- c(played_names, tolower(trimws(players_df$player_name)), tolower(trimws(players_df$player_display_name)))
  }
  if (!is.null(snaps_df) && nrow(snaps_df) > 0) {
    active_snaps <- snaps_df |> filter((offense_snaps + defense_snaps + st_snaps) > 0)
    played_names <- c(played_names, tolower(trimws(active_snaps$player)))
  }
  played_names <- unique(played_names[nzchar(played_names)])

  inj_rows <- list()
  for (i in seq_len(nrow(g_inj))) {
    row_i <- g_inj[i, ]
    pid <- if (!is.na(row_i$gsis_id) && nzchar(row_i$gsis_id)) as.character(row_i$gsis_id) else NULL
    pname <- as.character(row_i$player_name)
    pos <- if ("position" %in% names(row_i) && !is.na(row_i$position) && nzchar(row_i$position)) as.character(row_i$position) else NULL
    body_part <- if (!is.na(row_i$injury_desc) && nzchar(row_i$injury_desc)) as.character(row_i$injury_desc) else NULL

    has_played <- FALSE
    if (!is.null(pid) && pid %in% played_ids) {
      has_played <- TRUE
    } else if (tolower(trimws(pname)) %in% played_names) {
      has_played <- TRUE
    }

    inj_rows[[length(inj_rows) + 1]] <- list(
      playerId    = pid,
      playerName  = pname,
      position    = pos,
      designation = as.character(row_i$status),
      body_part   = body_part,
      played      = has_played
    )
  }

  if (length(inj_rows) == 0) NULL else inj_rows
}

# ==============================================================================
# Attribution & Explainability Helpers (Phase 2, Issue 2-6 / #115)
# ==============================================================================

.precompute_team_eff_metrics <- function(pbp_df, target_season = CURRENT_SEASON) {
  if (is.null(pbp_df) || nrow(pbp_df) == 0) return(NULL)
  pbp_sub <- pbp_df |>
    filter(season == target_season, !is.na(posteam), !is.na(epa))
  if (nrow(pbp_sub) == 0) return(NULL)

  pbp_sub |>
    group_by(season, week, game_id, team = posteam) |>
    summarize(
      epa_per_play = mean(epa, na.rm = TRUE),
      success_rate = mean(success == 1, na.rm = TRUE) * 100,
      dropback_epa = mean(epa[pass == 1], na.rm = TRUE),
      rush_epa     = mean(epa[pass == 0], na.rm = TRUE),
      cpoe         = if (any(!is.na(cpoe))) mean(cpoe, na.rm = TRUE) else NA_real_,
      .groups      = "drop"
    )
}

.build_entering_baselines <- function(team_eff_df, g_season, g_week, gid, away_tm, home_tm, is_completed) {
  metrics_meta <- list(
    list(key = "epa_per_play", label = "EPA / Play"),
    list(key = "success_rate", label = "Success Rate"),
    list(key = "dropback_epa", label = "Dropback EPA"),
    list(key = "rush_epa", label = "Rush EPA"),
    list(key = "cpoe", label = "CPOE")
  )

  results <- list()

  for (tm in c(away_tm, home_tm)) {
    prior_games <- if (!is.null(team_eff_df)) {
      team_eff_df |> filter(season == g_season, team == tm, week < g_week)
    } else {
      data.frame()
    }
    prior_n <- nrow(prior_games)
    is_low <- prior_n < 4

    cur_game <- if (is_completed && !is.null(team_eff_df)) {
      team_eff_df |> filter(game_id == gid, team == tm)
    } else {
      data.frame()
    }

    for (m in metrics_meta) {
      k <- m$key
      ent_val <- if (prior_n > 0 && k %in% names(prior_games) && any(!is.na(prior_games[[k]]))) {
        mean(prior_games[[k]], na.rm = TRUE)
      } else {
        NA_real_
      }

      real_val <- if (nrow(cur_game) > 0 && k %in% names(cur_game) && !is.na(cur_game[[k]][1])) {
        cur_game[[k]][1]
      } else {
        NA_real_
      }

      delta_val <- if (!is.na(ent_val) && !is.na(real_val)) {
        round(real_val - ent_val, 3)
      } else {
        NULL
      }

      results[[length(results) + 1L]] <- list(
        metric_key        = k,
        metric_label      = m$label,
        team_abbr         = tm,
        entering_baseline = if (!is.na(ent_val)) round(ent_val, 3) else NULL,
        realized_value    = if (!is.na(real_val)) round(real_val, 3) else NULL,
        delta             = delta_val,
        prior_games_n     = as.integer(prior_n),
        is_low_sample     = is_low
      )
    }
  }

  results
}

.build_game_explainability <- function(gid, g_season, g_week, away_tm, home_tm, pred_row, shap_game, team_eff_df, is_completed, include_oos = FALSE) {
  if (is.null(pred_row)) return(NULL)

  # 1. Waterfall steps (Section 5.2)
  waterfall_steps <- list(
    list(key = "step_current_epa", label = "Current-Season EPA", points = round(as.numeric(pred_row$step_current_epa), 2), description = "Current season rolling EPA net differential"),
    list(key = "step_prior_epa", label = "Pre-Season Prior", points = round(as.numeric(pred_row$step_prior_epa), 2), description = "Prior season baseline regressed to mean"),
    list(key = "step_elo_diff", label = "Elo Differential", points = round(as.numeric(pred_row$step_elo_diff), 2), description = "Elo rating points differential"),
    list(key = "step_home_field", label = "Home Field Advantage", points = round(as.numeric(pred_row$step_home_field), 2), description = "Neutral site and home field advantage blend"),
    list(key = "step_qb_adjustment", label = "Starting Quarterback", points = round(as.numeric(pred_row$step_qb_adjustment), 2), description = "Quarterback availability and injury adjustment"),
    list(key = "step_rounding", label = "Rounding", points = round(as.numeric(pred_row$step_rounding), 3), description = "Decomposition residual")
  )

  waterfall_payload <- list(
    projected_margin = round(as.numeric(pred_row$projected_margin), 2),
    home_win_prob    = round(as.numeric(pred_row$home_win_prob), 3),
    steps            = waterfall_steps,
    rounding         = round(as.numeric(pred_row$step_rounding), 3),
    sigma            = if (!is.null(pred_row$margin_sigma) && !is.na(pred_row$margin_sigma)) as.numeric(pred_row$margin_sigma) else 14.60,
    intercept        = if (!is.null(pred_row$ridge_b_intercept) && !is.na(pred_row$ridge_b_intercept)) round(as.numeric(pred_row$ridge_b_intercept), 2) else 1.84
  )

  # 2. Secondary model TreeSHAP summary (Section 5.4)
  secondary_model <- NULL
  if (!is.null(shap_game)) {
    sec_prob <- round(as.numeric(shap_game$model_win_prob), 3)
    h_prob   <- round(as.numeric(pred_row$home_win_prob), 3)
    agreement_val <- if ((sec_prob >= 0.5 && h_prob >= 0.5) || (sec_prob < 0.5 && h_prob < 0.5)) "agree" else "differ"

    secondary_model <- list(
      model_id             = shap_game$model_metadata$model_id,
      model_label          = shap_game$model_metadata$model_label,
      model_win_prob       = sec_prob,
      logit                = round(as.numeric(shap_game$logit), 4),
      base_value           = round(as.numeric(shap_game$base_value), 4),
      factors              = shap_game$features,
      agreement            = agreement_val
    )

    # Season accuracy block is kept in weekly attribution datasets, but omitted from
    # individual game files to keep completed game files frozen and avoid O(N) churn.
    if (isTRUE(include_oos) && !is.null(shap_game$model_metadata$out_of_sample_record)) {
      secondary_model$out_of_sample_record <- list(
        n_games  = as.integer(shap_game$model_metadata$out_of_sample_record$n_games),
        accuracy = as.numeric(shap_game$model_metadata$out_of_sample_record$accuracy),
        brier    = as.numeric(shap_game$model_metadata$out_of_sample_record$brier),
        logloss  = as.numeric(shap_game$model_metadata$out_of_sample_record$logloss)
      )
    }
  }

  # 3. Entering baselines (Section 5.5)
  baselines <- .build_entering_baselines(team_eff_df, g_season, g_week, gid, away_tm, home_tm, is_completed)

  # 4. Divergence note
  divergence_note <- NULL
  if (is_completed && length(baselines) > 0) {
    deltas <- sapply(baselines, function(b) if (!is.null(b$delta)) abs(b$delta) else -1)
    max_idx <- which.max(deltas)
    if (length(max_idx) > 0 && deltas[max_idx] >= 0) {
      top_b <- baselines[[max_idx]]
      divergence_note <- sprintf("%s %s (%+0.3f) showed the largest divergence from entering baseline (%+0.3f).",
                                 top_b$team_abbr, top_b$metric_label, top_b$realized_value, top_b$entering_baseline)
    }
  }

  basis_str <- if (!is.null(pred_row$log_source)) {
    if (identical(as.character(pred_row$log_source), "LOGGED_PREGAME")) "logged_pregame"
    else if (identical(as.character(pred_row$log_source), "BACKTEST_PREWEEK")) "backtest_preweek"
    else "primary_ensemble"
  } else {
    "primary_ensemble"
  }

  list(
    game_id                 = gid,
    season                  = as.integer(g_season),
    week                    = as.integer(g_week),
    projection_basis        = basis_str,
    predicted_margin        = round(as.numeric(pred_row$projected_margin), 2),
    predicted_home_win_prob = round(as.numeric(pred_row$home_win_prob), 3),
    waterfall               = waterfall_payload,
    secondary_model         = secondary_model,
    entering_baselines      = baselines,
    divergence_note         = divergence_note,
    margin_waterfall        = waterfall_steps
  )
}

.export_weekly_attribution <- function(sched_df, pred_log_df, shap_df, team_eff_df, force = FALSE) {
  if (!dir.exists(WEB_ATTRIBUTION_DIR)) {
    dir.create(WEB_ATTRIBUTION_DIR, recursive = TRUE, showWarnings = FALSE)
  }

  unplayed_games <- sched_df |>
    filter(season == CURRENT_SEASON, is.na(home_score) | is.na(away_score))

  if (nrow(unplayed_games) == 0) {
    log_info("No unplayed games found for weekly attribution export.", call = "export_weekly_attribution()")
    return(invisible(0L))
  }

  weeks <- sort(unique(unplayed_games$week))
  n_written <- 0L

  for (w in weeks) {
    w_games <- unplayed_games |> filter(week == w)
    explain_list <- list()

    for (i in seq_len(nrow(w_games))) {
      g <- w_games[i, ]
      gid <- as.character(g$game_id)
      away_tm <- as.character(g$away_team)
      home_tm <- as.character(g$home_team)

      pred_row <- if (!is.null(pred_log_df)) {
        p_sub <- pred_log_df |> filter(game_id == gid)
        if (nrow(p_sub) > 0) p_sub[1, ] else NULL
      } else NULL

      shap_game <- if (!is.null(shap_df) && !is.null(shap_df$games[[gid]])) {
        shap_df$games[[gid]]
      } else NULL

      if (!is.null(pred_row)) {
        expl <- .build_game_explainability(gid, CURRENT_SEASON, w, away_tm, home_tm, pred_row, shap_game, team_eff_df, is_completed = FALSE, include_oos = TRUE)
        if (!is.null(expl)) {
          explain_list[[length(explain_list) + 1L]] <- expl
        }
      }
    }

    if (length(explain_list) > 0) {
      out_path <- file.path(WEB_ATTRIBUTION_DIR, sprintf("%d_%d.json", CURRENT_SEASON, w))
      gen_time <- format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")

      weekly_envelope <- list(
        schema_version = "1.0",
        generated_at   = gen_time,
        season         = as.integer(CURRENT_SEASON),
        week           = as.integer(w),
        games          = explain_list
      )

      cand_json <- toJSON(weekly_envelope, auto_unbox = TRUE, pretty = 2, null = "null")

      if (!isTRUE(force) && file.exists(out_path)) {
        exist_json <- paste(readLines(out_path, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
        strip_pattern <- '"generated_at"\\s*:\\s*"[^"]*",?'
        if (isTRUE(trimws(gsub(strip_pattern, "", cand_json)) == trimws(gsub(strip_pattern, "", exist_json)))) {
          next
        }
      }

      writeLines(cand_json, out_path, useBytes = TRUE)
      n_written <- n_written + 1L
    }
  }

  log_info(sprintf("Exported weekly attribution files: %d written for %d weeks.", n_written, length(weeks)),
           call = "export_weekly_attribution()")
  invisible(n_written)
}

#' Describe what changed between an existing game file and newly rebuilt payload
.describe_game_detail_changes <- function(old_env, new_payload) {
  changes <- character(0)

  old_d <- if (!is.null(old_env)) old_env$data else NULL
  if (!is.null(old_d)) {
    old_h_score <- old_d$home_team$score
    new_h_score <- new_payload$home_team$score
    old_a_score <- old_d$away_team$score
    new_a_score <- new_payload$away_team$score
    if (!identical(old_h_score, new_h_score) || !identical(old_a_score, new_a_score)) {
      changes <- c(changes, sprintf("score (%s-%s -> %s-%s)", old_a_score, old_h_score, new_a_score, new_h_score))
    }

    if (!identical(old_d$home_team$is_winner, new_payload$home_team$is_winner)) {
      changes <- c(changes, sprintf("home_winner (%s -> %s)", old_d$home_team$is_winner, new_payload$home_team$is_winner))
    }

    old_f <- old_d$forecast
    new_f <- new_payload$forecast
    if (!is.null(old_f) && !is.null(new_f)) {
      if (!identical(old_f$projected_margin, new_f$projected_margin)) {
        changes <- c(changes, sprintf("forecast_margin (%s -> %s)", old_f$projected_margin, new_f$projected_margin))
      }
      if (!identical(old_f$home_win_prob, new_f$home_win_prob)) {
        changes <- c(changes, sprintf("home_win_prob (%s -> %s)", old_f$home_win_prob, new_f$home_win_prob))
      }
      if (!identical(old_f$home_power_rating, new_f$home_power_rating) || !identical(old_f$away_power_rating, new_f$away_power_rating)) {
        changes <- c(changes, sprintf("power_ratings (H:%s A:%s -> H:%s A:%s)",
                                      old_f$home_power_rating, old_f$away_power_rating,
                                      new_f$home_power_rating, new_f$away_power_rating))
      }
    }

    old_pc <- length(old_d$box_score$away_players) + length(old_d$box_score$home_players)
    new_pc <- length(new_payload$box_score$away_players) + length(new_payload$box_score$home_players)
    if (!identical(old_pc, new_pc)) {
      changes <- c(changes, sprintf("box_score_players (%d -> %d)", old_pc, new_pc))
    }

    # Team stats comparison
    if (!is.null(old_d$team_stats) && !is.null(new_payload$team_stats)) {
      old_ts_map <- list()
      for (row in old_d$team_stats) old_ts_map[[row$stat_key]] <- row
      for (row in new_payload$team_stats) {
        k <- row$stat_key
        if (!is.null(old_ts_map[[k]])) {
          o_row <- old_ts_map[[k]]
          if (!identical(o_row$away_value, row$away_value) || !identical(o_row$home_value, row$home_value)) {
            changes <- c(changes, sprintf("team_stat:%s (A:%s H:%s -> A:%s H:%s)",
                                          k, o_row$away_value, o_row$home_value,
                                          row$away_value, row$home_value))
          }
        }
      }
    }

    # Player stats per-player comparison (detects stat corrections including player-to-player transfers)
    stat_cols <- c("passing_tds", "passing_interceptions", "passing_yards",
                   "rushing_tds", "rushing_yards", "receiving_tds", "receiving_yards",
                   "def_interceptions", "def_sacks", "def_tackles_solo")
    old_all_players <- c(old_d$box_score$away_players, old_d$box_score$home_players)
    new_all_players <- c(new_payload$box_score$away_players, new_payload$box_score$home_players)

    old_p_map <- list()
    for (p in old_all_players) {
      pid <- if (!is.null(p$playerId)) p$playerId else p$playerName
      if (!is.null(pid)) old_p_map[[pid]] <- p
    }
    for (p in new_all_players) {
      pid <- if (!is.null(p$playerId)) p$playerId else p$playerName
      if (!is.null(pid) && !is.null(old_p_map[[pid]])) {
        o_p <- old_p_map[[pid]]
        for (col in stat_cols) {
          o_val <- if (!is.null(o_p[[col]])) o_p[[col]] else 0
          n_val <- if (!is.null(p[[col]])) p[[col]] else 0
          o_num <- suppressWarnings(as.numeric(o_val))
          n_num <- suppressWarnings(as.numeric(n_val))
          diff_detected <- if (!is.na(o_num) && !is.na(n_num)) {
            abs(o_num - n_num) > 1e-6
          } else {
            !identical(o_val, n_val)
          }
          if (diff_detected) {
            p_label <- if (!is.null(p$playerName)) p$playerName else pid
            changes <- c(changes, sprintf("player_stat:%s[%s] (%s -> %s)", col, p_label, o_val, n_val))
          }
        }
      }
    }
  }

  if (length(changes) == 0) {
    changes <- "rebuilt metadata, attribution, or stats updated"
  }
  paste(changes, collapse = ", ")
}

#' Build per-game JSON files under web/public/data/games/{game_id}.json
#'
#' @param force Logical. If TRUE, re-evaluates all completed games regardless of date.
#' @param out_dir Directory path where game detail JSON files are written.
#' @param today_date Date used for churn control 7-day evaluation window.
#' @param sched_df_override Optional schedule dataframe override (for testing).
#' @param ts_df_override Optional team stats dataframe override (for testing).
#' @param ps_df_override Optional player stats dataframe override (for testing).
#' @param sc_df_override Optional snap counts dataframe override (for testing).
#' @param matchups_path Path to matchups JSON file for forecast lookup (defaults to WEB_JSON_MATCHUPS_CURRENT_WEEK).
#' @param matchups_list Optional in-memory list of matchup objects from export_web_datasets.R (single-run pipeline guarantee).
#' @return Invisible summary list of evaluated, written, and skipped game counts.
build_game_details <- function(force = FALSE,
                               out_dir = WEB_GAMES_DIR,
                               today_date = Sys.Date(),
                               sched_df_override = NULL,
                               ts_df_override = NULL,
                               ps_df_override = NULL,
                               sc_df_override = NULL,
                               ros_df_override = NULL,
                               pred_log_df_override = NULL,
                               matchups_path = WEB_JSON_MATCHUPS_CURRENT_WEEK,
                               matchups_list = NULL) {
  log_info("Starting game details JSON builder...", call = "build_game_details()")

  if (!dir.exists(out_dir)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Load caches
  if (!is.null(sched_df_override)) {
    sched_df <- sched_df_override
  } else {
    if (!file.exists(CACHE_SCHEDULES)) {
      stop("CACHE_SCHEDULES not found: ", CACHE_SCHEDULES)
    }
    sched_df <- readRDS(CACHE_SCHEDULES) |> filter(season == CURRENT_SEASON)
  }

  ts_df <- if (!is.null(ts_df_override)) ts_df_override else if (file.exists(CACHE_TEAM_STATS)) readRDS(CACHE_TEAM_STATS) else NULL
  ps_df <- if (!is.null(ps_df_override)) ps_df_override else if (file.exists(CACHE_PLAYER_STATS)) readRDS(CACHE_PLAYER_STATS) else NULL
  sc_df <- if (!is.null(sc_df_override)) sc_df_override else if (file.exists(CACHE_SNAP_COUNTS)) readRDS(CACHE_SNAP_COUNTS) else NULL
  ros_df <- if (!is.null(ros_df_override)) ros_df_override else if (file.exists(CACHE_ROSTERS)) readRDS(CACHE_ROSTERS) else NULL
  inj_df <- if (file.exists(CACHE_INJURY_DATA)) readRDS(CACHE_INJURY_DATA) else NULL

  # Load PBP cache if available for efficiency factors
  pbp_df <- if (file.exists(CACHE_PBP)) readRDS(CACHE_PBP) else NULL

  # Load explainability and attribution caches
  pred_log_df <- if (!is.null(pred_log_df_override)) {
    pred_log_df_override
  } else if (file.exists(CACHE_PREDICTION_ACCURACY_LOG)) {
    tryCatch(readRDS(CACHE_PREDICTION_ACCURACY_LOG), error = function(e) NULL)
  } else NULL
  shap_df <- if (file.exists(CACHE_XGBOOST_SHAP)) {
    tryCatch(readRDS(CACHE_XGBOOST_SHAP), error = function(e) NULL)
  } else NULL
  team_eff_df <- .precompute_team_eff_metrics(pbp_df, CURRENT_SEASON)

  # Precompute GSIS to PFR ID crosswalk once
  gsis_to_pfr <- list()
  if (!is.null(ros_df) && nrow(ros_df) > 0) {
    r_valid <- ros_df |> filter(!is.na(gsis_id), !is.na(pfr_id)) |>
      distinct(gsis_id, .keep_all = TRUE)
    if (nrow(r_valid) > 0) {
      for (i in seq_len(nrow(r_valid))) {
        gsis_to_pfr[[r_valid$gsis_id[i]]] <- r_valid$pfr_id[i]
      }
    }
  }

  # Load matchups for forecast lookup if available (preferring in-memory matchups_list)
  forecast_map <- list()
  if (!is.null(matchups_list) && length(matchups_list) > 0) {
    for (m in matchups_list) {
      if (!is.null(m$game_id)) {
        forecast_map[[m$game_id]] <- m
      }
    }
  } else if (file.exists(matchups_path)) {
    tryCatch({
      m_json <- fromJSON(matchups_path, simplifyVector = FALSE)
      if (!is.null(m_json$matchups)) {
        for (m in m_json$matchups) {
          if (!is.null(m$game_id)) {
            forecast_map[[m$game_id]] <- m
          }
        }
      }
    }, error = function(e) {
      log_warn(sprintf("Failed to load forecast data from %s", matchups_path))
    })
  }

  # Identify completed games with box scores
  completed_games <- sched_df |>
    filter(!is.na(home_score), !is.na(away_score))

  n_eval <- 0
  n_written <- 0
  n_created <- 0
  n_unchanged <- 0
  n_skipped_churn <- 0
  updates <- list()

  today <- as.Date(today_date)

  for (i in seq_len(nrow(completed_games))) {
    g <- completed_games[i, ]
    gid <- as.character(g$game_id)
    out_file <- file.path(out_dir, sprintf("%s.json", gid))

    # Team stats and player stats for this game
    g_ts <- if (!is.null(ts_df) && "game_id" %in% names(ts_df)) ts_df |> filter(game_id == gid) else data.frame()
    g_ps <- if (!is.null(ps_df) && "game_id" %in% names(ps_df)) ps_df |> filter(game_id == gid) else data.frame()
    g_sc <- if (!is.null(sc_df) && "game_id" %in% names(sc_df)) sc_df |> filter(game_id == gid) else data.frame()
    g_pbp <- if (!is.null(pbp_df) && "game_id" %in% names(pbp_df)) pbp_df |> filter(game_id == gid) else NULL

    existed <- file.exists(out_file)
    has_box_score <- nrow(g_ts) > 0 || nrow(g_ps) > 0 || existed
    if (!has_box_score) {
      # Per spec: write one JSON file per completed game WITH box scores
      next
    }

    n_eval <- n_eval + 1

    away_tm <- as.character(g$away_team)
    home_tm <- as.character(g$home_team)

    has_box_score <- nrow(g_ts) > 0 || nrow(g_ps) > 0 || file.exists(out_file)
    if (!has_box_score) {
      # Per spec: write one JSON file per completed game WITH box scores
      next
    }

    away_score <- as.integer(g$away_score)
    home_score <- as.integer(g$home_score)

    away_ts_sub <- if (nrow(g_ts) > 0) g_ts |> filter(team == away_tm) else data.frame()
    home_ts_sub <- if (nrow(g_ts) > 0) g_ts |> filter(team == home_tm) else data.frame()

    # Forecast
    f_matchup <- forecast_map[[gid]]
    forecast_data <- NULL
    if (!is.null(f_matchup) && !identical(f_matchup$has_projection, FALSE) && !is.null(f_matchup$projected_margin)) {
      forecast_data <- list(
        projected_margin   = if (!is.null(f_matchup$projected_margin)) round(as.numeric(f_matchup$projected_margin), 1) + 0 else NULL,
        home_win_prob      = f_matchup$home_win_prob,
        away_win_prob      = f_matchup$away_win_prob,
        home_power_rating  = f_matchup$home_power_rating,
        away_power_rating  = f_matchup$away_power_rating,
        prediction_correct = f_matchup$prediction_correct
      )
    }

    # Gametime format HH:MM
    g_time <- if (!is.na(g$gametime) && grepl("^\\d{2}:\\d{2}$", g$gametime)) {
      as.character(g$gametime)
    } else {
      "13:00"
    }

    # If stats tables are not loaded but existing game file exists on disk, reuse existing box score payload
    existing_env <- NULL
    if (file.exists(out_file)) {
      existing_env <- tryCatch(fromJSON(out_file, simplifyVector = FALSE), error = function(e) NULL)
    }

    if (nrow(g_ts) == 0 && nrow(g_ps) == 0 && !is.null(existing_env$data)) {
      eff_factors  <- existing_env$data$efficiency_factors
      team_comp    <- existing_env$data$team_stats
      leaders      <- existing_env$data$leaders
      away_players <- if (!is.null(existing_env$data$box_score$away_players)) existing_env$data$box_score$away_players else list()
      home_players <- if (!is.null(existing_env$data$box_score$home_players)) existing_env$data$box_score$home_players else list()
      injuries     <- existing_env$data$injury_designations
      if (is.null(forecast_data)) {
        forecast_data <- existing_env$data$forecast
      }
    } else {
      # Build components from caches
      eff_factors <- .build_efficiency_factors(g_pbp, away_tm, home_tm)
      team_comp   <- .build_team_stats(away_ts_sub, home_ts_sub)
      leaders     <- .build_leaders(g_ps, away_tm, home_tm)

      away_players <- .build_player_box_rows(g_ps, away_tm, g_sc, gsis_to_pfr)
      home_players <- .build_player_box_rows(g_ps, home_tm, g_sc, gsis_to_pfr)

      injuries    <- .build_injury_designations(inj_df, as.integer(g$week), as.integer(g$season), away_tm, home_tm, g_ps, g_sc)
    }

    # Explainability & Attribution (Section 5.2, 5.4, 5.5)
    pred_row <- if (!is.null(pred_log_df)) {
      p_sub <- pred_log_df |> filter(game_id == gid)
      if (nrow(p_sub) > 0) p_sub[1, ] else NULL
    } else NULL
    shap_game <- if (!is.null(shap_df) && !is.null(shap_df$games[[gid]])) shap_df$games[[gid]] else NULL
    expl_data <- .build_game_explainability(gid, as.integer(g$season), as.integer(g$week), away_tm, home_tm, pred_row, shap_game, team_eff_df, is_completed = TRUE)

    # Current UTC timestamp
    gen_time <- format(as.POSIXlt(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ")

    payload <- list(
      game_id             = gid,
      season              = as.integer(g$season),
      season_label        = sprintf("%d-%d", as.integer(g$season), as.integer(g$season) + 1),
      week                = as.integer(g$week),
      week_label          = sprintf("Week %d", as.integer(g$week)),
      gameday             = as.character(g$gameday),
      weekday             = as.character(g$weekday),
      gametime            = g_time,
      is_completed        = TRUE,
      has_box_score       = TRUE,
      away_team           = list(
        teamAbbr  = away_tm,
        teamName  = unname(NFL_TEAMS[away_tm] %||% away_tm),
        score     = away_score,
        is_winner = (away_score > home_score)
      ),
      home_team           = list(
        teamAbbr  = home_tm,
        teamName  = unname(NFL_TEAMS[home_tm] %||% home_tm),
        score     = home_score,
        is_winner = (home_score > away_score)
      ),
      forecast            = forecast_data,
      efficiency_factors  = eff_factors,
      team_stats          = team_comp,
      leaders             = leaders,
      box_score           = list(
        away_players = away_players,
        home_players = home_players
      ),
      injury_designations = injuries,
      explainability      = expl_data
    )

    envelope <- list(
      schema_version    = "1.0",
      generated_at      = gen_time,
      sport             = "nfl",
      endpoint          = "game_detail",
      season            = as.integer(g$season),
      season_label      = sprintf("%d-%d", as.integer(g$season), as.integer(g$season) + 1),
      game_id           = gid,
      data              = payload
    )

    # Serialize candidate JSON
    candidate_json <- toJSON(envelope, auto_unbox = TRUE, pretty = 2, null = "null")

    # Idempotency check: compare candidate JSON bytes against existing file bytes ignoring generated_at
    if (existed) {
      existing_json <- paste(readLines(out_file, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
      # Strip generated_at from both
      strip_pattern <- '"generated_at"\\s*:\\s*"[^"]*",?'
      cand_clean <- gsub(strip_pattern, "", candidate_json)
      exist_clean <- gsub(strip_pattern, "", existing_json)

      if (isTRUE(trimws(cand_clean) == trimws(exist_clean))) {
        n_unchanged <- n_unchanged + 1
        next
      }
    }

    # Write file
    writeLines(candidate_json, out_file, useBytes = TRUE)
    n_written <- n_written + 1

    if (existed) {
      existing_env <- tryCatch(fromJSON(existing_json, simplifyVector = FALSE), error = function(e) NULL)
      change_desc <- .describe_game_detail_changes(existing_env, payload)
      g_date <- tryCatch(as.Date(g$gameday), error = function(e) NA)
      days_old <- if (!is.na(g_date)) as.integer(today - g_date) else NA_integer_
      log_info(sprintf(">>> Game detail %s (%s days old) updated: %s", gid, days_old, change_desc), call = "build_game_details()")
      updates[[length(updates) + 1L]] <- list(
        game_id  = gid,
        days_old = days_old,
        changes  = change_desc
      )
    } else {
      n_created <- n_created + 1
    }
  }

  log_info(sprintf("Game details builder completed: %d evaluated, %d written (%d created, %d updated), %d unchanged.",
                   n_eval, n_written, n_created, n_written - n_created, n_unchanged),
           call = "build_game_details()")

  # Export weekly attribution files for unplayed games (Section 3.2, Issue 2-6)
  n_weekly_written <- if (identical(out_dir, WEB_GAMES_DIR)) {
    .export_weekly_attribution(sched_df, pred_log_df, shap_df, team_eff_df, force = force)
  } else {
    0L
  }

  invisible(list(
    evaluated      = n_eval,
    written        = n_written,
    created        = n_created,
    updated        = n_written - n_created,
    unchanged      = n_unchanged,
    skipped_churn  = 0L,
    updates        = updates,
    weekly_written = n_weekly_written
  ))
}

if (sys.nframe() == 0L) {
  build_game_details(force = TRUE)
}
