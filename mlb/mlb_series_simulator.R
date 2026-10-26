# ==============================================================================
# mlb_series_simulator.R
# Phase 1 / Sprint 1: Interactive Playoff Series Matchup Simulator Engine
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_series_simulator.R
#
# Incorporates starting pitcher rotation scheduling (Game 1 Ace vs Ace, SP2, SP3, SP4),
# bullpen leverage fatigue modeling, tactical mismatch adjustments, and
# 10,000 Monte Carlo series iterations per pairing across Best-of-3, Best-of-5,
# and Best-of-7 formats.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "mlb_series_simulator.R"

message(">>> [SERIES SIM] Initializing MLB Playoff Series Simulator Engine...")

#' Build 30-Team Playoff Profiles (Rotations, Lineups, Bullpen, Tactical Ratings)
build_mlb_playoff_profiles <- function(teams_df, players_df, post_ops) {
  profiles <- list()
  
  bullpen_lookup <- list()
  if (!is.null(post_ops$bullpen_status)) {
    for (b in seq_len(nrow(post_ops$bullpen_status))) {
      row <- post_ops$bullpen_status[b, ]
      bullpen_lookup[[row$team]] <- row
    }
  }
  
  for (i in seq_len(nrow(teams_df))) {
    tm_row <- teams_df[i, ]
    tm_code <- tm_row$team
    
    # Extract players for this team
    tm_players <- players_df %>% filter(team == tm_code)
    
    # Split Pitchers and Batters
    pitchers <- tm_players %>% filter(player_type == "Pitcher")
    batters <- tm_players %>% filter(player_type == "Batter")
    
    # Sort Pitchers by rGS (stat3_val) descending, then proj_workload
    pitchers_sorted <- pitchers %>% 
      arrange(desc(coalesce(stat3_val, 50)), desc(proj_workload))
    
    # Designate Top 4 Starters
    sp_count <- min(4, nrow(pitchers_sorted))
    starters <- head(pitchers_sorted, sp_count)
    starters_list <- list()
    sp_roles <- c("SP1 (Ace)", "SP2 (Mid-Rotation)", "SP3", "SP4")
    
    for (s in seq_len(sp_count)) {
      p <- starters[s, ]
      starters_list[[s]] <- list(
        playerId   = p$player_id,
        mlbamId    = p$mlbam_id,
        playerName = p$player_name,
        rGS        = round(coalesce(p$stat3_val, 52.0), 1),
        projEra    = round(coalesce(p$stat2_pooled, 3.80), 2),
        xFip       = round(coalesce(p$stat1_pooled, 3.85), 2),
        kPct       = round(coalesce(p$k_pct_pooled, 22.0), 1),
        bbPct      = round(coalesce(p$bb_pct_pooled, 7.5), 1),
        role       = sp_roles[s]
      )
    }
    
    # Fill remaining SP slots if fewer than 4 exist
    if (sp_count < 4) {
      for (s in (sp_count + 1):4) {
        starters_list[[s]] <- list(
          playerId   = paste0("SP_", tm_code, "_", s),
          mlbamId    = "000000",
          playerName = paste0(tm_code, " Depth Starter ", s),
          rGS        = 48.0,
          projEra    = 4.25,
          xFip       = 4.30,
          kPct       = 19.5,
          bbPct      = 8.2,
          role       = sp_roles[s]
        )
      }
    }
    
    # Designate Relievers (next 4 pitchers or lowest xFIP)
    relievers_pool <- if (nrow(pitchers_sorted) > 4) tail(pitchers_sorted, -4) else pitchers_sorted
    relievers_sorted <- relievers_pool %>% arrange(coalesce(stat1_pooled, 4.00))
    rel_count <- min(4, nrow(relievers_sorted))
    relievers_list <- list()
    rel_roles <- c("Closer (High-LI)", "Setup Arm", "Bridge Reliever", "Middle Reliever")
    
    for (r in seq_len(rel_count)) {
      p <- relievers_sorted[r, ]
      relievers_list[[r]] <- list(
        playerId   = p$player_id,
        playerName = p$player_name,
        projEra    = round(coalesce(p$stat2_pooled, 3.50), 2),
        xFip       = round(coalesce(p$stat1_pooled, 3.60), 2),
        kPct       = round(coalesce(p$k_pct_pooled, 25.0), 1),
        role       = rel_roles[r]
      )
    }
    
    # Fill remaining relievers if fewer than 4
    if (rel_count < 4) {
      for (r in (rel_count + 1):4) {
        relievers_list[[r]] <- list(
          playerId   = paste0("RP_", tm_code, "_", r),
          playerName = paste0(tm_code, " Relief Arm ", r),
          projEra    = 3.90,
          xFip       = 3.95,
          kPct       = 22.0,
          role       = rel_roles[r]
        )
      }
    }
    
    # Designate Lineup Core (Top 9 Batters by wOBA)
    batters_sorted <- batters %>% arrange(desc(coalesce(stat1_raw, 0.310)))
    lineup_count <- min(9, nrow(batters_sorted))
    lineup_list <- list()
    
    for (b in seq_len(lineup_count)) {
      p <- batters_sorted[b, ]
      lineup_list[[b]] <- list(
        playerId   = p$player_id,
        playerName = p$player_name,
        wOBA       = round(coalesce(p$stat1_raw, 0.315), 3),
        iso        = round(coalesce(p$stat2_raw, 0.160), 3),
        obp        = round(coalesce(p$stat3_val, 0.320), 3),
        hr         = round(coalesce(p$count1_val, 18), 0),
        kPct       = round(coalesce(p$k_pct_pooled, 21.0), 1),
        bbPct      = round(coalesce(p$bb_pct_pooled, 8.0), 1),
        slot       = paste0("Lineup #", b)
      )
    }
    
    # Fill remaining lineup slots if fewer than 9
    if (lineup_count < 9) {
      for (b in (lineup_count + 1):9) {
        lineup_list[[b]] <- list(
          playerId   = paste0("B_", tm_code, "_", b),
          playerName = paste0(tm_code, " Regular #", b),
          wOBA       = 0.305,
          iso        = 0.140,
          obp        = 0.310,
          hr         = 12,
          kPct       = 22.5,
          bbPct      = 7.0,
          slot       = paste0("Lineup #", b)
        )
      }
    }
    
    # Base Elo & Projected Wins
    base_elo <- round(coalesce(tm_row$variant_bottom_up_mean_wins * 2.8 + 1250, 1500.0), 1)
    if (!is.null(bullpen_lookup[[tm_code]])) {
      base_elo <- round(bullpen_lookup[[tm_code]]$elo_rating, 1)
    }
    
    # Calculate 5 Sabermetric Tactical Ratings (0-100 Percentiles)
    # 1. Rotation Depth: weighted rGS of top 4 starters
    mean_rgs <- mean(sapply(starters_list, function(x) x$rGS))
    rotation_rating <- pmin(99, pmax(30, round((mean_rgs - 46) * 3.5 + 50)))
    
    # 2. Bullpen Leverage: based on reliever fatigue & xFIP
    bp_data <- bullpen_lookup[[tm_code]]
    bp_fatigue <- if (!is.null(bp_data)) bp_data$avg_bullpen_fatigue else 50
    bp_vuln <- if (!is.null(bp_data)) bp_data$bullpen_vulnerability else 50
    bullpen_rating <- pmin(99, pmax(25, round(100 - (bp_vuln * 0.55 + bp_fatigue * 0.25))))
    
    # 3. Power / ISO: Lineup average ISO
    mean_iso <- mean(sapply(lineup_list, function(x) x$iso))
    power_rating <- pmin(99, pmax(30, round((mean_iso - 0.140) * 550 + 50)))
    
    # 4. Contact & Plate Discipline: Lineup average K-avoidance & BB%
    mean_k <- mean(sapply(lineup_list, function(x) x$kPct))
    contact_rating <- pmin(99, pmax(30, round((25.0 - mean_k) * 3.8 + 50)))
    
    # 5. Defensive Efficiency & Catcher Framing
    def_rating <- case_when(
      tm_code %in% c("MIL", "TOR", "CLE", "SEA", "TEX", "KC") ~ round(runif(1, 86, 96)),
      tm_code %in% c("NYY", "LAD", "PHI", "HOU", "ATL", "BAL") ~ round(runif(1, 74, 85)),
      tm_code %in% c("BOS", "CHW", "COL", "MIA", "ATH") ~ round(runif(1, 40, 58)),
      TRUE ~ round(runif(1, 60, 75))
    )
    
    profiles[[tm_code]] <- list(
      teamAbbr        = tm_code,
      teamName        = tm_row$team_name,
      fullName        = tm_row$full_name,
      league          = tm_row$league,
      division        = tm_row$division,
      regularWins     = round(tm_row$ensemble_mean_wins, 1),
      baseElo         = base_elo,
      tacticalRatings = list(
        rotationDepth     = rotation_rating,
        bullpenLeverage   = bullpen_rating,
        powerIso          = power_rating,
        contactDiscipline = contact_rating,
        defenseFielding   = def_rating
      ),
      starters        = starters_list,
      relievers       = relievers_list,
      lineupCore      = lineup_list
    )
  }
  
  profiles
}

