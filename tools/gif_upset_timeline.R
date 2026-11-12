# ==============================================================================
# tools/gif_upset_timeline.R
# Path: tools/gif_upset_timeline.R
#
# WNBA Underdog Upset Timeline & Victory Tracker Animation. Gallery chart #9
# of GitHub issue kailot-harris/front-office#145 (part of #140's "gallery
# phase 2" batch), built on #144's phase-1 shared viz plumbing
# (tools/viz_common.R / tools/viz_gallery_helpers.R).
#
# NBA counterpart: ../NBA Analytics/tools/gif_upset_timeline.R. That script
# re-derives its own preseason Elo prior and re-runs a local Elo update loop
# over matchups_team_box_2027.rds/ensemble_team_ratings.rds to manufacture a
# pre-game win probability per game. This WNBA script does NOT do that --
# per #145's brief, "upset" here means ONLY a game where the model's own
# GENUINE pre-game forecast (logged by prediction_accuracy_logger.R BEFORE
# the game, via log_todays_predictions()) had the eventual winner as the
# lower-probability team. Re-deriving a parallel Elo estimate here would (a)
# duplicate rating logic this repo already centralizes elsewhere
# (roster_bottom_up_engine.R / playoff_simulator.R's get_playoff_adjusted_
# rating()) and (b) silently diverge from the model's actual priced
# probability for games where the two disagree -- exactly the kind of
# invented-data path issue #140/#144's zero-fallback contract forbids for
# this chart family. So this script is a pure CONSUMER of the real
# prediction log: it never computes a probability of its own.
#
# "Genuine pre-game forecast" filter (see prediction_accuracy_logger.R's own
# schema/migration comments and docs/PREDICTION_LOGGING_PLAN.md's phased
# plan for the authoritative definitions this mirrors):
#   - status == "RESOLVED"            -- excludes PENDING/UNRESOLVABLE rows,
#                                         which have no actual_winner to
#                                         compare the forecast against.
#   - is_synthetic == FALSE            -- excludes migrate_prediction_log()'s
#                                         backfilled DIAG_*/DIAGNOSTIC/
#                                         WNBA_GAME_N fixture rows (FINDING
#                                         C-3), which were never real
#                                         pre-game forecasts.
#   - predicted_home_win_prob and actual_winner both non-NA -- a NA here
#     means the row was logged against a degraded slate (see the 2026-09-19
#     "completeness_fields" finding in prediction_accuracy_logger.R) and
#     cannot support a genuine probability comparison.
#   - as.Date(prediction_timestamp) <= game_date -- log_todays_predictions()
#     stamps prediction_timestamp with Sys.time() at the moment the SAME-DAY
#     slate is logged (see that function's `now_ts <- Sys.time()`), so a
#     genuine pre-game row's timestamp date can never be AFTER its own
#     game_date. Empirically verified against the real cache on this
#     machine: every RESOLVED, non-synthetic row's (timestamp date - game_
#     date) is <= 0 (range -6..0 days). This guards against any future
#     backfill path that logs a prediction retroactively after a game result
#     is already known, which would not be a genuine forecast even if
#     is_synthetic were FALSE.
# An "upset" is then any genuine row where the ACTUAL winner's own forecast
# win probability was < 0.50 -- i.e. the model's own pre-game numbers made
# the eventual winner the underdog. No separate hardcoded probability/Elo-
# diff threshold is invented here (unlike the NBA script's winner_prob <=
# 0.43 constant) -- "lower-probability team won" is exactly winner_prob < 0.5.
#
# Foundation & theme:
#   - sources tools/viz_common.R (theme_wnba_dark(), WNBA_TEAM_COLORS,
#     get_wnba_team_color(), viz_logo_map(), viz_stop_no_data(),
#     render_animated_artifact())
#   - sources tools/viz_gallery_helpers.R (viz_repo_root(), viz_cache_dir(),
#     viz_render_frames())
#   - renders dual artifacts via viz_render_frames(): gif_upset_timeline.gif
#     and gif_upset_timeline.png (reduced-motion static final frame), written
#     to cache/ and (when web/public/media exists) mirrored there too.
#
# Zero-fallback contract (issue #140/#144, overriding CLAUDE.md's general
# "fall back to a clearly labeled synthetic value" house rule for this chart
# family specifically): if the real prediction log is unavailable, or has no
# genuine resolved pre-game rows, or those genuine rows contain zero real
# upsets, this script stops via viz_stop_no_data() with nothing rendered. It
# never invents a prediction, a game result, or an upset.
#
# Data inputs:
#   - prediction_accuracy_logger.R's prediction log cache (config.R's
#     PRED_LOG_RDS, cache/prediction_accuracy_log.rds) -- reused via that
#     file's own migrate_prediction_log() so schema migration logic is not
#     duplicated here. cache/ is git-ignored, so a fresh git worktree has no
#     local copy -- find_prediction_log_cache() below climbs to an ancestor
#     checkout that does, mirroring the WNBA_VIZ_CACHE_DIR convention
#     viz_gallery_helpers.R::viz_cache_dir() already documents for cache/.
#     This locates the SAME real file, never a substitute, and is
#     overridable via the WNBA_VIZ_CACHE_DIR env var.
#
# Usage:
#   Rscript tools/gif_upset_timeline.R
# ==============================================================================

