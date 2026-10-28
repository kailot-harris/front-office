# ==============================================================================
# tests/test_pure_functions.R
# Foundational offline R unit tests for NFL Analytics (Tier 2 §4 row 7).
#
# Runs with base R ONLY (stats, utils, tools, methods) -- zero network calls,
# zero paid API keys, and zero external CRAN package dependencies required --
# so the CI `r` job on ubuntu-latest executes this suite in ~1 second without
# needing an `install-deps.R` or `renv::restore()` step.
#
# Scope (50 assertions across 5 production modules):
#   1. config.R                  -- structural & empirical constants, WEB_DATA_FILES
#   2. logging_utils.R           -- M-6 `%||%` vector/NA safety, H-1 `.log_redact()`,
#                                   `.log_format_extra()`
#   3. market_odds_engine.R      -- odds/prob/Kelly math, H-4 `resolve_team_name()`
#   4. tools/refresh_live_results.R -- `.rlr_is_true()`, `.rlr_grade()`,
#                                   `apply_results()`, `recompute_diagnostics()`,
#                                   `reconcile_diagnostics()`, `fetch_season_results()`
#   5. tools/publish_web.R       -- `.pw_payload_generated_at()`, `.pw_log_timestamp()`,
#                                   `.scan_exporter_warnings()`,
#                                   `.compute_active_week_from_schedules()`
# ==============================================================================

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

# AST helper: evaluate selected top-level assignments from an R file into `env`
# without executing `library()` or side-effecting top-level code.
load_ast_symbols <- function(path, symbols, env) {
  exprs <- parse(file = path, keep.source = FALSE)
  for (e in exprs) {
    if (is.call(e) && length(e) >= 3L &&
        as.character(e[[1L]]) %in% c("<-", "=") &&
        is.symbol(e[[2L]]) &&
        as.character(e[[2L]]) %in% symbols) {
      eval(e, envir = env)
    }
  }
  env
}

cat("=== NFL Analytics Foundational R Unit Tests ===\n\n")

# ==============================================================================
# SECTION 1: config.R structural & modeling invariants
# ==============================================================================
cat("--- Section 1: config.R structural & modeling invariants ---\n")
source("config.R")

ok("CFG-1 NFL_TEAMS has exactly 32 franchises with unique abbreviations and full names",
   length(NFL_TEAMS) == 32L &&
     NFL_TEAM_COUNT == 32L &&
     length(unique(names(NFL_TEAMS))) == 32L &&
     length(unique(unname(NFL_TEAMS))) == 32L,
   sprintf("%d teams", length(NFL_TEAMS)))

ok("CFG-2 NFL_DIVISIONS covers all 32 NFL_TEAMS across 8 divisions of 4 teams each",
   identical(sort(names(NFL_DIVISIONS)), sort(names(NFL_TEAMS))) &&
     length(unique(NFL_DIVISIONS)) == 8L &&
     all(as.integer(table(NFL_DIVISIONS)) == 4L),
   "8 divisions x 4 teams = 32")

ok("CFG-3 NFL regular-season and roster structural constants match modern NFL rules",
   NFL_SEASON_GAMES == 17L &&
     NFL_ROSTER_MAX == 53L &&
     NFL_GAMEDAY_ACTIVE_MAX == 48L &&
     NFL_PLAYOFF_FIELD == 14L &&
     NFL_PLAYOFF_TEAMS_PER_CONF == 7L,
   sprintf("season=%d, roster=%d/%d, playoffs=%d",
           NFL_SEASON_GAMES, NFL_GAMEDAY_ACTIVE_MAX, NFL_ROSTER_MAX, NFL_PLAYOFF_FIELD))

