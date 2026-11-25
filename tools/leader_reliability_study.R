# ==============================================================================
# tools/leader_reliability_study.R
#
# Issue #229: how large a sample does a player need before each NFL leader stat
# reflects his real level rather than noise? RESEARCH ONLY. This script is not
# wired into the pipeline, changes no production setting and chooses no
# qualifying minimum. It measures reliability curves; the owner reads them and
# sets the minimums (the NFL leaders panel consumes them). It repeats the NBA
# study (NBA_analytics#253) with the same methods and code structure.
#
# WHAT IT DOES
#   Four stat groups, each with its own sample unit (a 17-game season is too
#   short for game-based curves, so per-play stats are measured in plays):
#     - Passing   (unit: dropbacks; per-game stats: games played)
#     - Rushing   (unit: carries;   per-game stats: games played)
#     - Receiving (unit: targets;   per-game stats: games played)
#     - Defense   (unit: defensive snaps; per-game stats: games played)
#   Regular season only, past complete seasons only.
#     - Split-half reliability: each player-season's games are numbered in week
#       order; odd-numbered games form half A, even-numbered games half B. At
#       sample size n the stat is computed on each half from the first n units
#       of that half and correlated across player-seasons (Pearson).
#       Spearman-Brown: r_sb = 2r / (1 + r), the reliability of a 2n sample.
#     - Rest-of-season check: the stat over a player's first n units of the
#       season against the same stat over ALL his remaining units that season,
#       for player-seasons whose remainder holds at least n units.
#     - Intervals: player-season block bootstrap, percentile 95% intervals.
#
# Units and samples: passing, rushing and receiving rates from play-by-play are
# play-level, so "first n units" is exactly the first n plays (in week and play
# order). Stats that only exist per game (box-score counts, Pro Football
# Reference yards after contact and pressures, defensive snaps) are game-level;
# there "first n units" is the shortest run of whole games whose cumulative
# units reach n, and the mean realised size is reported at every point.
#
# No imputation: a value that is missing stays missing; any sample that contains
# it is dropped at that point and counted (n_missing).
#
# Run from the project root (fresh session):
#   Rscript tools/leader_reliability_study.R
# Smoke test with fewer resamples:
#   LRS_N_BOOT=50 Rscript tools/leader_reliability_study.R
# Re-run each offseason by changing SEASONS below.
# ==============================================================================

# ---- Settings (change these to re-run the study) ------------------------------
# Season = the year the regular season starts. 2016 is the earliest season of the
# participation and snap-count era the pipeline uses (PARTICIPATION_MIN_SEASON);
# Pro Football Reference weekly advanced stats start in 2018 and are used from
# there. 2026 is in progress and is not used.
SEASONS         <- 2016:2025
SEED            <- 229L
N_BOOT          <- as.integer(Sys.getenv("LRS_N_BOOT", "1000"))
GRID_GAMES      <- 1:8                              # a half holds at most 8-9 games
GRID_DROPBACKS  <- c(10, seq(25, 300, 25))
GRID_CARRIES    <- c(10, seq(20, 160, 10))
GRID_TARGETS    <- seq(5, 80, 5)
GRID_DEF_SNAPS  <- c(25, seq(50, 550, 50))
REF_BARS        <- c(0.5, 0.6, 0.7, 0.8)
MIN_PLAYERS     <- 30L             # a curve point is reported only with >= this many player-seasons
# --------------------------------------------------------------------------------

t_start <- Sys.time()

PROJECT_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  if (length(f) == 1L) {
    normalizePath(file.path(dirname(normalizePath(f)), ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(getwd(), winslash = "/", mustWork = FALSE)
  }
})
setwd(PROJECT_ROOT)
if (!file.exists("config.R") || !file.exists("epa_metrics_engine.R")) stop("Run from the NFL Analytics project root.")

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  library(jsonlite)
})

CACHE   <- "cache"
OUT_DIR <- file.path("docs", "research")
FIG_DIR <- file.path(OUT_DIR, "leader_reliability_study")
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

say <- function(...) message(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), sprintf(...))
say("NFL leader reliability study: seasons %s, %d bootstrap resamples, seed %d",
    paste(range(SEASONS), collapse = "-"), N_BOOT, SEED)

# ==============================================================================
# 1. Data (downloaded once into cache/lrs_*.rds; never modified)
# ==============================================================================
cached <- function(name, fetch) {
  path <- file.path(CACHE, name)
  if (!file.exists(path)) { say("Downloading %s", name); saveRDS(fetch(), path) }
  readRDS(path)
}
PBP_COLS <- c("season", "season_type", "week", "game_id", "play_id", "play_type", "two_point_attempt",
              "qb_dropback", "qb_scramble", "qb_kneel", "qb_spike", "pass_attempt", "sack", "interception",
              "complete_pass", "pass_touchdown", "rush_attempt", "passer_id", "rusher_player_id",
              "receiver_player_id", "passing_yards", "receiving_yards", "rushing_yards", "epa", "qb_epa",
              "success", "cpoe")
load_pbp_season <- function(s) cached(sprintf("lrs_pbp_%d.rds", s), function() {
  p <- as.data.frame(nflreadr::load_pbp(seasons = s))
  p[, intersect(PBP_COLS, names(p)), drop = FALSE]
})
# Pro Football Reference weekly advanced stats: seasons the source does not
# serve are recorded with the source's own error and left out.
pfr_fail <- list()
load_pfr <- function(type) {
  out <- list()
  for (s in SEASONS) {
    x <- tryCatch(cached(sprintf("lrs_pfr_%s_%d.rds", type, s), function()
      as.data.frame(nflreadr::load_pfr_advstats(seasons = s, stat_type = type, summary_level = "week"))),
      error = function(e) { pfr_fail[[sprintf("%s_%d", type, s)]] <<- conditionMessage(e); NULL })
    if (!is.null(x) && nrow(x)) out[[as.character(s)]] <- x
  }
  if (length(out)) do.call(rbind, lapply(out, function(d) d[, Reduce(intersect, lapply(out, names))])) else NULL
}

pbp <- do.call(rbind, lapply(SEASONS, function(s) {
  p <- load_pbp_season(s)
  for (c in setdiff(PBP_COLS, names(p))) p[[c]] <- NA
  p[p$season_type == "REG", PBP_COLS]
}))
say("Play-by-play: %d regular-season plays", nrow(pbp))
pstats  <- as.data.frame(cached("lrs_player_stats.rds", function()
  nflreadr::load_player_stats(seasons = SEASONS, summary_level = "week")))
