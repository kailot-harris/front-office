# ==============================================================================
# series_length_predictor.R
# Path: tools/series_length_predictor.R
#
# Exact (non-simulated) probability distribution over playoff series length
# (best-of-3 / best-of-5 / best-of-7), e.g. "P(semifinal series goes 4 games)".
#
# This is deliberately NOT built on top of playoff_simulator.R's Monte Carlo
# loop. The series-length state space is tiny (at most win_threshold^2 states,
# <=16 for a bo7), so it is computed exactly via dynamic programming over
# (wins_high, wins_low) instead of sampled — series_length_distribution() below
# is the production source of truth. simulate_single_series() (sourced from
# playoff_simulator.R, unmodified) is invoked only inside
# crossvalidate_series_length() as an optional sanity check against DP, never
# as the primary calculation.
#
# Reuses, never restates: PLAYOFF_FORMATS / simulate_single_series() /
# get_playoff_adjusted_rating() from playoff_simulator.R, and
# WNBA_MARGIN_SIGMA / WNBA_HCA from config.R.
# ==============================================================================

PROJECT_DIR <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
})

if (!exists("WNBA_MARGIN_SIGMA") || !exists("WNBA_HCA")) source("config.R")
if (!exists("PLAYOFF_FORMATS") || !exists("simulate_single_series")) source("playoff_simulator.R")

.LOG_SCRIPT <- "series_length_predictor.R"
message(">>> [SERIES LENGTH] Initializing Exact Series-Length Distribution Engine (DP)...")

# ------------------------------------------------------------------------------
# Exact DP: P(series length = N) for a given format and matchup.
# ------------------------------------------------------------------------------
# State = (w_high, w_low) wins-so-far, not yet decided. Next game number to be
# played from that state is g = w_high + w_low + 1, whose host (and therefore
# whose pnorm() win probability applies) comes from
# PLAYOFF_FORMATS[[format]]$home_flags[g] — the SAME two formulas
# simulate_single_series() uses (playoff_simulator.R lines 122-123), just
# enumerated exactly instead of sampled with runif().
#
# Terminal mass is routed directly into length_probs[[total_games]] the instant
# either side reaches win_threshold, rather than written back into the live
# state table and mopped up afterward — this guarantees
# sum(length_probs) == 1 exactly (up to floating point) with no leftover mass,
# since every format's win_threshold/max_games pairing forces the series to
# finish by max_games.
series_length_distribution <- function(team_high, team_low, net_high, net_low,
                                        format = "bo7", hca_pts = WNBA_HCA) {
  if (!format %in% names(PLAYOFF_FORMATS)) {
    stop(sprintf("Unknown playoff format '%s' — must be one of: %s", format, paste(names(PLAYOFF_FORMATS), collapse = ", ")))
  }
  fmt <- PLAYOFF_FORMATS[[format]]
  home_high_flags <- fmt$home_flags
  win_threshold    <- fmt$win_threshold
  max_games        <- length(home_high_flags)

  rating_diff <- net_high - net_low
  p_high_home <- pnorm((rating_diff + hca_pts) / WNBA_MARGIN_SIGMA)
  p_high_away <- pnorm((rating_diff - hca_pts) / WNBA_MARGIN_SIGMA)

  # dp[i, j] = probability of reaching the live (not-yet-decided) state
  # (w_high = i-1, w_low = j-1). 1-indexed because R matrices have no index 0.
  dp <- matrix(0, nrow = win_threshold, ncol = win_threshold)
  dp[1, 1] <- 1
  length_probs <- setNames(numeric(max_games), as.character(seq_len(max_games)))

  for (w_high in 0:(win_threshold - 1)) {
    for (w_low in 0:(win_threshold - 1)) {
      p_mass <- dp[w_high + 1, w_low + 1]
      if (p_mass == 0) next

      g <- w_high + w_low + 1
      if (g > max_games) next # unreachable given win_threshold/max_games pairing; defensive only
      p_g <- if (home_high_flags[g]) p_high_home else p_high_away

      if (w_high + 1 == win_threshold) {
        len <- as.character(w_high + 1 + w_low)
        length_probs[[len]] <- length_probs[[len]] + p_mass * p_g
      } else {
        dp[w_high + 2, w_low + 1] <- dp[w_high + 2, w_low + 1] + p_mass * p_g
      }

      if (w_low + 1 == win_threshold) {
        len <- as.character(w_high + w_low + 1)
        length_probs[[len]] <- length_probs[[len]] + p_mass * (1 - p_g)
      } else {
        dp[w_high + 1, w_low + 2] <- dp[w_high + 1, w_low + 2] + p_mass * (1 - p_g)
      }
    }
  }

  # Math invariant (not a data fail-safe) — a hard stop here is appropriate,
  # unlike the file-missing fail-safes elsewhere in this repo.
  stopifnot(abs(sum(length_probs) - 1) < 1e-9)

  length_probs <- length_probs[length_probs > 0]
  tibble(
    length = as.integer(names(length_probs)),
    label = paste0(names(length_probs), " games"),
    probability = round(as.numeric(length_probs), 6)
  ) %>%
    arrange(length)
}

