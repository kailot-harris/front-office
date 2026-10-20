# ==============================================================================
# NFL Playoff-Clinching Probability Engine - Single-Trial Season Simulator
# Path: c:/Users/kailo/kayceeslices/front-office/nfl analytics/playoff_odds_engine.R
#
# GitHub issue #12 ("Playoff Odds 2: Single-trial remaining-season simulation + real-
# tiebreaker reseed function"). Part of the playoff-clinching-probability feature spec'd in
# docs/SPEC_playoff_odds_table.md (decisions #2 and #4). This file is PURELY the single-trial
# logic: simulate the rest of the regular season once, re-seed the real 14-team field from
# that one hypothetical completed season via the REAL NFL tiebreaker procedure, and return
# the resulting 14 team abbreviations. It deliberately does NOT contain a Monte Carlo loop
# (no N_SEASON_SIMULATIONS usage), no cache write (no CACHE_PLAYOFF_ODDS usage), no
# run_playoff_odds_engine() entry point, and no Discord dispatch - those are separate later
# issues (#13 loops this function N_SEASON_SIMULATIONS times and writes CACHE_PLAYOFF_ODDS,
# #14 adds Discord). No top-level side effects beyond function definitions - safe to
# source() from any script or console, same convention as nfl_tiebreakers.R.
#
# ------------------------------------------------------------------------------------------
# WHY THIS REUSES playoff_simulator.R / nfl_tiebreakers.R RATHER THAN DUPLICATING THEM:
#
#   - .seed_conference() (playoff_simulator.R): turns a 32-team `records` table (with
#     conference/division attached) + a `game_log` into a 7-seed-per-conference field via the
#     real tiebreaker procedure. This file calls it UNMODIFIED against a records/game_log pair
#     built from a HYPOTHETICAL completed season (real completed games union simulated
#     remaining games), rather than playoff_simulator.R's own real-completed-games-so-far
#     season. Same function, different (hypothetical) input - not a copy.
#   - build_tiebreak_data() (nfl_tiebreakers.R): produces the exact game_log/records shapes
#     .seed_conference() expects from a schedule-shaped data.frame, filtering internally to
#     season == CURRENT_SEASON, game_type == "REG", non-NA scores (i.e. "completed" games
#     only). Rather than hand-replicating its column shapes (team/opponent/own_score/
#     opp_score/win/loss/tie/team_conf/opp_conf/team_div/opp_div/is_division_game/
#     is_conference_game for game_log; team/wins/losses/ties/games_played/points_for/
#     points_against/win_pct for records - see that file's header), this file constructs a
#     HYPOTHETICAL schedule data.frame (real completed rows as-is, plus one simulated-outcome
#     row per currently-remaining game, all stamped season = CURRENT_SEASON, game_type =
#     "REG") and feeds THAT into build_tiebreak_data() directly. Every simulated game is
#     therefore "completed" from build_tiebreak_data()'s point of view, so it produces an
#     identically-shaped game_log/records pair with zero duplicated column logic.
#   - .simulate_game() (playoff_simulator.R) implements pnorm((rating_diff + hca) /
#     NFL_MARGIN_SIGMA) for two BRACKET SEED numbers. This file needs the same formula applied
#     to two TEAM ABBREVIATIONS for a regular-season game instead, so it is NOT called
#     directly (its signature is seed-shaped, not team-shaped) - the formula itself is
#     reproduced inline below for team-vs-team, referencing config.R's NFL_HCA /
#     NFL_MARGIN_SIGMA symbols exactly as .simulate_game() does (never a re-typed literal -
#     see CLAUDE.md's constants-single-source-of-truth discipline).
#
# ------------------------------------------------------------------------------------------
# SIMULATED-GAME SCORING CONVENTION (documented choice, not an unstated hack):
#
# A simulated remaining game is recorded as winner 1 - loser 0 (never a tie). Only the
# win/loss outcome matters for seeding purposes here - build_tiebreak_data()/
# resolve_division_ties()/resolve_wildcard_ties() need win_pct and, deeper in the cascade,
# net-points-based criteria, but nfl_tiebreakers.R's own header already documents that its
# final two real-world criteria (net touchdowns, coin toss) are NOT modeled and fall back to
# alphabetical order - so a plausible/realistic point MARGIN for simulated games was never
# going to materially change the result beyond what that documented fallback already covers.
# 1-0 is the simplest winner/loser encoding that resolves win/loss correctly without
# fabricating a fake margin that could be mistaken for a modeled quantity.
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "playoff_odds_engine.R"

