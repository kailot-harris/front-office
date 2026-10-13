# ==============================================================================
# NFL Playoff Odds — Week-by-Week History Backfill
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/tools/playoff_odds_history_backfill.R
#
# GitHub issue #18 ("Historical weekly playoff-odds backfill (CACHE_PLAYOFF_ODDS_HISTORY)"),
# docs/task_assignments_phase8.md task P9-B. CACHE_PLAYOFF_ODDS (playoff_odds_engine.R's
# run_playoff_odds_engine()) only ever holds a point-in-time "as of right now" snapshot - no
# week dimension. Task P9-I (agent_viz_c_playoff_turnover, Wave 2) needs odds AS OF each past
# completed week to animate a probability-by-week chart, and consumes CACHE_PLAYOFF_ODDS_HISTORY
# without seeing this file's code - the schema below is a load-bearing contract, not a
# convenience choice.
#
# This is a tools/ one-off (per CLAUDE.md's folder-layout convention), not part of
# run_full_pipeline.R's DAG - it is re-run manually/periodically, not every pipeline run, since
# it is strictly more expensive than the single "now" snapshot (see cost note below).
#
# ------------------------------------------------------------------------------------------
# WHY THIS REUSES .seed_conference() / build_tiebreak_data() RATHER THAN DUPLICATING THEM:
#
# Exactly the same reuse rationale playoff_odds_engine.R's own header documents for
# .simulate_one_season(): .seed_conference() (playoff_simulator.R) and build_tiebreak_data()
# (nfl_tiebreakers.R) are called UNMODIFIED below, against a hypothetical schedule data.frame
# this script builds per (week, trial). Neither function, nor N_SEASON_SIMULATIONS itself, is
# edited or reimplemented anywhere in this file.
#
# .simulate_one_season_asof() below is a near-twin of playoff_odds_engine.R's
# .simulate_one_season(), NOT a call to it, for two reasons specific to this backfill:
#   1. .simulate_one_season() always treats "today's" full set of completed games as real and
#      simulates only what remains right now - it has no week-cutoff parameter. Reusing it
#      as-is would only ever reproduce the SAME "now" snapshot for every week, not a true
#      retrospective "as of week W" snapshot. A `week_cutoff` parameter is added here precisely
#      so only games with `week <= week_cutoff` (and non-NA scores) count as real - everything
#      else, including week_cutoff AND the rest of the season, is simulated once per trial,
#      same as .simulate_one_season() does for "the rest of the season" relative to today.
#   2. .simulate_one_season() returns only the flat 14 winning team abbreviations - enough for
#      playoff_prob alone. This backfill's required schema (division_win_prob, playoff_prob,
#      bye_prob per issue #18) needs each trial's seed/role detail too (division_win_prob =
#      role == "division_winner"; bye_prob = seed == 1, the sole #1-seed-per-conference bye per
#      playoff_simulator.R's header), so this function returns the full seed table instead of
#      discarding seed/role down to a flat vector.
# Both are orchestration-layer differences (same class of difference playoff_odds_engine.R's
# own header draws between itself and playoff_simulator.R), not changes to the underlying
# tiebreak/seeding logic itself.
#
# ------------------------------------------------------------------------------------------
# RETROSPECTIVE SNAPSHOT DEFINITION (week_cutoff semantics):
#
# For week W, "real" games are exactly `season == CURRENT_SEASON & game_type == "REG" &
# week <= W & !is.na(home_score) & !is.na(away_score)`. Every other REG game (week > W, or a
# week <= W game with a missing score, e.g. postponed) is treated as not-yet-played and
# simulated fresh for that trial - never read from CACHE_SCHEDULES' current (today's) actual
# outcome. This is what makes each week's snapshot a true retrospective "if the season had
# stopped there" view rather than today's full state relabeled.
#
# ------------------------------------------------------------------------------------------
# COST (measured, not assumed - see run log / task result for the actual timing):
#
# This is N_SEASON_SIMULATIONS trials PER historical week, i.e. (latest completed week) times
# the cost of one CACHE_PLAYOFF_ODDS snapshot - the exact risk GitHub issue #18 flags. Single-
# week cost was timed before running the full backfill (see this task's result/data for the
# measured seconds-per-week and total runtime); N_SEASON_SIMULATIONS itself was NOT reduced for
# this script - if the measured cost had made an unattended full run impractical, this script
# would stop short of running the whole backfill rather than silently cutting the trial count.
# ==============================================================================

setwd("C:/Users/kailo/kayceeslices/NFL Analytics")
source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "playoff_odds_history_backfill.R"

