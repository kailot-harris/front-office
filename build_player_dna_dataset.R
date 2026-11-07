# ==============================================================================
# build_player_dna_dataset.R
# Path: build_player_dna_dataset.R
#
# Feature 5: High-Dimensional WNBA Player DNA Skill Fingerprints (Issue #148)
# Calculates 12-D real skill vectors across Finishing, Shooting, Playmaking,
# Defense, and Rebounding from observed play-by-play, box-score, defensive
# tracking, and ridge possession RAPM caches:
#   - cache/player_pbp_features.rds
#   - cache/player_box_scores_cache.rds
#   - cache/defensive_metrics.rds
#   - cache/rapm_ratings.rds (via rapm_join_utils.R::join_rapm_to_roster())
#
# Optical-tracking-only dimensions and hand-typed historical comparison tables
# have been removed. Pairwise cosine similarity is computed across current WNBA
# players on standardized 12-D skill vectors.
#
# Exports:
#   - web/public/data/player_dna_profiles.json
#   - web/public/data/player_dna.json
#   - cache/player_dna_profiles.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(data.table)
  library(jsonlite)
  library(tibble)
})

# Source global configuration and RAPM utilities
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

rapm_utils_path <- if (file.exists("rapm_join_utils.R")) "rapm_join_utils.R" else "../rapm_join_utils.R"
source(rapm_utils_path)

cat(">>> [PLAYER DNA] Initializing 12-D WNBA Player Skill Embeddings...\n")

# ------------------------------------------------------------------------------
# 1. Load Player Universe & Upstream Real Caches
# ------------------------------------------------------------------------------
proj_players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}
players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d WNBA player projections for 2026 season.\n", nrow(players_df)))

rapm_file <- file.path(CACHE_DIR, "rapm_ratings.rds")
pbp_feat_file <- file.path(CACHE_DIR, "player_pbp_features.rds")
box_cache_file <- file.path(CACHE_DIR, "player_box_scores_cache.rds")
def_cache_file <- file.path(CACHE_DIR, "defensive_metrics.rds")

for (req_file in c(rapm_file, pbp_feat_file, box_cache_file, def_cache_file)) {
  if (!file.exists(req_file)) {
    stop(sprintf("Missing required upstream cache: %s", req_file))
  }
}

rapm_df <- readRDS(rapm_file)
pbp_df <- readRDS(pbp_feat_file)
box_dt <- as.data.table(readRDS(box_cache_file))
def_list <- readRDS(def_cache_file)

# Join real possession dRAPM using standard join utility
roster_df <- players_df |>
  transmute(
    player_id = as.integer(.data$player_id),
    player_name = .data$player_name,
    team_abbreviation = .data$team,
    team_name = unname(WNBA_TEAMS[.data$team])
  )

rapm_joined <- join_rapm_to_roster(roster_df, rapm_df, matched_only = FALSE)
rapm_lookup <- setNames(rapm_joined$drapm, as.character(rapm_joined$player_id))

cat(sprintf(">>> Joined real possession RAPM for %d of %d players.\n",
            sum(rapm_joined$rapm_matched), nrow(roster_df)))

# Extract defensive metrics lookup from cache/defensive_metrics.rds
def_df <- tibble(
  player_id = vapply(def_list, function(x) as.character(x$playerId), character(1)),
  rim_dfg_delta = vapply(def_list, function(x) as.numeric(x$rimDfgDelta), numeric(1)),
  rim_deterrence = vapply(def_list, function(x) as.numeric(x$rimDeterrenceIndex), numeric(1)),
  rim_source = vapply(def_list, function(x) as.character(x$rimDefenseSource), character(1)),
  versatility_score = vapply(def_list, function(x) as.numeric(x$versatilityScore), numeric(1))
)

