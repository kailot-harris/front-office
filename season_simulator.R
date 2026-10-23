# ==============================================================================
# season_simulator.R
# Phase 1: 1,000-Season Monte Carlo Projections Engine & Frontend Exporter
# Multi-Model Variant Simulation (RAPM, Bottom-Up, Shot/Fatigue, Embeddings, Ensemble)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

# ------------------------------------------------------------------------------
# 1. Environment & Paths Configuration
# ------------------------------------------------------------------------------
if (file.exists("config.R")) {
  source("config.R")
}

# Fallbacks for running stand-alone from a checkout without config.R.
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(getwd(), "cache")
if (!exists("WEB_DATA_DIR")) WEB_DATA_DIR <- file.path(getwd(), "web", "public", "data")
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)
if (!dir.exists(WEB_DATA_DIR)) dir.create(WEB_DATA_DIR, recursive = TRUE)

# Timestamp for the publish contract at the end of this script: every cache and
# web JSON artifact must be rewritten at or after this instant.
simulator_started_at <- Sys.time()

# Ensure local cache directory exists in worktree
if (!dir.exists("cache")) {
  dir.create("cache", recursive = TRUE)
}

# Resolve input cache directories (check local worktree cache first, then CACHE_DIR)
get_cache_file <- function(filename) {
  local_path <- file.path("cache", filename)
  if (file.exists(local_path)) return(local_path)
  if (exists("CACHE_DIR") && file.exists(file.path(CACHE_DIR, filename))) {
    return(file.path(CACHE_DIR, filename))
  }
  return(local_path)
}

MARGIN_SIGMA  <- if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8
HCA_PTS       <- 2.40
N_SIMS        <- 1000
# Both Monte Carlo blocks (team ensemble and per-player season) are seeded from this
# single constant so the stage is reproducible: unchanged inputs must yield identical
# published projections, otherwise every run churns the committed JSON and leaves
# downstream datasets referencing a stale draw.
SIM_SEED      <- 424242
CURR_SEASON   <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2026

cat("\n==================================================================\n")
cat("   NBA SEASON-LONG PROJECTIONS: 1,000-SEASON MONTE CARLO ENGINE   \n")
cat(sprintf("   Simulations: %d | Margin Sigma: %.1f | Season: %d\n", N_SIMS, MARGIN_SIGMA, CURR_SEASON))
cat("==================================================================\n\n")

# ------------------------------------------------------------------------------
# 2. Canonical 30 NBA Teams Reference
# ------------------------------------------------------------------------------
NBA_TEAMS <- tibble::tribble(
  ~team_id, ~team, ~team_name,      ~conference, ~division,
  1L,       "ATL", "Hawks",         "East",      "Southeast",
  2L,       "BOS", "Celtics",       "East",      "Atlantic",
  3L,       "NOP", "Pelicans",      "West",      "Southwest",
  4L,       "CHI", "Bulls",         "East",      "Central",
  5L,       "CLE", "Cavaliers",     "East",      "Central",
  6L,       "DAL", "Mavericks",     "West",      "Southwest",
  7L,       "DEN", "Nuggets",       "West",      "Northwest",
  8L,       "DET", "Pistons",       "East",      "Central",
  9L,       "GSW", "Warriors",      "West",      "Pacific",
  10L,      "HOU", "Rockets",       "West",      "Southwest",
  11L,      "IND", "Pacers",        "East",      "Central",
  12L,      "LAC", "Clippers",      "West",      "Pacific",
  13L,      "LAL", "Lakers",        "West",      "Pacific",
  14L,      "MIA", "Heat",          "East",      "Southeast",
  15L,      "MIL", "Bucks",         "East",      "Central",
  16L,      "MIN", "Timberwolves",  "West",      "Northwest",
  17L,      "BKN", "Nets",          "East",      "Atlantic",
  18L,      "NYK", "Knicks",        "East",      "Atlantic",
  19L,      "ORL", "Magic",         "East",      "Southeast",
  20L,      "PHI", "76ers",         "East",      "Atlantic",
  21L,      "PHX", "Suns",          "West",      "Pacific",
  22L,      "POR", "Trail Blazers", "West",      "Northwest",
  23L,      "SAC", "Kings",         "West",      "Pacific",
  24L,      "SAS", "Spurs",         "West",      "Southwest",
  25L,      "OKC", "Thunder",       "West",      "Northwest",
  26L,      "UTA", "Jazz",          "West",      "Northwest",
  27L,      "WAS", "Wizards",       "East",      "Southeast",
  28L,      "TOR", "Raptors",       "East",      "Atlantic",
  29L,      "MEM", "Grizzlies",     "West",      "Southwest",
  30L,      "CHA", "Hornets",       "East",      "Southeast"
)

# Standard abbreviation normalizer
normalize_abbr <- function(abbr) {
  recode <- c(
    "GS" = "GSW", "NO" = "NOP", "NY" = "NYK",
    "SA" = "SAS", "UTAH" = "UTA", "WSH" = "WAS"
  )
  if (abbr %in% names(recode)) recode[[abbr]] else abbr
}

# ------------------------------------------------------------------------------
# 3. Schedule Construction (Balanced 1,230-Game Matrix: 41 Home / 41 Away)
# ------------------------------------------------------------------------------
cat("[1/6] Generating balanced 82-game regular season schedule (1,230 games)...\n")

n_teams <- nrow(NBA_TEAMS)
# Round-robin 2 games (1 home, 1 away) between all 435 pairs = 870 games (29 home, 29 away per team)
base_pairs <- t(combn(n_teams, 2))
base_sched <- rbind(
  data.frame(home = base_pairs[, 1], away = base_pairs[, 2]),
  data.frame(home = base_pairs[, 2], away = base_pairs[, 1])
)

# Balanced 12 extra home and away games per team using circulant graph offsets (360 games)
extra_home <- rep(1:n_teams, each = 12)
extra_away <- unlist(lapply(1:n_teams, function(i) ((i - 1 + 1:12) %% n_teams) + 1))
extra_sched <- data.frame(home = extra_home, away = extra_away)

schedule_df <- rbind(base_sched, extra_sched)
stopifnot(nrow(schedule_df) == 1230)
stopifnot(all(table(schedule_df$home) == 41))
stopifnot(all(table(schedule_df$away) == 41))

cat(sprintf("      Generated %d games: exactly 41 home & 41 away games per team.\n", nrow(schedule_df)))

# ------------------------------------------------------------------------------
# 4. Load & Compute Model Ratings for 4 Variants
# ------------------------------------------------------------------------------
cat("[2/6] Computing ratings for 4 model variants...\n")

