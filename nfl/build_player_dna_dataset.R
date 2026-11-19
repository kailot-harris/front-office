# ==============================================================================
# build_player_dna_dataset.R
# Feature: High-Dimensional NFL Player DNA & Nearest Current-Season Peer Comparables
# Calculates 5-D skill vectors for QBs and skill positions (WR/RB/TE) and compares each
# player with every OTHER qualified player of the same position in the same season
# window. No hand-typed historical comparables (NFL_analytics #79) and no mixed or
# unstated seasons (NFL_analytics #78). Modelled on NBA_analytics PR #195.
#
# All skill dimensions are grounded in empirical play-by-play
# (cache/nfl_pbp_<CURRENT_SEASON>.rds), Next Gen Stats tracking
# (cache/nfl_ngs_passing_<CURRENT_SEASON>.rds, cache/nfl_ngs_rushing_<CURRENT_SEASON>.rds)
# and player box logs (cache/nfl_player_stats_<CURRENT_SEASON>.rds). The cache paths are the
# CACHE_DNA_* constants in config.R.
#
# Exports JSON for the Next.js web application to web/public/data/player_dna_profiles.json
# (WEB_JSON_PLAYER_DNA_PROFILES) as an envelope:
#   { season, throughWeek, generatedAt, profiles: [...] }
#
# Data window (front-office#109, NFL_analytics #78)
#   Season: CURRENT_SEASON (config.R) only, shared with /clutch. Every input is read by the
#     exact filename built from it. When a file is missing the builder downloads exactly that
#     season with nflreadr and saves it under that name; it never globs, never falls back to
#     another season, and stops if a loaded file holds any other season.
#   throughWeek: the largest week W such that every regular-season game scheduled in weeks
#     1..W has finished and appears in the play-by-play (schedule from nflreadr, saved as
#     CACHE_DNA_SCHEDULES). Box rows, play-by-play and Next Gen Stats are all restricted to
#     weeks <= throughWeek, so the published window is exactly "season, weeks 1..throughWeek".
#   Filters: regular season only. QB pass and scramble plays, receiver targets and rushes.
#   Minimum sample: QBs need 40+ pass attempts or 4+ games. RBs need 40+ carries or 25+
#     targets, WRs 30+ targets, TEs 25+ targets (listed as "qualified players" on the page).
#     Early in a season these gates admit few players; they are not relaxed.
#   Known issues: pipeline wiring is NFL_analytics #86 (this builder is run by hand).
#
# Methodology (documented modelling choices on real data, not fabricated data)
#   - Shrinkage: deep and short completion rates are Empirical-Bayes shrunk toward
#     fixed priors (deep 0.40 with 5 pseudo-attempts, short 0.70 with 10) so tiny
#     samples do not produce extreme rates. Touchdown and explosive-play rates add
#     fixed pseudo-opportunities. Priors apply only on top of the player's own real
#     attempts; a player with no attempt data at all is null, not prior-only.
#   - Each raw dimension is a fixed weighted blend of real rates (weights visible in the
#     raw_* definitions below). Next Gen Stats inputs are weekly rows weighted by the
#     player's volume (attempts / rush attempts) over weeks 1..throughWeek.
#   - Scaling: each raw dimension becomes an ecdf percentile WITHIN the player's position,
#     scaled to 15 + 84 * ecdf (range 15-99). A dimension with no variance is null.
#   - Missing inputs are never imputed: no zero-fills, no position constants, no priors-only
#     values. If any real input of a dimension is missing (for example no Next Gen Stats row,
#     no deep attempts) that dimension is null.
#   - Null thresholds (config.R): overallRating is the mean of the non-null dimensions and is
#     null unless at least DNA_MIN_DIMS_OVERALL (3 of 5) are non-null. categoryScores are the
#     5 dimensions themselves (each null when its dimension is null). The archetype label is
#     null when overallRating is null.
#   - Peer comps: for each player, the DNA_PEER_COUNT (5) other players of the same position
#     with the highest similarity. Similarity is the cosine of the 50-centred percentile
#     vectors over the dimensions non-null for BOTH players, and requires at least
#     DNA_MIN_SHARED_DIMS (4 of 5) shared dimensions. Published as
#     similarityPct = max(cos, 0) * 100, one decimal. Centring removes the shared positive
#     offset of 15-99 percentiles that otherwise makes every pair look ~90% alike.
#     Ties break on playerId so repeated runs are identical.
#   - A player below the shared-dimension minimum gets peerComps = [] and can never appear
#     as another player's peer. keySharedTrait is a readable label of the shared dimension
#     where both players are strongest (or, if neither is above 50, weakest).
#   - Output is deterministic apart from generatedAt.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(sprintf(">>> [PLAYER DNA] Initializing Empirical Player DNA & Peer Comps (season %d)...\n", CURRENT_SEASON))

