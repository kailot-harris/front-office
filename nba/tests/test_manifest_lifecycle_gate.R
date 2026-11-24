# ==============================================================================
# tests/test_manifest_lifecycle_gate.R
#
# NBA_analytics#235: data-file lifecycle (`lifecycle = "live"` in season) in
# config.R + tools/write_data_manifest.R and publish gate assertion L
# (.assert_lifecycle) in tools/publish_web.R. Fully offline: tempdir fixtures
# only, never mutates web/public/data or cache/.
#
# Usage: Rscript tests/test_manifest_lifecycle_gate.R
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

n_pass <- 0L
n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) {
    n_pass <<- n_pass + 1L
    cat("  PASS:", label, "\n")
  } else {
    n_fail <<- n_fail + 1L
    cat("  FAIL:", label, "\n")
  }
}

make_entry <- function(lifecycle = "live",
                       through = "2026-11-22",
                       static = FALSE,
                       reason = NULL,
                       gen = "2026-11-24T05:13:45Z",
                       extra = list()) {
  e <- list(
    generated_at        = gen,
    through_date        = through,
    through_date_source = if (static) "static" else if (is.null(through)) "not_game_dated" else "payload:throughDate",
    stamp_source        = "payload:generated_at",
    content_sha256      = NULL,
    coverage_note       = if (!static && is.null(through)) "test: no game date" else NULL,
    source_season       = "2026-27",
    builder             = "build_x.R",
    max_lag_days        = 2L,
    static              = static,
    static_reason       = reason
  )
  if (!is.null(lifecycle)) e$lifecycle <- lifecycle
  for (nm in names(extra)) e[[nm]] <- extra[[nm]]
  e
}

make_fixture <- function(datasets, extra_files = character(0), write_manifest = TRUE) {
  d <- tempfile("lc_fixture_")
  dir.create(d, recursive = TRUE)
  for (f in c(names(datasets), extra_files)) {
    writeLines('{"x": 1}', file.path(d, f))
  }
  if (isTRUE(write_manifest)) {
    m <- list(
      schema_version = 1L,
      sport = "nba",
      generated_at = "2026-11-24T05:16:15Z",
      schedule_through_date = "2026-11-22",
      datasets = datasets
    )
    writeLines(jsonlite::toJSON(m, auto_unbox = TRUE, null = "null", pretty = TRUE),
               file.path(d, "data_manifest.json"))
  }
  d
}

cat("\n(a) config.R lifecycle helpers and write_data_manifest.R emission\n")
check(identical(WEB_DATA_LIFECYCLES, c("live", "season_final", "archived")),
      "WEB_DATA_LIFECYCLES lists live, season_final, archived")
lc_map <- nba_data_lifecycle(c("a.json", "b.json"))
check(identical(names(lc_map), c("a.json", "b.json")) &&
        all(vapply(lc_map, function(x) identical(x$lifecycle, "live"), logical(1))),
      "nba_data_lifecycle() assigns lifecycle = 'live' to every file")

fd <- tempfile("lc_writer_")
dir.create(fd, recursive = TRUE)
writeLines(jsonlite::toJSON(list(throughDate = "2026-11-22", generatedAt = "2026-11-24T05:13:46Z"),
                            auto_unbox = TRUE),
           file.path(fd, "defensive_metrics.json"))
writeLines('[{"team":"BOS"}]', file.path(fd, "projections_season_teams.json"))
writeLines('[{"pick":1}]', file.path(fd, "offseason_draft.json"))

write_data_manifest(data_dir = fd, schedule_path = NULL,
                    now = as.POSIXct("2026-11-24 05:16:15", tz = "UTC"))
wm <- jsonlite::fromJSON(file.path(fd, "data_manifest.json"), simplifyVector = FALSE)
check(length(wm$datasets) == 3L &&
        all(vapply(wm$datasets, function(e) identical(e$lifecycle, "live"), logical(1))),
      "write_data_manifest() attaches lifecycle = 'live' to every dataset (dated, undated, static)")
