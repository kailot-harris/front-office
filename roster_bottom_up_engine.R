# ==============================================================================
# Bottom-Up Player-Composed WNBA H2H Prediction & Standings Engine
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/roster_bottom_up_engine.R
#
# Ported from NBA Analytics/roster_bottom_up_engine.R (T2 / wnba_rating_engine_agent).
# This is the single most load-bearing script in the WNBA replication - market odds,
# props, playoffs, and the dashboard will all eventually read its output. Per
# WNBA_REPLICATION_PLAN.md §(b) Tier 3 and task_assignments.md's agent3.md brief, the
# following constants were recalibrated (not blindly copied) for WNBA:
#
#   - Rotation depth: NBA's `slice_head(n = 9)` -> WNBA `slice_head(n = WNBA_ROTATION_SIZE)`,
#     WNBA_ROTATION_SIZE = 8 (see rationale at its definition below).
#   - Team-minutes pool: NBA's 240 (48 min x 5 on floor) -> WNBA's 200 (40 min x 5), both for
#     `tot_proj_min` and the `allocated_min` proportional-allocation formula.
#   - `games_per_opponent`: NBA's `82 / (n_teams - 1)` -> `WNBA_SEASON_GAMES / (n_teams - 1)`
#     using config.R's validated 44-game constant, with the zero-sum invariant re-derived for
#     a 15-team league (Sigma wins == WNBA_SEASON_GAMES * n_teams / 2, not 1230/2).
#   - Sigma constant: NBA hardcodes 11.8 inline. WNBA uses `WNBA_MARGIN_SIGMA` from config.R -
#     an ACTUAL empirically-derived value (sd() of 1,953 real home-team-game margins from
#     T1's box_scores_cache.rds, 2019-2026 seasons == 14.01, rounded to 14.0), not a bare TODO
#     placeholder and not an NBA number silently inherited. See config.R's comment block next
#     to WNBA_MARGIN_SIGMA for the exact derivation code and per-season sd() breakdown.
#   - Team count / names: NBA's hardcoded "30 teams" language and reliance on integer team_id
#     -> config.R's WNBA_TEAMS / WNBA_TEAM_COUNT (15 teams) used everywhere.
#   - Output cache filename: `cache/projected_30_team_standings.rds` ->
#     `cache/projected_wnba_standings.rds` per the plan's explicit recommendation (avoids
#     downstream confusion with the NBA cache of the same shape). T4/T5 must read this exact
#     path.
#
# PHASE 4 UPDATE (finding C-1): the three `hca <- 2.40` literals below now read `WNBA_HCA` from
# config.R. The VALUE is unchanged; only its definition site moved. The caveat in the paragraph
# below still stands and is restated at WNBA_HCA's definition in config.R.
#
# Home-court advantage (hca <- 2.40) was left unchanged - not called out as a Tier 3 item in
# the plan/brief, and the real T1 data's empirical home-margin mean (~1.9 pts, computed during
# the WNBA_MARGIN_SIGMA derivation above) is close enough to 2.4 that reusing the NBA prior is
# a reasonable interim choice; it is NOT independently empirically re-derived here and should
# be treated with the same "recalibrate before fully trusting" caution as other unvalidated
# Tier-3-adjacent constants.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
# FINDING H-2: shared RAPM<->roster join helper (see compute_team_rapm_ratings() below).
source("rapm_join_utils.R")
# CLAUDE.md: use the EXISTING normalize_team_abbreviation() (CONN -> CON) rather than
# reimplementing it. Sourced from player_metrics.R (pure function definitions, no auto-run
# side effects) rather than daily_ingest.R, whose footer triggers a full live ingest.
source("player_metrics.R")

