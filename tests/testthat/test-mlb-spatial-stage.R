if (!file.exists("config.R")) {
  proj_dir <- if (file.exists("../../config.R")) {
    normalizePath("../..", winslash = "/")
  } else {
    stop("Cannot locate the project root: no config.R at ./ or ../../. Run tests from the repo root or from tests/testthat/.", call. = FALSE)
  }
  setwd(proj_dir)
}

suppressPackageStartupMessages({
  library(testthat)
  library(dplyr)
  library(tibble)
  library(jsonlite)
})

REPO_ROOT <- normalizePath(getwd(), winslash = "/", mustWork = TRUE)

make_spatial_statcast_fixture <- function(batter_id, pitcher_id, hit_dist = 415, velo = 97.2) {
  n_pitches <- 8L
  tibble::tibble(
    pitcher = rep(as.integer(pitcher_id), n_pitches),
    batter = rep(as.integer(batter_id), n_pitches),
    player_name = rep("Fixture Player", n_pitches),
    home_team = rep("NYY", n_pitches),
    stand = rep("R", n_pitches),
    p_throws = rep("R", n_pitches),
    type = c("X", "X", "S", "S", "S", "B", "B", "B"),
    events = c("home_run", "single", rep(NA_character_, 6L)),
    description = c("hit_into_play", "hit_into_play", "called_strike", "swinging_strike", "foul", "ball", "ball", "ball"),
    hc_x = c(185, 130, rep(NA_real_, 6L)),
    hc_y = c(45, 120, rep(NA_real_, 6L)),
    hit_distance_sc = c(hit_dist, 210, rep(NA_real_, 6L)),
    launch_speed = c(111.5, 95.8, rep(NA_real_, 6L)),
    launch_angle = c(27.0, 13.0, rep(NA_real_, 6L)),
    plate_x = c(0.05, -0.10, 0.72, 0.0, -0.25, -1.10, 1.05, 0.20),
    plate_z = c(2.45, 2.35, 2.50, 2.60, 2.80, 2.20, 3.80, 1.10),
    pfx_x = rep(-0.5, n_pitches),
    pfx_z = rep(1.2, n_pitches),
    release_speed = rep(velo, n_pitches),
    release_pos_x = rep(-2.0, n_pitches),
    release_pos_z = rep(5.8, n_pitches),
    release_extension = rep(6.3, n_pitches),
    pitch_type = rep("FF", n_pitches)
  )
}

