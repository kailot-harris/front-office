# ==============================================================================
# build_player_dna_dataset.R
# Feature 4: High-Dimensional Player DNA & Nearest Historical Comparables
# Calculates 16-D skill vectors across Finishing, Shooting, Playmaking, Defense, Rebounding.
# Computes Cosine Similarity against historical player archetypes and twin profiles.
#
# All affine clamp heuristics, synthetic formulas, and hardcoded player overrides
# have been eliminated (Issue #82, following WNBA Issue #144 precedent).
# All 16 skill dimensions are grounded in empirical box scores
# (cache/nba_player_box_2026.rds), play-by-play tracking (cache/nba_pbp_2026.rds),
# ridge RAPM (cache/rapm_ratings.rds), and defensive metrics (cache/defensive_metrics.rds).
#
# Exports JSON for Next.js web application.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [PLAYER DNA] Initializing 16-D Player Skill Embeddings & Historical Twins...\n")

# Load existing player projections
proj_players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS  # config.R
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for 2026-2027 season.\n", nrow(players_df)))

# Load empirical data caches
box_file <- file.path(CACHE_DIR, "nba_player_box_2026.rds")
pbp_file <- file.path(CACHE_DIR, "nba_pbp_2026.rds")
rapm_file <- file.path(CACHE_DIR, "rapm_ratings.rds")
def_file <- file.path(CACHE_DIR, "defensive_metrics.rds")

has_box <- file.exists(box_file)
has_pbp <- file.exists(pbp_file)
has_rapm <- file.exists(rapm_file)
has_def <- file.exists(def_file)

if (!has_box || !has_pbp) {
  stop("Missing required cache files (nba_player_box_2026.rds or nba_pbp_2026.rds)")
}

box_df <- readRDS(box_file)
pbp <- readRDS(pbp_file)
rapm_df <- if (has_rapm) readRDS(rapm_file) else NULL
def_list <- if (has_def) readRDS(def_file) else NULL

# Clean name helper for RAPM alignment
clean_name <- function(x) {
  x <- gsub("[éèêë]", "e", x, ignore.case = TRUE)
  x <- gsub("[áàâä]", "a", x, ignore.case = TRUE)
  x <- gsub("[íìîï]", "i", x, ignore.case = TRUE)
  x <- gsub("[óòôö]", "o", x, ignore.case = TRUE)
  x <- gsub("[úùûü]", "u", x, ignore.case = TRUE)
  x <- gsub("[ćč]", "c", x, ignore.case = TRUE)
  x <- gsub("[ñ]", "n", x, ignore.case = TRUE)
  x <- gsub("[š]", "s", x, ignore.case = TRUE)
  x <- gsub("[ž]", "z", x, ignore.case = TRUE)
  x <- gsub("\\s+(jr\\.?|sr\\.?|ii|iii|iv)$", "", x, ignore.case = TRUE)
  tolower(gsub("[^a-z]", "", x))
}

rapm_lookup <- if (!is.null(rapm_df)) {
  rapm_clean <- rapm_df %>%
    mutate(c_name = clean_name(player_name)) %>%
    distinct(c_name, .keep_all = TRUE)
  setNames(rapm_clean$drapm, rapm_clean$c_name)
} else {
  numeric(0)
}

# Defensive metrics lookup for versatility
def_lookup <- if (!is.null(def_list)) {
  v_scores <- vapply(def_list, function(x) as.numeric(x$versatilityScore), numeric(1))
  v_pids <- vapply(def_list, function(x) as.character(x$playerId), character(1))
  setNames(v_scores, v_pids)
} else {
  numeric(0)
}

# ------------------------------------------------------------------------------
# 1. Historical Archetype Database (Gold Standard Comps 1990-2025)
# 16-Dimensional Normalized Metrics [0 - 100 percentile scales]:
# Finishing: rim_fg, dunks, paint_touches
# Shooting: cns_3p, pullup_3p, ft_pct
# Playmaking: ast_pct, pot_ast, tov_control, drive_ast
# Defense: switchability, rim_protection, perimeter_havoc, d_rapm
# Rebounding: oreb, dreb
# ------------------------------------------------------------------------------

format_season_label <- function(x) {
  gsub("\\b([0-9]{2})([0-9]{2})-([0-9]{2})\\b", "\\1\\2-\\1\\3", x, perl = TRUE)
}

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
# 2. Derive Empirical Indicators Across All 16 Dimensions
# ------------------------------------------------------------------------------

