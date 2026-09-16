# ==============================================================================
# playoff_simulator.R (WNBA port)
# Phase 5 (T5 / wnba_live_dashboard_agent): Monte Carlo Playoff Series & Bracket Simulator
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/playoff_simulator.R
#
# Ported from NBA Analytics/playoff_simulator.R. The NBA original assumes best-of-7
# (2-2-1-1-1) for every playoff round, which per WNBA_REPLICATION_PLAN.md §(b) Tier 3 is
# explicitly flagged as NOT safe to assume for the WNBA without verification.
#
# VERIFIED CURRENT WNBA PLAYOFF FORMAT (web search, 2026-09-12, confirmed by wnba.com's own
# "2026 Regular Season Key Dates" release and wnba.com's 2025 postseason FAQ/format-change
# announcement — the format below has been in effect since the 2025 postseason and is
# confirmed unchanged for the 2026 postseason, which tips off 2026-09-27):
#   - First Round:   BEST-OF-3  (1-1-1 home schedule). Higher seed hosts Games 1 & 3; the
#                    LOWER seed hosts Game 2 (note: NOT the higher seed hosting Games 1-2 the
#                    way a naive "higher seed gets the extra home game up front" assumption
#                    would suggest — WNBA changed this specific detail for 2025 too, per the
#                    same source). Win threshold: first to 2 (w_high < 2).
#   - Semifinals:    BEST-OF-5  (2-2-1 home schedule). Higher seed hosts Games 1, 2, and (if
#                    necessary) 5. Win threshold: first to 3 (w_high < 3).
#   - Finals:        BEST-OF-7  (2-2-1-1-1 home schedule). Higher seed hosts Games 1, 2, 5, 7.
#                    Win threshold: first to 4 (w_high < 4). This is the ONLY round where the
#                    NBA original's assumption (best-of-7 everywhere) happens to be correct —
#                    the WNBA Finals moved from best-of-5 to best-of-7 starting in 2025.
# Sources: wnba.com/news/2025-wnba-postseason-faq, wnba.com/news/wnba-finals-format-expansion-2025,
# wnba.com/news/2026-regular-season-key-dates. Re-verify at the start of each future postseason —
# the WNBA has changed this format multiple times historically (including a single-elimination
# first round in some past seasons), so do NOT assume today's 3/5/7 structure is permanent.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

# Structural constants (WNBA_MARGIN_SIGMA, WNBA_HCA). This used to be sourced only from inside
# the auto-run guard at the bottom of the file, which meant an analyst who source()d this file
# and called simulate_single_series() directly hit "object 'WNBA_MARGIN_SIGMA' not found".
# Guarded so a caller that already sourced config.R does not pay for it twice.
if (!exists("WNBA_MARGIN_SIGMA") || !exists("WNBA_HCA")) source("config.R")

# FINDING M-6 (Phase 4 Wave 4): this file carried its own unhardened scalar %||%
# (errors on a length>1 vector), identical to the app.R/market_odds_engine.R copies
# M-6 fixed. Source the single canonical hardened definition instead of restating it;
# guarded the same way as the config.R source() just above.
if (!exists("%||%")) source("logging_utils.R")

message(">>> [WNBA PLAYOFFS] Initializing Monte Carlo Playoff Series Simulator...")

# ------------------------------------------------------------------------------
# Format registry: home-court flag sequence + win threshold per round type.
# Keying this off a named list (rather than re-deriving the flags inline every call, as the
# NBA original did for its one hardcoded best-of-7 case) makes the three real WNBA round
# formats explicit and greppable.
# ------------------------------------------------------------------------------
PLAYOFF_FORMATS <- list(
  bo3 = list(home_flags = c(TRUE, FALSE, TRUE),                               win_threshold = 2, label = "Best-of-3 (1-1-1)"),
  bo5 = list(home_flags = c(TRUE, TRUE, FALSE, FALSE, TRUE),                  win_threshold = 3, label = "Best-of-5 (2-2-1)"),
  bo7 = list(home_flags = c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE),     win_threshold = 4, label = "Best-of-7 (2-2-1-1-1)")
)

