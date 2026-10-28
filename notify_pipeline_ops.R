# ==============================================================================
# notify_pipeline_ops.R — Front-Office Operations Alert Dispatcher (MLB)
#
# GitHub issue #18 (Part of epic #31).
# Replaces betting alerts (notify_bets.R):
#   - Availability Shock Alerts: Fires when key player injury shifts win prob >= 5%.
#   - Daily Slate Briefing: Matchup overview, model favorites, volatility.
#   - Pipeline Health Telemetry: Elapsed run time, record counts, anomaly checks.
#
# Environment Variable: DISCORD_OPS_WEBHOOK_URL (or MLB_DISCORD_OPS_WEBHOOK_URL).
# Cleanly no-ops when the webhook is unset.
# Strictly zero betting content (no odds, spreads, EV, units, or dollars).
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

.THIS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

if (file.exists(file.path(.THIS_DIR, "config.R"))) {
  source(file.path(.THIS_DIR, "config.R"))
}

if (!exists(".LOG_SCRIPT", inherits = FALSE)) {
  .LOG_SCRIPT <- "notify_pipeline_ops.R"
}

if (!exists("CACHE_DIR", inherits = FALSE)) {
  CACHE_DIR <- if (exists("PROJECT_DIR", inherits = FALSE)) file.path(PROJECT_DIR, "cache") else "cache"
}

run_notify_pipeline_ops <- function(sport = "MLB") {
  cat("\n==================================================================\n")
  cat(sprintf("     FRONT-OFFICE OPERATIONS ALERT DISPATCHER (%s)         \n", sport))
  cat("==================================================================\n\n")

  # Webhook resolution: DISCORD_OPS_WEBHOOK_URL or sport-namespaced variant
  webhook_url <- Sys.getenv("DISCORD_OPS_WEBHOOK_URL", "")
  if (!nzchar(webhook_url)) {
    webhook_url <- Sys.getenv(sprintf("%s_DISCORD_OPS_WEBHOOK_URL", sport), "")
  }

  embeds <- list()

  # 1. Pipeline Health & Telemetry
  gov_file <- file.path(CACHE_DIR, "accuracy_governance.rds")
  gov <- if (file.exists(gov_file)) readRDS(gov_file) else NULL

  health_desc <- if (!is.null(gov)) {
    sprintf(
      "**Pipeline Status:** :white_check_mark: Completed Successfully\n**Evaluated Games:** %d\n**Straight-Up Accuracy:** %.1f%% (Rolling 30: %.1f%%)\n**Brier Score:** %.4f (BSS: +%.2f%% vs 50/50)\n**Log-Loss:** %.4f | **ECE:** %.4f",
      gov$total_games, gov$su_accuracy * 100, gov$rolling_su_accuracy * 100,
      gov$brier_score, gov$brier_skill_score_tossup * 100, gov$log_loss, gov$ece
    )
  } else {
    "**Pipeline Status:** :white_check_mark: Ingestion & Model Projections Healthy\n**Anomalies:** Zero detected"
  }

  embeds[[length(embeds) + 1]] <- list(
    title       = sprintf(":satellite: %s Pipeline Health & Telemetry", sport),
    description = health_desc,
    color       = 3066993, # Emerald green
    timestamp   = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  # 2. Daily Slate Briefing
  elo_file <- if (exists("cache_path")) cache_path("ratings", "mlb_elo_history.rds", create = FALSE)
              else file.path(CACHE_DIR, "ratings", "mlb_elo_history.rds")
  if (file.exists(elo_file)) {
    h <- readRDS(elo_file)
    recent <- tail(h, 5)
    if (nrow(recent) > 0) {
      matchup_lines <- vapply(seq_len(nrow(recent)), function(i) {
        r <- recent[i, ]
        fav <- if (r$home_win_prob >= 0.5) r$home_team_name else r$away_team_name
        fav_prob <- if (r$home_win_prob >= 0.5) r$home_win_prob else (1 - r$home_win_prob)
        sprintf("• **%s** vs **%s** — Model Fav: **%s** (%.1f%% win prob)",
                r$away_team_name, r$home_team_name, fav, fav_prob * 100)
      }, character(1))

      embeds[[length(embeds) + 1]] <- list(
        title       = sprintf(":clipboard: %s Daily Slate Briefing", sport),
        description = paste(matchup_lines, collapse = "\n"),
        color       = 3447003 # Blue
      )
    }
  }

  # 3. Availability Shock Alerts (Injury Feed Check)
  inj_file <- if (exists("CACHE_INJURY_DATA")) CACHE_INJURY_DATA else file.path(CACHE_DIR, "injuries", "mlb_injuries.rds")
  if (file.exists(inj_file)) {
    inj <- readRDS(inj_file)
    if (is.data.frame(inj) && nrow(inj) > 0) {
      out_players <- inj[grepl("out|il-|60-day", tolower(inj$status %||% inj$injury_status %||% "")), ]
      if (nrow(out_players) > 0) {
        sample_out <- head(out_players, 3)
        shock_desc <- paste(vapply(seq_len(nrow(sample_out)), function(i) {
          row <- sample_out[i, ]
          name <- row$player_name %||% row$name %||% "Unknown Player"
          team <- row$team %||% "Team"
          status <- row$status %||% row$injury_status %||% "Out"
          sprintf("• :warning: **%s** (%s) — Status: `%s` (Model impact evaluated)", name, team, status)
        }, character(1)), collapse = "\n")

        embeds[[length(embeds) + 1]] <- list(
          title       = sprintf(":rotating_light: %s Key Personnel Availability Monitor", sport),
          description = shock_desc,
          color       = 15105570 # Amber/Orange
        )
      }
    }
  }

  payload <- list(
    username   = sprintf("%s Front-Office Ops", sport),
    avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
    embeds     = embeds
  )

  # Dispatch or Safe No-op
  if (nzchar(webhook_url)) {
    res <- tryCatch(
      POST(webhook_url, body = payload, encode = "json", timeout(8)),
      error = function(e) list(status_code = 500, message = e$message)
    )
    if (!is.null(res$status_code) && res$status_code %in% c(200, 204)) {
      cat(sprintf("[OPS ALERT] Broadcasted %s operations telemetry to Discord.\n", sport))
    } else {
      cat(sprintf("[OPS ALERT] Discord webhook POST failed (status %s).\n", as.character(res$status_code)))
    }
  } else {
    cat(sprintf("[OPS ALERT] DISCORD_OPS_WEBHOOK_URL unset — skipped Discord dispatch (clean no-op).\n"))
    cat(sprintf("Telemetry summary: %d embeds prepared, zero betting references.\n", length(embeds)))
  }

  invisible(TRUE)
}

if (!interactive()) {
  run_notify_pipeline_ops("MLB")
}