pstats  <- pstats[pstats$season_type == "REG" & pstats$season %in% SEASONS, ]
snaps   <- as.data.frame(cached("lrs_snap_counts.rds", function() nflreadr::load_snap_counts(seasons = SEASONS)))
snaps   <- snaps[snaps$game_type == "REG" & snaps$season %in% SEASONS, ]
players <- as.data.frame(cached("lrs_players.rds", function() nflreadr::load_players()))
pfr_rush <- load_pfr("rush"); pfr_rush <- pfr_rush[pfr_rush$game_type == "REG", ]
pfr_def  <- load_pfr("def");  pfr_def  <- pfr_def[pfr_def$game_type == "REG", ]

# pfr_player_id -> gsis_id crosswalk (nflverse players table).
xw <- players[!is.na(players$pfr_id) & !is.na(players$gsis_id), c("pfr_id", "gsis_id")]
xw <- xw[!duplicated(xw$pfr_id), ]
snaps$gsis_id <- xw$gsis_id[match(snaps$pfr_player_id, xw$pfr_id)]
# Post-join match-rate check (repo convention): fail loudly rather than run on a broken link.
LINK_RATE <- mean(!is.na(snaps$gsis_id[(snaps$offense_snaps > 0) | (snaps$defense_snaps > 0)]))
say("Snap-count rows linked to a gsis id: %.1f%%", 100 * LINK_RATE)
if (!is.finite(LINK_RATE) || LINK_RATE < 0.9) stop(sprintf("pfr -> gsis link rate %.3f is below 0.9", LINK_RATE))

# ==============================================================================
# 2. Sample tables. Each row is one play or one player-game, with
#    ps (player-season), k (order within the player-season) and half (A/B).
# ==============================================================================
finish_table <- function(d, ps_key, game_key, order_cols) {
  d$ps_id <- ps_key
  d$game_key <- game_key
  d <- d[do.call(order, c(list(d$ps_id), lapply(order_cols, function(cn) d[[cn]]))), ]
  d$k <- ave(seq_len(nrow(d)), d$ps_id, FUN = seq_along)
  # game ordinal within the player-season (week order): odd = half A, even = half B
  g1 <- !duplicated(paste(d$ps_id, d$game_key))
  d$game_ord <- ave(as.integer(g1), d$ps_id, FUN = cumsum)
  d$half <- ifelse(d$game_ord %% 2L == 1L, "A", "B")
  lv <- sort(unique(d$ps_id))
  d$ps <- match(d$ps_id, lv)
  rownames(d) <- NULL
  d
}
nz <- function(x) !is.na(x) & x == 1

# ---- passing: dropbacks (pass attempts, sacks, scrambles), two-point tries excluded
db <- pbp[nz(pbp$qb_dropback) & pbp$play_type %in% c("pass", "run") & !nz(pbp$two_point_attempt) &
            !is.na(pbp$passer_id), ]
db$player_id <- db$passer_id
db$att <- as.numeric(nz(db$pass_attempt) & !nz(db$sack))
db$pass_yds <- ifelse(nz(db$complete_pass), db$passing_yards, 0)
T_pass <- finish_table(db, paste(db$season, db$player_id, sep = "_"), db$game_id, c("week", "play_id"))

# ---- rushing: designed carries (QB scrambles are dropbacks; kneels and two-point tries excluded)
ru <- pbp[pbp$play_type == "run" & nz(pbp$rush_attempt) & !nz(pbp$qb_scramble) & !nz(pbp$qb_kneel) &
            !nz(pbp$two_point_attempt) & !is.na(pbp$rusher_player_id), ]
ru$player_id <- ru$rusher_player_id
T_rush <- finish_table(ru, paste(ru$season, ru$player_id, sep = "_"), ru$game_id, c("week", "play_id"))

# ---- receiving: targets (pass attempts with a listed receiver; sacks and two-point tries excluded)
re <- pbp[pbp$play_type == "pass" & nz(pbp$pass_attempt) & !nz(pbp$sack) & !nz(pbp$two_point_attempt) &
            !is.na(pbp$receiver_player_id), ]
re$player_id <- re$receiver_player_id
re$rec_yds <- ifelse(nz(re$complete_pass), re$receiving_yards, 0)
T_rec <- finish_table(re, paste(re$season, re$player_id, sep = "_"), re$game_id, c("week", "play_id"))

# ---- per-game tables: games played = offensive (or defensive) snaps > 0 in the
#      snap counts; box-score counts from load_player_stats(). The stats table is
#      built from play-by-play and lists a player in a game only when he recorded
#      an event, so a played game with no stats row is a game with none of these
#      events (counted as such and reported). A played game whose player cannot
#      be linked to a gsis id has missing box-score counts (missing, counted).
PS_KEEP <- c("player_id", "game_id", "passing_yards", "passing_tds", "carries", "rushing_yards",
             "receptions", "receiving_yards", "targets", "def_sacks", "def_interceptions",
             "def_tackles_for_loss")
ps_small <- pstats[, PS_KEEP]
ps_small <- ps_small[!duplicated(ps_small[, c("player_id", "game_id")]), ]
ps_small$has_row <- 1
game_table <- function(snap_col, pool) {
  s <- snaps[!is.na(snaps[[snap_col]]) & snaps[[snap_col]] > 0, ]
  s <- s[!duplicated(s[, c("pfr_player_id", "game_id")]), ]
  s$pool_key <- paste(s$season, s$gsis_id, sep = "_")
  if (!is.null(pool)) s <- s[!is.na(s$gsis_id) & s$pool_key %in% pool, ]
  j <- merge(s, ps_small, by.x = c("gsis_id", "game_id"), by.y = c("player_id", "game_id"), all.x = TRUE)
  stat_cols <- setdiff(PS_KEEP, c("player_id", "game_id"))
  linked <- !is.na(j$gsis_id)
  no_row <- linked & is.na(j$has_row)
  for (cn in stat_cols) {
    v <- as.numeric(j[[cn]])
    v[no_row] <- 0                      # played, no event recorded in the stats table
    v[!linked] <- NA                    # cannot be linked: missing
    j[[cn]] <- v
  }
  j$no_stats_row <- no_row
  j$unlinked <- !linked
  finish_table(j, paste(j$season, j$pfr_player_id, sep = "_"), j$game_id, c("week", "game_id"))
}
pool_pass <- unique(T_pass$ps_id); pool_rush <- unique(T_rush$ps_id); pool_rec <- unique(T_rec$ps_id)
G_pass <- game_table("offense_snaps", pool_pass)
G_rush <- game_table("offense_snaps", pool_rush)
G_rec  <- game_table("offense_snaps", pool_rec)
G_def  <- game_table("defense_snaps", NULL)
# Pressures (PFR weekly, 2018+): a played defensive game with no PFR row is missing.
if (!is.null(pfr_def)) {
  pd <- pfr_def[!duplicated(pfr_def[, c("pfr_player_id", "game_id")]), c("pfr_player_id", "game_id", "def_pressures")]
  G_def$def_pressures <- as.numeric(pd$def_pressures[match(paste(G_def$pfr_player_id, G_def$game_id),
                                                          paste(pd$pfr_player_id, pd$game_id))])
  G_def$def_pressures[!(G_def$season %in% unique(pfr_def$season))] <- NA
} else G_def$def_pressures <- NA_real_
G_def$def_snaps <- as.numeric(G_def$defense_snaps)

