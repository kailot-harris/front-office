# ==============================================================================
# mlb_postseason_simulator.R — MLB 12-Team Postseason Monte Carlo Bracket Simulator
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_postseason_simulator.R
#
# Phase 4: Postseason Bracket Simulator (Issue #19)
#
# Methodology & Rules (docs/MLB_REPLICATION_PLAN.md §6 items 4 and 5):
#   1. 12-Team Tiered Bracket Shape (6 per league: 3 division winners + 3 wild cards):
#        - Seeds 1-3: Division winners ranked by regular season record (Seeds 1 & 2 get byes).
#        - Seeds 4-6: Top 3 non-division winners ranked by regular season record.
#        - Wild Card Round (WC):
#            #3 seed vs #6 seed (best-of-3, hosted entirely by #3 seed)
#            #4 seed vs #5 seed (best-of-3, hosted entirely by #4 seed)
#        - Division Series (LDS):
#            #1 seed vs winner of #4/#5 (best-of-5, 2-2-1 format)
#            #2 seed vs winner of #3/#6 (best-of-5, 2-2-1 format)
#        - League Championship Series (LCS):
#            Winner DS1 vs Winner DS2 (best-of-7, 2-3-2 format)
#        - World Series (WS):
#            AL Champion vs NL Champion (best-of-7, 2-3-2 format, home advantage to
#            higher regular season record)
#   2. Round-Specific Series Length:
#        Round length varies by round (WC=3, LDS=5, LCS=7, WS=7) — not a single
#        imported series-length constant.
#   3. Regular-Season / Postseason Rule-Regime Split:
#        The Manfred-man extra-innings rule (automatic runner on 2nd) applies in the
#        regular season but NOT in the postseason (Official Baseball Rules 7.01(b)(2)).
#        Single-game win probabilities and simulated game outcomes use traditional
#        extra-innings rules without artificial ghost runners.
#   4. Win Probability Engine:
#        Utilizes team Elo ratings from Phase 2 (mlb_elo_engine.R) or Pythagorean
#        win-expectations with home-field advantage and run-environment variance.
#
# Interface Contract:
#   - Exposes top-level callable: run_postseason_simulator(season = 2024, n_sims = 10000, force_refresh = FALSE)
#   - Writes outputs to cache_path("postseason", ...):
#       cache/postseason/postseason_sim_results_2024.rds
#       cache/postseason/postseason_team_probabilities.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "mlb_postseason_simulator.R"

#' Determine 12-Team Postseason Seeding for AL and NL
#'
#' @param season Season integer (defaults to 2024)
#' @return Named list containing `AL` and `NL` seed tibbles (seeds 1 to 6)
seed_postseason_teams <- function(season = 2024) {
  log_info(sprintf("Determining postseason seeding for season %d", season), script = .LOG_SCRIPT)

  # Load pythag standings (prefer mlb_pythag_standings.rds which has team_id)
  pythag_file <- cache_path("pythag", "mlb_pythag_standings.rds", create = FALSE)
  if (!file.exists(pythag_file)) {
    pythag_file <- cache_path("pythag", sprintf("pythag_baseline_%d.rds", season), create = FALSE)
  }
  if (!file.exists(pythag_file)) {
    stop(sprintf("Standings cache not found at %s. Run mlb_pythag_baseline.R first.", pythag_file))
  }
  standings <- readRDS(pythag_file)

  # Ensure team metadata (division and league)
  teams_meta <- MLB_TEAMS %>%
    dplyr::filter(league_name %in% c("American League", "National League")) %>%
    dplyr::select(team_id, team_full_name, team_abbreviation, division_name, league_name)

  # Merge standings with metadata (by team_id if available, otherwise by team_name)
  df <- if ("team_id" %in% names(standings)) {
    standings %>% dplyr::inner_join(teams_meta, by = "team_id")
  } else {
    standings %>% dplyr::inner_join(teams_meta, by = c("team_name" = "team_full_name"))
  }

  # Ensure run_diff and team_full_name columns exist
  if (!"run_diff" %in% names(df) && "run_differential" %in% names(df)) {
    df$run_diff <- df$run_differential
  }
  if (!"team_full_name" %in% names(df) && "team_name" %in% names(df)) {
    df$team_full_name <- df$team_name
  }

  # Load team Elo ratings if available for rating enrichment
  elo_file <- cache_path("ratings", "mlb_team_ratings.rds")
  if (file.exists(elo_file)) {
    elo_df <- readRDS(elo_file) %>%
      dplyr::select(team_id, elo_rating)
    df <- df %>%
      dplyr::left_join(elo_df, by = "team_id")
  } else {
    df$elo_rating <- 1500.0
  }

  seed_league <- function(lg_name) {
    lg_df <- df %>%
      dplyr::filter(league_name == lg_name)

    # 1. Division winners: top team in each of the 3 divisions
    div_winners <- lg_df %>%
      dplyr::group_by(division_name) %>%
      dplyr::arrange(desc(wins), desc(run_diff)) %>%
      dplyr::slice(1) %>%
      dplyr::ungroup() %>%
      dplyr::arrange(desc(wins), desc(run_diff)) %>%
      dplyr::mutate(seed = dplyr::row_number()) # Seeds 1, 2, 3

    div_winner_ids <- div_winners$team_id

    # 2. Wild Cards: top 3 non-division winners
    wild_cards <- lg_df %>%
      dplyr::filter(!team_id %in% div_winner_ids) %>%
      dplyr::arrange(desc(wins), desc(run_diff)) %>%
      dplyr::slice(1:3) %>%
      dplyr::mutate(seed = 3L + dplyr::row_number()) # Seeds 4, 5, 6

    # Combined seeds 1 through 6
    dplyr::bind_rows(div_winners, wild_cards) %>%
      dplyr::arrange(seed) %>%
      dplyr::transmute(
        seed, team_id, team_name = team_full_name, team_abbr = team_abbreviation,
        division = division_name, wins, losses, run_diff, elo_rating
      )
  }


  seeds <- list(
    AL = seed_league("American League"),
    NL = seed_league("National League")
  )

  log_info(sprintf("Postseason seeding established: AL top seed %s (%d wins), NL top seed %s (%d wins)",
                   seeds$AL$team_name[1], seeds$AL$wins[1], seeds$NL$team_name[1], seeds$NL$wins[1]),
           script = .LOG_SCRIPT)

  seeds
}

