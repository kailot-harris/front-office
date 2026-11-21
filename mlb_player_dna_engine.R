# ==============================================================================
# mlb_player_dna_engine.R
# Player DNA: empirical current-season skill vectors and nearest peer comps
# Path: mlb_player_dna_engine.R
#
# Builds a skill vector for every qualified MLB batter and pitcher of ONE season
# (MLB_CURRENT_SEASON in config.R), then lists each player's 5 nearest peers of
# the same type (batters against batters, pitchers against pitchers) in that same
# season. There are no hand-typed historical comparables and no hand-typed skill
# vectors. Modelled on NBA_analytics#195 and NFL_analytics#172.
#
# Inputs (exact filenames, constants in config.R; never a glob, never another season)
#   CACHE_DNA_FG_BATTERS   cache/stats_sync/fg_batters.rds   FanGraphs batter leaderboard
#   CACHE_DNA_FG_PITCHERS  cache/stats_sync/fg_pitchers.rds  FanGraphs pitcher leaderboard
#   CACHE_DNA_SCHEDULE     cache/ingest/mlb_schedule_<MLB_CURRENT_SEASON>.rds
#   Both leaderboards are written by mlb_stats_sync.R and may hold several seasons;
#   only rows whose `season` equals MLB_CURRENT_SEASON are used. If no such rows
#   exist the engine logs a `>>> [FAIL]` line and writes nothing.
#
# Output: web/public/data/player_dna_profiles.json (WEB_JSON_PLAYER_DNA_PROFILES),
#   an envelope { generated_at, season, throughDate, generatedAt, dimensions,
#   categories, profiles }. dimensions.<Batter|Pitcher> lists every published
#   dimension ({key, label, category}) and categories.<Batter|Pitcher> every
#   category ({key, label}), so the page takes its labels and counts from the data.
#   team is the player's club code, or null when FanGraphs reports "- - -" (he played
#   for 2+ clubs that season); no made-up team code is ever published.
#   generated_at (UTC ISO-8601) stays FIRST because tools/publish_web.R assertion F
#   reads it from the first 4096 bytes; generatedAt is the same instant for the web.
#   throughDate is the last regular-season date with a Final game in the season
#   schedule on or before the date the leaderboards were fetched (baseballr_timestamp
#   attribute of the leaderboard caches). It is null when either input is missing.
#
# Methodology (documented modelling choices on real data, not fabricated data)
#   - Qualified players: batters with at least DNA_MIN_PA plate appearances and
#     pitchers with at least DNA_MIN_IP innings in the season.
#   - Each dimension is the player's percentile within his qualified pool (batters or
#     pitchers) on ONE real FanGraphs column of that season: mid-rank percentile
#     100 * (rank - 0.5) / n, reversed (100 - p) where a lower raw value is better.
#     A dimension with no variance is null. Batters have 16 dimensions and pitchers 15
#     (see BATTER_DIMS / PITCHER_DIMS below for the source column of each).
#   - Missing inputs are never imputed: no league-average constants, no 50 fillers,
#     no zero-fills. A missing column value publishes null for that dimension.
#   - categoryScores: mean of the category's non-null dimensions, null unless at least
#     half of that category's dimensions are non-null.
#   - overallRating ("DNA score"): mean of the non-null dimensions, null unless at least
#     DNA_MIN_DIMS dimensions are non-null.
#   - Manifold coordinates: fixed linear combinations of the category scores (layout
#     only, see the formulas below); null when any category used is null.
#   - Archetype: NA-safe threshold rules on the player's own dimension percentiles
#     (a missing dimension never satisfies a threshold), first match wins:
#       Batters  iso_power>=85 & walk_rate>=80          Power & Patience Slugger
#                exit_velo_90>=85 & barrel_pct>=85      Damage-on-Contact Power Bat
#                strikeout_avoidance>=85 & zone_contact>=80  Bat-to-Ball Contact Hitter
#                speed_score>=85 & baserunning_val>=80  Speed & Baserunning Threat
#                fielding_range>=85                     Glove-First Defender
#                chase_discipline>=85                   Selective Zone Controller
#                otherwise                              Balanced Everyday Profile
#       Pitchers strikeout_rate>=85 & stuff_plus>=85    Power Strikeout Arm
#                walk_suppression>=85 & location_plus>=80  Command & Control Artist
#                barrel_suppression>=85 & hard_hit_suppression>=80  Soft-Contact Suppressor
#                groundball_rate>=85                    Groundball Specialist
#                fastball_velo>=85                      High-Velocity Fastball Pitcher
#                arsenal_diversity>=85                  Deep-Arsenal Pitcher
#                otherwise                              Balanced Pitching Profile
#     The archetype is null when overallRating is null.
#   - Peer comps: for each player, the DNA_PEER_COUNT (5) other players of the same
#     type with the highest similarity. Similarity is the cosine of the 50-centred
#     percentile vectors over the dimensions non-null for BOTH players, and requires at
#     least DNA_MIN_SHARED_DIMS (4) shared dimensions. Published as
#     similarityPct = max(cos, 0) * 100, one decimal. Ties break on playerId.
#     A player with fewer than DNA_MIN_DIMS non-null dimensions has peerComps = [] and
#     is never another player's peer. keySharedTrait names the shared dimension where
#     both players are strongest (or, if neither is above 50 anywhere, weakest).
#   - Output is deterministic apart from generated_at / generatedAt.
#
# Failure handling: any failure logs a `>>> [FAIL] [PLAYER DNA]` line and returns
#   without writing. The engine never calls stop(), so the pipeline exit code is not
#   affected (schedule_daily.bat publishes nothing unless the pipeline exits 0).
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "mlb_player_dna_engine.R"

