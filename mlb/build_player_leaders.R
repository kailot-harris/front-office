# ==============================================================================
# build_player_leaders.R - MLB league leaders panel data layer (MLB-Analytics#163)
#
# Writes web/public/data/player_leaders.json, read by the leaders panel at the
# top of /players. One card per stat, grouped as batting and pitching; each
# card carries the top 10 for All, IF, OF, C / DH, Starters and Relievers,
# its own through date and a noise-note flag where applicable.
#
# INPUTS (real data only; no synthetic fill-ins or prior-season fallback):
#   - MLB Stats API regular-season player game logs (statsapi.mlb.com,
#     gameType=R), cached in cache/leaders_gamelogs_<season>.rds
#   - MLB Stats API schedule & teams (regular-season team games played)
#   - FanGraphs season constants (wOBA weights & cFIP), cached in
#     cache/leaders_fg_guts.rds
#   - Statcast batted-ball events (Baseball Savant search CSV, balls in play),
#     cached in cache/leaders_statcast_bip_<season>.rds (for Barrel%)
#
# QUALIFYING (config.R, LEADERS_*): every minimum is the owner's full-season
# (162-game) bar and scales with the player's CURRENT team's games played:
#   required = minimum * team_games_played / LEADERS_FULL_SEASON_GAMES.
# A traded player's sample counts every game he played this season, for any
# team, and is held to the bar of the team he played for most recently.
#
# RANKING: highest leads, except batting K%, pitching ERA, FIP, WHIP, and
# pitching BB%, where the lowest leads. Ties share a rank.
#
# EVENING REFRESH: the payload carries `season_totals` (per-player sums of
# every numerator and denominator, team games played, FanGraphs season
# constants, and the game_ids included), so tools/refresh_live_results.R can
# add a night's regular-season box scores from MLB Stats API without any cache
# and rebuild the box-score cards with the same functions. This file therefore
# loads jsonlite and base R only.
#
# Set MLB_SKIP_STAGE_AUTORUN=1 to source this file for its definitions only.
# ==============================================================================

.LEADERS_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  ofile <- NULL
  for (fr in sys.frames()) {
    cand <- tryCatch(get("ofile", envir = fr, inherits = FALSE), error = function(e) NULL)
    if (is.character(cand) && length(cand) == 1L && nzchar(cand)) ofile <- cand
  }
  base <- if (!is.null(ofile)) dirname(ofile)
          else if (length(f) == 1L && nzchar(f) && grepl("build_player_leaders\\.R$", f)) dirname(f)
          else getwd()
  normalizePath(base, winslash = "/", mustWork = FALSE)
})

suppressPackageStartupMessages(library(jsonlite))

