# ==============================================================================
# Play-by-Play Player Features (Clutch Scoring, Assists, Shot-Mix) - WNBA
# Path: pbp_engine.R
#
# WHAT THIS IS
# ------------
# Follows up on tools/research_pbp_granularity.R (read that file for the original
# exploratory findings; it is NOT modified here). That research confirmed
# wehoop::load_wnba_pbp() is real, non-empty, event-level (not possession-level)
# play-by-play with ~67 columns, and established the facts this script depends on:
#
#   - `athlete_id_1` is in the ESPN athlete-id namespace, i.e. it joins DIRECTLY
#     (integer == integer) to `cache/active_rosters_cache.rds$player_id`. It does
#     NOT match `cache/rapm_ratings.rds$player_id` at all (0/185 sampled ids
#     matched) — that is the SAME RAPM<->roster id-namespace mismatch CLAUDE.md
#     already documents for those two caches, just confirmed to extend to this
#     PBP feed too. This script therefore joins PBP -> roster directly on
#     `player_id` and never touches rapm_ratings.rds or join_rapm_to_roster() —
#     there is nothing to bridge here.
#   - On a made-shot event (`scoring_play == TRUE & shooting_play == TRUE`),
#     `athlete_id_1`/`athlete_name_1` is the SCORER and `athlete_id_2`/
#     `athlete_name_2` (populated ~30% of the time) is the ASSISTER.
#   - `points_attempted` (2 or 3) is populated on EVERY shot attempt including
#     misses, unlike `score_value` (populated only on makes) — used here for shot
#     value / 3PA detection instead of score_value.
#   - `home_score`/`away_score` are RUNNING totals AFTER each event.
#
# WHAT IS REAL vs. FALLBACK HERE (mirrors the documentary style of rapm_engine.R /
# shot_quality_engine.R / player_props_engine.R::get_team_def_rapm()'s neutral()):
#   - REAL_CURRENT_SEASON: player has >=1 PBP event in CURRENT_SEASON. Metrics
#     computed from CURRENT_SEASON events only.
#   - REAL_HISTORICAL_FALLBACK: player has zero CURRENT_SEASON PBP events (e.g. a
#     rookie who debuted after the pull, or genuinely zero clutch/shot events yet)
#     but the PBP cache itself loaded successfully. Metrics computed from the full
#     ALL_SEASONS-spanning pull instead (same coalesce-to-history pattern
#     player_props_engine.R::build_real_rotation_table() uses for box stats). If a
#     player also has zero events across all cached history, this label is still
#     used (fallback WAS attempted; the honest result is legitimately 0/NA, not a
#     data-availability failure) — this is deliberately distinct from...
#   - PBP_UNAVAILABLE: the PBP cache failed to build entirely (zero seasons
#     pulled successfully) or the roster cache itself is missing, i.e. there is no
#     real data source to even attempt a fallback against. Every metric column is
#     NA/0 in this case, never a fabricated number, exactly like
#     get_team_def_rapm()'s neutral() fallback for a missing rapm_ratings.rds.
#
# CACHE PATHS
# -----------
#   - PBP event cache:      CACHE_PBP_RAW (config.R)             = wnba_espn_pbp_cache.rds
#   - Output feature cache: CACHE_PLAYER_PBP_FEATURES (config.R) = player_pbp_features.rds
#   UPDATE (2026-09-17): promoted from bare literals to config.R constants once
#   run_full_pipeline.R (stage wiring) and app.R (dashboard tab) became additional
#   consumers of the feature cache — this is now a multi-consumer path, exactly the
#   threshold CLAUDE.md's standings-cache note describes for centralizing a literal.
#
# *** REAL NAME/PATH COLLISION DISCOVERED AND AVOIDED (2026-09-17) ***
# rapm_engine.R ALREADY defines a function called `load_or_build_wnba_pbp_cache()`
# that caches to the exact same literal path this task originally specified —
# `file.path(CACHE_DIR, "wnba_pbp_cache.rds")` — but it pulls completely different
# data (`wehoop::load_wnba_stats_possessions()`/`load_wnba_stats_shots()`, the
# WNBA-Stats-API possession/shot ID namespace RAPM uses, NOT ESPN's event-level
# `load_wnba_pbp()` this script needs). Confirmed empirically: an existing
# cache/wnba_pbp_cache.rds on disk (RAPM's possessions list, built 2026-09-12) was
# loaded by this script's first draft and crashed downstream code expecting an
# ESPN PBP tibble, because `nrow()` on RAPM's `list` object returns NULL/NA.
# Using the same filename would have meant whichever engine's cache-build runs
# LAST silently overwrites the other's file, and whichever engine's function
# definition is source()'d last in a shared R session (e.g. run_full_pipeline.R)
# wins the function-name collision. To avoid this, this script's function and
# cache path are named `load_or_build_wnba_espn_pbp_cache()` /
# `wnba_espn_pbp_cache.rds` instead of the plain names — a deliberate, documented
# deviation from how the task was originally phrased, made for real-collision-
# avoidance reasons rather than style preference. `compute_player_pbp_features()`
# still calls this renamed function directly, so callers of the public entry
# point are unaffected.
#
# EXPLICITLY NOT ATTEMPTED
# -------------------------
#   - No lineup reconstruction / on-off plus-minus from substitution events (out
#     of scope; possession-level lineup work already belongs to rapm_engine.R).
#   - No attempt to force pct_rim / pct_off_dribble_jumper / pct_catch_shoot_jumper
#     (a 2PA-only, type_text-keyword taxonomy) and pct_three (a points_attempted-
#     based, ALL-shots fraction) into one mutually exclusive breakdown — they are
#     reported on two different denominators on purpose (see comments below);
#     forcing them together would either double-count or silently drop 3PA shots
#     that also carry off-dribble-style type_text (e.g. "Pullup Jump Shot" from
#     three-point range).
#   - No join to rapm_ratings.rds (see namespace note above).
#   - Not wired into run_full_pipeline.R — that is a deliberately separate
#     follow-up step.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(wehoop)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "pbp_engine.R"

