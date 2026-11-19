# ==============================================================================
# build_player_dna_dataset.R
# Feature 4: High-Dimensional Player DNA & Nearest Current-Season Peer Comparables
# Calculates 15-D skill vectors across Finishing, Shooting, Playmaking, Defense, Rebounding.
# Computes cosine similarity between each player's empirical skill vector and every
# other player's (current-season peers only; no hand-typed historical comps).
#
# All affine clamp heuristics, synthetic formulas, and hardcoded player overrides
# have been eliminated (Issue #82, following WNBA Issue #144 precedent).
# All 15 skill dimensions are grounded in empirical box scores
# (cache/nba_player_box_<CURRENT_SEASON>.rds), play-by-play tracking (cache/nba_pbp_<CURRENT_SEASON>.rds),
# ridge RAPM (cache/rapm_ratings.rds), and defensive metrics (cache/defensive_metrics.rds).
#
# Exports JSON for Next.js web application.
#
# Data window (front-office#109):
#   Seasons: the current season (CURRENT_SEASON in config.R, labelled via
#     season_label(); 2027 = 2026-27): cache/nba_player_box_<CURRENT_SEASON>.rds
#     and cache/nba_pbp_<CURRENT_SEASON>.rds (the script stops if either is
#     missing; no fallback to another season, front-office#191), plus
#     cache/rapm_ratings.rds and cache/defensive_metrics.rds when present (when
#     absent, the dependent skills are published as null; no substitute
#     constants). defensive_metrics.rds is written by build_defense_dataset.R,
#     which must run first. The JSON exports season, throughDate (latest game_date
#     in the play-by-play input), generatedAt and rapmSeason. rapm_ratings.rds is
#     NOT current-season (possession data for the in-progress season is not
#     published, so rapm_engine.R fits the last completed season); d_rapm is kept
#     but its season is read from the file and exported as rapmSeason. The
#     player list comes from the 2026-27 season projections. No season-type filter
#     is applied.
#   Filters: box-score rows with more than 0 minutes; dunks are play-by-play rows
#     whose play type contains "dunk". Each skill is a percentile across every
#     player in the projections file.
#   Minimum sample: none. Every projected player is listed. Per-36 rates use at least
#     40 minutes (eff_min).
#   Methodology (documented modelling choices, not fabricated data):
#     - Shooting percentages are Empirical-Bayes shrunk toward league averages
#       (2P 0.54, 3P 0.36, FT 0.78) with 25 two-point, 15 three-point and 10
#       free-throw pseudo-attempts.
#     - Each raw dimension is a fixed weighted blend of per-36 rates (the weights
#       are visible in the raw_* definitions below); 3PA/36 is capped at 12.
#     - Percentiles are ecdf ranks scaled to 15 + 83 * ecdf, i.e. range 15-98.
#     - Peer similarity is the cosine of the 50-centred percentile vectors over
#       dimensions non-null for both players (minimum 8 shared), published as
#       similarityPct = max(cos, 0) * 100 (negative cosines floored at 0). keySharedTrait
#       is the dimension with the highest min(a, b), shown with a readable label.
#     - Archetype labels come from category-score thresholds (assign_archetype); players with no box row get a null archetype.
#     - Missing inputs are never imputed: a player with no current-season box-score row has
#       every box/PBP-derived skill published as null, receives peerComps = [] and is
#       excluded from other players' comp candidates. A missing RAPM or defensive
#       metric likewise publishes null for d_rapm / switchability. A category score
#       averages its non-null dimensions and is null unless at least half of them
#       are non-null; overallRating is null unless at least 8 of 15 are non-null.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [PLAYER DNA] Initializing 15-D Player Skill Embeddings & Peer Comps...\n")

# Load existing player projections
proj_players_file <- WEB_JSON_PROJECTIONS_SEASON_PLAYERS  # config.R
if (!file.exists(proj_players_file)) {
  stop("Missing projections_season_players.json")
}

players_df <- jsonlite::fromJSON(proj_players_file)
cat(sprintf(">>> Loaded %d player projections for %s season.\n", nrow(players_df), season_label()))

# Load empirical data caches
box_file <- current_season_cache("player_box")  # stop()s if missing
pbp_file <- current_season_cache("pbp")          # stop()s if missing
rapm_file <- file.path(CACHE_DIR, "rapm_ratings.rds")
def_file <- file.path(CACHE_DIR, "defensive_metrics.rds")

has_rapm <- file.exists(rapm_file)
has_def <- file.exists(def_file)

