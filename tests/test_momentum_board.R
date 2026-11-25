# ==============================================================================
# tests/test_momentum_board.R - Momentum Board data layer (NFL_analytics#226)
# Offline, base R plus jsonlite. Uses a small hand-built fixture (12 teams, two
# earlier seasons and the first weeks of this one) in temp directories; never
# touches the real cache/, web/public/data/ or data/history/ files.
#   1. config: owner settings, unchanged ROLLING_WINDOW_SIZE / OFFSEASON_METHOD, output lists
#   2. window values and the mean_regress carry-over
#   3. standardisation within the season-week and the combined score from config weights
#   4. payload: windows, carried-game labelling, weights in the JSON, no badges
#   5. null-with-reason paths (key players missing, starting QB)
#   6. rank history: append, idempotent for a week already written, never rewritten
#   7. pipeline / manifest / publish wiring
# Run: Rscript tests/test_momentum_board.R
# ==============================================================================
failures <- 0L
ok <- function(label, cond) {
  if (isTRUE(cond)) cat(sprintf("[PASS] %s\n", label))
  else { cat(sprintf("[FAIL] %s\n", label)); failures <<- failures + 1L }
}
root_dir <- if (file.exists("config.R")) getwd() else normalizePath("..", winslash = "/")
setwd(root_dir)
source("config.R")
source("build_momentum_board.R")

tmp <- tempfile("mboard_"); dir.create(tmp)
S <- as.integer(CURRENT_SEASON)

# ---- 1. config ----------------------------------------------------------------
ok("MB-01 windows are 3, 6, 9 and 3 is the noisiest", identical(MOMENTUM_BOARD_WINDOWS, c(3L, 6L, 9L)) && MOMENTUM_BOARD_NOISIEST_WINDOW == 3L)
ok("MB-02 weights match the owner's #226 settings exactly",
   identical(MOMENTUM_BOARD_WEIGHTS[["3"]], c(form = 0.45, trend = 0, residual = 0, elo_change = 0.55)) &&
     identical(MOMENTUM_BOARD_WEIGHTS[["6"]], c(form = 0.40, trend = 0, residual = 0, elo_change = 0.60)) &&
     identical(MOMENTUM_BOARD_WEIGHTS[["9"]], c(form = 0.25, trend = 0.25, residual = 0, elo_change = 0.50)) &&
     all(abs(vapply(MOMENTUM_BOARD_WEIGHTS, sum, 0) - 1) < 1e-12))
ok("MB-03 carry method mean_regress (keep 0.5) and the study commit",
   MOMENTUM_BOARD_CARRY_METHOD == "mean_regress" && MOMENTUM_BOARD_REGRESS_KEEP == 0.5 &&
     MOMENTUM_BOARD_STUDY_COMMIT == "4ac7997efcd51d9173e24ed893b2a681d98d4d78")
ok("MB-04 ROLLING_WINDOW_SIZE and OFFSEASON_METHOD unchanged", ROLLING_WINDOW_SIZE == 4 && OFFSEASON_METHOD == "reset")
ok("MB-05 JSON in WEB_DATA_FILES, history in PIPELINE_OUTPUT_FILES",
   gsub("\\\\", "/", WEB_JSON_MOMENTUM_BOARD) == "web/public/data/momentum_board.json" && WEB_JSON_MOMENTUM_BOARD %in% WEB_DATA_FILES &&
     gsub("\\\\", "/", MOMENTUM_RANK_HISTORY) == "data/history/momentum_rank_history.csv" && MOMENTUM_RANK_HISTORY %in% PIPELINE_OUTPUT_FILES)