# ---- yards after contact (PFR weekly rushing, 2018+), game level, unit carries
T_yac <- NULL
if (!is.null(pfr_rush)) {
  y <- pfr_rush[!is.na(pfr_rush$carries) & pfr_rush$carries > 0, ]
  y <- y[!duplicated(y[, c("pfr_player_id", "game_id")]), ]
  y$carries <- as.numeric(y$carries)
  y$yac <- as.numeric(y$rushing_yards_after_contact)
  T_yac <- finish_table(y, paste(y$season, y$pfr_player_id, sep = "_"), y$game_id, c("week", "game_id"))
}

TABLES <- list(pass = T_pass, rush = T_rush, rec = T_rec, yac = T_yac,
               g_pass = G_pass, g_rush = G_rush, g_rec = G_rec, g_def = G_def)
TABLES <- TABLES[!vapply(TABLES, is.null, TRUE)]
for (tn in names(TABLES)) say("Table %s: %d rows, %d player-seasons", tn, nrow(TABLES[[tn]]),
                              length(unique(TABLES[[tn]]$ps)))

# ==============================================================================
# 3. Stat definitions. value over a sample = sum(num) / sum(den); unit is what n counts.
# ==============================================================================
one <- function(d) rep(1, nrow(d))
STATS <- list(
  # ---- passing
  pass_ypg   = list(group = "passing", table = "g_pass", unit = "games", label = "Passing yards per game",
                    formula = "sum(passing yards) / games played", num = function(d) d$passing_yards, den = one),
  pass_tdpg  = list(group = "passing", table = "g_pass", unit = "games", label = "Passing TDs per game",
                    formula = "sum(passing TDs) / games played", num = function(d) d$passing_tds, den = one),
  pass_ypdb  = list(group = "passing", table = "pass", unit = "dropbacks", label = "Passing yards per dropback",
                    formula = "sum(passing yards on completions) / dropbacks", num = function(d) d$pass_yds, den = one),
  pass_tdpdb = list(group = "passing", table = "pass", unit = "dropbacks", label = "Passing TDs per dropback",
                    formula = "sum(pass_touchdown) / dropbacks", num = function(d) d$pass_touchdown, den = one),
  pass_epa   = list(group = "passing", table = "pass", unit = "dropbacks", label = "EPA per dropback",
                    formula = "sum(qb_epa) / dropbacks", num = function(d) d$qb_epa, den = one),
  pass_cpoe  = list(group = "passing", table = "pass", unit = "dropbacks", label = "Completion % over expected",
                    formula = "mean(cpoe) over dropbacks that are pass attempts with a cpoe value",
                    num = function(d) ifelse(is.na(d$cpoe), 0, d$cpoe), den = function(d) as.numeric(!is.na(d$cpoe))),
  pass_succ  = list(group = "passing", table = "pass", unit = "dropbacks", label = "Dropback success rate",
                    formula = "sum(success) / dropbacks (success = EPA > 0)", num = function(d) d$success, den = one),
  sack_rate  = list(group = "passing", table = "pass", unit = "dropbacks", label = "Sack rate",
                    formula = "sacks / dropbacks", num = function(d) d$sack, den = one),
  int_rate   = list(group = "passing", table = "pass", unit = "dropbacks", label = "Interception rate",
                    formula = "interceptions / pass attempts (sacks and scrambles excluded)",
                    num = function(d) d$interception, den = function(d) d$att),
  # ---- rushing
  rush_ypg   = list(group = "rushing", table = "g_rush", unit = "games", label = "Rushing yards per game",
                    formula = "sum(rushing yards) / games played", num = function(d) d$rushing_yards, den = one),
  rush_ypc   = list(group = "rushing", table = "rush", unit = "carries", label = "Rushing yards per carry",
                    formula = "sum(rushing_yards) / designed carries", num = function(d) d$rushing_yards, den = one),
  rush_epa   = list(group = "rushing", table = "rush", unit = "carries", label = "EPA per carry",
                    formula = "sum(epa) / designed carries", num = function(d) d$epa, den = one),
  rush_succ  = list(group = "rushing", table = "rush", unit = "carries", label = "Rushing success rate",
                    formula = "sum(success) / designed carries", num = function(d) d$success, den = one),
  rush_yac   = list(group = "rushing", table = "yac", unit = "pfr_carries", label = "Yards after contact per carry",
                    formula = "sum(PFR rushing_yards_after_contact) / sum(PFR carries)",
                    num = function(d) d$yac, den = function(d) d$carries),
  # ---- receiving
  rec_ypg    = list(group = "receiving", table = "g_rec", unit = "games", label = "Receiving yards per game",
                    formula = "sum(receiving yards) / games played", num = function(d) d$receiving_yards, den = one),
  rec_pg     = list(group = "receiving", table = "g_rec", unit = "games", label = "Receptions per game",
                    formula = "sum(receptions) / games played", num = function(d) d$receptions, den = one),
  rec_ypt    = list(group = "receiving", table = "rec", unit = "targets", label = "Receiving yards per target",
                    formula = "sum(receiving yards on completions) / targets", num = function(d) d$rec_yds, den = one),
  rec_epa    = list(group = "receiving", table = "rec", unit = "targets", label = "EPA per target",
                    formula = "sum(epa) / targets", num = function(d) d$epa, den = one),
  catch_rate = list(group = "receiving", table = "rec", unit = "targets", label = "Catch rate (receptions per target)",
                    formula = "receptions / targets", num = function(d) d$complete_pass, den = one),
  # ---- defense
  sacks_pg   = list(group = "defense", table = "g_def", unit = "games", label = "Sacks per game",
                    formula = "sum(def_sacks) / games played", num = function(d) d$def_sacks, den = one),
  ints_pg    = list(group = "defense", table = "g_def", unit = "games", label = "Interceptions per game",
                    formula = "sum(def_interceptions) / games played", num = function(d) d$def_interceptions, den = one),
  tfl_pg     = list(group = "defense", table = "g_def", unit = "games", label = "Tackles for loss per game",
                    formula = "sum(def_tackles_for_loss) / games played", num = function(d) d$def_tackles_for_loss, den = one),
  press_pg   = list(group = "defense", table = "g_def", unit = "games", label = "Pressures per game",
                    formula = "sum(PFR def_pressures) / games played", num = function(d) d$def_pressures, den = one),
  sacks_ps   = list(group = "defense", table = "g_def", unit = "def_snaps", label = "Sacks per 100 defensive snaps",
                    formula = "100 x sum(def_sacks) / sum(defensive snaps)",
                    num = function(d) 100 * d$def_sacks, den = function(d) d$def_snaps),
  ints_ps    = list(group = "defense", table = "g_def", unit = "def_snaps", label = "Interceptions per 100 defensive snaps",
                    formula = "100 x sum(def_interceptions) / sum(defensive snaps)",
                    num = function(d) 100 * d$def_interceptions, den = function(d) d$def_snaps),
  tfl_ps     = list(group = "defense", table = "g_def", unit = "def_snaps", label = "Tackles for loss per 100 defensive snaps",
                    formula = "100 x sum(def_tackles_for_loss) / sum(defensive snaps)",
                    num = function(d) 100 * d$def_tackles_for_loss, den = function(d) d$def_snaps),
  press_ps   = list(group = "defense", table = "g_def", unit = "def_snaps", label = "Pressures per 100 defensive snaps",
                    formula = "100 x sum(PFR def_pressures) / sum(defensive snaps)",
                    num = function(d) 100 * d$def_pressures, den = function(d) d$def_snaps)
)
UNIT_COL   <- c(games = NA, dropbacks = NA, carries = NA, targets = NA, pfr_carries = "carries", def_snaps = "def_snaps")
UNIT_GRID  <- list(games = GRID_GAMES, dropbacks = GRID_DROPBACKS, carries = GRID_CARRIES, targets = GRID_TARGETS,
                   pfr_carries = GRID_CARRIES, def_snaps = GRID_DEF_SNAPS)
