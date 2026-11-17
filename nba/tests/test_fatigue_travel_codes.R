# ==============================================================================
# tests/test_fatigue_travel_codes.R
#
# NBA_analytics#155/#156/#157: fatigue_travel_engine.R is a pure library now
# (no stage, no cache write, no betting-worded column), and
# calculate_travel_fatigue() accepts the six ESPN codes that differ from
# ARENA_DB's (SA, NO, GS, NY, UTAH, WSH). A code it cannot place yields NA plus
# one >>> [WARN] line, never an error.
#
# No network, no caches. The slate below is real ESPN usage: ESPN's own short
# codes for road trips involving all six clubs.
#
# Usage: Rscript tests/test_fatigue_travel_codes.R
# ==============================================================================
REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
setwd(REPO_ROOT)
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) cat("  PASS:", label, "\n") else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n") }
}

out_rds <- file.path("cache", "travel_fatigue_metrics.rds")
before <- if (file.exists(out_rds)) file.info(out_rds)$mtime else NA
fe <- new.env()
msgs <- character(0)
withCallingHandlers(sys.source(file.path(REPO_ROOT, "fatigue_travel_engine.R"), envir = fe),
                    message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") })
after <- if (file.exists(out_rds)) file.info(out_rds)$mtime else NA

cat("sourcing is side-effect free\n")
check(identical(before, after), "no travel_fatigue_metrics.rds written")
check(!exists("evaluate_slate_fatigue", envir = fe), "slate stage function is gone")
check(is.function(fe$calculate_travel_fatigue) && is.data.frame(fe$ARENA_DB), "library API present")
check(!any(grepl("point_spread", readLines(file.path(REPO_ROOT, "fatigue_travel_engine.R")))), "no betting-worded column (#157)")
check(!any(grepl("fatigue_travel_engine", readLines(file.path(REPO_ROOT, "run_full_pipeline.R"))[
  grepl("run_stage", readLines(file.path(REPO_ROOT, "run_full_pipeline.R")))])), "not a pipeline stage")

cat("ESPN codes resolve to the same answer as the canonical codes\n")
pairs <- list(c("SA", "SAS"), c("NO", "NOP"), c("GS", "GSW"), c("NY", "NYK"), c("UTAH", "UTA"), c("WSH", "WAS"))
for (p in pairs) {
  as_dest <- fe$calculate_travel_fatigue(p[[1]], "BOS", days_rest = 1, is_back_to_back = FALSE)
  as_orig <- fe$calculate_travel_fatigue("DEN", p[[1]], days_rest = 0, is_back_to_back = TRUE)
  ref_dest <- fe$calculate_travel_fatigue(p[[2]], "BOS", days_rest = 1, is_back_to_back = FALSE)
  ref_orig <- fe$calculate_travel_fatigue("DEN", p[[2]], days_rest = 0, is_back_to_back = TRUE)
  check(!is.na(as_dest$fatigue_drag_pts) && identical(as_dest, ref_dest) && identical(as_orig, ref_orig),
        sprintf("%s == %s (as destination and as origin)", p[[1]], p[[2]]))
}

cat("a whole slate with those codes computes without error\n")
slate <- data.frame(home = c("SA", "NO", "GS", "NY", "UTAH", "WSH", "BOS"),
                    away = c("NY", "WSH", "UTAH", "GS", "NO", "SA", "DEN"), stringsAsFactors = FALSE)
res <- tryCatch(vapply(seq_len(nrow(slate)), function(i)
  fe$calculate_travel_fatigue(slate$home[i], slate$away[i], 1, FALSE)$fatigue_drag_pts, numeric(1)),
  error = function(e) NULL)
check(!is.null(res) && !anyNA(res), "7 games, all resolved, no NA")
rw <- tryCatch(
  dplyr::mutate(dplyr::rowwise(slate), fm = list(fe$calculate_travel_fatigue(home, away, 1, FALSE)),
                tz = fm$timezone_shift, miles = fm$travel_miles),
  error = function(e) NULL)
check(!is.null(rw) && !anyNA(rw$tz), "rowwise mutate (the #156 failure shape) works")

cat("an unknown code gives NA and one warning, never an error\n")
w <- character(0)
r <- withCallingHandlers(
  tryCatch(fe$calculate_travel_fatigue("XXX", "BOS", 1, FALSE), error = function(e) "THREW"),
  message = function(m) { w <<- c(w, conditionMessage(m)); invokeRestart("muffleMessage") })
check(is.list(r) && all(is.na(unlist(r))) && setequal(names(r),
      c("travel_miles", "timezone_shift", "destination_elevation", "fatigue_drag_pts")), "NA row with the normal shape")
check(sum(grepl("^>>> [[]WARN[]].*'XXX'", w)) == 1L, "one >>> [WARN] line")
w2 <- character(0)
withCallingHandlers(fe$calculate_travel_fatigue("XXX", "DEN", 1, FALSE),
                    message = function(m) { w2 <<- c(w2, conditionMessage(m)); invokeRestart("muffleMessage") })
check(length(w2) == 0L, "the same code is not warned about twice")
check(is.na(fe$calculate_travel_fatigue("BOS", NA_character_, 1, FALSE)$fatigue_drag_pts), "NA code -> NA, no error")

cat("every canonical ARENA_DB code still resolves against every other\n")
codes <- fe$ARENA_DB$team
all_ok <- all(vapply(codes, function(a) all(vapply(codes, function(b)
  !is.na(fe$calculate_travel_fatigue(a, b, 1, FALSE)$fatigue_drag_pts), logical(1))), logical(1)))
check(length(codes) == 30L && all_ok, "30 x 30 arena pairs all numeric")

cat(sprintf("\n%s\n", if (n_fail == 0L) "ALL PASSED" else sprintf("%d FAILED", n_fail)))
quit(status = if (n_fail == 0L) 0L else 1L)