# --- Variant 1: Production Bottom-Up Rotation BPM ---
standings_path <- get_cache_file("projected_30_team_standings.rds")
if (file.exists(standings_path)) {
  standings <- readRDS(standings_path)
  bu_map <- setNames(standings$Net_Rating, standings$Team)
  rating_bu <- sapply(NBA_TEAMS$team_name, function(tn) {
    if (tn %in% names(bu_map)) bu_map[[tn]] else 0.0
  })
} else {
  message(">>> [WARN] Using SYNTHETIC_FALLBACK: projected_30_team_standings.rds missing.")
  rating_bu <- setNames(rep(0.0, n_teams), NBA_TEAMS$team)
}
# Center at 0.00
rating_bu <- round(rating_bu - mean(rating_bu), 2)

# Provenance guard: the engines now stamp a `data_source` column onto their outputs.
# A cache artifact that is stamped SYNTHETIC_FALLBACK -- or predates the stamp
# entirely -- is not an observation, and the variant built on it carries no
# information about real teams. Report it here, where the rating is actually used.
check_provenance <- function(df, label) {
  src <- if ("data_source" %in% names(df)) unique(as.character(df$data_source)) else NA_character_
  if (length(src) == 0 || all(is.na(src))) {
    message(sprintf(">>> [PROVENANCE] %s carries no data_source stamp; treat it as unverified (regenerate it to find out).", label))
    return(invisible("unstamped"))
  }
  if (any(grepl("SYNTHETIC", src, ignore.case = TRUE))) {
    message(sprintf(">>> [PROVENANCE] %s is SYNTHETIC (%s). This variant is not evidence about real teams.",
                    label, paste(src, collapse = ", ")))
    return(invisible("synthetic"))
  }
  message(sprintf(">>> [PROVENANCE] %s sourced from %s.", label, paste(src, collapse = ", ")))
  invisible("real")
}

# Which NBA season a variant's inputs were actually observed in. Several engines now
# stamp a `season_label` / `source_seasons` column onto their artifacts; this reads it
# back so the exported metadata (and the web UI built on it) can say "2025-26" next to
# a number rather than leaving the reader to assume it describes the season being
# projected. Returns NULL when an artifact carries no season stamp -- the UI then shows
# nothing rather than a guess.
expand_season_label <- function(lab) {
  lab <- trimws(as.character(lab))
  vapply(lab, function(x) {
    if (grepl("^\\d{4}-\\d{2}$", x)) {
      paste0(substr(x, 1, 4), "-", substr(x, 1, 2), substr(x, 6, 7))
    } else {
      x
    }
  }, character(1), USE.NAMES = FALSE)
}

read_season_label <- function(df) {
  if (is.null(df)) return(NULL)
  if ("season_label" %in% names(df)) {
    lab <- unique(as.character(df$season_label))
    lab <- lab[!is.na(lab) & lab != ""]
    if (length(lab) > 0) {
      return(paste(sort(expand_season_label(lab)), collapse = " + "))
    }
  }
  # shot_quality_engine.R stamps `source_seasons` in hoopR end-year numbering
  # ("2026+2027"), which has to be expanded to display spans.
  if ("source_seasons" %in% names(df)) {
    raw <- unique(unlist(strsplit(as.character(df$source_seasons), "\\+")))
    raw <- suppressWarnings(as.integer(trimws(raw)))
    raw <- sort(raw[!is.na(raw)])
    if (length(raw) > 0) {
      return(paste(sprintf("%d-%d", raw - 1L, raw), collapse = " + "))
    }
  }
  NULL
}

# --- Variant 2: Possession-Level RAPM (ORAPM / DRAPM) ---
rapm_path <- get_cache_file("rapm_ratings.rds")
rapm_season_label <- NULL
if (file.exists(rapm_path)) {
  rapm_df <- readRDS(rapm_path)
  check_provenance(rapm_df, "rapm_ratings.rds (Variant 2)")
  rapm_season_label <- read_season_label(rapm_df)
  if (!is.null(rapm_season_label)) {
    message(sprintf(">>> [PROVENANCE] rapm_ratings.rds was fit on the %s season.", rapm_season_label))
  }
  # Proportional weights for 10-man rotation
  rot_weights <- c(36, 34, 32, 28, 26, 24, 22, 18, 10, 10) / 240 * 5.0
  rating_rapm_raw <- sapply(NBA_TEAMS$team, function(tm) {
    tm_players <- rapm_df %>% filter(team == tm) %>% arrange(desc(total_rapm))
    if (nrow(tm_players) >= 5) {
      n_p <- min(nrow(tm_players), length(rot_weights))
      sum(head(tm_players$total_rapm, n_p) * rot_weights[1:n_p])
    } else {
      0.0
    }
  })
} else {
  message(">>> [WARN] Using SYNTHETIC_FALLBACK: rapm_ratings.rds missing.")
  rating_rapm_raw <- setNames(rep(0.0, n_teams), NBA_TEAMS$team)
}
rating_rapm <- round(rating_rapm_raw - mean(rating_rapm_raw), 2)

# --- Variant 3: Shot-Quality Regression & Circadian Travel Fatigue ---
sq_path <- get_cache_file("team_shot_quality.rds")
sq_season_label <- NULL
if (file.exists(sq_path)) {
  sq_df <- readRDS(sq_path)
  check_provenance(sq_df, "team_shot_quality.rds (Variant 3)")
  sq_season_label <- read_season_label(sq_df)
  sq_map <- setNames(sq_df$regression_edge_pts, sq_df$team)
  # Full season regress 60% of shot-luck residuals
  sq_adj <- sapply(NBA_TEAMS$team, function(tm) {
    if (tm %in% names(sq_map)) sq_map[[tm]] * 0.60 else 0.0
  })
} else {
  sq_adj <- setNames(rep(0.0, n_teams), NBA_TEAMS$team)
}

