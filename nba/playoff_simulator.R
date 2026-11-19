# ==============================================================================
# playoff_simulator.R
# Phase 4 / Sprint 1 Upgrade: Comprehensive 7-Game Playoff Series Matchup Simulator
# Incorporates 8-man postseason rotation minute-tightening, deterministic empirical
# team tactical ratings (from Player DNA, Defensive Metrics, and Clutch eFG%),
# pairwise tactical mismatch adjustments, and 10,000 seeded Monte Carlo series
# iterations per matchup.
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

# Load baseline team, player, and empirical tactical datasets
teams_file <- WEB_JSON_PROJECTIONS_SEASON_TEAMS  # config.R
players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS  # config.R
dna_file <- WEB_JSON_PLAYER_DNA_PROFILES
defense_file <- WEB_JSON_DEFENSIVE_METRICS
clutch_file <- WEB_JSON_CLUTCH_LEVERAGE_METRICS

required_inputs <- c(teams_file, players_file, dna_file, defense_file, clutch_file)
missing_inputs <- required_inputs[!file.exists(required_inputs)]
if (length(missing_inputs) > 0) {
  stop(sprintf("Missing required input dataset(s): %s", paste(missing_inputs, collapse = ", ")))
}

unwrap_profiles <- function(obj, label) {
  if (is.data.frame(obj)) {
    return(obj)
  }
  if (is.list(obj) && !is.null(obj$profiles) && is.data.frame(obj$profiles)) {
    return(obj$profiles)
  }
  stop(sprintf("Unexpected JSON envelope in %s: expected data.frame or object with $profiles", label))
}

teams_df <- fromJSON(teams_file)
players_df <- fromJSON(players_file)
dna_profiles_df <- unwrap_profiles(fromJSON(dna_file), dna_file)
def_profiles_df <- unwrap_profiles(fromJSON(defense_file), defense_file)
clutch_profiles_df <- unwrap_profiles(fromJSON(clutch_file), clutch_file)

message(sprintf(
  ">>> Loaded %d teams, %d projected players, %d DNA profiles, %d defensive profiles, %d clutch profiles.",
  nrow(teams_df), nrow(players_df), nrow(dna_profiles_df), nrow(def_profiles_df), nrow(clutch_profiles_df)
))

# ------------------------------------------------------------------------------
# 1. Empirical Team Tactical Profiling & 8-Man Playoff Rotation
# ------------------------------------------------------------------------------
message(">>> Computing empirical team tactical ratings and 8-man playoff rotations...")

weighted_mean_safe <- function(vals, wts) {
  if (length(vals) == 0) return(NA_real_)
  vals_num <- suppressWarnings(as.numeric(vals))
  wts_num <- suppressWarnings(as.numeric(wts))
  ok <- is.finite(vals_num) & is.finite(wts_num) & wts_num > 0
  if (any(ok)) {
    return(sum(vals_num[ok] * wts_num[ok]) / sum(wts_num[ok]))
  }
  ok_v <- is.finite(vals_num)
  if (any(ok_v)) {
    return(mean(vals_num[ok_v]))
  }
  NA_real_
}

scale_rating <- function(x, lo, hi, metric_name = "metric") {
  x_num <- suppressWarnings(as.numeric(x))
  bad <- !is.finite(x_num)
  if (any(bad)) {
    med <- median(x_num[!bad], na.rm = TRUE)
    if (!is.finite(med)) med <- (lo + hi) / 2
    warning(sprintf("Empirical %s had %d missing/non-finite team value(s); filled with league median.", metric_name, sum(bad)))
    x_num[bad] <- med
  }
  rng <- range(x_num)
  if (diff(rng) == 0) {
    return(rep(as.integer(round((lo + hi) / 2)), length(x_num)))
  }
  as.integer(round(lo + ((x_num - rng[1]) / (rng[2] - rng[1])) * (hi - lo)))
}

