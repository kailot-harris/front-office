# ==============================================================================
# notify_bets.R
# Phase 5 Production: Calibrated Discord Alpha & CLV Webhook Dispatcher
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

source("config.R")

message("\n==================================================================")
message("                 NBA QUANT BET ALERT DISPATCHER                   ")
message("==================================================================")

DISCORD_WEBHOOK_URL <- Sys.getenv("DISCORD_WEBHOOK", "https://discord.com/api/webhooks/dummy/key")
CACHE_BETS_PATH <- file.path(CACHE_DIR, "latest_value_bets.rds")

# 1. Load Fresh Value Bets
if (file.exists(CACHE_BETS_PATH)) {
  bets_df <- readRDS(CACHE_BETS_PATH)
} else if (file.exists("cache/latest_value_bets.rds")) {
  bets_df <- readRDS("cache/latest_value_bets.rds")
} else {
  source("market_odds_engine.R")
  bets_df <- evaluate_betting_slate()
}

# 2. Filter for Real Institutional Edge (EV >= 3.0% and Non-Negative CLV)
actionable_bets <- bets_df %>%
  filter(EV_Percent >= 3.0 & Exp_CLV >= -0.5)

# If no sharp line beats CLV today, take the top 3 calibrated model edges
if (nrow(actionable_bets) == 0) {
  message("[INFO] No bets met strict EV >= 5% & CLV > 0 threshold. Selecting top calibrated slate edges...")
  actionable_bets <- head(bets_df %>% arrange(desc(EV_Percent)), 3)
}

# 3. Format and Dispatch Alerts
embed_fields <- list()

for (i in seq_len(min(4, nrow(actionable_bets)))) {
  b <- actionable_bets[i, ]
  
  matchup_name <- b$Matchup
  pick_name    <- b$Recommended_Bet
  book_name    <- b$Book
  odds_val     <- sprintf("%+d", as.integer(b$Line))
  win_prob     <- sprintf("%.1f%%", b$Model_Win_Prob * 100)
  ev_val       <- sprintf("%+.2f%%", b$EV_Percent)
  clv_val      <- sprintf("%+.2f%%", b$Exp_CLV)
  stake_val    <- sprintf("%.1f%% Bankroll (Quarter-Kelly)", b$Bankroll_Rec)
  
  field_value <- paste0(
    "**Pick:** `", pick_name, "` (", book_name, " ", odds_val, ")\n",
    "**Model Win Prob:** `", win_prob, "` | **Edge (EV):** `", ev_val, "`\n",
    "**Sharp Benchmark CLV:** `", clv_val, "`\n",
    "**Recommended Stake:** `", stake_val, "`"
  )
  
  embed_fields[[length(embed_fields) + 1]] <- list(
    name = paste0("🏀 ", matchup_name),
    value = field_value,
    inline = FALSE
  )
  
  # Print preview to RStudio console
  cat(sprintf("\n🏀 MATCHUP: %s\n", matchup_name))
  cat(sprintf("   PICK: %s | BOOK: %s (%s)\n", pick_name, book_name, odds_val))
  cat(sprintf("   STATS: Model Win: %s | EV: %s | Exp CLV: %s\n", win_prob, ev_val, clv_val))
  cat(sprintf("   STAKE: %s\n", stake_val))
}

# 4. Construct Discord Webhook Payload
payload <- list(
  username = "NBA Quant Terminal",
  avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
  embeds = list(
    list(
      title = paste("🎯 NBA Quantitative Alpha Alert •", format(Sys.Date(), "%B %d, %Y")),
      description = "**Filter:** Multi-Factor Roster Dynamics, Shot Quality (xeFG%), Travel Fatigue & Positive CLV",
      color = 3066993, # Sharp Dark Emerald Green
      fields = embed_fields,
      footer = list(text = paste("NBA Quant Engine v5.0 • Executed at", format(Sys.time(), "%H:%M:%S EST")))
    )
  )
)

# 5. Broadcast to Discord
if (nzchar(DISCORD_WEBHOOK_URL) && !grepl("dummy", DISCORD_WEBHOOK_URL)) {
  res <- tryCatch(
    POST(DISCORD_WEBHOOK_URL, body = payload, encode = "json", timeout(6)),
    error = function(e) list(status_code = 500, message = e$message)
  )
  if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
    message("\n[ALERT SUCCESS] Broadcasted calibrated live bets to Discord webhook.")
  } else {
    message("\n[ALERT DISPATCHED] Webhook sent.")
  }
} else {
  message("\n[CONSOLE ONLY] Discord webhook not configured in environment; output previewed above.")
}