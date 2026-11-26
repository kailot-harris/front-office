# ==============================================================================
# test-season-lifecycle-freeze.R (MLB-Analytics#147)
# tools/freeze_season.R: season-end detection, refusal of incomplete files,
# frozen_sha256 recording, --thaw lifecycle moves, and a freeze -> manifest ->
# off-season gate round trip. Offline: temp-dir fixtures only.
# ==============================================================================

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

lc_bootstrap()

TODAY <- as.Date("2026-11-23")
NOW   <- as.POSIXct("2026-11-24 03:00:00", tz = "UTC")

test_that("fs_season_last_game finds latest completed slate game and refuses unfinished/absent seasons", {
  expect_identical(fs_season_last_game(lc_schedule(), 2026L, today = TODAY), as.Date("2026-10-28"))

  # Spring training / exhibition games after last_done are ignored when game_type is present.
  sched_ex <- rbind(
    lc_schedule(),
    data.frame(season = 2026L, game_type = "E", official_date = "2026-11-05",
               status_detailed_state = "Final", if_necessary = "N", stringsAsFactors = FALSE)
  )
  expect_identical(fs_season_last_game(sched_ex, 2026L, today = TODAY), as.Date("2026-10-28"))

  # Uncompleted game on or after today means the season is not over.
  expect_error(fs_season_last_game(lc_schedule(), 2026L, today = as.Date("2026-10-30")), "not over")
  expect_error(fs_season_last_game(lc_schedule(), 2025L, today = TODAY), "no games")
})

test_that("freeze_season refuses incomplete or absent files all-or-nothing without writing", {
  d <- lc_data_dir(digest_through = "2026-10-24")
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)

  r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                     season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_false(r$ok)
  expect_true("landing_digest.json" %in% r$refused$file)
  expect_true(grepl("2026-10-24 is before the season's last game 2026-10-28",
                    r$refused$reason[r$refused$file == "landing_digest.json"], fixed = TRUE))
  expect_identical(r$refused$file, "landing_digest.json")
  expect_false(file.exists(reg))
  expect_length(r$frozen, 0L)

  d_u <- lc_data_dir(digest_through = "2026-10-28", undated_stamp = "2026-10-27T10:00:00Z")
  on.exit(unlink(d_u, recursive = TRUE), add = TRUE)
  r_u <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                       season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_false(r_u$ok)
  expect_identical(r_u$refused$file, "projections_season_teams.json")

  r_abs <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                         season_files = c(LC_SEASON_FILES, "missing_season_file.json"),
                         today = TODAY, now = NOW)
  expect_false(r_abs$ok)
  expect_true("missing_season_file.json" %in% r_abs$refused$file)
  expect_false(file.exists(reg))

  expect_error(
    freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                  season_files = LC_SEASON_FILES, today = as.Date("2026-10-30"), now = NOW),
    "not over"
  )
  expect_false(file.exists(reg))
})

test_that("freeze_season records frozen_sha256 for complete set and dry-run writes nothing", {
  d2 <- lc_data_dir(digest_through = "2026-10-28", ws_through = "2026-10-28", undated_stamp = "2026-11-06T19:49:32Z")
  reg_dry <- tempfile("fs_reg_dry_", fileext = ".json")
  reg2 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d2, reg_dry, reg2), recursive = TRUE), add = TRUE)

  r_dry <- freeze_season(2026L, data_dir = d2, registry_path = reg_dry, schedule = lc_schedule(),
                         season_files = LC_SEASON_FILES, today = TODAY, now = NOW, write = FALSE)
  expect_true(r_dry$ok)
  expect_false(file.exists(reg_dry))
  expect_setequal(names(r_dry$frozen), LC_SEASON_FILES)

  r2 <- freeze_season(2026L, data_dir = d2, registry_path = reg2, schedule = lc_schedule(),
                      season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_true(r2$ok)
  rg <- mlb_read_lifecycle_registry(reg2)
  expect_identical(sort(names(rg$files)), sort(LC_SEASON_FILES))

  b <- rg$files[["landing_digest.json"]]
  expect_identical(b$lifecycle, "season_final")
  expect_identical(as.integer(b$season), 2026L)
  expect_identical(b$final_through_date, "2026-10-28")
  expect_identical(b$frozen_at, "2026-11-24T03:00:00Z")
  expect_identical(b$frozen_sha256, mlb_lifecycle_sha256(file.path(d2, "landing_digest.json")))
  expect_match(b$frozen_sha256, "^[0-9a-f]{64}$")

  expect_null(rg$files[["offseason_monitor.json"]])
  expect_null(rg$files[["legacy_2025_archive.json"]])
  expect_identical(lc_assign(reg2)("landing_digest.json")[[1]]$lifecycle, "season_final")
  expect_identical(lc_assign(reg2)("offseason_monitor.json")[[1]]$lifecycle, "live")

  # Round trip: freeze -> manifest -> off-season gate (F, H, M).
  m2 <- lc_manifest(d2, reg2)
  RUN_START <- as.POSIXct("2026-11-30 09:00:00", tz = "UTC")
  F2 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m2, data_dir = d2)
  H2 <- lc_quiet(.assert_manifest_and_coverage(d2, mode = "offseason", manifest = m2))
  M2 <- .assert_lifecycle(d2, manifest = m2, expected = lc_assign(reg2))
  expect_true(F2$pass)
  expect_true(H2$pass)
  expect_true(M2$pass)
})