# ------------------------------------------------------------------------------
# 1. Thresholds
# ------------------------------------------------------------------------------
DNA_MIN_PA          <- 300   # qualified batter: plate appearances in the season
DNA_MIN_IP          <- 50    # qualified pitcher: innings pitched in the season
DNA_MIN_DIMS        <- 8L    # non-null dimensions needed for a rating, archetype and peers
DNA_MIN_SHARED_DIMS <- 4L    # shared non-null dimensions needed to compare two players
DNA_PEER_COUNT      <- 5L

# ------------------------------------------------------------------------------
# 2. Dimension definitions: one real FanGraphs column (or a stated derivation of
#    real columns) per dimension. higher = FALSE reverses the percentile.
# ------------------------------------------------------------------------------
PITCH_MIX_COLS <- c("pfx_FA_pct", "pfx_FC_pct", "pfx_SI_pct", "pfx_SL_pct", "pfx_CU_pct",
                    "pfx_CH_pct", "pfx_ST_pct", "pfx_KC_pct", "pfx_FS_pct", "pfx_KN_pct",
                    "pfx_FO_pct", "pfx_EP_pct")

calc_spray_balance <- function(pull, cent, oppo) {
  p <- c(pull, cent, oppo)
  if (any(is.na(p))) return(NA_real_)
  p <- p[p > 0]
  if (length(p) == 0) return(NA_real_)
  p <- p / sum(p)
  # Normalized Shannon entropy against a uniform 3-way distribution (log(3))
  -sum(p * log(p)) / log(3)
}

calc_pitch_arsenal_entropy <- function(df) {
  cols <- intersect(PITCH_MIX_COLS, names(df))
  m <- as.matrix(df[, cols, drop = FALSE])
  apply(m, 1, function(vals) {
    vals <- as.numeric(vals)
    if (all(is.na(vals))) return(NA_real_)
    vals <- vals[!is.na(vals) & vals > 0]
    if (length(vals) == 0) return(NA_real_)
    p <- vals / sum(vals)
    -sum(p * log(p))
  })
}

col_or_na <- function(df, col) if (col %in% names(df)) as.numeric(df[[col]]) else rep(NA_real_, nrow(df))

