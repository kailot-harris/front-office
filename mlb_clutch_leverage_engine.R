# ==============================================================================
# mlb_clutch_leverage_engine.R
# Phase 3 / Sprint 3: True Clutch & Leverage Index Engine
# Path: mlb_clutch_leverage_engine.R
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

num_or_na <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else as.numeric(x)
}

str_or_na <- function(x) {
  if (is.null(x) || length(x) == 0 || is.na(x) || !nzchar(as.character(x))) NA_character_ else as.character(x)
}

round_or_na <- function(x, digits = 2) {
  if (is.null(x) || length(x) == 0 || is.na(x)) NA_real_ else round(as.numeric(x), digits)
}

message(">>> [CLUTCH ENGINE] Initializing MLB True Clutch & Leverage Engine...")

run_mlb_clutch_engine <- function(
  players_file = file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json"),
  post_file = file.path(PROJECT_DIR, "web", "public", "data", "projections_postseason_ops.json"),
  fg_batters_file = NULL,
  fg_pitchers_file = NULL,
  boxscores_file = NULL,
  output_json = file.path(PROJECT_DIR, "web", "public", "data", "clutch_leverage_metrics.json"),
  expected_season = if (exists("MLB_CURRENT_SEASON")) MLB_CURRENT_SEASON else 2026L
) {
  snap <- read_projections_season_players(
    players_file = players_file,
    expected_season = expected_season,
    caller = "CLUTCH ENGINE"
  )
  if (!isTRUE(snap$ok)) {
    warning(snap$reason, call. = FALSE)
    return(invisible(NULL))
  }
  players_df <- snap$players
  if (is.null(players_df) || !is.data.frame(players_df) || nrow(players_df) == 0) {
    warning("No player rows available; skipping clutch leverage engine.")
    return(invisible(NULL))
  }
  post_ops <- if (!is.null(post_file) && file.exists(post_file)) fromJSON(post_file) else list()
  
  message(sprintf(">>> Loaded %d players from projections database.", nrow(players_df)))
  
  # Select Top Batters (by composite z-score and workload, NAs last)
  batters_pool <- players_df %>% 
    filter(player_type == "Batter") %>% 
    arrange(is.na(composite_zscore), desc(composite_zscore), is.na(proj_workload), desc(proj_workload)) %>% 
    head(150)
    
  # Select Top Pitchers (Relievers + Top Starters, NAs last)
  pitchers_pool <- players_df %>% 
    filter(player_type == "Pitcher") %>% 
    arrange(is.na(composite_zscore), desc(composite_zscore), is.na(proj_workload), desc(proj_workload)) %>% 
    head(150)
    
  # Load empirical FanGraphs splits and boxscores
  if (is.null(fg_batters_file)) {
    fg_batters_file <- file.path(PROJECT_DIR, "cache", "stats_sync", "fg_batters.rds")
    if (!file.exists(fg_batters_file) && exists("cache_path")) {
      fg_batters_file <- cache_path("stats_sync", "fg_batters.rds")
    }
  }
  fg_batters <- if (!is.null(fg_batters_file) && file.exists(fg_batters_file)) readRDS(fg_batters_file) else tibble::tibble()

  if (is.null(fg_pitchers_file)) {
    fg_pitchers_file <- file.path(PROJECT_DIR, "cache", "stats_sync", "fg_pitchers.rds")
    if (!file.exists(fg_pitchers_file) && exists("cache_path")) {
      fg_pitchers_file <- cache_path("stats_sync", "fg_pitchers.rds")
    }
  }
  fg_pitchers <- if (!is.null(fg_pitchers_file) && file.exists(fg_pitchers_file)) readRDS(fg_pitchers_file) else tibble::tibble()

  if (is.null(boxscores_file)) {
    boxscores_file <- file.path(PROJECT_DIR, "cache", "ingest", "mlb_boxscores_2026.rds")
    if (!file.exists(boxscores_file) && exists("cache_path")) {
      boxscores_file <- cache_path("ingest", "mlb_boxscores_2026.rds")
    }
  }
  boxscores_df <- if (!is.null(boxscores_file) && file.exists(boxscores_file)) {
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
    
    woba <- num_or_na(p$stat1_raw)
    iso <- num_or_na(p$stat2_raw)
    obp <- num_or_na(p$stat3_val)
    z_score <- num_or_na(p$composite_zscore)
    pa <- num_or_na(p$proj_workload)
    
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
    
    # Leverage Distribution Breakdown (%): no empirical PA-level LI bucket source in repo; emit NA/null
    high_pct <- NA_real_
    extreme_pct <- NA_real_
    med_pct <- NA_real_
    low_pct <- NA_real_
    
    # RISP 2-Out Situation Split: no empirical 2-out RISP split source in repo; emit NA/null
    risp_pa <- NA_integer_
    risp_woba <- NA_real_
    risp_avg <- NA_real_
    risp_obp <- NA_real_
    risp_slg <- NA_real_
    risp_ops <- NA_real_
    
    # Clutch Archetype Assignment
    archetype <- case_when(
      is.na(clutch_delta) ~ "Unclassified",
      clutch_delta >= 0.035 & high_li_wpa >= 2.0 ~ "Ice-in-Veins Walkoff Anchor",
      clutch_delta >= 0.020 & !is.na(risp_ops) & risp_ops >= 0.880 ~ "Two-Out RISP Punisher",
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
      position          = str_or_na(p$position),
      clutchArchetype   = archetype,
      baseMetricLabel   = "Base wOBA",
      baseMetricVal     = round_or_na(woba, 3),
      clutchMetricLabel = "High-LI wOBA",
      clutchMetricVal   = round_or_na(clutch_woba, 3),
      deltaClutch       = round_or_na(clutch_delta, 3),
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
    
    xfip <- num_or_na(p$stat1_pooled)
    proj_era <- num_or_na(p$stat2_pooled)
    rgs <- num_or_na(p$stat3_val)
    z_score <- num_or_na(p$composite_zscore)
    workload <- num_or_na(p$proj_workload)
    is_reliever <- if (!is.na(workload)) workload < 95 else NA
    
    # Expected wOBA against baseline (linear ERA-to-wOBA conversion)
    base_woba_against <- round((proj_era * 0.055) + 0.110, 3)
    
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
    } else if (!is.na(is_reliever) && !is.na(z_score)) {
      round(max(0.80, min(2.15, if (is_reliever) 1.55 + (z_score * 0.12) else 1.05 + (z_score * 0.04))), 2)
    } else {
      NA_real_
    }

    # High-LI wOBA against delta: negative delta means elite suppression under pressure
    # Derived from true FanGraphs Pitcher Clutch score (~50 pts per win of clutch)
    clutch_delta <- round(-clutch_score / 50, 3)
    clutch_woba_against <- round(base_woba_against + clutch_delta, 3)
    high_li_wpa <- round(wpa_total * 0.55 - (clutch_delta * 40), 2)

    # Leverage Breakdown: no empirical BF-level LI bucket source in repo; emit NA/null
    high_pct <- NA_real_
    extreme_pct <- NA_real_
    med_pct <- NA_real_
    low_pct <- NA_real_

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
    archetype <- if (isTRUE(is_reliever)) {
      if (!is.na(strand_rate) && strand_rate >= 82.0 && !is.na(high_li_wpa) && high_li_wpa >= 2.5) {
        "Bases-Loaded Fireman Eraser"
      } else if (!is.na(gmli) && gmli >= 1.70 && !is.na(clutch_delta) && clutch_delta <= -0.020) {
        "Triple-Digit 9th Inning Closer"
      } else if (!is.na(workload) && workload >= 65 && !is.na(strand_rate) && strand_rate >= 74.0) {
        "High-Leverage Multi-Inning Bridge"
      } else if (!is.na(clutch_delta) && clutch_delta <= -0.010) {
        "Groundball Double-Play Specialist"
      } else {
        "Middle Relief Low-Stress Arm"
      }
    } else if (isFALSE(is_reliever)) {
      if (!is.na(clutch_delta) && clutch_delta <= -0.020 && !is.na(rgs) && rgs >= 58.0) {
        "Ace Jam-Escape Specialist"
      } else if (!is.na(clutch_delta) && abs(clutch_delta) <= 0.015) {
        "Steady Workhorse Starter"
      } else {
        "High-Stress Volatile Starter"
      }
    } else {
      "Unclassified"
    }

    pitcher_pos <- str_or_na(p$position)
    if (is.na(pitcher_pos) && !is.na(is_reliever)) {
      pitcher_pos <- if (is_reliever) "RP" else "SP"
    }
    
    clutch_profiles[[p$player_id]] <- list(
      playerId          = p$player_id,
      mlbamId           = p$mlbam_id,
      playerName        = p$player_name,
      team              = p$team,
      playerType        = "Pitcher",
      position          = pitcher_pos,
      clutchArchetype   = archetype,
      baseMetricLabel   = "Base wOBA Against",
      baseMetricVal     = round_or_na(base_woba_against, 3),
      clutchMetricLabel = "High-LI wOBA Against",
      clutchMetricVal   = round_or_na(clutch_woba_against, 3),
      deltaClutch       = round_or_na(clutch_delta, 3),
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
        pa   = NA_integer_,
        avg  = NA_real_,
        obp  = NA_real_,
        slg  = NA_real_,
        wOBA = NA_real_,
        ops  = NA_real_
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
  batter_sub <- profile_list[vapply(profile_list, function(x) identical(x$playerType, "Batter"), logical(1))]
  batter_leaders <- if (length(batter_sub) > 0) {
    batter_order <- order(vapply(batter_sub, function(x) num_or_na(x$clutchScore), numeric(1)), decreasing = TRUE, na.last = TRUE)
    unname(vapply(head(batter_sub[batter_order], 10), function(x) as.character(x$playerName), character(1)))
  } else {
    character(0)
  }
    
  pitcher_sub <- profile_list[vapply(profile_list, function(x) identical(x$playerType, "Pitcher"), logical(1))]
  pitcher_leaders <- if (length(pitcher_sub) > 0) {
    pitcher_order <- order(vapply(pitcher_sub, function(x) num_or_na(x$clutchScore), numeric(1)), decreasing = TRUE, na.last = TRUE)
    unname(vapply(head(pitcher_sub[pitcher_order], 10), function(x) as.character(x$playerName), character(1)))
  } else {
    character(0)
  }
    
  output_catalog <- list(
    # generated_at is what tools/publish_web.R's assertion F reads: UTC, ISO-8601,
    # and FIRST in the object because F only scans the first 4096 bytes of the
    # file (this payload is ~287 KB). `updatedAt` is kept for the web app, which
    # already renders it; it is local-time and not a format F can parse.
    generated_at         = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    updatedAt            = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    projectionsSnapshot  = list(season = snap$season, as_of_date = snap$as_of_date),
    totalProfiles        = length(profile_list),
    clutchLeaderBatters  = batter_leaders,
    clutchLeaderPitchers = pitcher_leaders,
    profiles             = profile_list
  )
  
  dir.create(dirname(output_json), recursive = TRUE, showWarnings = FALSE)
  write(toJSON(output_catalog, auto_unbox = TRUE, pretty = TRUE, na = "null"), output_json)
  message(sprintf(">>> Wrote clutch metrics catalog to %s (%.2f MB)", output_json, file.info(output_json)$size / 1e6))
  
  invisible(output_catalog)
}

if (sys.nframe() == 0) {
  run_mlb_clutch_engine()
}
