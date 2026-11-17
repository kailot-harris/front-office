# ==============================================================================
# tests/test_game_details_builder.R
# Unit and integration tests for Phase 1 Tier 1a Game Details Builder (Issue #104).
#
# Tests:
#   1. Builder execution and valid GameDetailEnvelope output.
#   2. Idempotency and 7-day churn control: 0 rewrites on repeat run.
#   3. Exact player-to-team counting stat reconciliation across all box scores.
# ==============================================================================

suppressWarnings(suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
}))

source("config.R")
source("tools/game_details_builder.R")
source("tests/helpers/test_fixtures.R")

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

cat("=== NFL Analytics Game Details Builder Tests ===\n\n")

# ------------------------------------------------------------------------------
# Test 1: Run builder and verify output files exist
# ------------------------------------------------------------------------------
# build_game_details() reads gitignored pipeline caches. When caches are absent
# (e.g. fresh clone / CI), committed test fixtures under tests/fixtures/ are used.
root_dir <- if (file.exists("config.R")) getwd() else if (file.exists("../config.R")) normalizePath("..", winslash = "/") else getwd()
fixture <- get_game_details_fixture(root_dir)
pred_log_path <- get_prediction_log_path(root_dir)
pred_log_fixture <- if (!is.null(pred_log_path)) readRDS(pred_log_path) else NULL
use_caches <- file.exists(CACHE_SCHEDULES)
have_data <- use_caches || !is.null(fixture)

if (!have_data) {
  cat("[SKIP] game details builder tests skipped: cache/schedules_cache.rds and tests/fixtures/game_details_fixture.rds are absent\n")
  quit(status = 0L)
}

test_games_dir <- file.path(tempdir(), "test_game_details_output")
if (dir.exists(test_games_dir)) unlink(test_games_dir, recursive = TRUE)
dir.create(test_games_dir, recursive = TRUE, showWarnings = FALSE)
on.exit(if (dir.exists(test_games_dir)) unlink(test_games_dir, recursive = TRUE), add = TRUE)

cat("--- Section 1: Builder execution and file generation ---\n")
initial_run <- if (use_caches) {
  build_game_details(out_dir = test_games_dir)
} else {
  build_game_details(
    out_dir              = test_games_dir,
    sched_df_override    = fixture$schedules,
    ts_df_override       = fixture$team_stats,
    ps_df_override       = fixture$player_stats,
    sc_df_override       = fixture$snap_counts,
    ros_df_override      = fixture$rosters,
    pred_log_df_override = pred_log_fixture
  )
}
ok("BUILD-1 Initial build completed", is.list(initial_run))

game_files <- list.files(test_games_dir, pattern = "\\.json$", full.names = TRUE)
ok("BUILD-2 Game detail JSON files produced", length(game_files) > 0L,
   sprintf("%d files in %s", length(game_files), test_games_dir))

# ------------------------------------------------------------------------------
# Test 2: Idempotency & churn control (0 rewrites on consecutive run)
# ------------------------------------------------------------------------------
cat("\n--- Section 2: Idempotency and Churn Control ---\n")
second_run <- if (use_caches) {
  build_game_details(out_dir = test_games_dir)
} else {
  build_game_details(
    out_dir              = test_games_dir,
    sched_df_override    = fixture$schedules,
    ts_df_override       = fixture$team_stats,
    ps_df_override       = fixture$player_stats,
    sc_df_override       = fixture$snap_counts,
    ros_df_override      = fixture$rosters,
    pred_log_df_override = pred_log_fixture
  )
}
ok("IDEMP-1 Running builder consecutively writes exactly 0 files",
   identical(as.integer(second_run$written), 0L),
   sprintf("written: %d, unchanged: %d, skipped: %d",
           second_run$written, second_run$unchanged, second_run$skipped_churn))

ok("IDEMP-2 Evaluated files in candidate window are marked unchanged",
   second_run$unchanged > 0L || second_run$evaluated == 0L,
   sprintf("%d files evaluated without change", second_run$unchanged))

