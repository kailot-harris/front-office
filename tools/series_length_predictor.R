# ==============================================================================
# series_length_predictor.R
# Path: tools/series_length_predictor.R
#
# Exact (non-simulated) probability distribution over playoff series length
# (best-of-3 / best-of-5 / best-of-7), e.g. "P(semifinal series goes 4 games)".
#
# ORPHANED PRODUCER (declared 2026-10-23): its only consumer has retired. The
# summary app's bracket tab, which read this script's
# `cache/series_length_predictions.rds`, now lives in a separate repository
# (`kailot-harris/DATA-607-Agentic_Coding-WNBA-Summary`), and that app's stale
# fork in THIS repo has been deleted. So that cache is currently produced here
# and consumed by nothing in this repo. This is expected, not a bug -- the
# orphaned-cache-audit skill will flag the artifact and this note is the answer.
# The producer is kept
# deliberately: it is the only exact (non-Monte-Carlo) series-length model here.
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

# GitHub issue #90: this used to be a hardcoded absolute path to the repo's pre-move
# location, which stopped existing once the repo moved under front-office/ (see that issue
# for the exact string). Because it was guarded by `if (dir.exists(PROJECT_DIR))` it silently
# no-op'd instead of erroring, so the script only ran at all when the caller's CWD already
# happened to be the project root. Derived portably now, the same way
# tools/generate_historical_season_snapshots.R does it, so this tools/ script setwd()s to the
# real project root regardless of where it is invoked from (CLAUDE.md's tools/ convention).
if (!requireNamespace("here", quietly = TRUE)) {
  stop("Package 'here' is required to derive PROJECT_DIR portably. Install it with install.packages('here').")
}
PROJECT_DIR <- here::here()
setwd(PROJECT_DIR)

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

  # mc_result (the full simulate_single_series() return -- p_high_seed_win,
  # fair_ml_high/low, avg_series_games, exact_outcomes, format_label) is kept
  # here, not just the length-only mc_dist summary, so callers that need the
  # actual series win probability (not just its length distribution) don't
  # have to re-simulate a second time.
  list(dp = dp_dist, mc = mc_dist, comparison = comparison, max_abs_diff = round(max_abs_diff, 4),
       mc_result = mc_result)
}