# ------------------------------------------------------------------------------
# bo3-specific game-by-game breakdown: answers "how do you break a best-of-3
# series into game-by-game predictions" directly, rather than leaving it
# implicit inside the generic DP above.
# ------------------------------------------------------------------------------
bo3_game_by_game_breakdown <- function(net_high, net_low, hca_pts = WNBA_HCA) {
  fmt <- PLAYOFF_FORMATS[["bo3"]]
  stopifnot(identical(fmt$home_flags, c(TRUE, FALSE, TRUE)))

  rating_diff <- net_high - net_low
  p_high_home <- pnorm((rating_diff + hca_pts) / WNBA_MARGIN_SIGMA)
  p_high_away <- pnorm((rating_diff - hca_pts) / WNBA_MARGIN_SIGMA)

  p1 <- p_high_home # Game 1: high seed hosts
  p2 <- p_high_away # Game 2: low seed hosts (high seed is the road team)
  p3 <- p_high_home # Game 3 (if necessary): high seed hosts again

  p_length_2 <- p1 * p2 + (1 - p1) * (1 - p2)
  p_length_3 <- 1 - p_length_2

  paths <- tibble(
    path = c("High sweeps (W-W)", "Low sweeps (L-L)",
             "Split, High wins G3 (W-L-W or L-W-W)", "Split, Low wins G3 (W-L-L or L-W-L)"),
    probability = c(
      p1 * p2,
      (1 - p1) * (1 - p2),
      (p1 * (1 - p2) + (1 - p1) * p2) * p3,
      (p1 * (1 - p2) + (1 - p1) * p2) * (1 - p3)
    ),
    length = c(2L, 2L, 3L, 3L)
  )
  stopifnot(abs(sum(paths$probability) - 1) < 1e-9)

  list(p1 = p1, p2 = p2, p3 = p3, paths = paths,
       p_length_2 = p_length_2, p_length_3 = p_length_3)
}

# ------------------------------------------------------------------------------
# Cross-check: DP distribution vs. the EXISTING, unmodified Monte Carlo
# simulate_single_series(). DP remains sole source of truth; this function is
# only a sanity check, invoked here and nowhere else.
# ------------------------------------------------------------------------------
crossvalidate_series_length <- function(team_high, team_low, net_high, net_low,
                                         format = "bo7", hca_pts = WNBA_HCA,
                                         n_sims = 10000, tolerance = 0.02) {
  dp_dist <- series_length_distribution(team_high, team_low, net_high, net_low, format, hca_pts)

  mc_result <- simulate_single_series(team_high, team_low, net_high, net_low,
                                       n_sims = n_sims, hca_pts = hca_pts, format = format)

  # Soft coupling: relies on simulate_single_series()'s exact
  # paste0(team_high, " ", high_w, "-", low_w, " ", team_low) scoreline format
  # (playoff_simulator.R line ~165). Parsed from the string rather than
  # re-derived from win_threshold assumptions, so this only breaks if that
  # exact format changes.
  scoreline_games <- mc_result$exact_outcomes %>%
    mutate(
      high_w = as.integer(sub("^.*?(\\d+)-(\\d+).*$", "\\1", scoreline)),
      low_w  = as.integer(sub("^.*?(\\d+)-(\\d+).*$", "\\2", scoreline)),
      total_games = high_w + low_w
    )

  mc_dist <- scoreline_games %>%
    group_by(length = total_games) %>%
    summarise(p_mc = sum(prob_pct) / 100, .groups = "drop")

  comparison <- dp_dist %>%
    select(length, p_dp = probability) %>%
    full_join(mc_dist, by = "length") %>%
    mutate(
      p_dp = coalesce(p_dp, 0),
      p_mc = coalesce(p_mc, 0),
      abs_diff = abs(p_dp - p_mc)
    ) %>%
    arrange(length)

  max_abs_diff <- max(comparison$abs_diff)
  if (max_abs_diff > tolerance) {
    message(sprintf(
      ">>> [SERIES LENGTH] WARNING: DP/MC mismatch for %s vs %s (%s) exceeds tolerance: max |DP-MC| = %.4f (tolerance %.4f)",
      team_high, team_low, format, max_abs_diff, tolerance
    ))
  }

  list(dp = dp_dist, mc = mc_dist, comparison = comparison, max_abs_diff = round(max_abs_diff, 4))
}