check(isTRUE(wm$datasets[["offseason_draft.json"]]$static) &&
        identical(wm$datasets[["defensive_metrics.json"]]$through_date, "2026-11-22"),
      "existing manifest fields (static, through_date) are preserved")

# Standalone sourcing without config.R still defaults every file to live.
standalone_env <- new.env(parent = baseenv())
sys.source(file.path(REPO_ROOT, "tools", "write_data_manifest.R"), envir = standalone_env)
sm <- standalone_env$build_data_manifest(data_dir = fd, schedule_path = NULL, prev_manifest = NULL)
check(all(vapply(sm$datasets, function(e) identical(e$lifecycle, "live"), logical(1))),
      "standalone write_data_manifest.R without config.R still assigns lifecycle = 'live'")

# Committed web/public/data tree receives lifecycle = "live" on every dataset.
dd <- file.path(REPO_ROOT, "web", "public", "data")
real_m <- build_data_manifest(data_dir = dd, schedule_path = NULL)
on_disk <- setdiff(sort(list.files(dd, pattern = "\\.json$")), "data_manifest.json")
check(setequal(names(real_m$datasets), on_disk) &&
        all(vapply(real_m$datasets, function(e) identical(e$lifecycle, "live"), logical(1))),
      sprintf("build_data_manifest() emits lifecycle = 'live' across all %d committed payloads", length(on_disk)))

cat("\n(b) assertion L passes when every file has valid lifecycle\n")
L_fd <- .assert_lifecycle(fd)
check(isTRUE(L_fd$pass) && identical(L_fd$id, "L") && isTRUE(L_fd$fatal),
      "assertion L passes on manifest built by write_data_manifest() (id = 'L', fatal = TRUE)")
check(identical(unname(L_fd$counts[["live"]]), 3L), "assertion L counts 3 live datasets")

md_copy <- tempfile("lc_real_")
dir.create(md_copy, recursive = TRUE)
invisible(file.copy(file.path(dd, on_disk), md_copy))
writeLines(jsonlite::toJSON(real_m, auto_unbox = TRUE, null = "null", pretty = TRUE),
           file.path(md_copy, "data_manifest.json"))
L_real <- .assert_lifecycle(md_copy)
check(isTRUE(L_real$pass), "assertion L passes on rebuilt manifest for the committed web/public/data tree")
H_real <- .assert_manifest_and_coverage(md_copy, schedule_through_date = real_m$schedule_through_date,
                                        schedule_path = file.path(md_copy, "no_cache.rds"))
check(isTRUE(H_real$pass), "assertion H still passes when lifecycle = 'live' is present")

# Valid mix of live, archived, and season_final (with matching hash).
d_mix <- make_fixture(list("a.json" = make_entry("live"),
                           "b.json" = make_entry("archived", through = NULL, static = TRUE, reason = "prior season")),
                      extra_files = "c.json", write_manifest = FALSE)
frozen_hash <- nba_lifecycle_sha256(file.path(d_mix, "c.json"))
mix_manifest <- list(
  schema_version = 1L, sport = "nba", generated_at = "2026-11-24T05:16:15Z",
  schedule_through_date = "2026-11-22",
  datasets = list(
    "a.json" = make_entry("live"),
    "b.json" = make_entry("archived", through = NULL, static = TRUE, reason = "prior season"),
    "c.json" = make_entry("season_final", extra = list(
      season = "2025-26",
      final_through_date = "2026-06-20",
      frozen_sha256 = frozen_hash,
      frozen_at = "2026-06-21T03:00:00Z"
    ))
  )
)
writeLines(jsonlite::toJSON(mix_manifest, auto_unbox = TRUE, null = "null", pretty = TRUE),
           file.path(d_mix, "data_manifest.json"))
L_mix <- .assert_lifecycle(d_mix)
check(isTRUE(L_mix$pass) && identical(unname(L_mix$counts[["season_final"]]), 1L),
      "assertion L passes for live + archived + hash-verified season_final")