if (!exists("WEB_JSON_PLAYER_LEADERS") || !exists("LEADERS_STUDY_SOURCE_COMMIT")) {
  source(file.path(.LEADERS_DIR, "config.R"), local = TRUE)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

# ------------------------------------------------------------------------------
# Definitions
# ------------------------------------------------------------------------------
PL_SCHEMA_VERSION <- 1L
PL_TOP_N <- 10L
PL_POSITIONS <- c("all", "IF", "OF", "C_DH", "SP", "RP")
PL_POSITION_LABELS <- c(
  all  = "All",
  IF   = "IF",
  OF   = "OF",
  C_DH = "C / DH",
  SP   = "Starters",
  RP   = "Relievers"
)
PL_GROUPS <- list(
  list(key = "batting",  label = "Batting"),
  list(key = "pitching", label = "Pitching")
)
PL_NOT_ENOUGH <- "Not enough games yet"
PL_NOISE_TEXT <- "Mostly noise at season sample sizes: treat the order as rough."

# MLB Stats API team abbreviations -> site canonical codes
PL_ABBR_FIXUPS <- c(
  AZ  = "ARI",
  CWS = "CHW",
  WSN = "WSH",
  OAK = "ATH",
  KCR = "KC",
  SDP = "SD",
  SFG = "SF",
  TBR = "TB"
)
pl_norm_abbr <- function(x) {
  x <- toupper(trimws(as.character(x)))
  hit <- !is.na(x) & x %in% names(PL_ABBR_FIXUPS)
  x[hit] <- PL_ABBR_FIXUPS[x[hit]]
  x
}

# Listed primary position -> hitter filter group (IF, OF, C_DH).
pl_batter_position_group <- function(pos) {
  p <- toupper(trimws(as.character(pos)))
  out <- rep(NA_character_, length(p))
  out[p %in% c("1B", "2B", "3B", "SS", "IF")] <- "IF"
  out[p %in% c("LF", "CF", "RF", "OF")]       <- "OF"
  out[p %in% c("C", "DH")]                    <- "C_DH"
  out
}

# Pitcher role from appearances started (50%+ starts = SP, else RP).
pl_pitcher_role_group <- function(gs, app) {
  out <- rep(NA_character_, length(app))
  ok <- !is.na(app) & app > 0 & !is.na(gs)
  out[ok & (gs / app >= 0.5)] <- "SP"
  out[ok & (gs / app <  0.5)] <- "RP"
  out
}

PL_BAT_ID_FIELDS <- c("player_id", "player", "team_id", "team", "position",
                      "last_game_date", "last_game_id")
PL_BAT_SUM_FIELDS <- c("games", "pa", "ab", "h", "d2", "d3", "hr", "bb", "ibb",
                       "hbp", "sf", "so", "sb", "tb", "woba_num", "woba_den",
                       "barrels", "bbe_tracked", "sc_missing_games")

PL_PIT_ID_FIELDS <- c("player_id", "player", "team_id", "team", "position",
                      "last_game_date", "last_game_id")
PL_PIT_SUM_FIELDS <- c("app", "gs", "relief_app", "bf", "outs", "ip", "h", "bb",
                       "hbp", "so", "hr", "er", "sv", "fip_num")

.pl_stat <- function(key, label, group, kind, format, unit, min, lower = FALSE,
                     noise = FALSE, num = NULL, den = NULL) {
  list(key = key, label = label, group = group, kind = kind, format = format,
       unit = unit, min = min, lower_is_better = lower, noise = noise,
       num = num, den = den)
}
.ones <- function(t) rep(1, nrow(t))

PL_STATS <- list(
  # Batting (10 stats)
  .pl_stat("avg",  "Batting average (AVG)",   "batting", "rate", "avg", "pa", "LEADERS_MIN_PA_AVG",  noise = TRUE,
           num = function(t) t$h, den = function(t) t$ab),
  .pl_stat("obp",  "On-base % (OBP)",         "batting", "rate", "avg", "pa", "LEADERS_MIN_PA_OBP",  noise = TRUE,
           num = function(t) t$h + t$bb + t$hbp, den = function(t) t$ab + t$bb + t$hbp + t$sf),
  .pl_stat("slg",  "Slugging % (SLG)",        "batting", "rate", "avg", "pa", "LEADERS_MIN_PA_SLG",  noise = TRUE,
           num = function(t) t$tb, den = function(t) t$ab),
  .pl_stat("ops",  "OPS",                     "batting", "rate", "avg", "pa", "LEADERS_MIN_PA_OPS",  noise = TRUE,
           num = function(t) {
             obp_d <- t$ab + t$bb + t$hbp + t$sf
             obp <- ifelse(obp_d > 0, (t$h + t$bb + t$hbp) / obp_d, NA_real_)
             slg <- ifelse(t$ab > 0, t$tb / t$ab, NA_real_)
             obp + slg
           }, den = .ones),
  .pl_stat("hr",   "Home runs (HR)",          "batting", "counting", "int", "pa", "LEADERS_MIN_PA_HR",
           num = function(t) t$hr, den = .ones),
  .pl_stat("sb",   "Stolen bases (SB)",       "batting", "counting", "int", "pa", "LEADERS_MIN_PA_SB",
           num = function(t) t$sb, den = .ones),
  .pl_stat("woba", "wOBA",                    "batting", "rate", "avg", "pa", "LEADERS_MIN_PA_WOBA", noise = TRUE,
           num = function(t) t$woba_num, den = function(t) t$woba_den),
  .pl_stat("k_pct", "Strikeout rate (K%)",    "batting", "rate", "pct", "pa", "LEADERS_MIN_PA_K_PCT", lower = TRUE,
           num = function(t) t$so, den = function(t) t$pa),
  .pl_stat("bb_pct", "Walk rate (BB%)",       "batting", "rate", "pct", "pa", "LEADERS_MIN_PA_BB_PCT",
           num = function(t) t$bb, den = function(t) t$pa),
  .pl_stat("barrel_pct", "Barrel rate (Barrel%)", "batting", "statcast", "pct", "pa", "LEADERS_MIN_PA_BARREL_PCT",
           num = function(t) t$barrels, den = function(t) t$bbe_tracked),

  # Pitching (7 stats)
  .pl_stat("era",  "Earned run average (ERA)", "pitching", "rate", "era", "bf", "LEADERS_MIN_BF_ERA",  lower = TRUE, noise = TRUE,
           num = function(t) 9 * t$er, den = function(t) t$ip),
  .pl_stat("fip",  "Fielding independent pitching (FIP)", "pitching", "rate", "era", "bf", "LEADERS_MIN_BF_FIP", lower = TRUE,
           num = function(t) t$fip_num, den = function(t) t$ip),
  .pl_stat("whip", "WHIP",                     "pitching", "rate", "era", "bf", "LEADERS_MIN_BF_WHIP", lower = TRUE,
           num = function(t) t$bb + t$h, den = function(t) t$ip),
  .pl_stat("p_k_pct",  "Strikeout rate (K%)",  "pitching", "rate", "pct", "bf", "LEADERS_MIN_BF_K_PCT",
           num = function(t) t$so, den = function(t) t$bf),
  .pl_stat("p_bb_pct", "Walk rate (BB%)",      "pitching", "rate", "pct", "bf", "LEADERS_MIN_BF_BB_PCT", lower = TRUE,
           num = function(t) t$bb, den = function(t) t$bf),
  .pl_stat("ip",    "Innings pitched (IP)",    "pitching", "counting", "ip",  "app", "LEADERS_MIN_APP_IP",
           num = function(t) t$ip, den = .ones),
  .pl_stat("saves", "Saves (SV)",              "pitching", "counting", "int", "relief_app", "LEADERS_MIN_RELIEF_APP_SAVES",
           num = function(t) t$sv, den = .ones)
)
names(PL_STATS) <- vapply(PL_STATS, `[[`, "", "key")

PL_UNIT_LABELS <- c(
  pa         = "plate appearances",
  bf         = "batters faced",
  app        = "appearances",
  relief_app = "relief appearances"
)

pl_minimum <- function(st) as.numeric(get(st$min))

pl_required <- function(minimum, team_games_played, base = LEADERS_FULL_SEASON_GAMES) {
  minimum * team_games_played / base
}

# ------------------------------------------------------------------------------
# Additive season totals
# ------------------------------------------------------------------------------
pl_empty_bat_totals <- function() {
  df <- as.data.frame(setNames(replicate(length(PL_BAT_ID_FIELDS), character(0), simplify = FALSE),
                               PL_BAT_ID_FIELDS), stringsAsFactors = FALSE)
  for (f in PL_BAT_SUM_FIELDS) df[[f]] <- numeric(0)
  df
}

pl_empty_pit_totals <- function() {
  df <- as.data.frame(setNames(replicate(length(PL_PIT_ID_FIELDS), character(0), simplify = FALSE),
                               PL_PIT_ID_FIELDS), stringsAsFactors = FALSE)
  for (f in PL_PIT_SUM_FIELDS) df[[f]] <- numeric(0)
  df
}

.pl_merge_totals <- function(totals, g, id_fields, sum_fields) {
  if (is.null(g) || !nrow(g)) return(totals)
  g <- g[order(g$game_date, g$game_id), , drop = FALSE]
  sums <- stats::aggregate(g[, sum_fields, drop = FALSE],
                           by = list(player_id = g$player_id), FUN = sum)
  latest <- g[!duplicated(g$player_id, fromLast = TRUE),
              c("player_id", "player", "team_id", "team", "position", "game_date", "game_id")]
  names(latest)[6:7] <- c("last_game_date", "last_game_id")
  add <- merge(latest, sums, by = "player_id")
  out <- totals
  for (i in seq_len(nrow(add))) {
    k <- match(add$player_id[i], out$player_id)
    if (is.na(k)) {
      out[nrow(out) + 1L, ] <- add[i, names(out)]
    } else {
      for (f in sum_fields) out[[f]][k] <- out[[f]][k] + add[[f]][i]
      if (is.na(out$last_game_date[k]) || add$last_game_date[i] >= out$last_game_date[k]) {
        for (f in setdiff(id_fields, "player_id")) out[[f]][k] <- add[[f]][i]
      }
    }
  }
  out
}

pl_add_bat_games <- function(totals, g) {
  .pl_merge_totals(totals, g, PL_BAT_ID_FIELDS, PL_BAT_SUM_FIELDS)
}

pl_add_pit_games <- function(totals, g) {
  .pl_merge_totals(totals, g, PL_PIT_ID_FIELDS, PL_PIT_SUM_FIELDS)
}

pl_team_games_from_rows <- function(rows) {
  if (is.null(rows) || !nrow(rows)) {
    return(data.frame(team_id = character(0), team = character(0),
                      games = numeric(0), stringsAsFactors = FALSE))
  }
  rows <- rows[!duplicated(rows[, c("game_id", "team_id")]), , drop = FALSE]
  n <- table(rows$team_id)
  abbr <- tapply(rows$team, rows$team_id, function(x) x[length(x)])
  data.frame(team_id = names(n), team = unname(as.character(abbr[names(n)])),
             games = as.numeric(n), stringsAsFactors = FALSE)
}

pl_add_team_games <- function(team_games, rows) {
  new <- pl_team_games_from_rows(rows)
  for (i in seq_len(nrow(new))) {
    k <- match(new$team_id[i], team_games$team_id)
    if (is.na(k)) team_games[nrow(team_games) + 1L, ] <- new[i, names(team_games)]
    else {
      team_games$games[k] <- team_games$games[k] + new$games[i]
      team_games$team[k]  <- new$team[i]
    }
  }
  team_games
}

# ------------------------------------------------------------------------------
# Cards
# ------------------------------------------------------------------------------
.pl_round <- function(x, d = 4L) ifelse(is.finite(x), round(x, d), NA_real_)

pl_rank_rows <- function(df, lower_is_better) {
  if (!nrow(df)) return(df)
  v <- round(df$value, 6)
  ord <- if (lower_is_better) order(v, df$player) else order(-v, df$player)
  df <- df[ord, , drop = FALSE]
  key <- if (lower_is_better) round(df$value, 4) else -round(df$value, 4)
  df$rank <- as.integer(rank(key, ties.method = "min"))
  df
}

.pl_leader_list <- function(df, n = PL_TOP_N) {
  df <- utils::head(df, n)
  lapply(seq_len(nrow(df)), function(i) list(
    rank = df$rank[i],
    player_id = df$player_id[i],
    player = df$player[i],
    team = df$team[i],
    position = if (is.na(df$position[i])) NULL else df$position[i],
    position_group = if (is.na(df$position_group[i])) NULL else df$position_group[i],
    value = .pl_round(df$value[i]),
    sample = .pl_round(df$sample[i], 1L),
    required = .pl_round(df$required[i], 1L),
    team_games_played = df$team_games_played[i]
  ))
}

pl_card <- function(st, cand, through_date, through_date_null_reason = NULL,
                    unavailable_reason = NULL) {
  minimum <- pl_minimum(st)
  if (is.null(cand) || !nrow(cand)) {
    cand <- data.frame(player_id = character(0), player = character(0),
                       team = character(0), position = character(0),
                       position_group = character(0), value = numeric(0),
                       sample = numeric(0), team_games_played = numeric(0),
                       stringsAsFactors = FALSE)
  }
  cand$required <- pl_required(minimum, cand$team_games_played)
  keep <- is.finite(cand$value) & is.finite(cand$required) & cand$sample >= cand$required
  q <- cand[keep, , drop = FALSE]
  q <- pl_rank_rows(q, st$lower_is_better)
  leaders <- list(); counts <- list()
  for (p in PL_POSITIONS) {
    sub <- if (p == "all") q else q[!is.na(q$position_group) & q$position_group == p, , drop = FALSE]
    if (p != "all" && nrow(sub)) {
      sub$rank <- as.integer(rank(
        if (st$lower_is_better) round(sub$value, 4) else -round(sub$value, 4),
        ties.method = "min"
      ))
    }
    leaders[[p]] <- .pl_leader_list(sub)
    counts[[p]] <- nrow(sub)
  }
  empty <- nrow(q) == 0L
  list(
    key = st$key, label = st$label, group = st$group, kind = st$kind,
    format = st$format, lower_is_better = st$lower_is_better,
    unit = st$unit, unit_label = PL_UNIT_LABELS[[st$unit]],
    minimum_full_season = minimum, minimum_constant = st$min,
    through_date = through_date, through_date_null_reason = through_date_null_reason,
    noise_note = st$noise, noise_note_text = if (st$noise) PL_NOISE_TEXT else NULL,
    status = if (empty) "not_enough_games" else "ok",
    status_text = if (empty) PL_NOT_ENOUGH else NULL,
    null_reason = if (!empty) NULL else (unavailable_reason %||%
      sprintf("No player has reached the scaled minimum yet (%s %s over a full season, scaled by team games played).",
              format(minimum, big.mark = ","), PL_UNIT_LABELS[[st$unit]])),
    candidates = nrow(cand),
    qualified_count = counts,
    leaders = leaders
  )
}

pl_build_cards <- function(bat_totals, pit_totals, team_games, through_date) {
  btg <- team_games$games[match(bat_totals$team_id, team_games$team_id)]
  ptg <- team_games$games[match(pit_totals$team_id, team_games$team_id)]
  bat_pg <- pl_batter_position_group(bat_totals$position)
  pit_pg <- pl_pitcher_role_group(pit_totals$gs, pit_totals$app)

  cards <- list()
  for (st in PL_STATS) {
    if (st$group == "batting") {
      num <- st$num(bat_totals); den <- st$den(bat_totals)
      value <- ifelse(den > 0, num / den, NA_real_)
      unavail <- NULL
      if (st$kind == "statcast") {
        has_sc <- any(!is.na(bat_totals$bbe_tracked) & bat_totals$bbe_tracked > 0)
        if (!has_sc) {
          value <- rep(NA_real_, nrow(bat_totals))
          unavail <- "Statcast batted-ball data is unavailable for this run; Barrel% is omitted rather than imputed."
        } else {
          value[bat_totals$sc_missing_games > 0] <- NA_real_
        }
      }
      cand <- data.frame(
        player_id = bat_totals$player_id, player = bat_totals$player,
        team = bat_totals$team, position = bat_totals$position,
        position_group = bat_pg, value = value, sample = bat_totals$pa,
        team_games_played = btg, stringsAsFactors = FALSE
      )
      cards[[st$key]] <- pl_card(st, cand, through_date, unavailable_reason = unavail)
    } else {
      num <- st$num(pit_totals); den <- st$den(pit_totals)
      value <- ifelse(den > 0, num / den, NA_real_)
      sample <- switch(st$unit,
        bf = pit_totals$bf,
        app = pit_totals$app,
        relief_app = pit_totals$relief_app
      )
      cand <- data.frame(
        player_id = pit_totals$player_id, player = pit_totals$player,
        team = pit_totals$team, position = pit_totals$position,
        position_group = pit_pg, value = value, sample = sample,
        team_games_played = ptg, stringsAsFactors = FALSE
      )
      cards[[st$key]] <- pl_card(st, cand, through_date)
    }
  }
  cards
}

# ------------------------------------------------------------------------------
# Payload
# ------------------------------------------------------------------------------
pl_methods <- function() {
  mins <- lapply(PL_STATS, function(st) list(
    key = st$key, label = st$label, group = st$group,
    unit = st$unit, unit_label = PL_UNIT_LABELS[[st$unit]],
    minimum_full_season = pl_minimum(st), constant = st$min
  ))
  list(
    scaling_rule = sprintf("required = minimum x team games played / %d", LEADERS_FULL_SEASON_GAMES),
    scaling_text = sprintf(paste0(
      "Each minimum is a full-season (%d-game) bar set by the owner after reviewing the reliability study's curves; ",
      "the study did not choose them. The bar scales with the team games played by the player's current team: ",
      "required = minimum x team games played / %d. For example, after 81 team games the AVG bar is 251 plate appearances."),
      LEADERS_FULL_SEASON_GAMES, LEADERS_FULL_SEASON_GAMES),
    traded_players = paste0(
      "A traded player's sample counts every game he played this season, for any team, and is held to the bar ",
      "of the team he played for most recently."),
    position_note = paste0(
      "Hitter positions use the listed primary position (IF = 1B/2B/3B/SS, OF = LF/CF/RF/OF, C/DH = C/DH). ",
      "Pitcher roles (Starters vs. Relievers) are classified from appearances started (50%+ starts = Starter)."),
    ranking = paste0(
      "Highest leads for counting and positive rate stats; lowest leads for batting K%, pitching ERA, FIP, WHIP, ",
      "and pitching BB%. Ties share a rank."),
    noise_note = paste0(
      "Batting AVG, OBP, SLG, OPS, wOBA and pitching ERA remain below 0.60 split-half reliability at season ",
      "sample sizes in the reliability study; treat small gaps as rough."),
    rate_formulas = list(
      avg = "H / AB",
      obp = "(H + BB + HBP) / (AB + BB + HBP + SF)",
      slg = "TB / AB",
      ops = "OBP + SLG",
      woba = "(wBB x uBB + wHBP x HBP + w1B x 1B + w2B x 2B + w3B x 3B + wHR x HR) / (AB + BB - IBB + SF + HBP)",
      k_pct = "SO / PA (batting) or SO / BF (pitching)",
      bb_pct = "BB / PA (batting) or BB / BF (pitching)",
      barrel_pct = "Barrels / tracked batted-ball events (Statcast launch_speed_angle == 6)",
      era = "9 x ER / IP (IP = outs / 3)",
      fip = "(13 x HR + 3 x (BB + HBP) - 2 x SO) / IP + cFIP",
      whip = "(BB + H) / IP"
    ),
    refresh = paste0(
      "Box-score and rate cards update in the daily pipeline run and in evening score refreshes. ",
      "Statcast Barrel% updates in the daily pipeline run. Each card shows its own through date."),
    sample = "Regular-season games only (gameType R).",
    study_source_commit = LEADERS_STUDY_SOURCE_COMMIT,
    base_games = LEADERS_FULL_SEASON_GAMES,
    minimums = unname(mins),
    nulls = "Values that cannot be supported are null with a reason; nothing is imputed or synthesised."
  )
}

.pl_cols <- function(df) lapply(as.list(df), function(x) I(if (is.numeric(x)) round(x, 4) else x))

pl_build_payload <- function(bat_totals, pit_totals, team_games, game_ids, guts, sources,
                             now = Sys.time(), season = MLB_CURRENT_SEASON,
                             override_cards = NULL) {
  dates <- c(bat_totals$last_game_date, pit_totals$last_game_date)
  dates <- dates[!is.na(dates) & nzchar(dates)]
  through <- if (length(dates)) max(dates) else NULL
  cards_map <- pl_build_cards(bat_totals, pit_totals, team_games, through)
  if (!is.null(override_cards)) {
    for (k in names(override_cards)) cards_map[[k]] <- override_cards[[k]]
  }
  order_keys <- names(PL_STATS)
  cards <- unname(cards_map[order_keys[order_keys %in% names(cards_map)]])
  tg <- team_games[order(team_games$team), , drop = FALSE]
  list(
    schema_version = PL_SCHEMA_VERSION,
    generated_at = format(now, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    season = as.character(season),
    through_date = through,
    position_filters = lapply(PL_POSITIONS, function(p) list(key = p, label = PL_POSITION_LABELS[[p]])),
    groups = PL_GROUPS,
    cards = cards,
    methods = pl_methods(),
    sources = sources,
    season_totals = list(
      description = paste0("Per-player season sums behind the batting and pitching cards, ",
                           "team games played, FanGraphs season constants, and game_ids included, ",
                           "so evening refreshes can add newly finished regular-season games."),
      game_ids = I(sort(unique(as.character(game_ids)))),
      guts = as.list(guts),
      team_games = .pl_cols(tg),
      batters = .pl_cols(bat_totals[order(bat_totals$player_id), , drop = FALSE]),
      pitchers = .pl_cols(pit_totals[order(pit_totals$player_id), , drop = FALSE])
    )
  )
}

pl_json_text <- function(payload) {
  as.character(jsonlite::toJSON(payload, auto_unbox = TRUE, pretty = FALSE,
                                null = "null", na = "null", digits = NA))
}

pl_write_payload <- function(payload, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  writeLines(pl_json_text(payload), path, useBytes = TRUE)
  invisible(path)
}

pl_read_totals <- function(payload) {
  st <- payload$season_totals
  read_tbl <- function(lst, id_fields, sum_fields, empty_fn) {
    df <- as.data.frame(lapply(lst, unlist), stringsAsFactors = FALSE)
    if (!nrow(df) || !ncol(df)) return(empty_fn())
    for (f in id_fields) df[[f]] <- as.character(df[[f]])
    for (f in sum_fields) df[[f]] <- as.numeric(df[[f]])
    df[, c(id_fields, sum_fields), drop = FALSE]
  }
  tg <- as.data.frame(lapply(st$team_games, unlist), stringsAsFactors = FALSE)
  if (!nrow(tg) || !ncol(tg)) {
    tg <- data.frame(team_id = character(0), team = character(0),
                     games = numeric(0), stringsAsFactors = FALSE)
  } else {
    tg$team_id <- as.character(tg$team_id)
    tg$team    <- as.character(tg$team)
    tg$games   <- as.numeric(tg$games)
    tg <- tg[, c("team_id", "team", "games"), drop = FALSE]
  }
  list(
    batters = read_tbl(st$batters, PL_BAT_ID_FIELDS, PL_BAT_SUM_FIELDS, pl_empty_bat_totals),
    pitchers = read_tbl(st$pitchers, PL_PIT_ID_FIELDS, PL_PIT_SUM_FIELDS, pl_empty_pit_totals),
    team_games = tg,
    game_ids = as.character(unlist(st$game_ids)),
    guts = st$guts
  )
}

# ------------------------------------------------------------------------------
# Evening refresh: MLB Stats API game boxscore -> player-game rows
# ------------------------------------------------------------------------------
PL_MLB_BOXSCORE_URL <- "https://statsapi.mlb.com/api/v1/game/%s/boxscore"

pl_mlb_fetch_boxscore <- function(game_pk) {
  tryCatch({
    con <- url(sprintf(PL_MLB_BOXSCORE_URL, game_pk), open = "rb",
               headers = c("User-Agent" = "Mozilla/5.0"))
    on.exit(close(con), add = TRUE)
    jsonlite::fromJSON(paste(readLines(con, warn = FALSE), collapse = ""), simplifyVector = FALSE)
  }, error = function(e) {
    warning(sprintf("MLB boxscore fetch failed for %s: %s", game_pk, conditionMessage(e)), call. = FALSE)
    NULL
  })
}

# Convert baseball IP string (e.g. "6.2") to outs (20)
.pl_ip_to_outs <- function(ip_str) {
  if (is.null(ip_str) || is.na(ip_str)) return(NA_real_)
  s <- as.character(ip_str)
  parts <- strsplit(s, ".", fixed = TRUE)[[1]]
  whole <- suppressWarnings(as.numeric(parts[1]))
  rem <- if (length(parts) >= 2L) suppressWarnings(as.numeric(parts[2])) else 0
  if (is.na(whole) || is.na(rem)) return(NA_real_)
  whole * 3 + rem
}

pl_game_rows_from_mlb_box <- function(box, game_id, game_date, guts) {
  if (is.null(box$teams$away) || is.null(box$teams$home)) {
    stop(sprintf("boxscore for %s has no away/home teams", game_id), call. = FALSE)
  }
  bat_rows <- list(); pit_rows <- list(); team_rows <- list()
  for (side_name in c("away", "home")) {
    side <- box$teams[[side_name]]
    tid <- as.character(side$team$id)
    tabbr <- pl_norm_abbr(side$team$abbreviation)
    team_rows[[length(team_rows) + 1L]] <- data.frame(
      game_id = as.character(game_id), team_id = tid, team = tabbr,
      stringsAsFactors = FALSE
    )
    players <- side$players %||% list()
    for (p in players) {
      pid <- as.character(p$person$id)
      pname <- as.character(p$person$fullName)
      pos <- as.character(p$position$abbreviation %||% NA_character_)
      bs <- p$stats$batting
      if (!is.null(bs) && length(bs) && !is.null(bs$plateAppearances)) {
        n <- function(k) as.numeric(bs[[k]] %||% 0)
        pa <- n("plateAppearances")
        ab <- n("atBats"); h <- n("hits"); d2 <- n("doubles"); d3 <- n("triples")
        hr <- n("homeRuns"); bb <- n("baseOnBalls"); ibb <- n("intentionalWalks")
        hbp <- n("hitByPitch"); sf <- n("sacFlies"); so <- n("strikeOuts")
        sb <- n("stolenBases"); tb <- n("totalBases")
        singles <- h - d2 - d3 - hr
        woba_num <- guts$wBB * (bb - ibb) + guts$wHBP * hbp + guts$w1B * singles +
          guts$w2B * d2 + guts$w3B * d3 + guts$wHR * hr
        woba_den <- ab + bb - ibb + sf + hbp
        if (pa > 0 || sb > 0) {
          bat_rows[[length(bat_rows) + 1L]] <- data.frame(
            game_id = as.character(game_id), game_date = as.character(game_date),
            player_id = pid, player = pname, team_id = tid, team = tabbr, position = pos,
            games = 1, pa = pa, ab = ab, h = h, d2 = d2, d3 = d3, hr = hr,
            bb = bb, ibb = ibb, hbp = hbp, sf = sf, so = so, sb = sb, tb = tb,
            woba_num = woba_num, woba_den = woba_den,
            barrels = 0, bbe_tracked = 0, sc_missing_games = 1,
            stringsAsFactors = FALSE
          )
        }
      }
      ps <- p$stats$pitching
      if (!is.null(ps) && length(ps) && (!is.null(ps$battersFaced) || !is.null(ps$inningsPitched))) {
        n <- function(k) as.numeric(ps[[k]] %||% 0)
        outs <- if (!is.null(ps$outs)) n("outs") else .pl_ip_to_outs(ps$inningsPitched)
        if (is.na(outs)) outs <- 0
        ip <- outs / 3
        gs <- n("gamesStarted"); bf <- n("battersFaced")
        h <- n("hits"); bb <- n("baseOnBalls"); hbp <- n("hitBatsmen")
        so <- n("strikeOuts"); hr <- n("homeRuns"); er <- n("earnedRuns"); sv <- n("saves")
        fip_num <- 13 * hr + 3 * (bb + hbp) - 2 * so + guts$cFIP * ip
        if (bf > 0 || outs > 0) {
          pit_rows[[length(pit_rows) + 1L]] <- data.frame(
            game_id = as.character(game_id), game_date = as.character(game_date),
            player_id = pid, player = pname, team_id = tid, team = tabbr, position = pos,
            app = 1, gs = gs, relief_app = as.numeric(gs == 0),
            bf = bf, outs = outs, ip = ip, h = h, bb = bb, hbp = hbp,
            so = so, hr = hr, er = er, sv = sv, fip_num = fip_num,
            stringsAsFactors = FALSE
          )
        }
      }
    }
  }
  if (!length(bat_rows) && !length(pit_rows)) {
    stop(sprintf("boxscore for %s lists no players", game_id), call. = FALSE)
  }
  list(
    batters = if (length(bat_rows)) do.call(rbind, bat_rows) else NULL,
    pitchers = if (length(pit_rows)) do.call(rbind, pit_rows) else NULL,
    teams = do.call(rbind, team_rows)
  )
}

PL_REFRESH_MAX_GAMES <- 30L

#' Add newly finished regular-season games' box scores to player_leaders.json.
#'
#' All or nothing: if any game's boxscore cannot be fetched or parsed, the file
#' is left unchanged. Barrel% card is preserved from the existing payload
#' (Statcast updates in the daily pipeline run).
pl_refresh_leaders <- function(path, games, fetch_boxscore = pl_mlb_fetch_boxscore,
                               max_games = PL_REFRESH_MAX_GAMES, now = Sys.time()) {
  if (!file.exists(path)) return(list(status = "no_file", n_games = 0L, file = NULL))
  payload <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  tot <- pl_read_totals(payload)
  done <- !is.na(games$is_completed) & games$is_completed &
    (if ("game_type" %in% names(games)) games$game_type == "R" else TRUE)
  ids <- as.character(games$game_id[done])
  dates <- substr(as.character(games$game_date[done]), 1, 10)
  new <- !(ids %in% tot$game_ids)
  if (!any(new)) return(list(status = "up_to_date", n_games = 0L, file = NULL))
  if (sum(new) > max_games) {
    return(list(status = sprintf("skipped: %d games missing, more than %d; left for the daily run",
                                 sum(new), max_games),
                n_games = 0L, file = NULL))
  }
  bat_batches <- list(); pit_batches <- list(); teams <- list()
  for (k in which(new)) {
    bx <- fetch_boxscore(ids[k])
    if (is.null(bx)) return(list(status = sprintf("fetch_failed: %s", ids[k]), n_games = 0L, file = NULL))
    r <- tryCatch(pl_game_rows_from_mlb_box(bx, ids[k], dates[k], tot$guts), error = function(e) e)
    if (inherits(r, "error")) {
      return(list(status = sprintf("parse_failed: %s", conditionMessage(r)), n_games = 0L, file = NULL))
    }
    if (!is.null(r$batters))  bat_batches[[length(bat_batches) + 1L]] <- r$batters
    if (!is.null(r$pitchers)) pit_batches[[length(pit_batches) + 1L]] <- r$pitchers
    teams[[length(teams) + 1L]] <- r$teams
  }
  batters  <- if (length(bat_batches)) pl_add_bat_games(tot$batters, do.call(rbind, bat_batches)) else tot$batters
  pitchers <- if (length(pit_batches)) pl_add_pit_games(tot$pitchers, do.call(rbind, pit_batches)) else tot$pitchers
  team_games <- pl_add_team_games(tot$team_games, do.call(rbind, teams))
  # Preserve Statcast Barrel% card (updates in daily pipeline run)
  sc_card <- Filter(function(cd) identical(cd$key, "barrel_pct"), payload$cards)
  override <- if (length(sc_card)) list(barrel_pct = sc_card[[1]]) else NULL
  sources <- payload$sources
  sources$evening_refresh <- sprintf("%d regular-season game(s) added from MLB Stats API by tools/refresh_live_results.R",
                                     sum(new))
  out <- pl_build_payload(batters, pitchers, team_games, c(tot$game_ids, ids[new]),
                          tot$guts, sources, now = now, season = as.integer(payload$season),
                          override_cards = override)
  pl_write_payload(out, path)
  list(status = "updated", n_games = sum(new), file = path)
}

# ------------------------------------------------------------------------------
# Data fetchers for daily pipeline (cached in cache/leaders_*)
# ------------------------------------------------------------------------------
.pl_fetch_raw <- function(url, tries = 4L) {
  for (i in seq_len(tries)) {
    res <- tryCatch({
      con <- url(url, open = "rb", headers = c("User-Agent" = "Mozilla/5.0"))
      on.exit(close(con), add = TRUE)
      paste(readLines(con, warn = FALSE), collapse = "\n")
    }, error = function(e) NULL)
    if (!is.null(res) && nzchar(res)) return(res)
    Sys.sleep(2 * i)
  }
  stop("download failed after retries: ", url, call. = FALSE)
}

.pl_fetch_json <- function(url) jsonlite::fromJSON(.pl_fetch_raw(url), simplifyVector = TRUE)

pl_load_fg_guts <- function(season = MLB_CURRENT_SEASON,
                            cache_path = file.path(MLB_CACHE_ROOT, "leaders_fg_guts.rds")) {
  if (file.exists(cache_path)) {
    g <- readRDS(cache_path)
    row <- g[as.integer(g$season) == as.integer(season), , drop = FALSE]
    if (nrow(row) == 1L) return(as.list(row[, c("wBB", "wHBP", "w1B", "w2B", "w3B", "wHR", "cFIP")]))
  }
  if (requireNamespace("baseballr", quietly = TRUE)) {
    g <- as.data.frame(baseballr::fg_guts())
    dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
    saveRDS(g, cache_path)
    row <- g[as.integer(g$season) == as.integer(season), , drop = FALSE]
    if (nrow(row) == 1L) return(as.list(row[, c("wBB", "wHBP", "w1B", "w2B", "w3B", "wHR", "cFIP")]))
  }
  stop(sprintf("No FanGraphs season constants available for %d", season), call. = FALSE)
}

pl_load_gamelogs <- function(season = MLB_CURRENT_SEASON,
                             cache_path = file.path(MLB_CACHE_ROOT, sprintf("leaders_gamelogs_%d.rds", season)),
                             force_refresh = FALSE) {
  if (!force_refresh && file.exists(cache_path)) return(readRDS(cache_path))
  api <- "https://statsapi.mlb.com/api/v1"
  teams_j <- .pl_fetch_json(sprintf("%s/teams?sportId=1&season=%d", api, season))$teams
  team_map <- setNames(pl_norm_abbr(teams_j$abbreviation), as.character(teams_j$id))

  sched_j <- .pl_fetch_json(sprintf("%s/schedule?sportId=1&season=%d&gameTypes=R", api, season))
  tg_rows <- list()
  for (games in sched_j$dates$games) {
    if (is.null(games) || !NROW(games)) next
    for (i in seq_len(NROW(games))) {
      st <- games$status$detailedState[i]
      if (!(st %in% c("Final", "Completed Early", "Game Over"))) next
      gpk <- as.character(games$gamePk[i])
      htid <- as.character(games$teams$home$team$id[i])
      atid <- as.character(games$teams$away$team$id[i])
      tg_rows[[length(tg_rows) + 1L]] <- data.frame(
        game_id = c(gpk, gpk),
        team_id = c(htid, atid),
        team = unname(team_map[c(htid, atid)]),
        stringsAsFactors = FALSE
      )
    }
  }
  tg_df <- if (length(tg_rows)) do.call(rbind, tg_rows) else
    data.frame(game_id = character(0), team_id = character(0), team = character(0), stringsAsFactors = FALSE)

  roster <- .pl_fetch_json(sprintf("%s/sports/1/players?season=%d", api, season))$people
  pos_map <- setNames(as.character(roster$primaryPosition$abbreviation), as.character(roster$id))
  ids <- unique(as.character(roster$id))

  num_col <- function(d, col) if (col %in% names(d)) suppressWarnings(as.numeric(d[[col]])) else rep(0, nrow(d))
  parse_bat <- function(sp) {
    sp <- jsonlite::flatten(as.data.frame(sp))
    sp <- sp[!is.na(sp$gameType) & sp$gameType == "R", , drop = FALSE]
    if (!nrow(sp)) return(NULL)
    pid <- as.character(sp$player.id)
    tid <- as.character(sp$team.id)
    data.frame(
      game_id = as.character(sp$game.gamePk),
      game_date = as.character(as.Date(sp$date)),
      player_id = pid,
      player = as.character(sp$player.fullName),
      team_id = tid,
      team = unname(team_map[tid]),
      position = unname(pos_map[pid]),
      games = 1,
      pa = num_col(sp, "stat.plateAppearances"),
      ab = num_col(sp, "stat.atBats"),
      h  = num_col(sp, "stat.hits"),
      d2 = num_col(sp, "stat.doubles"),
      d3 = num_col(sp, "stat.triples"),
      hr = num_col(sp, "stat.homeRuns"),
      bb = num_col(sp, "stat.baseOnBalls"),
      ibb = num_col(sp, "stat.intentionalWalks"),
      hbp = num_col(sp, "stat.hitByPitch"),
      sf = num_col(sp, "stat.sacFlies"),
      so = num_col(sp, "stat.strikeOuts"),
      sb = num_col(sp, "stat.stolenBases"),
      tb = num_col(sp, "stat.totalBases"),
      stringsAsFactors = FALSE
    )
  }
  parse_pit <- function(sp) {
    sp <- jsonlite::flatten(as.data.frame(sp))
    sp <- sp[!is.na(sp$gameType) & sp$gameType == "R", , drop = FALSE]
    if (!nrow(sp)) return(NULL)
    pid <- as.character(sp$player.id)
    tid <- as.character(sp$team.id)
    gs <- num_col(sp, "stat.gamesStarted")
    outs <- num_col(sp, "stat.outs")
    data.frame(
      game_id = as.character(sp$game.gamePk),
      game_date = as.character(as.Date(sp$date)),
      player_id = pid,
      player = as.character(sp$player.fullName),
      team_id = tid,
      team = unname(team_map[tid]),
      position = unname(pos_map[pid]),
      app = 1, gs = gs, relief_app = as.numeric(gs == 0),
      bf = num_col(sp, "stat.battersFaced"),
      outs = outs, ip = outs / 3,
      h = num_col(sp, "stat.hits"),
      bb = num_col(sp, "stat.baseOnBalls"),
      hbp = num_col(sp, "stat.hitBatsmen"),
      so = num_col(sp, "stat.strikeOuts"),
      hr = num_col(sp, "stat.homeRuns"),
      er = num_col(sp, "stat.earnedRuns"),
      sv = num_col(sp, "stat.saves"),
      stringsAsFactors = FALSE
    )
  }

  hit_list <- list(); pit_list <- list()
  batch <- 40L
  for (bi in seq(1L, length(ids), by = batch)) {
    chunk <- ids[bi:min(bi + batch - 1L, length(ids))]
    u <- sprintf("%s/people?personIds=%s&hydrate=stats(group=[hitting,pitching],type=[gameLog],season=%d,gameType=R)",
                 api, paste(chunk, collapse = ","), season)
    u <- gsub("\\[", "%5B", gsub("\\]", "%5D", u))
    x <- .pl_fetch_json(u)$people
    if (is.null(x) || !"stats" %in% names(x)) next
    for (i in seq_len(nrow(x))) {
      st <- x$stats[[i]]
      if (is.null(st) || !nrow(st)) next
      for (j in seq_len(nrow(st))) {
        grp <- st$group$displayName[j]
        sp <- st$splits[[j]]
        if (is.null(sp) || !length(sp) || !NROW(sp)) next
        if (grp == "hitting")  hit_list[[length(hit_list) + 1L]] <- parse_bat(sp)
        if (grp == "pitching") pit_list[[length(pit_list) + 1L]] <- parse_pit(sp)
      }
    }
  }
  bat <- if (length(hit_list)) do.call(rbind, hit_list) else data.frame()
  pit <- if (length(pit_list)) do.call(rbind, pit_list) else data.frame()
  if (nrow(bat)) bat <- bat[!duplicated(bat[, c("player_id", "game_id")]), , drop = FALSE]
  if (nrow(pit)) pit <- pit[!duplicated(pit[, c("player_id", "game_id")]), , drop = FALSE]
  res <- list(bat = bat, pit = pit, team_rows = tg_df)
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(res, cache_path)
  res
}

pl_load_statcast_bip <- function(season, date_from, date_to,
                                 cache_path = file.path(MLB_CACHE_ROOT, sprintf("leaders_statcast_bip_%d.rds", season)),
                                 force_refresh = FALSE) {
  if (!force_refresh && file.exists(cache_path)) return(readRDS(cache_path))
  starts <- seq(as.Date(date_from), as.Date(date_to), by = 8L)
  parts <- list()
  for (a in starts) {
    a <- as.Date(a, origin = "1970-01-01")
    b <- min(a + 7L, as.Date(date_to))
    u <- sprintf(paste0("https://baseballsavant.mlb.com/statcast_search/csv?all=true",
                        "&hfPR=hit%%5C.%%5C.into%%5C.%%5C.play%%7C&hfGT=R%%7C&hfSea=%d%%7C",
                        "&player_type=batter&game_date_gt=%s&game_date_lt=%s&type=details"),
                 season, format(a), format(b))
    txt <- .pl_fetch_raw(u)
    d <- if (nchar(txt) < 50L) NULL else utils::read.csv(text = txt, stringsAsFactors = FALSE)
    if (!is.null(d) && nrow(d)) {
      d <- d[!duplicated(d), , drop = FALSE]
      d <- d[d$type == "X", c("game_pk", "batter", "launch_speed_angle"), drop = FALSE]
      parts[[length(parts) + 1L]] <- d
    }
    Sys.sleep(0.5)
  }
  d <- if (length(parts)) do.call(rbind, parts) else data.frame(game_pk = character(0), batter = character(0), launch_speed_angle = numeric(0))
  d$tracked <- !is.na(d$launch_speed_angle)
  agg <- stats::aggregate(
    cbind(bbe_tracked = tracked,
          barrels = !is.na(launch_speed_angle) & launch_speed_angle == 6) ~ game_pk + batter,
    data = d, FUN = sum
  )
  res <- list(
    agg = data.frame(game_id = as.character(agg$game_pk), player_id = as.character(agg$batter),
                     bbe_tracked = agg$bbe_tracked, barrels = agg$barrels, stringsAsFactors = FALSE),
    game_pks = unique(as.character(d$game_pk))
  )
  dir.create(dirname(cache_path), recursive = TRUE, showWarnings = FALSE)
  saveRDS(res, cache_path)
  res
}

# ------------------------------------------------------------------------------
# Stage entry point
# ------------------------------------------------------------------------------
build_player_leaders <- function(season = MLB_CURRENT_SEASON,
                                 output_json = WEB_JSON_PLAYER_LEADERS,
                                 force_refresh = FALSE,
                                 now = Sys.time()) {
  gl <- pl_load_gamelogs(season = season, force_refresh = force_refresh)
  guts <- pl_load_fg_guts(season = season)
  bat <- gl$bat; pit <- gl$pit
  if (!nrow(bat) && !nrow(pit)) {
    stop(sprintf("build_player_leaders: no regular-season game logs for %d", season), call. = FALSE)
  }

  singles <- bat$h - bat$d2 - bat$d3 - bat$hr
  bat$woba_num <- guts$wBB * (bat$bb - bat$ibb) + guts$wHBP * bat$hbp +
    guts$w1B * singles + guts$w2B * bat$d2 + guts$w3B * bat$d3 + guts$wHR * bat$hr
  bat$woba_den <- bat$ab + bat$bb - bat$ibb + bat$sf + bat$hbp

  pit$fip_num <- 13 * pit$hr + 3 * (pit$bb + pit$hbp) - 2 * pit$so + guts$cFIP * pit$ip

  sc <- tryCatch(
    pl_load_statcast_bip(season, min(bat$game_date), max(bat$game_date), force_refresh = force_refresh),
    error = function(e) {
      message(">>> [LEADERS] Statcast BIP unavailable: ", conditionMessage(e))
      NULL
    }
  )
  if (!is.null(sc)) {
    m <- match(paste(bat$game_id, bat$player_id), paste(sc$agg$game_id, sc$agg$player_id))
    in_sc <- bat$game_id %in% sc$game_pks
    bat$bbe_tracked      <- ifelse(in_sc, ifelse(is.na(m), 0, sc$agg$bbe_tracked[m]), 0)
    bat$barrels          <- ifelse(in_sc, ifelse(is.na(m), 0, sc$agg$barrels[m]), 0)
    bat$sc_missing_games <- as.numeric(!in_sc)
  } else {
    bat$bbe_tracked <- 0; bat$barrels <- 0; bat$sc_missing_games <- 1
  }

  bat_totals <- pl_add_bat_games(pl_empty_bat_totals(), bat)
  pit_totals <- pl_add_pit_games(pl_empty_pit_totals(), pit)
  team_games <- pl_team_games_from_rows(gl$team_rows)
  game_ids   <- unique(c(gl$team_rows$game_id, bat$game_id, pit$game_id))

  sources <- list(
    gamelogs = sprintf("MLB Stats API people gameLog hydration (season %d, gameType R)", season),
    guts     = sprintf("FanGraphs season constants (season %d)", season),
    statcast = if (is.null(sc)) "unavailable" else sprintf("Baseball Savant Statcast balls in play (season %d)", season)
  )
  payload <- pl_build_payload(bat_totals, pit_totals, team_games, game_ids, guts, sources,
                              now = now, season = season)
  pl_write_payload(payload, output_json)
  ok <- vapply(payload$cards, function(cd) cd$status == "ok", logical(1))
  cat(sprintf(">>> [LEADERS] Wrote %s (through %s): %d of %d cards have qualifiers\n",
              output_json, payload$through_date %||% "n/a", sum(ok), length(ok)))
  invisible(payload)
}

if (!nzchar(Sys.getenv("MLB_SKIP_STAGE_AUTORUN")) && !exists(".PIPELINE_SOURCED")) {
  build_player_leaders()
}
