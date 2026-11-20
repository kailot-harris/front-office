# ==============================================================================
# tests/test_coaching_dataset.R
# Offline tests for build_coaching_dataset.R and the coaching_profiles.json it
# publishes (NFL_analytics#171).
#   1. The minimum-sample constants match the spec table, and coaching_min_n()
#      applies max(floor, ceiling(per_game * games_coached)) without floating
#      point drift.
#   2. The pure helpers: mid-season coach changes, coach challenges vs booth
#      reviews, called timeouts vs timeouts charged for a lost challenge, the
#      go-rate exclusions and null-below-minimum figures.
#   3. The published JSON: 32 teams, generated_at / season present, no removed
#      field, every non-null figure has n >= min_n, and min_n equals the
#      formula for that team's games_coached.
#   4. Head coaches equal the schedule's coach for each team's latest game
#      (needs the gitignored CACHE_COACHING_SCHEDULES; prints [SKIP] without it).
#   5. A static check fails if the builder holds a literal table of named
#      coaches with numeric values.
#
# Runs via:
#   Rscript tests/test_coaching_dataset.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}
setwd(root_dir)
source("config.R")

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

load_ast_symbols <- function(path, symbols, env) {
  exprs <- parse(file = path, keep.source = FALSE)
  for (e in exprs) {
    if (is.call(e) && length(e) >= 3L &&
        as.character(e[[1L]]) %in% c("<-", "=") &&
        is.symbol(e[[2L]]) &&
        (as.character(e[[2L]]) %in% symbols || grepl("^COACHING_", as.character(e[[2L]])))) {
      eval(e, envir = env)
    }
  }
  env
}

BUILDER <- "build_coaching_dataset.R"
CE <- new.env(parent = globalenv())
load_ast_symbols(BUILDER, c(
  "coaching_min_sample_rules", "coaching_min_n", "coaching_figure", "coaching_flag",
  "coaching_team_games", "coaching_current_coach", "coaching_tenure", "coaching_career",
  "coaching_fourth_down_decisions", "coaching_go_rate", "coaching_nfl4th_rates",
  "coaching_challenges", "coaching_challenge_success", "coaching_called_timeouts",
  "coaching_timeout_q13_share"
), CE) |> invisible()

cat("=== build_coaching_dataset.R tests ===\n\n")

# ------------------------------------------------------------------------------
# 1. Minimum-sample constants and formula
# ------------------------------------------------------------------------------
spec_table <- data.frame(
  metric = c("fourth_down_go_rate", "nfl4th_go_when_recommended", "nfl4th_go_when_not_recommended",
             "pass_rate_over_expected", "early_down_pass_rate", "play_action_rate",
             "seconds_per_play", "challenge_success_rate", "epa_after_own_timeout",
             "timeouts_q1_q3_share", "unused_timeouts_close_losses"),
  per_game = c(1.5, 0.8, 1.5, 15, 15, 10, 15, 0.3, 0.8, 1.5, NA),
  floor = c(5, 3, 5, 40, 40, 30, 40, 2, 3, 5, 2),
  stringsAsFactors = FALSE
)
rules <- CE$coaching_min_sample_rules()
ok("COACH-1 the builder's minimum-sample constants match the spec section 4 table",
   identical(rules$metric, spec_table$metric) &&
     isTRUE(all.equal(rules$per_game, spec_table$per_game)) &&
     isTRUE(all.equal(as.numeric(rules$floor), spec_table$floor)),
   sprintf("%d rules", nrow(rules)))

src_lines <- readLines(BUILDER, warn = FALSE)
const_lines <- grep("^COACHING_MIN_(PER_GAME|FLOOR)_[A-Z0-9_]+ *<-", src_lines, value = TRUE)
ok("COACH-2 every per-game rate and floor is a named constant with a one-line comment",
   length(const_lines) == 19L && all(grepl("<- *[0-9.]+L? *#", const_lines)),
   sprintf("%d constants", length(const_lines)))

