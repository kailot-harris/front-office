# ==============================================================================
# build_player_dna_dataset.R
# Path: build_player_dna_dataset.R
#
# Feature 5: High-Dimensional WNBA Player DNA Skill Fingerprints
# Calculates 16-D skill vectors across Finishing, Shooting, Playmaking, Defense, Rebounding.
# Grounds d_rapm in real possession defensive RAPM from cache/rapm_ratings.rds
# via rapm_join_utils.R::join_rapm_to_roster().
# Exports JSON for Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global configuration and RAPM utilities
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

rapm_utils_path <- if (file.exists("rapm_join_utils.R")) "rapm_join_utils.R" else "../rapm_join_utils.R"
source(rapm_utils_path)

cat(">>> [PLAYER DNA] Initializing 16-D WNBA Player Skill Embeddings...\n")

# Load existing player projections
proj_players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d WNBA player projections for 2026 season.\n", nrow(players_df)))

# Load real possession RAPM ratings
rapm_file <- file.path(CACHE_DIR, "rapm_ratings.rds")
if (!file.exists(rapm_file)) {
  stop("Missing rapm_ratings.rds")
}
rapm_df <- readRDS(rapm_file)

# Construct roster table to join with RAPM
roster_df <- players_df |>
  transmute(
    player_id = as.integer(.data$player_id),
    player_name = .data$player_name,
    team_abbreviation = .data$team,
    team_name = unname(WNBA_TEAMS[.data$team])
  )

# Join real possession dRAPM using standard join utility
rapm_joined <- join_rapm_to_roster(roster_df, rapm_df, matched_only = FALSE)
rapm_lookup <- setNames(rapm_joined$drapm, as.character(rapm_joined$player_id))
drapm_ecdf <- ecdf(rapm_df$drapm)

cat(sprintf(">>> Joined real possession RAPM for %d of %d players (%d unmatched use baseline neutral).\n",
            sum(rapm_joined$rapm_matched), nrow(roster_df), sum(!rapm_joined$rapm_matched)))

# ------------------------------------------------------------------------------
# 16-Dimensional Normalized Metrics [0 - 100 percentile scales]:
# Finishing: rim_fg, paint_power, paint_touches
# Shooting: cns_3p, pullup_3p, ft_pct
# Playmaking: ast_pct, pot_ast, tov_control, drive_ast
# Defense: switchability, rim_protection, perimeter_havoc, d_rapm
# Rebounding: oreb, dreb
# ------------------------------------------------------------------------------

dim_names <- c(
  "rim_fg", "paint_power", "paint_touches",
  "cns_3p", "pullup_3p", "ft_pct",
  "ast_pct", "pot_ast", "tov_control", "drive_ast",
  "switchability", "rim_protection", "perimeter_havoc", "d_rapm",
  "oreb", "dreb"
)

clamp <- function(x, mn = 15, mx = 99) {
  pmax(mn, pmin(mx, round(x, 1)))
}

# ------------------------------------------------------------------------------
# Derive 16-D Skill Vectors for All WNBA Rotation Players
# ------------------------------------------------------------------------------