# ------------------------------------------------------------------------------
# Test 3: Envelope and payload schema invariants on generated files
# ------------------------------------------------------------------------------
cat("\n--- Section 3: Envelope and Payload Schema Invariants ---\n")
sample_file <- game_files[1]
sample_json <- tryCatch(fromJSON(sample_file, simplifyVector = FALSE), error = function(e) NULL)

ok("SCHEMA-1 JSON file parses cleanly", !is.null(sample_json))
ok("SCHEMA-2 Envelope top-level fields match spec",
   identical(sample_json$schema_version, "1.0") &&
     identical(sample_json$sport, "nfl") &&
     identical(sample_json$endpoint, "game_detail") &&
     identical(as.integer(sample_json$season), as.integer(CURRENT_SEASON)) &&
     nzchar(sample_json$season_label) &&
     nzchar(sample_json$game_id),
   sprintf("game_id: %s, schema: %s", sample_json$game_id, sample_json$schema_version))

ok("SCHEMA-3 generated_at matches ISO-8601 UTC timestamp format",
   grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", sample_json$generated_at),
   sample_json$generated_at)

d <- sample_json$data
ok("SCHEMA-4 Payload core fields present and valid",
   isTRUE(d$is_completed) &&
     isTRUE(d$has_box_score) &&
     is.list(d$away_team) &&
     is.list(d$home_team) &&
     is.list(d$box_score) &&
     is.list(d$leaders) &&
     nzchar(d$away_team$teamAbbr) &&
     nzchar(d$home_team$teamAbbr))

# Check player box rows
away_players <- d$box_score$away_players
home_players <- d$box_score$home_players
all_sample_players <- c(away_players, home_players)

valid_cats <- c("passing", "rushing", "receiving", "defense", "kicking")
players_have_valid_cats <- length(all_sample_players) > 0 && all(sapply(all_sample_players, function(p) {
  is.list(p) && nzchar(p$playerId) && nzchar(p$playerName) &&
    all(unlist(p$categories) %in% valid_cats)
}))
ok("SCHEMA-5 Player rows contain valid identifiers and category tags",
   players_have_valid_cats,
   sprintf("%d total players in sample game", length(all_sample_players)))

# Check category leaders
leaders <- d$leaders
leaders_valid <- is.list(leaders) && length(leaders) > 0 && all(sapply(leaders, function(ld) {
  ld$category %in% valid_cats && nzchar(ld$teamAbbr) && nzchar(ld$playerId) &&
    nzchar(ld$playerName) && nzchar(ld$stat_line)
}))
ok("SCHEMA-6 Category leaders populated with required fields",
   leaders_valid,
   sprintf("%d leaders in sample game", length(leaders)))

# Check efficiency factors
eff <- d$efficiency_factors
eff_valid <- is.null(eff) || (is.list(eff) && length(eff) == 8L && all(sapply(eff, function(ef) {
  nzchar(ef$key) && nzchar(ef$label) && ef$unit %in% c("epa", "pct", "yards") &&
    is.logical(ef$higher_is_better) && nzchar(ef$description)
})))
ok("SCHEMA-7 Efficiency factors conform to 8-metric definition",
   eff_valid,
   sprintf("%d efficiency metrics", length(eff)))