# Team code normalization
clean_team <- function(t) {
  t <- as.character(t)
  t[t == "LAR"] <- "LA"
  t[t == "WSH"] <- "WAS"
  t
}

# NaN from mean()/division over empty groups is a missing value, not a number
nan_to_na <- function(x) ifelse(is.nan(x), NA_real_, x)

# ------------------------------------------------------------------------------
# 1. Load current-season caches (exact filenames; download that one season if absent)
# ------------------------------------------------------------------------------
load_season_cache <- function(path, loader, label) {
  d <- if (file.exists(path)) {
    readRDS(path)
  } else if (requireNamespace("nflreadr", quietly = TRUE)) {
    cat(sprintf(">>> Downloading %s for season %d via nflreadr -> %s\n", label, CURRENT_SEASON, basename(path)))
    d <- loader()
    saveRDS(d, path)
    d
  } else {
    stop(sprintf("Missing %s cache '%s' and nflreadr is unavailable", label, path))
  }
  if (!"season" %in% names(d) || nrow(d) == 0 || !all(d$season == CURRENT_SEASON)) {
    stop(sprintf("%s cache '%s' is empty or holds seasons other than %d; delete it and re-run",
                 label, path, CURRENT_SEASON))
  }
  d
}

pbp       <- load_season_cache(CACHE_DNA_PBP, function() nflreadr::load_pbp(seasons = CURRENT_SEASON), "play-by-play")
ps        <- load_season_cache(CACHE_DNA_PLAYER_STATS, function() nflreadr::load_player_stats(seasons = CURRENT_SEASON), "player stats")
schedule  <- load_season_cache(CACHE_DNA_SCHEDULES, function() nflreadr::load_schedules(seasons = CURRENT_SEASON), "schedule")
ngs_pass  <- load_season_cache(CACHE_DNA_NGS_PASSING, function() nflreadr::load_nextgen_stats(seasons = CURRENT_SEASON, stat_type = "passing"), "NGS passing")
ngs_rush  <- load_season_cache(CACHE_DNA_NGS_RUSHING, function() nflreadr::load_nextgen_stats(seasons = CURRENT_SEASON, stat_type = "rushing"), "NGS rushing")

# throughWeek: last week W where every scheduled REG game in weeks 1..W is in the play-by-play
sched_reg <- schedule %>% filter(game_type == "REG")
pbp_games <- unique(pbp$game_id[pbp$season_type == "REG" & !is.na(pbp$week)])
week_done <- sched_reg %>%
  group_by(week) %>%
  summarise(done = all(game_id %in% pbp_games), .groups = "drop") %>%
  arrange(week)
incomplete <- week_done$week[!week_done$done]
through_week <- if (length(incomplete) == 0) max(week_done$week) else min(incomplete) - 1L
through_week <- as.integer(through_week)
if (!is.finite(through_week) || through_week < 1L) stop("No completed regular-season week in the play-by-play data")

cat(sprintf(">>> Loaded caches for %d: PBP (%d rows), Player Stats (%d rows); completed through Week %d\n",
            CURRENT_SEASON, nrow(pbp), nrow(ps), through_week))

# Regular season, completed weeks only
ps_reg  <- ps  %>% filter(season_type == "REG", week <= through_week)
pbp_reg <- pbp %>% filter(season_type == "REG", week <= through_week)

# Volume-weighted mean (NA when there is no usable row)
wmean <- function(x, w) {
  ok <- !is.na(x) & !is.na(w) & w > 0
  if (!any(ok)) NA_real_ else sum(x[ok] * w[ok]) / sum(w[ok])
}

