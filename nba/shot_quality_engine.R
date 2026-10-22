# ==============================================================================
# shot_quality_engine.R (15-Game Rolling Calibration)
# Phase 5: Spatial Shot Quality (xeFG%) & Luck-Adjusted Net Rating Engine
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (file.exists("config.R")) source("config.R")
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [SHOT QUALITY] Initializing 15-Game Rolling Shot Quality Engine...")

.cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else "cache"
.current_season <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2027

# Early in a season the current-year sample is only a handful of games. Mixing those
# rows into a 15-game rolling window still leaves the estimate dominated by the prior
# season, but makes the displayed provenance ambiguous. Require a meaningful sample
# before treating the projected season as usable; otherwise fall back cleanly to the
# last completed season and label it as such.
MIN_CURRENT_SEASON_GAMES <- 10L

# Synthetic shot distributions are opt-in only. Without real shot data this engine
# fails loudly rather than writing invented profiles that read as model output
# downstream (season_simulator.R ingests regression_edge_pts with no provenance check).
ALLOW_SYNTHETIC_SHOT_QUALITY <- isTRUE(as.logical(
  Sys.getenv("ALLOW_SYNTHETIC_SHOT_QUALITY", "FALSE")
))

# ESPN abbreviations -> project team codes (same mapping as season_simulator.R)
ESPN_ABBR_FIXUPS <- c(GS = "GSW", SA = "SAS", NY = "NYK", UTAH = "UTA",
                      NO = "NOP", WSH = "WAS")
# All-Star rosters appear in the shot feed and are not NBA teams. The exhibition
# format has been renamed repeatedly (EAST/WEST, then STARS/STRIPES, then USA/WORLD),
# so this list is matched after the abbreviation fixups are applied.
NON_TEAM_ABBRS <- c("EAST", "WEST", "USA", "WORLD", "STARS", "STRIPES",
                    "OWN", "GLOBAL", "RISING")

# Parametric prior on make probability by distance. This is the hand-written curve
# the engine shipped with; it is retained only as the baseline for distance bins the
# real sample covers too thinly to estimate directly (see build_xfg_baseline).
# It is NOT the primary expected-value model: measured against real 2026/2027 shot
# locations it under-predicts makes by roughly 4 points per team-game, which would
# turn `shooting_luck_pts` into a biased quantity rather than a residual.
calc_expected_shot_prob <- function(distance_ft, is_corner_3 = FALSE) {
  # Corner 3s are ~22.0 ft from the hoop, so this branch must be tested before the
  # `distance_ft <= 22` mid-range branch or it can never be reached.
  case_when(
    is_corner_3 ~ 0.385,
    distance_ft <= 3 ~ 0.67 - (distance_ft * 0.02),
    distance_ft <= 10 ~ 0.49 - ((distance_ft - 3) * 0.012),
    distance_ft <= 22 ~ 0.42 - ((distance_ft - 10) * 0.003),
    distance_ft <= 28 ~ 0.365 - ((distance_ft - 23.75) * 0.008),
    TRUE ~ pmax(0.10, 0.32 - ((distance_ft - 28) * 0.03))
  )
}

# Empirical league-average make probability by (1 ft distance bin x corner-3 flag),
# estimated from the pooled real sample. Expected points for a shot are then
# "what the league as a whole converts from this spot", so actual - expected is
# shot-making relative to league average given location, centered near zero by
# construction. Bins with thin support fall back to the parametric prior above.
MIN_BIN_ATTEMPTS <- 200

build_xfg_baseline <- function(fga) {
  fga %>%
    group_by(dist_bin, is_corner_3) %>%
    summarise(bin_fga = n(), bin_fgm = sum(made, na.rm = TRUE), .groups = "drop") %>%
    mutate(
      bin_fg_pct = bin_fgm / bin_fga,
      prior_pct = calc_expected_shot_prob(dist_bin, is_corner_3),
      x_prob_bin = ifelse(bin_fga >= MIN_BIN_ATTEMPTS, bin_fg_pct, prior_pct)
    )
}

