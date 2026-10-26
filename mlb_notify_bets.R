# ==============================================================================
# mlb_notify_bets.R
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_notify_bets.R
# Phase 7 — MLB Discord Alpha & CLV Webhook Dispatcher (Issue #22)
#
# Ported from the NFL Analytics sibling repo's notify_bets.R (sport-agnostic
# Discord embed formatting and webhook dispatch logic adapted for MLB).
#
# Architectural principles:
#   1. Wrapped in run_notify_bets() — callable runner function adhering to this
#      repo's call_fn convention for run_full_pipeline.R integration.
#      No bare top-level auto-run and no fragile sys.nframe() == 0 guards.
#   2. Webhook & Secret Hygiene: Sourced from MLB_DISCORD_WEBHOOK (config.R) /
#      Sys.getenv("MLB_DISCORD_WEBHOOK", Sys.getenv("DISCORD_WEBHOOK_URL", "")).
#      Zero hardcoded webhook URLs anywhere in code. If not provisioned, displays
#      a console-only preview and returns TRUE. .log_redact() ensures URLs are
#      never logged to disk in plaintext.
#   3. Input Schema & Resilient Fallback: Reads CACHE_LATEST_VALUE_BETS.
#      If the cache is missing or empty, generates a calibrated synthetic
#      fallback slate so the alerting and formatting engine can be verified
#      independently of a live Odds API run.
#   4. Filters: Excludes insufficient-sample rows (early-season gating) and
#      filters for institutional edge (EV >= 3.0% & Exp_CLV >= -0.5%).
#   5. Sport Branding: MLB Quant Terminal, baseball iconography (⚾),
#      and Pythagenpat / Starting-Pitcher Adjusted Elo model descriptions.
# ==============================================================================

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

source("config.R")
source("logging_utils.R")

.LOG_SCRIPT <- "mlb_notify_bets.R"

#' Generate a Calibrated Synthetic Fallback Slate for MLB Bet Alerts
#'
#' Used when CACHE_LATEST_VALUE_BETS is absent or empty, enabling end-to-end
#' testing and verification of the Discord formatting engine without requiring
#' a live Odds API query.
# ------------------------------------------------------------------------------
# filter_live_provenance() -- the provenance gate, as a pure function.
#
# Two upstream paths can put fabricated rows into the value-bets data frame: the
# generate_synthetic_mlb_slate() fallback below, and mlb_market_odds_engine.R's
# own fallback, which writes SYNTHETIC_FALLBACK rows into the value-bets cache
# when the live odds feed returns nothing. On 2026-10-25 the second path put six
# invented bets -- invented game_ids and prices, on teams already eliminated --
# into the cache, and run_notify_bets() broadcast three of them to Discord
# (status 204). The rows were correctly labelled; nothing downstream read the
# label. This is that check.
#
# Fails CLOSED: a row whose market_data_source is missing, NA or anything other
# than LIVE_ODDS_API is treated as untrusted and dropped. A bet whose provenance
# cannot be established is exactly the kind that must not be sent.
#
# Kept separate from run_notify_bets() so the decision is unit-testable without
# a cache, a webhook or log scraping -- see tests/testthat/test-notify-provenance.R.
LIVE_PROVENANCE <- "LIVE_ODDS_API"

filter_live_provenance <- function(df) {
  if (is.null(df) || nrow(df) == 0) {
    return(list(kept = df, n_before = 0L, n_dropped = 0L, dropped_sources = character(0)))
  }
  n_before <- nrow(df)
  src <- if ("market_data_source" %in% names(df)) as.character(df$market_data_source) else rep(NA_character_, n_before)
  is_live <- !is.na(src) & src == LIVE_PROVENANCE
  dropped <- src[!is_live]
  dropped[is.na(dropped)] <- "<missing>"
  list(
    kept = df[is_live, , drop = FALSE],
    n_before = n_before,
    n_dropped = n_before - sum(is_live),
    dropped_sources = dropped
  )
}

generate_synthetic_mlb_slate <- function() {
  data.frame(
    Matchup = c(
      "New York Yankees @ Los Angeles Dodgers",
      "Baltimore Orioles @ Boston Red Sox",
      "Atlanta Braves @ Philadelphia Phillies",
      "Houston Astros @ Texas Rangers"
    ),
    Recommended_Bet = c(
      "Los Angeles Dodgers Moneyline",
      "Baltimore Orioles Moneyline",
      "Atlanta Braves Moneyline",
      "Texas Rangers Moneyline"
    ),
    Book = c(
      "DraftKings",
      "FanDuel",
      "BetMGM",
      "Caesars"
    ),
    Line = c(
      -125L,
      +115L,
      -110L,
      +135L
    ),
    Model_Win_Prob = c(
      0.585,
      0.510,
      0.552,
      0.460
    ),
    EV_Percent = c(
      4.25,
      3.80,
      5.40,
      8.10
    ),
    Exp_CLV = c(
      1.20,
      0.65,
      1.50,
      2.10
    ),
    Bankroll_Rec = c(
      1.2,
      0.8,
      1.5,
      0.0
    ),
    Status = c(
      "\U0001F525 SHARP +EV (EV \u2265 5% & CLV > 0)",
      "\u2605 VALUE BET (+EV)",
      "\U0001F525 SHARP +EV (EV \u2265 5% & CLV > 0)",
      "\u26a0 INSUFFICIENT SAMPLE (early season)"
    ),
    market_data_source = rep("SYNTHETIC_FALLBACK", 4),
    stringsAsFactors = FALSE
  )
}