# Brings in .seed_conference() (playoff_simulator.R) and, transitively, build_tiebreak_data() /
# resolve_division_ties() / resolve_wildcard_ties() / order_by_record() (nfl_tiebreakers.R), plus
# dplyr - same "source the file, call its top-level functions directly" pattern
# playoff_odds_engine.R itself uses.
source("playoff_simulator.R")

# ------------------------------------------------------------------------------------------
# .simulate_one_season_asof(): one hypothetical-season trial AS OF `week_cutoff`. Returns a
# data.frame(team, seed, role) for the 14 teams (7 AFC + 7 NFC) that make that one trial's
# hypothetical field, or NULL (logged) if a required cache is missing - mirrors
# .simulate_one_season()'s non-stop()ping error contract.
# ------------------------------------------------------------------------------------------
.simulate_one_season_asof <- function(week_cutoff, team_ratings, sch) {
  rating_lookup <- setNames(team_ratings$power_rating, team_ratings$team)
  league_mean_rating <- mean(team_ratings$power_rating, na.rm = TRUE)
  if (!is.finite(league_mean_rating)) league_mean_rating <- 0

  .rating_for <- function(tm) {
    r <- rating_lookup[[tm]]
    if (is.null(r) || length(r) == 0 || is.na(r)) league_mean_rating else r
  }

  reg_season <- sch |> dplyr::filter(season == CURRENT_SEASON, game_type == "REG")

  is_real_completed <- reg_season$week <= week_cutoff &
    !is.na(reg_season$home_score) & !is.na(reg_season$away_score)

  completed <- reg_season[is_real_completed, ]
  remaining <- reg_season[!is_real_completed, ]

  # ---- Simulate every not-yet-real-as-of-week_cutoff game once (same team-vs-team formula
  # .simulate_one_season() uses) ----
  if (nrow(remaining) > 0) {
    sim_home_win <- vapply(seq_len(nrow(remaining)), function(i) {
      home <- remaining$home_team[i]
      away <- remaining$away_team[i]
      rating_diff <- .rating_for(home) - .rating_for(away)
      p_home_win <- pnorm((rating_diff + NFL_HCA) / NFL_MARGIN_SIGMA)
      runif(1) < p_home_win
    }, logical(1))

    # Winner 1 - loser 0 (same documented scoring convention as .simulate_one_season()'s header).
    remaining$home_score <- ifelse(sim_home_win, 1, 0)
    remaining$away_score <- ifelse(sim_home_win, 0, 1)
  }

  keep_cols <- c("season", "game_type", "home_team", "away_team", "home_score", "away_score")
  hypothetical_sch <- dplyr::bind_rows(completed[, keep_cols], remaining[, keep_cols])

  tiebreak_data <- build_tiebreak_data(hypothetical_sch)
  records  <- tiebreak_data$records
  game_log <- tiebreak_data$game_log

  conf_div <- NFL_DIVISIONS[records$team]
  records$conference <- sub(" .*$", "", conf_div)
  records$division   <- conf_div

  if (any(is.na(records$conference))) {
    missing <- records$team[is.na(records$conference)]
    log_error(sprintf("NFL_DIVISIONS missing entries for: %s - cannot seed hypothetical playoff field (week %d).",
                       paste(missing, collapse = ", "), week_cutoff),
              call = ".simulate_one_season_asof()")
    return(NULL)
  }

  afc_seeds <- .seed_conference(records, game_log, "AFC")
  nfc_seeds <- .seed_conference(records, game_log, "NFC")

  dplyr::bind_rows(afc_seeds, nfc_seeds)[, c("team", "seed", "role")]
}

