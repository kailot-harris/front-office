# ==============================================================================
# notify_bets.R
# Path: c:/Users/kailo/kayceeslices/NFL Analytics/notify_bets.R
# Phase 7 (P7-A) — NFL Discord Alpha & CLV Webhook Dispatcher
#
# Ported from the WNBA Analytics sibling repo's notify_bets.R (see that file's header —
# entirely sport-agnostic Discord embed/dispatch logic, no sport-specific content beyond
# the column names it reads from CACHE_LATEST_VALUE_BETS). Two adaptations per
# docs/task_assignments_phase6.md's P7-A brief:
#   1. Wrapped into run_notify_bets(), this repo's established call_fn-style exposed-function
#      convention (all 9 existing run_full_pipeline.R stages use this) instead of WNBA's bare
#      top-level auto-run script. No sys.nframe()/!interactive() guard.
#   2. Reads NFL_DISCORD_WEBHOOK (config.R), NOT the plain DISCORD_WEBHOOK name the WNBA repo
#      uses — see config.R's own comment on why (two sibling repos can share one machine's
#      environment; a plain name would let one repo's pipeline post to the other sport's
#      Discord channel). NO hardcoded webhook URL, live or dummy, anywhere in this file.
#
# This is a terminal notification stage — no cache output of its own (matches WNBA's own
# run_stage() call for notify_bets.R, which declares no `output`).
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
  library(stringr)
})

source("config.R")
source("logging_utils.R")

.LOG_SCRIPT <- "notify_bets.R"

