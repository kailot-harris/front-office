# ------------------------------------------------------------------------------
# tools/verify_rapm_y_centering.R — verification for GitHub issue #76
# (centre the ridge target `y` on the league mean in build_possession_design_matrix()).
#
# WRITES NOTHING UNDER cache/. The one refit it performs is written to a tempfile()
# path, and the shipped cache/rapm_ratings.rds is read only. Does NOT source
# rapm_engine.R directly: its trailing `if (!interactive()) invisible(estimate_rapm_ratings())`
# would refit the model and overwrite cache/rapm_ratings.rds. The engine is loaded from a
# sanitised temp copy with that trailing block stripped (same pattern as
# tools/verify_rapm_centering.R:38-60).
#
# Criteria:
#   1. build_possession_design_matrix() returns a centred y and a league_ppp scalar.
#   2. The exported ratings frame carries league_ppp rounded to 4 dp (one unique value, ~1.16).
#   3. Raw PRE-centring block means drop from ~+7.12 to ~0 — two fits on the identical X and
#      identical lambda, one on centred y and one on raw points.
#   4. Exported orapm/drapm/total_rapm vs. the shipped cache for all rows: max abs diff and
#      the number of total_rapm rank changes.
#   5. assert_rapm_centered(tol 0.02) and assert_rapm_additive(tol 0.015) pass unchanged on
#      the new refit, and assert_rapm_additive() still catches a half-applied sign change.
#
# Run: "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/verify_rapm_y_centering.R
# ------------------------------------------------------------------------------

# Per tools/ convention: resolve the project root so the script runs from anywhere.
if (!dir.exists("cache") && dir.exists(file.path("..", "cache"))) setwd("..")
stopifnot(dir.exists("cache"), file.exists("rapm_engine.R"))

LAMBDA     <- 900     # must match fit_rapm_ratings()'s default lambda
TOL_CENTER <- 0.02    # rapm_engine.R::assert_rapm_centered() default — NOT tightened here (#77)
TOL_ADD    <- 0.015   # rapm_engine.R::assert_rapm_additive() default — NOT tightened here (#77)
TOL_ZERO   <- 0.1     # centred raw block means must be within this of zero
TOL_EXPORT <- 0.02    # exported total_rapm movement budget: round(,2) + ~0.002 pre-filter residual

results <- list()
record  <- function(id, ok) { results[[id]] <<- isTRUE(ok); invisible(ok) }
rule    <- function(x) cat("\n==== ", x, " ====\n", sep = "")

# --- load the engine from a sanitised copy ------------------------------------
# Strip the trailing auto-run block, then source the remainder. Nothing in what is left
# fits or saves anything, so the production cache can never be touched from here.
engine_src  <- readLines("rapm_engine.R", warn = FALSE)
cut_at      <- grep("^if \\(!interactive\\(\\)\\)", engine_src)
stopifnot(length(cut_at) == 1)
sanitised   <- tempfile(fileext = ".R")
writeLines(engine_src[seq_len(cut_at[1] - 1L)], sanitised)
suppressMessages(source(sanitised))
cat("Loaded rapm_engine.R from a sanitised temp copy (trailing auto-run block stripped at\n",
    sprintf("source line %d; production cache untouched).\n", cut_at[1]), sep = "")

# ---------------------------------------------------------------- 1. design matrix
rule("1. build_possession_design_matrix(): centred y + league_ppp in the returned list")
pbp <- load_or_build_wnba_pbp_cache(seasons = ALL_SEASONS, force_refresh = FALSE)
stopifnot(!is.null(pbp), !is.null(pbp$possessions), nrow(pbp$possessions) > 0)
dm <- build_possession_design_matrix(pbp$possessions)

has_ppp  <- "league_ppp" %in% names(dm)
cat(sprintf("league_ppp present in returned list : %s\n", has_ppp))
cat(sprintf("league_ppp                          = %.6f\n", dm$league_ppp))
cat(sprintf("mean(y)                             = %.12f   (must be ~0)\n", mean(dm$y)))
cat(sprintf("mean(y) + league_ppp                = %.6f   (== raw mean points)\n",
            mean(dm$y) + dm$league_ppp))
cat(sprintf("n_possessions = %d, n_players = %d\n", nrow(dm$X), dm$n_players))
record("1", has_ppp && abs(mean(dm$y)) < 1e-9 && dm$league_ppp > 0.8 && dm$league_ppp < 1.5)
cat(sprintf("CRITERION 1: %s\n", if (results[["1"]]) "PASS" else "FAIL"))

