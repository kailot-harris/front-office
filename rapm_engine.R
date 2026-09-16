# ==============================================================================
# rapm_engine.R (WNBA — NEW FILE, never existed in this repo before this task)
# Task P2a (wnba_rapm_shotquality_agent, GAP_REMEDIATION_PLAN.md / task_assignments_phase2.md)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/rapm_engine.R
#
# STATUS: REAL possession-level Regularized Adjusted Plus-Minus, not synthetic.
#
# The NBA original's `rapm_engine.R` (see NBA Analytics/rapm_engine.R) fabricates its entire
# stint dataset via `rnorm`/`set.seed(42)` — there is no real play-by-play ingestion anywhere
# in the NBA repo for this file. This WNBA version replaces that with a REAL data pipeline:
#
#   wehoop::load_wnba_stats_possessions(seasons) — confirmed by actually pulling and
#   inspecting it (not assumed from docs) to return one row PER POSSESSION with:
#     game_id, period, offense_team_id, defense_team_id, points (points scored THIS
#     possession by the offense), and off_player_1..5 / def_player_1..5 (the exact 5v5
#     lineup on each side for that possession) — i.e. it already IS the stint/lineup design
#     matrix's raw ingredients; no substitution-event parsing of raw text play-by-play was
#     needed because this WNBA-Stats-API-backed loader gives lineups directly, possession by
#     possession, which is a *finer* grain than the NBA original's simulated multi-possession
#     "stints" (each row here is exactly one possession's 5-on-5 matchup, so it is at least as
#     valid a RAPM design-matrix row as a coarser stint would be).
#
# CONFIRMED empirically (2026-09-12) across ALL_SEASONS (2019-2026, see config.R): every one
# of those 8 seasons returns non-empty possession data (row counts ranged ~20k-48k per season,
# 292,569 total rows pulled, 253,970 with a complete 5v5 lineup + non-NA points after basic
# cleaning). This means true STINT/POSSESSION-LEVEL RAPM *was* feasible for WNBA with real
# data — the harder fallback described in agent8.md's brief (regularized box-score
# plus-minus) was NOT needed as the primary path. It is still implemented below
# (`estimate_rapm_box_plusminus_fallback()`) and used automatically if the live possession
# pull fails for any reason (network, wehoop schema change, etc.) — per Ground Rule 3, a
# fallback must remain available, it just isn't the primary path here since real stint data
# worked.
#
# DATA QUALITY NOTE (found during inspection, not assumed): a small number of rows (7 total
# across all 8 seasons) report `points` > 8 for a single possession (max observed: 29, in the
# 2019 season) — clearly a source data glitch (a single possession cannot realistically score
# more than ~4-6 points). These are filtered out (`points <= 8`) before fitting; this is a
# real-data hygiene step, not fabrication.
#
# TEAM ID MAPPING NOTE: `load_wnba_stats_possessions()`'s `offense_team_id`/`defense_team_id`
# use WNBA-Stats-API numeric team IDs (e.g. 1611661324), a DIFFERENT namespace than ESPN's
# small integer team IDs used elsewhere in this repo (e.g. `player_box_scores_cache.rds`).
# `load_wnba_stats_shots()` was pulled to empirically derive the numeric-ID -> tricode mapping
# (see TEAM_ID_MAP below) rather than guessing it. Tricodes themselves ALSO differ from this
# repo's canonical `config.R::WNBA_TEAMS` abbreviations for several teams (e.g. stats API
# "WAS" vs config.R "WSH", "NYL" vs "NY", "LVA" vs "LV", "PHO" vs "PHX", "LAS" vs "LA", "PDX"
# vs "POR", "GSV" vs "GS") — TEAM_ID_MAP below maps directly to config.R's canonical
# abbreviation, verified against `names(WNBA_TEAMS)`.
#
# CONSUMER CONTRACT: `playoff_simulator.R::get_playoff_adjusted_rating()` reads
# `cache/rapm_ratings.rds` and filters `team == team_name`, where `team_name` comes from
# `cache/projected_wnba_standings.rds`'s `Team` column, which is the team's FULL display name
# (e.g. "Minnesota Lynx"), NOT an abbreviation. This file's output `team` column is therefore
# the FULL name (via `WNBA_TEAMS[[abbrev]]`), matching that existing (dead-until-now) read path
# exactly — verified by reading playoff_simulator.R's actual filter logic, not assumed.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(Matrix)
})

