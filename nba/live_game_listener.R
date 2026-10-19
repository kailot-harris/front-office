# ==============================================================================
# live_game_listener.R
# Phase 4 Upgrade: In-Play Live Steam Sniper & Discord Alert Engine
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

source("config.R")

message(">>> [LIVE SNIPER] Starting Live Game Listener & Market Steam Sniper...")

DISCORD_WEBHOOK_URL <- Sys.getenv("DISCORD_WEBHOOK", "https://discord.com/api/webhooks/dummy/key")
ODDS_API_KEY <- Sys.getenv("ODDS_API_KEY", Sys.getenv("THE_ODDS_API_KEY", ""))

# In-memory tracking of alerted game IDs and timestamps to prevent webhook flooding
if (!exists("ALERT_LOG")) {
  ALERT_LOG <- list()
}

# ------------------------------------------------------------------------------
# Dynamic Live Win Probability Engine (Ornstein-Uhlenbeck Drift Model)
# ------------------------------------------------------------------------------
calc_live_win_prob <- function(home_margin, seconds_remaining, pre_game_home_prob = 0.55) {
  if (seconds_remaining <= 0) {
    return(ifelse(home_margin > 0, 1.0, ifelse(home_margin < 0, 0.0, 0.5)))
  }
  
  total_seconds <- 2880 # 48 minutes
  time_frac <- seconds_remaining / total_seconds
  
  # Mean drift toward pre-game rating
  pre_spread <- qnorm(pre_game_home_prob) * 11.0 # ~11 pts standard dev for game
  expected_remaining_margin <- pre_spread * time_frac
  expected_final_margin <- home_margin + expected_remaining_margin
  
  # Standard deviation scales with sqrt of time remaining
  sigma_remaining <- 11.0 * sqrt(time_frac)
  sigma_remaining <- max(sigma_remaining, 0.5)
  
  z_score <- expected_final_margin / sigma_remaining
  pnorm(z_score)
}

# ------------------------------------------------------------------------------
# Steam Alert Dispatcher
# ------------------------------------------------------------------------------
send_live_steam_snipe_alert <- function(game_id, home_team, away_team, score_h, score_a,
                                        period, clock_str, pre_fav, live_book, live_odds,
                                        model_fair_odds, ev_pct, kelly_stake) {
  
  now_time <- Sys.time()
  last_alert <- ALERT_LOG[[game_id]]
  if (!is.null(last_alert) && as.numeric(difftime(now_time, last_alert, units = "mins")) < 10) {
    message(sprintf(">>> [SUPPRESSED] Snipe alert for %s already sent in last 10m.", game_id))
    return(FALSE)
  }
  
  ALERT_LOG[[game_id]] <<- now_time
  
  title <- sprintf("🚨 LIVE STEAM SNIPE: %s trailing %s (EV: +%.1f%%)", pre_fav, 
                   ifelse(pre_fav == home_team, away_team, home_team), ev_pct)
  
  desc <- sprintf(
    paste0(
      "**Scoreboard:** %s %d - %d %s\n",
      "**Game Clock:** %s - %s\n",
      "**Target Wager:** **%s Live Moneyline**\n",
      "**Book Offered Odds:** `%+d` (Implied %.1f%%)\n",
      "**Model Fair Odds:** `%+d` (True Win Prob: %.1f%%)\n",
      "**Expected Edge:** `+%.1f%%` | **Quarter-Kelly Stake:** `%.2f Units`\n\n",
      "*Market Microstructure Note:* Recreational bookmaker (%s) lagging during timeout transition."
    ),
    home_team, score_h, score_a, away_team,
    period, clock_str,
    pre_fav,
    live_odds, (ifelse(live_odds > 0, 100 / (live_odds + 100), abs(live_odds) / (abs(live_odds) + 100))) * 100,
    model_fair_odds, (ifelse(model_fair_odds > 0, 100 / (model_fair_odds + 100), abs(model_fair_odds) / (abs(model_fair_odds) + 100))) * 100,
    ev_pct, kelly_stake, live_book
  )
  
  payload <- list(
    username = "NBA Steam Sniper Bot",
    avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
    embeds = list(
      list(
        title = title,
        description = desc,
        color = 15158332, # Bright Red / Gold Alert
        footer = list(text = paste("NBA Quantitative Engine v4.0 • Live In-Play Feed •", format(Sys.time(), "%H:%M:%S EST")))
      )
    )
  )
  
  if (nzchar(DISCORD_WEBHOOK_URL) && !grepl("dummy", DISCORD_WEBHOOK_URL)) {
    tryCatch({
      POST(DISCORD_WEBHOOK_URL, body = payload, encode = "json", timeout(5))
      message(sprintf(">>> [DISCORD] Successfully broadcast Live Steam Snipe for %s!", game_id))
    }, error = function(e) {
      warning(">>> [DISCORD ERROR] Failed to dispatch live webhook: ", e$message)
    })
  } else {
    message(">>> [MOCK DISCORD SNIPE]\n", desc)
  }
  return(TRUE)
}

