# ==============================================================================
# tools/test_phase4_engine.R
# Path: tools/test_phase4_engine.R
#
# Phase 4 Wave 2 verification suite for P4-A (`agent_engine`). Re-runs the exact
# reproductions from docs/SECURITY_TECHNICAL_REVIEW.md for findings C-1, H-1, H-4,
# L-1, M-5 (engine half) and M-6 (local-definition removal) and asserts the defect
# is gone. Not part of run_full_pipeline.R's DAG.
#
# Per tools/ convention: setwd() to the absolute project root, then source()
# dependencies by bare filename, so this runs from any invocation directory.
#
# Run:  "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_engine.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(tidyr)
  library(httr2)
  library(tibble)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "test_phase4_engine.R"

ENGINE_FILE <- "market_odds_engine.R"
failures <- 0L

ok <- function(label, cond, detail = "") {
  cond <- isTRUE(cond)
  if (!cond) failures <<- failures + 1L
  cat(sprintf("[%s] %s%s\n", if (cond) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
  invisible(cond)
}

# ------------------------------------------------------------------------------
# Load market_odds_engine.R's DEFINITIONS ONLY.
# The file ends with a bare `evaluate_betting_slate()` call, so a plain source()
# would execute the whole pipeline. Eval only top-level `name <- value` assignments
# -- that captures every function definition while skipping the trailing call, the
# library()/source() calls and the setwd() guard. This means the functions under
# test are the REAL ones from the shipped file, not copies pasted into this test.
# ------------------------------------------------------------------------------
ENG <- new.env(parent = globalenv())
for (e in parse(ENGINE_FILE)) {
  if (is.call(e) && length(e) == 3L &&
      identical(as.character(e[[1]]), "<-") && is.name(e[[2]])) {
    eval(e, ENG)
  }
}
resolve_team_name <- get("resolve_team_name", envir = ENG)
fetch_market_odds <- get("fetch_market_odds", envir = ENG)

cat("\n=== Phase 4 Wave 2 engine tests (P4-A / agent_engine) ===\n\n")

# ==============================================================================
# CHECK 1 (C-1) -- the headline reproduction from the review, re-run.
# "implied home-prob for two IDENTICAL teams at hca=11.6, sigma=14: 0.796"
# Two identical teams => (h_net - a_net) == 0, fatigue_drag == 0, matchup delta
# == 0, so fair_margin collapses to the HCA term alone.
# ==============================================================================
p_fixed <- pnorm((0 + WNBA_HCA + 0 + 0) / WNBA_MARGIN_SIGMA)
p_bug   <- pnorm((0 + 11.6      + 0 + 0) / WNBA_MARGIN_SIGMA)
cat(sprintf("  config.R::WNBA_HCA = %s | WNBA_MARGIN_SIGMA = %s\n", WNBA_HCA, WNBA_MARGIN_SIGMA))
cat(sprintf("  implied home-prob for two IDENTICAL teams at hca=%.2f (fixed) : %.3f\n", WNBA_HCA, p_fixed))
cat(sprintf("  implied home-prob for two IDENTICAL teams at hca=11.60 (bug)  : %.3f\n", p_bug))
ok("CHECK 1 (C-1) implied home-win prob for two identical teams in [0.53, 0.60]",
   p_fixed >= 0.53 && p_fixed <= 0.60,
   sprintf("p = %.3f (was %.3f under the 11.6 bug; real WNBA home rate ~55-58%%)", p_fixed, p_bug))

# No literal HCA left in the engine source.
eng_src <- readLines(ENGINE_FILE, warn = FALSE)
code_only <- eng_src[!grepl("^\\s*#", eng_src)]
hca_literals <- grep("(\\+\\s*11\\.6|<-\\s*11\\.6|<-\\s*2\\.40?\\s*$)", code_only, value = TRUE)
ok("CHECK 1b (C-1) no hardcoded 11.6 / 2.40 HCA literal remains in engine code",
   length(hca_literals) == 0,
   if (length(hca_literals)) paste(trimws(hca_literals), collapse = " | ") else "0 literal HCA assignments; both sites read WNBA_HCA")

# ==============================================================================
# CHECK 2 (H-4 / L-1) -- resolve_team_name() fuzz.
# Review reproduction:  ""->Atlanta Dream, "a"->Atlanta Dream, "s"->Chicago Sky.
# ==============================================================================
cat("\n  resolve_team_name() fuzz (warnings below are the new H-4 WARN log lines):\n")
degenerate <- c("", "a", "s", "  ", "xy")
deg_res <- vapply(degenerate, function(x) {
  r <- resolve_team_name(x); if (is.na(r)) NA_character_ else r
}, character(1))
for (i in seq_along(degenerate)) {
  cat(sprintf("    input=%-8s -> %s\n", paste0('"', degenerate[i], '"'),
              ifelse(is.na(deg_res[i]), "NA_character_", deg_res[i])))
}
ok("CHECK 2a (H-4) degenerate inputs ('', 'a', 's', '  ', 'xy') all return NA_character_",
   all(is.na(deg_res)),
   sprintf("%d/%d returned NA (review had ''->Atlanta Dream, 'a'->Atlanta Dream, 's'->Chicago Sky)",
           sum(is.na(deg_res)), length(deg_res)))

good <- c("Las Vegas Aces", "Seattle Storm", "Minnesota Lynx", "Connecticut Sun",
          "Golden State Valkyries", "New York Liberty")
good_res <- vapply(good, resolve_team_name, character(1))
for (i in seq_along(good)) cat(sprintf("    input=%-24s -> %s\n", good[i], good_res[i]))
ok("CHECK 2b (H-4 regression guard) exact full franchise names still resolve to themselves",
   identical(unname(good_res), good),
   sprintf("%d/%d exact matches preserved", sum(unname(good_res) == good), length(good)))

abbr_in  <- c("LV", "SEA", "NY", "GS", "CON")
abbr_res <- vapply(abbr_in, resolve_team_name, character(1))
cat(sprintf("    abbreviations: %s\n", paste(sprintf("%s->%s", abbr_in, abbr_res), collapse = ", ")))
ok("CHECK 2c (H-4) 2-3 char WNBA_TEAMS abbreviations still resolve (length gate does not eat them)",
   identical(unname(abbr_res), unname(WNBA_TEAMS[abbr_in])),
   "abbreviation branch runs before the nchar(s) < 3 guard")

nick_res <- vapply(c("Aces", "Storm", "Valkyries"), resolve_team_name, character(1))
cat(sprintf("    nicknames: %s\n", paste(sprintf("%s->%s", names(nick_res), nick_res), collapse = ", ")))
ok("CHECK 2d (L-1) nickname clause is vectorized: every nickname tested, not just nick[1]",
   identical(unname(nick_res), c("Las Vegas Aces", "Seattle Storm", "Golden State Valkyries")),
   "pre-fix, grepl() saw a length-15 pattern and only ever tested 'dream'")

# L-1's signature R warning must be gone.
warns <- character(0)
withCallingHandlers(
  invisible(lapply(c("Storm", "Valkyries", "Unknown FC", "Toronto Raptors"), resolve_team_name)),
  warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }
)
len_warn <- grep("length > 1", warns, value = TRUE)
ok("CHECK 2e (L-1) no \"argument 'pattern' has length > 1\" R warning is raised",
   length(len_warn) == 0,
   if (length(len_warn)) paste(len_warn, collapse = "; ") else "0 pattern-length warnings across 4 fuzz inputs")

unk <- vapply(c("Unknown FC", "Toronto Raptors"), resolve_team_name, character(1))
ok("CHECK 2f (H-4) unrecognized-but-long inputs return NA, not the raw input passed through",
   all(is.na(unk)),
   sprintf("'Unknown FC' -> %s, 'Toronto Raptors' -> %s",
           ifelse(is.na(unk[1]), "NA", unk[1]), ifelse(is.na(unk[2]), "NA", unk[2])))

# The one caller must survive an NA team name (routes into its consensus fallback).
caller_ok <- tryCatch({
  standings <- readRDS(file.path(CACHE_DIR, "projected_wnba_standings.rds"))
  tm_col <- names(standings)[tolower(names(standings)) %in% c("team", "team_name")][1]
  h_row <- standings |> filter(tolower(.data[[tm_col]]) == tolower(NA_character_))
  abbr_for <- get("abbr_for", envir = ENG)
  list(nrow = nrow(h_row), abbr = abbr_for(NA_character_))
}, error = function(e) e)
ok("CHECK 2g (H-4) caller at get_model_slate_probabilities() handles an NA team name without crashing",
   !inherits(caller_ok, "error") && caller_ok$nrow == 0 && is.na(caller_ok$abbr),
   if (inherits(caller_ok, "error")) conditionMessage(caller_ok)
   else sprintf("standings filter on NA -> %d rows (routes to the devigged-consensus fallback); abbr_for(NA) -> NA",
                caller_ok$nrow))

# ==============================================================================
# CHECK 3 (H-1) -- the credential must never reach a log sink, from the REAL call
# site. ODDS_API_KEY is set to the review's fake secret and fetch_market_odds() is
# invoked for real; the request fails (bad key / no network), which is exactly the
# branch that used to write the key to console + wnba_pipeline.log + logs.duckdb.
# ==============================================================================
SECRET <- "SUPERSECRET123"
cat("\n  -- H-1: invoking the real fetch_market_odds() with ODDS_API_KEY=", SECRET, " --\n", sep = "")

log_file <- tryCatch(LOG_FILE, error = function(e) file.path("logs", "wnba_pipeline.log"))
n_before <- if (file.exists(log_file)) length(readLines(log_file, warn = FALSE)) else 0L

old_key <- Sys.getenv("ODDS_API_KEY", NA_character_)
Sys.setenv(ODDS_API_KEY = SECRET)
console <- capture.output(
  slate <- suppressWarnings(fetch_market_odds()),
  type = "output"
)
if (is.na(old_key)) Sys.unsetenv("ODDS_API_KEY") else Sys.setenv(ODDS_API_KEY = old_key)

new_lines <- if (file.exists(log_file)) {
  all_l <- readLines(log_file, warn = FALSE)
  if (length(all_l) > n_before) all_l[(n_before + 1L):length(all_l)] else character(0)
} else character(0)
cat(sprintf("  new %s lines written by that call: %d\n", log_file, length(new_lines)))
for (l in new_lines) cat("    ", l, "\n", sep = "")

db_hit <- tryCatch({
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = LOG_DB_FILE)
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)
  r <- DBI::dbGetQuery(con, "SELECT count(*) AS n FROM logs WHERE extra_json LIKE '%SUPERSECRET123%' OR message LIKE '%SUPERSECRET123%'")
  as.integer(r$n[1])
}, error = function(e) NA_integer_)