UNIT_LABEL <- c(games = "games played", dropbacks = "dropbacks", carries = "carries", targets = "targets",
                pfr_carries = "carries (PFR, whole games)", def_snaps = "defensive snaps (whole games)")
SOURCE_LABEL <- c(pass = "nflreadr::load_pbp()", rush = "nflreadr::load_pbp()", rec = "nflreadr::load_pbp()",
                  yac = "nflreadr::load_pfr_advstats(stat_type = \"rush\")",
                  g_pass = "nflreadr::load_player_stats() + load_snap_counts()",
                  g_rush = "nflreadr::load_player_stats() + load_snap_counts()",
                  g_rec = "nflreadr::load_player_stats() + load_snap_counts()",
                  g_def = "nflreadr::load_player_stats() + load_snap_counts()")
SOURCE_LABEL_STAT <- function(st) {
  if (st %in% c("press_pg", "press_ps")) return("nflreadr::load_pfr_advstats(stat_type = \"def\") + load_snap_counts()")
  SOURCE_LABEL[[STATS[[st]]$table]]
}

# Seasons each stat uses: a season is used only if the stat's value is
# measurable in at least one row of that season (the field exists there).
stat_seasons <- list()
for (st in names(STATS)) {
  d <- TABLES[[STATS[[st]]$table]]
  if (is.null(d)) { stat_seasons[[st]] <- integer(0); next }
  num <- STATS[[st]]$num(d); den <- STATS[[st]]$den(d)
  okr <- is.finite(num) & is.finite(den) & den > 0
  stat_seasons[[st]] <- sort(unique(as.integer(d$season[okr])))
}

# ==============================================================================
# 4. Bootstrap weights (player-season blocks), one matrix per sample table.
# ==============================================================================
WS <- list()
for (i in seq_along(TABLES)) {
  set.seed(SEED + i - 1L)
  np <- length(unique(TABLES[[i]]$ps))
  W <- matrix(0, nrow = np, ncol = N_BOOT)
  for (b in seq_len(N_BOOT)) W[, b] <- tabulate(sample.int(np, np, replace = TRUE), np)
  WS[[names(TABLES)[i]]] <- W
}

# Weighted Pearson correlation for every resample at once; idx = player-season rows.
boot_cor <- function(Wm, idx, x, y) {
  x <- x - mean(x); y <- y - mean(y)
  Wq  <- Wm[idx, , drop = FALSE]
  sw  <- colSums(Wq)
  sx  <- drop(crossprod(Wq, x));     sy  <- drop(crossprod(Wq, y))
  sxx <- drop(crossprod(Wq, x * x)); syy <- drop(crossprod(Wq, y * y))
  sxy <- drop(crossprod(Wq, x * y))
  num <- sw * sxy - sx * sy
  den <- sqrt(pmax(sw * sxx - sx^2, 0) * pmax(sw * syy - sy^2, 0))
  ifelse(den > 0, num / den, NA_real_)
}
sb  <- function(r) 2 * r / (1 + r)
q95 <- function(v) {
  v <- v[is.finite(v)]
  if (length(v) < 10) return(c(NA_real_, NA_real_))
  unname(quantile(v, c(0.025, 0.975)))
}

# ==============================================================================
# 5. Curves
# ==============================================================================
cum_frame <- function(d, num, den, unit, grp) {
  o <- order(grp, d$k)
  d <- d[o, ]; num <- num[o]; den <- den[o]; unit <- unit[o]; grp <- grp[o]
  data.frame(grp = grp, ps = d$ps,
             cnum = ave(num, grp, FUN = cumsum), cden = ave(den, grp, FUN = cumsum),
             cu = ave(unit, grp, FUN = cumsum))
}
first_reach <- function(cf, n) {
  r <- cf[!is.na(cf$cu) & cf$cu >= n, ]
  r[!duplicated(r$grp), ]
}