# Arena coordinates for travel fatigue
ARENA_COORDS <- tibble::tribble(
  ~team, ~lat, ~lon, ~tz, ~alt,
  "BOS", 42.3662,  -71.0621, -5,  141,
  "BKN", 40.6826,  -73.9754, -5,   56,
  "NYK", 40.7505,  -73.9934, -5,   33,
  "PHI", 39.9012,  -75.1720, -5,   39,
  "TOR", 43.6435,  -79.3791, -5,  251,
  "CHI", 41.8807,  -87.6742, -6,  597,
  "CLE", 41.4965,  -81.6882, -5,  653,
  "DET", 42.3411,  -83.0553, -5,  600,
  "IND", 39.7640,  -86.1555, -5,  715,
  "MIL", 43.0451,  -87.9174, -6,  617,
  "ATL", 33.7573,  -84.3963, -5, 1020,
  "CHA", 35.2251,  -80.8392, -5,  751,
  "MIA", 25.7814,  -80.1870, -5,    6,
  "ORL", 28.5392,  -81.3839, -5,   82,
  "WAS", 38.8982,  -77.0209, -5,   25,
  "DEN", 39.7487, -105.0077, -7, 5280,
  "MIN", 44.9795,  -93.2761, -6,  830,
  "OKC", 35.4634,  -97.5151, -6, 1201,
  "POR", 45.5316, -122.6668, -8,   50,
  "UTA", 40.7683, -111.9011, -7, 4226,
  "GSW", 37.7680, -122.3877, -8,   10,
  "LAC", 34.0430, -118.2673, -8,  233,
  "LAL", 34.0430, -118.2673, -8,  233,
  "PHX", 33.4457, -112.0712, -7, 1086,
  "SAC", 38.6491, -121.4997, -8,   30,
  "DAL", 32.7905,  -96.8103, -6,  430,
  "HOU", 29.7508,  -95.3621, -6,   80,
  "MEM", 35.1382,  -90.0505, -6,  337,
  "NOP", 29.9490,  -90.0821, -6,    3,
  "SAS", 29.4270,  -98.4375, -6,  650
)

# Great circle distance
haversine_mi <- function(lat1, lon1, lat2, lon2) {
  r <- 3958.8
  p1 <- lat1 * pi / 180; p2 <- lat2 * pi / 180
  dp <- (lat2 - lat1) * pi / 180; dl <- (lon2 - lon1) * pi / 180
  a <- sin(dp/2)^2 + cos(p1)*cos(p2)*sin(dl/2)^2
  r * 2 * atan2(sqrt(a), sqrt(1 - a))
}

# Calculate average road travel drag per team across the schedule
coord_map <- ARENA_COORDS %>% right_join(NBA_TEAMS %>% select(team_id, team), by = "team") %>% arrange(team_id)
road_fatigue_penalty <- numeric(n_teams)

for (i in 1:n_teams) {
  road_games <- schedule_df$home[schedule_df$away == i]
  drags <- sapply(road_games, function(h) {
    dist <- haversine_mi(coord_map$lat[i], coord_map$lon[i], coord_map$lat[h], coord_map$lon[h])
    tz_diff <- abs(coord_map$tz[h] - coord_map$tz[i])
    alt_tax <- if (coord_map$alt[h] >= 4000 && coord_map$alt[i] < 2000) 1.2 else 0.0
    (dist / 1000) * 0.40 + tz_diff * 0.25 + alt_tax
  })
  road_fatigue_penalty[i] <- mean(drags)
}
fatigue_adj <- -(road_fatigue_penalty - mean(road_fatigue_penalty))

rating_sf_raw <- rating_bu + sq_adj + fatigue_adj
rating_sf <- round(rating_sf_raw - mean(rating_sf_raw), 2)

# --- Variant 4: 16-D Team Latent Style Embeddings ---
emb_file <- if (file.exists("team_similarity_matrix.csv")) {
  "team_similarity_matrix.csv"
} else if (exists("CACHE_SIMILARITY") && file.exists(CACHE_SIMILARITY)) {
  CACHE_SIMILARITY
} else {
  NULL
}

if (!is.null(emb_file)) {
  sim_raw <- read.csv(emb_file, row.names = 1, check.names = FALSE)
  # Extract submatrix for 1:30
  sim_sub <- as.matrix(sim_raw[as.character(1:30), as.character(1:30)])
} else {
  sim_sub <- matrix(0.2, nrow = 30, ncol = 30)
  diag(sim_sub) <- 1.0
}

# Style adaptation factor: teams with favorable style matchups overperform
style_centrality <- (rowMeans(sim_sub) - mean(sim_sub)) * 3.5
rating_emb_raw <- rating_bu + style_centrality
rating_emb <- round(rating_emb_raw - mean(rating_emb_raw), 2)

cat(sprintf("      Variant ratings ready: bottom_up (sd=%.2f), rapm (sd=%.2f), shot_fatigue (sd=%.2f), embeddings (sd=%.2f)\n",
            sd(rating_bu), sd(rating_rapm), sd(rating_sf), sd(rating_emb)))

# ------------------------------------------------------------------------------
# 5. Fast Vectorized Monte Carlo Simulation Engine
# ------------------------------------------------------------------------------
cat("[3/6] Simulating 1,000 seasons for all 4 model variants...\n")

# Best-of-7 series win probability formula
prob_best_of_7 <- function(p_game) {
  p_game <- pmax(0.01, pmin(0.99, p_game))
  q <- 1 - p_game
  p_game^4 * (1 + 4*q + 10*q^2 + 20*q^3)
}

# Playoff tournament simulation for 1 season
simulate_season_playoffs <- function(team_wins, team_ratings, east_idx, west_idx) {
  # Tie-breaking with uniform noise
  noise <- runif(length(team_wins), 0, 1e-4)
  rank_scores <- team_wins + noise
  
  # Rank conference teams 1..15
  east_order <- east_idx[order(rank_scores[east_idx], decreasing = TRUE)]
  west_order <- west_idx[order(rank_scores[west_idx], decreasing = TRUE)]
  
  # Seeds 1-6 qualify directly
  east_playoffs <- east_order[1:6]
  west_playoffs <- west_order[1:6]
  
  # Play-In Tournament (Seeds 7-10)
  sim_game <- function(t1, t2) {
    p <- pnorm((team_ratings[t1] - team_ratings[t2] + HCA_PTS) / MARGIN_SIGMA)
    if (runif(1) < p) t1 else t2
  }
  
  # East Play-In
  w7_8  <- sim_game(east_order[7], east_order[8])
  l7_8  <- if (w7_8 == east_order[7]) east_order[8] else east_order[7]
  w9_10 <- sim_game(east_order[9], east_order[10])
  w_final_east <- sim_game(l7_8, w9_10)
  east_playoffs <- c(east_playoffs, w7_8, w_final_east)
  
  # West Play-In
  w7_8_w  <- sim_game(west_order[7], west_order[8])
  l7_8_w  <- if (w7_8_w == west_order[7]) west_order[8] else west_order[7]
  w9_10_w <- sim_game(west_order[9], west_order[10])
  w_final_west <- sim_game(l7_8_w, w9_10_w)
  west_playoffs <- c(west_playoffs, w7_8_w, w_final_west)
  
  # Best-of-7 series between high seed and low seed
  sim_series <- function(high, low) {
    p_h <- pnorm((team_ratings[high] - team_ratings[low] + HCA_PTS) / MARGIN_SIGMA)
    p_a <- pnorm((team_ratings[high] - team_ratings[low] - HCA_PTS) / MARGIN_SIGMA)
    p_avg <- (4 * p_h + 3 * p_a) / 7
    p_ser <- prob_best_of_7(p_avg)
    if (runif(1) < p_ser) high else low
  }
  
  # East Bracket (8 teams)
  e_r1_1 <- sim_series(east_playoffs[1], east_playoffs[8])
  e_r1_2 <- sim_series(east_playoffs[4], east_playoffs[5])
  e_r1_3 <- sim_series(east_playoffs[2], east_playoffs[7])
  e_r1_4 <- sim_series(east_playoffs[3], east_playoffs[6])
  
  e_r2_1 <- sim_series(e_r1_1, e_r1_2)
  e_r2_2 <- sim_series(e_r1_3, e_r1_4)
  east_champ <- sim_series(e_r2_1, e_r2_2)
  
  # West Bracket (8 teams)
  w_r1_1 <- sim_series(west_playoffs[1], west_playoffs[8])
  w_r1_2 <- sim_series(west_playoffs[4], west_playoffs[5])
  w_r1_3 <- sim_series(west_playoffs[2], west_playoffs[7])
  w_r1_4 <- sim_series(west_playoffs[3], west_playoffs[6])
  
  w_r2_1 <- sim_series(w_r1_1, w_r1_2)
  w_r2_2 <- sim_series(w_r1_3, w_r1_4)
  west_champ <- sim_series(w_r2_1, w_r2_2)
  
  # NBA Finals (HCA to team with more regular season wins)
  champ <- if (team_wins[east_champ] >= team_wins[west_champ]) {
    sim_series(east_champ, west_champ)
  } else {
    sim_series(west_champ, east_champ)
  }
  
  list(
    playoff_teams = c(east_playoffs, west_playoffs),
    champion = champ
  )
}

