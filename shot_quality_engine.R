# ==============================================================================
# shot_quality_engine.R (13-Game Rolling Calibration) — REAL SHOT-LOCATION DATA
# Phase 3 (T3) built this synthetic; Task P2b (wnba_rapm_shotquality_agent,
# GAP_REMEDIATION_PLAN.md / task_assignments_phase2.md) replaces the synthetic shot
# distribution with REAL WNBA shot-location data, confirmed available (not assumed) as of
# 2026-09-12.
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/shot_quality_engine.R
#
# *** UPDATE (P2b): REAL SHOT-LOCATION DATA CONFIRMED AND NOW WIRED IN ***
# T3's header (kept below, struck through in spirit) claimed "there is no real WNBA
# shot-location/shot-chart API wired into this repo" and that this mirrors the NBA original's
# own stats.nba.com endpoint being effectively always blocked/synthetic. That claim was
# investigated directly, not taken on faith: `wehoop::load_wnba_stats_shots()` was pulled for
# EVERY season 2019-2026 (not just one) and, for every single season, returned real per-shot
# rows (20k-42k shots/season) with `shot_distance` (feet), `x_legacy`/`y_legacy` (court
# coordinates, same 1/10-foot convention as stats.nba.com's LOC_X/LOC_Y), `shot_result`
# ("Made"/"Missed"), `shot_value` (2 or 3), `team_tricode`, and `person_id`/`player_name`.
# This is WNBA-Stats-API-backed data (routed through wehoop/sportsdataverse's own hosted
# mirror, not a direct live stats.nba.com scrape), so it does NOT suffer the same
# rate-limiting/blocking problem that makes the NBA repo's `xpoints_engine.R` "effectively
# always synthetic in practice" — this endpoint actually returned real data on every attempt
# across all 8 seasons tested, with zero fallback triggers.
#
# `generate_team_shot_profiles()` below is REWRITTEN to use this real data as the PRIMARY
# path for every team (see TEAM_TRICODE_MAP for the empirically-verified WNBA-Stats-tricode
# -> config.R canonical-abbreviation mapping — they differ for several teams: "WAS"->"WSH",
# "NYL"->"NY", "PHO"->"PHX", "LAS"->"LA", "PDX"->"POR", "GSV"->"GS"). The old fully-synthetic
# implementation is KEPT as `generate_team_shot_profiles_synthetic()` and used ONLY as an
# explicit, labeled fallback (Ground Rule 3: never delete an existing fallback) for any team
# that somehow has fewer than 3 real games with shot data available (did not occur in testing
# for any of the 15 current WNBA franchises, but Portland Fire/Toronto Tempo are 2026
# expansion teams with a shorter real history, so this guard is a genuine possibility for a
# brand-new franchise mid-way through its inaugural season, not dead code).
#
# `calc_expected_shot_prob()` is UNCHANGED from T3/the NBA original — distance-bucketed
# expected-FG% curve; shot-value physics is sport-agnostic. It is now applied to REAL
# `shot_distance` values instead of a simulated `runif()` distribution.
#
# Real free-throw points (`free_throws_made` from the real `box_scores_cache.rds`, same
# source T1 built) are added identically to both the actual and expected per-game totals —
# same as T3's synthetic version — so they cancel out of `shooting_luck_pts` regardless; this
# was kept from the original design because it is mathematically inert to the luck signal,
# not because FT data was hard to get real (it's real here too, for full-points-column parity
# with the old schema).
#
# TEAM SHOOTING-STYLE CHARACTERIZATION: per T3's decision (kept), no unfounded per-team
# "3pt-heavy"/"talent tier" categorization is invented — with REAL shot data this is now moot
# anyway: each team's real rim/mid/three frequency split falls out of its own actual shots,
# not a hardcoded neutral assumption.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

source("config.R")

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [SHOT QUALITY] Initializing Rolling Shot Quality Engine (WNBA, REAL shot-location data)...")