curve_rows <- list()
boot_store <- list()
for (st in names(STATS)) {
  spec  <- STATS[[st]]
  dall  <- TABLES[[spec$table]]
  grid  <- UNIT_GRID[[spec$unit]]
  if (is.null(dall) || !length(stat_seasons[[st]])) { say("Not measured: %s", st); next }
  games <- dall[dall$season %in% stat_seasons[[st]], ]
  W     <- WS[[spec$table]]
  num   <- spec$num(games); den <- spec$den(games)
  unit  <- if (is.na(UNIT_COL[[spec$unit]])) rep(1, nrow(games)) else games[[UNIT_COL[[spec$unit]]]]

  cf_half <- cum_frame(games, num, den, unit, paste(games$ps, games$half))
  cf_half$half <- sub("^.* ", "", cf_half$grp)
  cf_full <- cum_frame(games, num, den, unit, games$ps)
  tot <- cf_full[!duplicated(cf_full$grp, fromLast = TRUE), c("ps", "cnum", "cden", "cu")]
  names(tot) <- c("ps", "tnum", "tden", "tu")

  sh_b <- matrix(NA_real_, length(grid), N_BOOT); ros_b <- sh_b
  for (gi in seq_along(grid)) {   # ---- curve loop
    n <- grid[gi]
    # ---- split-half
    a <- first_reach(cf_half[cf_half$half == "A", ], n)
    b <- first_reach(cf_half[cf_half$half == "B", ], n)
    m <- merge(a[, c("ps", "cnum", "cden", "cu")], b[, c("ps", "cnum", "cden", "cu")],
               by = "ps", suffixes = c("_a", "_b"))
    m$va <- ifelse(!is.na(m$cden_a) & m$cden_a > 0, m$cnum_a / m$cden_a, NA_real_)
    m$vb <- ifelse(!is.na(m$cden_b) & m$cden_b > 0, m$cnum_b / m$cden_b, NA_real_)
    ok <- is.finite(m$va) & is.finite(m$vb)
    n_ok <- sum(ok); n_miss <- sum(!ok)
    r <- if (n_ok >= MIN_PLAYERS) cor(m$va[ok], m$vb[ok]) else NA_real_
    if (n_ok >= MIN_PLAYERS) sh_b[gi, ] <- boot_cor(W, m$ps[ok], m$va[ok], m$vb[ok])
    ci <- q95(sh_b[gi, ]); ci_sb <- q95(sb(sh_b[gi, ]))
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "split_half", n = n,
      n_players = n_ok, n_missing = n_miss,
      mean_realised_units = if (n_ok > 0) mean(c(m$cu_a[ok], m$cu_b[ok])) else NA_real_,
      r = r, r_lo = ci[1], r_hi = ci[2],
      sb_sample = 2 * n, r_sb = sb(r), r_sb_lo = ci_sb[1], r_sb_hi = ci_sb[2])
    # ---- rest of season: first n units vs all remaining units, remainder >= n units
    f <- merge(first_reach(cf_full, n)[, c("ps", "cnum", "cden", "cu")], tot, by = "ps")
    f <- f[!is.na(f$tu) & (f$tu - f$cu) >= n, ]
    f$ve <- ifelse(!is.na(f$cden) & f$cden > 0, f$cnum / f$cden, NA_real_)
    f$vr <- ifelse(!is.na(f$tden - f$cden) & (f$tden - f$cden) > 0, (f$tnum - f$cnum) / (f$tden - f$cden), NA_real_)
    ok2 <- is.finite(f$ve) & is.finite(f$vr)
    n_ok2 <- sum(ok2)
    r2 <- if (n_ok2 >= MIN_PLAYERS) cor(f$ve[ok2], f$vr[ok2]) else NA_real_
    if (n_ok2 >= MIN_PLAYERS) ros_b[gi, ] <- boot_cor(W, f$ps[ok2], f$ve[ok2], f$vr[ok2])
    ci2 <- q95(ros_b[gi, ])
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "rest_of_season", n = n,
      n_players = n_ok2, n_missing = sum(!ok2),
      mean_realised_units = if (n_ok2 > 0) mean(f$cu[ok2]) else NA_real_,
      r = r2, r_lo = ci2[1], r_hi = ci2[2],
      sb_sample = NA_real_, r_sb = NA_real_, r_sb_lo = NA_real_, r_sb_hi = NA_real_)
  }
  boot_store[[st]] <- list(grid = grid, sh = sh_b, ros = ros_b,
                           player_seasons = length(unique(games$ps)), rows = nrow(games))
  say("Curves done: %s (%d player-seasons)", st, length(unique(games$ps)))
}
curves <- do.call(rbind, curve_rows)
MEASURED <- names(boot_store)

# ==============================================================================
# 6. Crossings of the reference bars (reference points only)
# ==============================================================================
# First grid point at which the curve is at or above the bar. Interval: the same
# first-crossing rule applied to each bootstrap curve, percentile 95%. Resamples in
# which the curve never reaches the bar inside the grid are counted (share_not_reached)
# and enter the percentile as +Inf (reported as "beyond grid").
first_cross <- function(grid, v, bar) { i <- which(!is.na(v) & v >= bar); if (length(i)) grid[i[1]] else Inf }
cross_summary <- function(grid, point_curve, boot_mat, bar, scale = 1) {
  pt <- first_cross(grid, point_curve, bar)
  bc <- apply(boot_mat, 2, function(v) first_cross(grid, v, bar))
  qs <- unname(quantile(bc, c(0.025, 0.975), type = 1))
  list(bar = bar, point = if (is.finite(pt)) pt * scale else NULL,
       lo = if (is.finite(qs[1])) qs[1] * scale else NULL,
       hi = if (is.finite(qs[2])) qs[2] * scale else NULL,
       share_not_reached = mean(!is.finite(bc)))
}
crossings <- list()
for (st in MEASURED) {
  bs <- boot_store[[st]]
  shc <- curves[curves$stat == st & curves$method == "split_half", ]
  roc <- curves[curves$stat == st & curves$method == "rest_of_season", ]
  crossings[[st]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r, bs$sh, b)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r_sb, sb(bs$sh), b, scale = 2)),
    rest_of_season = lapply(REF_BARS, function(b) cross_summary(bs$grid, roc$r, bs$ros, b)))
}

# ==============================================================================
# 7. Plots (one PNG per stat group)
# ==============================================================================
GROUPS <- c("passing", "rushing", "receiving", "defense")
plot_group <- function(grp, file) {
  d <- curves[curves$group == grp, ]
  if (!nrow(d)) return(invisible(FALSE))
  d$label <- vapply(d$stat, function(s) sprintf("%s\n(by %s)", STATS[[s]]$label, UNIT_LABEL[[STATS[[s]]$unit]]), "")
  d$label <- factor(d$label, levels = unique(d$label))
  sh <- d[d$method == "split_half", ]; ro <- d[d$method == "rest_of_season", ]
  long <- rbind(
    data.frame(label = sh$label, x = sh$n, r = sh$r, lo = sh$r_lo, hi = sh$r_hi,
               curve = "Split-half r (sample n)"),
    data.frame(label = sh$label, x = sh$sb_sample, r = sh$r_sb, lo = sh$r_sb_lo, hi = sh$r_sb_hi,
               curve = "Spearman-Brown (sample 2n)"),
    data.frame(label = ro$label, x = ro$n, r = ro$r, lo = ro$r_lo, hi = ro$r_hi,
               curve = "Rest of season r (first n)"))
  npan <- length(levels(d$label))
  p <- ggplot(long, aes(x, r, colour = curve, fill = curve)) +
    geom_hline(yintercept = REF_BARS, linetype = "dashed", colour = "grey55", linewidth = 0.3) +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, colour = NA, na.rm = TRUE) +
    geom_line(linewidth = 0.7, na.rm = TRUE) +
    facet_wrap(~ label, scales = "free_x", ncol = min(4, npan)) +
    coord_cartesian(ylim = c(-0.1, 1)) +
    labs(x = "Sample size (unit named in each panel)", y = "Correlation", colour = NULL, fill = NULL,
         title = sprintf("NFL leader reliability: %s", grp),
         subtitle = sprintf("Regular seasons %s; bands = player-season bootstrap 95%% (%d resamples); dashed = bars %s",
                            paste(range(SEASONS), collapse = "-"), N_BOOT, paste(REF_BARS, collapse = ", "))) +
    theme_minimal(base_size = 10) + theme(legend.position = "bottom")
  ggsave(file, p, width = 12, height = 2.2 + 2.6 * ceiling(npan / 4), dpi = 110, bg = "white")
  invisible(TRUE)
}
plot_files <- setNames(paste0(GROUPS, ".png"), GROUPS)
for (g in GROUPS) plot_group(g, file.path(FIG_DIR, plot_files[[g]]))

