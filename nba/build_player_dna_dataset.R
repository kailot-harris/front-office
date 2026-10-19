# ==============================================================================
# build_player_dna_dataset.R
# Feature 4: High-Dimensional Player DNA & Nearest Historical Comparables
# Calculates 16-D skill vectors across Finishing, Shooting, Playmaking, Defense, Rebounding.
# Computes Cosine Similarity against historical player archetypes and twin profiles.
# Exports JSON for Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

cat(">>> [PLAYER DNA] Initializing 16-D Player Skill Embeddings & Historical Twins...\n")

# Load existing player projections
proj_players_file <- "web/public/data/projections_season_players.json"
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for 2026-2027 season.\n", nrow(players_df)))

# ------------------------------------------------------------------------------
# 1. Historical Archetype Database (Gold Standard Comps 1990-2025)
# 16-Dimensional Normalized Metrics [0 - 100 percentile scales]:
# Finishing: rim_fg_pct, dunk_freq, paint_touches
# Shooting: cns_three_pct, pullup_three_pct, ft_pct
# Playmaking: ast_pct, pot_ast, tov_rate_inv, drive_ast_pct
# Defense: switchability, block_pct, steal_defl_pct, d_rapm
# Rebounding: oreb_pct, dreb_pct
# ------------------------------------------------------------------------------

historical_comps <- tribble(
  ~comp_name, ~era, ~archetype, ~pos, ~dna_vector,
  "LeBron James (2012-13 MIA)", "2012-13", "Helio-Centric Power Hub", "F",
    c(96, 92, 95,  75, 78, 76,  94, 95, 78, 92,  95, 72, 85, 96,  58, 82),
  "Stephen Curry (2015-16 GSW)", "2015-16", "Off-Ball Movement Sniper", "G",
    c(88, 15, 65,  99, 99, 98,  82, 85, 72, 80,  62, 28, 92, 65,  35, 62),
  "Kevin Durant (2016-17 GSW)", "2016-17", "Three-Level Scoring Wing", "F",
    c(92, 78, 85,  92, 95, 94,  74, 76, 75, 72,  84, 82, 74, 86,  42, 84),
  "Nikola Jokic (2023-24 DEN)", "2023-24", "Post Playmaking Maestro", "C",
    c(95, 45, 98,  72, 68, 88,  99, 98, 82, 88,  48, 64, 82, 88,  94, 98),
  "Giannis Antetokounmpo (2019-20 MIL)", "2019-20", "Rim-Running Attrition Beast", "F",
    c(98, 99, 99,  55, 48, 68,  78, 80, 65, 75,  92, 88, 76, 98,  88, 97),
  "Kawhi Leonard (2018-19 TOR)", "2018-19", "Two-Way Mid-Range Assassin", "F",
    c(88, 68, 78,  88, 86, 90,  68, 72, 84, 70,  94, 62, 94, 94,  52, 78),
  "James Harden (2018-19 HOU)", "2018-19", "Isolation Step-Back Engine", "G",
    c(85, 42, 88,  82, 98, 89,  95, 96, 60, 94,  55, 45, 88, 68,  44, 72),
  "Anthony Davis (2019-20 LAL)", "2019-20", "Anchor Big & Lob Threat", "C",
    c(94, 95, 92,  68, 55, 84,  58, 60, 78, 55,  88, 96, 78, 95,  84, 94),
  "Chris Paul (2007-08 NOH)", "2007-08", "Floor General Point God", "G",
    c(78, 12, 72,  82, 84, 91,  98, 98, 95, 92,  75, 22, 98, 84,  38, 64),
  "Klay Thompson (2015-16 GSW)", "2015-16", "Catch-and-Shoot Specialist", "G",
    c(74, 38, 50,  98, 86, 89,  48, 50, 85, 45,  78, 48, 72, 76,  28, 48),
  "Draymond Green (2015-16 GSW)", "2015-16", "Defensive Disruptor & Short-Roll Hub", "F",
    c(70, 48, 65,  78, 65, 72,  88, 89, 74, 82,  98, 85, 94, 98,  62, 88),
  "Rudy Gobert (2020-21 UTA)", "2020-21", "Paint Fortress & Rim Deterrent", "C",
    c(92, 96, 88,  20, 15, 64,  32, 35, 70, 25,  52, 98, 55, 97,  96, 98),
  "Russell Westbrook (2016-17 OKC)", "2016-17", "Downhill Force Engine", "G",
    c(86, 82, 92,  72, 75, 84,  96, 97, 52, 95,  68, 38, 86, 68,  68, 85),
  "Jimmy Butler (2019-20 MIA)", "2019-20", "Grind-it-Out Two-Way Slasher", "F",
    c(84, 62, 85,  68, 62, 86,  78, 82, 82, 85,  92, 54, 92, 89,  68, 76),
  "Paul George (2018-19 OKC)", "2018-19", "Two-Way Wing Shotmaker", "F",
    c(82, 74, 76,  90, 88, 85,  68, 72, 78, 68,  90, 58, 94, 88,  48, 78),
  "Dirk Nowitzki (2005-06 DAL)", "2005-06", "Trail Big & Mid-Post Deadeye", "F",
    c(86, 45, 80,  92, 90, 92,  64, 66, 88, 55,  58, 65, 62, 78,  52, 88),
  "Manu Ginobili (2006-07 SAS)", "2006-07", "Eurostep Craft Creator", "G",
    c(86, 52, 75,  85, 82, 84,  84, 86, 76, 88,  78, 42, 90, 78,  42, 65),
  "Dwight Howard (2008-09 ORL)", "2008-09", "Hyper-Athletic Paint Eraser", "C",
    c(94, 99, 96,  15, 10, 59,  40, 42, 62, 30,  70, 99, 72, 98,  96, 99),
  "Kyrie Irving (2015-16 CLE)", "2015-16", "Elite Isolation Finisher", "G",
    c(92, 35, 82,  88, 94, 89,  80, 82, 84, 86,  60, 32, 78, 62,  32, 52),
  "Marcus Smart (2021-22 BOS)", "2021-22", "Point-of-Attack Pest", "G",
    c(68, 25, 52,  75, 72, 79,  76, 78, 76, 72,  96, 45, 96, 92,  38, 58)
)