test_that("thaw_season moves reused names to live and unique prior-season files to archived", {
  d2 <- lc_data_dir(digest_through = "2026-10-28", ws_through = "2026-10-28")
  reg2 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d2, reg2), recursive = TRUE), add = TRUE)
  # Freeze a set including a 2026-only filename alongside reused filenames.
  lc_write(d2, "postseason_bracket_2026.json", list(generated_at = "2026-11-01T12:00:00Z"))
  season_2026 <- c("postseason_bracket_2026.json", "landing_digest.json", "projections_season_teams.json")
  r2 <- freeze_season(2026L, data_dir = d2, registry_path = reg2, schedule = lc_schedule(),
                      season_files = season_2026, today = TODAY, now = NOW)
  expect_true(r2$ok)
  b_hash <- mlb_read_lifecycle_registry(reg2)$files[["postseason_bracket_2026.json"]]$frozen_sha256

  new_files <- c("postseason_bracket_2027.json", "landing_digest.json", "projections_season_teams.json")
  t <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
  expect_identical(sort(t$to_live), c("landing_digest.json", "projections_season_teams.json"))
  expect_identical(t$to_archived, "postseason_bracket_2026.json")

  rg2 <- mlb_read_lifecycle_registry(reg2)
  lc_after <- mlb_data_lifecycle(
    c("postseason_bracket_2026.json", "landing_digest.json", "postseason_bracket_2027.json"),
    registry = rg2,
    offseason_live = LC_LIVE,
    season_files = new_files,
    archived_files = LC_ARCHIVED
  )
  expect_identical(vapply(lc_after, `[[`, "", "lifecycle"),
                   c(postseason_bracket_2026.json = "archived",
                     landing_digest.json = "live",
                     postseason_bracket_2027.json = "live"))
  expect_identical(as.integer(rg2$files[["postseason_bracket_2026.json"]]$season), 2026L)
  expect_identical(rg2$files[["postseason_bracket_2026.json"]]$frozen_sha256, b_hash)

  t2 <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
  expect_length(t2$to_live, 0L)
  expect_length(t2$to_archived, 0L)

  reg3 <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(reg3), add = TRUE)
  invisible(freeze_season(2026L, data_dir = d2, registry_path = reg3, schedule = lc_schedule(),
                          season_files = season_2026, today = TODAY, now = NOW))
  t3 <- thaw_season(2026L, registry_path = reg3, season_files = season_2026)
  expect_length(t3$to_live, 0L)
  expect_length(t3$to_archived, 0L)
})

test_that("freeze_season CLI exits non-zero when --season is omitted", {
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  out <- suppressWarnings(system2(rscript, c("--vanilla", shQuote(file.path("tools", "freeze_season.R"))),
                                  stdout = TRUE, stderr = TRUE))
  st <- attr(out, "status")
  expect_true(!is.null(st) && st != 0L)
})

# Regular-season-only files (config.R's WEB_DATA_REGULAR_SEASON_FILES) and
# already-frozen entries. lc_schedule(): last regular-season game 2026-09-27,
# last game of the season 2026-10-28.
LC_REG_FILE <- "player_leaders.json"
lc_leaders <- function(through) list(generated_at = "2026-11-01T12:00:00Z", season = 2026L,
                                     through_date = through, batting = list())

