# ------------------------------------------------------------------------------
# tools/verify_rapm_sign_flip.R — verification for GitHub issues #79 and #80
# (drapm flipped to the conventional orientation: positive == strong defender,
# total_rapm == orapm + drapm).
#
# READ-ONLY. Reads cache/rapm_ratings.rds and cache/active_rosters_cache.rds and writes
# NOTHING. Does not source rapm_engine.R or player_props_engine.R wholesale (both have
# trailing auto-run blocks that would refit the model / rewrite production caches); the
# functions it needs are pulled from sanitised temp copies with those blocks stripped.
# No cache is regenerated or refit anywhere here — issue #81 owns the refit.
#
# Checks:
#   1. TOTAL PRESERVATION. Apply the new negate -> centre -> sum transform to the shipped
#      cache's raw orapm/drapm and compare against the shipped total_rapm.
#      Reports max(abs(new_total - old_total)) against the 0.01 round(, 2) tolerance.
#   2. RANK PRESERVATION. Count rows whose rank under arrange(desc(total_rapm)) moves.
#   3. assert_rapm_additive() passes on the transformed (new-convention) frame.
#   4. assert_rapm_additive() FAILS on a deliberately HALF-APPLIED change (drapm negated,
#      total_rapm left as a subtraction) and SKIPS on an all-NA box-score-fallback frame.
#   5. PROPS MULTIPLIER INVARIANCE. For all 15 franchises, compare the multiplier from
#      (+0.0256, raw drapm) against (-0.0256, negated drapm).
#      Reports max(abs(difference)).
#
# NOTE on check 5: it verifies the ALGEBRA of the paired flip (slope and regressor flipped
# together => identical multiplier), which is what issues #79/#80 change. It does NOT claim
# the shipped cache is already in the new convention — it is not (see the printed means
# below: both 7.12, so cache/rapm_ratings.rds predates both #71's centring and #79's
# negation). Until issue #81 refits that cache, the live props path reads old-convention
# drapm through the new negative slope. That inconsistency is reported, not papered over.
#
# Run: "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" --no-init-file tools/verify_rapm_sign_flip.R
# (--no-init-file is needed in a git worktree, where renv/library is unpopulated and renv's
#  sandbox hides the user library; it is a no-op for the packages this script uses.)
# ------------------------------------------------------------------------------

# Per tools/ convention: resolve the project root so the script runs from anywhere.
if (!dir.exists("cache") && dir.exists(file.path("..", "cache"))) setwd("..")
stopifnot(dir.exists("cache"), file.exists("rapm_engine.R"))

TOL_TOTAL    <- 0.01     # round(, 2) on each of orapm/drapm -> total can move by <= 0.01
TOL_ADDITIVE <- 0.015    # assert_rapm_additive()'s default: 3 * 0.005 rounding accumulation
OLD_SLOPE    <- 0.0256   # OPP_DEF_MU_SLOPE before issue #79
NEW_SLOPE    <- -0.0256  # OPP_DEF_MU_SLOPE after issue #79
CLAMP        <- c(0.85, 1.15)

rule <- function(x) cat("\n==== ", x, " ====\n", sep = "")
verdict <- function(label, ok) cat(sprintf("[%s] %s\n", if (isTRUE(ok)) "PASS" else "FAIL", label))

# --- pull the invariants from a sanitised copy of rapm_engine.R ----------------
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

eng <- sanitised_source("rapm_engine.R", want = c("assert_rapm_additive", "assert_rapm_centered"))
stopifnot(is.function(eng$assert_rapm_additive), is.function(eng$assert_rapm_centered))
assert_rapm_additive <- eng$assert_rapm_additive
assert_rapm_centered <- eng$assert_rapm_centered
cat("Sourced assert_rapm_additive() + assert_rapm_centered() from a sanitised temp copy of\n",
    "rapm_engine.R (trailing auto-run block stripped; production caches untouched).\n", sep = "")

r <- readRDS("cache/rapm_ratings.rds")
cat(sprintf("Loaded cache/rapm_ratings.rds: %d rows, %d cols (mtime %s)\n",
            nrow(r), ncol(r), format(file.info("cache/rapm_ratings.rds")$mtime)))
cat(sprintf("Shipped cache means: mean(orapm) = %.4f, mean(drapm) = %.4f\n",
            mean(r$orapm, na.rm = TRUE), mean(r$drapm, na.rm = TRUE)))
cat(sprintf("Shipped cache identity: max|total - (orapm - drapm)| = %.4f ; ",
            max(abs(r$total_rapm - (r$orapm - r$drapm)), na.rm = TRUE)))
cat(sprintf("max|total - (orapm + drapm)| = %.4f\n",
            max(abs(r$total_rapm - (r$orapm + r$drapm)), na.rm = TRUE)))