ok("CFG-4 Empirically derived NFL_HCA and NFL_MARGIN_SIGMA sit in sane NFL ranges",
   is.numeric(NFL_HCA) && NFL_HCA > 1.0 && NFL_HCA < 3.5 &&
     is.numeric(NFL_MARGIN_SIGMA) && NFL_MARGIN_SIGMA > 12.0 && NFL_MARGIN_SIGMA < 17.0 &&
     abs(pnorm(NFL_HCA / NFL_MARGIN_SIGMA) - 0.5526) < 0.01,
   sprintf("NFL_HCA=%.2f, NFL_MARGIN_SIGMA=%.2f -> neutral home win prob=%.3f",
           NFL_HCA, NFL_MARGIN_SIGMA, pnorm(NFL_HCA / NFL_MARGIN_SIGMA)))

ok("CFG-5 WEB_DATA_FILES declares the 9 derived JSON datasets and excludes static coaching_profiles.json",
   length(WEB_DATA_FILES) == 9L &&
     all(grepl("^web/public/data/.*\\.json$", gsub("\\\\", "/", WEB_DATA_FILES))) &&
     !(WEB_JSON_COACHING_PROFILES %in% WEB_DATA_FILES),
   sprintf("%d files in WEB_DATA_FILES", length(WEB_DATA_FILES)))

# ==============================================================================
# SECTION 2: logging_utils.R pure helpers (%||%, .log_redact, .log_format_extra)
# ==============================================================================
cat("\n--- Section 2: logging_utils.R pure helpers ---\n")
LOG_ENV <- new.env(parent = globalenv())
load_ast_symbols(
  "logging_utils.R",
  c("%||%", ".LOG_REDACT_PARAMS", ".log_redact", ".log_format_extra"),
  LOG_ENV
)
`%||%` <- LOG_ENV$`%||%`
.log_redact <- LOG_ENV$.log_redact
.log_format_extra <- LOG_ENV$.log_format_extra

ok("LOG-1 (M-6) `%||%` returns fallback on NULL, character(0), NA, and c(NA, 'x') without R 4.3+ length>1 error",
   identical(NULL %||% "fb", "fb") &&
     identical(character(0) %||% "fb", "fb") &&
     identical(NA_character_ %||% "fb", "fb") &&
     identical(c(NA_character_, "second") %||% "fb", "fb") &&
     identical(c("first", "second") %||% "fb", c("first", "second")),
   "scalar + vector coalescing safe")

red_q <- .log_redact("https://api.the-odds-api.com/v4/sports/americanfootball_nfl/odds/?regions=us&apiKey=SUPERSECRET123&oddsFormat=american")
ok("LOG-2 (H-1) `.log_redact()` scrubs query-string apiKey= parameters while preserving surrounding URL",
   !grepl("SUPERSECRET123", red_q, fixed = TRUE) &&
     grepl("apiKey=***REDACTED***", red_q, fixed = TRUE) &&
     grepl("oddsFormat=american", red_q, fixed = TRUE),
   red_q)

red_json <- .log_redact('{"access_token": "tok_live_987654321", "status": "ok"}')
ok("LOG-3 (H-1) `.log_redact()` scrubs JSON/list style token/secret fields",
   !grepl("tok_live_987654321", red_json, fixed = TRUE) &&
     grepl("***REDACTED***", red_json, fixed = TRUE),
   red_json)

red_wh <- .log_redact("POST https://discord.com/api/webhooks/1234567890/AbCdEfGhIjKlMnOpQrStUvWxYz failed")
ok("LOG-4 (H-1) `.log_redact()` scrubs Discord webhook URLs",
   !grepl("AbCdEfGhIjKlMnOpQrStUvWxYz", red_wh, fixed = TRUE) &&
     grepl("https://discord.com/api/webhooks/***REDACTED***", red_wh, fixed = TRUE),
   red_wh)

red_auth <- .log_redact("Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9")
ok("LOG-5 (H-1) `.log_redact()` scrubs Bearer authorization tokens",
   !grepl("eyJhbGci", red_auth, fixed = TRUE) &&
     grepl("Bearer ***REDACTED***", red_auth, fixed = TRUE),
   red_auth)