# NOT "wnba_pbp_cache.rds" — see the header's "REAL NAME/PATH COLLISION DISCOVERED
# AND AVOIDED" note. That literal is already owned by rapm_engine.R for a
# completely different (WNBA-Stats-API possession-level) dataset.
# Now config.R constants (promoted 2026-09-17 once run_full_pipeline.R + app.R
# became additional consumers) — see config.R's cache-filepath block for rationale.
CACHE_PBP_EVENTS   <- CACHE_PBP_RAW
CACHE_PBP_FEATURES <- CACHE_PLAYER_PBP_FEATURES

# Contract column list every consumer can rely on existing, in this exact order,
# even in the PBP_UNAVAILABLE fallback path.
PBP_FEATURE_COLS <- c(
  "player_id", "player_name", "team_abbreviation", "data_source",
  "fga_total", "clutch_points", "clutch_fga", "clutch_fg_pct", "clutch_scoring_plays",
  "assists", "pct_rim", "pct_off_dribble_jumper", "pct_catch_shoot_jumper", "pct_three"
)

# ------------------------------------------------------------------------------------------
# 1. Chunked per-season PBP pull with cache, retry/backoff, and skip-on-failure.
#
# Mirrors player_metrics.R::get_player_box_scores_chunked()'s pattern EXCEPT for one
# deliberate difference: that function stop()s the whole pipeline if a single season
# fails after MAX_RETRIES. This script does NOT — a full ALL_SEASONS PBP pull is a much
# bigger/slower ask (event-level, not game-level, rows) than a box-score pull, and the
# spec for this script explicitly requires "skip a season that errors with a message,
# don't abort the whole pull." Only a TOTAL failure (zero seasons succeed) gives up,
# returning NULL for the caller to handle via the fail-safe path in
# compute_player_pbp_features().
# ------------------------------------------------------------------------------------------
load_or_build_wnba_espn_pbp_cache <- function(seasons = ALL_SEASONS, force_refresh = FALSE) {
  if (file.exists(CACHE_PBP_EVENTS) && !force_refresh) {
    message(sprintf("[PBP] Loading cached play-by-play from: %s", CACHE_PBP_EVENTS))
    return(readRDS(CACHE_PBP_EVENTS))
  }

  message("[PBP] Cache not found (or force_refresh=TRUE). Pulling per-season with retry/backoff...")
  season_dfs <- list()

  for (s in seasons) {
    message(sprintf("  -> Ingesting PBP for season %d...", s))
    s_data <- NULL
    for (attempt in 1:MAX_RETRIES) {
      s_data <- tryCatch({
        wehoop::load_wnba_pbp(seasons = s)
      }, error = function(e) {
        warning(sprintf("     Attempt %d failed for PBP season %d: %s", attempt, s, e$message))
        log_error(sprintf("wehoop::load_wnba_pbp() attempt %d/%d failed for season %d.",
                           attempt, MAX_RETRIES, s),
                  condition = e, call = "load_or_build_wnba_espn_pbp_cache()", season = s, attempt = attempt)
        Sys.sleep(RATE_LIMIT_SLEEP_SEC * 2)
        NULL
      })
      if (!is.null(s_data) && nrow(s_data) > 0) break
      s_data <- NULL
    }

    if (is.null(s_data)) {
      # Deliberately NOT stop()-ing here (unlike get_player_box_scores_chunked()) —
      # a single bad/rate-limited season should not sacrifice every other season's
      # already-successful pull.
      log_error(sprintf("Skipping PBP season %d after %d failed attempts.", s, MAX_RETRIES),
                call = "load_or_build_wnba_espn_pbp_cache()", season = s, max_retries = MAX_RETRIES)
      message(sprintf("  -> Skipping season %d (failed after %d attempts).", s, MAX_RETRIES))
      next
    }

    log_info(sprintf("Ingested %d PBP event rows for season %d.", nrow(s_data), s),
             call = "load_or_build_wnba_espn_pbp_cache()", season = s, rows = nrow(s_data))
    season_dfs[[as.character(s)]] <- s_data
    Sys.sleep(RATE_LIMIT_SLEEP_SEC)
  }

  if (length(season_dfs) == 0) {
    log_error("Zero PBP seasons succeeded — returning NULL, caller must fail-safe.",
              call = "load_or_build_wnba_espn_pbp_cache()")
    message("[PBP] All seasons failed. Returning NULL (no cache written).")
    return(NULL)
  }

  all_pbp <- bind_rows(season_dfs)
  saveRDS(all_pbp, CACHE_PBP_EVENTS)
  message(sprintf("[PBP] Ingestion complete. Cached %d PBP event rows across %d/%d requested seasons.",
                  nrow(all_pbp), length(season_dfs), length(seasons)))
  log_info(sprintf("Cached %d total PBP event rows across %d/%d requested seasons.",
                   nrow(all_pbp), length(season_dfs), length(seasons)),
           call = "load_or_build_wnba_espn_pbp_cache()", rows = nrow(all_pbp), out_path = CACHE_PBP_EVENTS)
  all_pbp
}

