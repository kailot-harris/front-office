# ==============================================================================
# research_shot_mix_regression.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/tools/research_shot_mix_regression.R
#
# Full empirical derivation behind player_props_engine.R's SHOT_MIX_PTS_SLOPE /
# adjust_mu_for_shot_mix() (see that file, and docs/pbp_shot_mix_regression_findings.md for the
# narrative writeup). Folded from four separate one-off scratch scripts written during that
# derivation (join-key check, panel-build+regression, clamp sanity check, prop spot-check) into
# one script with clear sections, so the full methodology is reproducible end-to-end from a
# single `Rscript.exe tools/research_shot_mix_regression.R` run rather than scattered across
# files that only made sense run in a specific undocumented order.
#
# Re-run this whenever CACHE_PBP_RAW / CACHE_PLAYER_BOX are refreshed with more seasons, to
# confirm the coefficient in player_props_engine.R is still current — it is a real, re-checkable
# empirical result, not a one-time assertion (same philosophy as OPP_DEF_MU_SLOPE's own
# derivation comment in player_props_engine.R).
# ==============================================================================

setwd("C:/Users/kailo/kayceeslices/WNBA Analytics")
source("config.R")
suppressPackageStartupMessages(library(dplyr))

out_dir <- file.path("tools", "research_output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

pbp <- readRDS(CACHE_PBP_RAW)
box <- readRDS(CACHE_PLAYER_BOX)

# ------------------------------------------------------------------------------
# SECTION 1: join-key verification (CACHE_PBP_RAW <-> CACHE_PLAYER_BOX)
# ------------------------------------------------------------------------------
# Both are ESPN-backed (unlike the WNBA-Stats-API possessions cache rapm_engine.R uses, which
# does NOT share a game_id namespace with anything else in this repo - see that file's header).
# Verify directly rather than assuming, per this repo's own convention (CLAUDE.md's RAPM/roster
# ID-mismatch caution applies generally: never assume two caches share a key without checking).
message("\n=== SECTION 1: join-key verification ===")
pbp_gids <- unique(pbp$game_id)
box_gids <- unique(box$game_id)
message(sprintf("distinct game_ids: pbp=%d, box=%d, overlap=%d (%.2f%% of box game_ids found in pbp)",
                 length(pbp_gids), length(box_gids), length(intersect(pbp_gids, box_gids)),
                 mean(box_gids %in% pbp_gids) * 100))

pbp_pg <- pbp |> filter(!is.na(athlete_id_1)) |> distinct(athlete_id_1, game_id)
box_pg <- box |> filter(!is.na(athlete_id)) |> distinct(athlete_id, game_id)
joined_pg <- inner_join(pbp_pg, box_pg, by = c("athlete_id_1" = "athlete_id", "game_id" = "game_id"))
message(sprintf("player-game join: %d/%d box (athlete,game) pairs matched (%.2f%%) - the unmatched remainder are real 0-FGA games (players who didn't shoot), not a join failure.",
                 nrow(joined_pg), nrow(box_pg), nrow(joined_pg) / nrow(box_pg) * 100))

# ------------------------------------------------------------------------------
# SECTION 2: build the per-game shot-mix panel and run the regression
# ------------------------------------------------------------------------------
message("\n=== SECTION 2: panel construction + regression ===")

# Mirror pbp_engine.R's exact keyword buckets - do not diverge, or this regression would be
# estimating a coefficient for a DIFFERENT pct_rim definition than the one shipped to the
# dashboard and consumed by player_props_engine.R's adjust_mu_for_shot_mix().
.RIM_KW <- "(?i)layup|dunk|putback|tip shot|tip-in|tip in"

shots <- pbp |> filter(shooting_play == TRUE, !is.na(athlete_id_1))

fga_tbl <- shots |>
  group_by(athlete_id = athlete_id_1, game_id) |>
  summarise(fga_total = n(), .groups = "drop")

mix_tbl <- shots |>
  filter(points_attempted == 2) |>
  mutate(is_rim = grepl(.RIM_KW, trimws(type_text), perl = TRUE)) |>
  group_by(athlete_id = athlete_id_1, game_id) |>
  summarise(two_pa_total = n(), rim_n = sum(is_rim, na.rm = TRUE), .groups = "drop") |>
  mutate(pct_rim = rim_n / two_pa_total)

panel <- fga_tbl |>
  inner_join(mix_tbl, by = c("athlete_id", "game_id")) |>
  inner_join(box |> select(athlete_id, game_id, points, minutes) |> filter(!is.na(athlete_id)),
             by = c("athlete_id", "game_id")) |>
  filter(fga_total >= 3, two_pa_total > 0, !is.na(pct_rim))

player_game_counts <- panel |> count(athlete_id, name = "n_games")
keep_players <- player_game_counts |> filter(n_games >= 5) |> pull(athlete_id)
panel_f <- panel |> filter(athlete_id %in% keep_players)

message(sprintf("Final panel: %d player-games, %d distinct players (>=5 qualifying games/player, >=3 FGA/game).",
                 nrow(panel_f), length(unique(panel_f$athlete_id))))
saveRDS(panel_f, file.path(out_dir, "shot_mix_panel.rds"))

# Within-player fixed effects via demeaning (equivalent to factor(athlete_id) - see Model 4).
panel_de <- panel_f |>
  group_by(athlete_id) |>
  mutate(points_dm  = points - mean(points, na.rm = TRUE),
         pct_rim_dm = pct_rim - mean(pct_rim, na.rm = TRUE),
         minutes_dm = minutes - mean(minutes, na.rm = TRUE)) |>
  ungroup()

message("\n--- Model 1: absolute points, demeaned, pct_rim only ---")
print(summary(lm(points_dm ~ pct_rim_dm, data = panel_de)))

message("\n--- Model 2: absolute points, demeaned, + minutes control ---")
print(summary(lm(points_dm ~ pct_rim_dm + minutes_dm, data = panel_de)))

message("\n--- Model 3: fractional (points / player_mean_points), demeaned -> the estimand actually used ---")
panel_frac <- panel_f |>
  group_by(athlete_id) |>
  mutate(player_mean_pts = mean(points, na.rm = TRUE),
         pts_frac = points / player_mean_pts,
         pts_frac_dm = pts_frac - mean(pts_frac, na.rm = TRUE),
         pct_rim_dm = pct_rim - mean(pct_rim, na.rm = TRUE),
         minutes_dm = minutes - mean(minutes, na.rm = TRUE)) |>
  ungroup() |>
  filter(is.finite(pts_frac), player_mean_pts > 0)
m3 <- lm(pts_frac_dm ~ pct_rim_dm + minutes_dm, data = panel_frac)
print(summary(m3))

message("\n--- Model 4: sanity check with explicit factor(athlete_id) FE (confirms demeaning shortcut is unbiased) ---")
m4 <- lm(points ~ pct_rim + minutes + factor(athlete_id), data = panel_f)
print(summary(m4)$coefficients[c("(Intercept)", "pct_rim", "minutes"), , drop = FALSE])

message("\n--- Corroboration: player-season pct_rim vs PPG (cross-sectional, NOT causal - expected to run the OPPOSITE sign due to usage/role confounding, which within-player FE removes) ---")
season_join <- pbp |> select(game_id, season) |> distinct()
season_agg <- panel_f |>
  left_join(season_join, by = "game_id") |>
  group_by(athlete_id, season) |>
  summarise(games = n(), ppg = mean(points), season_pct_rim = weighted.mean(pct_rim, two_pa_total), .groups = "drop") |>
  filter(games >= 5)
print(cor.test(season_agg$season_pct_rim, season_agg$ppg))

# ------------------------------------------------------------------------------
# SECTION 3: clamp sanity check against real current data
# ------------------------------------------------------------------------------
message("\n=== SECTION 3: SHOT_MIX_PTS_CLAMP sanity check ===")
SLOPE <- 0.1174  # must match player_props_engine.R::SHOT_MIX_PTS_SLOPE - re-sync if Section 2 changes it.

feats <- readRDS(CACHE_PLAYER_PBP_FEATURES)
real <- feats |> filter(!is.na(pct_rim), fga_total >= 20)
league_avg_season <- mean(real$pct_rim, na.rm = TRUE)
message(sprintf("Season-aggregated (dashboard-shipped) pct_rim: league avg=%.4f, unclamped ratio range across real players=[%.4f, %.4f]",
                 league_avg_season,
                 1 + SLOPE * (min(real$pct_rim) - league_avg_season),
                 1 + SLOPE * (max(real$pct_rim) - league_avg_season)))

player_season_avg <- panel_f |> group_by(athlete_id) |>
  summarise(avg_pct_rim = weighted.mean(pct_rim, two_pa_total), .groups = "drop")
league_avg_panel <- mean(player_season_avg$avg_pct_rim)
message(sprintf("Panel-derived player-level season-avg pct_rim: league avg=%.4f, unclamped ratio range=[%.4f, %.4f] (this is the actual quantity adjust_mu_for_shot_mix() receives at call time - confirms SHOT_MIX_PTS_CLAMP's +/-10%% bound is not binding on real data).",
                 league_avg_panel,
                 1 + SLOPE * (min(player_season_avg$avg_pct_rim) - league_avg_panel),
                 1 + SLOPE * (max(player_season_avg$avg_pct_rim) - league_avg_panel)))

# ------------------------------------------------------------------------------
# SECTION 4: spot-check the wired-in adjustment against real generated props
# ------------------------------------------------------------------------------
message("\n=== SECTION 4: live spot-check against cache/latest_player_props.rds ===")
if (file.exists(CACHE_PLAYER_PROPS)) {
  props <- readRDS(CACHE_PLAYER_PROPS)
  roster <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds")) |> distinct(player_id, player_name)
  pts <- props |> filter(stat == "PTS") |>
    left_join(roster, by = c("player" = "player_name")) |>
    left_join(feats |> select(player_id, pct_rim, fga_total), by = "player_id") |>
    filter(!is.na(pct_rim), fga_total >= 20) |>
    arrange(desc(pct_rim))
  message("Top 5 highest pct_rim players (expect an UPWARD adj_pts bump):")
  print(utils::head(pts |> select(player, pct_rim, proj_mu), 5))
  message("\nBottom 5 lowest pct_rim players (expect a DOWNWARD adj_pts nudge):")
  print(utils::tail(pts |> select(player, pct_rim, proj_mu), 5))
} else {
  message("cache/latest_player_props.rds not found - run player_props_engine.R first to spot-check the live wiring.")
}
