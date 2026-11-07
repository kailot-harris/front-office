# ==============================================================================
# mlb_clutch_leverage_engine.R
# Phase 3 / Sprint 3: True Clutch & Leverage Index Engine
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_clutch_leverage_engine.R
#
# Formulates Tom Tango's Leverage Index (LI), Win Probability Added (WPA),
# high-stakes RISP pressure resilience for batters, and inherited runners
# stranded "Fireman" ratings for high-leverage relievers.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "mlb_clutch_leverage_engine.R"

message(">>> [CLUTCH ENGINE] Initializing MLB True Clutch & Leverage Engine...")

run_mlb_clutch_engine <- function() {
  players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
  post_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_postseason_ops.json")
  
  if (!file.exists(players_file)) {
    stop("Missing projections_season_players.json")
  }
  
  players_df <- fromJSON(players_file)
  post_ops <- if (file.exists(post_file)) fromJSON(post_file) else list()
  
  message(sprintf(">>> Loaded %d players from projections database.", nrow(players_df)))
  
  # Select Top Batters (by composite z-score and workload)
  batters_pool <- players_df %>% 
    filter(player_type == "Batter") %>% 
    arrange(desc(composite_zscore), desc(proj_workload)) %>% 
    head(150)
    
  # Select Top Pitchers (Relievers + Top Starters)
  pitchers_pool <- players_df %>% 
    filter(player_type == "Pitcher") %>% 
    arrange(desc(composite_zscore), desc(proj_workload)) %>% 
    head(150)
    
  # Load empirical FanGraphs splits and boxscores
  fg_batters_file <- file.path(PROJECT_DIR, "cache", "stats_sync", "fg_batters.rds")
  if (!file.exists(fg_batters_file) && exists("cache_path")) {
    fg_batters_file <- cache_path("stats_sync", "fg_batters.rds")
  }
  fg_batters <- if (file.exists(fg_batters_file)) readRDS(fg_batters_file) else tibble::tibble()

  fg_pitchers_file <- file.path(PROJECT_DIR, "cache", "stats_sync", "fg_pitchers.rds")
  if (!file.exists(fg_pitchers_file) && exists("cache_path")) {
    fg_pitchers_file <- cache_path("stats_sync", "fg_pitchers.rds")
  }
  fg_pitchers <- if (file.exists(fg_pitchers_file)) readRDS(fg_pitchers_file) else tibble::tibble()

  boxscores_file <- file.path(PROJECT_DIR, "cache", "ingest", "mlb_boxscores_2026.rds")
  if (!file.exists(boxscores_file) && exists("cache_path")) {
    boxscores_file <- cache_path("ingest", "mlb_boxscores_2026.rds")
  }
  boxscores_df <- if (file.exists(boxscores_file)) {
    tryCatch(readRDS(boxscores_file), error = function(e) NULL)
  } else {
    NULL
  }

  clutch_profiles <- list()
  
  # ----------------------------------------------------------------------------
  # 1. Process Batters: True Clutch, RISP Splits & Leverage Distribution
  # ----------------------------------------------------------------------------
  for (i in seq_len(nrow(batters_pool))) {
    p <- batters_pool[i, ]
    
    woba <- coalesce(p$stat1_raw, 0.315)
    iso <- coalesce(p$stat2_raw, 0.160)
    obp <- coalesce(p$stat3_val, 0.320)
    z_score <- coalesce(p$composite_zscore, 1.0)
    pa <- coalesce(p$proj_workload, 500)
    
    # Ingest true FanGraphs clutch, WPA, and leverage metrics (cache/stats_sync/fg_batters.rds)
    fg_b_match <- if (nrow(fg_batters) > 0) {
      fg_batters %>%
        filter(as.character(xMLBAMID) == as.character(p$mlbam_id) | PlayerName == p$player_name) %>%
        head(1)
    } else {
      tibble::tibble()
    }

    # Ingest true empirical values from fg_batters
    clutch_score <- if (nrow(fg_b_match) > 0 && !is.na(fg_b_match$Clutch)) round(fg_b_match$Clutch, 2) else 0.0
    wpa_total <- if (nrow(fg_b_match) > 0 && !is.na(fg_b_match$WPA)) round(fg_b_match$WPA, 2) else round((woba - 0.310) * (pa / 100) * 1.35, 2)
    pli <- if (nrow(fg_b_match) > 0 && !is.na(fg_b_match$pLI)) round(max(0.0, fg_b_match$pLI), 2) else round(max(0.85, min(1.45, 1.00 + (z_score * 0.06))), 2)

    # Pressure wOBA Delta: derived from true FanGraphs Clutch score (~45 pts per win of clutch)
    clutch_delta <- round(clutch_score / 45, 3)
    clutch_woba <- round(woba + clutch_delta, 3)
    high_li_wpa <- round(wpa_total * 0.45 + (clutch_delta * 35), 2)
    
    # Leverage Distribution Breakdown (%)
    # Typical MLB: Low 58%, Med 27%, High 11%, Extreme 4%
    high_pct <- round(pmax(7.0, pmin(18.0, 11.0 + (pli - 1.0) * 15)), 1)
    extreme_pct <- round(pmax(2.5, pmin(7.5, 4.0 + (pli - 1.0) * 6)), 1)
    med_pct <- round(pmax(22.0, pmin(32.0, 27.0 - (high_pct - 11.0) * 0.5)), 1)
    low_pct <- round(100.0 - high_pct - extreme_pct - med_pct, 1)
    
    # RISP 2-Out Situation Split
    risp_pa <- round(pa * 0.24)
    risp_woba <- round(woba + clutch_delta * 1.15, 3)
    risp_avg <- round(pmax(0.200, pmin(0.380, (risp_woba - 0.070) * 0.90)), 3)
    risp_obp <- round(pmax(0.280, pmin(0.480, obp + clutch_delta * 0.8)), 3)
    risp_slg <- round(pmax(0.330, pmin(0.680, risp_avg + iso + clutch_delta * 0.7)), 3)
    risp_ops <- round(risp_obp + risp_slg, 3)
    
    # Clutch Archetype Assignment
    archetype <- case_when(
      clutch_delta >= 0.035 & high_li_wpa >= 2.0 ~ "Ice-in-Veins Walkoff Anchor",
      clutch_delta >= 0.020 & risp_ops >= 0.880 ~ "Two-Out RISP Punisher",
      clutch_delta >= 0.010 ~ "High-Discipline Pressure Grinder",
      abs(clutch_delta) < 0.015 ~ "Steady-State Context Neutral",
      clutch_delta <= -0.025 ~ "Low-Leverage Run Padder",
      TRUE ~ "Balanced Late-Inning Contributor"
    )
    
    clutch_profiles[[p$player_id]] <- list(
      playerId          = p$player_id,
      mlbamId           = p$mlbam_id,
      playerName        = p$player_name,
      team              = p$team,
      playerType        = "Batter",
      position          = coalesce(p$position, "OF"),
      clutchArchetype   = archetype,
      baseMetricLabel   = "Base wOBA",
      baseMetricVal     = round(woba, 3),
      clutchMetricLabel = "High-LI wOBA",
      clutchMetricVal   = round(clutch_woba, 3),
      deltaClutch       = round(clutch_delta, 3),
      clutchScore       = clutch_score,
      wpaTotal          = wpa_total,
      highLiWpa         = high_li_wpa,
      avgLeverageIndex  = pli,
      leverageBreakdown = list(
        lowPct     = low_pct,
        medPct     = med_pct,
        highPct    = high_pct,
        extremePct = extreme_pct
      ),
      rispSplit         = list(
        pa   = risp_pa,
        avg  = risp_avg,
        obp  = risp_obp,
        slg  = risp_slg,
        wOBA = risp_woba,
        ops  = risp_ops
      )
    )
  }
  
  # ----------------------------------------------------------------------------
  # 2. Process Pitchers: Fireman Ratings, IS%, and High-LI Suppression
  # ----------------------------------------------------------------------------
  for (j in seq_len(nrow(pitchers_pool))) {
    p <- pitchers_pool[j, ]
    
    xfip <- coalesce(p$stat1_pooled, 3.85)
    proj_era <- coalesce(p$stat2_pooled, 3.80)
    rgs <- coalesce(p$stat3_val, 52.0)
    z_score <- coalesce(p$composite_zscore, 1.0)
    workload <- coalesce(p$proj_workload, 120)
    is_reliever <- workload < 95
    
    # Expected wOBA against baseline
    base_woba_against <- round(pmax(0.240, pmin(0.360, (proj_era * 0.055) + 0.110)), 3)
    
    # Ingest true FanGraphs pitcher metrics (cache/stats_sync/fg_pitchers.rds)
    fg_p_match <- if (nrow(fg_pitchers) > 0) {
      fg_pitchers %>%
        filter(as.character(xMLBAMID) == as.character(p$mlbam_id) | PlayerName == p$player_name) %>%
        head(1)
    } else {
      tibble::tibble()
    }

    # Ingest true empirical values from fg_pitchers
    clutch_score <- if (nrow(fg_p_match) > 0 && !is.na(fg_p_match$Clutch)) round(fg_p_match$Clutch, 2) else 0.0
    wpa_total <- if (nrow(fg_p_match) > 0 && !is.na(fg_p_match$WPA)) round(fg_p_match$WPA, 2) else round((0.315 - base_woba_against) * (workload / 25) * 1.25, 2)
    gmli <- if (nrow(fg_p_match) > 0 && !is.na(fg_p_match$pLI)) {
      round(max(0.0, fg_p_match$pLI), 2)
    } else {
      round(max(0.80, min(2.15, if (is_reliever) 1.55 + (z_score * 0.12) else 1.05 + (z_score * 0.04))), 2)
    }

    # High-LI wOBA against delta: negative delta means elite suppression under pressure
    # Derived from true FanGraphs Pitcher Clutch score (~50 pts per win of clutch)
    clutch_delta <- round(-clutch_score / 50, 3)
    clutch_woba_against <- round(base_woba_against + clutch_delta, 3)
    high_li_wpa <- round(wpa_total * 0.55 - (clutch_delta * 40), 2)

    # Leverage Breakdown
    high_pct <- round(pmax(10.0, pmin(35.0, if (is_reliever) 24.0 + (gmli - 1.5) * 20 else 12.0)), 1)
    extreme_pct <- round(pmax(4.0, pmin(15.0, if (is_reliever) 9.0 + (gmli - 1.5) * 10 else 4.0)), 1)
    med_pct <- round(pmax(20.0, pmin(32.0, 26.0)), 1)
    low_pct <- round(100.0 - high_pct - extreme_pct - med_pct, 1)

    # Ingest inherited runners (IR) and inherited scored (IS) from boxscores or set to 0 when absent
    ir <- 0L
    inherited_scored <- 0L
    if (!is.null(boxscores_df) && is.data.frame(boxscores_df)) {
      p_id_cols <- intersect(c("pitcher_id", "player_id", "mlbam_id", "xMLBAMID"), colnames(boxscores_df))
      ir_cols <- intersect(c("inherited_runners", "inheritedRunners", "IR", "ir"), colnames(boxscores_df))
      is_cols <- intersect(c("inherited_runners_scored", "inherited_scored", "inheritedScored", "IS", "is"), colnames(boxscores_df))

      if (length(p_id_cols) > 0 && length(ir_cols) > 0) {
        pid_col <- p_id_cols[1]
        ir_col <- ir_cols[1]
        p_box <- boxscores_df %>%
          filter(as.character(.data[[pid_col]]) == as.character(p$mlbam_id) |
                 as.character(.data[[pid_col]]) == as.character(p$player_id))
        if (nrow(p_box) > 0) {
          ir <- as.integer(sum(p_box[[ir_col]], na.rm = TRUE))
          if (length(is_cols) > 0) {
            is_col <- is_cols[1]
            inherited_scored <- as.integer(sum(p_box[[is_col]], na.rm = TRUE))
          }
        }
      }
    }

    # Strand rate: FanGraphs empirical LOB% or derived from inherited runners
    strand_rate <- if (ir > 0 && inherited_scored >= 0) {
      round(max(0.0, min(100.0, (1 - (inherited_scored / ir)) * 100)), 1)
    } else if (nrow(fg_p_match) > 0 && !is.na(fg_p_match$LOB_pct)) {
      round(max(0.0, min(100.0, fg_p_match$LOB_pct * 100)), 1)
    } else {
      round(max(55.0, min(90.0, 72.0 - (clutch_delta * 300) + (z_score * 2.5))), 1)
    }

    if (ir > 0 && inherited_scored == 0L) {
      inherited_scored <- round(ir * (1 - (strand_rate / 100)))
    }
    shutdowns <- round(pmax(8, (workload / 5) * 0.45 + (z_score * 3)))
    meltdowns <- round(pmax(1, 6 - (z_score * 1.5)))
    fireman_idx <- round((strand_rate * 0.5) + (high_li_wpa * 12) + (shutdowns * 1.2) - (meltdowns * 2.5), 1)
    
    # Clutch Archetype
    archetype <- if (is_reliever) {
      if (strand_rate >= 82.0 && high_li_wpa >= 2.5) {
        "Bases-Loaded Fireman Eraser"
      } else if (gmli >= 1.70 && clutch_delta <= -0.020) {
        "Triple-Digit 9th Inning Closer"
      } else if (workload >= 65 && strand_rate >= 74.0) {
        "High-Leverage Multi-Inning Bridge"
      } else if (clutch_delta <= -0.010) {
        "Groundball Double-Play Specialist"
      } else {
        "Middle Relief Low-Stress Arm"
      }
    } else {
      if (clutch_delta <= -0.020 && rgs >= 58.0) {
        "Ace Jam-Escape Specialist"
      } else if (abs(clutch_delta) <= 0.015) {
        "Steady Workhorse Starter"
      } else {
        "High-Stress Volatile Starter"
      }
    }
    
    clutch_profiles[[p$player_id]] <- list(
      playerId          = p$player_id,
      mlbamId           = p$mlbam_id,
      playerName        = p$player_name,
      team              = p$team,
      playerType        = "Pitcher",
      position          = if (is_reliever) "RP" else "SP",
      clutchArchetype   = archetype,
      baseMetricLabel   = "Base wOBA Against",
      baseMetricVal     = round(base_woba_against, 3),
      clutchMetricLabel = "High-LI wOBA Against",
      clutchMetricVal   = round(clutch_woba_against, 3),
      deltaClutch       = round(clutch_delta, 3),
      clutchScore       = clutch_score,
      wpaTotal          = wpa_total,
      highLiWpa         = high_li_wpa,
      avgLeverageIndex  = gmli,
      leverageBreakdown = list(
        lowPct     = low_pct,
        medPct     = med_pct,
        highPct    = high_pct,
        extremePct = extreme_pct
      ),
      rispSplit         = list(
        pa   = round(workload * 0.8),
        avg  = round(base_woba_against * 0.78, 3),
        obp  = round(base_woba_against * 0.95, 3),
        slg  = round(base_woba_against * 1.15, 3),
        wOBA = clutch_woba_against,
        ops  = round(base_woba_against * 2.10, 3)
      ),
      firemanStats      = list(
        inheritedRunners = ir,
        inheritedScored  = inherited_scored,
        strandRatePct    = strand_rate,
        shutdowns        = shutdowns,
        meltdowns        = meltdowns,
        firemanIndex     = fireman_idx
      )
    )
  }
  
  profile_list <- unname(clutch_profiles)
  message(sprintf(">>> Generated Clutch profiles for %d players (%d Batters, %d Pitchers).",
                  length(profile_list), nrow(batters_pool), nrow(pitchers_pool)))
                  
  # Top clutch leaders
  batter_sub <- profile_list[sapply(profile_list, function(x) x$playerType == "Batter")]
  batter_order <- order(sapply(batter_sub, function(x) x$clutchScore), decreasing = TRUE)
  batter_leaders <- sapply(head(batter_sub[batter_order], 10), function(x) x$playerName)
    
  pitcher_sub <- profile_list[sapply(profile_list, function(x) x$playerType == "Pitcher")]
  pitcher_order <- order(sapply(pitcher_sub, function(x) x$clutchScore), decreasing = TRUE)
  pitcher_leaders <- sapply(head(pitcher_sub[pitcher_order], 10), function(x) x$playerName)
    
  output_catalog <- list(
    # generated_at is what tools/publish_web.R's assertion F reads: UTC, ISO-8601,
    # and FIRST in the object because F only scans the first 4096 bytes of the
    # file (this payload is ~287 KB). `updatedAt` is kept for the web app, which
    # already renders it; it is local-time and not a format F can parse.
    generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    updatedAt            = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    totalProfiles        = length(profile_list),
    clutchLeaderBatters  = batter_leaders,
    clutchLeaderPitchers = pitcher_leaders,
    profiles             = profile_list
  )
  
  output_json <- file.path(PROJECT_DIR, "web", "public", "data", "clutch_leverage_metrics.json")
  write(toJSON(output_catalog, auto_unbox = TRUE, pretty = TRUE), output_json)
  message(sprintf(">>> Wrote clutch metrics catalog to %s (%.2f MB)", output_json, file.info(output_json)$size / 1e6))
  
  invisible(output_catalog)
}

if (sys.nframe() == 0) {
  run_mlb_clutch_engine()
}
