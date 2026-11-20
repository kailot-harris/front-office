# ==============================================================================
# tests/test_data_manifest_and_lag_gate.R
#
# front-office#102 / #191: tools/write_data_manifest.R and publish gate
# assertion H (.assert_manifest_and_coverage). Fully offline: every case builds
# a throwaway data dir under tempdir() and passes the schedule date explicitly.
#
# Usage: Rscript tests/test_data_manifest_and_lag_gate.R
# ==============================================================================

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
setwd(REPO_ROOT)
source(file.path(REPO_ROOT, "tools", "publish_web.R"))
source(file.path(REPO_ROOT, "tools", "write_data_manifest.R"))

n_pass <- 0L; n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) { n_pass <<- n_pass + 1L; cat("  PASS:", label, "\n") }
  else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n") }
}

entry <- function(through = "2026-11-19", max_lag = 2L, static = FALSE, reason = NULL,
                  gen = "2026-11-20T14:00:00Z", builder = "build_x.R") {
  list(generated_at = gen, through_date = through,
       through_date_source = if (static) "static" else if (is.null(through)) "not_game_dated" else "payload:through_date",
       stamp_source = "payload:generated_at", content_sha256 = NULL,
       coverage_note = if (!static && is.null(through)) "test: no game date" else NULL,
       source_season = "2026-27",
       builder = builder, max_lag_days = max_lag, static = static, static_reason = reason)
}

fixture <- function(datasets, extra_files = character(0)) {
  d <- tempfile("dm_fixture_"); dir.create(d)
  for (f in c(names(datasets), extra_files)) writeLines('{"x": 1}', file.path(d, f))
  m <- list(schema_version = 1L, sport = "nba", generated_at = "2026-11-20T14:00:00Z",
            schedule_through_date = "2026-11-19", datasets = datasets)
  writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", pretty = TRUE),
             file.path(d, "data_manifest.json"))
  d
}
H <- function(d, sched = NULL) .assert_manifest_and_coverage(d, schedule_through_date = sched,
                                                             schedule_path = file.path(d, "no_cache.rds"))

cat("\n(a) lagging through_date fails\n")
d <- fixture(list("a.json" = entry("2026-11-10", 2L), "b.json" = entry("2026-11-19", 2L)))
r <- H(d, "2026-11-19")
check(!r$pass && identical(r$failing, "a.json"), "dataset 9 days behind with max_lag 2 fails H")
check(any(grepl("\\[LAGGING\\].*a\\.json.*lag=9d max=2d", r$detail)), "detail line marks it [LAGGING] with lag")
check(H(d, "2026-11-12")$pass, "same data within lag of an earlier schedule passes")

cat("\n(b) off-season passes\n")
d <- fixture(list("a.json" = entry("2026-04-12", 0L)))
check(H(d, "2026-04-12")$pass, "schedule_through_date == through_date passes")
check(H(d, "2026-03-01")$pass, "schedule_through_date < through_date passes")

cat("\n(c) static exceptions\n")
d <- fixture(list("s.json" = entry(NULL, 0L, TRUE, "frozen off-season snapshot")))
r <- H(d, "2026-11-19")
check(r$pass && any(grepl("\\[STATIC\\].*s\\.json", r$detail)), "static with reason passes as [STATIC]")
d <- fixture(list("s.json" = entry(NULL, 0L, TRUE, NULL)))
check(!H(d, "2026-11-19")$pass, "static without reason fails")
d <- fixture(list("n.json" = entry(NULL, 2L)))
r <- H(d, "2026-11-19")
check(r$pass && any(grepl("\\[UNDATED\\].*n\\.json", r$detail)), "not_game_dated with fresh generated_at passes as [UNDATED]")
d <- fixture(list("n.json" = entry(NULL, 2L, gen = "2026-11-01T14:00:00Z")))
check(!H(d, "2026-11-19")$pass, "not_game_dated with old generated_at fails (never silently fresh)")
e <- entry(NULL, 2L); e$through_date_source <- "payload:through_date"
d <- fixture(list("n.json" = e))
check(!H(d, "2026-11-19")$pass, "game-dated source with null through_date fails when schedule known")

cat("\n(d) unstamped / unlisted payloads fail, even with no schedule\n")
d <- fixture(list("a.json" = entry()), extra_files = "orphan.json")
r <- H(d, NULL)
check(!r$pass && "orphan.json" %in% r$failing, "unlisted JSON fails H with schedule absent")
d <- fixture(list("a.json" = entry(gen = "2026-11-20 14:00:00")))
check(!H(d, NULL)$pass, "non-UTC-ISO generated_at fails")
d <- fixture(list("a.json" = entry(builder = "")))
check(!H(d, NULL)$pass, "missing builder fails")
d <- fixture(list("a.json" = entry()))
r <- H(d, NULL)
check(r$pass && grepl("schedule cache absent; manifest completeness verified", r$summary),
      "complete manifest + absent schedule passes with the completeness note")
d <- tempfile("dm_nomanifest_"); dir.create(d); writeLines("{}", file.path(d, "a.json"))
check(!H(d, NULL)$pass, "absent manifest fails")

cat("\n(e) dry run lists every dataset's coverage\n")
d <- fixture(list("a.json" = entry("2026-11-19"), "b.json" = entry("2026-11-18"),
                  "s.json" = entry(NULL, 0L, TRUE, "frozen")))
