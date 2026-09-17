# ==============================================================================
# market_odds_engine.R (NFL port)
# Phase 6 (task P6-A) - Market Odds / Value-Betting Engine
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/market_odds_engine.R
#
# Ported from the WNBA Analytics repo's market_odds_engine.R. Sport-agnostic pieces
# (american_to_decimal/american_to_prob/prob_to_american/calculate_kelly, sharp-book
# detection, devig-consensus math, The Odds API integration shape, H-1 secret handling)
# are unchanged in shape. DELIBERATE improvement over the WNBA version, per
# docs/task_assignments_phase5.md's Overview:
#
#   WNBA's market_odds_engine.R re-derives its own model win-probability from
#   standings net-rating + fatigue + HCA/sigma computed INLINE, duplicating logic
#   that also exists independently in that repo's rating engine - a second place
#   the same math can silently drift (exactly the class of bug config.R's own
#   Finding C-1 header warns about). This repo already has team_ratings_engine.R
#   writing real per-game model probabilities to cache/projected_matchups.rds for
#   every upcoming CACHE_SCHEDULES game (home_win_prob, projected_margin - the
#   latter already includes NFL_HCA, verified by reading team_ratings_engine.R's
#   own projected_margin <- (home_rating - away_rating) + NFL_HCA line). THIS
#   ENGINE MUST CONSUME THAT CACHE AS ITS MODEL-PROBABILITY SOURCE, layering only a
#   fatigue adjustment (from cache/fatigue_metrics.rds's per-team fatigue_drag_pts)
#   on top, recomputed via pnorm() using config.R's NFL_HCA/NFL_MARGIN_SIGMA
#   (referenced, never restated - see NFL_MARGIN_SIGMA below).
#
# Other NFL-specific changes from the WNBA port:
#   1. The Odds API sport key swapped basketball_wnba -> americanfootball_nfl.
#      Verified LIVE against GET /v4/sports/ on 2026-09-16: "americanfootball_nfl"
#      is present, active = TRUE. Env var name (ODDS_API_KEY) is UNCHANGED - the
#      same Odds API account/key intentionally works for both sibling repos (see
#      config.R's Secrets/Webhooks section comment on why ODDS_API_KEY, unlike
#      NFL_DISCORD_WEBHOOK, is deliberately NOT namespaced).
#   2. Fixture fallback rewritten to real current NFL_TEAMS franchises (fabricated
#      odds/dates), tagged market_data_source = "SYNTHETIC_FALLBACK".
#   3. resolve_team_name() canonicalizes against NFL_TEAMS and returns the
#      ABBREVIATION (not the full name, unlike WNBA's version) - because BOTH
#      cache/projected_matchups.rds (home_team/away_team) and
#      cache/fatigue_metrics.rds (team/opponent) key on abbreviation already, so no
#      separate abbr_for() reverse-lookup helper is needed here.
#   4. Model probability source: cache/projected_matchups.rds (columns verified live
#      via readRDS() on 2026-09-16: game_id, season, week, home_team, away_team,
#      home_power_rating, away_power_rating, projected_margin, home_win_prob - NOT
#      the task-assignment doc's placeholder names model_home_prob/predicted_margin;
#      same "doc names vs. real cache names diverge" lesson as the WNBA repo's T2
#      standings-filename rename). Joined to cache/schedules_cache.rds by game_id
#      (both caches share nflverse's game_id key) to recover each game's gameday,
#      then matched to the live odds slate by (home abbr, away abbr, date).
#   5. Fatigue adjustment: cache/fatigue_metrics.rds is LONG (one row per team per
#      game, column fatigue_drag_pts = non-negative points that TEAM's own expected
#      performance is dragged down by - confirmed by reading
#      fatigue_engine.R::calculate_travel_fatigue_vec(), which only ever adds
#      non-negative distance/circadian/altitude/short-week taxes into
#      fatigue_drag_pts). A team's OWN drag hurts its OWN margin; the OPPONENT's
#      drag helps this team's relative margin. So, from the home team's
#      perspective: fatigue_adjustment = away_fatigue_drag_pts - home_fatigue_drag_pts.
#      adjusted_margin = projected_margin + fatigue_adjustment
#      adjusted_home_prob = pnorm(adjusted_margin / NFL_MARGIN_SIGMA)
#      Both NFL_HCA (already baked into projected_margin upstream - not re-added
#      here) and NFL_MARGIN_SIGMA are read from config.R, never restated (Finding
#      C-1 discipline).
#   6. Exposed function is run_market_odds_engine(), returns TRUE/FALSE (not the
#      value-bets tibble the WNBA version returned) - this repo's run_full_pipeline.R
#      wiring convention (per docs/task_assignments_phase5.md's Interface Contract).
#      No sys.nframe()/!interactive() auto-run footer - this repo's established
#      8-stage convention is call_fn-style explicit invocation only.
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/NFL Analytics"
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(httr2)
  library(jsonlite)
  library(dplyr)
  library(tidyr)
  library(stringr)
})

