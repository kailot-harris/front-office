# ==============================================================================
# research_team_depth_regression.R
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/tools/research_team_depth_regression.R
#
# Full empirical derivation behind the "Tier 2" question for cache/features_cache.rds
# (team_top5_bpm / team_minutes_concentration, produced by player_metrics.R::get_player_features()
# but never consumed by anything): does either signal carry real, non-circular, FORECASTING-
# useful predictive power for a team's game margin, over and above the team's own recent-form
# baseline? See docs/team_depth_signal_regression_findings.md for the narrative writeup.
#
# Mirrors tools/research_shot_mix_regression.R's structure exactly (numbered sections, join-key
# verification, panel build, regression, decision) so this is reproducible end-to-end via a
# single `Rscript.exe tools/research_team_depth_regression.R` run.
#
# CIRCULARITY TRAP (see task brief / CLAUDE.md-adjacent instructions): team_weighted_bpm /
# team_top5_bpm / team_minutes_concentration for game G are computed FROM game G's own box
# stats -- the same box stats that mechanically determine game G's score/margin. Regressing
# SAME-GAME margin on SAME-GAME features would be near-tautological. This script NEVER does
# that regression. Instead it builds TRAILING (strictly-prior-games-only) rolling averages per
# team and tests whether those predict the team's CURRENT (next, relative to the trailing
# window) game margin, over and above the team's own trailing-average margin.
# ==============================================================================

setwd("C:/Users/kailo/kayceeslices/WNBA Analytics")
source("config.R")
source("player_metrics.R")  # for filter_real_franchises()/normalize_team_abbreviation() - function defs only, no side effects (see that file's header)
suppressPackageStartupMessages(library(dplyr))

out_dir <- file.path("tools", "research_output")
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

feat <- readRDS(CACHE_FEATURES)
box  <- readRDS(CACHE_PLAYER_BOX)

# ------------------------------------------------------------------------------
# SECTION 1: join-key verification (CACHE_FEATURES <-> CACHE_PLAYER_BOX)
# ------------------------------------------------------------------------------
# Per CLAUDE.md's task brief, this is asserted to already share a namespace (both derived from
# the same wehoop::load_wnba_player_box() pull inside get_player_features()) - verified directly
# here rather than trusted, matching this repo's own stated convention of never assuming a join
# key without checking (see research_shot_mix_regression.R Section 1, and the RAPM<->roster
# caution in CLAUDE.md).
message("\n=== SECTION 1: join-key verification ===")
message(sprintf("CACHE_FEATURES: %d team-game rows. class(game_id)=%s, class(team_id)=%s",
                 nrow(feat), class(feat$game_id), class(feat$team_id)))
message(sprintf("CACHE_PLAYER_BOX (raw): %d player-game rows. class(game_id)=%s, class(team_id)=%s",
                 nrow(box), class(box$game_id), class(box$team_id)))

# Per CLAUDE.md: raw wehoop box data can include non-franchise exhibition rows, and CONN must be
# normalized to CON before filtering. Confirmed empirically below that this cache is ALREADY
# clean (get_player_box_scores_chunked() applies filter_real_franchises() before it's ever
# cached) - but the filter is applied here too, defensively and idempotently, rather than
# trusting that the on-disk cache was necessarily built post-fix.
box_clean <- filter_real_franchises(box)
message(sprintf("player_box after filter_real_franchises(): %d rows (%d dropped as non-franchise/exhibition).",
                 nrow(box_clean), nrow(box) - nrow(box_clean)))
distinct_abbrevs <- sort(unique(box_clean$team_abbreviation))
message(sprintf("Distinct team_abbreviation after filter (%d): %s -- matches names(WNBA_TEAMS) (%d): %s",
                 length(distinct_abbrevs), paste(distinct_abbrevs, collapse = ","),
                 length(names(WNBA_TEAMS)), all(distinct_abbrevs %in% names(WNBA_TEAMS))))

box_tg <- box_clean |>
  mutate(game_id_chr = as.character(game_id)) |>
  distinct(game_id_chr, team_id)
feat_tg <- feat |> distinct(game_id, team_id)

overlap <- inner_join(box_tg, feat_tg, by = c("game_id_chr" = "game_id", "team_id" = "team_id"))
message(sprintf("Team-game key overlap: %d box team-games, %d features team-games, %d in common (%.2f%% of features rows matched).",
                 nrow(box_tg), nrow(feat_tg), nrow(overlap), nrow(overlap) / nrow(feat_tg) * 100))
stopifnot(nrow(overlap) == nrow(feat_tg))  # CLAUDE.md's brief asserts an EXACT same-namespace match; verify, don't assume.
message("CONFIRMED: exact 1:1 (game_id, team_id) match between CACHE_FEATURES and CACHE_PLAYER_BOX. Direct join, no bridging needed.")

# ------------------------------------------------------------------------------
# SECTION 2: build the team-game panel (real margin + real depth/top5-BPM features)
# ------------------------------------------------------------------------------
message("\n=== SECTION 2: team-game panel construction ===")

