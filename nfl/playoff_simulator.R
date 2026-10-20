# ==============================================================================
# NFL Playoff Bracket Simulator
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/playoff_simulator.R
#
# Phase 4, Task P4-A (docs/task_assignments_phase3.md). Genuinely new bracket-advancement
# logic, NOT a port of the WNBA sibling repo's playoff_simulator.R: that file models
# best-of-N (3/5/7) series with a fixed home-game schedule per round. The NFL playoffs are
# single-elimination with a RESEEDING bracket (no fixed tree), which is a structurally
# different simulation problem, not a parameter swap on the WNBA file's approach.
#
# ------------------------------------------------------------------------------------------
# LIVE-VERIFIED PLAYOFF STRUCTURE (web search, 2026-09-16 - see config.R's own
# NFL_PLAYOFF_FIELD / NFL_PLAYOFF_BYES_PER_CONF comment block for the 14-team / bye-allocation
# verification; the facts below are the ADDITIONAL rules this script itself needed verified):
#
#   1. Reseeding (not a fixed bracket tree): confirmed via si.com ("Does the NFL Reseed After
#      Each Round? Playoff Format Explained") and nbcnewyork.com's playoff-bracket explainer -
#      "the NFL reseeds in the playoffs... the top-seeded teams will face the lowest-seeded
#      teams left in their respective conferences following the opening round... the four
#      surviving teams in each conference are reseeded by their original regular-season seed,
#      and matchups are assigned fresh, with the highest surviving seed always hosting the
#      lowest." This is UNIQUE to the NFL among major US leagues (no static bracket path) -
#      confirmed still true for the 2026 postseason as of this verification date.
#   2. Only the #1 seed per conference gets a first-round (Wild Card) bye - already verified
#      in config.R's NFL_PLAYOFF_BYES_PER_CONF comment; re-cited here since it directly drives
#      this script's bracket-advancement logic (a #1 seed has no "Wild Card win" event to
#      simulate - it advances to the Divisional round automatically).
#   3. Higher remaining seed always hosts, at every round through the Conference Championship -
#      same sources as (1) above.
#   4. The Super Bowl is played at a fixed, pre-selected NEUTRAL site with NO home team -
#      confirmed via sportsgeardaily.com ("the game is played at a neutral site selected years
#      in advance... Neither of the two competing teams has home-field advantage by default,
#      regardless of conference or regular-season record") and the 2026 Super Bowl's own site
#      (Levi's Stadium, home of a team not necessarily in the game). Accordingly, unlike every
#      other round, the Super Bowl game below applies NO NFL_HCA adjustment to either side.
#
# Bracket-advancement rules implemented (per conference, then a single cross-conference game):
#   Wild Card:      seed 2 vs 7, seed 3 vs 6, seed 4 vs 5 (#1 seed byes).
#   Divisional:     remaining 4 seeds (1 + the 3 Wild Card winners) are RESEEDED - sorted by
#                   original seed - and paired best-vs-worst, 2nd-best-vs-2nd-worst.
#   Conf. Champ.:   the two Divisional-round winners, higher remaining seed hosts.
#   Super Bowl:     the two Conference Champions (cross-conference), neutral site, no HCA term.
#
# ------------------------------------------------------------------------------------------
# REAL CURRENT PLAYOFF FIELD - REAL NFL TIEBREAKER PROCEDURE (updated 2026-09-17; read before
# trusting the output as "the" playoff picture):
#
# This script determines each of the 32 real NFL_TEAMS' win% from REAL completed
# CACHE_SCHEDULES games for CURRENT_SEASON (config.R), REG season only. Division winners
# (seeds 1-4 per conference) = the team with the best record in each of NFL_DIVISIONS' 8
# groups, ties broken via nfl_tiebreakers.R's resolve_division_ties() (head-to-head, division
# record, common games, conference record, strength of victory/schedule, combined point
# rankings, net points - the NFL's real official multi-step procedure). Wildcards (seeds 5-7)
# = the next-3 best remaining conference teams, ties broken via resolve_wildcard_ties() (same
# idea, wild-card-specific ordering, plus the same-division-representative reduction step).
# See nfl_tiebreakers.R's own header for the full verified procedure, the cascade/restart rule,
# and two explicitly documented scope limitations (net touchdowns and coin toss are not
# modeled - both fall back to alphabetical order, which only matters in the exceedingly rare
# case every other real criterion above them ties exactly). Treat the resulting seed order as
# a faithful application of the real tiebreaker rules to this repo's own game log, not as a
# league-office-certified result - especially early in a season when few games have been
# played and the deeper tiebreak criteria (common games, SOV/SOS) are themselves noisy.
#
# A run during an in-progress (incomplete) season - the expected/normal case, not an error
# condition - therefore produces a real-but-PROVISIONAL field and simulation based on
# in-progress records. This is documented behavior, not a bug: re-run later in the season (or
# after it completes) for a less noisy field. A team with 0 completed games (e.g. a run before
# Week 1 kicks off) gets win_pct = NA and is sorted last within its group rather than crashing
# the seeding computation.
#
# Win probability for every simulated game (except the neutral-site Super Bowl) comes from
# team_ratings_engine.R's real power_rating column in CACHE_TEAM_RATINGS combined with
# config.R's NFL_HCA / NFL_MARGIN_SIGMA - see that script's header for the power_rating
# derivation (rolling EPA/play, scaled to a projected point margin). This script never
# hardcodes NFL_HCA/NFL_MARGIN_SIGMA's values - it only ever references the config.R symbols.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "playoff_simulator.R"

