# ==============================================================================
# tools/gif_forecast_calibration.R
# Path: tools/gif_forecast_calibration.R
#
# WNBA Predicted-vs-Actual Win-Rate Calibration Animation. Gallery chart #10
# of GitHub issue kailot-harris/front-office#145 (part of #140's "gallery
# phase 2" batch), built on #144's phase-1 shared viz plumbing
# (tools/viz_common.R / tools/viz_gallery_helpers.R).
#
# NBA counterpart: NONE. Per #140's design table this chart is "Planned for
# NBA" -- the NBA repo does not have a prediction-accuracy log or this chart
# yet either, so there is nothing to port/adapt from. This is a from-scratch
# WNBA-only build.
#
# What this chart shows: bins this model's own genuine pre-game win-probability
# forecasts into deciles (or fewer, if the real log does not yet have enough
# rows to support ten groups -- see n_calibration_bins() below) and plots mean
# predicted probability against the actual win rate observed in each bin, with
# a y = x reference line. Points on the line mean "when the model says X%, it
# wins about X% of the time" -- the standard reliability-diagram reading. The
# animation adds one real calendar week of additional resolved genuine
# predictions per frame, so viewers watch the calibration curve firm up (and
# any systematic over/under-confidence emerge) as more real games resolve.
#
# Foundation & theme:
#   - sources tools/viz_common.R (theme_wnba_dark(), WNBA_COLORS,
#     viz_stop_no_data(), render_animated_artifact())
#   - sources tools/viz_gallery_helpers.R (viz_repo_root(), viz_cache_dir(),
#     viz_render_frames())
#   - renders dual artifacts via viz_render_frames(): gif_forecast_calibration.gif
#     and gif_forecast_calibration.png (reduced-motion static final frame),
#     written to cache/ and (when web/public/media exists) mirrored there too.
#
# Zero-fallback contract (issue #140/#144/#145, overriding CLAUDE.md's general
# "fall back to a clearly labeled synthetic value" house rule for this chart
# family specifically): if the real prediction log is unavailable, has no
# genuine (non-synthetic) RESOLVED rows, or has too few of them to form even
# one calibration bin, this script stops via viz_stop_no_data() with nothing
# rendered. It never invents a prediction, an outcome, or a calibration point.
#
# "Genuine pre-game forecasts only" -- exact definition, read from
# prediction_accuracy_logger.R's own comments (docs/PREDICTION_LOGGING_PLAN.md
# is not present in this worktree/checkout; the source file's inline findings
# are the authoritative definition actually implemented):
#   - status == "RESOLVED": the row has a real actual_winner/correct outcome
#     (PENDING rows have no outcome yet; UNRESOLVABLE rows -- FINDING M-5 --
#     are PENDING rows that aged out against a synthetic fixture slate and
#     can never resolve against a real box score).
#   - !is_synthetic: FINDING C-3's provenance flag. TRUE for diagnostic
#     fixtures (tools/generate_diagnostic_data.R, game_id starting "DIAG_")
#     and for predictions priced off a SYNTHETIC_FALLBACK odds slate (FINDING
#     M-5); FALSE for everything else, i.e. a real game priced against a real
#     odds slate. This is the EXACT filter summarize_prediction_accuracy()
#     itself uses by default (include_synthetic = FALSE) to keep fabricated
#     rows out of any reported accuracy number -- re-used here rather than a
#     second, possibly-inconsistent re-derivation.
#   - predicted_home_win_prob logged BEFORE the game resolves by construction:
#     log_todays_predictions() only ever writes PENDING rows with
#     prediction_timestamp = Sys.time() at log time, same day as the
#     market_odds_engine.R slate that priced the game (see that function's own
#     header comment); a row only transitions to RESOLVED afterward, inside
#     reconcile_predictions(), once a completed game's box score lands. There
#     is no code path that logs a prediction after the fact, so RESOLVED rows
#     passing the two filters above are pre-game forecasts by construction --
#     no extra timestamp-vs-tipoff comparison is needed or possible with the
#     columns this log actually carries.
#
# Data inputs:
#   - prediction_accuracy_logger.R's get_prediction_log() (cache/
#     prediction_accuracy_log.rds via config.R's CACHE_DIR). cache/ is
#     git-ignored, so a fresh git worktree has none of its own --
#     find_prediction_log_cache() below mirrors tools/gif_net_rating_quadrant.R's
#     find_team_box_cache() ancestor-climbing search for this exact problem
#     (overridable via the WNBA_VIZ_CACHE_DIR env var, the same override
#     viz_gallery_helpers.R::viz_cache_dir() already documents), then PRED_LOG_RDS
#     is pointed at that real file before get_prediction_log() is called, so
#     the function reads the SAME real log a normal checkout would, not a
#     substitute.
#
# Usage:
#   Rscript tools/gif_forecast_calibration.R
# ==============================================================================