# ---- fixture --------------------------------------------------------------------
teams <- sprintf("T%02d", 1:12)
team_names <- setNames(paste("Team", teams), teams)
strength <- setNames(seq(-5.5, 5.5, length.out = 12), teams)
rr_round <- function(r) {   # circle method, 12 teams, 11 rounds
  ids <- c(1, ((0:10 + r) %% 11) + 2)
  cbind(teams[ids[1:6]], teams[ids[12:7]])
}
games <- list(); d0 <- as.Date(sprintf("%d-09-07", S - 2L))
for (s in (S - 2L):S) {
  nweeks <- if (s == S) 4L else 11L
  base <- as.Date(sprintf("%d-09-07", s))
  for (w in seq_len(nweeks)) {
    pr <- rr_round(w - 1L)
    for (j in 1:6) {
      h <- pr[j, if (w %% 2) 1 else 2]; a <- pr[j, if (w %% 2) 2 else 1]
      hs <- 20L + round(strength[h] - strength[a]) + (w %% 3L) + j %% 2L; as <- 17L + (w %% 4L)
      games[[length(games) + 1L]] <- data.frame(game_id = sprintf("%d_%02d_%s_%s", s, w, a, h), season = s, game_type = "REG",
        week = w, gameday = format(base + 7L * (w - 1L) + (j %% 2L)), home_team = h, away_team = a,
        home_score = as.integer(max(hs, 0)), away_score = as.integer(as), location = "Home", stringsAsFactors = FALSE)
    }
  }
}
SCHED <- do.call(rbind, games)
# week 5 of this season: scheduled, not played
nx <- rr_round(4L)
SCHED <- rbind(SCHED, data.frame(game_id = sprintf("%d_05_%s_%s", S, nx[, 2], nx[, 1]), season = S, game_type = "REG", week = 5L,
                                 gameday = format(as.Date(sprintf("%d-09-07", S)) + 28L), home_team = nx[, 1], away_team = nx[, 2],
                                 home_score = NA_integer_, away_score = NA_integer_, location = "Home", stringsAsFactors = FALSE))
mk_plays <- function(g) {
  out <- list()
  for (side in c("home", "away")) {
    pos <- if (side == "home") g$home_team else g$away_team; def <- if (side == "home") g$away_team else g$home_team
    e <- (strength[pos] - strength[def]) / 20 + c(0.3, -0.1, 0.05, -0.2) + (g$week %% 5) / 50
    qb <- if (pos == "T01" && g$season == S && g$week >= 3) "QB-T01-B" else paste0("QB-", pos)
    out[[side]] <- data.frame(game_id = g$game_id, season = g$season, week = g$week, season_type = "REG",
      home_team = g$home_team, away_team = g$away_team, posteam = pos, defteam = def,
      play_type = c("pass", "run", "pass", "field_goal"), pass = c(1, 0, 1, 0), epa = unname(e),
      success = c(1, 0, 1, 0), qb_dropback = c(1, 0, 1, 0),
      passer_player_id = c(qb, NA, qb, NA), passer_player_name = c(qb, NA, qb, NA),
      rusher_player_id = c(NA, "RB", NA, NA), rusher_player_name = c(NA, "RB", NA, NA),
      interception = c(0, 0, as.numeric(g$week == 2), 0), fumble = c(0, 1, 0, 0), fumble_lost = c(0, as.numeric(side == "home"), 0, 0),
      fumbled_1_team = c(NA, pos, NA, NA), fumble_recovery_1_team = c(NA, if (side == "home") def else pos, NA, NA),
      field_goal_attempt = c(0, 0, 0, 1), field_goal_result = c(NA, NA, NA, if (g$week %% 2) "made" else "missed"),
      stringsAsFactors = FALSE)
  }
  do.call(rbind, out)
}
played <- SCHED[!is.na(SCHED$home_score), ]
PBP <- do.call(rbind, lapply(seq_len(nrow(played)), function(i) mk_plays(played[i, ])))
DNA <- PBP[PBP$season == S, ]
SNAPS <- do.call(rbind, lapply(which(played$season == S), function(i) {
  g <- played[i, ]
  do.call(rbind, lapply(c(g$home_team, g$away_team), function(t) {
    pl <- data.frame(game_id = g$game_id, season = S, game_type = "REG", week = g$week, team = t,
                     player = paste(t, c("Quarterback", "Tackle", "Corner")), pfr_player_id = paste0(t, c("QB", "OT", "CB")),
                     position = c("QB", "T", "CB"), offense_snaps = c(60, 60, 0), offense_pct = c(1, 1, 0),
                     defense_snaps = c(0, 0, 55), defense_pct = c(0, 0, 0.9), stringsAsFactors = FALSE)
    if (t == "T02" && g$week == 2) pl <- pl[pl$position != "CB", ]   # T02's corner missed week 2
    pl
  }))
}))
INJ <- data.frame(season = S, week = 3L, team = "T03", player_name = "T03 Tackle", status = "Out", stringsAsFactors = FALSE)
INPUTS <- list(schedules = SCHED, pbp = PBP, dna_pbp = DNA, snaps = SNAPS, injuries = INJ)
# replace whole elements (modifyList would merge into data frames)
with_inputs <- function(repl) { x <- INPUTS; for (n in names(repl)) x[n] <- list(repl[[n]]); x }
build <- function(inputs = INPUTS, hist = file.path(tmp, "hist.csv"), write = TRUE)
  mb_build_payload(inputs, season = S, now = as.POSIXct("2026-11-25 12:00:00", tz = "UTC"), teams = teams,
                   team_names = team_names, history_path = hist, write_history = write)

