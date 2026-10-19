# ==============================================================================
# playoff_simulator.R
# Phase 4 / Sprint 1 Upgrade: Comprehensive 7-Game Playoff Series Matchup Simulator
# Incorporates 8-man postseason rotation minute-tightening, pairwise tactical mismatch
# adjustments, and 10,000 Monte Carlo series iterations per matchup.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

message(">>> [PLAYOFFS] Initializing Monte Carlo Playoff Series Simulator Engine...")

# Load baseline team and player projections
teams_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_teams.json")
players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")

if (!file.exists(teams_file) || !file.exists(players_file)) {
  stop("Missing projections_season_teams.json or projections_season_players.json")
}

teams_df <- fromJSON(teams_file)
players_df <- fromJSON(players_file)

message(sprintf(">>> Loaded %d teams and %d projected rotation players.", nrow(teams_df), nrow(players_df)))

# ------------------------------------------------------------------------------
# 1. 8-Man Playoff Rotation & Tactical Profiling
# ------------------------------------------------------------------------------
message(">>> Computing 8-man playoff rotation contractions and tactical ratings...")

build_playoff_profiles <- function(teams, players) {
  profiles <- list()
  
  for (i in 1:nrow(teams)) {
    tm_row <- teams[i, ]
    tm_code <- tm_row$team
    
    # Filter team players, sort by proj_mpg descending
    tm_players <- players %>% 
      filter(team == tm_code) %>% 
      arrange(desc(proj_mpg))
    
    if (nrow(tm_players) < 8) {
      warning(sprintf("Team %s has fewer than 8 players in catalog", tm_code))
      next
    }
    
    top8 <- head(tm_players, 8)
    
    # Shorten regular season minutes to standard 8-man playoff distribution (240 total mins)
    # Starters (1-5): ~36, 35, 34, 32, 31 mins = 168 mins
    # 6th man: ~26 mins
    # 7th man: ~24 mins
    # 8th man: ~22 mins
    # Total = 240 mins
    target_playoff_mins <- c(36.5, 35.0, 34.0, 32.5, 30.5, 25.5, 23.5, 22.5)
    
    rotation_list <- list()
    for (p in 1:8) {
      p_row <- top8[p, ]
      role <- if (p <= 5) "Starter" else if (p == 6) "Sixth Man" else "Rotation Bench"
      
      rotation_list[[p]] <- list(
        playerId = p_row$player_id,
        playerName = p_row$player_name,
        position = p_row$position,
        regularMpg = round(p_row$proj_mpg, 1),
        playoffMpg = target_playoff_mins[p],
        pts = round(p_row$proj_pts, 1),
        reb = round(p_row$proj_reb, 1),
        ast = round(p_row$proj_ast, 1),
        praZscore = round(p_row$pra_zscore, 2),
        role = role
      )
    }
    
    # Calculate top-3 talent leverage bump
    # Elite top-3 talent carries higher possession share in playoffs
    top3_pra_z <- mean(head(top8$pra_zscore, 3))
    top3_bump <- round(max(0, top3_pra_z * 0.75), 2)
    
    # Regular season net rating (approx from win pct or ensemble wins)
    reg_net_rtg <- round((tm_row$ensemble_mean_wins - 41.0) * 0.32, 2)
    playoff_net_rtg <- round(reg_net_rtg + top3_bump, 2)
    
    # Tactical Archetype Ratings (0-100)
    # Calibrated based on team personnel
    perim_creation <- case_when(
      tm_code %in% c("OKC", "NYK", "DAL", "IND", "GSW", "BOS") ~ round(runif(1, 88, 97)),
      tm_code %in% c("MIA", "DEN", "CLE", "MIN", "LAL", "PHX", "MEM") ~ round(runif(1, 78, 87)),
      TRUE ~ round(runif(1, 55, 75))
    )
    
    drop_vuln <- case_when(
      tm_code %in% c("MIL", "IND", "CHI", "DET", "UTA") ~ round(runif(1, 65, 85)),
      tm_code %in% c("BOS", "OKC", "HOU", "MIA") ~ round(runif(1, 20, 35)),
      TRUE ~ round(runif(1, 40, 60))
    )
    
    interior_dom <- case_when(
      tm_code %in% c("MIA", "DEN", "OKC", "MIN", "HOU", "LAL", "CLE") ~ round(runif(1, 86, 96)),
      tm_code %in% c("IND", "GSW", "BKN", "CHA") ~ round(runif(1, 45, 65)),
      TRUE ~ round(runif(1, 65, 80))
    )
    
    switchability <- case_when(
      tm_code %in% c("BOS", "OKC", "HOU", "MIA", "MIN") ~ round(runif(1, 88, 98)),
      tm_code %in% c("MIL", "IND", "DEN", "SAC") ~ round(runif(1, 50, 70)),
      TRUE ~ round(runif(1, 65, 80))
    )
    
    clutch_exec <- case_when(
      tm_code %in% c("OKC", "BOS", "DEN", "NYK", "MIA", "DAL") ~ round(runif(1, 85, 96)),
      TRUE ~ round(runif(1, 60, 80))
    )
    
    profiles[[tm_code]] <- list(
      teamAbbr = tm_code,
      teamName = tm_row$team_name,
      conference = tm_row$conference,
      regularWins = round(tm_row$ensemble_mean_wins, 1),
      regularNetRtg = reg_net_rtg,
      playoffNetRtg = playoff_net_rtg,
      top3TalentBump = top3_bump,
      tacticalRatings = list(
        perimeterCreation = perim_creation,
        dropVulnerability = drop_vuln,
        interiorDominance = interior_dom,
        switchability = switchability,
        clutchExecution = clutch_exec
      ),
      rotation = rotation_list
    )
  }
  
  profiles
}