# Aggregate per-player box scores (CURRENT_SEASON coalesced with multi-season career history)
agg_player_box <- function(dt) {
  dt[!is.na(minutes) & minutes > 0, .(
    games = .N,
    min_tot = sum(minutes, na.rm = TRUE),
    fgm = sum(field_goals_made, na.rm = TRUE),
    fga = sum(field_goals_attempted, na.rm = TRUE),
    fg3m = sum(three_point_field_goals_made, na.rm = TRUE),
    fg3a = sum(three_point_field_goals_attempted, na.rm = TRUE),
    ftm = sum(free_throws_made, na.rm = TRUE),
    fta = sum(free_throws_attempted, na.rm = TRUE),
    oreb = sum(offensive_rebounds, na.rm = TRUE),
    dreb = sum(defensive_rebounds, na.rm = TRUE),
    reb = sum(rebounds, na.rm = TRUE),
    ast = sum(assists, na.rm = TRUE),
    stl = sum(steals, na.rm = TRUE),
    blk = sum(blocks, na.rm = TRUE),
    tov = sum(turnovers, na.rm = TRUE),
    pts = sum(points, na.rm = TRUE)
  ), by = .(player_id = as.character(athlete_id))]
}

box_cur <- agg_player_box(box_dt[season == CURRENT_SEASON])
box_all <- agg_player_box(box_dt)

box_merged <- merge(
  box_all,
  box_cur,
  by = "player_id",
  all.x = TRUE,
  suffixes = c("_all", "_cur")
)

use_cur <- !is.na(box_merged$min_tot_cur) & box_merged$min_tot_cur >= 40
box_stats <- tibble(
  player_id = box_merged$player_id,
  min_tot   = ifelse(use_cur, box_merged$min_tot_cur, box_merged$min_tot_all),
  fgm       = ifelse(use_cur, box_merged$fgm_cur, box_merged$fgm_all),
  fga       = ifelse(use_cur, box_merged$fga_cur, box_merged$fga_all),
  fg3m      = ifelse(use_cur, box_merged$fg3m_cur, box_merged$fg3m_all),
  fg3a      = ifelse(use_cur, box_merged$fg3a_cur, box_merged$fg3a_all),
  ftm       = ifelse(use_cur, box_merged$ftm_cur, box_merged$ftm_all),
  fta       = ifelse(use_cur, box_merged$fta_cur, box_merged$fta_all),
  oreb      = ifelse(use_cur, box_merged$oreb_cur, box_merged$oreb_all),
  dreb      = ifelse(use_cur, box_merged$dreb_cur, box_merged$dreb_all),
  ast       = ifelse(use_cur, box_merged$ast_cur, box_merged$ast_all),
  stl       = ifelse(use_cur, box_merged$stl_cur, box_merged$stl_all),
  blk       = ifelse(use_cur, box_merged$blk_cur, box_merged$blk_all),
  tov       = ifelse(use_cur, box_merged$tov_cur, box_merged$tov_all)
)

pbp_lookup <- pbp_df |>
  mutate(player_id = as.character(.data$player_id)) |>
  select(
    "player_id",
    pbp_source = "data_source",
    "fga_total",
    pbp_assists = "assists",
    "pct_rim",
    "pct_off_dribble_jumper",
    "pct_catch_shoot_jumper",
    "pct_three"
  )

# ------------------------------------------------------------------------------
# 2. Compute Raw Observed Rates Across All 12 Real Skill Dimensions
# ------------------------------------------------------------------------------
# 12-Dimensional Real Skill Vector [0 - 100 empirical percentiles]:
# Finishing (2): rim_fg, paint_power
# Shooting  (3): cns_3p, pullup_3p, ft_pct
# Playmaking(2): ast_pct, tov_control
# Defense   (3): rim_protection, perimeter_havoc, d_rapm
# Rebounding(2): oreb, dreb
# ------------------------------------------------------------------------------

dim_names <- c(
  "rim_fg", "paint_power",
  "cns_3p", "pullup_3p", "ft_pct",
  "ast_pct", "tov_control",
  "rim_protection", "perimeter_havoc", "d_rapm",
  "oreb", "dreb"
)

# Minimum exposure prior for per-36 rates (40 minutes) to prevent 1-game call-up spikes
MIN_PRIOR <- 40.0