leak_log     <- any(grepl(SECRET, new_lines, fixed = TRUE))
leak_console <- any(grepl(SECRET, console, fixed = TRUE))
leak_src     <- any(grepl('"apiKey=", *api_key', eng_src)) ||
                any(grepl("paste0\\(.*apiKey.*api_key", eng_src))
ok("CHECK 3a (H-1) secret absent from logs/wnba_pipeline.log lines written by the real call site",
   !leak_log, sprintf("secret present in log = %s", leak_log))
ok("CHECK 3b (H-1) secret absent from console/stdout of the real call site",
   !leak_console, sprintf("secret present on stdout = %s", leak_console))
ok("CHECK 3c (H-1) secret absent from the logs.duckdb `logs` table",
   !is.na(db_hit) && db_hit == 0L,
   sprintf("rows in logs.duckdb containing the secret = %s", ifelse(is.na(db_hit), "QUERY FAILED", db_hit)))
ok("CHECK 3d (H-1) engine source never interpolates api_key into a URL string at all",
   !leak_src, "key is attached via httr2::req_url_query(); only the keyless base URL is logged")

# ==============================================================================
# CHECK 4 (M-5) -- provenance marker reaches the caller.
# ==============================================================================
cat("\n")
ok("CHECK 4a (M-5) fetch_market_odds() return value carries a market_data_source column",
   "market_data_source" %in% names(slate),
   sprintf("columns: %s", paste(names(slate), collapse = ", ")))