# ------------------------------------------------------------------------------
# Real shot-location ingestion
# ------------------------------------------------------------------------------
# Resolution order:
#   1. cache/shot_locations.rds        (explicit override, if an operator supplies one)
#   2. cache/nba_shots_<season>.rds    (already-cached hoopR pulls, newest first)
#   3. hoopR::load_nba_shots()         (fetch and cache)
# A 15-game rolling window needs the current season plus the prior one as backfill,
# since early in a season the current one has too few games.
load_real_shots <- function(seasons) {
  override <- file.path(.cache_dir, "shot_locations.rds")
  if (file.exists(override)) {
    shots <- tryCatch(readRDS(override), error = function(e) NULL)
    if (!is.null(shots) && nrow(shots) > 0) {
      message(sprintf(">>> [SHOT QUALITY] Loaded %s shot records from %s.",
                      format(nrow(shots), big.mark = ","), override))
      return(list(data = as.data.frame(shots), source = "shot_locations.rds"))
    }
    message(sprintf(">>> [WARN] '%s' exists but is empty or unreadable; falling through.", override))
  }

  frames <- list()
  used <- character(0)
  for (sn in seasons) {
    season_cache <- file.path(.cache_dir, sprintf("nba_shots_%d.rds", sn))
    got <- NULL
    if (file.exists(season_cache)) {
      got <- tryCatch(readRDS(season_cache), error = function(e) NULL)
      if (!is.null(got) && nrow(got) > 0) {
        message(sprintf(">>> [SHOT QUALITY] Loaded season %d from cache (%s records).",
                        sn, format(nrow(got), big.mark = ",")))
        used <- c(used, sprintf("nba_shots_%d.rds", sn))
      } else {
        got <- NULL
      }
    }
    if (is.null(got)) {
      message(sprintf(">>> [SHOT QUALITY] Fetching season %d shot records via hoopR...", sn))
      got <- tryCatch(
        {
          s <- hoopR::load_nba_shots(seasons = sn)
          if (!is.null(s) && nrow(s) > 0) saveRDS(s, season_cache)
          s
        },
        error = function(e) {
          message(sprintf(">>> [WARN] hoopR fetch failed for season %d: %s", sn, conditionMessage(e)))
          NULL
        }
      )
      if (!is.null(got) && nrow(got) > 0) used <- c(used, sprintf("hoopR season %d", sn))
    }
    if (!is.null(got) && nrow(got) > 0) frames[[length(frames) + 1]] <- as.data.frame(got)
  }

  if (length(frames) == 0) return(NULL)
  list(data = bind_rows(frames), source = paste(used, collapse = " + "))
}

# ------------------------------------------------------------------------------
# Field-goal attempt table
# ------------------------------------------------------------------------------
# Court transform matches build_shot_chart_dataset.R: ESPN raw y is measured from the
# backboard plane, regulation half-court measures from the baseline 4.0 ft behind it.
prepare_fga <- function(shots) {
  shots %>%
    filter(!is.na(athlete_id_1), score_value %in% c(0, 2, 3) | scoring_play) %>%
    filter(!grepl("Free Throw", type_text, ignore.case = TRUE)) %>%
    mutate(
      team = recode(as.character(team_abbrev), !!!as.list(ESPN_ABBR_FIXUPS)),
      x = round(coordinate_x_raw - 25.0, 1),
      y = round(pmax(0, pmin(47, coordinate_y_raw + 4.0)), 1),
      dist = round(sqrt(x^2 + (y - 5.25)^2), 1),
      made = as.logical(scoring_play),
      val = ifelse(score_value == 3 | dist >= 23.5, 3, 2),
      # Corner 3: beyond the 22 ft corner line and below where the arc begins (y = 14)
      is_corner_3 = val == 3 & abs(x) >= 22 & y <= 14,
      dist_bin = pmin(40, floor(dist))
    ) %>%
    filter(!team %in% NON_TEAM_ABBRS, !is.na(dist), dist <= 40)
}

# Real free-throw points per team-game. FT points are added identically to the actual
# and expected columns, so they cancel out of shooting_luck_pts exactly as in the
# previous revision -- the luck term stays purely field-goal based.
prepare_ft <- function(shots) {
  shots %>%
    filter(grepl("Free Throw", type_text, ignore.case = TRUE)) %>%
    mutate(team = recode(as.character(team_abbrev), !!!as.list(ESPN_ABBR_FIXUPS))) %>%
    filter(!team %in% NON_TEAM_ABBRS) %>%
    group_by(team, game_id) %>%
    summarise(ft_pts = sum(as.logical(scoring_play), na.rm = TRUE), .groups = "drop")
}

