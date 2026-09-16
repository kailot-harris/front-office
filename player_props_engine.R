# ==============================================================================
# player_props_engine.R (WNBA port)
# Phase 4 (T4) — Zero-Inflated Negative Binomial (ZINB) & PRA Alpha Engine
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/player_props_engine.R
#
# ZINB pricing math (dzinb/pzinb/pzinb_over/price_prop_zinb) is ported BYTE-FOR-BYTE
# unchanged from the NBA original — it is sport-agnostic count-model math with no
# NBA-specific constants.
#
# *** UPDATE (Task P3-2.3, 2026-09-15): Empirical Parameterization ***
# The dispersion (theta) and zero-inflation (pi_0) constants were derived from
# the real WNBA rotation distribution in `cache/player_box_scores_cache.rds`.
# Logic:
#   - pi_0 = empirical proportion of zero-observations for the stat.
#   - theta = mu^2 / (Var(X) - mu), derived from rotation-player distributions.
#
# REAL BUG FIX (per REPO_MAP.md §6/§9 and task_assignments.md's T4 brief — this is
# the one thing this file is required to actually fix rather than reproduce):
# the NBA original's `generate_active_props_table()` reads `cache/active_rosters.rds`,
# but the NBA `sync_rosters.R` writes `cache/active_rosters_cache.rds` — those two
# filenames never match, so the NBA props engine ALWAYS silently falls back to its
# fabricated roster, even though a real roster cache sits right next to it on disk.
# This WNBA port reads the EXACT filename T1's sync_rosters.R actually wrote:
# `cache/active_rosters_cache.rds` (209 rows, verified in task_assignments.md's T1
# Handoff Notes) — the filename mismatch bug is FIXED here, not reproduced.
#
# SECOND REAL FIX beyond the filename (required for the fix above to be more than
# cosmetic): T1's `active_rosters_cache.rds` schema is `team_abbreviation, team_name,
# team_id, player_id, player_name, position, jersey` — it has NO per-player stat-mean
# columns (pts_mu/reb_mu/etc.), unlike what the NBA original's `generate_active_props_table()`
# implicitly assumed a "real" roster cache would already contain. Simply fixing the
# filename would have loaded a real roster with no usable stat projections and
# crashed downstream (`p$pts_mu` would be NULL for every row). Instead, real
# per-player stat means are computed here from T1's real
# `cache/player_box_scores_cache.rds` (44,675 rows, 2019-2026), joined to the roster
# on `player_id == athlete_id` (both are real ESPN athlete IDs per T1's Handoff
# Notes), averaged over CURRENT_SEASON's real games. This is what actually lets the
# props engine price real WNBA players off real 2026-season per-game production
# instead of always falling back to synthetic data.
#
# Roster fallback per-team player count shrunk from the NBA original's `1:8`
# (hardcoded literal) to `config.R`'s WNBA_ROTATION_SIZE constant (8, chosen by T2 to
# match its own rotation-depth choice in roster_bottom_up_engine.R — see
# task_assignments.md T2 Handoff Notes) referenced by name, not re-hardcoded, and the
# fallback team list is WNBA's real 15 franchises (WNBA_TEAMS) instead of 30 NBA
# teams. NOTE: 8 happens to numerically match the NBA original's hardcoded 8 — the
# "shrink" here is about correctness (WNBA_ROTATION_SIZE is a named, greppable,
# empirically-chosen WNBA constant) and about using the real 15-team list, not about
# the raw number changing.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

source("config.R")

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [PROPS] Initializing WNBA Zero-Inflated Negative Binomial (ZINB) Props Engine...")

# Category Dispersion Parameters (Theta) — derived empirically from WNBA rotation data (2026-09-15).
# Low theta = high overdispersion; Large theta -> Poisson limit
PROP_DISPERSION <- list(
  "PTS"  = 2.4,
  "REB"  = 2.8,
  "AST"  = 2.1,
  "FG3M" = 1.4,
  "STL"  = 3.9,
  "BLK"  = 1.0
)

# Zero-inflation structural propensity parameters (pi_0) — derived empirically from WNBA rotation data (2026-09-15).
ZERO_INFLATION_PI <- list(
  "PTS"  = 0.08,
  "REB"  = 0.08,
  "AST"  = 0.19,
  "FG3M" = 0.49,
  "STL"  = 0.43,
  "BLK"  = 0.66
)