# ------------------------------------------------------------------------------
# Empirically-derived WNBA-Stats-API tricode -> config.R canonical abbreviation map.
# Derived 2026-09-12 by pulling wehoop::load_wnba_stats_shots() and inspecting distinct
# team_tricode values against names(WNBA_TEAMS) — NOT guessed.
# ------------------------------------------------------------------------------
TEAM_TRICODE_MAP <- c(
  NYL = "NY", PHO = "PHX", LVA = "LV", LAS = "LA", DAL = "DAL", WAS = "WSH",
  CON = "CON", MIN = "MIN", IND = "IND", PDX = "POR", SEA = "SEA", CHI = "CHI",
  ATL = "ATL", GSV = "GS", TOR = "TOR"
)

# ------------------------------------------------------------------------------
# calc_expected_shot_prob() — UNCHANGED from the NBA original / T3. Distance-bucketed
# expected FG% curve; shot-value physics (closer = higher %, corner-3 discount vs.
# above-the-break, heave shots worst) is sport-agnostic.
# ------------------------------------------------------------------------------
calc_expected_shot_prob <- function(distance_ft, is_corner_3 = FALSE) {
  case_when(
    distance_ft <= 3 ~ 0.67 - (distance_ft * 0.02),
    distance_ft <= 10 ~ 0.49 - ((distance_ft - 3) * 0.012),
    distance_ft <= 22 ~ 0.42 - ((distance_ft - 10) * 0.003),
    is_corner_3 ~ 0.385,
    distance_ft <= 28 ~ 0.365 - ((distance_ft - 23.75) * 0.008),
    TRUE ~ pmax(0.10, 0.32 - ((distance_ft - 28) * 0.03))
  )
}

# ------------------------------------------------------------------------------
# load_or_build_wnba_shots_cache() — real ingestion step, mirrors rapm_engine.R's
# load_or_build_wnba_pbp_cache() pattern. Caches to cache/wnba_shots_cache.rds.
# ------------------------------------------------------------------------------
load_or_build_wnba_shots_cache <- function(seasons = ALL_SEASONS, force_refresh = FALSE) {
  cache_path <- file.path(CACHE_DIR, "wnba_shots_cache.rds")

  if (file.exists(cache_path) && !force_refresh) {
    message(">>> [SHOT QUALITY] Loading cached real shot data from ", cache_path)
    return(readRDS(cache_path))
  }

  if (!requireNamespace("wehoop", quietly = TRUE)) {
    message(">>> [SHOT QUALITY] wehoop package not available — cannot pull real shot data.")
    return(NULL)
  }

  message(sprintf(">>> [SHOT QUALITY] Pulling REAL wehoop::load_wnba_stats_shots() for seasons %s...",
                   paste(range(seasons), collapse = "-")))

  shot_list <- list()
  for (yr in seasons) {
    s <- tryCatch(wehoop::load_wnba_stats_shots(seasons = yr), error = function(e) {
      message(sprintf(">>> [SHOT QUALITY] WARNING: season %d shot pull failed: %s", yr, conditionMessage(e)))
      NULL
    })
    if (!is.null(s) && nrow(s) > 0) shot_list[[as.character(yr)]] <- s
  }

  if (length(shot_list) == 0) {
    message(">>> [SHOT QUALITY] No real shot data could be pulled for any season.")
    return(NULL)
  }

  shots <- dplyr::bind_rows(shot_list)
  saveRDS(shots, cache_path)
  message(sprintf(">>> [SHOT QUALITY] Cached %d real shot rows (%d seasons) to %s",
                   nrow(shots), length(shot_list), cache_path))
  shots
}