raw_tbl <- players_df |>
  as_tibble() |>
  mutate(player_id = as.character(.data$player_id)) |>
  left_join(box_stats, by = "player_id") |>
  left_join(pbp_lookup, by = "player_id") |>
  left_join(def_df, by = "player_id") |>
  mutate(
    drapm_val = unname(rapm_lookup[.data$player_id]),
    has_observed = !is.na(.data$min_tot) & .data$min_tot > 0 &
                   !is.na(.data$fga_total) & .data$fga_total > 0,
    dna_source = ifelse(.data$has_observed, "observed_pbp_box", "projection_prior_fallback"),

    eff_min = pmax(coalesce(.data$min_tot, 0), MIN_PRIOR),
    fg2m = pmax(0, coalesce(.data$fgm, 0) - coalesce(.data$fg3m, 0)),
    fg2a = pmax(0, coalesce(.data$fga, 0) - coalesce(.data$fg3a, 0)),

    # Bayes-shrunk shooting efficiencies (shrunk toward empirical league baselines on small samples)
    fg2_shrunk = (.data$fg2m + 15 * 0.48) / (.data$fg2a + 15),
    fg3_shrunk = (coalesce(.data$fg3m, 0) + 12 * 0.33) / (coalesce(.data$fg3a, 0) + 12),
    ft_shrunk  = (coalesce(.data$ftm, 0) + 10 * 0.78) / (coalesce(.data$fta, 0) + 10),
    ftr_shrunk = (coalesce(.data$fta, 0) + 5) / (coalesce(.data$fga, 0) + 20),

    fg2m_per36 = (.data$fg2m / .data$eff_min) * 36,
    fg3m_per36 = (coalesce(.data$fg3m, 0) / .data$eff_min) * 36,

    # 1. rim_fg: 2P FG% combined with PBP rim shot share (pct_rim)
    raw_rim_fg = ifelse(
      .data$has_observed,
      .data$fg2_shrunk * 0.70 + coalesce(.data$pct_rim, 0.50) * 0.30,
      NA_real_
    ),

    # 2. paint_power: Interior 2PT makes per 36 + free-throw rate + PBP rim frequency
    raw_paint_power = ifelse(
      .data$has_observed,
      .data$fg2m_per36 * (0.50 + 0.50 * coalesce(.data$pct_rim, 0.50)) + .data$ftr_shrunk * 6.0,
      NA_real_
    ),

    # 3. cns_3p: Catch-and-shoot jumper profile + 3P efficiency & 3PA share
    cns_jumper_ratio = ifelse(
      !is.na(.data$pct_catch_shoot_jumper) & !is.na(.data$pct_off_dribble_jumper) &
        (.data$pct_catch_shoot_jumper + .data$pct_off_dribble_jumper) > 0,
      .data$pct_catch_shoot_jumper / (.data$pct_catch_shoot_jumper + .data$pct_off_dribble_jumper),
      0.50
    ),
    raw_cns_3p = ifelse(
      .data$has_observed,
      .data$fg3_shrunk * 0.55 + coalesce(.data$pct_three, 0) * 0.30 + .data$cns_jumper_ratio * 0.15,
      NA_real_
    ),

    # 4. pullup_3p: PBP off-dribble jumper creation share + 3P efficiency & volume
    raw_pullup_3p = ifelse(
      .data$has_observed,
      coalesce(.data$pct_off_dribble_jumper, 0) * 0.50 + .data$fg3_shrunk * 0.30 + coalesce(.data$pct_three, 0) * 0.20,
      NA_real_
    ),

    # 5. ft_pct: Real box-score free-throw percentage (empirical Bayes shrunk)
    raw_ft_pct = ifelse(.data$has_observed, .data$ft_shrunk, NA_real_),

    # 6. ast_pct: Real box-score + PBP assists per 36 minutes
    raw_ast_pct = ifelse(
      .data$has_observed,
      ((coalesce(.data$ast, 0) * 0.7 + coalesce(.data$pbp_assists, 0) * 0.3) / .data$eff_min) * 36,
      NA_real_
    ),

    # 7. tov_control: Ball security (1 - turnover share of offensive touches)
    off_touches = coalesce(.data$fga, 0) + 0.44 * coalesce(.data$fta, 0) +
                  coalesce(.data$ast, 0) + coalesce(.data$tov, 0),
    raw_tov_control = ifelse(
      .data$has_observed & .data$off_touches > 0,
      1.0 - ((coalesce(.data$tov, 0) + 2.0) / (.data$off_touches + 12.0)),
      NA_real_
    ),

    # 8. rim_protection: Blocks per 36 + real rim FG% suppression & deterrence from defensive_metrics.rds
    blk_per36 = (coalesce(.data$blk, 0) / .data$eff_min) * 36,
    rim_supp = -coalesce(.data$rim_dfg_delta, 0) + 0.5 * coalesce(.data$rim_deterrence, 0),
    raw_rim_protection = ifelse(
      .data$has_observed,
      .data$blk_per36 * 3.5 + .data$rim_supp * 0.35,
      NA_real_
    ),

    # 9. perimeter_havoc: Steals per 36 + real positional switch entropy from defensive_metrics.rds
    stl_per36 = (coalesce(.data$stl, 0) / .data$eff_min) * 36,
    raw_perimeter_havoc = ifelse(
      .data$has_observed,
      .data$stl_per36 * 4.0 + coalesce(.data$versatility_score, 50) * 0.025,
      NA_real_
    ),

    # 10. d_rapm: Real ridge possession dRAPM from cache/rapm_ratings.rds
    raw_d_rapm = .data$drapm_val,

    # 11. oreb: Offensive rebounds per 36 minutes from box scores
    raw_oreb = ifelse(.data$has_observed, (coalesce(.data$oreb, 0) / .data$eff_min) * 36, NA_real_),

    # 12. dreb: Defensive rebounds per 36 minutes from box scores
    raw_dreb = ifelse(.data$has_observed, (coalesce(.data$dreb, 0) / .data$eff_min) * 36, NA_real_)
  )