# ---- 2. window values and carry-over -------------------------------------------
H0 <- data.frame(season = c(S - 1L, S - 1L, S, S), team = "X", x = c(1, 3, 10, 20), game_date = as.Date("2026-01-01") + 0:3, game_id = letters[1:4])
avg <- c(setNames(2, S - 1L), setNames(15, S))
ok("MB-10 window mean with no carried games is the plain mean", isTRUE(all.equal(mb_window_mean(H0, 3:4, "x", S, 2, avg), 15)))
# carried values 1 and 3 pulled 50% toward last season's average 2 -> 1.5, 2.5
ok("MB-11 mean_regress pulls carried games toward their season's average",
   isTRUE(all.equal(mb_window_mean(H0, 1:4, "x", S, 4, avg), mean(c(1.5, 2.5, 10, 20)))))
ok("MB-12 two seasons back: keep^2", isTRUE(all.equal(mb_window_mean(H0, 1:2, "x", S + 1L, 2, avg), mean(2 + 0.25 * c(-1, 1)))))
ok("MB-13 a short window or a missing game gives NA",
   is.na(mb_window_mean(H0, 3:4, "x", S, 3, avg)) && { H1 <- H0; H1$x[3] <- NA; is.na(mb_window_mean(H1, 1:4, "x", S, 4, avg)) })

# ---- 3. standardisation and combined score -------------------------------------
z <- mb_zscore(c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, NA))
ok("MB-20 z-score: mean 0, sd 1 across teams, NA kept", abs(mean(z, na.rm = TRUE)) < 1e-12 && abs(sd(z, na.rm = TRUE) - 1) < 1e-12 && is.na(z[12]))
ok("MB-21 a component equal for every team standardises to 0", all(mb_zscore(rep(2, 12)) == 0))
ok("MB-22 fewer than MOMENTUM_BOARD_MIN_Z_TEAMS teams gives no value", all(is.na(mb_zscore(c(1:5, rep(NA, 7))))))
Z <- data.frame(form = c(1, -1), trend = c(NA, NA), residual = c(2, 2), elo_change = c(0.5, -0.5))
ok("MB-23 combined = sum of config weight x z; a zero-weight missing component does not null the score",
   isTRUE(all.equal(mb_combine(Z, MOMENTUM_BOARD_WEIGHTS[["6"]]), c(0.4 * 1 + 0.6 * 0.5, -0.4 - 0.3))))
ok("MB-24 a weighted missing component nulls the score", all(is.na(mb_combine(Z, MOMENTUM_BOARD_WEIGHTS[["9"]]))))

# ---- 4. payload ------------------------------------------------------------------
P <- build()
json <- mb_json_text(P)
J <- jsonlite::fromJSON(json, simplifyVector = FALSE)
ok("MB-30 windows 3/6/9, one board each with every team once",
   identical(unlist(J$windows), c(3L, 6L, 9L)) && all(vapply(J$boards, function(b) length(b$rows) == 12 && length(unique(vapply(b$rows, `[[`, "", "team"))) == 12, TRUE)))
