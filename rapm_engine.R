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
source("rapm_join_utils.R")  # normalize_rapm_last_name() — current-roster re-attribution below
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
# reattribute_to_current_roster_team() — fixes a confirmed staleness bug: both
# estimate_rapm_ratings()'s possession-vote team assignment (see `team_votes` above)
# and estimate_rapm_box_plusminus_fallback()'s team assignment are derived from
# historical data pooled across ALL_SEASONS, so they reflect "the team this player
# accumulated the most historical data with," not their CURRENT team. That is wrong
# for any player who isn't still on that team — not just mid-season trades, but any
# offseason free-agent signing, trade, or expansion-draft move. Empirically (2026-10-07
# investigation): 62 of 152 unambiguous-last-name comparisons against
# cache/active_rosters_cache.rds disagreed — e.g. Angel Reese's possession plurality is
# still with the Chicago Sky even though she is now on the Atlanta Dream roster. Because
# rapm_join_utils.R::join_rapm_to_roster() joins on (team_name, last_name) with
# inner-join semantics, every such mismatch silently vanished from the RAPM leaderboard
# with no warning.
#
# Fix: override `team` with the CURRENT roster's team_name whenever a player's last name
# is UNAMBIGUOUS on the roster side (maps to exactly one team_name league-wide) — this is
# the same identity signal join_rapm_to_roster() itself relies on, so fixing it here keeps
# that join correct. Last names ambiguous on the roster side (e.g. multiple
# "Jones"/"Williams" on different teams) are deliberately left on the historical team:
# there is no way to tell, from a last-name-only RAPM row, which of several same-surname
# roster players it belongs to, and guessing would risk a WORSE (silently wrong)
# attribution than today's season-agnostic one.
# Fail-safe: if active_rosters_cache.rds is missing/unreadable/malformed, this is a no-op
# and rapm_df keeps its original team assignment exactly as before.
# ------------------------------------------------------------------------------
reattribute_to_current_roster_team <- function(rapm_df) {
  roster_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")
  if (!file.exists(roster_path)) {
    log_warn("active_rosters_cache.rds not found; RAPM team attribution not re-checked against current rosters.",
             call = "reattribute_to_current_roster_team()")
    return(rapm_df)
  }

  roster <- tryCatch(readRDS(roster_path), error = function(e) NULL)
  if (is.null(roster) || !is.data.frame(roster) ||
      !all(c("player_name", "team_name") %in% names(roster))) {
    log_warn("active_rosters_cache.rds missing/malformed; skipping current-team re-attribution.",
             call = "reattribute_to_current_roster_team()")
    return(rapm_df)
  }

  roster_last <- roster %>%
    dplyr::mutate(last_name = normalize_rapm_last_name(.data$player_name, from_full_name = TRUE)) %>%
    dplyr::count(.data$last_name, .data$team_name) %>%
    dplyr::group_by(.data$last_name) %>%
    dplyr::filter(dplyr::n_distinct(.data$team_name) == 1) %>%
    dplyr::ungroup() %>%
    dplyr::distinct(.data$last_name, .data$team_name)

  roster_team_by_last <- setNames(roster_last$team_name, roster_last$last_name)

  n_reattributed <- rapm_df %>%
    dplyr::mutate(.last_name = normalize_rapm_last_name(.data$player_name, from_full_name = FALSE)) %>%
    dplyr::filter(!is.na(roster_team_by_last[.data$.last_name]),
                   roster_team_by_last[.data$.last_name] != .data$team) %>%
    nrow()

  rapm_df <- rapm_df %>%
    dplyr::mutate(
      .last_name = normalize_rapm_last_name(.data$player_name, from_full_name = FALSE),
      team = dplyr::coalesce(unname(roster_team_by_last[.data$.last_name]), .data$team)
    ) %>%
    dplyr::select(-".last_name")

  message(sprintf(">>> [RAPM] Re-attributed %d player(s) to their current roster team (was: historical-possession-plurality team).",
                   n_reattributed))
  log_info(sprintf("Re-attributed %d player(s) to current roster team via active_rosters_cache.rds.", n_reattributed),
           call = "reattribute_to_current_roster_team()", n_reattributed = n_reattributed)

  rapm_df
}