# ------------------------------------------------------------------------------
# Real confirmed 2026 playoff field (NOT cache/projected_wnba_standings.rds —
# per WNBA_2026_Postseason_Predictions.qmd lines 217-224, that cache is a
# forward-looking MID-SEASON projection, and does not reflect which 8 teams
# actually made the playoffs or Round 1's real results. Once games have
# actually been played, net rating should come from real per-game point
# differential in CACHE_TEAM_BOX (data/box_scores_cache.rds), the same source
# and formula the postseason report uses (qmd lines 226-245).
#
# Seeds/abbreviations below are the verified 2026 bracket (qmd lines 211-213,
# cross-checked against Yahoo/CBS/NBC Sports): #1 MIN, #2 GS, #3 LV, #4 ATL,
# #5 WSH, #6 IND, #7 DAL, #8 NY. Round 1 is complete; the real confirmed
# semifinal pairings (qmd lines 335-336) are (4) Atlanta Dream vs (8) New York
# Liberty, and (2) Golden State Valkyries vs (3) Las Vegas Aces — NOT a
# generic "seed 2 vs seed 3" pairing, since Round 1 upsets (Minnesota, the #1
# seed, lost) mean the bracket's fixed #1-vs-#8 / #4-vs-#5 and #2-vs-#7 /
# #3-vs-#6 halves do not collapse to adjacent seed numbers.
# ------------------------------------------------------------------------------
REAL_2026_BRACKET <- tibble(
  seed = 1:8,
  abbr = c("MIN", "GS", "LV", "ATL", "WSH", "IND", "DAL", "NY")
)

load_real_2026_playoff_seeds <- function() {
  if (file.exists(CACHE_TEAM_BOX)) {
    box <- readRDS(CACHE_TEAM_BOX)
    net_real <- box %>%
      filter(season == 2026) %>%
      group_by(team_abbreviation) %>%
      summarise(net_rating = mean(team_score - opponent_team_score), .groups = "drop")

    seeds <- REAL_2026_BRACKET %>%
      mutate(team = unname(WNBA_TEAMS[abbr])) %>%
      left_join(net_real, by = c("abbr" = "team_abbreviation"))

    if (!any(is.na(seeds$net_rating))) {
      seeds <- seeds %>%
        rowwise() %>%
        mutate(net_adj = get_playoff_adjusted_rating(team, net_rating)) %>%
        ungroup()
      message(sprintf(">>> [SERIES LENGTH] Loaded real 2026 net ratings from %s for all 8 playoff teams.", CACHE_TEAM_BOX))
      return(seeds)
    }
    warning(">>> [SERIES LENGTH] CACHE_TEAM_BOX is missing 2026 rows for one or more of the 8 real playoff teams — falling back to a plausible placeholder slate instead.")
  } else {
    warning(sprintf(">>> [SERIES LENGTH] %s not found — falling back to a plausible placeholder slate instead.", CACHE_TEAM_BOX))
  }

  tibble(
    seed = 1:8,
    abbr = c("MIN", "GS", "LV", "ATL", "WSH", "IND", "DAL", "NY"),
    team = c("Minnesota Lynx", "Golden State Valkyries", "Las Vegas Aces", "Atlanta Dream",
             "Washington Mystics", "Indiana Fever", "Dallas Wings", "New York Liberty"),
    net_rating = c(12.1, 8.4, 6.0, 4.2, 1.5, 3.0, -2.0, 5.5),
    net_adj = c(12.1, 8.4, 6.0, 4.2, 1.5, 3.0, -2.0, 5.5)
  )
}

# ------------------------------------------------------------------------------
# Convenience wrapper: resolve two real bracket seeds -> net ratings via
# load_real_2026_playoff_seeds(), then run the DP.
# ------------------------------------------------------------------------------
predict_series_length <- function(seed_high, seed_low, format = "bo7", hca_pts = WNBA_HCA, seeds = NULL) {
  if (is.null(seeds)) seeds <- load_real_2026_playoff_seeds()

  row_of <- function(s) {
    row <- seeds %>% filter(seed == s)
    if (nrow(row) == 0) stop(sprintf("Seed %s not found in bracket.", s))
    row
  }
  high <- row_of(seed_high)
  low  <- row_of(seed_low)

  dist <- series_length_distribution(high$team[1], low$team[1], high$net_adj[1], low$net_adj[1], format, hca_pts)
  attr(dist, "team_high") <- high$team[1]
  attr(dist, "team_low") <- low$team[1]
  attr(dist, "net_high_adj") <- high$net_adj[1]
  attr(dist, "net_low_adj") <- low$net_adj[1]
  dist
}