source("config.R")
source("logging_utils.R")
.LOG_SCRIPT <- "market_odds_engine.R"

# FINDING M-6: the local scalar `%||%` that used to live in the WNBA original has been
# REMOVED here too. The single canonical (hardened) definition lives in logging_utils.R,
# sourced immediately above - do not re-add a local copy.

# ------------------------------------------------------------------------------
# Sport-agnostic odds/EV/Kelly math - ported VERBATIM in shape from the WNBA repo's
# market_odds_engine.R (which itself ported these unchanged from the NBA original).
# Do not loosen the Kelly fraction (0.25) or its 3.0% cap "to compensate" for
# anything (per docs/task_assignments_phase5.md's Constraints section).
# ------------------------------------------------------------------------------
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
# Team-name canonicalization against config.R's single source of truth, NFL_TEAMS
# (abbreviation -> full franchise name). Returns the ABBREVIATION (unlike WNBA's
# version, which returned the full name) because both cache/projected_matchups.rds
# and cache/fatigue_metrics.rds already key on abbreviation.
# ------------------------------------------------------------------------------
resolve_team_name <- function(tm_raw) {
  s <- tolower(trimws(as.character(tm_raw)))
  full_names <- unname(NFL_TEAMS)
  abbrs      <- names(NFL_TEAMS)

  # FINDING H-4 (ported hardening, same pattern as WNBA's version): this function is
  # the canonicalization boundary between The Odds API's UNTRUSTED home_team/away_team
  # fields and the internal projected_matchups/fatigue lookups that produce money
  # recommendations. Two rules, both load-bearing:
  #  (a) Minimum input length gate. Degenerate inputs ("", "a", "s") must NOT resolve.
  #  (b) NO reverse-containment clause (`grepl(s, fn, fixed = TRUE)` - does the INPUT
  #      appear inside the franchise name?) - only the forward direction is used:
  #      does a franchise name/abbr appear inside the input. The reverse direction is
  #      exactly what let "" match every team in the original NBA/WNBA bug lineage.
  if (length(s) != 1 || is.na(s)) {
    log_warn("resolve_team_name(): non-scalar/NA input could not be resolved to an NFL franchise.",
             call = "resolve_team_name()", unresolved_value = paste(as.character(tm_raw), collapse = ","))
    return(NA_character_)
  }

  # 1. Exact abbreviation match (covers internal callers already passing an
  #    NFL_TEAMS abbreviation, e.g. "BUF", "LA"). Checked BEFORE the length gate -
  #    NFL abbreviations are 2-3 characters ("LA", "GB", "SF", "BUF"), so they would
  #    otherwise be collateral damage of the length gate below.
  hit_ab <- abbrs[tolower(abbrs) == s]
  if (length(hit_ab) >= 1) return(unname(hit_ab[1]))

  # 2. H-4 length gate: below 4 characters nothing but an exact abbreviation (already
  #    checked above) can be trusted - refuse rather than guess.
  if (nchar(s) < 4) {
    log_warn("resolve_team_name(): input too short to resolve to an NFL franchise (H-4 guard).",
             call = "resolve_team_name()", unresolved_value = as.character(tm_raw))
    return(NA_character_)
  }

  # 3. Forward substring match against full franchise names (covers The Odds API's
  #    home_team/away_team fields, which use full names like "Buffalo Bills").
  hit <- abbrs[vapply(tolower(full_names), function(fn) grepl(fn, s, fixed = TRUE), logical(1))]
  if (length(hit) >= 1) return(unname(hit[1]))

  # 4. Nickname-only match (last word of the full name, e.g. "Bills", "Chiefs").
  #    Vectorized with vapply() (per WNBA's Finding L-1) so each nickname is
  #    genuinely tested against the input, rather than grepl() silently only using
  #    pattern[1] and recycling across all 32 positions.
  nick <- tolower(word(full_names, -1))
  hit_nick <- abbrs[vapply(nick, function(n) grepl(paste0("\\b", n, "\\b"), s), logical(1))]
  if (length(hit_nick) >= 1) return(unname(hit_nick[1]))

  # FINDING H-4: no match -> NA_character_, NOT the raw input passed through.
  log_warn("resolve_team_name(): input did not match any NFL franchise; returning NA.",
           call = "resolve_team_name()", unresolved_value = as.character(tm_raw))
  NA_character_
}