# ------------------------------------------------------------------------------
# 3. Convert Raw Observed Rates to Empirical Percentiles (ecdf) Across Roster
# ------------------------------------------------------------------------------
raw_cols <- paste0("raw_", dim_names)

# Position-specific empirical median fallback for rookies/unmatched players with no PBP/box observations
compute_percentile_col <- function(raw_vec, pos_vec, ref_vec = NULL) {
  fit_pool <- if (!is.null(ref_vec)) ref_vec[!is.na(ref_vec)] else raw_vec[!is.na(raw_vec)]
  fn <- stats::ecdf(fit_pool)
  pct_vals <- ifelse(!is.na(raw_vec), round(fn(raw_vec) * 100, 1), NA_real_)

  # Fill unmatched/rookie rows with the empirical positional median percentile of observed players
  for (p_code in unique(pos_vec)) {
    pos_med <- stats::median(pct_vals[pos_vec == p_code & !is.na(pct_vals)], na.rm = TRUE)
    if (is.na(pos_med)) pos_med <- 50.0
    pct_vals[pos_vec == p_code & is.na(pct_vals)] <- round(pos_med, 1)
  }
  pct_vals[is.na(pct_vals)] <- 50.0
  pct_vals
}

skill_matrix <- matrix(0, nrow = nrow(raw_tbl), ncol = length(dim_names))
colnames(skill_matrix) <- dim_names

for (d in dim_names) {
  r_col <- paste0("raw_", d)
  ref_pool <- if (d == "d_rapm") rapm_df$drapm else NULL
  skill_matrix[, d] <- compute_percentile_col(raw_tbl[[r_col]], raw_tbl$position, ref_vec = ref_pool)
}

cat(sprintf(">>> Computed 12-D skill percentiles: %d observed_pbp_box, %d projection_prior_fallback.\n",
            sum(raw_tbl$dna_source == "observed_pbp_box"),
            sum(raw_tbl$dna_source == "projection_prior_fallback")))

# ------------------------------------------------------------------------------
# 4. Pairwise Cosine Similarity Across Standardized 12-D Current Player Vectors
# ------------------------------------------------------------------------------
scaled_matrix <- scale(skill_matrix)
scaled_matrix[is.na(scaled_matrix)] <- 0

row_norms <- sqrt(rowSums(scaled_matrix^2))
row_norms[row_norms == 0] <- 1
norm_matrix <- scaled_matrix / row_norms
cos_sim_matrix <- tcrossprod(norm_matrix)

# 2D PCA Manifold Projection from the standardized 12-D skill matrix
pca_fit <- stats::prcomp(scaled_matrix, center = FALSE, scale. = FALSE)
# Align PC1 sign with playmaking + shooting creation, PC2 sign with interior defense + rebounding
pc1_raw <- pca_fit$x[, 1]
pc2_raw <- pca_fit$x[, 2]
if (stats::cor(pc1_raw, skill_matrix[, "ast_pct"] + skill_matrix[, "pullup_3p"]) < 0) {
  pc1_raw <- -pc1_raw
}
if (stats::cor(pc2_raw, skill_matrix[, "rim_protection"] + skill_matrix[, "dreb"]) < 0) {
  pc2_raw <- -pc2_raw
}
scale_to_manifold <- function(v) {
  rng <- max(abs(v))
  if (rng == 0) return(rep(0, length(v)))
  round((v / rng) * 42, 1)
}
manifold_x_vec <- scale_to_manifold(pc1_raw)
manifold_y_vec <- scale_to_manifold(pc2_raw)