fmt_extra <- .log_format_extra(list(call = "fetch()", url = "https://example.com?api_key=MYKEY999", empty = NULL))
ok("LOG-6 `.log_format_extra()` drops NULL entries, formats key-value pairs, and redacts secrets",
   !grepl("MYKEY999", fmt_extra, fixed = TRUE) &&
     !grepl("empty", fmt_extra, fixed = TRUE) &&
     grepl("call: fetch\\(\\)", fmt_extra) &&
     grepl("api_key=\\*\\*\\*REDACTED\\*\\*\\*", fmt_extra),
   fmt_extra)

# ==============================================================================
# SECTION 3: market_odds_engine.R odds/Kelly math & H-4 team canonicalization
# ==============================================================================
cat("\n--- Section 3: market_odds_engine.R pure functions ---\n")
ENG_ENV <- new.env(parent = globalenv())
ENG_ENV$NFL_TEAMS <- NFL_TEAMS
ENG_ENV$if_else <- function(cond, t, f) ifelse(cond, t, f)
ENG_ENV$word <- function(string, start = 1L) {
  if (identical(as.integer(start), -1L)) sub("^.*\\s+", "", string) else string
}
ENG_ENV$log_warn <- function(...) invisible(NULL)

load_ast_symbols(
  "market_odds_engine.R",
  c("american_to_decimal", "american_to_prob", "prob_to_american",
    "calculate_kelly", "resolve_team_name"),
  ENG_ENV
)

dec <- ENG_ENV$american_to_decimal(c(-110, 100, 150, -200))
ok("ODDS-1 `american_to_decimal()` converts positive and negative American odds accurately",
   max(abs(dec - c(1 + 100/110, 2.0, 2.5, 1.5))) < 1e-9,
   paste(round(dec, 4), collapse = ", "))

imp <- ENG_ENV$american_to_prob(c(-110, 100, -200, 200, NA, 0))
ok("ODDS-2 `american_to_prob()` computes implied probabilities and defaults NA/0 to 0.50",
   max(abs(imp - c(110/210, 0.5, 200/300, 100/300, 0.5, 0.5))) < 1e-9,
   paste(round(imp, 4), collapse = ", "))

am_roundtrip <- ENG_ENV$prob_to_american(c(0.5, 2/3, 0.25))
ok("ODDS-3 `prob_to_american()` converts probabilities to expected moneyline odds",
   identical(as.numeric(am_roundtrip), c(-100, -200, 300)),
   paste(am_roundtrip, collapse = ", "))

kelly_no_edge <- ENG_ENV$calculate_kelly(prob = 0.50, decimal_odds = 1.91)
kelly_mod     <- ENG_ENV$calculate_kelly(prob = 0.60, decimal_odds = 2.00) # raw=0.20, quarter=5.0% -> capped at 3.0%
kelly_small   <- ENG_ENV$calculate_kelly(prob = 0.54, decimal_odds = 2.00) # raw=0.08, quarter=2.0%
ok("ODDS-4 `calculate_kelly()` enforces 0 floor on negative EV, 0.25 fractional multiplier, and 3.0% max cap",
   kelly_no_edge == 0 && kelly_mod == 3.0 && abs(kelly_small - 2.0) < 1e-9,
   sprintf("no_edge=%.2f, capped=%.2f, small_edge=%.2f", kelly_no_edge, kelly_mod, kelly_small))

deg_inputs <- c("", " ", "a", "s", "xy", "xyz")
deg_out <- vapply(deg_inputs, ENG_ENV$resolve_team_name, character(1), USE.NAMES = FALSE)
ok("ODDS-5 (H-4) `resolve_team_name()` rejects short/degenerate inputs (<4 chars unless exact NFL abbr)",
   all(is.na(deg_out)) &&
     is.na(ENG_ENV$resolve_team_name(NA_character_)) &&
     is.na(ENG_ENV$resolve_team_name(c("Buffalo Bills", "Miami Dolphins"))),
   "all degenerate / NA / vector inputs -> NA_character_")

abbr_out <- vapply(c("BUF", "la", "KC", "was", "SF"), ENG_ENV$resolve_team_name, character(1), USE.NAMES = FALSE)
ok("ODDS-6 `resolve_team_name()` resolves 2-3 character NFL abbreviations case-insensitively before length guard",
   identical(abbr_out, c("BUF", "LA", "KC", "WAS", "SF")),
   paste(abbr_out, collapse = ", "))