# ==============================================================================
# 8. Data audit
# ==============================================================================
audit <- lapply(SEASONS, function(s) {
  cnt <- function(tn) { d <- TABLES[[tn]]; if (is.null(d)) 0L else sum(d$season == s) }
  ps_cnt <- function(tn) { d <- TABLES[[tn]]; if (is.null(d)) 0L else length(unique(d$ps[d$season == s])) }
  gd <- TABLES$g_def
  list(season = s,
       regular_season_plays = sum(pbp$season == s),
       dropbacks = cnt("pass"), dropbacks_epa_missing = sum(T_pass$season == s & is.na(T_pass$qb_epa)),
       designed_carries = cnt("rush"), carries_epa_missing = sum(T_rush$season == s & is.na(T_rush$epa)),
       targets = cnt("rec"), targets_epa_missing = sum(T_rec$season == s & is.na(T_rec$epa)),
       passer_seasons = ps_cnt("pass"), rusher_seasons = ps_cnt("rush"), receiver_seasons = ps_cnt("rec"),
       pfr_rushing_player_games = cnt("yac"),
       offense_games_played_passing = cnt("g_pass"), offense_games_played_rushing = cnt("g_rush"),
       offense_games_played_receiving = cnt("g_rec"),
       offense_games_no_stats_row = sum(c(G_pass$no_stats_row[G_pass$season == s], G_rush$no_stats_row[G_rush$season == s],
                                          G_rec$no_stats_row[G_rec$season == s])),
       defense_games_played = cnt("g_def"), defender_seasons = ps_cnt("g_def"),
       defense_games_no_stats_row = sum(gd$no_stats_row[gd$season == s]),
       defense_games_unlinked_to_gsis = sum(gd$unlinked[gd$season == s]),
       defense_games_pressures_missing = sum(gd$season == s & is.na(gd$def_pressures)))
})
pool_unlinked <- c(passing = sum(!(pool_pass %in% unique(paste(G_pass$season, G_pass$gsis_id, sep = "_")))),
                   rushing = sum(!(pool_rush %in% unique(paste(G_rush$season, G_rush$gsis_id, sep = "_")))),
                   receiving = sum(!(pool_rec %in% unique(paste(G_rec$season, G_rec$gsis_id, sep = "_")))))

runtime_min <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))

# ==============================================================================
# 9. Results JSON
# ==============================================================================
NOT_MEASURED <- list(
  list(stat = "Yards per route run (receiving)",
       reason = paste("Routes run per player are not in the nflverse data. load_participation() has a single",
                      "`route` value per play (the targeted receiver's route, recorded from 2023 only), not the",
                      "routes of every receiver on the play, so routes run cannot be counted. Receiving is",
                      "therefore measured by targets.")))
for (st in setdiff(names(STATS), MEASURED))
  NOT_MEASURED[[length(NOT_MEASURED) + 1]] <- list(stat = STATS[[st]]$label,
    reason = "Its source returned no measurable value for any season in SEASONS.")