box_df <- readRDS(box_file)
pbp <- readRDS(pbp_file)
rapm_df <- if (has_rapm) readRDS(rapm_file) else NULL
def_list <- if (has_def) readRDS(def_file) else NULL
through_date <- data_through_date(pbp, box_df)
cat(sprintf(">>> Season %s, data through %s (earlier of play-by-play and player box).\n", season_label(), through_date))
rapm_season <- if (!is.null(rapm_df) && "season_label" %in% names(rapm_df)) {
  u <- unique(as.character(rapm_df$season_label)); if (length(u) == 1L) u else NA_character_
} else NA_character_
if (!is.null(rapm_df) && !identical(rapm_season, season_label())) {
  cat(sprintf(">>> [NOTE] rapm_ratings.rds covers %s, not %s; dRAPM is published with rapmSeason so it is not read as current-season.\n",
              ifelse(is.na(rapm_season), "an unknown season", rapm_season), season_label()))
}

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
# 1. Skill dimensions (15-D, empirical percentiles [15 - 98] across the player universe)
# Finishing: rim_fg, dunks, paint_touches
# Shooting: cns_3p, pullup_3p, ft_pct
# Playmaking: ast_pct, tov_control, drive_ast
# Defense: switchability, rim_protection, perimeter_havoc, d_rapm
# Rebounding: oreb, dreb
# ------------------------------------------------------------------------------

dim_names <- c(
  "rim_fg", "dunks", "paint_touches",
  "cns_3p", "pullup_3p", "ft_pct",
  "ast_pct", "tov_control", "drive_ast",
  "switchability", "rim_protection", "perimeter_havoc", "d_rapm",
  "oreb", "dreb"
)

# ------------------------------------------------------------------------------
# 2. Derive Empirical Indicators Across All 15 Dimensions
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
    # Missing RAPM -> NA (published as null), never a made-up position constant
    drapm_val = unname(rapm_lookup[c_name]),
    # Players with no current-season box-score row: every box- and PBP-derived quantity
    # stays NA (published as null). No priors-only shrinkage, no zero-fill, no
    # proj_* substitution.
    has_box_row = !is.na(games),
    # A player with a box row and no dunk play-by-play events genuinely has 0 dunks
    dunk_count = if_else(has_box_row, coalesce(dunk_count, 0L), NA_integer_),
    eff_min = pmax(min_tot, 40.0),

    # 2P and 3P stats (Empirical Bayes shrunk; only when the player has box data)
    fg2m = pmax(0, fgm - fg3m),
    fg2a = pmax(0, fga - fg3a),
    fg2_pct = (fg2m + 25 * 0.54) / (fg2a + 25),
    fg3_pct = (fg3m + 15 * 0.36) / (fg3a + 15),
    ft_pct_raw = (ftm + 10 * 0.78) / (fta + 10),

    # Per-36 minute rates
    pts_per36 = (pts / eff_min) * 36,
    dunk_per36 = (dunk_count / eff_min) * 36,
    paint_per36 = (fg2m / eff_min) * 36 + (fta / eff_min) * 18,
    fg3a_per36 = (fg3a / eff_min) * 36,
    ast_per36 = (ast / eff_min) * 36,
    oreb_per36 = (oreb / eff_min) * 36,
    dreb_per36 = (dreb / eff_min) * 36,
    stl_per36 = (stl / eff_min) * 36,
    blk_per36 = (blk / eff_min) * 36,
    tov_per36 = (tov / eff_min) * 36,

    # Versatility score from defensive metrics
    # Missing defensive metrics -> NA (published as null), never a constant
    versatility = if_else(has_box_row, unname(def_lookup[pid]), NA_real_),

    # Raw dimension values
    raw_rim_fg = fg2_pct,
    raw_dunks = dunk_per36 * 3.0 + (fg2m / eff_min) * 10,
    raw_paint_touches = paint_per36,
    raw_cns_3p = fg3_pct * 0.60 + (pmin(fg3a_per36, 12) / 12) * 0.40,
    raw_pullup_3p = (pmin(fg3a_per36, 12) / 12) * 0.65 + fg3_pct * 0.35,
    raw_ft_pct = ft_pct_raw,
    raw_ast_pct = ast_per36,
    raw_tov_control = 1.0 - (tov + 2) / (fga + ast + tov + 10),
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

cat(">>> Computed empirical 15-D skill percentiles across all 330 roster players.\n")

# Cosine similarity of 50-centred percentile vectors, over the dimensions both
# players have (NA dims skipped). Returns NA when fewer than MIN_OVERLAP dims are
# shared. Published as similarityPct = max(cos, 0) * 100 (negatives floored at 0).
# Centring removes the shared positive offset of raw 15-98 percentiles, which
# otherwise makes every pair look ~90%+ similar.
MIN_OVERLAP <- 8
calc_cosine_sim <- function(v1, v2) {
  ok <- !is.na(v1) & !is.na(v2)
  if (sum(ok) < MIN_OVERLAP) return(NA_real_)
  v1 <- v1[ok] - 50; v2 <- v2[ok] - 50
  norm1 <- sqrt(sum(v1^2))
  norm2 <- sqrt(sum(v2^2))
  if (norm1 == 0 || norm2 == 0) return(NA_real_)
  round(max(sum(v1 * v2) / (norm1 * norm2), 0) * 100, 1)
}

# Human-readable dimension labels for keySharedTrait
dim_labels <- c(
  rim_fg = "Rim finishing", dunks = "Dunking", paint_touches = "Paint touches",
  cns_3p = "Catch-and-shoot 3PT", pullup_3p = "Pull-up 3PT", ft_pct = "Free-throw shooting",
  ast_pct = "Assist rate", tov_control = "Turnover control", drive_ast = "Drive creation",
  switchability = "Switchability", rim_protection = "Rim protection",
  perimeter_havoc = "Perimeter havoc", d_rapm = "Defensive RAPM",
  oreb = "Offensive rebounding", dreb = "Defensive rebounding"
)

