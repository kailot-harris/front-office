# ==============================================================================
# tools/derive_props_distribution_params.R
# ------------------------------------------------------------------------------
# PROVENANCE / RE-DERIVATION TOOL (Phase 4 finding L-5).
#
# Consolidates the three root-level `temp_derive_*.R` scratch files that
# originally produced the hardcoded distribution constants now living in the
# props engines. They sat at repo root — where this repo's convention is that
# *everything* is a pipeline script sourced by bare filename — and were
# indistinguishable from production code to a newcomer, while between them
# containing three verbatim copies of the same rotation-selection preamble.
#
# Constants this script re-derives (run it to re-check them against fresher
# `cache/player_box_scores_cache.rds` data; it writes nothing and mutates
# nothing):
#   - `player_props_engine.R`'s  PROP_DISPERSION   (theta per stat category)
#   - `player_props_engine.R`'s  ZERO_INFLATION_PI (pi_0 per stat category)
#   - `copula_props_engine.R`'s  sigma_mat         (PTS/REB/AST correlations in
#                                                   simulate_joint_player_props)
# All three are commented in their engines as "derived empirically from WNBA
# rotation data (2026-09-15)" — this file is the missing *how*.
#
# Superseded scratch files, and what happened to each (L-5):
#   - temp_derive_props_rot.R  -> folded in here as the ROTATION-FILTERED pass
#                                 (the pass whose numbers actually shipped).
#   - temp_derive_copula.R     -> folded in here as the CORRELATION pass.
#   - temp_derive_props.R      -> folded in here as the ALL-PLAYERS pass, kept
#                                 only as the contrast case that shows *why*
#                                 the rotation filter matters (garbage-time and
#                                 deep-bench rows inflate pi_0 and deflate mu).
#                                 Its numbers were NOT the ones shipped.
#   - temp_check_rapm.R        -> deleted, not folded in: a 3-line
#                                 `print(colnames(readRDS(...)))` REPL probe of
#                                 cache/rapm_ratings.rds with no derivation in
#                                 it, superseded by tools/data_health_probe.R
#                                 and by rapm_join_utils.R's typed contract.
#
# NOTE on the rotation selection below: `player_props_engine.R`'s
# `build_real_rotation_table()` is the PRODUCTION rotation selector and is
# strictly better (it prefers CURRENT_SEASON per-game means, coalesces to
# historical means, and applies `.by_group = TRUE` before slicing). It is NOT
# reused here on purpose: sourcing `player_props_engine.R` executes the whole
# engine as a side effect, which a read-only derivation tool must not do. The
# simplified selector below is therefore a deliberate approximation, kept
# because it is exactly what produced the shipped constants — reproducing them
# is the point. If you re-derive and the numbers move, reconcile against
# `build_real_rotation_table()` before editing any engine constant.
#
# R: C:\Program Files\R\R-4.5.2\bin\Rscript.exe tools/derive_props_distribution_params.R
# ==============================================================================

suppressPackageStartupMessages(library(dplyr))