# ---------------------------------------------------------------- 3. raw block means
# (run before criterion 2 because it reuses `dm`; the two fits below share X, weights and
# lambda exactly and differ ONLY in whether league_ppp was subtracted from the target.)
rule("3. Raw PRE-centring block means: centred y vs. raw points")
fit_blocks <- function(y, label) {
  co <- solve_ridge_rapm(dm$X, y, weights = dm$weights, lambda = LAMBDA)
  m_off <- mean(co[1:dm$n_players] * 100)
  m_def <- mean(co[(dm$n_players + 1):(2 * dm$n_players)] * 100)
  cat(sprintf("%-14s mean(raw_orapm_block) = %+8.4f   mean(raw_drapm_block) = %+8.4f\n",
              label, m_off, m_def))
  c(off = m_off, def = m_def)
}
cat("Blocks are the RAW ridge coefficients * 100, before the issue-#79 negation of the\n",
    "defensive block and before the post-hoc sum-to-zero centring step.\n", sep = "")
centred   <- fit_blocks(dm$y, "centred y:")
uncentred <- fit_blocks(dm$y + dm$league_ppp, "raw points:")
cat(sprintf("\nshift removed: %+.4f (offence), %+.4f (defence)\n",
            centred["off"] - uncentred["off"], centred["def"] - uncentred["def"]))
record("3", max(abs(centred)) <= TOL_ZERO && min(abs(uncentred)) > 1)
cat(sprintf("CRITERION 3: %s (centred pair within %.2f of zero: %s)\n",
            if (results[["3"]]) "PASS" else "FAIL", TOL_ZERO, max(abs(centred)) <= TOL_ZERO))

# ---------------------------------------------------------------- 2. exported league_ppp
rule("2. Standalone refit: exported league_ppp column")
out_path <- tempfile(fileext = ".rds")   # TEMP ONLY — never cache/
refit <- suppressMessages(fit_rapm_ratings(seasons = ALL_SEASONS, lambda = LAMBDA,
                                           force_refresh = FALSE,
                                           team_attribution = "current_roster"))
saveRDS(refit, out_path)
cat(sprintf("Refit written to temp path: %s\n", out_path))
cat(sprintf("refit rows = %d, cols = %d\n", nrow(refit), ncol(refit)))
u <- unique(refit$league_ppp)
cat(sprintf("unique(refit$league_ppp) = %s  (n = %d)\n",
            paste(sprintf("%.4f", u), collapse = ", "), length(u)))
cat(sprintf("4-dp rounded as exported, matches dm$league_ppp: %s\n",
            identical(u, round(dm$league_ppp, 4))))
record("2", length(u) == 1 && identical(u, round(dm$league_ppp, 4)) && u > 0.8 && u < 1.5)
cat(sprintf("CRITERION 2: %s\n", if (results[["2"]]) "PASS" else "FAIL"))

# ---------------------------------------------------------------- 4. vs the shipped cache
rule("4. Exported ratings vs. the shipped cache/rapm_ratings.rds")
old <- readRDS("cache/rapm_ratings.rds")
cat(sprintf("shipped cache: %d rows, %d cols | refit: %d rows, %d cols\n",
            nrow(old), ncol(old), nrow(refit), ncol(refit)))
cat(sprintf("new columns in refit: %s\n",
            paste(setdiff(names(refit), names(old)), collapse = ", ")))
j <- merge(old[, c("player_id", "orapm", "drapm", "total_rapm")],
           refit[, c("player_id", "orapm", "drapm", "total_rapm")],
           by = "player_id", suffixes = c("_old", "_new"))
cat(sprintf("rows matched on player_id: %d of %d\n", nrow(j), nrow(old)))
dmax <- sapply(c("orapm", "drapm", "total_rapm"), function(cc)
  max(abs(j[[paste0(cc, "_new")]] - j[[paste0(cc, "_old")]]), na.rm = TRUE))
for (cc in names(dmax)) cat(sprintf("max(abs(diff %-10s)) = %.6f\n", cc, dmax[[cc]]))
cat(sprintf("rows with any total_rapm movement at all: %d of %d\n",
            sum(abs(j$total_rapm_new - j$total_rapm_old) > 1e-9), nrow(j)))

rank_of <- function(df) {
  o <- df[order(-df$total_rapm, df$player_id), ]
  setNames(seq_len(nrow(o)), o$player_id)
}
r_old <- rank_of(old[, c("player_id", "total_rapm")])
r_new <- rank_of(refit[, c("player_id", "total_rapm")])
common <- intersect(names(r_old), names(r_new))
rank_changes <- sum(r_old[common] != r_new[common])
cat(sprintf("total_rapm rank changes under arrange(desc(total_rapm)): %d of %d\n",
            rank_changes, length(common)))
rank_delta <- abs(r_old[common] - r_new[common])
cat(sprintf("rank-change magnitude: max %d places, median (among movers) %g\n",
            max(rank_delta), median(rank_delta[rank_delta > 0])))
record("4", nrow(j) == nrow(old) && dmax[["total_rapm"]] <= TOL_EXPORT && rank_changes == 0)
cat(sprintf("CRITERION 4: %s (budget: |total_rapm diff| <= %.2f AND no rank change)\n",
            if (results[["4"]]) "PASS" else "FAIL", TOL_EXPORT))

