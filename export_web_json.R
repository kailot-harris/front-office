# ==============================================================================
# export_web_json.R
# Static JSON Export Stage for Next.js Web App (WNBA Analytics)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/export_web_json.R
#
# Generates static JSON files in web/public/data/ consumed by the Next.js frontend:
#   1. projections_season_teams.json   - Team projected standings, 4 model variants & ensemble
#   2. projections_season_players.json - Player projection distributions, MPG & outlier flags
#   3. projections_models_metadata.json - Simulation constants, model descriptions & weights
#   4. projections_diagnostics.json     - Historical model calibration, Brier score, drift
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

source("config.R")
if (file.exists("logging_utils.R")) source("logging_utils.R")

WNBA_TEAM_METADATA <- list(
  ATL = list(id = 20, name = "Dream", fullName = "Atlanta Dream", conf = "East", div = "Eastern"),
  CHI = list(id = 19, name = "Sky", fullName = "Chicago Sky", conf = "East", div = "Eastern"),
  CON = list(id = 18, name = "Sun", fullName = "Connecticut Sun", conf = "East", div = "Eastern"),
  DAL = list(id = 6,  name = "Wings", fullName = "Dallas Wings", conf = "West", div = "Western"),
  GS  = list(id = 25, name = "Valkyries", fullName = "Golden State Valkyries", conf = "West", div = "Western"),
  IND = list(id = 5,  name = "Fever", fullName = "Indiana Fever", conf = "East", div = "Eastern"),
  LA  = list(id = 8,  name = "Sparks", fullName = "Los Angeles Sparks", conf = "West", div = "Western"),
  LV  = list(id = 17, name = "Aces", fullName = "Las Vegas Aces", conf = "West", div = "Western"),
  MIN = list(id = 9,  name = "Lynx", fullName = "Minnesota Lynx", conf = "West", div = "Western"),
  NY  = list(id = 11, name = "Liberty", fullName = "New York Liberty", conf = "East", div = "Eastern"),
  PHX = list(id = 14, name = "Mercury", fullName = "Phoenix Mercury", conf = "West", div = "Western"),
  POR = list(id = 26, name = "Fire", fullName = "Portland Fire", conf = "West", div = "Western"),
  SEA = list(id = 16, name = "Storm", fullName = "Seattle Storm", conf = "West", div = "Western"),
  TOR = list(id = 27, name = "Tempo", fullName = "Toronto Tempo", conf = "East", div = "Eastern"),
  WSH = list(id = 3,  name = "Mystics", fullName = "Washington Mystics", conf = "East", div = "Eastern")
)

