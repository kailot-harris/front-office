# ==============================================================================
# market_odds_engine.R
# Phase 5: Timezone-Aware Date Preservation & Multi-Factor Market Valuation
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/market_odds_engine.R
# ==============================================================================

PROJECT_DIR <- "c:/Users/kailo/kayceeslices/front-office/NBA Analytics"
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

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)) a else b

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

resolve_team_name <- function(tm_raw) {
  s <- tolower(trimws(as.character(tm_raw)))
  case_when(
    grepl("celtic|\\bbos\\b|boston", s)                       ~ "Celtics",
    grepl("thunder|\\bokc\\b|oklahoma", s)                    ~ "Thunder",
    grepl("cavalier|\\bcle\\b|cleveland|cavs", s)             ~ "Cavaliers",
    grepl("spur|\\bsas?\\b|san antonio", s)                   ~ "Spurs",
    grepl("warrior|\\bgsw?\\b|golden state|dubs", s)          ~ "Warriors",
    grepl("rocket|\\bhou\\b|houston", s)                      ~ "Rockets",
    grepl("knick|\\bnyk?\\b|new york", s)                     ~ "Knicks",
    grepl("piston|\\bdet\\b|detroit", s)                      ~ "Pistons",
    grepl("nugget|\\bden\\b|denver", s)                       ~ "Nuggets",
    grepl("heat|\\bmia\\b|miami", s)                          ~ "Heat",
    grepl("76er|sixer|\\bphi\\b|philadelphia", s)             ~ "76ers",
    grepl("pacer|\\bind\\b|indiana", s)                       ~ "Pacers",
    grepl("blazer|\\bpor\\b|portland", s)                     ~ "Trail Blazers",
    grepl("timberwolv|\\bmin\\b|minnesota|wolves", s)         ~ "Timberwolves",
    grepl("magic|\\borl\\b|orlando", s)                       ~ "Magic",
    grepl("grizzl|\\bmem\\b|memphis", s)                      ~ "Grizzlies",
    grepl("laker|\\blal\\b|los angeles lakers", s)            ~ "Lakers",
    grepl("raptor|\\btor\\b|toronto", s)                      ~ "Raptors",
    grepl("hawk|\\batl\\b|atlanta", s)                        ~ "Hawks",
    grepl("maverick|\\bdal\\b|dallas|mavs", s)                ~ "Mavericks",
    grepl("clipper|\\blac\\b|los angeles clippers", s)        ~ "Clippers",
    grepl("buck|\\bmil\\b|milwaukee", s)                      ~ "Bucks",
    grepl("sun|\\bphx\\b|phoenix", s)                         ~ "Suns",
    grepl("jazz|\\butah?\\b", s)                              ~ "Jazz",
    grepl("hornet|\\bcha\\b|charlotte", s)                    ~ "Hornets",
    grepl("net|\\bbkn?\\b|brooklyn", s)                       ~ "Nets",
    grepl("bull|\\bchi\\b|chicago", s)                        ~ "Bulls",
    grepl("pelican|\\bnop?\\b|new orleans", s)                ~ "Pelicans",
    grepl("wizard|\\bwas\\b|\\bwsh\\b|washington", s)         ~ "Wizards",
    grepl("king|\\bsac\\b|sacramento", s)                     ~ "Kings",
    TRUE                                                      ~ as.character(tm_raw)
  )
}