# ------------------------------------------------------------------------------------------
# 2. Per-player feature computation from one PBP event table (either the CURRENT_SEASON
#    slice or the full ALL_SEASONS-spanning table). Called twice by
#    compute_player_pbp_features() — once per cut — and coalesced there.
#
# CLUTCH DEFINITION (documented per the spec's "pick one and be consistent" instruction):
#   period >= 4 (4th quarter or any OT period, since OT periods are period 5+)
#   AND (clock_minutes*60 + clock_seconds) <= 300   (last 5 minutes of that period)
#   AND abs(home_score - away_score) <= 5           (margin at that event)
#   Score margin uses home_score/away_score AS STORED ON THE EVENT ROW, i.e. the
#   running score AFTER that event has been applied (confirmed by research: these
#   are post-event running totals) — chosen over back-deriving a pre-event score
#   because it requires no extra computation and is consistent event-to-event.
#
# SHOT-MIX KEYWORD RULES (against `type_text`, case-insensitive, applied only to
# shooting_play==TRUE events where the player is the shooter, athlete_id_1):
#   pct_three            : points_attempted == 3, as a fraction of ALL shooting_play
#                          events (fga_total) — i.e. of every shot, real or missed,
#                          any range. Orthogonal to the three buckets below.
#   Within 2PA shots only (points_attempted == 2), classified with precedence
#   rim > off_dribble > catch_shoot to keep the three buckets mutually exclusive of
#   each other (but NOT exclusive against pct_three's separate denominator):
#     pct_rim               : type_text matches Layup/Dunk/Putback/Tip Shot/Tip-In.
#     pct_off_dribble_jumper : type_text matches Pullup/Step Back/Turnaround/
#                              "Driving Floating"/Fade Away/plain "Floating Jump
#                              Shot" (a floater is definitionally off the dribble).
#     pct_catch_shoot_jumper : type_text is EXACTLY "Jump Shot" or "Jump Shot Bank"
#                              (trimmed) — i.e. no driving/pullup/stepback/
#                              turnaround/fadeaway/floating qualifier at all.
#   Any 2PA type_text matching none of the three (e.g. "Running Jump Shot", "Hook
#   Shot", "Layup Driving Reverse" edge cases not explicitly listed above) is left
#   unclassified: it still counts in the 2PA denominator but not in any numerator,
#   so the three pct_* values need not sum to 1. Documented tradeoff per the task
#   spec's "clarity over cleverness" instruction rather than guessing at an exact
#   keyword for every one of the ~120 distinct type_text values.
# ------------------------------------------------------------------------------------------
.RIM_KW          <- "(?i)layup|dunk|putback|tip shot|tip-in|tip in"
.OFF_DRIBBLE_KW  <- "(?i)pullup|pull-up|step ?back|turnaround|driving floating|fade ?away"
.CATCH_SHOOT_RE  <- "(?i)^jump shot( bank)?$"

