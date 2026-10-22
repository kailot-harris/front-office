# ------------------------------------------------------------------------------
# tools/verify_rapm_centering.R — verification for GitHub issue #71, fix A
# (ORAPM/DRAPM league-centering + low_sample_flag threshold raise).
#
# READ-ONLY. Reads cache/rapm_ratings.rds and writes NOTHING. Does not source
# rapm_engine.R (its trailing `if (!interactive()) invisible(estimate_rapm_ratings())`
# would refit the model and overwrite the production cache); the two functions it needs
# are sourced from a sanitised temp copy with that trailing block stripped.
#
# Checks:
#   1. mean(orapm) == mean(drapm) in the shipped cache (ridge's minimum-norm tie-break),
#      which is the precondition that makes centering total_rapm-preserving.
#   2. Applying the centering transform to the shipped cache leaves total_rapm unchanged:
#      reports max(abs(new_total - old_total)) against the 0.01 rounding tolerance.
#   3. assert_rapm_centered() passes on the centered frame, fails on the uncentered one,
#      and SKIPS (does not error) on an all-NA box-score-fallback-shaped frame.
#   4. low_sample_flag: old (300) vs new (2500) threshold — flagged counts and whether
#      each known noisy leaderboard entry is caught.
#
# Run: "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/verify_rapm_centering.R
# ------------------------------------------------------------------------------

# Per tools/ convention: resolve the project root so the script runs from anywhere.
if (!dir.exists("cache") && dir.exists(file.path("..", "cache"))) setwd("..")
stopifnot(dir.exists("cache"), file.exists("rapm_engine.R"))

OLD_THRESHOLD <- 300L
NEW_THRESHOLD <- 2500L
TOL_TOTAL     <- 0.01     # round(, 2) on each of orapm/drapm -> total can move by <= 0.01
TOL_CENTER    <- 0.02

rule <- function(x) cat("\n==== ", x, " ====\n", sep = "")

# --- source assert_rapm_centered() from a sanitised copy of rapm_engine.R ------
# Strips the trailing `if (!interactive()) invisible(estimate_rapm_ratings())` auto-run block,
# then evaluates ONLY the top-level `<name> <- function(...)` assignments — no source() calls,
# no package loading, no fit, no saveRDS. The production cache can never be touched from here.
sanitised_source <- function(path, want) {
  src <- readLines(path, warn = FALSE)
  cut <- grep("^if \\(!interactive\\(\\)\\)", src)
  if (length(cut) > 0) src <- src[seq_len(min(cut) - 1L)]
  tmp <- tempfile(fileext = ".R")
  writeLines(src, tmp)
  env <- new.env(parent = globalenv())
  for (expr in as.list(parse(tmp))) {
    if (!is.call(expr) || !as.character(expr[[1]]) %in% c("<-", "=")) next
    if (!is.name(expr[[2]]) || !as.character(expr[[2]]) %in% want) next
    if (!is.call(expr[[3]]) || as.character(expr[[3]][[1]]) != "function") next
    eval(expr, envir = env)
  }
  env
}

eng <- sanitised_source("rapm_engine.R", want = "assert_rapm_centered")
stopifnot(is.function(eng$assert_rapm_centered))
assert_rapm_centered <- eng$assert_rapm_centered
cat("Sourced assert_rapm_centered() from a sanitised temp copy of rapm_engine.R ",
    "(trailing auto-run block stripped; production cache untouched).\n", sep = "")

r <- readRDS("cache/rapm_ratings.rds")
cat(sprintf("Loaded cache/rapm_ratings.rds: %d rows, %d cols\n", nrow(r), ncol(r)))

# ---------------------------------------------------------------- 1. precondition
rule("1. Ridge minimum-norm precondition: mean(orapm) == mean(drapm)")
m_o <- mean(r$orapm, na.rm = TRUE)
m_d <- mean(r$drapm, na.rm = TRUE)
cat(sprintf("mean(orapm) = %.6f\nmean(drapm) = %.6f\ndifference  = %.8f\n", m_o, m_d, m_o - m_d))
cat(sprintf("PRECONDITION: %s (|diff| %s %.3f)\n",
            if (abs(m_o - m_d) <= TOL_TOTAL) "HOLDS" else "FAILS",
            if (abs(m_o - m_d) <= TOL_TOTAL) "<=" else ">", TOL_TOTAL))

