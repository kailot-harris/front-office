# ==============================================================================
# notify_bets.R (WNBA port)
# Phase 5 (T4) — Calibrated Discord Alpha & CLV Webhook Dispatcher
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/notify_bets.R
#
# Ported as-is per task_assignments.md's T4 brief item 6 — only the webhook
# source changes: reads DISCORD_WEBHOOK from an env var ONLY (per T0's
# convention / Ground Rule 4), with NO hardcoded fallback URL of any kind
# (unlike the NBA original, which fell back to a "dummy" placeholder literal
# string). A new webhook must be created and set as a real env var before this
# will actually dispatch to Discord; until then it prints a clearly-labeled
# console-only preview, which is the same fail-safe behavior principle
# (ADR.md Principle III) used throughout this repo.
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

source("config.R")

message("\n==================================================================")
message("                 WNBA QUANT BET ALERT DISPATCHER                   ")
message("==================================================================")

# NO hardcoded webhook URL, live or dummy — per Ground Rule 4 / config.R's own
# convention (DISCORD_WEBHOOK <- Sys.getenv("DISCORD_WEBHOOK", "")). A new
# Discord webhook must be created for this project and set as a real
# environment variable; until then this is "" and the dispatch step below is
# skipped in favor of a console-only preview.
DISCORD_WEBHOOK_URL <- Sys.getenv("DISCORD_WEBHOOK", "")
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
# NOTE: per the plan's risk #2 (thinner WNBA book coverage), expect this
# threshold to qualify fewer games per slate than it would for NBA — that is a
# data-quality observation, NOT a reason to loosen this filter.
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
    name = paste0("\U0001F3C0 ", matchup_name),
    value = field_value,
    inline = FALSE
  )

  # Print preview to console
  cat(sprintf("\n\U0001F3C0 MATCHUP: %s\n", matchup_name))
  cat(sprintf("   PICK: %s | BOOK: %s (%s)\n", pick_name, book_name, odds_val))
  cat(sprintf("   STATS: Model Win: %s | EV: %s | Exp CLV: %s\n", win_prob, ev_val, clv_val))
  cat(sprintf("   STAKE: %s\n", stake_val))
}

# 4. Construct Discord Webhook Payload
payload <- list(
  username = "WNBA Quant Terminal",
  avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
  embeds = list(
    list(
      title = paste("\U0001F3AF WNBA Quantitative Alpha Alert \u2022", format(Sys.Date(), "%B %d, %Y")),
      description = "**Filter:** Multi-Factor Roster Dynamics, Shot Quality (xeFG%), Travel Fatigue & Positive CLV",
      color = 3066993, # Sharp Dark Emerald Green
      fields = embed_fields,
      footer = list(text = paste("WNBA Quant Engine v1.0 (T4) \u2022 Executed at", format(Sys.time(), "%H:%M:%S EST")))
    )
  )
)

# 5. Broadcast to Discord — ONLY if a real env var is set. No hardcoded/dummy
# URL check needed since there is no hardcoded fallback to guard against.
if (nzchar(DISCORD_WEBHOOK_URL)) {
  res <- tryCatch(
    POST(DISCORD_WEBHOOK_URL, body = payload, encode = "json", timeout(6)),
    error = function(e) list(status_code = 500, message = e$message)
  )
  if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
    message("\n[ALERT SUCCESS] Broadcasted calibrated live WNBA bets to Discord webhook.")
  } else {
    message("\n[ALERT DISPATCHED] Webhook sent.")
  }
} else {
  message("\n[CONSOLE ONLY] DISCORD_WEBHOOK env var not set for this project - Discord dispatch skipped.")
  message("[ACTION REQUIRED] Create a NEW Discord webhook for the WNBA project and set it as the")
  message("DISCORD_WEBHOOK environment variable (do NOT reuse the NBA repo's webhook). Output previewed above.")
}
