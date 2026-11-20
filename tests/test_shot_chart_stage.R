# ==============================================================================
# tests/test_shot_chart_stage.R
#
# Offline regression suite for NBA_analytics#192:
#   1. build_shot_chart_dataset.R portable config.R bootstrap, foreign-cwd load
#      under NBA_SKIP_STAGE_AUTORUN=1, CURRENT_SEASON default +
#      NBA_SHOT_CHART_SEASON env override, CACHE_DIR/WEB_DATA_DIR usage,
#      generated_at (UTC ISO-8601) + through_date (YYYY-MM-DD or JSON null),
#      and pruning stale shots/<id>.json files for 1-to-1 sync with shots_index.json.
#   2. run_full_pipeline.R registers build_shot_chart_dataset.R after both
#      shot_quality_engine.R and season_simulator.R with declared outputs
#      shots_index.json and shots_metadata.json.
#   3. tools/publish_web.R .pw_do_publish uses `git add -A` so added, modified,
#      and removed per-player shot files are all staged and committed.
#
# Usage: Rscript tests/test_shot_chart_stage.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
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
canon <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)

bootstrap_code <- function(path) {
  for (e in parse(path)) {
    if (is.call(e) && length(e) == 3L &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) && identical(as.character(e[[2]]), ".THIS_DIR")) {
      return(paste(deparse(e[[3]]), collapse = "\n"))
    }
  }
  NA_character_
}

# ------------------------------------------------------------------------------
section("1. Static checks, portable bootstrap, and foreign-cwd loading")
# ------------------------------------------------------------------------------

shot_script <- file.path(REPO_ROOT, "build_shot_chart_dataset.R")
ref_script  <- file.path(REPO_ROOT, "prediction_accuracy_logger.R")

shot_lines <- readLines(shot_script, warn = FALSE)
code_lines <- sub("#.*$", "", shot_lines)

ok("build_shot_chart_dataset.R has no hardcoded authoring path",
   !any(grepl("[A-Za-z]:[/\\\\]Users[/\\\\][A-Za-z0-9_]", shot_lines, ignore.case = TRUE)))
ok("build_shot_chart_dataset.R never calls setwd()",
   !any(grepl("setwd(", code_lines, fixed = TRUE)))
ok("build_shot_chart_dataset.R has no cwd-relative source()",
   !any(startsWith(shot_lines, "source(\"")))
ok("build_shot_chart_dataset.R has no bare relative web/public/data or cache/nba_shots paths",
   !any(grepl("\"web/public/data|\"cache/nba_shots_", code_lines)))
ok("build_shot_chart_dataset.R .THIS_DIR matches prediction_accuracy_logger.R",
   identical(bootstrap_code(shot_script), bootstrap_code(ref_script)))

scratch_dir <- file.path(tempdir(), "shot_chart_scratch_cwd")
if (dir.exists(scratch_dir)) unlink(scratch_dir, recursive = TRUE)
dir.create(scratch_dir, recursive = TRUE)
on.exit(unlink(scratch_dir, recursive = TRUE), add = TRUE)

old_wd <- canon(getwd())
old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
old_season_env <- Sys.getenv("NBA_SHOT_CHART_SEASON", unset = NA)

env_default <- new.env(parent = globalenv())
local({
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  Sys.unsetenv("NBA_SHOT_CHART_SEASON")
  setwd(scratch_dir)
  on.exit({
    setwd(old_wd)
    if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
    else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
    if (is.na(old_season_env)) Sys.unsetenv("NBA_SHOT_CHART_SEASON")
    else Sys.setenv(NBA_SHOT_CHART_SEASON = old_season_env)
  }, add = TRUE)
  wd_during <<- canon(getwd())
  suppressMessages(suppressWarnings(
    capture.output(source(shot_script, local = env_default))
  ))
  wd_after <<- canon(getwd())
})

ok("sourced build_shot_chart_dataset.R from outside repo root",
   !identical(wd_during, canon(REPO_ROOT)))
ok("sourcing left working directory unchanged",
   identical(wd_after, wd_during))
ok("PROJECT_DIR resolved to repo checkout",
   identical(canon(env_default$PROJECT_DIR), canon(REPO_ROOT)))
