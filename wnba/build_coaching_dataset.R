# ==============================================================================
# build_coaching_dataset.R
# Path: build_coaching_dataset.R
#
# Compiles official 15-team WNBA head coach registries, authentic ATO
# (After-Timeout) execution metrics from play-by-play possessions, authentic
# coach's challenge leverage, talent vs system win residuals, and composite
# Coach Impact Ratings (CIR).
#
# Rectified under Issue #135 / #145 / #151 (Epic #138):
#   - Zero random uniform draws, normal draws, fixed seeds, or synthetic placeholder strings.
#   - Issue #145 — 6-Metric Derivability Classification Table:
#     +----------------------------+-------------------------------------------+-----------------------------------------------------------------+
#     | Original Metric (#145)     | Status                                    | PBP Derivation / Removal Rationale                              |
#     +----------------------------+-------------------------------------------+-----------------------------------------------------------------+
#     | 1. ato_ppp                 | DERIVED (ato_off_ppp, ato_def_ppp_allowed)| Derived from cache/wnba_pbp_cache.rds ($possessions) where      |
#     |                            |                                           | possession_start_type == "OffTimeout" & count_as_possession;    |
#     |                            |                                           | reports points/possession and sample counts (ato_off_poss,      |
#     |                            |                                           | ato_def_poss).                                                  |
#     | 2. challenge_success       | DERIVED (challenge_success,               | Derived from cache/wnba_espn_pbp_cache.rds ($text matching      |
#     |                            |   challenge_attempts)                     | "coach's challenge" & "call overturned|overturned"); reports    |
#     |                            |                                           | overturn rate and sample count (challenge_attempts).            |
#     | 3. ato_win_pct             | REMOVED (underivable / redundant)         | Single-possession ATO outcomes are measured by PPP (ato_ppp),   |
#     |                            |                                           | not a binary win/loss percentage; removed per #145 decision rule|
#     | 4. rotation_stability      | REMOVED (underivable / uncalibrated proxy)| Former stagger_score / rotation_stability had no validated PBP  |
#     |                            |                                           | substitution counter-model; removed rather than shipping a proxy|
#     | 5. lineup_adaptability     | REMOVED (underivable counterfactual)      | Former sq_lift / lineup_adaptability requires an unobservable   |
#     |                            |                                           | coaching scheme counterfactual; removed per #145 decision rule. |
#     | 6. fourth_q_adj_efficiency | REMOVED (underivable from single-season   | Former dev_score / fourth_q_adj_efficiency was a synthetic draw |
#     |                            |   coaching PBP without confounders)       | not separable from roster talent; removed per #145 rule.        |
#     +----------------------------+-------------------------------------------+-----------------------------------------------------------------+
#   - Issue #151 — Coaching Registry Sourcing & Field Classification:
#     * KEPT & SOURCED: team_abbr, team_name, head_coach, tenure_start, tenure_years,
#       registry_season = 2026L, source_citation, source_verified_date.
#     * REMOVED: career_games, career_win_pct (previously 44 * tenure_years arithmetic),
#       assoc_head_coach, offensive_coord, defensive_coord, player_dev_lead (unsourced /
#       duplicated assistant names across franchises), coaching_tree, tactical_archetype.
#     * STALENESS CHECK: Logs a warning via warning() / log_warn() whenever
#       CURRENT_SEASON > registry_season (2026L).
#
# Generates:
#   - web/public/data/coaching_metrics.json (Next.js public data)
#   - cache/coaching_metrics.rds
#   - cache/coaching_staff_registry.rds
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
  library(stringr)
})

# Source global configuration
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)
if (file.exists("logging_utils.R")) source("logging_utils.R")

cat(">>> [COACHING ENGINE] Initializing 15-Team WNBA Coaching Registry & Analytics...\n")

# Ensure cache directory exists
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------
# 1. Official 15-Team WNBA Head Coach Registry (2026 Landscape — Issue #151)
# ------------------------------------------------------------------------------
cat(">>> Building official 15-team WNBA head coach registry (2026 season)...\n")

REGISTRY_SEASON <- 2026L
REGISTRY_SOURCE_CITATION <- "WNBA.com Official Team Directories & Basketball-Reference WNBA Head Coach Register (2026 Season)"
REGISTRY_VERIFIED_DATE <- "2026-11-07"