#' Normalize Slate Column Names across Differing Sibling/Phase Conventions
#'
#' Supports canonical Phase 6 / NFL sibling column names as well as
#' alternative key names (e.g., home_team/away_team, odds, model_prob, ev, kelly_stake).
normalize_bets_schema <- function(df) {
  if (is.null(df) || nrow(df) == 0) return(df)
  out <- df

  # Matchup
  if (!"Matchup" %in% names(out)) {
    if (all(c("away_team", "home_team") %in% names(out))) {
      out$Matchup <- paste(out$away_team, "@", out$home_team)
    } else if ("matchup" %in% names(out)) {
      out$Matchup <- out$matchup
    } else {
      out$Matchup <- "MLB Matchup"
    }
  }

  # Recommended_Bet
  if (!"Recommended_Bet" %in% names(out)) {
    if ("bet_on" %in% names(out)) {
      out$Recommended_Bet <- paste(out$bet_on, "Moneyline")
    } else if ("bet_side" %in% names(out)) {
      out$Recommended_Bet <- out$bet_side
    } else if ("Team" %in% names(out)) {
      out$Recommended_Bet <- paste(out$Team, "Moneyline")
    } else {
      out$Recommended_Bet <- "Moneyline"
    }
  }

  # Book
  if (!"Book" %in% names(out)) {
    if ("bookmaker" %in% names(out)) {
      out$Book <- out$bookmaker
    } else if ("best_retail_book" %in% names(out)) {
      out$Book <- out$best_retail_book
    } else {
      out$Book <- "Consensus"
    }
  }

  # Line
  if (!"Line" %in% names(out)) {
    if ("odds" %in% names(out)) {
      out$Line <- as.integer(out$odds)
    } else if ("best_odds" %in% names(out)) {
      out$Line <- as.integer(out$best_odds)
    } else {
      out$Line <- -110L
    }
  }

  # Model_Win_Prob
  if (!"Model_Win_Prob" %in% names(out)) {
    if ("model_prob" %in% names(out)) {
      out$Model_Win_Prob <- as.numeric(out$model_prob)
    } else if ("best_prob" %in% names(out)) {
      out$Model_Win_Prob <- as.numeric(out$best_prob)
    } else {
      out$Model_Win_Prob <- 0.50
    }
  }

  # EV_Percent
  if (!"EV_Percent" %in% names(out)) {
    if ("ev" %in% names(out)) {
      out$EV_Percent <- as.numeric(out$ev)
    } else if ("best_ev" %in% names(out)) {
      out$EV_Percent <- as.numeric(out$best_ev)
    } else {
      out$EV_Percent <- 0.0
    }
  }

  # Exp_CLV
  if (!"Exp_CLV" %in% names(out)) {
    if ("clv" %in% names(out)) {
      out$Exp_CLV <- as.numeric(out$clv)
    } else if ("exp_clv" %in% names(out)) {
      out$Exp_CLV <- as.numeric(out$exp_clv)
    } else {
      out$Exp_CLV <- 0.0
    }
  }

  # Bankroll_Rec
  if (!"Bankroll_Rec" %in% names(out)) {
    if ("kelly_stake" %in% names(out)) {
      out$Bankroll_Rec <- as.numeric(out$kelly_stake)
    } else if ("quarter_kelly_pct" %in% names(out)) {
      out$Bankroll_Rec <- as.numeric(out$quarter_kelly_pct)
    } else {
      out$Bankroll_Rec <- 0.0
    }
  }

  # Status
  if (!"Status" %in% names(out)) {
    if ("edge_flag" %in% names(out)) {
      out$Status <- out$edge_flag
    } else {
      out$Status <- "Qualified"
    }
  }

  out
}

