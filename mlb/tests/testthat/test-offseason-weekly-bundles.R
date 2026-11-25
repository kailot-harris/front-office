.load_offseason_monitor <- function(envir) {
  old_wd <- getwd()
  on.exit(setwd(old_wd), add = TRUE)
  candidates <- c(
    file.path(old_wd, "build_offseason_monitor.R"),
    file.path(old_wd, "..", "..", "build_offseason_monitor.R")
  )
  target <- candidates[file.exists(candidates)][1L]
  stopifnot(!is.na(target))
  source(normalizePath(target, winslash = "/", mustWork = TRUE), local = envir)
}

test_that("compute_offseason_week and offseason_week_bounds anchor to 2026-10-31", {
  .load_offseason_monitor(environment())

  expect_identical(compute_offseason_week("2026-10-29"), 1L)
  expect_identical(compute_offseason_week("2026-10-31"), 1L)
  expect_identical(compute_offseason_week("2026-11-06"), 1L)
  expect_identical(compute_offseason_week("2026-11-07"), 2L)
  expect_identical(compute_offseason_week("2026-11-13"), 2L)
  expect_identical(compute_offseason_week("2026-11-14"), 3L)
  expect_identical(compute_offseason_week("2026-11-20"), 3L)
  expect_identical(compute_offseason_week("2026-11-21"), 4L)
  expect_identical(compute_offseason_week("2026-11-25"), 4L)
  expect_identical(compute_offseason_week("2026-11-27"), 4L)
  expect_identical(compute_offseason_week("2026-11-28"), 5L)

  b1 <- offseason_week_bounds(1L)
  expect_identical(b1$weekStartDate, "2026-10-31")
  expect_identical(b1$weekEndDate, "2026-11-06")

  b4 <- offseason_week_bounds(4L)
  expect_identical(b4$weekStartDate, "2026-11-21")
  expect_identical(b4$weekEndDate, "2026-11-27")
})

test_that("consolidate_offseason_editions merges same-week editions and deduplicates confirmedChanges", {
  .load_offseason_monitor(environment())

  mk_change <- function(date, player, tx_type, url) {
    list(
      date = date,
      team = "NYM",
      playerName = player,
      rosterTier = "MAJOR_40_MAN",
      transactionType = tx_type,
      priorValue = "A",
      newValue = "B",
      sourceUrl = url
    )
  }

  legacy <- list(
    list(
      weekNumber = 17L,
      publishDate = "2026-11-25",
      isQuietWeek = FALSE,
      isFrozenWeek = FALSE,
      totalConfirmedCount = 2L,
      confirmedChanges = list(
        mk_change("2026-11-24", "Player One", "FREE_AGENCY", "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=1"),
        mk_change("2026-11-24", "Player Two", "TRADE", "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=2")
      )
    ),
    list(
      weekNumber = 15L,
      publishDate = "2026-11-23",
      isQuietWeek = TRUE,
      isFrozenWeek = FALSE,
      totalConfirmedCount = 0L,
      confirmedChanges = list()
    ),
    list(
      weekNumber = 13L,
      publishDate = "2026-11-21",
      isQuietWeek = FALSE,
      isFrozenWeek = FALSE,
      totalConfirmedCount = 2L,
      confirmedChanges = list(
        mk_change("2026-11-24", "Player Two", "TRADE", "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=2"),
        mk_change("2026-11-20", "Player Three", "WAIVER_CLAIM", "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=3")
      )
    ),
    list(
      weekNumber = 1L,
      publishDate = "2026-10-31",
      isQuietWeek = FALSE,
      isFrozenWeek = FALSE,
      totalConfirmedCount = 1L,
      confirmedChanges = list(
        mk_change("2026-10-31", "Player Zero", "OPTION_DECLINED", "https://statsapi.mlb.com/api/v1/transactions?teamId=121&transactionIds=0")
      )
    )
  )

  out <- consolidate_offseason_editions(legacy)
  expect_length(out, 2L)
  expect_identical(out[[1]]$weekNumber, 4L)
  expect_identical(out[[1]]$weekStartDate, "2026-11-21")
  expect_identical(out[[1]]$weekEndDate, "2026-11-27")
  expect_identical(out[[1]]$publishDate, "2026-11-25")
  expect_identical(out[[1]]$totalConfirmedCount, 3L)
  expect_length(out[[1]]$confirmedChanges, 3L)
  expect_false(out[[1]]$isQuietWeek)

  expect_identical(out[[2]]$weekNumber, 1L)
  expect_identical(out[[2]]$weekStartDate, "2026-10-31")
  expect_identical(out[[2]]$weekEndDate, "2026-11-06")
  expect_identical(out[[2]]$totalConfirmedCount, 1L)
})