df_rows <- function(d) lapply(seq_len(nrow(d)), function(i) as.list(d[i, , drop = FALSE]))
stats_json <- lapply(MEASURED, function(st) {
  s <- STATS[[st]]
  list(label = s$label, group = s$group, unit = s$unit, unit_label = UNIT_LABEL[[s$unit]],
       source = SOURCE_LABEL_STAT(st), formula = s$formula, seasons_used = stat_seasons[[st]],
       player_seasons = boot_store[[st]]$player_seasons,
       split_half = df_rows(curves[curves$stat == st & curves$method == "split_half",
                                   c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi",
                                     "sb_sample", "r_sb", "r_sb_lo", "r_sb_hi")]),
       rest_of_season = df_rows(curves[curves$stat == st & curves$method == "rest_of_season",
                                       c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi")]),
       crossings = crossings[[st]])
})
names(stats_json) <- MEASURED

results <- list(
  issue = "NFL_analytics#229",
  note = "Reference points only. No qualifying minimum is chosen here; the owner sets them after reviewing the curves.",
  settings = list(seasons = SEASONS, seed = SEED, n_boot = N_BOOT, grid_games = GRID_GAMES,
                  grid_dropbacks = GRID_DROPBACKS, grid_carries = GRID_CARRIES, grid_targets = GRID_TARGETS,
                  grid_def_snaps = GRID_DEF_SNAPS, reference_bars = REF_BARS, min_players_per_point = MIN_PLAYERS),
  data_audit = audit,
  pfr_seasons_not_served = pfr_fail,
  pool_player_seasons_without_snap_link = as.list(pool_unlinked),
  stats = stats_json,
  not_measured = NOT_MEASURED,
  runtime_minutes = round(runtime_min, 2)
)
writeLines(toJSON(results, auto_unbox = TRUE, digits = 4, null = "null", na = "null", pretty = TRUE),
           file.path(OUT_DIR, "leader_reliability_study_results.json"))

# ==============================================================================
# 10. Report
# ==============================================================================
f2 <- function(x) ifelse(is.na(x), "NA", sprintf("%.2f", x))
fmt_n <- function(x) format(x, big.mark = ",", trim = TRUE, scientific = FALSE)
fmt_cross <- function(cx) {
  if (is.null(cx$point)) return(sprintf("not reached (%.0f%% of resamples)", 100 * cx$share_not_reached))
  hi <- if (is.null(cx$hi)) "beyond grid" else fmt_n(cx$hi)
  lo <- if (is.null(cx$lo)) "beyond grid" else fmt_n(cx$lo)
  sprintf("%s [%s, %s]", fmt_n(cx$point), lo, hi)
}
seasons_str <- function(v) {
  if (!length(v)) return("none")
  if (length(v) == max(v) - min(v) + 1) sprintf("%d-%d (%d)", min(v), max(v), length(v))
  else paste(v, collapse = ", ")
}
kinds_box <- c(split_half = "split-half r, sample n", spearman_brown = "Spearman-Brown, sample 2n",
               rest_of_season = "rest-of-season r, first n")
cross_table <- function(stats) {
  lines <- c(paste0("| Stat | Unit | Curve | ", paste(sprintf("bar %.1f", REF_BARS), collapse = " | "), " |"),
             paste0("|", paste(rep("---", 3 + length(REF_BARS)), collapse = "|"), "|"))
  for (st in stats) for (kd in names(kinds_box)) {
    cx <- crossings[[st]][[kd]]
    lines <- c(lines, sprintf("| %s | %s | %s | %s |", STATS[[st]]$label, UNIT_LABEL[[STATS[[st]]$unit]], kinds_box[[kd]],
                              paste(vapply(cx, fmt_cross, ""), collapse = " | ")))
  }
  lines
}
point_at <- function(st, method, n) {
  r <- curves[curves$stat == st & curves$method == method & curves$n == n, ]
  if (!nrow(r) || is.na(r$r)) return(sprintf("NA (N=%d)", if (nrow(r)) r$n_players else 0L))
  sprintf("%s [%s, %s] (N=%d)", f2(r$r), f2(r$r_lo), f2(r$r_hi), r$n_players)
}
snap_n <- c(games = 4, dropbacks = 150, carries = 60, pfr_carries = 60, targets = 30, def_snaps = 250)
snap <- c("| Stat | Unit | n | Split-half r at n | Spearman-Brown (2n) | Rest-of-season r at n |",
          "|---|---|---|---|---|---|")
for (st in MEASURED) {
  u <- STATS[[st]]$unit; n <- snap_n[[u]]
  r <- curves[curves$stat == st & curves$method == "split_half" & curves$n == n, ]
  snap <- c(snap, sprintf("| %s | %s | %s | %s | %s | %s |", STATS[[st]]$label, UNIT_LABEL[[u]], n,
                          point_at(st, "split_half", n),
                          if (nrow(r) && !is.na(r$r)) sprintf("%s [%s, %s]", f2(r$r_sb), f2(r$r_sb_lo), f2(r$r_sb_hi)) else "NA",
                          point_at(st, "rest_of_season", n)))
}
season_tbl <- c("| Group | Stat | Unit | Source | Seasons used | Player-seasons |", "|---|---|---|---|---|---|")
for (st in MEASURED) season_tbl <- c(season_tbl, sprintf("| %s | %s | %s | %s | %s | %s |", STATS[[st]]$group,
  STATS[[st]]$label, UNIT_LABEL[[STATS[[st]]$unit]], gsub("\\|", "/", SOURCE_LABEL_STAT(st)),
  seasons_str(stat_seasons[[st]]), fmt_n(boot_store[[st]]$player_seasons)))
formula_tbl <- c("| Stat | Unit | Formula (over a sample of plays or games) |", "|---|---|---|")
for (st in MEASURED) formula_tbl <- c(formula_tbl, sprintf("| %s | %s | %s |", STATS[[st]]$label,
  UNIT_LABEL[[STATS[[st]]$unit]], STATS[[st]]$formula))
audit_tbl <- c("| Season | REG plays | Dropbacks | Designed carries | Targets | EPA missing (db/car/tgt) | PFR rushing player-games | Defensive player-games | Def. games, no stats row | Def. games unlinked | Def. games, pressures missing |",
               "|---|---|---|---|---|---|---|---|---|---|---|")
for (a in audit) audit_tbl <- c(audit_tbl, sprintf("| %d | %s | %s | %s | %s | %d/%d/%d | %s | %s | %s | %s | %s |",
  a$season, fmt_n(a$regular_season_plays), fmt_n(a$dropbacks), fmt_n(a$designed_carries), fmt_n(a$targets),
  a$dropbacks_epa_missing, a$carries_epa_missing, a$targets_epa_missing, fmt_n(a$pfr_rushing_player_games),
  fmt_n(a$defense_games_played), fmt_n(a$defense_games_no_stats_row), fmt_n(a$defense_games_unlinked_to_gsis),
  fmt_n(a$defense_games_pressures_missing)))
pg_pairs <- list(c("pass_ypg", "pass_ypdb"), c("pass_tdpg", "pass_tdpdb"), c("rush_ypg", "rush_ypc"),
                 c("rec_ypg", "rec_ypt"), c("rec_pg", "catch_rate"), c("sacks_pg", "sacks_ps"),
                 c("ints_pg", "ints_ps"), c("tfl_pg", "tfl_ps"), c("press_pg", "press_ps"))
pair_tbl <- c("| Per-game stat (unit: games played) | Per-play form | Per-play unit |", "|---|---|---|")
for (p in pg_pairs) if (all(p %in% MEASURED)) pair_tbl <- c(pair_tbl, sprintf("| %s | %s | %s |",
  STATS[[p[1]]]$label, STATS[[p[2]]]$label, UNIT_LABEL[[STATS[[p[2]]]$unit]]))
nm_lines <- vapply(NOT_MEASURED, function(x) sprintf("- **%s.** %s", x$stat, x$reason), "")
pfr_lines <- if (length(pfr_fail)) sprintf("- Pro Football Reference weekly advanced stats are not served for: %s (source message: \"%s\"). Yards after contact and pressures use the seasons it does serve.",
  paste(sub("^(rush|def)_", "\\1 ", names(pfr_fail)), collapse = ", "), unique(unlist(pfr_fail))[1]) else character(0)

report <- c(
  "# NFL leader reliability study (issue #229)",
  "",
  "Research only. This study measures how quickly each NFL leader stat settles as a player's sample grows, repeating the NBA study (NBA_analytics#253) for football. It does not choose any qualifying minimum and changes no production code; the owner reviews these curves and sets the minimums (used by the NFL leaders panel).",
  "",
  sprintf("Generated by `tools/leader_reliability_study.R` (seed %d, %d bootstrap resamples). Runtime of this run: %.1f minutes.", SEED, N_BOOT, runtime_min),
  "",
  "## Data",
  "",
  sprintf("- NFL regular seasons %s (season = the year it starts). 2016 is the first season of the participation and snap-count era the pipeline uses; 2026 is in progress and is not used. Regular season only (`season_type == \"REG\"` / `game_type == \"REG\"`).", seasons_str(SEASONS)),
  "- Play-by-play: `nflreadr::load_pbp()` (nflfastR fields `qb_epa`, `epa`, `success`, `cpoe`, `passer_id`, `rusher_player_id`, `receiver_player_id`). Per-game box-score counts: `nflreadr::load_player_stats(summary_level = \"week\")`. Games played and defensive snaps: `nflreadr::load_snap_counts()`, linked to gsis ids through `nflreadr::load_players()`. Yards after contact and pressures: `nflreadr::load_pfr_advstats(summary_level = \"week\")`, which the source serves from 2018.",
  "- Participation data (`nflreadr::load_participation()`) was examined for routes and pressures. Its `route` field is one value per play (the targeted receiver's route, from 2023) and `was_pressure` is a play-level flag not credited to a defender, so neither gives a per-player count; pressures come from Pro Football Reference instead and routes run are not measured (see below).",
  pfr_lines,
  "- **Seasons each stat uses** (a season is used only if the stat's field is measurable in it):",
  "",
  season_tbl,
  "",
  "- **Missing values.** Nothing is imputed. A missing value (for example a play with no EPA, a defensive game with no Pro Football Reference row, or a player who cannot be linked to a gsis id) makes any sample that contains it missing at that point, and the number of such player-seasons is reported at every point (`n_missing` in the JSON).",
  "- **Games with no stats row.** `load_player_stats()` is built from play-by-play and lists a player in a game only when he recorded an event. A game in which the snap counts show the player on the field and the stats table has no row for him is a game with none of the counted events (zero), not a missing value; these games are counted in the audit below. Pro Football Reference rows are not built this way, so a played defensive game without one has missing pressures.",
  sprintf("- Pool player-seasons that could not be linked to snap counts (no per-game rows for them): passing %d, rushing %d, receiving %d.", pool_unlinked[["passing"]], pool_unlinked[["rushing"]], pool_unlinked[["receiving"]]),
  "- A player-season covers every team the player played for that season.",
  "",
  audit_tbl,
  "",
  "## Methods",
  "",
  "- **Position groups and pools.** Curves are per stat group. Passing: every player-season with at least one dropback. Rushing: every player-season with at least one designed carry. Receiving: every player-season with at least one target. Defense: every player-season with at least one defensive snap. A player can appear in more than one group. Per-game stats in a group use the same pool, with games played (offensive or defensive snaps above zero) as the unit.",
  "- **Split-half reliability.** Each player-season's games are numbered in week order; odd-numbered games form half A and even-numbered games half B. For play units the games numbered are those in which the player had at least one play of that unit; for per-game and snap units they are the games he played. At each sample size n the stat is computed on each half from the first n units of that half, for every player-season whose two halves each reach n units, and the two halves are correlated across player-seasons (Pearson). The raw correlation is the reliability of an n-unit sample. The Spearman-Brown value 2r / (1 + r) is the projected reliability of a 2n-unit sample and is plotted at 2n.",
  "- **Rest-of-season check.** The stat over a player's first n units of the season against the same stat over all of his remaining units that season. Rule: only player-seasons whose remainder holds at least n units are used, so the remainder is never smaller than the early sample.",
  "- **Units.** Dropbacks, designed carries and targets come from play-by-play, so a sample of n is exactly the first n plays. Yards after contact (Pro Football Reference carries) and the defensive per-snap stats are only available per game, so a sample of n there is the shortest run of whole games whose cumulative units reach n; the mean realised size is reported in the JSON (`mean_realised_units`).",
  sprintf("- **Intervals.** Player-season block bootstrap: player-seasons are resampled with replacement (%d resamples, seed %d and one stream per sample table), every curve point is recomputed on each resample with the same draw, and the 2.5th and 97.5th percentiles are reported. Points with fewer than %d player-seasons are not reported.", N_BOOT, SEED, MIN_PLAYERS),
  "- **Reading the curves at large n.** Only high-volume players reach large samples, so the player pool narrows as n grows; a narrower range of true talent lowers correlations. A curve that flattens or dips at the right-hand end reflects that selection as well as noise, and the player count at each point should be read with it.",
  "- **Who is in the pool.** As issue #229 specifies (following the NBA study), every player-season that reaches n is correlated, from backups and depth players to stars. The range of true levels across that pool is wide (a starter's yards per game differ from a backup's mostly through role and snaps), and a wide range makes correlations high at small n. Separating players near the top of a leader list from each other is a harder task than this pool-wide correlation measures, so the crossings below describe the whole league, not the top of a list.",
  "",
  "## Units and per-game stats",
  "",
  sprintf("A regular season has only 16 games (2016-2020) or 17 games (2021 on), so a half holds at most 8 or 9 games and the per-game curves stop at n = %d games per half (Spearman-Brown projects to %d). The issue lists yards per game, touchdowns, receptions, sacks, interceptions, tackles for loss and pressures as per-game or counting stats, so each is reported twice: per game, by games played, and in a per-play form by the group's play unit. Catch rate is the per-play form of receptions (receptions per target).", max(GRID_GAMES), 2 * max(GRID_GAMES)),
  "",
  pair_tbl,
  "",
  "## Formulas",
  "",
  "For a sample, each stat is the sum of its numerators over the sum of its denominators. Dropbacks are plays with `qb_dropback == 1` (pass attempts, sacks and scrambles) of type pass or run, credited to `passer_id`. Designed carries are run plays with `rush_attempt == 1`, excluding QB scrambles (counted as dropbacks) and kneels, credited to `rusher_player_id`. Targets are pass attempts (not sacks) with a `receiver_player_id`. Two-point tries are excluded throughout. Success is nflfastR's `success` (EPA > 0). CPOE is nflfastR's `cpoe` (percentage points); dropbacks without a `cpoe` value (sacks, scrambles, attempts without a completion probability) carry no weight. Yards on incomplete passes are 0.",
  "",
  formula_tbl,
  "",
  "## Curves",
  "",
  "### Passing (dropbacks; per-game stats by games played)",
  "", "![Passing](leader_reliability_study/passing.png)", "",
  "### Rushing (designed carries; per-game stats by games played)",
  "", "![Rushing](leader_reliability_study/rushing.png)", "",
  "### Receiving (targets; per-game stats by games played)",
  "", "![Receiving](leader_reliability_study/receiving.png)", "",
  "### Defense (games played and defensive snaps)",
  "", "![Defense](leader_reliability_study/defense.png)", "",
  "### Snapshot at one sample size per unit",
  "",
  "Correlation [bootstrap 95%] and player-season count. The full curves, with player counts at every point, are in the results JSON.",
  "", snap, "",
  "## Not measured",
  "",
  nm_lines,
  "",
  "## Reference points for the owner's review",
  "",
  "For each stat, the first grid sample size at which each curve reaches the bar, with a bootstrap 95% interval for that crossing. \"Beyond grid\" means some resamples did not reach the bar inside the grid; \"not reached\" means the curve stays below the bar over the whole grid. These are reference points for review, not chosen values. Split-half and rest-of-season values are in the stat's own unit for an n-unit sample; Spearman-Brown values are the projected sample (2n) at which reliability reaches the bar. The pool covers every player-season, from backups to stars, so separating players near the top of a list is harder than these curves suggest.",
  ""
)
for (g in GROUPS) {
  sts <- MEASURED[vapply(MEASURED, function(s) STATS[[s]]$group == g, TRUE)]
  if (length(sts)) report <- c(report, sprintf("### %s", tools::toTitleCase(g)), "", cross_table(sts), "")
}
writeLines(report, file.path(OUT_DIR, "leader_reliability_study.md"))

say("Done in %.1f minutes. Wrote %s, %s and %d plots.", runtime_min,
    file.path(OUT_DIR, "leader_reliability_study.md"), file.path(OUT_DIR, "leader_reliability_study_results.json"),
    length(list.files(FIG_DIR, pattern = "\\.png$")))