build_pbp_player_features <- function(pbp_subset) {
  empty <- tibble(
    player_id = integer(0), fga_total = integer(0),
    clutch_points = numeric(0), clutch_fga = integer(0),
    clutch_fg_pct = numeric(0), clutch_scoring_plays = integer(0),
    assists = integer(0), pct_rim = numeric(0), pct_off_dribble_jumper = numeric(0),
    pct_catch_shoot_jumper = numeric(0), pct_three = numeric(0)
  )
  if (is.null(pbp_subset) || nrow(pbp_subset) == 0) return(empty)

  # --- shot-mix + fga_total (as shooter, athlete_id_1) ---
  shots <- pbp_subset |>
    filter(shooting_play == TRUE, !is.na(athlete_id_1))

  fga_tbl <- shots |>
    group_by(player_id = athlete_id_1) |>
    summarise(fga_total = n(), .groups = "drop")

  three_tbl <- shots |>
    filter(points_attempted == 3) |>
    group_by(player_id = athlete_id_1) |>
    summarise(three_fga = n(), .groups = "drop")

  two_pa <- shots |>
    filter(points_attempted == 2) |>
    mutate(
      tt_trim   = trimws(type_text),
      is_rim    = grepl(.RIM_KW, tt_trim, perl = TRUE),
      is_dribble = !is_rim & grepl(.OFF_DRIBBLE_KW, tt_trim, perl = TRUE),
      is_catch  = !is_rim & !is_dribble & grepl(.CATCH_SHOOT_RE, tt_trim, perl = TRUE)
    )

  mix_tbl <- two_pa |>
    group_by(player_id = athlete_id_1) |>
    summarise(
      two_pa_total = n(),
      rim_n        = sum(is_rim, na.rm = TRUE),
      dribble_n    = sum(is_dribble, na.rm = TRUE),
      catch_n      = sum(is_catch, na.rm = TRUE),
      .groups = "drop"
    )

  # --- clutch (see clutch definition comment above) ---
  clutch_window <- pbp_subset |>
    filter(
      period >= 4,
      (clock_minutes * 60 + clock_seconds) <= 300,
      abs(home_score - away_score) <= 5
    )

  clutch_fga_tbl <- clutch_window |>
    filter(shooting_play == TRUE, !is.na(athlete_id_1)) |>
    group_by(player_id = athlete_id_1) |>
    summarise(
      clutch_fga           = n(),
      clutch_makes_n        = sum(scoring_play == TRUE, na.rm = TRUE),
      .groups = "drop"
    )

  clutch_pts_tbl <- clutch_window |>
    filter(scoring_play == TRUE, shooting_play == TRUE, !is.na(athlete_id_1)) |>
    group_by(player_id = athlete_id_1) |>
    summarise(
      clutch_points        = sum(score_value, na.rm = TRUE),
      clutch_scoring_plays = n(),
      .groups = "drop"
    )

  # --- assists: player is athlete_id_2 on a qualifying made shot ---
  assist_tbl <- pbp_subset |>
    filter(scoring_play == TRUE, shooting_play == TRUE, !is.na(athlete_id_2)) |>
    group_by(player_id = athlete_id_2) |>
    summarise(assists = n(), .groups = "drop")

  out <- fga_tbl |>
    full_join(three_tbl,      by = "player_id") |>
    full_join(mix_tbl,        by = "player_id") |>
    full_join(clutch_fga_tbl, by = "player_id") |>
    full_join(clutch_pts_tbl, by = "player_id") |>
    full_join(assist_tbl,     by = "player_id") |>
    mutate(
      fga_total            = coalesce(fga_total, 0L),
      three_fga            = coalesce(three_fga, 0L),
      two_pa_total         = coalesce(two_pa_total, 0L),
      rim_n                = coalesce(rim_n, 0L),
      dribble_n            = coalesce(dribble_n, 0L),
      catch_n              = coalesce(catch_n, 0L),
      clutch_fga           = coalesce(clutch_fga, 0L),
      clutch_makes_n       = coalesce(clutch_makes_n, 0L),
      clutch_points        = coalesce(clutch_points, 0),
      clutch_scoring_plays = coalesce(clutch_scoring_plays, 0L),
      assists              = coalesce(assists, 0L),
      clutch_fg_pct        = if_else(clutch_fga > 0, clutch_makes_n / clutch_fga, NA_real_),
      pct_rim              = if_else(two_pa_total > 0, rim_n / two_pa_total, NA_real_),
      pct_off_dribble_jumper = if_else(two_pa_total > 0, dribble_n / two_pa_total, NA_real_),
      pct_catch_shoot_jumper = if_else(two_pa_total > 0, catch_n / two_pa_total, NA_real_),
      pct_three            = if_else(fga_total > 0, three_fga / fga_total, NA_real_)
    ) |>
    select(player_id, fga_total, clutch_points, clutch_fga, clutch_fg_pct,
           clutch_scoring_plays, assists, pct_rim, pct_off_dribble_jumper,
           pct_catch_shoot_jumper, pct_three)

  out
}