# ------------------------------------------------------------------------------
# Elo & RAPM Feature Computation (Task P3-2.1)
# ------------------------------------------------------------------------------
# LATENT DEFECT UN-MASKED BY FINDING C-2 (agent_pipeline, Phase 4 Wave 2).
# This function was written against a WIDE, one-row-per-game schema
# (`team_home_abbreviation` / `team_away_abbreviation` / `team_home_score` /
# `team_away_score`, `season_type == "Regular Season"`). `data/box_scores_cache.rds` has never
# had that shape: it is wehoop::load_wnba_team_box() output, which is LONG — one row per team
# per game, keyed on `team_abbreviation` / `opponent_team_abbreviation` / `team_score` /
# `opponent_team_score` / `team_home_away`, with a NUMERIC `season_type` (2 = Regular Season,
# 3 = Postseason), never the string "Regular Season".
# The first filter() therefore errors with "object 'team_home_abbreviation' not found". Nobody
# saw it because C-2 meant this script never executed inside the pipeline. Reshaping here (and
# NOT weakening the fix to a tryCatch) is required for the C-2 fix to produce real output — this
# is exactly the "silent no-op becomes a visible hard failure" case the review predicted.
# CLAUDE.md data quirks honoured: CONN -> CON is normalized BEFORE the WNBA_TEAMS membership
# filter (otherwise five seasons of real Connecticut Sun games are dropped as "exhibitions"),
# via the shared normalize_team_abbreviation() helper rather than a local reimplementation.
compute_elo_ratings <- function() {
  if (!file.exists(CACHE_TEAM_BOX)) stop("Team box cache missing.")

  games <- readRDS(CACHE_TEAM_BOX) |>
    normalize_team_abbreviation() |>
    filter(
      as.character(season_type) %in% c("2", "Regular Season"),
      team_abbreviation %in% names(WNBA_TEAMS),
      opponent_team_abbreviation %in% names(WNBA_TEAMS),
      team_home_away == "home"          # collapse the long table to one row per game
    ) |>
    transmute(
      game_id, game_date, season,
      h_team  = team_abbreviation,
      a_team  = opponent_team_abbreviation,
      h_score = suppressWarnings(as.numeric(team_score)),
      a_score = suppressWarnings(as.numeric(opponent_team_score))
    ) |>
    filter(!is.na(h_score), !is.na(a_score), h_score != a_score) |>
    distinct(game_id, .keep_all = TRUE) |>
    arrange(game_date)

  if (nrow(games) == 0) {
    warning("[ELO] No usable regular-season games in the team box cache; returning flat 1500 ratings.")
    return(setNames(rep(1500, length(WNBA_TEAMS)), names(WNBA_TEAMS)))
  }
  message(sprintf(">>> [ELO] Rating %d real regular-season WNBA games (%s to %s).",
                  nrow(games), min(games$game_date), max(games$game_date)))

  ratings <- setNames(rep(1500, length(WNBA_TEAMS)), names(WNBA_TEAMS))
  last_season <- NA

  for (i in seq_len(nrow(games))) {
    curr_season <- games$season[i]
    if (!is.na(last_season) && curr_season != last_season) {
      ratings <- 1500 + 0.75 * (ratings - 1500)   # offseason regression toward the mean
    }
    last_season <- curr_season
    h_team <- games$h_team[i]
    a_team <- games$a_team[i]
    h_win  <- games$h_score[i] > games$a_score[i]
    exp_h  <- 1 / (1 + 10^((ratings[a_team] - ratings[h_team]) / 400))
    ratings[h_team] <- ratings[h_team] + 20 * (as.numeric(h_win) - exp_h)
    ratings[a_team] <- ratings[a_team] + 20 * (as.numeric(!h_win) - (1 - exp_h))
  }
  return(ratings)
}