# name, label, category, higher-is-better, raw value function
BATTER_DIMS <- list(
  list(key = "exit_velo_90",        label = "90th-pct exit velo",  cat = "power",       higher = TRUE,  raw = function(d) col_or_na(d, "EV90")),
  list(key = "barrel_pct",          label = "Barrel rate",         cat = "power",       higher = TRUE,  raw = function(d) col_or_na(d, "Barrel_pct")),
  list(key = "hard_hit_pct",        label = "Hard-hit rate",       cat = "power",       higher = TRUE,  raw = function(d) col_or_na(d, "HardHit_pct")),
  list(key = "iso_power",           label = "Isolated power",      cat = "power",       higher = TRUE,  raw = function(d) col_or_na(d, "ISO")),
  list(key = "zone_contact",        label = "In-zone contact",     cat = "contact",     higher = TRUE,  raw = function(d) col_or_na(d, "Z-Contact_pct")),
  list(key = "whiff_avoidance",     label = "Swinging-strike avoidance", cat = "contact", higher = FALSE, raw = function(d) col_or_na(d, "SwStr_pct")),
  list(key = "strikeout_avoidance", label = "Strikeout avoidance", cat = "contact",     higher = FALSE, raw = function(d) col_or_na(d, "K_pct")),
  list(key = "chase_discipline",    label = "Chase discipline",    cat = "discipline",  higher = FALSE, raw = function(d) col_or_na(d, "O-Swing_pct")),
  list(key = "walk_rate",           label = "Walk rate",           cat = "discipline",  higher = TRUE,  raw = function(d) col_or_na(d, "BB_pct")),
  list(key = "squared_up_pct",      label = "Squared-up contact",  cat = "batted_ball", higher = TRUE,  raw = function(d) col_or_na(d, "SquaredUpContact_pct")),
  list(key = "pull_air_pct",        label = "Pull x fly-ball rate", cat = "batted_ball", higher = TRUE, raw = function(d) col_or_na(d, "Pull_pct") * col_or_na(d, "FB_pct")),
  list(key = "all_fields_spray",    label = "All-fields spray",    cat = "batted_ball", higher = TRUE,  raw = function(d) mapply(calc_spray_balance, col_or_na(d, "Pull_pct"), col_or_na(d, "Cent_pct"), col_or_na(d, "Oppo_pct"))),
  list(key = "speed_score",         label = "Speed score",         cat = "athleticism", higher = TRUE,  raw = function(d) col_or_na(d, "Spd")),
  list(key = "baserunning_val",     label = "Baserunning runs",    cat = "athleticism", higher = TRUE,  raw = function(d) col_or_na(d, "wBsR")),
  list(key = "fielding_range",      label = "Fielding runs",       cat = "athleticism", higher = TRUE,  raw = function(d) col_or_na(d, "Fielding")),
  list(key = "clutch_resilience",   label = "Clutch",              cat = "athleticism", higher = TRUE,  raw = function(d) col_or_na(d, "Clutch"))
)

PITCHER_DIMS <- list(
  list(key = "fastball_velo",        label = "Four-seam velocity",    cat = "velocity_physics",  higher = TRUE,  raw = function(d) col_or_na(d, "pfx_vFA")),
  list(key = "fastball_ivb",         label = "Four-seam vertical break", cat = "velocity_physics", higher = TRUE, raw = function(d) col_or_na(d, "pfx_FA-Z")),
  list(key = "horizontal_break",     label = "Four-seam horizontal break", cat = "velocity_physics", higher = TRUE, raw = function(d) abs(col_or_na(d, "pfx_FA-X"))),
  list(key = "stuff_plus",           label = "Stuff+",                cat = "arsenal_stuff",     higher = TRUE,  raw = function(d) col_or_na(d, "sp_stuff")),
  list(key = "arsenal_diversity",    label = "Arsenal diversity",     cat = "arsenal_stuff",     higher = TRUE,  raw = function(d) calc_pitch_arsenal_entropy(d)),
  list(key = "swinging_strike_rate", label = "Swinging-strike rate",  cat = "arsenal_stuff",     higher = TRUE,  raw = function(d) col_or_na(d, "SwStr_pct")),
  list(key = "location_plus",        label = "Location+",             cat = "command_k",         higher = TRUE,  raw = function(d) col_or_na(d, "sp_location")),
  list(key = "zone_rate",            label = "Zone rate",             cat = "command_k",         higher = TRUE,  raw = function(d) col_or_na(d, "Zone_pct")),
  list(key = "strikeout_rate",       label = "Strikeout rate",        cat = "command_k",         higher = TRUE,  raw = function(d) col_or_na(d, "K_pct")),
  list(key = "walk_suppression",     label = "Walk suppression",      cat = "command_k",         higher = FALSE, raw = function(d) col_or_na(d, "BB_pct")),
  list(key = "hard_hit_suppression", label = "Hard-hit suppression",  cat = "batted_ball",       higher = FALSE, raw = function(d) col_or_na(d, "HardHit_pct")),
  list(key = "barrel_suppression",   label = "Barrel suppression",    cat = "batted_ball",       higher = FALSE, raw = function(d) col_or_na(d, "Barrel_pct")),
  list(key = "groundball_rate",      label = "Ground-ball rate",      cat = "batted_ball",       higher = TRUE,  raw = function(d) col_or_na(d, "GB_pct")),
  list(key = "workload_stamina",     label = "Innings per appearance", cat = "workload_leverage", higher = TRUE, raw = function(d) col_or_na(d, "IP") / col_or_na(d, "G")),
  list(key = "clutch_resilience",    label = "Clutch",                cat = "workload_leverage", higher = TRUE,  raw = function(d) col_or_na(d, "Clutch"))
)