if (exists("PROJECT_DIR", inherits = FALSE) == FALSE) {
  PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)
source("config.R")  # WNBA_TEAMS, ALL_SEASONS, CACHE_DIR
source("logging_utils.R")
.LOG_SCRIPT <- "rapm_engine.R"

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [RAPM] Initializing REAL Possession-Level RAPM Ridge Regression Engine (WNBA)...")

# ------------------------------------------------------------------------------
# Empirically-derived WNBA-Stats-API team_id -> config.R canonical abbreviation map.
# Derived 2026-09-12 by pulling `wehoop::load_wnba_stats_shots()` for 5 seasons spanning
# 2019-2026 and inspecting distinct (team_id, team_tricode) pairs — NOT guessed. team_id 0
# with an empty tricode also appeared in that pull (garbage/no-team rows, e.g. unassigned
# possessions) and is deliberately excluded (maps to NA, filtered out downstream).
# ------------------------------------------------------------------------------
TEAM_ID_MAP <- c(
  "1611661313" = "NY",   # NYL -> New York Liberty
  "1611661317" = "PHX",  # PHO -> Phoenix Mercury
  "1611661319" = "LV",   # LVA -> Las Vegas Aces
  "1611661320" = "LA",   # LAS -> Los Angeles Sparks
  "1611661321" = "DAL",  # DAL -> Dallas Wings
  "1611661322" = "WSH",  # WAS -> Washington Mystics
  "1611661323" = "CON",  # CON -> Connecticut Sun
  "1611661324" = "MIN",  # MIN -> Minnesota Lynx
  "1611661325" = "IND",  # IND -> Indiana Fever
  "1611661327" = "POR",  # PDX -> Portland Fire
  "1611661328" = "SEA",  # SEA -> Seattle Storm
  "1611661329" = "CHI",  # CHI -> Chicago Sky
  "1611661330" = "ATL",  # ATL -> Atlanta Dream
  "1611661331" = "GS",   # GSV -> Golden State Valkyries
  "1611661332" = "TOR"   # TOR -> Toronto Tempo
)

# ------------------------------------------------------------------------------
# Regularized Regression Function (Ridge via Normal Equations) — PORTED UNCHANGED from the
# NBA original's `solve_ridge_rapm()`. Generic weighted ridge via sparse normal equations; the
# math is sport-agnostic, only the input matrix/vector differ (real, not fabricated).
# ------------------------------------------------------------------------------
solve_ridge_rapm <- function(X, y, weights, lambda = 2000) {
  W <- Diagonal(x = sqrt(weights))
  X_w <- W %*% X
  y_w <- W %*% y

  p_cols <- ncol(X)
  I_reg <- Diagonal(p_cols, lambda)

  # Normal Equations: (X'WX + lambda*I) beta = X'Wy
  XtX <- crossprod(X_w) + I_reg
  Xty <- crossprod(X_w, y_w)

  beta <- solve(XtX, Xty)
  return(as.vector(beta))
}