# Real NFL tiebreaker procedures (head-to-head, division/conference record, common games,
# strength of victory/schedule, combined point rankings, net points) - see nfl_tiebreakers.R's
# own header for the full verified procedure, cascade rule, and documented scope limitations
# (net touchdowns / coin toss are not modeled - alphabetical fallback, exceedingly rare in
# practice). Replaces this file's PRE-2026-09-17 simplified win%->games_played->alphabetical
# tiebreak.
source("nfl_tiebreakers.R")

# ------------------------------------------------------------------------------------------
# .seed_conference(): given the full 32-team records table (with conference/division attached)
# plus the per-team-per-game log, and a target conference ("AFC"/"NFC"), returns a 7-row
# data.frame with seed 1-7, team, division, win_pct, games_played, role. Division winners are
# the best-by-real-tiebreak team in each division; ties among division winners for seed ORDER
# (they've already made the playoffs - this only affects seeding 1-4) use the wild-card
# procedure, since by definition they're from different divisions. Wildcards (seeds 5-7) are
# the next-best remaining conference teams by the same wild-card procedure.
# ------------------------------------------------------------------------------------------
.seed_conference <- function(records, game_log, conf) {
  conf_teams <- records |> filter(conference == conf)

  division_winners <- conf_teams |>
    group_by(division) |>
    group_modify(~ {
      ordered <- order_by_record(.x, resolve_division_ties, game_log, records)
      ordered |> slice(1)
    }) |>
    ungroup()

  division_winners <- order_by_record(division_winners, resolve_wildcard_ties, game_log, records) |>
    mutate(seed = row_number(), role = "division_winner")

  remaining <- conf_teams |> filter(!team %in% division_winners$team)
  wildcards <- order_by_record(remaining, resolve_wildcard_ties, game_log, records) |>
    slice(1:NFL_PLAYOFF_WILDCARDS_PER_CONF) |>
    mutate(seed = NFL_PLAYOFF_DIVISION_WINNERS_PER_CONF + row_number(), role = "wildcard")

  bind_rows(division_winners, wildcards) |>
    arrange(seed) |>
    select(seed, team, conference, division, win_pct, games_played, role)
}

# ------------------------------------------------------------------------------------------
# .simulate_conference_round(): one game between two seeds. `high_seed`/`low_seed` are seed
# NUMBERS (lower number = higher/better seed = home team, per the live-verified "higher
# remaining seed always hosts" rule). `apply_hca` = FALSE only for the neutral-site Super Bowl.
# Returns the WINNING seed number.
# ------------------------------------------------------------------------------------------
.simulate_game <- function(high_seed, low_seed, rating_by_seed, apply_hca = TRUE) {
  hca <- if (apply_hca) NFL_HCA else 0
  rating_diff <- rating_by_seed[[as.character(high_seed)]] - rating_by_seed[[as.character(low_seed)]]
  p_high_win <- pnorm((rating_diff + hca) / NFL_MARGIN_SIGMA)
  if (runif(1) < p_high_win) high_seed else low_seed
}