cat("  => the shipped cache is still PRE-#79 (and pre-#71-centring). Issue #81 owns the refit.\n")

# ------------------------------------------------- 1. total preservation
rule("1. Total preservation: negate -> centre -> sum vs centre -> subtract")
# The shipped cache's drapm is the RAW (un-negated, un-centred) defensive block, exactly what
# `coefficients[(n+1):(2n)] * 100` produces inside fit_rapm_ratings(). Replay BOTH pipelines
# on those same raw inputs and compare them to each other. That is the apples-to-apples test
# of what issue #79 changes, and it is the headline number.
#
# NEW (post-#79): negate, then centre each side on its own mean, then SUM.
o_new <- r$orapm - mean(r$orapm, na.rm = TRUE)
d_new <- -r$drapm
d_new <- d_new - mean(d_new, na.rm = TRUE)
total_new <- o_new + d_new
# OLD (pre-#79): centre each side on its own mean, then SUBTRACT.
o_old <- r$orapm - mean(r$orapm, na.rm = TRUE)
d_old <- r$drapm - mean(r$drapm, na.rm = TRUE)
total_old <- o_old - d_old

max_total_diff <- max(abs(total_new - total_old), na.rm = TRUE)
cat(sprintf("rows compared                            : %d\n", sum(!is.na(total_old))))
cat(sprintf("max(abs(new_total - old_total))           : %.3e\n", max_total_diff))
cat(sprintf("mean(abs(new_total - old_total))          : %.3e\n",
            mean(abs(total_new - total_old), na.rm = TRUE)))
cat(sprintf("tolerance                                 : %.4f\n", TOL_TOTAL))
cat("  (exactly 0 up to float representation: orapm - d_raw IS orapm + (-d_raw), and\n",
    "   mean(-d) == -mean(d), so the two pipelines are algebraically the same expression.)\n", sep = "")
verdict(sprintf("total_rapm preserved for all %d rows", nrow(r)), max_total_diff <= TOL_TOTAL)

# Order-independence of negation vs centring, stated explicitly.
alt <- -(r$drapm - mean(r$drapm, na.rm = TRUE))
cat(sprintf("negate-then-centre vs centre-then-negate  : max abs diff = %.3e (they commute)\n",
            max(abs(alt - d_new), na.rm = TRUE)))

# CONTEXT (not the criterion): the SHIPPED total_rapm column is round(, 2) AND predates #71's
# centring, so it differs from either recomputed pipeline by the rounding artifact that
# tools/verify_rapm_centering.R already documents at the 0.01 tolerance, plus the 0.000256
# residual of mean(orapm) - mean(drapm). That gap is pre-existing and identical for the old and
# new pipelines — it is not caused by the sign flip. Both numbers below are the same.
cat(sprintf("vs SHIPPED (rounded, uncentred) column    : new %.6f / old %.6f  [pre-existing\n",
            max(abs(total_new - r$total_rapm), na.rm = TRUE),
            max(abs(total_old - r$total_rapm), na.rm = TRUE)))
cat("   round(, 2) + pre-#71-centring artifact, identical for both pipelines; see\n",
    "   tools/verify_rapm_centering.R. Issue #81 owns the refit that clears it.]\n", sep = "")

# ------------------------------------------------- 2. rank preservation
rule("2. Rank preservation under arrange(desc(total_rapm))")
# Like-for-like again: rank the OLD pipeline's output against the NEW pipeline's output.
old_rank <- rank(-total_old, ties.method = "first")
new_rank <- rank(-total_new, ties.method = "first")
rank_changes <- sum(old_rank != new_rank)
cat(sprintf("rows whose rank changes: %d of %d\n", rank_changes, nrow(r)))
if (rank_changes > 0) {
  i <- which(old_rank != new_rank)
  print(data.frame(player = r$player_name[i], old_rank = old_rank[i], new_rank = new_rank[i]))
}
verdict("player ordering by total_rapm is identical", rank_changes == 0)

# Same check on the EXPORTED (round(, 2)) values, which is what any consumer actually sorts.
rank_changes_rounded <- sum(rank(-round(total_old, 2), ties.method = "first") !=
                            rank(-round(total_new, 2), ties.method = "first"))
cat(sprintf("rows whose rank changes after round(, 2): %d of %d\n", rank_changes_rounded, nrow(r)))
verdict("ordering identical on the exported, rounded values too", rank_changes_rounded == 0)

# ------------------------------------------------- 3/4. the additive invariant
rule("3. assert_rapm_additive() on the correctly-transformed frame")
good <- data.frame(orapm = round(o_new, 2), drapm = round(d_new, 2),
                   total_rapm = round(total_new, 2))