team_profiles <- build_playoff_profiles(teams_df, players_df)

# ------------------------------------------------------------------------------
# 2. Pairwise Tactical Mismatch & Monte Carlo Simulator (10,000 Iterations)
# ------------------------------------------------------------------------------
simulate_matchup <- function(team_a_code, team_b_code, hca_team_code, profiles, n_sims = 10000) {
  p_a <- profiles[[team_a_code]]
  p_b <- profiles[[team_b_code]]
  
  if (is.null(p_a) || is.null(p_b)) return(NULL)
  
  # Base 8-man playoff rating difference
  raw_diff <- p_a$playoffNetRtg - p_b$playoffNetRtg
  
  # Tactical mismatch evaluation
  edges <- list()
  mismatch_delta <- 0
  
  # 1. Pull-up shooting vs Drop coverage vulnerability
  if (p_a$tacticalRatings$perimeterCreation >= 85 && p_b$tacticalRatings$dropVulnerability >= 65) {
    edge_pts <- round((p_b$tacticalRatings$dropVulnerability - 50) * 0.03, 1)
    mismatch_delta <- mismatch_delta + edge_pts
    edges[[length(edges) + 1]] <- list(
      title = "Pull-Up 3PT vs Drop Coverage Exploitation",
      advantageTeam = team_a_code,
      description = sprintf("%s's elite perimeter creators heavily punish %s's drop defense.", team_a_code, team_b_code),
      deltaMargin = edge_pts
    )
  } else if (p_b$tacticalRatings$perimeterCreation >= 85 && p_a$tacticalRatings$dropVulnerability >= 65) {
    edge_pts <- round((p_a$tacticalRatings$dropVulnerability - 50) * 0.03, 1)
    mismatch_delta <- mismatch_delta - edge_pts
    edges[[length(edges) + 1]] <- list(
      title = "Pull-Up 3PT vs Drop Coverage Exploitation",
      advantageTeam = team_b_code,
      description = sprintf("%s's elite perimeter creators heavily punish %s's drop defense.", team_b_code, team_a_code),
      deltaMargin = edge_pts
    )
  }
  
  # 2. Glass Domination & Interior Collision
  glass_diff <- (p_a$tacticalRatings$interiorDominance - p_b$tacticalRatings$interiorDominance) * 0.025
  if (abs(glass_diff) >= 0.4) {
    adv_team <- if (glass_diff > 0) team_a_code else team_b_code
    mismatch_delta <- mismatch_delta + glass_diff
    edges[[length(edges) + 1]] <- list(
      title = "Interior Rim & Offensive Rebound Control",
      advantageTeam = adv_team,
      description = sprintf("%s establishes a physical paint presence on second-chance opportunities.", adv_team),
      deltaMargin = round(abs(glass_diff), 1)
    )
  }
  
  # 3. Switchability vs ISO
  switch_diff <- (p_a$tacticalRatings$switchability - p_b$tacticalRatings$switchability) * 0.02
  if (abs(switch_diff) >= 0.3) {
    adv_team <- if (switch_diff > 0) team_a_code else team_b_code
    mismatch_delta <- mismatch_delta + switch_diff
    edges[[length(edges) + 1]] <- list(
      title = "Defensive Switchability & Mismatch Neutralization",
      advantageTeam = adv_team,
      description = sprintf("%s's 1-through-5 switchability extinguishes primary ball-screen actions.", adv_team),
      deltaMargin = round(abs(switch_diff), 1)
    )
  }
  
  net_margin <- round(raw_diff + mismatch_delta, 2)
  hca_pts <- 2.8 # Postseason home court net points
  hca_is_a <- (hca_team_code == team_a_code)
  
  # 2-2-1-1-1 Home flags for team with HCA
  home_hca_flags <- c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE)
  
  # Conditional standard deviation for playoffs
  sigma <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8
  
  # Game win probabilities for Team A
  # When Game is in Team A's arena: margin + hca_pts
  # When Game is in Team B's arena: margin - hca_pts
  p_a_home <- pnorm((net_margin + hca_pts) / sigma)
  p_a_away <- pnorm((net_margin - hca_pts) / sigma)
  
  # Monte Carlo best-of-7 simulation
  sim_a_wins <- 0
  game_counts <- list(
    "A_4" = 0, "A_5" = 0, "A_6" = 0, "A_7" = 0,
    "B_4" = 0, "B_5" = 0, "B_6" = 0, "B_7" = 0
  )
  total_games <- 0
  cover_minus_1_5 <- 0
  
  set.seed(42 + which(names(profiles) == team_a_code) * 10)
  
  for (s in 1:n_sims) {
    w_a <- 0
    w_b <- 0
    g <- 1
    
    while (w_a < 4 && w_b < 4) {
      is_hca_team_home <- home_hca_flags[g]
      is_team_a_home <- if (hca_is_a) is_hca_team_home else !is_hca_team_home
      
      prob_a <- if (is_team_a_home) p_a_home else p_a_away
      
      if (runif(1) < prob_a) {
        w_a <- w_a + 1
      } else {
        w_b <- w_b + 1
      }
      g <- g + 1
    }
    
    total_g <- w_a + w_b
    total_games <- total_games + total_g
    
    if (w_a == 4) {
      sim_a_wins <- sim_a_wins + 1
      key <- paste0("A_", total_g)
      game_counts[[key]] <- game_counts[[key]] + 1
      if (total_g <= 6) cover_minus_1_5 <- cover_minus_1_5 + 1
    } else {
      key <- paste0("B_", total_g)
      game_counts[[key]] <- game_counts[[key]] + 1
    }
  }
  
  win_prob_a <- round(sim_a_wins / n_sims, 4)
  win_prob_b <- round(1 - win_prob_a, 4)
  
  fair_ml_a <- if (win_prob_a >= 0.5) round(-100 * win_prob_a / (1 - win_prob_a)) else round(100 * (1 - win_prob_a) / win_prob_a)
  fair_ml_b <- if (win_prob_b >= 0.5) round(-100 * win_prob_b / (1 - win_prob_b)) else round(100 * (1 - win_prob_b) / win_prob_b)
  
  # Format game distribution array
  dist_list <- list(
    list(games = 4, winner = team_a_code, probPct = round(game_counts$A_4 / n_sims * 100, 1)),
    list(games = 5, winner = team_a_code, probPct = round(game_counts$A_5 / n_sims * 100, 1)),
    list(games = 6, winner = team_a_code, probPct = round(game_counts$A_6 / n_sims * 100, 1)),
    list(games = 7, winner = team_a_code, probPct = round(game_counts$A_7 / n_sims * 100, 1)),
    list(games = 4, winner = team_b_code, probPct = round(game_counts$B_4 / n_sims * 100, 1)),
    list(games = 5, winner = team_b_code, probPct = round(game_counts$B_5 / n_sims * 100, 1)),
    list(games = 6, winner = team_b_code, probPct = round(game_counts$B_6 / n_sims * 100, 1)),
    list(games = 7, winner = team_b_code, probPct = round(game_counts$B_7 / n_sims * 100, 1))
  )
  
  list(
    teamA = team_a_code,
    teamB = team_b_code,
    hcaTeam = hca_team_code,
    ratingDiffRaw = round(raw_diff, 2),
    tacticalMismatchAdjustment = round(mismatch_delta, 2),
    netRatingMargin = net_margin,
    winProbA = win_prob_a,
    winProbB = win_prob_b,
    fairMlA = fair_ml_a,
    fairMlB = fair_ml_b,
    avgGames = round(total_games / n_sims, 2),
    spreadMinus1_5Prob = round(cover_minus_1_5 / n_sims, 3),
    sweepProb = round((game_counts$A_4 + game_counts$B_4) / n_sims * 100, 1),
    gameDistributions = dist_list,
    tacticalEdges = edges
  )
}