# ------------------------------------------------------------------------------
# Ingest Multi-Book Feeds & Parse True Local Game Dates
# ------------------------------------------------------------------------------
fetch_market_odds <- function() {
  api_key <- Sys.getenv("ODDS_API_KEY", "")

  if (nchar(api_key) > 0) {
    # FINDING H-1: the API key is NEVER interpolated into a URL string. The base URL
    # is keyless and is the only thing that is ever logged, printed, or passed
    # around; the secret is attached via httr2::req_url_query() on the request
    # object itself, immediately before req_perform(). logging_utils.R's
    # .log_redact() sink is defense-in-depth layer 2, not the only protection.
    base_url <- "https://api.the-odds-api.com/v4/sports/americanfootball_nfl/odds/"

    cat("[FEED] Querying live multi-region NFL odds from The Odds API...\n")
    log_info("Querying live multi-region NFL odds from The Odds API.",
             call = "fetch_market_odds()", url = base_url)
    resp_raw <- tryCatch({
      request(base_url) |>
        req_url_query(
          regions     = "us,us2,eu",
          markets     = "h2h",
          oddsFormat  = "american",
          apiKey      = api_key
        ) |>
        req_timeout(15) |>
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

    if (!is.null(resp_raw) && length(resp_raw) > 0 && is.data.frame(resp_raw) && nrow(resp_raw) > 0) {
      cat(sprintf("[FEED SUCCESS] Parsing %d live NFL games from API.\n", nrow(resp_raw)))
      log_info(sprintf("Odds API returned %d live NFL games.", nrow(resp_raw)),
               call = "fetch_market_odds()", rows = nrow(resp_raw))
      parsed <- parse_multi_book_feed(resp_raw)
      if (nrow(parsed) > 0) {
        log_info(sprintf("Parsed %d live games with usable bookmaker odds.", nrow(parsed)),
                 call = "parse_multi_book_feed()", rows = nrow(parsed))
        # FINDING M-5: provenance marker travels WITH the slate so every downstream
        # consumer can tell a real slate from the fixture slate.
        return(parsed |> mutate(market_data_source = "LIVE_ODDS_API"))
      }
      log_warn("Odds API returned games but none had parseable bookmaker odds; falling back to fixture slate.",
               call = "fetch_market_odds()")
    } else {
      log_warn("Odds API returned zero usable games; falling back to fixture slate.",
               call = "fetch_market_odds()")
    }
  } else {
    cat("[FEED NOTICE] ODDS_API_KEY not set in this environment. ")
    log_warn("ODDS_API_KEY not set in this environment; using SYNTHETIC_FALLBACK fixture slate.",
             call = "fetch_market_odds()")
  }

  # ----------------------------------------------------------------------------
  # FIXTURE FALLBACK - clearly labeled synthetic/demo slate, not live odds. Real
  # current NFL franchises from config.R's NFL_TEAMS. Matchups/odds/dates below are
  # fabricated for demonstration only.
  # ----------------------------------------------------------------------------
  cat("[FEED NOTICE] Using calibrated NFL fixture slate (SYNTHETIC_FALLBACK - no live odds).\n")
  log_warn("Using SYNTHETIC_FALLBACK calibrated NFL fixture slate (no live odds).",
           call = "fetch_market_odds()", data_source = "SYNTHETIC_FALLBACK")
  tibble(
    game_id           = paste0("NFL_GAME_", 1:6),
    game_date         = as.Date(c("2026-09-20", "2026-09-20", "2026-09-20", "2026-09-21", "2026-09-21", "2026-09-24")),
    tip_time_est      = c("13:00", "13:00", "16:25", "13:00", "20:20", "20:15"),
    matchup           = c("Detroit Lions vs. Buffalo Bills", "Carolina Panthers vs. Atlanta Falcons",
                          "New Orleans Saints vs. Baltimore Ravens", "Cincinnati Bengals vs. Houston Texans",
                          "Green Bay Packers vs. New York Jets", "Cleveland Browns vs. Tampa Bay Buccaneers"),
    home_team         = c("Buffalo Bills", "Atlanta Falcons", "Baltimore Ravens", "Houston Texans", "New York Jets", "Tampa Bay Buccaneers"),
    away_team         = c("Detroit Lions", "Carolina Panthers", "New Orleans Saints", "Cincinnati Bengals", "Green Bay Packers", "Cleveland Browns"),
    best_retail_book  = c("DraftKings", "FanDuel", "BetMGM", "Caesars", "DraftKings", "FanDuel"),
    home_ml           = c(-210, -145, -175, -120, +105, -160),
    away_ml           = c(+175, +122, +150, +100, -125, +135),
    consensus_home_ml = c(-225, -152, -188, -128, +98, -170),
    consensus_away_ml = c(+188, +130, +162, +108, -118, +145),
    # FINDING M-5: these six matchups are FABRICATED and can never reconcile against
    # a real box score. The marker below is the only thing that lets a future
    # prediction-accuracy logger tell that and exclude/flag these rows.
    market_data_source = "SYNTHETIC_FALLBACK"
  )
}

# ------------------------------------------------------------------------------
# fetch_devigged_market_probs() - Phase 1 (model-quality remediation, docs/HANDOFF.md's
# post-backtest roadmap). Small, reusable extraction of this file's existing devig math
# (american_to_prob() + 2-way normalization, same formula already used for cons_fair_h/a
# below in evaluate_betting_slate()) so team_ratings_engine.R can blend a devigged market
# probability into CACHE_PROJECTED_MATCHUPS.home_win_prob WITHOUT re-deriving model
# probability independently (that rule stays intact - see that file's own header) and
# WITHOUT this file itself changing its consumption contract.
#
# Calls fetch_market_odds() itself (same live-fetch-or-fixture-fallback function this file's
# own evaluate_betting_slate() uses) - this means team_ratings_engine.R (pipeline stage 5)
# and market_odds_engine.R (stage 9) each trigger their own Odds API call per pipeline run
# (a documented, accepted cost - see docs/HANDOFF.md's Phase 1 risk callouts - rather than
# reordering the pipeline's existing stage 5-10 dependency chain).
#
# Returns a tibble keyed by (home_team, away_team) - NFL_TEAMS ABBREVIATIONS, matching
# CACHE_PROJECTED_MATCHUPS's own key shape, via resolve_team_name() - with market_home_prob
# and market_data_source (the SYNTHETIC_FALLBACK provenance marker travels through so a
# caller can refuse to blend against fabricated fixture odds - see team_ratings_engine.R's
# use of this function for that guard).
# ------------------------------------------------------------------------------
fetch_devigged_market_probs <- function() {
  raw_slate <- fetch_market_odds()
  if (nrow(raw_slate) == 0) {
    return(tibble(home_team = character(0), away_team = character(0),
                   market_home_prob = numeric(0), market_data_source = character(0)))
  }

  home_abbr <- vapply(raw_slate$home_team, resolve_team_name, character(1))
  away_abbr <- vapply(raw_slate$away_team, resolve_team_name, character(1))
  imp_h <- american_to_prob(raw_slate$consensus_home_ml)
  imp_a <- american_to_prob(raw_slate$consensus_away_ml)

  tibble(
    home_team = home_abbr,
    away_team = away_abbr,
    market_home_prob = imp_h / (imp_h + imp_a),
    market_data_source = raw_slate$market_data_source
  ) |> filter(!is.na(home_team), !is.na(away_team))
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
    sharp_book_used <- NA_character_

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

        # Sharp-book detection (pinnacle/circa/lowvig/betonlineag). Per
        # docs/task_assignments_phase5.md's Constraints, NFL is expected to have
        # DEEPER sharp-book coverage than WNBA - verify empirically on the live run
        # rather than assuming either way. Devigged-consensus fallback below handles
        # the zero-sharp-book case regardless.
        if (b_key %in% sharp_keys) {
          sharp_h <- h_price
          sharp_a <- a_price
          sharp_book_used <- b_key
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
        consensus_away_ml = cons_a_ml,
        sharp_book_used   = sharp_book_used
      )
    }
  }
  bind_rows(results)
}