# Run Monte Carlo simulation for a given variant
simulate_variant <- function(ratings, n_sims = 1000) {
  # Expected margin for each game
  h_ratings <- ratings[schedule_df$home]
  a_ratings <- ratings[schedule_df$away]
  game_margins <- (h_ratings - a_ratings) + HCA_PTS
  p_home_win <- pnorm(game_margins / MARGIN_SIGMA)
  
  # Vectorized random simulation across all games and seasons
  u_matrix <- matrix(runif(nrow(schedule_df) * n_sims), nrow = nrow(schedule_df), ncol = n_sims)
  home_won <- (u_matrix < p_home_win)
  
  # Team wins matrix (30 teams x n_sims)
  wins_matrix <- matrix(0L, nrow = n_teams, ncol = n_sims)
  home_indices <- lapply(1:n_teams, function(i) which(schedule_df$home == i))
  away_indices <- lapply(1:n_teams, function(i) which(schedule_df$away == i))
  
  for (i in 1:n_teams) {
    h_wins <- colSums(home_won[home_indices[[i]], , drop = FALSE])
    a_wins <- colSums(!home_won[away_indices[[i]], , drop = FALSE])
    wins_matrix[i, ] <- h_wins + a_wins
  }
  
  # Conference indices
  east_idx <- which(NBA_TEAMS$conference == "East")
  west_idx <- which(NBA_TEAMS$conference == "West")
  
  playoffs_matrix <- matrix(0L, nrow = n_teams, ncol = n_sims)
  title_matrix    <- matrix(0L, nrow = n_teams, ncol = n_sims)
  
  for (s in 1:n_sims) {
    po_res <- simulate_season_playoffs(wins_matrix[, s], ratings, east_idx, west_idx)
    playoffs_matrix[po_res$playoff_teams, s] <- 1L
    title_matrix[po_res$champion, s] <- 1L
  }
  
  list(
    wins_matrix = wins_matrix,
    playoffs_matrix = playoffs_matrix,
    title_matrix = title_matrix,
    mean_wins = round(rowMeans(wins_matrix), 1),
    median_wins = round(apply(wins_matrix, 1, median), 1),
    sd_wins = round(apply(wins_matrix, 1, sd), 2),
    p10 = round(apply(wins_matrix, 1, quantile, 0.10), 1),
    p25 = round(apply(wins_matrix, 1, quantile, 0.25), 1),
    p50 = round(apply(wins_matrix, 1, quantile, 0.50), 1),
    p75 = round(apply(wins_matrix, 1, quantile, 0.75), 1),
    p90 = round(apply(wins_matrix, 1, quantile, 0.90), 1),
    playoff_prob = round(rowMeans(playoffs_matrix), 4),
    title_prob = round(rowMeans(title_matrix), 4)
  )
}

set.seed(SIM_SEED)
sim_bottom_up   <- simulate_variant(rating_bu, n_sims = N_SIMS)
sim_rapm        <- simulate_variant(rating_rapm, n_sims = N_SIMS)
sim_shot_fatigue <- simulate_variant(rating_sf, n_sims = N_SIMS)
sim_embeddings  <- simulate_variant(rating_emb, n_sims = N_SIMS)

# ------------------------------------------------------------------------------
# 6. Ensemble Blend (35% Bottom-Up, 25% RAPM, 20% Shot-Fatigue, 20% Embeddings)
# ------------------------------------------------------------------------------
cat("[4/6] Computing weighted ensemble blend...\n")

ens_w_bu  <- 0.35
ens_w_rap <- 0.25
ens_w_sf  <- 0.20
ens_w_emb <- 0.20

rating_ensemble_raw <-
  ens_w_bu * rating_bu +
  ens_w_rap * rating_rapm +
  ens_w_sf * rating_sf +
  ens_w_emb * rating_emb
rating_ensemble <- round(rating_ensemble_raw, 2)

# RATING-SCALE DISAGREEMENT. How far apart the four models put this team, as a
# weight-respecting SD around the blend, in the same net-rating points the
# margin is expressed in. This is NOT the win-total SD (`ensemble_sd_wins`),
# which is the spread of simulated 82-game outcomes; this is the spread of the
# four *inputs*, so a team the models agree on gets a narrow number and one they
# argue over gets a wide one. build_matchups_dataset.R adds the two sides'
# values in quadrature to MARGIN_SIGMA, widening a game's win probability
# toward 0.5 exactly where the ensemble is least sure of the teams in it.
# Weights sum to 1, so this is the weighted variance around the weighted mean.
rating_variant_mat <- cbind(rating_bu, rating_rapm, rating_sf, rating_emb)
rating_disagreement_sd <- round(sqrt(as.numeric(
  ((rating_variant_mat - rating_ensemble_raw)^2) %*%
    c(ens_w_bu, ens_w_rap, ens_w_sf, ens_w_emb)
)), 2)
cat(sprintf(paste0(
  "      Rating-scale disagreement SD: mean %.2f, range %.2f .. %.2f pts ",
  "(widest: %s)\n"),
  mean(rating_disagreement_sd), min(rating_disagreement_sd),
  max(rating_disagreement_sd),
  NBA_TEAMS$team[which.max(rating_disagreement_sd)]))