ok("COACH-3 coaching_min_n() = max(floor, ceiling(per_game * games)), exact on 0.3 * 10",
   CE$coaching_min_n(0.3, 2L, 10L) == 3L &&
     CE$coaching_min_n(0.3, 2L, 11L) == 4L &&
     CE$coaching_min_n(1.5, 5L, 9L) == 14L &&
     CE$coaching_min_n(0.8, 3L, 10L) == 8L &&
     CE$coaching_min_n(15, 40L, 1L) == 40L &&
     CE$coaching_min_n(NA_real_, 2L, 17L) == 2L,
   "3, 4, 14, 8, 40, 2")

f_low <- CE$coaching_figure(42.123, 4L, 5L, 1)
f_ok <- CE$coaching_figure(42.123, 5L, 5L, 1)
ok("COACH-4 a figure below its minimum publishes value NA (null) with n and min_n; at the minimum it publishes",
   is.na(f_low$value) && f_low$n == 4L && f_low$min_n == 5L && f_ok$value == 42.1)

# ------------------------------------------------------------------------------
# 2. Pure helpers on small hand-built frames (test inputs, never published)
# ------------------------------------------------------------------------------
sched <- data.frame(
  game_id = c("S1", "S2", "S3", "S4", "P1"),
  season = c(2026L, 2026L, 2026L, 2026L, 2025L),
  game_type = c("REG", "REG", "REG", "REG", "SB"),
  week = c(1L, 2L, 3L, 4L, 22L),
  gameday = c("2026-09-10", "2026-09-17", "2026-09-24", "2026-10-01", "2026-02-08"),
  home_team = c("AAA", "BBB", "AAA", "AAA", "AAA"),
  away_team = c("BBB", "AAA", "BBB", "BBB", "BBB"),
  home_coach = c("Coach One", "Coach Two", "Coach Three", "Coach Three", "Coach One"),
  away_coach = c("Coach Two", "Coach One", "Coach Two", "Coach Two", "Coach Two"),
  home_score = c(20, 10, 17, NA, 30),
  away_score = c(17, 24, 17, NA, 3),
  result = c(3, -14, 0, NA, 27),
  stringsAsFactors = FALSE
)
tg <- CE$coaching_team_games(sched)
cc <- CE$coaching_current_coach(tg, "AAA", 2026L)
ok("COACH-5 a mid-season change: the current coach is the latest played game's coach, since_week is his first week",
   cc$head_coach == "Coach Three" && cc$since_week == 3L && cc$games_coached == 1L &&
     identical(cc$game_ids, "S3") && cc$latest_game_id == "S3",
   sprintf("%s since week %d, %d game(s)", cc$head_coach, cc$since_week, cc$games_coached))

car <- CE$coaching_career(tg, "Coach One", history_start = 2025L)
ok("COACH-6 career record counts every team and the playoffs; Super Bowl wins and the 1999-style truncation flag",
   car$career_record == "3-0" && car$super_bowl_wins == 1L &&
     car$career_first_season == 2025L && isTRUE(car$career_possibly_truncated) &&
     CE$coaching_tenure(tg, "BBB", "Coach Two", 2026L) == 2L,
   sprintf("%s, SB %d, tenure BBB %d", car$career_record, car$super_bowl_wins,
           CE$coaching_tenure(tg, "BBB", "Coach Two", 2026L)))