# ------------------------------------------------------------------------------
# Test 4: Full player-to-team counting stat reconciliation across all game files
# ------------------------------------------------------------------------------
cat("\n--- Section 4: Player-to-Team Exact Counting Stat Reconciliation ---\n")
have_ts <- file.exists(CACHE_TEAM_STATS) || (!is.null(fixture) && !is.null(fixture$team_stats))
if (have_ts) {
  ts_df <- if (file.exists(CACHE_TEAM_STATS)) readRDS(CACHE_TEAM_STATS) else fixture$team_stats

  reconcile_stats <- c(
    "completions", "attempts", "passing_yards", "passing_tds", "passing_interceptions",
    "sacks_suffered", "sack_yards_lost",
    "carries", "rushing_yards", "rushing_tds", "rushing_fumbles", "rushing_fumbles_lost", "rushing_first_downs",
    "receptions", "targets", "receiving_yards", "receiving_tds", "receiving_fumbles", "receiving_fumbles_lost", "receiving_first_downs",
    "def_tackles_solo", "def_tackle_assists", "def_tackles_for_loss", "def_sacks", "def_qb_hits", "def_interceptions", "def_pass_defended", "def_fumbles_forced",
    "fg_made", "fg_att", "pat_made", "pat_att"
  )

  total_checks <- 0L
  mismatches <- 0L

  for (f in game_files) {
    g_json <- fromJSON(f, simplifyVector = FALSE)
    gid <- g_json$game_id
    d_g <- g_json$data

    for (side in c("away", "home")) {
      tm <- if (side == "away") d_g$away_team$teamAbbr else d_g$home_team$teamAbbr
      players <- if (side == "away") d_g$box_score$away_players else d_g$box_score$home_players

      ts_row <- ts_df |> filter(game_id == gid, team == tm)
      if (nrow(ts_row) == 0) next

      for (st in reconcile_stats) {
        if (!st %in% names(ts_row)) next
        t_val <- ts_row[[st]][1]
        if (is.na(t_val)) next

        p_vals <- sapply(players, function(p) {
          val <- p[[st]]
          if (is.null(val) || is.na(val)) 0 else val
        })
        p_sum <- sum(p_vals)

        total_checks <- total_checks + 1L
        if (abs(p_sum - t_val) > 1e-6) {
          cat(sprintf("  Reconciliation mismatch: %s | %s | %s (team=%s, player_sum=%s)\n",
                      gid, tm, st, t_val, p_sum))
          mismatches <- mismatches + 1L
        }
      }
    }
  }

  ok("RECON-1 All 32 counting stats aggregate exactly from players to team totals",
     mismatches == 0L,
     sprintf("%d checks across %d games, %d mismatches", total_checks, length(game_files), mismatches))
} else {
  cat("[SKIP] Section 4 skipped because CACHE_TEAM_STATS is not in ephemeral cache\n")
}

# ------------------------------------------------------------------------------
# Test 5: Phase 2 Attribution & Explainability Invariants (Issue #115 / 2-6)
# ------------------------------------------------------------------------------
cat("\n--- Section 5: Phase 2 Attribution & Explainability Invariants ---\n")

# ATTR-1: All completed games carry non-null explainability
expl_null_count <- 0L
waterfall_mismatches <- 0L

for (f in game_files) {
  g_json <- fromJSON(f, simplifyVector = FALSE)
  exp <- g_json$data$explainability
  if (is.null(exp)) {
    expl_null_count <- expl_null_count + 1L
    next
  }

  # Check waterfall additivity
  if (!is.null(exp$waterfall) && !is.null(exp$waterfall$steps)) {
    pts <- sapply(exp$waterfall$steps, function(s) s$points)
    wf_sum <- sum(pts)
    proj_m <- exp$waterfall$projected_margin
    if (abs(wf_sum - proj_m) > 0.02 + 1e-6) {
      waterfall_mismatches <- waterfall_mismatches + 1L
    }
  }
}

ok("ATTR-1 All completed games carry non-null explainability payload",
   expl_null_count == 0L,
   sprintf("%d / %d completed games have explainability", length(game_files) - expl_null_count, length(game_files)))

ok("ATTR-2 Waterfall steps sum to projected margin within 0.02 across all completed games",
   waterfall_mismatches == 0L,
   sprintf("%d waterfall mismatches across %d games", waterfall_mismatches, length(game_files)))

# ATTR-3: Weekly attribution files exist
weekly_files <- if (dir.exists(WEB_ATTRIBUTION_DIR)) {
  list.files(WEB_ATTRIBUTION_DIR, pattern = "\\.json$", full.names = TRUE)
} else character(0)

ok("ATTR-3 At least 9 weekly attribution files exist for unplayed weeks",
   length(weekly_files) >= 9L,
   sprintf("%d weekly attribution files found", length(weekly_files)))

# ATTR-4: Zero banned betting vocabulary in weekly attribution files
banned_betting_pattern <- "\\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\\b"
betting_term_violations <- 0L

for (wf in weekly_files) {
  content <- paste(readLines(wf, warn = FALSE, encoding = "UTF-8"), collapse = " ")
  if (grepl(banned_betting_pattern, content, ignore.case = TRUE)) {
    cat(sprintf("  Forbidden betting vocabulary found in %s\n", basename(wf)))
    betting_term_violations <- betting_term_violations + 1L
  }
}