ensemble_wins_matrix <- (ens_w_bu * sim_bottom_up$wins_matrix +
                         ens_w_rap * sim_rapm$wins_matrix +
                         ens_w_sf * sim_shot_fatigue$wins_matrix +
                         ens_w_emb * sim_embeddings$wins_matrix)

ensemble_mean_wins   <- round(rowMeans(ensemble_wins_matrix), 1)
ensemble_median_wins <- round(apply(ensemble_wins_matrix, 1, median), 1)
ensemble_sd_wins     <- round(apply(ensemble_wins_matrix, 1, sd), 2)
ensemble_p10         <- round(apply(ensemble_wins_matrix, 1, quantile, 0.10), 1)
ensemble_p25         <- round(apply(ensemble_wins_matrix, 1, quantile, 0.25), 1)
ensemble_p50         <- round(apply(ensemble_wins_matrix, 1, quantile, 0.50), 1)
ensemble_p75         <- round(apply(ensemble_wins_matrix, 1, quantile, 0.75), 1)
ensemble_p90         <- round(apply(ensemble_wins_matrix, 1, quantile, 0.90), 1)

ensemble_playoff_prob <- round(
  ens_w_bu * sim_bottom_up$playoff_prob +
  ens_w_rap * sim_rapm$playoff_prob +
  ens_w_sf * sim_shot_fatigue$playoff_prob +
  ens_w_emb * sim_embeddings$playoff_prob, 4
)

ensemble_title_prob <- round(
  ens_w_bu * sim_bottom_up$title_prob +
  ens_w_rap * sim_rapm$title_prob +
  ens_w_sf * sim_shot_fatigue$title_prob +
  ens_w_emb * sim_embeddings$title_prob, 4
)

# Build 30-Team Final Projection Table
team_projections <- NBA_TEAMS %>%
  mutate(
    # Ensemble metrics
    ensemble_mean_wins   = ensemble_mean_wins,
    ensemble_median_wins = ensemble_median_wins,
    ensemble_sd_wins     = ensemble_sd_wins,
    ensemble_p10         = ensemble_p10,
    ensemble_p25         = ensemble_p25,
    ensemble_p50         = ensemble_p50,
    ensemble_p75         = ensemble_p75,
    ensemble_p90         = ensemble_p90,
    ensemble_playoff_prob = ensemble_playoff_prob,
    ensemble_title_prob   = ensemble_title_prob,
    
    # Aliases
    proj_wins   = ensemble_mean_wins,
    proj_losses = round(82 - ensemble_mean_wins, 1),
    win_pct     = round(ensemble_mean_wins / 82, 3),

    # Variant: Bottom-Up
    variant_bottom_up_mean_wins   = sim_bottom_up$mean_wins,
    variant_bottom_up_median_wins = sim_bottom_up$median_wins,
    variant_bottom_up_sd_wins     = sim_bottom_up$sd_wins,
    variant_bottom_up_p10         = sim_bottom_up$p10,
    variant_bottom_up_p25         = sim_bottom_up$p25,
    variant_bottom_up_p50         = sim_bottom_up$p50,
    variant_bottom_up_p75         = sim_bottom_up$p75,
    variant_bottom_up_p90         = sim_bottom_up$p90,
    variant_bottom_up_playoff_prob = sim_bottom_up$playoff_prob,
    variant_bottom_up_title_prob   = sim_bottom_up$title_prob,

    # Variant: RAPM
    variant_rapm_mean_wins   = sim_rapm$mean_wins,
    variant_rapm_median_wins = sim_rapm$median_wins,
    variant_rapm_sd_wins     = sim_rapm$sd_wins,
    variant_rapm_p10         = sim_rapm$p10,
    variant_rapm_p25         = sim_rapm$p25,
    variant_rapm_p50         = sim_rapm$p50,
    variant_rapm_p75         = sim_rapm$p75,
    variant_rapm_p90         = sim_rapm$p90,
    variant_rapm_playoff_prob = sim_rapm$playoff_prob,
    variant_rapm_title_prob   = sim_rapm$title_prob,

    # Variant: Shot Quality / Travel Fatigue
    variant_shot_fatigue_mean_wins   = sim_shot_fatigue$mean_wins,
    variant_shot_fatigue_median_wins = sim_shot_fatigue$median_wins,
    variant_shot_fatigue_sd_wins     = sim_shot_fatigue$sd_wins,
    variant_shot_fatigue_p10         = sim_shot_fatigue$p10,
    variant_shot_fatigue_p25         = sim_shot_fatigue$p25,
    variant_shot_fatigue_p50         = sim_shot_fatigue$p50,
    variant_shot_fatigue_p75         = sim_shot_fatigue$p75,
    variant_shot_fatigue_p90         = sim_shot_fatigue$p90,
    variant_shot_fatigue_playoff_prob = sim_shot_fatigue$playoff_prob,
    variant_shot_fatigue_title_prob   = sim_shot_fatigue$title_prob,

    # Variant: Embeddings
    variant_embeddings_mean_wins   = sim_embeddings$mean_wins,
    variant_embeddings_median_wins = sim_embeddings$median_wins,
    variant_embeddings_sd_wins     = sim_embeddings$sd_wins,
    variant_embeddings_p10         = sim_embeddings$p10,
    variant_embeddings_p25         = sim_embeddings$p25,
    variant_embeddings_p50         = sim_embeddings$p50,
    variant_embeddings_p75         = sim_embeddings$p75,
    variant_embeddings_p90         = sim_embeddings$p90,
    variant_embeddings_playoff_prob = sim_embeddings$playoff_prob,
    variant_embeddings_title_prob   = sim_embeddings$title_prob
  ) %>%
  arrange(desc(ensemble_mean_wins)) %>%
  mutate(rank = row_number()) %>%
  relocate(rank, team_id, team, team_name, conference, division, proj_wins, proj_losses, win_pct)

cat(sprintf("      Generated 30-team projections. League average wins: %.1f\n", mean(team_projections$proj_wins)))

# ------------------------------------------------------------------------------
# 7. Player Level Projections with Stochastic Injury/Rest Hazard
# ------------------------------------------------------------------------------
cat("[5/6] Simulating player-level distributions with stochastic hazard (>=300 rotation players)...\n")

if (file.exists("roster_join_utils.R")) {
  source("roster_join_utils.R")
}

# Load active rotation players (11 per team = 330 players)
rosters_raw <- if (exists("build_real_rotation_table")) {
  build_real_rotation_table(rotation_size = 11)
} else {
  NULL
}