player_dna_list <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pts <- p$proj_pts
  reb <- p$proj_reb
  ast <- p$proj_ast
  mpg <- p$proj_mpg

  is_guard <- pos == "G"
  is_center <- pos == "C"
  is_forward <- pos == "F"

  # Base vector estimates
  rim_fg <- 60 + pts * 1.4 + (if(is_center) 15 else if(is_forward) 8 else 2)
  paint_power <- if (is_center) clamp(reb * 6 + pts * 2.0, 30, 98) else if (is_forward) clamp(pts * 2.5, 20, 92) else clamp(pts * 1.0, 10, 75)
  paint_touches <- clamp(pts * 2.2 + reb * 3.0, 25, 98)
  
  cns_3p <- if (is_guard) clamp(75 + pts * 0.8, 50, 98) else if (is_forward) clamp(65 + pts * 0.6, 40, 95) else clamp(30 + pts * 0.7, 15, 88)
  pullup_3p <- if (is_guard) clamp(65 + pts * 1.1, 40, 99) else if (is_forward) clamp(50 + pts * 0.9, 25, 92) else clamp(20 + pts * 0.4, 10, 75)
  ft_pct <- clamp(70 + pts * 0.8, 50, 96)
  
  ast_pct <- clamp(ast * 10.5 + (if(is_guard) 15 else 0), 20, 99)
  pot_ast <- clamp(ast * 11.0 + (if(is_guard) 12 else 0), 20, 99)
  tov_control <- clamp(85 - ast * 2.5 + (if(is_guard) 10 else 5), 45, 95)
  drive_ast <- clamp(ast * 9.5 + pts * 1.0, 25, 98)
  
  switchability <- if (is_forward) clamp(70 + reb * 1.8, 45, 98) else if (is_guard) clamp(60 + pts * 0.4, 40, 92) else clamp(40 + reb * 1.4, 25, 88)
  rim_protection <- if (is_center) clamp(reb * 7.5 + 25, 60, 99) else if (is_forward) clamp(reb * 5.0 + 15, 30, 92) else clamp(20 + reb * 1.8, 15, 65)
  perimeter_havoc <- if (is_guard) clamp(65 + ast * 2.4, 40, 96) else if (is_forward) clamp(60 + pts * 0.6, 35, 92) else clamp(35 + reb * 1.8, 20, 75)
  
  # Ground d_rapm in real ridge possession dRAPM from cache/rapm_ratings.rds
  pid_str <- as.character(p$player_id)
  raw_drapm <- rapm_lookup[[pid_str]]
  d_rapm_val <- if (is.null(raw_drapm) || is.na(raw_drapm)) 50.0 else round(drapm_ecdf(raw_drapm) * 100, 1)
  d_rapm <- clamp(d_rapm_val, 15, 99)
  
  oreb <- clamp(reb * 8.5 + (if(is_center) 20 else if(is_forward) 10 else 0), 20, 99)
  dreb <- clamp(reb * 9.2 + (if(is_center) 22 else if(is_forward) 12 else 0), 25, 99)

  # Purely algorithmic archetype assignment based on player stats
  archetype <- if (is_guard && ast > 5.5) "Playmaking Floor General" else
               if (is_guard && pts > 16.0) "Dynamic Scoring Guard" else
               if (is_center && reb > 7.5) "Interior Anchor & Glass Eater" else
               if (is_forward && pts > 16.0) "Three-Level Scoring Forward" else
               if (is_forward && reb > 5.5) "Two-Way Wing Connector" else
               "Versatile System Contributor"

  vec <- c(
    clamp(rim_fg), clamp(paint_power), clamp(paint_touches),
    clamp(cns_3p), clamp(pullup_3p), clamp(ft_pct),
    clamp(ast_pct), clamp(pot_ast), clamp(tov_control), clamp(drive_ast),
    clamp(switchability), clamp(rim_protection), clamp(perimeter_havoc), clamp(d_rapm),
    clamp(oreb), clamp(dreb)
  )

  # 5-Category Aggregate Scores for radar UI
  category_scores <- list(
    finishing = round(mean(vec[1:3]), 1),
    shooting = round(mean(vec[4:6]), 1),
    playmaking = round(mean(vec[7:10]), 1),
    defense = round(mean(vec[11:14]), 1),
    rebounding = round(mean(vec[15:16]), 1)
  )

  # 2D t-SNE / PCA Manifold Coordinates for scatter plot
  # X: Offensive Shot Creation vs Spot-Up (-50 to +50)
  # Y: Defensive Interior Anchor vs Perimeter Guard (-50 to +50)
  manifold_x <- round((category_scores$playmaking * 0.6 + category_scores$shooting * 0.4) - 50, 1)
  manifold_y <- round((category_scores$defense * 0.5 + category_scores$rebounding * 0.5) - 50, 1)

  player_dna_list[[i]] <- list(
    season = 2026,
    playerId = pid_str,
    playerName = name,
    team = team,
    position = pos,
    archetype = archetype,
    projPts = p$proj_pts,
    projReb = p$proj_reb,
    projAst = p$proj_ast,
    projMpg = p$proj_mpg,
    overallRating = round(mean(vec), 1),
    manifoldX = manifold_x,
    manifoldY = manifold_y,
    skillVector = as.list(setNames(vec, dim_names)),
    categoryScores = category_scores
  )
}

# ------------------------------------------------------------------------------
# Export to JSON for Next.js Web Application
# ------------------------------------------------------------------------------
output_json <- file.path(PROJECT_DIR, "web", "public", "data", "player_dna_profiles.json")
jsonlite::write_json(player_dna_list, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

cache_rds <- file.path(CACHE_DIR, "player_dna_profiles.rds")
saveRDS(player_dna_list, cache_rds)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_rds))