# Empirical percentile mapping [15.0 to 99.0]; NA stays NA, no variance -> NA (no imputed 50)
pct_map <- function(v) {
  ok <- !is.na(v)
  if (sum(ok) == 0 || length(unique(v[ok])) <= 1) return(rep(NA_real_, length(v)))
  fn <- stats::ecdf(v[ok])
  res <- rep(NA_real_, length(v))
  res[ok] <- pmin(pmax(round(15.0 + fn(v[ok]) * 84.0, 1), 15.0), 99.0)
  res
}

# ------------------------------------------------------------------------------
# 2. Derive Empirical QB Skill Dimensions
# ------------------------------------------------------------------------------
cat(">>> Extracting QB empirical metrics from PBP, NGS and box stats...\n")

pbp_qb <- pbp_reg %>%
  filter(!is.na(passer_player_id), pass == 1 | qb_scramble == 1) %>%
  group_by(passer_player_id) %>%
  summarise(
    deep_attempts = sum(air_yards >= 15, na.rm = TRUE),
    deep_completions = sum(air_yards >= 15 & complete_pass == 1, na.rm = TRUE),
    deep_epa = nan_to_na(mean(epa[which(air_yards >= 15)], na.rm = TRUE)),
    pressure_epa = nan_to_na(mean(epa[which(qb_hit == 1 | sack == 1)], na.rm = TRUE)),
    short_attempts = sum(air_yards < 10, na.rm = TRUE),
    short_completions = sum(air_yards < 10 & complete_pass == 1, na.rm = TRUE),
    scramble_epa_tot = sum(epa[which(qb_scramble == 1)], na.rm = TRUE),
    .groups = "drop"
  )

ngs_qb <- ngs_pass %>%
  filter(season_type == "REG", week >= 1, week <= through_week, !is.na(player_gsis_id)) %>%
  group_by(player_gsis_id) %>%
  summarise(
    avg_time_to_throw = wmean(avg_time_to_throw, attempts),
    avg_intended_air_yards = wmean(avg_intended_air_yards, attempts),
    aggressiveness = wmean(aggressiveness, attempts),
    .groups = "drop"
  )

qb_box <- ps_reg %>%
  filter(position == "QB") %>%
  group_by(player_id) %>%
  summarise(
    player_name = first(player_name),
    position = "QB",
    games = n_distinct(game_id),
    attempts = sum(attempts, na.rm = TRUE),
    pass_yards = sum(passing_yards, na.rm = TRUE),
    pass_tds = sum(passing_tds, na.rm = TRUE),
    interceptions = sum(passing_interceptions, na.rm = TRUE),
    sacks = sum(sacks_suffered, na.rm = TRUE),
    air_yards_tot = sum(passing_air_yards, na.rm = TRUE),
    pass_epa_tot = sum(passing_epa, na.rm = TRUE),
    pass_cpoe_mean = nan_to_na(mean(passing_cpoe, na.rm = TRUE)),
    carries = sum(carries, na.rm = TRUE),
    rush_yards = sum(rushing_yards, na.rm = TRUE),
    rush_tds = sum(rushing_tds, na.rm = TRUE),
    rush_epa_tot = sum(rushing_epa, na.rm = TRUE),
    team = clean_team(last(team)),
    .groups = "drop"
  ) %>%
  filter(attempts >= 40 | games >= 4)

qb_combined <- qb_box %>%
  left_join(pbp_qb, by = c("player_id" = "passer_player_id")) %>%
  left_join(ngs_qb, by = c("player_id" = "player_gsis_id")) %>%
  mutate(
    # Raw dimensions: any missing real input -> NA (never coalesced to a constant)
    # 1. Deep accuracy: shrunk deep completion rate + CPOE + deep EPA/play
    raw_deep_acc = (deep_completions + 5 * 0.40) / (deep_attempts + 5) * 50 +
                   pass_cpoe_mean * 1.5 + deep_epa * 20,
    # 2. Pressure resilience: EPA on pressured dropbacks + sack avoidance + NGS aggressiveness
    sack_avoidance = 1.0 - (sacks / (attempts + sacks + 1)),
    raw_pressure_res = pressure_epa * 50 + sack_avoidance * 40 + aggressiveness * 0.5,
    # 3. Quick game: shrunk short completion rate + fast release (inverse NGS time to throw)
    raw_quick_game = (short_completions + 10 * 0.70) / (short_attempts + 10) * 60 +
                     pmax(0, 3.2 - avg_time_to_throw) * 40,
    # 4. Scramble / rushing EPA and rush yards per game
    raw_scramble_epa = scramble_epa_tot * 1.5 + rush_epa_tot * 1.0 + (rush_yards / games) * 0.8,
    # 5. Air yards: air yards per attempt + NGS intended air yards
    raw_air_yards = if_else(attempts > 0, air_yards_tot / attempts, NA_real_) * 8.0 +
                    avg_intended_air_yards * 4.0
  )

