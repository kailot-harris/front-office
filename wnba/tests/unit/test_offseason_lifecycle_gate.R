# ==============================================================================
# test_offseason_lifecycle_gate.R  (WNBA#250)
# tools/publish_web.R off-season scoping of assertions F and I by data-file
# lifecycle, and assertion L (lifecycle present + frozen-file integrity).
# Offline: temp-dir fixtures only (tests/helpers/lifecycle_fixtures.R).
# Run: Rscript tests/unit/test_offseason_lifecycle_gate.R
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

RUN_START <- as.POSIXct("2026-11-30 09:00:00", tz = "UTC")

# The 2026-11-23 failure shape: an untouched season file with an old stamp and
# a through_date that trails the schedule, next to a freshly rebuilt live file.
cat("\n-- 1. unchanged season_final file: old stamp + lagging through_date --\n")
d <- lc_data_dir(bracket_through = "2026-10-24")
reg <- tempfile("lc_reg_", fileext = ".json")
lc_freeze_entry(reg, d, "playoff_bracket_2026.json")
lc_freeze_entry(reg, d, "matchups_slates.json")
lc_freeze_entry(reg, d, "projections_season_teams.json")
m <- lc_manifest(d, reg)
e <- setNames(m$datasets, vapply(m$datasets, `[[`, "", "file"))
check("manifest carries lifecycle + frozen fields from the registry",
      identical(e[["playoff_bracket_2026.json"]]$lifecycle, "season_final") &&
        identical(e[["offseason_monitor.json"]]$lifecycle, "live") &&
        identical(e[["cba_cap_sheet.json"]]$lifecycle, "archived") &&
        !is.null(e[["playoff_bracket_2026.json"]]$frozen_sha256) &&
        identical(as.integer(e[["playoff_bracket_2026.json"]]$season), 2026L))
check("fixture really is lagging: bracket through 2026-10-24, schedule through 2026-10-29",
      identical(e[["playoff_bracket_2026.json"]]$through_date, "2026-10-24") &&
        identical(m$schedule_through_date, "2026-10-29"))
F_off <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m, data_dir = d)
check("offseason F passes (season_final not stamp-checked)", F_off$pass, c(F_off$summary, F_off$detail))
check("offseason F still checked the live file", any(grepl("[[]FRESH[]] +offseason_monitor[.]json", F_off$detail)))
check("offseason F lists the frozen file as [FROZEN]", any(grepl("[[]FROZEN[]] +playoff_bracket_2026[.]json", F_off$detail)))
I_off <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE, mode = "offseason", manifest = m))
check("offseason I passes (season_final not lag-checked)", I_off$pass, I_off$problems)
check("offseason I reports the frozen file", any(grepl("[FROZEN] playoff_bracket_2026.json", I_off$detail, fixed = TRUE)))
L_res <- .assert_lifecycle(d, manifest = m, expected = lc_assign(reg))
check("L passes: every file has a lifecycle, frozen hashes match", L_res$pass, L_res$problems)
I_in <- quiet(.assert_manifest_and_coverage(d, dry_run = TRUE, manifest = m))
check("control: the same manifest in-season still fails I on the lagging file",
      !I_in$pass && any(grepl("playoff_bracket_2026.json lagging", I_in$problems, fixed = TRUE)), I_in$problems)

cat("\n-- 2. season_final file whose bytes changed after the freeze --\n")
d2 <- lc_data_dir(bracket_through = "2026-10-24")
reg2 <- tempfile("lc_reg_", fileext = ".json")
for (f in LC_SEASON_FILES) lc_freeze_entry(reg2, d2, f)
lc_write(d2, "playoff_bracket_2026.json", list(generated_at = "2026-11-01T12:00:00Z", season = 2026L,
                                               series = list(list(games = list(list(gameDate = "2026-10-29"))))))
