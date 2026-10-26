# ==============================================================================
# live_game_listener.R (WNBA port)
# Phase 5 (T5 / wnba_live_dashboard_agent): In-Play Live Steam Sniper & Discord Alert Engine
# Path: live_game_listener.R
#
# Ported from NBA Analytics/live_game_listener.R. Per the T5 brief:
#   - `total_seconds <- 2880` (48 min) -> `total_seconds <- 2400` (WNBA's 40-minute game,
#     4x10 vs NBA's 4x12) inside `calc_live_win_prob()`.
#   - Hardcoded demo live game swapped for a plausible current WNBA matchup.
#   - `ODDS_API_KEY`/`basketball_wnba` wiring kept consistent with T4's market_odds_engine.R
#     (same env var name `ODDS_API_KEY`, NOT the NBA original's `THE_ODDS_API_KEY` — T4's
#     header comment confirms the same account/key works for both leagues via the sport-key
#     swap alone, so this file now reads the SAME env var market_odds_engine.R does, rather
#     than perpetuating the NBA repo's two-different-env-var-names inconsistency flagged in
#     REPO_MAP.md §10). Still not actually wired to a live in-play odds call in this file
#     (same as the NBA original — REPO_MAP.md §9 flags this as an open wishlist item, not
#     something T5's brief asked to build).
#   - Discord webhook: `Sys.getenv("DISCORD_WEBHOOK", "")` only, per Ground Rule 4 — no
#     hardcoded dummy-URL fallback string (the NBA original's dummy placeholder pattern is
#     dropped entirely here, same choice T4's notify_bets.R made).
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

PROJECT_DIR <- here::here()   # issue #90: derived portably; never hardcode the repo root
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("config.R")

message(">>> [WNBA LIVE SNIPER] Starting Live Game Listener & Market Steam Sniper...")

# No hardcoded dummy webhook (Ground Rule 4) — empty string means "not configured", handled
# as a console-only no-op below, exactly like T4's notify_bets.R.
DISCORD_WEBHOOK_URL <- Sys.getenv("DISCORD_WEBHOOK", "")

# Same ODDS_API_KEY env var name T4's market_odds_engine.R reads (see header note) — read but
# NOT actually called against a live in-play endpoint in this file, matching the NBA original's
# own not-yet-implemented state (REPO_MAP.md §9's "Live in-play odds integration" wishlist item).
ODDS_API_KEY <- Sys.getenv("ODDS_API_KEY", "")

if (!nzchar(ODDS_API_KEY)) {
  message(">>> [FEED NOTICE] ODDS_API_KEY not set in this environment — live in-play odds pull is not implemented in this file (same as the NBA original); this demo runs entirely on the hardcoded sample game below.")
}

# In-memory tracking of alerted game IDs and timestamps to prevent webhook flooding
if (!exists("ALERT_LOG")) {
  ALERT_LOG <- list()
}

# ------------------------------------------------------------------------------
# Dynamic Live Win Probability Engine (Ornstein-Uhlenbeck-style Drift Model)
# ------------------------------------------------------------------------------
calc_live_win_prob <- function(home_margin, seconds_remaining, pre_game_home_prob = 0.55) {
  if (seconds_remaining <= 0) {
    return(ifelse(home_margin > 0, 1.0, ifelse(home_margin < 0, 0.0, 0.5)))
  }

  total_seconds <- 2400 # WNBA regulation: 4 x 10-minute quarters = 40 minutes (vs NBA's 48/2880s)
  time_frac <- seconds_remaining / total_seconds

  # Mean drift toward pre-game rating. Uses WNBA_MARGIN_SIGMA (14.0, T2's real empirically-fit
  # WNBA home-margin sd — see config.R) in place of the NBA original's hardcoded 11.0, per
  # WNBA_REPLICATION_PLAN.md §(b) Tier 3's instruction not to reuse NBA sigma constants uncritically.
  pre_spread <- qnorm(pre_game_home_prob) * WNBA_MARGIN_SIGMA
  expected_remaining_margin <- pre_spread * time_frac
  expected_final_margin <- home_margin + expected_remaining_margin

  # Standard deviation scales with sqrt of time remaining
  sigma_remaining <- WNBA_MARGIN_SIGMA * sqrt(time_frac)
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

  title <- sprintf("\U0001F6A8 LIVE STEAM SNIPE: %s trailing %s (EV: +%.1f%%)", pre_fav,
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
    username = "WNBA Steam Sniper Bot",
    avatar_url = "https://cdn-icons-png.flaticon.com/512/3211/3211244.png",
    embeds = list(
      list(
        title = title,
        description = desc,
        color = 15158332, # Bright Red / Gold Alert
        footer = list(text = paste("WNBA Quantitative Engine v5.0 (WNBA Port) - Live In-Play Feed -", format(Sys.time(), "%H:%M:%S %Z")))
      )
    )
  )

  if (nzchar(DISCORD_WEBHOOK_URL)) {
    tryCatch({
      POST(DISCORD_WEBHOOK_URL, body = payload, encode = "json", timeout(5))
      message(sprintf(">>> [DISCORD] Successfully broadcast Live Steam Snipe for %s!", game_id))
    }, error = function(e) {
      warning(">>> [DISCORD ERROR] Failed to dispatch live webhook: ", e$message)
    })
  } else {
    message(">>> [MOCK DISCORD SNIPE] (DISCORD_WEBHOOK not set - console preview only)\n", desc)
  }
  return(TRUE)
}