# ------------------------------------------------------------------------------
# In-Play Game Polling Loop
# ------------------------------------------------------------------------------
poll_live_inplay_steam <- function() {
  message(sprintf(">>> [LIVE TICK] Checking live games at %s...", format(Sys.time(), "%H:%M:%S")))
  
  # Live simulated game test case representing in-play conditions
  active_live_games <- list(
    list(
      game_id = "BOS_NYK_LIVE",
      home_team = "BOS",
      away_team = "NYK",
      score_h = 42,
      score_a = 54, # Boston trailing by 12 at home
      period = "Q2",
      clock = "04:15",
      seconds_rem = 1695,
      pre_game_home_prob = 0.74, # Heavy pre-game favorite
      pre_fav = "BOS",
      books = list(
        list(book = "DraftKings", live_ml_fav = +140), # Stale price
        list(book = "Pinnacle", live_ml_fav = -105)     # Sharp repriced
      )
    )
  )
  
  for (gm in active_live_games) {
    h_margin <- gm$score_h - gm$score_a
    p_home_live <- calc_live_win_prob(h_margin, gm$seconds_rem, gm$pre_game_home_prob)
    
    p_fav_live <- ifelse(gm$pre_fav == gm$home_team, p_home_live, 1 - p_home_live)
    
    # Model fair American odds
    fair_odds_fav <- ifelse(p_fav_live >= 0.5, 
                            round(-100 * p_fav_live / (1 - p_fav_live)), 
                            round(100 * (1 - p_fav_live) / p_fav_live))
    
    # Check each recreational book against model
    for (bk in gm$books) {
      dec_odds <- ifelse(bk$live_ml_fav > 0, 1 + bk$live_ml_fav / 100, 1 + 100 / abs(bk$live_ml_fav))
      ev <- (p_fav_live * dec_odds) - 1
      
      # Snipe criteria: Fav trailing by 8+ in Q2, EV >= +8.0%
      fav_trailing <- (gm$pre_fav == gm$home_team && h_margin <= -8) || (gm$pre_fav == gm$away_team && h_margin >= 8)
      
      if (fav_trailing && gm$period == "Q2" && ev >= 0.08) {
        b <- dec_odds - 1
        kelly <- max(0, ((p_fav_live * b) - (1 - p_fav_live)) / b) * 0.25
        
        send_live_steam_snipe_alert(
          game_id = gm$game_id,
          home_team = gm$home_team,
          away_team = gm$away_team,
          score_h = gm$score_h,
          score_a = gm$score_a,
          period = gm$period,
          clock_str = gm$clock,
          pre_fav = gm$pre_fav,
          live_book = bk$book,
          live_odds = bk$live_ml_fav,
          model_fair_odds = fair_odds_fav,
          ev_pct = ev * 100,
          kelly_stake = round(kelly, 2)
        )
      }
    }
  }
}

if (!interactive()) {
  poll_live_inplay_steam()
}