#' Run MLB Bet Alert Notification Dispatcher
#'
#' @return Logical TRUE on success/preview, FALSE on fatal error
run_notify_bets <- function() {
  log_info("Starting MLB Discord bet-alert dispatcher.", script = .LOG_SCRIPT)

  cat("\n==================================================================\n")
  cat("                  MLB QUANT BET ALERT DISPATCHER                   \n")
  cat("==================================================================\n")

  # Webhook resolution: zero hardcoded URLs
  webhook_url <- Sys.getenv("MLB_DISCORD_WEBHOOK", Sys.getenv("DISCORD_WEBHOOK_URL", ""))
  if (!nzchar(webhook_url) && exists("MLB_DISCORD_WEBHOOK", envir = .GlobalEnv)) {
    webhook_url <- get("MLB_DISCORD_WEBHOOK", envir = .GlobalEnv)
  }

  # 1. Load Fresh Value Bets (or trigger Phase 6 / synthetic fallback)
  bets_df <- NULL
  target_cache <- if (exists("CACHE_LATEST_VALUE_BETS")) CACHE_LATEST_VALUE_BETS else cache_path("market", "latest_value_bets.rds")

  if (file.exists(target_cache)) {
    log_info(sprintf("Loading value bets from canonical cache: %s", target_cache), script = .LOG_SCRIPT)
    bets_df <- tryCatch(readRDS(target_cache), error = function(e) NULL)
  } else if (file.exists("cache/market/latest_value_bets.rds")) {
    log_info("Loading value bets from cache/market/latest_value_bets.rds", script = .LOG_SCRIPT)
    bets_df <- tryCatch(readRDS("cache/market/latest_value_bets.rds"), error = function(e) NULL)
  } else if (file.exists("cache/latest_value_bets.rds")) {
    log_info("Loading value bets from cache/latest_value_bets.rds", script = .LOG_SCRIPT)
    bets_df <- tryCatch(readRDS("cache/latest_value_bets.rds"), error = function(e) NULL)
  } else if (file.exists("mlb_market_odds_engine.R")) {
    log_info("Canonical cache not found; sourcing mlb_market_odds_engine.R to generate it.", script = .LOG_SCRIPT)
    source("mlb_market_odds_engine.R")
    if (exists("run_market_odds_engine", mode = "function")) {
      run_market_odds_engine()
      if (file.exists(target_cache)) {
        bets_df <- tryCatch(readRDS(target_cache), error = function(e) NULL)
      }
    }
  }

  # If still absent or empty, populate with calibrated synthetic fallback slate
  if (is.null(bets_df) || nrow(bets_df) == 0) {
    log_info("No existing value-bets cache found; generating calibrated synthetic fallback slate.", script = .LOG_SCRIPT)
    cat("\n>>> [NOTICE] No market odds cache found. Using calibrated synthetic MLB fallback slate.\n")
    bets_df <- generate_synthetic_mlb_slate()
  }

  # Normalize schema across alternative column conventions
  bets_df <- normalize_bets_schema(bets_df)

  if (is.null(bets_df) || nrow(bets_df) == 0) {
    log_error("No value-bet rows available to notify on (empty/NULL slate).", script = .LOG_SCRIPT)
    return(FALSE)
  }

  # 1b. Provenance gate -- never broadcast bets that are not real market data.
  # See filter_live_provenance() above for why this exists and why it fails closed.
  if (nzchar(Sys.getenv("MLB_NOTIFY_ALLOW_SYNTHETIC", unset = ""))) {
    log_warn("MLB_NOTIFY_ALLOW_SYNTHETIC is set -- provenance gate DISABLED; synthetic bets may be dispatched.",
             script = .LOG_SCRIPT)
  } else {
    gate <- filter_live_provenance(bets_df)
    bets_df <- gate$kept

    if (gate$n_dropped > 0) {
      tab <- table(gate$dropped_sources)
      log_warn(sprintf(
        "Provenance gate dropped %d/%d bet(s) that are not %s (%s). These are model/synthetic rows and will NOT be broadcast.",
        gate$n_dropped, gate$n_before, LIVE_PROVENANCE,
        paste(sprintf("%s=%d", names(tab), as.integer(tab)), collapse = ", ")
      ), script = .LOG_SCRIPT)
    }

    if (nrow(bets_df) == 0) {
      msg <- sprintf(
        "0 bets with live market provenance (all %d row(s) were synthetic/model fallback). Skipping Discord dispatch this run.",
        gate$n_before)
      log_warn(msg, script = .LOG_SCRIPT)
      cat(sprintf("\n>>> [SKIP] %s\n", msg))
      # TRUE, not FALSE: declining to send fabricated advice is this function
      # working, not failing. Returning FALSE would fail the pipeline stage and
      # train everyone to ignore it.
      return(TRUE)
    }
  }

  # 2. Exclude Insufficient-Sample Rows (Early Season Sample Gating)
  is_gated <- grepl("INSUFFICIENT SAMPLE", bets_df$Status, fixed = TRUE)
  n_gated  <- sum(is_gated, na.rm = TRUE)
  eligible_bets <- bets_df[is.na(bets_df$Status) | !is_gated, , drop = FALSE]

  if (n_gated > 0) {
    log_info(sprintf("Excluded %d/%d row(s) flagged insufficient-sample (early season) before actionable-bets filtering.",
                     n_gated, nrow(bets_df)), script = .LOG_SCRIPT)
  }

  # 3. Filter for Institutional Edge (EV >= 3.0% and Non-Negative CLV >= -0.5%)
  actionable_bets <- eligible_bets %>%
    filter(EV_Percent >= 3.0 & Exp_CLV >= -0.5)

  # Fallback to top 3 calibrated model edges if no bets clear the strict bar
  if (nrow(actionable_bets) == 0 && nrow(eligible_bets) > 0) {
    log_info("No bets met strict EV >= 3.0% & Exp_CLV >= -0.5% threshold. Selecting top calibrated slate edges (excluding insufficient-sample rows).",
             script = .LOG_SCRIPT)
    actionable_bets <- head(eligible_bets %>% arrange(desc(EV_Percent)), 3)
  }

  # Graceful exit if 0 actionable bets remain
  if (nrow(actionable_bets) == 0) {
    msg <- sprintf(
      "0 actionable bets after insufficient-sample exclusion: all %d game(s) in this slate are flagged insufficient-sample. Skipping Discord dispatch this run.",
      nrow(bets_df)
    )
    log_info(msg, script = .LOG_SCRIPT)
    cat(sprintf("\n[NO DISPATCH] %s\n", msg))
    return(TRUE)
  }

  # 4. Format and Preview Alerts
  embed_fields <- list()
  n_picks <- min(4, nrow(actionable_bets))

  for (i in seq_len(n_picks)) {
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
      name   = paste0("\u26BE ", matchup_name),
      value  = field_value,
      inline = FALSE
    )

    # Print preview to console
    cat(sprintf("\n\u26BE MATCHUP: %s\n", matchup_name))
    cat(sprintf("   PICK: %s | BOOK: %s (%s)\n", pick_name, book_name, odds_val))
    cat(sprintf("   STATS: Model Win: %s | EV: %s | Exp CLV: %s\n", win_prob, ev_val, clv_val))
    cat(sprintf("   STAKE: %s\n", stake_val))
  }

  log_info(sprintf("Formatted %d pick(s) into Discord embed payload.", n_picks), script = .LOG_SCRIPT)

  # 5. Construct Discord Webhook Payload
  payload <- list(
    username   = "MLB Quant Terminal",
    avatar_url = "https://cdn-icons-png.flaticon.com/512/1099/1099672.png",
    embeds     = list(
      list(
        title       = paste("\u26BE MLB Quantitative Alpha Alert \u2022", format(Sys.Date(), "%B %d, %Y")),
        description = "**Filter:** Pythagenpat / Team Elo w/ Starting-Pitcher Adjustment, Bullpen Fatigue & Positive CLV",
        color       = 3066993, # Sharp Dark Emerald Green (#1E7E34)
        fields      = embed_fields,
        footer      = list(text = paste("MLB Quant Engine v1.0 (Phase 7) \u2022 Executed at", format(Sys.time(), "%H:%M:%S EST")))
      )
    )
  )

  # 6. Broadcast to Discord (if webhook configured) or Console Preview
  if (nzchar(webhook_url)) {
    res <- tryCatch(
      httr::POST(webhook_url, body = payload, encode = "json", httr::timeout(6)),
      error = function(e) list(status_code = 500, message = e$message)
    )
    if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
      cat("\n[ALERT SUCCESS] Broadcasted calibrated live MLB bets to Discord webhook.\n")
      log_info("Broadcasted MLB bet alert to Discord webhook.", script = .LOG_SCRIPT, status_code = res$status_code)
      return(TRUE)
    } else {
      cat("\n[ALERT DISPATCHED] Webhook sent.\n")
      log_warn("Discord webhook POST did not return a clean 200/204.", script = .LOG_SCRIPT,
               status_code = res$status_code)
      return(TRUE)
    }
  } else {
    cat("\n[CONSOLE ONLY] MLB_DISCORD_WEBHOOK env var not set for this project - Discord dispatch skipped.\n")
    cat("[ACTION REQUIRED] Set MLB_DISCORD_WEBHOOK as a real environment variable (e.g. in a\n")
    cat("user-level .Renviron file). Output previewed above.\n")
    log_warn("MLB_DISCORD_WEBHOOK not configured; skipped Discord dispatch (console-only preview shown). Set it as a real environment variable (.Renviron) to enable live dispatch.",
             script = .LOG_SCRIPT)
    return(TRUE)
  }
}