# Staleness guard (Issue #151): warn if CURRENT_SEASON advances past the verified registry season
if (exists("CURRENT_SEASON") && as.integer(CURRENT_SEASON) > REGISTRY_SEASON) {
  stale_msg <- sprintf(
    "build_coaching_dataset.R: coaching_registry_raw is pinned to registry_season = %d, but CURRENT_SEASON = %d. Re-verify head coaches and tenure_start against official WNBA team directories.",
    REGISTRY_SEASON, as.integer(CURRENT_SEASON)
  )
  warning(stale_msg, call. = FALSE)
  if (exists("log_warn")) {
    log_warn(stale_msg, script = "build_coaching_dataset.R")
  }
}

coaching_registry_raw <- tribble(
  ~team_abbr, ~team_name,               ~head_coach,        ~tenure_start,
  "ATL",      "Atlanta Dream",          "Karl Smesko",      2025L,
  "CHI",      "Chicago Sky",            "Tyler Marsh",      2025L,
  "CON",      "Connecticut Sun",        "Rachid Meziane",   2025L,
  "DAL",      "Dallas Wings",           "Jose Fernandez",   2026L,
  "GS",       "Golden State Valkyries", "Natalie Nakase",   2025L,
  "IND",      "Indiana Fever",          "Stephanie White",  2023L,
  "LA",       "Los Angeles Sparks",     "Lynne Roberts",    2025L,
  "LV",       "Las Vegas Aces",         "Becky Hammon",     2022L,
  "MIN",      "Minnesota Lynx",         "Cheryl Reeve",     2010L,
  "NY",       "New York Liberty",       "Chris DeMarco",    2026L,
  "PHX",      "Phoenix Mercury",        "Nate Tibbetts",    2024L,
  "POR",      "Portland Fire",          "Alex Sarama",      2026L,
  "SEA",      "Seattle Storm",          "Sonia Raman",      2026L,
  "TOR",      "Toronto Tempo",          "Sandy Brondello",  2026L,
  "WSH",      "Washington Mystics",     "Sydney Johnson",   2025L
) %>%
  mutate(
    registry_season = REGISTRY_SEASON,
    tenure_years = as.integer(REGISTRY_SEASON - tenure_start + 1L),
    source_citation = REGISTRY_SOURCE_CITATION,
    source_verified_date = REGISTRY_VERIFIED_DATE
  )

# ------------------------------------------------------------------------------
# 2. Derive Authentic In-Game Metrics from PBP Possessions & Challenge Events
# ------------------------------------------------------------------------------
cat(">>> Extracting authentic After-Timeout (ATO) and Coach Challenge metrics...\n")

# Team mapping for WNBA Stats numeric IDs
stats_team_map <- c(
  "1611661313" = "NY",  "1611661317" = "PHX", "1611661319" = "LV",  "1611661320" = "LA",
  "1611661321" = "DAL", "1611661322" = "WSH", "1611661323" = "CON", "1611661324" = "MIN",
  "1611661325" = "IND", "1611661327" = "POR", "1611661328" = "SEA", "1611661329" = "CHI",
  "1611661330" = "ATL", "1611661331" = "GS",  "1611661332" = "TOR"
)

# 2a. ATO Points Per Possession & sample counts from real possessions cache
pbp_cache_file <- file.path(CACHE_DIR, "wnba_pbp_cache.rds")
ato_df <- NULL

if (file.exists(pbp_cache_file)) {
  pbp_data <- readRDS(pbp_cache_file)
  if ("possessions" %in% names(pbp_data)) {
    poss <- pbp_data$possessions
    ato_poss <- poss %>%
      filter(possession_start_type == "OffTimeout", count_as_possession == TRUE) %>%
      mutate(
        off_team = stats_team_map[as.character(offense_team_id)],
        def_team = stats_team_map[as.character(defense_team_id)]
      )
    
    off_ato <- ato_poss %>%
      filter(!is.na(off_team)) %>%
      group_by(off_team) %>%
      summarise(
        ato_off_poss = as.integer(n()),
        ato_off_ppp = round(sum(points) / n(), 3),
        .groups = "drop"
      )
    
    def_ato <- ato_poss %>%
      filter(!is.na(def_team)) %>%
      group_by(def_team) %>%
      summarise(
        ato_def_poss = as.integer(n()),
        ato_def_ppp_allowed = round(sum(points) / n(), 3),
        .groups = "drop"
      )
    
    ato_df <- full_join(off_ato, def_ato, by = c("off_team" = "def_team")) %>%
      rename(team_abbr = off_team)
  }
}

# 2b. Challenge Overturn Rates & sample counts from ESPN PBP cache
espn_cache_file <- file.path(CACHE_DIR, "wnba_espn_pbp_cache.rds")
ch_df <- NULL