# ------------------------------------------------------------------------------
# fit_rapm_ratings() — shared fitting core, extracted from estimate_rapm_ratings() (GitHub
# issue #70, sub-issue of #69) so a historical, season-specific RAPM snapshot can be produced
# without touching the live current-season pipeline.
#
# team_attribution:
#   - "current_roster" (used by the live estimate_rapm_ratings() wrapper, unchanged behavior):
#     overrides `team` via reattribute_to_current_roster_team() at the end, and falls back to
#     estimate_rapm_box_plusminus_fallback() (also reattributed) if the possession pull fails
#     or returns 0 rows — never crashes the live pipeline, per this repo's fail-safe
#     convention.
#   - "season_pooled" (used only by tools/generate_historical_season_snapshots.R): keeps the
#     already-computed `primary_team_abbrev` possession-vote as the final `team` column
#     (no reattribution to 2026 current rosters, which would be wrong for a historical
#     snapshot), and HARD-STOPS via stop() if the possession pull fails or returns 0 rows for
#     the requested `seasons` instead of silently falling through to the career-pooled
#     box-score fallback, which cannot be made season-specific and would silently produce a
#     wrong (non-season-specific) answer for this path.
#
# Also fixes the latent season-filter bug documented in CLAUDE.md /issue #70:
# load_or_build_wnba_pbp_cache() silently ignores `seasons` whenever
# cache/wnba_pbp_cache.rds already exists (it always does, pooled across ALL of ALL_SEASONS).
# This function re-filters `possessions` by `season %in% seasons` right after the cache call —
# a no-op for the live default caller (seasons = ALL_SEASONS, which matches the cache's full
# span exactly) but load-bearing for any caller requesting a single historical season.
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
#
# *** WHAT THIS MODEL CAN AND CANNOT IDENTIFY (GitHub issue #71, fix A) ***
# build_possession_design_matrix() emits 2 * n_players columns: offense first, defense second,
# each possession contributing +1 to five offense columns and +1 to five defense columns. The
# design matrix therefore has an EXACT null direction:
#
#     v = (+1, ..., +1,   -1, ..., -1)        # +1 on every offense column, -1 on every defense column
#     X %*% v = 5 - 5 = 0                     # exactly 0 for every possession row (verified: max|X %*% v| = 0
#                                             # over all 253,968 possessions / 860 columns)
#
# Consequence: adding a constant c to EVERY offensive coefficient while subtracting c from
# EVERY defensive coefficient leaves every prediction unchanged. The ABSOLUTE LEVELS of
# orapm and drapm are NOT IDENTIFIED by this fit. What IS identified is (a) relative values
# within the offense side, (b) relative values within the defense side, and (c) the centered
# total `orapm - drapm`.
#
# Ridge's minimum-norm solution resolves the degeneracy by pinning sum(beta_off) ==
# sum(beta_def), i.e. mean(orapm) == mean(drapm) (empirically both 7.12 in the shipped cache).
# That equality is what makes the centering step below SAFE for total_rapm: subtracting each
# side's own mean shifts the total by mean(drapm) - mean(orapm), which is 0 up to float noise.
# See tools/verify_rapm_centering.R for the numerical proof against the shipped cache.
#
# NOTE: the ~0.77 orapm/drapm correlation reported in issue #71 is a lambda-driven shrinkage
# artifact (0.06 at lambda=50, 0.77 at lambda=900, 0.99 at lambda=30,000), NOT an O/D encoding
# bug. It is deliberately NOT addressed here; lambda stays 900.
# ------------------------------------------------------------------------------
fit_rapm_ratings <- function(seasons = ALL_SEASONS, lambda = 900, force_refresh = FALSE,
                              team_attribution = c("current_roster", "season_pooled")) {
  team_attribution <- match.arg(team_attribution)

  pbp_cache <- tryCatch(
    load_or_build_wnba_pbp_cache(seasons = seasons, force_refresh = force_refresh),
    error = function(e) {
      message(">>> [RAPM] load_or_build_wnba_pbp_cache() errored: ", conditionMessage(e))
      log_error("load_or_build_wnba_pbp_cache() errored.", condition = e, call = "fit_rapm_ratings()")
      NULL
    }
  )

  if (!is.null(pbp_cache) && !is.null(pbp_cache$possessions)) {
    # Fix for the latent season-filter bug: load_or_build_wnba_pbp_cache() silently ignores
    # `seasons` whenever the pooled cache already exists. Re-filter here. No-op for the live
    # default caller (seasons = ALL_SEASONS == the cache's full pooled span).
    pbp_cache$possessions <- dplyr::filter(pbp_cache$possessions, season %in% seasons)
  }

  if (is.null(pbp_cache) || is.null(pbp_cache$possessions) || nrow(pbp_cache$possessions) == 0) {
    if (team_attribution == "season_pooled") {
      log_error(sprintf("No real possession data available for season(s) %s; hard-stopping (season_pooled path does not fall back).",
                         paste(seasons, collapse = ",")),
                call = "fit_rapm_ratings()", seasons = paste(seasons, collapse = ","))
      stop(sprintf("[RAPM] fit_rapm_ratings(): no real possession data for season(s) %s and team_attribution = 'season_pooled' — refusing to fall back to the career-pooled box-score fallback for a season-specific request.",
                    paste(seasons, collapse = ",")))
    }
    message(">>> [RAPM] Real possession data unavailable — using documented box-score fallback.")
    log_warn("Real possession data unavailable; using documented real-box-score fallback for RAPM.",
             call = "fit_rapm_ratings()")
    rapm_df <- estimate_rapm_box_plusminus_fallback()
    rapm_df <- reattribute_to_current_roster_team(rapm_df)
    return(rapm_df)
  }

  dm <- build_possession_design_matrix(pbp_cache$possessions)
  message(sprintf(">>> [RAPM] Solving REAL possession-level Ridge across %d possessions & %d player parameters (lambda = %g)...",
                   nrow(dm$X), 2 * dm$n_players, lambda))

  coefficients <- solve_ridge_rapm(dm$X, dm$y, weights = dm$weights, lambda = lambda)

  orapm <- coefficients[1:dm$n_players] * 100      # scaled to "points per 100 possessions"
  drapm <- coefficients[(dm$n_players + 1):(2 * dm$n_players)] * 100

  # --- CENTERING STEP (issue #71, fix A) -------------------------------------------------
  # The absolute O/D levels are not identified (see the null-direction note in this
  # function's header), so the raw coefficients' shared positive offset is an artifact of
  # ridge's minimum-norm tie-break, not a finding. Export each side centered on its own
  # league mean so 0 == league average and the sign of a single number is interpretable.
  # total_rapm is computed AFTER centering and is unchanged to within float noise, because
  # ridge pins mean(orapm) == mean(drapm): the total shifts by mean(drapm) - mean(orapm) ~ 0.
  orapm <- orapm - mean(orapm, na.rm = TRUE)
  drapm <- drapm - mean(drapm, na.rm = TRUE)
  # ---------------------------------------------------------------------------------------

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

  if (team_attribution == "current_roster") {
    rapm_df <- reattribute_to_current_roster_team(rapm_df)
  }
  # team_attribution == "season_pooled": leave `team` as the already-computed
  # primary_team_abbrev possession-vote for the requested season(s) — do NOT reattribute to
  # the 2026 current roster, which would be wrong for a historical snapshot.

  # Low-sample-size honesty flag: WNBA's ~44-game seasons and 12-player rosters mean far fewer
  # possessions per player than NBA over the same calendar span. Flag (not drop) the noisiest
  # ratings so downstream consumers/humans know which ones not to trust.
  #
  # RULE CHANGED from a raw possession count to a SHRINKAGE rule (issue #71, fix A).
  #
  # The old `(n_off_poss + n_def_poss) < 300` cut flagged 63 of 430 players (14.7%) and caught
  # NONE of the low-exposure players topping the Total RAPM leaderboard — Dungee (391
  # combined), Nivar (561), Clouden (1,662), Jaquez (1,931), Park (2,207) all ranked 3rd-10th
  # league-wide while unflagged. But raising the count is the wrong instrument, and the
  # intuition behind it ("low exposure = noisy") is empirically BACKWARDS here: measured sd of
  # total_rapm by combined-possession band is 1.48 (<500), 2.51 (500-1k), 2.87 (1-2k), 3.29
  # (2-3k), 2.71 (>5k). The LOWEST-exposure band is the LEAST variable, because ridge shrinks
  # it hardest. Shrinkage dominates MORE at low exposure, not less. A count-based cut also
  # lands arbitrarily: the league median combined exposure is 2,597, so any threshold near
  # 2,500 flags ~half the league by construction rather than by evidence.
  #
  # What actually matters is HOW MUCH OF A RATING IS DATA vs. PRIOR. Ridge shrinks each
  # coefficient by roughly s_i = n_i / (n_i + lambda), so `1 - s_i` is the fraction of the
  # reported number contributed by the shrinkage prior rather than by the player's own
  # possessions. Flag a player when the weaker of their two sides is more than two-thirds
  # prior (s < 1/3, i.e. fewer than lambda/2 possessions on that side). This is why Dungee
  # ranks 5th at +6.19 on 194 offensive possessions: she is 82% prior, shrunk ~5x toward zero
  # and still top-five, so her unshrunk signal is ~+34/100 — lineup luck, not a player effect.
  # Measured: flags 124 of 430 (28.8%), catching Dungee (82% prior) and Nivar (76%).
  #
  # Expressing the rule against `lambda` rather than a hardcoded possession count means it
  # stays correct if lambda is ever re-tuned (see this function's header: lambda = 900 came
  # from a coarse grid search and a CV pass is a known follow-up). Flag, never drop.
  RAPM_MIN_DATA_SHARE <- 1 / 3
  rapm_df <- rapm_df %>%
    dplyr::mutate(
      shrinkage_data_share = pmin(
        n_off_poss / (n_off_poss + lambda),
        n_def_poss / (n_def_poss + lambda)
      ),
      low_sample_flag = shrinkage_data_share < RAPM_MIN_DATA_SHARE
    )

  # Leaderboard eligibility is a SEPARATE mechanism from the honesty flag above (issue #71,
  # fix A). `low_sample_flag` answers "how much of this one number is prior?"; eligibility
  # answers "should this row compete for a top-N rank at all?". Conflating them into one
  # boolean was what forced the earlier 48.8% flag rate — a dataset-level claim that half the
  # league is untrustworthy, in order to clean a presentation-level ranking.
  #
  # Require >= 1,000 possessions on BOTH sides (not combined, which lets a one-sided specialist
  # through on garbage-time minutes). Measured: 242 of 430 eligible, and the resulting top ten
  # is Parker, Delle Donne, Park, Prince, Jones, Gray, Miles, Diggins-Smith, Burton, Clark —
  # no sub-1,000-possession row. Consumers that rank or sort should filter on this column;
  # consumers that display a single player's rating should use `low_sample_flag` instead.
  RAPM_LEADERBOARD_MIN_POSS_PER_SIDE <- 1000L
  rapm_df <- rapm_df %>%
    dplyr::mutate(leaderboard_eligible = pmin(n_off_poss, n_def_poss) >=
                    RAPM_LEADERBOARD_MIN_POSS_PER_SIDE)

  # --- CONTRACT INVARIANT (issue #71, fix A) ---------------------------------------------
  # On the real-possession path orapm/drapm are league-centered above, so all three rating
  # columns must have mean ~0. Tolerance 0.02 covers the round(, 2) applied to each column
  # (max rounding shift of a mean is 0.005) with ample headroom. Skipped, not failed, when
  # orapm/drapm are all NA (the estimate_rapm_box_plusminus_fallback() path, which never
  # reaches this line today but is guarded anyway).
  assert_rapm_centered(rapm_df, tolerance = 0.02)

  rapm_df
}