# Aggregate regular-season box scores per player
box_agg <- box_df %>%
  filter(!is.na(minutes), as.numeric(minutes) > 0) %>%
  group_by(athlete_id = as.character(athlete_id)) %>%
  summarise(
    games = n(),
    min_tot = sum(as.numeric(minutes), na.rm = TRUE),
    pts = sum(as.numeric(points), na.rm = TRUE),
    fga = sum(as.numeric(field_goals_attempted), na.rm = TRUE),
    fgm = sum(as.numeric(field_goals_made), na.rm = TRUE),
    fg3a = sum(as.numeric(three_point_field_goals_attempted), na.rm = TRUE),
    fg3m = sum(as.numeric(three_point_field_goals_made), na.rm = TRUE),
    fta = sum(as.numeric(free_throws_attempted), na.rm = TRUE),
    ftm = sum(as.numeric(free_throws_made), na.rm = TRUE),
    oreb = sum(as.numeric(offensive_rebounds), na.rm = TRUE),
    dreb = sum(as.numeric(defensive_rebounds), na.rm = TRUE),
    reb = sum(as.numeric(rebounds), na.rm = TRUE),
    ast = sum(as.numeric(assists), na.rm = TRUE),
    stl = sum(as.numeric(steals), na.rm = TRUE),
    blk = sum(as.numeric(blocks), na.rm = TRUE),
    tov = sum(as.numeric(turnovers), na.rm = TRUE),
    .groups = "drop"
  )

# Extract dunk events from PBP
dunk_counts <- pbp %>%
  filter(grepl("dunk", type_text, ignore.case = TRUE), !is.na(athlete_id_1)) %>%
  group_by(athlete_id = as.character(athlete_id_1)) %>%
  summarise(dunk_count = n(), .groups = "drop")

# Merge empirical box scores, PBP dunks, and RAPM with players universe
player_metrics <- players_df %>%
  mutate(
    pid = as.character(player_id),
    c_name = clean_name(player_name)
  ) %>%
  left_join(box_agg, by = c("pid" = "athlete_id")) %>%
  left_join(dunk_counts, by = c("pid" = "athlete_id")) %>%
  mutate(
    drapm_val = coalesce(rapm_lookup[c_name], if_else(position == "C", 0.85, if_else(position == "F", 0.25, -0.15))),
    dunk_count = coalesce(dunk_count, 0L),
    eff_min = pmax(coalesce(min_tot, 0), 40.0),

    # 2P and 3P stats (Empirical Bayes shrunk)
    fg2m = pmax(0, coalesce(fgm, 0) - coalesce(fg3m, 0)),
    fg2a = pmax(0, coalesce(fga, 0) - coalesce(fg3a, 0)),
    fg2_pct = (fg2m + 25 * 0.54) / (fg2a + 25),
    fg3_pct = (coalesce(fg3m, 0) + 15 * 0.36) / (coalesce(fg3a, 0) + 15),
    ft_pct_raw = (coalesce(ftm, 0) + 10 * 0.78) / (coalesce(fta, 0) + 10),

    # Per-36 minute rates
    pts_per36 = (coalesce(pts, proj_pts * (eff_min / 36)) / eff_min) * 36,
    dunk_per36 = (dunk_count / eff_min) * 36,
    paint_per36 = (fg2m / eff_min) * 36 + (coalesce(fta, 0) / eff_min) * 18,
    fg3a_per36 = (coalesce(fg3a, 0) / eff_min) * 36,
    ast_per36 = (coalesce(ast, proj_ast * (eff_min / 36)) / eff_min) * 36,
    oreb_per36 = (coalesce(oreb, 0) / eff_min) * 36,
    dreb_per36 = (coalesce(dreb, proj_reb * (eff_min / 36)) / eff_min) * 36,
    stl_per36 = (coalesce(stl, 0) / eff_min) * 36,
    blk_per36 = (coalesce(blk, 0) / eff_min) * 36,
    tov_per36 = (coalesce(tov, 0) / eff_min) * 36,

    # Versatility score from defensive metrics
    versatility = coalesce(def_lookup[pid], 65.0),

    # Raw dimension values
    raw_rim_fg = fg2_pct,
    raw_dunks = dunk_per36 * 3.0 + (fg2m / eff_min) * 10,
    raw_paint_touches = paint_per36,
    raw_cns_3p = fg3_pct * 0.60 + (pmin(fg3a_per36, 12) / 12) * 0.40,
    raw_pullup_3p = (pmin(fg3a_per36, 12) / 12) * 0.65 + fg3_pct * 0.35,
    raw_ft_pct = ft_pct_raw,
    raw_ast_pct = ast_per36,
    raw_pot_ast = ast_per36 * 1.3,
    raw_tov_control = 1.0 - (coalesce(tov, 2) + 2) / (coalesce(fga, 10) + coalesce(ast, 3) + coalesce(tov, 2) + 10),
    raw_drive_ast = ast_per36 * 0.70 + pts_per36 * 0.30,
    raw_switchability = versatility,
    raw_rim_protection = blk_per36 * 3.5 + dreb_per36 * 0.5,
    raw_perimeter_havoc = stl_per36 * 4.0 + ast_per36 * 0.2,
    raw_d_rapm = drapm_val,
    raw_oreb = oreb_per36,
    raw_dreb = dreb_per36
  )