if (is.null(rosters_raw) || nrow(rosters_raw) < 300) {
  message(">>> [WARN] Using SYNTHETIC_FALLBACK player rotation pool.")
  teams_vec <- rep(NBA_TEAMS$team, each = 11)
  rosters_raw <- tibble(
    player_name = paste(teams_vec, "Player", rep(1:11, times = 30)),
    team = teams_vec,
    pts_mu = rep(c(25, 20, 16, 14, 12, 10, 8, 7, 6, 5, 4), times = 30),
    reb_mu = rep(c(7, 8, 5, 4, 5, 3, 3, 2, 2, 2, 1), times = 30),
    ast_mu = rep(c(6, 4, 4, 3, 2, 2, 1, 1, 1, 1, 1), times = 30),
    avg_min = rep(c(34, 32, 30, 28, 25, 22, 18, 15, 12, 10, 8), times = 30),
    data_source = "SYNTHETIC_FALLBACK"
  )
}

# Normalize team abbreviations and add metadata
roster_meta_path <- get_cache_file("active_rosters_cache.rds")
active_rosters_df <- if (file.exists(roster_meta_path)) readRDS(roster_meta_path) else NULL

player_base <- rosters_raw %>%
  mutate(team = sapply(team, normalize_abbr))

if (!is.null(active_rosters_df)) {
  pos_lookup <- active_rosters_df %>%
    distinct(player_name, .keep_all = TRUE) %>%
    select(player_name, position, player_id)
  player_base <- player_base %>%
    left_join(pos_lookup, by = "player_name") %>%
    mutate(
      position = coalesce(position, "F"),
      player_id = coalesce(as.character(player_id), paste0(team, "_", row_number()))
    )
} else {
  player_base <- player_base %>%
    mutate(
      position = "F",
      player_id = paste0(team, "_", row_number())
    )
}

n_players <- nrow(player_base)

# Stochastic simulation for each player across 1,000 seasons
set.seed(SIM_SEED)
sim_games_mat <- matrix(0L, nrow = n_players, ncol = N_SIMS)
sim_pts_mat   <- matrix(0.0, nrow = n_players, ncol = N_SIMS)
sim_reb_mat   <- matrix(0.0, nrow = n_players, ncol = N_SIMS)
sim_ast_mat   <- matrix(0.0, nrow = n_players, ncol = N_SIMS)
sim_mpg_mat   <- matrix(0.0, nrow = n_players, ncol = N_SIMS)

for (p in 1:n_players) {
  # Durability / load management prior: Beta distribution centered around ~72 games (0.878)
  # High minute starters face slightly more load management variance
  base_avail <- pmax(0.70, pmin(0.95, 0.88 - (player_base$avg_min[p] - 20) * 0.002))
  p_avail <- rbeta(N_SIMS, shape1 = base_avail * 30, shape2 = (1 - base_avail) * 30)
  
  # Occasional severe injury shock (3% probability of missing substantial time)
  injury_shock <- runif(N_SIMS) < 0.03
  p_avail[injury_shock] <- p_avail[injury_shock] * runif(sum(injury_shock), 0.35, 0.65)
  
  games_played <- rbinom(N_SIMS, size = 82, prob = p_avail)
  games_played <- pmax(10, games_played) # Floor at 10 games
  
  # Minute variation per season
  mpg <- pmax(6.0, rnorm(N_SIMS, mean = player_base$avg_min[p], sd = 1.2))
  
  # Production rates per minute
  rate_pts <- player_base$pts_mu[p] / max(8.0, player_base$avg_min[p])
  rate_reb <- player_base$reb_mu[p] / max(8.0, player_base$avg_min[p])
  rate_ast <- player_base$ast_mu[p] / max(8.0, player_base$avg_min[p])
  
  # Simulated season totals
  tot_pts <- games_played * pmax(1.0, rnorm(N_SIMS, mean = rate_pts * mpg, sd = 1.5))
  tot_reb <- games_played * pmax(0.5, rnorm(N_SIMS, mean = rate_reb * mpg, sd = 0.8))
  tot_ast <- games_played * pmax(0.2, rnorm(N_SIMS, mean = rate_ast * mpg, sd = 0.6))
  
  sim_games_mat[p, ] <- games_played
  sim_mpg_mat[p, ]   <- mpg
  sim_pts_mat[p, ]   <- tot_pts
  sim_reb_mat[p, ]   <- tot_reb
  sim_ast_mat[p, ]   <- tot_ast
}

# Aggregate player distributions
# Unrounded simulation means, taken once so the published per-game rates and
# season totals below are derived from the SAME numbers rather than computed
# independently and reconciled afterwards.
mean_games     <- rowMeans(sim_games_mat)
mean_pts_total <- rowMeans(sim_pts_mat)
mean_reb_total <- rowMeans(sim_reb_mat)
mean_ast_total <- rowMeans(sim_ast_mat)