team_names <- c(AAA = "Alpha City Ants", BBB = "Beta Town Bees")
plays <- data.frame(
  game_id = "G1", play_id = c(1, 2, 3, 4),
  home_team = "AAA", away_team = "BBB",
  desc = c("Pass incomplete. Alpha City challenged the incomplete pass ruling, and the play was REVERSED.",
           "Run for 2. Beta Town Bees challenged the first down ruling, and the play was Upheld. (Timeout #1.)",
           "Fumble. The Replay Official reviewed the fumble ruling, and the play was REVERSED.",
           "Timeout #2 by BBB at 05:00."),
  replay_or_challenge_result = c("reversed", "upheld", "reversed", NA),
  timeout = c(0, 1, 0, 1), timeout_team = c(NA, "BBB", NA, "BBB"), qtr = c(1, 2, 3, 4),
  stringsAsFactors = FALSE
)
ch <- CE$coaching_challenges(plays, team_names)
ok("COACH-7 coach challenges come from the description (booth reviews excluded), resolved by location or full name",
   nrow(ch) == 2L && identical(ch$team, c("AAA", "BBB")) && identical(ch$reversed, c(TRUE, FALSE)) &&
     CE$coaching_challenge_success(ch, "AAA")$value == 100,
   sprintf("%d challenges: %s", nrow(ch), paste(ch$team, collapse = ",")))

to <- CE$coaching_called_timeouts(plays)
ok("COACH-8 called timeouts are the stand-alone 'Timeout #N by' rows, not timeouts charged for a lost challenge",
   nrow(to) == 1L && to$play_id == 4 && CE$coaching_timeout_q13_share(to, "BBB")$value == 0)

fourth <- data.frame(
  game_id = "G1", play_id = 1:6, posteam = "AAA", down = 4,
  play_type = c("run", "punt", "pass", "field_goal", "pass", "no_play"),
  half_seconds_remaining = c(900, 900, 60, 900, 900, 900),
  yardline_100 = c(40, 60, 40, 30, 1, 40),
  go_boost = c(2.5, -3, 1, NA, 4, 1),
  stringsAsFactors = FALSE
)
dec <- CE$coaching_fourth_down_decisions(fourth)
gr <- CE$coaching_go_rate(dec, "AAA")
m4 <- CE$coaching_nfl4th_rates(dec, "AAA")
ok("COACH-9 go rate skips the last 2:00 and the opponent's 2-yard line; nfl4th rates skip decisions without go_boost",
   nrow(dec) == 5L && gr$n == 3L && abs(gr$value - 100 / 3) < 1e-9 &&
     m4$go_when_recommended$n == 3L && m4$go_when_recommended$value == 100 &&
     m4$go_when_not_recommended$n == 1L && m4$go_when_not_recommended$value == 0 &&
     m4$without_model_estimate == 1L,
   sprintf("go n=%d, should-go n=%d, should-kick n=%d, no estimate=%d",
           gr$n, m4$go_when_recommended$n, m4$go_when_not_recommended$n, m4$without_model_estimate))

# ------------------------------------------------------------------------------
# 3. The published JSON
# ------------------------------------------------------------------------------
json_path <- WEB_JSON_COACHING_PROFILES
j <- jsonlite::fromJSON(json_path, simplifyVector = FALSE)
removed <- c("offensive_coordinator", "defensive_coordinator", "play_caller", "offensive_play_caller",
             "defensive_play_caller", "offensive_scheme", "defensive_scheme", "timeout_management_grade",
             "fourth_down_aggression_index")
first_key <- names(j)[1]
ok("COACH-10 coaching_profiles.json has generated_at (first key), season = CURRENT_SEASON and 32 teams",
   identical(first_key, "generated_at") && grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", j$generated_at) &&
     identical(as.integer(j$season), as.integer(CURRENT_SEASON)) &&
     length(j$teams) == NFL_TEAM_COUNT &&
     setequal(vapply(j$teams, `[[`, character(1), "team"), names(NFL_TEAMS)),
   sprintf("%d teams, season %s", length(j$teams), j$season))

all_keys <- unique(unlist(lapply(j$teams, names)))
ok("COACH-11 no removed field (staff, scheme, grade, aggression index) is present",
   !any(removed %in% c(all_keys, names(j))),
   paste(intersect(removed, all_keys), collapse = ","))