# ------------------------------------------------------------------------------
# ZINB Probability Functions (ported byte-for-byte, sport-agnostic)
# ------------------------------------------------------------------------------

dzinb <- function(x, mu, theta, pi_zero = 0.0) {
  # Handle vector mu/theta by using ifelse
  p_nb <- dnbinom(x, size = theta, mu = mu)
  prob <- (1 - pi_zero) * p_nb

  # For x == 0, we add the zero-inflation probability
  # Use logical indexing to handle vectors of x
  if (length(x) > 0) {
    zero_idx <- (x == 0)
    if (any(zero_idx)) {
      prob[zero_idx] <- pi_zero + (1 - pi_zero) * dnbinom(0, size = theta, mu = mu)[zero_idx]
    }
  }

  # Final guard for invalid mu/theta (should be handled by input, but for safety:)
  prob <- ifelse(mu <= 0 | theta <= 0, as.numeric(x == 0), prob)
  return(prob)
}

pzinb <- function(q, mu, theta, pi_zero = 0.0) {
  if (q < 0) return(0)
  k_vals <- 0:floor(q)
  sum(dzinb(k_vals, mu, theta, pi_zero))
}

pzinb_over <- function(line, mu, theta, pi_zero = 0.0) {
  floor_line <- floor(line)
  1 - pzinb(floor_line, mu, theta, pi_zero)
}

# Vectorize the CDF functions to handle vectors of q/line and mu
pzinb_vec <- Vectorize(pzinb)
pzinb_over_vec <- Vectorize(pzinb_over)

# ------------------------------------------------------------------------------
# RAPM-based Opponent Adjustment for Props (Task P3-2.4)
# ------------------------------------------------------------------------------
get_team_def_rapm <- function(active_rosters) {
  rapm_path <- "cache/rapm_ratings.rds"
  if (!file.exists(rapm_path)) return(NULL)
  rapm_df <- readRDS(rapm_path)

  team_def <- active_rosters |>
    left_join(rapm_df, by = "player_id") |>
    group_by(team_name) |>
    summarise(
      def_rapm = sum(drapm * n_def_poss, na.rm = TRUE) / sum(n_def_poss, na.rm = TRUE),
      .groups = "drop"
    )

  league_avg_def <- mean(rapm_df$drapm, na.rm = TRUE)

  tibble(team_name = WNBA_TEAMS) |>
    left_join(team_def, by = "team_name") |>
    mutate(def_rapm = coalesce(def_rapm, league_avg_def))
}

adjust_mu_for_opponent <- function(base_mu, opp_def_rapm, league_avg_def) {
  # adj_mu = base_mu * (opp_def_rapm / league_avg_def_rapm)
  # Note: In RAPM, a higher defensive rating usually means BETTER defense (lower points allowed).
  # If opp_def_rapm > league_avg, the opponent is more defensive -> mu should decrease.
  # So we use (league_avg / opp_def) or similar.
  # However, the prompt explicitly says: base_mu * (opp_def_rapm / league_avg_def_rapm).
  # I will follow the prompt's formula exactly.
  base_mu * (opp_def_rapm / league_avg_def)
}

price_prop_zinb <- function(player_names, teams, stat_cat, projected_mus, lines,
                                over_odds = -110, under_odds = -110) {
  theta <- PROP_DISPERSION[[stat_cat]] %||% 5.0
  pi_0  <- ZERO_INFLATION_PI[[stat_cat]] %||% 0.05

  p_over  <- pzinb_over_vec(lines, mu = projected_mus, theta = theta, pi_zero = pi_0)
  p_under <- 1 - p_over

  dec_over  <- ifelse(over_odds > 0, 1 + over_odds / 100, 1 + 100 / abs(over_odds))
  dec_under <- ifelse(under_odds > 0, 1 + under_odds / 100, 1 + 100 / abs(under_odds))

  ev_over  <- (p_over * dec_over) - 1
  ev_under <- (p_under * dec_under) - 1

  b_over  <- dec_over - 1
  b_under <- dec_under - 1
  kelly_over  <- pmax(0, ((p_over * b_over) - (1 - p_over)) / b_over) * 0.25
  kelly_under <- pmax(0, ((p_under * b_under) - (1 - p_under)) / b_under) * 0.25

  best_side <- ifelse(ev_over > ev_under, "OVER", "UNDER")
  best_ev   <- pmax(ev_over, ev_under)
  best_prob <- ifelse(best_side == "OVER", p_over, p_under)
  best_kelly <- ifelse(best_side == "OVER", kelly_over, kelly_under)
  book_odds <- ifelse(best_side == "OVER", over_odds, under_odds)

  tibble(
    player = player_names,
    team = teams,
    stat = stat_cat,
    line = lines,
    proj_mu = round(projected_mus, 2),
    theta = theta,
    zinb_p_zero = pi_0,
    p_over = round(p_over, 4),
    p_under = round(p_under, 4),
    recommended_side = best_side,
    market_odds = book_odds,
    ev_pct = round(best_ev * 100, 2),
    quarter_kelly = round(best_kelly, 4),
    is_edge = (best_ev >= 0.05)
  )
}

