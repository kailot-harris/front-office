# ==============================================================================
# NFL Playoff Odds — Week-by-Week History Backfill
# Path: tools/playoff_odds_history_backfill.R
#
# GitHub issue #18 ("Historical weekly playoff-odds backfill (CACHE_PLAYOFF_ODDS_HISTORY)"),
# docs/task_assignments_phase8.md task P9-B. CACHE_PLAYOFF_ODDS (playoff_odds_engine.R's
# run_playoff_odds_engine()) only ever holds a point-in-time "as of right now" snapshot - no
# week dimension. Task P9-I (agent_viz_c_playoff_turnover, Wave 2) needs odds AS OF each past
# completed week to animate a probability-by-week chart, and consumes CACHE_PLAYOFF_ODDS_HISTORY
# without seeing this file's code - the schema below is a load-bearing contract, not a
# convenience choice.
#
# This is a tools/ script (per CLAUDE.md's folder-layout convention), not a run_full_pipeline.R
# stage of its own: the weekly GIF stage (render_weekly_gifs.R GIF_HISTORY_BUILDERS,
# NFL_analytics#194) runs it as a history prerequisite of gif_playoff_odds_heatmap.R and
# gif_playoff_prob_bump.R, about once a week, not every pipeline run. It can also be run by hand.
#
# SEASON GUARD (#194): the cache has no season column, so CACHE_PLAYOFF_ODDS_HISTORY_META
# (a gitignored sidecar JSON) records the season it was built for. If it is missing or names
# another season, the existing cache is ignored and every completed week is rebuilt.
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
#
# INCREMENTAL BEHAVIOR (added after the initial full backfill, so re-running weekly doesn't
# re-pay the whole season's cost every time): a week's retrospective snapshot is a deterministic
# function of only the games completed through that week (see "RETROSPECTIVE SNAPSHOT
# DEFINITION" above) plus whatever's in CACHE_SCHEDULES/CACHE_TEAM_RATINGS right now for the
# not-yet-real portion of the simulated season - once week W has actually been played out to
# completion, re-simulating "as of week W" again produces the same quantity (up to Monte Carlo
# noise alone), so an already-cached completed week is never recomputed. Each run reads any
# existing CACHE_PLAYOFF_ODDS_HISTORY, diffs its cached `week` values against
# 1:latest_completed_week, and only runs .simulate_one_season_asof() for the weeks NOT already
# present - e.g. with weeks 1-6 cached, a week-7 run does 1 week of simulation (not 7), the
# Monday-after-games-conclude cadence this script is meant to run on. A first-ever run (no
# cache file yet) or a cache that fails its schema check still runs the full 1:latest_completed_
# week backfill, same as the original behavior.
# ==============================================================================

