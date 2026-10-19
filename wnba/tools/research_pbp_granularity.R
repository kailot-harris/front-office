# ==============================================================================
# research_pbp_granularity.R — RESEARCH EXERCISE, NOT part of run_full_pipeline.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/tools/research_pbp_granularity.R
#
# SPEC
# ----
# Question: does raw event-level play-by-play (wehoop::load_wnba_pbp()) give us signal
# beyond what rapm_engine.R (possession-level, lineups + points only) and
# shot_quality_engine.R (shot-location, made/miss only) already extract, and is it real/
# reliable enough on this data source to be worth building into the pipeline later?
#
# SCOPE
# -----
# In scope:
#   1. Confirm load_wnba_pbp() returns real, non-empty data and inspect its actual schema
#      (column names/types, event-type vocabulary) — do not assume it matches the NBA
#      hoopR schema.
#   2. Data-quality pass: NA rates on key fields, clock monotonicity within period, whether
#      player IDs on this feed match any existing ID namespace already in this repo
#      (WNBA-Stats-API numeric IDs per rapm_engine.R's TEAM_ID_MAP, or ESPN IDs per
#      active_rosters_cache.rds) — a repeat of the RAPM/roster ID-mismatch trap documented
#      in CLAUDE.md is the single most likely failure mode here.
#   3. Build ONE candidate derived feature not available from existing engines: per-player
#      clutch scoring (points scored on PBP-tagged possessions in the last 5 min of a game
#      within 5 pts) as a concrete test of "can we get something existing engines can't."
#   4. Face-validity check: compare the clutch metric's top/bottom players against
#      cache/rapm_ratings.rds and player BPM from cache/features_cache.rds (do the players
#      RAPM/BPM already rate highest also show up with reasonable clutch numbers, or is the
#      metric noise).
#
# Out of scope (explicitly deferred, do NOT do in this script):
#   - Any change to rapm_engine.R, shot_quality_engine.R, or run_full_pipeline.R.
#   - Any new cache/*.rds consumed by app.R or another production script.
#   - Full ALL_SEASONS (2019-2026) ingestion — start with a 1-2 season sample; only widen
#     if the sample pull is clean and fast enough to justify it.
#
# TEST PLAN (executed top-to-bottom below, each step prints PASS/FAIL/NOTE to stdout)
#   T1. Package/function existence check (wehoop::load_wnba_pbp exists, is callable).
#   T2. Non-empty pull for one recent completed season (2025) — row count, distinct games.
#   T3. Schema dump — column names/types, first few rows, distinct `type_text`/event-type
#       values and their frequencies.
#   T4. NA-rate audit on fields this research would depend on (player id/name, event type,
#       clock, scoring fields, team id).
#   T5. Clock monotonicity spot-check within one game/period (should be non-increasing).
#   T6. ID-namespace check: do PBP player IDs match rapm_ratings.rds's player_id, or
#       active_rosters_cache.rds's ESPN id, or neither (a third namespace)?
#   T7. Derived feature: clutch points per player over the sample season.
#   T8. Face-validity: join clutch metric to rapm_ratings.rds top-20 players (via
#       join_rapm_to_roster()-style team+last-name key, reusing rapm_join_utils.R) and
#       print side-by-side so a human can eyeball whether it's plausible.
#
# All output is research-only: printed to stdout + one CSV in tools/research_output/
# (gitignored-style scratch, not a config.R cache path) for later inspection. Nothing here
# is sourced by any other script.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

source("config.R")
source("rapm_join_utils.R")