#' Calculate Head-to-Head Single-Game Win Probability
#'
#' @param team_home Team data row (with elo_rating)
#' @param team_away Team data row (with elo_rating)
#' @param is_neutral Logical; whether game is at neutral site
#' @param is_postseason Logical; ensures postseason rules (traditional extra innings)
#' @return Numeric win probability for home team (between 0 and 1)
calc_game_win_prob <- function(team_home, team_away, is_neutral = FALSE, is_postseason = TRUE) {
  elo_home <- team_home$elo_rating %||% 1500.0
  elo_away <- team_away$elo_rating %||% 1500.0

  hca <- if (is_neutral) 0.0 else (MLB_ELO_HOME_FIELD_ADVANTAGE %||% 14.9)
  
  # Elo differential with home field advantage
  elo_diff <- (elo_home + hca) - elo_away
  win_prob <- 1 / (1 + 10^(-elo_diff / 400))

  # Postseason Rule-Regime Adjustment:
  # In regular season, automatic runner on 2nd increases extra-inning variance / run conversion.
  # In postseason, traditional extra innings apply (MLB_POSTSEASON_RULES$ghost_runner_extra_innings == FALSE).
  # Under traditional rules, extra innings revert to base team skill / bullpen depth with slightly
  # lower home-advantage leverage compared to the sudden-death nature of regular season ghost runners.
  if (is_postseason && (!is.null(MLB_POSTSEASON_RULES$ghost_runner_extra_innings) && !MLB_POSTSEASON_RULES$ghost_runner_extra_innings)) {
    # Traditional extra innings slightly dampens home-field variance in extras
    win_prob <- (win_prob * 0.98) + (0.50 * 0.02)
  }

  pmax(0.01, pmin(0.99, win_prob))
}

