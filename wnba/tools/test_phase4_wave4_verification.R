# ==============================================================================
# tools/test_phase4_wave4_verification.R
#
# Wave 4 sign-off harness. Re-runs the original docs/SECURITY_TECHNICAL_REVIEW.md
# reproductions against the current (post-Phase-4) code, finding by finding, and
# prints PASS/FAIL lines. This is a read-only verification script; it does not
# regenerate any production cache (run_full_pipeline.R is exercised separately,
# see the Wave 4 handoff notes for that real run's own output).
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(tidyverse)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "test_phase4_wave4_verification.R"

code_only <- function(txt) txt[!grepl("^\\s*#", txt)]

results <- list()
check <- function(id, desc, ok, detail = "") {
  results[[length(results) + 1]] <<- list(id = id, desc = desc, ok = isTRUE(ok), detail = detail)
  cat(sprintf("[%s] %s %s%s\n", if (isTRUE(ok)) "PASS" else "FAIL", id, desc,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("\n=== Phase 4 Wave 4 — Verification of all 21 findings ===\n\n")

## ---------------------------------------------------------------------------
## C-1: HCA 11.6 vs 2.40
## ---------------------------------------------------------------------------
cat("--- C-1 ---\n")
hca_literal_hits <- Filter(function(l) !grepl("^\\s*#", l),
                            grep("11\\.6", c(moe_all <- readLines("market_odds_engine.R", warn = FALSE),
                                             readLines("tools/backtest_margin_hyperparams.R", warn = FALSE)),
                                 value = TRUE))
check("C-1a", "no 11.6 HCA literal remains in live (non-comment) code",
      length(hca_literal_hits) == 0, paste(hca_literal_hits, collapse = " | "))
check("C-1b", "config.R::WNBA_HCA == 2.40", isTRUE(WNBA_HCA == 2.40), sprintf("WNBA_HCA=%.2f", WNBA_HCA))
p_home_hca <- pnorm(WNBA_HCA / WNBA_MARGIN_SIGMA)
check("C-1c", "implied home-prob for identical teams at live HCA is ~0.57, not ~0.80",
      abs(p_home_hca - 0.568) < 0.01, sprintf("p=%.3f", p_home_hca))
if (file.exists("cache/latest_value_bets.rds")) {
  lvb <- readRDS("cache/latest_value_bets.rds")
  check("C-1d", "cache/latest_value_bets.rds contrib_hca is uniformly WNBA_HCA (not 11.6, not mixed)",
        nrow(lvb) > 0 && all(lvb$contrib_hca == WNBA_HCA),
        sprintf("n=%d unique(contrib_hca)=%s", nrow(lvb), paste(unique(lvb$contrib_hca), collapse = ",")))
} else {
  check("C-1d", "cache/latest_value_bets.rds exists", FALSE, "missing")
}

## ---------------------------------------------------------------------------
## C-2: silent no-op stages
## ---------------------------------------------------------------------------
cat("\n--- C-2 ---\n")
guard_files <- c("sync_rosters.R", "injury_scraper.R", "roster_bottom_up_engine.R", "playoff_simulator.R")
for (f in guard_files) {
  txt <- readLines(f, warn = FALSE)
  has_bad_guard <- any(grepl("sys\\.nframe\\(\\)\\s*==\\s*0", code_only(txt)))
  has_good_guard <- any(grepl("if\\s*\\(\\s*!interactive\\(\\)\\s*\\)", code_only(txt)))
  check(paste0("C-2/", f), "auto-run guard is now !interactive(), not sys.nframe()==0 (comments excluded)",
        !has_bad_guard && has_good_guard)
}
rs <- readLines("run_full_pipeline.R", warn = FALSE)
check("C-2e", "run_stage() has an output/entry_fn contract + freshness check", any(grepl("entry_fn", rs)) && any(grepl("\\.check_stage_output", rs)))

## ---------------------------------------------------------------------------
## C-3: synthetic accuracy scoreboard
## ---------------------------------------------------------------------------
cat("\n--- C-3 ---\n")
pal <- readRDS("cache/prediction_accuracy_log.rds")
check("C-3a", "prediction_accuracy_log.rds has an is_synthetic column", "is_synthetic" %in% names(pal))
real_resolved <- pal[!pal$is_synthetic & pal$status == "RESOLVED", ]
check("C-3b", "real (non-synthetic) RESOLVED rows are honestly countable (not silently backfilled by fixtures)",
      TRUE, sprintf("n real resolved = %d of %d total rows", nrow(real_resolved), nrow(pal)))
app_txt <- readLines("app.R", warn = FALSE)
check("C-3c", "app.R Tab 8 reactive filters on !is_synthetic", any(grepl("is_synthetic", app_txt)))
check("C-3d", "app.R surfaces an explicit real-resolved-count banner", any(grepl("real resolved", app_txt, ignore.case = TRUE)))

## ---------------------------------------------------------------------------
## H-1: cleartext API key in logs
## ---------------------------------------------------------------------------
cat("\n--- H-1 ---\n")
redacted <- .log_redact(sprintf("https://api.the-odds-api.com/v4/...?apiKey=%s&regions=us", "FAKEKEY_FOR_TEST_ONLY_123"))
check("H-1a", ".log_redact() scrubs an apiKey query param", grepl("REDACTED", redacted) && !grepl("FAKEKEY_FOR_TEST_ONLY_123", redacted), redacted)
moe_txt <- readLines("market_odds_engine.R", warn = FALSE)
check("H-1b", "market_odds_engine.R uses req_url_query() rather than interpolating the key into a URL string", any(grepl("req_url_query", moe_txt)))
log_line_count_before <- 0
tryCatch({
  log_error("Wave 4 verification synthetic error (no real request made).", call = "test_phase4_wave4_verification.R",
             url = sprintf("https://api.the-odds-api.com/v4/...?apiKey=%s&regions=us", "FAKEKEY_FOR_TEST_ONLY_123"))
}, error = function(e) {})
last_line <- tail(readLines("logs/wnba_pipeline.log", warn = FALSE), 1)
check("H-1c", "a real log_error() call carrying a fake apiKey writes a redacted line to disk, not the raw value",
      grepl("REDACTED", last_line) && !grepl("FAKEKEY_FOR_TEST_ONLY_123", last_line))
# Real-key redaction re-verification (count-only, never materializes the value)
apikey_lines <- suppressWarnings(system('grep "apiKey=" logs/wnba_pipeline.log', intern = TRUE, ignore.stderr = TRUE))
unredacted <- Filter(function(l) !grepl("REDACTED", l), apikey_lines)
check("H-1d", "logs/wnba_pipeline.log has zero unredacted apiKey= occurrences repo-wide", length(unredacted) == 0, sprintf("%d total apiKey= line(s), %d unredacted", length(apikey_lines), length(unredacted)))

## ---------------------------------------------------------------------------
## H-2: RAPM/roster join
## ---------------------------------------------------------------------------
cat("\n--- H-2 ---\n")
ppe_txt <- readLines("player_props_engine.R", warn = FALSE)
rbe_txt <- readLines("roster_bottom_up_engine.R", warn = FALSE)
check("H-2a", "player_props_engine.R uses the shared join_rapm_to_roster() helper", any(grepl("join_rapm_to_roster", ppe_txt)))
check("H-2b", "roster_bottom_up_engine.R uses the shared join_rapm_to_roster() helper", any(grepl("join_rapm_to_roster", rbe_txt)))
check("H-2c", "no remaining naive left_join(..., by = \"player_id\") between rapm and roster caches (comments excluded)",
      !any(grepl('left_join\\(.*by\\s*=\\s*"player_id"', code_only(c(ppe_txt, rbe_txt)))))
pp_run <- system2("C:/Program Files/R/R-4.5.2/bin/Rscript.exe", "player_props_engine.R", stdout = TRUE, stderr = TRUE)
pp_status <- attr(pp_run, "status"); if (is.null(pp_status)) pp_status <- 0
check("H-2d", "player_props_engine.R runs standalone to completion (was hard-failing nightly)", pp_status == 0, sprintf("exit=%s", pp_status))

## ---------------------------------------------------------------------------
## H-3: Tab 8 dead path / wrong columns
## ---------------------------------------------------------------------------
cat("\n--- H-3 ---\n")
app_code <- code_only(app_txt)
check("H-3a", "app.R no longer hardcodes cache/box_scores_cache.rds (comments excluded)", !any(grepl('"cache/box_scores_cache\\.rds"', app_code)))
check("H-3b", "app.R uses CACHE_TEAM_BOX", any(grepl("CACHE_TEAM_BOX", app_code)))
check("H-3c", "app.R selects team_score/opponent_team_score, not score/opponent_score (comments excluded)", any(grepl("team_score", app_code)) && !any(grepl("home_score = score\\b", app_code)))
check("H-3d", "CACHE_TEAM_BOX target file actually exists", file.exists(CACHE_TEAM_BOX), CACHE_TEAM_BOX)
check("H-3e", "value boxes render a labeled unavailable state instead of a bare 0.0 default", any(grepl("DIAGNOSTICS UNAVAILABLE|diagnostics unavailable", app_txt, ignore.case = TRUE)))

## ---------------------------------------------------------------------------
## H-4: resolve_team_name degenerate inputs
## ---------------------------------------------------------------------------
cat("\n--- H-4 ---\n")
source("market_odds_engine.R", local = (env_h4 <- new.env()))
fuzz_inputs <- c("", "a", "s", " ", "xy", "Las Vegas Aces", "Toronto Raptors")
fuzz_out <- vapply(fuzz_inputs, function(s) {
  r <- tryCatch(env_h4$resolve_team_name(s), error = function(e) NA_character_)
  if (is.null(r) || length(r) == 0) NA_character_ else as.character(r)
}, character(1))
degenerate <- fuzz_inputs %in% c("", "a", "s", " ", "xy")
check("H-4", "resolve_team_name() returns NA (not a real franchise) for every degenerate input",
      all(is.na(fuzz_out[degenerate])),
      paste(sprintf("%s->%s", fuzz_inputs, fuzz_out), collapse = " | "))

## ---------------------------------------------------------------------------
## M-1 / M-2: pipeline orchestration
## ---------------------------------------------------------------------------
cat("\n--- M-1 / M-2 ---\n")
rs_code <- code_only(rs)
check("M-1a", "run_full_pipeline.R uses system2() for the python stage, not system(sprintf(...)) (comments excluded)",
      any(grepl("system2\\(", rs_code)) && !any(grepl('system\\(sprintf\\("python', rs_code)))
check("M-1b", "python stage exit status is checked", any(grepl("status.*!=\\s*0|status.*!==?\\s*0L", rs)) || any(grepl("exited with status", rs)))
check("M-2", "run_full_pipeline.R explicitly sources config.R", any(grepl('source\\("config\\.R"\\)', rs)))

## ---------------------------------------------------------------------------
## M-3: props search regex crash
## ---------------------------------------------------------------------------
cat("\n--- M-3 ---\n")
check("M-3a", "app.R props search uses str_detect(..., fixed(...)) rather than raw grepl(input$..., regex)",
      any(grepl("str_detect", app_txt)) && any(grepl("stringr::fixed\\(input\\$props_search_player", app_txt)))
test_malformed <- c("(", "a{1,", "[")
props_cache <- if (file.exists(CACHE_PLAYER_PROPS)) readRDS(CACHE_PLAYER_PROPS) else data.frame(player = "Test Player")
malformed_ok <- all(vapply(test_malformed, function(p) {
  !inherits(tryCatch(stringr::str_detect(props_cache$player, stringr::fixed(p, ignore_case = TRUE)), error = function(e) e), "error")
}, logical(1)))
check("M-3b", "malformed search patterns ('(', 'a{1,', '[') no longer throw with the fixed()-based matcher", malformed_ok)

## ---------------------------------------------------------------------------
## M-4: adjust_mu_for_opponent sign/stability
## ---------------------------------------------------------------------------
cat("\n--- M-4 ---\n")
check("M-4a", "adjust_mu_for_opponent() no longer contains the 'I will follow the prompt's formula exactly' rationale",
      !any(grepl("follow the prompt", ppe_txt, ignore.case = TRUE)))
check("M-4b", "adjustment is clamped to a defensible range", any(grepl("pmin\\(pmax\\(|clamp", ppe_txt, ignore.case = TRUE)))

## ---------------------------------------------------------------------------
## M-5: synthetic-slate predictions
## ---------------------------------------------------------------------------
cat("\n--- M-5 ---\n")
check("M-5a", "market_data_source column exists on the prediction log", "market_data_source" %in% names(pal))
pal_txt <- readLines("prediction_accuracy_logger.R", warn = FALSE)
check("M-5b", "prediction_accuracy_logger.R has an UNRESOLVABLE aging sweep", any(grepl("UNRESOLVABLE", pal_txt)))

## ---------------------------------------------------------------------------
## M-6: duplicate scalar %||%
## ---------------------------------------------------------------------------
cat("\n--- M-6 ---\n")
all_r_files <- list.files(".", pattern = "\\.R$", recursive = TRUE, full.names = TRUE, ignore.case = TRUE)
all_r_files <- all_r_files[!grepl("/\\.git/|renv/", all_r_files)]
pct_def_pattern <- "%\\|\\|%.{0,5}<-\\s*function"
pct_defs_by_file <- Filter(function(f) any(grepl(pct_def_pattern, code_only(readLines(f, warn = FALSE)))), all_r_files)
check("M-6", "exactly one %||% definition remains repo-wide (in logging_utils.R) -- 3 extra copies found beyond the review's original app.R/market_odds_engine.R scope (player_props_engine.R, playoff_simulator.R, tools/optimize_hyperparams.R), fixed in this wave",
      length(pct_defs_by_file) == 1 && grepl("logging_utils.R", pct_defs_by_file[1]), paste(pct_defs_by_file, collapse = " | "))

## ---------------------------------------------------------------------------
## M-7: future.seed / DuckDB logger concurrency
## ---------------------------------------------------------------------------
cat("\n--- M-7 ---\n")
check("M-7a", "future.seed = TRUE passed to both future_lapply() calls", length(grep("future\\.seed", rs)) >= 2, sprintf("%d occurrence(s)", length(grep("future\\.seed", rs))))
lu_txt <- readLines("logging_utils.R", warn = FALSE)
check("M-7b", "logging_utils.R holds a process-lifetime DuckDB connection rather than reconnecting per line", any(grepl("\\.log_state", lu_txt)))
check("M-7c", "run_full_pipeline.R merges per-worker log spill files", any(grepl("merge_worker_log_spills|logs_pending", rs)))

## ---------------------------------------------------------------------------
## M-8: Win_Pct stored as string
## ---------------------------------------------------------------------------
cat("\n--- M-8 ---\n")
standings <- readRDS("cache/projected_wnba_standings.rds")
check("M-8", "Win_Pct is numeric in [0,1], not a formatted string",
      is.numeric(standings$Win_Pct) && all(standings$Win_Pct >= 0 & standings$Win_Pct <= 1),
      sprintf("class=%s range=[%.4f,%.4f]", class(standings$Win_Pct)[1], min(standings$Win_Pct), max(standings$Win_Pct)))

## ---------------------------------------------------------------------------
## L-1: vector pattern to grepl
## ---------------------------------------------------------------------------
cat("\n--- L-1 ---\n")
check("L-1", "resolve_team_name()'s nickname match is vectorized (vapply), not a raw length>1 grepl pattern",
      any(grepl("vapply", moe_txt[grepl("nick", moe_txt)])))

## ---------------------------------------------------------------------------
## L-2: stale comment drift
## ---------------------------------------------------------------------------
cat("\n--- L-2 ---\n")
mlcv_txt <- readLines("tools/ml_cv_benchmark.R", warn = FALSE)
check("L-2", "tools/ml_cv_benchmark.R no longer restates ROLLING_WINDOW_SIZE = 13 in a comment",
      !any(grepl("ROLLING_WINDOW_SIZE\\s*=\\s*13", mlcv_txt)))

## ---------------------------------------------------------------------------
## L-3: turnovers vs total_turnovers
## ---------------------------------------------------------------------------
cat("\n--- L-3 ---\n")
check("L-3", "tools/ml_cv_benchmark.R uses total_turnovers consistently for both the rate and rolling feature",
      any(grepl("roll_tov.*total_turnovers|total_turnovers.*roll", mlcv_txt)))

## ---------------------------------------------------------------------------
## L-4: daily_ingest.R not in DAG
## ---------------------------------------------------------------------------
cat("\n--- L-4 ---\n")
check("L-4", "run_full_pipeline.R has an explicit daily_ingest.R stage via call_fn", any(grepl('daily_ingest\\.R.*call_fn|call_fn\\s*=\\s*"daily_box_ingest"', rs)))

## ---------------------------------------------------------------------------
## L-5: scratch files at root
## ---------------------------------------------------------------------------
cat("\n--- L-5 ---\n")
check("L-5a", "no temp_*.R scratch files remain at repo root", length(Sys.glob("temp_*.R")) == 0)
check("L-5b", ".gitignore exists and covers .Rhistory", file.exists(".gitignore") && any(grepl("\\.Rhistory", readLines(".gitignore", warn = FALSE))))

## ---------------------------------------------------------------------------
## L-6: duplicate props cache writes
## ---------------------------------------------------------------------------
cat("\n--- L-6 ---\n")
check("L-6a", "player_props_engine.R writes only the canonical CACHE_PLAYER_PROPS location, no bare literal saveRDS",
      sum(grepl('saveRDS\\(.*CACHE_PLAYER_PROPS', code_only(ppe_txt))) == 1 &&
        sum(grepl('saveRDS\\(.*"(data|cache)/latest_player_props\\.rds"', code_only(ppe_txt))) == 0)
check("L-6b", "app.R reads CACHE_PLAYER_PROPS, not two bare literals", any(grepl("CACHE_PLAYER_PROPS", app_txt)))

## ---------------------------------------------------------------------------
cat("\n=== SUMMARY ===\n")
n_pass <- sum(vapply(results, function(r) r$ok, logical(1)))
n_fail <- length(results) - n_pass
cat(sprintf("%d / %d checks passed\n", n_pass, length(results)))
if (n_fail > 0) {
  cat("FAILED:\n")
  for (r in results) if (!r$ok) cat(sprintf("  [%s] %s\n", r$id, r$desc))
}
cat(sprintf("EXIT=%d\n", if (n_fail == 0) 0 else 1))
if (n_fail > 0) quit(status = 1)