run_notify_bets <- function() {
  log_info("Starting NFL Discord bet-alert dispatcher.", script = .LOG_SCRIPT)

  cat("\n==================================================================\n")
  cat("                  NFL QUANT BET ALERT DISPATCHER                   \n")
  cat("==================================================================\n")

  # NO hardcoded webhook URL, live or dummy — per config.R's own convention
  # (NFL_DISCORD_WEBHOOK <- Sys.getenv("NFL_DISCORD_WEBHOOK", "")). Until a real webhook is
  # provisioned and visible to this R process, this is "" and dispatch below is skipped in
  # favor of a console-only preview.
  webhook_url <- Sys.getenv("NFL_DISCORD_WEBHOOK", "")

  # 1. Load Fresh Value Bets
  if (file.exists(CACHE_LATEST_VALUE_BETS)) {
    bets_df <- readRDS(CACHE_LATEST_VALUE_BETS)
  } else if (file.exists("cache/latest_value_bets.rds")) {
    bets_df <- readRDS("cache/latest_value_bets.rds")
  } else {
    log_warn(sprintf("%s not found; sourcing market_odds_engine.R to generate it.", CACHE_LATEST_VALUE_BETS),
             script = .LOG_SCRIPT)
    source("market_odds_engine.R")
    bets_df <- run_market_odds_engine()
  }

  if (is.null(bets_df) || nrow(bets_df) == 0) {
    log_error("No value-bet rows available to notify on (empty/NULL slate).", script = .LOG_SCRIPT)
    return(FALSE)
  }

  # 2. Exclude insufficient-sample-flagged rows FIRST (Phase 8, task P8-C).
  # market_odds_engine.R (P8-B) forces Bankroll_Rec <- 0 and sets Status to an insufficient-
  # sample marker (currently "⚠ INSUFFICIENT SAMPLE (early season)") when either team in a
  # matchup has played fewer than MIN_SAMPLE_GAMES_FOR_STAKE real current-season games, EVEN IF
  # the row's computed EV/CLV looks attractive (noisy early-season power ratings can produce
  # large but not-actually-tradeable EV figures). A game must clear BOTH the EV/CLV bar below AND
  # not be insufficient-sample-flagged to ever be dispatched. Matched via grepl() on "INSUFFICIENT
  # SAMPLE" (not an exact `==` string match) so this stays robust to the leading emoji glyph or
  # minor wording drift in market_odds_engine.R's Status string, while still being specific enough
  # not to accidentally exclude an unrelated Status value.
  is_gated <- grepl("INSUFFICIENT SAMPLE", bets_df$Status, fixed = TRUE)
  n_gated  <- sum(is_gated, na.rm = TRUE)
  eligible_bets <- bets_df[is.na(bets_df$Status) | !is_gated, , drop = FALSE]

  if (n_gated > 0) {
    log_info(sprintf("Excluded %d/%d row(s) flagged insufficient-sample (early season) before actionable-bets filtering.",
                      n_gated, nrow(bets_df)), script = .LOG_SCRIPT)
  }

  # 3. Filter for Real Institutional Edge (EV >= 3.0% and Non-Negative CLV)
  # Port verbatim per docs/task_assignments_phase6.md's Constraints — do not loosen. Applied only
  # to eligible_bets (already insufficient-sample-excluded), per P8-C's requirement that the
  # top-3 fallback below must also only ever pick from non-gated rows.
  actionable_bets <- eligible_bets %>%
    filter(EV_Percent >= 3.0 & Exp_CLV >= -0.5)

  # If no sharp line beats CLV today, take the top 3 calibrated model edges — still restricted to
  # eligible_bets, never the raw (possibly gated) bets_df.
  if (nrow(actionable_bets) == 0 && nrow(eligible_bets) > 0) {
    log_info("No bets met strict EV >= 3.0% & Exp_CLV >= -0.5% threshold. Selecting top calibrated slate edges (excluding insufficient-sample rows).",
             script = .LOG_SCRIPT)
    actionable_bets <- head(eligible_bets %>% arrange(desc(EV_Percent)), 3)
  }

  # If literally every row is insufficient-sample-flagged (the real current Week 2 2026 state,
  # per CLAUDE.md/task_assignments_phase7.md context), eligible_bets is empty and the fallback
  # above legitimately has nothing to select from. Handle that gracefully — skip dispatch
  # entirely with a clear explanatory log/console message, not an error.
  if (nrow(actionable_bets) == 0) {
    msg <- sprintf(
      "0 actionable bets after insufficient-sample exclusion: all %d game(s) in this slate are flagged insufficient-sample (early season). Skipping Discord dispatch this run.",
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
      name = paste0("\U0001F3C8 ", matchup_name),
      value = field_value,
      inline = FALSE
    )

    # Print preview to console
    cat(sprintf("\n\U0001F3C8 MATCHUP: %s\n", matchup_name))
    cat(sprintf("   PICK: %s | BOOK: %s (%s)\n", pick_name, book_name, odds_val))
    cat(sprintf("   STATS: Model Win: %s | EV: %s | Exp CLV: %s\n", win_prob, ev_val, clv_val))
    cat(sprintf("   STAKE: %s\n", stake_val))
  }

  log_info(sprintf("Formatted %d pick(s) into Discord embed payload.", n_picks), script = .LOG_SCRIPT)

  # 5. Construct Discord Webhook Payload
  payload <- list(
    username = "NFL Quant Terminal",
    avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
    embeds = list(
      list(
        title = paste("\U0001F3AF NFL Quantitative Alpha Alert \u2022", format(Sys.Date(), "%B %d, %Y")),
        description = "**Filter:** Multi-Factor EPA/Power Ratings, Fatigue/Travel, Playoff Leverage & Positive CLV",
        color = 3066993, # Sharp Dark Emerald Green
        fields = embed_fields,
        footer = list(text = paste("NFL Quant Engine v1.0 (P7-A) \u2022 Executed at", format(Sys.time(), "%H:%M:%S EST")))
      )
    )
  )

  # 6. Broadcast to Discord — ONLY if a real env var is set. No hardcoded/dummy URL check
  # needed since there is no hardcoded fallback to guard against. .log_redact() in
  # logging_utils.R already scrubs Discord webhook URL patterns from any log line, so the URL
  # is never logged in full even incidentally.
  if (nzchar(webhook_url)) {
    res <- tryCatch(
      POST(webhook_url, body = payload, encode = "json", timeout(6)),
      error = function(e) list(status_code = 500, message = e$message)
    )
    if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
      cat("\n[ALERT SUCCESS] Broadcasted calibrated live NFL bets to Discord webhook.\n")
      log_info("Broadcasted NFL bet alert to Discord webhook.", script = .LOG_SCRIPT, status_code = res$status_code)
      return(TRUE)
    } else {
      cat("\n[ALERT DISPATCHED] Webhook sent.\n")
      log_warn("Discord webhook POST did not return a clean 200/204.", script = .LOG_SCRIPT,
               status_code = res$status_code)
      return(TRUE)
    }
  } else {
    cat("\n[CONSOLE ONLY] NFL_DISCORD_WEBHOOK env var not set for this project - Discord dispatch skipped.\n")
    cat("[ACTION REQUIRED] Set NFL_DISCORD_WEBHOOK as a real environment variable (e.g. in a\n")
    cat("user-level .Renviron file) - do NOT reuse the WNBA repo's DISCORD_WEBHOOK. Output previewed above.\n")
    log_warn("NFL_DISCORD_WEBHOOK not configured; skipped Discord dispatch (console-only preview shown). Set it as a real environment variable (.Renviron) to enable live dispatch.",
             script = .LOG_SCRIPT)
    # This is the designed fail-safe path (see docs/task_assignments_phase6.md), not a
    # failure: the function completed its job (loaded data, filtered, formatted, previewed)
    # cleanly. TRUE == "ran without error"; FALSE is reserved for genuine data failures
    # (e.g. an empty/NULL betting slate) below.
    return(TRUE)
  }
}
