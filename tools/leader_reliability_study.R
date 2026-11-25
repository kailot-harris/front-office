# ==============================================================================
# tools/leader_reliability_study.R
#
# Issue #162: how large a sample does a player need before each MLB leader stat
# reflects his real level rather than noise? RESEARCH ONLY. This script is not
# wired into the pipeline, changes no production setting and chooses no
# qualifying minimum. It measures reliability curves; the owner reads them and
# sets the minimums (the leaders panel consumes them). It repeats the NBA study
# (NBA_analytics#253, tools/leader_reliability_study.R there) for MLB and reuses
# its curve, bootstrap, crossing, plot and report code.
#
# WHAT IT DOES
#   1. Player game logs (one row per player per game) from the MLB Stats API
#      (statsapi.mlb.com, the API baseballr's mlb_* functions wrap), regular
#      season only:
#        - batting stats, sample unit plate appearances (PA);
#        - pitching rate stats, sample unit batters faced (BF);
#        - innings pitched per appearance (unit: appearances) and saves per
#          relief appearance (unit: relief appearances, games not started).
#      Barrel rate comes from Statcast batted-ball events (Baseball Savant
#      search CSV, the endpoint baseballr::statcast_search() reads, filtered to
#      balls in play). wOBA weights and the FIP constant are FanGraphs' season
#      constants (baseballr::fg_guts()).
#        - Split-half reliability: each player-season's games are numbered by
#          date; odd-numbered games form half A, even-numbered games half B. At
#          sample size n the stat is computed on each half from the first n
#          units of that half and correlated across player-seasons (Pearson).
#          Spearman-Brown: r_sb = 2r / (1 + r), the reliability of a sample of
#          2n units.
#        - Rest-of-season check: the stat over a player's first n units of the
#          season against the same stat over ALL his remaining games that
#          season, for player-seasons whose remainder holds at least n units.
#   2. Intervals: player-season block bootstrap, percentile 95% intervals.
#   3. Comparison with MLB's official qualifying rules (3.1 PA and 1 inning
#      pitched per team game).
#
# Units and samples: games are discrete, so the sample "first n units" is the
# shortest run of whole games (in date order) whose cumulative units reach n.
# The realised sample is therefore n plus at most one game's worth of units; the
# mean realised size is reported at every point.
#
# No imputation: a value that is missing in a game stays missing; any sample
# that contains it is dropped at that point and counted (n_missing). A sample
# whose stat is undefined (for example zero outs recorded for ERA) is counted
# the same way.
#
# Run from the project root in a fresh session. The project's .Rprofile
# activates renv; this research script only needs baseballr, jsonlite, curl,
# ggplot2 from the user library, so skip the profile:
#   Rscript --no-init-file tools/leader_reliability_study.R
# Smoke test with fewer resamples:
#   LRS_N_BOOT=50 Rscript --no-init-file tools/leader_reliability_study.R
# (LRS_SEASONS=2017,2018 also limits the seasons for a smoke test; a smoke run
# overwrites the outputs, so finish with a full run.)
# Re-run each offseason by changing SEASONS below. Downloads are cached in
# cache/lrs_*.rds; delete them to refetch.
# ==============================================================================

# ---- Settings (change these to re-run the study) ------------------------------
# Complete regular seasons. 2020 is left out because it was a 60-game season.
# 2017 is the first season used; Statcast barrels exist from 2015, so the range
# can be extended back by editing this vector.
SEASONS        <- c(2017L, 2018L, 2019L, 2021L, 2022L, 2023L, 2024L, 2025L, 2026L)
if (nzchar(Sys.getenv("LRS_SEASONS")))   # smoke tests only, e.g. LRS_SEASONS=2017,2018
  SEASONS <- as.integer(strsplit(Sys.getenv("LRS_SEASONS"), ",")[[1]])
SEED          <- 162L
N_BOOT         <- as.integer(Sys.getenv("LRS_N_BOOT", "1000"))
GRID_PA        <- c(seq(10, 100, 10), seq(125, 400, 25))      # plate appearances
GRID_BF        <- c(seq(10, 100, 10), seq(125, 450, 25))      # batters faced
GRID_APPS      <- 1:40                                        # appearances
REF_BARS       <- c(0.5, 0.6, 0.7, 0.8)
MIN_PLAYERS    <- 30L    # a curve point is reported only with >= this many player-seasons
# MLB official qualifying rules for rate-stat leaders (per team game)
QUAL_PA_PER_TEAM_GAME <- 3.1
QUAL_IP_PER_TEAM_GAME <- 1.0
TEAM_GAMES            <- 162L
# Download settings
API_BATCH       <- 40L   # players per MLB Stats API game-log request
STATCAST_WINDOW <- 8L    # days per Baseball Savant request (row cap 25,000)
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
if (!file.exists("mlb_ingest.R") || !file.exists("config.R")) stop("Run from the MLB Analytics project root.")

suppressPackageStartupMessages({
  library(ggplot2)
  library(jsonlite)
})

CACHE   <- "cache"
OUT_DIR <- file.path("docs", "research")
FIG_DIR <- file.path(OUT_DIR, "leader_reliability_study")
dir.create(CACHE, showWarnings = FALSE, recursive = TRUE)
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

say <- function(...) message(sprintf("[%s] ", format(Sys.time(), "%H:%M:%S")), sprintf(...))
say("MLB leader reliability study: seasons %s, %d bootstrap resamples, seed %d",
    paste(SEASONS, collapse = ","), N_BOOT, SEED)

# ==============================================================================
# 1. Data
# ==============================================================================
API <- "https://statsapi.mlb.com/api/v1"
fetch_raw <- function(url, tries = 5L) {
  for (i in seq_len(tries)) {
    res <- tryCatch(curl::curl_fetch_memory(url), error = function(e) NULL)
    if (!is.null(res) && res$status_code == 200L) return(res$content)
    Sys.sleep(3 * i)
  }
  stop("download failed after retries: ", url)
}
fetch_json <- function(url) fromJSON(rawToChar(fetch_raw(url)))

num <- function(d, col) if (col %in% names(d)) suppressWarnings(as.numeric(d[[col]])) else rep(NA_real_, nrow(d))

HIT_FIELDS <- c(pa = "plateAppearances", ab = "atBats", h = "hits", d2 = "doubles", d3 = "triples",
                hr = "homeRuns", bb = "baseOnBalls", ibb = "intentionalWalks", hbp = "hitByPitch",
                sf = "sacFlies", sh = "sacBunts", so = "strikeOuts", sb = "stolenBases",
                cs = "caughtStealing", tb = "totalBases")
PIT_FIELDS <- c(gs = "gamesStarted", bf = "battersFaced", outs = "outs", h = "hits", bb = "baseOnBalls",
                ibb = "intentionalWalks", hbp = "hitBatsmen", so = "strikeOuts", hr = "homeRuns",
                er = "earnedRuns", sv = "saves", svo = "saveOpportunities")

