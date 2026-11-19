# ==============================================================================
# tests/test_clutch_pre_play_margin.R
#
# Regression suite for NBA_analytics#187: build_clutch_dataset.R must compute
# score margin from the PRE-PLAY score (entering each play within game_id)
# rather than the post-play score on the play row.
#
# Post-play margin created survivorship bias:
#   - Made shots pushing a 4-5 pt lead past 5 were dropped as "non-clutch"
#     while misses from the exact same score were kept.
#   - Trailing shots from a 6-8 pt deficit that cut the lead to <= 5 were
#     falsely kept as "clutch".
#
# Runs completely in-memory / tempdir() with NBA_SKIP_STAGE_AUTORUN=1 so it
# requires no cache/ directory or network access.
#
# Usage: Rscript tests/test_clutch_pre_play_margin.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

section <- function(title) cat(sprintf("\n== %s ==\n", title))

# ------------------------------------------------------------------------------
section("1. Isolated sourcing of build_clutch_dataset.R from scratch cwd")
# ------------------------------------------------------------------------------

old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA_character_)
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
on.exit({
  if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
  else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
}, add = TRUE)

orig_wd <- getwd()
scratch_cwd <- tempfile("clutch_cwd_")
dir.create(scratch_cwd, recursive = TRUE)
setwd(scratch_cwd)

clutch_env <- new.env(parent = globalenv())
source(file.path(REPO_ROOT, "build_clutch_dataset.R"), local = clutch_env)

ok("build_clutch_dataset.R loads from scratch cwd without changing working directory",
   identical(normalizePath(getwd(), winslash = "/", mustWork = FALSE),
             normalizePath(scratch_cwd, winslash = "/", mustWork = FALSE)))
setwd(orig_wd)
unlink(scratch_cwd, recursive = TRUE)

ok("PROJECT_DIR in clutch_env resolves to REPO_ROOT",
   identical(normalizePath(clutch_env$PROJECT_DIR, winslash = "/", mustWork = FALSE),
             normalizePath(REPO_ROOT, winslash = "/", mustWork = FALSE)))
ok("compute_pre_play_margin, filter_clutch_pbp, and build_clutch_dataset are defined",
   is.function(clutch_env$compute_pre_play_margin) &&
     is.function(clutch_env$filter_clutch_pbp) &&
     is.function(clutch_env$build_clutch_dataset))

compute_pre_play_margin <- clutch_env$compute_pre_play_margin
filter_clutch_pbp       <- clutch_env$filter_clutch_pbp
build_clutch_dataset    <- clutch_env$build_clutch_dataset

# Helper to build synthetic play rows
mk_play <- function(play_id, game_id, gpn, period, min, sec,
                    home_score, away_score,
                    shooting_play = TRUE, scoring_play = FALSE,
                    points_attempted = 2L, type_text = "Jump Shot",
                    team_id = "1", athlete_id_1 = "101",
                    athlete_id_2 = NA_character_,
                    home_team_id = "1") {
  data.frame(
    play_id = play_id,
    game_id = game_id,
    game_date = as.Date("2026-11-15"),
    game_play_number = gpn,
    period_number = period,
    clock_minutes = min,
    clock_seconds = sec,
    home_score = home_score,
    away_score = away_score,
    team_id = team_id,
    home_team_id = home_team_id,
    athlete_id_1 = athlete_id_1,
    athlete_id_2 = athlete_id_2,
    shooting_play = shooting_play,
    scoring_play = scoring_play,
    points_attempted = points_attempted,
    type_text = type_text,
    text = type_text,
    coordinate_x = 0,
    coordinate_y = 25,
    stringsAsFactors = FALSE
  )
}

# ------------------------------------------------------------------------------
section("2. Pre-play margin retains 4Q/OT makes pushing lead past 5 & drops >5 starts")
# ------------------------------------------------------------------------------