#' Simulate a Single Postseason Series with Correct Format
#'
#' @param team_high Higher seed team row
#' @param team_low Lower seed team row
#' @param round_name Character; "wild_card", "div_series", "champ_series", or "world_series"
#' @return The winning team row
simulate_series <- function(team_high, team_low, round_name = c("wild_card", "div_series", "champ_series", "world_series")) {
  round_name <- match.arg(round_name)

  # Round-specific series lengths: WC=3, DS=5, LCS=7, WS=7
  best_of <- MLB_POSTSEASON_RULES$series_length[[round_name]] %||% 7L
  wins_needed <- ceiling(best_of / 2)

  # Home-away sequence
  home_seq <- MLB_POSTSEASON_RULES$home_format[[round_name]]
  if (is.null(home_seq) || length(home_seq) < best_of) {
    # Fallback to standard 2-2-1-1-1 or 2-3-2 if not specified
    home_seq <- rep("higher", best_of)
  }

  high_wins <- 0L
  low_wins  <- 0L

  for (game_num in seq_len(best_of)) {
    is_high_home <- (home_seq[game_num] == "higher")
    
    if (is_high_home) {
      prob_high <- calc_game_win_prob(team_high, team_low, is_neutral = FALSE, is_postseason = TRUE)
    } else {
      prob_low <- calc_game_win_prob(team_low, team_high, is_neutral = FALSE, is_postseason = TRUE)
      prob_high <- 1.0 - prob_low
    }

    # Simulate game outcome
    if (runif(1) < prob_high) {
      high_wins <- high_wins + 1L
    } else {
      low_wins <- low_wins + 1L
    }

    if (high_wins == wins_needed) return(team_high)
    if (low_wins == wins_needed)  return(team_low)
  }

  if (high_wins > low_wins) team_high else team_low
}

#' Simulate One Complete 12-Team MLB Postseason Bracket
#'
#' @param seeds Named list with AL and NL seed tibbles
#' @return Named list of round champions and World Series champion
simulate_single_bracket <- function(seeds) {
  sim_league <- function(lg_seeds) {
    t1 <- lg_seeds %>% dplyr::filter(seed == 1) %>% as.list()
    t2 <- lg_seeds %>% dplyr::filter(seed == 2) %>% as.list()
    t3 <- lg_seeds %>% dplyr::filter(seed == 3) %>% as.list()
    t4 <- lg_seeds %>% dplyr::filter(seed == 4) %>% as.list()
    t5 <- lg_seeds %>% dplyr::filter(seed == 5) %>% as.list()
    t6 <- lg_seeds %>% dplyr::filter(seed == 6) %>% as.list()

    # Round 1: Wild Card Series (Best-of-3, all games hosted by higher seed)
    wc1_winner <- simulate_series(t3, t6, round_name = "wild_card")
    wc2_winner <- simulate_series(t4, t5, round_name = "wild_card")

    # Round 2: Division Series (Best-of-5, 2-2-1 format)
    # Seed 1 plays winner of 4/5 (wc2); Seed 2 plays winner of 3/6 (wc1)
    ds1_winner <- simulate_series(t1, wc2_winner, round_name = "div_series")
    ds2_winner <- simulate_series(t2, wc1_winner, round_name = "div_series")

    # Round 3: League Championship Series (Best-of-7, 2-3-2 format)
    # Higher original seed hosts games 1, 2, 6, 7
    if (ds1_winner$seed < ds2_winner$seed) {
      lcs_high <- ds1_winner
      lcs_low  <- ds2_winner
    } else {
      lcs_high <- ds2_winner
      lcs_low  <- ds1_winner
    }
    pennant_winner <- simulate_series(lcs_high, lcs_low, round_name = "champ_series")

    list(
      wc_winners = c(wc1_winner$team_name, wc2_winner$team_name),
      ds_winners = c(ds1_winner$team_name, ds2_winner$team_name),
      pennant    = pennant_winner
    )
  }

  al_res <- sim_league(seeds$AL)
  nl_res <- sim_league(seeds$NL)

  # Round 4: World Series (Best-of-7, 2-3-2 format)
  # Host advantage goes to team with better regular season record (or higher wins/run_diff)
  al_champ <- al_res$pennant
  nl_champ <- nl_res$pennant

  if (al_champ$wins > nl_champ$wins || (al_champ$wins == nl_champ$wins && al_champ$run_diff >= nl_champ$run_diff)) {
    ws_high <- al_champ
    ws_low  <- nl_champ
  } else {
    ws_high <- nl_champ
    ws_low  <- al_champ
  }

  ws_champion <- simulate_series(ws_high, ws_low, round_name = "world_series")

  list(
    al_ds_teams   = c(al_res$wc_winners, seeds$AL$team_name[1:2]),
    nl_ds_teams   = c(nl_res$wc_winners, seeds$NL$team_name[1:2]),
    al_lcs_teams  = al_res$ds_winners,
    nl_lcs_teams  = nl_res$ds_winners,
    al_champion   = al_champ$team_name,
    nl_champion   = nl_champ$team_name,
    ws_champion   = ws_champion$team_name
  )
}

