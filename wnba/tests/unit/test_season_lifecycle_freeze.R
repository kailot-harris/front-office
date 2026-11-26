# ==============================================================================
# test_season_lifecycle_freeze.R  (WNBA#250)
# tools/freeze_season.R: season-end detection, refusal of incomplete files,
# frozen_sha256 recording, --thaw lifecycle moves, and a freeze -> manifest ->
# off-season gate round trip, regular-season-only files, and already-frozen
# entries (kept on a matching hash, refused on a changed one). Offline: temp-dir
# fixtures only.
# Run: Rscript tests/unit/test_season_lifecycle_freeze.R
# ==============================================================================

local({
  a <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", a[grepl("^--file=", a)])
  root <- if (length(f) == 1 && file.exists(f)) dirname(dirname(dirname(normalizePath(f, winslash = "/")))) else getwd()
  while (!file.exists(file.path(root, "config.R")) && dirname(root) != root) root <- dirname(root)
  setwd(root)
})
source(file.path("tests", "helpers", "lifecycle_fixtures.R"))
lc_bootstrap()

TODAY <- as.Date("2026-11-23")
NOW   <- as.POSIXct("2026-11-24 03:00:00", tz = "UTC")

cat("\n-- season's last game --\n")
check("last game = latest COMPLETED game, playoffs included; unplayed if-necessary game ignored",
      identical(fs_season_last_game(lc_schedule(), 2026L, today = TODAY), as.Date("2026-10-29")))
err <- tryCatch({ fs_season_last_game(lc_schedule(), 2026L, today = as.Date("2026-10-30")); NULL },
                error = function(e) conditionMessage(e))
check("a season with an uncompleted game still ahead is not over", !is.null(err) && grepl("not over", err), err)
err2 <- tryCatch({ fs_season_last_game(lc_schedule(), 2025L, today = TODAY); NULL }, error = function(e) conditionMessage(e))
check("a season absent from the schedule is refused", !is.null(err2) && grepl("no games", err2), err2)

cat("\n-- freeze refuses an incomplete file --\n")
d <- lc_data_dir(bracket_through = "2026-10-24")          # bracket stops before 10-29
reg <- tempfile("fs_reg_", fileext = ".json")
r <- freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                   season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
check("freeze refuses when a file's through_date is before the last game", !r$ok)
check("the refusal names the file and the dates",
      "playoff_bracket_2026.json" %in% r$refused$file &&
        grepl("2026-10-24 is before the season's last game 2026-10-29",
              r$refused$reason[r$refused$file == "playoff_bracket_2026.json"], fixed = TRUE), r$refused$reason)
check("only the incomplete file is refused", identical(r$refused$file, "playoff_bracket_2026.json"), r$refused$file)
check("a refused freeze writes nothing (all or nothing)", !file.exists(reg) && length(r$frozen) == 0)

d_u <- lc_data_dir(bracket_through = "2026-10-29", undated_stamp = "2026-10-27T10:00:00Z")
r_u <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                     season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
check("freeze refuses an undated file generated before the last game",
      !r_u$ok && identical(r_u$refused$file, "projections_season_teams.json"), r_u$refused$reason)
r_abs <- freeze_season(2026L, data_dir = d_u, registry_path = reg, schedule = lc_schedule(),
                       season_files = c(LC_SEASON_FILES, "finals_series_backtest_2026.json"), today = TODAY, now = NOW)
check("freeze refuses an absent season file", "finals_series_backtest_2026.json" %in% r_abs$refused$file)
err3 <- tryCatch({ freeze_season(2026L, data_dir = d, registry_path = reg, schedule = lc_schedule(),
                                 season_files = LC_SEASON_FILES, today = as.Date("2026-10-30"), now = NOW); NULL },
                 error = function(e) conditionMessage(e))
check("freeze refuses outright while the season is not over", !is.null(err3) && grepl("not over", err3) && !file.exists(reg), err3)

cat("\n-- freeze records frozen_sha256 for a complete set --\n")
d2 <- lc_data_dir(bracket_through = "2026-10-29", matchups_through = "2026-10-29", undated_stamp = "2026-11-06T19:49:32Z")
reg2 <- tempfile("fs_reg_", fileext = ".json")
r2 <- freeze_season(2026L, data_dir = d2, registry_path = reg2, schedule = lc_schedule(),
                    season_files = LC_SEASON_FILES, today = TODAY, now = NOW)