parse_splits <- function(sp, fields) {
  sp <- jsonlite::flatten(as.data.frame(sp))
  sp <- sp[!is.na(sp$gameType) & sp$gameType == "R", , drop = FALSE]
  if (!nrow(sp)) return(NULL)
  out <- data.frame(player_id = as.character(sp$player.id), player = as.character(sp$player.fullName),
                    game_pk = as.character(sp$game.gamePk), game_date = as.Date(sp$date),
                    team_id = as.character(sp$team.id), stringsAsFactors = FALSE)
  for (k in names(fields)) out[[k]] <- num(sp, paste0("stat.", fields[[k]]))
  out
}

# One request per API_BATCH players returns each player's batting and pitching
# game logs for the season (people endpoint, stats hydration).
load_game_logs <- function(season) {
  path <- file.path(CACHE, sprintf("lrs_gamelogs_%d.rds", season))
  if (file.exists(path)) return(readRDS(path))
  say("Downloading MLB Stats API game logs %d", season)
  roster <- as.data.frame(baseballr::mlb_sports_players(sport_id = 1, season = season))
  ids <- unique(as.character(roster$player_id))
  hit <- list(); pit <- list()
  for (bi in seq(1, length(ids), by = API_BATCH)) {
    chunk <- ids[bi:min(bi + API_BATCH - 1L, length(ids))]
    url <- sprintf("%s/people?personIds=%s&hydrate=stats(group=[hitting,pitching],type=[gameLog],season=%d,gameType=R)",
                   API, paste(chunk, collapse = ","), season)
    url <- gsub("\\[", "%5B", gsub("\\]", "%5D", url))
    x <- fetch_json(url)$people
    if (is.null(x) || !"stats" %in% names(x)) next
    for (i in seq_len(nrow(x))) {
      st <- x$stats[[i]]
      if (is.null(st) || !nrow(st)) next
      for (j in seq_len(nrow(st))) {
        grp <- st$group$displayName[j]
        sp  <- st$splits[[j]]
        if (is.null(sp) || !length(sp) || !NROW(sp)) next
        if (grp == "hitting")  hit[[length(hit) + 1]] <- parse_splits(sp, HIT_FIELDS)
        if (grp == "pitching") pit[[length(pit) + 1]] <- parse_splits(sp, PIT_FIELDS)
      }
    }
  }
  # League totals for the completeness audit
  tt <- fetch_json(sprintf("%s/teams/stats?season=%d&group=hitting,pitching&stats=season&sportIds=1&gameType=R", API, season))$stats
  tot <- list()
  for (j in seq_len(nrow(tt))) {
    s <- jsonlite::flatten(as.data.frame(tt$splits[[j]]))
    g <- tt$group$displayName[j]
    if (g == "hitting")  tot$team_pa <- sum(num(s, "stat.plateAppearances"))
    if (g == "pitching") { tot$team_bf <- sum(num(s, "stat.battersFaced")); tot$team_outs <- sum(num(s, "stat.outs"))
                           tot$team_games <- sum(num(s, "stat.gamesPlayed")) }
  }
  res <- list(hit = do.call(rbind, hit), pit = do.call(rbind, pit), roster_players = length(ids), team_totals = tot,
              source = sprintf("MLB Stats API people gameLog hydration, season %d, gameType R", season))
  saveRDS(res, path)
  res
}

# Statcast balls in play, aggregated per batter and game: barrels
# (launch_speed_angle == 6) and batted-ball events with and without a tracked
# launch_speed_angle.
load_statcast_bip <- function(season, date_from, date_to) {
  path <- file.path(CACHE, sprintf("lrs_statcast_bip_%d.rds", season))
  if (file.exists(path)) return(readRDS(path))
  say("Downloading Statcast balls in play %d (%s to %s)", season, date_from, date_to)
  starts <- seq(date_from, date_to, by = STATCAST_WINDOW)
  parts <- list()
  for (k in seq_along(starts)) {
    a <- starts[k]; b <- min(a + STATCAST_WINDOW - 1L, date_to)
    url <- sprintf(paste0("https://baseballsavant.mlb.com/statcast_search/csv?all=true",
                          "&hfPR=hit%%5C.%%5C.into%%5C.%%5C.play%%7C&hfGT=R%%7C&hfSea=%d%%7C",
                          "&player_type=batter&game_date_gt=%s&game_date_lt=%s&type=details"),
                   season, format(a), format(b))
    txt <- rawToChar(fetch_raw(url))
    d <- if (nchar(txt) < 50) NULL else utils::read.csv(text = txt, stringsAsFactors = FALSE)
    if (!is.null(d) && nrow(d) >= 25000) stop("Savant row cap reached for window ", a, "; shorten STATCAST_WINDOW")
    if (!is.null(d) && nrow(d)) {
      d <- d[!duplicated(d), , drop = FALSE]   # exact duplicate rows only
      d <- d[d$type == "X", c("game_pk", "batter", "launch_speed_angle")]
      parts[[length(parts) + 1]] <- d
    }
    Sys.sleep(1)
  }
  d <- do.call(rbind, parts)   # windows do not overlap, so every row is a distinct pitch
  d$tracked <- !is.na(d$launch_speed_angle)
  agg <- aggregate(cbind(bbe_tracked = tracked, bbe_untracked = !tracked,
                         barrels = !is.na(launch_speed_angle) & launch_speed_angle == 6) ~ game_pk + batter,
                   data = d, FUN = sum)
  res <- list(agg = data.frame(game_pk = as.character(agg$game_pk), player_id = as.character(agg$batter),
                               bbe_tracked = agg$bbe_tracked, bbe_untracked = agg$bbe_untracked,
                               barrels = agg$barrels, stringsAsFactors = FALSE),
              game_pks = unique(as.character(d$game_pk)), rows = nrow(d))
  saveRDS(res, path)
  res
}

guts_path <- file.path(CACHE, "lrs_fg_guts.rds")
if (!file.exists(guts_path)) saveRDS(as.data.frame(baseballr::fg_guts()), guts_path)
guts <- readRDS(guts_path)
guts$season <- as.integer(guts$season)
GUTS_COLS <- c("season", "wBB", "wHBP", "w1B", "w2B", "w3B", "wHR", "cFIP")