out_dir <- file.path(PROJECT_DIR, "tools", "research_output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

pass <- function(msg) message(sprintf("[PASS] %s", msg))
fail <- function(msg) message(sprintf("[FAIL] %s", msg))
note <- function(msg) message(sprintf("[NOTE] %s", msg))

SAMPLE_SEASON <- 2025

# ------------------------------------------------------------------------------
# T1. Package/function existence
# ------------------------------------------------------------------------------
message("\n=== T1: wehoop::load_wnba_pbp existence ===")
if (!requireNamespace("wehoop", quietly = TRUE)) {
  fail("wehoop package not installed — cannot proceed with any step below.")
  quit(save = "no", status = 1)
}
if (!exists("load_wnba_pbp", where = asNamespace("wehoop"), mode = "function")) {
  fail("wehoop::load_wnba_pbp does not exist on this wehoop version.")
  quit(save = "no", status = 1)
}
pass("wehoop::load_wnba_pbp exists and is callable.")

# ------------------------------------------------------------------------------
# T2. Non-empty pull, one season
# ------------------------------------------------------------------------------
message(sprintf("\n=== T2: pulling load_wnba_pbp(seasons = %d) ===", SAMPLE_SEASON))
pbp <- tryCatch(
  wehoop::load_wnba_pbp(seasons = SAMPLE_SEASON),
  error = function(e) {
    fail(sprintf("load_wnba_pbp(%d) errored: %s", SAMPLE_SEASON, conditionMessage(e)))
    NULL
  }
)

if (is.null(pbp) || nrow(pbp) == 0) {
  fail(sprintf("load_wnba_pbp(%d) returned no rows — aborting remaining steps.", SAMPLE_SEASON))
  quit(save = "no", status = 1)
}
pass(sprintf("Pulled %d PBP event rows across %d distinct games for season %d.",
             nrow(pbp), dplyr::n_distinct(pbp$game_id), SAMPLE_SEASON))

# ------------------------------------------------------------------------------
# T3. Schema dump
# ------------------------------------------------------------------------------
message("\n=== T3: schema ===")
schema_tbl <- tibble(column = names(pbp), type = vapply(pbp, function(x) class(x)[1], character(1)))
print(schema_tbl, n = 100)
write.csv(schema_tbl, file.path(out_dir, "pbp_schema.csv"), row.names = FALSE)

type_col <- intersect(c("type_text", "event_type_abbreviation", "type_abbreviation"), names(pbp))
if (length(type_col) > 0) {
  tc <- type_col[1]
  note(sprintf("Using '%s' as the event-type column.", tc))
  freq <- pbp %>% dplyr::count(.data[[tc]], sort = TRUE)
  print(freq, n = 50)
  write.csv(freq, file.path(out_dir, "pbp_event_type_freq.csv"), row.names = FALSE)
} else {
  note("No obvious event-type column found among type_text/event_type_abbreviation/type_abbreviation.")
}

# ------------------------------------------------------------------------------
# T4. NA-rate audit
# ------------------------------------------------------------------------------
message("\n=== T4: NA-rate audit on key fields ===")
key_candidates <- c("game_id", "period", "clock_display_value", "clock_minutes", "clock_seconds",
                     "team_id", "athlete_id_1", "athlete_id_2", "player_id", "home_score", "away_score",
                     "scoring_play", "score_value", "type_text")
present <- intersect(key_candidates, names(pbp))
na_tbl <- tibble(
  column = present,
  na_rate = vapply(present, function(cn) mean(is.na(pbp[[cn]])), numeric(1))
)
print(na_tbl)
write.csv(na_tbl, file.path(out_dir, "pbp_na_rates.csv"), row.names = FALSE)

# ------------------------------------------------------------------------------
# T5. Clock monotonicity spot-check (one game, one period)
# ------------------------------------------------------------------------------
message("\n=== T5: clock monotonicity spot-check ===")
clock_col <- intersect(c("clock_minutes", "clock_display_value"), names(pbp))
if ("period" %in% names(pbp) && length(clock_col) > 0) {
  g1 <- pbp$game_id[1]
  p1 <- pbp %>% dplyr::filter(game_id == g1, period == min(period, na.rm = TRUE))
  note(sprintf("Spot-checking game_id=%s, period 1, %d events.", g1, nrow(p1)))
  print(utils::head(p1, 10))
} else {
  note("Could not identify a usable clock/period column pair for the monotonicity check.")
}

# ------------------------------------------------------------------------------
# T6. ID-namespace check against existing caches
# ------------------------------------------------------------------------------
message("\n=== T6: player-ID namespace check ===")
pbp_id_col <- intersect(c("athlete_id_1", "player_id", "participants_athlete_id"), names(pbp))
rapm_path <- file.path(CACHE_DIR, "rapm_ratings.rds")
roster_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")

if (length(pbp_id_col) == 0) {
  note("No obvious single-player-id column on this PBP feed (may need to unnest athlete lists).")
} else {
  idc <- pbp_id_col[1]
  pbp_ids <- unique(na.omit(pbp[[idc]]))
  note(sprintf("Using '%s' as PBP player-id column (%d distinct ids).", idc, length(pbp_ids)))

  if (file.exists(rapm_path)) {
    rapm <- readRDS(rapm_path)
    if ("player_id" %in% names(rapm)) {
      overlap_rapm <- length(intersect(pbp_ids, unique(rapm$player_id)))
      note(sprintf("Overlap with rapm_ratings.rds player_id namespace: %d / %d PBP ids.",
                   overlap_rapm, length(pbp_ids)))
    }
  } else {
    note("cache/rapm_ratings.rds not found — skipping RAPM id comparison.")
  }

  if (file.exists(roster_path)) {
    roster <- readRDS(roster_path)
    id_col_roster <- intersect(c("player_id", "athlete_id", "id"), names(roster))
    if (length(id_col_roster) > 0) {
      overlap_roster <- length(intersect(pbp_ids, unique(roster[[id_col_roster[1]]])))
      note(sprintf("Overlap with active_rosters_cache.rds '%s' namespace: %d / %d PBP ids.",
                   id_col_roster[1], overlap_roster, length(pbp_ids)))
    }
  } else {
    note("cache/active_rosters_cache.rds not found — skipping roster id comparison.")
  }
}

# ------------------------------------------------------------------------------
# T7. Derived feature: clutch points per player (last 5 min, margin <= 5)
# ------------------------------------------------------------------------------
message("\n=== T7: derived feature — clutch scoring ===")
clutch_result <- NULL
needed <- c("period", "home_score", "away_score", "scoring_play", "score_value")
name_col <- intersect(c("athlete_name_1", "player_name", "text"), names(pbp))

if (all(needed %in% names(pbp)) && length(pbp_id_col) > 0 && length(clock_col) > 0) {
  idc <- pbp_id_col[1]
  clk <- clock_col[1]
  clutch_events <- pbp %>%
    dplyr::filter(period >= 4 | (("period" %in% names(pbp)) & period == max(period, na.rm = TRUE))) %>%
    dplyr::filter(abs(home_score - away_score) <= 5) %>%
    dplyr::filter(scoring_play == TRUE, !is.na(.data[[idc]]))

  if (nrow(clutch_events) > 0) {
    clutch_result <- clutch_events %>%
      dplyr::group_by(player_id = .data[[idc]]) %>%
      dplyr::summarise(clutch_points = sum(score_value, na.rm = TRUE),
                        clutch_scoring_plays = dplyr::n(), .groups = "drop") %>%
      dplyr::arrange(dplyr::desc(clutch_points))
    pass(sprintf("Computed clutch scoring for %d players from %d qualifying events.",
                 nrow(clutch_result), nrow(clutch_events)))
    print(utils::head(clutch_result, 15))
    write.csv(clutch_result, file.path(out_dir, "pbp_clutch_scoring.csv"), row.names = FALSE)
  } else {
    note("No clutch-window scoring events matched the filter — check field names/logic above.")
  }
} else {
  note("Missing one or more required columns (period/home_score/away_score/scoring_play/score_value/player-id/clock) — cannot compute clutch feature as specified. See schema dump for actual column names to adapt this filter.")
}

# ------------------------------------------------------------------------------
# T8. Face-validity vs RAPM
# ------------------------------------------------------------------------------
message("\n=== T8: face-validity check against RAPM ===")
if (!is.null(clutch_result) && file.exists(rapm_path) && file.exists(roster_path)) {
  rapm <- readRDS(rapm_path)
  roster <- readRDS(roster_path)

  # T6 finding: PBP athlete_id_1 lands in active_rosters_cache.rds's ESPN player_id
  # namespace (137/185 matched), NOT rapm_ratings.rds's own player_id namespace (0/185
  # matched) — same RAPM<->roster ID mismatch CLAUDE.md already documents. Bridge PBP ->
  # roster (direct id join, real ESPN ids) -> RAPM (team + last-name key, via the shared
  # join_rapm_to_roster() helper) instead of inventing a new join.
  id_col_roster <- intersect(c("player_id", "athlete_id", "id"), names(roster))[1]
  clutch_named <- clutch_result %>%
    dplyr::inner_join(roster, by = c("player_id" = id_col_roster))

  note(sprintf("Bridged %d of %d clutch players to roster names via ESPN id join.",
               nrow(clutch_named), nrow(clutch_result)))

  bridged <- tryCatch(join_rapm_to_roster(roster, rapm), error = function(e) {
    note(sprintf("join_rapm_to_roster() failed: %s", conditionMessage(e)))
    NULL
  })

  if (!is.null(bridged) && nrow(bridged) > 0 && nrow(clutch_named) > 0) {
    name_col_roster <- intersect(c("player_name", "full_name", "athlete_name"), names(clutch_named))[1]

    compare <- clutch_named %>%
      dplyr::inner_join(bridged, by = "player_id") %>%
      dplyr::arrange(dplyr::desc(clutch_points)) %>%
      dplyr::select(dplyr::any_of(c(name_col_roster, "team_name", "clutch_points",
                                     "clutch_scoring_plays", "total_rapm", "orapm")))
    note(sprintf("Bridged clutch table to RAPM for %d of %d clutch players.",
                 nrow(compare), nrow(clutch_named)))
    note("Top clutch scorers (T7) joined to RAPM (via roster bridge) for face validity:")
    print(utils::head(compare, 15))
    write.csv(compare, file.path(out_dir, "pbp_clutch_vs_rapm.csv"), row.names = FALSE)
  } else {
    note("join_rapm_to_roster() returned 0 rows or clutch_named was empty — printing top clutch scorers by ESPN id only.")
    print(utils::head(clutch_named, 15))
  }
} else {
  note("Skipping — clutch_result empty, or rapm_ratings.rds/active_rosters_cache.rds missing.")
}

message("\n=== DONE. Research outputs written to tools/research_output/. ===")