# --- 4b. WHY: ridge is LINEAR but not SHIFT-EQUIVARIANT in y ------------------
# coefs(y) = (X'X + lambda*I)^-1 X'y is linear in y, so
#     coefs(points - c) == coefs(points) - c * coefs(1)
# where coefs(1) is the ridge fit against an all-ones target. coefs(1) is NOT a constant
# vector: entry i is shrunk by roughly n_i / (n_i + lambda), so a high-exposure player
# absorbs far more of the constant than a heavily shrunk one. Subtracting league_ppp from y
# therefore does NOT merely slide both blocks along the unidentified null direction v -- it
# re-weights every coefficient by its own exposure. That is why the post-hoc sum-to-zero step
# cannot undo it, and why the exported O/D SPLIT moves even though the shared offset was
# already being removed. Proof by direct computation below.
rule("4b. Why the exported split moves: coefs(1) is exposure-weighted, not constant")
unit <- solve_ridge_rapm(dm$X, rep(1, length(dm$y)), weights = dm$weights, lambda = LAMBDA)
d_off <- dm$league_ppp * unit[1:dm$n_players] * 100
d_def <- dm$league_ppp * unit[(dm$n_players + 1):(2 * dm$n_players)] * 100
cat(sprintf("per-player shift from subtracting league_ppp (pts/100), offence block:\n"))
cat(sprintf("  mean %+.4f | sd %.4f | range [%+.4f, %+.4f]\n",
            mean(d_off), sd(d_off), min(d_off), max(d_off)))
cat(sprintf("  defence block: mean %+.4f | sd %.4f | range [%+.4f, %+.4f]\n",
            mean(d_def), sd(d_def), min(d_def), max(d_def)))
cat(sprintf("mean == the +7.12 offset the fit used to carry: %+.4f\n", mean(d_off)))
# After the post-hoc centring, orapm moves by -(d_off - mean(d_off)); drapm is NEGATED on
# export so it moves by +(d_def - mean(d_def)); total_rapm moves by the DIFFERENCE of the two,
# which is non-zero exactly where a player's offensive and defensive exposure differ.
pred_orapm <- -(d_off - mean(d_off))
pred_total <- (d_def - mean(d_def)) - (d_off - mean(d_off))
cat(sprintf("predicted |orapm| movement after centring: max %.4f (observed %.4f)\n",
            max(abs(pred_orapm)), dmax[["orapm"]]))
cat(sprintf("predicted |total_rapm| movement:           max %.4f (observed %.4f)\n",
            max(abs(pred_total)), dmax[["total_rapm"]]))
cat("CONCLUSION: the movement is an exposure-weighted re-split of O vs D, NOT rounding and\n",
    "NOT the ~0.002 pre-filter residual. total_rapm is near-preserved only because the two\n",
    "blocks shift almost identically per player; it is not preserved exactly.\n", sep = "")

# ---------------------------------------------------------------- 5. invariants
rule("5. Existing invariants at their CURRENT tolerances (unchanged — #77 owns tightening)")
cat(sprintf("refit means: orapm %.6f | drapm %.6f | total %.6f\n",
            mean(refit$orapm), mean(refit$drapm), mean(refit$total_rapm)))
ok_c <- tryCatch({ assert_rapm_centered(refit, tolerance = TOL_CENTER); TRUE },
                 error = function(e) { cat("UNEXPECTED ERROR: ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("assert_rapm_centered(tolerance = %.3f) -> %s (expected: passes)\n",
            TOL_CENTER, if (ok_c) "passes" else "ERRORS"))
ok_a <- tryCatch({ assert_rapm_additive(refit, tolerance = TOL_ADD); TRUE },
                 error = function(e) { cat("UNEXPECTED ERROR: ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("assert_rapm_additive(tolerance = %.3f) -> %s (expected: passes)\n",
            TOL_ADD, if (ok_a) "passes" else "ERRORS"))

# Deliberately half-applied sign change: negate drapm but leave total_rapm as the sum of the
# un-negated pair. The additive identity must break loudly.
half <- refit
half$drapm <- -half$drapm            # total_rapm left as orapm + (un-negated drapm)
ok_h <- tryCatch({ assert_rapm_additive(half, tolerance = TOL_ADD); FALSE },
                 error = function(e) { cat("caught (expected): ", conditionMessage(e), "\n"); TRUE })
cat(sprintf("assert_rapm_additive() on the half-applied frame -> %s (expected: errors)\n",
            if (ok_h) "errors" else "PASSES (BAD)"))
record("5", ok_c && ok_a && ok_h)
cat(sprintf("CRITERION 5: %s\n", if (results[["5"]]) "PASS" else "FAIL"))

# ---------------------------------------------------------------- summary
rule("SUMMARY")
for (id in c("1", "2", "3", "4", "5"))
  cat(sprintf("  criterion %s: %s\n", id, if (results[[id]]) "PASS" else "FAIL"))
all_ok <- all(unlist(results))
cat(sprintf("\nOVERALL: %s  (nothing written under cache/; refit went to %s)\n",
            if (all_ok) "PASS" else "FAIL", out_path))
if (!all_ok) quit(status = 1)
