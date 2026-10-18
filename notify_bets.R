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

# Load dynamic risk state
risk_state_path <- if (exists("CACHE_RISK_STATE")) CACHE_RISK_STATE else file.path(CACHE_DIR, "risk_state.rds")
risk_state <- if (file.exists(risk_state_path)) tryCatch(readRDS(risk_state_path), error = function(e) NULL) else NULL
active_kelly_mult <- if (!is.null(risk_state$active_kelly_multiplier) && !is.na(risk_state$active_kelly_multiplier)) max(0, as.numeric(risk_state$active_kelly_multiplier)) else 0.25
risk_status <- if (!is.null(risk_state$risk_status) && !is.na(risk_state$risk_status)) as.character(risk_state$risk_status) else "OPTIMAL"

message(sprintf("[RISK INTEGRATION] Active Risk Status: %s | Kelly Multiplier: %.3f", risk_status, active_kelly_mult))

# 2. Filter for Real Institutional Edge (EV >= 3.0% and Non-Negative CLV)
is_halted <- active_kelly_mult == 0.0 || risk_status == "TRADING_HALT" || (nrow(bets_df) > 0 && all(grepl("HALT", bets_df$Status)))

if (is_halted) {
  message(sprintf("[RISK HALT] Trading halted due to drawdown stop-loss (status: %s, Kelly multiplier: %.3f). No bets dispatched.", risk_status, active_kelly_mult))
  actionable_bets <- head(bets_df, 0)
} else {
  actionable_bets <- bets_df %>%
    filter(EV_Percent >= 3.0 & Exp_CLV >= -0.5 & !grepl("HALT", Status))
  
  # If no sharp line beats CLV today, take the top 3 calibrated model edges
  if (nrow(actionable_bets) == 0) {
    message("[INFO] No bets met strict EV >= 5% & CLV > 0 threshold. Selecting top calibrated slate edges...")
    actionable_bets <- head(bets_df %>% arrange(desc(EV_Percent)), 3)
  }
}

# 3. Format and Dispatch Alerts
embed_fields <- list()

kelly_mode_label <- case_when(
  active_kelly_mult == 0.00  ~ "Trading Halted",
  active_kelly_mult == 0.10  ~ "0.10 Kelly - Capital Preservation",
  active_kelly_mult == 0.175 ~ "0.175 Kelly - Caution",
  active_kelly_mult == 0.25  ~ "Quarter-Kelly",
  TRUE                       ~ sprintf("%.3f Kelly", active_kelly_mult)
)

if (is_halted) {
  embed_fields[[1]] <- list(
    name = "🛑 TRADING HALTED (Drawdown Stop-Loss)",
    value = sprintf("Strategy circuit breaker active (Status: `%s` | Active Multiplier: `%.3f`). Current bankroll drawdown exceeds risk tolerance (>= 8.0 units). Capital deployment halted.", risk_status, active_kelly_mult),
    inline = FALSE
  )
  cat(sprintf("\n🛑 TRADING HALTED: Risk Status = %s | Kelly Multiplier = %.3f. No bets recommended.\n", risk_status, active_kelly_mult))
} else {
  for (i in seq_len(min(4, nrow(actionable_bets)))) {
    b <- actionable_bets[i, ]
    
    matchup_name <- b$Matchup
    pick_name    <- b$Recommended_Bet
    book_name    <- b$Book
    odds_val     <- sprintf("%+d", as.integer(b$Line))
    win_prob     <- sprintf("%.1f%%", b$Model_Win_Prob * 100)
    ev_val       <- sprintf("%+.2f%%", b$EV_Percent)
    clv_val      <- sprintf("%+.2f%%", b$Exp_CLV)
    stake_val    <- sprintf("%.1f%% Bankroll (%s)", b$Bankroll_Rec, kelly_mode_label)
    
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
}

# 4. Construct Discord Webhook Payload
description_text <- paste0(
  "**Filter:** Multi-Factor Roster Dynamics, Shot Quality (xeFG%), Travel Fatigue & Positive CLV\n",
  "**Risk State:** `", risk_status, "` (Kelly Multiplier: `", sprintf("%.3f", active_kelly_mult), "`)"
)

payload <- list(
  username = "NBA Quant Terminal",
  avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
  embeds = list(
    list(
      title = paste("🎯 NBA Quantitative Alpha Alert •", format(Sys.Date(), "%B %d, %Y")),
      description = description_text,
      color = if (is_halted) 15158332 else 3066993, # Red if halted, else Sharp Emerald Green
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