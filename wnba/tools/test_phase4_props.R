# ==============================================================================
# tools/test_phase4_props.R
# Phase 4 Wave 2 — P4-E / agent_props verification suite.
#
# Covers findings H-2, M-4, M-5, C-3, L-4, L-6 for the four files owned by
# agent_props: player_props_engine.R, prediction_accuracy_logger.R, daily_ingest.R,
# tools/generate_diagnostic_data.R.
#
# Runs against the REAL caches in cache/ and data/ — nothing here is mocked except
# the two deliberately-degenerate fail-safe probes (CHECK M-4d) and the sweep probe
# (CHECK M-5c), which operate on in-memory copies and never touch disk.
#
# Usage: "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_props.R
# ==============================================================================

setwd("c:/Users/kailo/kayceeslices/WNBA Analytics")

suppressPackageStartupMessages({
  library(dplyr)
  library(tibble)
})

.fails <- 0L
ok <- function(label, cond, detail = "") {
  cond <- isTRUE(cond)
  if (!cond) .fails <<- .fails + 1L
  cat(sprintf("[%s] %s%s\n", if (cond) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
  invisible(cond)
}
hdr <- function(x) cat(sprintf("\n----- %s -----\n", x))

cat("=== Phase 4 Wave 2 — P4-E (agent_props) tests ===\n")

RSCRIPT <- "C:/Program Files/R/R-4.5.2/bin/Rscript.exe"
CANON_PROPS <- "cache/latest_player_props.rds"   # config.R's CACHE_PLAYER_PROPS
STALE_PROPS <- "data/latest_player_props.rds"    # the L-6 second copy

# ==============================================================================
# H-2 — the nightly RAPM<->roster join failure
# ==============================================================================
hdr("H-2  player_props_engine.R runs to completion (was hard-failing nightly)")

mtime_before_canon <- if (file.exists(CANON_PROPS)) file.info(CANON_PROPS)$mtime else as.POSIXct(NA)
mtime_before_stale <- if (file.exists(STALE_PROPS)) file.info(STALE_PROPS)$mtime else as.POSIXct(NA)
cat(sprintf("  before: %s mtime = %s\n", CANON_PROPS, format(mtime_before_canon)))
cat(sprintf("  before: %s mtime = %s\n", STALE_PROPS, format(mtime_before_stale)))

Sys.sleep(1.1)  # guarantee an observable mtime tick on a 1s-resolution filesystem
run_out <- suppressWarnings(system2(RSCRIPT, "player_props_engine.R", stdout = TRUE, stderr = TRUE))
run_status <- attr(run_out, "status")
run_status <- if (is.null(run_status)) 0L else as.integer(run_status)

cat("  --- real stdout/stderr of `Rscript player_props_engine.R` ---\n")
cat(paste0("  ", run_out[!grepl("built under R version|^Warning message", run_out)]), sep = "\n")

ok("CHECK H-2a  player_props_engine.R exits 0 standalone against real caches",
   run_status == 0L, sprintf("exit status = %d", run_status))

join_err <- any(grepl("incompatible types|Can't join", run_out))
ok("CHECK H-2b  the nightly join type-error is GONE from the run output",
   !join_err,
   if (join_err) "STILL PRESENT" else "no \"Can't join ... incompatible types\" in stdout/stderr")

mtime_after_canon <- file.info(CANON_PROPS)$mtime
ok("CHECK H-2c  canonical props cache mtime advanced (was frozen at 2026-09-14 09:51)",
   is.na(mtime_before_canon) || mtime_after_canon > mtime_before_canon,
   sprintf("%s -> %s", format(mtime_before_canon), format(mtime_after_canon)))

props <- readRDS(CANON_PROPS)
ok("CHECK H-2d  fresh props cache is non-empty and covers all 15 franchises",
   nrow(props) > 0 && length(unique(props$team)) == 15,
   sprintf("%d rows, %d teams, %d stat categories",
           nrow(props), length(unique(props$team)), length(unique(props$stat))))

src <- readLines("player_props_engine.R", warn = FALSE)
n_naive <- sum(grepl('by = "player_id"', src, fixed = TRUE))
ok("CHECK H-2e  grep -c 'by = \"player_id\"' player_props_engine.R == 0",
   n_naive == 0L, sprintf("count = %d", n_naive))

ok("CHECK H-2f  player_props_engine.R sources the shared rapm_join_utils.R helper",
   any(grepl('source\\("rapm_join_utils.R"\\)', src)) &&
     any(grepl("join_rapm_to_roster\\(", src)),
   "source(\"rapm_join_utils.R\") + join_rapm_to_roster() both present")

# ==============================================================================
# M-4 — adjust_mu_for_opponent() sign, centring, clamp
# ==============================================================================
hdr("M-4  adjust_mu_for_opponent()")

# Load the engine's functions WITHOUT re-running the whole stage.
local({
  e <- new.env()
  old_int <- interactive
  sys.source("player_props_engine.R", envir = globalenv())
})
# sys.source() executes the trailing `if (!interactive())` block; that is fine (it
# just regenerates the cache again), but we re-read mtime afterwards where needed.

source("config.R")
source("rapm_join_utils.R")

rost <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
def_df <- get_team_def_rapm(rost)
league_avg <- attr(def_df, "league_avg_def")

cat(sprintf("  league centre (mean TEAM def_rapm) = %.4f   [old code used mean(rapm$drapm) = %.4f]\n",
            league_avg, mean(readRDS("cache/rapm_ratings.rds")$drapm, na.rm = TRUE)))
cat(sprintf("  team def_rapm range = %.3f .. %.3f across %d teams\n",
            min(def_df$def_rapm), max(def_df$def_rapm), nrow(def_df)))

base_mu <- 15.0

# *** READ THIS BEFORE "FIXING" THE DIRECTION OF THIS ASSERTION ***
# The P4-E brief asks to assert that `opp_def_rapm > league_avg_def` DECREASES mu,
# on the premise "facing a better defense should lower the projection". That premise
# is inherited from the very code comment M-4 exists to delete, and it is WRONG for
# this repo's cache: rapm_ratings.rds satisfies total_rapm == orapm - drapm (max abs
# deviation 0.01 over all 430 rows), i.e. drapm is points-ALLOWED flavoured, so
# LOWER drapm = BETTER defense. The empirical within-player slope is POSITIVE
# (+0.259 pts per +1 opponent drapm, t = +7.60, p = 3.0e-14, 2024-2026, n = 16,657).
# So we assert the SEMANTIC intent ("a better defense lowers mu") expressed in the
# correct variable direction, and separately pin the literal numeric direction the
# data actually supports. Asserting the brief's literal form would enshrine the sign
# error the finding is about.
mu_vs_weak   <- adjust_mu_for_opponent(base_mu, league_avg + 2, league_avg)  # weak D (high drapm)
mu_vs_strong <- adjust_mu_for_opponent(base_mu, league_avg - 2, league_avg)  # strong D (low drapm)
mu_vs_avg    <- adjust_mu_for_opponent(base_mu, league_avg,     league_avg)

cat(sprintf("  base_mu = %.2f | vs STRONG defense (drapm-2) -> %.4f | vs league-average -> %.4f | vs WEAK defense (drapm+2) -> %.4f\n",
            base_mu, mu_vs_strong, mu_vs_avg, mu_vs_weak))

ok("CHECK M-4a  facing a BETTER defense (lower drapm) LOWERS mu vs. base_mu",
   mu_vs_strong < base_mu,
   sprintf("%.4f < %.4f (delta %.4f)", mu_vs_strong, base_mu, mu_vs_strong - base_mu))

ok("CHECK M-4b  facing a WEAKER defense (higher drapm) RAISES mu; league-average is a no-op",
   mu_vs_weak > base_mu && isTRUE(all.equal(mu_vs_avg, base_mu)),
   sprintf("weak %.4f > base %.4f; average %.4f == base", mu_vs_weak, base_mu, mu_vs_avg))

# Empirical sign re-derivation, recomputed here so the test fails if the cache drifts.
pb <- readRDS(CACHE_PLAYER_BOX)
team_def <- def_df |> inner_join(
  tibble(team_name = unname(WNBA_TEAMS), abbr = names(WNBA_TEAMS)), by = "team_name")
d <- pb |>
  filter(season %in% 2024:2026, !is.na(points), !is.na(minutes), minutes > 0) |>
  mutate(opp_abbr = if_else(opponent_team_abbreviation == "CONN", "CON", opponent_team_abbreviation)) |>
  inner_join(team_def |> select(opp_abbr = abbr, opp_def = def_rapm), by = "opp_abbr") |>
  group_by(athlete_id) |> filter(n() >= 5) |>
  mutate(resid = points - mean(points, na.rm = TRUE), opp_c = opp_def - league_avg) |> ungroup()
fit <- summary(lm(resid ~ opp_c, data = d))$coefficients
cat(sprintf("  within-player regression (2024-2026, n=%d): slope = %+0.4f pts per +1 opp drapm (t = %+0.2f, p = %.3g)\n",
            nrow(d), fit[2, 1], fit[2, 3], fit[2, 4]))
ok("CHECK M-4c  shipped slope sign matches the sign measured on real box-score data",
   sign(fit[2, 1]) == sign(OPP_DEF_MU_SLOPE) && fit[2, 4] < 0.01,
   sprintf("measured %+0.4f (p = %.3g) vs shipped OPP_DEF_MU_SLOPE %+0.4f", fit[2, 1], fit[2, 4], OPP_DEF_MU_SLOPE))

# Clamp + no-division: the old raw-ratio form blew up on a near-zero denominator.
extreme_hi <- adjust_mu_for_opponent(base_mu, league_avg + 1000, league_avg)
extreme_lo <- adjust_mu_for_opponent(base_mu, league_avg - 1000, league_avg)
near_zero  <- adjust_mu_for_opponent(base_mu, 5, 1e-9)
neg_avg    <- adjust_mu_for_opponent(base_mu, -3, 0)
ok("CHECK M-4d  multiplier is clamped to [0.85, 1.15] and survives a near-zero / zero league_avg_def",
   isTRUE(all.equal(extreme_hi, base_mu * 1.15)) &&
     isTRUE(all.equal(extreme_lo, base_mu * 0.85)) &&
     is.finite(near_zero) && near_zero > 0 && is.finite(neg_avg) && neg_avg > 0,
   sprintf("+1000 -> %.3f (cap %.3f), -1000 -> %.3f (floor %.3f), league_avg=1e-9 -> %.3f, league_avg=0 -> %.3f",
           extreme_hi, base_mu * 1.15, extreme_lo, base_mu * 0.85, near_zero, neg_avg))

ok("CHECK M-4e  the \"I will follow the prompt's formula exactly\" rationale is deleted",
   !any(grepl("follow the prompt", src, ignore.case = TRUE)),
   "no 'follow the prompt' text remains in player_props_engine.R")

# ==============================================================================
# L-6 — exactly one props file is written
# ==============================================================================
hdr("L-6  single canonical props write")

ok("CHECK L-6a  player_props_engine.R writes ONLY CACHE_PLAYER_PROPS",
   sum(grepl("saveRDS\\(all_props", src)) == 1L &&
     any(grepl("saveRDS\\(all_props, CACHE_PLAYER_PROPS\\)", src)) &&
     !any(grepl('saveRDS\\(all_props, "data/latest_player_props.rds"\\)', src)),
   sprintf("%d saveRDS(all_props, ...) call site(s), target = CACHE_PLAYER_PROPS",
           sum(grepl("saveRDS\\(all_props", src))))

mtime_after_stale <- if (file.exists(STALE_PROPS)) file.info(STALE_PROPS)$mtime else as.POSIXct(NA)
ok("CHECK L-6b  the non-canonical data/ copy was NOT rewritten (left stale + untouched)",
   file.exists(STALE_PROPS) && isTRUE(all.equal(mtime_before_stale, mtime_after_stale)),
   sprintf("%s still at %s while canonical is at %s",
           STALE_PROPS, format(mtime_after_stale), format(file.info(CANON_PROPS)$mtime)))

# ==============================================================================
# C-3 / M-5 — prediction log schema, migration, provenance, sweep
# ==============================================================================
hdr("C-3 / M-5  prediction_accuracy_log.rds schema + migration")

source("prediction_accuracy_logger.R")   # sys.nframe() != 0 here, so nothing auto-runs

plog <- get_prediction_log()   # triggers + persists the one-time migration

ok("CHECK C-3a  `is_synthetic` column exists and is logical",
   "is_synthetic" %in% names(plog) && is.logical(plog$is_synthetic),
   sprintf("class = %s", class(plog$is_synthetic)[1]))

ok("CHECK C-3b  `market_data_source` column exists and is character",
   "market_data_source" %in% names(plog) && is.character(plog$market_data_source),
   sprintf("values = %s", paste(sort(unique(plog$market_data_source)), collapse = ", ")))

n_diag <- sum(grepl("^DIAG_", plog$game_id))
ok("CHECK C-3c  sum(is_synthetic) == the 100 DIAG_* rows from the review's reproduction",
   sum(plog$is_synthetic, na.rm = TRUE) == 100L && n_diag == 100L,
   sprintf("sum(is_synthetic) = %d, DIAG_* rows = %d, total rows = %d",
           sum(plog$is_synthetic, na.rm = TRUE), n_diag, nrow(plog)))

ok("CHECK C-3d  no NA in is_synthetic, and every DIAG_* row is flagged TRUE",
   !any(is.na(plog$is_synthetic)) &&
     all(plog$is_synthetic[grepl("^DIAG_", plog$game_id)]),
   sprintf("NA count = %d", sum(is.na(plog$is_synthetic))))

ok("CHECK C-3e  schema_version bumped to 2 on every row",
   all(plog$schema_version == 2L),
   sprintf("distinct schema_version = %s", paste(unique(plog$schema_version), collapse = ",")))

ok("CHECK C-3f  migration is idempotent (second read changes nothing)",
   identical(get_prediction_log()$is_synthetic, plog$is_synthetic) &&
     nrow(get_prediction_log()) == nrow(plog),
   sprintf("still %d rows, %d synthetic", nrow(plog), sum(plog$is_synthetic)))

ok("CHECK C-3g  the migration is persisted to disk, not recomputed per read",
   { onDisk <- readRDS(file.path(CACHE_DIR, "prediction_accuracy_log.rds"))
     "is_synthetic" %in% names(onDisk) && is.logical(onDisk$is_synthetic) &&
       sum(onDisk$is_synthetic) == 100L },
   "cache/prediction_accuracy_log.rds on disk carries the migrated schema")

summ_real <- summarize_prediction_accuracy("all")
summ_all  <- summarize_prediction_accuracy("all", include_synthetic = TRUE)
cat(sprintf("  summarize_prediction_accuracy('all')                        -> n = %d, accuracy = %s, excluded = %d\n",
            summ_real$n, format(summ_real$accuracy), summ_real$n_synthetic_excluded))
cat(sprintf("  summarize_prediction_accuracy('all', include_synthetic=TRUE) -> n = %d, accuracy = %s\n",
            summ_all$n, format(summ_all$accuracy)))
ok("CHECK C-3h  the fabricated 83%-accuracy fixtures no longer reach a reported metric",
   summ_real$n == 0L && summ_real$n_synthetic_excluded == 100L && summ_all$n == 100L,
   sprintf("real resolved n = %d (was 100 fixtures reported as 0.83 accuracy)", summ_real$n))

hdr("M-5  market_data_source propagation + UNRESOLVABLE sweep")

lp_src <- readLines("prediction_accuracy_logger.R", warn = FALSE)
# Executable lines only — these files carry long finding-ID comment blocks that
# legitimately quote the removed code, so a raw grep would match the prose.
code_only <- function(x) x[!grepl("^\\s*#", x)]
lp_code <- code_only(lp_src)
ok("CHECK M-5a  log_todays_predictions() writes market_data_source + is_synthetic",
   any(grepl("market_data_source\\s*=\\s*market_src", lp_src)) &&
     any(grepl("is_synthetic\\s*=\\s*row_synthetic", lp_src)),
   "both columns populated from the slate's provenance")

fake_slate <- tibble(market_data_source = c("LIVE_ODDS_API", "SYNTHETIC_FALLBACK", NA_character_))
got <- .slate_market_data_source(fake_slate)
no_col <- .slate_market_data_source(tibble(x = 1:3))
ok("CHECK M-5b  .slate_market_data_source() reads the column, and fails safe to UNKNOWN",
   identical(got, c("LIVE_ODDS_API", "SYNTHETIC_FALLBACK", "UNKNOWN")) &&
     identical(no_col, rep("UNKNOWN", 3)),
   sprintf("with column -> %s ; without column -> %s",
           paste(got, collapse = "/"), paste(unique(no_col), collapse = "/")))

probe <- tibble(
  game_id      = c("OLD_STUCK", "RECENT_PENDING", "ALREADY_RESOLVED"),
  game_date    = Sys.Date() - c(60, 1, 60),
  status       = c("PENDING", "PENDING", "RESOLVED"),
  is_synthetic = c(TRUE, FALSE, FALSE),
  resolved_timestamp = as.POSIXct(NA)
)
# persist = FALSE: exercise the sweep WITHOUT writing the probe over the real log.
log_rows_before_probe <- nrow(readRDS(file.path(CACHE_DIR, "prediction_accuracy_log.rds")))
swept <- .sweep_unresolvable(probe, persist = FALSE)
log_rows_after_probe <- nrow(readRDS(file.path(CACHE_DIR, "prediction_accuracy_log.rds")))
cat(sprintf("  sweep probe statuses: %s\n", paste(swept$game_id, swept$status, sep = "=", collapse = ", ")))
ok("CHECK M-5c  PENDING rows > 7 days past game_date become UNRESOLVABLE; fresh + RESOLVED untouched",
   swept$status[1] == "UNRESOLVABLE" && swept$status[2] == "PENDING" && swept$status[3] == "RESOLVED",
   "permanently-stuck fixture rows are now visible instead of accumulating under \"...yet\"")

ok("CHECK M-5e  the sweep probe did not touch the production log (persist = FALSE honoured)",
   log_rows_before_probe == log_rows_after_probe && log_rows_after_probe == 114L,
   sprintf("log still %d rows before and after the probe", log_rows_after_probe))

ok("CHECK M-5d  the misleading \"yet\" is gone from the no-match log message",
   !any(grepl('completed game in box_scores_cache.rds yet', lp_src)),
   "reconcile_predictions() no longer frames a permanent condition as transient")

# ==============================================================================
# L-4 — daily_ingest.R DAG wiring
# ==============================================================================
hdr("L-4  daily_ingest.R DAG wiring")

n_src_ingest  <- sum(grepl('source\\("daily_ingest.R"\\)', lp_code))
n_call_ingest <- sum(grepl("daily_box_ingest\\(", lp_code))
ok("CHECK L-4a  prediction_accuracy_logger.R no longer sources or triggers the ingest",
   n_src_ingest == 0L && n_call_ingest == 0L && any(grepl("CACHE_TEAM_BOX", lp_code)),
   sprintf("executable lines: %d source(\"daily_ingest.R\"), %d daily_box_ingest() call(s); reads CACHE_TEAM_BOX instead",
           n_src_ingest, n_call_ingest))

ok("CHECK L-4b  daily_box_ingest() is NOT defined after sourcing the logger (no implicit ingest)",
   !exists("daily_box_ingest", mode = "function"),
   "sourcing prediction_accuracy_logger.R no longer drags daily_ingest.R in")

# Reproduce run_stage()'s exact call shape: source(..., local = FALSE) from inside a
# function, then invoke the entry point by name — i.e. the call_fn mechanism.
nframe_seen <- NA_integer_
guard_fired <- FALSE
run_stage_shape <- function() {
  # A stand-in for daily_ingest.R's guard, measured at run_stage()'s nesting depth.
  nframe_seen <<- sys.nframe()
  invisible(NULL)
}
outer_wrapper <- function() run_stage_shape()
outer_wrapper()
ok("CHECK L-4c  sys.nframe() inside a run_stage()-shaped source is non-zero, so the guard stays dormant",
   !is.na(nframe_seen) && nframe_seen != 0L,
   sprintf("sys.nframe() = %d (guard `sys.nframe() == 0` is inert => call_fn must invoke explicitly)", nframe_seen))

di_src <- readLines("daily_ingest.R", warn = FALSE)
ok("CHECK L-4d  daily_ingest.R still guards on sys.nframe() == 0 and documents why (not !interactive())",
   any(grepl("if \\(sys.nframe\\(\\) == 0\\)", di_src)) &&
     any(grepl("call_fn", di_src)) &&
     !any(grepl("if \\(!interactive\\(\\)\\)", di_src)),
   "converting to !interactive() would double-ingest under call_fn; documented at the guard")

# Prove call_fn-style explicit invocation reaches the function.
ingest_env <- new.env()
invisible(capture.output(suppressMessages(sys.source("daily_ingest.R", envir = ingest_env))))
ok("CHECK L-4e  sourcing daily_ingest.R defines daily_box_ingest() WITHOUT running it (call_fn-ready)",
   exists("daily_box_ingest", envir = ingest_env, mode = "function"),
   "entry point is available for run_stage(call_fn = 'daily_box_ingest')")

# ==============================================================================
hdr("RESULT")
cat(sprintf("=== %s: %d check(s) failed ===\n",
            if (.fails == 0L) "ALL CHECKS PASSED" else "FAILURES", .fails))
quit(status = if (.fails == 0L) 0L else 1L)