# Archetype per player (also reused as the archetype of each peer comp)
# Mean of non-null dims, or NA unless at least min_n dims are non-null
mean_or_na <- function(x, min_n = 1) if (sum(!is.na(x)) < min_n) NA_real_ else round(mean(x, na.rm = TRUE), 1)
assign_archetype <- function(cs, pos, proj_pts, proj_reb, has_box) {
  if (!has_box) return(NA_character_)  # no box data: no archetype, published as null
  is_guard <- pos == "G"; is_center <- pos == "C"; is_forward <- pos == "F"
  ge <- function(x, t) !is.na(x) && x >= t
  if (is_center && ge(cs$defense, 80)) "Interior Rim Anchor" else
  if (ge(cs$playmaking, 85) && ge(cs$shooting, 80)) "Helio-Centric Playmaking Engine" else
  if (ge(cs$finishing, 85) && ge(cs$rebounding, 85)) "Rim-Running Attrition Beast" else
  if (ge(cs$playmaking, 85)) "Floor General Point Hub" else
  if (ge(cs$shooting, 85) && is_guard) "Off-Ball Movement Sniper" else
  if (ge(cs$defense, 80) && is_forward) "Two-Way Championship Wing" else
  if (ge(cs$defense, 80) && is_guard) "Point-of-Attack Stopper" else
  if (is_guard && proj_pts >= 22.0) "Scoring Combo Guard" else
  if (is_forward && proj_pts >= 20.0) "Three-Level Scoring Forward" else
  if (is_forward && proj_reb >= 6.0) "Two-Way Wing Connector" else
  if (is_center) "Interior Frontcourt Anchor" else
  "Versatile System Contributor"
}
# A category score needs at least half of its dimensions non-null
cat_mean <- function(v) mean_or_na(v, min_n = ceiling(length(v) / 2))
cat_scores <- function(vec) list(
  finishing = cat_mean(vec[1:3]),
  shooting = cat_mean(vec[4:6]),
  playmaking = cat_mean(vec[7:9]),
  defense = cat_mean(vec[10:13]),
  rebounding = cat_mean(vec[14:15])
)
has_box_row <- player_metrics$has_box_row
all_archetypes <- vapply(seq_len(nrow(players_df)), function(j) {
  assign_archetype(cat_scores(skill_matrix[j, ]), players_df$position[j],
                   players_df$proj_pts[j], players_df$proj_reb[j], has_box_row[j])
}, character(1))

player_dna_list <- list()

for (i in seq_len(nrow(players_df))) {
  p <- players_df[i, ]
  name <- p$player_name
  pos <- p$position
  team <- p$team
  pid <- as.character(p$player_id)

  vec <- skill_matrix[i, ]

  # 5-Category Aggregate Scores for radar UI
  category_scores <- cat_scores(vec)

  # Peer comps: cosine similarity vs every OTHER current-season player
  # No-box players neither receive comps nor appear as candidates for others.
  sim_scores <- vapply(seq_len(nrow(players_df)), function(j) {
    if (j == i || !has_box_row[i] || !has_box_row[j]) NA_real_
    else calc_cosine_sim(vec, skill_matrix[j, ])
  }, numeric(1))
  rank_order <- order(sim_scores, decreasing = TRUE, na.last = NA)
  top_idx <- head(rank_order, 5)

  peers <- lapply(top_idx, function(idx) {
    shared <- pmin(vec, skill_matrix[idx, ])
    list(
      compName = players_df$player_name[idx],
      playerId = as.character(players_df$player_id[idx]),
      era = season_label(),
      archetype = all_archetypes[idx],
      position = players_df$position[idx],
      similarityPct = sim_scores[idx],
      keySharedTrait = paste0("Shared strength: ", dim_labels[[dim_names[which.max(shared)]]])
    )
  })

  archetype <- all_archetypes[i]

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
    overallRating = mean_or_na(vec, min_n = 8),
    manifoldX = manifold_x,
    manifoldY = manifold_y,
    skillVector = as.list(setNames(as.numeric(vec), dim_names)),
    categoryScores = category_scores,
    peerComps = peers
  )
}

# ------------------------------------------------------------------------------
# 3. Export to JSON for Next.js Web Application
# ------------------------------------------------------------------------------
output_json <- WEB_JSON_PLAYER_DNA_PROFILES  # config.R
dna_payload <- list(
  season = season_label(),
  throughDate = through_date,
  generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  rapmSeason = if (is.na(rapm_season)) NULL else rapm_season,
  profiles = player_dna_list
)
jsonlite::write_json(dna_payload, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null")
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles to '%s'.\n", length(player_dna_list), output_json))

# Cache RDS as well
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)
saveRDS(player_dna_list, "cache/player_dna_profiles.rds")
cat(">>> [SUCCESS] Cached RDS in 'cache/player_dna_profiles.rds'.\n")
