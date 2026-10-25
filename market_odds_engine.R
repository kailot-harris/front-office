# ==============================================================================
# market_odds_engine.R (WNBA port)
# Phase 4 (T4) — Timezone-Aware Date Preservation & Multi-Factor Market Valuation
# Path: market_odds_engine.R
#
# Ported from the NBA Analytics repo's market_odds_engine.R. Sport-agnostic pieces
# (parse_multi_book_feed(), sharp-book detection, devig math, EV/Kelly math) are
# unchanged. WNBA-specific changes:
#   1. The Odds API sport key swapped from `basketball_nba` -> `basketball_wnba`.
#      Env var name (`ODDS_API_KEY`) is UNCHANGED — same account/key works for both
#      sports on The Odds API, only the sport-key URL segment differs.
#   2. Fixture fallback rewritten to real current (2026) WNBA teams from config.R's
#      `WNBA_TEAMS` (was a hardcoded 6-game NBA slate).
#   3. `resolve_team_name()` rewritten to canonicalize against `WNBA_TEAMS` (15 real
#      franchises) instead of a 30-team NBA regex table.
#   4. `get_model_slate_probabilities()` reads T2's actual standings cache filename,
#      `cache/projected_wnba_standings.rds` (NOT `projected_30_team_standings.rds` —
#      that NBA filename does not exist in this repo; per task_assignments.md T2
#      Handoff Notes this was a deliberate rename, not a placeholder to fill in).
#   5. Margin -> win-probability sigma uses `WNBA_MARGIN_SIGMA` and home-court
#      advantage uses `WNBA_HCA` — BOTH read from config.R, neither restated as a
#      literal anywhere in this file (FINDING C-1; see config.R for each constant's
#      derivation and provenance comment).
#   6. Shot-quality / fatigue lookups: T3's `team_shot_quality.rds` and
#      `travel_fatigue_metrics.rds` key on WNBA team ABBREVIATIONS (e.g. "LV", "SEA"),
#      not full team names like the standings cache's `Team` column ("Las Vegas
#      Aces"). `resolve_team_name()` returns the canonical FULL name (to match
#      standings), and a small `abbr_for()` helper maps that back to the abbreviation
#      for the shot-quality/fatigue joins.
#
# KNOWN DATA-QUALITY CAVEAT (per WNBA_REPLICATION_PLAN.md §(e) risk #2 — do not treat
# this as a reason to loosen risk controls, just as a labeling issue for the
# dashboard/T5 to surface): WNBA book coverage on The Odds API is materially thinner
# than NBA's. Expect `parse_multi_book_feed()`'s sharp-book detector
# (pinnacle/circa/lowvig/betonlineag) to find ZERO sharp books far more often than in
# the NBA version — this already falls back to devigged retail consensus
# (`cons_h_ml <- ifelse(!is.na(sharp_h), sharp_h, prob_to_american(fair_cons_h))`),
# which is preserved unchanged below. Do NOT weaken the EV/Kelly thresholds to
# "compensate" for thinner markets; that is a data-quality flag for the dashboard
# layer (T5), not a reason to loosen staking discipline here.
# ==============================================================================