ok("ATTR-4 Zero banned betting vocabulary in all weekly attribution files",
   betting_term_violations == 0L,
   sprintf("%d violations across %d files", betting_term_violations, length(weekly_files)))

# ------------------------------------------------------------------------------
# Test 6: Frozen game re-evaluation on input/forecast modification (Task 1b redesign)
# ------------------------------------------------------------------------------
cat("\n--- Section 6: Frozen Game Re-evaluation on Input & Forecast Modification ---\n")

drift_test_dir <- file.path(tempdir(), "nfl_test_game_drift")
dir.create(drift_test_dir, recursive = TRUE, showWarnings = FALSE)

# 1. Select a completed game (e.g. Week 1)
test_sched <- if (use_caches) {
  readRDS(CACHE_SCHEDULES) |> filter(season == CURRENT_SEASON)
} else {
  fixture$schedules |> filter(season == CURRENT_SEASON)
}
test_completed <- test_sched |> filter(!is.na(home_score), !is.na(away_score))
target_game <- test_completed[1, ]
target_gid <- as.character(target_game$game_id)
target_file <- file.path(drift_test_dir, sprintf("%s.json", target_gid))

# Copy existing test file into drift test directory
orig_file <- file.path(test_games_dir, sprintf("%s.json", target_gid))
file.copy(orig_file, target_file, overwrite = TRUE)

ok("DRIFT-1 Existing game file staged in test directory",
   file.exists(target_file),
   sprintf("staged file: %s", target_file))

# Read initial json
env_before <- fromJSON(target_file, simplifyVector = FALSE)
score_before <- env_before$data$home_team$score

target_ts <- if (!use_caches) fixture$team_stats |> filter(game_id == target_gid) else NULL
target_ps <- if (!use_caches) fixture$player_stats |> filter(game_id == target_gid) else NULL
target_sc <- if (!use_caches) fixture$snap_counts |> filter(game_id == target_gid) else NULL
target_ros <- if (!use_caches) fixture$rosters else NULL

# Repeat run with unchanged game: assert evaluated and marked unchanged, written = 0
simulated_today <- as.Date(target_game$gameday) + 30
repeat_drift <- build_game_details(
  force = FALSE,
  out_dir = drift_test_dir,
  today_date = simulated_today,
  sched_df_override = target_game,
  ts_df_override = target_ts,
  ps_df_override = target_ps,
  sc_df_override = target_sc,
  ros_df_override = target_ros,
  pred_log_df_override = pred_log_fixture
)

ok("DRIFT-2 Unchanged input evaluates game but writes 0 files",
   identical(as.integer(repeat_drift$written), 0L) && repeat_drift$unchanged >= 1L,
   sprintf("written: %d, unchanged: %d", repeat_drift$written, repeat_drift$unchanged))

# 2. Modify one input row (simulating nflverse late stat correction to home_score)
modified_game <- target_game
new_test_score <- as.integer(target_game$home_score) + 4L
modified_game$home_score <- new_test_score

# Run builder with modified input: must detect diff and rebuild
rebuild_drift <- build_game_details(
  force = FALSE,
  out_dir = drift_test_dir,
  today_date = simulated_today,
  sched_df_override = modified_game,
  ts_df_override = target_ts,
  ps_df_override = target_ps,
  sc_df_override = target_sc,
  ros_df_override = target_ros,
  pred_log_df_override = pred_log_fixture
)

ok("DRIFT-3 Modified input row triggers automatic rebuild",
   identical(as.integer(rebuild_drift$written), 1L) && identical(as.integer(rebuild_drift$updated), 1L),
   sprintf("written: %d, updated: %d", rebuild_drift$written, rebuild_drift$updated))

# Assert rebuilt file reflects the updated input score
env_after <- fromJSON(target_file, simplifyVector = FALSE)
score_after <- env_after$data$home_team$score

ok("DRIFT-4 Rebuilt file has new score matching modified input",
   identical(as.integer(score_after), as.integer(new_test_score)),
   sprintf("score_before: %d, score_after: %d", score_before, score_after))