ok("MB-31 through week 4, completed week 4, 3 noisiest", J$through_week == 4 && J$completed_week == 4 && isTRUE(J$boards[["3"]]$noisiest) && !isTRUE(J$boards[["6"]]$noisiest))
rowsw <- function(w) J$boards[[as.character(w)]]$rows
ok("MB-32 carried-game labelling: window 3 has none at week 4, 6 carries 2, 9 carries 5, from last season",
   all(vapply(rowsw(3), function(r) r$carried_games == 0 && is.null(r$carried_from_season), TRUE)) &&
     all(vapply(rowsw(6), function(r) r$carried_games == 2 && r$carried_from_season == S - 1L && r$current_season_games_in_window == 4, TRUE)) &&
     all(vapply(rowsw(9), function(r) r$carried_games == 5 && r$games_in_window == 9, TRUE)))
ok("MB-33 every team ranked from the carry-over; ranks 1..n", all(vapply(rowsw(6), `[[`, TRUE, "ranked")) &&
     identical(sort(vapply(rowsw(6), `[[`, 0L, "rank")), 1:12))
ok("MB-34 weights in the JSON equal the config constants (rows and methods)",
   all(vapply(c("3", "6", "9"), function(w) {
     cw <- MOMENTUM_BOARD_WEIGHTS[[w]]
     isTRUE(all.equal(unlist(J$methods$combined_score$weights[[w]])[names(cw)], cw)) &&
       all(vapply(J$boards[[w]]$rows, function(r) isTRUE(all.equal(unlist(r$combined_score$weights)[names(cw)], cw)), TRUE))
   }, TRUE)))
ok("MB-35 combined score = weighted sum of the published z-scores",
   all(vapply(c("3", "6", "9"), function(w) all(vapply(J$boards[[w]]$rows, function(r) {
     c <- r$combined_score$components; cw <- MOMENTUM_BOARD_WEIGHTS[[w]]
     abs(r$combined_score$value - (cw[["form"]] * c$form_z + cw[["trend"]] * c$trend_z + cw[["residual"]] * c$residual_z + cw[["elo_change"]] * c$elo_change_z)) < 0.005
   }, TRUE)), TRUE)))
ok("MB-36 standardised within the season-week: each component's z has mean 0 across teams",
   all(vapply(c("3", "6", "9"), function(w) { f <- vapply(J$boards[[w]]$rows, function(r) r$combined_score$components$form_z, 0)
     abs(mean(f)) < 0.01 && abs(sd(f) - 1) < 0.01 }, TRUE)))
flags <- do.call(c, lapply(J$boards, function(b) do.call(c, lapply(b$rows, `[[`, "flags"))))
ok("MB-37 no significance badge: every flag has significant = false", length(flags) == 3 * 12 * 11 && all(vapply(flags, function(f) identical(f$significant, FALSE), TRUE)))
ok("MB-38 every null flag value carries a reason", all(vapply(flags, function(f) !is.null(f$value) || (is.character(f$null_reason) && nzchar(f$null_reason)), TRUE)))
ok("MB-39 methods: no prediction beyond Elo, weights' source commit, hidden-badge reason",
   identical(J$methods$predictive_beyond_elo, FALSE) && grepl("not a forecast", J$methods$summary) &&
     J$methods$source$study_commit == MOMENTUM_BOARD_STUDY_COMMIT && grepl(MOMENTUM_BOARD_STUDY_COMMIT, J$methods$combined_score$weights_source) &&
     identical(J$methods$flags$significance_shown, FALSE) && grepl("Table 11", J$methods$flags$significance_hidden_reason))