full_out <- vapply(
  c("Buffalo Bills", "Kansas City Chiefs", "San Francisco 49ers", "Washington Commanders"),
  ENG_ENV$resolve_team_name, character(1), USE.NAMES = FALSE
)
ok("ODDS-7 `resolve_team_name()` resolves full franchise names to canonical nflverse abbreviations",
   identical(full_out, c("BUF", "KC", "SF", "WAS")),
   paste(full_out, collapse = ", "))

nick_out <- vapply(c("Bills", "Chiefs", "Seahawks", "Buccaneers", "Packers"),
                   ENG_ENV$resolve_team_name, character(1), USE.NAMES = FALSE)
ok("ODDS-8 (L-1) `resolve_team_name()` vectorized nickname matching resolves every franchise nickname",
   identical(nick_out, c("BUF", "KC", "SEA", "TB", "GB")),
   paste(nick_out, collapse = ", "))

unk_out <- vapply(c("Toronto Argonauts", "Unknown Football Club", " Las Vegas Aces "),
                  ENG_ENV$resolve_team_name, character(1), USE.NAMES = FALSE)
ok("ODDS-9 (H-4) `resolve_team_name()` returns NA_character_ for unrecognized long strings",
   all(is.na(unk_out)),
   "unrecognized franchises -> NA_character_")

# ==============================================================================
# SECTION 4: tools/refresh_live_results.R pure grading & reconciliation functions
# ==============================================================================
cat("\n--- Section 4: tools/refresh_live_results.R pure functions ---\n")
RLR_ENV <- new.env(parent = globalenv())
RLR_ENV$CURRENT_SEASON <- CURRENT_SEASON
RLR_ENV$NFLVERSE_GAMES_CSV <- "https://raw.githubusercontent.com/nflverse/nfldata/master/data/games.csv"
load_ast_symbols(
  "tools/refresh_live_results.R",
  c("%||%", ".rlr_is_true", "fetch_season_results", ".rlr_grade",
    "apply_results", "recompute_diagnostics", "reconcile_diagnostics"),
  RLR_ENV
)

ok("RLR-1 `.rlr_is_true()` converts TRUE/FALSE/NA logical vectors into NA-free logical masks",
   identical(RLR_ENV$.rlr_is_true(c(TRUE, FALSE, NA)), c(TRUE, FALSE, FALSE)),
   "c(TRUE, FALSE, NA) -> c(TRUE, FALSE, FALSE)")

base_row <- data.frame(
  game_id = "2026_08_BUF_SEA",
  week = 8L,
  home_team = "SEA",
  away_team = "BUF",
  home_team_name = "Seattle Seahawks",
  away_team_name = "Buffalo Bills",
  projected_margin = 3.5,
  home_win_prob = 0.60,
  is_completed = FALSE,
  home_score = NA_integer_,
  away_score = NA_integer_,
  actual_winner = NA_character_,
  prediction_correct = NA,
  stringsAsFactors = FALSE
)

g_home <- RLR_ENV$.rlr_grade(base_row, 27L, 20L)
g_away <- RLR_ENV$.rlr_grade(base_row, 17L, 31L)
g_tie  <- RLR_ENV$.rlr_grade(base_row, 24L, 24L)

ok("RLR-2 `.rlr_grade()` sets full franchise name as actual_winner and grades home/away/tie accurately",
   identical(g_home$actual_winner, "Seattle Seahawks") && isTRUE(g_home$prediction_correct) &&
     identical(g_away$actual_winner, "Buffalo Bills") && identical(g_away$prediction_correct, FALSE) &&
     is.na(g_tie$actual_winner) && is.na(g_tie$prediction_correct),
   "home win -> TRUE, away win -> FALSE, tie -> NA")