# Known environment quirk on this machine: the active R installation's renv
# project library (both this worktree's and the main checkout's) is missing
# packages this script needs (dplyr/ggplot2/gifski/ggimage), while a complete,
# working set is installed in the ordinary user library. Prepend it so
# library() calls below resolve there too, without disabling renv outright.
.user_lib <- "C:/Users/kailo/AppData/Local/R/win-library/4.5"
if (dir.exists(.user_lib)) .libPaths(c(.user_lib, .libPaths()))

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_upset_timeline.R"

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
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

# Reused for its migrate_prediction_log() -- the canonical, already-reviewed
# genuine/synthetic classification + schema-migration logic (FINDING C-3 and
# the later WNBA_GAME_5/6 reconciliation). This file's own top-level lines
# (PROJECT_DIR <- here::here(); setwd(); re-source config.R/logging_utils.R)
# are idempotent no-ops here since we have already setwd()'d to the same
# root -- it never auto-runs log_todays_predictions()/reconcile_predictions()
# on source (see its own header DEVIATION #3: both are guarded behind a
# sys.nframe() == 0 check that is never true under source()).
source("prediction_accuracy_logger.R")

VIZ_ROOT       <- viz_repo_root()
VIZ_CACHE_DIR  <- viz_cache_dir(VIZ_ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real prediction log cache (see header comment above).
# ------------------------------------------------------------------------------
find_prediction_log_cache <- function() {
  env_dir <- Sys.getenv("WNBA_VIZ_CACHE_DIR", "")
  candidates <- c(
    if (nzchar(env_dir)) file.path(env_dir, "prediction_accuracy_log.rds") else NA_character_,
    file.path(VIZ_CACHE_DIR, "prediction_accuracy_log.rds"),
    if (exists("PRED_LOG_RDS")) PRED_LOG_RDS else NA_character_
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
  viz_stop_no_data(SCRIPT_NAME, "prediction_accuracy_log.rds (config.R's prediction log cache, written by prediction_accuracy_logger.R) is missing.")
}

raw_log <- tryCatch(readRDS(pred_log_file), error = function(e) NULL)
if (is.null(raw_log) || !is.data.frame(raw_log) || nrow(raw_log) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("%s exists but contains no rows.", basename(pred_log_file)))
}

# Reuse the canonical migration logic (idempotent, persist = FALSE so this
# read-only gallery chart never writes back to the production log).
pred_log <- migrate_prediction_log(raw_log, persist = FALSE)

# ------------------------------------------------------------------------------
# 2. Filter to GENUINE pre-game forecasts only (see header comment for the
#    exact definition this mirrors) and flag real upsets.
# ------------------------------------------------------------------------------
genuine <- pred_log |>
  filter(
    !is.na(status), status == "RESOLVED",
    !is.na(is_synthetic), is_synthetic == FALSE,
    !is.na(predicted_home_win_prob), !is.na(actual_winner),
    !is.na(home_team), !is.na(away_team),
    home_team %in% names(WNBA_TEAMS), away_team %in% names(WNBA_TEAMS),
    !is.na(prediction_timestamp), !is.na(game_date),
    as.Date(prediction_timestamp) <= as.Date(game_date)
  ) |>
  mutate(
    game_date   = as.Date(game_date),
    winner_prob = if_else(actual_winner == home_team, predicted_home_win_prob, 1 - predicted_home_win_prob),
    loser       = if_else(actual_winner == home_team, away_team, home_team),
    is_upset    = winner_prob < 0.5,
    upset_leverage = round((0.5 - winner_prob) * 100, 1)
  ) |>
  arrange(game_date, game_id)

if (nrow(genuine) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s has no RESOLVED, non-synthetic, pre-game-timestamped prediction rows.",
    basename(pred_log_file)
  ))
}

all_upsets <- genuine |> filter(is_upset)
if (nrow(all_upsets) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%d genuine pre-game forecast(s) were found in %s, but none were upsets (lower-probability team never won).",
    nrow(genuine), basename(pred_log_file)
  ))
}