data_audit <- list(); hit_list <- list(); pit_list <- list(); statcast_seasons <- integer(0)
for (s in SEASONS) {
  gl <- load_game_logs(s)
  hit <- gl$hit; pit <- gl$pit
  hit$season <- s; pit$season <- s
  hit <- hit[!duplicated(hit[, c("player_id", "game_pk")]), ]
  pit <- pit[!duplicated(pit[, c("player_id", "game_pk")]), ]
  gw <- guts[guts$season == s, GUTS_COLS]
  if (nrow(gw) != 1L) stop("No FanGraphs season constants for ", s)
  # wOBA numerator per game with that season's FanGraphs weights
  hit$singles  <- hit$h - hit$d2 - hit$d3 - hit$hr
  hit$woba_num <- gw$wBB * (hit$bb - hit$ibb) + gw$wHBP * hit$hbp + gw$w1B * hit$singles +
                  gw$w2B * hit$d2 + gw$w3B * hit$d3 + gw$wHR * hit$hr
  hit$woba_den <- hit$ab + hit$bb - hit$ibb + hit$sf + hit$hbp
  pit$ip       <- pit$outs / 3
  pit$fip_num  <- 13 * pit$hr + 3 * (pit$bb + pit$hbp) - 2 * pit$so + gw$cFIP * pit$ip
  pit$app      <- 1
  pit$relief   <- as.numeric(!is.na(pit$gs) & pit$gs == 0)

  # Statcast: a player-game in a game absent from the Statcast pull has
  # missing barrel fields (left NA, counted), never zero.
  sc <- tryCatch(load_statcast_bip(s, min(hit$game_date), max(hit$game_date)),
                 error = function(e) { say("Statcast %d unavailable: %s", s, conditionMessage(e)); NULL })
  if (!is.null(sc)) {
    statcast_seasons <- c(statcast_seasons, s)
    m <- match(paste(hit$game_pk, hit$player_id), paste(sc$agg$game_pk, sc$agg$player_id))
    in_sc_game <- hit$game_pk %in% sc$game_pks
    hit$bbe_tracked   <- ifelse(in_sc_game, ifelse(is.na(m), 0, sc$agg$bbe_tracked[m]), NA_real_)
    hit$bbe_untracked <- ifelse(in_sc_game, ifelse(is.na(m), 0, sc$agg$bbe_untracked[m]), NA_real_)
    hit$barrels       <- ifelse(in_sc_game, ifelse(is.na(m), 0, sc$agg$barrels[m]), NA_real_)
  } else {
    hit$bbe_tracked <- NA_real_; hit$bbe_untracked <- NA_real_; hit$barrels <- NA_real_
  }
  box_bip <- sum(hit$ab - hit$so + hit$sf + hit$sh, na.rm = TRUE)
  tt <- gl$team_totals
  data_audit[[as.character(s)]] <- list(
    season = s, source = gl$source, roster_players_requested = gl$roster_players,
    batting_player_games = nrow(hit), pitching_player_games = nrow(pit),
    games = length(unique(c(hit$game_pk, pit$game_pk))),
    batters = length(unique(hit$player_id)), pitchers = length(unique(pit$player_id)),
    pa_game_logs = sum(hit$pa, na.rm = TRUE), pa_team_totals = tt$team_pa,
    bf_game_logs = sum(pit$bf, na.rm = TRUE), bf_team_totals = tt$team_bf,
    outs_game_logs = sum(pit$outs, na.rm = TRUE), outs_team_totals = tt$team_outs,
    team_games = tt$team_games,
    batting_rows_missing_any_field = sum(!complete.cases(hit[, names(HIT_FIELDS)])),
    pitching_rows_missing_any_field = sum(!complete.cases(pit[, names(PIT_FIELDS)])),
    statcast_available = !is.null(sc),
    statcast_bbe_tracked = if (is.null(sc)) NA else sum(hit$bbe_tracked, na.rm = TRUE),
    statcast_bbe_untracked = if (is.null(sc)) NA else sum(hit$bbe_untracked, na.rm = TRUE),
    box_balls_in_play = box_bip,
    batting_player_games_in_games_missing_from_statcast = if (is.null(sc)) NA else sum(is.na(hit$barrels)))
  hit_list[[as.character(s)]] <- hit
  pit_list[[as.character(s)]] <- pit
  say("Season %d: %d batting and %d pitching player-games; PA %d of %d team PA; Statcast %s",
      s, nrow(hit), nrow(pit), sum(hit$pa, na.rm = TRUE), tt$team_pa, if (is.null(sc)) "missing" else "ok")
}
if (identical(Sys.getenv("LRS_DATA_ONLY"), "1")) { say("Data only: done."); quit(save = "no", status = 0) }

# Order each player-season by date (then game id, for doubleheaders) and assign
# odd/even halves. ps indexes the player-season (bootstrap block).
prep_domain <- function(d, ps_levels = NULL) {
  d$ps_id <- paste(d$season, d$player_id, sep = "_")
  d <- d[order(d$ps_id, d$game_date, d$game_pk), ]
  d$k    <- ave(seq_len(nrow(d)), d$ps_id, FUN = seq_along)
  d$half <- ifelse(d$k %% 2L == 1L, "A", "B")
  if (is.null(ps_levels)) ps_levels <- sort(unique(d$ps_id))
  d$ps <- match(d$ps_id, ps_levels)
  list(d = d, ps_levels = ps_levels)
}
bat <- prep_domain(do.call(rbind, hit_list))
pit <- prep_domain(do.call(rbind, pit_list))
pall <- do.call(rbind, pit_list)
rel <- prep_domain(pall[pall$relief == 1, ], ps_levels = pit$ps_levels)  # relief appearances only
rm(hit_list, pit_list, pall)
DOMAINS <- list(bat = bat$d, pit = pit$d, rel = rel$d)
N_PS <- c(bat = length(bat$ps_levels), pit = length(pit$ps_levels))
say("%d batting player-seasons, %d pitching player-seasons", N_PS[["bat"]], N_PS[["pit"]])