check("freeze succeeds when every season file reaches the last game", r2$ok, r2$refused$reason)
rg <- wnba_read_lifecycle_registry(reg2)
check("registry lists exactly the season files", identical(sort(names(rg$files)), sort(LC_SEASON_FILES)), names(rg$files))
b <- rg$files[["playoff_bracket_2026.json"]]
check("entry is season_final with season, final_through_date, frozen_at",
      identical(b$lifecycle, "season_final") && identical(as.integer(b$season), 2026L) &&
        identical(b$final_through_date, "2026-10-29") && identical(b$frozen_at, "2026-11-24T03:00:00Z"))
check("frozen_sha256 is the file's content hash",
      identical(b$frozen_sha256, wnba_lifecycle_sha256(file.path(d2, "playoff_bracket_2026.json"))) &&
        grepl("^[0-9a-f]{64}$", b$frozen_sha256))
check("files outside the season set are not frozen", is.null(rg$files[["offseason_monitor.json"]]) &&
        is.null(rg$files[["cba_cap_sheet.json"]]))
check("config.R's assignment now reads season_final from the registry",
      identical(lc_assign(reg2)("playoff_bracket_2026.json")[[1]]$lifecycle, "season_final") &&
        identical(lc_assign(reg2)("offseason_monitor.json")[[1]]$lifecycle, "live"))

cat("\n-- round trip: freeze -> manifest -> off-season gate --\n")
m2 <- lc_manifest(d2, reg2)
RUN_START <- as.POSIXct("2026-11-30 09:00:00", tz = "UTC")
F2 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m2, data_dir = d2)
I2 <- quiet(.assert_manifest_and_coverage(d2, dry_run = TRUE, mode = "offseason", manifest = m2))
L2 <- .assert_lifecycle(d2, manifest = m2, expected = lc_assign(reg2))
check("off-season F, I and L all pass over the frozen set", F2$pass && I2$pass && L2$pass,
      c(F2$summary, I2$problems, L2$problems))

cat("\n-- thaw: new season starts --\n")
new_files <- c("playoff_bracket_2027.json", "matchups_slates.json", "projections_season_teams.json")
t <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
check("thaw moves reused file names to live", identical(sort(t$to_live), c("matchups_slates.json", "projections_season_teams.json")), t$to_live)
check("thaw moves the old season's own files to archived", identical(t$to_archived, "playoff_bracket_2026.json"), t$to_archived)
rg2 <- wnba_read_lifecycle_registry(reg2)
lc_after <- wnba_data_lifecycle(c("playoff_bracket_2026.json", "matchups_slates.json", "playoff_bracket_2027.json"),
                                registry = rg2, offseason_live = LC_LIVE, season_files = new_files,
                                archived_files = LC_ARCHIVED)
check("after thaw: old bracket archived, reused file live, new-season file live",
      identical(vapply(lc_after, `[[`, "", "lifecycle"),
                c(playoff_bracket_2026.json = "archived", matchups_slates.json = "live", playoff_bracket_2027.json = "live")))
check("an archived entry keeps its season and hash for the record",
      identical(as.integer(rg2$files[["playoff_bracket_2026.json"]]$season), 2026L) &&
        identical(rg2$files[["playoff_bracket_2026.json"]]$frozen_sha256, b$frozen_sha256))
t2 <- thaw_season(2027L, registry_path = reg2, season_files = new_files)
check("thaw is idempotent", length(t2$to_live) == 0 && length(t2$to_archived) == 0)
reg3 <- tempfile("fs_reg_", fileext = ".json")
invisible(freeze_season(2026L, data_dir = d2, registry_path = reg3, schedule = lc_schedule(),
                        season_files = LC_SEASON_FILES, today = TODAY, now = NOW))
t3 <- thaw_season(2026L, registry_path = reg3, season_files = LC_SEASON_FILES)
check("thaw leaves the same season's frozen files alone", length(t3$to_live) == 0 && length(t3$to_archived) == 0)

cat("\n-- regular-season-only files freeze at the last regular-season game --\n")
LC_REG_FILES <- c(LC_SEASON_FILES, "player_leaders.json")
lc_leaders <- function(through) list("player_leaders.json" = list(
  schema_version = 1L, generated_at = "2026-11-26T06:00:00Z", season = "2026", through_date = through, cards = list()))
check("last regular-season game = latest completed season_type 2 game",
      identical(fs_season_last_game(lc_schedule(), 2026L, today = TODAY, regular_season_only = TRUE), as.Date("2026-09-10")))
d_rs <- lc_data_dir(bracket_through = "2026-10-29", extra = lc_leaders("2026-09-10"))
reg_rs <- tempfile("fs_reg_", fileext = ".json")
r_rs <- freeze_season(2026L, data_dir = d_rs, registry_path = reg_rs, schedule = lc_schedule(),
                      season_files = LC_REG_FILES, regular_season_files = "player_leaders.json",
                      today = TODAY, now = NOW)