# ------------------------------------------------------------------------------
# Playoff seeding, DERIVED from regular-season standings (GitHub issue #92).
#
# This replaces two hand-maintained constants that used to live here: a
# seed-to-abbreviation tibble for the 2026 field, and a hardcoded list of the
# 2026 Round 1 scorelines (see GitHub issue #92 for the names). Both were
# frozen as of 2026-10-04 -- i.e. at Round 1 -- so by the time the real bracket
# had reached the Finals, anything reading them still rendered a Round-1-era
# bracket with a "Finals (TBD)" box. They were also kept in sync by hand against
# a .qmd, on the premise (recorded in the old comment, and in config.R's own
# CURRENT_SEASON note) that the wehoop feed carried no playoff flag. That premise
# is now false: data/box_scores_cache.rds does carry `season_type`, with 2 =
# regular season and 3 = postseason, empirically verified in
# tools/generate_historical_season_snapshots.R's header. So both the field and
# the results are derivable, and are derived -- here for seeds, and in
# build_playoff_bracket_2026.R for the resolved series.
#
# Seeding rule, applied to `season_type == season_type_filter` games only:
#   1. Win percentage, descending.
#   2. Ties broken by head-to-head record among the tied teams -- this is the
#      WNBA's own first tiebreaker, and it is reconstructable from team-level box
#      scores (unlike the division/conference-record tiebreakers further down the
#      real rulebook, which is why the historical-snapshot script settles for
#      alphabetical instead). It matters in 2026: Indiana and Washington both
#      finished 28-16, and head-to-head (WSH 2-1) is what separates them into the
#      #5 and #6 seeds. Ordering them alphabetically instead would hand out seed
#      numbers that contradict the bracket the league actually played.
#   3. Remaining ties broken by net rating, descending, then team name ascending,
#      so the result is always fully deterministic with no randomness.
#
# The field is the set of teams that actually appear in that season's postseason
# rows, so the bracket size is read off the data rather than assumed to be 8.
# ------------------------------------------------------------------------------
derive_playoff_seeds <- function(season_yr = CURRENT_SEASON, season_type_filter = 2L) {
  if (!file.exists(CACHE_TEAM_BOX)) {
    warning(sprintf(">>> [SERIES LENGTH] %s not found — cannot derive playoff seeds.", CACHE_TEAM_BOX))
    return(NULL)
  }

  box <- readRDS(CACHE_TEAM_BOX)
  # CLAUDE.md: normalize CONN -> CON and drop non-franchise exhibition rows BEFORE
  # aggregating, via daily_ingest.R's shared helper (never a local reimplementation).
  if (!exists("filter_real_franchises")) source("daily_ingest.R")
  box <- filter_real_franchises(box)

  reg  <- box %>% filter(season == season_yr, season_type == season_type_filter)
  post <- box %>% filter(season == season_yr, season_type == 3L)

  if (nrow(reg) == 0 || nrow(post) == 0) {
    warning(sprintf(
      ">>> [SERIES LENGTH] No %d rows for season_type %s / 3 in %s — cannot derive playoff seeds.",
      season_yr, season_type_filter, CACHE_TEAM_BOX))
    return(NULL)
  }

  playoff_abbrs <- sort(unique(post$team_abbreviation))

  standings <- reg %>%
    group_by(team_abbreviation) %>%
    summarise(
      team       = dplyr::first(team_display_name),
      wins       = sum(team_winner == TRUE, na.rm = TRUE),
      losses     = sum(team_winner == FALSE, na.rm = TRUE),
      net_rating = mean(team_score - opponent_team_score),
      .groups = "drop"
    ) %>%
    mutate(win_pct = wins / (wins + losses)) %>%
    filter(team_abbreviation %in% playoff_abbrs)

  # Head-to-head win pct against the other teams tied on win_pct with this team.
  h2h_win_pct <- vapply(standings$team_abbreviation, function(abbr) {
    my_pct <- standings$win_pct[standings$team_abbreviation == abbr]
    tied <- setdiff(standings$team_abbreviation[standings$win_pct == my_pct], abbr)
    if (length(tied) == 0) return(NA_real_)
    g <- reg %>% filter(team_abbreviation == abbr, opponent_team_abbreviation %in% tied)
    if (nrow(g) == 0) return(NA_real_)
    sum(g$team_winner == TRUE, na.rm = TRUE) / nrow(g)
  }, numeric(1))

  seeds <- standings %>%
    mutate(h2h = coalesce(unname(h2h_win_pct), 0)) %>%
    arrange(desc(win_pct), desc(h2h), desc(net_rating), team) %>%
    mutate(seed = row_number()) %>%
    rowwise() %>%
    mutate(net_adj = get_playoff_adjusted_rating(team, net_rating)) %>%
    ungroup() %>%
    select(seed, abbr = team_abbreviation, team, wins, losses, win_pct, net_rating, net_adj)

  message(sprintf(
    ">>> [SERIES LENGTH] Derived %d %d playoff seeds from regular-season standings (season_type == %s): %s.",
    nrow(seeds), season_yr, season_type_filter,
    paste(sprintf("#%d %s", seeds$seed, seeds$abbr), collapse = ", ")))
  seeds
}