write_offline_teams_cache <- function(root_dir) {
  teams_dir <- file.path(root_dir, "cache", "id_crosswalk")
  dir.create(teams_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(data.frame(), file.path(teams_dir, "mlb_teams.rds"))
}

read_spatial_index_ids <- function(index_file) {
  raw <- paste(readLines(index_file, warn = FALSE, encoding = "UTF-8"), collapse = "")
  expect_true(grepl("^\\[.*\\]$", trimws(raw)), info = "spatial_index.json root must be a JSON array")
  parsed <- jsonlite::fromJSON(raw, simplifyVector = FALSE)
  expect_true(is.list(parsed))
  expect_null(names(parsed))
  vapply(parsed, function(entry) as.character(entry[["player_id"]]), character(1))
}

run_r_child <- function(script_lines, env_vars = list(), wd = REPO_ROOT) {
  script_file <- tempfile("mlb_spatial_child_", fileext = ".R")
  on.exit(unlink(script_file, force = TRUE), add = TRUE)
  writeLines(script_lines, script_file, useBytes = TRUE)

  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  setwd(wd)

  vars <- c(list(RENV_ACTIVATE_PROJECT = "FALSE"), env_vars)
  prev <- lapply(names(vars), function(nm) Sys.getenv(nm, unset = NA_character_))
  names(prev) <- names(vars)
  on.exit({
    for (nm in names(prev)) {
      if (is.na(prev[[nm]])) Sys.unsetenv(nm) else do.call(Sys.setenv, setNames(list(prev[[nm]]), nm))
    }
  }, add = TRUE)

  for (nm in names(vars)) {
    if (is.na(vars[[nm]]) || !nzchar(vars[[nm]])) {
      Sys.unsetenv(nm)
    } else {
      do.call(Sys.setenv, setNames(list(vars[[nm]]), nm))
    }
  }

  out <- suppressWarnings(system2(rscript, c("--vanilla", shQuote(script_file)),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  list(status = if (is.null(st)) 0L else as.integer(st),
       out = if (is.null(out)) character(0) else as.character(out))
}

test_that("export_player_spatial_maps resolves season Statcast cache, prunes stale files, and keeps 1-to-1 array index", {
  tmp_root <- tempfile("mlb-spatial-prune-")
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

  ingest_dir <- file.path(tmp_root, "cache", "ingest")
  out_dir <- file.path(tmp_root, "web", "public", "data")
  spatial_dir <- file.path(out_dir, "spatial")
  dir.create(ingest_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(spatial_dir, recursive = TRUE, showWarnings = FALSE)
  write_offline_teams_cache(tmp_root)

  # Distinct Statcast caches per season to verify season-scoped resolution
  saveRDS(
    make_spatial_statcast_fixture(batter_id = 592450L, pitcher_id = 543037L, hit_dist = 428, velo = 98.4),
    file.path(ingest_dir, "statcast_pitches_2026.rds")
  )
  saveRDS(
    make_spatial_statcast_fixture(batter_id = 660271L, pitcher_id = 543037L, hit_dist = 402, velo = 94.1),
    file.path(ingest_dir, "statcast_pitches_2025.rds")
  )

  # Pre-existing stale player maps + legacy monolith file from an earlier build
  writeLines('{"player_id":"B_STALE_1"}', file.path(spatial_dir, "B_STALE_1.json"))
  writeLines('{"player_id":"P_STALE_2"}', file.path(spatial_dir, "P_STALE_2.json"))
  writeLines("{}", file.path(out_dir, "player_spatial_maps.json"))

  players_2026 <- data.frame(
    player_id = c("B_592450", "P_543037"),
    mlbam_id = c(592450L, 543037L),
    player_name = c("Aaron Judge", "Gerrit Cole"),
    player_type = c("Batter", "Pitcher"),
    team = c("NYY", "NYY"),
    position = c("B", "SP"),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(
    list(generated_at = "2026-04-01T12:00:00Z", season = 2026L, players = players_2026),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )

  assign("PROJECT_DIR", REPO_ROOT, envir = globalenv())
  source("tools/export_player_spatial_maps.R")
  on.exit(if (exists(".log_disconnect", mode = "function")) .log_disconnect(), add = TRUE)

  idx_path <- export_player_spatial_maps(out_dir = out_dir, season = 2026L, root_dir = tmp_root)
  expect_true(file.exists(idx_path))
  expect_false(file.exists(file.path(out_dir, "player_spatial_maps.json")))
  expect_false(file.exists(file.path(spatial_dir, "B_STALE_1.json")))
  expect_false(file.exists(file.path(spatial_dir, "P_STALE_2.json")))

  idx_ids <- read_spatial_index_ids(idx_path)
  disk_files <- sort(list.files(spatial_dir, pattern = "\\.json$", full.names = FALSE))
  expect_equal(sort(paste0(idx_ids, ".json")), disk_files)
  expect_setequal(idx_ids, c("B_592450", "P_543037"))

  judge <- jsonlite::fromJSON(file.path(spatial_dir, "B_592450.json"), simplifyVector = FALSE)
  expect_true(isTRUE(judge$is_statcast_tracked))
  expect_equal(judge$batter_summary$max_dist, 428)

  cole <- jsonlite::fromJSON(file.path(spatial_dir, "P_543037.json"), simplifyVector = FALSE)
  expect_true(isTRUE(cole$is_statcast_tracked))
  expect_equal(cole$pitcher_summary$avg_velo, 98.4)

  # Second export drops P_543037 and switches season to 2025: P_543037.json must be pruned
  players_2025 <- data.frame(
    player_id = c("B_660271", "B_592450"),
    mlbam_id = c(660271L, 592450L),
    player_name = c("Shohei Ohtani", "Aaron Judge"),
    player_type = c("Batter", "Batter"),
    team = c("LAD", "NYY"),
    position = c("B", "B"),
    stringsAsFactors = FALSE
  )
  jsonlite::write_json(
    list(generated_at = "2025-04-01T12:00:00Z", season = 2025L, players = players_2025),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )

  export_player_spatial_maps(out_dir = out_dir, season = 2025L, root_dir = tmp_root)
  expect_false(file.exists(file.path(spatial_dir, "P_543037.json")))

  idx_ids_2025 <- read_spatial_index_ids(idx_path)
  disk_files_2025 <- sort(list.files(spatial_dir, pattern = "\\.json$", full.names = FALSE))
  expect_equal(sort(paste0(idx_ids_2025, ".json")), disk_files_2025)

  ohtani <- jsonlite::fromJSON(file.path(spatial_dir, "B_660271.json"), simplifyVector = FALSE)
  expect_true(isTRUE(ohtani$is_statcast_tracked))
  expect_equal(ohtani$batter_summary$max_dist, 402)

  judge_2025 <- jsonlite::fromJSON(file.path(spatial_dir, "B_592450.json"), simplifyVector = FALSE)
  expect_false(isTRUE(judge_2025$is_statcast_tracked))
  expect_equal(judge_2025$sample_size, 0L)

  # Missing Statcast cache for season = 2027 still emits untracked placeholders and keeps 1-to-1 parity
  writeLines('{"player_id":"STALE_2027"}', file.path(spatial_dir, "STALE_2027.json"))
  jsonlite::write_json(
    list(generated_at = "2027-04-01T12:00:00Z", season = 2027L, players = players_2025),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )
  export_player_spatial_maps(out_dir = out_dir, season = 2027L, root_dir = tmp_root)
  expect_false(file.exists(file.path(spatial_dir, "STALE_2027.json")))
  ohtani_2027 <- jsonlite::fromJSON(file.path(spatial_dir, "B_660271.json"), simplifyVector = FALSE)
  expect_false(isTRUE(ohtani_2027$is_statcast_tracked))
  expect_equal(ohtani_2027$sample_size, 0L)
  expect_equal(
    sort(paste0(read_spatial_index_ids(idx_path), ".json")),
    sort(list.files(spatial_dir, pattern = "\\.json$", full.names = FALSE))
  )

  # Empty roster prunes all spatial/*.json files and preserves JSON array []
  jsonlite::write_json(
    list(generated_at = "2025-04-01T12:00:00Z", season = 2025L, players = list()),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )
  export_player_spatial_maps(out_dir = out_dir, season = 2025L, root_dir = tmp_root)
  expect_length(read_spatial_index_ids(idx_path), 0L)
  expect_length(list.files(spatial_dir, pattern = "\\.json$"), 0L)
})

test_that("run_full_pipeline.R registers export_player_spatial_maps after Stage 14 and run_stage executes cleanly", {
  # 1. Static AST / source verification of stage registration and ordering
  parsed <- parse(file.path(REPO_ROOT, "run_full_pipeline.R"))
  collect_run_stage_calls <- function(expr) {
    calls <- list()
    walk <- function(node) {
      if (!is.call(node)) return()
      fn <- node[[1]]
      if (is.symbol(fn) && identical(as.character(fn), "run_stage")) {
        calls[[length(calls) + 1L]] <<- node
      }
      for (k in seq_along(node)) {
        if (k > 1L) walk(node[[k]])
      }
    }
    for (top in expr) walk(top)
    calls
  }

  stage_calls <- collect_run_stage_calls(parsed)
  scripts <- vapply(stage_calls, function(cl) {
    val <- cl[["script_name"]]
    if (is.character(val)) val else paste(deparse(val), collapse = "")
  }, character(1))

  idx_web <- which(scripts == "tools/export_web_data.R")
  idx_spatial <- which(scripts == "tools/export_player_spatial_maps.R")
  expect_length(idx_web, 1L)
  expect_length(idx_spatial, 1L)
  expect_gt(idx_spatial, idx_web)

  spatial_call <- stage_calls[[idx_spatial]]
  expect_equal(spatial_call[["call_fn"]], "export_player_spatial_maps")
  expect_identical(as.character(spatial_call[["season"]]), "season")
  expect_identical(as.character(spatial_call[["output"]]), "WEB_JSON_SPATIAL_INDEX")

  # config.R non-member contract remains intact
  source(file.path(REPO_ROOT, "config.R"))
  expect_false(WEB_JSON_SPATIAL_INDEX %in% WEB_DATA_FILES)
  expect_false(WEB_DIR_SPATIAL %in% WEB_DATA_FILES)

  # 2. Sandbox run_stage execution via run_full_pipeline.R in isolated MLB_ANALYTICS_ROOT
  tmp_root <- tempfile("mlb-pipeline-stage-")
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)
  ingest_dir <- file.path(tmp_root, "cache", "ingest")
  out_dir <- file.path(tmp_root, "web", "public", "data")
  spatial_dir <- file.path(out_dir, "spatial")
  dir.create(ingest_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(spatial_dir, recursive = TRUE, showWarnings = FALSE)
  write_offline_teams_cache(tmp_root)

  saveRDS(
    make_spatial_statcast_fixture(batter_id = 592450L, pitcher_id = 543037L, hit_dist = 431, velo = 99.1),
    file.path(ingest_dir, "statcast_pitches_2026.rds")
  )
  writeLines('{"player_id":"STALE_STAGE"}', file.path(spatial_dir, "STALE_STAGE.json"))
  jsonlite::write_json(
    list(
      generated_at = sprintf("%d-04-01T12:00:00Z", MLB_CURRENT_SEASON),
      season = MLB_CURRENT_SEASON,
      players = data.frame(
        player_id = c("B_592450", "P_543037"),
        mlbam_id = c(592450L, 543037L),
        player_name = c("Aaron Judge", "Gerrit Cole"),
        player_type = c("Batter", "Pitcher"),
        team = c("NYY", "NYY"),
        position = c("B", "SP"),
        stringsAsFactors = FALSE
      )
    ),
    file.path(out_dir, "projections_season_players.json"),
    auto_unbox = TRUE
  )

  res <- run_r_child(
    c(
      'source("run_full_pipeline.R")',
      "ok <- run_stage(",
      '  script_name = "tools/export_player_spatial_maps.R",',
      '  description = "Export Empirical Player Spatial Maps & Prune Stale Files",',
      '  call_fn = "export_player_spatial_maps",',
      "  output = WEB_JSON_SPATIAL_INDEX,",
      "  require_fresh = TRUE,",
      "  season = 2026L",
      ")",
      "stopifnot(isTRUE(ok))",
      "stopifnot(length(.pipeline_stages_run) == 1L)",
      'stopifnot(identical(.pipeline_stages_run[[1]]$status, "OK"))'
    ),
    env_vars = list(MLB_ANALYTICS_ROOT = normalizePath(tmp_root, winslash = "/"))
  )

  expect_equal(res$status, 0L, info = paste(res$out, collapse = "\n"))
  expect_false(file.exists(file.path(spatial_dir, "STALE_STAGE.json")))
  expect_true(file.exists(file.path(out_dir, "spatial_index.json")))
  expect_setequal(
    list.files(spatial_dir, pattern = "\\.json$"),
    c("B_592450.json", "P_543037.json")
  )
})

test_that("publish_web .pw_do_publish stages added and deleted spatial files in-season without breaking off-season selective staging", {
  tmp_root <- tempfile("mlb-publish-spatial-")
  on.exit(unlink(tmp_root, recursive = TRUE, force = TRUE), add = TRUE)

  bare <- file.path(tmp_root, "origin.git")
  work <- file.path(tmp_root, "work")
  dir.create(bare, recursive = TRUE)
  dir.create(file.path(work, "tools"), recursive = TRUE)
  dir.create(file.path(work, "web", "public", "data", "spatial"), recursive = TRUE)
  dir.create(file.path(work, "web", "public", "data", "archive"), recursive = TRUE)
  write_offline_teams_cache(work)

  file.copy(file.path(REPO_ROOT, "config.R"), file.path(work, "config.R"))
  file.copy(file.path(REPO_ROOT, "logging_utils.R"), file.path(work, "logging_utils.R"))
  file.copy(file.path(REPO_ROOT, "tools", "publish_web.R"), file.path(work, "tools", "publish_web.R"))
  writeLines(c("/logs/", "/cache/"), file.path(work, ".gitignore"))

  git_in <- function(repo, args) {
    out <- suppressWarnings(system2("git", c("-C", shQuote(repo), args), stdout = TRUE, stderr = TRUE))
    st <- attr(out, "status")
    list(ok = is.null(st) || identical(as.integer(st), 0L),
         out = if (is.null(out)) character(0) else as.character(out))
  }

  expect_true(git_in(bare, c("init", "--bare", "-b", "main"))$ok)
  expect_true(git_in(work, c("init", "-b", "main"))$ok)
  expect_true(git_in(work, c("config", "user.name", "Test User"))$ok)
  expect_true(git_in(work, c("config", "user.email", "test@example.com"))$ok)
  expect_true(git_in(work, c("remote", "add", "origin", shQuote(bare)))$ok)

  data_dir <- file.path(work, "web", "public", "data")
  spatial_dir <- file.path(data_dir, "spatial")
  writeLines('{"player_id":"KEEP_1"}', file.path(spatial_dir, "KEEP_1.json"))
  writeLines('{"player_id":"OLD_1"}', file.path(spatial_dir, "OLD_1.json"))
  writeLines('[{"player_id":"KEEP_1"},{"player_id":"OLD_1"}]', file.path(data_dir, "spatial_index.json"))
  writeLines('[{"team":"NYY"}]', file.path(data_dir, "projections_season_teams.json"))
  writeLines('{"activePhase":"Post-World Series Review"}', file.path(data_dir, "offseason_monitor.json"))
  writeLines('{"editions":[]}', file.path(data_dir, "archive", "offseason_2026_editions.json"))
  writeLines("base", file.path(work, "unrelated.txt"))

  expect_true(git_in(work, c("add", "-A"))$ok)
  expect_true(git_in(work, c("commit", "-m", shQuote("Initial seed")))$ok)
  expect_true(git_in(work, c("push", "-u", "origin", "main"))$ok)

  # 1. In-season change: delete OLD_1.json, add NEW_1.json, modify KEEP_1.json + spatial_index.json,
  #    plus an unrelated dirty file outside web/public/data.
  unlink(file.path(spatial_dir, "OLD_1.json"))
  writeLines('{"player_id":"NEW_1"}', file.path(spatial_dir, "NEW_1.json"))
  writeLines('{"player_id":"KEEP_1","updated":true}', file.path(spatial_dir, "KEEP_1.json"))
  writeLines('[{"player_id":"KEEP_1"},{"player_id":"NEW_1"}]', file.path(data_dir, "spatial_index.json"))
  writeLines("dirty-outside-web", file.path(work, "unrelated.txt"))

  inseason_res <- run_r_child(
    c(
      'source("tools/publish_web.R")',
      'repo_root <- .pw_repo_root()',
      'diff_in <- .assert_nonempty_diff(repo_root, mode = "inseason")',
      "stopifnot(isTRUE(diff_in$pass))",
      'stopifnot(identical(diff_in$paths, "web/public/data"))',
      '.pw_do_publish(repo_root, diff_in$paths, "In-season spatial update")'
    ),
    env_vars = list(
      MLB_ANALYTICS_ROOT = "",
      GIT_AUTHOR_NAME = "Test User",
      GIT_AUTHOR_EMAIL = "test@example.com",
      GIT_COMMITTER_NAME = "Test User",
      GIT_COMMITTER_EMAIL = "test@example.com"
    ),
    wd = work
  )
  expect_equal(inseason_res$status, 0L, info = paste(inseason_res$out, collapse = "\n"))

  commit_changes <- git_in(work, c("diff", "--name-status", "HEAD~1", "HEAD"))$out
  expect_true("A\tweb/public/data/spatial/NEW_1.json" %in% commit_changes)
  expect_true("D\tweb/public/data/spatial/OLD_1.json" %in% commit_changes)
  expect_true("M\tweb/public/data/spatial/KEEP_1.json" %in% commit_changes)
  expect_true("M\tweb/public/data/spatial_index.json" %in% commit_changes)
  expect_false(any(grepl("unrelated.txt", commit_changes, fixed = TRUE)))

  remote_spatial <- git_in(bare, c("ls-tree", "-r", "--name-only", "HEAD", "web/public/data/spatial"))$out
  expect_setequal(
    remote_spatial,
    c("web/public/data/spatial/KEEP_1.json", "web/public/data/spatial/NEW_1.json")
  )

  # 2. Off-season selective staging: modify offseason_monitor.json while also modifying
  #    projections_season_teams.json and adding/deleting spatial files. Only off-season paths stage!
  writeLines('{"activePhase":"Post-World Series Review","tick":2}', file.path(data_dir, "offseason_monitor.json"))
  writeLines('[{"team":"NYY","dirty":true}]', file.path(data_dir, "projections_season_teams.json"))
  writeLines('{"player_id":"EXTRA_OFF"}', file.path(spatial_dir, "EXTRA_OFF.json"))
  unlink(file.path(spatial_dir, "NEW_1.json"))

  offseason_res <- run_r_child(
    c(
      'source("tools/publish_web.R")',
      'repo_root <- .pw_repo_root()',
      'diff_off <- .assert_nonempty_diff(repo_root, mode = "offseason")',
      "stopifnot(isTRUE(diff_off$pass))",
      'stopifnot(all(diff_off$paths %in% c("web/public/data/offseason_monitor.json", "web/public/data/archive/offseason_2026_editions.json")))',
      '.pw_do_publish(repo_root, diff_off$paths, "Off-season monitor update")',
      'err <- tryCatch({ .pw_do_publish(repo_root, character(0), "Empty paths guard"); NULL }, error = function(e) conditionMessage(e))',
      "stopifnot(!is.null(err))"
    ),
    env_vars = list(
      MLB_ANALYTICS_ROOT = "",
      GIT_AUTHOR_NAME = "Test User",
      GIT_AUTHOR_EMAIL = "test@example.com",
      GIT_COMMITTER_NAME = "Test User",
      GIT_COMMITTER_EMAIL = "test@example.com"
    ),
    wd = work
  )
  expect_equal(offseason_res$status, 0L, info = paste(offseason_res$out, collapse = "\n"))

  off_commit_files <- git_in(work, c("diff", "--name-only", "HEAD~1", "HEAD"))$out
  expect_equal(off_commit_files, "web/public/data/offseason_monitor.json")

  # Unrelated edits remain unstaged in working tree
  porcelain <- git_in(work, c("status", "--porcelain"))$out
  expect_true(any(grepl("projections_season_teams.json", porcelain, fixed = TRUE)))
  expect_true(any(grepl("EXTRA_OFF.json", porcelain, fixed = TRUE)))
  expect_true(any(grepl("NEW_1.json", porcelain, fixed = TRUE)))
  expect_true(any(grepl("unrelated.txt", porcelain, fixed = TRUE)))
})