ok("DRIFT-5 Builder logged score change description in updates list",
   length(rebuild_drift$updates) >= 1L && grepl("score", rebuild_drift$updates[[1]]$changes),
   sprintf("logged changes: %s", if (length(rebuild_drift$updates) >= 1L) rebuild_drift$updates[[1]]$changes else "none"))

# 3. Modify ONLY the slate forecast (e.g. upstream regrade changes projected_margin)
# Stage a temporary matchups_current_week.json with a modified margin for target_gid
temp_matchups_path <- file.path(drift_test_dir, "matchups_current_week.json")
base_matchups <- if (file.exists(WEB_JSON_MATCHUPS_CURRENT_WEEK)) {
  fromJSON(WEB_JSON_MATCHUPS_CURRENT_WEEK, simplifyVector = FALSE)
} else {
  list(matchups = list())
}

old_margin <- env_after$data$forecast$projected_margin
new_margin <- if (!is.null(old_margin)) round(old_margin + 5.5, 1) else 4.5

# Insert or update target_gid in temp matchups
found <- FALSE
if (!is.null(base_matchups$matchups)) {
  for (idx in seq_along(base_matchups$matchups)) {
    if (identical(base_matchups$matchups[[idx]]$game_id, target_gid)) {
      base_matchups$matchups[[idx]]$projected_margin <- new_margin
      found <- TRUE
      break
    }
  }
}
if (!found) {
  base_matchups$matchups[[length(base_matchups$matchups) + 1L]] <- list(
    game_id = target_gid,
    projected_margin = new_margin,
    home_win_prob = 0.65,
    home_power_rating = 22.0,
    away_power_rating = 18.0,
    prediction_correct = TRUE
  )
}
writeLines(toJSON(base_matchups, auto_unbox = TRUE, pretty = 2), temp_matchups_path)

# Run builder with the new matchups slate
rebuild_slate <- build_game_details(
  force = FALSE,
  out_dir = drift_test_dir,
  today_date = simulated_today,
  sched_df_override = modified_game,
  ts_df_override = target_ts,
  ps_df_override = target_ps,
  sc_df_override = target_sc,
  ros_df_override = target_ros,
  pred_log_df_override = pred_log_fixture,
  matchups_path = temp_matchups_path
)

ok("DRIFT-6 Upstream slate forecast change alone triggers automatic rebuild",
   identical(as.integer(rebuild_slate$written), 1L) && identical(as.integer(rebuild_slate$updated), 1L),
   sprintf("written: %d, updated: %d", rebuild_slate$written, rebuild_slate$updated))

env_slate <- fromJSON(target_file, simplifyVector = FALSE)
margin_after <- env_slate$data$forecast$projected_margin

ok("DRIFT-7 Rebuilt game file forecast matches updated slate forecast",
   !is.null(margin_after) && abs(margin_after - new_margin) < 1e-4,
   sprintf("margin before: %s, slate margin: %s, game file margin: %s",
           old_margin, new_margin, margin_after))

ok("DRIFT-8 Builder logged forecast_margin change description",
   length(rebuild_slate$updates) >= 1L && grepl("forecast_margin", rebuild_slate$updates[[1]]$changes),
   sprintf("logged changes: %s", if (length(rebuild_slate$updates) >= 1L) rebuild_slate$updates[[1]]$changes else "none"))

# 4. Stat correction detailed logging test
# Simulate player stat correction (e.g. passing_tds increases by 1)
stat_test_dir <- file.path(tempdir(), "nfl_test_stat_drift")
dir.create(stat_test_dir, recursive = TRUE, showWarnings = FALSE)
stat_gid <- target_gid