ok_good <- tryCatch({ assert_rapm_additive(good, tolerance = TOL_ADDITIVE); TRUE },
                    error = function(e) { cat("  unexpected error: ", conditionMessage(e), "\n"); FALSE })
cat(sprintf("max row-wise |total - (o + d)| on the transformed frame: %.4f (tolerance %.3f)\n",
            max(abs(good$total_rapm - (good$orapm + good$drapm))), TOL_ADDITIVE))
verdict("invariant PASSES on the new-convention frame", ok_good)
# The centring invariant must still hold on the same frame (it is sign-agnostic).
ok_centred <- tryCatch({ assert_rapm_centered(good, tolerance = 0.02); TRUE },
                       error = function(e) FALSE)
verdict("assert_rapm_centered() still PASSES on the same frame", ok_centred)

rule("4. assert_rapm_additive() on a deliberately HALF-APPLIED change")
# The exact failure mode issue #79 is easiest to get wrong: negate drapm in the engine but
# leave total_rapm as a subtraction. Every row then breaks the identity by 2 * drapm.
half <- data.frame(orapm = round(o_new, 2), drapm = round(d_new, 2),
                   total_rapm = round(o_new - d_new, 2))
msg <- tryCatch({ assert_rapm_additive(half, tolerance = TOL_ADDITIVE); NA_character_ },
                error = function(e) conditionMessage(e))
cat("error raised:\n  ", if (is.na(msg)) "<none - INVARIANT DID NOT FIRE>" else msg, "\n", sep = "")
verdict("invariant FAILS on the half-applied change", !is.na(msg))

# Fallback path: all-NA O/D must SKIP, not fail.
fb <- data.frame(orapm = NA_real_, drapm = NA_real_, total_rapm = c(1.5, -2.0, 0.3))
ok_fb <- tryCatch({ assert_rapm_additive(fb, tolerance = TOL_ADDITIVE); TRUE },
                  error = function(e) FALSE)
verdict("invariant SKIPS (does not fail) on the all-NA box-score fallback frame", ok_fb)

# ------------------------------------------------- 5. props multiplier invariance
rule("5. adjust_mu_for_opponent() multiplier invariance across the paired flip")
# Replay get_team_def_rapm()'s possession-weighted team aggregate, then build the multiplier
# both ways. OLD: (+0.0256, raw drapm). NEW: (-0.0256, negated drapm). Both centre on the
# league mean of the same 15 team aggregates, so the bracketed difference just changes sign.
suppressPackageStartupMessages({ library(dplyr); library(tibble) })
source("config.R")
source("rapm_join_utils.R")

rosters <- readRDS("cache/active_rosters_cache.rds")
joined  <- join_rapm_to_roster(rosters, r, matched_only = TRUE)

agg_old <- joined %>% group_by(team_name) %>%
  summarise(def_rapm = sum(drapm * n_def_poss, na.rm = TRUE) / sum(n_def_poss, na.rm = TRUE),
            .groups = "drop") %>% filter(is.finite(def_rapm))
agg_new <- agg_old %>% mutate(def_rapm = -def_rapm)   # negation passes through the weighted mean

multiplier <- function(def_rapm, league_avg, slope) {
  ratio <- 1 + slope * (def_rapm - league_avg)
  pmin(pmax(ratio, CLAMP[1]), CLAMP[2])
}
m_old <- multiplier(agg_old$def_rapm, mean(agg_old$def_rapm), OLD_SLOPE)
m_new <- multiplier(agg_new$def_rapm, mean(agg_new$def_rapm), NEW_SLOPE)

cmp <- tibble(team = agg_old$team_name,
              def_rapm_old = round(agg_old$def_rapm, 4),
              def_rapm_new = round(agg_new$def_rapm, 4),
              mult_old = m_old, mult_new = m_new,
              diff = m_new - m_old)
print(as.data.frame(cmp), digits = 10)
max_mult_diff <- max(abs(cmp$diff))
cat(sprintf("\nfranchises compared                 : %d\n", nrow(cmp)))
cat(sprintf("league centre old / new             : %+.4f / %+.4f\n",
            mean(agg_old$def_rapm), mean(agg_new$def_rapm)))
cat(sprintf("max(abs(mult_new - mult_old))        : %.3e\n", max_mult_diff))
verdict("multiplier bit-identical across the paired flip for all 15 franchises",
        max_mult_diff < 1e-12)

rule("SUMMARY")
cat(sprintf("max_total_diff   = %.10f  (tolerance %.4f)\n", max_total_diff, TOL_TOTAL))
cat(sprintf("rank_changes     = %d\n", rank_changes))
cat(sprintf("max_mult_diff    = %.3e\n", max_mult_diff))
cat("Nothing was written. cache/ is untouched by this script.\n")