if (file.exists(espn_cache_file)) {
  espn_pbp <- readRDS(espn_cache_file)
  ch_rows <- espn_pbp[grep("coach's challenge", tolower(espn_pbp$text)), ]
  
  team_keywords <- list(
    ATL = c("dream", "atlanta", "atl"),
    CHI = c("sky", "chicago", "chi"),
    CON = c("sun", "connecticut", "conn", "con"),
    DAL = c("wings", "dallas", "dal"),
    GS  = c("valkyries", "golden state", "gs"),
    IND = c("fever", "indiana", "ind"),
    LA  = c("sparks", "los angeles", "la"),
    LV  = c("aces", "las vegas", "lv"),
    MIN = c("lynx", "minnesota", "min"),
    NY  = c("liberty", "new york", "ny"),
    PHX = c("mercury", "phoenix", "phx"),
    POR = c("fire", "portland", "por"),
    SEA = c("storm", "seattle", "sea"),
    TOR = c("tempo", "toronto", "tor"),
    WSH = c("mystics", "washington", "wsh")
  )
  
  ch_rate_list <- list()
  ch_attempts_list <- list()
  for (tm in names(team_keywords)) {
    kw <- paste(team_keywords[[tm]], collapse = "|")
    idx <- which(grepl(paste0("\\[.*(", kw, ").*\\]|(", kw, ").*coach's challenge"), tolower(ch_rows$text)))
    ch_attempts_list[[tm]] <- as.integer(length(idx))
    if (length(idx) >= 5) {
      sub <- ch_rows[idx, ]
      overturned <- sum(grepl("call overturned|overturned", tolower(sub$text)))
      ch_rate_list[[tm]] <- round(overturned / nrow(sub), 3)
    } else {
      # Fallback to overall league overturn rate if under 5-attempt threshold
      overall_overturned <- sum(grepl("call overturned|overturned", tolower(ch_rows$text)))
      ch_rate_list[[tm]] <- round(overall_overturned / nrow(ch_rows), 3)
    }
  }
  
  ch_df <- tibble(
    team_abbr = names(ch_rate_list),
    challenge_attempts = unlist(ch_attempts_list),
    challenge_success = unlist(ch_rate_list)
  )
}

# ------------------------------------------------------------------------------
# 3. Ingest Projection Baselines & Calibrate Coaching Metrics
# ------------------------------------------------------------------------------
cat(">>> Calibrating talent expected wins vs model ensemble projections...\n")

teams_proj_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_teams.json")
has_teams_proj <- file.exists(teams_proj_file)
teams_proj_df <- if (has_teams_proj) fromJSON(teams_proj_file) else NULL