# Category key -> display label. The label names what the category's dimensions
# (the `cat` entries above) actually measure; the page reads it from the JSON.
BATTER_CATEGORIES <- c(power       = "Power",
                       contact     = "Contact",
                       discipline  = "Plate discipline",
                       batted_ball = "Batted-ball profile",
                       athleticism = "Running, glove & clutch")
PITCHER_CATEGORIES <- c(velocity_physics  = "Fastball velo & movement",
                        arsenal_stuff     = "Stuff, mix & whiffs",
                        command_k         = "Command, K & BB",
                        batted_ball       = "Contact suppression",
                        workload_leverage = "Workload & clutch")

# FanGraphs team codes -> site codes. FanGraphs reports "- - -" for a player who
# played for more than one club in the season; there is no single team to publish,
# so `team` is null (the page shows "2+ teams" and no logo). Never invent a code.
FG_MULTI_TEAM <- "- - -"
FG_TEAM_TO_SITE <- c(KCR = "KC", SDP = "SD", SFG = "SF", TBR = "TB", WSN = "WSH",
                     CWS = "CHW", OAK = "ATH")
site_team <- function(x) {
  x <- as.character(x)
  out <- ifelse(x %in% names(FG_TEAM_TO_SITE), FG_TEAM_TO_SITE[x], x)
  out[is.na(x) | x == "" | x == FG_MULTI_TEAM] <- NA_character_
  unname(out)
}

# Published dimension and category metadata for one player type (page labels and counts)
dimension_meta <- function(dims) {
  lapply(dims, function(d) list(key = d$key, label = d$label, category = d$cat))
}
category_meta <- function(categories) {
  lapply(names(categories), function(k) list(key = k, label = unname(categories[[k]])))
}

# ------------------------------------------------------------------------------
# 3. Helpers
# ------------------------------------------------------------------------------
.dna_fail <- function(msg) {
  message(sprintf(">>> [FAIL] [PLAYER DNA] %s", msg))
  log_error(sprintf("Player DNA engine failed: %s", msg), script = .LOG_SCRIPT)
  invisible(NULL)
}

# Mid-rank percentile within the pool; NA stays NA; no variance -> all NA
pool_percentile <- function(x, higher = TRUE) {
  out <- rep(NA_real_, length(x))
  ok <- !is.na(x) & is.finite(x)
  if (sum(ok) < 2 || length(unique(x[ok])) < 2) return(out)
  r <- rank(x[ok], ties.method = "average")
  p <- 100 * (r - 0.5) / sum(ok)
  if (!higher) p <- 100 - p
  out[ok] <- round(p)
  out
}

build_skill_matrix <- function(df, dims) {
  m <- sapply(dims, function(d) pool_percentile(d$raw(df), d$higher))
  if (is.null(dim(m))) m <- matrix(m, nrow = nrow(df))
  colnames(m) <- vapply(dims, function(d) d$key, character(1))
  m
}

n_present <- function(vec) sum(!is.na(vec))

mean_or_na <- function(vals, min_n) {
  if (sum(!is.na(vals)) < min_n) NA_real_ else round(mean(vals, na.rm = TRUE))
}

category_scores <- function(vec, dims, categories) {
  cats <- vapply(dims, function(d) d$cat, character(1))
  out <- lapply(categories, function(cn) {
    v <- vec[cats == cn]
    mean_or_na(v, ceiling(length(v) / 2))
  })
  names(out) <- categories
  out
}

# Cosine of 50-centred percentile vectors over dims both players have; NA when
# fewer than DNA_MIN_SHARED_DIMS are shared. Published as max(cos, 0) * 100.
calc_cosine_sim <- function(v1, v2) {
  ok <- !is.na(v1) & !is.na(v2)
  if (sum(ok) < DNA_MIN_SHARED_DIMS) return(NA_real_)
  a <- v1[ok] - 50
  b <- v2[ok] - 50
  n1 <- sqrt(sum(a^2))
  n2 <- sqrt(sum(b^2))
  if (n1 == 0 || n2 == 0) return(NA_real_)
  round(max(sum(a * b) / (n1 * n2), 0) * 100, 1)
}