# ------------------------------------------------------------------------------------------
# .simulate_bracket(): runs N_SIMULATIONS full brackets (both conferences + Super Bowl),
# tracking each team's count of Wild Card / Divisional / Conference Championship / Super Bowl
# wins. Returns a named list of count vectors keyed by team abbreviation.
# ------------------------------------------------------------------------------------------
.simulate_bracket <- function(seed_tables, n_sims) {
  all_teams <- unlist(lapply(seed_tables, function(x) x$team), use.names = FALSE)
  mk_counts <- function() setNames(integer(length(all_teams)), all_teams)

  wc_wins   <- mk_counts()
  div_wins  <- mk_counts()
  cc_wins   <- mk_counts()
  sb_wins   <- mk_counts()

  # Per-conference lookup: seed number -> team abbrev, and seed number -> rating.
  seed_to_team   <- lapply(seed_tables, function(x) setNames(x$team, as.character(x$seed)))
  seed_to_rating <- lapply(seed_tables, function(x) setNames(x$power_rating, as.character(x$seed)))

  wc_matchups <- list(c(2, 7), c(3, 6), c(4, 5))

  for (i in seq_len(n_sims)) {
    conf_champion_seed <- list()

    for (conf in names(seed_tables)) {
      rating_by_seed <- seed_to_rating[[conf]]
      s2t <- seed_to_team[[conf]]

      # Wild Card round (#1 seed byes - no game, no wc_wins increment for it).
      wc_winner_seeds <- integer(0)
      for (m in wc_matchups) {
        w <- .simulate_game(m[1], m[2], rating_by_seed, apply_hca = TRUE)
        wc_wins[[s2t[[as.character(w)]]]] <- wc_wins[[s2t[[as.character(w)]]]] + 1L
        wc_winner_seeds <- c(wc_winner_seeds, w)
      }

      # Divisional round: reseed remaining 4 (1 + three WC winners) by original seed,
      # pair best-vs-worst and 2nd-best-vs-2nd-worst (live-verified reseeding rule).
      remaining <- sort(c(1L, wc_winner_seeds))
      div_pairs <- list(c(remaining[1], remaining[4]), c(remaining[2], remaining[3]))
      div_winner_seeds <- integer(0)
      for (m in div_pairs) {
        w <- .simulate_game(m[1], m[2], rating_by_seed, apply_hca = TRUE)
        div_wins[[s2t[[as.character(w)]]]] <- div_wins[[s2t[[as.character(w)]]]] + 1L
        div_winner_seeds <- c(div_winner_seeds, w)
      }

      # Conference Championship: the two Divisional winners, higher seed hosts.
      cc_high <- min(div_winner_seeds); cc_low <- max(div_winner_seeds)
      w <- .simulate_game(cc_high, cc_low, rating_by_seed, apply_hca = TRUE)
      cc_wins[[s2t[[as.character(w)]]]] <- cc_wins[[s2t[[as.character(w)]]]] + 1L
      conf_champion_seed[[conf]] <- w
    }

    # Super Bowl: cross-conference, neutral site, NO NFL_HCA (see header verification).
    confs <- names(seed_tables)
    afc_team <- seed_to_team[[confs[1]]][[as.character(conf_champion_seed[[confs[1]]])]]
    nfc_team <- seed_to_team[[confs[2]]][[as.character(conf_champion_seed[[confs[2]]])]]
    afc_rating <- seed_to_rating[[confs[1]]][[as.character(conf_champion_seed[[confs[1]]])]]
    nfc_rating <- seed_to_rating[[confs[2]]][[as.character(conf_champion_seed[[confs[2]]])]]
    p_afc_win <- pnorm((afc_rating - nfc_rating) / NFL_MARGIN_SIGMA)  # no HCA - neutral site
    sb_winner <- if (runif(1) < p_afc_win) afc_team else nfc_team
    sb_wins[[sb_winner]] <- sb_wins[[sb_winner]] + 1L
  }

  list(wc_wins = wc_wins, div_wins = div_wins, cc_wins = cc_wins, sb_wins = sb_wins)
}

