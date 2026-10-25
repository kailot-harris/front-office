# ==============================================================================
# research_bpm_recalibration.R
# Path: tools/research_bpm_recalibration.R
#
# Empirical recalibration of calculate_bpm_components()'s per-stat weights
# (player_metrics.R), which have carried an NBA-hand-tuned TODO(recalibrate) since
# Phase 0: "the -2.0 replacement-level anchor (and the per-stat weights below) were
# hand-tuned against NBA per-36 distributions in the original repo ... re-derive this
# anchor (and ideally the weights) from the actual WNBA per-36 stat distribution."
#
# CIRCULARITY TRAP (same discipline as research_team_depth_regression.R, which this
# script mirrors structurally): a team-game's own box stats mechanically determine
# that same game's own margin (margin = team_score - opponent_team_score, and
# team_score IS the box score's points total) -- regressing SAME-GAME margin on
# SAME-GAME box categories would make the "points" weight trivially ~1.0 and everything
# else noise. This script NEVER does that regression. Instead it builds TRAILING
# (strictly-prior-games-only) rolling averages of each raw box category per team and
# regresses those against the team's CURRENT game margin, controlling for the team's
# own trailing-average margin (recent-form baseline) -- exactly
# research_team_depth_regression.R's established pattern, applied here to the 9
# individual box categories inside calculate_bpm_components() instead of to the single
# composite team_top5_bpm signal.
#
# Why team-level (not player-level) regression: calculate_bpm_components()'s per-stat
# weight for a stat (e.g. 0.60 for points) represents "how many margin points one unit
# of that stat is worth" -- a linear coefficient that is identical whether estimated
# from team-total stats or from summing player-level contributions (since
# team_total_stat = sum_players(player_stat), and margin = weight * team_total_stat +
# ... under an additive linear model, so weight is estimable directly from team-level
# aggregates without needing a player-level panel). The existing formula's per-36-minute
# scaling and -2.0 replacement-level anchor are separate, playing-time-normalization
# mechanics applied AFTER the weight is chosen -- untouched by this recalibration of the
# weight VALUES themselves. The anchor is re-derived separately in Section 6 below,
# from the real distribution of qualified players' weighted-sum-before-anchor, per the
# TODO's own "(and ideally the weights)" framing (anchor first, weights second, in that
# comment's parenthetical -- both addressed here).
# ==============================================================================

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
      stop(sprintf("research_bpm_recalibration.R: cannot locate the repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)
source("config.R")
source("player_metrics.R")  # normalize_team_abbreviation()/filter_real_franchises() defs only
suppressPackageStartupMessages(library(dplyr))

out_dir <- file.path("tools", "research_output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

# ------------------------------------------------------------------------------
# SECTION 1: load + verify CACHE_TEAM_BOX is already exhibition-filtered
# ------------------------------------------------------------------------------
message("=== SECTION 1: load + verify CACHE_TEAM_BOX ===")
team_box <- readRDS(CACHE_TEAM_BOX) |> normalize_team_abbreviation()
non_franchise <- team_box |> filter(!team_abbreviation %in% names(WNBA_TEAMS))
message(sprintf("CACHE_TEAM_BOX: %d rows. Non-franchise rows after normalize: %d (expect 0 -- daily_ingest.R already filters at ingest).",
                 nrow(team_box), nrow(non_franchise)))
stopifnot(nrow(non_franchise) == 0)

# ------------------------------------------------------------------------------
# SECTION 2: team-game panel of raw box categories (same 9 categories as
# calculate_bpm_components()'s weighted sum) + real margin
# ------------------------------------------------------------------------------
message("\n=== SECTION 2: team-game panel construction ===")

team_game <- team_box |>
  transmute(
    game_id            = as.character(game_id),
    team_id            = as.integer(team_id),
    team_abbreviation,
    season,
    game_date,
    margin             = team_score - opponent_team_score,
    points             = team_score,
    rebounds           = total_rebounds,
    assists            = assists,
    steals             = steals,
    blocks             = blocks,
    turnovers          = total_turnovers,  # L-3 convention: total_turnovers, not turnovers -- see ml_cv_benchmark.R
    missed_fg          = field_goals_attempted - field_goals_made,
    missed_ft          = free_throws_attempted - free_throws_made,
    made_3pm           = three_point_field_goals_made
  )

message(sprintf("Team-game panel: %d rows, %d distinct teams, seasons %d-%d.",
                 nrow(team_game), length(unique(team_game$team_id)), min(team_game$season), max(team_game$season)))
saveRDS(team_game, file.path(out_dir, "bpm_recal_panel_raw.rds"))

# ------------------------------------------------------------------------------
# SECTION 3: trailing (strictly-prior-games) rolling averages per team
# ------------------------------------------------------------------------------
message("\n=== SECTION 3: trailing rolling averages ===")
message(sprintf("ROLLING_WINDOW_SIZE = %d (config.R), MIN_TRAILING_GAMES = 5 (same precedent as research_team_depth_regression.R / research_shot_mix_regression.R).",
                 ROLLING_WINDOW_SIZE))
MIN_TRAILING_GAMES <- 5

trailing_avg <- function(x, window) {
  n <- length(x)
  out <- rep(NA_real_, n)
  for (i in seq_len(n)) {
    lo <- max(1, i - window)
    hi <- i - 1
    if (hi >= lo) out[i] <- mean(x[lo:hi], na.rm = TRUE)
  }
  out
}

panel <- team_game |>
  arrange(team_id, game_date) |>
  group_by(team_id) |>
  mutate(
    n_prior_games        = pmin(row_number() - 1, ROLLING_WINDOW_SIZE),
    t_margin             = trailing_avg(margin, ROLLING_WINDOW_SIZE),
    t_points             = trailing_avg(points, ROLLING_WINDOW_SIZE),
    t_rebounds           = trailing_avg(rebounds, ROLLING_WINDOW_SIZE),
    t_assists            = trailing_avg(assists, ROLLING_WINDOW_SIZE),
    t_steals             = trailing_avg(steals, ROLLING_WINDOW_SIZE),
    t_blocks             = trailing_avg(blocks, ROLLING_WINDOW_SIZE),
    t_turnovers          = trailing_avg(turnovers, ROLLING_WINDOW_SIZE),
    t_missed_fg          = trailing_avg(missed_fg, ROLLING_WINDOW_SIZE),
    t_missed_ft          = trailing_avg(missed_ft, ROLLING_WINDOW_SIZE),
    t_made_3pm           = trailing_avg(made_3pm, ROLLING_WINDOW_SIZE)
  ) |>
  ungroup() |>
  filter(n_prior_games >= MIN_TRAILING_GAMES,
         if_all(starts_with("t_"), is.finite))

message(sprintf("Qualifying panel (>= %d trailing games/team): %d team-games across %d distinct teams.",
                 MIN_TRAILING_GAMES, nrow(panel), length(unique(panel$team_id))))
saveRDS(panel, file.path(out_dir, "bpm_recal_panel_trailing.rds"))

# ------------------------------------------------------------------------------
# SECTION 4: within-team fixed-effects regression (demeaned)
# margin ~ trailing_avg_margin + 9 trailing box-category averages
# ------------------------------------------------------------------------------
message("\n=== SECTION 4: within-team FE regression ===")

panel_de <- panel |>
  group_by(team_id) |>
  mutate(across(c(margin, starts_with("t_")), ~ . - mean(., na.rm = TRUE), .names = "{.col}_dm")) |>
  ungroup()

fml <- margin_dm ~ t_margin_dm + t_points_dm + t_rebounds_dm + t_assists_dm + t_steals_dm +
  t_blocks_dm + t_turnovers_dm + t_missed_fg_dm + t_missed_ft_dm + t_made_3pm_dm
m_full <- lm(fml, data = panel_de)
print(summary(m_full))

message("\n--- Explicit factor(team_id) FE sanity check (confirms demeaning shortcut is unbiased) ---")
fml_fe <- margin ~ t_margin + t_points + t_rebounds + t_assists + t_steals + t_blocks +
  t_turnovers + t_missed_fg + t_missed_ft + t_made_3pm + factor(team_id)
m_fe <- lm(fml_fe, data = panel)
keep_rows <- c("(Intercept)", "t_margin", "t_points", "t_rebounds", "t_assists", "t_steals",
               "t_blocks", "t_turnovers", "t_missed_fg", "t_missed_ft", "t_made_3pm")
print(summary(m_fe)$coefficients[keep_rows, , drop = FALSE])

# ------------------------------------------------------------------------------
# SECTION 5: collinearity check (VIF, no `car` dependency)
# ------------------------------------------------------------------------------
message("\n=== SECTION 5: collinearity check ===")
vif_of <- function(target, others_df) {
  aux <- lm(target ~ ., data = others_df)
  1 / (1 - summary(aux)$r.squared)
}
regressors <- panel_de |>
  select(t_margin_dm, t_points_dm, t_rebounds_dm, t_assists_dm, t_steals_dm,
         t_blocks_dm, t_turnovers_dm, t_missed_fg_dm, t_missed_ft_dm, t_made_3pm_dm)
vifs <- sapply(names(regressors), function(nm) vif_of(regressors[[nm]], regressors[, setdiff(names(regressors), nm)]))
print(round(vifs, 3))
message("Rule of thumb applied: VIF > 5 flags severe collinearity (points/missed_fg/made_3pm are the most likely candidates since they jointly determine team_score).")

# ------------------------------------------------------------------------------
# SECTION 6: derive new weights + replacement-level anchor
# ------------------------------------------------------------------------------
message("\n=== SECTION 6: new weights (from m_full, significant terms only) + replacement-level anchor ===")

coefs <- summary(m_full)$coefficients
term_map <- c(
  t_points_dm    = "points",
  t_rebounds_dm  = "rebounds",
  t_assists_dm   = "assists",
  t_steals_dm    = "steals",
  t_blocks_dm    = "blocks",
  t_turnovers_dm = "turnovers",
  t_missed_fg_dm = "missed_fg",
  t_missed_ft_dm = "missed_ft",
  t_made_3pm_dm  = "made_3pm"
)
old_weights <- c(points = 0.60, rebounds = 0.70, assists = 1.05, steals = 1.40, blocks = 1.15,
                  turnovers = -1.20, missed_fg = -0.45, missed_ft = -0.35, made_3pm = 0.30)

new_weights <- old_weights
for (term in names(term_map)) {
  stat <- term_map[[term]]
  est <- coefs[term, "Estimate"]
  p   <- coefs[term, "Pr(>|t|)"]
  sig <- p < 0.05
  message(sprintf("%-10s: old=%+.3f  new_estimate=%+.4f  p=%.4g  %s",
                   stat, old_weights[[stat]], est, p,
                   if (sig) "SIGNIFICANT -> use new estimate" else "NOT significant -> KEEP OLD (insufficient evidence to move it)"))
  if (sig) new_weights[[stat]] <- unname(est)
}

message("\nFinal recalibrated weight vector:")
print(round(new_weights, 4))
message("\nSign-consistency check against theory (turnovers/missed_fg/missed_ft should be negative, everything else positive):")
expect_negative <- c("turnovers", "missed_fg", "missed_ft")
for (stat in names(new_weights)) {
  should_be_neg <- stat %in% expect_negative
  is_neg <- new_weights[[stat]] < 0
  ok <- should_be_neg == is_neg
  message(sprintf("  %-10s: %+.4f -- %s", stat, new_weights[[stat]], if (ok) "OK" else "SIGN FLIP vs theory (flagged, not auto-corrected)"))
}

# Replacement-level anchor: recompute calculate_bpm_components()'s weighted sum (pre-anchor,
# pre-per-36-scaling) using the NEW weights against real player-game rows, then set the anchor
# to the 10th percentile of the MINUTES-WEIGHTED distribution among rotation players (>= 10
# minutes, a real-rotation floor consistent with WNBA's 12-player active roster / ~8-9 man
# rotations per config.R's WNBA_ROTATION_SIZE) -- i.e. replacement level = "worse than ~90% of
# real rotation minutes," the standard BPM-family convention (a bench/10th-man baseline), applied
# here to actual WNBA per-36 data instead of carried forward from the NBA fit.
message("\n=== SECTION 6b: replacement-level anchor re-derivation ===")
player_box <- readRDS(CACHE_PLAYER_BOX) |> filter_real_franchises()
pb <- player_box |>
  mutate(
    minutes = suppressWarnings(as.numeric(minutes)),
    minutes = replace_na(minutes, 0),
    points = suppressWarnings(as.numeric(points)), points = replace_na(points, 0),
    rebounds = suppressWarnings(as.numeric(rebounds)), rebounds = replace_na(rebounds, 0),
    assists = suppressWarnings(as.numeric(assists)), assists = replace_na(assists, 0),
    steals = suppressWarnings(as.numeric(steals)), steals = replace_na(steals, 0),
    blocks = suppressWarnings(as.numeric(blocks)), blocks = replace_na(blocks, 0),
    turnovers = suppressWarnings(as.numeric(turnovers)), turnovers = replace_na(turnovers, 0),
    field_goals_made = suppressWarnings(as.numeric(field_goals_made)), field_goals_made = replace_na(field_goals_made, 0),
    field_goals_attempted = suppressWarnings(as.numeric(field_goals_attempted)), field_goals_attempted = replace_na(field_goals_attempted, 0),
    three_point_field_goals_made = suppressWarnings(as.numeric(three_point_field_goals_made)), three_point_field_goals_made = replace_na(three_point_field_goals_made, 0),
    free_throws_made = suppressWarnings(as.numeric(free_throws_made)), free_throws_made = replace_na(free_throws_made, 0),
    free_throws_attempted = suppressWarnings(as.numeric(free_throws_attempted)), free_throws_attempted = replace_na(free_throws_attempted, 0)
  ) |>
  filter(minutes >= 10) |>
  mutate(
    # turnovers/missed_fg/missed_ft weights are already signed negative in new_weights
    # (kept from old_weights or re-estimated), so every term below is a simple `+`.
    weighted_sum_per36 = (new_weights[["points"]] * points + new_weights[["rebounds"]] * rebounds +
                            new_weights[["assists"]] * assists + new_weights[["steals"]] * steals +
                            new_weights[["blocks"]] * blocks + new_weights[["turnovers"]] * turnovers +
                            new_weights[["missed_fg"]] * (field_goals_attempted - field_goals_made) +
                            new_weights[["missed_ft"]] * (free_throws_attempted - free_throws_made) +
                            new_weights[["made_3pm"]] * three_point_field_goals_made) * (36 / minutes)
  )

anchor_10pct <- as.numeric(quantile(pb$weighted_sum_per36, 0.10, na.rm = TRUE))
message(sprintf("n = %d player-games with minutes >= 10. 10th-percentile per-36 weighted sum (new replacement-level anchor) = %.4f (old hardcoded anchor = -2.0).",
                 nrow(pb), anchor_10pct))
message(sprintf("Distribution summary: mean=%.3f, median=%.3f, p25=%.3f, p75=%.3f, p90=%.3f.",
                 mean(pb$weighted_sum_per36, na.rm = TRUE), median(pb$weighted_sum_per36, na.rm = TRUE),
                 quantile(pb$weighted_sum_per36, 0.25, na.rm = TRUE), quantile(pb$weighted_sum_per36, 0.75, na.rm = TRUE),
                 quantile(pb$weighted_sum_per36, 0.90, na.rm = TRUE)))

results <- list(
  new_weights = new_weights,
  old_weights = old_weights,
  anchor_10pct = anchor_10pct,
  n_team_games = nrow(panel),
  n_teams = length(unique(panel$team_id)),
  n_player_games_anchor = nrow(pb),
  vifs = vifs,
  model_summary = summary(m_full)
)
saveRDS(results, file.path(out_dir, "bpm_recalibration_results.rds"))

message("\n=== DONE ===")