test_that("freeze_season freezes a regular-season-only file at the last regular-season game", {
  d <- lc_data_dir(digest_through = "2026-10-28", extra = setNames(list(lc_leaders("2026-09-27")), LC_REG_FILE))
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)

  expect_identical(fs_season_last_game(lc_schedule(), 2026L, today = TODAY, types = "R"), as.Date("2026-09-27"))
  r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                     season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = LC_REG_FILE,
                     today = TODAY, now = NOW)
  expect_true(r$ok)
  expect_identical(r$regular_season_last_game, as.Date("2026-09-27"))
  rg <- mlb_read_lifecycle_registry(reg)
  expect_identical(rg$files[[LC_REG_FILE]]$final_through_date, "2026-09-27")
  expect_identical(rg$files[[LC_REG_FILE]]$frozen_sha256, mlb_lifecycle_sha256(file.path(d, LC_REG_FILE)))
  # Every other file keeps the full-season rule.
  expect_identical(rg$files[["landing_digest.json"]]$final_through_date, "2026-10-28")

  # Without the regular-season classification the same file is refused (postseason rule).
  reg_b <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(reg_b), add = TRUE)
  r_b <- freeze_season(2026L, data_dir = d, registry_path = reg_b, schedule = lc_schedule(),
                       season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = character(0),
                       today = TODAY, now = NOW)
  expect_false(r_b$ok)
  expect_identical(r_b$refused$file, LC_REG_FILE)
  expect_false(file.exists(reg_b))
})

test_that("freeze_season refuses a regular-season-only file that stops before the regular-season end", {
  d <- lc_data_dir(digest_through = "2026-10-28", extra = setNames(list(lc_leaders("2026-09-20")), LC_REG_FILE))
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)

  r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                     season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = LC_REG_FILE,
                     today = TODAY, now = NOW)
  expect_false(r$ok)
  expect_identical(r$refused$file, LC_REG_FILE)
  expect_true(grepl("2026-09-20 is before the season's last regular-season game 2026-09-27",
                    r$refused$reason, fixed = TRUE))
  expect_false(file.exists(reg))
})

test_that("freeze_season keeps an already-frozen file with a matching hash, frozen_at unchanged", {
  d <- lc_data_dir(digest_through = "2026-10-28")
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)
  r1 <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                      season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
  expect_true(r1$ok)
  before <- readLines(reg)

  # A season file added later is frozen on its own; the earlier entries stay byte-identical.
  lc_write(d, LC_REG_FILE, lc_leaders("2026-09-27"))
  later <- as.POSIXct("2026-11-26 21:00:00", tz = "UTC")
  r2 <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                      season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = LC_REG_FILE,
                      today = TODAY, now = later)
  expect_true(r2$ok)
  expect_setequal(r2$kept, LC_SEASON_FILES)
  expect_identical(names(r2$frozen), LC_REG_FILE)
  rg <- mlb_read_lifecycle_registry(reg)
  expect_identical(rg$files[["landing_digest.json"]]$frozen_at, "2026-11-24T03:00:00Z")
  expect_identical(rg$files[[LC_REG_FILE]]$frozen_at, "2026-11-26T21:00:00Z")
  after <- readLines(reg)
  expect_identical(setdiff(before, after), character(0))
  expect_identical(length(after) - length(before), 7L)

  # Nothing new to freeze: the registry is not rewritten at all.
  mtime <- file.mtime(reg)
  r3 <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                      season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = LC_REG_FILE,
                      today = TODAY, now = later + 3600)
  expect_true(r3$ok)
  expect_length(r3$frozen, 0L)
  expect_identical(readLines(reg), after)
  expect_identical(file.mtime(reg), mtime)
})

test_that("freeze_season refuses an already-frozen file whose content changed", {
  d <- lc_data_dir(digest_through = "2026-10-28")
  reg <- tempfile("fs_reg_", fileext = ".json")
  on.exit(unlink(c(d, reg), recursive = TRUE), add = TRUE)
  expect_true(freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                            season_files = LC_SEASON_FILES, today = TODAY, now = NOW)$ok)
  before <- readLines(reg)

  lc_write(d, "projections_season_teams.json",
           list(generated_at = "2026-11-25T08:00:00Z", teams = list(list(team = "changed"))))
  lc_write(d, LC_REG_FILE, lc_leaders("2026-09-27"))
  r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                     season_files = c(LC_SEASON_FILES, LC_REG_FILE), regular_season_files = LC_REG_FILE,
                     today = TODAY, now = NOW + 86400)
  expect_false(r$ok)
  expect_identical(r$refused$file, "projections_season_teams.json")
  expect_match(r$refused$reason, "content changed since it was frozen", fixed = TRUE)
  expect_length(r$frozen, 0L)
  expect_identical(readLines(reg), before)   # all or nothing: the new file is not frozen either
})