# Known environment quirk on this machine (see tools/gif_elo_rank_bump.R /
# tools/gif_net_rating_quadrant.R): this worktree's renv project library is
# missing packages this script needs (dplyr/tidyr/ggplot2/gifski/tidyverse),
# while a complete, working set is installed in the ordinary user library.
# Prepend it so library() calls below resolve there too, without disabling
# renv outright.
.user_lib <- "C:/Users/kailo/AppData/Local/R/win-library/4.5"
if (dir.exists(.user_lib)) .libPaths(c(.user_lib, .libPaths()))

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_forecast_calibration.R"

# ------------------------------------------------------------------------------
# 0. Resolve repo root and source shared plumbing. Per CLAUDE.md, tools/
#    scripts setwd() to the absolute project root before source()-ing
#    siblings by bare filename.
# ------------------------------------------------------------------------------
.args  <- commandArgs(trailingOnly = FALSE)
.fpath <- sub("^--file=", "", .args[grepl("^--file=", .args)])
SCRIPT_DIR <- if (length(.fpath) == 1L) {
  dirname(normalizePath(.fpath, winslash = "/", mustWork = FALSE))
} else {
  file.path(getwd(), "tools")
}
PROJECT_ROOT <- normalizePath(file.path(SCRIPT_DIR, ".."), winslash = "/", mustWork = FALSE)
if (dir.exists(PROJECT_ROOT)) setwd(PROJECT_ROOT)

source("config.R")
source("logging_utils.R")
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

# prediction_accuracy_logger.R has a `sys.nframe() == 0` auto-run guard at its
# own tail (reconcile_predictions(); log_todays_predictions()) that only fires
# when the file is Rscript'd directly -- source()-ing it here (nframe > 0)
# does NOT trigger either call, per that file's own DEVIATION #3 comment
# (verified empirically there). This is the same safe-to-source pattern
# tools/gif_net_rating_quadrant.R relies on for playoff_simulator.R.
source("prediction_accuracy_logger.R")

VIZ_ROOT      <- viz_repo_root()
VIZ_CACHE_DIR <- viz_cache_dir(VIZ_ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real prediction log. cache/ is git-ignored, so a fresh
#    worktree has no copy of its own -- climb ancestor directories looking for
#    one that does, mirroring tools/gif_net_rating_quadrant.R's
#    find_team_box_cache() exactly (same idea, same search order, no
#    synthetic fallback). WNBA_VIZ_CACHE_DIR is checked first since that is
#    the override viz_cache_dir() (sourced above) already honors for this
#    worktree's cache/ redirection.
# ------------------------------------------------------------------------------
find_prediction_log_cache <- function() {
  env_dir <- Sys.getenv("WNBA_VIZ_CACHE_DIR", "")
  candidates <- c(
    if (nzchar(env_dir)) file.path(env_dir, "prediction_accuracy_log.rds") else NA_character_,
    PRED_LOG_RDS
  )
  anc <- PROJECT_ROOT
  for (i in 1:4) {
    anc <- dirname(anc)
    candidates <- c(candidates, file.path(anc, "cache", "prediction_accuracy_log.rds"))
  }
  candidates <- candidates[!is.na(candidates)]
  for (cand in candidates) {
    if (file.exists(cand)) return(normalizePath(cand, winslash = "/"))
  }
  NULL
}

pred_log_file <- find_prediction_log_cache()
if (is.null(pred_log_file)) {
  viz_stop_no_data(SCRIPT_NAME, "prediction_accuracy_log.rds (prediction_accuracy_logger.R's PRED_LOG_RDS) is missing.")
}

# Point the real accessor at the file we actually found. get_prediction_log()
# reads the global PRED_LOG_RDS at call time (it is defined in the same
# environment this script source()s into), so reassigning it here is enough
# -- no re-implementation of get_prediction_log()'s own read/migrate logic.
PRED_LOG_RDS <- pred_log_file

# ------------------------------------------------------------------------------
# 2. Load and filter to genuine pre-game forecasts only (see header comment).
# ------------------------------------------------------------------------------
pred_log <- get_prediction_log()

if (is.null(pred_log) || nrow(pred_log) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("%s contains zero rows.", basename(pred_log_file)))
}

required_cols <- c("status", "is_synthetic", "predicted_home_win_prob", "correct", "game_date")
missing_cols <- setdiff(required_cols, names(pred_log))
if (length(missing_cols) > 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s is missing expected column(s): %s.", basename(pred_log_file), paste(missing_cols, collapse = ", ")))
}

genuine <- pred_log %>%
  filter(status == "RESOLVED") %>%
  filter(!coalesce(is_synthetic, FALSE)) %>%
  filter(!is.na(predicted_home_win_prob), !is.na(correct), !is.na(game_date)) %>%
  mutate(
    game_day = as.Date(game_date),
    # Probability the model assigned to whichever side it actually picked
    # (predicted_winner) -- always >= 0.5 by construction, since
    # log_todays_predictions() derives predicted_winner from whichever side
    # predicted_home_win_prob favors.
    p_pred   = pmax(predicted_home_win_prob, 1 - predicted_home_win_prob),
    outcome  = as.numeric(correct)
  )

if (nrow(genuine) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s has 0 genuine (non-synthetic, RESOLVED) pre-game predictions -- every row is either PENDING/UNRESOLVABLE or is_synthetic == TRUE.",
    basename(pred_log_file)))
}

