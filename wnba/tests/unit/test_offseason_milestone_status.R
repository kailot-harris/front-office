# ==============================================================================
# test_offseason_milestone_status.R
# Status mapping for the edition's upcomingMilestones in build_offseason_monitor.R.
#
# Before this, every status other than Confirmed/Tentative became "Tentative",
# so the reported (not confirmed) 2027 season window showed as Tentative.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# ------------------------------------------------------------------------------
args_all <- commandArgs(trailingOnly = FALSE)
f <- sub("^--file=", "", args_all[grepl("^--file=", args_all)])
if (length(f) == 1 && nzchar(f) && file.exists(f)) {
  cand <- normalizePath(dirname(dirname(dirname(f))), winslash = "/", mustWork = FALSE)
  if (file.exists(file.path(cand, "config.R"))) setwd(cand)
}
cur <- getwd()
while (!file.exists(file.path(cur, "config.R")) && dirname(cur) != cur) {
  cur <- dirname(cur)
}
if (file.exists(file.path(cur, "config.R"))) setwd(cur)

dir.create("logs", showWarnings = FALSE)

# renv's sandbox hides the user library where testthat is installed. renv keeps
# the user library path it replaced in RENV_DEFAULT_R_LIBS_USER; append it.
default_user_libs <- strsplit(Sys.getenv("RENV_DEFAULT_R_LIBS_USER"), .Platform$path.sep, fixed = TRUE)[[1]]
default_user_libs <- default_user_libs[nzchar(default_user_libs) & dir.exists(default_user_libs)]
.libPaths(unique(c(.libPaths(), default_user_libs, Sys.getenv("R_LIBS_USER"))))

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

# Source the builder without triggering its trailing CLI guard
interactive <- function() TRUE
source("build_offseason_monitor.R")
rm(interactive)

test_that("Confirmed, Tentative and Reported pass through; anything else is Tentative", {
  ms <- map_upcoming_milestones(list(
    list(date = "2026-11-15", event = "A", status = "Confirmed"),
    list(date = "2027-04-25", event = "B", status = "Tentative"),
    list(date = "2027-05-07", event = "C", status = "Reported"),
    list(date = NULL, event = "D", status = "Unannounced"),
    list(date = "2027-04-12", event = "E")
  ))
  expect_identical(vapply(ms, `[[`, character(1), "status"),
                   c("Confirmed", "Tentative", "Reported", "Tentative", "Tentative"))
  expect_identical(vapply(ms, `[[`, character(1), "event"), c("A", "B", "C", "D", "E"))
})

test_that("empty or missing dates become NULL (Date TBD), real dates are kept", {
  ms <- map_upcoming_milestones(list(
    list(date = "2026-11-15", event = "A", status = "Confirmed"),
    list(date = setNames(list(), character(0)), event = "B", status = "Unannounced"),
    list(date = "", event = "C", status = "Tentative"),
    list(event = "D", status = "Tentative")
  ))
  expect_identical(ms[[1]]$date, "2026-11-15")
  expect_null(ms[[2]]$date)
  expect_null(ms[[3]]$date)
  expect_null(ms[[4]]$date)
  expect_length(map_upcoming_milestones(NULL), 0L)
})

test_that("baseline-shaped JSON: the reported season window maps to Reported, empty dates to NULL", {
  # Same JSON shape as league.calendarMilestones.value in the league state
  # baseline written by tools/offseason/capture_baseline_s0.R (PR #219), read
  # the way the builder reads it. Inline on purpose: tests never read cache/.
  season_url <- "https://www.espn.com/wnba/story/_/id/50466261/sources-2027-wnba-season-start-7"
  baseline_json <- sprintf('[
    {"date": "2026-11-15", "event": "2027 WNBA Draft Lottery", "status": "Confirmed"},
    {"date": {}, "event": "Free Agency Negotiation & Contract Execution Period", "status": "Unannounced"},
    {"date": "2027-05-07",
     "event": "2027 WNBA season window, reported, not confirmed: expected to open May 7 and end no later than Oct. 24 (reported by ESPN 2026-11-13, %s)",
     "status": "Reported", "sourceUrl": "%s"}
  ]', season_url, season_url)
  ms <- map_upcoming_milestones(jsonlite::fromJSON(baseline_json, simplifyVector = FALSE))

  expect_identical(vapply(ms, `[[`, character(1), "status"), c("Confirmed", "Tentative", "Reported"))
  expect_identical(ms[[3]]$date, "2027-05-07")
  expect_null(ms[[2]]$date)

  # Serialized the way the dataset is written: TBD dates are null.
  js <- jsonlite::toJSON(ms, auto_unbox = TRUE, null = "null")
  expect_true(grepl('"status":"Reported"', js, fixed = TRUE))
  expect_true(grepl('"date":null', js, fixed = TRUE))
})