pbp_core <- bind_rows(
  # Game G1: starts Q1 0-0, enters Q4 at 98-95 (margin 3), then:
  mk_play("G1_q1",   "G1", 1L, 1L, 12L, 0L,   0,  0, FALSE, FALSE, 0L, "Jump Ball"),
  mk_play("G1_q3",   "G1", 2L, 3L,  0L, 1L,  98, 95, FALSE, FALSE, 0L, "End Period"),
  # 4Q 4:10: Home makes 3PT from 98-95 -> 101-95 (pre=3 <= 5, post=6 > 5) => RETAIN
  mk_play("G1_make_3_to_6", "G1", 3L, 4L, 4L, 10L, 101, 95, TRUE, TRUE, 3L, "Three Point Jumper"),
  # 4Q 3:50: Away misses 2PT starting at 101-95 (pre=6 > 5) => EXCLUDE
  mk_play("G1_miss_from_6", "G1", 4L, 4L, 3L, 50L, 101, 95, TRUE, FALSE, 2L, "Jump Shot", team_id = "2", athlete_id_1 = "201"),
  # 4Q 3:30: Home makes 2PT starting at 101-95 -> 103-95 (pre=6 > 5) => EXCLUDE
  mk_play("G1_make_from_6", "G1", 5L, 4L, 3L, 30L, 103, 95, TRUE, TRUE, 2L, "Driving Layup"),
  # 4Q 3:10: Away makes 3PT starting at 103-95 -> 103-98 (pre=8 > 5, post=5 <= 5) => EXCLUDE
  mk_play("G1_make_8_to_5", "G1", 6L, 4L, 3L, 10L, 103, 98, TRUE, TRUE, 3L, "Three Point Jumper", team_id = "2", athlete_id_1 = "201"),
  # 4Q 2:40: Home makes 2PT starting at 103-98 -> 105-98 (pre=5 <= 5, post=7 > 5) => RETAIN
  mk_play("G1_make_5_to_7", "G1", 7L, 4L, 2L, 40L, 105, 98, TRUE, TRUE, 2L, "Jump Shot"),
  # 4Q 2:10: Away hits 3PT (105-101, pre=7 > 5 => EXCLUDE), then Home makes 2PT from 105-101 -> 107-101 (pre=4 <= 5, post=6 > 5) => RETAIN
  mk_play("G1_make_7_to_4", "G1", 8L, 4L, 2L, 20L, 105, 101, TRUE, TRUE, 3L, "Three Point Jumper", team_id = "2", athlete_id_1 = "201"),
  mk_play("G1_make_4_to_6", "G1", 9L, 4L, 2L, 10L, 107, 101, TRUE, TRUE, 2L, "Driving Layup"),

  # Game G2: tests game_id isolation right after G1 ended at 105-98, plus OT make 5->8
  mk_play("G2_q1",          "G2", 1L, 1L, 12L,  0L,   0,   0, FALSE, FALSE, 0L, "Jump Ball"),
  # 4Q exact 5:00 boundary at 95-90 (pre=5 <= 5) -> 95-90 miss => RETAIN
  mk_play("G2_q4_setup",    "G2", 2L, 4L,  5L,  5L,  95,  90, FALSE, FALSE, 0L, "Turnover"),
  mk_play("G2_q4_500_miss", "G2", 3L, 4L,  5L,  0L,  95,  90, TRUE,  FALSE, 2L, "Jump Shot"),
  # 4Q 5:01 outside clock window => EXCLUDE
  mk_play("G2_q3_late",     "G2", 1L, 3L,  0L, 10L,  70,  70, TRUE,  TRUE,  2L, "Jump Shot"),
  # End Q4 tied 100-100, then OT (period 5) up 105-100 and Home hits 3PT -> 108-100 (pre=5, post=8) => RETAIN
  mk_play("G2_q4_tie",      "G2", 4L, 4L,  0L,  0L, 100, 100, FALSE, FALSE, 0L, "End Period"),
  mk_play("G2_ot_setup",    "G2", 5L, 5L,  3L,  0L, 105, 100, FALSE, FALSE, 0L, "Made Free Throw"),
  mk_play("G2_ot_make_5_8", "G2", 6L, 5L,  2L, 20L, 108, 100, TRUE,  TRUE,  3L, "Three Point Jumper")
)

scored <- compute_pre_play_margin(pbp_core)
clutch_res <- filter_clutch_pbp(pbp_core)
kept_ids <- clutch_res$play_id

ok("4Q made 3PT pushing margin 3 -> 6 is retained",
   "G1_make_3_to_6" %in% kept_ids)
ok("4Q made 2PT pushing margin 4 -> 6 is retained",
   "G1_make_4_to_6" %in% kept_ids)
