# ==============================================================================
# Market-Disagreement Project: Phases 0-2 (label + hypothesized features + exploratory
# diagnostics, NO model fit yet - that's Phase 3, a separate future script)
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/market_disagreement_features.R
#
# PHASE 0 FINDINGS (fact-check before building anything, 2026-09-17):
#   - nflreadr::dictionary_schedules (v1.5.1, live-checked via data(dictionary_schedules,
#     package="nflreadr") - NOT a namespace function, a lazy-loaded data object, a real gotcha
#     worth remembering) describes home_moneyline/away_moneyline/spread_line only as "Odds for
#     [team] to win the game" / "The spread line for the game" - NO mention anywhere of
#     opening vs. closing timing or which sportsbook/vendor it came from. Checked nflseedR's
#     load_sharpe_games() docs too (the historical community source these columns trace back
#     to) - same result, genuinely undocumented at the source.
#   - This repo's OWN CACHE_ODDS_HISTORY (market_odds_engine.R) only has 416 rows spanning
#     <24 hours (started this session) - there is no historical line-MOVEMENT data of any kind,
#     and no temporal overlap with nflverse's historical moneylines to cross-validate against.
#   - CONCLUSION: the exact timing of every historical `home_moneyline`/`away_moneyline` value
#     this repo has ever backtested against is UNVERIFIABLE with data currently available. This
#     is a real, previously-unflagged epistemic gap, not a blocker - the common public-NFL-
#     analytics assumption (unverified here) is that these approximate closing-line-like
#     numbers. Every `market_residual` figure below inherits this uncertainty - treat conclusions
#     as "residual against nflverse's recorded line," not provably "residual against the true
#     closing line," until an independent cross-check becomes possible (e.g. once this repo's
#     own CACHE_ODDS_HISTORY accumulates enough real history to compare against a future
#     season's nflverse-recorded lines for the same games).
#   - Public bet-percentage/handle data (the classic "fade the public" signal) does not exist
#     anywhere in this repo and is a new paid-vendor decision explicitly deferred pending user
#     sign-off - not included in the features below.
#
# PHASE 1: the label. market_residual = home_win (0/1) - market_prob (devigged consensus,
# same american_to_prob()/devig math every other candidate in this repo uses) - positive means
# the home team won more often than the market's own price implied (market underrated home),
# negative means the opposite. This is the literal target a "predict market disagreement,
# not game outcome" model would eventually be trained against (Phase 3, not this file).
#
# PHASE 2: features hypothesized to correlate with MARKET ERROR specifically (not just game
# outcome) - deliberately different from every situational-EPA/Kalman/participation feature
# already tried this session, all buildable from CACHE_SCHEDULES alone (already-computed
# home_rest/away_rest/div_game columns - live-verified, no new ingestion needed) plus the
# existing QB-backup flag builder (tools/qb_injury_features.R):
#   rest_diff       = home_rest - away_rest (short-rest mismatches - a classic "does the market
#                     fully price fatigue" question)
#   div_game        = already a real CACHE_SCHEDULES column (rivalry games are publicly
#                     believed to run "closer" than a model would predict - public money
#                     narrative bias)
#   is_primetime    = Thursday/Monday any time, or Sunday >= 18:00 - national-TV games draw
#                     more public betting volume, a precondition for the "fade the public"
#                     effect even without direct bet-percentage data
#   spread_line     = the market's OWN point spread (a large one may itself proxy for "a
#                     popular/heavily-bet favorite")
#   qb_backup flags = reused verbatim from tools/qb_injury_features.R (never a second copy)
#
# THIS FILE DOES NOT FIT A MODEL. It builds the labeled+featured dataset and runs exploratory
# slicing (mean residual by feature bucket, with a naive CI) to answer the Phase-1/2 question
# honestly: is there ANY visible structure here worth a Phase 3 model at all, before spending
# that effort? See the printed output / cache/market_disagreement_features.rds for the answer.
#
# Run with:
#   "/c/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/market_disagreement_features.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/market_disagreement_features.R"

source("team_ratings_engine.R")
source("market_odds_engine.R")
source("tools/backtest_common.R")
source("tools/qb_injury_features.R")

epa <- readRDS(CACHE_EPA_METRICS) |> mutate(game_date = as.Date(game_date))
sch <- readRDS(CACHE_SCHEDULES)   |> mutate(gameday = as.Date(gameday))
completed <- sch |> filter(!is.na(home_score), !is.na(away_score))

STAKING_SEASONS <- 2010L:(CURRENT_SEASON - 1L)  # real moneylines only, same window as MARKET_BLEND_WEIGHT
avg_plays_per_game <- mean(epa$n_off_plays, na.rm = TRUE)

cat("==============================================================\n")
cat("Market-disagreement label + feature build - run at", format(Sys.time()), "\n")
cat("==============================================================\n\n")

games <- build_walkforward_games(epa, completed, STAKING_SEASONS, avg_plays_per_game) |>
  filter(!is.na(home_ml), !is.na(away_ml))
cat(sprintf("Built %d walk-forward games with real historical moneylines.\n", nrow(games)))

# ---- Phase 1: the label ----
imp_h <- american_to_prob(games$home_ml)
imp_a <- american_to_prob(games$away_ml)
games$market_prob <- imp_h / (imp_h + imp_a)
games$market_residual <- games$home_win - games$market_prob