# CRLF rewrite on season_final still verifies as unchanged.
c_path <- file.path(d_mix, "c.json")
c_lines <- readLines(c_path, warn = FALSE)
con <- file(c_path, "wb")
writeBin(charToRaw(paste0(paste(c_lines, collapse = "\r\n"), "\r\n")), con)
close(con)
check(isTRUE(.assert_lifecycle(d_mix)$pass),
      "assertion L treats CRLF-only difference on season_final as unchanged")

cat("\n(c) assertion L fails on missing, empty, unknown, unlisted, or tampered lifecycle\n")
d_missing <- make_fixture(list("a.json" = make_entry("live"), "b.json" = make_entry(lifecycle = NULL)))
r_missing <- .assert_lifecycle(d_missing)
check(!r_missing$pass && "b.json" %in% r_missing$failing &&
        any(grepl("\\[NO LIFECYCLE\\].*b\\.json", r_missing$detail)),
      "file with no lifecycle fails assertion L with [NO LIFECYCLE]")

d_empty <- make_fixture(list("a.json" = make_entry("")))
r_empty <- .assert_lifecycle(d_empty)
check(!r_empty$pass && "a.json" %in% r_empty$failing,
      "file with empty string lifecycle fails assertion L")

d_unknown <- make_fixture(list("a.json" = make_entry("live"), "bad.json" = make_entry("bogus")))
r_unknown <- .assert_lifecycle(d_unknown)
check(!r_unknown$pass && "bad.json" %in% r_unknown$failing &&
        any(grepl("unknown lifecycle 'bogus'", r_unknown$detail, fixed = TRUE)),
      "file with unknown lifecycle fails assertion L")

d_unlisted <- make_fixture(list("a.json" = make_entry("live")), extra_files = "orphan.json")
r_unlisted <- .assert_lifecycle(d_unlisted)
check(!r_unlisted$pass && "orphan.json" %in% r_unlisted$failing,
      "unlisted JSON file on disk fails assertion L")

d_nomanifest <- make_fixture(list("a.json" = make_entry("live")), write_manifest = FALSE)
check(!.assert_lifecycle(d_nomanifest)$pass,
      "absent data_manifest.json fails assertion L")

# season_final missing frozen_sha256 fails; tampered bytes fail.
bad_frozen <- mix_manifest
bad_frozen$datasets[["c.json"]]$frozen_sha256 <- NULL
check(!.assert_lifecycle(d_mix, manifest = bad_frozen)$pass,
      "season_final missing frozen_sha256 fails assertion L")

writeLines('{"x": 999}', file.path(d_mix, "c.json"))
r_tamper <- .assert_lifecycle(d_mix)
check(!r_tamper$pass && "c.json" %in% r_tamper$failing &&
        any(grepl("\\[CHANGED\\].*c\\.json", r_tamper$detail)),
      "season_final whose bytes changed fails assertion L with [CHANGED]")

cat("\n(d) publish_web() integrates assertion L without altering A-H\n")
pw_src <- paste(readLines(file.path(REPO_ROOT, "tools", "publish_web.R"), warn = FALSE), collapse = "\n")
check(grepl(".assert_lifecycle(WEB_DATA_DIR)", pw_src, fixed = TRUE),
      "publish_web() calls .assert_lifecycle(WEB_DATA_DIR)")
quiet_pw <- function(expr) { utils::capture.output(r <- suppressMessages(expr)); r }
pw_res <- quiet_pw(publish_web(dry_run = TRUE, skip_contracts = TRUE))
check("L" %in% c(pw_res$assertions_passed, pw_res$assertions_failed) &&
        all(c("A", "B", "C", "D", "E", "F", "G", "H") %in% c(pw_res$assertions_passed, pw_res$assertions_failed)),
      "publish_web() executes assertion L alongside A-H")
check(isTRUE(pw_res$manifest_pass),
      "publish_web() keeps assertion H passing regardless of lifecycle state")

cat(sprintf("\n%d passed, %d failed\n", n_pass, n_fail))
quit(status = if (n_fail == 0L) 0L else 1L)
