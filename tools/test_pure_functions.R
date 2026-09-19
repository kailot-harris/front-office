# ==============================================================================
# tools/test_pure_functions.R
# ------------------------------------------------------------------------------
# Lightweight regression suite for pure (or safely-testable via an explicit
# persist=FALSE/path-injection parameter) functions that were previously only
# verified ad hoc during whichever session touched them.
#
# Motivated by a real 2026-09-19 near-miss: an ad hoc test script sourced
# prediction_accuracy_logger.R to unit-test migrate_prediction_log(), but the
# nested source() of config.R silently reset a pre-set temp-path override,
# causing the function's real saveRDS()/write.csv() calls to overwrite the
# production cache/prediction_accuracy_log.rds with test fixture data (caught via
# git status, recovered via git checkout since it was already committed). See
# AGENTS.md's "Testing scripts with real save side effects" section. This suite
# is the sanctioned, safe way to test that function (and others like it) going
# forward: migrate_prediction_log() is always called with persist = FALSE here,
# so no real cache file is ever touched no matter what PRED_LOG_RDS/PRED_LOG_CSV
# resolve to.
#
# Every other function tested here (normalize_team_abbreviation, filter_real_
# franchises, join_rapm_to_roster, normalize_rapm_last_name) is a pure
# data-in/data-out function with no file-write side effect at all.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe tools/test_pure_functions.R
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages(library(dplyr))
source("config.R")
source("logging_utils.R")
source("player_metrics.R")           # normalize_team_abbreviation(), filter_real_franchises()
source("rapm_join_utils.R")          # join_rapm_to_roster(), normalize_rapm_last_name()
source("prediction_accuracy_logger.R")  # migrate_prediction_log() -- side-effect-free on source