ok("CHECK 4b (M-5) fallback slate is marked SYNTHETIC_FALLBACK",
   all(slate$market_data_source == "SYNTHETIC_FALLBACK"),
   sprintf("unique(market_data_source) = %s over %d rows",
           paste(unique(slate$market_data_source), collapse = "/"), nrow(slate)))
live_marked <- any(grepl('market_data_source = "LIVE_ODDS_API"', eng_src, fixed = TRUE))
ok("CHECK 4c (M-5) live-parse branch is marked LIVE_ODDS_API",
   live_marked, "parse_multi_book_feed() result is tagged before return")
carried <- any(grepl("market_data_source = market_data_source", eng_src, fixed = TRUE))
ok("CHECK 4d (M-5) marker is carried into cache/latest_value_bets.rds's output_table",
   carried, "so prediction_accuracy_logger.R (agent_props) can read it off the cache")

# ==============================================================================
# CHECK 5 (M-6) -- zero local `%||%` DEFINITIONS remain (uses are fine).
# ==============================================================================
cat("\n")
defs <- grep("^\\s*`%\\|\\|%`\\s*(<-|=)", eng_src, value = TRUE)
uses <- grep("%\\|\\|%", eng_src, value = TRUE)
uses <- uses[!grepl("^\\s*#", uses) & !grepl("^\\s*`%\\|\\|%`\\s*(<-|=)", uses)]
src_line <- grep('source\\("logging_utils.R"\\)', eng_src)[1]
first_use <- grep("%\\|\\|%", eng_src)
first_use <- first_use[!grepl("^\\s*#", eng_src[first_use])][1]
cat(sprintf("  local `%%||%%` definitions in %s: %d | uses: %d\n", ENGINE_FILE, length(defs), length(uses)))
cat(sprintf("  source(\"logging_utils.R\") at line %d; first %%||%% use at line %d\n", src_line, first_use))
ok("CHECK 5a (M-6) zero local `%||%` redefinitions remain in market_odds_engine.R",
   length(defs) == 0,
   if (length(defs)) paste(trimws(defs), collapse = " | ") else "0 definitions; canonical one comes from logging_utils.R")