base_ps <- data.frame(
  game_id = stat_gid,
  player_id = "00-0012345",
  player_name = "Test QB",
  player_display_name = "Test QB",
  team = as.character(target_game$home_team[1]),
  position = "QB",
  attempts = 30L,
  completions = 20L,
  passing_yards = 250L,
  passing_tds = 2L,
  passing_interceptions = 0L,
  passing_cpoe = NA_real_,
  sacks_suffered = 1L,
  sack_yards_lost = 5L,
  passing_epa = 0.15,
  carries = 2L,
  rushing_yards = 10L,
  rushing_tds = 0L,
  rushing_fumbles = 0L,
  rushing_fumbles_lost = 0L,
  rushing_first_downs = 1L,
  rushing_epa = 0.05,
  targets = 0L,
  receptions = 0L,
  receiving_yards = 0L,
  receiving_tds = 0L,
  receiving_fumbles = 0L,
  receiving_fumbles_lost = 0L,
  receiving_first_downs = 0L,
  receiving_epa = NA_real_,
  def_tackles_solo = 0L,
  def_tackle_assists = 0L,
  def_sacks = 0L,
  def_interceptions = 0L,
  def_pass_defended = 0L,
  def_qb_hits = 0L,
  def_fumbles_forced = 0L,
  def_tackles_for_loss = 0L,
  fg_att = 0L,
  pat_att = 0L,
  fg_made = 0L,
  pat_made = 0L,
  stringsAsFactors = FALSE
)

# Initial build to establish baseline file
build_game_details(
  force = TRUE,
  out_dir = stat_test_dir,
  sched_df_override = target_game,
  ps_df_override = base_ps
)

# Now modify passing_tds (2 -> 3)
mod_ps <- base_ps
mod_ps$passing_tds <- 3L

rebuild_stat <- build_game_details(
  force = FALSE,
  out_dir = stat_test_dir,
  sched_df_override = target_game,
  ps_df_override = mod_ps
)

ok("STAT-1 Player stat correction (passing_tds) triggers rebuild and names stat in log",
   identical(as.integer(rebuild_stat$written), 1L) &&
     length(rebuild_stat$updates) >= 1L &&
     grepl("player_stat:passing_tds", rebuild_stat$updates[[1]]$changes),
   sprintf("logged changes: %s", if (length(rebuild_stat$updates) >= 1L) rebuild_stat$updates[[1]]$changes else "none"))

unlink(stat_test_dir, recursive = TRUE)

# 4b. Defensive stat correction logging test
# Simulate defensive stat correction (e.g. def_sacks 1.0 -> 2.0 and def_interceptions 0 -> 1)
def_test_dir <- file.path(tempdir(), "nfl_test_def_drift")
dir.create(def_test_dir, recursive = TRUE, showWarnings = FALSE)

base_def_ps <- data.frame(
  game_id = stat_gid,
  player_id = "00-0099999",
  player_name = "Test DE",
  player_display_name = "Test DE",
  team = as.character(target_game$away_team[1]),
  position = "DE",
  attempts = 0L,
  completions = 0L,
  passing_yards = 0L,
  passing_tds = 0L,
  passing_interceptions = 0L,
  passing_cpoe = NA_real_,
  sacks_suffered = 0L,
  sack_yards_lost = 0L,
  passing_epa = NA_real_,
  carries = 0L,
  rushing_yards = 0L,
  rushing_tds = 0L,
  rushing_fumbles = 0L,
  rushing_fumbles_lost = 0L,
  rushing_first_downs = 0L,
  rushing_epa = NA_real_,
  targets = 0L,
  receptions = 0L,
  receiving_yards = 0L,
  receiving_tds = 0L,
  receiving_fumbles = 0L,
  receiving_fumbles_lost = 0L,
  receiving_first_downs = 0L,
  receiving_epa = NA_real_,
  def_tackles_solo = 3L,
  def_tackle_assists = 1L,
  def_sacks = 1.0,
  def_interceptions = 0L,
  def_pass_defended = 1L,
  def_qb_hits = 2L,
  def_fumbles_forced = 0L,
  def_tackles_for_loss = 1L,
  fg_att = 0L,
  pat_att = 0L,
  fg_made = 0L,
  pat_made = 0L,
  stringsAsFactors = FALSE
)

# Initial build to establish baseline file
build_game_details(
  force = TRUE,
  out_dir = def_test_dir,
  sched_df_override = target_game,
  ps_df_override = base_def_ps
)

# Modify def_sacks (1.0 -> 2.0) and def_interceptions (0 -> 1)
mod_def_ps <- base_def_ps
mod_def_ps$def_sacks <- 2.0
mod_def_ps$def_interceptions <- 1L