# ------------------------------------------------------------------------------
# In-Play Game Polling Loop
# ------------------------------------------------------------------------------
poll_live_inplay_steam <- function() {
  message(sprintf(">>> [LIVE TICK] Checking live WNBA games at %s...", format(Sys.time(), "%H:%M:%S")))

  # Plausible current WNBA matchup (Minnesota Lynx @ New York Liberty — the two real top
  # teams in T2's actual `cache/projected_wnba_standings.rds` output, per T2's Handoff Notes)
  # in place of the NBA original's hardcoded BOS_NYK_LIVE fake game. This remains a
  # structurally-synthetic in-play scoreboard snapshot (no live scoreboard feed is wired up
  # in this file, matching the NBA original's own state), but the teams/context are real and
  # plausible rather than borrowed from the wrong league.
  active_live_games <- list(
    list(
      game_id = "MIN_NY_LIVE",
      home_team = "New York Liberty",
      away_team = "Minnesota Lynx",
      score_h = 38,
      score_a = 49, # Liberty trailing by 11 at home
      period = "Q2",
      clock = "03:40",
      seconds_rem = 1420, # WNBA quarters are 10 min = 600s; Q2 running clock within the 2400s game total
      pre_game_home_prob = 0.52, # Two evenly-matched top contenders per real standings (~12.1 vs 12.1 net rating)
      pre_fav = "New York Liberty",
      books = list(
        list(book = "DraftKings", live_ml_fav = +135), # Stale price
        list(book = "Pinnacle", live_ml_fav = -110)     # Sharp repriced
      )
    )
  )

  for (gm in active_live_games) {
    h_margin <- gm$score_h - gm$score_a
    p_home_live <- calc_live_win_prob(h_margin, gm$seconds_rem, gm$pre_game_home_prob)

    p_fav_live <- ifelse(gm$pre_fav == gm$home_team, p_home_live, 1 - p_home_live)

    fair_odds_fav <- ifelse(p_fav_live >= 0.5,
                            round(-100 * p_fav_live / (1 - p_fav_live)),
                            round(100 * (1 - p_fav_live) / p_fav_live))

    for (bk in gm$books) {
      dec_odds <- ifelse(bk$live_ml_fav > 0, 1 + bk$live_ml_fav / 100, 1 + 100 / abs(bk$live_ml_fav))
      ev <- (p_fav_live * dec_odds) - 1

      # Snipe criteria: Fav trailing by 8+ in Q2, EV >= +8.0% — thresholds carried over
      # unchanged from the NBA original (not flagged as a Tier 3 sport-specific recalibration
      # item in the plan; WNBA margin variance is wider per WNBA_MARGIN_SIGMA, so this "trail
      # by 8" trigger may in practice fire somewhat less often for WNBA relative to its own
      # scoring scale than it did for NBA — a reasonable future recalibration candidate, not
      # changed here without empirical validation).
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
