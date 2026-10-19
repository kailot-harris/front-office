# ==============================================================================
# Gate-aware re-verification + multiple-comparisons correction for the home-backup-QB
# market-bias finding (docs/HANDOFF.md Known Issue #4).
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/verify_qb_backup_market_bias_gated.R
#
# tools/verify_qb_backup_market_bias.R's walk-forward strategy test (n=399 bets, Sharpe
# +0.0911, cumulative return +96.6%, bootstrap 95% CI [-0.0058, +0.187], 96.7% of resamples
# positive) does NOT apply either of the two real production staking gates
# (MIN_SAMPLE_GAMES_FOR_STAKE, LONGSHOT_DECIMAL_ODDS_CAP - both defined in config.R and both
# actually enforced in market_odds_engine.R's live slate table, see that file's
# `insufficient_sample`/`longshot_excluded` mutate() blocks). This script:
#
#   (1) Re-runs the identical walk-forward bias-estimation/betting loop from
#       verify_qb_backup_market_bias.R, but drops any candidate bet that would have been
#       zeroed out by either live gate: min(home_gp, away_gp) < MIN_SAMPLE_GAMES_FOR_STAKE,
#       or away_dec > LONGSHOT_DECIMAL_ODDS_CAP (this strategy only ever bets the away side -
#       see the parent script's header). Gate order mirrors market_odds_engine.R's own
#       (sample-size gate, then longshot gate, each independently able to zero a bet).
#
#   (2) Applies a multiple-comparisons correction across every bucket-level actually tested by
#       tools/market_disagreement_features.R's exploratory screen. That script's own in-code
#       comment says "~8 buckets scanned" but the REAL, verified count (from
#       cache/market_disagreement_features.rds$diagnostics, 2026-09-30) is 14 distinct
#       bucket-levels across 5 features (rest_bucket: 3, div_game: 2, is_primetime: 2,
#       spread_bucket: 3, qb_situation: 4) - the "~8" in that script's comment was a loose
#       verbal estimate, not a recount; this script uses the verified 14, not the comment's
#       approximation (repo convention: re-verify a cited figure rather than propagate it).
#       Benjamini-Hochberg (FDR) is used as the primary correction (standard for an exploratory
#       multi-bucket screen where some real effects are plausible and total false-discovery
#       control, not zero-tolerance family-wise error, is the appropriate bar) with Bonferroni
#       reported alongside for the more conservative reading.
#
# Run with:
#   & "C:\Program Files\R\R-4.5.2\bin\Rscript.exe" tools/verify_qb_backup_market_bias_gated.R
# ==============================================================================

# NOTE: config.R hardcodes its own PROJECT_DIR/CACHE_DIR to the main checkout
# ("c:/Users/kailo/kayceeslices/NFL Analytics") - sourcing it always repoints CACHE_DIR there
# regardless of this script's own setwd(). When running this script from a worktree, override
# CACHE_DIR back to the worktree's own cache/ AFTER source("config.R") (below) so outputs land
# in the worktree being worked in, not the shared main checkout.
PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-afcb1ad06438eb485"
setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "tools/verify_qb_backup_market_bias_gated.R"
source("market_odds_engine.R")  # -> american_to_decimal(), calculate_kelly()
# Both config.R (line 22) and market_odds_engine.R's own source("config.R") re-assign
# PROJECT_DIR (into globalenv, since source()'s default local=FALSE) back to the hardcoded
# main-checkout path every time either is sourced - so re-deriving CACHE_DIR from PROJECT_DIR
# here would silently pick up the OVERWRITTEN value, not this script's own. Use a
# script-local, differently-named constant instead so it survives every source() call above.
WORKTREE_CACHE_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics/.claude/worktrees/agent-afcb1ad06438eb485/cache"
CACHE_DIR <- WORKTREE_CACHE_DIR  # see NOTE above
# CACHE_SCHEDULES was already resolved to file.path(<main-checkout CACHE_DIR>, ...) at
# source("config.R") time above (a one-time file.path() call, not lazily re-evaluated) - fix it
# too, for the same reason. Content is identical either way (both checkouts are at the same
# commit as of this run), but reads should still target this worktree's own copy, not reach
# into the shared main checkout.
CACHE_SCHEDULES <- file.path(WORKTREE_CACHE_DIR, "schedules_cache.rds")

cached <- readRDS(file.path(CACHE_DIR, "market_disagreement_features.rds"))
games_all <- cached$games
games <- games_all |> filter(qb_situation == "home_backup_only") |> arrange(season, week)
cat(sprintf("home_backup_only games: %d (seasons %d-%d)\n", nrow(games), min(games$season), max(games$season)))