# ------------------------------------------------------------------------------
# Demo / auto-run: the REAL confirmed 2026 matchups, not a generic rank-based
# pairing. Round 1 is complete, so it is shown as a worked historical example
# of the bo3 game-by-game breakdown; both real confirmed semifinal pairings
# are run (Round 2 is not yet decided, so both get simulated); the Finals
# matchup is genuinely undetermined pending the semifinals, so it is reported
# as TBD rather than fabricated.
# ------------------------------------------------------------------------------
run_series_length_demo <- function() {
  seeds <- load_real_2026_playoff_seeds()

  seed_row <- function(s) {
    row <- seeds %>% filter(seed == s)
    list(team = row$team[1], net = row$net_rating[1], net_adj = row$net_adj[1])
  }

  run_round <- function(high, low, format, label) {
    net_high_adj <- high$net_adj
    net_low_adj  <- low$net_adj

    dist <- series_length_distribution(high$team, low$team, net_high_adj, net_low_adj, format = format)
    xval <- crossvalidate_series_length(high$team, low$team, net_high_adj, net_low_adj, format = format)
    breakdown <- if (format == "bo3") bo3_game_by_game_breakdown(net_high_adj, net_low_adj) else NULL

    cat(sprintf("\n--- %s ---\n", label))
    if (!is.null(breakdown)) {
      cat(sprintf("  Game 1 (host: %s): p(%s wins) = %.3f\n", high$team, high$team, breakdown$p1))
      cat(sprintf("  Game 2 (host: %s): p(%s wins) = %.3f\n", low$team, high$team, breakdown$p2))
    }
    for (i in seq_len(nrow(dist))) {
      cat(sprintf("  P(length=%d) = %.3f\n", dist$length[i], dist$probability[i]))
    }
    if (format == "bo5") {
      len4 <- dist$probability[dist$length == 4]
      len5 <- dist$probability[dist$length == 5]
      cat(sprintf(">>> P(%s vs %s series goes 4 games) = %.1f%%\n", high$team, low$team, if (length(len4)) len4 * 100 else 0))
      cat(sprintf(">>> P(%s vs %s series goes 5 games) = %.1f%%\n", high$team, low$team, if (length(len5)) len5 * 100 else 0))
    }
    cat(sprintf("  Cross-check vs Monte Carlo (n=10000): max |DP - MC| = %.4f%s\n",
                xval$max_abs_diff, if (xval$max_abs_diff > 0.02) " (WARNING: exceeds tolerance)" else " (within tolerance)"))

    list(format = format, team_high = high$team, team_low = low$team,
         net_high_adj = net_high_adj, net_low_adj = net_low_adj,
         distribution = dist, crossvalidation = xval, bo3_breakdown = breakdown)
  }

  # Real bracket seeds (qmd lines 211-213): #1 MIN, #2 GS, #3 LV, #4 ATL, #5 WSH,
  # #6 IND, #7 DAL, #8 NY. Round 1 pairs were #1v8, #2v7, #3v6, #4v5 (no reseeding).
  s2 <- seed_row(2); s3 <- seed_row(3); s4 <- seed_row(4); s5 <- seed_row(5); s8 <- seed_row(8)

  cat("\n>>> [SERIES LENGTH] Round 1 is complete; shown below as a worked historical example of\n")
  cat(">>> the bo3 game-by-game breakdown (not a live prediction). Real confirmed semifinal\n")
  cat(">>> pairings per Round 1's actual results: (4) Atlanta Dream vs (8) New York Liberty, and\n")
  cat(">>> (2) Golden State Valkyries vs (3) Las Vegas Aces. The Finals matchup is undetermined\n")
  cat(">>> pending both semifinal series, so it is NOT simulated here (no fabricated matchup).\n")

  results <- list(
    first_round_example = run_round(s4, s5, "bo3", "Round 1 example (Bo3): Atlanta Dream vs Washington Mystics"),
    semifinal_atl_ny    = run_round(s4, s8, "bo5", "Semifinals (Bo5): Atlanta Dream vs New York Liberty"),
    semifinal_gs_lv     = run_round(s2, s3, "bo5", "Semifinals (Bo5): Golden State Valkyries vs Las Vegas Aces"),
    finals = NULL
  )
  results$finals_note <- "Finals matchup undetermined pending both semifinal series — not simulated."
  results$generated_at <- Sys.time()

  saveRDS(results, "cache/series_length_predictions.rds")
  message(">>> [SERIES LENGTH] Saved cache/series_length_predictions.rds (list: $first_round_example, $semifinal_atl_ny, $semifinal_gs_lv, $finals=NULL, $finals_note).")

  invisible(results)
}

if (!interactive()) {
  invisible(run_series_length_demo())
}