ok("CHECK 5b (M-6) logging_utils.R is sourced before the first `%||%` use",
   !is.na(src_line) && !is.na(first_use) && src_line < first_use,
   sprintf("source line %d < first use line %d", src_line, first_use))
bt_defs <- grep("^\\s*`%\\|\\|%`\\s*(<-|=)",
                readLines("tools/backtest_margin_hyperparams.R", warn = FALSE), value = TRUE)
ok("CHECK 5c (M-6) zero local `%||%` redefinitions in tools/backtest_margin_hyperparams.R (owned file)",
   length(bt_defs) == 0, "same unsafe scalar copy; removed for the same reason")

# ==============================================================================
# CHECK 6 (C-1, end to end) -- run the REAL engine standalone against real caches
# and assert every contrib_hca row equals WNBA_HCA.
#
# Phase 4 constraint: Wave 2 must not mutate cached .rds artifacts (regeneration is
# P4-G, Wave 3, pending user go-ahead). evaluate_betting_slate() writes
# latest_value_bets.rds and odds_history.rds, so both are backed up byte-for-byte
# before the run and restored after.
# ==============================================================================
cat("\n  -- C-1 end to end: running market_odds_engine.R standalone --\n")
touched <- file.path(CACHE_DIR, c("latest_value_bets.rds", "odds_history.rds"))
backups <- paste0(touched, ".p4a_bak")
for (i in seq_along(touched)) if (file.exists(touched[i])) file.copy(touched[i], backups[i], overwrite = TRUE)

rscript <- "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
run_out <- suppressWarnings(system2(rscript, shQuote(ENGINE_FILE), stdout = TRUE, stderr = TRUE))
run_status <- attr(run_out, "status"); if (is.null(run_status)) run_status <- 0L

vb_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
vb <- if (file.exists(vb_path)) readRDS(vb_path) else NULL

cat(sprintf("  exit status: %d | rows produced: %s\n", run_status, if (is.null(vb)) "NA" else nrow(vb)))
if (!is.null(vb) && "contrib_hca" %in% names(vb)) {
  cat("  contrib_hca column written by the run:\n")
  print(vb |> select(Matchup, contrib_hca, contrib_net_diff, predicted_margin, Model_Win_Prob, market_data_source) |> as.data.frame())
}

ok("CHECK 6a (C-1) market_odds_engine.R completes standalone against real caches",
   run_status == 0L && !is.null(vb) && nrow(vb) > 0,
   sprintf("exit=%d, %s rows", run_status, if (is.null(vb)) "0" else nrow(vb)))
ok("CHECK 6b (C-1) every contrib_hca row equals WNBA_HCA (2.40), not 11.6",
   !is.null(vb) && "contrib_hca" %in% names(vb) &&
     all(abs(vb$contrib_hca - WNBA_HCA) < 1e-9) && !any(abs(vb$contrib_hca - 11.6) < 1e-9),
   if (is.null(vb)) "no output" else sprintf("unique(contrib_hca) = %s",
                                             paste(unique(vb$contrib_hca), collapse = ", ")))
ok("CHECK 6c (M-5) market_data_source survives into cache/latest_value_bets.rds",
   !is.null(vb) && "market_data_source" %in% names(vb) &&
     all(vb$market_data_source %in% c("LIVE_ODDS_API", "SYNTHETIC_FALLBACK")),
   if (is.null(vb)) "no output" else paste(unique(vb$market_data_source), collapse = "/"))
if (!is.null(vb) && "Model_Win_Prob" %in% names(vb)) {
  ok("CHECK 6d (C-1 impact) recommendations are no longer all-home / all-max-stake",
     !all(vb$Bankroll_Rec == 3.0),
     sprintf("Bankroll_Rec values = %s (review: all 8 pinned at the 3%% Kelly cap)",
             paste(sort(unique(vb$Bankroll_Rec)), collapse = ", ")))
}

# Restore caches (Wave 2 must not mutate cached artifacts -- P4-G owns regeneration).
for (i in seq_along(touched)) {
  if (file.exists(backups[i])) { file.copy(backups[i], touched[i], overwrite = TRUE); file.remove(backups[i]) }
}
cat("  cached .rds artifacts restored to their pre-test bytes (P4-G owns regeneration).\n")

cat(sprintf("\n=== %s: %d check(s) failed ===\n",
            if (failures == 0L) "ALL CHECKS PASSED" else "FAILURES", failures))
quit(status = if (failures == 0L) 0L else 1L)