# ------------------------------------------------------------------------------
# Rolling-window profiles
# ------------------------------------------------------------------------------
generate_team_shot_profiles <- function(n_rolling_games = 15) {
  seasons <- c(.current_season, .current_season - 1)
  real <- load_real_shots(seasons)

  if (is.null(real)) {
    msg <- sprintf(paste0(
      "No real shot data available (tried %s/shot_locations.rds, cached nba_shots_<season>.rds ",
      "for seasons %s, and a hoopR fetch). Refusing to write synthetic shot profiles: ",
      "season_simulator.R consumes team_shot_quality.rds as if it were observed. ",
      "Set ALLOW_SYNTHETIC_SHOT_QUALITY=TRUE to override for offline testing."),
      .cache_dir, paste(seasons, collapse = ", "))
    if (!ALLOW_SYNTHETIC_SHOT_QUALITY) stop(msg)
    message(">>> [WARN] ", msg)
    return(generate_synthetic_shot_profiles(n_rolling_games))
  }

  shots <- real$data

  # Fall back to the last completed season when the projected season's sample is
  # still too small to stand on its own. The rolling window would otherwise be
  # mostly prior-season games while still claiming a current-season span.
  current_games <- if (all(c("season", "game_id") %in% names(shots))) {
    length(unique(shots$game_id[shots$season == .current_season]))
  } else {
    0L
  }
  if (current_games < MIN_CURRENT_SEASON_GAMES) {
    prior <- shots[shots$season < .current_season, , drop = FALSE]
    if (nrow(prior) == 0) {
      stop(sprintf(paste0(
        "Only %d game(s) observed in season %d and no prior-season shot rows are ",
        "available to fall back to. Refusing to label a partial sample as a full season."),
        current_games, .current_season))
    }
    message(sprintf(
      ">>> [SHOT QUALITY] Only %d game(s) observed in %d; need %d. Falling back to the last completed season (%d).",
      current_games, .current_season, MIN_CURRENT_SEASON_GAMES, .current_season - 1L))
    shots <- prior
    real$source <- paste0(real$source, " (fallback: current-season sample too small)")
  }

  fga <- prepare_fga(shots)
  ft <- prepare_ft(shots)

  if (nrow(fga) == 0) stop("Shot source loaded but produced zero field-goal attempts after filtering.")

  # League-average conversion by location, estimated on the pooled real sample
  baseline <- build_xfg_baseline(fga)
  n_prior_bins <- sum(baseline$bin_fga < MIN_BIN_ATTEMPTS)
  fga <- fga %>%
    left_join(baseline %>% select(dist_bin, is_corner_3, x_prob_bin),
              by = c("dist_bin", "is_corner_3")) %>%
    mutate(x_prob = coalesce(x_prob_bin, calc_expected_shot_prob(dist, is_corner_3)))

  message(sprintf(
    ">>> [SHOT QUALITY] xeFG baseline fit on %s real FGA across %d location bins (%d thin bins fell back to the parametric prior).",
    format(nrow(fga), big.mark = ","), nrow(baseline), n_prior_bins))

  # Per team-game actual vs expected field-goal points
  team_games <- fga %>%
    group_by(team, season, game_id) %>%
    summarise(
      fga = n(),
      act_fg_pts = sum(made * val, na.rm = TRUE),
      x_fg_pts = sum(x_prob * val, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    left_join(ft, by = c("team", "game_id")) %>%
    mutate(ft_pts = coalesce(ft_pts, 0))

  # game_id is monotonically increasing with date in the ESPN feed, so it orders a
  # team's schedule without needing a game_date column (the shot feed has none).
  recent <- team_games %>%
    arrange(team, desc(season), desc(as.numeric(game_id))) %>%
    group_by(team) %>%
    slice_head(n = n_rolling_games) %>%
    ungroup()

  sampled_seasons <- sort(unique(recent$season))
  season_label_text <- paste(
    sprintf("%d-%d", sampled_seasons - 1L, sampled_seasons),
    collapse = " + "
  )

  shot_profiles <- recent %>%
    group_by(team) %>%
    summarise(
      games_sampled = n(),
      current_season_games = sum(season == .current_season),
      fga_per_game = round(mean(fga), 1),
      actual_pts_per_game = round(mean(act_fg_pts + ft_pts), 1),
      x_pts_per_game = round(mean(x_fg_pts + ft_pts), 1),
      .groups = "drop"
    ) %>%
    mutate(
      shooting_luck_pts = round(actual_pts_per_game - x_pts_per_game, 2),
      regression_edge_pts = -shooting_luck_pts,
      regression_signal = case_when(
        shooting_luck_pts >= 2.0  ~ "OVERVALUED (Fade Shooting Luck)",
        shooting_luck_pts <= -2.0 ~ "UNDERVALUED (Buy Positive Regression)",
        TRUE ~ "NEUTRAL"
      ),
      data_source = real$source,
      xfg_method = "empirical_league_baseline",
      source_seasons = paste(sort(unique(recent$season)), collapse = "+"),
      season_label = season_label_text,
      generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ) %>%
    arrange(desc(shooting_luck_pts))

  out_path <- file.path(.cache_dir, "team_shot_quality.rds")
  saveRDS(shot_profiles, out_path)
  message(sprintf(
    ">>> [SHOT QUALITY] Profiled %d teams over %d-game rolling windows from %s (seasons %s; %d of the sampled games are %d).",
    nrow(shot_profiles), n_rolling_games, real$source,
    shot_profiles$source_seasons[1], sum(recent$season == .current_season), .current_season))
  # Sanity check: against a league-average baseline the cross-team mean residual
  # should sit near zero. A large offset means the baseline is mis-calibrated and
  # regression_edge_pts is carrying bias into season_simulator.R's Variant 3.
  message(sprintf(
    ">>> [SHOT QUALITY] League residual check: mean %+.2f pts/gm, sd %.2f, range %+.1f to %+.1f.",
    mean(shot_profiles$shooting_luck_pts), sd(shot_profiles$shooting_luck_pts),
    min(shot_profiles$shooting_luck_pts), max(shot_profiles$shooting_luck_pts)))
  return(shot_profiles)
}

# ------------------------------------------------------------------------------
# Synthetic profiles (opt-in only -- see ALLOW_SYNTHETIC_SHOT_QUALITY)
# ------------------------------------------------------------------------------
generate_synthetic_shot_profiles <- function(n_rolling_games = 15) {
  message(sprintf(">>> [WARN] Using SYNTHETIC_FALLBACK: simulating %d-game shot distributions for 30 teams.", n_rolling_games))

  teams <- c("BOS", "OKC", "DEN", "MIN", "NYK", "MIL", "PHI", "CLE", "IND", "DAL",
             "PHX", "LAC", "NOP", "LAL", "GSW", "SAC", "MIA", "ORL", "HOU", "CHI",
             "ATL", "MEM", "BKN", "TOR", "UTA", "SAS", "POR", "CHA", "DET", "WAS")

  set.seed(42)

  shot_profiles <- lapply(teams, function(tm) {
    is_3pt_heavy <- tm %in% c("BOS", "GSW", "DAL", "MIL", "SAC")
    rim_freq  <- if (is_3pt_heavy) 0.28 else 0.35
    mid_freq  <- if (is_3pt_heavy) 0.18 else 0.27
    three_freq <- 1 - (rim_freq + mid_freq)

    game_actual_pts <- numeric(n_rolling_games)
    game_x_pts      <- numeric(n_rolling_games)

    talent_tier <- case_when(
      tm %in% c("BOS", "DEN", "OKC") ~ 1.04,
      tm %in% c("CHA", "DET", "WAS", "POR") ~ 0.96,
      TRUE ~ 1.00
    )

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

      x_probs <- calc_expected_shot_prob(distances, FALSE) * talent_tier
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

    tibble(
      team = tm,
      games_sampled = n_rolling_games,
      current_season_games = 0L,
      fga_per_game = NA_real_,
      actual_pts_per_game = avg_actual,
      x_pts_per_game = avg_expected
    )
  }) %>% bind_rows()

  shot_profiles <- shot_profiles %>%
    mutate(
      shooting_luck_pts = round(actual_pts_per_game - x_pts_per_game, 2),
      regression_edge_pts = -shooting_luck_pts,
      regression_signal = case_when(
        shooting_luck_pts >= 2.0  ~ "OVERVALUED (Fade Shooting Luck)",
        shooting_luck_pts <= -2.0 ~ "UNDERVALUED (Buy Positive Regression)",
        TRUE ~ "NEUTRAL"
      ),
      data_source = "SYNTHETIC_FALLBACK",
      xfg_method = "parametric_prior",
      source_seasons = NA_character_,
      generated_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ) %>%
    arrange(desc(shooting_luck_pts))

  saveRDS(shot_profiles, file.path(.cache_dir, "team_shot_quality.rds"))
  message(sprintf(">>> [SHOT QUALITY] Wrote SYNTHETIC profiles for 30 teams over %d-game windows.", n_rolling_games))
  return(shot_profiles)
}

# Auto-execute on source
invisible(generate_team_shot_profiles())