# ------------------------------------------------------------------------------
# Playoff Net Rating Adjuster
# ------------------------------------------------------------------------------
# Same fallback-fail-safe structure as the NBA original: prefer real per-player RAPM if
# `cache/rapm_ratings.rds` exists, else fall back to a hand-set contender-leverage bump.
#
# STATUS AS OF THIS SESSION: no `rapm_engine.R` was ever ported into this WNBA repo by T0-T4
# (it was not in any prior agent's deliverable list per task_assignments.md's Handoff Notes,
# and confirmed absent via a directory listing before writing this file) — so the RAPM branch
# below is dead code in practice today, exactly as documented, not silently assumed to fire.
# The fallback contender-leverage table is keyed on WNBA_TEAMS' FULL team names (matching
# `cache/projected_wnba_standings.rds`'s `Team` column convention, per T2's Handoff Notes),
# not abbreviations, and reflects plausible-but-not-empirically-derived playoff leverage for
# the league's more established contenders as of the 2026 season (Lynx/Liberty/Aces have been
# the WNBA's dominant recent title contenders; Fever/Dream are included as up-and-coming playoff
# teams) — same "reasonable prior, not a fitted model" spirit as the NBA original's own hardcoded
# table, not represented as validated.
get_playoff_adjusted_rating <- function(team_name, reg_net_rating) {
  if (file.exists("cache/rapm_ratings.rds")) {
    rapm_data <- readRDS("cache/rapm_ratings.rds")
    tm_players <- rapm_data %>% filter(team == team_name) %>% arrange(desc(total_rapm))
    if (nrow(tm_players) >= 3) {
      top3_boost <- mean(head(tm_players$total_rapm, 3)) * 0.35
      return(reg_net_rating + top3_boost)
    }
  }
  contender_leverage <- c(
    "Minnesota Lynx"    = 2.2,
    "New York Liberty"  = 2.1,
    "Las Vegas Aces"    = 1.9,
    "Indiana Fever"     = 1.6,
    "Atlanta Dream"     = 1.4,
    "Seattle Storm"     = 1.3
  )
  return(reg_net_rating + (contender_leverage[[team_name]] %||% 0.0))
}