fixture_rows <- rbind(
  base_row,
  transform(base_row, game_id = "2026_08_KC_LV", week = 8L,
            home_team = "LV", away_team = "KC",
            home_team_name = "Las Vegas Raiders", away_team_name = "Kansas City Chiefs",
            projected_margin = -6.5, home_win_prob = 0.32,
            is_completed = TRUE, home_score = 17L, away_score = 27L,
            actual_winner = "Kansas City Chiefs", prediction_correct = TRUE),
  transform(base_row, game_id = "2026_09_DAL_PHI", week = 9L,
            home_team = "PHI", away_team = "DAL",
            home_team_name = "Philadelphia Eagles", away_team_name = "Dallas Cowboys",
            projected_margin = 4.0, home_win_prob = 0.62,
            is_completed = FALSE)
)

fixture_results <- data.frame(
  game_id = c("2026_08_BUF_SEA", "2026_08_KC_LV", "2026_09_DAL_PHI"),
  home_score = c(21L, 99L, 30L),
  away_score = c(28L, 99L, 14L),
  stringsAsFactors = FALSE
)

patched <- RLR_ENV$apply_results(fixture_rows, fixture_results, active_week = 8L)
ok("RLR-3 `apply_results()` grades newly completed games, preserves already-completed scores, and defers games past active_week",
   patched$n_changed == 1L &&
     patched$n_deferred == 1L &&
     isTRUE(patched$rows$is_completed[1]) &&
     patched$rows$home_score[1] == 21L &&
     identical(patched$rows$actual_winner[1], "Buffalo Bills") &&
     patched$rows$home_score[2] == 17L && # unchanged (was already completed)
     !isTRUE(patched$rows$is_completed[3]), # week 9 deferred when active_week == 8
   sprintf("n_changed=%d, n_deferred=%d", patched$n_changed, patched$n_deferred))

metrics <- RLR_ENV$recompute_diagnostics(patched$rows)
# Row 1: home_win=0, p=0.60 -> incorrect (0), brier=(0.60-0)^2=0.36, logloss=-log(0.40)
# Row 2: home_win=0, p=0.32 -> correct (1),   brier=(0.32-0)^2=0.1024, logloss=-log(0.68)
exp_brier   <- round(mean(c(0.36, 0.1024)), 4)
exp_logloss <- round(mean(c(-log(0.40), -log(0.68))), 4)
ok("RLR-4 `recompute_diagnostics()` computes exact accuracy, Brier score, and clamped log-loss",
   !is.null(metrics) &&
     metrics$n_games_graded == 2L &&
     metrics$overall_accuracy == 50.0 &&
     metrics$overall_brier == exp_brier &&
     metrics$overall_logloss == exp_logloss,
   sprintf("n=%d, acc=%.1f%%, brier=%.4f, logloss=%.4f",
           metrics$n_games_graded, metrics$overall_accuracy, metrics$overall_brier, metrics$overall_logloss))

diag_in <- list(
  n_games_graded = c(1L),
  overall_accuracy = c(100.0),
  overall_brier = c(0.1024),
  overall_logloss = c(0.3857),
  brier_baseline = c(0.25),
  brier_improvement = c(59.04),
  last_evaluated = c("2026-10-20 00:00:00")
)
rec1 <- RLR_ENV$reconcile_diagnostics(diag_in, metrics)
rec2 <- RLR_ENV$reconcile_diagnostics(rec1$diag, metrics)
ok("RLR-5 `reconcile_diagnostics()` updates tail row when game count changes and is idempotent on repeat call",
   isTRUE(rec1$changed) &&
     rec1$diag$n_games_graded[1] == 2L &&
     rec1$diag$overall_brier[1] == exp_brier &&
     !isTRUE(rec2$changed),
   sprintf("first call changed=%s, second call changed=%s", rec1$changed, rec2$changed))

mock_csv <- function(url) {
  data.frame(
    game_id = c("2025_01_A_B", "2026_01_A_B", "2026_01_C_D"),
    season = c(2025L, 2026L, 2026L),
    home_score = c(20L, 24L, NA_integer_),
    away_score = c(17L, 21L, NA_integer_),
    stringsAsFactors = FALSE
  )
}
fetched <- RLR_ENV$fetch_season_results(season = 2026L, csv_reader = mock_csv)
ok("RLR-6 `fetch_season_results()` filters to target season and scored finals only",
   nrow(fetched) == 1L && identical(fetched$game_id, "2026_01_A_B") && fetched$home_score == 24L,
   sprintf("rows=%d (%s)", nrow(fetched), fetched$game_id))