# Brings in .seed_conference() / .simulate_game() and, transitively, nfl_tiebreakers.R's
# build_tiebreak_data() / resolve_division_ties() / resolve_wildcard_ties() / order_by_record()
# - same "source the file, call its top-level functions directly" pattern playoff_simulator.R
# itself uses for nfl_tiebreakers.R. Also brings dplyr into scope via its own library() call.
source("playoff_simulator.R")

# ------------------------------------------------------------------------------------------
# .simulate_one_season(): simulates every not-yet-played CURRENT_SEASON REG game once, using
# each game's two teams' real power_rating (CACHE_TEAM_RATINGS) + NFL_HCA/NFL_MARGIN_SIGMA via
# pnorm() - the same win-probability formula playoff_simulator.R's .simulate_game() uses for
# bracket games, applied here to real regular-season matchups instead of bracket seeds.
# Combines those simulated outcomes with the REAL completed games (never re-simulated - their
# real recorded scores stand) into one hypothetical full-season schedule, reseeds both
# conferences via the real tiebreaker procedure (.seed_conference(), sourced above), and
# returns just the resulting 14 team abbreviations (7 AFC + 7 NFC) that made that one
# hypothetical season's field - no bracket simulation, no round-by-round odds.
#
# Returns NULL (and logs an error) if required caches are missing, mirroring
# run_playoff_simulator()'s non-stop()ping error contract. Returns a character vector of
# length 14 on success.
# ------------------------------------------------------------------------------------------
.simulate_one_season <- function() {
  if (!file.exists(CACHE_TEAM_RATINGS)) {
    log_error("CACHE_TEAM_RATINGS does not exist - run_team_ratings() must run before .simulate_one_season().",
              call = ".simulate_one_season()")
    return(NULL)
  }
  if (!file.exists(CACHE_SCHEDULES)) {
    log_error("CACHE_SCHEDULES does not exist - ingestion must run before .simulate_one_season().",
              call = ".simulate_one_season()")
    return(NULL)
  }

  team_ratings <- readRDS(CACHE_TEAM_RATINGS)
  sch          <- readRDS(CACHE_SCHEDULES)

  # Same documented fallback run_playoff_simulator() uses: league-mean power_rating for any
  # team missing a rating, so a gap in CACHE_TEAM_RATINGS can't crash the simulation.
  rating_lookup <- setNames(team_ratings$power_rating, team_ratings$team)
  league_mean_rating <- mean(team_ratings$power_rating, na.rm = TRUE)
  if (!is.finite(league_mean_rating)) league_mean_rating <- 0

  .rating_for <- function(tm) {
    r <- rating_lookup[[tm]]
    if (is.null(r) || length(r) == 0 || is.na(r)) league_mean_rating else r
  }

  reg_season <- sch |> dplyr::filter(season == CURRENT_SEASON, game_type == "REG")

  completed <- reg_season |> dplyr::filter(!is.na(home_score), !is.na(away_score))
  remaining <- reg_season |> dplyr::filter(is.na(home_score) | is.na(away_score))

  # ---- Simulate every remaining game once (team-vs-team version of .simulate_game()'s formula) ----
  if (nrow(remaining) > 0) {
    sim_home_win <- vapply(seq_len(nrow(remaining)), function(i) {
      home <- remaining$home_team[i]
      away <- remaining$away_team[i]
      rating_diff <- .rating_for(home) - .rating_for(away)
      p_home_win <- pnorm((rating_diff + NFL_HCA) / NFL_MARGIN_SIGMA)
      runif(1) < p_home_win
    }, logical(1))

    # Winner 1 - loser 0 (see header's documented scoring convention) - win/loss resolves
    # correctly; no fabricated point margin.
    remaining$home_score <- ifelse(sim_home_win, 1, 0)
    remaining$away_score <- ifelse(sim_home_win, 0, 1)
  }

  # ---- Hypothetical full season: real completed games UNION simulated remaining games ----
  # Feeding this into build_tiebreak_data() (nfl_tiebreakers.R) directly reuses that function's
  # exact game_log/records column shapes rather than hand-duplicating them (see header).
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
    log_error(sprintf("NFL_DIVISIONS missing entries for: %s - cannot seed hypothetical playoff field.",
                       paste(missing, collapse = ", ")), call = ".simulate_one_season()")
    return(NULL)
  }

  afc_seeds <- .seed_conference(records, game_log, "AFC")
  nfc_seeds <- .seed_conference(records, game_log, "NFC")

  c(afc_seeds$team, nfc_seeds$team)
}