PROJECT_DIR <- here::here()   # issue #90: derived portably; never hardcode the repo root
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(ranger)
  library(httr)
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(tidyr)
  library(stringr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "market_odds_engine.R"

# FINDING M-6: the local scalar `%||%` that used to live here has been REMOVED. The
# single canonical definition (hardened `is.na(a)[1]` form) lives in logging_utils.R,
# which is sourced immediately above — before any `%||%` use in this file. Do not
# re-add a local copy: two definitions made "which one wins" depend on source order.

# ------------------------------------------------------------------------------
# Model Robustness & XAI Helpers
# ------------------------------------------------------------------------------
apply_rating_limits <- function(rating) {
  # Ceiling/Floor adjustment to prevent extreme ratings from dominating.
  # Phase 2 (docs/HYPERPARAMETER_BACKTEST_PHASE2.md, tools/backtest_margin_hyperparams.R):
  # limit=5.0/dampening=0.1 re-confirmed via leakage-free walk-forward LOSO CV across all
  # 8 real seasons (2019-2026, N=1,902 real games) in data/box_scores_cache.rds — this exact
  # combination was independently selected as the training-fold optimum in 7 of 8
  # out-of-season folds (the 8th picked dampening=0.2, a one-step neighbor), for a pooled
  # out-of-fold MAE of 13.11 [95% CI 12.70-13.52] vs. 13.57 for the pre-optimization
  # defaults (limit=15.0/dampening=0.5). This supersedes Phase 1's
  # (tools/optimize_hyperparams.R) caveat that the same values looked like a
  # boundary/overfit artifact on a small synthetic sample — Phase 2 shows they hold up on
  # the real, full multi-season test set.
  limit <- 5.0
  dampening <- 0.1
  if (rating > limit) return(limit + dampening * (rating - limit))
  if (rating < -limit) return(-limit + dampening * (rating + limit))
  return(rating)
}

calculate_matchup_delta <- function(h_abbr, a_abbr) {
  # Player-Player matchup specifics: Star Power Delta
  rapm_path <- CACHE_RAPM_RATINGS
  rost_path <- file.path(CACHE_DIR, "active_rosters_cache.rds")

  if (!file.exists(rapm_path) || !file.exists(rost_path)) return(0.0)

  rapm <- readRDS(rapm_path)
  rost <- readRDS(rost_path)

  # BUG FIX (Phase 2, docs/HYPERPARAMETER_BACKTEST_PHASE2.md "Critical Finding"): this used
  # to join rapm_ratings.rds to active_rosters_cache.rds on `player_id`, but the two caches
  # use INCOMPATIBLE ID schemes (rapm's are stats-provider numeric IDs, e.g. 201496;
  # rosters' are ESPN athlete IDs, e.g. 869) with ZERO overlap, and rapm's `player_name` is
  # last-name-only (e.g. "Wilson") vs. rosters' full "First Last" — so this function has been
  # silently returning 0.0 for every single game since it was added; star_weight (below) has
  # never actually been live. Fixed by joining on (team full name + normalized last name)
  # instead: verified zero team+last-name collisions across all 209 rostered players, and
  # every one of the 15 teams has >=5 matched players. Re-derive/refresh this check if
  # active_rosters_cache.rds or rapm_ratings.rds's schema changes.
  norm_last <- function(x) tolower(trimws(gsub("[^a-zA-Z ]", "", word(x, -1))))
  h_players <- rost |> filter(team_abbreviation == h_abbr) |> mutate(last_name = norm_last(player_name))
  a_players <- rost |> filter(team_abbreviation == a_abbr) |> mutate(last_name = norm_last(player_name))
  rapm_x <- rapm |> mutate(last_name = tolower(trimws(gsub("[^a-zA-Z ]", "", player_name))))

  # Get top player for home team (joined on team full name, matching rapm's `team` column)
  h_matched <- h_players |> inner_join(rapm_x, by = c("team_name" = "team", "last_name"))
  h_top <- h_matched |> arrange(desc(total_rapm)) |> slice(1) |> pull(total_rapm)

  # Get top player for away team
  a_matched <- a_players |> inner_join(rapm_x, by = c("team_name" = "team", "last_name"))
  a_top <- a_matched |> arrange(desc(total_rapm)) |> slice(1) |> pull(total_rapm)

  if (length(h_top) == 0 || length(a_top) == 0) return(0.0)

  # Weighted adjustment: star_weight * star-power gap. Phase 2's tools/backtest_margin_hyperparams.R
  # swept star_weight (with the join bug fixed, so this is the first time this was actually
  # testable) against 301 real 2026-season games at the confirmed limit=5.0/dampening=0.1: MAE is
  # flat across 0.05-0.30 (12.875-12.877, effectively noise) with a shallow minimum at 0.15 — not a
  # grid-boundary hit. Set to that point estimate; treat 0.05-0.30 as statistically equivalent.
  star_weight <- 0.15
  return(star_weight * (h_top - a_top))
}

american_to_decimal <- function(odds) {

  odds <- as.numeric(odds)
  if_else(odds > 0, (odds / 100) + 1, (100 / abs(odds)) + 1)
}

american_to_prob <- function(odds) {
  odds <- as.numeric(odds)
  if_else(is.na(odds) | odds == 0, 0.50,
          if_else(odds > 0, 100 / (odds + 100), abs(odds) / (abs(odds) + 100)))
}

prob_to_american <- function(p) {
  if_else(p >= 0.5, round(-100 * p / (1 - p)), round(100 * (1 - p) / p))
}

calculate_kelly <- function(prob, decimal_odds, fraction = 0.25, max_cap_pct = 3.0) {
  b <- decimal_odds - 1
  q <- 1 - prob
  raw_kelly <- (b * prob - q) / b
  pct <- round(pmax(0, raw_kelly * fraction * 100), 2)
  pmin(pct, max_cap_pct)
}

# ------------------------------------------------------------------------------
# Team-name canonicalization against config.R's single source of truth, WNBA_TEAMS
# (abbreviation -> full franchise name). Returns the FULL name (matches T2's
# standings cache `Team` column), not a short nickname like the NBA version.
# ------------------------------------------------------------------------------
resolve_team_name <- function(tm_raw) {
  s <- tolower(trimws(as.character(tm_raw)))
  full_names <- unname(WNBA_TEAMS)
  abbrs      <- names(WNBA_TEAMS)

  # FINDING H-4: this function is the canonicalization boundary between The Odds
  # API's UNTRUSTED home_team/away_team fields and the internal standings lookup
  # that produces money recommendations. Two hardening rules, both load-bearing:
  #
  #  (a) Minimum input length. Degenerate inputs ("", "a", "s") must NOT resolve.
  #      They previously did, because of the reverse-containment clause below.
  #  (b) The reverse-containment clause `grepl(s, fn, fixed = TRUE)` (does the
  #      INPUT appear inside the franchise name?) has been DELETED. Only the
  #      forward direction is meaningful: is a franchise name present inside the
  #      input. The reverse direction only ever helped for prefixes and is
  #      precisely what made "" match every team and return "Atlanta Dream".
  #
  # Abbreviations are length 2-3 ("LV", "NY", "GS"), so they are checked BEFORE the
  # length gate rather than being collateral damage of it.
  if (length(s) != 1 || is.na(s)) {
    log_warn("resolve_team_name(): non-scalar/NA input could not be resolved to a WNBA franchise.",
             call = "resolve_team_name()", unresolved_value = paste(as.character(tm_raw), collapse = ","))
    return(NA_character_)
  }

  # 1. Abbreviation match (covers internal callers that already pass a WNBA_TEAMS
  #    abbreviation, e.g. "LV"). Exact equality only — no substring semantics.
  hit_ab <- abbrs[tolower(abbrs) == s]
  if (length(hit_ab) >= 1) return(unname(WNBA_TEAMS[hit_ab[1]]))

  # 2. H-4 length gate: below 3 characters nothing but an exact abbreviation can be
  #    trusted, so refuse rather than guess.
  if (nchar(s) < 3) {
    log_warn("resolve_team_name(): input too short to resolve to a WNBA franchise (H-4 guard).",
             call = "resolve_team_name()", unresolved_value = as.character(tm_raw))
    return(NA_character_)
  }

  # 3. Forward substring match against full franchise names (covers The Odds API's
  #    `home_team`/`away_team` fields, which use full names like "Las Vegas Aces").
  hit <- full_names[vapply(tolower(full_names), function(fn) grepl(fn, s, fixed = TRUE), logical(1))]
  if (length(hit) >= 1) return(hit[1])

  # 4. Nickname-only match (last word of the full name, e.g. "Aces", "Storm").
  #    FINDING L-1: `nick` is length 15, so paste0("\\b", nick, "\\b") used to be
  #    handed to grepl() as a length-15 `pattern` — grepl uses only element [1]
  #    ("dream") and warns, then `|` recycles that single result across all 15
  #    positions. Harmless only because WNBA_TEAMS happens to start with Atlanta;
  #    config.R explicitly anticipates re-ordering on expansion. Vectorized with
  #    vapply() so each nickname is genuinely tested against the input.
  nick <- tolower(word(full_names, -1))
  hit_nick <- full_names[vapply(nick, function(n) grepl(paste0("\\b", n, "\\b"), s), logical(1))]
  if (length(hit_nick) >= 1) return(hit_nick[1])

  # FINDING H-4: no match -> NA_character_, NOT the raw input passed through. The
  # caller (get_model_slate_probabilities()) must handle NA explicitly; its
  # `nrow(h_row) > 0` standings check routes NA into the devigged-consensus
  # fallback, same as any other unrecognized team.
  log_warn("resolve_team_name(): input did not match any WNBA franchise; returning NA.",
           call = "resolve_team_name()", unresolved_value = as.character(tm_raw))
  NA_character_
}

# Map a canonical full WNBA_TEAMS name back to its abbreviation (used for the
# shot-quality/fatigue caches, which are keyed on abbreviation, not full name).
abbr_for <- function(full_name) {
  idx <- match(full_name, WNBA_TEAMS)
  if (is.na(idx)) return(NA_character_)
  names(WNBA_TEAMS)[idx]
}

# ------------------------------------------------------------------------------
# Ingest Multi-Book Feeds & Parse True Local Game Dates
# ------------------------------------------------------------------------------
fetch_market_odds <- function() {
  api_key <- Sys.getenv("ODDS_API_KEY", "")

  if (nchar(api_key) > 0) {
    # FINDING H-1: the API key is NEVER interpolated into a URL string. The base URL
    # is keyless and is the only thing that is ever logged, printed, or passed
    # around; the secret is attached by httr2::req_url_query() on the request object
    # itself, immediately before req_perform(). This is layer 1 of 2 — Wave 1 also
    # added redaction inside logging_utils.R's sink (defense in depth), but the sink
    # must not be the ONLY thing standing between a credential and a plaintext log.
    base_url <- "https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/"

    cat("[FEED] Querying live multi-region WNBA odds from The Odds API...\n")
    log_info("Querying live multi-region WNBA odds from The Odds API.",
             call = "fetch_market_odds()", url = base_url)
    resp_raw <- tryCatch({
      request(base_url) |>
        req_url_query(
          regions     = "us,us2,eu",
          markets     = "h2h",
          oddsFormat  = "american",
          apiKey      = api_key
        ) |>
        req_timeout(8) |>
        req_retry(max_tries = 3) |>
        req_perform() |>
        resp_body_json(simplifyVector = TRUE)
    }, error = function(e) {
      # H-1: log the KEYLESS base URL only. `condition = e` is still safe because
      # logging_utils.R's .log_redact() scrubs apiKey= out of any condition message
      # httr2 may have embedded the full request URL into.
      cat(sprintf("[FEED WARNING] API query failed (%s). Using calibrated fixture slate.\n", e$message))
      log_error("Odds API request failed.", condition = e, call = "fetch_market_odds()", url = base_url)
      NULL
    })

    if (!is.null(resp_raw) && length(resp_raw) > 0 && nrow(resp_raw) > 0) {
      cat(sprintf("[FEED SUCCESS] Parsing %d live WNBA games from API.\n", nrow(resp_raw)))
      log_info(sprintf("Odds API returned %d live WNBA games.", nrow(resp_raw)),
               call = "fetch_market_odds()", rows = nrow(resp_raw))
      parsed <- parse_multi_book_feed(resp_raw)
      if (nrow(parsed) > 0) {
        log_info(sprintf("Parsed %d live games with usable bookmaker odds.", nrow(parsed)),
                 call = "parse_multi_book_feed()", rows = nrow(parsed))
        # FINDING M-5: provenance marker travels WITH the slate, so every downstream
        # consumer (evaluate_betting_slate() -> latest_value_bets.rds ->
        # prediction_accuracy_logger.R::log_todays_predictions()) can tell a real
        # slate from the fixture slate. Mirrors the existing injury_data_source
        # pattern. Contract: character, "LIVE_ODDS_API" | "SYNTHETIC_FALLBACK".
        return(parsed |> mutate(market_data_source = "LIVE_ODDS_API"))
      }
      log_warn("Odds API returned games but none had parseable bookmaker odds; falling back to fixture slate.",
               call = "fetch_market_odds()")
    }
  } else {
    cat("[FEED NOTICE] ODDS_API_KEY not set in this environment. ")
    log_warn("ODDS_API_KEY not set in this environment; using SYNTHETIC_FALLBACK fixture slate.",
             call = "fetch_market_odds()")
  }

  # ----------------------------------------------------------------------------
  # FIXTURE FALLBACK — clearly labeled synthetic/demo slate, not live odds.
  # Real current (2026) WNBA franchises from config.R's WNBA_TEAMS (verified by T0
  # via web search + live wehoop data), NOT the NBA original's hardcoded NBA teams.
  # Matchups/odds/dates below are fabricated for demonstration only.
  # ----------------------------------------------------------------------------
  cat("[FEED NOTICE] Using calibrated WNBA fixture slate (SYNTHETIC_FALLBACK — no live odds).\n")
  log_warn("Using SYNTHETIC_FALLBACK calibrated WNBA fixture slate (no live odds).",
           call = "fetch_market_odds()", data_source = "SYNTHETIC_FALLBACK")
  tibble(
    game_id           = paste0("WNBA_GAME_", 1:6),
    game_date         = as.Date(c("2026-09-14", "2026-09-14", "2026-09-15", "2026-09-15", "2026-09-16", "2026-09-16")),
    tip_time_est      = c("19:00", "21:30", "18:00", "20:00", "19:30", "22:00"),
    matchup           = c("Seattle Storm vs. Minnesota Lynx", "Los Angeles Sparks vs. Las Vegas Aces",
                          "Washington Mystics vs. New York Liberty", "Chicago Sky vs. Atlanta Dream",
                          "Dallas Wings vs. Phoenix Mercury", "Connecticut Sun vs. Indiana Fever"),
    home_team         = c("Minnesota Lynx", "Las Vegas Aces", "New York Liberty", "Atlanta Dream", "Phoenix Mercury", "Indiana Fever"),
    away_team         = c("Seattle Storm", "Los Angeles Sparks", "Washington Mystics", "Chicago Sky", "Dallas Wings", "Connecticut Sun"),
    best_retail_book  = c("DraftKings", "FanDuel", "BetMGM", "Caesars", "DraftKings", "FanDuel"),
    home_ml           = c(-210, -260, -145, +110, -120, -175),
    away_ml           = c(+175, +215, +122, -130, +100, +150),
    consensus_home_ml = c(-225, -280, -152, +102, -128, -188),
    consensus_away_ml = c(+188, +230, +130, -118, +108, +162),
    # FINDING M-5: these six matchups are FABRICATED and can never reconcile against
    # a real box score. The marker below is the only thing that lets
    # prediction_accuracy_logger.R tell that and exclude/flag these rows.
    market_data_source = "SYNTHETIC_FALLBACK"
  )
}

parse_multi_book_feed <- function(games_df) {
  results <- list()
  sharp_keys <- c("pinnacle", "circa", "lowvig", "betonlineag")

  for (i in seq_len(nrow(games_df))) {
    game <- games_df[i, ]
    bks  <- game$bookmakers[[1]]
    if (is.null(bks) || nrow(bks) == 0) next

    home_team <- game$home_team
    away_team <- game$away_team

    # Accurate UTC -> US Eastern Local Conversion
    commence_raw <- game$commence_time %||% paste0(Sys.Date(), "T00:00:00Z")
    utc_time <- as.POSIXct(commence_raw, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    local_time <- format(utc_time, tz = "America/New_York", usetz = FALSE)

    game_date <- as.Date(substr(local_time, 1, 10))
    game_tip_est <- substr(local_time, 12, 16)

    home_odds_list <- c()
    away_odds_list <- c()
    best_h_book <- "DraftKings"
    best_h_odds <- -9999
    best_a_book <- "DraftKings"
    best_a_odds <- -9999
    sharp_h <- NA_real_
    sharp_a <- NA_real_

    for (b in seq_len(nrow(bks))) {
      b_key   <- bks$key[b]
      b_title <- bks$title[b]
      mkts    <- bks$markets[[b]]
      if (is.null(mkts) || nrow(mkts) == 0) next
      h2h     <- mkts |> filter(key == "h2h")
      if (nrow(h2h) == 0) next
      outs    <- h2h$outcomes[[1]]

      h_row <- outs |> filter(tolower(name) == tolower(home_team))
      a_row <- outs |> filter(tolower(name) == tolower(away_team))

      if (nrow(h_row) > 0 && nrow(a_row) > 0) {
        h_price <- as.numeric(h_row$price[1])
        a_price <- as.numeric(a_row$price[1])

        home_odds_list <- c(home_odds_list, h_price)
        away_odds_list <- c(away_odds_list, a_price)

        # Sharp-book detection (pinnacle/circa/lowvig/betonlineag). Per the plan's
        # risk #2, expect this to hit far less often on WNBA slates than NBA slates
        # (thinner book coverage) — the devigged-consensus fallback below already
        # handles that; do not remove or loosen it.
        if (b_key %in% sharp_keys) {
          sharp_h <- h_price
          sharp_a <- a_price
        }

        if (h_price > best_h_odds) {
          best_h_odds <- h_price
          best_h_book <- b_title
        }
        if (a_price > best_a_odds) {
          best_a_odds <- a_price
          best_a_book <- b_title
        }
      }
    }

    if (length(home_odds_list) > 0) {
      mean_h_prob <- mean(american_to_prob(home_odds_list))
      mean_a_prob <- mean(american_to_prob(away_odds_list))
      fair_cons_h <- mean_h_prob / (mean_h_prob + mean_a_prob)
      fair_cons_a <- mean_a_prob / (mean_h_prob + mean_a_prob)

      cons_h_ml <- ifelse(!is.na(sharp_h), sharp_h, prob_to_american(fair_cons_h))
      cons_a_ml <- ifelse(!is.na(sharp_a), sharp_a, prob_to_american(fair_cons_a))

      results[[length(results) + 1]] <- tibble(
        game_id           = game$id,
        game_date         = game_date,
        tip_time_est      = game_tip_est,
        matchup           = paste(away_team, "vs.", home_team),
        home_team         = home_team,
        away_team         = away_team,
        best_retail_book  = best_h_book,
        home_ml           = best_h_odds,
        away_ml           = best_a_odds,
        consensus_home_ml = cons_h_ml,
        consensus_away_ml = cons_a_ml
      )
    }
  }
  bind_rows(results)
}

# ------------------------------------------------------------------------------
# Model Probabilities & Multi-Factor Margins
# ------------------------------------------------------------------------------
get_model_slate_probabilities <- function(slate_df) {
  # T2's exact standings-cache filename (NOT the NBA name `projected_30_team_standings.rds`
  # — see task_assignments.md T2 Handoff Notes).
  standings_path <- file.path(CACHE_DIR, "projected_wnba_standings.rds")
  if (!file.exists(standings_path)) standings_path <- "cache/projected_wnba_standings.rds"

  sq_path <- file.path(CACHE_DIR, "team_shot_quality.rds")
  fatigue_path <- file.path(CACHE_DIR, "travel_fatigue_metrics.rds")

  if (file.exists(standings_path)) {
    standings <- readRDS(standings_path)
    c_names <- names(standings)
    tm_col  <- c_names[tolower(c_names) %in% c("team", "team_name")][1]
    net_col <- c_names[tolower(c_names) %in% c("net_rating", "bottom_up_net_rating")][1]

    sq_db <- if (file.exists(sq_path)) readRDS(sq_path) else NULL
    fatigue_db <- if (file.exists(fatigue_path)) readRDS(fatigue_path) else NULL

    home_probs <- numeric(nrow(slate_df))
    fair_margins <- numeric(nrow(slate_df))
    net_diffs    <- numeric(nrow(slate_df))
    hcas         <- numeric(nrow(slate_df))
    fatigues     <- numeric(nrow(slate_df))

    for (i in seq_len(nrow(slate_df))) {
      h_canon <- resolve_team_name(slate_df$home_team[i])
      a_canon <- resolve_team_name(slate_df$away_team[i])
      h_abbr  <- abbr_for(h_canon)
      a_abbr  <- abbr_for(a_canon)

      h_row <- standings |> filter(tolower(.data[[tm_col]]) == tolower(h_canon))
      a_row <- standings |> filter(tolower(.data[[tm_col]]) == tolower(a_canon))

      if (nrow(h_row) > 0 && nrow(a_row) > 0) {
        h_net <- as.numeric(h_row[[net_col]][1])
        a_net <- as.numeric(a_row[[net_col]][1])

        # T3's team_shot_quality.rds is keyed on WNBA team ABBREVIATION, not full
        # name — join via abbr_for(), not the canonical full name directly.
        if (!is.null(sq_db) && !is.na(h_abbr) && !is.na(a_abbr)) {
          h_luck <- sq_db$shooting_luck_pts[toupper(sq_db$team) == h_abbr][1] %||% 0.0
          a_luck <- sq_db$shooting_luck_pts[toupper(sq_db$team) == a_abbr][1] %||% 0.0
          h_net <- h_net - (0.50 * h_luck)
          a_net <- a_net - (0.50 * a_luck)
        }

        # Ceiling/Floor Adjustment
        h_net <- apply_rating_limits(h_net)
        a_net <- apply_rating_limits(a_net)

        fatigue_drag <- 0.0
        if (!is.null(fatigue_db) && !is.na(h_abbr) && !is.na(a_abbr)) {
          f_match <- fatigue_db |> filter(
            toupper(away_team) == a_abbr & toupper(home_team) == h_abbr
          )
          if (nrow(f_match) > 0) fatigue_drag <- f_match$point_spread_drag[1]
        }

        # FINDING C-1: home-court advantage is read from `config.R::WNBA_HCA`. It is
        # NOT restated as a literal here. This line previously added a hardcoded
        # `11.6` while the comment above it documented `2.40` — `11.6` was the NBA
        # original's sigma-family constant pasted into the HCA slot, which made the
        # model believe two identical teams win at home 79.6% of the time (real WNBA
        # rate ~55-58%), saturating Kelly at the 3% cap on every recommendation.
        # Sigma likewise comes from config.R's empirically-derived
        # WNBA_MARGIN_SIGMA, NOT the NBA original's hardcoded 11.2 — WNBA margins run
        # wider (fewer possessions/game). Read both from config.R; do not re-derive
        # or restate either number in this file.
        fair_margin <- (h_net - a_net) + WNBA_HCA + fatigue_drag + calculate_matchup_delta(h_abbr, a_abbr)
        p_home <- pnorm(fair_margin / WNBA_MARGIN_SIGMA)
        p_home <- min(max(p_home, 0.03), 0.97)
        home_probs[i] <- round(p_home, 3)
        fair_margins[i] <- fair_margin
        net_diffs[i]    <- h_net - a_net
        hcas[i]         <- WNBA_HCA  # FINDING C-1: config.R constant, never a literal
        fatigues[i]     <- fatigue_drag
      } else {
        p_raw_h <- american_to_prob(slate_df$consensus_home_ml[i])
        p_raw_a <- american_to_prob(slate_df$consensus_away_ml[i])
        home_probs[i] <- round(p_raw_h / (p_raw_h + p_raw_a), 3)
      }
    }
    return(slate_df |> mutate(
      model_home_prob    = home_probs,
      predicted_margin   = fair_margins,
      contrib_net_diff    = net_diffs,
      contrib_hca         = hcas,
      contrib_fatigue     = fatigues
    ))
  }

  # 2026-09-19 fix: this fallback (cache/projected_wnba_standings.rds missing) used to
  # return a data frame with model_home_prob = 0.50 and NO predicted_margin/contrib_*
  # columns at all. Two real downstream failure modes: (a) evaluate_betting_slate()'s
  # select(predicted_margin = predicted_margin, ...) would hard-error on the missing
  # column rather than degrading gracefully (violates this repo's fail-safe convention
  # - see CLAUDE.md "Process/conventions"); (b) if that select() were ever relaxed to
  # tolerate it, downstream MAE/RMSE/bias diagnostics (app.R's Model Diagnostics tab,
  # tools/check_accuracy_0916_0917.R) would silently score against a fabricated margin.
  # Explicit NA_real_ + a loud warning keeps the schema consistent AND makes the
  # degraded state visible in logs, instead of a silent 50/50 guess or a crash.
  log_warn("cache/projected_wnba_standings.rds not found; returning a degraded slate with model_home_prob = 0.50 and NA predicted_margin/contrib_* for every game (not a real model prediction).",
           call = "get_model_slate_probabilities()")
  slate_df |> mutate(
    model_home_prob  = 0.50,
    predicted_margin = NA_real_,
    contrib_net_diff = NA_real_,
    contrib_hca      = NA_real_,
    contrib_fatigue  = NA_real_
  )
}

# ------------------------------------------------------------------------------
# Master Evaluation & Cache Writer (Preserves Exact Game Dates)
# Output: cache/latest_value_bets.rds, cache/odds_history.rds
# ------------------------------------------------------------------------------
evaluate_betting_slate <- function() {
  cat("\n==================================================================\n")
  cat("           WNBA VALUE BETTING & CLV ENGINE (+EV IDENTIFIER)        \n")
  cat("==================================================================\n\n")

  raw_slate <- fetch_market_odds()

  snapshot <- raw_slate |> mutate(snapshot_time = Sys.time(), bet_date = Sys.Date())
  if (file.exists(file.path(CACHE_DIR, "odds_history.rds"))) {
    existing_hist <- readRDS(file.path(CACHE_DIR, "odds_history.rds"))
    saveRDS(bind_rows(existing_hist, snapshot), file.path(CACHE_DIR, "odds_history.rds"))
  } else {
    saveRDS(snapshot, file.path(CACHE_DIR, "odds_history.rds"))
  }

  slate <- get_model_slate_probabilities(raw_slate) |>
    mutate(
      model_away_prob = 1 - model_home_prob,
      home_dec = american_to_decimal(home_ml),
      away_dec = american_to_decimal(away_ml),

      cons_imp_h = american_to_prob(consensus_home_ml),
      cons_imp_a = american_to_prob(consensus_away_ml),
      cons_fair_h = cons_imp_h / (cons_imp_h + cons_imp_a),
      cons_fair_a = cons_imp_a / (cons_imp_h + cons_imp_a),

      home_ev = round((model_home_prob * home_dec - 1) * 100, 2),
      away_ev = round((model_away_prob * away_dec - 1) * 100, 2),

      home_exp_clv = round(((home_dec * cons_fair_h) - 1) * 100, 2),
      away_exp_clv = round(((away_dec * cons_fair_a) - 1) * 100, 2),

      pick_home   = home_ev > away_ev,
      bet_side    = if_else(pick_home, paste(home_team, "(Home)"), paste(away_team, "(Away)")),
      team_picked = if_else(pick_home, home_team, away_team),
      best_ev     = pmax(home_ev, away_ev),
      best_odds   = if_else(pick_home, home_ml, away_ml),
      best_dec    = if_else(pick_home, home_dec, away_dec),
      best_prob   = if_else(pick_home, model_home_prob, model_away_prob),
      cons_ml     = if_else(pick_home, consensus_home_ml, consensus_away_ml),
      exp_clv     = if_else(pick_home, home_exp_clv, away_exp_clv),

      # Staking discipline unchanged from NBA (Quarter-Kelly, 3% cap) — thinner WNBA
      # book depth is a DATA-QUALITY flag for the dashboard, not a reason to loosen
      # this.
      quarter_kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
      edge_flag = case_when(
        best_ev >= 5.0 & exp_clv > 0.0 ~ "\U0001F525 SHARP +EV (EV \u2265 5% & CLV > 0)",
        best_ev >= 3.0                 ~ "\u2605 VALUE BET (+EV)",
        TRUE                           ~ "No Action"
      )
    )

  # Explicitly preserve game_date and tip_time_est
  output_table <- slate |>
    select(
      game_date         = game_date,
      tip_time_est      = tip_time_est,
      Matchup           = matchup,
      Recommended_Bet   = bet_side,
      Team              = team_picked,
      Book              = best_retail_book,
      Line              = best_odds,
      Model_Win_Prob    = best_prob,
      predicted_margin   = predicted_margin,
      contrib_net_diff    = contrib_net_diff,
      contrib_hca         = contrib_hca,
      contrib_fatigue     = contrib_fatigue,
      EV_Percent        = best_ev,
      Exp_CLV           = exp_clv,
      Bankroll_Rec      = quarter_kelly_pct,
      Status            = edge_flag,
      sharp_line        = cons_ml,
      game_id           = game_id,
      # FINDING M-5: carried through to cache/latest_value_bets.rds so
      # prediction_accuracy_logger.R::log_todays_predictions() can record slate
      # provenance ("LIVE_ODDS_API" / "SYNTHETIC_FALLBACK") on each logged row.
      market_data_source = market_data_source
    ) |>
    arrange(game_date, desc(EV_Percent))

  display_table <- output_table |> select(-game_id, -sharp_line, -Team, -market_data_source)
  print(knitr::kable(display_table, format = "simple"))

  out_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
  saveRDS(output_table, out_path)
  cat(sprintf("\n[SUCCESS] Timezone-calibrated WNBA value bets saved to: %s\n", out_path))
  log_info(sprintf("Saved %d value bets to %s.", nrow(output_table), out_path),
           call = "evaluate_betting_slate()", rows = nrow(output_table), out_path = out_path)

  # Appended, NEVER-overwritten history of this exact output_table (full model inputs:
  # predicted_margin/contrib_*/market_data_source per game_id), same accumulate-don't-
  # overwrite pattern already used for odds_history.rds above. Added 2026-09-19
  # (docs/HANDOFF.md open item 4): latest_value_bets.rds itself is overwritten every run,
  # which is exactly why 5 already-logged prediction_accuracy_log.rds rows with NA
  # predicted_margin could not be forensically diagnosed after the fact — "the exact
  # model inputs at that prediction moment aren't reconstructable from any surviving
  # cache." This closes that gap going forward: prediction_accuracy_logger.R's
  # log_todays_predictions() (or any future debugging session) can now join
  # cache/value_bets_history.rds by game_id to recover the exact predicted_margin/
  # contrib_* values that were live at any past snapshot_time, not just today's.
  history_path <- file.path(CACHE_DIR, "value_bets_history.rds")
  history_snapshot <- output_table |> mutate(snapshot_time = Sys.time())
  if (file.exists(history_path)) {
    existing_history <- tryCatch(readRDS(history_path), error = function(e) NULL)
    if (is.null(existing_history)) {
      log_warn(sprintf("%s exists but failed to read; starting a fresh history rather than blocking the slate.", history_path),
               call = "evaluate_betting_slate()")
      saveRDS(history_snapshot, history_path)
    } else {
      saveRDS(bind_rows(existing_history, history_snapshot), history_path)
    }
  } else {
    saveRDS(history_snapshot, history_path)
  }

  return(output_table)
}

evaluate_betting_slate()