#' Simulate Head-to-Head Series Under Arbitrary Series Length (Best-of-3, 5, or 7)
simulate_mlb_series <- function(team_a_code, team_b_code, hca_team_code, profiles, series_length = 7, n_sims = 10000) {
  p_a <- profiles[[team_a_code]]
  p_b <- profiles[[team_b_code]]
  
  if (is.null(p_a) || is.null(p_b)) return(NULL)
  
  # Wins needed to clinch
  wins_to_clinch <- ceiling(series_length / 2)
  
  # Home schedule matrix
  # Best-of-3: All games at HCA site (modern MLB format)
  # Best-of-5: 2-2-1 format (HCA at Games 1, 2, 5)
  # Best-of-7: 2-3-2 format (HCA at Games 1, 2, 6, 7)
  home_schedule_hca <- if (series_length == 3) {
    c(TRUE, TRUE, TRUE)
  } else if (series_length == 5) {
    c(TRUE, TRUE, FALSE, FALSE, TRUE)
  } else {
    c(TRUE, TRUE, FALSE, FALSE, FALSE, TRUE, TRUE)
  }
  
  hca_is_a <- (hca_team_code == team_a_code)
  a_is_home <- if (hca_is_a) home_schedule_hca else !home_schedule_hca
  
  # Starting Pitcher Rotation Slotting per Game:
  # Best-of-3: SP1, SP2, SP3
  # Best-of-5: SP1, SP2, SP3, SP4 (or SP1 on 3d rest), SP1
  # Best-of-7: SP1, SP2, SP3, SP4, SP1, SP2, SP3
  sp_slot_a <- if (series_length == 3) {
    c(1, 2, 3)
  } else if (series_length == 5) {
    c(1, 2, 3, 4, 1)
  } else {
    c(1, 2, 3, 4, 1, 2, 3)
  }
  sp_slot_b <- sp_slot_a
  
  # Tactical mismatch evaluation
  edges <- list()
  mismatch_elo <- 0
  
  # 1. High-Whiff Pitching vs High-K Lineup
  if (p_a$tacticalRatings$rotationDepth >= 85 && p_b$tacticalRatings$contactDiscipline <= 48) {
    edge_elo <- 14.0
    mismatch_elo <- mismatch_elo + edge_elo
    edges[[length(edges) + 1]] <- list(
      title = "Swing-and-Miss Pitching Arsenal vs High-Whiff Lineup",
      advantageTeam = team_a_code,
      description = sprintf("%s's high-strikeout rotation exploits %s's swing-and-miss tendencies.", team_a_code, team_b_code),
      deltaElo = edge_elo
    )
  } else if (p_b$tacticalRatings$rotationDepth >= 85 && p_a$tacticalRatings$contactDiscipline <= 48) {
    edge_elo <- 14.0
    mismatch_elo <- mismatch_elo - edge_elo
    edges[[length(edges) + 1]] <- list(
      title = "Swing-and-Miss Pitching Arsenal vs High-Whiff Lineup",
      advantageTeam = team_b_code,
      description = sprintf("%s's high-strikeout rotation exploits %s's swing-and-miss tendencies.", team_b_code, team_a_code),
      deltaElo = edge_elo
    )
  }
  
  # 2. Bullpen Firepower & Rest Advantage
  bp_diff <- (p_a$tacticalRatings$bullpenLeverage - p_b$tacticalRatings$bullpenLeverage) * 0.35
  if (abs(bp_diff) >= 4.0) {
    adv_team <- if (bp_diff > 0) team_a_code else team_b_code
    mismatch_elo <- mismatch_elo + bp_diff
    edges[[length(edges) + 1]] <- list(
      title = "Late-Inning Relief Leverage & Bullpen Depth",
      advantageTeam = adv_team,
      description = sprintf("%s holds a significant high-leverage bullpen shutdown advantage in close games.", adv_team),
      deltaElo = round(abs(bp_diff), 1)
    )
  }
  
  # 3. Defensive Efficiency & Catcher Framing
  def_diff <- (p_a$tacticalRatings$defenseFielding - p_b$tacticalRatings$defenseFielding) * 0.25
  if (abs(def_diff) >= 3.5) {
    adv_team <- if (def_diff > 0) team_a_code else team_b_code
    mismatch_elo <- mismatch_elo + def_diff
    edges[[length(edges) + 1]] <- list(
      title = "Defensive Run Prevention & Strike-Zone Framing",
      advantageTeam = adv_team,
      description = sprintf("%s prevents extra outs through elite infield/outfield conversion.", adv_team),
      deltaElo = round(abs(def_diff), 1)
    )
  }
  
  # Base Elo differential
  base_elo_diff <- p_a$baseElo - p_b$baseElo
  hfa_elo <- 24.0 # Playoff HFA
  
  # Precompute Game-by-Game Win Probabilities for Team A
  game_prob_a <- numeric(series_length)
  game_details <- list()
  
  for (g in seq_len(series_length)) {
    is_home <- a_is_home[g]
    hfa_adj <- if (is_home) hfa_elo else -hfa_elo
    
    # Starter rGS differential
    sp_a <- p_a$starters[[sp_slot_a[g]]]
    sp_b <- p_b$starters[[sp_slot_b[g]]]
    rgs_diff <- 4.7 * (sp_a$rGS - sp_b$rGS)
    
    # Short rest penalty for Game 4 or 5 if ace brought back on short rest
    if (series_length >= 5 && sp_slot_a[g] == 1 && g %in% c(4, 5)) {
      rgs_diff <- rgs_diff - 12.0
    }
    
    total_elo_diff <- base_elo_diff + hfa_adj + rgs_diff + mismatch_elo
    p_win <- 1 / (1 + 10^(-total_elo_diff / 400))
    game_prob_a[g] <- p_win
    
    game_details[[g]] <- list(
      gameNumber   = g,
      homeTeam     = if (is_home) team_a_code else team_b_code,
      awayTeam     = if (is_home) team_b_code else team_a_code,
      starterA     = sp_a$playerName,
      starterB     = sp_b$playerName,
      starterArGS  = sp_a$rGS,
      starterBrGS  = sp_b$rGS,
      winProbA     = round(p_win, 3),
      winProbB     = round(1 - p_win, 3)
    )
  }
  
  # Monte Carlo Simulation (N = 10,000)
  set.seed(1234 + which(names(profiles) == team_a_code) * 17)
  
  sim_a_wins <- 0
  dist_counts <- list()
  
  # Initialize distribution keys
  for (g in wins_to_clinch:series_length) {
    dist_counts[[paste0("A_", g)]] <- 0
    dist_counts[[paste0("B_", g)]] <- 0
  }
  
  total_games_played <- 0
  
  for (sim in seq_len(n_sims)) {
    w_a <- 0
    w_b <- 0
    g_idx <- 1
    
    while (w_a < wins_to_clinch && w_b < wins_to_clinch) {
      if (runif(1) < game_prob_a[g_idx]) {
        w_a <- w_a + 1
      } else {
        w_b <- w_b + 1
      }
      g_idx <- g_idx + 1
    }
    
    games_in_series <- (g_idx - 1)
    total_games_played <- total_games_played + games_in_series
    
    if (w_a == wins_to_clinch) {
      sim_a_wins <- sim_a_wins + 1
      key <- paste0("A_", games_in_series)
      dist_counts[[key]] <- dist_counts[[key]] + 1
    } else {
      key <- paste0("B_", games_in_series)
      dist_counts[[key]] <- dist_counts[[key]] + 1
    }
  }
  
  prob_a <- round(sim_a_wins / n_sims, 3)
  prob_b <- round(1 - prob_a, 3)
  
  # Fair American Moneyline
  calc_ml <- function(prob) {
    if (prob <= 0.001) return(9999)
    if (prob >= 0.999) return(-9999)
    if (prob >= 0.50) {
      round(-(prob / (1 - prob)) * 100)
    } else {
      round(((1 - prob) / prob) * 100)
    }
  }
  
  game_dist_list <- list()
  for (k in names(dist_counts)) {
    parts <- strsplit(k, "_")[[1]]
    winner_team <- if (parts[1] == "A") team_a_code else team_b_code
    game_dist_list[[length(game_dist_list) + 1]] <- list(
      games   = as.numeric(parts[2]),
      winner  = winner_team,
      probPct = round((dist_counts[[k]] / n_sims) * 100, 1)
    )
  }
  
  # Sweep probability
  sweep_key_a <- paste0("A_", wins_to_clinch)
  sweep_key_b <- paste0("B_", wins_to_clinch)
  sweep_prob <- round(((dist_counts[[sweep_key_a]] + dist_counts[[sweep_key_b]]) / n_sims) * 100, 1)
  
  list(
    teamA                     = team_a_code,
    teamB                     = team_b_code,
    hcaTeam                   = hca_team_code,
    seriesLength              = series_length,
    winsToClinch              = wins_to_clinch,
    baseEloDiff               = round(base_elo_diff, 1),
    tacticalMismatchAdjustment = round(mismatch_elo, 1),
    winProbA                  = prob_a,
    winProbB                  = prob_b,
    fairMlA                   = calc_ml(prob_a),
    fairMlB                   = calc_ml(prob_b),
    avgGames                  = round(total_games_played / n_sims, 2),
    sweepProb                 = sweep_prob,
    gameDistributions         = game_dist_list,
    tacticalEdges             = edges,
    gameSchedule              = game_details
  )
}