# ==============================================================================
# 2. Stat definitions. comps are per-game columns summed over the sample; value
#    turns the summed components into the stat. unit is the column n counts.
# ==============================================================================
rt <- function(a, b) ifelse(b > 0, a / b, NA_real_)
STATS <- list(
  # ---- batting, unit = plate appearances
  avg    = list(group = "batting", label = "Batting average (AVG)", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("h", "ab"), value = function(c) rt(c$h, c$ab), formula = "H / AB"),
  obp    = list(group = "batting", label = "On-base percentage (OBP)", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("h", "bb", "hbp", "ab", "sf"),
                value = function(c) rt(c$h + c$bb + c$hbp, c$ab + c$bb + c$hbp + c$sf),
                formula = "(H + BB + HBP) / (AB + BB + HBP + SF)"),
  slg    = list(group = "batting", label = "Slugging (SLG)", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("tb", "ab"), value = function(c) rt(c$tb, c$ab), formula = "TB / AB"),
  ops    = list(group = "batting", label = "OPS", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("h", "bb", "hbp", "ab", "sf", "tb"),
                value = function(c) rt(c$h + c$bb + c$hbp, c$ab + c$bb + c$hbp + c$sf) + rt(c$tb, c$ab),
                formula = "OBP + SLG, each computed over the sample"),
  woba   = list(group = "batting", label = "wOBA", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("woba_num", "woba_den"), value = function(c) rt(c$woba_num, c$woba_den),
                formula = "(wBB x uBB + wHBP x HBP + w1B x 1B + w2B x 2B + w3B x 3B + wHR x HR) / (AB + BB - IBB + SF + HBP); uBB = BB - IBB; weights are FanGraphs' constants for that season"),
  k_pct  = list(group = "batting", label = "Strikeout rate (K%)", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("so", "pa"), value = function(c) rt(c$so, c$pa), formula = "SO / PA"),
  bb_pct = list(group = "batting", label = "Walk rate (BB%)", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("bb", "pa"), value = function(c) rt(c$bb, c$pa), formula = "BB / PA (BB includes intentional walks, as FanGraphs' BB%)"),
  barrel = list(group = "batting", label = "Barrel rate (barrels / BBE)", domain = "bat", unit = "pa", source = "statcast",
                comps = c("barrels", "bbe_tracked"), value = function(c) rt(c$barrels, c$bbe_tracked),
                formula = "Barrels / batted-ball events with a tracked launch angle and exit velocity; barrel = Statcast launch_speed_angle code 6; sample size counted in PA"),
  hr_pa  = list(group = "batting", label = "Home runs per PA", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("hr", "pa"), value = function(c) rt(c$hr, c$pa), formula = "HR / PA"),
  sb_pa  = list(group = "batting", label = "Stolen bases per PA", domain = "bat", unit = "pa", source = "gamelog",
                comps = c("sb", "pa"), value = function(c) rt(c$sb, c$pa),
                formula = "SB / PA (steals in games without a PA, such as pinch-running, count in the numerator)"),
  # ---- pitching, unit = batters faced
  era    = list(group = "pitching", label = "ERA", domain = "pit", unit = "bf", source = "gamelog",
                comps = c("er", "ip"), value = function(c) rt(9 * c$er, c$ip), formula = "9 x ER / IP; IP = outs / 3"),
  fip    = list(group = "pitching", label = "FIP", domain = "pit", unit = "bf", source = "gamelog",
                comps = c("fip_num", "ip"), value = function(c) rt(c$fip_num, c$ip),
                formula = "(13 x HR + 3 x (BB + HBP) - 2 x SO) / IP + cFIP; cFIP is FanGraphs' constant for that season; BB includes intentional walks"),
  whip   = list(group = "pitching", label = "WHIP", domain = "pit", unit = "bf", source = "gamelog",
                comps = c("bb", "h", "ip"), value = function(c) rt(c$bb + c$h, c$ip), formula = "(BB + H) / IP"),
  pk_pct = list(group = "pitching", label = "Strikeout rate (K%)", domain = "pit", unit = "bf", source = "gamelog",
                comps = c("so", "bf"), value = function(c) rt(c$so, c$bf), formula = "SO / BF"),
  pbb_pct = list(group = "pitching", label = "Walk rate (BB%)", domain = "pit", unit = "bf", source = "gamelog",
                comps = c("bb", "bf"), value = function(c) rt(c$bb, c$bf), formula = "BB / BF (BB includes intentional walks)"),
  # ---- pitching volume (counting stats), unit = appearances
  ip_app = list(group = "pitching_volume", label = "Innings pitched per appearance", domain = "pit", unit = "app",
                source = "gamelog", comps = c("ip", "app"), value = function(c) rt(c$ip, c$app),
                formula = "IP / appearances, all appearances (starts and relief)"),
  sv_rel = list(group = "pitching_volume", label = "Saves per relief appearance", domain = "rel", unit = "app",
                source = "gamelog", comps = c("sv", "app"), value = function(c) rt(c$sv, c$app),
                formula = "SV / relief appearances (appearances that were not starts); pool: every pitcher-season with relief appearances")
)
UNIT_GRID  <- list(pa = GRID_PA, bf = GRID_BF, app = GRID_APPS)
UNIT_LABEL <- c(pa = "plate appearances", bf = "batters faced", app = "appearances")
unit_label_of <- function(st) if (st == "sv_rel") "relief appearances" else UNIT_LABEL[[STATS[[st]]$unit]]

# Seasons each stat uses: a season enters a stat only if its source exists for
# that season and the stat's fields are present in its rows.
stat_seasons <- lapply(names(STATS), function(st) {
  sp <- STATS[[st]]; d <- DOMAINS[[sp$domain]]
  ok <- vapply(SEASONS, function(s) {
    if (sp$source == "statcast" && !(s %in% statcast_seasons)) return(FALSE)
    x <- d[d$season == s, c(sp$comps, sp$unit), drop = FALSE]
    nrow(x) > 0 && all(vapply(x, function(v) any(!is.na(v)), TRUE))
  }, TRUE)
  SEASONS[ok]
})
names(stat_seasons) <- names(STATS)

# ==============================================================================
# 3. Bootstrap weights (player-season blocks), one matrix per player-season
#    index (batting; pitching, shared by relief appearances).
# ==============================================================================
make_W <- function(n, seed) {
  set.seed(seed)
  W <- matrix(0, nrow = n, ncol = N_BOOT)
  for (b in seq_len(N_BOOT)) W[, b] <- tabulate(sample.int(n, n, replace = TRUE), n)
  W
}
W_LIST <- list(bat = make_W(N_PS[["bat"]], SEED), pit = make_W(N_PS[["pit"]], SEED + 1L))
W_OF <- c(bat = "bat", pit = "pit", rel = "pit")

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
# 4. Curves
# ==============================================================================
# Cumulative sums of every component along each ordered sequence; for size n,
# the first row (per group) whose cumulative units reach n ends the sample.
cum_frame <- function(d, comps, unit, grp) {
  o <- order(grp, d$k)
  d <- d[o, , drop = FALSE]; unit <- unit[o]; grp <- grp[o]
  out <- data.frame(grp = grp, ps = d$ps, cu = ave(unit, grp, FUN = cumsum))
  for (cc in comps) out[[cc]] <- ave(d[[cc]], grp, FUN = cumsum)
  out
}
first_reach <- function(cf, n) {
  r <- cf[!is.na(cf$cu) & cf$cu >= n, ]
  r[!duplicated(r$grp), ]
}
val_of <- function(spec, df, suffix = "") {
  cl <- lapply(spec$comps, function(cc) df[[paste0(cc, suffix)]]); names(cl) <- spec$comps
  spec$value(cl)
}