# ==============================================================================
# PART 1: gate-aware walk-forward re-run
# ==============================================================================
cat("\n==============================================================\n")
cat("PART 1: re-run with MIN_SAMPLE_GAMES_FOR_STAKE + LONGSHOT_DECIMAL_ODDS_CAP applied\n")
cat(sprintf("MIN_SAMPLE_GAMES_FOR_STAKE = %d, LONGSHOT_DECIMAL_ODDS_CAP = %.1f\n",
            MIN_SAMPLE_GAMES_FOR_STAKE, LONGSHOT_DECIMAL_ODDS_CAP))
cat("==============================================================\n\n")

run_walkforward <- function(games, apply_gates) {
  MIN_PRIOR_GAMES <- 20
  seasons <- sort(unique(games$season))
  bet_rows <- list()

  for (s in seasons) {
    prior <- games |> filter(season < s)
    if (nrow(prior) < MIN_PRIOR_GAMES) next
    bias <- mean(prior$market_residual)

    cur <- games |> filter(season == s)
    for (i in seq_len(nrow(cur))) {
      g <- cur[i, ]

      if (apply_gates) {
        min_gp <- suppressWarnings(min(g$home_gp, g$away_gp))
        if (is.na(min_gp) || min_gp < MIN_SAMPLE_GAMES_FOR_STAKE) next  # sample-size gate
      }

      adj_home_prob <- min(max(g$market_prob + bias, 1e-4), 1 - 1e-4)
      adj_away_prob <- 1 - adj_home_prob
      away_dec <- american_to_decimal(g$away_ml)

      if (apply_gates && away_dec > LONGSHOT_DECIMAL_ODDS_CAP) next  # longshot gate

      away_ev <- adj_away_prob * away_dec - 1
      if (away_ev <= 0) next
      kelly_pct <- calculate_kelly(adj_away_prob, away_dec, fraction = 0.25, max_cap_pct = 3.0)
      if (kelly_pct <= 0) next
      won <- g$home_win == 0L
      bet_return_pct <- if (won) kelly_pct / 100 * (away_dec - 1) else -kelly_pct / 100
      bet_rows[[length(bet_rows) + 1]] <- data.frame(
        season = s, week = g$week, game_id = g$game_id, home_team = g$home_team, away_team = g$away_team,
        prior_bias_used = bias, market_prob = g$market_prob, adj_away_prob = adj_away_prob,
        away_dec = away_dec, kelly_pct = kelly_pct, won = won, bet_return_pct = bet_return_pct
      )
    }
  }
  bind_rows(bet_rows)
}

summarize_bets <- function(bets, label) {
  cat(sprintf("\n--- %s ---\n", label))
  if (nrow(bets) < 5) {
    cat(sprintf("n=%d - too few bets to evaluate meaningfully.\n", nrow(bets)))
    return(list(n = nrow(bets), sharpe = NA_real_, cum_ret_pct = NA_real_, boot_ci = c(NA_real_, NA_real_), pct_positive = NA_real_))
  }
  sharpe <- mean(bets$bet_return_pct) / sd(bets$bet_return_pct)
  cum_ret_pct <- sum(bets$bet_return_pct) * 100
  cat(sprintf("n=%d, win rate=%.1f%%, Sharpe=%.4f, cumulative return=%.2f%%\n",
              nrow(bets), 100 * mean(bets$won), sharpe, cum_ret_pct))
  print(bets |> group_by(season) |> summarise(n = dplyr::n(), win_rate = mean(won), cum_ret_pct = sum(bet_return_pct) * 100, .groups = "drop"))
  n_pos_seasons <- bets |> group_by(season) |> summarise(cum = sum(bet_return_pct), .groups = "drop") |> summarise(sum(cum > 0)) |> pull()
  n_seasons <- length(unique(bets$season))
  cat(sprintf("Positive in %d/%d seasons.\n", n_pos_seasons, n_seasons))

  set.seed(20260917)
  boot_sharpes <- vapply(seq_len(10000), function(i) {
    s <- sample(bets$bet_return_pct, size = nrow(bets), replace = TRUE)
    if (sd(s) == 0) return(NA_real_)
    mean(s) / sd(s)
  }, numeric(1))
  boot_sharpes <- boot_sharpes[!is.na(boot_sharpes)]
  ci <- quantile(boot_sharpes, c(0.025, 0.975))
  pct_positive <- mean(boot_sharpes > 0) * 100
  cat(sprintf("Bootstrap 95%% CI on Sharpe: [%.4f, %.4f], %.1f%% of resamples positive.\n", ci[1], ci[2], pct_positive))

  list(n = nrow(bets), sharpe = sharpe, cum_ret_pct = cum_ret_pct,
       boot_ci = as.numeric(ci), pct_positive = pct_positive, n_pos_seasons = n_pos_seasons, n_seasons = n_seasons)
}

bets_ungated <- run_walkforward(games, apply_gates = FALSE)
res_ungated  <- summarize_bets(bets_ungated, "UNGATED (reproduces original verify_qb_backup_market_bias.R)")

bets_gated <- run_walkforward(games, apply_gates = TRUE)
res_gated  <- summarize_bets(bets_gated, "GATED (MIN_SAMPLE_GAMES_FOR_STAKE + LONGSHOT_DECIMAL_ODDS_CAP applied)")