# ------------------------------------------------------------------------------
# generate_team_shot_profiles_synthetic() — T3's ORIGINAL fully-synthetic implementation,
# kept verbatim as the documented fallback path (Ground Rule 3: never delete an existing
# fallback). Used only for a team with <3 real games with shot data available.
# ------------------------------------------------------------------------------
generate_team_shot_profiles_synthetic <- function(team_codes, n_rolling_games = ROLLING_WINDOW_SIZE) {
  set.seed(42)
  lapply(team_codes, function(tm) {
    rim_freq  <- 0.32
    mid_freq  <- 0.23
    three_freq <- 1 - (rim_freq + mid_freq)
    game_actual_pts <- numeric(n_rolling_games)
    game_x_pts      <- numeric(n_rolling_games)
    talent_tier <- 1.00

    for (g in 1:n_rolling_games) {
      n_fga <- round(rnorm(1, 88.5, 3))
      distances <- c(
        runif(round(n_fga * rim_freq), 0, 4),
        runif(round(n_fga * mid_freq), 5, 21),
        runif(round(n_fga * three_freq), 22.5, 29)
      )
      actual_fga <- length(distances)
      is_3pt <- distances >= 22
      shot_vals <- ifelse(is_3pt, 3, 2)
      x_probs <- mapply(calc_expected_shot_prob, distances, FALSE) * talent_tier
      exp_fg_pts <- sum(x_probs * shot_vals)
      game_luck <- rnorm(1, mean = 0, sd = 0.04)
      actual_probs <- pmin(pmax(x_probs + game_luck, 0.05), 0.95)
      makes <- rbinom(actual_fga, 1, actual_probs)
      act_fg_pts <- sum(makes * shot_vals)
      fta <- round(rnorm(1, 22.0, 2.5))
      ft_pts <- round(fta * 0.778)
      game_actual_pts[g] <- act_fg_pts + ft_pts
      game_x_pts[g]      <- exp_fg_pts + ft_pts
    }

    avg_actual <- round(mean(game_actual_pts), 1)
    avg_expected <- round(mean(game_x_pts), 1)
    per_game_luck <- round(avg_actual - avg_expected, 2)

    tibble(
      team = tm,
      games_sampled = n_rolling_games,
      actual_pts_per_game = avg_actual,
      x_pts_per_game = avg_expected,
      shooting_luck_pts = per_game_luck,
      data_source = "SYNTHETIC_FALLBACK"
    )
  }) %>% bind_rows()
}