ok("CACHE_DIR resolved under repo checkout",
   identical(canon(env_default$CACHE_DIR), canon(file.path(REPO_ROOT, "cache"))))
ok("WEB_DATA_DIR resolved under repo checkout",
   identical(canon(env_default$WEB_DATA_DIR), canon(file.path(REPO_ROOT, "web", "public", "data"))))
ok("build_shot_chart_dataset() exported as a function",
   is.function(env_default$build_shot_chart_dataset))
ok("SHOT_CHART_SEASON defaults to CURRENT_SEASON when NBA_SHOT_CHART_SEASON is unset",
   identical(as.integer(env_default$SHOT_CHART_SEASON), as.integer(env_default$CURRENT_SEASON)))

env_override <- new.env(parent = globalenv())
local({
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1", NBA_SHOT_CHART_SEASON = "2026")
  on.exit({
    if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
    else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
    if (is.na(old_season_env)) Sys.unsetenv("NBA_SHOT_CHART_SEASON")
    else Sys.setenv(NBA_SHOT_CHART_SEASON = old_season_env)
  }, add = TRUE)
  suppressMessages(suppressWarnings(
    capture.output(source(shot_script, local = env_override))
  ))
})
ok("SHOT_CHART_SEASON honors NBA_SHOT_CHART_SEASON env override",
   identical(as.integer(env_override$SHOT_CHART_SEASON), 2026L))

# Load publish_web.R in isolated env so we can verify .pw_payload_generated_at()
pw_env <- new.env(parent = globalenv())
local({
  wd_before <- getwd()
  on.exit(setwd(wd_before), add = TRUE)
  source(file.path(REPO_ROOT, "tools", "publish_web.R"), local = pw_env)
})

# ------------------------------------------------------------------------------
section("2. Temp sandbox: CURRENT_SEASON, timestamps, through_date, pruning & sync")
# ------------------------------------------------------------------------------

sb_root <- file.path(tempdir(), "shot_chart_sandbox")
if (dir.exists(sb_root)) unlink(sb_root, recursive = TRUE)
sb_cache <- file.path(sb_root, "cache")
sb_web   <- file.path(sb_root, "web_data")
sb_shots <- file.path(sb_web, "shots")
dir.create(sb_cache, recursive = TRUE)
dir.create(sb_shots, recursive = TRUE)
on.exit(unlink(sb_root, recursive = TRUE), add = TRUE)

players_fixture <- data.frame(
  player_id   = c("101", "102", "103"),
  player_name = c("Alpha Guard", "Beta Wing", "Gamma Center"),
  team        = c("LAL", "BOS", "OKC"),
  stringsAsFactors = FALSE
)
write_json(players_fixture, file.path(sb_web, "projections_season_players.json"),
           auto_unbox = TRUE, pretty = TRUE)

make_shots_df <- function(season_val, with_game_date = TRUE, all_na_date = FALSE,
                          include_players = c("101", "102")) {
  rows <- list()
  add_row <- function(aid, aname, tm, sx, sy, sv, made, tt, per, clk, gd) {
    rows[[length(rows) + 1L]] <<- data.frame(
      athlete_id_1        = aid,
      athlete_name_1      = aname,
      team_abbrev         = tm,
      coordinate_x_raw    = sx,
      coordinate_y_raw    = sy,
      score_value         = sv,
      scoring_play        = made,
      type_text           = tt,
      period_number       = per,
      clock_display_value = clk,
      season              = season_val,
      game_date           = gd,
      stringsAsFactors    = FALSE
    )
  }

  if ("101" %in% include_players) {
    add_row("101", "Alpha Guard", "LAL", 25.0, 2.0, 2L, TRUE,  "Driving Layup Shot", 1L, "1:08:45", "2026-11-10")
    add_row("101", "Alpha Guard", "LAL", 48.0, 4.0, 3L, FALSE, "Jump Shot",          2L, "5:12",    "2026-11-15")
    # Free throw must be filtered out of FGA counts and per-player shots
    add_row("101", "Alpha Guard", "LAL", 25.0, 15.0, 1L, TRUE, "Free Throw 1 of 2",  2L, "4:00",    "2026-11-12")
  }
  if ("102" %in% include_players) {
    add_row("102", "Beta Wing",   "BOS", 2.0, 4.0, 3L, TRUE,   "Jump Shot",          3L, "9:30",    "2026-11-14")
  }
  if ("103" %in% include_players) {
    add_row("103", "Gamma Center", "OKC", 26.0, 3.0, 2L, TRUE, "Dunk Shot",          1L, "10:15",   "2026-11-11")
  }
  # Non-rotation player: counted in league FGA total, excluded from per-player catalog & files
  add_row("999", "Bench Walkon", "MIA", 30.0, 10.0, 2L, FALSE, "Pullup Jump Shot",   4L, "2:05",    NA_character_)

  df <- do.call(rbind, rows)
  if (!with_game_date) {
    df$game_date <- NULL
  } else if (all_na_date) {
    df$game_date <- as.Date(rep(NA_character_, nrow(df)))
  }
  df
}