# ------------------------------------------------------------------------------------------
# run_playoff_simulator()
#
# Sole exposed entry point (per docs/task_assignments_phase3.md's Interface Contract). No
# required args. Reads CACHE_TEAM_RATINGS + CACHE_SCHEDULES (never writes either). Writes
# cache/playoff_simulation.rds via CACHE_PLAYOFF_SIMULATION (added to config.R as a narrow
# documented exception - see that file's comment above it). Returns TRUE on success, FALSE on
# failure (mirrors run_team_ratings()'s non-stop()ping contract for run_full_pipeline.R's
# run_stage()).
# ------------------------------------------------------------------------------------------
run_playoff_simulator <- function() {
  log_info("Starting NFL playoff bracket simulator...")

  result <- tryCatch({
    if (!file.exists(CACHE_TEAM_RATINGS)) {
      log_error("CACHE_TEAM_RATINGS does not exist - run_team_ratings() must run before run_playoff_simulator().",
                call = "run_playoff_simulator()")
      return(FALSE)
    }
    if (!file.exists(CACHE_SCHEDULES)) {
      log_error("CACHE_SCHEDULES does not exist - ingestion must run before run_playoff_simulator().",
                call = "run_playoff_simulator()")
      return(FALSE)
    }

    team_ratings <- readRDS(CACHE_TEAM_RATINGS)
    sch          <- readRDS(CACHE_SCHEDULES)

    # ---- Real current field: win% + full game log per team, conference/division from NFL_DIVISIONS ----
    tiebreak_data <- build_tiebreak_data(sch)
    records  <- tiebreak_data$records
    game_log <- tiebreak_data$game_log
    conf_div <- NFL_DIVISIONS[records$team]
    records$conference <- sub(" .*$", "", conf_div)
    records$division   <- conf_div

    if (any(is.na(records$conference))) {
      missing <- records$team[is.na(records$conference)]
      log_error(sprintf("NFL_DIVISIONS missing entries for: %s - cannot seed playoff field.",
                         paste(missing, collapse = ", ")), call = "run_playoff_simulator()")
      return(FALSE)
    }

    afc_seeds <- .seed_conference(records, game_log, "AFC")
    nfc_seeds <- .seed_conference(records, game_log, "NFC")

    # ---- Attach real power ratings (with a documented, logged fallback for any missing team) ----
    rating_lookup <- setNames(team_ratings$power_rating, team_ratings$team)
    league_mean_rating <- mean(team_ratings$power_rating, na.rm = TRUE)
    if (!is.finite(league_mean_rating)) league_mean_rating <- 0

    attach_ratings <- function(seed_tbl) {
      seed_tbl$power_rating <- vapply(seed_tbl$team, function(tm) {
        r <- rating_lookup[[tm]]
        if (is.null(r) || length(r) == 0 || is.na(r)) {
          log_warn(sprintf("No power_rating for playoff team %s - using league mean (%.2f) as fallback.",
                            tm, league_mean_rating), call = "run_playoff_simulator()")
          league_mean_rating
        } else {
          r
        }
      }, numeric(1))
      seed_tbl
    }

    afc_seeds <- attach_ratings(afc_seeds)
    nfc_seeds <- attach_ratings(nfc_seeds)

    field <- bind_rows(afc_seeds, nfc_seeds)
    log_info(sprintf("Determined real 14-team playoff field for season %d (provisional if season incomplete): %s",
                      CURRENT_SEASON,
                      paste(sprintf("%s#%d(%s)", field$team, field$seed, field$conference), collapse = ", ")),
             call = "run_playoff_simulator()")

    # ---- Monte Carlo simulate the full reseeding bracket ----
    seed_tables <- list(AFC = afc_seeds, NFC = nfc_seeds)
    sim_counts  <- .simulate_bracket(seed_tables, N_SIMULATIONS)

    field <- field |>
      mutate(
        wild_card_win_prob = ifelse(seed == 1, NA_real_, sim_counts$wc_wins[team] / N_SIMULATIONS),
        divisional_win_prob = sim_counts$div_wins[team] / N_SIMULATIONS,
        conference_championship_win_prob = sim_counts$cc_wins[team] / N_SIMULATIONS,
        super_bowl_win_prob = sim_counts$sb_wins[team] / N_SIMULATIONS
      ) |>
      arrange(conference, seed)

    playoff_simulation <- list(
      season          = CURRENT_SEASON,
      generated_at    = Sys.time(),
      n_simulations   = N_SIMULATIONS,
      seeding_method  = "Real NFL tiebreaker procedure (head-to-head, division/conference record, common games, strength of victory/schedule, combined point rankings, net points) via nfl_tiebreakers.R - see that file's header for the full verified procedure and its two documented scope limitations (net touchdowns / coin toss not modeled, alphabetical fallback instead).",
      field           = field
    )

    saveRDS(playoff_simulation, CACHE_PLAYOFF_SIMULATION)
    log_info(sprintf("Wrote playoff bracket simulation (%d sims/conference-bracket) to CACHE_PLAYOFF_SIMULATION.",
                      N_SIMULATIONS),
             call = "run_playoff_simulator()", out_path = CACHE_PLAYOFF_SIMULATION)

    TRUE
  }, error = function(e) {
    log_error("Playoff bracket simulator failed.", condition = e, call = "run_playoff_simulator()")
    FALSE
  })

  invisible(isTRUE(result))
}