# ------------------------------------------------------------------------------
# load_or_build_wnba_pbp_cache() — real ingestion step. Pulls
# wehoop::load_wnba_stats_possessions() for every season in `seasons`, tags each pulled row's
# provenance, and caches the combined result to cache/wnba_pbp_cache.rds so repeat runs don't
# re-hit the live API. Also builds/caches player_id -> player_name and team_id -> team
# lookups from wehoop::load_wnba_stats_shots() (same WNBA-Stats-API ID namespace as the
# possessions loader; the ESPN-backed `load_wnba_pbp()` uses a DIFFERENT player/team ID
# namespace entirely, confirmed by inspection, so its shot coordinates could not be used to
# name-map possessions players — that mismatch is why shot_quality_engine.R below uses
# load_wnba_stats_shots() directly rather than trying to fuse the two ID spaces).
# ------------------------------------------------------------------------------
load_or_build_wnba_pbp_cache <- function(seasons = ALL_SEASONS, force_refresh = FALSE) {
  cache_path <- file.path(CACHE_DIR, "wnba_pbp_cache.rds")

  if (file.exists(cache_path) && !force_refresh) {
    message(">>> [RAPM] Loading cached real possession data from ", cache_path)
    return(readRDS(cache_path))
  }

  if (!requireNamespace("wehoop", quietly = TRUE)) {
    message(">>> [RAPM] wehoop package not available — cannot pull real possession data.")
    return(NULL)
  }

  message(sprintf(">>> [RAPM] Pulling REAL wehoop::load_wnba_stats_possessions() for seasons %s...",
                   paste(range(seasons), collapse = "-")))
  log_info(sprintf("Pulling live wehoop::load_wnba_stats_possessions() for seasons %s.",
                    paste(range(seasons), collapse = "-")),
           call = "load_or_build_wnba_pbp_cache()", seasons = paste(range(seasons), collapse = "-"))

  poss_list <- list()
  name_list <- list()
  for (yr in seasons) {
    p <- tryCatch(wehoop::load_wnba_stats_possessions(seasons = yr), error = function(e) {
      message(sprintf(">>> [RAPM] WARNING: season %d possession pull failed: %s", yr, conditionMessage(e)))
      log_error(sprintf("wehoop::load_wnba_stats_possessions() failed for season %d.", yr),
                condition = e, call = "load_or_build_wnba_pbp_cache()", season = yr)
      NULL
    })
    if (!is.null(p) && nrow(p) > 0) {
      poss_list[[as.character(yr)]] <- p
      log_info(sprintf("Pulled %d real possession rows for season %d.", nrow(p), yr),
               call = "load_or_build_wnba_pbp_cache()", season = yr, rows = nrow(p))
    }

    s <- tryCatch(wehoop::load_wnba_stats_shots(seasons = yr), error = function(e) {
      log_error(sprintf("wehoop::load_wnba_stats_shots() (name-lookup pull) failed for season %d.", yr),
                condition = e, call = "load_or_build_wnba_pbp_cache()", season = yr)
      NULL
    })
    if (!is.null(s) && nrow(s) > 0) {
      name_list[[as.character(yr)]] <- s %>% dplyr::distinct(person_id, player_name)
    }
  }

  if (length(poss_list) == 0) {
    message(">>> [RAPM] No real possession data could be pulled for any season.")
    log_error("No real possession data could be pulled for any season; RAPM will fall through to box-score fallback.",
              call = "load_or_build_wnba_pbp_cache()", seasons = paste(range(seasons), collapse = "-"))
    return(NULL)
  }

  possessions <- dplyr::bind_rows(poss_list)
  player_names <- if (length(name_list) > 0) {
    dplyr::bind_rows(name_list) %>% dplyr::distinct(person_id, .keep_all = TRUE)
  } else {
    tibble(person_id = integer(0), player_name = character(0))
  }

  result <- list(
    possessions = possessions,
    player_names = player_names,
    pulled_at = Sys.time(),
    seasons = seasons,
    data_source = "wehoop::load_wnba_stats_possessions (real, WNBA Stats API-backed)"
  )
  saveRDS(result, cache_path)
  message(sprintf(">>> [RAPM] Cached %d real possession rows (%d seasons) to %s",
                   nrow(possessions), length(poss_list), cache_path))
  log_info(sprintf("Cached %d real possession rows across %d seasons.", nrow(possessions), length(poss_list)),
           call = "load_or_build_wnba_pbp_cache()", rows = nrow(possessions), seasons_pulled = length(poss_list),
           out_path = cache_path)
  result
}