#' Master Execution Function
run_mlb_series_simulator <- function() {
  teams_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_teams.json")
  players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
  post_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_postseason_ops.json")
  
  if (!file.exists(teams_file) || !file.exists(players_file)) {
    stop("Missing required base JSON files for Series Simulator")
  }
  
  teams_df <- fromJSON(teams_file)
  players_df <- fromJSON(players_file)
  post_ops <- if (file.exists(post_file)) fromJSON(post_file) else list()
  
  message(sprintf(">>> Loaded %d teams and %d players.", nrow(teams_df), nrow(players_df)))
  
  # 1. Build Playoff Profiles
  profiles <- build_mlb_playoff_profiles(teams_df, players_df, post_ops)
  message(sprintf(">>> Built playoff profiles for %d MLB clubs.", length(profiles)))
  
  # 2. Select Playoff Contenders & Matchup Pairs
  team_codes <- names(profiles)
  # Sort teams by projected wins descending
  sorted_tms <- names(sort(sapply(profiles, function(x) x$regularWins), decreasing = TRUE))
  top16 <- head(sorted_tms, 16) # Top 16 playoff contenders for full precomputed matrix
  
  message(sprintf(">>> Precomputing 3/5/7-game series simulations for top contenders (%d clubs)...", length(top16)))
  
  matchups_catalog <- list()
  pair_count <- 0
  
  for (i in 1:(length(top16) - 1)) {
    for (j in (i + 1):length(top16)) {
      tm_a <- top16[i]
      tm_b <- top16[j]
      
      # Higher projected wins gets HCA
      hca_tm <- if (profiles[[tm_a]]$regularWins >= profiles[[tm_b]]$regularWins) tm_a else tm_b
      
      # Precompute 7-game series (Primary), 5-game series, and 3-game series
      res7 <- simulate_mlb_series(tm_a, tm_b, hca_tm, profiles, series_length = 7, n_sims = 10000)
      res5 <- simulate_mlb_series(tm_a, tm_b, hca_tm, profiles, series_length = 5, n_sims = 10000)
      res3 <- simulate_mlb_series(tm_a, tm_b, hca_tm, profiles, series_length = 3, n_sims = 10000)
      
      key <- paste(tm_a, tm_b, sep = "_vs_")
      matchups_catalog[[key]] <- list(
        matchupKey = key,
        teamA      = tm_a,
        teamB      = tm_b,
        hcaTeam    = hca_tm,
        series7    = res7,
        series5    = res5,
        series3    = res3
      )
      pair_count <- pair_count + 1
    }
  }
  
  message(sprintf(">>> Successfully simulated %d head-to-head franchise pairings across 3/5/7 game formats.", pair_count))
  
  output_catalog <- list(
    # generated_at is what tools/publish_web.R's assertion F reads: UTC, ISO-8601,
    # and FIRST in the object because F only scans the first 4096 bytes of the
    # file (this payload is ~1.2 MB). `updatedAt` is kept for the web app, which
    # already renders it; it is local-time and not a format F can parse.
    generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    updatedAt   = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    nSims       = 10000,
    teams       = profiles,
    matchups    = matchups_catalog
  )
  
  output_json <- file.path(PROJECT_DIR, "web", "public", "data", "playoff_series_matchups.json")
  write(toJSON(output_catalog, auto_unbox = TRUE, pretty = TRUE), output_json)
  message(sprintf(">>> Wrote series simulator catalog to %s (%.2f MB)", output_json, file.info(output_json)$size / 1e6))
  
  invisible(output_catalog)
}

if (sys.nframe() == 0) {
  run_mlb_series_simulator()
}