player_projections <- tibble(
  player_id       = player_base$player_id,
  player_name     = player_base$player_name,
  team            = player_base$team,
  position        = player_base$position,
  
  # Projected games & minutes
  proj_games      = round(mean_games, 1),
  proj_mpg        = round(rowMeans(sim_mpg_mat), 1),
  proj_min_total  = round(rowMeans(sim_games_mat * sim_mpg_mat), 1),
  
  # Projected per-game stats.
  #
  # These are the SEASON RATE, mean(total) / mean(games), not the mean of each
  # simulation's own per-game ratio. The two are different statistics: a player
  # whose minutes and availability are correlated across simulations has
  # E[pts/games] != E[pts]/E[games] (Jensen), and the published totals below are
  # E[pts]. Publishing the mean-of-ratios here left season totals that did not
  # reconcile with per_game * games by up to 5.3 points - a real inconsistency
  # between two numbers on the same row of the same page, not a rounding
  # artifact. The rate is also what a "per game" figure on a season projection
  # means: total production divided by games played.
  proj_pts        = round(mean_pts_total / mean_games, 1),
  proj_reb        = round(mean_reb_total / mean_games, 1),
  proj_ast        = round(mean_ast_total / mean_games, 1),

  # Projected season totals, straight off the unrounded simulation. These are
  # the source of truth; the per-game rates above are derived from them, so the
  # identity total == per_game * games now holds exactly before publishing and
  # the only residual is the 1-decimal rounding of the three published figures.
  proj_pts_total  = round(mean_pts_total, 1),
  proj_reb_total  = round(mean_reb_total, 1),
  proj_ast_total  = round(mean_ast_total, 1),
  
  # Quantile distributions: Points
  pts_p10         = round(apply(sim_pts_mat / sim_games_mat, 1, quantile, 0.10), 1),
  pts_p25         = round(apply(sim_pts_mat / sim_games_mat, 1, quantile, 0.25), 1),
  pts_p50         = round(apply(sim_pts_mat / sim_games_mat, 1, quantile, 0.50), 1),
  pts_p75         = round(apply(sim_pts_mat / sim_games_mat, 1, quantile, 0.75), 1),
  pts_p90         = round(apply(sim_pts_mat / sim_games_mat, 1, quantile, 0.90), 1),
  
  # Quantile distributions: Rebounds
  reb_p10         = round(apply(sim_reb_mat / sim_games_mat, 1, quantile, 0.10), 1),
  reb_p25         = round(apply(sim_reb_mat / sim_games_mat, 1, quantile, 0.25), 1),
  reb_p50         = round(apply(sim_reb_mat / sim_games_mat, 1, quantile, 0.50), 1),
  reb_p75         = round(apply(sim_reb_mat / sim_games_mat, 1, quantile, 0.75), 1),
  reb_p90         = round(apply(sim_reb_mat / sim_games_mat, 1, quantile, 0.90), 1),
  
  # Quantile distributions: Assists
  ast_p10         = round(apply(sim_ast_mat / sim_games_mat, 1, quantile, 0.10), 1),
  ast_p25         = round(apply(sim_ast_mat / sim_games_mat, 1, quantile, 0.25), 1),
  ast_p50         = round(apply(sim_ast_mat / sim_games_mat, 1, quantile, 0.50), 1),
  ast_p75         = round(apply(sim_ast_mat / sim_games_mat, 1, quantile, 0.75), 1),
  ast_p90         = round(apply(sim_ast_mat / sim_games_mat, 1, quantile, 0.90), 1),
  
  # Quantile distributions: Games Played
  games_p10       = round(apply(sim_games_mat, 1, quantile, 0.10), 1),
  games_p25       = round(apply(sim_games_mat, 1, quantile, 0.25), 1),
  games_p50       = round(apply(sim_games_mat, 1, quantile, 0.50), 1),
  games_p75       = round(apply(sim_games_mat, 1, quantile, 0.75), 1),
  games_p90       = round(apply(sim_games_mat, 1, quantile, 0.90), 1),
  
  # Uncertainty (standard deviation)
  games_sd        = round(apply(sim_games_mat, 1, sd), 1),
  pts_sd          = round(apply(sim_pts_mat / sim_games_mat, 1, sd), 1),
  reb_sd          = round(apply(sim_reb_mat / sim_games_mat, 1, sd), 1),
  ast_sd          = round(apply(sim_ast_mat / sim_games_mat, 1, sd), 1)
)

# Compute outlier z-scores across active player pool
pts_mu_all <- mean(player_projections$proj_pts)
pts_sd_all <- sd(player_projections$proj_pts)
reb_mu_all <- mean(player_projections$proj_reb)
reb_sd_all <- sd(player_projections$proj_reb)
ast_mu_all <- mean(player_projections$proj_ast)
ast_sd_all <- sd(player_projections$proj_ast)
pra_all    <- player_projections$proj_pts + player_projections$proj_reb + player_projections$proj_ast
pra_mu_all <- mean(pra_all)
pra_sd_all <- sd(pra_all)

player_projections <- player_projections %>%
  mutate(
    pts_zscore = round((proj_pts - pts_mu_all) / pts_sd_all, 2),
    reb_zscore = round((proj_reb - reb_mu_all) / reb_sd_all, 2),
    ast_zscore = round((proj_ast - ast_mu_all) / ast_sd_all, 2),
    pra_zscore = round(((proj_pts + proj_reb + proj_ast) - pra_mu_all) / pra_sd_all, 2),
    is_outlier = abs(pts_zscore) >= 2.0 | abs(reb_zscore) >= 2.0 | abs(ast_zscore) >= 2.0
  ) %>%
  arrange(desc(proj_pts))

cat(sprintf("      Generated projections for %d rotation players. Outlier players flagged: %d\n",
            nrow(player_projections), sum(player_projections$is_outlier)))

# ------------------------------------------------------------------------------
# 8. Export RDS & JSON Artifacts
# ------------------------------------------------------------------------------
cat("[6/6] Exporting RDS caches and Next.js frontend JSON schemas...\n")

# Model metadata schema
projected_season_label <- sprintf("%d-%d", CURR_SEASON - 1L, CURR_SEASON)
prior_season_label     <- sprintf("%d-%d", CURR_SEASON - 2L, CURR_SEASON - 1L)

metadata_obj <- list(
  # 1.2 adds the projected `season_label` and full-year per-model
  # `source_season_label`, so the UI can distinguish the season being PROJECTED
  # from the season each variant's inputs were OBSERVED in.
  schema_version       = "1.2",
  pipeline_stage       = "season_long_projections",
  generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  season               = CURR_SEASON,
  season_label         = projected_season_label,
  n_simulations        = N_SIMS,
  margin_sigma         = MARGIN_SIGMA,
  home_court_advantage = HCA_PTS,
  total_schedule_games = nrow(schedule_df),
  teams_count          = nrow(team_projections),
  players_count        = nrow(player_projections),
  models = list(
    ensemble = list(
      name = "Multi-Model Ensemble Blend",
      weights = list(
        variant_bottom_up   = ens_w_bu,
        variant_rapm        = ens_w_rap,
        variant_shot_fatigue = ens_w_sf,
        variant_embeddings  = ens_w_emb
      ),
      description = "Weighted blend of production bottom-up, possession-level RAPM, shot quality fatigue, and style embeddings"
    ),
    variant_bottom_up = list(
      name = "Production Bottom-Up Rotation BPM",
      weight = ens_w_bu,
      description = "Minute-weighted player BPM ratings aggregated over 240-minute active roster rotations",
      # Player BPM and rotation form come from the last completed season; only the
      # schedule and simulation horizon are 2026-2027.
      source_season_label = prior_season_label
    ),
    variant_rapm = list(
      name = "Possession-Level RAPM (ORAPM / DRAPM)",
      weight = ens_w_rap,
      description = paste0("Ridge-regularized adjusted plus-minus fit one row per possession, ",
                           "separating offensive and defensive impact, centered across league"),
      # The season the ratings were OBSERVED in, which is not the season being
      # projected: hoopR publishes no possession table for a season in progress.
      source_season_label = rapm_season_label
    ),
    variant_shot_fatigue = list(
      name = "Shot Quality & Circadian Travel Fatigue",
      weight = ens_w_sf,
      description = "Bottom-up ratings adjusted for spatial shot-quality regression and travel/circadian rest fatigue",
      source_season_label = sq_season_label
    ),
    variant_embeddings = list(
      name = "16-D Style Latent Embeddings",
      weight = ens_w_emb,
      description = "Pythagorean expected win probability modulated by 16-D team stylistic similarity matrix",
      # The similarity matrix is estimated from the last completed season's style
      # profile, so the observed input span is the prior season.
      source_season_label = prior_season_label
    )
  )
)