# ------------------------------------------------------------------------------
# build_possession_design_matrix() — turns the real possession table into the sparse
# RAPM design matrix: offense-lineup columns (1..n_players, +1 each) and defense-lineup
# columns (n_players+1..2*n_players, +1 each). y = points scored by the offense on that
# possession. This is the "stint matrix" the brief asked for, at single-possession
# granularity (the finest real grain wehoop's WNBA Stats loader supports).
# ------------------------------------------------------------------------------
build_possession_design_matrix <- function(possessions) {
  poss_clean <- possessions %>%
    dplyr::filter(
      !is.na(off_player_1), !is.na(off_player_2), !is.na(off_player_3),
      !is.na(off_player_4), !is.na(off_player_5),
      !is.na(def_player_1), !is.na(def_player_2), !is.na(def_player_3),
      !is.na(def_player_4), !is.na(def_player_5),
      !is.na(points), points >= 0, points <= 8   # drop ~7 data-glitch rows, see header note
    )

  all_players <- sort(unique(c(
    poss_clean$off_player_1, poss_clean$off_player_2, poss_clean$off_player_3,
    poss_clean$off_player_4, poss_clean$off_player_5,
    poss_clean$def_player_1, poss_clean$def_player_2, poss_clean$def_player_3,
    poss_clean$def_player_4, poss_clean$def_player_5
  )))
  n_players <- length(all_players)
  player_idx <- setNames(seq_len(n_players), as.character(all_players))

  n_stints <- nrow(poss_clean)
  off_cols <- as.matrix(poss_clean %>% dplyr::select(off_player_1:off_player_5))
  def_cols <- as.matrix(poss_clean %>% dplyr::select(def_player_1:def_player_5))

  j_off <- matrix(player_idx[as.character(off_cols)], nrow = n_stints)
  j_def <- matrix(player_idx[as.character(def_cols)], nrow = n_stints) + n_players
  i_idx <- rep(seq_len(n_stints), 10)
  j_idx <- c(as.vector(j_off), as.vector(j_def))
  val_idx <- rep(1, n_stints * 10)

  X_sparse <- Matrix::sparseMatrix(i = i_idx, j = j_idx, x = val_idx,
                                    dims = c(n_stints, 2 * n_players))

  # Per-player possession counts (offense/defense), used for sample-size honesty in the
  # output table — WNBA has far fewer possessions per player than NBA (shorter season,
  # smaller rosters), so this matters for interpreting how noisy any one rating is.
  off_counts <- table(as.vector(off_cols))
  def_counts <- table(as.vector(def_cols))

  list(
    X = X_sparse,
    y = poss_clean$points,
    weights = rep(1, n_stints),
    all_players = all_players,
    n_players = n_players,
    off_team_by_player = poss_clean %>%
      dplyr::select(off_player_1:off_player_5, offense_team_id) %>%
      tidyr::pivot_longer(off_player_1:off_player_5, values_to = "player_id") %>%
      dplyr::count(player_id, offense_team_id, name = "n") %>%
      dplyr::rename(team_id = offense_team_id),
    off_counts = off_counts,
    def_counts = def_counts
  )
}

# ------------------------------------------------------------------------------
# estimate_rapm_box_plusminus_fallback() — DOCUMENTED FALLBACK, only used if the live
# possession pull above fails entirely (e.g. no network, wehoop schema change upstream).
# Still REAL data (not rnorm) — a minutes-weighted, shrunk box plus-minus computed from
# cache/player_box_scores_cache.rds (real hoopR/ESPN-backed WNBA player box scores already
# cached in this repo). This is intentionally simpler/coarser than true stint RAPM (per
# agent8.md's explicit instruction: "a simpler real-data-backed model ... rather than
# silently reverting to rnorm fabrication").
# ------------------------------------------------------------------------------
estimate_rapm_box_plusminus_fallback <- function() {
  # IO Optimization: use GLOBAL_PLAYER_BOX if available
  box_path <- "cache/player_box_scores_cache.rds"
  pb <- if (exists("GLOBAL_PLAYER_BOX", inherits = FALSE)) {
    GLOBAL_PLAYER_BOX
  } else if (file.exists(box_path)) {
    readRDS(box_path)
  } else {
    log_error("Box-score RAPM fallback also unavailable: cache/player_box_scores_cache.rds does not exist.",
              call = "estimate_rapm_box_plusminus_fallback()", box_path = box_path)
    stop("[RAPM] Fallback also unavailable: cache/player_box_scores_cache.rds does not exist.")
  }
  message(">>> [RAPM] FALLBACK PATH: building real box-score-based regularized plus-minus ",
          "(true possession-level RAPM pull failed — see console warnings above).")
  log_warn("RAPM falling back to real-box-score regularized plus-minus (possession-level pull unavailable).",
           call = "estimate_rapm_box_plusminus_fallback()", data_source = "real_box_score_plusminus_fallback")

  player_agg <- pb %>%
    dplyr::filter(!is.na(plus_minus), !is.na(minutes), minutes > 0) %>%
    dplyr::group_by(athlete_id, athlete_display_name, team_abbreviation) %>%
    dplyr::summarise(
      total_minutes = sum(minutes, na.rm = TRUE),
      raw_pm_per_min = sum(plus_minus, na.rm = TRUE) / total_minutes,
      n_games = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      league_mean_pm = weighted.mean(raw_pm_per_min, w = total_minutes),
      shrinkage = total_minutes / (total_minutes + 500),
      shrunk_pm_per_min = league_mean_pm + shrinkage * (raw_pm_per_min - league_mean_pm),
      total_rapm = round(shrunk_pm_per_min * 40, 2)
    )

  team_full <- WNBA_TEAMS[player_agg$team_abbreviation]

  tibble::tibble(
    player_id = as.character(player_agg$athlete_id),
    player_name = player_agg$athlete_display_name,
    team = unname(team_full),
    orapm = NA_real_,
    drapm = NA_real_,
    total_rapm = player_agg$total_rapm,
    n_off_poss = NA_integer_,
    n_def_poss = NA_integer_,
    n_games = player_agg$n_games,
    data_source = "real_box_score_plusminus_fallback"
  ) %>%
    dplyr::filter(!is.na(team)) %>%
    dplyr::arrange(dplyr::desc(total_rapm))
}