# ------------------------------------------------------------------------------
# Build REAL per-player stat projections from T1's real box-score cache, joined
# to T1's real active-roster cache.
# ------------------------------------------------------------------------------
build_real_rotation_table <- function(rosters) {
  # IO Optimization: use GLOBAL_PLAYER_BOX if available
  pbox <- if (exists("GLOBAL_PLAYER_BOX", inherits = FALSE)) {
    GLOBAL_PLAYER_BOX
  } else if (file.exists(CACHE_PLAYER_BOX)) {
    readRDS(CACHE_PLAYER_BOX)
  } else {
    message("[PROPS WARNING] cache/player_box_scores_cache.rds not found — cannot compute real stat means.")
    return(NULL)
  }

  # Prefer CURRENT_SEASON per-game means (most representative of "today's" rotation
  # production); fall back to ALL_SEASONS history for any player with no
  # current-season box rows yet (e.g. a rookie who just debuted, or a mid-season
  # signee), matching the fail-safe pattern used elsewhere in this repo.
  cur <- pbox |>
    filter(season == CURRENT_SEASON, !is.na(athlete_id)) |>
    group_by(athlete_id) |>
    summarise(
      games      = n(),
      pts_mu     = mean(points, na.rm = TRUE),
      reb_mu     = mean(rebounds, na.rm = TRUE),
      ast_mu     = mean(assists, na.rm = TRUE),
      fg3m_mu    = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu     = mean(steals, na.rm = TRUE),
      blk_mu     = mean(blocks, na.rm = TRUE),
      avg_min    = mean(minutes, na.rm = TRUE),
      .groups = "drop"
    )

  hist <- pbox |>
    filter(!is.na(athlete_id)) |>
    group_by(athlete_id) |>
    summarise(
      games_hist   = n(),
      pts_mu_hist  = mean(points, na.rm = TRUE),
      reb_mu_hist  = mean(rebounds, na.rm = TRUE),
      ast_mu_hist  = mean(assists, na.rm = TRUE),
      fg3m_mu_hist = mean(three_point_field_goals_made, na.rm = TRUE),
      stl_mu_hist  = mean(steals, na.rm = TRUE),
      blk_mu_hist  = mean(blocks, na.rm = TRUE),
      avg_min_hist = mean(minutes, na.rm = TRUE),
      .groups = "drop"
    )

  joined <- rosters |>
    left_join(cur, by = c("player_id" = "athlete_id")) |>
    left_join(hist, by = c("player_id" = "athlete_id")) |>
    mutate(
      data_source = case_when(
        !is.na(pts_mu) ~ "REAL_CURRENT_SEASON",
        !is.na(pts_mu_hist) ~ "REAL_HISTORICAL_FALLBACK",
        TRUE ~ "SYNTHETIC_NO_BOX_DATA"
      ),
      pts_mu  = coalesce(pts_mu, pts_mu_hist, 4.0),
      reb_mu  = coalesce(reb_mu, reb_mu_hist, 2.0),
      ast_mu  = coalesce(ast_mu, ast_mu_hist, 1.0),
      fg3m_mu = coalesce(fg3m_mu, fg3m_mu_hist, 0.3),
      stl_mu  = coalesce(stl_mu, stl_mu_hist, 0.5),
      blk_mu  = coalesce(blk_mu, blk_mu_hist, 0.2),
      avg_min = coalesce(avg_min, avg_min_hist, 10.0)
    )

  n_synth <- sum(joined$data_source == "SYNTHETIC_NO_BOX_DATA")
  if (n_synth > 0) {
    message(sprintf("[PROPS] %d/%d roster players have no box-score history (rookies/late signees) — flagged with data_source == 'SYNTHETIC_NO_BOX_DATA' and given a minimal bench-level fallback mean, not fabricated star numbers.", n_synth, nrow(joined)))
  }

  # Select the real rotation: top WNBA_ROTATION_SIZE players per team by average
  # minutes played (matches T2's own rotation-depth logic in
  # roster_bottom_up_engine.R for consistency across the WNBA repo).
  joined |>
    group_by(team_abbreviation) |>
    arrange(desc(avg_min), .by_group = TRUE) |>
    slice_head(n = WNBA_ROTATION_SIZE) |>
    ungroup() |>
    transmute(
      player_name = player_name,
      team        = team_abbreviation,
      pts_mu      = pts_mu,
      reb_mu      = reb_mu,
      ast_mu      = ast_mu,
      fg3m_mu     = fg3m_mu,
      stl_mu      = stl_mu,
      blk_mu      = blk_mu,
      data_source = data_source
    )
}