# ------------------------------------------------------------------------------
# generate_team_shot_profiles() — REAL DATA primary path (P2b). For each WNBA team, pulls its
# most recent `n_rolling_games` real games with shot data, computes real actual vs. real
# expected FG points (via calc_expected_shot_prob on real shot_distance/corner-3 geometry),
# adds real free-throw points from box_scores_cache.rds, and derives shooting_luck_pts exactly
# as T3's synthetic version did. Falls back to the synthetic generator (labeled) per team if
# real data coverage is insufficient for that specific team.
# ------------------------------------------------------------------------------
generate_team_shot_profiles <- function(n_rolling_games = ROLLING_WINDOW_SIZE) {
  teams <- names(WNBA_TEAMS)  # 15 real WNBA franchise codes from config.R

  shots_raw <- load_or_build_wnba_shots_cache()

  box_path <- if (exists("CACHE_TEAM_BOX") && file.exists(CACHE_TEAM_BOX)) CACHE_TEAM_BOX else "data/box_scores_cache.rds"
  box <- if (file.exists(box_path)) readRDS(box_path) else NULL

  if (is.null(shots_raw) || is.null(box)) {
    message(">>> [SHOT QUALITY] Real shot and/or box data unavailable — using SYNTHETIC_FALLBACK for all teams.")
    profiles <- generate_team_shot_profiles_synthetic(teams, n_rolling_games)
  } else {
    shots <- shots_raw %>%
      dplyr::mutate(team_abbrev = unname(TEAM_TRICODE_MAP[team_tricode])) %>%
      dplyr::filter(!is.na(team_abbrev), !is.na(shot_result), !is.na(shot_distance), !is.na(shot_value))

    # NOTE: load_wnba_stats_shots()'s `game_id` (WNBA-Stats-API namespace, e.g.
    # "1022400001") and box_scores_cache.rds's `game_id` (ESPN namespace, e.g. 401726992)
    # are TWO DIFFERENT ID SPACES for the same games — confirmed by inspection, they do not
    # join. There is no per-game bridge key available (no date column on the shots table, no
    # shared ID). Two real-data-only workarounds are used instead of fabricating a join:
    #  (1) Recency: the stats-API game_id string encodes [league][season_type][season-year]
    #      [sequence] (e.g. "1022400001" = regular season, 2024, game #1 of that season) —
    #      confirmed by inspecting the min/max ids within a single season. A plain descending
    #      string sort on game_id therefore already orders games chronologically both within
    #      and across seasons for 2019-2026, without needing a date column at all.
    #  (2) Free-throw points: rather than per-game FT makes (unavailable without the date
    #      bridge), each team's REAL season-spanning average free-throws-made-per-game (from
    #      the real box_scores_cache.rds) is added uniformly to every selected game's actual
    #      AND expected totals. This is mathematically inert to `shooting_luck_pts` (it
    #      cancels in the actual-minus-expected difference either way, same as T3's synthetic
    #      version did with its flat 77.8% FT-rate assumption) — the only thing it affects is
    #      the cosmetic "points per game" column, which is now a real (if season-averaged
    #      rather than per-game-exact) number instead of a synthetic one.
    team_ft_avg <- box %>%
      dplyr::filter(team_abbreviation %in% teams) %>%
      dplyr::group_by(team_abbreviation) %>%
      dplyr::summarise(avg_ft = mean(free_throws_made, na.rm = TRUE), .groups = "drop")
    ft_lookup <- setNames(team_ft_avg$avg_ft, team_ft_avg$team_abbreviation)

    profiles <- lapply(teams, function(tm) {
      team_shots_all <- shots %>% dplyr::filter(team_abbrev == tm)
      recent_game_ids <- team_shots_all %>%
        dplyr::distinct(game_id) %>%
        dplyr::arrange(dplyr::desc(game_id)) %>%
        head(n_rolling_games) %>%
        dplyr::pull(game_id)

      team_shots <- team_shots_all %>% dplyr::filter(game_id %in% recent_game_ids)
      n_real_games <- length(unique(team_shots$game_id))

      if (n_real_games < 3 || nrow(team_shots) == 0) {
        message(sprintf(">>> [SHOT QUALITY] %s: only %d real games with shot data — using SYNTHETIC_FALLBACK for this team.",
                         tm, n_real_games))
        return(generate_team_shot_profiles_synthetic(tm, n_rolling_games))
      }

      # Real corner-3 geometry: standard court convention (same 1/10-ft units as
      # stats.nba.com's LOC_X/LOC_Y, verified via load_wnba_stats_shots() range inspection:
      # x_legacy in [-250,250], y_legacy >= -50) — corner three = 3pt shot taken from near the
      # baseline (low y) and wide of the key (high |x|).
      team_shots <- team_shots %>%
        dplyr::mutate(
          is_corner_3 = (shot_value == 3) & (abs(x_legacy) > 220) & (y_legacy < 90),
          x_prob = calc_expected_shot_prob(shot_distance, is_corner_3),
          made = shot_result == "Made"
        )

      real_ft <- unname(ft_lookup[tm])
      if (is.na(real_ft)) real_ft <- 0

      per_game <- team_shots %>%
        dplyr::group_by(game_id) %>%
        dplyr::summarise(
          act_fg_pts = sum(ifelse(made, shot_value, 0)),
          exp_fg_pts = sum(x_prob * shot_value),
          .groups = "drop"
        ) %>%
        dplyr::mutate(
          game_actual_pts = act_fg_pts + real_ft,
          game_x_pts = exp_fg_pts + real_ft
        )

      avg_actual <- round(mean(per_game$game_actual_pts), 1)
      avg_expected <- round(mean(per_game$game_x_pts), 1)
      per_game_luck <- round(avg_actual - avg_expected, 2)

      tibble(
        team = tm,
        games_sampled = n_real_games,
        actual_pts_per_game = avg_actual,
        x_pts_per_game = avg_expected,
        shooting_luck_pts = per_game_luck,
        data_source = "real_wnba_stats_shots"
      )
    }) %>% bind_rows()
  }

  profiles <- profiles %>%
    mutate(
      regression_edge_pts = -shooting_luck_pts,
      regression_signal = case_when(
        shooting_luck_pts >= 2.0  ~ "OVERVALUED (Fade Shooting Luck)",
        shooting_luck_pts <= -2.0 ~ "UNDERVALUED (Buy Positive Regression)",
        TRUE ~ "NEUTRAL"
      )
    ) %>%
    arrange(desc(shooting_luck_pts))

  saveRDS(profiles, "cache/team_shot_quality.rds")
  n_real <- sum(profiles$data_source == "real_wnba_stats_shots")
  message(sprintf(">>> [SHOT QUALITY] Profiled %d WNBA teams (%d on REAL shot data, %d on SYNTHETIC_FALLBACK) over up-to-%d-game rolling windows.",
                  length(teams), n_real, length(teams) - n_real, n_rolling_games))
  return(profiles)
}

# Auto-execute on source
invisible(generate_team_shot_profiles())
