# ==============================================================================
# test_season_lifecycle_freeze.R  (WNBA#250)
# tools/freeze_season.R: season-end detection, refusal of incomplete files,
# frozen_sha256 recording, --thaw lifecycle moves, and a freeze -> manifest ->
# off-season gate round trip. Offline: temp-dir fixtures only.
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

lc_finish()