# ------------------------------------------------------------------------------
# Generalized Best-of-N Series Simulation (format-aware — bo3 / bo5 / bo7)
# ------------------------------------------------------------------------------
# FINDING C-1: `hca_pts` defaulted to the literal 2.40; it now defaults to config.R's WNBA_HCA.
# Same value, single definition site. (Default args are lazily evaluated, so WNBA_HCA only needs
# to exist at call time — the guarded source() above guarantees that.)
simulate_single_series <- function(team_high, team_low, net_high, net_low, n_sims = 10000,
                                    hca_pts = WNBA_HCA, format = "bo7") {
  if (!format %in% names(PLAYOFF_FORMATS)) stop(sprintf("Unknown playoff format '%s' — must be one of: %s", format, paste(names(PLAYOFF_FORMATS), collapse = ", ")))
  fmt <- PLAYOFF_FORMATS[[format]]
  home_high_flags <- fmt$home_flags
  win_threshold    <- fmt$win_threshold

  rating_diff <- net_high - net_low

  # WNBA_MARGIN_SIGMA (14.0, empirically derived by T2 from real 2019-2026 WNBA home-margin
  # variance — see config.R) replaces the NBA original's hardcoded 11.2, per
  # WNBA_REPLICATION_PLAN.md §(b) Tier 3's explicit instruction not to reuse the NBA sigma.
  p_high_home <- pnorm((rating_diff + hca_pts) / WNBA_MARGIN_SIGMA)
  p_high_away <- pnorm((rating_diff - hca_pts) / WNBA_MARGIN_SIGMA)

  max_games <- length(home_high_flags)
  sim_results <- matrix(0, nrow = n_sims, ncol = 2) # [high_wins, low_wins]
  series_lengths <- integer(n_sims)
  high_series_wins <- 0

  for (s in 1:n_sims) {
    w_high <- 0
    w_low  <- 0
    g <- 1

    while (w_high < win_threshold && w_low < win_threshold) {
      g_idx <- min(g, max_games) # guard against pathological >max_games loops (should never trigger)
      p_win <- ifelse(home_high_flags[g_idx], p_high_home, p_high_away)
      if (runif(1) < p_win) {
        w_high <- w_high + 1
      } else {
        w_low <- w_low + 1
      }
      g <- g + 1
    }

    series_lengths[s] <- (w_high + w_low)
    if (w_high == win_threshold) high_series_wins <- high_series_wins + 1
    sim_results[s, ] <- c(w_high, w_low)
  }

  p_series_high <- high_series_wins / n_sims
  p_series_low  <- 1 - p_series_high

  fair_ml_high <- ifelse(p_series_high >= 0.5,
                         round(-100 * p_series_high / (1 - p_series_high)),
                         round(100 * (1 - p_series_high) / p_series_high))
  fair_ml_low  <- ifelse(p_series_low >= 0.5,
                         round(-100 * p_series_low / (1 - p_series_low)),
                         round(100 * (1 - p_series_low) / p_series_low))

  outcomes <- tibble(
    high_w = sim_results[, 1],
    low_w  = sim_results[, 2]
  ) %>%
    mutate(scoreline = paste0(team_high, " ", high_w, "-", low_w, " ", team_low)) %>%
    count(scoreline) %>%
    mutate(prob_pct = round((n / n_sims) * 100, 2)) %>%
    arrange(desc(prob_pct))

  # Series-spread pricing: only meaningful for bo5/bo7 (a bo3 series has no "-1.5/-2.5 games"
  # market in practice since it's over in 2 or 3 games) — compute generically off win_threshold
  # rather than hardcoding "<=2"/"<=1" the way the NBA original did for its bo7-only case.
  p_cover_minus_1_5 <- mean(sim_results[, 1] == win_threshold & sim_results[, 2] <= (win_threshold - 2))
  p_cover_minus_2_5 <- mean(sim_results[, 1] == win_threshold & sim_results[, 2] <= (win_threshold - 3))

  list(
    format = format,
    format_label = fmt$label,
    high_seed = team_high,
    low_seed = team_low,
    p_high_seed_win = round(p_series_high, 4),
    p_low_seed_win = round(p_series_low, 4),
    fair_ml_high = fair_ml_high,
    fair_ml_low = fair_ml_low,
    avg_series_games = round(mean(series_lengths), 2),
    p_high_cover_minus_1_5 = round(p_cover_minus_1_5, 4),
    p_high_cover_minus_2_5 = round(p_cover_minus_2_5, 4),
    exact_outcomes = outcomes
  )
}