json_rules <- do.call(rbind, lapply(j$min_sample_rules, function(r)
  data.frame(metric = r$metric, per_game = if (is.null(r$per_game)) NA_real_ else r$per_game,
             floor = r$floor, stringsAsFactors = FALSE)))
ok("COACH-12 the JSON's min_sample_rules equal the builder constants",
   identical(json_rules$metric, rules$metric) &&
     isTRUE(all.equal(json_rules$per_game, rules$per_game)) &&
     isTRUE(all.equal(as.numeric(json_rules$floor), as.numeric(rules$floor))))

bad_n <- character(0)
bad_min <- character(0)
for (t in j$teams) {
  for (i in seq_len(nrow(json_rules))) {
    m <- json_rules$metric[i]
    fig <- t[[m]]
    if (is.null(fig) || is.null(fig$n) || is.null(fig$min_n)) {
      bad_min <- c(bad_min, sprintf("%s %s missing", t$team, m))
      next
    }
    want <- CE$coaching_min_n(json_rules$per_game[i], json_rules$floor[i], t$games_coached)
    if (fig$min_n != want) bad_min <- c(bad_min, sprintf("%s %s min_n=%d want %d", t$team, m, fig$min_n, want))
    if (!is.null(fig$value) && fig$n < fig$min_n) bad_n <- c(bad_n, sprintf("%s %s n=%d < %d", t$team, m, fig$n, fig$min_n))
  }
}
ok("COACH-13 every non-null figure has n >= min_n", length(bad_n) == 0L, paste(head(bad_n, 5), collapse = "; "))
ok("COACH-14 every min_n equals max(floor, ceiling(per_game * games_coached)) for that team",
   length(bad_min) == 0L, paste(head(bad_min, 5), collapse = "; "))

# ------------------------------------------------------------------------------
# 4. Head coaches against the schedule (gitignored cache)
# ------------------------------------------------------------------------------
if (file.exists(CACHE_COACHING_SCHEDULES)) {
  s <- readRDS(CACHE_COACHING_SCHEDULES)
  mism <- character(0)
  for (t in j$teams) {
    g <- s[s$game_id == t$latest_game_id, , drop = FALSE]
    want <- if (nrow(g) != 1L) NA_character_ else if (g$home_team == t$team) g$home_coach else g$away_coach
    later <- s[s$season == j$season & !is.na(s$result) & (s$home_team == t$team | s$away_team == t$team) &
                 s$week > g$week, , drop = FALSE]
    if (!identical(want, t$head_coach) || nrow(later) > 0L) mism <- c(mism, t$team)
  }
  ok("COACH-15 every head coach is the schedule's coach for that team's latest played game",
     length(mism) == 0L, paste(mism, collapse = ","))
} else {
  cat(sprintf("[SKIP] COACH-15 needs %s (written by build_coaching_dataset.R)\n", CACHE_COACHING_SCHEDULES))
}

# ------------------------------------------------------------------------------
# 5. Static check: no literal table of named coaches with numeric values
# ------------------------------------------------------------------------------
# Walks the parsed builder. A call (c, list, data.frame, tibble, tribble, ...)
# whose literal arguments hold two or more person-like names ("First Last") and
# at least one number is a hand-typed coach table. Any string literal equal to a
# published head coach's name also fails.
TABLE_CONSTRUCTORS <- c("data.frame", "tibble", "tribble", "data.table", "list", "setNames", "structure", "cbind", "rbind")

# Every literal leaf (string or number) inside an expression, plus string argument names.
leaves <- function(e) {
  out <- list()
  if (is.character(e) || is.numeric(e)) return(as.list(e))
  if (is.call(e) || is.pairlist(e) || is.expression(e)) {
    nm <- names(e)
    if (!is.null(nm)) out <- c(out, as.list(nm[nzchar(nm)]))
    for (k in seq_along(e)) {
      if (is.symbol(e[[k]]) && !nzchar(as.character(e[[k]]))) next
      if (!is.null(e[[k]])) out <- c(out, leaves(e[[k]]))
    }
  }
  out
}