# ------------------------------------------------------------------------------
# assert_rapm_centered() — contract invariant for the centering introduced in issue #71.
# Verifies mean(orapm) ~ 0, mean(drapm) ~ 0 and mean(total_rapm) ~ 0 within `tolerance`.
# Returns `rapm_df` invisibly so it can be used inline. No-ops (with a message) when
# orapm/drapm are entirely NA, which is the documented box-score fallback path where absolute
# O/D splits are not produced at all.
# ------------------------------------------------------------------------------
assert_rapm_centered <- function(rapm_df, tolerance = 0.02) {
  if (is.null(rapm_df) || nrow(rapm_df) == 0) return(invisible(rapm_df))
  if (!all(c("orapm", "drapm", "total_rapm") %in% names(rapm_df))) return(invisible(rapm_df))

  if (all(is.na(rapm_df$orapm)) && all(is.na(rapm_df$drapm))) {
    message(">>> [RAPM] Centering invariant skipped: orapm/drapm are all NA (box-score fallback path).")
    return(invisible(rapm_df))
  }

  means <- c(
    orapm      = mean(rapm_df$orapm, na.rm = TRUE),
    drapm      = mean(rapm_df$drapm, na.rm = TRUE),
    total_rapm = mean(rapm_df$total_rapm, na.rm = TRUE)
  )
  bad <- names(means)[!is.finite(means) | abs(means) > tolerance]
  if (length(bad) > 0) {
    stop(sprintf("[RAPM] Centering contract violated (tolerance %.3f): %s. orapm/drapm must be exported centered on their league means (issue #71).",
                  tolerance,
                  paste(sprintf("mean(%s) = %.4f", bad, means[bad]), collapse = "; ")))
  }
  invisible(rapm_df)
}

# ------------------------------------------------------------------------------
# estimate_rapm_ratings() — main entry point, live/current-season path. Thin wrapper around
# fit_rapm_ratings(..., team_attribution = "current_roster") that adds the saveRDS() to
# cache/rapm_ratings.rds and the final success log/message. Behavior-preserving: every real
# call site in this repo uses the defaults (seasons = ALL_SEASONS), so this refactor is a
# no-op for the live path (see fit_rapm_ratings()'s header comment for the season-filter fix,
# which is also a no-op at seasons = ALL_SEASONS).
# ------------------------------------------------------------------------------
estimate_rapm_ratings <- function(lambda = 900, seasons = ALL_SEASONS, force_refresh = FALSE) {
  rapm_df <- fit_rapm_ratings(seasons = seasons, lambda = lambda, force_refresh = force_refresh,
                               team_attribution = "current_roster")

  saveRDS(rapm_df, "cache/rapm_ratings.rds")

  if (identical(rapm_df$data_source[1], "real_box_score_plusminus_fallback")) {
    # Fallback path already logged its own warning inside estimate_rapm_box_plusminus_fallback().
    return(rapm_df)
  }

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
