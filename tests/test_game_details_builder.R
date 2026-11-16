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
cat("--- Section 1: Builder execution and file generation ---\n")
initial_run <- build_game_details()
ok("BUILD-1 Initial build completed", is.list(initial_run))

game_files <- list.files(WEB_GAMES_DIR, pattern = "\\.json$", full.names = TRUE)
ok("BUILD-2 Game detail JSON files produced", length(game_files) > 0L,
   sprintf("%d files in %s", length(game_files), WEB_GAMES_DIR))

# ------------------------------------------------------------------------------
# Test 2: Idempotency & churn control (0 rewrites on consecutive run)
# ------------------------------------------------------------------------------
cat("\n--- Section 2: Idempotency and Churn Control ---\n")
second_run <- build_game_details()
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
ts_df <- readRDS(CACHE_TEAM_STATS)

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

# ------------------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------------------
cat("\n==================================================\n")
if (failures > 0L) {
  cat(sprintf("FAILED with %d failure(s).\n", failures))
  quit(status = 1L)
} else {
  cat(sprintf("All %d checks PASSED successfully.\n", 11L))
  quit(status = 0L)
}