# ------------------------------------------------------------------------------
# Ingest Multi-Book Feeds & Parse True Local Game Dates
# ------------------------------------------------------------------------------
fetch_market_odds <- function() {
  api_key <- Sys.getenv("ODDS_API_KEY", "")
  
  if (nchar(api_key) > 0) {
    url <- paste0(
      "https://api.the-odds-api.com/v4/sports/basketball_nba/odds/?",
      "apiKey=", api_key,
      "&regions=us,us2,eu&markets=h2h&oddsFormat=american"
    )
    
    cat("[FEED] Querying live multi-region odds from The Odds API...\n")
    resp_raw <- tryCatch({
      request(url) |>
        req_timeout(8) |>
        req_perform() |>
        resp_body_json(simplifyVector = TRUE)
    }, error = function(e) {
      cat(sprintf("[FEED WARNING] API query failed (%s). Using consensus slate.\n", e$message))
      NULL
    })
    
    if (!is.null(resp_raw) && length(resp_raw) > 0 && nrow(resp_raw) > 0) {
      cat(sprintf("[FEED SUCCESS] Parsing %d live NBA games from API.\n", nrow(resp_raw)))
      parsed <- parse_multi_book_feed(resp_raw)
      if (nrow(parsed) > 0) return(parsed)
    }
  }
  
  # Official Calibrated Schedule Fallback with True Dates
  message(">>> [WARN] Using SYNTHETIC_FALLBACK schedule slate: The Odds API returned 0 games or key unavailable.")
  cat("[FEED NOTICE] Using calibrated schedule slate.\n")
  tibble(
    game_id           = paste0("GAME_", 1:6),
    game_date         = as.Date(c("2026-10-20", "2026-10-20", "2026-10-21", "2026-10-21", "2026-10-21", "2026-10-21")),
    tip_time_est      = c("19:30", "22:00", "19:00", "19:30", "20:00", "22:30"),
    matchup           = c("New York Knicks vs. Boston Celtics", "Minnesota Timberwolves vs. Los Angeles Lakers",
                          "Milwaukee Bucks vs. Philadelphia 76ers", "Cleveland Cavaliers vs. Toronto Raptors",
                          "Oklahoma City Thunder vs. Denver Nuggets", "Phoenix Suns vs. LA Clippers"),
    home_team         = c("Boston Celtics", "Los Angeles Lakers", "Philadelphia 76ers", "Toronto Raptors", "Denver Nuggets", "LA Clippers"),
    away_team         = c("New York Knicks", "Minnesota Timberwolves", "Milwaukee Bucks", "Cleveland Cavaliers", "Oklahoma City Thunder", "Phoenix Suns"),
    best_retail_book  = c("DraftKings", "FanDuel", "BetMGM", "Caesars", "DraftKings", "FanDuel"),
    home_ml           = c(-175, -115, +125, +140, -135, -110),
    away_ml           = c(+150, -105, -145, -165, +115, -110),
    consensus_home_ml = c(-188, -122, +115, +130, -142, -112),
    consensus_away_ml = c(+162, +104, -135, -155, +122, -108)
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
  standings_path <- file.path(CACHE_DIR, "projected_30_team_standings.rds")
  if (!file.exists(standings_path)) standings_path <- "projected_30_team_standings.rds"
  
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
    
    for (i in seq_len(nrow(slate_df))) {
      h_canon <- resolve_team_name(slate_df$home_team[i])
      a_canon <- resolve_team_name(slate_df$away_team[i])
      
      h_row <- standings |> filter(tolower(.data[[tm_col]]) == tolower(h_canon))
      a_row <- standings |> filter(tolower(.data[[tm_col]]) == tolower(a_canon))
      
      if (nrow(h_row) > 0 && nrow(a_row) > 0) {
        h_net <- as.numeric(h_row[[net_col]][1])
        a_net <- as.numeric(a_row[[net_col]][1])
        
        if (!is.null(sq_db)) {
          h_luck <- sq_db$shooting_luck_pts[tolower(sq_db$team) == tolower(h_canon)][1] %||% 0.0
          a_luck <- sq_db$shooting_luck_pts[tolower(sq_db$team) == tolower(a_canon)][1] %||% 0.0
          h_net <- h_net - (0.50 * h_luck)
          a_net <- a_net - (0.50 * a_luck)
        }
        
        fatigue_drag <- 0.0
        if (!is.null(fatigue_db)) {
          f_match <- fatigue_db |> filter(
            tolower(away_team) == tolower(a_canon) & tolower(home_team) == tolower(h_canon)
          )
          if (nrow(f_match) > 0) fatigue_drag <- f_match$point_spread_drag[1]
        }
        
        fair_margin <- (h_net - a_net) + 2.4 + fatigue_drag
        p_home <- pnorm(fair_margin / (if (exists("MARGIN_SIGMA")) MARGIN_SIGMA else 11.8))
        p_home <- min(max(p_home, 0.03), 0.97)
        home_probs[i] <- round(p_home, 3)
      } else {
        p_raw_h <- american_to_prob(slate_df$consensus_home_ml[i])
        p_raw_a <- american_to_prob(slate_df$consensus_away_ml[i])
        home_probs[i] <- round(p_raw_h / (p_raw_h + p_raw_a), 3)
      }
    }
    return(slate_df |> mutate(model_home_prob = home_probs))
  }
  message(sprintf(">>> [WARN] Using SYNTHETIC_FALLBACK: '%s' missing. Defaulting model home win probabilities to 0.50.", standings_path))
  slate_df |> mutate(model_home_prob = 0.50)
}