# ------------------------------------------------------------------------------
# Backwards-compatible wrapper for the old name. Fail-safe per repo convention:
# the derived path is tried first, and the clearly-labeled placeholder slate is
# kept as the fallback rather than removed, so a missing/empty box-score cache
# degrades instead of crashing.
#
# NOTE ON THE `season_type_filter` DEFAULT (GitHub issue #92): this function used
# to compute net ratings as `filter(season == 2026)` with NO season_type filter,
# so postseason games were pooled into the ratings used to predict postseason
# series. The default is now 2 (regular season only), which is leak-free. The
# archived figures in cache/series_length_predictions.rds were produced by the
# older pooled path and are deliberately NOT regenerated — they are the only
# record of what the model actually said before those series were played, and
# build_playoff_bracket_2026.R copies them verbatim for that reason.
# ------------------------------------------------------------------------------
load_real_2026_playoff_seeds <- function(season_yr = CURRENT_SEASON, season_type_filter = 2L) {
  seeds <- derive_playoff_seeds(season_yr = season_yr, season_type_filter = season_type_filter)
  if (!is.null(seeds) && nrow(seeds) > 0 && !any(is.na(seeds$net_rating))) {
    return(seeds)
  }

  warning(">>> [SERIES LENGTH] FALLBACK: playoff seeds could not be derived from real data — using a clearly-labeled placeholder slate. Any number downstream of this is synthetic.")
  tibble(
    seed = 1:8,
    abbr = c("MIN", "GS", "LV", "ATL", "WSH", "IND", "DAL", "NY"),
    team = c("Minnesota Lynx", "Golden State Valkyries", "Las Vegas Aces", "Atlanta Dream",
             "Washington Mystics", "Indiana Fever", "Dallas Wings", "New York Liberty"),
    wins = rep(NA_integer_, 8), losses = rep(NA_integer_, 8), win_pct = rep(NA_real_, 8),
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
run_series_length_demo <- function(overwrite = FALSE) {
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
         distribution = dist, crossvalidation = xval, bo3_breakdown = breakdown,
         # Full series object (p_high_seed_win, fair_ml_high/low, avg_series_games,
         # format_label, exact_outcomes) -- same shape playoff_simulator.R's own
         # demo suite produces -- so a consumer (e.g. the summary app's bracket
         # tab, which now lives in the sibling repo
         # `kailot-harris/DATA-607-Agentic_Coding-WNBA-Summary`) can read a real
         # win probability for this REAL confirmed matchup without re-simulating.
         series = xval$mc_result)
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
    # `round1_results` used to be a hardcoded list of 2026 Round 1 scorelines. Resolved
    # results are no longer this script's job: they are derived from box scores by
    # build_playoff_bracket_2026.R into CACHE_PLAYOFF_BRACKET_CURRENT, which stays current
    # as the bracket advances instead of freezing at whatever round it was written in.
    round1_results      = NULL,
    round1_results_note = sprintf(
      "Resolved series results are derived from box scores into %s by build_playoff_bracket_2026.R.",
      basename(CACHE_PLAYOFF_BRACKET_CURRENT)),
    first_round_example = run_round(s4, s5, "bo3", "Round 1 example (Bo3): Atlanta Dream vs Washington Mystics"),
    semifinal_atl_ny    = run_round(s4, s8, "bo5", "Semifinals (Bo5): Atlanta Dream vs New York Liberty"),
    semifinal_gs_lv     = run_round(s2, s3, "bo5", "Semifinals (Bo5): Golden State Valkyries vs Las Vegas Aces"),
    finals = NULL
  )
  results$finals_note <- "Finals matchup undetermined pending both semifinal series — not simulated."
  results$generated_at <- Sys.time()

  # ARCHIVE PROTECTION (GitHub issue #92). cache/series_length_predictions.rds holds the
  # ONLY archived record in this repo of what the model said about a series BEFORE it was
  # played: the two 2026 semifinal forecasts, generated 2026-10-04. This function overwrites
  # that file in place and keeps no history, so re-running it after the series resolved would
  # silently replace a genuine pre-game forecast with a post-hoc recomputation. That record
  # is the point, so the overwrite is now opt-in rather than the default.
  out_path <- "cache/series_length_predictions.rds"
  if (file.exists(out_path) && !isTRUE(overwrite)) {
    message(sprintf(
      paste0(">>> [SERIES LENGTH] NOT writing %s — it already exists and holds the archived ",
             "pre-game forecast record. Pass overwrite = TRUE to replace it deliberately."),
      out_path))
  } else {
    saveRDS(results, out_path)
    message(">>> [SERIES LENGTH] Saved cache/series_length_predictions.rds (list: $round1_results=NULL, $round1_results_note, $first_round_example, $semifinal_atl_ny, $semifinal_gs_lv, $finals=NULL, $finals_note).")
  }

  invisible(results)
}

# Auto-run guard. Sourcing this file for its functions alone (e.g.
# build_playoff_bracket_2026.R needs series_length_distribution()) must not fire the demo,
# which re-simulates every series and -- see ARCHIVE PROTECTION above -- targets the archived
# forecast file. Set WNBA_SERIES_LENGTH_NO_AUTORUN=1 to source this as a library.
if (!interactive() && !identical(Sys.getenv("WNBA_SERIES_LENGTH_NO_AUTORUN"), "1")) {
  invisible(run_series_length_demo())
}