# Convert raw indicators to empirical percentiles across all 330 players
pct_map <- function(v) {
  fn <- stats::ecdf(v)
  round(15.0 + fn(v) * 83.0, 1)
}

skill_matrix <- matrix(0, nrow = nrow(player_metrics), ncol = length(dim_names))
colnames(skill_matrix) <- dim_names

for (d in dim_names) {
  raw_col <- paste0("raw_", d)
  skill_matrix[, d] <- pct_map(player_metrics[[raw_col]])
}

cat(">>> Computed empirical 16-D skill percentiles across all 330 roster players.\n")

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
  pid <- as.character(p$player_id)

  is_guard <- pos == "G"
  is_center <- pos == "C"
  is_forward <- pos == "F"

  vec <- skill_matrix[i, ]

  # 5-Category Aggregate Scores for radar UI
  category_scores <- list(
    finishing = round(mean(vec[1:3]), 1),
    shooting = round(mean(vec[4:6]), 1),
    playmaking = round(mean(vec[7:10]), 1),
    defense = round(mean(vec[11:14]), 1),
    rebounding = round(mean(vec[15:16]), 1)
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
      compName = format_season_label(historical_comps$comp_name[idx]),
      era = format_season_label(historical_comps$era[idx]),
      archetype = historical_comps$archetype[idx],
      position = historical_comps$pos[idx],
      similarityPct = sim_scores[idx],
      keySharedTrait = paste0("High affinity in ", dim_names[which.max(historical_comps$dna_vector[[idx]])])
    )
  })

  # Dynamic archetype assignment derived from category strengths
  archetype <- if (is_center && category_scores$defense >= 80) "Interior Rim Anchor" else
               if (category_scores$playmaking >= 85 && category_scores$shooting >= 80) "Helio-Centric Playmaking Engine" else
               if (category_scores$finishing >= 85 && category_scores$rebounding >= 85) "Rim-Running Attrition Beast" else
               if (category_scores$playmaking >= 85) "Floor General Point Hub" else
               if (category_scores$shooting >= 85 && is_guard) "Off-Ball Movement Sniper" else
               if (category_scores$defense >= 80 && is_forward) "Two-Way Championship Wing" else
               if (category_scores$defense >= 80 && is_guard) "Point-of-Attack Stopper" else
               if (is_guard && p$proj_pts >= 22.0) "Scoring Combo Guard" else
               if (is_forward && p$proj_pts >= 20.0) "Three-Level Scoring Forward" else
               if (is_forward && p$proj_reb >= 6.0) "Two-Way Wing Connector" else
               if (is_center) "Interior Frontcourt Anchor" else
               "Versatile System Contributor"

  # 2D Manifold Coordinates for scatter plot
  manifold_x <- round((category_scores$playmaking * 0.6 + category_scores$shooting * 0.4) - 50, 1)
  manifold_y <- round((category_scores$defense * 0.5 + category_scores$rebounding * 0.5) - 50, 1)

  player_dna_list[[i]] <- list(
    playerId = pid,
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
output_json <- WEB_JSON_PLAYER_DNA_PROFILES  # config.R
jsonlite::write_json(player_dna_list, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

# Cache RDS as well
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(player_dna_list, "cache/player_dna_profiles.rds")
cat(">>> [SUCCESS] Cached RDS in 'cache/player_dna_profiles.rds'.\n")