# ------------------------------------------------------------------------------------------
# run_playoff_odds_history_backfill()
#
# Sole exposed entry point (no sys.nframe()/interactive() auto-run guard, per this repo's
# call_fn convention - see CLAUDE.md). No required args. For each week W in
# 1:(latest fully-completed week in CURRENT_SEASON), runs N_SEASON_SIMULATIONS trials of
# .simulate_one_season_asof(W, ...), tallies each of the 32 real NFL_TEAMS abbreviations'
# appearance as a playoff team / division winner / #1-seed bye across those trials, and writes
# one (week, team) row per team per week to CACHE_PLAYOFF_ODDS_HISTORY. Mirrors
# run_playoff_odds_engine()'s non-stop()ping TRUE/FALSE return contract.
#
# "Latest fully-completed week" = the largest week number for which every scheduled REG game
# has a non-NA score (a week with any in-progress/postponed game is NOT treated as complete).
#
# A single .simulate_one_season_asof() call returning NULL aborts the whole run immediately
# (log + return FALSE), same non-silent-undercounting contract run_playoff_odds_engine() uses.
# ------------------------------------------------------------------------------------------
run_playoff_odds_history_backfill <- function() {
  log_info(sprintf("Starting NFL playoff odds history backfill (%d season simulations per week)...",
                    N_SEASON_SIMULATIONS),
            call = "run_playoff_odds_history_backfill()")

  result <- tryCatch({
    if (!file.exists(CACHE_TEAM_RATINGS)) {
      log_error("CACHE_TEAM_RATINGS does not exist - run_team_ratings() must run before run_playoff_odds_history_backfill().",
                call = "run_playoff_odds_history_backfill()")
      return(FALSE)
    }
    if (!file.exists(CACHE_SCHEDULES)) {
      log_error("CACHE_SCHEDULES does not exist - ingestion must run before run_playoff_odds_history_backfill().",
                call = "run_playoff_odds_history_backfill()")
      return(FALSE)
    }

    team_ratings <- readRDS(CACHE_TEAM_RATINGS)
    sch          <- readRDS(CACHE_SCHEDULES)

    reg_season <- sch |> dplyr::filter(season == CURRENT_SEASON, game_type == "REG")
    by_week <- reg_season |>
      dplyr::group_by(week) |>
      dplyr::summarise(n = dplyr::n(),
                        completed = sum(!is.na(home_score) & !is.na(away_score)),
                        .groups = "drop") |>
      dplyr::arrange(week)

    fully_completed_weeks <- by_week$week[by_week$completed == by_week$n]
    if (length(fully_completed_weeks) == 0) {
      log_error("No fully-completed week found in CURRENT_SEASON's REG schedule - nothing to backfill.",
                call = "run_playoff_odds_history_backfill()")
      return(FALSE)
    }
    latest_completed_week <- max(fully_completed_weeks)
    log_info(sprintf("Latest fully-completed week in CURRENT_SEASON (%d): week %d. Backfilling weeks 1:%d.",
                      CURRENT_SEASON, latest_completed_week, latest_completed_week),
             call = "run_playoff_odds_history_backfill()")

    team_abbrs <- names(NFL_TEAMS)
    all_rows <- vector("list", latest_completed_week)

    for (w in seq_len(latest_completed_week)) {
      week_start <- Sys.time()

      playoff_counts   <- setNames(integer(length(team_abbrs)), team_abbrs)
      division_counts  <- setNames(integer(length(team_abbrs)), team_abbrs)
      bye_counts       <- setNames(integer(length(team_abbrs)), team_abbrs)

      for (trial in seq_len(N_SEASON_SIMULATIONS)) {
        field <- .simulate_one_season_asof(w, team_ratings, sch)

        if (is.null(field)) {
          log_error(sprintf(".simulate_one_season_asof() returned NULL on week %d trial %d of %d - aborting run_playoff_odds_history_backfill().",
                             w, trial, N_SEASON_SIMULATIONS),
                    call = "run_playoff_odds_history_backfill()")
          return(FALSE)
        }

        playoff_counts[field$team] <- playoff_counts[field$team] + 1L

        div_teams <- field$team[field$role == "division_winner"]
        division_counts[div_teams] <- division_counts[div_teams] + 1L

        bye_teams <- field$team[field$seed == 1]
        bye_counts[bye_teams] <- bye_counts[bye_teams] + 1L
      }

      week_elapsed <- as.numeric(Sys.time() - week_start, units = "secs")
      log_info(sprintf("Backfilled week %d/%d (%d season simulations) in %.1f sec.",
                        w, latest_completed_week, N_SEASON_SIMULATIONS, week_elapsed),
               call = "run_playoff_odds_history_backfill()")

      all_rows[[w]] <- data.frame(
        week               = w,
        team               = team_abbrs,
        division_win_prob  = division_counts[team_abbrs] / N_SEASON_SIMULATIONS,
        playoff_prob       = playoff_counts[team_abbrs] / N_SEASON_SIMULATIONS,
        bye_prob           = bye_counts[team_abbrs] / N_SEASON_SIMULATIONS,
        stringsAsFactors   = FALSE,
        row.names          = NULL
      )
    }

    playoff_odds_history <- dplyr::bind_rows(all_rows)

    saveRDS(playoff_odds_history, CACHE_PLAYOFF_ODDS_HISTORY)
    log_info(sprintf("Wrote playoff odds history (weeks 1:%d, %d season simulations/week) to CACHE_PLAYOFF_ODDS_HISTORY.",
                      latest_completed_week, N_SEASON_SIMULATIONS),
             call = "run_playoff_odds_history_backfill()", out_path = CACHE_PLAYOFF_ODDS_HISTORY)

    TRUE
  }, error = function(e) {
    log_error("Playoff odds history backfill failed.", condition = e, call = "run_playoff_odds_history_backfill()")
    FALSE
  })

  invisible(isTRUE(result))
}