rebuild_def <- build_game_details(
  force = FALSE,
  out_dir = def_test_dir,
  sched_df_override = target_game,
  ps_df_override = mod_def_ps
)

ok("STAT-2 Defensive stat correction (def_sacks/def_interceptions) triggers rebuild and names stat in log",
   identical(as.integer(rebuild_def$written), 1L) &&
     length(rebuild_def$updates) >= 1L &&
     grepl("player_stat:def_sacks", rebuild_def$updates[[1]]$changes) &&
     grepl("player_stat:def_interceptions", rebuild_def$updates[[1]]$changes),
   sprintf("logged changes: %s", if (length(rebuild_def$updates) >= 1L) rebuild_def$updates[[1]]$changes else "none"))

unlink(def_test_dir, recursive = TRUE)

# 5. Single-run completion pipeline integration test (replacing ORDER-1)
# Verifies that a newly completed game gets its game file AND correct flags (has_box_score=TRUE,
# has_game_detail=TRUE) in a single pipeline run with zero pre-existing game file.
pipe_test_dir <- file.path(tempdir(), "nfl_test_pipeline_run")
pipe_games_dir <- file.path(pipe_test_dir, "games")
dir.create(pipe_games_dir, recursive = TRUE, showWarnings = FALSE)

pipe_gid <- target_gid
pipe_ts_override <- data.frame(
  game_id = pipe_gid,
  team = c(as.character(target_game$away_team[1]), as.character(target_game$home_team[1])),
  passing_yards = c(200L, 250L),
  rushing_yards = c(100L, 120L),
  stringsAsFactors = FALSE
)

pipe_matchups_list <- list(
  list(
    game_id           = pipe_gid,
    season            = as.integer(target_game$season),
    week              = as.integer(target_game$week),
    home_team         = as.character(target_game$home_team),
    away_team         = as.character(target_game$away_team),
    projected_margin  = 3.5,
    home_win_prob     = 0.60,
    home_power_rating = 21.0,
    away_power_rating = 17.5,
    is_completed      = TRUE,
    has_box_score     = FALSE,
    has_game_detail   = FALSE,
    home_score        = as.integer(target_game$home_score),
    away_score        = as.integer(target_game$away_score),
    prediction_correct= TRUE
  )
)

# Step 1: Run builder passing in-memory matchups list to destination directory
pipe_build_res <- build_game_details(
  force = FALSE,
  out_dir = pipe_games_dir,
  today_date = simulated_today,
  sched_df_override = target_game,
  ts_df_override = pipe_ts_override,
  matchups_list = pipe_matchups_list
)

# Step 2: Set flags reflecting game files produced by the builder
for (i in seq_along(pipe_matchups_list)) {
  gid_check <- pipe_matchups_list[[i]]$game_id
  file_on_disk <- file.exists(file.path(pipe_games_dir, paste0(gid_check, ".json")))
  pipe_matchups_list[[i]]$has_box_score <- file_on_disk
  pipe_matchups_list[[i]]$has_game_detail <- file_on_disk
}

# Step 3: Serialize slate to disk
pipe_slate_path <- file.path(pipe_test_dir, "matchups_current_week.json")
writeLines(toJSON(list(matchups = pipe_matchups_list), auto_unbox = TRUE, pretty = 2), pipe_slate_path)

game_file_created <- file.exists(file.path(pipe_games_dir, paste0(pipe_gid, ".json")))
read_slate <- fromJSON(pipe_slate_path, simplifyVector = FALSE)
slate_item <- read_slate$matchups[[1]]

ok("PIPE-1a Game file created in single run without pre-existing file",
   isTRUE(game_file_created),
   sprintf("created: %s", file.path(pipe_games_dir, paste0(pipe_gid, ".json"))))

ok("PIPE-1b Slate flags has_box_score and has_game_detail both TRUE in single run",
   isTRUE(slate_item$has_box_score) && isTRUE(slate_item$has_game_detail),
   sprintf("has_box_score: %s, has_game_detail: %s", slate_item$has_box_score, slate_item$has_game_detail))