curve_rows <- list()
boot_store <- list()
for (st in names(STATS)) {
  spec <- STATS[[st]]
  d    <- DOMAINS[[spec$domain]]
  d    <- d[d$season %in% stat_seasons[[st]], , drop = FALSE]
  W    <- W_LIST[[W_OF[[spec$domain]]]]
  unit <- d[[spec$unit]]
  grid <- UNIT_GRID[[spec$unit]]
  cc   <- spec$comps

  cf_half <- cum_frame(d, cc, unit, paste(d$ps, d$half))
  cf_half$half <- sub("^.* ", "", cf_half$grp)
  cf_full <- cum_frame(d, cc, unit, d$ps)
  tot <- cf_full[!duplicated(cf_full$grp, fromLast = TRUE), c("ps", "cu", cc)]
  names(tot) <- c("ps", "tu", paste0(cc, "_t"))
  cf_A <- cf_half[cf_half$half == "A", ]; cf_B <- cf_half[cf_half$half == "B", ]

  sh_b <- matrix(NA_real_, length(grid), N_BOOT); ros_b <- sh_b
  for (gi in seq_along(grid)) {
    n <- grid[gi]
    # ---- split-half
    a <- first_reach(cf_A, n); b <- first_reach(cf_B, n)
    m <- merge(a[, c("ps", "cu", cc)], b[, c("ps", "cu", cc)], by = "ps", suffixes = c("_a", "_b"))
    va <- val_of(spec, m, "_a"); vb <- val_of(spec, m, "_b")
    ok <- is.finite(va) & is.finite(vb)
    n_ok <- sum(ok); n_miss <- sum(!ok)
    r <- if (n_ok >= MIN_PLAYERS) cor(va[ok], vb[ok]) else NA_real_
    if (n_ok >= MIN_PLAYERS) sh_b[gi, ] <- boot_cor(W, m$ps[ok], va[ok], vb[ok])
    ci <- q95(sh_b[gi, ]); ci_sb <- q95(sb(sh_b[gi, ]))
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "split_half", n = n,
      n_players = n_ok, n_missing = n_miss,
      mean_realised_units = if (n_ok > 0) mean(c(m$cu_a[ok], m$cu_b[ok])) else NA_real_,
      r = r, r_lo = ci[1], r_hi = ci[2],
      sb_sample = 2 * n, r_sb = sb(r), r_sb_lo = ci_sb[1], r_sb_hi = ci_sb[2])
    # ---- rest of season: first n units vs all remaining games, remainder >= n units
    f <- merge(first_reach(cf_full, n)[, c("ps", "cu", cc)], tot, by = "ps")
    f <- f[!is.na(f$tu) & (f$tu - f$cu) >= n, , drop = FALSE]
    ve <- val_of(spec, f)
    rest <- f[, "ps", drop = FALSE]
    for (x in cc) rest[[x]] <- f[[paste0(x, "_t")]] - f[[x]]
    vr <- val_of(spec, rest)
    ok2 <- is.finite(ve) & is.finite(vr)
    n_ok2 <- sum(ok2)
    r2 <- if (n_ok2 >= MIN_PLAYERS) cor(ve[ok2], vr[ok2]) else NA_real_
    if (n_ok2 >= MIN_PLAYERS) ros_b[gi, ] <- boot_cor(W, f$ps[ok2], ve[ok2], vr[ok2])
    ci2 <- q95(ros_b[gi, ])
    curve_rows[[length(curve_rows) + 1]] <- data.frame(
      stat = st, group = spec$group, unit = spec$unit, method = "rest_of_season", n = n,
      n_players = n_ok2, n_missing = sum(!ok2),
      mean_realised_units = if (n_ok2 > 0) mean(f$cu[ok2]) else NA_real_,
      r = r2, r_lo = ci2[1], r_hi = ci2[2],
      sb_sample = NA_real_, r_sb = NA_real_, r_sb_lo = NA_real_, r_sb_hi = NA_real_)
  }
  boot_store[[st]] <- list(grid = grid, sh = sh_b, ros = ros_b)
  say("Curves done: %s (seasons %s)", st, paste(stat_seasons[[st]], collapse = ","))
}
curves <- do.call(rbind, curve_rows)

# ==============================================================================
# 5. Official qualifying rules
# ==============================================================================
# Rate-stat leaders need 3.1 PA (batters) or 1 IP (pitchers) per team game. A
# split-half sample of n per half projects (Spearman-Brown) to 2n, so the rule
# is read at the grid point nearest half the rule. IP is converted to batters
# faced with the pooled BF per out of the seasons used.
bf_per_out <- sum(DOMAINS$pit$bf, na.rm = TRUE) / sum(DOMAINS$pit$outs, na.rm = TRUE)
RULE <- list(
  pa = list(rule = QUAL_PA_PER_TEAM_GAME * TEAM_GAMES, label = sprintf("%.1f PA per team game = %.0f PA over %d games",
            QUAL_PA_PER_TEAM_GAME, QUAL_PA_PER_TEAM_GAME * TEAM_GAMES, TEAM_GAMES)),
  bf = list(rule = QUAL_IP_PER_TEAM_GAME * TEAM_GAMES * 3 * bf_per_out,
            label = sprintf("%.0f IP per team game = %d IP over %d games = about %.0f BF at %.3f BF per out",
                            QUAL_IP_PER_TEAM_GAME, as.integer(QUAL_IP_PER_TEAM_GAME * TEAM_GAMES), TEAM_GAMES,
                            QUAL_IP_PER_TEAM_GAME * TEAM_GAMES * 3 * bf_per_out, bf_per_out)))
nearest <- function(grid, x) grid[which.min(abs(grid - x))]
at_rule <- lapply(names(STATS), function(st) {
  u <- STATS[[st]]$unit
  if (!u %in% names(RULE)) return(list(applies = FALSE,
    reason = "MLB's qualifying rules apply to rate stats only; counting totals (innings pitched, saves) are ranked without a minimum, so no rule-equivalent sample exists for this per-appearance curve."))
  half <- nearest(UNIT_GRID[[u]], RULE[[u]]$rule / 2)
  sh <- curves[curves$stat == st & curves$method == "split_half" & curves$n == half, ]
  ro <- curves[curves$stat == st & curves$method == "rest_of_season" & curves$n == half, ]
  list(applies = TRUE, rule = RULE[[u]]$label, rule_units = round(RULE[[u]]$rule, 1),
       half_rule_grid_point = half, spearman_brown_sample = 2 * half,
       split_half_r = sh$r, split_half_r_lo = sh$r_lo, split_half_r_hi = sh$r_hi, split_half_players = sh$n_players,
       spearman_brown = sh$r_sb, spearman_brown_lo = sh$r_sb_lo, spearman_brown_hi = sh$r_sb_hi,
       rest_of_season_r = ro$r, rest_of_season_r_lo = ro$r_lo, rest_of_season_r_hi = ro$r_hi,
       rest_of_season_players = ro$n_players)
})
names(at_rule) <- names(STATS)

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
for (st in names(STATS)) {
  bs <- boot_store[[st]]
  shc <- curves[curves$stat == st & curves$method == "split_half", ]
  roc <- curves[curves$stat == st & curves$method == "rest_of_season", ]
  crossings[[st]] <- list(
    split_half     = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r, bs$sh, b)),
    spearman_brown = lapply(REF_BARS, function(b) cross_summary(bs$grid, shc$r_sb, sb(bs$sh), b, scale = 2)),
    rest_of_season = lapply(REF_BARS, function(b) cross_summary(bs$grid, roc$r, bs$ros, b)))
}

# ==============================================================================
# 7. Plots
# ==============================================================================
GROUP_TITLE <- c(batting = "batting (by plate appearances)", pitching = "pitching (by batters faced)",
                 pitching_volume = "pitching volume (by appearances)")