cat(sprintf("\nGate impact: %d -> %d bets (%.1f%% of ungated bets survive both gates).\n",
            res_ungated$n, res_gated$n, 100 * res_gated$n / res_ungated$n))

# ==============================================================================
# PART 2: multiple-comparisons correction across the screened buckets
# ==============================================================================
cat("\n==============================================================\n")
cat("PART 2: multiple-comparisons correction across screened buckets\n")
cat("==============================================================\n\n")

all_diag <- bind_rows(lapply(names(cached$diagnostics), function(nm) {
  d <- as.data.frame(cached$diagnostics[[nm]])
  d$feature <- nm
  d$bucket  <- as.character(d[[1]])
  d
}))
cat(sprintf("Verified bucket-level count actually screened: %d (across %d features: %s)\n",
            nrow(all_diag), length(cached$diagnostics), paste(names(cached$diagnostics), collapse = ", ")))
cat("(market_disagreement_features.R's own comment says '~8 buckets' - that was a loose verbal\n")
cat(" estimate, not a recount; the true, verified figure from the cached diagnostics is used below.)\n\n")

all_diag <- all_diag |>
  mutate(
    z = mean_residual / se,
    p_raw = 2 * pnorm(-abs(z))
  ) |>
  arrange(p_raw)

all_diag$p_bonferroni <- pmin(1, all_diag$p_raw * nrow(all_diag))
all_diag$p_bh <- p.adjust(all_diag$p_raw, method = "BH")

print(all_diag |> select(feature, bucket, n, mean_residual, se, p_raw, p_bonferroni, p_bh))

target_row <- all_diag |> filter(feature == "qb", bucket == "home_backup_only")
cat(sprintf("\nhome_backup_only: raw p=%.5f, Bonferroni-corrected p=%.5f, BH-corrected p=%.5f\n",
            target_row$p_raw, target_row$p_bonferroni, target_row$p_bh))
cat(sprintf("Survives alpha=0.05 - raw: %s | Bonferroni: %s | BH: %s\n",
            target_row$p_raw < 0.05, target_row$p_bonferroni < 0.05, target_row$p_bh < 0.05))

# ==============================================================================
# PART 3: 2025-2026 true-holdout feasibility check (cache-only, no live calls)
# ==============================================================================
cat("\n==============================================================\n")
cat("PART 3: 2025-2026 true-holdout feasibility (cached data only)\n")
cat("==============================================================\n\n")

cat(sprintf("Discovery window used by market_disagreement_features.R: seasons %d-%d (STAKING_SEASONS).\n",
            min(games_all$season), max(games_all$season)))
cat(sprintf("CURRENT_SEASON = %d. A true holdout requires season %d in-progress data NOT already\n", CURRENT_SEASON, CURRENT_SEASON))
cat("inside that discovery window.\n\n")

sch <- readRDS(CACHE_SCHEDULES)
season_now <- sch |> filter(season == CURRENT_SEASON)
completed_now <- season_now |> filter(!is.na(home_score), !is.na(away_score))
cat(sprintf("CACHE_SCHEDULES season %d: %d scheduled games, %d completed (weeks: %s).\n",
            CURRENT_SEASON, nrow(season_now), nrow(completed_now),
            paste(sort(unique(completed_now$week)), collapse = ",")))

has_depth_chart_cache <- any(grepl("depth", list.files(CACHE_DIR), ignore.case = TRUE))
cat(sprintf("\nCached depth-chart / QB-starter data for season %d present under cache/: %s\n",
            CURRENT_SEASON, has_depth_chart_cache))
cat("get_qb_starter_table()/compute_qb_backup_flags() (tools/qb_injury_features.R) require\n")
cat("nflreadr::load_depth_charts(seasons=...) - a LIVE network call, out of scope for this task\n")
cat("(brief restricts this task to already-cached data, no live network calls). No persisted\n")
cat("depth-chart cache exists in this repo for any season (team_ratings_engine.R calls\n")
cat("load_depth_charts() live, in-process, every pipeline run - it is never written to a CACHE_*\n")
cat("file) - so the season-2026 home_backup_only subset cannot be constructed from cached data\n")
cat("alone, at any sample size.\n")

saveRDS(list(
  run_at = Sys.time(),
  bets_ungated = bets_ungated, res_ungated = res_ungated,
  bets_gated = bets_gated, res_gated = res_gated,
  bucket_pvalues = all_diag,
  holdout_check = list(current_season = CURRENT_SEASON,
                        n_completed_games = nrow(completed_now),
                        weeks_completed = sort(unique(completed_now$week)),
                        depth_chart_cache_present = has_depth_chart_cache)
), file.path(CACHE_DIR, "qb_backup_market_bias_gated_verification.rds"))
cat("\nSaved to cache/qb_backup_market_bias_gated_verification.rds\n")