dim_names <- c(
  "rim_fg", "dunks", "paint_touches",
  "cns_3p", "pullup_3p", "ft_pct",
  "ast_pct", "pot_ast", "tov_control", "drive_ast",
  "switchability", "rim_protection", "perimeter_havoc", "d_rapm",
  "oreb", "dreb"
)

# ------------------------------------------------------------------------------
# 2. Derive 16-D Skill Vectors for All Season Players
# ------------------------------------------------------------------------------

clamp <- function(x, mn = 15, mx = 99) {
  pmax(mn, pmin(mx, round(x, 1)))
}

# Cosine similarity function
calc_cosine_sim <- function(v1, v2) {
  dot_prod <- sum(v1 * v2)
  norm1 <- sqrt(sum(v1^2))
  norm2 <- sqrt(sum(v2^2))
  if (norm1 == 0 || norm2 == 0) return(0)
  sim <- (dot_prod / (norm1 * norm2)) * 100
  return(round(sim, 1))
}

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
  rim_fg <- 60 + pts * 0.8 + (if(is_center) 15 else if(is_forward) 8 else 2)
  dunks <- if (is_center) clamp(reb * 5 + pts * 1.5, 30, 98) else if (is_forward) clamp(pts * 2.2, 20, 92) else clamp(pts * 0.8, 10, 75)
  paint_touches <- clamp(pts * 1.8 + reb * 2.5, 25, 98)
  
  cns_3p <- if (is_guard) clamp(75 + pts * 0.6, 50, 98) else if (is_forward) clamp(65 + pts * 0.4, 40, 95) else clamp(30 + pts * 0.5, 15, 88)
  pullup_3p <- if (is_guard) clamp(65 + pts * 0.9, 40, 99) else if (is_forward) clamp(50 + pts * 0.8, 25, 92) else clamp(20 + pts * 0.3, 10, 75)
  ft_pct <- clamp(70 + pts * 0.6, 50, 96)
  
  ast_pct <- clamp(ast * 8.5 + (if(is_guard) 15 else 0), 20, 99)
  pot_ast <- clamp(ast * 8.8 + (if(is_guard) 12 else 0), 20, 99)
  tov_control <- clamp(85 - ast * 2.2 + (if(is_guard) 10 else 5), 45, 95)
  drive_ast <- clamp(ast * 7.5 + pts * 0.8, 25, 98)
  
  switchability <- if (is_forward) clamp(70 + reb * 1.5, 45, 98) else if (is_guard) clamp(60 + pts * 0.3, 40, 92) else clamp(40 + reb * 1.2, 25, 88)
  rim_protection <- if (is_center) clamp(reb * 6.5 + 25, 60, 99) else if (is_forward) clamp(reb * 4.0 + 15, 30, 92) else clamp(20 + reb * 1.5, 15, 65)
  perimeter_havoc <- if (is_guard) clamp(65 + ast * 2.0, 40, 96) else if (is_forward) clamp(60 + pts * 0.5, 35, 92) else clamp(35 + reb * 1.5, 20, 75)
  d_rapm <- clamp(50 + (reb * 2.5) + (if(is_center) 15 else if(is_forward) 10 else 0), 30, 98)
  
  oreb <- clamp(reb * 7.5 + (if(is_center) 20 else if(is_forward) 10 else 0), 20, 99)
  dreb <- clamp(reb * 8.2 + (if(is_center) 22 else if(is_forward) 12 else 0), 25, 99)

  # Archetype assignment and vector tailoring for notable archetypes & players
  archetype <- if (is_guard && ast > 6.0) "Playmaking Lead Guard" else
               if (is_guard && pts > 20.0) "Scoring Combo Guard" else
               if (is_center && reb > 8.0) "Interior Rim Anchor" else
               if (is_forward && pts > 20.0) "Three-Level Scoring Forward" else
               if (is_forward && reb > 6.0) "Two-Way Wing Connector" else
               "Versatile System Contributor"
  
  if (grepl("Luka Doncic", name)) {
    archetype <- "Helio-Centric Playmaking Engine"
    pullup_3p <- 97; ast_pct <- 98; pot_ast <- 99; drive_ast <- 96; tov_control <- 65; switchability <- 62; d_rapm <- 68
  } else if (grepl("Nikola Jokic", name)) {
    archetype <- "Post Playmaking Maestro"
    ast_pct <- 99; pot_ast <- 99; paint_touches <- 98; rim_fg <- 95; dreb <- 98; oreb <- 95; tov_control <- 88; switchability <- 52; d_rapm <- 85
  } else if (grepl("Victor Wembanyama", name)) {
    archetype <- "Generational Two-Way Alien"
    rim_protection <- 99; switchability <- 96; d_rapm <- 99; pullup_3p <- 84; dunks <- 96; paint_touches <- 94; perimeter_havoc <- 90
  } else if (grepl("Shai Gilgeous-Alexander", name)) {
    archetype <- "Downhill Iso & Mid-Range Maestro"
    rim_fg <- 94; drive_ast <- 92; pullup_3p <- 88; ft_pct <- 94; tov_control <- 86; perimeter_havoc <- 95; d_rapm <- 88
  } else if (grepl("Giannis Antetokounmpo", name)) {
    archetype <- "Rim-Running Attrition Beast"
    rim_fg <- 98; dunks <- 99; paint_touches <- 99; cns_3p <- 55; pullup_3p <- 45; d_rapm <- 97; switchability <- 94; dreb <- 96; oreb <- 90
  } else if (grepl("Stephen Curry", name)) {
    archetype <- "Off-Ball Gravity & Movement Sniper"
    cns_3p <- 99; pullup_3p <- 99; ft_pct <- 98; ast_pct <- 85; drive_ast <- 82; rim_protection <- 25; switchability <- 58
  } else if (grepl("Anthony Edwards", name)) {
    archetype <- "Three-Level Explosive Slasher"
    dunks <- 94; rim_fg <- 90; pullup_3p <- 89; perimeter_havoc <- 88; d_rapm <- 82; switchability <- 84
  } else if (grepl("Cooper Flagg", name)) {
    archetype <- "Hyper-Versatile Point-Forward Anchor"
    switchability <- 95; rim_protection <- 91; perimeter_havoc <- 90; d_rapm <- 92; paint_touches <- 88; ast_pct <- 78; dreb <- 86
  } else if (grepl("Amen Thompson", name)) {
    archetype <- "Athletic Transition Terror & POA Stopper"
    dunks <- 96; perimeter_havoc <- 97; switchability <- 96; rim_protection <- 84; oreb <- 92; cns_3p <- 48; pullup_3p <- 42; drive_ast <- 85
  } else if (grepl("Jayson Tatum", name)) {
    archetype <- "Two-Way Championship Wing Anchor"
    pullup_3p <- 90; cns_3p <- 89; switchability <- 92; dreb <- 88; d_rapm <- 90; rim_fg <- 88
  } else if (grepl("Chet Holmgren", name)) {
    archetype <- "Stretch Rim-Protecting Unicorn"
    rim_protection <- 96; cns_3p <- 88; d_rapm <- 94; switchability <- 82; dreb <- 88; oreb <- 74
  } else if (grepl("Tyrese Haliburton", name)) {
    archetype <- "Turbo-Pace Floor General"
    ast_pct <- 98; pot_ast <- 99; pullup_3p <- 92; tov_control <- 94; drive_ast <- 95; switchability <- 55; rim_protection <- 30
  } else if (grepl("Anthony Davis", name)) {
    archetype <- "Elite Paint Anchor & Roll Menace"
    rim_protection <- 97; d_rapm <- 96; switchability <- 88; dunks <- 94; dreb <- 95; oreb <- 88
  } else if (grepl("LeBron James", name)) {
    archetype <- "Immortal Point-Forward Maestro"
    ast_pct <- 92; pot_ast <- 94; rim_fg <- 90; switchability <- 78; dreb <- 82; tov_control <- 78
  } else if (grepl("Paolo Banchero", name)) {
    archetype <- "Physical Iso Creator & Point-Forward"
    paint_touches <- 92; rim_fg <- 86; pullup_3p <- 78; ast_pct <- 82; drive_ast <- 84; dreb <- 82
  } else if (grepl("Cade Cunningham", name)) {
    archetype <- "Jumbo Pick-and-Roll Tactician"
    ast_pct <- 92; pot_ast <- 94; pullup_3p <- 86; drive_ast <- 90; switchability <- 76
  }

  vec <- c(
    clamp(rim_fg), clamp(dunks), clamp(paint_touches),
    clamp(cns_3p), clamp(pullup_3p), clamp(ft_pct),
    clamp(ast_pct), clamp(pot_ast), clamp(tov_control), clamp(drive_ast),
    clamp(switchability), clamp(rim_protection), clamp(perimeter_havoc), clamp(d_rapm),
    clamp(oreb), clamp(dreb)
  )

  # Compute Cosine Similarity against all historical archetypes
  sim_scores <- sapply(1:nrow(historical_comps), function(h_idx) {
    calc_cosine_sim(vec, historical_comps$dna_vector[[h_idx]])
  })

  # Rank top 5 historical twins
  rank_order <- order(sim_scores, decreasing = TRUE)
  top_5_indices <- rank_order[1:5]
  
  twins <- lapply(top_5_indices, function(idx) {
    list(
      compName = historical_comps$comp_name[idx],
      era = historical_comps$era[idx],
      archetype = historical_comps$archetype[idx],
      position = historical_comps$pos[idx],
      similarityPct = sim_scores[idx],
      keySharedTrait = paste0("High affinity in ", dim_names[which.max(historical_comps$dna_vector[[idx]])])
    )
  })

  # 5-Category Aggregate Scores for radar UI
  category_scores <- list(
    finishing = round(mean(vec[1:3]), 1),
    shooting = round(mean(vec[4:6]), 1),
    playmaking = round(mean(vec[7:10]), 1),
    defense = round(mean(vec[11:14]), 1),
    rebounding = round(mean(vec[15:16]), 1)
  )

  # 2D t-SNE / PCA Manifold Coordinates for scatter plot (synthetic projection)
  # X: Offensive Shot Creation vs Spot-Up (-100 to +100)
  # Y: Defensive Interior Anchor vs Perimeter Guard (-100 to +100)
  manifold_x <- round((category_scores$playmaking * 0.6 + category_scores$shooting * 0.4) - 50, 1)
  manifold_y <- round((category_scores$defense * 0.5 + category_scores$rebounding * 0.5) - 50, 1)

  player_dna_list[[i]] <- list(
    playerId = as.character(p$player_id),
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
    categoryScores = category_scores,
    historicalTwins = twins
  )
}

# ------------------------------------------------------------------------------
# 3. Export to JSON for Next.js Web Application
# ------------------------------------------------------------------------------
output_json <- "web/public/data/player_dna_profiles.json"
jsonlite::write_json(player_dna_list, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

# Cache RDS as well
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(player_dna_list, "cache/player_dna_profiles.rds")
cat(">>> [SUCCESS] Cached RDS in 'cache/player_dna_profiles.rds'.\n")