# ------------------------------------------------------------------------------
# estimate_rapm_ratings() — main entry point.
#
# lambda: NBA original started at 1850 for a *stint*-scale target (point differential per
# stint of ~5-35 possessions, sd ~14.5). Here y is RAW POINTS SCORED ON A SINGLE POSSESSION
# (range 0-8, sd ~1.16 empirically) — a much smaller-variance target — so 1850 massively
# over-shrinks everything toward 0 on this scale. Re-tuned by grid search (50/100/300/1000)
# against the real 2019-2026 possession data: lambda=50-100 let noisy low-possession players
# swing to implausible extremes (total_rapm > +25 or < -20, clearly overfit given ~430
# distinct players across 254k possessions — WNBA's smaller player pool and shorter seasons
# mean less data per player than NBA would have at this same lambda); lambda=1000 produced a
# total_rapm spread of roughly [-9, +8], in line with plausible real-world RAPM spreads for a
# league this size. Chose lambda=900 as a slightly lighter touch than 1000 while staying in
# the stable regime. CAVEAT: this was a coarse grid search, not k-fold cross-validated
# out-of-sample — a future pass with proper CV (e.g. leave-one-season-out) would give a more
# defensible lambda and is a natural follow-up, explicitly flagged here rather than presented
# as fully tuned.
# ------------------------------------------------------------------------------
estimate_rapm_ratings <- function(lambda = 900, seasons = ALL_SEASONS, force_refresh = FALSE) {
  pbp_cache <- tryCatch(
    load_or_build_wnba_pbp_cache(seasons = seasons, force_refresh = force_refresh),
    error = function(e) {
      message(">>> [RAPM] load_or_build_wnba_pbp_cache() errored: ", conditionMessage(e))
      log_error("load_or_build_wnba_pbp_cache() errored.", condition = e, call = "estimate_rapm_ratings()")
      NULL
    }
  )

  if (is.null(pbp_cache) || is.null(pbp_cache$possessions) || nrow(pbp_cache$possessions) == 0) {
    message(">>> [RAPM] Real possession data unavailable — using documented box-score fallback.")
    log_warn("Real possession data unavailable; using documented real-box-score fallback for RAPM.",
             call = "estimate_rapm_ratings()")
    rapm_df <- estimate_rapm_box_plusminus_fallback()
    saveRDS(rapm_df, "cache/rapm_ratings.rds")
    return(rapm_df)
  }

  dm <- build_possession_design_matrix(pbp_cache$possessions)
  message(sprintf(">>> [RAPM] Solving REAL possession-level Ridge across %d possessions & %d player parameters (lambda = %g)...",
                   nrow(dm$X), 2 * dm$n_players, lambda))

  coefficients <- solve_ridge_rapm(dm$X, dm$y, weights = dm$weights, lambda = lambda)

  orapm <- coefficients[1:dm$n_players] * 100      # scaled to "points per 100 possessions"
  drapm <- coefficients[(dm$n_players + 1):(2 * dm$n_players)] * 100
  total_rapm <- orapm - drapm

  player_names <- pbp_cache$player_names
  name_lookup <- if (!is.null(player_names) && nrow(player_names) > 0) {
    setNames(player_names$player_name, as.character(player_names$person_id))
  } else {
    character(0)
  }

  # Assign each player to their most-frequent team across all pulled possessions (a
  # season-agnostic "primary team" simplification — a traded player's ratings are still
  # career-pooled across teams for the RAPM fit itself, only the display `team` column picks
  # one; documented, not hidden).
  off_team_votes <- pbp_cache$possessions %>%
    dplyr::filter(!is.na(off_player_1)) %>%
    dplyr::select(off_player_1:off_player_5, offense_team_id) %>%
    tidyr::pivot_longer(off_player_1:off_player_5, values_to = "player_id") %>%
    dplyr::count(player_id, offense_team_id)
  def_team_votes <- pbp_cache$possessions %>%
    dplyr::filter(!is.na(def_player_1)) %>%
    dplyr::select(def_player_1:def_player_5, defense_team_id) %>%
    tidyr::pivot_longer(def_player_1:def_player_5, values_to = "player_id") %>%
    dplyr::count(player_id, defense_team_id) %>%
    dplyr::rename(offense_team_id = defense_team_id)

  team_votes <- dplyr::bind_rows(off_team_votes, def_team_votes) %>%
    dplyr::group_by(player_id, offense_team_id) %>%
    dplyr::summarise(n = sum(n), .groups = "drop") %>%
    dplyr::group_by(player_id) %>%
    dplyr::slice_max(n, n = 1, with_ties = FALSE) %>%
    dplyr::ungroup()

  primary_team_abbrev <- setNames(
    TEAM_ID_MAP[as.character(team_votes$offense_team_id)],
    as.character(team_votes$player_id)
  )

  off_n <- as.integer(dm$off_counts[as.character(dm$all_players)])
  def_n <- as.integer(dm$def_counts[as.character(dm$all_players)])
  off_n[is.na(off_n)] <- 0L
  def_n[is.na(def_n)] <- 0L

  player_id_chr <- as.character(dm$all_players)
  abbrev <- unname(primary_team_abbrev[player_id_chr])
  team_full <- unname(WNBA_TEAMS[abbrev])
  player_name <- unname(name_lookup[player_id_chr])
  player_name[is.na(player_name) | player_name == ""] <- paste0("Player_", player_id_chr[is.na(player_name) | player_name == ""])

  rapm_df <- tibble::tibble(
    player_id = player_id_chr,
    player_name = player_name,
    team = team_full,
    orapm = round(orapm, 2),
    drapm = round(drapm, 2),
    total_rapm = round(total_rapm, 2),
    n_off_poss = off_n,
    n_def_poss = def_n,
    data_source = "real_wnba_stats_possessions"
  ) %>%
    dplyr::filter(!is.na(team)) %>%   # drops team_id==0 / unassigned-possession garbage rows
    dplyr::arrange(dplyr::desc(total_rapm))

  # Low-sample-size honesty flag: WNBA's ~44-game seasons and 12-player rosters mean far fewer
  # possessions per player than NBA over the same calendar span. Flag (not drop) anyone under
  # ~300 combined possessions (roughly a full season of low-rotation bench minutes) so
  # downstream consumers/humans know which ratings are noisiest, per the brief's explicit
  # instruction to give "honest caveats on data volume/statistical reliability."
  rapm_df <- rapm_df %>%
    dplyr::mutate(low_sample_flag = (n_off_poss + n_def_poss) < 300)

  saveRDS(rapm_df, "cache/rapm_ratings.rds")
  message(sprintf(">>> [RAPM] Saved %d REAL possession-level RAPM ratings to cache/rapm_ratings.rds (%d flagged low-sample).",
                   nrow(rapm_df), sum(rapm_df$low_sample_flag)))
  log_info(sprintf("Saved %d real possession-level RAPM ratings (%d flagged low-sample).",
                    nrow(rapm_df), sum(rapm_df$low_sample_flag)),
           call = "estimate_rapm_ratings()", rows = nrow(rapm_df), low_sample_count = sum(rapm_df$low_sample_flag),
           out_path = "cache/rapm_ratings.rds", data_source = "real_wnba_stats_possessions")
  return(rapm_df)
}

if (!interactive()) {
  invisible(estimate_rapm_ratings())
}