# ------------------------------------------------------------------------------------------
# run_playoff_odds_engine()
#
# GitHub issue #13 ("Playoff Odds 3: Monte Carlo loop + run_playoff_odds_engine() cache write
# (no Discord yet)"). Sole exposed entry point for this file (no sys.nframe()/interactive()
# auto-run guard, per this repo's call_fn convention - see CLAUDE.md). No required args.
#
# Runs N_SEASON_SIMULATIONS trials of .simulate_one_season() (each trial re-reads
# CACHE_SCHEDULES/CACHE_TEAM_RATINGS fresh - an accepted inefficiency for now; issue #16 tunes
# performance, not this issue), tallies how many trials each of the 32 real NFL_TEAMS team
# abbreviations appears in the returned 14-team field, and writes a 32-row
# team/conference/division/playoff_prob result to CACHE_PLAYOFF_ODDS. Mirrors
# run_playoff_simulator()'s structure and non-stop()ping TRUE/FALSE return contract.
#
# A single .simulate_one_season() call returning NULL (its own documented failure path when a
# required cache is missing) aborts the whole run immediately (log + return FALSE) rather than
# silently skipping that trial and undercounting.
# ------------------------------------------------------------------------------------------
run_playoff_odds_engine <- function() {
  log_info(sprintf("Starting NFL playoff odds engine (%d season simulations)...", N_SEASON_SIMULATIONS),
            call = "run_playoff_odds_engine()")

  result <- tryCatch({
    team_abbrs <- names(NFL_TEAMS)
    appearance_counts <- setNames(integer(length(team_abbrs)), team_abbrs)

    for (trial in seq_len(N_SEASON_SIMULATIONS)) {
      field <- .simulate_one_season()

      if (is.null(field)) {
        log_error(sprintf(".simulate_one_season() returned NULL on trial %d of %d - aborting run_playoff_odds_engine().",
                           trial, N_SEASON_SIMULATIONS),
                  call = "run_playoff_odds_engine()")
        return(FALSE)
      }

      appearance_counts[field] <- appearance_counts[field] + 1L
    }

    conf_div <- NFL_DIVISIONS[team_abbrs]
    field_table <- data.frame(
      team         = team_abbrs,
      conference   = sub(" .*$", "", conf_div),
      division     = conf_div,
      playoff_prob = appearance_counts[team_abbrs] / N_SEASON_SIMULATIONS,
      stringsAsFactors = FALSE,
      row.names = NULL
    )

    playoff_odds <- list(
      season        = CURRENT_SEASON,
      generated_at  = Sys.time(),
      n_simulations = N_SEASON_SIMULATIONS,
      field         = field_table
    )

    saveRDS(playoff_odds, CACHE_PLAYOFF_ODDS)
    log_info(sprintf("Wrote playoff odds (%d season simulations) to CACHE_PLAYOFF_ODDS.",
                      N_SEASON_SIMULATIONS),
             call = "run_playoff_odds_engine()", out_path = CACHE_PLAYOFF_ODDS)

    # --------------------------------------------------------------------------------------
    # Discord dispatch (GitHub issue #14) — reuses notify_bets.R's/accuracy_tracker.R's exact
    # webhook/payload/fallback pattern verbatim (same NFL_DISCORD_WEBHOOK env var, same
    # nzchar()-gated POST()/console-only branching). NO hardcoded webhook URL, live or dummy,
    # anywhere in this file.
    #
    # Payload shape per docs/SPEC_playoff_odds_table.md decision #7 / issue #14: exactly TWO
    # embed fields (AFC, NFC), NOT one field per team (32 fields would blow past readability and
    # risk bumping into Discord's 25-field-per-embed cap). Each field is a compact newline-
    # joined list of that conference's 16 teams, sorted descending by playoff_prob.
    webhook_url <- Sys.getenv("NFL_DISCORD_WEBHOOK", "")

    .conf_field_value <- function(conf_name) {
      conf_rows <- field_table[field_table$conference == conf_name, ]
      conf_rows <- conf_rows[order(-conf_rows$playoff_prob), ]
      lines <- sprintf("`%s` — %.1f%%", conf_rows$team, conf_rows$playoff_prob * 100)
      paste(lines, collapse = "\n")
    }

    afc_value <- .conf_field_value("AFC")
    nfc_value <- .conf_field_value("NFC")

    embed_fields <- list(
      list(name = "\U0001F3C8 AFC", value = afc_value, inline = TRUE),
      list(name = "\U0001F3C8 NFC", value = nfc_value, inline = TRUE)
    )

    payload <- list(
      username = "NFL Quant Terminal",
      avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
      embeds = list(
        list(
          title = paste("\U0001F3C6 NFL Playoff-Clinching Odds •", format(Sys.Date(), "%B %d, %Y")),
          description = sprintf(
            "**%d-season** Monte Carlo field: probability each team clinches a playoff berth (not advancement odds), %d season.",
            N_SEASON_SIMULATIONS, CURRENT_SEASON
          ),
          color = 3066993, # Sharp Dark Emerald Green — matches notify_bets.R's embed style
          fields = embed_fields,
          footer = list(text = paste("NFL Quant Engine - Playoff Odds • Generated at", format(Sys.time(), "%H:%M:%S EST")))
        )
      )
    )

    if (nzchar(webhook_url)) {
      res <- tryCatch(
        POST(webhook_url, body = payload, encode = "json", timeout(6)),
        error = function(e) list(status_code = 500, message = e$message)
      )
      if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
        cat("\n[ALERT SUCCESS] Broadcasted NFL playoff odds to Discord webhook.\n")
        log_info("Broadcasted NFL playoff odds to Discord webhook.", call = "run_playoff_odds_engine()",
                 status_code = res$status_code)
      } else {
        cat("\n[ALERT DISPATCHED] Webhook sent.\n")
        log_warn("Discord webhook POST did not return a clean 200/204.", call = "run_playoff_odds_engine()",
                 status_code = res$status_code)
      }
    } else {
      cat("\n[CONSOLE ONLY] NFL_DISCORD_WEBHOOK env var not set for this project - Discord dispatch skipped.\n")
      cat("AFC (top 3):\n")
      cat(paste(head(strsplit(afc_value, "\n")[[1]], 3), collapse = "\n"), "\n")
      cat("NFC (top 3):\n")
      cat(paste(head(strsplit(nfc_value, "\n")[[1]], 3), collapse = "\n"), "\n")
      log_warn("NFL_DISCORD_WEBHOOK not configured; skipped Discord dispatch (console-only preview shown). Set it as a real environment variable (.Renviron) to enable live dispatch.",
               call = "run_playoff_odds_engine()")
    }

    TRUE
  }, error = function(e) {
    log_error("Playoff odds engine failed.", condition = e, call = "run_playoff_odds_engine()")
    FALSE
  })

  invisible(isTRUE(result))
}
