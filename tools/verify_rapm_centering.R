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

OLD_THRESHOLD      <- 300L    # the cut that shipped before issue #71
REJECTED_THRESHOLD <- 2500L   # count-based cut considered and rejected (flagged 48.8%)
LAMBDA             <- 900     # must match fit_rapm_ratings()'s default lambda
MIN_DATA_SHARE     <- 1 / 3   # rapm_engine.R::RAPM_MIN_DATA_SHARE
MIN_POSS_PER_SIDE  <- 1000L   # rapm_engine.R::RAPM_LEADERBOARD_MIN_POSS_PER_SIDE
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

# ------------------------------------------------- 4. low_sample_flag: shrinkage rule
# The flag is no longer a possession count. It is a SHRINKAGE rule: ridge shrinks each
# coefficient by ~ s = n / (n + lambda), so 1 - s is the share of the reported rating that
# came from the prior rather than the player. Flag when the weaker side is > 2/3 prior.
rule("4. low_sample_flag: shrinkage rule (s_min < 1/3) vs the old count cuts")
n_comb <- r$n_off_poss + r$n_def_poss
s_min  <- pmin(r$n_off_poss / (r$n_off_poss + LAMBDA),
               r$n_def_poss / (r$n_def_poss + LAMBDA))
known  <- c("Dungee", "Nivar", "Clouden", "Park", "Jaquez")
ord    <- order(-r$total_rapm)

# The two players the rule exists to catch, and the two it deliberately leaves visible.
MUST_FLAG  <- c("Dungee", "Nivar")

cat("\n-- exposure band vs. variability (why a count-based cut is the wrong instrument) --\n")
band <- cut(n_comb, c(0, 500, 1000, 2000, 3000, 5000, Inf),
            labels = c("<500", "500-1k", "1-2k", "2-3k", "3-5k", ">5k"))
bt <- do.call(rbind, lapply(levels(band), function(b) {
  v <- r$total_rapm[band == b]
  data.frame(band = b, n = length(v), sd = round(sd(v), 2))
}))
print(bt, row.names = FALSE)
cat("NOTE: sd does NOT rise as exposure falls -- the <500 band is the LEAST variable,\n")
cat("      because ridge shrinks it hardest. 'low exposure = noisy' is backwards here.\n")

cat("\n-- candidate rules --\n")
rules <- list(
  "combined < 300 (shipped)"   = n_comb < OLD_THRESHOLD,
  "combined < 2500 (rejected)" = n_comb < REJECTED_THRESHOLD,
  "s_min < 1/3 (adopted)"      = s_min < MIN_DATA_SHARE
)
for (nm in names(rules)) {
  f <- rules[[nm]]
  cat(sprintf("%-28s flagged=%3d (%4.1f%%)  of current top10 flagged: %d\n",
              nm, sum(f), 100 * mean(f), sum(f[ord][1:10])))
}

flag <- s_min < MIN_DATA_SHARE
sel  <- r$player_name %in% known
tab <- data.frame(
  player    = r$player_name[sel],
  off_poss  = r$n_off_poss[sel],
  def_poss  = r$n_def_poss[sel],
  total     = r$total_rapm[sel],
  pct_prior = round(100 * (1 - s_min[sel])),
  flagged   = flag[sel]
)
cat("\n-- adopted rule, applied to the five players the issue named --\n")
print(tab[order(tab$off_poss), ], row.names = FALSE)

must_ok <- all(flag[r$player_name %in% MUST_FLAG])
cat(sprintf("\nmust-flag players (%s) all flagged: %s\n",
            paste(MUST_FLAG, collapse = ", "), must_ok))
cat(sprintf("flag rate %.1f%% (was 48.8%% under the rejected count cut)\n", 100 * mean(flag)))
cat(sprintf("CRITERION 5: %s\n", if (must_ok && mean(flag) < 0.35) "PASS" else "FAIL"))

# ------------------------------------------------- 5. leaderboard eligibility
# Separate mechanism from the honesty flag: rank-eligibility, per side, not combined.
rule("5. leaderboard_eligible: >= 1000 possessions on BOTH sides")
elig <- pmin(r$n_off_poss, r$n_def_poss) >= MIN_POSS_PER_SIDE
cat(sprintf("eligible: %d of %d rows (%.1f%%)\n", sum(elig), length(elig), 100 * mean(elig)))
e <- r[elig, ]
e <- e[order(-e$total_rapm), ]
cat("\ntop 10 among eligible rows:\n")
print(data.frame(player = e$player_name[1:10],
                 weaker_side = pmin(e$n_off_poss, e$n_def_poss)[1:10],
                 total_rapm = e$total_rapm[1:10]), row.names = FALSE)
worst <- min(pmin(e$n_off_poss, e$n_def_poss)[1:10])
cat(sprintf("\nweakest side among the eligible top 10: %d (must be >= %d)\n",
            worst, MIN_POSS_PER_SIDE))
cat(sprintf("CRITERION 6: %s\n", if (worst >= MIN_POSS_PER_SIDE) "PASS" else "FAIL"))

rule("DONE (nothing written)")