# ------------------------------------------------------------------------------
# Demonstration suite: real current WNBA teams from T2's actual standings cache, one example
# per round format (bo3/bo5/bo7) rather than the NBA original's single hardcoded BOS-vs-NYK
# example, per the T5 brief's instruction to swap in a real/plausible current matchup AND per
# this file's own need to demonstrate all three now-verified WNBA round formats.
# ------------------------------------------------------------------------------
simulate_playoff_suite <- function() {
  standings_path <- "cache/projected_wnba_standings.rds"
  if (file.exists(standings_path)) {
    standings <- readRDS(standings_path) %>% arrange(Rank)
    message(sprintf(">>> [PLAYOFFS] Loaded real standings from %s (%d teams).", standings_path, nrow(standings)))
  } else {
    warning(">>> [PLAYOFFS] cache/projected_wnba_standings.rds not found — run roster_bottom_up_engine.R first. Using a plausible placeholder 4-team slate instead.")
    standings <- tibble(
      Rank = 1:4,
      Team = c("Minnesota Lynx", "New York Liberty", "Las Vegas Aces", "Indiana Fever"),
      Net_Rating = c(12.14, 12.09, 6.0, 3.0)
    )
  }

  seed <- function(rank) {
    row <- standings %>% filter(Rank == rank)
    if (nrow(row) == 0) row <- standings %>% slice(min(rank, nrow(standings)))
    list(team = row$Team[1], net = row$Net_Rating[1])
  }

  results <- list()

  # First Round (best-of-3): a plausible #4-vs-#5 seed matchup from the real live standings.
  s4 <- seed(4); s5 <- seed(5)
  results$first_round <- simulate_single_series(
    team_high = s4$team, team_low = s5$team,
    net_high = get_playoff_adjusted_rating(s4$team, s4$net),
    net_low  = get_playoff_adjusted_rating(s5$team, s5$net),
    n_sims = 10000, format = "bo3"
  )
  message(sprintf(">>> [PLAYOFFS] First Round (Bo3): %s vs %s | %s Series Win: %.1f%%",
                  s4$team, s5$team, s4$team, results$first_round$p_high_seed_win * 100))

  # Semifinals (best-of-5): #2 vs #3 seed.
  s2 <- seed(2); s3 <- seed(3)
  results$semifinals <- simulate_single_series(
    team_high = s2$team, team_low = s3$team,
    net_high = get_playoff_adjusted_rating(s2$team, s2$net),
    net_low  = get_playoff_adjusted_rating(s3$team, s3$net),
    n_sims = 10000, format = "bo5"
  )
  message(sprintf(">>> [PLAYOFFS] Semifinals (Bo5): %s vs %s | %s Series Win: %.1f%%",
                  s2$team, s3$team, s2$team, results$semifinals$p_high_seed_win * 100))

  # Finals (best-of-7): #1 seed vs #2 seed — the real current top-2 teams in T2's live
  # standings (Minnesota Lynx / New York Liberty as of the 2026-09-12 run, per T2's Handoff
  # Notes), in place of the NBA original's hardcoded BOS-vs-NYK example.
  s1 <- seed(1)
  results$finals <- simulate_single_series(
    team_high = s1$team, team_low = s2$team,
    net_high = get_playoff_adjusted_rating(s1$team, s1$net),
    net_low  = get_playoff_adjusted_rating(s2$team, s2$net),
    n_sims = 10000, format = "bo7"
  )
  message(sprintf(">>> [PLAYOFFS] Finals (Bo7): %s vs %s | %s Series Win: %.1f%% (%+d) | Avg Games: %.2f",
                  s1$team, s2$team, s1$team, results$finals$p_high_seed_win * 100,
                  results$finals$fair_ml_high, results$finals$avg_series_games))

  saveRDS(results, "cache/playoff_series_wnba_demo.rds")
  message(">>> [PLAYOFFS] Saved cache/playoff_series_wnba_demo.rds (list: $first_round, $semifinals, $finals).")
  return(results)
}

# FINDING C-2 (docs/SECURITY_TECHNICAL_REVIEW.md): the guard was
# `if (!interactive() && sys.nframe() == 0)`. The second clause is never satisfied under
# run_full_pipeline.R's run_stage(), which source()s each stage from inside a function
# (sys.nframe() ~10), so this stage logged "[COMPLETED] playoff_simulator.R in 0.02 seconds"
# without ever simulating a series or touching cache/playoff_series_wnba_demo.rds.
# Dropping the sys.nframe() clause leaves `!interactive()` — the guard style already proven
# correct in copula_props_engine.R / rapm_engine.R / risk_management_engine.R.
# (config.R is now sourced at the top of this file rather than here.)
if (!interactive()) {
  invisible(simulate_playoff_suite())
}