cat(sprintf(">>> Processed %d QBs.\n", nrow(qb_combined)))

# ------------------------------------------------------------------------------
# 3. Derive Empirical Skill Position Dimensions (WR / RB / TE)
# ------------------------------------------------------------------------------
cat(">>> Extracting Skill Position empirical metrics from PBP, NGS and box stats...\n")

# Yards after the catch relative to expectation, per catch (completed passes only)
pbp_rec <- pbp_reg %>%
  filter(!is.na(receiver_player_id), pass == 1, complete_pass == 1) %>%
  group_by(receiver_player_id) %>%
  summarise(
    catches_pbp = n(),
    yac_over_expected_tot = sum(yards_after_catch - xyac_mean_yardage, na.rm = TRUE),
    .groups = "drop"
  )

ngs_rush_agg <- ngs_rush %>%
  filter(season_type == "REG", week >= 1, week <= through_week, !is.na(player_gsis_id)) %>%
  group_by(player_gsis_id) %>%
  summarise(
    ryoe_per_att = wmean(rush_yards_over_expected_per_att, rush_attempts),
    .groups = "drop"
  )

skill_box <- ps_reg %>%
  filter(position %in% c("WR", "RB", "TE")) %>%
  group_by(player_id) %>%
  summarise(
    player_name = first(player_name),
    position = first(position),
    games = n_distinct(game_id),
    carries = sum(carries, na.rm = TRUE),
    rush_yards = sum(rushing_yards, na.rm = TRUE),
    rush_tds = sum(rushing_tds, na.rm = TRUE),
    targets = sum(targets, na.rm = TRUE),
    receptions = sum(receptions, na.rm = TRUE),
    rec_yards = sum(receiving_yards, na.rm = TRUE),
    rec_tds = sum(receiving_tds, na.rm = TRUE),
    rec_yac = sum(receiving_yards_after_catch, na.rm = TRUE),
    target_share_mean = nan_to_na(mean(target_share, na.rm = TRUE)),
    wopr_mean = nan_to_na(mean(wopr, na.rm = TRUE)),
    explosive_rec = sum(receiving_20, na.rm = TRUE),
    explosive_rush = sum(rushing_20, na.rm = TRUE),
    tot_epa = sum(receiving_epa, na.rm = TRUE) + sum(rushing_epa, na.rm = TRUE),
    team = clean_team(last(team)),
    .groups = "drop"
  ) %>%
  filter(
    (position == "RB" & (carries >= 40 | targets >= 25)) |
    (position == "WR" & targets >= 30) |
    (position == "TE" & targets >= 25)
  )