team_game <- box_clean |>
  mutate(game_id = as.character(game_id)) |>
  group_by(game_id, team_id) |>
  summarise(
    team_abbreviation = first(team_abbreviation),
    season            = first(season),
    game_date         = first(game_date),
    home_away         = first(home_away),
    team_score        = first(team_score),
    opponent_team_score = first(opponent_team_score),
    margin            = first(team_score) - first(opponent_team_score),
    .groups = "drop"
  ) |>
  inner_join(feat, by = c("game_id", "team_id"))

message(sprintf("Team-game panel: %d rows (%d distinct teams, %d distinct games), seasons %d-%d.",
                 nrow(team_game), length(unique(team_game$team_id)), length(unique(team_game$game_id)),
                 min(team_game$season), max(team_game$season)))
saveRDS(team_game, file.path(out_dir, "team_depth_panel_raw.rds"))

# ------------------------------------------------------------------------------
# SECTION 3: trailing (strictly-prior-games) rolling averages per team
# ------------------------------------------------------------------------------
message("\n=== SECTION 3: trailing rolling averages (avoiding the same-game circularity trap) ===")
message(sprintf("Using ROLLING_WINDOW_SIZE = %d from config.R (the repo's existing, empirically re-tested trailing-window constant for exactly this kind of forward-looking feature).",
                 ROLLING_WINDOW_SIZE))

# Minimum trailing-games threshold before a team-game qualifies. Full ROLLING_WINDOW_SIZE (12)
# would drop a large fraction of each team's early-season games; relaxed to >= 5, matching the
# >= 5-games threshold already used for OPP_DEF_MU_SLOPE/SHOT_MIX_PTS_SLOPE elsewhere in this
# repo (same documented precedent, not a new arbitrary number).
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
    n_prior_games                              = pmin(row_number() - 1, ROLLING_WINDOW_SIZE),
    trailing_avg_margin                        = trailing_avg(margin, ROLLING_WINDOW_SIZE),
    trailing_avg_team_minutes_concentration    = trailing_avg(team_minutes_concentration, ROLLING_WINDOW_SIZE),
    trailing_avg_team_top5_bpm                 = trailing_avg(team_top5_bpm, ROLLING_WINDOW_SIZE)
  ) |>
  ungroup() |>
  filter(n_prior_games >= MIN_TRAILING_GAMES,
         is.finite(trailing_avg_margin), is.finite(trailing_avg_team_minutes_concentration),
         is.finite(trailing_avg_team_top5_bpm))

message(sprintf("Qualifying panel (>= %d trailing games/team): %d team-games across %d distinct teams.",
                 MIN_TRAILING_GAMES, nrow(panel), length(unique(panel$team_id))))
saveRDS(panel, file.path(out_dir, "team_depth_panel_trailing.rds"))

# ------------------------------------------------------------------------------
# SECTION 4: collinearity check
# ------------------------------------------------------------------------------
message("\n=== SECTION 4: collinearity check (trailing_avg_team_top5_bpm vs trailing_avg_margin) ===")
corr_top5_margin <- cor(panel$trailing_avg_team_top5_bpm, panel$trailing_avg_margin)
corr_conc_margin <- cor(panel$trailing_avg_team_minutes_concentration, panel$trailing_avg_margin)
corr_conc_top5   <- cor(panel$trailing_avg_team_minutes_concentration, panel$trailing_avg_team_top5_bpm)
message(sprintf("cor(trailing_avg_team_top5_bpm, trailing_avg_margin) = %.4f", corr_top5_margin))
message(sprintf("cor(trailing_avg_team_minutes_concentration, trailing_avg_margin) = %.4f", corr_conc_margin))
message(sprintf("cor(trailing_avg_team_minutes_concentration, trailing_avg_team_top5_bpm) = %.4f", corr_conc_top5))

# Manual VIF (no `car` dependency): VIF_j = 1 / (1 - R^2 of regressing regressor j on the OTHER
# regressors in the model, including trailing_avg_margin).
vif_of <- function(target, others_df) {
  aux <- lm(target ~ ., data = others_df)
  1 / (1 - summary(aux)$r.squared)
}
regressors <- panel |> select(trailing_avg_margin, trailing_avg_team_minutes_concentration, trailing_avg_team_top5_bpm)
vif_margin <- vif_of(regressors$trailing_avg_margin, regressors |> select(-trailing_avg_margin))
vif_conc   <- vif_of(regressors$trailing_avg_team_minutes_concentration, regressors |> select(-trailing_avg_team_minutes_concentration))
vif_top5   <- vif_of(regressors$trailing_avg_team_top5_bpm, regressors |> select(-trailing_avg_team_top5_bpm))
message(sprintf("VIF: trailing_avg_margin=%.3f, trailing_avg_team_minutes_concentration=%.3f, trailing_avg_team_top5_bpm=%.3f",
                 vif_margin, vif_conc, vif_top5))