failures <- 0L
report <- function(ok, id, desc, detail = "") {
  if (!ok) failures <<- failures + 1L
  cat(sprintf("[%s] %s %s%s\n", if (ok) "PASS" else "FAIL", id, desc,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("=== Pure-function regression suite ===\n\n")

# ------------------------------------------------------------------------------
# normalize_team_abbreviation() -- the CONN -> CON gotcha (CLAUDE.md)
# ------------------------------------------------------------------------------
df_conn <- data.frame(
  team_abbreviation = c("CONN", "CON", "LV", NA_character_),
  opponent_team_abbreviation = c("LV", "CONN", "CON", "ATL"),
  stringsAsFactors = FALSE
)
out_conn <- normalize_team_abbreviation(df_conn)
report(identical(out_conn$team_abbreviation, c("CON", "CON", "LV", NA_character_)),
       "CHECK 1", "normalize_team_abbreviation() maps CONN -> CON on team_abbreviation",
       paste(out_conn$team_abbreviation, collapse = ","))
report(identical(out_conn$opponent_team_abbreviation, c("LV", "CON", "CON", "ATL")),
       "CHECK 2", "normalize_team_abbreviation() maps CONN -> CON on opponent_team_abbreviation",
       paste(out_conn$opponent_team_abbreviation, collapse = ","))

df_no_cols <- data.frame(x = 1:3)
report(identical(normalize_team_abbreviation(df_no_cols), df_no_cols),
       "CHECK 3", "normalize_team_abbreviation() is a no-op when neither column is present")

# ------------------------------------------------------------------------------
# filter_real_franchises() -- exhibition/All-Star row drop, real-franchise keep
# ------------------------------------------------------------------------------
df_exhib <- data.frame(
  team_abbreviation = c("CONN", "DEL", "ALL", "LV", "USA"),
  stringsAsFactors = FALSE
)
out_exhib <- filter_real_franchises(df_exhib)
report(nrow(out_exhib) == 2L && setequal(out_exhib$team_abbreviation, c("CON", "LV")),
       "CHECK 4", "filter_real_franchises() drops exhibition rows and keeps CONN(->CON)/LV",
       paste(out_exhib$team_abbreviation, collapse = ","))

# ------------------------------------------------------------------------------
# migrate_prediction_log() -- ALWAYS persist = FALSE (see file header)
# ------------------------------------------------------------------------------
df_mig <- data.frame(
  game_id = c("WNBA_GAME_5", "WNBA_GAME_6", "REAL_GAME_1", "DIAG_1", "WNBA_GAME_7"),
  market_data_source = c("UNKNOWN", "UNKNOWN", "LIVE_ODDS_API", "DIAGNOSTIC", "LIVE_ODDS_API"),
  injury_data_source = c(NA, NA, NA, "DIAGNOSTIC", NA),
  schema_version = c(1L, 1L, 2L, 2L, 2L),
  stringsAsFactors = FALSE
)
res_mig <- migrate_prediction_log(df_mig, persist = FALSE)
report(isTRUE(res_mig$is_synthetic[res_mig$game_id == "WNBA_GAME_5"]),
       "CHECK 5", "migrate_prediction_log(): pre-provenance WNBA_GAME_5 fixture -> is_synthetic = TRUE")
report(isTRUE(res_mig$is_synthetic[res_mig$game_id == "WNBA_GAME_6"]),
       "CHECK 6", "migrate_prediction_log(): pre-provenance WNBA_GAME_6 fixture -> is_synthetic = TRUE")
report(!isTRUE(res_mig$is_synthetic[res_mig$game_id == "REAL_GAME_1"]),
       "CHECK 7", "migrate_prediction_log(): real game with known market_data_source -> is_synthetic = FALSE")
report(isTRUE(res_mig$is_synthetic[res_mig$game_id == "DIAG_1"]),
       "CHECK 8", "migrate_prediction_log(): DIAG_ prefixed row -> is_synthetic = TRUE")
report(!isTRUE(res_mig$is_synthetic[res_mig$game_id == "WNBA_GAME_7"]),
       "CHECK 9", "migrate_prediction_log(): WNBA_GAME_N pattern with KNOWN (non-UNKNOWN) market_data_source is NOT misclassified as synthetic",
       "regression guard: the new predicate must stay gated on market_data_source == UNKNOWN")

df_empty <- data.frame()
report(identical(migrate_prediction_log(df_empty, persist = FALSE), df_empty),
       "CHECK 10", "migrate_prediction_log() is a no-op on a zero-row/empty data frame")

# Regression guard for the 2026-09-19 (later session) reconciliation fix
# (docs/future-work.md item 10): a WNBA_GAME_N fixture row already stamped
# is_synthetic = FALSE under an OLDER schema_version must still get force-corrected to
# TRUE once PRED_LOG_SCHEMA_VERSION is bumped -- the naive coalesce-only backfill would
# have permanently preserved the stale incorrect FALSE forever.
df_stale <- data.frame(
  game_id = "WNBA_GAME_5",
  market_data_source = "UNKNOWN",
  injury_data_source = NA,
  schema_version = 2L,  # already "migrated" once under the pre-fix 2-predicate logic
  is_synthetic = FALSE,  # the stale, incorrect stamp this fix must override
  stringsAsFactors = FALSE
)
res_stale <- migrate_prediction_log(df_stale, persist = FALSE)
report(isTRUE(res_stale$is_synthetic),
       "CHECK 10b", "migrate_prediction_log() force-corrects an already-schema-2 fixture row stamped FALSE by an older classifier version",
       sprintf("is_synthetic=%s schema_version=%s", res_stale$is_synthetic, res_stale$schema_version))

# ------------------------------------------------------------------------------
# join_rapm_to_roster() -- collision handling (H-2), missing columns, empty input
# ------------------------------------------------------------------------------
rost <- tibble(
  team_abbreviation = c("LA", "LA"),
  team_name = c("Los Angeles Sparks", "Los Angeles Sparks"),
  player_id = c(1L, 2L),
  player_name = c("Nneka Ogwumike", "Some Other")
)
rapm <- tibble(
  team = c("Los Angeles Sparks", "Los Angeles Sparks", "Los Angeles Sparks"),
  player_name = c("Ogwumike", "Ogwumike", "Other"),
  total_rapm = c(3.5, -1.0, 0.2),
  n_off_poss = c(500, 50, 10),
  n_def_poss = c(500, 50, 10),
  player_id = c("101", "102", "103")
)
out_rapm <- join_rapm_to_roster(rost, rapm, matched_only = TRUE)
report(nrow(out_rapm) == 2L,
       "CHECK 11", "join_rapm_to_roster() resolves a (team, last_name) collision to exactly 1 row per roster player",
       sprintf("nrow=%d", nrow(out_rapm)))
og_row <- out_rapm |> filter(player_id == 1L)
report(nrow(og_row) == 1L && isTRUE(all.equal(og_row$total_rapm, 3.5)) && isTRUE(og_row$rapm_ambiguous),
       "CHECK 12", "join_rapm_to_roster() picks the higher-possession RAPM row on a collision and flags rapm_ambiguous",
       sprintf("total_rapm=%s ambiguous=%s", og_row$total_rapm, og_row$rapm_ambiguous))

out_missing_cols <- join_rapm_to_roster(rost |> select(-team_name), rapm)
report(nrow(out_missing_cols) == 0L,
       "CHECK 13", "join_rapm_to_roster() returns 0 rows (not an error) when a required roster column is missing")

out_empty <- join_rapm_to_roster(tibble(), rapm)
report(nrow(out_empty) == 0L,
       "CHECK 14", "join_rapm_to_roster() returns 0 rows (not an error) on an empty roster input")

report(normalize_rapm_last_name("Nneka Ogwumike", from_full_name = TRUE) == "ogwumike",
       "CHECK 15", "normalize_rapm_last_name() extracts + lowercases the last name from a full name")
report(normalize_rapm_last_name("O'Neal-Smith", from_full_name = TRUE) == "onealsmith",
       "CHECK 16", "normalize_rapm_last_name() strips punctuation")

# ------------------------------------------------------------------------------
cat(sprintf("\n=== %d failure(s) ===\n", failures))
if (failures > 0L) quit(status = 1L)
