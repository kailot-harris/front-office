# ==============================================================================
# Player-Level Impact Metrics (BPM, Minutes Concentration & Depth) - WNBA
# Path: player_metrics.R
#
# Ported from NBA Analytics/player_metrics.R. Swaps hoopR::load_nba_player_box() for
# wehoop::load_wnba_player_box(), same chunked per-season retry/backoff pattern using
# MAX_RETRIES / RATE_LIMIT_SLEEP_SEC from config.R. calculate_bpm_components() and
# get_player_features() are ported unchanged (BPM box-score weights are not
# NBA-specific per WNBA_REPLICATION_PLAN.md §b Tier 2) except for the WNBA-specific
# exhibition-row filter applied right after each chunked wehoop pull.
# ==============================================================================

suppressPackageStartupMessages({
  library(tidyverse)
  library(wehoop)
  library(slider)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "player_metrics.R"

# Same WNBA-specific gotcha as daily_ingest.R: raw wehoop player box includes
# non-franchise All-Star/Team USA exhibition rows. Filter before caching/aggregating.
#
# Also normalizes "CONN" -> "CON": ESPN used "CONN" as the Connecticut Sun's real
# abbreviation for 2019-2023 (switching to "CON" from 2024 on) - discovered during T1
# validation (2026-09-12). This is a real franchise code, not an exhibition row; a
# naive filter against WNBA_TEAMS would silently drop 5 seasons of real Sun player-game
# rows. See daily_ingest.R's normalize_team_abbreviation() for the team-box equivalent.
normalize_team_abbreviation <- function(df) {
  if ("team_abbreviation" %in% names(df)) {
    df <- df |> mutate(team_abbreviation = if_else(team_abbreviation == "CONN", "CON", team_abbreviation))
  }
  if ("opponent_team_abbreviation" %in% names(df)) {
    df <- df |> mutate(opponent_team_abbreviation = if_else(opponent_team_abbreviation == "CONN", "CON", opponent_team_abbreviation))
  }
  df
}

filter_real_franchises <- function(df) {
  if (!"team_abbreviation" %in% names(df)) return(df)
  df <- normalize_team_abbreviation(df)
  df |> filter(team_abbreviation %in% names(WNBA_TEAMS))
}

get_player_box_scores_chunked <- function(seasons = ALL_SEASONS) {
  if (file.exists(CACHE_PLAYER_BOX)) {
    message(sprintf("[Player Metrics] Loading player box scores from cache: %s", CACHE_PLAYER_BOX))
    return(readRDS(CACHE_PLAYER_BOX))
  }

  message("[Player Metrics] Cache not found. Initiating chunked download with rate-limiting...")
  season_dfs <- list()

  for (s in seasons) {
    message(sprintf("  -> Ingesting season %d...", s))
    s_data <- NULL
    for (attempt in 1:MAX_RETRIES) {
      s_data <- tryCatch({
        wehoop::load_wnba_player_box(seasons = s)
      }, error = function(e) {
        warning(sprintf("     Attempt %d failed for season %d: %s", attempt, s, e$message))
        log_error(sprintf("wehoop::load_wnba_player_box() attempt %d/%d failed for season %d.",
                           attempt, MAX_RETRIES, s),
                  condition = e, call = "get_player_box_scores_chunked()", season = s, attempt = attempt)
        Sys.sleep(RATE_LIMIT_SLEEP_SEC * 2)
        NULL
      })
      if (!is.null(s_data)) break
    }

    if (is.null(s_data)) {
      log_error(sprintf("Failed to retrieve player box scores for season %d after %d retries.", s, MAX_RETRIES),
                call = "get_player_box_scores_chunked()", season = s, max_retries = MAX_RETRIES)
      stop(sprintf("Failed to retrieve player box scores for season %d after %d retries.", s, MAX_RETRIES))
    }

    s_data <- filter_real_franchises(s_data)
    log_info(sprintf("Ingested %d real-franchise player-game rows for season %d.", nrow(s_data), s),
             call = "get_player_box_scores_chunked()", season = s, rows = nrow(s_data))
    season_dfs[[as.character(s)]] <- s_data
    Sys.sleep(RATE_LIMIT_SLEEP_SEC) # Protect ESPN/wehoop endpoints
  }

  all_player_box <- bind_rows(season_dfs)
  saveRDS(all_player_box, CACHE_PLAYER_BOX)
  message(sprintf("[Player Metrics] Ingestion complete. Cached %d player-game rows.", nrow(all_player_box)))
  log_info(sprintf("Cached %d total player-game rows across %d seasons.", nrow(all_player_box), length(seasons)),
           call = "get_player_box_scores_chunked()", rows = nrow(all_player_box), out_path = CACHE_PLAYER_BOX)
  return(all_player_box)
}

# AUDITED 2026-09-17 (docs/bpm_implementation_audit_findings.md): this is deliberately a
# DIFFERENT metric from roster_bottom_up_engine.R::get_player_bpm_ratings() (different weights,
# per-game not season-aggregated, no plus-minus blend). Its output feeds
# cache/features_cache.rds's team_top5_bpm/team_minutes_concentration, which
# TOP5_BPM_MARGIN_SLOPE/MINUTES_CONCENTRATION_MARGIN_SLOPE were empirically regressed against
# EXACTLY as computed here. Do not change these weights without re-running
# tools/research_team_depth_regression.R and re-deriving those slopes — see the audit doc.
calculate_bpm_components <- function(player_df) {
  # Robust column mapping across wehoop/ESPN historical schemas
  df <- player_df |>
    mutate(
      minutes = suppressWarnings(as.numeric(minutes)),
      minutes = replace_na(minutes, 0),
      points = suppressWarnings(as.numeric(points)),
      rebounds = suppressWarnings(as.numeric(rebounds)),
      assists = suppressWarnings(as.numeric(assists)),
      steals = suppressWarnings(as.numeric(steals)),
      blocks = suppressWarnings(as.numeric(blocks)),
      turnovers = suppressWarnings(as.numeric(turnovers)),
      field_goals_made = suppressWarnings(as.numeric(field_goals_made)),
      field_goals_attempted = suppressWarnings(as.numeric(field_goals_attempted)),
      three_point_field_goals_made = suppressWarnings(as.numeric(three_point_field_goals_made)),
      free_throws_made = suppressWarnings(as.numeric(free_throws_made)),
      free_throws_attempted = suppressWarnings(as.numeric(free_throws_attempted))
    ) |>
    replace_na(list(
      points = 0, rebounds = 0, assists = 0, steals = 0, blocks = 0,
      turnovers = 0, field_goals_made = 0, field_goals_attempted = 0,
      three_point_field_goals_made = 0, free_throws_made = 0, free_throws_attempted = 0
    ))

  # Standard empirical BPM linear weights scaled per 36 minutes.
  # RECALIBRATED 2026-09-19 (docs/bpm_recalibration_findings.md,
  # tools/research_bpm_recalibration.R): re-derived all 9 per-stat weights against real
  # WNBA data via a within-team, trailing-average (non-circular) regression of team
  # margin on each box category, mirroring research_team_depth_regression.R's discipline.
  # Result: only `steals` cleared the significance bar (p=0.004, 0.875 vs the old
  # NBA-ported 1.40); the other 8 terms were not significant and were left AS-IS per this
  # repo's significance-gated "don't move a number without real evidence" convention —
  # this is a mostly-negative empirical result, not a full recalibration. The -2.0
  # replacement-level anchor was ALSO attempted (10th percentile of the weighted-sum
  # distribution among minutes>=10 player-games) but produced an implausible result
  # (+3.51, wrong sign/scale vs. the BPM-family convention of a deeply-negative
  # replacement level) — deferred, NOT wired in; the anchor below is still the original
  # NBA-ported -2.0. See the findings doc for the full writeup, including why a
  # rotation-filtered percentile is likely the wrong replacement-level proxy and what a
  # better derivation would need (true bottom-of-roster/end-of-bench minutes, not a
  # percentile within an already-filtered rotation subsample).
  # Any further change to these weights requires re-running
  # tools/research_team_depth_regression.R and re-deriving TOP5_BPM_MARGIN_SLOPE /
  # MINUTES_CONCENTRATION_MARGIN_SLOPE in roster_bottom_up_engine.R — see the audit
  # comment above and docs/bpm_implementation_audit_findings.md.
  df <- df |>
    mutate(
      min_factor = if_else(minutes > 0, 36 / minutes, 0),
      raw_bpm_rate = if_else(
        minutes >= 5,
        (0.60 * points + 0.70 * rebounds + 1.05 * assists + 0.875 * steals + 1.15 * blocks -
           1.20 * turnovers - 0.45 * (field_goals_attempted - field_goals_made) -
           0.35 * (free_throws_attempted - free_throws_made) + 0.30 * three_point_field_goals_made) * (minutes / 36) - 2.0,
        -2.0
      )
    )
  return(df)
}

get_player_features <- function(seasons = ALL_SEASONS) {
  raw_player_box <- get_player_box_scores_chunked(seasons)
  bpm_df <- calculate_bpm_components(raw_player_box)

  # Aggregate features at team-game level
  team_game_features <- bpm_df |>
    filter(minutes > 0) |>
    group_by(game_id, team_id) |>
    summarise(
      total_team_minutes = sum(minutes, na.rm = TRUE),
      # Minutes-weighted BPM
      team_weighted_bpm = sum(raw_bpm_rate * minutes, na.rm = TRUE) / pmax(1, sum(minutes, na.rm = TRUE)),
      # Top-5 Unit BPM
      team_top5_bpm = mean(head(sort(raw_bpm_rate, decreasing = TRUE), 5), na.rm = TRUE),
      # Minutes Concentration (Herfindahl-Hirschman Index of team minutes)
      team_minutes_concentration = sum((minutes / pmax(1, sum(minutes, na.rm = TRUE)))^2, na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(
      game_id = as.character(game_id),
      team_id = as.integer(team_id)
    )

  return(team_game_features)
}

# ------------------------------------------------------------------------------
# compute_and_cache_player_features() — pipeline entry point (Tier 1 fix, 2026-09-17).
#
# get_player_features() above was always fully implemented and real-data-backed, but was
# never wired into run_full_pipeline.R and never had its output saved anywhere — config.R
# has declared CACHE_FEATURES ("cache/features_cache.rds") since Phase 0, and
# tools/data_health_probe.R has flagged it "missing" across three separate remediation
# waves (see docs/task_assignments_phase4.md's Phase 4 handoff notes), each one noting it
# as "pre-existing and unrelated" without tracing it to this root cause: there was simply
# no producer. (There is also still no CONSUMER of this cache anywhere in the pipeline —
# that is a separate, deliberate follow-up requiring its own empirical validation, not
# addressed here; see the research note this fix was scoped from.)
#
# This wrapper is deliberately the ONLY thing in this file with a side effect.
# player_metrics.R itself must stay side-effect-free on a bare source() —
# roster_bottom_up_engine.R already sources this file purely for its function
# definitions (per that file's own header comment) and must not trigger a recompute as a
# side effect of that source() call. So this is invoked via run_full_pipeline.R's
# `call_fn` mechanism (same pattern as daily_ingest.R/prediction_accuracy_logger.R), not
# an auto-run `if (!interactive())` footer.
compute_and_cache_player_features <- function(seasons = ALL_SEASONS) {
  features <- get_player_features(seasons)
  saveRDS(features, CACHE_FEATURES)
  message(sprintf("[Player Metrics] Cached %d team-game feature rows (BPM/minutes-concentration) to %s",
                   nrow(features), CACHE_FEATURES))
  invisible(features)
}