m2 <- lc_manifest(d2, reg2)
L2 <- .assert_lifecycle(d2, manifest = m2, expected = lc_assign(reg2))
check("L fails on a content-hash mismatch", !L2$pass && any(grepl("playoff_bracket_2026.json changed since frozen", L2$problems, fixed = TRUE)),
      L2$problems)
check("L names it [CHANGED]", any(grepl("[CHANGED] playoff_bracket_2026.json", L2$detail, fixed = TRUE)))
# A CRLF-only difference is not a content change (core.autocrlf checkouts).
d2b <- lc_data_dir(); reg2b <- tempfile("lc_reg_", fileext = ".json")
for (f in LC_SEASON_FILES) lc_freeze_entry(reg2b, d2b, f)
p <- file.path(d2b, "playoff_bracket_2026.json")
txt <- readLines(p); con <- file(p, "wb"); writeBin(charToRaw(paste0(paste(txt, collapse = "\r\n"), "\r\n")), con); close(con)
L2b <- .assert_lifecycle(d2b, manifest = lc_manifest(d2b, reg2b), expected = lc_assign(reg2b))
check("L treats a CRLF-only rewrite as unchanged", L2b$pass, L2b$problems)
# season_final without its frozen fields fails
m2c <- lc_manifest(d2b, reg2b)
for (i in seq_along(m2c$datasets)) if (m2c$datasets[[i]]$file == "matchups_slates.json") m2c$datasets[[i]]$frozen_sha256 <- NULL
L2c <- .assert_lifecycle(d2b, manifest = m2c, expected = NULL)
check("L fails a season_final entry without frozen_sha256",
      !L2c$pass && any(grepl("matchups_slates.json season_final missing frozen_sha256", L2c$problems, fixed = TRUE)), L2c$problems)

cat("\n-- 3. live files are still checked in full off-season --\n")
reg3 <- tempfile("lc_reg_", fileext = ".json")   # nothing frozen: season files are live
d3 <- lc_data_dir(live_stamp = "2026-11-17T20:04:32Z", matchups_through = "2026-10-29", bracket_through = "2026-10-29")
lc_freeze_entry(reg3, d3, "playoff_bracket_2026.json"); lc_freeze_entry(reg3, d3, "matchups_slates.json")
lc_freeze_entry(reg3, d3, "projections_season_teams.json")
F3 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = lc_manifest(d3, reg3), data_dir = d3)
check("offseason F fails a stale live file", !F3$pass && identical(F3$stale, "offseason_monitor.json"), F3$detail)

d3b <- lc_data_dir(live_stamp = NULL, bracket_through = "2026-10-29")
reg3b <- tempfile("lc_reg_", fileext = ".json")
for (f in LC_SEASON_FILES) lc_freeze_entry(reg3b, d3b, f)
F3b <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = lc_manifest(d3b, reg3b), data_dir = d3b)
check("offseason F fails a live file with no stamp", !F3b$pass && identical(F3b$unstamped, "offseason_monitor.json"), F3b$detail)

d3c <- lc_data_dir(matchups_through = "2026-10-20", bracket_through = "2026-10-29")
reg3c <- tempfile("lc_reg_", fileext = ".json")
lc_freeze_entry(reg3c, d3c, "playoff_bracket_2026.json")       # matchups NOT frozen -> live
lc_freeze_entry(reg3c, d3c, "projections_season_teams.json")
m3c <- lc_manifest(d3c, reg3c)
check("an unfrozen season file is live", identical(Filter(function(x) x$file == "matchups_slates.json", m3c$datasets)[[1]]$lifecycle, "live"))
I3c <- quiet(.assert_manifest_and_coverage(d3c, dry_run = TRUE, mode = "offseason", manifest = m3c))
check("offseason I fails a lagging live file", !I3c$pass && any(grepl("matchups_slates.json lagging 9", I3c$problems, fixed = TRUE)), I3c$problems)
F3c <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m3c, data_dir = d3c)
check("offseason F fails the unfrozen season file's old stamp", !F3c$pass && "matchups_slates.json" %in% F3c$stale, F3c$detail)