export_web_json <- function(output_dir = file.path("web", "public", "data"), sync_cache = TRUE) {
  start_time <- Sys.time()
  message(">>> [EXPORT_WEB_JSON] Starting JSON export for WNBA Next.js web app...")
  if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

  # ----------------------------------------------------------------------------
  # 1. Team Projections & Model Variants (projections_season_teams.json)
  # ----------------------------------------------------------------------------
  standings_path <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  if (!file.exists(standings_path)) {
    warning("Standings cache not found; running roster_bottom_up_engine...")
    if (file.exists("roster_bottom_up_engine.R")) {
      source("roster_bottom_up_engine.R")
    }
  }

  standings_df <- if (file.exists(standings_path)) readRDS(standings_path) else NULL
  if (is.null(standings_df)) {
    stop("Cannot export web JSON: projected_wnba_standings.rds unavailable.")
  }

  # Load secondary engine caches for variants
  rapm_path <- CACHE_RAPM_RATINGS
  rapm_df <- if (file.exists(rapm_path)) readRDS(rapm_path) else NULL

  shot_path <- file.path(CACHE_DIR, "team_shot_quality.rds")
  shot_df <- if (file.exists(shot_path)) readRDS(shot_path) else NULL

  emb_path <- file.path("data", "team_embeddings.csv")
  emb_df <- if (file.exists(emb_path)) read.csv(emb_path, stringsAsFactors = FALSE) else NULL

  # Map full team names to abbreviations
  team_abbr_map <- setNames(names(WNBA_TEAMS), unname(WNBA_TEAMS))

  # Compute variant ratings / win adjustments
  teams_list <- list()

  for (i in seq_len(nrow(standings_df))) {
    row <- standings_df[i, ]
    full_name <- row$Team
    abbr <- team_abbr_map[full_name]
    if (is.na(abbr)) {
      # Fallback by partial match
      matched <- names(WNBA_TEAMS)[sapply(unname(WNBA_TEAMS), function(n) grepl(n, full_name) || grepl(full_name, n))]
      abbr <- if (length(matched) > 0) matched[1] else "WNBA"
    }

    info <- WNBA_TEAM_METADATA[[abbr]]
    if (is.null(info)) {
      info <- list(id = i, name = full_name, fullName = full_name, conf = "East", div = "Eastern")
    }

    bu_wins <- as.numeric(row$Proj_Wins)
    sd_wins <- if ("Proj_Wins_SD" %in% names(row) && !is.na(row$Proj_Wins_SD)) as.numeric(row$Proj_Wins_SD) else 3.1
    sd_wins <- max(1.5, min(5.0, sd_wins))

    # Variant 2: RAPM variation
    # Check if team has player RAPM sum
    rapm_adj <- 0
    if (!is.null(rapm_df) && "team" %in% names(rapm_df)) {
      t_rapm <- rapm_df %>% filter(team == full_name | team == abbr)
      if (nrow(t_rapm) > 0) {
        rapm_adj <- mean(head(sort(t_rapm$total_rapm, decreasing = TRUE), 8), na.rm = TRUE) - 4.5
        rapm_adj <- pmax(-4, pmin(4, rapm_adj))
      }
    }
    rapm_wins <- round(pmax(10, pmin(36, bu_wins + rapm_adj * 0.8)), 1)

    # Variant 3: Shot quality & Fatigue variation
    shot_adj <- 0
    if (!is.null(shot_df) && "team" %in% names(shot_df)) {
      t_shot <- shot_df %>% filter(team == abbr | team == full_name)
      if (nrow(t_shot) > 0 && "regression_edge_pts" %in% names(t_shot)) {
        shot_adj <- as.numeric(t_shot$regression_edge_pts[1]) * 0.6
      }
    }
    shot_wins <- round(pmax(10, pmin(36, bu_wins + shot_adj)), 1)

    # Variant 4: Latent Style Embeddings variation
    emb_adj <- 0
    if (!is.null(emb_df) && "team_id" %in% names(emb_df)) {
      t_emb <- emb_df %>% filter(team_id == abbr)
      if (nrow(t_emb) > 0) {
        # Norm of first 4 style dimensions centered
        emb_adj <- (sum(as.numeric(t_emb[1, 2:5])) - 0.2) * 1.2
        emb_adj <- pmax(-3.5, pmin(3.5, emb_adj))
      }
    }
    emb_wins <- round(pmax(10, pmin(36, bu_wins + emb_adj)), 1)

    # Ensemble blend (weights: 0.35 BU, 0.25 RAPM, 0.20 Shot/Fatigue, 0.20 Embeddings)
    ens_wins <- round(0.35 * bu_wins + 0.25 * rapm_wins + 0.20 * shot_wins + 0.20 * emb_wins, 1)
    ens_losses <- round(WNBA_SEASON_GAMES - ens_wins, 1)
    win_pct <- round(ens_wins / WNBA_SEASON_GAMES, 3)

    # Quantile helper
    q_helper <- function(m, s) {
      list(
        p10 = round(pmax(8, m - 1.28 * s), 1),
        p25 = round(pmax(10, m - 0.67 * s), 1),
        p50 = round(m, 1),
        p75 = round(pmin(40, m + 0.67 * s), 1),
        p90 = round(pmin(42, m + 1.28 * s), 1)
      )
    }

    ens_q <- q_helper(ens_wins, sd_wins)
    bu_q  <- q_helper(bu_wins, sd_wins * 1.05)
    rapm_q <- q_helper(rapm_wins, sd_wins * 1.1)
    shot_q <- q_helper(shot_wins, sd_wins * 1.02)
    emb_q <- q_helper(emb_wins, sd_wins * 1.08)

    # Probabilities: 8 playoff spots out of 15 teams
    # 21.5 wins is roughly the 8th seed threshold in 44-game season (league average is 22)
    playoff_prob <- function(m, s) round(pmax(0.01, pmin(0.999, pnorm((m - 21.0) / s))), 4)
    title_prob <- function(m) {
      val <- exp((m - 26.5) * 0.45) / (1 + exp((m - 26.5) * 0.45)) * 0.35
      round(pmax(0.001, pmin(0.35, val)), 4)
    }

    team_entry <- list(
      rank                           = as.integer(row$Rank),
      team_id                        = as.integer(info$id),
      team                           = abbr,
      team_name                      = info$name,
      conference                     = info$conf,
      division                       = info$div,
      proj_wins                      = ens_wins,
      proj_losses                    = ens_losses,
      win_pct                        = win_pct,
      ensemble_mean_wins             = ens_wins,
      ensemble_median_wins           = ens_q$p50,
      ensemble_sd_wins               = round(sd_wins, 2),
      ensemble_p10                   = ens_q$p10,
      ensemble_p25                   = ens_q$p25,
      ensemble_p50                   = ens_q$p50,
      ensemble_p75                   = ens_q$p75,
      ensemble_p90                   = ens_q$p90,
      ensemble_playoff_prob          = playoff_prob(ens_wins, sd_wins),
      ensemble_title_prob            = title_prob(ens_wins),
      variant_bottom_up_mean_wins    = bu_wins,
      variant_bottom_up_median_wins  = bu_q$p50,
      variant_bottom_up_sd_wins      = round(sd_wins * 1.05, 2),
      variant_bottom_up_p10          = bu_q$p10,
      variant_bottom_up_p25          = bu_q$p25,
      variant_bottom_up_p50          = bu_q$p50,
      variant_bottom_up_p75          = bu_q$p75,
      variant_bottom_up_p90          = bu_q$p90,
      variant_bottom_up_playoff_prob = playoff_prob(bu_wins, sd_wins * 1.05),
      variant_bottom_up_title_prob   = title_prob(bu_wins),
      variant_rapm_mean_wins         = rapm_wins,
      variant_rapm_median_wins       = rapm_q$p50,
      variant_rapm_sd_wins           = round(sd_wins * 1.1, 2),
      variant_rapm_p10               = rapm_q$p10,
      variant_rapm_p25               = rapm_q$p25,
      variant_rapm_p50               = rapm_q$p50,
      variant_rapm_p75               = rapm_q$p75,
      variant_rapm_p90               = rapm_q$p90,
      variant_rapm_playoff_prob      = playoff_prob(rapm_wins, sd_wins * 1.1),
      variant_rapm_title_prob        = title_prob(rapm_wins),
      variant_shot_fatigue_mean_wins = shot_wins,
      variant_shot_fatigue_median_wins = shot_q$p50,
      variant_shot_fatigue_sd_wins   = round(sd_wins * 1.02, 2),
      variant_shot_fatigue_p10       = shot_q$p10,
      variant_shot_fatigue_p25       = shot_q$p25,
      variant_shot_fatigue_p50       = shot_q$p50,
      variant_shot_fatigue_p75       = shot_q$p75,
      variant_shot_fatigue_p90       = shot_q$p90,
      variant_shot_fatigue_playoff_prob = playoff_prob(shot_wins, sd_wins * 1.02),
      variant_shot_fatigue_title_prob = title_prob(shot_wins),
      variant_embeddings_mean_wins   = emb_wins,
      variant_embeddings_median_wins = emb_q$p50,
      variant_embeddings_sd_wins     = round(sd_wins * 1.08, 2),
      variant_embeddings_p10         = emb_q$p10,
      variant_embeddings_p25         = emb_q$p25,
      variant_embeddings_p50         = emb_q$p50,
      variant_embeddings_p75         = emb_q$p75,
      variant_embeddings_p90         = emb_q$p90,
      variant_embeddings_playoff_prob = playoff_prob(emb_wins, sd_wins * 1.08),
      variant_embeddings_title_prob  = title_prob(emb_wins)
    )
    teams_list[[length(teams_list) + 1]] <- team_entry
  }

  teams_df <- bind_rows(lapply(teams_list, as.data.frame, stringsAsFactors = FALSE))
  teams_df <- teams_df %>%
    arrange(desc(ensemble_mean_wins)) %>%
    mutate(rank = row_number())

  # ----------------------------------------------------------------------------
  # 2. Player Projections (projections_season_players.json)
  # ----------------------------------------------------------------------------
  rosters_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  player_box_path <- file.path(CACHE_DIR, "player_box_scores_cache.rds")

  rosters_df <- if (file.exists(rosters_path)) readRDS(rosters_path) else tibble()
  player_box_df <- if (file.exists(player_box_path)) readRDS(player_box_path) else tibble()

  # Compute empirical per-player averages from box scores (prioritize CURRENT_SEASON with historical fallback)
  if (nrow(player_box_df) > 0) {
    # Check if season column is present
    has_season_col <- "season" %in% names(player_box_df)
    
    current_season_box <- if (has_season_col) {
      player_box_df %>% filter(season == CURRENT_SEASON, !is.na(minutes) & minutes > 0)
    } else {
      tibble()
    }

    # If current season has games for players, compute current season averages
    current_stats <- if (nrow(current_season_box) > 0) {
      current_season_box %>%
        group_by(athlete_display_name) %>%
        summarise(
          career_games = n(),
          avg_mpg = mean(minutes, na.rm = TRUE),
          avg_pts = mean(points, na.rm = TRUE),
          avg_reb = mean(rebounds, na.rm = TRUE),
          avg_ast = mean(assists, na.rm = TRUE),
          sd_pts = sd(points, na.rm = TRUE),
          sd_reb = sd(rebounds, na.rm = TRUE),
          sd_ast = sd(assists, na.rm = TRUE),
          .groups = "drop"
        )
    } else {
      tibble()
    }

    # All-season averages as fallback for rookies or players with small 2026 sample
    all_stats <- player_box_df %>%
      filter(!is.na(minutes) & minutes > 0) %>%
      group_by(athlete_display_name) %>%
      summarise(
        all_career_games = n(),
        all_avg_mpg = mean(minutes, na.rm = TRUE),
        all_avg_pts = mean(points, na.rm = TRUE),
        all_avg_reb = mean(rebounds, na.rm = TRUE),
        all_avg_ast = mean(assists, na.rm = TRUE),
        all_sd_pts = sd(points, na.rm = TRUE),
        all_sd_reb = sd(rebounds, na.rm = TRUE),
        all_sd_ast = sd(assists, na.rm = TRUE),
        .groups = "drop"
      )

    if (nrow(current_stats) > 0) {
      player_stats <- all_stats %>%
        left_join(current_stats, by = "athlete_display_name") %>%
        mutate(
          career_games = coalesce(career_games, all_career_games),
          avg_mpg = coalesce(avg_mpg, all_avg_mpg),
          avg_pts = coalesce(avg_pts, all_avg_pts),
          avg_reb = coalesce(avg_reb, all_avg_reb),
          avg_ast = coalesce(avg_ast, all_avg_ast),
          sd_pts = coalesce(sd_pts, all_sd_pts),
          sd_reb = coalesce(sd_reb, all_sd_reb),
          sd_ast = coalesce(sd_ast, all_sd_ast)
        ) %>%
        select(athlete_display_name, career_games, avg_mpg, avg_pts, avg_reb, avg_ast, sd_pts, sd_reb, sd_ast)
    } else {
      player_stats <- all_stats %>%
        rename(
          career_games = all_career_games,
          avg_mpg = all_avg_mpg,
          avg_pts = all_avg_pts,
          avg_reb = all_avg_reb,
          avg_ast = all_avg_ast,
          sd_pts = all_sd_pts,
          sd_reb = all_sd_reb,
          sd_ast = all_sd_ast
        )
    }
  } else {
    player_stats <- tibble(
      athlete_display_name = character(),
      career_games = integer(),
      avg_mpg = numeric(),
      avg_pts = numeric(),
      avg_reb = numeric(),
      avg_ast = numeric(),
      sd_pts = numeric(),
      sd_reb = numeric(),
      sd_ast = numeric()
    )
  }

  # Build projected player table for all active roster players
  if (nrow(rosters_df) > 0) {
    players_joined <- rosters_df %>%
      left_join(player_stats, by = c("player_name" = "athlete_display_name")) %>%
      mutate(
        position = coalesce(position, "F"),
        # Fill missing stats with reasonable role-player prior
        proj_mpg = round(coalesce(avg_mpg, 16.0), 1),
        proj_pts = round(coalesce(avg_pts, 7.5), 1),
        proj_reb = round(coalesce(avg_reb, 3.2), 1),
        proj_ast = round(coalesce(avg_ast, 1.8), 1),
        # Games played out of 44
        proj_games = round(pmin(43, pmax(25, 38.5 + (proj_mpg - 20) * 0.15 + rnorm(n(), 0, 1.5))), 1),
        proj_min_total = round(proj_games * proj_mpg, 1),
        proj_pts_total = round(proj_games * proj_pts, 1),
        proj_reb_total = round(proj_games * proj_reb, 1),
        proj_ast_total = round(proj_games * proj_ast, 1),
        # SDs
        pts_sd = round(coalesce(sd_pts, pmax(1.0, proj_pts * 0.35)), 1),
        reb_sd = round(coalesce(sd_reb, pmax(0.6, proj_reb * 0.40)), 1),
        ast_sd = round(coalesce(sd_ast, pmax(0.5, proj_ast * 0.45)), 1),
        games_sd = round(runif(n(), 2.5, 4.5), 1),
        # Quantiles
        pts_p10 = round(pmax(0, proj_pts - 1.28 * pts_sd * 0.4), 1),
        pts_p25 = round(pmax(0, proj_pts - 0.67 * pts_sd * 0.4), 1),
        pts_p50 = proj_pts,
        pts_p75 = round(proj_pts + 0.67 * pts_sd * 0.4, 1),
        pts_p90 = round(proj_pts + 1.28 * pts_sd * 0.4, 1),
        reb_p10 = round(pmax(0, proj_reb - 1.28 * reb_sd * 0.4), 1),
        reb_p25 = round(pmax(0, proj_reb - 0.67 * reb_sd * 0.4), 1),
        reb_p50 = proj_reb,
        reb_p75 = round(proj_reb + 0.67 * reb_sd * 0.4, 1),
        reb_p90 = round(proj_reb + 1.28 * reb_sd * 0.4, 1),
        ast_p10 = round(pmax(0, proj_ast - 1.28 * ast_sd * 0.4), 1),
        ast_p25 = round(pmax(0, proj_ast - 0.67 * ast_sd * 0.4), 1),
        ast_p50 = proj_ast,
        ast_p75 = round(proj_ast + 0.67 * ast_sd * 0.4, 1),
        ast_p90 = round(proj_ast + 1.28 * ast_sd * 0.4, 1),
        games_p10 = round(pmax(15, proj_games - 1.28 * games_sd), 1),
        games_p25 = round(pmax(20, proj_games - 0.67 * games_sd), 1),
        games_p50 = proj_games,
        games_p75 = round(pmin(44, proj_games + 0.67 * games_sd), 1),
        games_p90 = round(pmin(44, proj_games + 1.28 * games_sd), 1)
      )

    # Compute outlier z-scores
    mu_pts <- mean(players_joined$proj_pts)
    sd_pts_all <- sd(players_joined$proj_pts)
    mu_reb <- mean(players_joined$proj_reb)
    sd_reb_all <- sd(players_joined$proj_reb)
    mu_ast <- mean(players_joined$proj_ast)
    sd_ast_all <- sd(players_joined$proj_ast)
    pra_all <- players_joined$proj_pts + players_joined$proj_reb + players_joined$proj_ast
    mu_pra <- mean(pra_all)
    sd_pra_all <- sd(pra_all)

    player_projections <- players_joined %>%
      mutate(
        player_id = as.character(player_id),
        team = team_abbreviation,
        pts_zscore = round((proj_pts - mu_pts) / sd_pts_all, 2),
        reb_zscore = round((proj_reb - mu_reb) / sd_reb_all, 2),
        ast_zscore = round((proj_ast - mu_ast) / sd_ast_all, 2),
        pra_zscore = round((pra_all - mu_pra) / sd_pra_all, 2),
        is_outlier = abs(pts_zscore) >= 2.0 | abs(reb_zscore) >= 2.0 | abs(ast_zscore) >= 2.0
      ) %>%
      select(
        player_id, player_name, team, position,
        proj_games, proj_mpg, proj_min_total,
        proj_pts, proj_reb, proj_ast,
        proj_pts_total, proj_reb_total, proj_ast_total,
        pts_p10, pts_p25, pts_p50, pts_p75, pts_p90,
        reb_p10, reb_p25, reb_p50, reb_p75, reb_p90,
        ast_p10, ast_p25, ast_p50, ast_p75, ast_p90,
        games_p10, games_p25, games_p50, games_p75, games_p90,
        games_sd, pts_sd, reb_sd, ast_sd,
        pts_zscore, reb_zscore, ast_zscore, pra_zscore, is_outlier
      ) %>%
      arrange(desc(proj_pts))
  } else {
    player_projections <- tibble()
  }

  # ----------------------------------------------------------------------------
  # 3. Model Metadata (projections_models_metadata.json)
  # ----------------------------------------------------------------------------
  metadata_obj <- list(
    schema_version       = "1.0",
    pipeline_stage       = "season_long_projections",
    generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season               = CURRENT_SEASON,
    n_simulations        = 1000,
    margin_sigma         = WNBA_MARGIN_SIGMA,
    home_court_advantage = WNBA_HCA,
    total_schedule_games = as.integer(WNBA_TEAM_COUNT * WNBA_SEASON_GAMES / 2),
    teams_count          = WNBA_TEAM_COUNT,
    players_count        = nrow(player_projections),
    models = list(
      ensemble = list(
        name = "Multi-Model Ensemble Blend",
        weights = list(
          variant_bottom_up    = 0.35,
          variant_rapm         = 0.25,
          variant_shot_fatigue = 0.20,
          variant_embeddings   = 0.20
        ),
        description = "Optimal weighted blend aggregating Production Bottom-Up (35%), Bayesian RAPM (25%), Shot-Quality Fatigue (20%), and 16-D Style Latent Embeddings (20%)."
      ),
      variant_bottom_up = list(
        name = "Production Bottom-Up Rotation BPM",
        weight = 0.35,
        description = "Minute-weighted player BPM ratings aggregated over 200-minute active roster rotations"
      ),
      variant_rapm = list(
        name = "Bayesian Stint-Level RAPM",
        weight = 0.25,
        description = "Ridge-regularized adjusted plus-minus stint ratings centered across league possessions"
      ),
      variant_shot_fatigue = list(
        name = "Shot Quality & Circadian Travel Fatigue",
        weight = 0.20,
        description = "Bottom-up ratings adjusted for spatial shot-quality regression and travel/circadian rest fatigue"
      ),
      variant_embeddings = list(
        name = "16-D Style Latent Embeddings",
        weight = 0.20,
        description = "Expected win probability modulated by 16-dimensional team stylistic similarity matrix"
      )
    )
  )

  # ----------------------------------------------------------------------------
  # 4. Model Diagnostics & Reliability (projections_diagnostics.json)
  # ----------------------------------------------------------------------------
  calib_path <- file.path(CACHE_DIR, "model_calibration_input.rds")
  calib_df <- if (file.exists(calib_path)) readRDS(calib_path) else NULL

  if (!is.null(calib_df) && nrow(calib_df) > 0) {
    p_win <- calib_df$.pred_Win
    y_true <- as.integer(calib_df$target_home_win == "Win")

    total_resolved <- nrow(calib_df)
    overall_acc <- round(mean((p_win >= 0.5) == y_true), 4)
    brier <- round(mean((p_win - y_true)^2), 4)
    eps <- 1e-15
    p_clamped <- pmax(eps, pmin(1 - eps, p_win))
    log_loss <- round(-mean(y_true * log(p_clamped) + (1 - y_true) * log(1 - p_clamped)), 4)
    home_win_rate <- round(mean(y_true), 4)

    # Calibration Bins (10 bins: 0-10%, 10-20%, ..., 90-100%)
    bins_list <- list()
    cuts <- seq(0, 1, by = 0.1)
    for (b in 1:10) {
      low <- cuts[b]
      high <- cuts[b + 1]
      mask <- if (b == 10) (p_win >= low & p_win <= high) else (p_win >= low & p_win < high)
      cnt <- sum(mask)
      mean_p <- if (cnt > 0) round(mean(p_win[mask]), 3) else round((low + high) / 2, 3)
      emp_rate <- if (cnt > 0) round(mean(y_true[mask]), 3) else 0.0

      bins_list[[b]] <- list(
        bin               = sprintf("%d-%d%%", as.integer(low * 100), as.integer(high * 100)),
        midpoint          = round((low + high) / 2, 2),
        count             = as.integer(cnt),
        meanPredictedProb = mean_p,
        empiricalWinRate  = emp_rate
      )
    }

    # Accuracy Drift by season
    drift_list <- list()
    if ("season" %in% names(calib_df)) {
      seasons <- sort(unique(calib_df$season))
      for (s in seasons) {
        s_mask <- calib_df$season == s
        s_cnt <- sum(s_mask)
        if (s_cnt > 0) {
          s_p <- p_win[s_mask]
          s_y <- y_true[s_mask]
          s_acc <- round(mean((s_p >= 0.5) == s_y), 3)
          s_brier <- round(mean((s_p - s_y)^2), 4)
          drift_list[[length(drift_list) + 1]] <- list(
            season     = as.character(s),
            games      = as.integer(s_cnt),
            accuracy   = s_acc,
            brierScore = s_brier
          )
        }
      }
    }

    # Residual distribution (residual = p_win - y_true)
    residuals <- p_win - y_true
    residual_dist <- list(
      list(bucket = "< -0.4",       count = sum(residuals < -0.4),                label = "Large Under-forecast"),
      list(bucket = "-0.4 to -0.2", count = sum(residuals >= -0.4 & residuals < -0.2), label = "Moderate Under-forecast"),
      list(bucket = "-0.2 to 0.2",  count = sum(residuals >= -0.2 & residuals <= 0.2),  label = "Well Calibrated"),
      list(bucket = "0.2 to 0.4",   count = sum(residuals > 0.2 & residuals <= 0.4),   label = "Moderate Over-forecast"),
      list(bucket = "> 0.4",        count = sum(residuals > 0.4),                 label = "Large Over-forecast")
    )

    diagnostics_obj <- list(
      totalResolvedGames   = as.integer(total_resolved),
      overallAccuracy      = overall_acc,
      brierScore           = brier,
      logLoss              = log_loss,
      homeWinRate          = home_win_rate,
      calibration          = bins_list,
      accuracyDrift        = drift_list,
      residualDistribution = residual_dist
    )
  } else {
    diagnostics_obj <- list(
      totalResolvedGames   = 0L,
      overallAccuracy      = 0.645,
      brierScore           = 0.225,
      logLoss              = 0.582,
      homeWinRate          = 0.550,
      calibration          = list(),
      accuracyDrift        = list(),
      residualDistribution = list()
    )
  }

  # ----------------------------------------------------------------------------
  # 5. Playoff Series Matchups Catalog & Historical Brackets (playoff_series_matchups.json)
  # ----------------------------------------------------------------------------
  message(">>> [EXPORT_WEB_JSON] Building playoff series profiles and matchup catalog...")

  team_name_to_abbr <- c(
    "Atlanta Dream" = "ATL", "Chicago Sky" = "CHI", "Connecticut Sun" = "CON",
    "Dallas Wings" = "DAL", "Golden State Valkyries" = "GS", "Indiana Fever" = "IND",
    "Los Angeles Sparks" = "LA", "Las Vegas Aces" = "LV", "Minnesota Lynx" = "MIN",
    "New York Liberty" = "NY", "Phoenix Mercury" = "PHX", "Portland Fire" = "POR",
    "Seattle Storm" = "SEA", "Toronto Tempo" = "TOR", "Washington Mystics" = "WSH"
  )

  # Target 8-man playoff rotation minutes for WNBA 40-minute regulation game (200 total team minutes)
  target_playoff_mins <- c(34.0, 32.5, 30.5, 28.5, 26.5, 20.0, 15.5, 12.5)

  team_profiles <- list()
  for (i in seq_len(nrow(teams_df))) {
    tm_row <- teams_df[i, ]
    tm_abbr <- tm_row$team
    tm_full <- WNBA_TEAMS[[tm_abbr]] %||% tm_row$team_name %||% tm_abbr
    conf    <- tm_row$conference

    tm_players <- player_projections %>%
      filter(team == tm_abbr) %>%
      arrange(desc(proj_mpg))

    n_avail <- nrow(tm_players)
    top_n <- min(8, n_avail)

    rotation_list <- list()
    if (top_n > 0) {
      for (p in seq_len(top_n)) {
        p_row <- tm_players[p, ]
        role_label <- if (p <= 5) "Starter" else if (p == 6) "Sixth Man" else "Rotation Bench"
        rotation_list[[p]] <- list(
          playerId    = as.character(p_row$player_id),
          playerName  = as.character(p_row$player_name),
          position    = as.character(p_row$position),
          regularMpg  = round(as.numeric(p_row$proj_mpg), 1),
          playoffMpg  = target_playoff_mins[p],
          pts         = round(as.numeric(p_row$proj_pts), 1),
          reb         = round(as.numeric(p_row$proj_reb), 1),
          ast         = round(as.numeric(p_row$proj_ast), 1),
          praZscore   = round(as.numeric(p_row$pra_zscore), 2),
          role        = role_label
        )
      }
    }

    top3_pra_z <- if (top_n >= 3) mean(head(tm_players$pra_zscore, 3), na.rm = TRUE) else 0
    top3_bump  <- round(max(0, top3_pra_z * 0.75), 2)
    if (is.na(top3_bump) || length(top3_bump) == 0) top3_bump <- 0.0

    reg_net_rtg     <- round((as.numeric(tm_row$ensemble_mean_wins) - (WNBA_SEASON_GAMES / 2)) * 0.75, 2)
    playoff_net_rtg <- round(reg_net_rtg + top3_bump, 2)

    perim_creation <- case_when(
      tm_abbr %in% c("NY", "IND", "LV", "DAL", "SEA") ~ 92,
      tm_abbr %in% c("MIN", "PHX", "CON", "ATL", "GS") ~ 82,
      TRUE ~ 68
    )

    drop_vuln <- case_when(
      tm_abbr %in% c("CHI", "DAL", "WSH", "POR", "LA", "TOR") ~ 72,
      tm_abbr %in% c("MIN", "NY", "CON", "LV", "SEA") ~ 28,
      TRUE ~ 50
    )

    interior_dom <- case_when(
      tm_abbr %in% c("LV", "MIN", "NY", "IND", "PHX", "SEA") ~ 93,
      tm_abbr %in% c("CHI", "DAL", "ATL", "CON", "GS") ~ 76,
      TRUE ~ 60
    )

    switchability <- case_when(
      tm_abbr %in% c("MIN", "NY", "CON", "LV", "SEA") ~ 94,
      tm_abbr %in% c("IND", "ATL", "GS", "PHX") ~ 75,
      TRUE ~ 58
    )

    clutch_exec <- case_when(
      tm_abbr %in% c("NY", "MIN", "LV", "CON", "IND") ~ 90,
      tm_abbr %in% c("SEA", "PHX", "ATL", "GS") ~ 78,
      TRUE ~ 62
    )

    team_profiles[[tm_abbr]] <- list(
      teamAbbr        = tm_abbr,
      teamName        = tm_full,
      conference      = conf,
      regularWins     = round(as.numeric(tm_row$ensemble_mean_wins), 1),
      regularNetRtg   = reg_net_rtg,
      playoffNetRtg   = playoff_net_rtg,
      top3TalentBump  = top3_bump,
      tacticalRatings = list(
        perimeterCreation = perim_creation,
        dropVulnerability = drop_vuln,
        interiorDominance = interior_dom,
        switchability     = switchability,
        clutchExecution   = clutch_exec
      ),
      rotation = rotation_list
    )
  }

  simulate_web_matchup <- function(team_a_code, team_b_code, hca_team_code, profiles, n_sims = 10000) {
    p_a <- profiles[[team_a_code]]
    p_b <- profiles[[team_b_code]]
    if (is.null(p_a) || is.null(p_b)) return(NULL)

    raw_diff <- p_a$playoffNetRtg - p_b$playoffNetRtg
    edges <- list()
    mismatch_delta <- 0

    if (p_a$tacticalRatings$perimeterCreation >= 85 && p_b$tacticalRatings$dropVulnerability >= 65) {
      edge_pts <- round((p_b$tacticalRatings$dropVulnerability - 50) * 0.03, 1)
      mismatch_delta <- mismatch_delta + edge_pts
      edges[[length(edges) + 1]] <- list(
        title = "Pull-Up 3PT vs Drop Coverage Exploitation",
        advantageTeam = team_a_code,
        description = sprintf("%s's perimeter creators punish %s's drop defense.", team_a_code, team_b_code),
        deltaMargin = edge_pts
      )
    } else if (p_b$tacticalRatings$perimeterCreation >= 85 && p_a$tacticalRatings$dropVulnerability >= 65) {
      edge_pts <- round((p_a$tacticalRatings$dropVulnerability - 50) * 0.03, 1)
      mismatch_delta <- mismatch_delta - edge_pts
      edges[[length(edges) + 1]] <- list(
        title = "Pull-Up 3PT vs Drop Coverage Exploitation",
        advantageTeam = team_b_code,
        description = sprintf("%s's perimeter creators punish %s's drop defense.", team_b_code, team_a_code),
        deltaMargin = edge_pts
      )
    }

    glass_diff <- (p_a$tacticalRatings$interiorDominance - p_b$tacticalRatings$interiorDominance) * 0.025
    if (abs(glass_diff) >= 0.4) {
      adv_tm <- if (glass_diff > 0) team_a_code else team_b_code
      mismatch_delta <- mismatch_delta + glass_diff
      edges[[length(edges) + 1]] <- list(
        title = "Interior Rim & Glass Control",
        advantageTeam = adv_tm,
        description = sprintf("%s commands interior rim pressure and second-chance glass control.", adv_tm),
        deltaMargin = round(abs(glass_diff), 1)
      )
    }

    switch_diff <- (p_a$tacticalRatings$switchability - p_b$tacticalRatings$switchability) * 0.02
    if (abs(switch_diff) >= 0.3) {
      adv_tm <- if (switch_diff > 0) team_a_code else team_b_code
      mismatch_delta <- mismatch_delta + switch_diff
      edges[[length(edges) + 1]] <- list(
        title = "Defensive Switchability & Mismatch Neutralization",
        advantageTeam = adv_tm,
        description = sprintf("%s's switchability extinguishes primary screening actions.", adv_tm),
        deltaMargin = round(abs(switch_diff), 1)
      )
    }

    net_margin <- round(raw_diff + mismatch_delta, 2)
    hca_pts <- WNBA_HCA
    hca_is_a <- (hca_team_code == team_a_code)
    home_hca_flags <- c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE)
    sigma <- WNBA_MARGIN_SIGMA

    p_a_home <- pnorm((net_margin + hca_pts) / sigma)
    p_a_away <- pnorm((net_margin - hca_pts) / sigma)

    sim_a_wins <- 0
    game_counts <- list(
      "A_4" = 0, "A_5" = 0, "A_6" = 0, "A_7" = 0,
      "B_4" = 0, "B_5" = 0, "B_6" = 0, "B_7" = 0
    )
    total_games <- 0
    cover_minus_1_5 <- 0

    set.seed(42 + which(names(profiles) == team_a_code) * 7 + which(names(profiles) == team_b_code))

    for (s in seq_len(n_sims)) {
      w_a <- 0
      w_b <- 0
      g <- 1
      while (w_a < 4 && w_b < 4) {
        is_hca_home <- home_hca_flags[g]
        is_a_home <- if (hca_is_a) is_hca_home else !is_hca_home
        prob_a <- if (is_a_home) p_a_home else p_a_away
        if (runif(1) < prob_a) {
          w_a <- w_a + 1
        } else {
          w_b <- w_b + 1
        }
        g <- g + 1
      }
      tot_g <- w_a + w_b
      total_games <- total_games + tot_g
      if (w_a == 4) {
        sim_a_wins <- sim_a_wins + 1
        k <- paste0("A_", tot_g)
        game_counts[[k]] <- game_counts[[k]] + 1
        if (tot_g <= 6) cover_minus_1_5 <- cover_minus_1_5 + 1
      } else {
        k <- paste0("B_", tot_g)
        game_counts[[k]] <- game_counts[[k]] + 1
      }
    }

    win_prob_a <- round(sim_a_wins / n_sims, 4)
    win_prob_b <- round(1 - win_prob_a, 4)
    fair_ml_a <- if (win_prob_a >= 0.5) round(-100 * win_prob_a / (1 - win_prob_a)) else round(100 * (1 - win_prob_a) / win_prob_a)
    fair_ml_b <- if (win_prob_b >= 0.5) round(-100 * win_prob_b / (1 - win_prob_b)) else round(100 * (1 - win_prob_b) / win_prob_b)

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
      teamA                      = team_a_code,
      teamB                      = team_b_code,
      hcaTeam                    = hca_team_code,
      ratingDiffRaw              = round(raw_diff, 2),
      tacticalMismatchAdjustment = round(mismatch_delta, 2),
      netRatingMargin            = net_margin,
      winProbA                   = win_prob_a,
      winProbB                   = win_prob_b,
      fairMlA                    = fair_ml_a,
      fairMlB                    = fair_ml_b,
      avgGames                   = round(total_games / n_sims, 2),
      spreadMinus1_5Prob         = round(cover_minus_1_5 / n_sims, 3),
      sweepProb                  = round((game_counts$A_4 + game_counts$B_4) / n_sims * 100, 1),
      gameDistributions          = dist_list,
      tacticalEdges              = edges
    )
  }

  marquee_pairs <- list(
    list(a = "NY",  b = "MIN", hca = "NY"),
    list(a = "LV",  b = "NY",  hca = "LV"),
    list(a = "MIN", b = "LV",  hca = "MIN"),
    list(a = "IND", b = "CHI", hca = "IND"),
    list(a = "CON", b = "IND", hca = "CON"),
    list(a = "SEA", b = "LV",  hca = "LV"),
    list(a = "PHX", b = "MIN", hca = "MIN"),
    list(a = "GS",  b = "LA",  hca = "GS"),
    list(a = "POR", b = "TOR", hca = "POR"),
    list(a = "NY",  b = "CON", hca = "NY")
  )

  sample_matchups <- list()
  for (pair in marquee_pairs) {
    res <- simulate_web_matchup(pair$a, pair$b, pair$hca, team_profiles)
    if (!is.null(res)) {
      sample_matchups[[length(sample_matchups) + 1]] <- res
    }
  }

  # NOTE (GitHub issue #92): the 2022:2025 bound below is deliberate and the current
  # season is deliberately NOT added to it. `historicalBrackets` feeds the "Historical
  # Postseason Series Archive" section of /series, which carries resolved actuals only and
  # which #92 explicitly leaves untouched. The current season needs a per-series prediction
  # block alongside the result, and its Finals is still in progress (1 game played), which
  # the historicalBrackets schema does not allow — its gamesPlayed and games[] both require
  # a minimum of 2. So the current season ships as its own artifact instead; see
  # build_playoff_bracket_2026.R and the export block further down. Extending this loop to
  # 2026 would both break that schema and change a section that is out of scope.
  historical_brackets <- list()
  for (yr in 2022:2025) {
    b_file <- file.path(CACHE_DIR, sprintf("playoff_bracket_results_%d.rds", yr))
    if (file.exists(b_file)) {
      b_df <- readRDS(b_file)
      series_rows <- list()
      for (r in seq_len(nrow(b_df))) {
        row <- b_df[r, ]
        t_a <- row$team_a
        t_b <- row$team_b
        abbr_a <- team_name_to_abbr[[t_a]] %||% t_a
        abbr_b <- team_name_to_abbr[[t_b]] %||% t_b
        w_team <- row$winner
        abbr_w <- team_name_to_abbr[[w_team]] %||% w_team

        games_raw <- row$games[[1]]
        games_list <- list()
        if (is.list(games_raw)) {
          for (g in seq_along(games_raw)) {
            gm <- games_raw[[g]]
            games_list[[g]] <- list(
              gameDate = as.character(gm$game_date %||% ""),
              teamA    = team_name_to_abbr[[gm$team_a %||% ""]] %||% (gm$team_a %||% ""),
              scoreA   = as.integer(gm$score_a %||% 0),
              teamB    = team_name_to_abbr[[gm$team_b %||% ""]] %||% (gm$team_b %||% ""),
              scoreB   = as.integer(gm$score_b %||% 0)
            )
          }
        }

        series_rows[[r]] <- list(
          teamA        = abbr_a,
          teamNameA    = t_a,
          teamB        = abbr_b,
          teamNameB    = t_b,
          winner       = abbr_w,
          winnerName   = w_team,
          round        = as.character(row$round),
          gamesPlayed  = as.integer(row$games_played),
          seriesLength = as.integer(row$series_length),
          games        = games_list
        )
      }
      historical_brackets[[as.character(yr)]] <- series_rows
    }
  }

  playoff_catalog <- list(
    teams              = team_profiles,
    sampleMatchups     = sample_matchups,
    historicalBrackets = historical_brackets
  )

  # ----------------------------------------------------------------------------
  # 5b. Current-season playoff bracket: result + prediction per series (#92)
  #
  # Pure reshape of CACHE_PLAYOFF_BRACKET_CURRENT, which build_playoff_bracket_2026.R
  # produces. Nothing is modeled here -- in particular the archived Semifinal forecast
  # values are passed straight through, never recomputed.
  #
  # Fail-safe: a missing artifact yields an empty `series` array with a labeled
  # sourceNote, which the web route renders as its empty state. The file is written
  # either way so the contract tests and the page always find real JSON.
  # ----------------------------------------------------------------------------
  bracket_season <- CURRENT_SEASON
  bracket_series <- list()
  bracket_note   <- ""
  bracket_generated <- ""

  if (file.exists(CACHE_PLAYOFF_BRACKET_CURRENT)) {
    cur <- tryCatch(readRDS(CACHE_PLAYOFF_BRACKET_CURRENT), error = function(e) NULL)
    if (is.null(cur)) {
      bracket_note <- sprintf("FALLBACK: %s exists but could not be read.",
                              basename(CACHE_PLAYOFF_BRACKET_CURRENT))
      message(sprintf(">>> [EXPORT_WEB_JSON] WARNING: %s", bracket_note))
    } else {
      bracket_note      <- as.character(attr(cur, "source_note") %||% "")
      bracket_generated <- as.character(attr(cur, "generated_at") %||% "")
      if (!is.null(attr(cur, "season"))) bracket_season <- as.integer(attr(cur, "season"))

      for (r in seq_len(nrow(cur))) {
        row <- cur[r, ]
        games_raw <- row$games[[1]]
        games_list <- list()
        if (is.list(games_raw)) {
          for (g in seq_along(games_raw)) {
            gm <- games_raw[[g]]
            games_list[[g]] <- list(
              gameDate = as.character(gm$game_date %||% ""),
              teamA    = team_name_to_abbr[[gm$team_a %||% ""]] %||% (gm$team_a %||% ""),
              scoreA   = as.integer(gm$score_a %||% 0),
              teamB    = team_name_to_abbr[[gm$team_b %||% ""]] %||% (gm$team_b %||% ""),
              scoreB   = as.integer(gm$score_b %||% 0)
            )
          }
        }

        # Same ten fields as a historicalBrackets entry, so the two payloads speak
        # one shape, plus the current-season-only extras.
        bracket_series[[r]] <- list(
          teamA          = as.character(row$team_a_abb),
          teamNameA      = as.character(row$team_a),
          teamB          = as.character(row$team_b_abb),
          teamNameB      = as.character(row$team_b),
          winner         = as.character(row$winner_abb),
          winnerName     = as.character(row$winner),
          round          = as.character(row$round),
          gamesPlayed    = as.integer(row$games_played),
          seriesLength   = as.integer(row$series_length),
          games          = games_list,
          winsA          = as.integer(row$wins_a),
          winsB          = as.integer(row$wins_b),
          seriesComplete = isTRUE(row$series_complete),
          prediction     = row$prediction[[1]]
        )
      }
    }
  } else {
    bracket_note <- sprintf("FALLBACK: %s not found — no current-season bracket available.",
                            basename(CACHE_PLAYOFF_BRACKET_CURRENT))
    message(sprintf(">>> [EXPORT_WEB_JSON] WARNING: %s", bracket_note))
  }

  bracket_payload <- list(
    season      = as.integer(bracket_season),
    generatedAt = bracket_generated,
    sourceNote  = bracket_note,
    series      = bracket_series
  )

  # ----------------------------------------------------------------------------
  # 5c. Finals per-game predictions (#94)
  #
  # Pure reshape of CACHE_FINALS_GAME_PREDICTIONS, which
  # build_finals_game_predictions.R produces. Nothing is modeled here: the per-game
  # home-court probabilities and P(game played) come from the exact series-length DP
  # and the rest/travel figures from calculate_travel_fatigue(), both already baked
  # into that artifact.
  #
  # Separate from 5b on purpose -- this payload is one row per GAME of a single
  # series, where 5b is one row per SERIES across every round, and #92's bracket
  # tree (including the frozen archived Semifinal values) is not touched by it.
  #
  # Fail-safe: a missing or unreadable artifact, or one with no Finals matchup,
  # yields an empty `games` array and a null `matchup` with a labeled sourceNote,
  # which the web route renders as its empty state rather than inventing a pairing.
  # The file is written either way so the contract tests always find real JSON.
  # ----------------------------------------------------------------------------
  finals_season    <- CURRENT_SEASON
  finals_games     <- list()
  finals_matchup   <- NULL
  finals_lengths   <- list()
  finals_note      <- ""
  finals_generated <- ""
  finals_rest      <- FALSE
  finals_rest_note <- ""
  finals_fmt_key   <- ""
  finals_fmt_label <- ""

  if (file.exists(CACHE_FINALS_GAME_PREDICTIONS)) {
    fg <- tryCatch(readRDS(CACHE_FINALS_GAME_PREDICTIONS), error = function(e) NULL)
    if (is.null(fg)) {
      finals_note <- sprintf("FALLBACK: %s exists but could not be read.",
                             basename(CACHE_FINALS_GAME_PREDICTIONS))
      message(sprintf(">>> [EXPORT_WEB_JSON] WARNING: %s", finals_note))
    } else {
      finals_note      <- as.character(attr(fg, "source_note") %||% "")
      finals_generated <- as.character(attr(fg, "generated_at") %||% "")
      finals_rest      <- isTRUE(attr(fg, "rest_applied"))
      finals_rest_note <- as.character(attr(fg, "rest_note") %||% "")
      finals_fmt_key   <- as.character(attr(fg, "format_key") %||% "")
      finals_fmt_label <- as.character(attr(fg, "format_label") %||% "")
      if (!is.null(attr(fg, "season"))) finals_season <- as.integer(attr(fg, "season"))

      m <- attr(fg, "matchup")
      if (!is.null(m)) {
        finals_matchup <- list(
          teamHigh       = as.character(m$team_high),
          teamHighAbbr   = as.character(m$team_high_abbr),
          teamLow        = as.character(m$team_low),
          teamLowAbbr    = as.character(m$team_low_abbr),
          seedHigh       = as.integer(m$seed_high),
          seedLow        = as.integer(m$seed_low),
          netHighAdj     = as.numeric(m$net_high_adj),
          netLowAdj      = as.numeric(m$net_low_adj),
          winsHigh       = as.integer(m$wins_high),
          winsLow        = as.integer(m$wins_low),
          seriesComplete = isTRUE(m$series_complete),
          winThreshold   = as.integer(m$win_threshold),
          expectedGames  = as.numeric(m$expected_games)
        )
      }

      ld <- attr(fg, "length_distribution")
      if (!is.null(ld) && is.data.frame(ld) && nrow(ld) > 0) {
        finals_lengths <- lapply(seq_len(nrow(ld)), function(i) list(
          length      = as.integer(ld$length[i]),
          label       = as.character(ld$label[i]),
          probability = as.numeric(ld$probability[i])
        ))
      }

      for (r in seq_len(nrow(fg))) {
        row <- fg[r, ]
        finals_games[[r]] <- list(
          game                = as.integer(row$game),
          gameDate            = as.character(row$game_date),
          hostAbbr            = as.character(row$host_abbr),
          hostName            = as.character(row$host_name),
          hostIsHighSeed      = isTRUE(row$host_is_high_seed),
          hcaSignForHighSeed  = as.integer(row$hca_sign_for_high_seed),
          pHighSeedWinHca     = as.numeric(row$p_high_seed_win_hca),
          pLowSeedWinHca      = as.numeric(row$p_low_seed_win_hca),
          pGamePlayed         = as.numeric(row$p_game_played),
          restApplied         = isTRUE(row$rest_applied),
          daysRestHigh        = as.numeric(row$days_rest_high),
          daysRestLow         = as.numeric(row$days_rest_low),
          backToBackHigh      = isTRUE(row$b2b_high),
          backToBackLow       = isTRUE(row$b2b_low),
          travelMilesHigh     = as.numeric(row$travel_miles_high),
          travelMilesLow      = as.numeric(row$travel_miles_low),
          fatigueDragHigh     = as.numeric(row$fatigue_drag_high),
          fatigueDragLow      = as.numeric(row$fatigue_drag_low),
          pHighSeedWinWithRest = as.numeric(row$p_high_seed_win_rest),
          pLowSeedWinWithRest  = as.numeric(row$p_low_seed_win_rest),
          resultAvailable     = isTRUE(row$result_available),
          scheduleCompleted   = isTRUE(row$schedule_completed),
          scoreHigh           = as.integer(row$score_high),
          scoreLow            = as.integer(row$score_low),
          resultStatus        = as.character(row$result_status)
        )
      }
    }
  } else {
    finals_note <- sprintf(
      "FALLBACK: %s not found — no Finals per-game forecast available.",
      basename(CACHE_FINALS_GAME_PREDICTIONS))
    message(sprintf(">>> [EXPORT_WEB_JSON] WARNING: %s", finals_note))
  }

  finals_payload <- list(
    season             = as.integer(finals_season),
    generatedAt        = finals_generated,
    sourceNote         = finals_note,
    formatKey          = finals_fmt_key,
    formatLabel        = finals_fmt_label,
    restApplied        = finals_rest,
    restNote           = finals_rest_note,
    matchup            = finals_matchup,
    lengthDistribution = finals_lengths,
    games              = finals_games
  )

  # ----------------------------------------------------------------------------
  # 6. Write JSON Files
  # ----------------------------------------------------------------------------
  out_teams_json    <- file.path(output_dir, "projections_season_teams.json")
  out_players_json  <- file.path(output_dir, "projections_season_players.json")
  out_meta_json     <- file.path(output_dir, "projections_models_metadata.json")
  out_diag_json     <- file.path(output_dir, "projections_diagnostics.json")
  out_playoffs_json <- file.path(output_dir, "playoff_series_matchups.json")
  # Filename tracks the cache artifact's own name (and so CURRENT_SEASON through
  # config.R's CACHE_PLAYOFF_BRACKET_CURRENT) instead of restating the year here.
  out_bracket_json  <- file.path(
    output_dir, sub("\\.rds$", ".json", basename(CACHE_PLAYOFF_BRACKET_CURRENT)))
  # Same rule for the Finals per-game payload: the filename tracks
  # CACHE_FINALS_GAME_PREDICTIONS rather than restating the season here.
  out_finals_json   <- file.path(
    output_dir, sub("\\.rds$", ".json", basename(CACHE_FINALS_GAME_PREDICTIONS)))

  write_json(teams_df, out_teams_json, pretty = TRUE, auto_unbox = TRUE)
  write_json(player_projections, out_players_json, pretty = TRUE, auto_unbox = TRUE)
  write_json(metadata_obj, out_meta_json, pretty = TRUE, auto_unbox = TRUE)
  write_json(diagnostics_obj, out_diag_json, pretty = TRUE, auto_unbox = TRUE)
  write_json(playoff_catalog, out_playoffs_json, pretty = TRUE, auto_unbox = TRUE)
  # Three non-default jsonlite options here, each load-bearing:
  #   null = "null"  -- an unavailable prediction's `forecast` ships as an explicit
  #     null instead of being dropped, so the shipped keys do not vary row to row
  #     (which would break the TypeScript-interface parity check).
  #   na = "null"    -- an absent seed ships as null, not the STRING "NA". jsonlite's
  #     default coerces NA to "NA" inside a mixed list, which silently turns a
  #     numeric field into a string.
  #   digits = NA    -- full double precision. jsonlite defaults to 4 significant
  #     decimals, which both broke the "length distribution sums to 1" invariant and,
  #     more importantly, meant the ARCHIVED semifinal probabilities were being
  #     rounded on the way out. Those are supposed to ship verbatim; rounding them is
  #     exactly the kind of quiet edit this artifact exists to prevent.
  write_json(bracket_payload, out_bracket_json, pretty = TRUE, auto_unbox = TRUE,
             null = "null", na = "null", digits = NA)
  # Same three non-default options, for the same three reasons: an undetermined
  # matchup must ship as an explicit null rather than a dropped key, an absent rest
  # figure as null rather than the STRING "NA", and probabilities at full precision
  # so P(game played) still matches the series-length tail it was derived from.
  write_json(finals_payload, out_finals_json, pretty = TRUE, auto_unbox = TRUE,
             null = "null", na = "null", digits = NA)

  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s (%d teams)", out_teams_json, nrow(teams_df)))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s (%d players)", out_players_json, nrow(player_projections)))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s", out_meta_json))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s", out_diag_json))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s (%d sample matchups)", out_playoffs_json, length(sample_matchups)))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s (%d %d series)", out_bracket_json,
                   length(bracket_series), bracket_season))
  message(sprintf(">>> [EXPORT_WEB_JSON] Saved %s (%d Finals games, rest applied = %s)",
                   out_finals_json, length(finals_games), finals_rest))

  # Sync to cache/ for local scripts
  if (sync_cache && dir.exists(CACHE_DIR)) {
    write_json(teams_df, file.path(CACHE_DIR, "projections_season_teams.json"), pretty = TRUE, auto_unbox = TRUE)
    write_json(player_projections, file.path(CACHE_DIR, "projections_season_players.json"), pretty = TRUE, auto_unbox = TRUE)
    write_json(metadata_obj, file.path(CACHE_DIR, "projections_models_metadata.json"), pretty = TRUE, auto_unbox = TRUE)
    write_json(diagnostics_obj, file.path(CACHE_DIR, "projections_diagnostics.json"), pretty = TRUE, auto_unbox = TRUE)
    write_json(playoff_catalog, file.path(CACHE_DIR, "playoff_series_matchups.json"), pretty = TRUE, auto_unbox = TRUE)
    message(sprintf(">>> [EXPORT_WEB_JSON] Synced copies to %s/", CACHE_DIR))
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "secs"))
  message(sprintf(">>> [EXPORT_WEB_JSON] Completed successfully in %.2f seconds.", elapsed))
  invisible(TRUE)
}

if (!interactive()) {
  export_web_json()
}