t01 <- Filter(function(r) r$team == "T01", rowsw(3))[[1]]
qf <- Filter(function(f) f$key == "starting_qb_change", t01$flags)[[1]]
ok("MB-40 starting-QB change counted (T01 changed starter in week 3)", qf$value == 1 && qf$detail$current_starter$id == "QB-T01-B")
t02 <- Filter(function(r) r$team == "T02", rowsw(3))[[1]]
kf <- Filter(function(f) f$key == "key_players_missing", t02$flags)[[1]]
ok("MB-41 key players missing: T02's corner without snaps in week 2 -> 1 of 9 player-games", kf$n == 9 && abs(kf$value - 1 / 9) < 1e-4)
t03 <- Filter(function(r) r$team == "T03", rowsw(3))[[1]]
kf3 <- Filter(function(f) f$key == "key_players_missing", t03$flags)[[1]]
ok("MB-42 key players missing: listed Out counts as missed even with snaps", kf3$value > 0 && kf3$detail$listed_out == 1)
ok("MB-43 no betting vocabulary, NaN or Infinity in the JSON",
   !grepl("\\b(odds|spread|spreads|bet|bets|betting|wager|wagers|parlay|sportsbook|moneyline|picks?|props?|lines?|edges?)\\b", json, ignore.case = TRUE) &&
     !grepl("NaN|Infinity|\"NA\"", json))

# ---- 5. null-with-reason paths ---------------------------------------------------
kpm <- function(p, team = "T02") Filter(function(f) f$key == "key_players_missing", Filter(function(r) r$team == team, p$boards[["3"]]$rows)[[1]]$flags)[[1]]
p1 <- build(with_inputs(list(snaps = NULL)), hist = file.path(tmp, "h1.csv"), write = FALSE)
ok("MB-50 no snap counts: key players missing is null with a reason", is.na(kpm(p1)$value) && grepl("snap count", kpm(p1)$null_reason))
p2 <- build(with_inputs(list(injuries = NULL)), hist = file.path(tmp, "h2.csv"), write = FALSE)
ok("MB-51 no injury reports: key players missing is null with a reason", is.na(kpm(p2)$value) && grepl("injury", kpm(p2)$null_reason))
p3 <- build(with_inputs(list(snaps = SNAPS[SNAPS$week != 4, ])), hist = file.path(tmp, "h3.csv"), write = FALSE)
ok("MB-52 snap counts lagging a game: null with a reason, never estimated", is.na(kpm(p3)$value) && grepl("not yet available", kpm(p3)$null_reason))
p4 <- build(with_inputs(list(dna_pbp = NULL)), hist = file.path(tmp, "h4.csv"), write = FALSE)
q4 <- Filter(function(f) f$key == "starting_qb_change", p4$boards[["3"]]$rows[[1]]$flags)[[1]]
f4 <- Filter(function(f) f$key == "fumble_recovery", p4$boards[["3"]]$rows[[1]]$flags)[[1]]
ok("MB-53 no full play-by-play: QB change and fumble recovery null with reasons", is.na(q4$value) && nzchar(q4$null_reason) && is.na(f4$value) && nzchar(f4$null_reason))
pb <- INPUTS$pbp; pb <- pb[!(pb$season == S & pb$week == 4 & (pb$posteam == "T05" | pb$defteam == "T05")), ]
p5 <- build(with_inputs(list(pbp = pb)), hist = file.path(tmp, "h5.csv"), write = FALSE)
r5 <- Filter(function(r) r$team == "T05", p5$boards[["3"]]$rows)[[1]]
ok("MB-54 a game without play-by-play EPA: no score, not ranked, reason given",
   is.na(r5$combined_score$value) && is.na(r5$rank) && !r5$ranked && grepl("play-by-play", r5$combined_score$null_reason))
ok("MB-55 the week is not written to the rank history while a team is unranked",
   !file.exists(file.path(tmp, "h5.csv")) && grepl("not written", p5$methods$rank_history$note))

# ---- 6. rank history -------------------------------------------------------------
hp <- file.path(tmp, "hist.csv")
h1 <- read.csv(hp, stringsAsFactors = FALSE)
ok("MB-60 first run writes one row per team per window for the completed week",
   identical(names(h1), MB_HISTORY_COLUMNS) && nrow(h1) == 36 && all(h1$week == 4) && all(h1$reconstruction == FALSE) && isTRUE(P$methods$rank_history$written_this_run))