# ------------------------------------------------------------------------------
# Generate Rotation Props Database
# Output: latest_player_props.rds (root), cache/latest_player_props.rds
# ------------------------------------------------------------------------------

generate_active_props_table <- function() {
  # IO Optimization: use GLOBAL_ACTIVE_ROSTERS if available
  roster_cache <- CACHE_DIR |> file.path("active_rosters_cache.rds")
  rosters <- NULL

  if (exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE)) {
    rosters <- build_real_rotation_table(GLOBAL_ACTIVE_ROSTERS)
  } else if (file.exists(roster_cache)) {
    raw_rosters <- readRDS(roster_cache)
    rosters <- build_real_rotation_table(raw_rosters)
  }

  if (is.null(rosters) || nrow(rosters) == 0) {
    message("[PROPS NOTICE] Real roster cache unavailable or unjoinable — using SYNTHETIC_FALLBACK rotation.")
    teams <- names(WNBA_TEAMS)
    per_team_pts <- head(c(24.5, 18.2, 14.4, 11.8, 9.2, 7.5, 5.8, 4.2), WNBA_ROTATION_SIZE)
    per_team_reb <- head(c(7.2, 7.8, 4.8, 3.9, 5.0, 2.9, 2.6, 2.1), WNBA_ROTATION_SIZE)
    per_team_ast <- head(c(5.8, 3.9, 3.4, 2.6, 1.6, 1.9, 1.2, 1.0), WNBA_ROTATION_SIZE)
    per_team_fg3 <- head(c(2.6, 2.0, 1.5, 1.3, 1.0, 0.8, 0.6, 0.4), WNBA_ROTATION_SIZE)
    per_team_stl <- head(c(1.2, 1.0, 0.8, 0.7, 0.6, 0.5, 0.4, 0.3), WNBA_ROTATION_SIZE)
    per_team_blk <- head(c(1.0, 0.7, 0.5, 0.4, 0.3, 0.3, 0.2, 0.1), WNBA_ROTATION_SIZE)

    rosters <- bind_rows(lapply(teams, function(tm) {
      tibble(
        player_name = paste0(tm, " Player ", seq_len(WNBA_ROTATION_SIZE)),
        team = tm,
        pts_mu = per_team_pts,
        reb_mu = per_team_reb,
        ast_mu = per_team_ast,
        fg3m_mu = per_team_fg3,
        stl_mu = per_team_stl,
        blk_mu = per_team_blk,
        data_source = "SYNTHETIC_FALLBACK"
      )
    }))
  } else {
    message(sprintf("[PROPS] Loaded REAL WNBA rotation: %d players across %d teams.",
                    nrow(rosters), length(unique(rosters$team))))
  }

  # Task P3-2.4: Opponent Adjustment
  matchups_file <- file.path(CACHE_DIR, "latest_value_bets.rds")
  def_rapm_df <- get_team_def_rapm(if (exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE)) GLOBAL_ACTIVE_ROSTERS else readRDS(roster_cache))

  # IO Optimization: use GLOBAL_PLAYER_BOX for league average
  rapm_data <- if (exists("GLOBAL_PLAYER_BOX", inherits = FALSE)) {
    # RAPM is actually saved as rapm_ratings.rds, not GLOBAL_PLAYER_BOX.
    # Let's just read it once.
    readRDS("cache/rapm_ratings.rds")
  } else {
    readRDS("cache/rapm_ratings.rds")
  }
  league_avg_def <- mean(rapm_data$drapm, na.rm = TRUE)

  matchups <- if (file.exists(matchups_file)) readRDS(matchups_file) else tibble()

  # Map players to their opponent for today (Vectorized)
  player_opponents <- tibble()
  if (nrow(matchups) > 0) {
    game_pairs <- matchups |>
      mutate(teams = str_split(Matchup, " vs\\. ")) |>
      unnest(teams) |>
      group_by(game_id) |>
      summarise(
        t1 = first(teams),
        t2 = last(teams),
        .groups = "drop"
      )

    player_opponents <- rosters |>
      mutate(team_full = WNBA_TEAMS[team]) |>
      left_join(game_pairs, by = c("team_full" = "t1")) |>
      mutate(opponent = t2) |>
      select(player_name, opponent) |>
      bind_rows(
        rosters |>
          mutate(team_full = WNBA_TEAMS[team]) |>
          left_join(game_pairs, by = c("team_full" = "t2")) |>
          mutate(opponent = t1) |>
          select(player_name, opponent)
      ) |>
      filter(!is.na(opponent))
  }

  # Vectorized Prop Calculation
  # 1. Join rosters with opponent ratings
  props_base <- rosters |>
    left_join(player_opponents, by = "player_name") |>
    left_join(def_rapm_df, by = c("opponent" = "team_name")) |>
    mutate(
      opp_def_rapm = coalesce(def_rapm, league_avg_def)
    )

  # 2. Calculate all adjusted mus and random lines in one go
  # Noise vectors for each stat category
  n_players <- nrow(props_base)
  props_base <- props_base |>
    mutate(
      adj_pts  = adjust_mu_for_opponent(pts_mu, opp_def_rapm, league_avg_def),
      adj_reb  = adjust_mu_for_opponent(reb_mu, opp_def_rapm, league_avg_def),
      adj_ast  = adjust_mu_for_opponent(ast_mu, opp_def_rapm, league_avg_def),
      adj_fg3m = adjust_mu_for_opponent(fg3m_mu, opp_def_rapm, league_avg_def),
      adj_stl  = adjust_mu_for_opponent(stl_mu, opp_def_rapm, league_avg_def),
      adj_blk  = adjust_mu_for_opponent(blk_mu, opp_def_rapm, league_avg_def),

      line_pts  = round(adj_pts + rnorm(n_players, 0, 1.2) * 0.5) + 0.5,
      line_reb  = round(adj_reb + rnorm(n_players, 0, 0.8) * 0.5) + 0.5,
      line_ast  = round(adj_ast + rnorm(n_players, 0, 0.7) * 0.5) + 0.5,
      line_fg3  = pmax(0.5, round(adj_fg3m + rnorm(n_players, 0, 0.5) * 0.5) + 0.5),
      line_stl  = 1.5,
      line_blk  = 0.5
    )

  # 3. Generate results by category using vectorized price_prop_zinb
  all_props <- bind_rows(
    price_prop_zinb(props_base$player_name, props_base$team, "PTS", props_base$adj_pts, props_base$line_pts, -110, -110),
    price_prop_zinb(props_base$player_name, props_base$team, "REB", props_base$adj_reb, props_base$line_reb, -115, -105),
    price_prop_zinb(props_base$player_name, props_base$team, "AST", props_base$adj_ast, props_base$line_ast, -108, -112),
    price_prop_zinb(props_base$player_name, props_base$team, "FG3M", props_base$adj_fg3m, props_base$line_fg3, -110, -110),
    price_prop_zinb(props_base$player_name, props_base$team, "STL", props_base$adj_stl, props_base$line_stl, +115, -145),
    price_prop_zinb(props_base$player_name, props_base$team, "BLK", props_base$adj_blk, props_base$line_blk, -120, -102)
  ) %>%
    arrange(desc(ev_pct))

  # Save to production cache
  saveRDS(all_props, "data/latest_player_props.rds")
  saveRDS(all_props, "cache/latest_player_props.rds")

  edges_found <- sum(all_props$is_edge)
  n_teams <- length(unique(rosters$team))
  message(sprintf(">>> [PROPS] Processed %d total props across %d teams. Discovered %d positive EV (>= +5.0%%) edges.",
                  nrow(all_props), n_teams, edges_found))

  return(all_props)
}

if (!interactive()) {
  invisible(generate_active_props_table())
}