cat("\n-- 4. a data file with no lifecycle fails in both modes --\n")
d4 <- lc_data_dir(extra = list("mystery_payload.json" = list(generated_at = "2026-11-30T09:05:00Z", x = 1L)))
reg4 <- tempfile("lc_reg_", fileext = ".json")
for (f in LC_SEASON_FILES) lc_freeze_entry(reg4, d4, f)
m4 <- lc_manifest(d4, reg4)
check("the writer leaves an unassigned file without a lifecycle",
      is.null(Filter(function(x) x$file == "mystery_payload.json", m4$datasets)[[1]]$lifecycle))
L4 <- .assert_lifecycle(d4, manifest = m4, expected = lc_assign(reg4))
check("L fails the unassigned file", !L4$pass && any(grepl("mystery_payload.json has no lifecycle", L4$problems, fixed = TRUE)), L4$problems)
# L is the same call in both modes (publish_web() runs it unconditionally); prove
# the in-season gate result list includes it by checking publish_web's source.
pw_src <- paste(readLines(file.path("tools", "publish_web.R")), collapse = "\n")
check("publish_web() runs L in every mode", grepl(".assert_lifecycle(WEB_DATA_DIR, manifest = manifest_obj)\n  )", pw_src, fixed = TRUE))
F4 <- .assert_payload_provenance(RUN_START, mode = "offseason", manifest = m4, data_dir = d4)
check("offseason F checks an unassigned file as live", any(grepl("mystery_payload.json", F4$detail, fixed = TRUE) & grepl("NO LIFECYCLE", F4$detail, fixed = TRUE)))
# A manifest entry with a lifecycle config.R no longer assigns is caught too.
m4b <- m4
for (i in seq_along(m4b$datasets)) if (m4b$datasets[[i]]$file == "mystery_payload.json") m4b$datasets[[i]]$lifecycle <- "live"
L4b <- .assert_lifecycle(d4, manifest = m4b, expected = lc_assign(reg4))
check("L fails a manifest lifecycle that config.R does not assign", !L4b$pass &&
        any(grepl("mystery_payload.json lifecycle live != config <none>", L4b$problems, fixed = TRUE)), L4b$problems)

cat("\n-- 5. in-season verdicts are unchanged by lifecycle fields --\n")
strip <- function(m) { m$datasets <- lapply(m$datasets, function(x) { x[c("lifecycle", DM_LIFECYCLE_FIELDS)] <- NULL; x }); m }
for (case in list(list(name = "lagging season_final (fails)", d = d, m = m),
                  list(name = "complete set (passes)", d = d3, m = lc_manifest(d3, reg3)),
                  list(name = "lagging live file (fails)", d = d3c, m = m3c))) {
  with_lc <- quiet(.assert_manifest_and_coverage(case$d, dry_run = TRUE, manifest = case$m))
  without <- quiet(.assert_manifest_and_coverage(case$d, dry_run = TRUE, manifest = strip(case$m)))
  check(sprintf("in-season I identical with and without lifecycle: %s", case$name),
        identical(with_lc$pass, without$pass) && identical(with_lc$problems, without$problems) &&
          identical(with_lc$detail, without$detail))
}
# The default mode is in-season and takes the original code path.
check("I defaults to in-season", identical(formals(.assert_manifest_and_coverage)$mode, "inseason"))
check("F defaults to in-season", identical(formals(.assert_payload_provenance)$mode, "inseason"))
# In-season F walks WEB_DATA_FILES and does not fail an unstamped payload (unchanged).
F_in <- .assert_payload_provenance(as.POSIXct("2000-01-01", tz = "UTC"))
check("in-season F unchanged: unstamped payloads are reported, not failed",
      isTRUE(F_in$pass) == (length(F_in$stale) == 0) && grepl("carry no stamp", F_in$summary))

lc_finish()