find_coach_tables <- function(path, coach_names = character(0)) {
  exprs <- parse(file = path, keep.source = FALSE)
  hits <- character(0)
  person <- "^[A-Z][a-z]+(['-][A-Za-z]+)?( [A-Z][a-zA-Z'.-]+)+$"
  walk <- function(e) {
    if (is.character(e) && length(e) == 1L && e %in% coach_names) {
      hits <<- c(hits, sprintf("literal coach name \"%s\"", e))
    }
    if (is.call(e)) {
      args <- as.list(e)[-1]
      lits <- Filter(function(a) is.character(a) || is.numeric(a), args)
      named <- Filter(function(a) is.character(a) && length(a) == 1L && grepl(person, a), lits)
      nums <- Filter(is.numeric, lits)
      # names given as argument names, e.g. c("Jane Doe" = 61, ...)
      arg_names <- names(args)
      named_args <- if (is.null(arg_names)) character(0) else arg_names[grepl(person, arg_names)]
      # Table constructors: count literals anywhere inside the call, so parallel
      # columns (coach = c("A B", ...), value = c(1, ...)) are caught too.
      deep <- if (is.symbol(e[[1L]]) && as.character(e[[1L]]) %in% TABLE_CONSTRUCTORS) leaves(e) else list()
      deep_named <- Filter(function(a) is.character(a) && grepl(person, a), deep)
      deep_nums <- Filter(is.numeric, deep)
      if ((length(named) >= 2L && length(nums) >= 1L) ||
          (length(named_args) >= 2L && length(nums) >= 1L) ||
          (length(deep_named) >= 2L && length(deep_nums) >= 1L)) {
        hits <<- c(hits, paste(deparse(e, width.cutoff = 60L)[1], "..."))
      }
      for (k in seq_along(args)) {
        if (is.symbol(args[[k]]) && !nzchar(as.character(args[[k]]))) next  # empty arg, e.g. x[i, ]
        if (!is.null(args[[k]])) walk(args[[k]])
      }
    } else if (is.expression(e) || is.list(e) || is.pairlist(e)) {
      for (k in seq_along(e)) {
        if (is.symbol(e[[k]]) && !nzchar(as.character(e[[k]]))) next  # formal with no default
        if (!is.null(e[[k]])) walk(e[[k]])
      }
    }
  }
  for (e in exprs) walk(e)
  unique(hits)
}

published_coaches <- vapply(j$teams, `[[`, character(1), "head_coach")
planted <- tempfile(fileext = ".R")
writeLines(c(
  'coach_table <- data.frame(',
  '  coach = c("Jane Doe", "John Roe"),',
  '  go_rate = c(21.4, 12.9)',
  ')',
  'grades <- c("Jane Doe" = 61, "John Roe" = 44)',
  'tribble_like <- list("Jane Doe", 12.5, "John Roe", 9.1)'
), planted)
planted_hits <- find_coach_tables(planted)
unlink(planted)
ok("COACH-16 the static check catches each planted literal coach table (self-test)",
   length(planted_hits) >= 3L &&
     any(grepl("^data.frame", planted_hits)) && any(startsWith(planted_hits, "c(")) &&
     any(grepl("^list", planted_hits)), sprintf("%d hit(s) on the planted file", length(planted_hits)))

builder_hits <- find_coach_tables(BUILDER, published_coaches)
ok("COACH-17 build_coaching_dataset.R holds no literal table of named coaches with numeric values",
   length(builder_hits) == 0L, if (length(builder_hits)) paste(builder_hits, collapse = " | ") else "clean")

cat("\n")
if (failures > 0L) {
  cat(sprintf("=== TEST FAILURES: %d failure(s) ===\n", failures))
  quit(status = 1L)
}
cat("=== ALL TESTS PASSED: 0 failure(s) ===\n")