ok("4Q made 2PT pushing margin 5 -> 7 is retained",
   "G1_make_5_to_7" %in% kept_ids)
ok("OT made 3PT pushing margin 5 -> 8 is retained",
   "G2_ot_make_5_8" %in% kept_ids)
ok("4Q exact 5:00 boundary at pre-play margin 5 is retained",
   "G2_q4_500_miss" %in% kept_ids)
ok("4Q shot starting at pre-play margin 6 (miss) is excluded",
   !("G1_miss_from_6" %in% kept_ids))
ok("4Q shot starting at pre-play margin 6 (make 6 -> 8) is excluded",
   !("G1_make_from_6" %in% kept_ids))
ok("4Q trailing 3PT starting at margin 8 -> 5 is excluded (pre-play margin > 5)",
   !("G1_make_8_to_5" %in% kept_ids))
ok("Q3 play with margin 0 is excluded by period >= 4",
   !("G2_q3_late" %in% kept_ids))
ok("Game G2 row 1 does not inherit G1 ending score (pre-play score is 0-0)",
   scored$pre_home_score[scored$play_id == "G2_q1"] == 0 &&
     scored$pre_away_score[scored$play_id == "G2_q1"] == 0)

# ------------------------------------------------------------------------------
section("3. Ordering invariance, NA score carry-forward, and truncated Q4 slices")
# ------------------------------------------------------------------------------

set.seed(187)
shuffled <- pbp_core[sample(nrow(pbp_core)), ]
clutch_shuffled <- filter_clutch_pbp(shuffled)
ok("Shuffled row order with game_play_number yields identical clutch play_ids",
   setequal(clutch_shuffled$play_id, kept_ids))

# Fallback ordering when neither game_play_number nor sequence_number is present
no_gpn <- pbp_core[, setdiff(names(pbp_core), "game_play_number")]
no_gpn_shuffled <- no_gpn[sample(nrow(no_gpn)), ]
clutch_no_gpn <- filter_clutch_pbp(no_gpn_shuffled)
ok("Fallback ordering by period_number + descending sec_remaining works without game_play_number",
   all(c("G1_make_3_to_6", "G1_make_5_to_7", "G2_ot_make_5_8") %in% clutch_no_gpn$play_id) &&
     !("G1_make_from_6" %in% clutch_no_gpn$play_id) &&
     !("G1_make_8_to_5" %in% clutch_no_gpn$play_id))

# NA running score on an administrative play amid two clutch plays
pbp_na <- bind_rows(
  mk_play("NA_1", "G_NA", 1L, 1L, 12L, 0L, 0, 0, FALSE, FALSE, 0L, "Jump Ball"),
  mk_play("NA_2", "G_NA", 2L, 4L, 4L, 0L, 100, 95, FALSE, FALSE, 0L, "Rebound"),
  mk_play("NA_3", "G_NA", 3L, 4L, 3L, 50L, NA_real_, NA_real_, FALSE, FALSE, 0L, "Official Timeout"),
  mk_play("NA_4", "G_NA", 4L, 4L, 3L, 30L, 103, 95, TRUE, TRUE, 3L, "Three Point Jumper")
)
clutch_na <- filter_clutch_pbp(pbp_na)
ok("NA score row carried forward: subsequent made 3PT retains pre-play margin 5 and is kept",
   "NA_4" %in% clutch_na$play_id &&
     all(!is.na(clutch_na$play_id)))

# Truncated Q4-only slice where row 1 is already a blowout (110-100)
pbp_trunc <- bind_rows(
  mk_play("T_1", "G_TRUNC", 1L, 4L, 4L, 30L, 110, 100, FALSE, FALSE, 0L, "Rebound"),
  mk_play("T_2", "G_TRUNC", 2L, 4L, 4L, 10L, 110, 103, TRUE, TRUE, 3L, "Three Point Jumper", team_id = "2")
)
clutch_trunc <- filter_clutch_pbp(pbp_trunc)
ok("Truncated Q4-only slice starting at margin 10 does not invent 0-0 on row 1",
   nrow(clutch_trunc) == 0L)

# Empty PBP edge case
empty_res <- filter_clutch_pbp(pbp_core[0, ])
ok("Empty PBP frame returns 0 rows cleanly with margin column",
   is.data.frame(empty_res) && nrow(empty_res) == 0L && "margin" %in% names(empty_res))