# ---- Phase 2: features (all from CACHE_SCHEDULES columns already present, plus QB flags) ----
sch_cols <- sch |> select(game_id, home_rest, away_rest, div_game, weekday, gametime, spread_line)
games <- games |> left_join(sch_cols, by = "game_id") |>
  mutate(
    rest_diff    = home_rest - away_rest,
    is_primetime = weekday %in% c("Thursday", "Monday") | (weekday == "Sunday" & gametime >= "18:00"),
    rest_bucket  = case_when(
      rest_diff <= -3 ~ "away_rest_advantage",
      rest_diff >=  3 ~ "home_rest_advantage",
      TRUE             ~ "similar_rest"
    ),
    spread_bucket = case_when(
      is.na(spread_line)      ~ NA_character_,
      abs(spread_line) < 3    ~ "close_spread (<3)",
      abs(spread_line) < 7    ~ "moderate_spread (3-7)",
      TRUE                     ~ "heavy_favorite (>7)"
    )
  )

starter_tbl <- get_qb_starter_table((MODERN_ERA_START_SEASON):(CURRENT_SEASON - 1L))
qb_flags <- compute_qb_backup_flags(starter_tbl) |> select(season, week, team, qb_backup_started)
games <- games |>
  left_join(qb_flags |> rename(home_qb_backup = qb_backup_started), by = c("season", "week", "home_team" = "team")) |>
  left_join(qb_flags |> rename(away_qb_backup = qb_backup_started), by = c("season", "week", "away_team" = "team")) |>
  mutate(
    # isTRUE() is NOT vectorized in base R (it only ever evaluates a single scalar) - using it
    # inside case_when()'s vectorized conditions silently collapses every row to the FALSE/
    # fallback branch. Confirmed live: an earlier version of this script using isTRUE() here
    # put all 4,009 rows into "neither_backup", masking any real QB-backup signal entirely.
    # `%in% TRUE` is the correct vectorized equivalent (also NA-safe: NA %in% TRUE is FALSE).
    home_backup_flag = home_qb_backup %in% TRUE,
    away_backup_flag = away_qb_backup %in% TRUE,
    qb_situation = case_when(
      home_backup_flag & !away_backup_flag ~ "home_backup_only",
      away_backup_flag & !home_backup_flag ~ "away_backup_only",
      home_backup_flag & away_backup_flag  ~ "both_backup",
      TRUE                                   ~ "neither_backup"
    )
  )

cat(sprintf("Games with a known QB situation: %d/%d.\n\n",
            sum(games$qb_situation != "neither_backup" | (!is.na(games$home_qb_backup) & !is.na(games$away_qb_backup))), nrow(games)))

# ------------------------------------------------------------------------------------------
# slice_diagnostic(): mean market_residual per bucket of `group_col`, with n and a naive 95%
# CI (mean +/- 1.96*SE) - exploratory only (no multiple-comparison correction - this is a
# "is anything here worth a closer look" scan, not a confirmatory test).
# ------------------------------------------------------------------------------------------
slice_diagnostic <- function(df, group_col, label) {
  cat(sprintf("--- %s ---\n", label))
  out <- df |>
    filter(!is.na(.data[[group_col]])) |>
    group_by(.data[[group_col]]) |>
    summarise(
      n = dplyr::n(),
      mean_residual = mean(market_residual),
      se = sd(market_residual) / sqrt(dplyr::n()),
      .groups = "drop"
    ) |>
    mutate(ci_low = mean_residual - 1.96 * se, ci_high = mean_residual + 1.96 * se)
  print(as.data.frame(out), row.names = FALSE)
  cat("\n")
  out
}

cat("==============================================================\n")
cat("EXPLORATORY DIAGNOSTICS: mean market_residual by feature bucket\n")
cat("(residual > 0 means the home team outperformed the market's price; < 0 means the market\n")
cat(" overrated the home team. A bucket whose 95% CI excludes 0 is worth a closer look - but\n")
cat(" with ~8 buckets scanned here, expect ~1 in 20 to cross that bar by chance alone even if\n")
cat(" nothing real is happening; this is a screen, not a confirmatory result.)\n")
cat("==============================================================\n\n")

r_rest    <- slice_diagnostic(games, "rest_bucket", "Rest-day mismatch")
r_div     <- slice_diagnostic(games, "div_game", "Divisional game (0/1)")
r_prime   <- slice_diagnostic(games, "is_primetime", "Primetime (TNF/SNF/MNF)")
r_spread  <- slice_diagnostic(games, "spread_bucket", "Spread size")
r_qb      <- slice_diagnostic(games, "qb_situation", "QB-backup situation")

cat("==============================================================\n")
cat(sprintf("Overall market_residual mean (sanity check - should be ~0 if devig math is correct): %.4f (n=%d)\n",
            mean(games$market_residual), nrow(games)))
cat("==============================================================\n")

saveRDS(list(
  run_at = Sys.time(), games = games,
  diagnostics = list(rest = r_rest, div_game = r_div, primetime = r_prime, spread = r_spread, qb = r_qb)
), file.path(CACHE_DIR, "market_disagreement_features.rds"))
cat("\nSaved full labeled+featured dataset and diagnostics to cache/market_disagreement_features.rds\n")