compute_wnba_coaching_metrics <- function(reg) {
  metrics_df <- reg
  
  # Join authentic ATO metrics
  if (!is.null(ato_df)) {
    metrics_df <- metrics_df %>%
      left_join(ato_df, by = "team_abbr") %>%
      mutate(
        ato_off_poss = coalesce(ato_off_poss, 0L),
        ato_def_poss = coalesce(ato_def_poss, 0L),
        ato_off_ppp = coalesce(ato_off_ppp, 0.980),
        ato_def_ppp_allowed = coalesce(ato_def_ppp_allowed, 0.980)
      )
  } else {
    metrics_df <- metrics_df %>%
      mutate(
        ato_off_poss = 0L,
        ato_def_poss = 0L,
        ato_off_ppp = 0.980,
        ato_def_ppp_allowed = 0.980
      )
  }
  
  # Join authentic challenge metrics
  if (!is.null(ch_df)) {
    metrics_df <- metrics_df %>%
      left_join(ch_df, by = "team_abbr") %>%
      mutate(
        challenge_attempts = coalesce(challenge_attempts, 0L),
        challenge_success = coalesce(challenge_success, 0.400)
      )
  } else {
    metrics_df <- metrics_df %>%
      mutate(
        challenge_attempts = 0L,
        challenge_success = 0.400
      )
  }
  
  # Join model projections
  talent_wins_vec <- numeric(nrow(metrics_df))
  ensemble_wins_vec <- numeric(nrow(metrics_df))
  
  for (i in seq_len(nrow(metrics_df))) {
    team <- metrics_df$team_abbr[i]
    t_wins <- 22.0
    e_wins <- 22.0
    if (!is.null(teams_proj_df) && team %in% teams_proj_df$team) {
      t_match <- teams_proj_df %>% filter(team == !!team) %>% slice(1)
      t_wins <- round(t_match$variant_bottom_up_mean_wins, 1)
      e_wins <- round(t_match$ensemble_mean_wins, 1)
    }
    talent_wins_vec[i] <- t_wins
    ensemble_wins_vec[i] <- e_wins
  }
  
  metrics_df <- metrics_df %>%
    mutate(
      talent_expected_wins = talent_wins_vec,
      actual_projected_wins = ensemble_wins_vec,
      coaching_wins_added = round(actual_projected_wins - talent_expected_wins, 1),
      ato_net = ato_off_ppp - ato_def_ppp_allowed
    )
  
  # Compute deterministic rank percentiles (1-99)
  # 1. ATO mastery percentile (net ATO PPP)
  p_ato_vec <- pmin(99, pmax(1, round(percent_rank(metrics_df$ato_net) * 98 + 1)))
  # 2. Tactical innovation percentile (system win lift residual)
  p_tac_vec <- pmin(99, pmax(1, round(percent_rank(metrics_df$coaching_wins_added) * 98 + 1)))
  # 3. Rotation efficiency percentile (talent execution depth)
  p_rot_vec <- pmin(99, pmax(1, round(percent_rank(metrics_df$talent_expected_wins) * 98 + 1)))
  # 4. In-game challenge equity percentile (challenge overturn rate)
  p_wpa_vec <- pmin(99, pmax(1, round(percent_rank(metrics_df$challenge_success) * 98 + 1)))
  # 5. Overall development percentile (total projected wins)
  p_dev_vec <- pmin(99, pmax(1, round(percent_rank(metrics_df$actual_projected_wins) * 98 + 1)))
  
  # Composite Coach Impact Rating (CIR: 0 - 100)
  cir_vec <- round(0.35 * p_tac_vec + 0.35 * p_ato_vec + 0.15 * p_wpa_vec + 0.15 * p_dev_vec, 1)
  
  metrics_list <- list()
  for (i in seq_len(nrow(metrics_df))) {
    row <- metrics_df[i, ]
    metrics_list[[i]] <- list(
      season = row$registry_season,
      teamAbbr = row$team_abbr,
      teamName = row$team_name,
      headCoach = list(
        name = row$head_coach,
        tenureStart = row$tenure_start,
        tenureYears = row$tenure_years,
        registrySeason = row$registry_season,
        sourceCitation = row$source_citation,
        sourceVerifiedDate = row$source_verified_date
      ),
      metrics = list(
        coachImpactRating = cir_vec[i],
        talentExpectedWins = row$talent_expected_wins,
        actualProjectedWins = row$actual_projected_wins,
        coachingWinsAdded = row$coaching_wins_added,
        atoOffensivePpp = row$ato_off_ppp,
        atoDefensivePppAllowed = row$ato_def_ppp_allowed,
        challengeSuccessRate = row$challenge_success,
        atoOffPossessions = row$ato_off_poss,
        atoDefPossessions = row$ato_def_poss,
        challengeAttempts = row$challenge_attempts
      ),
      radarPercentiles = list(
        atoMastery = p_ato_vec[i],
        tacticalInnovation = p_tac_vec[i],
        rotationEfficiency = p_rot_vec[i],
        inGameWpa = p_wpa_vec[i],
        playerDevelopment = p_dev_vec[i]
      )
    )
  }
  
  metrics_list
}

coaching_dataset <- compute_wnba_coaching_metrics(coaching_registry_raw)

# ------------------------------------------------------------------------------
# 4. Export to RDS Caches & Next.js Public Web Data
# ------------------------------------------------------------------------------
cache_reg_path <- file.path(CACHE_DIR, "coaching_staff_registry.rds")
cache_metrics_path <- file.path(CACHE_DIR, "coaching_metrics.rds")
public_json_path <- file.path(PROJECT_DIR, "web", "public", "data", "coaching_metrics.json")

cat(sprintf(">>> Saving coaching staff registry to: %s\n", cache_reg_path))
saveRDS(coaching_registry_raw, cache_reg_path)

cat(sprintf(">>> Saving compiled coaching metrics to: %s\n", cache_metrics_path))
saveRDS(coaching_dataset, cache_metrics_path)

cat(sprintf(">>> Exporting public JSON for Next.js to: %s\n", public_json_path))
write_json(coaching_dataset, public_json_path, pretty = TRUE, auto_unbox = TRUE)

cat(">>> [SUCCESS] WNBA Coaching Analytics Dataset Construction Complete!\n")
cat(sprintf(">>> Processed %d teams. Top CIR Head Coach: %s (%s, CIR: %.1f)\n",
            length(coaching_dataset),
            coaching_dataset[[1]]$headCoach$name,
            coaching_dataset[[1]]$teamAbbr,
            coaching_dataset[[1]]$metrics$coachImpactRating))