all_teams <- sort(names(WNBA_TEAMS))
dates <- sort(unique(genuine$game_date))

# ------------------------------------------------------------------------------
# 3. Cumulative upset trajectory across real game dates.
# ------------------------------------------------------------------------------
running_upsets <- setNames(rep(0L, length(all_teams)), all_teams)
timeline_history <- list()
timeline_history[[1]] <- tibble(
  step = 0L, date_label = "Season Start", team = all_teams,
  cum_upsets = 0L, recent_highlight = "Season Start"
)

for (idx in seq_along(dates)) {
  d <- dates[idx]
  d_upsets <- all_upsets |> filter(game_date == d)

  if (nrow(d_upsets) > 0) {
    for (u in seq_len(nrow(d_upsets))) {
      w <- d_upsets$actual_winner[u]
      running_upsets[w] <- running_upsets[w] + 1L
    }
    top_u <- d_upsets |> arrange(winner_prob) |> slice(1)
    highlight_str <- sprintf(
      "Upset: %s def. %s (%.1f%% pre-game win prob)",
      top_u$actual_winner, top_u$loser, top_u$winner_prob * 100
    )
  } else {
    highlight_str <- "No model-flagged upsets on slate"
  }

  timeline_history[[idx + 1]] <- tibble(
    step = as.integer(idx),
    date_label = format(d, "%b %d"),
    team = all_teams,
    cum_upsets = as.integer(running_upsets[all_teams]),
    recent_highlight = highlight_str
  )
}

timeline_df   <- bind_rows(timeline_history)
active_steps  <- sort(unique(timeline_df$step))

team_colors <- setNames(
  vapply(all_teams, function(tm) get_wnba_team_color(tm, "primary"), FUN.VALUE = character(1)),
  all_teams
)

TEAM_LOGOS <- viz_logo_map(script = SCRIPT_NAME)

# ------------------------------------------------------------------------------
# 4. Render animation frames (horizontal bar race) and encode GIF + PNG via
#    the shared gallery helper (writes into cache/ and, when it exists,
#    web/public/media/).
# ------------------------------------------------------------------------------
max_upsets_val <- max(timeline_df$cum_upsets)
x_max_limit    <- max(max_upsets_val + 1.5, 4.0)

plots <- list()
for (s in active_steps) {
  cur_step_data <- timeline_df |> filter(step == s)
  cur_label     <- cur_step_data$date_label[1]
  cur_highlight <- cur_step_data$recent_highlight[1]

  top_teams <- cur_step_data |>
    arrange(desc(cum_upsets), team) |>
    slice(1:length(all_teams)) |>
    mutate(
      bar_order = row_number(),
      label_str = sprintf("%d upset%s", cum_upsets, ifelse(cum_upsets == 1, "", "s"))
    )

  p_frame <- ggplot(top_teams, aes(x = cum_upsets, y = reorder(team, -bar_order), fill = team)) +
    geom_col(width = 0.72, alpha = 0.9, color = WNBA_COLORS$border) +
    ggimage::geom_image(aes(x = -0.035 * x_max_limit, image = TEAM_LOGOS[team]), size = 0.045, by = "height") +
    geom_text(
      aes(x = cum_upsets + 0.1, label = label_str),
      color = WNBA_COLORS$text, hjust = 0, size = 2.9, fontface = "bold"
    ) +
    scale_x_continuous(limits = c(-0.07 * x_max_limit, x_max_limit), breaks = 0:floor(x_max_limit)) +
    scale_fill_manual(values = team_colors, guide = "none") +
    theme_wnba_dark(base_size = 10) +
    theme(
      axis.text.y = element_blank(), axis.ticks.y = element_blank(),
      panel.grid.major.y = element_blank()
    ) +
    labs(
      title    = "WNBA Underdog Upset Tracker & Giant-Killer Timeline",
      subtitle = sprintf("Through %s \u2014 %s", cur_label, cur_highlight),
      x = "Genuine Pre-Game Upset Wins (model forecast win probability < 50%)",
      y = NULL,
      caption = "Model's own logged pre-game forecasts only (prediction_accuracy_logger.R); synthetic/backfilled rows excluded"
    )

  plots[[length(plots) + 1]] <- p_frame
}

viz_render_frames(
  plots      = plots,
  name       = "gif_upset_timeline",
  root       = VIZ_ROOT,
  cache_dir  = VIZ_CACHE_DIR,
  fps        = 2,
  hold_last_frames = 5,
  width      = 1000,
  height     = 700
)
