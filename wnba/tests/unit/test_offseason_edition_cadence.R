# ==============================================================================
# test_offseason_edition_cadence.R
# Week numbering and projected next edition for build_offseason_monitor.R.
#
# Before this, the weekly run passed no --week, the builder defaulted to Week 1,
# and every run replaced Week 1 instead of adding Week 2, Week 3, ...
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

ed <- function(week, date) list(weekNumber = as.integer(week), publishDate = date)

test_that("cadence constant is Monday", {
  expect_identical(OFFSEASON_CADENCE_WEEKDAY, 1L)
  expect_equal(cadence_week_start("2026-11-17"), as.Date("2026-11-16"))  # Tue -> Mon
  expect_equal(cadence_week_start("2026-11-16"), as.Date("2026-11-16"))  # Mon -> same Mon
  expect_equal(cadence_week_start("2026-11-22"), as.Date("2026-11-16"))  # Sun -> prior Mon
})

test_that("week number: Week 1 when there are no editions", {
  expect_identical(derive_offseason_week_number(as.Date("2026-11-23"), list()), 1L)
  expect_identical(derive_offseason_week_number(as.Date("2026-11-23"), NULL), 1L)
})

test_that("week number: latest + 1 in a later cadence week", {
  eds <- list(ed(1, "2026-11-17"))
  expect_identical(derive_offseason_week_number(as.Date("2026-11-23"), eds), 2L)
  expect_identical(derive_offseason_week_number(as.Date("2026-12-01"), eds), 2L)
  eds3 <- list(ed(1, "2026-11-17"), ed(2, "2026-11-23"), ed(3, "2026-11-30"))
  expect_identical(derive_offseason_week_number(as.Date("2026-12-07"), eds3), 4L)
})

test_that("week number: same-week re-run replaces the latest edition", {
  eds <- list(ed(1, "2026-11-17"))
  expect_identical(derive_offseason_week_number(as.Date("2026-11-17"), eds), 1L)
  expect_identical(derive_offseason_week_number(as.Date("2026-11-20"), eds), 1L)
  expect_identical(derive_offseason_week_number(as.Date("2026-11-22"), eds), 1L)
})

test_that("week number: --week=N overrides derivation", {
  eds <- list(ed(1, "2026-11-17"))
  expect_identical(derive_offseason_week_number(as.Date("2026-11-23"), eds, week_override = 5L), 5L)
  expect_identical(derive_offseason_week_number(as.Date("2026-11-23"), list(), week_override = 3L), 3L)
})

test_that("nextEdition: next Monday strictly after the latest publishDate", {
  ne <- compute_offseason_next_edition(list(ed(1, "2026-11-17")))
  expect_identical(ne$weekNumber, 2L)
  expect_identical(ne$projectedPublishDate, "2026-11-23")

  # A Monday publish date gives the following Monday, not the same day
  ne_mon <- compute_offseason_next_edition(list(ed(1, "2026-11-17"), ed(2, "2026-11-23")))
  expect_identical(ne_mon$weekNumber, 3L)
  expect_identical(ne_mon$projectedPublishDate, "2026-11-30")

  # Sunday publish date -> next day
  expect_identical(compute_offseason_next_edition(list(ed(1, "2026-11-22")))$projectedPublishDate, "2026-11-23")

  # Unordered input still keys off the highest weekNumber
  ne_unord <- compute_offseason_next_edition(list(ed(2, "2026-11-23"), ed(1, "2026-11-17")))
  expect_identical(ne_unord$weekNumber, 3L)

  expect_null(compute_offseason_next_edition(list()))
})

test_that("CLI defaults --week to NULL so the builder derives the week", {
  src <- readLines("build_offseason_monitor.R")
  wk_line <- grep('wk_val <- ', src, value = TRUE)
  expect_length(wk_line, 1L)
  expect_match(wk_line, "else NULL$")
})