message("Rule of thumb applied: VIF > 5 or |r| > 0.8 flags severe collinearity.")

# ------------------------------------------------------------------------------
# SECTION 5: within-team fixed-effects regression (demeaned, mirrors SHOT_MIX_PTS_SLOPE)
# ------------------------------------------------------------------------------
message("\n=== SECTION 5: within-team FE regression: margin ~ trailing_avg_margin + trailing_avg_conc + trailing_avg_top5_bpm ===")

panel_de <- panel |>
  group_by(team_id) |>
  mutate(
    margin_dm       = margin - mean(margin, na.rm = TRUE),
    tam_dm          = trailing_avg_margin - mean(trailing_avg_margin, na.rm = TRUE),
    tconc_dm        = trailing_avg_team_minutes_concentration - mean(trailing_avg_team_minutes_concentration, na.rm = TRUE),
    ttop5_dm        = trailing_avg_team_top5_bpm - mean(trailing_avg_team_top5_bpm, na.rm = TRUE)
  ) |>
  ungroup()

message("\n--- Model 1: margin ~ trailing_avg_margin only (recent-form baseline) ---")
m1 <- lm(margin_dm ~ tam_dm, data = panel_de)
print(summary(m1))

message("\n--- Model 2: margin ~ trailing_avg_margin + trailing_avg_team_minutes_concentration ---")
m2 <- lm(margin_dm ~ tam_dm + tconc_dm, data = panel_de)
print(summary(m2))

message("\n--- Model 3: margin ~ trailing_avg_margin + trailing_avg_team_top5_bpm ---")
m3 <- lm(margin_dm ~ tam_dm + ttop5_dm, data = panel_de)
print(summary(m3))

message("\n--- Model 4 (full, primary model): margin ~ trailing_avg_margin + trailing_avg_conc + trailing_avg_top5_bpm ---")
m4 <- lm(margin_dm ~ tam_dm + tconc_dm + ttop5_dm, data = panel_de)
print(summary(m4))

message("\n--- Model 5: explicit factor(team_id) FE sanity check (confirms demeaning shortcut is unbiased) ---")
m5 <- lm(margin ~ trailing_avg_margin + trailing_avg_team_minutes_concentration + trailing_avg_team_top5_bpm + factor(team_id), data = panel)
print(summary(m5)$coefficients[c("(Intercept)", "trailing_avg_margin", "trailing_avg_team_minutes_concentration", "trailing_avg_team_top5_bpm"), , drop = FALSE])

# ------------------------------------------------------------------------------
# SECTION 6: significance/sign decision for each candidate term (independent)
# ------------------------------------------------------------------------------
message("\n=== SECTION 6: decision ===")
coefs4 <- summary(m4)$coefficients
conc_p <- coefs4["tconc_dm", "Pr(>|t|)"]
conc_est <- coefs4["tconc_dm", "Estimate"]
top5_p <- coefs4["ttop5_dm", "Pr(>|t|)"]
top5_est <- coefs4["ttop5_dm", "Estimate"]
message(sprintf("trailing_avg_team_minutes_concentration: coef=%.4f, p=%.4g -> %s",
                 conc_est, conc_p, if (conc_p < 0.05) "SIGNIFICANT (sign a priori ambiguous, any sign acceptable)" else "NOT significant -> DROP"))
message(sprintf("trailing_avg_team_top5_bpm: coef=%.4f, p=%.4g, sign %s -> %s",
                 top5_est, top5_p,
                 if (top5_est > 0) "POSITIVE (theory-consistent)" else "NEGATIVE (theory-INCONSISTENT)",
                 if (top5_p < 0.05 && top5_est > 0) "SIGNIFICANT + correct sign -> WIRE IN" else "does not clear bar -> DROP"))

message("\n=== SECTION 6b: sample sizes for writeup ===")
message(sprintf("n = %d team-games, %d distinct teams, seasons %d-%d, MIN_TRAILING_GAMES = %d, ROLLING_WINDOW_SIZE = %d.",
                 nrow(panel), length(unique(panel$team_id)), min(panel$season), max(panel$season),
                 MIN_TRAILING_GAMES, ROLLING_WINDOW_SIZE))

# ------------------------------------------------------------------------------
# SECTION 7: live current-team spot-check data (for the clamp/writeup, if wired in)
# ------------------------------------------------------------------------------
message("\n=== SECTION 7: current (most-recent-window) trailing signal per team, for a live sanity check ===")
current_signal <- panel |>
  group_by(team_id) |>
  slice_max(order_by = game_date, n = 1) |>
  ungroup() |>
  select(team_id, team_abbreviation, game_date, trailing_avg_margin, trailing_avg_team_minutes_concentration, trailing_avg_team_top5_bpm) |>
  arrange(desc(trailing_avg_team_top5_bpm))
print(as.data.frame(current_signal))
saveRDS(current_signal, file.path(out_dir, "team_depth_current_signal.rds"))

message("\n=== DONE ===")