# ------------------------------------------------------------------------------
section("4. End-to-end build_clutch_dataset() counts made clutch 3PT pushing 5 -> 8")
# ------------------------------------------------------------------------------

tmp_dir <- tempfile("clutch_e2e_")
dir.create(tmp_dir, recursive = TRUE)
on.exit(unlink(tmp_dir, recursive = TRUE), add = TRUE)

proj_path <- file.path(tmp_dir, "projections.json")
pbp_path  <- file.path(tmp_dir, "pbp.rds")
box_path  <- file.path(tmp_dir, "box.rds")
out_json  <- file.path(tmp_dir, "clutch_out.json")
out_cache <- file.path(tmp_dir, "cache")

players_tbl <- data.frame(
  player_id = c("101", "201"),
  player_name = c("Player One", "Player Two"),
  position = c("G", "F"),
  team = c("BOS", "NYK"),
  proj_pts = c(24.0, 18.0),
  stringsAsFactors = FALSE
)
jsonlite::write_json(players_tbl, proj_path, auto_unbox = TRUE)

pbp_e2e <- bind_rows(
  mk_play("E_q1",   "GE", 1L, 1L, 12L,  0L,   0,  0, FALSE, FALSE, 0L, "Jump Ball", athlete_id_1 = NA_character_),
  # Score entering clutch: 100 - 95 (margin = 5)
  mk_play("E_pre",  "GE", 2L, 4L,  4L, 50L, 100, 95, FALSE, FALSE, 0L, "Defensive Rebound", athlete_id_1 = "101"),
  # Player One hits 3PT pushing lead 100-95 -> 103-95 (pre=5 <= 5, post=8 > 5)
  mk_play("E_make", "GE", 3L, 4L,  4L, 30L, 103, 95, TRUE,  TRUE,  3L, "Three Point Jumper", athlete_id_1 = "101"),
  # Player One takes another 2PT when already up 8 (103-95 -> 105-95, pre=8 > 5) => excluded
  mk_play("E_out",  "GE", 4L, 4L,  4L,  5L, 105, 95, TRUE,  TRUE,  2L, "Jump Shot", athlete_id_1 = "101"),
  # Player Two hits 3PT while down 10 (105-95 -> 105-98, pre=10 > 5) => excluded
  mk_play("E_p2",   "GE", 5L, 4L,  3L, 40L, 105, 98, TRUE,  TRUE,  3L, "Three Point Jumper", team_id = "2", athlete_id_1 = "201")
)
saveRDS(pbp_e2e, pbp_path)

box_e2e <- data.frame(
  game_date = as.Date(c("2026-11-15", "2026-11-15")),
  athlete_id = c("101", "201"),
  minutes = c(34, 32),
  points = c(25, 19),
  field_goals_attempted = c(18, 15),
  field_goals_made = c(9, 7),
  free_throws_attempted = c(4, 3),
  free_throws_made = c(4, 2),
  turnovers = c(2, 1),
  stringsAsFactors = FALSE
)
saveRDS(box_e2e, box_path)

invisible(capture.output(suppressMessages(
  res_payload <- build_clutch_dataset(
    proj_players_file = proj_path,
    pbp_file = pbp_path,
    box_file = box_path,
    output_json = out_json,
    cache_dir = out_cache
  )
)))

written <- jsonlite::fromJSON(out_json, simplifyVector = FALSE)
p_one <- written$profiles[[1]]
p_two <- written$profiles[[2]]

ok("End-to-end build retains Player One's 5->8 made 3PT (clutchFga == 1, three.fgm == 1) and excludes margin-8 shot",
   identical(as.integer(p_one$clutchFga), 1L) &&
     identical(as.integer(p_one$shotBreakdown$three$fga), 1L) &&
     identical(as.integer(p_one$shotBreakdown$three$fgm), 1L))
ok("End-to-end build excludes Player Two's shot from margin > 5 (clutchFga == 0)",
   identical(as.integer(p_two$clutchFga), 0L))
ok("End-to-end build writes cache/clutch_leverage_metrics.rds cleanly",
   file.exists(file.path(out_cache, "clutch_leverage_metrics.rds")))

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