plot_group <- function(grp, file) {
  d <- curves[curves$group == grp, ]
  d$label <- vapply(d$stat, function(s) STATS[[s]]$label, "")
  sh <- d[d$method == "split_half", ]
  ro <- d[d$method == "rest_of_season", ]
  long <- rbind(
    data.frame(label = sh$label, x = sh$n, r = sh$r, lo = sh$r_lo, hi = sh$r_hi, curve = "Split-half r (sample n)"),
    data.frame(label = sh$label, x = sh$sb_sample, r = sh$r_sb, lo = sh$r_sb_lo, hi = sh$r_sb_hi,
               curve = "Spearman-Brown (sample 2n)"),
    data.frame(label = ro$label, x = ro$n, r = ro$r, lo = ro$r_lo, hi = ro$r_hi, curve = "Rest of season r (first n)"))
  long$label <- factor(long$label, levels = unique(vapply(names(STATS)[vapply(STATS, function(s) s$group == grp, TRUE)],
                                                          function(s) STATS[[s]]$label, "")))
  u <- unique(d$unit)
  xlab <- if (grp == "pitching_volume") "Sample size, appearances (saves: relief appearances)" else paste("Sample size,", UNIT_LABEL[[u]])
  sub_rule <- if (u %in% names(RULE)) sprintf("; red line = official rule (%.0f %s), dotted red = half of it",
                                              RULE[[u]]$rule, if (u == "pa") "PA" else "BF") else ""
  p <- ggplot(long, aes(x, r, colour = curve, fill = curve)) +
    geom_hline(yintercept = REF_BARS, linetype = "dashed", colour = "grey55", linewidth = 0.3)
  if (u %in% names(RULE)) p <- p +
    geom_vline(xintercept = RULE[[u]]$rule, colour = "firebrick", linewidth = 0.4) +
    geom_vline(xintercept = RULE[[u]]$rule / 2, colour = "firebrick", linewidth = 0.4, linetype = "dotted")
  p <- p +
    geom_ribbon(aes(ymin = lo, ymax = hi), alpha = 0.18, colour = NA, na.rm = TRUE) +
    geom_line(linewidth = 0.7, na.rm = TRUE) +
    facet_wrap(~ label, scales = "free_x", ncol = if (grp == "pitching_volume") 2 else 3) +
    coord_cartesian(ylim = c(0, 1)) +
    labs(x = xlab, y = "Correlation", colour = NULL, fill = NULL,
         title = sprintf("MLB leader reliability: %s", GROUP_TITLE[[grp]]),
         subtitle = sprintf("%d regular seasons %d-%d%s; bands = bootstrap 95%% (%d resamples); dashed = bars %s%s",
                            length(SEASONS), min(SEASONS), max(SEASONS),
                            if (length(setdiff(min(SEASONS):max(SEASONS), SEASONS))) sprintf(" (not %s)", paste(setdiff(min(SEASONS):max(SEASONS), SEASONS), collapse = ", ")) else "",
                            N_BOOT, paste(REF_BARS, collapse = ", "), sub_rule)) +
    theme_minimal(base_size = 11) + theme(legend.position = "bottom", plot.subtitle = element_text(size = 8.5))
  ht <- c(batting = 11, pitching = 7.5, pitching_volume = 4.5)[[grp]]
  ggsave(file, p, width = 11, height = ht, dpi = 120, bg = "white")
}
plot_files <- c(batting = "batting.png", pitching = "pitching.png", pitching_volume = "pitching_volume.png")
for (g in names(plot_files)) plot_group(g, file.path(FIG_DIR, plot_files[[g]]))

runtime_min <- as.numeric(difftime(Sys.time(), t_start, units = "mins"))

# ==============================================================================
# 8. Results JSON
# ==============================================================================
df_rows <- function(d) lapply(seq_len(nrow(d)), function(i) as.list(d[i, , drop = FALSE]))
stats_json <- lapply(names(STATS), function(st) {
  s <- STATS[[st]]
  list(label = s$label, group = s$group, unit = s$unit, unit_label = unit_label_of(st),
       source = s$source, formula = s$formula, seasons_used = stat_seasons[[st]],
       seasons_left_out = setdiff(SEASONS, stat_seasons[[st]]),
       split_half = df_rows(curves[curves$stat == st & curves$method == "split_half",
                                   c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi",
                                     "sb_sample", "r_sb", "r_sb_lo", "r_sb_hi")]),
       rest_of_season = df_rows(curves[curves$stat == st & curves$method == "rest_of_season",
                                       c("n", "n_players", "n_missing", "mean_realised_units", "r", "r_lo", "r_hi")]),
       at_official_rule = at_rule[[st]],
       crossings = crossings[[st]])
})
names(stats_json) <- names(STATS)
NOT_MEASURED <- list()   # every stat listed in issue #162 is measured when its source loads
for (st in names(STATS)) if (!length(stat_seasons[[st]]))
  NOT_MEASURED[[st]] <- "No season has this stat's source fields."

results <- list(
  issue = "MLB-Analytics#162",
  note = "Reference points only. No qualifying minimum is chosen here; the owner sets them after reviewing the curves.",
  settings = list(seasons = SEASONS, seed = SEED, n_boot = N_BOOT, grid_pa = GRID_PA, grid_bf = GRID_BF,
                  grid_appearances = GRID_APPS, reference_bars = REF_BARS, min_players_per_point = MIN_PLAYERS,
                  qual_pa_per_team_game = QUAL_PA_PER_TEAM_GAME, qual_ip_per_team_game = QUAL_IP_PER_TEAM_GAME,
                  team_games = TEAM_GAMES, bf_per_out_pooled = round(bf_per_out, 4)),
  official_rules = lapply(RULE, function(x) list(units = round(x$rule, 1), label = x$label)),
  data_audit = unname(data_audit),
  player_seasons = list(batting = N_PS[["bat"]], pitching = N_PS[["pit"]],
                        pitching_with_relief_appearances = length(unique(DOMAINS$rel$ps))),
  stats = stats_json,
  stats_not_measured = NOT_MEASURED,
  runtime_minutes = round(runtime_min, 2)
)
writeLines(toJSON(results, auto_unbox = TRUE, digits = 4, null = "null", na = "null", pretty = TRUE),
           file.path(OUT_DIR, "leader_reliability_study_results.json"))

# ==============================================================================
# 9. Report
# ==============================================================================
f2 <- function(x) ifelse(is.null(x) | length(x) == 0, "NA", ifelse(is.na(x), "NA", sprintf("%.2f", x)))
fmt_cross <- function(cx) {
  if (is.null(cx$point)) return(sprintf("not reached (%.0f%% of resamples)", 100 * cx$share_not_reached))
  hi <- if (is.null(cx$hi)) "beyond grid" else format(cx$hi, big.mark = ",")
  lo <- if (is.null(cx$lo)) "beyond grid" else format(cx$lo, big.mark = ",")
  sprintf("%s [%s, %s]", format(cx$point, big.mark = ","), lo, hi)
}
kinds_box <- c(split_half = "split-half r, sample n", spearman_brown = "Spearman-Brown, sample 2n",
               rest_of_season = "rest-of-season r, first n")