compute_team_rapm_ratings <- function(active_rosters) {
  rapm_path <- file.path(CACHE_DIR, "rapm_ratings.rds")
  if (!file.exists(rapm_path)) return(NULL)
  rapm_df <- readRDS(rapm_path)

  # FINDING H-2 (docs/SECURITY_TECHNICAL_REVIEW.md): this used to be
  #   active_rosters |> left_join(rapm_df, by = "player_id")
  # which is the naive join CLAUDE.md explicitly warns against. rapm_ratings.rds$player_id is a
  # stats-provider ID stored as <character>; active_rosters_cache.rds$player_id is an ESPN athlete
  # ID stored as <integer>. Zero overlap even coerced, and dplyr now refuses the join outright
  # ("incompatible types") — the same line hard-fails player_props_engine.R nightly. It was masked
  # here only because C-2 made this whole script a no-op; fixing C-2 without this would have turned
  # a silent no-op into a second nightly hard failure.
  # Use the single shared helper from rapm_join_utils.R (agent_foundation, Wave 1). Do NOT copy
  # market_odds_engine.R's inline (team, last_name) join here: per that agent's Handoff Notes the
  # RAPM side has 15 duplicate (team, last_name) groups (both Ogwumike sisters, three Williams on
  # PHX, ...), so the inline version FANS OUT 121 roster players into 128 rows — harmless for
  # market_odds' per-team max(), but it would silently double-count in this possession-weighted
  # aggregate. join_rapm_to_roster() emits exactly one RAPM row per rostered player.
  joined <- join_rapm_to_roster(active_rosters, rapm_df, matched_only = TRUE)

  league_mean <- mean(rapm_df$total_rapm, na.rm = TRUE)

  if (nrow(joined) == 0 || !all(c("total_rapm", "n_off_poss") %in% names(joined))) {
    # Fail-safe (repo convention): never crash the stage on a schema surprise — fall back to a
    # flat league-average RAPM for every team and say so loudly.
    warning("[RAPM] join_rapm_to_roster() returned no usable rows; falling back to league-mean RAPM for all teams.")
    return(tibble(team_name = unname(WNBA_TEAMS), team_rapm = league_mean))
  }

  team_rapms <- joined |>
    group_by(team_name) |>
    summarise(
      tot_poss  = sum(n_off_poss, na.rm = TRUE),
      wsum      = sum(total_rapm * n_off_poss, na.rm = TRUE),
      mean_rapm = mean(total_rapm, na.rm = TRUE),
      .groups   = "drop"
    ) |>
    # Guard the zero-possession divide-by-zero (would have produced NaN, which coalesce() below
    # does NOT catch) by degrading to the unweighted team mean.
    mutate(team_rapm = if_else(tot_poss > 0, wsum / tot_poss, mean_rapm)) |>
    select(team_name, team_rapm)

  tibble(team_name = unname(WNBA_TEAMS)) |>
    left_join(team_rapms, by = "team_name") |>
    # coalesce() catches NA (team absent from the join) but not NaN/Inf, so check is.finite too.
    mutate(team_rapm = if_else(is.finite(coalesce(team_rapm, league_mean)),
                               coalesce(team_rapm, league_mean), league_mean))
}


# NOTE: the NBA original also `source("live_calibration.R")` here, but none of that file's
# functions (american_to_prob/remove_vig/calibration_analysis/load_market_odds/
# compare_model_vs_market/simulate_live_game) are actually called anywhere in this script -
# it's pure odds-math/calibration plumbing consumed by market_odds_engine.R/bet_tracker.R
# (T4's scope), not this rating engine. `live_calibration.R` has not been ported into this
# WNBA repo yet (out of scope for T2 per agent3.md's deliverable list), so the source() call
# is intentionally omitted rather than left as a broken dependency. T4 should port
# live_calibration.R itself when it needs those helpers (the file is sport-agnostic math with
# no NBA-specific constants, so it should port with no changes beyond the header comment).

# Ensure cache paths exist
if (!exists("CACHE_DIR")) CACHE_DIR <- file.path(PROJECT_DIR, "cache")
if (!exists("CACHE_INJURY_DATA")) CACHE_INJURY_DATA <- file.path(CACHE_DIR, "injury_data_cache.rds")

# ------------------------------------------------------------------------------
# WNBA-specific structural constants (recalibrated from the NBA original - see header)
# ------------------------------------------------------------------------------
# Rotation depth: WNBA_REPLICATION_PLAN.md §(b) Tier 3 recommends "top-7 or top-8" given the
# 12-player active roster cap (vs NBA's 15) and real-world WNBA coaching patterns of leaning
# on a shorter bench than NBA teams. We picked 8 (not 7): WNBA teams still commonly deploy
# 8-9 rotation players who see real minutes (per the plan's own reference to ~8-9 depth), and
# top-8 gives one more buffer player than top-7 against a single starter's injury/foul trouble
# corrupting the whole team rating, while still being meaningfully shallower than NBA's top-9.
# EXPLICITLY FLAGGED PER THE BRIEF: this has not yet been validated against actual WNBA
# per-player minutes distributions (e.g. checking what rotation size captures ~95% of team
# minutes in the real box score cache) - that validation should happen once this script has
# been run a few times against live rosters; if real minutes data shows an 8th player rarely
# clears meaningful floor time, drop to 7.
# NOTE (T4 update): this constant is now centralized in config.R (added during T4
# / wnba_betting_market_agent because player_props_engine.R also needs it for
# consistency). Kept here as a guarded fallback only, so this script still runs
# standalone even if sourced before config.R for any reason; value/rationale
# unchanged from the original T2 choice below.
if (!exists("WNBA_ROTATION_SIZE")) WNBA_ROTATION_SIZE <- 8