cur_season <- as.integer(env_default$CURRENT_SEASON)
saveRDS(
  make_shots_df(cur_season, with_game_date = TRUE, include_players = c("101", "102")),
  file.path(sb_cache, sprintf("nba_shots_%d.rds", cur_season))
)

# Pre-seed stale files that must be pruned by build_shot_chart_dataset()
writeLines('{"stale":true}', file.path(sb_shots, "999.json"))
writeLines('{"stale":true}', file.path(sb_shots, "103.json"))

local({
  Sys.unsetenv("NBA_SHOT_CHART_SEASON")
  on.exit({
    if (is.na(old_season_env)) Sys.unsetenv("NBA_SHOT_CHART_SEASON")
    else Sys.setenv(NBA_SHOT_CHART_SEASON = old_season_env)
  }, add = TRUE)
  suppressMessages(capture.output(
    env_default$build_shot_chart_dataset(cache_dir = sb_cache, web_data_dir = sb_web)
  ))
})

meta_path  <- file.path(sb_web, "shots_metadata.json")
index_path <- file.path(sb_web, "shots_index.json")

ok("sandbox shots_metadata.json written", file.exists(meta_path))
ok("sandbox shots_index.json written", file.exists(index_path))

meta_2027 <- fromJSON(meta_path, simplifyVector = FALSE)
idx_2027  <- fromJSON(index_path, simplifyVector = TRUE)
parsed_gen <- pw_env$.pw_payload_generated_at(meta_path)