# ==============================================================================
# SECTION 5: tools/publish_web.R pure gate helpers (Assertions B, D, F)
# ==============================================================================
cat("\n--- Section 5: tools/publish_web.R pure gate helpers ---\n")
PW_ENV <- new.env(parent = globalenv())
PW_ENV$CURRENT_SEASON <- CURRENT_SEASON
PW_ENV$WEB_DATA_FILES <- WEB_DATA_FILES
load_ast_symbols(
  "tools/publish_web.R",
  c(".pw_log_timestamp", ".pw_detect_run_start", ".scan_exporter_warnings",
    ".pw_payload_generated_at", ".assert_payload_provenance",
    ".compute_active_week_from_schedules"),
  PW_ENV
)

log_sample <- c(
  "[2026-10-28 05:15:00] [INFO] [run_full_pipeline.R] Pipeline run started.",
  "[2026-10-28 05:14:00] [WARN] [R] export_web_datasets: older warning before run_start",
  "[2026-10-28 05:16:30] [WARN] [R] export_web_datasets: value_bets.json NOT refreshed"
)
run_st <- PW_ENV$.pw_detect_run_start(log_sample)
warns_in_window <- PW_ENV$.scan_exporter_warnings(log_sample, run_st)
ok("PW-1 `.pw_detect_run_start()` and `.scan_exporter_warnings()` isolate warnings at or after run_start",
   !is.na(run_st) &&
     length(warns_in_window) == 1L &&
     grepl("value_bets\\.json NOT refreshed", warns_in_window[1]),
   sprintf("found %d warning in run window", length(warns_in_window)))

tmp_stamped <- tempfile(fileext = ".json")
tmp_unstamped <- tempfile(fileext = ".json")
on.exit(unlink(c(tmp_stamped, tmp_unstamped)), add = TRUE)
writeLines('{\n  "generated_at": "2026-10-28T17:30:00Z",\n  "season": 2026\n}', tmp_stamped)
writeLines('{\n  "season": 2026\n}', tmp_unstamped)

ts_stamped <- PW_ENV$.pw_payload_generated_at(tmp_stamped)
ts_unstamped <- PW_ENV$.pw_payload_generated_at(tmp_unstamped)
ok("PW-2 (Assertion F) `.pw_payload_generated_at()` parses ISO-8601 UTC `generated_at` and returns NA when absent",
   !is.na(ts_stamped) &&
     identical(format(ts_stamped, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "2026-10-28T17:30:00Z") &&
     is.na(ts_unstamped),
   sprintf("stamped=%s, unstamped=%s",
           format(ts_stamped, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
           ifelse(is.na(ts_unstamped), "NA", as.character(ts_unstamped))))

tmp_sched <- tempfile(fileext = ".rds")
on.exit(unlink(tmp_sched), add = TRUE)
saveRDS(
  data.frame(
    season = c(CURRENT_SEASON, CURRENT_SEASON, CURRENT_SEASON),
    week = c(1L, 2L, 3L),
    gameday = as.character(c(Sys.Date() - 14L, Sys.Date() - 1L, Sys.Date() + 3L)),
    stringsAsFactors = FALSE
  ),
  tmp_sched
)
comp_wk <- PW_ENV$.compute_active_week_from_schedules(tmp_sched)
ok("PW-3 (Assertion B) `.compute_active_week_from_schedules()` picks the lowest week whose last gameday >= today",
   identical(comp_wk, 3L),
   sprintf("computed active_week=%d", comp_wk))

cat(sprintf("\n=== %s: %d failure(s) ===\n",
            if (failures == 0L) "ALL TESTS PASSED" else "TEST FAILURES", failures))
quit(status = if (failures == 0L) 0L else 1L)