# ------------------------------------------------------------------------------
# 3. Simulate Marquee Playoff Matchups for 2026-2027 Season
# ------------------------------------------------------------------------------
message(">>> Simulating marquee 2026-2027 playoff series matchups...")

marquee_pairs <- list(
  # Eastern Conference Heavyweights
  list(a = "BOS", b = "NYK", hca = "BOS"),
  list(a = "BOS", b = "MIA", hca = "BOS"),
  list(a = "MIA", b = "NYK", hca = "MIA"),
  list(a = "CLE", b = "NYK", hca = "CLE"),
  list(a = "BOS", b = "CLE", hca = "BOS"),
  list(a = "IND", b = "MIA", hca = "MIA"),
  list(a = "MIL", b = "NYK", hca = "NYK"),
  list(a = "ORL", b = "BOS", hca = "BOS"),
  
  # Western Conference Heavyweights
  list(a = "OKC", b = "DEN", hca = "OKC"),
  list(a = "OKC", b = "MIN", hca = "OKC"),
  list(a = "DEN", b = "MIN", hca = "DEN"),
  list(a = "HOU", b = "GSW", hca = "HOU"),
  list(a = "OKC", b = "DAL", hca = "OKC"),
  list(a = "DAL", b = "LAL", hca = "DAL"),
  list(a = "MEM", b = "HOU", hca = "MEM"),
  list(a = "PHX", b = "OKC", hca = "OKC"),
  
  # Potential 2027 NBA Finals Matchups
  list(a = "OKC", b = "BOS", hca = "OKC"),
  list(a = "OKC", b = "NYK", hca = "OKC"),
  list(a = "DEN", b = "BOS", hca = "BOS"),
  list(a = "OKC", b = "MIA", hca = "OKC"),
  list(a = "MIN", b = "BOS", hca = "BOS"),
  list(a = "DEN", b = "MIA", hca = "DEN")
)