skill_combined <- skill_box %>%
  left_join(pbp_rec, by = c("player_id" = "receiver_player_id")) %>%
  left_join(ngs_rush_agg, by = c("player_id" = "player_gsis_id")) %>%
  mutate(
    total_touches = carries + receptions,
    total_scrimmage_yards = rush_yards + rec_yards,
    total_tds = rush_tds + rec_tds,
    opportunities = carries + targets,
    yac_per_rec = if_else(receptions > 0, rec_yac / receptions, NA_real_),

    # 1. Target share / volume gravity (RBs blend target share and carry volume)
    raw_target_share = if_else(
      position == "RB",
      target_share_mean * 60 + (carries / games) * 3.5,
      target_share_mean * 100 + wopr_mean * 30
    ),
    # 2. YAC over expected / elusiveness (RB: NGS RYOE per attempt needed)
    raw_yac_oe = if_else(
      position == "RB",
      ryoe_per_att * 25 + yac_per_rec * 8 + if_else(carries > 0, rush_yards / carries, NA_real_) * 10,
      if_else(catches_pbp > 0, yac_over_expected_tot / catches_pbp, NA_real_) * 20 + yac_per_rec * 10
    ),
    # 3. Touchdown efficiency (shrunk by pseudo-opportunities)
    raw_td_eff = (total_tds + 1.0) / (opportunities + 20.0) * 1000,
    # 4. Explosive play rate: 20+ yd plays per opportunity (shrunk)
    raw_explosive = (explosive_rec + explosive_rush + 2.0) / (opportunities + 25.0) * 1000,
    # 5. Versatility & scrimmage impact
    raw_versatility = (total_scrimmage_yards / games) * 0.8 +
                      (tot_epa / opportunities) * 50.0 +
                      (total_touches / games) * 2.0
  )

cat(sprintf(">>> Processed %d Skill Position players (WR/RB/TE).\n", nrow(skill_combined)))

# ------------------------------------------------------------------------------
# 4. Percentiles within position, then one unified player table
# ------------------------------------------------------------------------------
qb_dims    <- c("deep_accuracy", "pressure_resilience", "quick_game", "scramble_epa", "air_yards_share")
skill_dims <- c("target_share", "yac_over_expected", "touchdown_efficiency", "explosive_play_rate", "versatility_impact")
qb_raw     <- c("raw_deep_acc", "raw_pressure_res", "raw_quick_game", "raw_scramble_epa", "raw_air_yards")
skill_raw  <- c("raw_target_share", "raw_yac_oe", "raw_td_eff", "raw_explosive", "raw_versatility")

dim_labels <- c(
  deep_accuracy = "Deep accuracy", pressure_resilience = "Pressure resilience",
  quick_game = "Quick game", scramble_epa = "Scramble EPA", air_yards_share = "Air yards",
  target_share = "Target share", yac_over_expected = "YAC over expected",
  touchdown_efficiency = "Touchdown efficiency", explosive_play_rate = "Explosive play rate",
  versatility_impact = "Scrimmage impact"
)

# One row per player; percentile matrix columns follow the position's dimension names
pct_matrix <- function(df, raw_cols, dims) {
  m <- matrix(NA_real_, nrow = nrow(df), ncol = length(dims), dimnames = list(NULL, dims))
  for (pos in unique(df$position)) {
    idx <- which(df$position == pos)
    for (k in seq_along(dims)) m[idx, k] <- pct_map(df[[raw_cols[k]]][idx])
  }
  m
}
qb_m    <- pct_matrix(qb_combined, qb_raw, qb_dims)
skill_m <- pct_matrix(skill_combined, skill_raw, skill_dims)

entries <- list()
for (i in seq_len(nrow(qb_combined))) {
  q <- qb_combined[i, ]
  denom <- q$attempts + q$carries
  entries[[length(entries) + 1]] <- list(
    id = q$player_id, name = q$player_name, team = ifelse(is.na(q$team) | !nzchar(q$team), "FA", q$team),
    pos = "QB", vec = qb_m[i, ],
    stats = list(
      games = as.integer(q$games), passYards = as.integer(q$pass_yards), passTds = as.integer(q$pass_tds),
      interceptions = as.integer(q$interceptions), rushYards = as.integer(q$rush_yards),
      rushTds = as.integer(q$rush_tds),
      epaPerPlay = if (denom > 0) round((q$pass_epa_tot + q$rush_epa_tot) / denom, 3) else NA_real_
    )
  )
}
for (i in seq_len(nrow(skill_combined))) {
  s <- skill_combined[i, ]
  entries[[length(entries) + 1]] <- list(
    id = s$player_id, name = s$player_name, team = ifelse(is.na(s$team) | !nzchar(s$team), "FA", s$team),
    pos = s$position, vec = skill_m[i, ],
    stats = list(
      games = as.integer(s$games), rushYards = as.integer(s$rush_yards), rushTds = as.integer(s$rush_tds),
      receptions = as.integer(s$receptions), recYards = as.integer(s$rec_yards), recTds = as.integer(s$rec_tds),
      epaPerPlay = if (s$opportunities > 0) round(s$tot_epa / s$opportunities, 3) else NA_real_
    )
  )
}
ids <- vapply(entries, function(e) e$id, character(1))
stopifnot(!anyDuplicated(ids))