shared_trait <- function(v1, v2, labels) {
  ok <- !is.na(v1) & !is.na(v2)
  lo <- pmin(v1, v2)
  hi <- pmax(v1, v2)
  nm <- names(v1)
  if (max(lo[ok]) >= 50) {
    paste0("Shared strength: ", labels[[nm[ok][which.max(lo[ok])]]])
  } else {
    paste0("Shared weakness: ", labels[[nm[ok][which.min(hi[ok])]]])
  }
}

assign_archetype <- function(vec, type) {
  if (n_present(vec) < DNA_MIN_DIMS) return(NA_character_)
  ge <- function(nm, t) !is.na(vec[[nm]]) && vec[[nm]] >= t
  if (type == "Batter") {
    if (ge("iso_power", 85) && ge("walk_rate", 80)) "Power & Patience Slugger" else
    if (ge("exit_velo_90", 85) && ge("barrel_pct", 85)) "Damage-on-Contact Power Bat" else
    if (ge("strikeout_avoidance", 85) && ge("zone_contact", 80)) "Bat-to-Ball Contact Hitter" else
    if (ge("speed_score", 85) && ge("baserunning_val", 80)) "Speed & Baserunning Threat" else
    if (ge("fielding_range", 85)) "Glove-First Defender" else
    if (ge("chase_discipline", 85)) "Selective Zone Controller" else
    "Balanced Everyday Profile"
  } else {
    if (ge("strikeout_rate", 85) && ge("stuff_plus", 85)) "Power Strikeout Arm" else
    if (ge("walk_suppression", 85) && ge("location_plus", 80)) "Command & Control Artist" else
    if (ge("barrel_suppression", 85) && ge("hard_hit_suppression", 80)) "Soft-Contact Suppressor" else
    if (ge("groundball_rate", 85)) "Groundball Specialist" else
    if (ge("fastball_velo", 85)) "High-Velocity Fastball Pitcher" else
    if (ge("arsenal_diversity", 85)) "Deep-Arsenal Pitcher" else
    "Balanced Pitching Profile"
  }
}

fmt_or_na <- function(x, fmt) if (is.na(x)) NA_character_ else sprintf(fmt, x)
int_or_na <- function(x) if (is.na(x)) NA_integer_ else as.integer(round(x))
round_or_na <- function(x) if (is.na(x)) NA_real_ else round(unname(x), 1)

# Last regular-season date with a Final game, on or before the leaderboard fetch date
compute_through_date <- function(sched_file, fetched_on) {
  if (is.na(fetched_on) || !file.exists(sched_file)) return(NA_character_)
  s <- readRDS(sched_file)
  need <- c("game_type", "status_abstract_game_state", "official_date", "season")
  if (!all(need %in% names(s))) return(NA_character_)
  d <- as.Date(s$official_date)
  keep <- s$game_type == "R" & s$status_abstract_game_state == "Final" &
    as.integer(s$season) == MLB_CURRENT_SEASON & !is.na(d) & d <= fetched_on
  if (!any(keep, na.rm = TRUE)) return(NA_character_)
  format(max(d[which(keep)]), "%Y-%m-%d")
}

fetched_date <- function(df) {
  ts <- attr(df, "baseballr_timestamp")
  if (is.null(ts) || !inherits(ts, "POSIXct") || is.na(ts)) return(as.Date(NA))
  as.Date(format(ts, "%Y-%m-%d"))
}

load_season_rows <- function(path, what) {
  if (!file.exists(path)) {
    return(list(error = sprintf("Required %s cache %s not found. Run mlb_stats_sync.R first.", what, basename(path))))
  }
  df <- readRDS(path)
  if (!"season" %in% names(df)) {
    return(list(error = sprintf("%s cache %s has no season column.", what, basename(path))))
  }
  fetched_on <- fetched_date(df)
  df <- as.data.frame(df, stringsAsFactors = FALSE, check.names = FALSE)
  df <- df[!is.na(df$season) & as.integer(df$season) == MLB_CURRENT_SEASON, , drop = FALSE]
  if (nrow(df) == 0) {
    return(list(error = sprintf("%s cache %s holds no %d rows.", what, basename(path), MLB_CURRENT_SEASON)))
  }
  list(df = df, fetched_on = fetched_on)
}