# ------------------------------------------------------------------------------
# Master Evaluation & Cache Writer (Preserves Exact Game Dates)
# ------------------------------------------------------------------------------
evaluate_betting_slate <- function() {
  cat("\n==================================================================\n")
  cat("           NBA VALUE BETTING & CLV ENGINE (+EV IDENTIFIER)        \n")
  cat("==================================================================\n\n")
  
  # Read active Kelly multiplier and risk status from CACHE_RISK_STATE
  risk_state_path <- if (exists("CACHE_RISK_STATE")) CACHE_RISK_STATE else file.path(CACHE_DIR, "risk_state.rds")
  active_kelly_mult <- 0.25
  risk_status <- "OPTIMAL"
  
  if (file.exists(risk_state_path)) {
    risk_state <- tryCatch(readRDS(risk_state_path), error = function(e) NULL)
    if (!is.null(risk_state) && is.list(risk_state)) {
      if (!is.null(risk_state$active_kelly_multiplier) && is.numeric(risk_state$active_kelly_multiplier) && !is.na(risk_state$active_kelly_multiplier)) {
        active_kelly_mult <- max(0, as.numeric(risk_state$active_kelly_multiplier))
      }
      if (!is.null(risk_state$risk_status) && is.character(risk_state$risk_status) && !is.na(risk_state$risk_status)) {
        risk_status <- as.character(risk_state$risk_status)
      }
    }
  }
  cat(sprintf("[RISK INTEGRATION] Active Kelly multiplier set to %.3f (status: %s)\n", active_kelly_mult, risk_status))
  
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
      
      quarter_kelly_pct = calculate_kelly(best_prob, best_dec, fraction = active_kelly_mult, max_cap_pct = 3.0),
      edge_flag = case_when(
        active_kelly_mult == 0.0       ~ "🛑 TRADING HALTED (Drawdown Stop-Loss)",
        best_ev >= 5.0 & exp_clv > 0.0 ~ "🔥 SHARP +EV (EV ≥ 5% & CLV > 0)",
        best_ev >= 3.0                 ~ "★ VALUE BET (+EV)",
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
      EV_Percent        = best_ev,
      Exp_CLV           = exp_clv,
      Bankroll_Rec      = quarter_kelly_pct,
      Status            = edge_flag,
      sharp_line        = cons_ml,
      game_id           = game_id
    ) |>
    arrange(game_date, desc(EV_Percent))
  
  display_table <- output_table |> select(-game_id, -sharp_line, -Team)
  print(knitr::kable(display_table, format = "simple"))
  
  out_path <- file.path(CACHE_DIR, "latest_value_bets.rds")
  saveRDS(output_table, out_path)
  cat(sprintf("\n[SUCCESS] Timezone-calibrated value bets saved to: %s\n", out_path))
  
  return(output_table)
}

evaluate_betting_slate()