# ------------------------------------------------------------------------------
# 5. Archetypes, similarity and peer comps
# ------------------------------------------------------------------------------
n_dims_present <- function(vec) sum(!is.na(vec))
overall_of <- function(vec) {
  if (n_dims_present(vec) < DNA_MIN_DIMS_OVERALL) NA_real_ else round(mean(vec, na.rm = TRUE), 1)
}

# Threshold archetype labels; NA-safe (a missing dimension never satisfies a threshold)
assign_archetype <- function(vec, pos) {
  if (n_dims_present(vec) < DNA_MIN_DIMS_OVERALL) return(NA_character_)
  ge <- function(nm, t) !is.na(vec[[nm]]) && vec[[nm]] >= t
  if (pos == "QB") {
    if (ge("scramble_epa", 85) && ge("deep_accuracy", 80)) "Dual-Threat Off-Platform Playmaker" else
    if (ge("quick_game", 85) && ge("pressure_resilience", 80)) "Surgical Rhythm Field General" else
    if (ge("deep_accuracy", 85) && ge("air_yards_share", 85)) "Downfield Vertical Cannoneer" else
    if (ge("scramble_epa", 85)) "Dynamic Dual-Threat Scrambler" else
    if (ge("pressure_resilience", 85)) "Poised In-Pocket Eraser" else
    if (ge("quick_game", 80)) "Quick-Release Distributor" else
    "Balanced In-Structure Operator"
  } else if (pos == "RB") {
    if (ge("yac_over_expected", 85) && ge("target_share", 80)) "Elite Dual-Threat Scrimmage Engine" else
    if (ge("touchdown_efficiency", 85) && ge("explosive_play_rate", 80)) "Downhill Breakaway Finisher" else
    if (ge("yac_over_expected", 85)) "Contact-Balance Zone Slasher" else
    if (ge("target_share", 80)) "Pass-Catching Space Weapon" else
    "Complete Workhorse Running Back"
  } else if (pos == "WR") {
    if (ge("explosive_play_rate", 88) && ge("yac_over_expected", 85)) "Hyper-Explosive Dynamic Gamebreaker" else
    if (ge("target_share", 88) && ge("touchdown_efficiency", 80)) "Alpha Target Vacuum & Red-Zone Hub" else
    if (ge("explosive_play_rate", 85)) "Vertical Deep-Threat Boundary Burner" else
    if (ge("target_share", 85)) "High-Volume Intermediate Chain Mover" else
    if (ge("yac_over_expected", 80)) "Dynamic Open-Field YAC Specialist" else
    "Versatile Multi-Alignment Receiver"
  } else {
    if (ge("target_share", 85) && ge("touchdown_efficiency", 85)) "Elite Seam Dominator & Red-Zone Matchup" else
    if (ge("yac_over_expected", 85)) "YAC Enforcer & Middle-Field Threat" else
    if (ge("target_share", 80)) "High-Volume Receiving Flex TE" else
    "Reliable Complete Starting Tight End"
  }
}
archetypes <- vapply(entries, function(e) assign_archetype(e$vec, e$pos), character(1))

# Cosine of 50-centred percentile vectors over dims both players have; NA when fewer than
# DNA_MIN_SHARED_DIMS are shared. Published as max(cos, 0) * 100.
calc_cosine_sim <- function(v1, v2) {
  ok <- !is.na(v1) & !is.na(v2)
  if (sum(ok) < DNA_MIN_SHARED_DIMS) return(NA_real_)
  a <- v1[ok] - 50; b <- v2[ok] - 50
  n1 <- sqrt(sum(a^2)); n2 <- sqrt(sum(b^2))
  if (n1 == 0 || n2 == 0) return(NA_real_)
  round(max(sum(a * b) / (n1 * n2), 0) * 100, 1)
}