setwd(local({
  # Repo root: NFL_PROJECT_DIR if set, else this script's parent directory (it lives in
  # tools/), else the working directory if it holds config.R. No hard-coded fallback.
  env_root <- Sys.getenv("NFL_PROJECT_DIR", "")
  f <- sub("^--file=", "", grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE))
  f <- gsub("~+~", " ", f, fixed = TRUE)
  script_root <- if (length(f) == 1L) {
    dirname(dirname(normalizePath(f, winslash = "/", mustWork = FALSE)))
  } else ""
  root <- if (nzchar(env_root)) {
    env_root
  } else if (nzchar(script_root) && file.exists(file.path(script_root, "config.R"))) {
    script_root
  } else if (file.exists("config.R")) {
    getwd()
  } else {
    stop("Cannot locate the NFL Analytics project root: set NFL_PROJECT_DIR or run from the repo root.")
  }
  normalizePath(root, winslash = "/", mustWork = FALSE)
}))
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
.simulate_one_season_asof <- function(week_cutoff, team_ratings, sch, season = CURRENT_SEASON) {
  rating_lookup <- setNames(team_ratings$power_rating, team_ratings$team)
  league_mean_rating <- mean(team_ratings$power_rating, na.rm = TRUE)
  if (!is.finite(league_mean_rating)) league_mean_rating <- 0

  .rating_for <- function(tm) {
    r <- rating_lookup[[tm]]
    if (is.null(r) || length(r) == 0 || is.na(r)) league_mean_rating else r
  }

  reg_season <- sch[sch$season == season & sch$game_type == "REG", ]

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
# Exposed entry point (the direct-run guard at the bottom only covers `Rscript <this file>`).
# No required args. The arguments are test-only hooks (tests/test_playoff_odds_history_backfill.R):
# history_path / meta_path redirect the cache and sidecar to temp files, season overrides
# CURRENT_SEASON, sch / team_ratings replace the cache reads, and simulate_week swaps the Monte
# Carlo week (.simulate_week_odds) for a stub. The pipeline always uses the defaults. For each week W in
# 1:(latest fully-completed week in CURRENT_SEASON) NOT already present in an existing
# CACHE_PLAYOFF_ODDS_HISTORY (see "INCREMENTAL BEHAVIOR" above), runs N_SEASON_SIMULATIONS
# trials of .simulate_one_season_asof(W, ...), tallies each of the 32 real NFL_TEAMS
# abbreviations' appearance as a playoff team / division winner / #1-seed bye across those
# trials, and writes one (week, team) row per team per week to CACHE_PLAYOFF_ODDS_HISTORY -
# newly-simulated weeks combined with whatever already-cached weeks were reused unchanged.
# Mirrors run_playoff_odds_engine()'s non-stop()ping TRUE/FALSE return contract.
#
# "Latest fully-completed week" = the largest week number for which every scheduled REG game
# has a non-NA score (a week with any in-progress/postponed game is NOT treated as complete).
#
# A single .simulate_one_season_asof() call returning NULL aborts the whole run immediately
# (log + return FALSE), same non-silent-undercounting contract run_playoff_odds_engine() uses -
# the output file is NOT overwritten in this case, so a prior successful cache (full or partial)
# is left intact rather than being clobbered by a failed re-run.
# ------------------------------------------------------------------------------------------
# ------------------------------------------------------------------------------------------
# .simulate_week_odds(): N_SEASON_SIMULATIONS trials as of week `w`; one row per team with
# division_win_prob / playoff_prob / bye_prob. NULL if any trial fails (caller aborts).
# ------------------------------------------------------------------------------------------
.simulate_week_odds <- function(w, team_ratings, sch, season = CURRENT_SEASON) {
  team_abbrs <- names(NFL_TEAMS)
  playoff_counts   <- setNames(integer(length(team_abbrs)), team_abbrs)
  division_counts  <- setNames(integer(length(team_abbrs)), team_abbrs)
  bye_counts       <- setNames(integer(length(team_abbrs)), team_abbrs)

  for (trial in seq_len(N_SEASON_SIMULATIONS)) {
    field <- .simulate_one_season_asof(w, team_ratings, sch, season)
    if (is.null(field)) {
      log_error(sprintf(".simulate_one_season_asof() returned NULL on week %d trial %d of %d.",
                         w, trial, N_SEASON_SIMULATIONS),
                call = ".simulate_week_odds()")
      return(NULL)
    }
    playoff_counts[field$team] <- playoff_counts[field$team] + 1L
    div_teams <- field$team[field$role == "division_winner"]
    division_counts[div_teams] <- division_counts[div_teams] + 1L
    bye_teams <- field$team[field$seed == 1]
    bye_counts[bye_teams] <- bye_counts[bye_teams] + 1L
  }

  data.frame(
    week               = w,
    team               = team_abbrs,
    division_win_prob  = division_counts[team_abbrs] / N_SEASON_SIMULATIONS,
    playoff_prob       = playoff_counts[team_abbrs] / N_SEASON_SIMULATIONS,
    bye_prob           = bye_counts[team_abbrs] / N_SEASON_SIMULATIONS,
    stringsAsFactors   = FALSE,
    row.names          = NULL
  )
}

# Season the history cache was built for (sidecar JSON, gitignored). NA when the sidecar is
# missing or unreadable.
.history_meta_season <- function(meta_path) {
  if (!file.exists(meta_path)) return(NA_integer_)
  m <- tryCatch(jsonlite::fromJSON(meta_path), error = function(e) NULL)
  s <- suppressWarnings(as.integer(m$season))
  if (length(s) == 1L) s else NA_integer_
}

run_playoff_odds_history_backfill <- function(history_path = CACHE_PLAYOFF_ODDS_HISTORY,
                                              meta_path = CACHE_PLAYOFF_ODDS_HISTORY_META,
                                              season = CURRENT_SEASON,
                                              sch = NULL, team_ratings = NULL,
                                              simulate_week = .simulate_week_odds) {
  log_info(sprintf("Starting NFL playoff odds history backfill (%d season simulations per week)...",
                    N_SEASON_SIMULATIONS),
            call = "run_playoff_odds_history_backfill()")

  result <- tryCatch({
    if (is.null(team_ratings) && !file.exists(CACHE_TEAM_RATINGS)) {
      log_error("CACHE_TEAM_RATINGS does not exist - run_team_ratings() must run before run_playoff_odds_history_backfill().",
                call = "run_playoff_odds_history_backfill()")
      return(FALSE)
    }
    if (is.null(sch) && !file.exists(CACHE_SCHEDULES)) {
      log_error("CACHE_SCHEDULES does not exist - ingestion must run before run_playoff_odds_history_backfill().",
                call = "run_playoff_odds_history_backfill()")
      return(FALSE)
    }

    if (is.null(team_ratings)) team_ratings <- readRDS(CACHE_TEAM_RATINGS)
    if (is.null(sch))          sch          <- readRDS(CACHE_SCHEDULES)

    reg_season <- sch[sch$season == season & sch$game_type == "REG", ]
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

    # ---- Load any existing cache and work out which weeks are already done. A week already
    # present in the existing cache is a deterministic retrospective snapshot (see this file's
    # header) and is reused as-is rather than re-simulated - see "INCREMENTAL BEHAVIOR" above.
    # A missing file, an unreadable file, or a file with an unexpected schema are all treated
    # identically to "nothing cached yet" (full 1:latest_completed_week backfill), never a hard
    # failure - this script's whole job is to (re)build that cache, so a damaged/outdated one is
    # not a reason to stop.
    expected_cols <- c("week", "team", "division_win_prob", "playoff_prob", "bye_prob")
    existing_history <- NULL
    # Season guard: the cache has no season column, so the sidecar records which season it
    # was built for. A missing sidecar or a different season means a full rebuild; otherwise
    # last season's weeks would be taken as already computed.
    meta_season <- .history_meta_season(meta_path)
    if (file.exists(history_path) && !identical(meta_season, as.integer(season))) {
      log_warn(sprintf("CACHE_PLAYOFF_ODDS_HISTORY season sidecar says %s, current season is %d - running a full rebuild.",
                       if (is.na(meta_season)) "nothing (missing)" else meta_season, season),
               call = "run_playoff_odds_history_backfill()")
    } else if (file.exists(history_path)) {
      existing_history <- tryCatch({
        cached <- readRDS(history_path)
        if (!is.data.frame(cached) || !all(expected_cols %in% names(cached))) {
          log_warn("Existing CACHE_PLAYOFF_ODDS_HISTORY has an unexpected schema - ignoring it and running a full backfill.",
                   call = "run_playoff_odds_history_backfill()")
          NULL
        } else {
          cached
        }
      }, error = function(e) {
        log_warn(sprintf("Existing CACHE_PLAYOFF_ODDS_HISTORY could not be read (%s) - ignoring it and running a full backfill.",
                          conditionMessage(e)),
                 call = "run_playoff_odds_history_backfill()")
        NULL
      })
    }

    # Cached weeks beyond the current latest_completed_week are dropped rather than carried
    # forward - that situation only arises from a stale/leftover cache (e.g. a new season
    # started and CACHE_PLAYOFF_ODDS_HISTORY wasn't cleared), and such rows would otherwise
    # silently reappear in the output even though they're no longer a valid prefix of 1:latest_
    # completed_week.
    if (!is.null(existing_history)) {
      existing_history <- existing_history[existing_history$week <= latest_completed_week, ]
    }
    cached_weeks <- if (is.null(existing_history)) integer(0) else sort(unique(existing_history$week))
    weeks_to_run <- setdiff(seq_len(latest_completed_week), cached_weeks)

    if (length(weeks_to_run) == 0) {
      log_info(sprintf("CACHE_PLAYOFF_ODDS_HISTORY already covers weeks 1:%d (latest fully-completed week) - nothing to simulate.",
                        latest_completed_week),
               call = "run_playoff_odds_history_backfill()")
      return(TRUE)
    }

    log_info(sprintf("Latest fully-completed week in season %d: week %d. %d week(s) already cached; simulating week(s) %s.",
                      season, latest_completed_week, length(cached_weeks),
                      paste(weeks_to_run, collapse = ", ")),
             call = "run_playoff_odds_history_backfill()")

    all_rows <- vector("list", length(weeks_to_run))

    for (i in seq_along(weeks_to_run)) {
      w <- weeks_to_run[i]
      week_start <- Sys.time()
      rows <- simulate_week(w, team_ratings, sch, season)
      if (is.null(rows)) {
        log_error(sprintf("Simulating week %d failed - aborting run_playoff_odds_history_backfill(); cache left unchanged.", w),
                  call = "run_playoff_odds_history_backfill()")
        return(FALSE)
      }
      week_elapsed <- as.numeric(Sys.time() - week_start, units = "secs")
      log_info(sprintf("Backfilled week %d (%d/%d new week(s) this run, %d season simulations) in %.1f sec.",
                        w, i, length(weeks_to_run), N_SEASON_SIMULATIONS, week_elapsed),
               call = "run_playoff_odds_history_backfill()")
      all_rows[[i]] <- rows
    }

    newly_simulated <- dplyr::bind_rows(all_rows)

    # Reused cached weeks + newly-simulated weeks, deduped defensively on week (newly-simulated
    # rows win on the - should-never-happen - chance of overlap, since weeks_to_run was built as
    # a set difference against cached_weeks above) and sorted for a stable on-disk row order.
    playoff_odds_history <- if (is.null(existing_history)) {
      newly_simulated
    } else {
      dplyr::bind_rows(newly_simulated, existing_history[, expected_cols]) |>
        dplyr::distinct(week, team, .keep_all = TRUE)
    }
    playoff_odds_history <- playoff_odds_history |> dplyr::arrange(week, team)

    saveRDS(playoff_odds_history, history_path)
    jsonlite::write_json(list(season = as.integer(season), max_week = as.integer(latest_completed_week),
                              built_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")),
                         meta_path, auto_unbox = TRUE, pretty = TRUE)
    log_info(sprintf("Wrote playoff odds history (weeks 1:%d - %d newly simulated, %d reused from cache - %d season simulations/week) to CACHE_PLAYOFF_ODDS_HISTORY.",
                      latest_completed_week, length(weeks_to_run), length(cached_weeks), N_SEASON_SIMULATIONS),
             call = "run_playoff_odds_history_backfill()", out_path = history_path)

    TRUE
  }, error = function(e) {
    log_error("Playoff odds history backfill failed.", condition = e, call = "run_playoff_odds_history_backfill()")
    FALSE
  })

  invisible(isTRUE(result))
}

# Direct run (the weekly GIF stage runs this file as a history builder, render_weekly_gifs.R
# GIF_HISTORY_BUILDERS): exit non-zero on failure so the stage marks the dependent GIFs failed.
# Not sourced by run_full_pipeline.R, so the frame-depth caution in CLAUDE.md does not apply.
if (sys.nframe() == 0 && !interactive()) {
  if (!isTRUE(run_playoff_odds_history_backfill())) quit(status = 1L, save = "no")
}