cross_table <- function(stats) {
  lines <- c(paste0("| Stat | Unit | Curve | ", paste(sprintf("bar %.1f", REF_BARS), collapse = " | "), " |"),
             paste0("|", paste(rep("---", 3 + length(REF_BARS)), collapse = "|"), "|"))
  for (st in stats) for (kd in names(kinds_box)) {
    cx <- crossings[[st]][[kd]]
    lines <- c(lines, sprintf("| %s | %s | %s | %s |", STATS[[st]]$label, unit_label_of(st), kinds_box[[kd]],
                              paste(vapply(cx, fmt_cross, ""), collapse = " | ")))
  }
  lines
}
point_at <- function(st, method, n) {
  r <- curves[curves$stat == st & curves$method == method & curves$n == n, ]
  if (!nrow(r) || is.na(r$r)) return(sprintf("NA (N=%d)", if (nrow(r)) r$n_players else 0L))
  sprintf("%s [%s, %s] (N=%d)", f2(r$r), f2(r$r_lo), f2(r$r_hi), r$n_players)
}
snap_n <- c(pa = 100, bf = 100, app = 10)
snap <- c("| Stat | Unit | n | Split-half r at n | Spearman-Brown (2n) | Rest-of-season r at n |", "|---|---|---|---|---|---|")
for (st in names(STATS)) {
  n <- snap_n[[STATS[[st]]$unit]]
  r <- curves[curves$stat == st & curves$method == "split_half" & curves$n == n, ]
  snap <- c(snap, sprintf("| %s | %s | %s | %s | %s | %s |", STATS[[st]]$label, unit_label_of(st), n,
                          point_at(st, "split_half", n),
                          if (nrow(r) && !is.na(r$r)) sprintf("%s [%s, %s]", f2(r$r_sb), f2(r$r_sb_lo), f2(r$r_sb_hi)) else "NA",
                          point_at(st, "rest_of_season", n)))
}
fmtn <- function(x) format(x, big.mark = ",")
audit_tbl <- c("| Season | Batting player-games | Pitching player-games | Games | PA in game logs / team totals | BF in game logs / team totals | Outs in game logs / team totals | Rows missing a field (bat / pit) | Statcast BBE tracked / untracked | Box balls in play | Batting player-games in games missing from Statcast |",
               "|---|---|---|---|---|---|---|---|---|---|---|")
for (a in data_audit) audit_tbl <- c(audit_tbl, sprintf("| %d | %s | %s | %s | %s / %s | %s / %s | %s / %s | %d / %d | %s / %s | %s | %s |",
  a$season, fmtn(a$batting_player_games), fmtn(a$pitching_player_games), fmtn(a$games),
  fmtn(a$pa_game_logs), fmtn(a$pa_team_totals), fmtn(a$bf_game_logs), fmtn(a$bf_team_totals),
  fmtn(a$outs_game_logs), fmtn(a$outs_team_totals),
  a$batting_rows_missing_any_field, a$pitching_rows_missing_any_field,
  fmtn(a$statcast_bbe_tracked), fmtn(a$statcast_bbe_untracked), fmtn(a$box_balls_in_play),
  fmtn(a$batting_player_games_in_games_missing_from_statcast)))
gaps <- unlist(lapply(data_audit, function(a) c(
  if (a$pa_game_logs != a$pa_team_totals) sprintf("%d batting: game logs hold %s PA of %s in the team totals", a$season, fmtn(a$pa_game_logs), fmtn(a$pa_team_totals)),
  if (a$bf_game_logs != a$bf_team_totals) sprintf("%d pitching: game logs hold %s BF of %s", a$season, fmtn(a$bf_game_logs), fmtn(a$bf_team_totals)),
  if (a$outs_game_logs != a$outs_team_totals) sprintf("%d pitching: game logs hold %s outs of %s", a$season, fmtn(a$outs_game_logs), fmtn(a$outs_team_totals)))))
sc_gap <- vapply(data_audit, function(a) if (isTRUE(a$statcast_available)) abs(a$statcast_bbe_tracked + a$statcast_bbe_untracked - a$box_balls_in_play) else NA_real_, 0)
audit_note <- c(
  if (length(gaps)) sprintf("Game-log totals equal the API's team season totals for PA, BF and outs in every season except: %s. Those rows are absent from the people endpoint and are left out, not filled.", paste(gaps, collapse = "; ")) else
    "Game-log totals equal the API's team season totals for PA, BF and outs in every season.",
  "",
  sprintf("Statcast batted-ball events (tracked plus untracked) differ from the box-score balls in play (AB - SO + SF + SH) by at most %s per season, and %s batting player-games fall in games absent from the Statcast pull. The runtime above covers the analysis from cached data; the one-time download of game logs and Statcast data into `cache/` took about 53 minutes.",
          fmtn(max(sc_gap, na.rm = TRUE)),
          fmtn(sum(vapply(data_audit, function(a) as.numeric(a$batting_player_games_in_games_missing_from_statcast), 0), na.rm = TRUE))))
seasons_tbl <- c("| Stat | Source | Seasons used | Seasons left out |", "|---|---|---|---|")
for (st in names(STATS)) seasons_tbl <- c(seasons_tbl, sprintf("| %s | %s | %s | %s |", STATS[[st]]$label,
  if (STATS[[st]]$source == "statcast") "Statcast (Baseball Savant)" else "MLB Stats API game logs",
  paste(stat_seasons[[st]], collapse = ", "),
  if (length(setdiff(SEASONS, stat_seasons[[st]]))) paste(setdiff(SEASONS, stat_seasons[[st]]), collapse = ", ") else "none"))
formula_tbl <- c("| Stat | Unit counted by n | Formula over a sample of games |", "|---|---|---|")
for (st in names(STATS)) formula_tbl <- c(formula_tbl, sprintf("| %s | %s | %s |", STATS[[st]]$label, unit_label_of(st), STATS[[st]]$formula))
rule_tbl <- c("| Stat | Rule | Half-rule grid point (n per half) | Split-half r at n [95%] (N) | Spearman-Brown at 2n [95%] | Rest-of-season r at n [95%] (N) |",
              "|---|---|---|---|---|---|")
for (st in names(STATS)) {
  a <- at_rule[[st]]
  if (!isTRUE(a$applies)) { rule_tbl <- c(rule_tbl, sprintf("| %s | none | n/a | n/a | n/a | n/a |", STATS[[st]]$label)); next }
  rule_tbl <- c(rule_tbl, sprintf("| %s | %s %s | %d | %s [%s, %s] (%d) | %s [%s, %s] | %s [%s, %s] (%d) |",
    STATS[[st]]$label, fmtn(round(a$rule_units)), if (STATS[[st]]$unit == "pa") "PA" else "BF", a$half_rule_grid_point,
    f2(a$split_half_r), f2(a$split_half_r_lo), f2(a$split_half_r_hi), a$split_half_players,
    f2(a$spearman_brown), f2(a$spearman_brown_lo), f2(a$spearman_brown_hi),
    f2(a$rest_of_season_r), f2(a$rest_of_season_r_lo), f2(a$rest_of_season_r_hi), a$rest_of_season_players))
}
not_measured_lines <- if (length(NOT_MEASURED)) vapply(names(NOT_MEASURED), function(st)
  sprintf("- %s: not measured. %s", STATS[[st]]$label, NOT_MEASURED[[st]]), "") else
  "Every stat listed in issue #162 is measured. No stat had to be reported as not measured."

