# ==============================================================================
# test_offseason_memo_render.R
# Unit Tests for 7-Block Markdown Memo Renderer (Phase 4 / Issue #121)
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

suppressPackageStartupMessages({
  library(testthat)
})

source(file.path("tools", "offseason", "render_memo.R"))

test_that("Renderer generates quiet-week layout correctly", {
  memo_res <- render_7_block_memo(
    week_number = 1,
    publish_date = "2026-11-02",
    elapsed_days = 2,
    baseline_date = "2026-10-31",
    confirmed_changes = list(),
    reported_claims = list(),
    expired_claims = list(),
    upcoming_milestones = list(
      list(date = "2026-11-15", event = "2027 WNBA Draft Lottery (ESPN)", status = "Confirmed")
    ),
    sources_visited = list("https://www.wnba.com/news/transactions")
  )
  
  md <- memo_res$markdown
  
  # Check Header
  expect_true(grepl("## Week 1 — Monday, 02 November 2026", md))
  
  # Check Quiet Week sentence in State of Play
  expect_true(grepl("Quiet week: 0 confirmed state transitions recorded", md))
  expect_true(grepl("Elapsed interval 2 days \\(2026-10-31 to 2026-11-02\\)", md))
  
  # Check all 7 Block Headers
  expect_true(grepl("### 1\\. Confirmed Changes", md))
  expect_true(grepl("### 2\\. Reported \\(Unconfirmed\\)", md))
  expect_true(grepl("### 3\\. Expired Claims \\(Aged Out > 28 Days\\)", md))
  expect_true(grepl("### 4\\. Next 30 Days \\(Milestone Calendar\\)", md))
  expect_true(grepl("### 5\\. Model Implications \\(2027 Baseline Priors\\)", md))
  expect_true(grepl("### 6\\. Winter League & Alternative Play \\(Unrivaled / EuroLeague\\)", md))
  expect_true(grepl("### 7\\. Sources Verified", md))
  
  # Check Milestone
  expect_true(grepl("2026-11-15: 2027 WNBA Draft Lottery \\(ESPN\\)", md))
  
  # Check Sources
  expect_true(grepl("https://www.wnba.com/news/transactions", md))
})

test_that("Renderer formats confirmed changes and active rumors", {
  confirmed <- list(
    list(
      date = "2027-01-15",
      entityId = "1068",
      entityName = "Ezi Magbegor",
      field = "Core Designation",
      priorValue = "Uncored",
      newValue = "Cored",
      sourceUrl = "wnba.com/tx"
    )
  )
  
  reported <- list(
    list(
      id = "claim-1",
      entityName = "PHX",
      claim = "Seeking veteran point guard",
      sourceCategory = "Team Beat Wire",
      firstReportedDate = "2027-01-08",
      daysPending = 7
    )
  )
  
  memo_res <- render_7_block_memo(
    week_number = 11,
    publish_date = "2027-01-15",
    elapsed_days = 7,
    baseline_date = "2027-01-08",
    confirmed_changes = confirmed,
    reported_claims = reported
  )
  
  md <- memo_res$markdown
  
  expect_true(grepl("1 confirmed state transition recorded", md))
  expect_true(grepl("\\| 2027-01-15 \\| Ezi Magbegor \\| Core Designation \\| Uncored \\| Cored \\| wnba.com/tx \\|", md))
  expect_true(grepl("\\| PHX \\| Seeking veteran point guard \\| Team Beat Wire \\| 2027-01-08 \\| Pending \\(Day 7\\) \\|", md))
})