r <- H(d, "2026-11-19")
for (f in c("a.json", "b.json", "s.json")) {
  check(any(grepl(f, r$detail, fixed = TRUE) & grepl("through=", r$detail, fixed = TRUE)),
        sprintf("detail line names %s with its through date", f))
}

cat("\n(f) writer covers the committed tree and H passes on it\n")
dd <- file.path(REPO_ROOT, "web", "public", "data")
m <- build_data_manifest(data_dir = dd, schedule_path = NULL)
on_disk <- setdiff(list.files(dd, pattern = "\\.json$"), "data_manifest.json")
check(setequal(names(m$datasets), on_disk), sprintf("writer lists all %d top-level payloads", length(on_disk)))
check(all(vapply(m$datasets, function(e) .pw_is_utc_iso(e$generated_at), logical(1))), "every generated_at is UTC ISO-8601")
check(all(names(m$datasets) %in% names(DM_SPEC)), "every payload has a registered spec row")
md <- tempfile("dm_real_"); dir.create(md)
file.copy(file.path(dd, on_disk), md)
writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", pretty = TRUE), file.path(md, "data_manifest.json"))
check(H(md, m$schedule_through_date)$pass, "H passes on the committed tree with the committed schedule date")
check(H(md, NULL)$pass, "H passes on the committed tree offline")
sched_tmp <- tempfile(fileext = ".rds")
saveRDS(data.frame(game_date = c("2026-11-18", "2026-11-19", "2026-11-20"),
                   status_type_completed = c(TRUE, TRUE, FALSE),
                   home_short_display_name = "A", away_short_display_name = "B"), sched_tmp)
check(identical(dm_latest_completed_schedule_date(sched_tmp), as.Date("2026-11-19")),
      "dm_latest_completed_schedule_date returns the last completed date")
check(is.na(dm_latest_completed_schedule_date(file.path(md, "absent.rds"))), "absent schedule -> NA")

cat("\n(h) FO#191: stale content behind a brand-new stamp fails\n")
sd <- tempfile("dm_stale_"); dir.create(sd)
writeLines(jsonlite::toJSON(list(season = "2026-27", throughDate = "2026-11-02",
                                 generatedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                                 profiles = list()), auto_unbox = TRUE),
           file.path(sd, "defensive_metrics.json"))
write_data_manifest(data_dir = sd, schedule_path = NULL)
sm <- jsonlite::fromJSON(file.path(sd, "data_manifest.json"), simplifyVector = FALSE)
check(identical(sm$datasets[["defensive_metrics.json"]]$through_date, "2026-11-02") &&
        identical(sm$datasets[["defensive_metrics.json"]]$through_date_source, "payload:throughDate"),
      "through_date comes from payload content, not the fresh stamp")
check(!H(sd, "2026-11-19")$pass, "rebuilt-today-from-stale-cache payload fails assertion H")

cat("\n(i) FO#102: content-hash carry-forward, no file-system/VCS stamps\n")
cd <- tempfile("dm_hash_"); dir.create(cd)
writeLines('[{"a":1}]', file.path(cd, "projections_season_teams.json"))
t1 <- as.POSIXct("2026-11-01 12:00:00", tz = "UTC"); t2 <- as.POSIXct("2026-11-05 12:00:00", tz = "UTC")
write_data_manifest(data_dir = cd, now = t1)
m1 <- jsonlite::fromJSON(file.path(cd, "data_manifest.json"), simplifyVector = FALSE)
e1 <- m1$datasets[["projections_season_teams.json"]]
check(identical(e1$generated_at, "2026-11-01T12:00:00Z") && identical(e1$stamp_source, "manifest:content_hash") &&
        grepl("^[0-9a-f]{64}$", e1$content_sha256), "unstamped payload stamped at first observation with its sha256")
write_data_manifest(data_dir = cd, now = t2)
m2 <- jsonlite::fromJSON(file.path(cd, "data_manifest.json"), simplifyVector = FALSE)
check(identical(m2$datasets[["projections_season_teams.json"]]$generated_at, "2026-11-01T12:00:00Z"),
      "same bytes -> generated_at carried forward")
check(identical(m2$generated_at, m1$generated_at), "manifest top-level generated_at unchanged when no entry changed")
writeLines('[{"a":2}]', file.path(cd, "projections_season_teams.json"))
write_data_manifest(data_dir = cd, now = t2)
m3 <- jsonlite::fromJSON(file.path(cd, "data_manifest.json"), simplifyVector = FALSE)
check(identical(m3$datasets[["projections_season_teams.json"]]$generated_at, "2026-11-05T12:00:00Z") &&
        identical(m3$generated_at, "2026-11-05T12:00:00Z"), "changed bytes -> new stamp (entry and top level)")
code <- sub("#.*$", "", readLines(file.path(REPO_ROOT, "tools", "write_data_manifest.R"), warn = FALSE))
check(!any(grepl("file\\.info|file\\.mtime|mtime|system2|\\bgit\\b", code, perl = TRUE)),
      "writer code never calls file.info()/file.mtime() or git")

cat("\n(g) dry runs never write the manifest\n")
before <- tools::md5sum(file.path(md, "data_manifest.json"))
.pw_refresh_manifest(dry_run = TRUE, web_data_dir = md)
check(identical(unname(tools::md5sum(file.path(md, "data_manifest.json"))), unname(before)),
      "dry-run refresh is a no-op")

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
quit(status = if (n_fail == 0L) 0L else 1L)