# GitHub issue #90: PROJECT_DIR was a hardcoded absolute path to this repo's pre-move
# location, which stopped existing when the repo moved under front-office/. Derived from
# THIS SCRIPT'S own location now, walking up to the directory that holds config.R, so this
# tools/ script setwd()s to the real project root regardless of where it is invoked from
# (CLAUDE.md's tools/ convention) and fails loudly instead of silently no-op'ing (the
# dir.exists() guard) or aborting on a missing directory (the unguarded setwd). The walk-up
# is depth-agnostic, so it works from tools/<subdir>/ and inside a git worktree too.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()   # sourced interactively: start from the caller's cwd
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      stop(sprintf("derive_props_distribution_params.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
source("config.R")

ROSTERS_CACHE <- file.path(CACHE_DIR, "active_rosters_cache.rds")

if (!file.exists(CACHE_PLAYER_BOX) || !file.exists(ROSTERS_CACHE)) {
  # Fail-safe per repo convention: report and exit cleanly, never hard-crash.
  cat("[derive] Required cache missing — nothing to derive.\n")
  cat(sprintf("  %s exists = %s\n", CACHE_PLAYER_BOX, file.exists(CACHE_PLAYER_BOX)))
  cat(sprintf("  %s exists = %s\n", ROSTERS_CACHE, file.exists(ROSTERS_CACHE)))
  quit(save = "no", status = 0)
}

pbox    <- readRDS(CACHE_PLAYER_BOX)
rosters <- readRDS(ROSTERS_CACHE)

cat(sprintf("[derive] player box rows: %d | roster rows: %d | rotation depth: WNBA_ROTATION_SIZE = %d\n",
            nrow(pbox), nrow(rosters), WNBA_ROTATION_SIZE))

# ------------------------------------------------------------------------------
# Rotation selection (top-WNBA_ROTATION_SIZE players per team by average minutes).
# Depth reads config.R's constant rather than the literal `8` the scratch files
# hardcoded.
# ------------------------------------------------------------------------------
rotation_ids <- rosters |>
  left_join(
    pbox |> group_by(athlete_id) |> summarise(avg_min = mean(minutes, na.rm = TRUE), .groups = "drop"),
    by = c("player_id" = "athlete_id")
  ) |>
  group_by(team_name) |>
  arrange(desc(avg_min), .by_group = TRUE) |>
  slice_head(n = WNBA_ROTATION_SIZE) |>
  ungroup() |>
  pull(player_id)

pbox_rot <- pbox |> filter(athlete_id %in% rotation_ids)

cat(sprintf("[derive] rotation players selected: %d | rotation box rows: %d of %d (%.1f%%)\n",
            length(unique(rotation_ids)), nrow(pbox_rot), nrow(pbox),
            100 * nrow(pbox_rot) / max(1, nrow(pbox))))

# ------------------------------------------------------------------------------
# ZINB parameter derivation.
#   theta = mu^2 / (Var(X) - mu)   (negative-binomial method-of-moments)
#   pi_0  = P(X == 0)              (empirical structural-zero rate)
# theta falls back to 100 (effectively the Poisson limit) when Var <= mu, i.e.
# when the stat is under- rather than over-dispersed and NB has no valid MoM fit.
# ------------------------------------------------------------------------------
stat_cols <- c(PTS = "points", REB = "rebounds", AST = "assists",
               FG3M = "three_point_field_goals_made", STL = "steals", BLK = "blocks")

derive_zinb_params <- function(df, label) {
  out <- lapply(names(stat_cols), function(nm) {
    x     <- df[[stat_cols[[nm]]]]
    mu    <- mean(x, na.rm = TRUE)
    var_x <- var(x, na.rm = TRUE)
    pi_0  <- mean(x == 0, na.rm = TRUE)
    theta <- if (var_x > mu) mu^2 / (var_x - mu) else 100.0
    data.frame(stat = nm, mu = mu, var = var_x, pi_0 = pi_0, theta = theta)
  })
  res <- do.call(rbind, out)
  cat(sprintf("\n--- %s ---\n", label))
  print(res, row.names = FALSE, digits = 4)
  res
}

rot_params <- derive_zinb_params(pbox_rot, "ROTATION-FILTERED (this is what shipped)")
all_params <- derive_zinb_params(pbox,     "ALL PLAYERS (contrast only — NOT shipped)")

cat("\n[derive] Compare against player_props_engine.R's shipped constants:\n")
cat("  PROP_DISPERSION   (theta): PTS 2.4  REB 2.8  AST 2.1  FG3M 1.4  STL 3.9  BLK 1.0\n")
cat("  ZERO_INFLATION_PI (pi_0) : PTS 0.08 REB 0.08 AST 0.19 FG3M 0.49 STL 0.43 BLK 0.66\n")
cat("  (engine values are these rounded to the precision shown above)\n")

# ------------------------------------------------------------------------------
# Copula correlation matrix (copula_props_engine.R's sigma_mat).
# ------------------------------------------------------------------------------
cor_mat <- cor(pbox_rot |> select(points, rebounds, assists),
               use = "pairwise.complete.obs")

cat("\n--- PTS/REB/AST correlation, rotation players (copula_props_engine.R sigma_mat) ---\n")
print(round(cor_mat, 4))
cat("\n[derive] Compare against copula_props_engine.R's shipped sigma_mat:\n")
cat("  PTS-REB 0.37   PTS-AST 0.32   REB-AST 0.14\n")

cat("\n[derive] Done — read-only, no files written.\n")