# ------------------------------------------------------------------------------
# 4. Profiles for one player type
# ------------------------------------------------------------------------------
build_type_profiles <- function(df, type) {
  dims <- if (type == "Batter") BATTER_DIMS else PITCHER_DIMS
  categories <- names(if (type == "Batter") BATTER_CATEGORIES else PITCHER_CATEGORIES)
  labels <- setNames(lapply(dims, function(d) d$label), vapply(dims, function(d) d$key, character(1)))
  prefix <- if (type == "Batter") "B_" else "P_"

  df <- df[order(as.character(df$playerid)), , drop = FALSE]
  ids <- paste0(prefix, as.character(df$playerid))
  if (anyDuplicated(ids)) return(list(error = sprintf("duplicate %s playerid rows", type)))

  skill_m <- build_skill_matrix(df, dims)
  n <- nrow(df)
  vecs <- lapply(seq_len(n), function(i) skill_m[i, ])
  present <- vapply(vecs, n_present, integer(1))
  eligible <- present >= DNA_MIN_DIMS
  archetypes <- vapply(vecs, assign_archetype, character(1), type = type)
  names_v <- as.character(df$PlayerName)
  teams_v <- site_team(df$team_name)
  odd_team <- is.na(df$team_name) | df$team_name == ""
  if (any(odd_team)) {
    return(list(error = sprintf("%d qualified %s rows have no team_name (FanGraphs uses \"%s\" for 2+ teams).",
                                sum(odd_team), type, FG_MULTI_TEAM)))
  }

  if (type == "Batter") {
    positions <- ifelse(is.na(df$position) | df$position == "", NA_character_, as.character(df$position))
  } else {
    gs <- col_or_na(df, "GS"); g <- col_or_na(df, "G")
    positions <- ifelse(is.na(gs) | is.na(g) | g == 0, NA_character_, ifelse(gs / g >= 0.5, "SP", "RP"))
  }

  profiles <- vector("list", n)
  for (i in seq_len(n)) {
    vec <- vecs[[i]]
    r <- df[i, , drop = FALSE]

    peers <- list()
    if (eligible[i]) {
      sims <- vapply(seq_len(n), function(j) {
        if (j == i || !eligible[j]) NA_real_ else calc_cosine_sim(vec, vecs[[j]])
      }, numeric(1))
      cand <- which(!is.na(sims))
      cand <- cand[order(-sims[cand], ids[cand])]
      top_idx <- head(cand, DNA_PEER_COUNT)
      peers <- lapply(top_idx, function(j) list(
        playerId       = ids[j],
        compName       = names_v[j],
        team           = teams_v[j],
        position       = positions[j],
        archetype      = archetypes[j],
        similarityPct  = sims[j],
        keySharedTrait = shared_trait(vec, vecs[[j]], labels)
      ))
    }

    cat_scores <- category_scores(vec, dims, categories)
    if (type == "Batter") {
      mx <- (cat_scores$power - cat_scores$contact) * 0.65 + (cat_scores$athleticism - 50) * 0.35
      my <- (cat_scores$discipline - 50) * 0.75 + (cat_scores$batted_ball - 50) * 0.25
      headline <- list(
        stat1Label = "wOBA", stat1Val = fmt_or_na(col_or_na(r, "wOBA"), "%.3f"),
        stat2Label = "ISO",  stat2Val = fmt_or_na(col_or_na(r, "ISO"), "%.3f"),
        stat3Label = "OBP",  stat3Val = fmt_or_na(col_or_na(r, "OBP"), "%.3f"),
        countLabel = "HR",   countVal = int_or_na(col_or_na(r, "HR"))
      )
    } else {
      mx <- (cat_scores$arsenal_stuff - cat_scores$command_k) * 0.65 + (cat_scores$velocity_physics - 50) * 0.35
      my <- (cat_scores$workload_leverage - 50) * 0.70 + (cat_scores$batted_ball - 50) * 0.30
      headline <- list(
        stat1Label = "ERA",   stat1Val = fmt_or_na(col_or_na(r, "ERA"), "%.2f"),
        stat2Label = "xFIP",  stat2Val = fmt_or_na(col_or_na(r, "xFIP"), "%.2f"),
        stat3Label = "K-BB%", stat3Val = fmt_or_na(100 * col_or_na(r, "K-BB_pct"), "%.1f%%"),
        countLabel = "SO",    countVal = int_or_na(col_or_na(r, "SO"))
      )
    }

    profiles[[i]] <- list(
      playerId       = ids[i],
      mlbamId        = if (is.na(r$xMLBAMID)) NA_character_ else as.character(r$xMLBAMID),
      playerName     = names_v[i],
      team           = teams_v[i],
      playerType     = type,
      position       = positions[i],
      age            = int_or_na(col_or_na(r, "Age")),
      archetype      = archetypes[i],
      headlineStats  = headline,
      overallRating  = mean_or_na(vec, DNA_MIN_DIMS),
      manifoldX      = round_or_na(mx),
      manifoldY      = round_or_na(my),
      skillVector    = as.list(vec),
      categoryScores = cat_scores,
      peerComps      = peers
    )
  }

  # Best overall first (null ratings last), ties on playerId
  ratings <- vapply(profiles, function(p) p$overallRating, numeric(1))
  ord <- order(is.na(ratings), -ifelse(is.na(ratings), 0, ratings), ids)
  list(profiles = profiles[ord])
}