# ------------------------------------------------------------------------------
# Model Probabilities: consume cache/projected_matchups.rds (team_ratings_engine.R's
# real per-game output, already NFL_HCA-adjusted) as the SOLE model-probability
# source, joined to cache/schedules_cache.rds (shared game_id key) for gameday, then
# layer a fatigue adjustment from cache/fatigue_metrics.rds on top. Do NOT re-derive
# win probability independently (see file header).
# ------------------------------------------------------------------------------
get_model_slate_probabilities <- function(slate_df) {
  pm_path <- CACHE_PROJECTED_MATCHUPS
  sc_path <- CACHE_SCHEDULES
  fm_path <- CACHE_FATIGUE_METRICS

  if (!file.exists(pm_path)) {
    log_warn("cache/projected_matchups.rds not found; falling back to devigged-consensus probabilities only.",
             call = "get_model_slate_probabilities()", path = pm_path)
    p_raw_h <- american_to_prob(slate_df$consensus_home_ml)
    p_raw_a <- american_to_prob(slate_df$consensus_away_ml)
    return(slate_df |> mutate(
      model_home_prob  = round(p_raw_h / (p_raw_h + p_raw_a), 3),
      predicted_margin = NA_real_,
      contrib_fatigue  = NA_real_,
      home_games_played = NA_integer_,
      away_games_played = NA_integer_
    ))
  }

  pm <- readRDS(pm_path)

  # Recover each projected_matchups row's real calendar date via the shared game_id
  # key against CACHE_SCHEDULES (projected_matchups.rds itself carries no gameday
  # column - verified live via str() on 2026-09-16).
  if (file.exists(sc_path)) {
    sc <- readRDS(sc_path) |> select(game_id, gameday)
    pm <- pm |> left_join(sc, by = "game_id")
  } else {
    pm$gameday <- as.Date(NA)
  }

  fatigue <- if (file.exists(fm_path)) readRDS(fm_path) else NULL

  home_abbrs <- vapply(slate_df$home_team, resolve_team_name, character(1))
  away_abbrs <- vapply(slate_df$away_team, resolve_team_name, character(1))

  home_probs      <- rep(NA_real_, nrow(slate_df))
  adj_margins     <- rep(NA_real_, nrow(slate_df))
  base_margins    <- rep(NA_real_, nrow(slate_df))
  fatigue_adjs    <- rep(0.0, nrow(slate_df))
  matched         <- rep(FALSE, nrow(slate_df))
  # P8-B (docs/task_assignments_phase7.md): carry P8-A's per-team real current-season
  # games_played sample sizes through to the output so the staking gate below can use
  # them directly, rather than re-deriving games_played independently from CACHE_SCHEDULES
  # (a second, potentially drifting derivation of the same fact - Finding C-1 discipline).
  home_games_played_v <- rep(NA_integer_, nrow(slate_df))
  away_games_played_v <- rep(NA_integer_, nrow(slate_df))

  for (i in seq_len(nrow(slate_df))) {
    h_abbr <- home_abbrs[i]
    a_abbr <- away_abbrs[i]
    if (is.na(h_abbr) || is.na(a_abbr)) next

    cand <- pm |> filter(home_team == h_abbr, away_team == a_abbr)
    if (nrow(cand) == 0) next

    # Match on (team abbrs + date) per the Interface Contract. If multiple
    # candidate rows exist (should not, given game_id uniqueness, but defensive),
    # pick the one whose gameday is closest to the odds slate's game_date.
    game_date_i <- slate_df$game_date[i]
    if (nrow(cand) > 1 && !is.na(game_date_i) && any(!is.na(cand$gameday))) {
      cand <- cand |> arrange(abs(as.numeric(difftime(gameday, game_date_i, units = "days"))))
    }
    row <- cand[1, ]

    base_margin <- as.numeric(row$projected_margin[1])
    fatigue_adj <- 0.0

    if (!is.null(fatigue)) {
      h_fat <- fatigue |> filter(game_id == row$game_id[1], team == h_abbr) |> pull(fatigue_drag_pts)
      a_fat <- fatigue |> filter(game_id == row$game_id[1], team == a_abbr) |> pull(fatigue_drag_pts)
      h_fat <- h_fat[1] %||% NA_real_
      a_fat <- a_fat[1] %||% NA_real_
      # fatigue_drag_pts is a non-negative points-DRAG on that team's OWN expected
      # performance (fatigue_engine.R::calculate_travel_fatigue_vec() only ever adds
      # non-negative taxes). A team's own drag hurts its own margin; the opponent's
      # drag helps this team's relative margin.
      if (!is.na(h_fat) || !is.na(a_fat)) {
        fatigue_adj <- (a_fat %||% 0.0) - (h_fat %||% 0.0)
      }
    }

    adj_margin <- base_margin + fatigue_adj
    p_home <- pnorm(adj_margin / NFL_MARGIN_SIGMA)
    p_home <- min(max(p_home, 0.03), 0.97)

    home_probs[i]   <- round(p_home, 3)
    base_margins[i] <- base_margin
    adj_margins[i]  <- adj_margin
    fatigue_adjs[i] <- fatigue_adj
    matched[i]      <- TRUE
    home_games_played_v[i] <- as.integer(row$home_games_played[1])
    away_games_played_v[i] <- as.integer(row$away_games_played[1])
  }

  # Unmatched games (e.g. a team not yet in projected_matchups.rds's horizon, or a
  # resolve_team_name() miss): fall back to devigged-consensus market probability
  # rather than leaving NA, mirroring the WNBA original's fallback branch.
  if (any(!matched)) {
    log_warn(sprintf("%d of %d slate games could not be matched to cache/projected_matchups.rds; using devigged-consensus probability for those rows.",
                     sum(!matched), nrow(slate_df)),
             call = "get_model_slate_probabilities()")
    p_raw_h <- american_to_prob(slate_df$consensus_home_ml)
    p_raw_a <- american_to_prob(slate_df$consensus_away_ml)
    fallback_p <- round(p_raw_h / (p_raw_h + p_raw_a), 3)
    home_probs[!matched] <- fallback_p[!matched]
  }

  slate_df |> mutate(
    model_home_prob  = home_probs,
    predicted_margin = adj_margins,
    contrib_base_margin = base_margins,
    contrib_fatigue      = fatigue_adjs,
    model_matched        = matched,
    # P8-B: unmatched games (fallback devigged-consensus branch above) have no
    # projected_matchups.rds row to source games_played from - left NA, which the
    # staking gate below treats conservatively (NA is not >= threshold, so it gates).
    home_games_played    = home_games_played_v,
    away_games_played    = away_games_played_v
  )
}