ok("shots_metadata.json stamps generated_at in UTC ISO-8601 (%Y-%m-%dT%H:%M:%SZ)",
   is.character(meta_2027$generated_at) &&
     grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", meta_2027$generated_at))
ok("publish_web.R .pw_payload_generated_at() parses shots_metadata.json generated_at",
   inherits(parsed_gen, "POSIXct") && !is.na(parsed_gen))
ok("shots_metadata.json stamps updated_at in UTC ISO-8601",
   is.character(meta_2027$updated_at) &&
     grepl("^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}Z$", meta_2027$updated_at))
ok("shots_metadata.json stamps through_date as max game_date YYYY-MM-DD",
   identical(meta_2027$through_date, "2026-11-15"))
ok("shots_metadata.json source_season_label matches CURRENT_SEASON",
   identical(meta_2027$source_season_label, sprintf("%d-%d", cur_season - 1L, cur_season)))
ok("shots_metadata.json total_shots_sampled excludes Free Throws and includes league FGA",
   identical(as.integer(meta_2027$total_shots_sampled), 4L))

disk_ids_2027 <- sort(sub("\\.json$", "", list.files(sb_shots, pattern = "\\.json$")))
ok("stale shots/999.json and shots/103.json were pruned",
   !file.exists(file.path(sb_shots, "999.json")) &&
     !file.exists(file.path(sb_shots, "103.json")))
ok("shots_index.json and shots/ directory agree 1-to-1",
   identical(disk_ids_2027, sort(as.character(idx_2027$player_id))) &&
     identical(disk_ids_2027, c("101", "102")))

p101 <- fromJSON(file.path(sb_shots, "101.json"), simplifyVector = TRUE)
ok("per-player shot file normalizes H:MM:SS clock and matches catalog total_shots",
   identical(as.integer(p101$total_shots), 2L) &&
     identical(nrow(p101$shots), 2L) &&
     identical(p101$shots$clock[1], "08:45"))

# ------------------------------------------------------------------------------
section("3. through_date JSON null fallback, env override, and fetch_fn caching")
# ------------------------------------------------------------------------------

# 3a: NBA_SHOT_CHART_SEASON override + missing game_date column -> through_date: null
saveRDS(
  make_shots_df(2026L, with_game_date = FALSE, include_players = c("103")),
  file.path(sb_cache, "nba_shots_2026.rds")
)

local({
  Sys.setenv(NBA_SHOT_CHART_SEASON = "2026")
  on.exit({
    if (is.na(old_season_env)) Sys.unsetenv("NBA_SHOT_CHART_SEASON")
    else Sys.setenv(NBA_SHOT_CHART_SEASON = old_season_env)
  }, add = TRUE)
  suppressMessages(capture.output(
    env_default$build_shot_chart_dataset(cache_dir = sb_cache, web_data_dir = sb_web)
  ))
})

meta_raw_2026 <- paste(readLines(meta_path, warn = FALSE), collapse = "\n")
meta_2026 <- fromJSON(meta_path, simplifyVector = FALSE)
idx_2026  <- fromJSON(index_path, simplifyVector = TRUE)
disk_ids_2026 <- sort(sub("\\.json$", "", list.files(sb_shots, pattern = "\\.json$")))

ok("build_shot_chart_dataset() honors NBA_SHOT_CHART_SEASON override when season arg is omitted",
   identical(meta_2026$source_season_label, "2025-2026"))
ok("missing game_date serializes through_date as JSON null (not {} or \"NA\")",
   is.null(meta_2026$through_date) &&
     grepl('"through_date"\\s*:\\s*null', meta_raw_2026))
ok("previous season player files (101, 102) pruned; shots_index.json and shots/ stay 1-to-1",
   identical(disk_ids_2026, "103") &&
     identical(as.character(idx_2026$player_id), "103"))

# 3b: All-NA game_date via mock fetch_fn when cache RDS is absent
sb_cache_2025 <- file.path(sb_root, "cache_fetch")
dir.create(sb_cache_2025, recursive = TRUE)
fetch_called <- FALSE
mock_fetch <- function(sn) {
  fetch_called <<- TRUE
  make_shots_df(sn, with_game_date = TRUE, all_na_date = TRUE, include_players = c("101"))
}
suppressMessages(capture.output(
  env_default$build_shot_chart_dataset(
    season = 2025L,
    cache_dir = sb_cache_2025,
    web_data_dir = sb_web,
    fetch_fn = mock_fetch
  )
))
meta_raw_2025 <- paste(readLines(meta_path, warn = FALSE), collapse = "\n")
meta_2025 <- fromJSON(meta_path, simplifyVector = FALSE)
ok("fetch_fn caches nba_shots_<season>.rds when absent",
   isTRUE(fetch_called) && file.exists(file.path(sb_cache_2025, "nba_shots_2025.rds")))
ok("all-NA game_date serializes through_date as JSON null",
   is.null(meta_2025$through_date) &&
     grepl('"through_date"\\s*:\\s*null', meta_raw_2025))

# ------------------------------------------------------------------------------
section("4. run_full_pipeline.R stage presence, ordering, and declared outputs")
# ------------------------------------------------------------------------------

pipeline_exprs <- parse(file.path(REPO_ROOT, "run_full_pipeline.R"))
stage_calls <- list()

collect_run_stage <- function(expr) {
  if (!is.call(expr)) return()
  hd <- expr[[1]]
  if (is.name(hd) && identical(as.character(hd), "run_stage")) {
    stage_calls[[length(stage_calls) + 1L]] <<- expr
  }
  for (k in seq_along(expr)) {
    if (k > 1L) collect_run_stage(expr[[k]])
  }
}
for (ex in pipeline_exprs) collect_run_stage(ex)

stage_names <- vapply(stage_calls, function(call_expr) {
  if (length(call_expr) >= 2L && is.character(call_expr[[2L]])) call_expr[[2L]] else ""
}, character(1))

idx_sq  <- which(stage_names == "shot_quality_engine.R")
idx_sim <- which(stage_names == "season_simulator.R")
idx_sc  <- which(stage_names == "build_shot_chart_dataset.R")

ok("run_full_pipeline.R registers run_stage(\"build_shot_chart_dataset.R\", ...)",
   length(idx_sc) == 1L)
ok("build_shot_chart_dataset.R runs after both shot_quality_engine.R and season_simulator.R",
   length(idx_sq) == 1L && length(idx_sim) == 1L && length(idx_sc) == 1L &&
     idx_sc > idx_sq && idx_sc > idx_sim)

declared_out_txt <- if (length(idx_sc) == 1L) {
  sc_call <- stage_calls[[idx_sc]]
  sc_named <- match.call(
    function(script_name, description, call_fn = NULL, output = NULL, strict_output = FALSE) NULL,
    sc_call
  )
  paste(deparse(sc_named$output), collapse = " ")
} else {
  ""
}
ok("build_shot_chart_dataset.R stage declares shots_index.json and shots_metadata.json outputs",
   grepl("WEB_DATA_DIR", declared_out_txt, fixed = TRUE) &&
     grepl("shots_index.json", declared_out_txt, fixed = TRUE) &&
     grepl("shots_metadata.json", declared_out_txt, fixed = TRUE))

# ------------------------------------------------------------------------------
section("5. tools/publish_web.R .pw_do_publish stages added & deleted shot files")
# ------------------------------------------------------------------------------

pw_lines <- readLines(file.path(REPO_ROOT, "tools", "publish_web.R"), warn = FALSE)
ok("tools/publish_web.R .pw_do_publish passes -A to git add",
   any(grepl('c\\("add",\\s*"-A",\\s*"--",\\s*all_paths\\)', pw_lines)))

git_bin <- Sys.which("git")
ok("git binary available for temp-repo staging test", nzchar(git_bin))

if (nzchar(git_bin)) {
  tmp_git_root <- file.path(tempdir(), "shot_publish_git_test")
  if (dir.exists(tmp_git_root)) unlink(tmp_git_root, recursive = TRUE)
  dir.create(tmp_git_root, recursive = TRUE)
  on.exit(unlink(tmp_git_root, recursive = TRUE), add = TRUE)

  tmp_origin <- file.path(tmp_git_root, "origin.git")
  tmp_repo   <- file.path(tmp_git_root, "repo")
  dir.create(tmp_origin, recursive = TRUE)
  dir.create(tmp_repo, recursive = TRUE)

  run_git <- function(repo, args) {
    out <- suppressWarnings(system2(git_bin, c("-C", shQuote(repo), args),
                                    stdout = TRUE, stderr = TRUE))
    st <- attr(out, "status")
    list(ok = is.null(st) || identical(as.integer(st), 0L),
         out = if (is.null(out)) character(0) else as.character(out))
  }

  r_init_origin <- run_git(tmp_origin, c("init", "--bare"))
  r_init_repo   <- run_git(tmp_repo,   c("init"))
  run_git(tmp_repo, c("checkout", "-B", "main"))
  run_git(tmp_repo, c("config", "user.name", "Test Bot"))
  run_git(tmp_repo, c("config", "user.email", "test-bot@example.invalid"))
  run_git(tmp_repo, c("remote", "add", "origin", canon(tmp_origin)))

  repo_data  <- file.path(tmp_repo, "web", "public", "data")
  repo_shots <- file.path(repo_data, "shots")
  repo_media <- file.path(tmp_repo, "web", "public", "media")
  dir.create(repo_shots, recursive = TRUE)
  dir.create(repo_media, recursive = TRUE)

  writeLines('[{"player_id":"101"},{"player_id":"102"}]', file.path(repo_data, "shots_index.json"))
  writeLines('{"updated_at":"2026-11-18T00:00:00Z"}', file.path(repo_data, "shots_metadata.json"))
  writeLines('{"player_id":"101"}', file.path(repo_shots, "101.json"))
  writeLines('{"player_id":"102"}', file.path(repo_shots, "102.json"))
  writeLines("", file.path(repo_media, ".gitkeep"))
  writeLines("keep", file.path(tmp_repo, "unrelated.txt"))

  run_git(tmp_repo, c("add", "-A"))
  run_git(tmp_repo, c("commit", "-m", shQuote("Initial snapshot")))
  r_push_init <- run_git(tmp_repo, c("push", "-u", "origin", "main"))

  ok("temp git repo initialized and pushed to temp bare origin",
     r_init_origin$ok && r_init_repo$ok && r_push_init$ok)

  # Simulate pipeline update: modify 101, prune/delete 102, add 103, leave unrelated file untracked
  writeLines('[{"player_id":"101"},{"player_id":"103"}]', file.path(repo_data, "shots_index.json"))
  writeLines('{"generated_at":"2026-11-19T12:00:00Z","updated_at":"2026-11-19T12:00:00Z"}',
             file.path(repo_data, "shots_metadata.json"))
  writeLines('{"player_id":"101","updated":true}', file.path(repo_shots, "101.json"))
  unlink(file.path(repo_shots, "102.json"))
  writeLines('{"player_id":"103"}', file.path(repo_shots, "103.json"))
  writeLines("do not stage me", file.path(tmp_repo, "outside_scratch.txt"))

  old_web_data  <- pw_env$WEB_DATA_DIR
  old_web_media <- pw_env$WEB_MEDIA_DIR
  old_git_env   <- Sys.getenv(c("GIT_AUTHOR_NAME", "GIT_AUTHOR_EMAIL",
                                "GIT_COMMITTER_NAME", "GIT_COMMITTER_EMAIL"), unset = NA)
  on.exit({
    pw_env$WEB_DATA_DIR  <- old_web_data
    pw_env$WEB_MEDIA_DIR <- old_web_media
    for (nm in names(old_git_env)) {
      if (is.na(old_git_env[[nm]])) Sys.unsetenv(nm)
      else do.call(Sys.setenv, setNames(list(old_git_env[[nm]]), nm))
    }
  }, add = TRUE)

  pw_env$WEB_DATA_DIR  <- repo_data
  pw_env$WEB_MEDIA_DIR <- repo_media
  Sys.setenv(
    GIT_AUTHOR_NAME     = "Test Bot",
    GIT_AUTHOR_EMAIL    = "test-bot@example.invalid",
    GIT_COMMITTER_NAME  = "Test Bot",
    GIT_COMMITTER_EMAIL = "test-bot@example.invalid"
  )

  diff_res <- pw_env$.assert_nonempty_diff(canon(tmp_repo))
  ok(".assert_nonempty_diff detects pending shot chart changes in temp git repo",
     isTRUE(diff_res$pass) && identical(diff_res$paths, "web/public/data"))

  pub_err <- NULL
  tryCatch(
    pw_env$.pw_do_publish(canon(tmp_repo), diff_res$paths, "Publish shot chart add+delete test"),
    error = function(e) pub_err <<- conditionMessage(e)
  )
  ok(".pw_do_publish succeeds against temp git repo", is.null(pub_err))
  if (!is.null(pub_err)) cat(sprintf("        publish error: %s\n", pub_err))

  head_diff <- run_git(tmp_repo, c("show", "--name-status", "--format=", "HEAD"))$out
  porcelain <- run_git(tmp_repo, c("status", "--porcelain"))$out
  porcelain <- porcelain[nzchar(porcelain)]

  ok(".pw_do_publish staged and committed deleted shots/102.json",
     any(grepl("^D\\s+web/public/data/shots/102\\.json$", head_diff)))
  ok(".pw_do_publish staged and committed added shots/103.json",
     any(grepl("^A\\s+web/public/data/shots/103\\.json$", head_diff)))
  ok(".pw_do_publish staged and committed modified shots/101.json",
     any(grepl("^M\\s+web/public/data/shots/101\\.json$", head_diff)))
  ok(".pw_do_publish left unrelated outside file unstaged and no shot changes pending",
     identical(porcelain, "?? outside_scratch.txt"))

  local_sha  <- run_git(tmp_repo,   c("rev-parse", "HEAD"))$out[1]
  origin_sha <- run_git(tmp_origin, c("rev-parse", "main"))$out[1]
  ok(".pw_do_publish pushed commit to temp bare origin",
     nzchar(local_sha) && identical(local_sha, origin_sha))
}

# ------------------------------------------------------------------------------
cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