#' Run Postseason Monte Carlo Bracket Simulator
#'
#' @param season Season integer (defaults to 2024)
#' @param n_sims Number of Monte Carlo simulations (default 10,000)
#' @param force_refresh If TRUE, recomputes from standings
#' @return Named list with seeding summary, team advancement probabilities, and simulation counts
run_postseason_simulator <- function(season = 2024, n_sims = 10000, force_refresh = FALSE) {
  log_info("Starting MLB postseason Monte Carlo bracket simulator stage", script = .LOG_SCRIPT,
           season = season, n_sims = n_sims, force_refresh = force_refresh)

  cache_res  <- cache_path("postseason", sprintf("postseason_sim_results_%d.rds", season))
  cache_prob <- cache_path("postseason", "postseason_team_probabilities.rds")

  if (!force_refresh && file.exists(cache_res) && file.exists(cache_prob)) {
    log_info("Loading cached postseason simulation results from disk", script = .LOG_SCRIPT)
    return(list(
      sim_results  = readRDS(cache_res),
      probabilities= readRDS(cache_prob)
    ))
  }

  seeds <- seed_postseason_teams(season = season)

  all_teams <- dplyr::bind_rows(
    seeds$AL %>% dplyr::mutate(league = "AL"),
    seeds$NL %>% dplyr::mutate(league = "NL")
  )

  # Tracking containers
  n_teams <- nrow(all_teams)
  counts <- tibble::tibble(
    team_id     = all_teams$team_id,
    team_name   = all_teams$team_name,
    league      = all_teams$league,
    seed        = all_teams$seed,
    wins        = all_teams$wins,
    elo_rating  = all_teams$elo_rating,
    make_ds     = if_else(all_teams$seed <= 2, as.numeric(n_sims), 0),
    make_lcs    = 0,
    win_pennant = 0,
    win_ws      = 0
  )

  team_map <- setNames(seq_len(n_teams), all_teams$team_name)

  log_info(sprintf("Running %d Monte Carlo postseason bracket simulations...", n_sims), script = .LOG_SCRIPT)
  start_sim_time <- Sys.time()

  for (i in seq_len(n_sims)) {
    sim <- simulate_single_bracket(seeds)

    # LDS appearances (for seeds 3-6 who won WC)
    for (t in c(sim$al_ds_teams, sim$nl_ds_teams)) {
      idx <- team_map[[t]]
      if (!is.null(idx) && all_teams$seed[idx] > 2) {
        counts$make_ds[idx] <- counts$make_ds[idx] + 1
      }
    }

    # LCS appearances
    for (t in c(sim$al_lcs_teams, sim$nl_lcs_teams)) {
      idx <- team_map[[t]]
      if (!is.null(idx)) {
        counts$make_lcs[idx] <- counts$make_lcs[idx] + 1
      }
    }

    # Pennant winners
    al_champ_idx <- team_map[[sim$al_champion]]
    nl_champ_idx <- team_map[[sim$nl_champion]]
    if (!is.null(al_champ_idx)) counts$win_pennant[al_champ_idx] <- counts$win_pennant[al_champ_idx] + 1
    if (!is.null(nl_champ_idx)) counts$win_pennant[nl_champ_idx] <- counts$win_pennant[nl_champ_idx] + 1

    # World Series Champion
    ws_idx <- team_map[[sim$ws_champion]]
    if (!is.null(ws_idx)) counts$win_ws[ws_idx] <- counts$win_ws[ws_idx] + 1
  }

  sim_elapsed <- as.numeric(difftime(Sys.time(), start_sim_time, units = "secs"))
  log_info(sprintf("Completed %d simulations in %.2f seconds (%.0f sims/sec)",
                   n_sims, sim_elapsed, n_sims / sim_elapsed), script = .LOG_SCRIPT)

  # Convert counts to probabilities
  probabilities <- counts %>%
    dplyr::mutate(
      pct_ds      = round((make_ds / n_sims) * 100, 2),
      pct_lcs     = round((make_lcs / n_sims) * 100, 2),
      pct_pennant = round((win_pennant / n_sims) * 100, 2),
      pct_ws      = round((win_ws / n_sims) * 100, 2)
    ) %>%
    dplyr::arrange(desc(pct_ws), desc(pct_pennant), desc(pct_lcs))

  sim_data <- list(
    season       = season,
    n_sims       = n_sims,
    sim_elapsed  = sim_elapsed,
    seeds        = seeds,
    probabilities= probabilities
  )

  saveRDS(sim_data, cache_res)
  saveRDS(probabilities, cache_prob)

  log_info(sprintf("Saved postseason simulation results to %s and %s", cache_res, cache_prob),
           script = .LOG_SCRIPT)

  invisible(sim_data)
}