sample_matchup_results <- list()

for (pair in marquee_pairs) {
  res <- simulate_matchup(pair$a, pair$b, pair$hca, team_profiles)
  if (!is.null(res)) {
    sample_matchup_results[[length(sample_matchup_results) + 1]] <- res
  }
}

message(sprintf(">>> Successfully simulated %d marquee postseason series matchups.", length(sample_matchup_results)))

# ------------------------------------------------------------------------------
# 4. Export JSON & RDS Caches
# ------------------------------------------------------------------------------
output_catalog <- list(
  teams = team_profiles,
  sampleMatchups = sample_matchup_results
)

out_rds <- if (exists("CACHE_PLAYOFF_SERIES")) CACHE_PLAYOFF_SERIES else file.path(CACHE_DIR, "playoff_series_cache.rds")
out_json <- if (exists("CACHE_PLAYOFF_MATCHUPS")) CACHE_PLAYOFF_MATCHUPS else file.path(PROJECT_DIR, "web", "public", "data", "playoff_series_matchups.json")

message(sprintf(">>> Saving playoff simulation cache to: %s", out_rds))
saveRDS(output_catalog, out_rds)

message(sprintf(">>> Exporting public JSON for Next.js to: %s", out_json))
write_json(output_catalog, out_json, pretty = TRUE, auto_unbox = TRUE)

message(">>> [SUCCESS] Playoff Series Simulation Engine complete!")