# ------------------------------------------------- 2. total_rapm is preserved
rule("2. total_rapm preserved under centering")
orapm_c <- round(r$orapm - m_o, 2)
drapm_c <- round(r$drapm - m_d, 2)
new_total <- round(orapm_c - drapm_c, 2)
delta <- abs(new_total - r$total_rapm)
max_delta <- max(delta, na.rm = TRUE)
cat(sprintf("max(abs(new_total - old_total)) = %.6f  (tolerance %.2f)\n", max_delta, TOL_TOTAL))
cat(sprintf("rows differing at all           = %d of %d\n", sum(delta > 1e-9, na.rm = TRUE), nrow(r)))
# Engine-faithful variant: centering is applied before any rounding, so compare unrounded.
max_delta_unrounded <- max(abs(((r$orapm - m_o) - (r$drapm - m_d)) - (r$orapm - r$drapm)), na.rm = TRUE)
cat(sprintf("max delta WITHOUT double-rounding   = %.8f  (this is what the engine does)\n",
            max_delta_unrounded))
cat(sprintf("CRITERION 2: %s\n", if (max_delta <= TOL_TOTAL + 1e-9) "PASS" else "FAIL"))
# NOTE on the differing rows: this script DOUBLE-rounds (the cache columns are already
# round(, 2) and the transform rounds again), so values sitting exactly on a .xx5 boundary
# tip by one cent. In rapm_engine.R the centering is applied to the RAW coefficients BEFORE
# round(, 2), so the only real shift to total_rapm is mean(drapm) - mean(orapm) = -0.00026
# points per 100 possessions. Worst case either way is the 0.01 rounding tolerance, and no
# player's rank or interpretation moves.

# ------------------------------------------------- 3. contract invariant behaviour
rule("3. assert_rapm_centered() behaviour")
centered <- r
centered$orapm <- orapm_c
centered$drapm <- drapm_c
centered$total_rapm <- new_total
cat(sprintf("centered frame means: orapm %.6f | drapm %.6f | total %.6f\n",
            mean(centered$orapm), mean(centered$drapm), mean(centered$total_rapm)))
ok <- tryCatch({ assert_rapm_centered(centered, tolerance = TOL_CENTER); TRUE },
               error = function(e) { cat("UNEXPECTED ERROR: ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("  on CENTERED cache  -> %s (expected: passes)\n", if (ok) "passes" else "ERRORS"))

bad <- tryCatch({ assert_rapm_centered(r, tolerance = TOL_CENTER); FALSE },
                error = function(e) { cat("  caught (expected): ", conditionMessage(e), "\n"); TRUE })
cat(sprintf("  on UNCENTERED cache -> %s (expected: errors)\n", if (bad) "errors" else "PASSES (BAD)"))

fb <- centered
fb$orapm <- NA_real_; fb$drapm <- NA_real_; fb$total_rapm <- NA_real_
skipped <- tryCatch({ assert_rapm_centered(fb, tolerance = TOL_CENTER); TRUE },
                    error = function(e) { cat("UNEXPECTED ERROR: ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("  on all-NA fallback frame -> %s (expected: skipped, no error)\n",
            if (skipped) "skipped" else "ERRORS"))
cat(sprintf("CRITERION 4: %s\n", if (ok && bad && skipped) "PASS" else "FAIL"))

# ------------------------------------------------- 4. low_sample_flag thresholds
rule("4. low_sample_flag: old 300 vs new 2500")
n_comb <- r$n_off_poss + r$n_def_poss
known <- c("Dungee", "Nivar", "Clouden", "Park", "Jaquez")

for (thr in c(OLD_THRESHOLD, NEW_THRESHOLD)) {
  flag <- n_comb < thr
  cat(sprintf("\n-- threshold = %d combined possessions --\n", thr))
  cat(sprintf("flagged: %d of %d players (%.1f%%)\n", sum(flag), length(flag), 100 * mean(flag)))
  tab <- data.frame(
    player     = r$player_name[r$player_name %in% known],
    combined   = n_comb[r$player_name %in% known],
    total_rapm = r$total_rapm[r$player_name %in% known],
    flagged    = flag[r$player_name %in% known]
  )
  print(tab[order(tab$combined), ], row.names = FALSE)
  cat(sprintf("all known noisy leaders flagged: %s\n", all(tab$flagged)))
}

rule("DONE (nothing written)")