# ------------------------------------------------------------------------------
# 1. Compute Historical Player Impact (Empirically Centered BPM)
# ------------------------------------------------------------------------------
get_player_bpm_ratings <- function() {
  # IO Optimization: use GLOBAL_PLAYER_BOX if available
  if (!exists("GLOBAL_PLAYER_BOX", inherits = FALSE) && !file.exists(CACHE_PLAYER_BOX)) stop("Player box cache missing.")

  player_box <- if (exists("GLOBAL_PLAYER_BOX", inherits = FALSE)) {
    GLOBAL_PLAYER_BOX
  } else {
    readRDS(CACHE_PLAYER_BOX)
  }

  # Clean numeric plus_minus from raw game logs

  # Clean numeric plus_minus from raw game logs
  player_clean <- player_box |>
    filter(minutes > 8) |>
    mutate(
      pm_numeric = suppressWarnings(as.numeric(plus_minus)),
      pm_numeric = coalesce(pm_numeric, 0.0),
      # Weight the most recent completed/in-progress season heavier, same idea as the NBA
      # original's `season >= 2025` cutoff shifted forward by one year to WNBA's CURRENT_SEASON.
      weight     = if_else(season >= (CURRENT_SEASON - 1), 1.5, 1.0)
    )

  # Aggregate across all games
  raw_stats <- player_clean |>
    group_by(athlete_id) |>
    summarise(
      player_name  = last(athlete_display_name),
      games_played = n(),
      total_min    = sum(minutes, na.rm = TRUE),
      avg_min      = mean(minutes, na.rm = TRUE),

      # Per-36 Box Score Creation (weights unchanged from NBA - per plan §b Tier 2, BPM
      # box-score weights are not NBA-specific; T1's calculate_bpm_components() carried the
      # same weights forward with a TODO(recalibrate) comment, which this script inherits)
      pts36 = sum(points * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      reb36 = sum(rebounds * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      ast36 = sum(assists * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      stl36 = sum(steals * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      blk36 = sum(blocks * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      tov36 = sum(turnovers * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,

      # Ground-Truth Empirical On-Court Net Differential per 36
      empirical_pm36 = sum(pm_numeric * weight, na.rm = TRUE) / sum(minutes * weight, na.rm = TRUE) * 36,
      .groups = "drop"
    ) |>
    filter(total_min >= 200) |>
    mutate(
      # Standard Box Creation component
      box_score = 0.55 * pts36 + 0.60 * reb36 + 1.10 * ast36 + 1.40 * stl36 + 1.20 * blk36 - 1.25 * tov36
    )

  # Center both metrics at league average (0.00)
  box_mu <- sum(raw_stats$box_score * raw_stats$total_min) / sum(raw_stats$total_min)
  pm_mu  <- sum(raw_stats$empirical_pm36 * raw_stats$total_min) / sum(raw_stats$total_min)

  ratings <- raw_stats |>
    mutate(
      centered_box = box_score - box_mu,
      raw_centered_pm = empirical_pm36 - pm_mu,

      # Empirical Bayes Sample-Size Shrinkage:
      # Players with fewer minutes regress toward 0.0, preventing small-sample blowout distortion
      shrinkage_weight = total_min / (total_min + 500),
      centered_pm = raw_centered_pm * shrinkage_weight,

      # 50/50 Objective Fusion
      bpm = round(pmax(-5.0, pmin(12.0, 0.50 * centered_box + 0.50 * centered_pm)), 2)
    ) |>
    select(athlete_id, player_name, games_played, total_min, avg_min, bpm)

  return(ratings)
}

# ------------------------------------------------------------------------------
# 2. Build Dynamic Team Net Rating from a 200-Minute Rotation (40 min x 5 on floor)
# ------------------------------------------------------------------------------
compute_team_live_rating <- function(team, active_rosters, player_ratings, elo_ratings, team_rapm_df, injury_df = tibble()) {
  team_players <- active_rosters |>
    filter(team_name == team)

  if (nrow(team_players) == 0) return(list(net_rating = 0.0, elo = 1500, team_rapm = 0.0, rotation = tibble()))

  # Map team name to abbreviation for Elo lookup
  team_abbr <- names(WNBA_TEAMS)[WNBA_TEAMS == team]
  team_elo  <- if (length(team_abbr) > 0) elo_ratings[team_abbr] else 1500
  team_rapm <- team_rapm_df |> filter(team_name == team) |> pull(team_rapm)
  if (length(team_rapm) == 0) team_rapm <- 0.0

  # Primary Join on athlete_id (player_box_scores_cache.rds) <-> player_id (active_rosters_cache.rds)
  # - per T1's Handoff Notes, both are real ESPN athlete IDs, so this joins cleanly by ID first.
  roster_rated <- team_players |>
    left_join(player_ratings |> select(athlete_id, bpm, hist_avg_min = avg_min),
              by = c("player_id" = "athlete_id"))

  # Fallback fill for any players matching by name
  unmatched_idx <- which(is.na(roster_rated$bpm))
  if (length(unmatched_idx) > 0) {
    name_lookup <- player_ratings |> select(player_name, bpm_name = bpm, min_name = avg_min)
    roster_rated[unmatched_idx, ] <- roster_rated[unmatched_idx, ] |>
      left_join(name_lookup, by = "player_name") |>
      mutate(
        bpm = coalesce(bpm, bpm_name),
        hist_avg_min = coalesce(hist_avg_min, min_name)
      ) |>
      select(-bpm_name, -min_name)
  }

  # Replacement level prior (-2.0 BPM) for rookies/incoming players - unchanged from NBA;
  # T1's calculate_bpm_components() TODO(recalibrate) note applies equally here.
  roster_rated <- roster_rated |>
    mutate(
      bpm = coalesce(bpm, -2.0),
      hist_avg_min = coalesce(hist_avg_min, 15.0)
    )

  # Adjust minutes for real-time injury status (join key: team_name + player_name, matching
  # cache/injury_data_cache.rds's real schema - see T1 Handoff Notes)
  if (nrow(injury_df) > 0) {
    inj_team <- injury_df |> filter(team_name == team)
    if (nrow(inj_team) > 0) {
      roster_rated <- roster_rated |>
        left_join(inj_team |> select(player_name, status), by = "player_name") |>
        mutate(
          hist_avg_min = case_when(
            status == "Out"          ~ 0.0,
            status == "Doubtful"     ~ hist_avg_min * 0.25,
            status == "Questionable" ~ hist_avg_min * 0.50,
            TRUE                     ~ hist_avg_min
          )
        ) |>
        select(-status)
    }
  }

  # Select top-WNBA_ROTATION_SIZE rotation players (8, see constant definition above)
  active_rotation <- roster_rated |>
    arrange(desc(hist_avg_min * (bpm + 5.5))) |>
    slice_head(n = WNBA_ROTATION_SIZE)

  tot_proj_min <- sum(active_rotation$hist_avg_min)
  if (tot_proj_min <= 0) tot_proj_min <- 200  # 40 min x 5 on floor (WNBA regulation)

  # Proportionally allocate the 200 regulation minutes (40 min x 5, vs NBA's 240 = 48 min x 5)
  active_rotation <- active_rotation |>
    mutate(allocated_min = (hist_avg_min / tot_proj_min) * 200)

  # Team Net Rating (5 on floor * minutes-weighted BPM)
  # Bounds carried over unchanged from NBA (-10.5 to +14.0) - not flagged as a Tier 3 item in
  # the plan; revisit if WNBA net-rating spread empirically differs once this has run more.
  raw_team_nrtg <- sum(active_rotation$bpm * (active_rotation$allocated_min / 200)) * 5.0
  team_nrtg <- round(pmax(-10.5, pmin(14.0, raw_team_nrtg)), 2)

  list(
    net_rating = round(team_nrtg, 2),
    elo        = team_elo,
    team_rapm  = round(team_rapm, 2),
    rotation   = active_rotation |> select(player_name, position, bpm, allocated_min)
  )
}

# ------------------------------------------------------------------------------
# 3. Single Head-to-Head Matchup Evaluator
# ------------------------------------------------------------------------------
predict_live_matchup <- function(home_team, away_team, active_rosters, player_ratings, elo_ratings, team_rapm_df, injury_df = tibble()) {
  h_res <- compute_team_live_rating(home_team, active_rosters, player_ratings, elo_ratings, team_rapm_df, injury_df)
  a_res <- compute_team_live_rating(away_team, active_rosters, player_ratings, elo_ratings, team_rapm_df, injury_df)

  # FINDING C-1: was the literal `2.40`. Value unchanged — now read from config.R's WNBA_HCA so
  # there is exactly one definition of home-court advantage in the repo (the review found the
  # betting engine had drifted to 11.6 while three other sites still said 2.40).
  hca <- WNBA_HCA

  # Production Model Fusion (Task P3-2.1): Blend Net Rating, Team RAPM, and Elo.
  # We use an equal weight for the two point-based ratings (NetRating and RAPM)
  # and convert the Elo probability to a margin using WNBA_MARGIN_SIGMA.

  rating_diff <- h_res$net_rating - a_res$net_rating
  rapm_diff   <- h_res$team_rapm - a_res$team_rapm

  # Elo Prob -> Margin conversion
  elo_prob    <- 1 / (1 + 10^((a_res$elo - h_res$elo) / 400))
  elo_margin  <- qnorm(elo_prob) * WNBA_MARGIN_SIGMA

  expected_margin <- (0.4 * rating_diff) + (0.4 * rapm_diff) + (0.2 * elo_margin) + hca

  # WNBA_MARGIN_SIGMA (14.0) replaces NBA's hardcoded 11.8 - see config.R for the empirical
  # derivation (sd() of real 2019-2026 WNBA home-team-game margins).
  home_prob <- pnorm(expected_margin / WNBA_MARGIN_SIGMA)
  fair_spread <- -round(expected_margin, 1)

  fair_home_ml <- if_else(home_prob >= 0.50,
                          round(-100 * home_prob / (1 - home_prob)),
                          round(100 * (1 - home_prob) / home_prob))

  tibble(
    Matchup         = paste(away_team, "@", home_team),
    Home_Team       = home_team,
    Away_Team       = away_team,
    Home_Rating     = h_res$net_rating,
    Away_Rating     = a_res$net_rating,
    Diff_Elo       = h_res$elo - a_res$elo,
    Diff_Team_RAPM  = h_res$team_rapm - a_res$team_rapm,
    Proj_Margin     = round(expected_margin, 1),
    Fair_Spread     = fair_spread,
    Home_Win_Prob   = round(home_prob, 3),
    Fair_Home_ML    = fair_home_ml
  )
}

# ------------------------------------------------------------------------------
# 4. Full 15-Team Calibrated Schedule Simulation Matrix (Zero-Sum)
# ------------------------------------------------------------------------------
project_all_wnba_teams <- function() {
  cat("\n==================================================================\n")
  cat("   ALL WNBA TEAMS: ZERO-SUM", WNBA_SEASON_GAMES, "-GAME SCHEDULE SIMULATION      \n")
  cat("==================================================================\n\n")

  roster_file <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  if (!exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE) && !file.exists(roster_file)) stop("Run sync_rosters.R first.")

  active_rosters <- if (exists("GLOBAL_ACTIVE_ROSTERS", inherits = FALSE)) {
    GLOBAL_ACTIVE_ROSTERS
  } else {
    readRDS(roster_file)
  }
  player_ratings <- get_player_bpm_ratings()
  elo_ratings    <- compute_elo_ratings()
  team_rapm_df   <- compute_team_rapm_ratings(active_rosters)

  # Live injury status feeds into rotation-minute haircuts, same as NBA's compute call sites -
  # NBA's project_all_30_teams() never actually passed injury_df through; we deliberately DO
  # here (a small strengthening, not a deviation from anything load-bearing) since T1 already
  # produced a real, validated injury cache and there is no reason to leave standings blind to
  # currently-Out players.
  injury_df <- if (file.exists(CACHE_INJURY_DATA)) readRDS(CACHE_INJURY_DATA) else tibble()

  all_teams <- sort(unique(active_rosters$team_name))
  n_teams <- length(all_teams)

  raw_ratings <- numeric(n_teams)
  top_stars   <- character(n_teams)
  team_elos   <- numeric(n_teams)
  team_rapms  <- numeric(n_teams)

  for (idx in seq_along(all_teams)) {
    t <- all_teams[idx]
    res <- compute_team_live_rating(t, active_rosters, player_ratings, elo_ratings, team_rapm_df, injury_df)
    raw_ratings[idx] <- res$net_rating
    team_elos[idx]   <- res$elo
    team_rapms[idx]  <- res$team_rapm

    stars <- res$rotation |>
      arrange(desc(bpm)) |>
      slice_head(n = 3) |>
      pull(player_name) |>
      paste(collapse = ", ")
    top_stars[idx] <- stars
  }

  # Center League Net Ratings at Exactly 0.00
  league_mu <- mean(raw_ratings)
  true_net_ratings <- round(raw_ratings - league_mu, 2)

  team_df <- tibble(
    Team        = all_teams,
    True_NRtg   = true_net_ratings,
    Elo         = team_elos,
    Team_RAPM   = team_rapms,
    Top_Stars   = top_stars
  )

  # Round-Robin Schedule Simulation Matrix (WNBA_SEASON_GAMES games/team, half home/half away)
  hca <- WNBA_HCA   # FINDING C-1: centralized in config.R (was the literal 2.40).
  sigma <- WNBA_MARGIN_SIGMA
  games_per_opponent <- WNBA_SEASON_GAMES / (n_teams - 1)

  expected_wins <- numeric(n_teams)

  for (i in seq_along(all_teams)) {
    team_i_wins <- 0
    for (j in seq_along(all_teams)) {
      if (i == j) next

      # Production Model Fusion (Task P3-2.1)
      rating_diff <- true_net_ratings[i] - true_net_ratings[j]
      rapm_diff   <- team_rapms[i] - team_rapms[j]
      elo_prob    <- 1 / (1 + 10^((team_elos[j] - team_elos[i]) / 400))
      elo_margin  <- qnorm(elo_prob) * sigma

      margin_home <- (0.4 * rating_diff) + (0.4 * rapm_diff) + (0.2 * elo_margin) + hca
      p_win_home  <- pnorm(margin_home / sigma)

      margin_away <- (0.4 * (true_net_ratings[i] - true_net_ratings[j])) + (0.4 * (team_rapms[i] - team_rapms[j])) + (0.2 * (qnorm(1 - elo_prob) * sigma)) - hca
      p_win_away  <- pnorm(margin_away / sigma)

      team_i_wins <- team_i_wins + (0.5 * p_win_home + 0.5 * p_win_away) * games_per_opponent
    }
    expected_wins[i] <- round(team_i_wins, 1)
  }

  team_df <- team_df |>
    mutate(
      Proj_Wins   = expected_wins,
      Proj_Losses = round(WNBA_SEASON_GAMES - Proj_Wins, 1),
      # FINDING M-8 (docs/SECURITY_TECHNICAL_REVIEW.md): this was
      #   paste0(round((Proj_Wins / WNBA_SEASON_GAMES) * 100, 1), "%")
      # i.e. a presentation-formatted string ("79.3%") persisted into a cache that is an INPUT to
      # app.R, market_odds_engine.R and playoff_simulator.R. Any consumer treating it numerically
      # got silent NAs from as.numeric(). Caches stay typed for computation; percent formatting is
      # done at display time by app.R (scales::percent()), per the Phase 4 interface contract.
      Win_Pct     = round(Proj_Wins / WNBA_SEASON_GAMES, 4)
    ) |>
    arrange(desc(Proj_Wins)) |>
    mutate(Rank = row_number()) |>
    select(Rank, Team, Net_Rating = True_NRtg, Proj_Wins, Proj_Losses, Win_Pct, Top_Core_Players = Top_Stars)

  # Console preview only — Win_Pct is percent-formatted for THIS printout, never for the cache
  # (M-8): the saved team_df below keeps the numeric proportion.
  print(knitr::kable(
    team_df |> mutate(Win_Pct = sprintf("%.1f%%", Win_Pct * 100)),
    format = "simple"
  ))

  # Zero-sum invariant for a round-robin schedule: total league wins == total league games
  # played == WNBA_SEASON_GAMES * n_teams / 2 (each game has exactly one winner), NOT the NBA
  # invariant of 1230/2 == 615.
  expected_total_wins <- WNBA_SEASON_GAMES * n_teams / 2
  cat(sprintf(
    "\n[AUDIT] Total League Wins: %.1f / %.1f (League Average: %.1f wins)\n",
    sum(team_df$Proj_Wins), expected_total_wins, mean(team_df$Proj_Wins)
  ))

  # WNBA-specific output filename (NOT the NBA name `projected_30_team_standings.rds`) - per
  # the plan's explicit recommendation, to avoid any downstream script accidentally reading
  # the wrong league's standings. T4 (market/props) and T5 (live/dashboard) must read this
  # exact path: cache/projected_wnba_standings.rds
  out_path <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  saveRDS(team_df, out_path)
  cat(sprintf("[CACHE] Standings saved to: %s\n\n", out_path))

  return(team_df)
}

# ------------------------------------------------------------------------------
# 5. Universal Point Spread & Win Probability Query Tool
# ------------------------------------------------------------------------------
get_fair_spread <- function(home_team, away_team) {
  standings_file <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  if (!file.exists(standings_file)) project_all_wnba_teams()

  standings <- readRDS(standings_file)

  h_row <- standings |> filter(Team == home_team)
  a_row <- standings |> filter(Team == away_team)

  if (nrow(h_row) == 0 || nrow(a_row) == 0) {
    stop("Team not found. Please verify spelling against active rosters.")
  }

  # Use the same blended model as predict_live_matchup / project_all_wnba_teams
  hca <- WNBA_HCA   # FINDING C-1: centralized in config.R (was the literal 2.40).
  sigma <- WNBA_MARGIN_SIGMA

  rating_diff <- h_row$Net_Rating - a_row$Net_Rating
  rapm_diff   <- h_row$Team_RAPM - a_row$Team_RAPM
  elo_prob    <- 1 / (1 + 10^((a_row$Elo - h_row$Elo) / 400))
  elo_margin  <- qnorm(elo_prob) * sigma

  margin <- (0.4 * rating_diff) + (0.4 * rapm_diff) + (0.2 * elo_margin) + hca
  spread <- -round(margin, 1)
  win_prob <- round(pnorm(margin / sigma), 3)

  cat(sprintf("\nWNBA MATCHUP: %s (Away) @ %s (Home)\n", away_team, home_team))
  cat(sprintf("   Rating -> %s: %+0.2f | %s: %+0.2f\n", home_team, h_row$Net_Rating, away_team, a_row$Net_Rating))
  cat(sprintf("   Projected Margin: %+0.1f points to %s\n", margin, home_team))
  cat(sprintf("   Fair Vegas Spread: %s %s%0.1f\n", home_team, ifelse(spread > 0, "+", ""), spread))
  cat(sprintf("   Fair Win Probability: %s %.1f%% | %s %.1f%%\n\n",
              home_team, win_prob * 100, away_team, (1 - win_prob) * 100))
}

# Auto-execute simulation when run non-interactively.
# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md): the original guard was `sys.nframe() == 0`,
# intended to stop `source()` callers triggering a full simulation as a side effect. It did that
# far too well: run_full_pipeline.R's run_stage() ALSO source()s this file (from inside a
# function), so sys.nframe() was never 0 and the single most load-bearing script in the repo was
# a silent no-op — cache/projected_wnba_standings.rds went unchanged for four days while the
# stage logged "[COMPLETED] roster_bottom_up_engine.R in 0.05 seconds".
# `!interactive()` preserves the original intent for the case that actually matters (an analyst
# source()ing this in RStudio still gets only the function definitions) while letting the
# non-interactive pipeline run it. Note this also un-masks H-2 below (the RAPM join), which is
# why that is fixed in the same pass, exactly as the review recommends.
if (!interactive()) {
  project_all_wnba_teams()
}