shared_trait <- function(v1, v2) {
  ok <- !is.na(v1) & !is.na(v2)
  lo <- pmin(v1, v2); hi <- pmax(v1, v2)
  nm <- names(v1)
  if (max(lo[ok]) >= 50) {
    paste0("Shared strength: ", dim_labels[[nm[ok][which.max(lo[ok])]]])
  } else {
    paste0("Shared weakness: ", dim_labels[[nm[ok][which.min(hi[ok])]]])
  }
}

round_or_na <- function(x) if (is.na(x)) NA_real_ else round(unname(x), 1)
pos_vec <- vapply(entries, function(e) e$pos, character(1))
era_label <- as.character(CURRENT_SEASON)

player_dna_list <- vector("list", length(entries))
for (i in seq_along(entries)) {
  e <- entries[[i]]
  vec <- e$vec
  pos <- e$pos

  # Peers: same position and window, never the player themself; fewer than the minimum
  # shared dimensions (including players with no data) -> NA -> never a peer
  sims <- vapply(seq_along(entries), function(j) {
    if (j == i || pos_vec[j] != pos) NA_real_ else calc_cosine_sim(vec, entries[[j]]$vec)
  }, numeric(1))
  cand <- which(!is.na(sims))
  cand <- cand[order(-sims[cand], ids[cand])]
  top_idx <- head(cand, DNA_PEER_COUNT)
  peers <- lapply(top_idx, function(j) list(
    compName = entries[[j]]$name,
    playerId = entries[[j]]$id,
    era = era_label,
    archetype = if (is.na(archetypes[j])) NULL else archetypes[j],
    position = entries[[j]]$pos,
    similarityPct = sims[j],
    keySharedTrait = shared_trait(vec, entries[[j]]$vec)
  ))

  # 2D manifold coordinates (null when a contributing dimension is null)
  if (pos == "QB") {
    mx <- (vec[["air_yards_share"]] * 0.5 + vec[["deep_accuracy"]] * 0.5) - 50
    my <- (vec[["scramble_epa"]] * 0.6 + vec[["pressure_resilience"]] * 0.4) - 50
  } else {
    mx <- (vec[["explosive_play_rate"]] * 0.5 + vec[["yac_over_expected"]] * 0.5) - 50
    my <- (vec[["target_share"]] * 0.5 + vec[["touchdown_efficiency"]] * 0.5) - 50
  }

  radar_labels <- dim_labels[names(vec)]
  if (pos == "RB") {
    radar_labels[["target_share"]] <- "Workload share"
    radar_labels[["yac_over_expected"]] <- "YAC / RYOE"
  }
  radar_axes <- lapply(seq_along(vec), function(k) list(
    axis = names(vec)[k], label = unname(radar_labels[[names(vec)[k]]]), value = round_or_na(vec[[k]])
  ))

  player_dna_list[[i]] <- list(
    playerId = e$id,
    playerName = e$name,
    team = e$team,
    position = pos,
    archetype = if (is.na(archetypes[i])) NULL else archetypes[i],
    overallRating = overall_of(vec),
    statsSummary = e$stats,
    manifoldX = round_or_na(mx),
    manifoldY = round_or_na(my),
    radarAxes = radar_axes,
    skillVector = as.list(round(vec, 1)),
    categoryScores = as.list(round(vec, 1)),
    peerComps = peers
  )
}

# ------------------------------------------------------------------------------
# 6. Export to JSON for Next.js Web Application & Cache RDS
# ------------------------------------------------------------------------------
output <- list(
  season = as.integer(CURRENT_SEASON),
  throughWeek = through_week,
  generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  profiles = player_dna_list
)

output_json <- WEB_JSON_PLAYER_DNA_PROFILES
output_dir <- dirname(output_json)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

jsonlite::write_json(output, output_json, pretty = TRUE, auto_unbox = TRUE, na = "null", null = "null", digits = NA)
cat(sprintf(">>> [SUCCESS] Wrote %d Player DNA profiles (season %d, through Week %d) to '%s'.\n",
            length(player_dna_list), CURRENT_SEASON, through_week, output_json))

saveRDS(output, CACHE_PLAYER_DNA_PROFILES)
cat(sprintf(">>> [SUCCESS] Cached RDS in '%s'.\n", CACHE_PLAYER_DNA_PROFILES))