# Export targets.
# Cache is the internal artifact store; WEB_DATA_DIR is the directory Next.js
# serves. Both copies are written on every run so publishing projections needs
# no manual copy step (issue #18).
out_teams_rds    <- file.path(CACHE_DIR, "projections_season_teams.rds")
out_players_rds  <- file.path(CACHE_DIR, "projections_season_players.rds")
out_ensemble_ratings_rds <- file.path(CACHE_DIR, "ensemble_team_ratings.rds")
out_teams_json   <- file.path(CACHE_DIR, "projections_season_teams.json")
out_players_json <- file.path(CACHE_DIR, "projections_season_players.json")
out_meta_json    <- file.path(CACHE_DIR, "projections_models_metadata.json")

web_teams_json   <- file.path(WEB_DATA_DIR, "projections_season_teams.json")
web_players_json <- file.path(WEB_DATA_DIR, "projections_season_players.json")
web_meta_json    <- file.path(WEB_DATA_DIR, "projections_models_metadata.json")

# Write RDS
saveRDS(team_projections, out_teams_rds)
saveRDS(player_projections, out_players_rds)
ensemble_ratings_df <- tibble::tibble(
  team = NBA_TEAMS$team,
  team_name = NBA_TEAMS$team_name,
  ensemble_net_rating = rating_ensemble,
  rating_bottom_up = rating_bu,
  rating_rapm = rating_rapm,
  rating_shot_fatigue = rating_sf,
  rating_embeddings = rating_emb,
  proj_wins = ensemble_mean_wins,
  # Spread of simulated 82-game win totals. Reported, not consumed per game:
  # it is on the wins scale, not the margin scale.
  proj_wins_sd = ensemble_sd_wins,
  # Spread of the four model ratings around the blend, in net-rating points -
  # the margin-scale uncertainty build_matchups_dataset.R folds into a game's
  # sigma so the blend's own disagreement reaches the published win probability.
  rating_disagreement_sd = rating_disagreement_sd
)
saveRDS(ensemble_ratings_df, out_ensemble_ratings_rds)
cat(sprintf("      Saved: %s (%d rows)\n", out_teams_rds, nrow(team_projections)))
cat(sprintf("      Saved: %s (%d rows)\n", out_players_rds, nrow(player_projections)))
cat(sprintf("      Saved: %s (%d teams)\n", out_ensemble_ratings_rds, nrow(ensemble_ratings_df)))

# Write cache JSON (pretty, auto_unbox for clean API ingestion) and publish the
# exact same payloads to the web data directory.
write_json(team_projections, out_teams_json, pretty = TRUE, auto_unbox = TRUE)
write_json(player_projections, out_players_json, pretty = TRUE, auto_unbox = TRUE)
write_json(metadata_obj, out_meta_json, pretty = TRUE, auto_unbox = TRUE)
write_json(team_projections, web_teams_json, pretty = TRUE, auto_unbox = TRUE)
write_json(player_projections, web_players_json, pretty = TRUE, auto_unbox = TRUE)
write_json(metadata_obj, web_meta_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf("      Saved: %s\n", out_teams_json))
cat(sprintf("      Saved: %s\n", out_players_json))
cat(sprintf("      Saved: %s\n", out_meta_json))
cat(sprintf("      Published: %s\n", web_teams_json))
cat(sprintf("      Published: %s\n", web_players_json))
cat(sprintf("      Published: %s\n", web_meta_json))

# ------------------------------------------------------------------------------
# Publish contract (issue #18)
# ------------------------------------------------------------------------------
# A "successful" simulator run that leaves any of the six JSON artifacts
# untouched (or publishes a different payload than the cache copy) would let the
# site serve stale projections. Fail loudly instead: both the cache and web
# copies must exist, have been rewritten during this run, and carry the same
# generated_at / season_label.
published_json <- c(
  out_teams_json, out_players_json, out_meta_json,
  web_teams_json, web_players_json, web_meta_json
)

missing_json <- published_json[!file.exists(published_json)]
if (length(missing_json) > 0) {
  stop(sprintf(
    "Projection publish contract failed; missing artifact(s): %s",
    paste(missing_json, collapse = ", ")
  ), call. = FALSE)
}

published_mtimes <- file.info(published_json)$mtime
stale_json <- published_json[
  is.na(published_mtimes) |
    as.numeric(difftime(published_mtimes, simulator_started_at, units = "secs")) < -1
]
if (length(stale_json) > 0) {
  stop(sprintf(
    "Projection publish contract failed; artifact(s) not rewritten by this run: %s",
    paste(stale_json, collapse = ", ")
  ), call. = FALSE)
}

for (pair in list(
  c(out_teams_json, web_teams_json),
  c(out_players_json, web_players_json),
  c(out_meta_json, web_meta_json)
)) {
  cache_md5 <- unname(tools::md5sum(pair[[1]]))
  web_md5   <- unname(tools::md5sum(pair[[2]]))
  if (!identical(cache_md5, web_md5)) {
    stop(sprintf(
      "Projection publish contract failed; web copy does not match cache copy:\n  cache: %s\n  web:   %s",
      pair[[1]], pair[[2]]
    ), call. = FALSE)
  }
}

cache_meta <- fromJSON(out_meta_json)
web_meta   <- fromJSON(web_meta_json)
if (!identical(cache_meta$generated_at, web_meta$generated_at) ||
    !identical(cache_meta$season_label, web_meta$season_label)) {
  stop(sprintf(
    "Projection publish contract failed; metadata mismatch (cache generated_at=%s season=%s, web generated_at=%s season=%s).",
    cache_meta$generated_at, cache_meta$season_label,
    web_meta$generated_at, web_meta$season_label
  ), call. = FALSE)
}

generated_at_ct <- as.POSIXct(web_meta$generated_at, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
if (is.na(generated_at_ct) ||
    as.numeric(difftime(generated_at_ct, simulator_started_at, units = "secs")) < -2) {
  stop(sprintf(
    "Projection publish contract failed; web metadata generated_at (%s) predates this run (%s).",
    web_meta$generated_at, format(simulator_started_at, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ), call. = FALSE)
}

cat(sprintf("      Publish contract OK: 6 JSON artifacts rewritten and web copies match cache (%s, %s)\n",
            web_meta$generated_at, web_meta$season_label))

cat("\n==================================================================\n")
cat("      SEASON SIMULATOR RUN COMPLETED SUCCESSFULLY (<90s)          \n")
cat("==================================================================\n\n")