# A reliability diagram needs at least a couple of bins with at least a
# couple of points each to say anything; below that threshold there is no
# real calibration curve to show, only noise dressed up as one.
MIN_GENUINE_ROWS <- 6L
if (nrow(genuine) < MIN_GENUINE_ROWS) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "only %d genuine (non-synthetic, RESOLVED) pre-game prediction(s) are available in %s -- fewer than the minimum of %d needed to form even two calibration bins.",
    nrow(genuine), basename(pred_log_file), MIN_GENUINE_ROWS))
}

# ------------------------------------------------------------------------------
# 3. Weekly cumulative frames, one real calendar week of additional resolved
#    genuine predictions per frame -- same weekly-bucket cadence
#    tools/gif_elo_rank_bump.R / tools/gif_net_rating_quadrant.R use, so this
#    chart animates on a cadence consistent with the rest of the gallery.
#    Deciles (or fewer, scaled to sample size): quantile bins via
#    dplyr::ntile() rather than fixed-width cuts, so every bin in every frame
#    has a genuine, non-empty sample instead of some deciles landing empty
#    just because real forecasts cluster near 0.6-0.8.
# ------------------------------------------------------------------------------
genuine <- genuine %>% arrange(game_day)
first_date <- min(genuine$game_day)
genuine$week_bucket <- as.integer(difftime(genuine$game_day, first_date, units = "days")) %/% 7L

n_calibration_bins <- function(n) {
  # 10 (deciles) is the target per the brief ("bin ... into deciles (or
  # similar)"), but deciles of a 6-row sample would be six single-point
  # "bins" with nothing to average -- scale down so every bin can hold at
  # least ~3 genuine predictions, never below 2 bins (a single bin cannot
  # show a reliability curve, only one point) or above 10.
  max(2L, min(10L, n %/% 3L))
}

weeks <- sort(unique(genuine$week_bucket))
frames_data <- list()
fidx <- 0L
for (wk in weeks) {
  cum <- genuine %>% filter(week_bucket <= wk)
  if (nrow(cum) < MIN_GENUINE_ROWS) next  # too few resolved genuine rows yet this early
  nb <- n_calibration_bins(nrow(cum))
  cum$bin <- dplyr::ntile(cum$p_pred, nb)
  binned <- cum %>%
    group_by(bin) %>%
    summarize(
      mean_pred = mean(p_pred),
      win_rate  = mean(outcome),
      n         = n(),
      .groups = "drop"
    )
  fidx <- fidx + 1L
  frames_data[[fidx]] <- list(
    step       = fidx,
    week_label = format(max(cum$game_day), "%b %d, %Y"),
    n_total    = nrow(cum),
    n_bins     = nb,
    binned     = binned
  )
}

if (length(frames_data) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "no weekly cumulative snapshot of %s ever reached the minimum of %d genuine resolved predictions needed for a calibration bin.",
    basename(pred_log_file), MIN_GENUINE_ROWS))
}

# ------------------------------------------------------------------------------
# 4. Build one ggplot per animation frame.
# ------------------------------------------------------------------------------
plots <- vector("list", length(frames_data))
for (i in seq_along(frames_data)) {
  fd <- frames_data[[i]]
  binned <- fd$binned

  plots[[i]] <- ggplot(binned, aes(x = mean_pred, y = win_rate)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed",
                color = WNBA_COLORS$subtext, linewidth = 0.7) +
    geom_line(color = WNBA_COLORS$accent, linewidth = 0.8, alpha = 0.85) +
    geom_point(aes(size = n), color = WNBA_COLORS$accent, alpha = 0.9) +
    geom_text(aes(label = n), color = WNBA_COLORS$bg, size = 2.6, fontface = "bold") +
    scale_x_continuous(limits = c(0.45, 1.0), labels = scales::percent_format(accuracy = 1)) +
    scale_y_continuous(limits = c(0, 1.0), labels = scales::percent_format(accuracy = 1)) +
    scale_size_continuous(range = c(6, 16), guide = "none") +
    theme_wnba_dark() +
    labs(
      title = "WNBA Forecast Calibration: Predicted vs. Actual Win Rate",
      subtitle = sprintf(
        "%d genuine pre-game forecast(s) through %s, grouped into %d probability bin(s) -- dashed line = perfect calibration",
        fd$n_total, fd$week_label, fd$n_bins
      ),
      x = "Mean Predicted Win Probability (Binned)",
      y = "Actual Win Rate",
      caption = "Genuine, non-synthetic RESOLVED predictions only (prediction_accuracy_logger.R::get_prediction_log()). Point labels = predictions per bin."
    )
}

# ------------------------------------------------------------------------------
# 5. Encode animated artifact (GIF + reduced-motion PNG)
# ------------------------------------------------------------------------------
viz_render_frames(
  plots      = plots,
  name       = "gif_forecast_calibration",
  root       = VIZ_ROOT,
  cache_dir  = VIZ_CACHE_DIR,
  fps        = 2,
  hold_last_frames = 6,
  width      = 1000,
  height     = 700
)