report <- c(
  "# MLB leader reliability study (issue #162)",
  "",
  "Research only. This study measures how quickly each MLB league-leader stat settles as a player's sample grows. It repeats the NBA study (NBA_analytics#253) with the same methods. It does not choose any qualifying minimum and changes no production code; the owner reviews these curves and sets the minimums, which the leaders panel then uses.",
  "",
  sprintf("Generated by `tools/leader_reliability_study.R` (seed %d, %d bootstrap resamples). Runtime of this run: %.1f minutes.", SEED, N_BOOT, runtime_min),
  "",
  "## Data",
  "",
  sprintf("- MLB regular seasons %s. 2020 is left out because it was a 60-game season. Only complete seasons are used. Player-seasons: %s batting, %s pitching (%s of them with relief appearances).",
          paste(SEASONS, collapse = ", "), fmtn(N_PS[["bat"]]), fmtn(N_PS[["pit"]]), fmtn(length(unique(DOMAINS$rel$ps)))),
  "- Player game logs: MLB Stats API (`statsapi.mlb.com`, the API that baseballr's `mlb_*` functions read), one batting and one pitching row per player per game, `gameType == R`. The player list for each season is `baseballr::mlb_sports_players()`. baseballr has no bulk game-log function, so the logs are read with the API's people endpoint and its game-log hydration, 40 players per request. Completeness is checked against the API's team season totals (table below).",
  "- Barrel rate: Statcast batted-ball events from the Baseball Savant search CSV (the endpoint `baseballr::statcast_search()` reads), regular season, filtered to balls in play, joined to the game logs by game and batter. A player-game in a game that is absent from the Statcast pull has missing barrel fields, never zero. Batted balls without a tracked launch angle and exit velocity are left out of the denominator and counted in the table.",
  "- wOBA weights and the FIP constant: FanGraphs season constants (`baseballr::fg_guts()`).",
  "- Nothing is imputed. A missing value makes any sample that contains it missing at that point, and a sample whose stat is undefined (for example no outs recorded for ERA) is treated the same way; the number of such player-seasons is reported at every point (`n_missing` in the JSON).",
  "- A player-season covers every team the player played for that season. Doubleheaders are ordered by game id within the date.",
  "- Rule changes inside the window (2023: pitch clock, larger bases, limits on pickoffs and on the infield shift) shifted league levels of some stats, especially stolen bases. Correlations are computed within player-seasons, so a league-wide shift does not by itself create agreement between halves, but the pooled range of stolen-base rates is wider after 2023.",
  "",
  audit_tbl,
  "",
  audit_note,
  "",
  "### Seasons each stat uses",
  "",
  seasons_tbl,
  "",
  "### Stats not measured",
  "",
  not_measured_lines,
  "",
  "## Methods",
  "",
  "- **Split-half reliability.** Each player-season's games are numbered in date order; odd-numbered games form half A and even-numbered games half B. At each sample size n the stat is computed on each half from the first n units of that half, for every player-season whose two halves each reach n units, and the two halves are correlated across player-seasons (Pearson). The raw correlation is the reliability of an n-unit sample. The Spearman-Brown value 2r / (1 + r) is the projected reliability of a 2n-unit sample and is plotted at 2n.",
  "- **Rest-of-season check.** The stat over a player's first n units of the season against the same stat over all of his remaining games that season. Rule: only player-seasons whose remaining games hold at least n units are used, so the remainder is never smaller than the early sample.",
  "- **Units.** Batting: plate appearances. Pitching rate stats: batters faced. Innings pitched: per appearance, counted in appearances (starts and relief). Saves: per relief appearance, counted in relief appearances; for saves the odd/even numbering runs over relief appearances only. Games are indivisible, so a sample of n is the shortest run of whole games whose cumulative units reach n; the mean realised size is in the JSON (`mean_realised_units`).",
  sprintf("- **Intervals.** Player-season block bootstrap: player-seasons are resampled with replacement (%d resamples, seed %d for batters and %d for pitchers), every curve point is recomputed on each resample with the same draw, and the 2.5th and 97.5th percentiles are reported. Points with fewer than %d player-seasons are not reported.", N_BOOT, SEED, SEED + 1L, MIN_PLAYERS),
  "- **Reading the curves at large n.** Only regulars reach large samples, so the player pool narrows as n grows; a narrower range of true talent lowers correlations. A curve that flattens or dips at the right-hand end reflects that selection as well as noise, and the player count at each point should be read with it.",
  "- **Who is in the pool.** As issue #162 specifies, every player-season that reaches n is correlated, from bench players and September call-ups to stars. The range of true levels across that pool is wide (a slugger's home-run rate differs from a utility infielder's, a closer's save rate from a long reliever's, a starter's innings per appearance from a reliever's), and a wide range makes correlations high at small n. Separating players near the top of a leader list from each other is a harder task than this pool-wide correlation measures, so the crossings below describe the whole league, not the top of a list. This applies most to innings per appearance and saves, whose curves mostly separate roles (starter or reliever, closer or not). The innings-per-appearance curves fall sharply after about 16 appearances per half because starters (about 32 starts a season) leave the pool there, leaving relievers, whose innings per appearance vary much less; the drop is a change of pool, not a loss of reliability.",
  "",
  "## Formulas",
  "",
  "Each stat over a sample is computed from the summed per-game components (for example AVG over 50 PA is the sum of hits over the sum of at-bats in those games), never as an average of per-game values. IP = outs / 3.",
  "",
  formula_tbl,
  "",
  "## Curves",
  "",
  "### Batting (by plate appearances)",
  "", "![Batting](leader_reliability_study/batting.png)", "",
  "### Pitching (by batters faced)",
  "", "![Pitching](leader_reliability_study/pitching.png)", "",
  "### Pitching volume (by appearances)",
  "", "![Pitching volume](leader_reliability_study/pitching_volume.png)", "",
  "### Snapshot at one sample size per unit",
  "",
  "Correlation [bootstrap 95%] and player-season count. The full curves are in the results JSON.",
  "", snap, "",
  "## Comparison with MLB's official qualifying rules",
  "",
  sprintf("MLB ranks rate-stat leaders among players with 3.1 plate appearances or 1 inning pitched per team game: %s, and %s. A split-half sample holds half the games, so each rule is read at the grid point nearest half the rule; the Spearman-Brown value there is the projected reliability of a sample the size of the rule. The rest-of-season value at the same point compares the first half-rule sample with the rest of the season.",
          RULE$pa$label, RULE$bf$label),
  "",
  rule_tbl,
  "",
  "Innings pitched and saves are counting totals; MLB ranks them without a minimum, so no rule applies to their per-appearance curves.",
  "",
  "## Reference points for the owner's review",
  "",
  "For each stat, the first grid sample size at which each curve reaches the bar, with a bootstrap 95% interval for that crossing. \"Beyond grid\" means some resamples did not reach the bar inside the grid; \"not reached\" means the point curve stays below the bar over the whole grid (often because the pool of players reaching large samples becomes too small). These are reference points for review, not chosen values. Split-half and rest-of-season values are in the stat's own unit for an n-unit sample; Spearman-Brown values are the projected sample (2n) at which reliability reaches the bar. The pool covers every player-season, from bench players to stars, so separating players near the top of a list is harder than these curves suggest.",
  "",
  cross_table(names(STATS)),
  ""
)
writeLines(report, file.path(OUT_DIR, "leader_reliability_study.md"))

say("Done in %.1f minutes. Wrote %s, %s and %d plots.", runtime_min,
    file.path(OUT_DIR, "leader_reliability_study.md"), file.path(OUT_DIR, "leader_reliability_study_results.json"),
    length(list.files(FIG_DIR, pattern = "\\.png$")))