# ------------------------------------------------------------------------------
# 5. Engine
# ------------------------------------------------------------------------------
.run_mlb_player_dna_engine <- function() {
  message(sprintf(">>> [PLAYER DNA] Building %d skill vectors and same-season peer comps...", MLB_CURRENT_SEASON))

  b_in <- load_season_rows(CACHE_DNA_FG_BATTERS, "FanGraphs batter")
  if (!is.null(b_in$error)) return(.dna_fail(b_in$error))
  p_in <- load_season_rows(CACHE_DNA_FG_PITCHERS, "FanGraphs pitcher")
  if (!is.null(p_in$error)) return(.dna_fail(p_in$error))

  b_df <- b_in$df[!is.na(b_in$df$PA) & b_in$df$PA >= DNA_MIN_PA, , drop = FALSE]
  p_df <- p_in$df[!is.na(p_in$df$IP) & p_in$df$IP >= DNA_MIN_IP, , drop = FALSE]
  if (nrow(b_df) < 2 || nrow(p_df) < 2) {
    return(.dna_fail(sprintf("too few qualified players (%d batters, %d pitchers).", nrow(b_df), nrow(p_df))))
  }

  batters <- build_type_profiles(b_df, "Batter")
  if (!is.null(batters$error)) return(.dna_fail(batters$error))
  pitchers <- build_type_profiles(p_df, "Pitcher")
  if (!is.null(pitchers$error)) return(.dna_fail(pitchers$error))
  profile_list <- c(batters$profiles, pitchers$profiles)

  fetched_on <- suppressWarnings(min(b_in$fetched_on, p_in$fetched_on))
  through_date <- compute_through_date(CACHE_DNA_SCHEDULE, fetched_on)
  if (is.na(through_date)) {
    log_warn("throughDate could not be determined (schedule cache or fetch timestamp missing); publishing null.",
             script = .LOG_SCRIPT)
  }

  stamp <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  output_catalog <- list(
    generated_at = stamp,
    season       = as.integer(MLB_CURRENT_SEASON),
    throughDate  = through_date,
    generatedAt  = stamp,
    dimensions   = list(Batter = dimension_meta(BATTER_DIMS), Pitcher = dimension_meta(PITCHER_DIMS)),
    categories   = list(Batter = category_meta(BATTER_CATEGORIES), Pitcher = category_meta(PITCHER_CATEGORIES)),
    profiles     = profile_list
  )

  output_json <- WEB_JSON_PLAYER_DNA_PROFILES
  if (!dir.exists(dirname(output_json))) dir.create(dirname(output_json), recursive = TRUE)
  json_txt <- toJSON(output_catalog, auto_unbox = TRUE, pretty = TRUE, na = "null", null = "null", digits = NA)
  writeLines(json_txt, output_json, useBytes = TRUE)
  message(sprintf(">>> [PLAYER DNA] Wrote %d profiles (%d batters, %d pitchers; season %d through %s) to %s",
                  length(profile_list), length(batters$profiles), length(pitchers$profiles),
                  MLB_CURRENT_SEASON, if (is.na(through_date)) "unknown date" else through_date, output_json))
  invisible(output_catalog)
}

run_mlb_player_dna_engine <- function() {
  tryCatch(.run_mlb_player_dna_engine(), error = function(e) .dna_fail(conditionMessage(e)))
}

if (sys.nframe() == 0) {
  run_mlb_player_dna_engine()
}