check("a regular-season file that reaches the regular-season end freezes at that date",
      r_rs$ok && identical(r_rs$frozen[["player_leaders.json"]]$final_through_date, "2026-09-10") &&
        identical(wnba_read_lifecycle_registry(reg_rs)$files[["player_leaders.json"]]$final_through_date, "2026-09-10"),
      r_rs$refused$reason)
check("other season files in the same freeze keep the season's last game",
      identical(r_rs$frozen[["playoff_bracket_2026.json"]]$final_through_date, "2026-10-29"))
r_rs0 <- freeze_season(2026L, data_dir = d_rs, registry_path = tempfile("fs_reg_", fileext = ".json"),
                       schedule = lc_schedule(), season_files = LC_REG_FILES, regular_season_files = character(0),
                       today = TODAY, now = NOW, write = FALSE)
check("the same file outside the regular-season list must reach the season's last game",
      !r_rs0$ok && identical(r_rs0$refused$file, "player_leaders.json"), r_rs0$refused$reason)

d_rs_short <- lc_data_dir(bracket_through = "2026-10-29", extra = lc_leaders("2026-09-03"))
reg_rs_short <- tempfile("fs_reg_", fileext = ".json")
r_rs_short <- freeze_season(2026L, data_dir = d_rs_short, registry_path = reg_rs_short, schedule = lc_schedule(),
                            season_files = LC_REG_FILES, regular_season_files = "player_leaders.json",
                            today = TODAY, now = NOW)
check("a regular-season file that stops before the regular-season end is refused",
      !r_rs_short$ok && identical(r_rs_short$refused$file, "player_leaders.json") &&
        grepl("2026-09-03 is before the season's last regular-season game 2026-09-10",
              r_rs_short$refused$reason, fixed = TRUE) && !file.exists(reg_rs_short),
      r_rs_short$refused$reason)

cat("\n-- already-frozen entries --\n")
d_k <- lc_data_dir(bracket_through = "2026-10-29")
reg_k <- tempfile("fs_reg_", fileext = ".json")
r_k1 <- freeze_season(2026L, data_dir = d_k, registry_path = reg_k, schedule = lc_schedule(),
                      season_files = LC_SEASON_FILES, regular_season_files = character(0), today = TODAY, now = NOW)
before_k <- wnba_read_lifecycle_registry(reg_k)$files
lc_write(d_k, "player_leaders.json", lc_leaders("2026-09-10")[[1]])
NOW2 <- as.POSIXct("2026-11-26 21:00:00", tz = "UTC")
r_k2 <- freeze_season(2026L, data_dir = d_k, registry_path = reg_k, schedule = lc_schedule(),
                      season_files = LC_REG_FILES, regular_season_files = "player_leaders.json",
                      today = TODAY, now = NOW2)
after_k <- wnba_read_lifecycle_registry(reg_k)$files
check("an already-frozen file with a matching hash keeps its frozen_at",
      r_k1$ok && r_k2$ok && identical(sort(r_k2$kept), sort(LC_SEASON_FILES)) &&
        identical(names(r_k2$frozen), "player_leaders.json") &&
        identical(after_k[LC_SEASON_FILES], before_k[LC_SEASON_FILES]) &&
        identical(after_k[["playoff_bracket_2026.json"]]$frozen_at, "2026-11-24T03:00:00Z") &&
        identical(after_k[["player_leaders.json"]]$frozen_at, "2026-11-26T21:00:00Z"),
      c(r_k2$refused$reason, r_k2$kept))
reg_k_bytes <- readBin(reg_k, "raw", n = file.info(reg_k)$size)
lc_write(d_k, "matchups_slates.json", list(
  generated_at = "2026-11-25T12:00:00Z",
  matchups = list(list(game_date = "2026-10-20", is_completed = TRUE),
                  list(game_date = "2026-10-29", is_completed = TRUE),
                  list(game_date = "2026-10-29", is_completed = TRUE))))
r_k3 <- freeze_season(2026L, data_dir = d_k, registry_path = reg_k, schedule = lc_schedule(),
                      season_files = LC_REG_FILES, regular_season_files = "player_leaders.json",
                      today = TODAY, now = NOW2)
check("an already-frozen file with a changed hash is refused and nothing is written",
      !r_k3$ok && identical(r_k3$refused$file, "matchups_slates.json") &&
        grepl("content hash changed", r_k3$refused$reason, fixed = TRUE) &&
        identical(readBin(reg_k, "raw", n = file.info(reg_k)$size), reg_k_bytes),
      r_k3$refused$reason)

lc_finish()