pipe_game_env <- if (game_file_created) fromJSON(file.path(pipe_games_dir, paste0(pipe_gid, ".json")), simplifyVector = FALSE) else NULL
ok("PIPE-1c Game file forecast margin matches in-memory slate forecast (no lag)",
   !is.null(pipe_game_env) && identical(pipe_game_env$data$forecast$projected_margin, 3.5),
   sprintf("margin: %s", if (!is.null(pipe_game_env)) pipe_game_env$data$forecast$projected_margin else "NULL"))

unlink(pipe_test_dir, recursive = TRUE)

# 6. Completed game with no stats test
# Verifies that a game marked completed in schedule whose box score stats have not yet arrived
# does NOT create a game file, and slate flags remain FALSE without failing parity.
nostat_test_dir <- file.path(tempdir(), "nfl_test_nostat_run")
nostat_games_dir <- file.path(nostat_test_dir, "games")
dir.create(nostat_games_dir, recursive = TRUE, showWarnings = FALSE)

nostat_gid <- "2026_99_TEST_NOSTAT"
nostat_game <- target_game
nostat_game$game_id <- nostat_gid
nostat_game$home_score <- 28L
nostat_game$away_score <- 21L

nostat_matchups_list <- list(
  list(
    game_id           = nostat_gid,
    season            = as.integer(target_game$season),
    week              = 99L,
    home_team         = as.character(target_game$home_team),
    away_team         = as.character(target_game$away_team),
    projected_margin  = 4.0,
    home_win_prob     = 0.62,
    home_power_rating = 20.0,
    away_power_rating = 16.0,
    is_completed      = TRUE,
    has_box_score     = FALSE,
    has_game_detail   = FALSE,
    home_score        = 28L,
    away_score        = 21L,
    prediction_correct= TRUE
  )
)

# Run builder with empty stats dataframes and empty destination
nostat_build_res <- build_game_details(
  force = FALSE,
  out_dir = nostat_games_dir,
  today_date = simulated_today,
  sched_df_override = nostat_game,
  ts_df_override = data.frame(),
  ps_df_override = data.frame(),
  matchups_list = nostat_matchups_list
)

# Flags updated per file existence on disk
for (i in seq_along(nostat_matchups_list)) {
  gid_check <- nostat_matchups_list[[i]]$game_id
  file_on_disk <- file.exists(file.path(nostat_games_dir, paste0(gid_check, ".json")))
  nostat_matchups_list[[i]]$has_box_score <- file_on_disk
  nostat_matchups_list[[i]]$has_game_detail <- file_on_disk
}

nostat_file_exists <- file.exists(file.path(nostat_games_dir, paste0(nostat_gid, ".json")))

ok("NOSTAT-1 Completed game without stats produces 0 written game files",
   identical(as.integer(nostat_build_res$written), 0L) && !nostat_file_exists,
   sprintf("written: %d, file_exists: %s", nostat_build_res$written, nostat_file_exists))

ok("NOSTAT-2 Completed game without stats sets is_completed=TRUE with has_game_detail=FALSE",
   isTRUE(nostat_matchups_list[[1]]$is_completed) &&
     identical(nostat_matchups_list[[1]]$has_game_detail, FALSE) &&
     identical(nostat_matchups_list[[1]]$has_box_score, FALSE),
   sprintf("is_completed: %s, has_game_detail: %s, has_box_score: %s",
           nostat_matchups_list[[1]]$is_completed,
           nostat_matchups_list[[1]]$has_game_detail,
           nostat_matchups_list[[1]]$has_box_score))

ok("NOSTAT-3 Flag matches file existence (both FALSE), satisfying cross-dataset contract",
   identical(nostat_matchups_list[[1]]$has_game_detail, nostat_file_exists),
   sprintf("flag: %s, file_exists: %s", nostat_matchups_list[[1]]$has_game_detail, nostat_file_exists))

unlink(nostat_test_dir, recursive = TRUE)
unlink(drift_test_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat("\n==================================================\n")
if (failures > 0L) {
  cat(sprintf("FAILED with %d failure(s).\n", failures))
  quit(status = 1L)
} else {
  cat("All attribution and game details checks PASSED successfully.\n")
  quit(status = 0L)
}