# ------------------------------------------------------------------------------
# Master Evaluation & Cache Writer
# Output: CACHE_LATEST_VALUE_BETS (cache/latest_value_bets.rds),
#         CACHE_ODDS_HISTORY (cache/odds_history.rds)
# ------------------------------------------------------------------------------
evaluate_betting_slate <- function() {
  cat("\n==================================================================\n")
  cat("            NFL VALUE BETTING & CLV ENGINE (+EV IDENTIFIER)         \n")
  cat("==================================================================\n\n")

  raw_slate <- fetch_market_odds()

  snapshot <- raw_slate |> mutate(snapshot_time = Sys.time(), bet_date = Sys.Date())
  if (file.exists(CACHE_ODDS_HISTORY)) {
    existing_hist <- readRDS(CACHE_ODDS_HISTORY)
    saveRDS(bind_rows(existing_hist, snapshot), CACHE_ODDS_HISTORY)
  } else {
    saveRDS(snapshot, CACHE_ODDS_HISTORY)
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

      # Staking discipline: quarter-Kelly, 3% cap. Do not loosen "to compensate" for
      # thinner NFL book depth or missing model matches - a data-quality flag for a
      # future dashboard layer, not a reason to change staking math here.
      quarter_kelly_pct = calculate_kelly(best_prob, best_dec, fraction = 0.25, max_cap_pct = 3.0),
      edge_flag = case_when(
        best_ev >= 5.0 & exp_clv > 0.0 ~ "\U0001F525 SHARP +EV (EV \u2265 5% & CLV > 0)",
        best_ev >= 3.0                 ~ "\u2605 VALUE BET (+EV)",
        TRUE                           ~ "No Action"
      )
    ) |>
    mutate(
      # P8-B minimum-sample staking gate (docs/task_assignments_phase7.md), run AFTER
      # the EV-based edge_flag above so it OVERRIDES whatever Status/stake that logic
      # computed - a well-calibrated model still should not drive a real stake off 1-2
      # games of noisy current-season data (see config.R's MIN_SAMPLE_GAMES_FOR_STAKE
      # comment for the full rationale). min_games_sample uses pmin() with NA propagation
      # (an unmatched game with NA games_played is treated conservatively - gated, not
      # assumed sufficient) via the explicit is.na() check below rather than pmin()'s
      # default na.rm behavior.
      min_games_sample = pmin(home_games_played, away_games_played, na.rm = FALSE),
      insufficient_sample = is.na(min_games_sample) | (min_games_sample < MIN_SAMPLE_GAMES_FOR_STAKE),
      quarter_kelly_pct = if_else(insufficient_sample, 0, quarter_kelly_pct),
      edge_flag = if_else(insufficient_sample,
                           "\u26a0 INSUFFICIENT SAMPLE (early season)",
                           edge_flag)
    )

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
      predicted_margin  = predicted_margin,
      contrib_fatigue   = contrib_fatigue,
      EV_Percent        = best_ev,
      Exp_CLV           = exp_clv,
      Bankroll_Rec      = quarter_kelly_pct,
      Status            = edge_flag,
      home_games_played = home_games_played,
      away_games_played = away_games_played,
      sharp_line        = cons_ml,
      game_id           = game_id,
      market_data_source = market_data_source
    ) |>
    arrange(game_date, desc(EV_Percent))

  display_table <- output_table |> select(-game_id, -sharp_line, -Team, -market_data_source)
  print_ok <- tryCatch({
    print(knitr::kable(display_table, format = "simple"))
    TRUE
  }, error = function(e) FALSE)
  if (!isTRUE(print_ok)) print(display_table)

  saveRDS(output_table, CACHE_LATEST_VALUE_BETS)
  cat(sprintf("\n[SUCCESS] NFL value bets saved to: %s\n", CACHE_LATEST_VALUE_BETS))
  log_info(sprintf("Saved %d value bets to %s.", nrow(output_table), CACHE_LATEST_VALUE_BETS),
           call = "evaluate_betting_slate()", rows = nrow(output_table), out_path = CACHE_LATEST_VALUE_BETS)

  output_table
}

# ------------------------------------------------------------------------------
# Exposed entry point per docs/task_assignments_phase5.md's Interface Contract:
# no required args, returns TRUE/FALSE. No sys.nframe()/!interactive() auto-run
# guard - this repo's established call_fn-style explicit invocation convention.
# ------------------------------------------------------------------------------
run_market_odds_engine <- function() {
  result <- tryCatch({
    evaluate_betting_slate()
  }, error = function(e) {
    log_error("run_market_odds_engine() failed.", condition = e, call = "run_market_odds_engine()")
    NULL
  })
  !is.null(result)
}