bytes1 <- readBin(hp, "raw", file.size(hp))
Pb <- build()
ok("MB-61 idempotent: a second run for the same week appends nothing", identical(readBin(hp, "raw", file.size(hp)), bytes1) && !isTRUE(Pb$methods$rank_history$written_this_run))
ok("MB-62 the JSON rank history comes from the file", length(Pb$boards[["6"]]$rows[[1]]$rank_history) == 1)
# week 5 completes
s5 <- SCHED; w5 <- s5$season == S & s5$week == 5; s5$home_score[w5] <- 24L; s5$away_score[w5] <- 20L
pl5 <- s5[w5, ]
in5 <- with_inputs(list(schedules = s5, pbp = rbind(PBP, do.call(rbind, lapply(seq_len(nrow(pl5)), function(i) mk_plays(pl5[i, ]))))))
in5$dna_pbp <- in5$pbp[in5$pbp$season == S, ]
in5$snaps <- rbind(SNAPS, transform(SNAPS[SNAPS$week == 4, ], week = 5L, game_id = NA_character_))
in5$snaps$game_id[is.na(in5$snaps$game_id)] <- pl5$game_id[match(in5$snaps$team[is.na(in5$snaps$game_id)], pl5$home_team)]
miss <- is.na(in5$snaps$game_id); in5$snaps$game_id[miss] <- pl5$game_id[match(in5$snaps$team[miss], pl5$away_team)]
P5 <- build(in5)
bytes2 <- readBin(hp, "raw", file.size(hp))
h2 <- read.csv(hp, stringsAsFactors = FALSE)
ok("MB-63 a new completed week appends 36 rows and leaves earlier rows byte-identical",
   nrow(h2) == 72 && identical(bytes2[seq_along(bytes1)], bytes1) && all(h2$week[37:72] == 5))
ok("MB-64 rank change vs last week computed from games", all(vapply(P5$boards[["6"]]$rows, function(r) !is.na(r$rank_last_week), TRUE)))
P5b <- build(in5)
ok("MB-65 re-running week 5 appends nothing", identical(readBin(hp, "raw", file.size(hp)), bytes2))
writeLines("a,b\n1,2", file.path(tmp, "bad.csv"))
ok("MB-66 a history file with a different header is refused, not rewritten",
   inherits(tryCatch(mb_append_history(file.path(tmp, "bad.csv"), h1), error = function(e) e), "error") &&
     identical(readLines(file.path(tmp, "bad.csv")), c("a,b", "1,2")))

# ---- 7. wiring -------------------------------------------------------------------
pipe <- paste(readLines("run_full_pipeline.R", warn = FALSE), collapse = "\n")
pub <- paste(readLines(file.path("tools", "publish_web.R"), warn = FALSE), collapse = "\n")
man <- paste(readLines(file.path("tools", "write_data_manifest.R"), warn = FALSE), collapse = "\n")
ok("MB-70 pipeline stage declared with its output and entry function",
   grepl('run_stage("build_momentum_board.R"', pipe, fixed = TRUE) && grepl('call_fn = "run_build_momentum_board"', pipe, fixed = TRUE) &&
     grepl("output = WEB_JSON_MOMENTUM_BOARD", pipe, fixed = TRUE) &&
     regexpr('run_stage("build_momentum_board.R"', pipe, fixed = TRUE) > regexpr('run_stage("team_ratings_engine.R"', pipe, fixed = TRUE) &&
     regexpr('run_stage("build_momentum_board.R"', pipe, fixed = TRUE) > regexpr('run_stage("build_passing_dataset.R"', pipe, fixed = TRUE))
ok("MB-71 publish step stages the rank history by exact path", grepl("MOMENTUM_RANK_HISTORY", pub, fixed = TRUE) && grepl("git add data/history/momentum_rank_history.csv", pub, fixed = TRUE))
ok("MB-72 manifest spec lists momentum_board.json with its builder", grepl('"momentum_board.json" = list(builder = "build_momentum_board.R"', man, fixed = TRUE))

unlink(tmp, recursive = TRUE)
cat(sprintf("\n%s: %d failure(s)\n", if (failures == 0L) "ALL PASSED" else "FAILED", failures))
if (failures > 0L) quit(status = 1L)