# ------------------------------------------------------------------------------
# 5. Assemble Player DNA Profiles
# ------------------------------------------------------------------------------
player_dna_list <- vector("list", nrow(raw_tbl))

for (i in seq_len(nrow(raw_tbl))) {
  p <- raw_tbl[i, ]
  vec <- skill_matrix[i, ]

  # 5-Category Aggregate Scores from the 12 real dimensions
  finishing_score  <- round(mean(vec[c("rim_fg", "paint_power")]), 1)
  shooting_score   <- round(mean(vec[c("cns_3p", "pullup_3p", "ft_pct")]), 1)
  playmaking_score <- round(mean(vec[c("ast_pct", "tov_control")]), 1)
  defense_score    <- round(mean(vec[c("rim_protection", "perimeter_havoc", "d_rapm")]), 1)
  rebounding_score <- round(mean(vec[c("oreb", "dreb")]), 1)

  category_scores <- list(
    finishing  = finishing_score,
    shooting   = shooting_score,
    playmaking = playmaking_score,
    defense    = defense_score,
    rebounding = rebounding_score
  )

  # Algorithmic archetype derived from real skill percentiles and position
  pos <- p$position
  archetype <- if (pos == "G" && playmaking_score >= 70 && vec[["ast_pct"]] >= 75) {
    "Playmaking Floor General"
  } else if (pos == "G" && shooting_score >= 70) {
    "Dynamic Perimeter Creator"
  } else if (pos == "C" && (rebounding_score >= 70 || vec[["rim_protection"]] >= 75)) {
    "Interior Anchor & Glass Cleaner"
  } else if (pos == "F" && shooting_score >= 65 && finishing_score >= 65) {
    "Three-Level Scoring Forward"
  } else if (defense_score >= 68) {
    "Two-Way Defensive Connector"
  } else {
    "Versatile System Contributor"
  }

  # Top 3 nearest current WNBA peers by standardized cosine similarity
  sims <- cos_sim_matrix[i, ]
  sims[i] <- -Inf
  top_idx <- order(sims, decreasing = TRUE)[1:3]
  similar_players <- lapply(top_idx, function(j) {
    # Map cosine [-1, 1] to [0, 100] similarity score
    sim_pct <- round(((sims[j] + 1) / 2) * 100, 1)
    list(
      playerId      = raw_tbl$player_id[j],
      playerName    = raw_tbl$player_name[j],
      team          = raw_tbl$team[j],
      position      = raw_tbl$position[j],
      similarityPct = sim_pct
    )
  })

  player_dna_list[[i]] <- list(
    season         = 2026,
    playerId       = p$player_id,
    playerName     = p$player_name,
    team           = p$team,
    position       = pos,
    archetype      = archetype,
    dnaSource      = p$dna_source,
    projPts        = p$proj_pts,
    projReb        = p$proj_reb,
    projAst        = p$proj_ast,
    projMpg        = p$proj_mpg,
    overallRating  = round(mean(vec), 1),
    manifoldX      = manifold_x_vec[i],
    manifoldY      = manifold_y_vec[i],
    skillVector    = as.list(setNames(as.numeric(vec), dim_names)),
    categoryScores = category_scores,
    similarPlayers = similar_players
  )
}

# ------------------------------------------------------------------------------
# 6. Export JSON & RDS
# ------------------------------------------------------------------------------
output_json <- file.path(PROJECT_DIR, "web", "public", "data", "player_dna_profiles.json")
jsonlite::write_json(player_dna_list, output_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

output_alias_json <- file.path(PROJECT_DIR, "web", "public", "data", "player_dna.json")
jsonlite::write_json(player_dna_list, output_alias_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_alias_json))

cache_rds <- file.path(CACHE_DIR, "player_dna_profiles.rds")
saveRDS(player_dna_list, cache_rds)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", cache_rds))