# ------------------------------------------------------------------------------------------
# 3. Main entry point. One row per active-roster player, contract columns per
#    PBP_FEATURE_COLS above. Fail-safe: never crashes, never fabricates a stat.
# ------------------------------------------------------------------------------------------
compute_player_pbp_features <- function(pbp = NULL, force_refresh = FALSE) {
  roster_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")

  unavailable_from <- function(roster_df) {
    if (is.null(roster_df) || nrow(roster_df) == 0) {
      message("[PBP WARNING] No roster data available either — returning a zero-row feature table.")
      return(tibble(
        player_id = integer(0), player_name = character(0), team_abbreviation = character(0),
        data_source = character(0), fga_total = integer(0), clutch_points = numeric(0),
        clutch_fga = integer(0), clutch_fg_pct = numeric(0), clutch_scoring_plays = integer(0),
        assists = integer(0), pct_rim = numeric(0), pct_off_dribble_jumper = numeric(0),
        pct_catch_shoot_jumper = numeric(0), pct_three = numeric(0)
      ))
    }
    roster_df |>
      distinct(player_id, player_name, team_abbreviation) |>
      mutate(
        data_source = "PBP_UNAVAILABLE",
        fga_total = 0L, clutch_points = NA_real_, clutch_fga = 0L,
        clutch_fg_pct = NA_real_, clutch_scoring_plays = 0L, assists = 0L,
        pct_rim = NA_real_, pct_off_dribble_jumper = NA_real_,
        pct_catch_shoot_jumper = NA_real_, pct_three = NA_real_
      ) |>
      select(all_of(PBP_FEATURE_COLS))
  }

  if (!file.exists(roster_path)) {
    message(sprintf("[PBP WARNING] %s not found — cannot build a real player universe.", roster_path))
    log_error(sprintf("%s missing.", roster_path), call = "compute_player_pbp_features()")
    return(unavailable_from(NULL))
  }
  roster <- readRDS(roster_path) |> distinct(player_id, player_name, team_abbreviation)

  if (is.null(pbp)) {
    pbp <- load_or_build_wnba_espn_pbp_cache(seasons = ALL_SEASONS, force_refresh = force_refresh)
  }

  if (is.null(pbp) || nrow(pbp) == 0) {
    message("[PBP WARNING] No PBP data available (pull failed for every season) — every metric set to PBP_UNAVAILABLE.")
    log_error("PBP data unavailable for feature computation.", call = "compute_player_pbp_features()")
    return(unavailable_from(roster))
  }

  cur_pbp <- pbp |> filter(season == CURRENT_SEASON)

  cur_feats  <- build_pbp_player_features(cur_pbp)
  hist_feats <- build_pbp_player_features(pbp)

  # Player is considered to have real CURRENT_SEASON data if they appear as either
  # shooter or assister anywhere in the CURRENT_SEASON slice (broader than just
  # fga_total > 0, so an assist-only or clutch-only appearance still counts as
  # "real current season", not a spurious fallback).
  cur_present_ids <- union(
    unique(na.omit(cur_pbp$athlete_id_1)),
    unique(na.omit(cur_pbp$athlete_id_2))
  )
  hist_present_ids <- union(
    unique(na.omit(pbp$athlete_id_1)),
    unique(na.omit(pbp$athlete_id_2))
  )

  metric_cols <- c("fga_total", "clutch_points", "clutch_fga", "clutch_fg_pct",
                    "clutch_scoring_plays", "assists", "pct_rim",
                    "pct_off_dribble_jumper", "pct_catch_shoot_jumper", "pct_three")

  names(hist_feats)[names(hist_feats) %in% metric_cols] <-
    paste0(metric_cols[metric_cols %in% names(hist_feats)], "_hist")

  out <- roster |>
    left_join(cur_feats, by = "player_id") |>
    left_join(hist_feats, by = "player_id") |>
    mutate(
      data_source = case_when(
        player_id %in% cur_present_ids  ~ "REAL_CURRENT_SEASON",
        player_id %in% hist_present_ids ~ "REAL_HISTORICAL_FALLBACK",
        TRUE                            ~ "REAL_HISTORICAL_FALLBACK"
        # (Both non-matching branches resolve to the same label: the PBP cache
        # itself loaded fine, this specific player just has zero recorded events
        # in either cut — a legitimate 0/NA result, not a data-availability
        # failure. Reserve PBP_UNAVAILABLE strictly for "no PBP cache at all".)
      ),
      fga_total              = coalesce(fga_total, fga_total_hist, 0L),
      clutch_points          = coalesce(clutch_points, clutch_points_hist, 0),
      clutch_fga             = coalesce(clutch_fga, clutch_fga_hist, 0L),
      clutch_fg_pct          = coalesce(clutch_fg_pct, clutch_fg_pct_hist),
      clutch_scoring_plays   = coalesce(clutch_scoring_plays, clutch_scoring_plays_hist, 0L),
      assists                = coalesce(assists, assists_hist, 0L),
      pct_rim                = coalesce(pct_rim, pct_rim_hist),
      pct_off_dribble_jumper = coalesce(pct_off_dribble_jumper, pct_off_dribble_jumper_hist),
      pct_catch_shoot_jumper = coalesce(pct_catch_shoot_jumper, pct_catch_shoot_jumper_hist),
      pct_three              = coalesce(pct_three, pct_three_hist)
    ) |>
    select(all_of(PBP_FEATURE_COLS))

  n_hist <- sum(out$data_source == "REAL_HISTORICAL_FALLBACK")
  if (n_hist > 0) {
    message(sprintf("[PBP] %d/%d roster players had no CURRENT_SEASON PBP events — flagged REAL_HISTORICAL_FALLBACK (full ALL_SEASONS history used, or zero events at all if truly none cached).",
                    n_hist, nrow(out)))
  }

  saveRDS(out, CACHE_PBP_FEATURES)
  message(sprintf("[PBP] Wrote %d player rows to %s", nrow(out), CACHE_PBP_FEATURES))
  log_info(sprintf("Wrote %d player PBP feature rows.", nrow(out)),
           call = "compute_player_pbp_features()", rows = nrow(out), out_path = CACHE_PBP_FEATURES)

  out
}

if (!interactive()) {
  invisible(compute_player_pbp_features())
}