compute_empirical_tactical_ratings <- function(team_codes, dna_profiles, def_profiles, clutch_profiles) {
  n_teams <- length(team_codes)
  raw_perim <- numeric(n_teams)
  raw_dropv <- numeric(n_teams)
  raw_inter <- numeric(n_teams)
  raw_switc <- numeric(n_teams)
  raw_clutc <- numeric(n_teams)

  for (idx in seq_len(n_teams)) {
    tc <- team_codes[idx]

    d_sub <- dna_profiles[dna_profiles$team == tc, , drop = FALSE]
    if (nrow(d_sub) > 0 && is.data.frame(d_sub$skillVector) && is.data.frame(d_sub$categoryScores)) {
      sv <- d_sub$skillVector
      cs <- d_sub$categoryScores
      p_player <- 0.60 * as.numeric(sv$pullup_3p) + 0.40 * as.numeric(sv$drive_ast)
      i_player <- 0.45 * as.numeric(cs$finishing) + 0.35 * as.numeric(cs$rebounding) + 0.20 * as.numeric(sv$rim_protection)
      raw_perim[idx] <- weighted_mean_safe(p_player, d_sub$projMpg)
      raw_inter[idx] <- weighted_mean_safe(i_player, d_sub$projMpg)
    } else {
      raw_perim[idx] <- NA_real_
      raw_inter[idx] <- NA_real_
    }

    df_sub <- def_profiles[def_profiles$team == tc, , drop = FALSE]
    if (nrow(df_sub) > 0) {
      raw_dropv[idx] <- weighted_mean_safe(-as.numeric(df_sub$dRapm), df_sub$projMpg)
      raw_switc[idx] <- weighted_mean_safe(as.numeric(df_sub$versatilityScore), df_sub$projMpg)
    } else {
      raw_dropv[idx] <- NA_real_
      raw_switc[idx] <- NA_real_
    }

    c_sub <- clutch_profiles[clutch_profiles$team == tc, , drop = FALSE]
    if (nrow(c_sub) > 0 && is.data.frame(c_sub$shotBreakdown)) {
      sb <- c_sub$shotBreakdown
      fga_vec <- suppressWarnings(as.numeric(sb$totalClutchFga))
      ok_c <- is.finite(fga_vec) & fga_vec > 0
      tot_fga <- sum(fga_vec[ok_c], na.rm = TRUE)
      if (tot_fga > 0 && is.data.frame(sb$rim) && is.data.frame(sb$mid) && is.data.frame(sb$three)) {
        rim_fgm <- sum(suppressWarnings(as.numeric(sb$rim$fgm[ok_c])), na.rm = TRUE)
        mid_fgm <- sum(suppressWarnings(as.numeric(sb$mid$fgm[ok_c])), na.rm = TRUE)
        three_fgm <- sum(suppressWarnings(as.numeric(sb$three$fgm[ok_c])), na.rm = TRUE)
        raw_clutc[idx] <- (rim_fgm + mid_fgm + 1.5 * three_fgm) / tot_fga
      } else {
        raw_clutc[idx] <- NA_real_
      }
    } else {
      raw_clutc[idx] <- NA_real_
    }
  }

  scaled_df <- data.frame(
    team = team_codes,
    perimeterCreation = scale_rating(raw_perim, 35, 95, "perimeterCreation"),
    dropVulnerability = scale_rating(raw_dropv, 20, 85, "dropVulnerability"),
    interiorDominance = scale_rating(raw_inter, 35, 95, "interiorDominance"),
    switchability     = scale_rating(raw_switc, 35, 95, "switchability"),
    clutchExecution   = scale_rating(raw_clutc, 35, 95, "clutchExecution"),
    stringsAsFactors  = FALSE
  )

  out <- list()
  for (idx in seq_len(n_teams)) {
    out[[team_codes[idx]]] <- list(
      perimeterCreation = scaled_df$perimeterCreation[idx],
      dropVulnerability = scaled_df$dropVulnerability[idx],
      interiorDominance = scaled_df$interiorDominance[idx],
      switchability     = scaled_df$switchability[idx],
      clutchExecution   = scaled_df$clutchExecution[idx]
    )
  }
  out
}

build_playoff_profiles <- function(teams, players, tactical_ratings_by_team) {
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
    
    # Deterministic empirical tactical archetype ratings (0-100) derived from
    # Player DNA, Defensive Metrics (-dRapm, versatilityScore), and Clutch eFG%.
    t_ratings <- tactical_ratings_by_team[[tm_code]]
    if (is.null(t_ratings)) {
      stop(sprintf("Missing empirical tactical ratings for team %s", tm_code))
    }

    profiles[[tm_code]] <- list(
      teamAbbr = tm_code,
      teamName = tm_row$team_name,
      conference = tm_row$conference,
      regularWins = round(tm_row$ensemble_mean_wins, 1),
      regularNetRtg = reg_net_rtg,
      playoffNetRtg = playoff_net_rtg,
      top3TalentBump = top3_bump,
      tacticalRatings = t_ratings,
      rotation = rotation_list
    )
  }
  
  profiles
}

empirical_tactical_ratings <- compute_empirical_tactical_ratings(
  teams_df$team,
  dna_profiles_df,
  def_profiles_df,
  clutch_profiles_df
)
team_profiles <- build_playoff_profiles(teams_df, players_df, empirical_tactical_ratings)

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
    } else {
      key <- paste0("B_", total_g)
      game_counts[[key]] <- game_counts[[key]] + 1
    }
  }
  
  win_prob_a <- round(sim_a_wins / n_sims, 4)
  win_prob_b <- round(1 - win_prob_a, 4)
  
  
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
    avgGames = round(total_games / n_sims, 2),
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
  # First in the object, for assertion F's 4096-byte head scan, and UTC with a
  # trailing Z because that is the only form .pw_payload_generated_at() parses.
  # PlayoffMatchupsCatalogSchema in web/tests/contracts/schemas.ts is .strict(),
  # so this key is declared there in the same change.
  #
  # This payload needs the stamp more than any other in the repo: the series
  # simulation is seeded per matchup (set.seed(42 + i * 10) above), so it is
  # deterministic and rewrites byte-identical content on every run. Its mtime
  # advances each run while its bytes have not changed since 2026-10-25, which
  # means assertion A -- an mtime check -- reports it FRESH on the strength of a
  # rewrite that carried no new information. A is structurally unable to tell
  # the difference. F now can.
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  teams = team_profiles,
  sampleMatchups = sample_matchup_results
)

out_rds <- if (exists("CACHE_PLAYOFF_SERIES")) CACHE_PLAYOFF_SERIES else file.path(CACHE_DIR, "playoff_series_cache.rds")
out_json <- WEB_JSON_PLAYOFF_SERIES_MATCHUPS  # config.R; the exists() fallback duplicated the path

message(sprintf(">>> Saving playoff simulation cache to: %s", out_rds))
saveRDS(output_catalog, out_rds)

message(sprintf(">>> Exporting public JSON for Next.js to: %s", out_json))
write_json(output_catalog, out_json, pretty = TRUE, auto_unbox = TRUE)

message(">>> [SUCCESS] Playoff Series Simulation Engine complete!")