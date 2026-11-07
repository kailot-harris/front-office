# ==============================================================================
# test_offseason_sentiment_pulse.R
# Unit Tests for Media Sentiment Pulse (Issue #156)
#
# Covers: populated happy path, zero beat-feed items, missing-package
# degradation, unreachable source_url fail-soft, and the additive memo block.
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

source(file.path("tools", "offseason", "sentiment_pulse.R"))
source(file.path("tools", "offseason", "render_memo.R"))

# ------------------------------------------------------------------------------
# Fixtures
# ------------------------------------------------------------------------------
mk_item <- function(id, src, text, url = NULL) {
  list(
    item_id = id,
    source_family = "beat_feeds",
    source_id = src,
    source_url = url,
    observed_at = "2026-11-07T12:00:00Z",
    event_date = "2026-11-06",
    raw_text = text
  )
}

happy_items <- list(
  mk_item("beat_001", "espn_wnba_beat",
          "Liberty extend star forward - A brilliant, triumphant week for New York as the front office secured a wonderful deal that delighted fans."),
  mk_item("beat_002", "winsidr",
          "Mystics season ends in disaster - A dreadful, painful collapse left the roster broken and the coaching staff bitterly disappointed."),
  mk_item("beat_003", "the_next_hoops",
          "Draft lottery order set - The league confirmed the sequence of selections for the upcoming draft."),
  # A non-beat item that must be ignored by the filter
  list(item_id = "wire_001", source_family = "league_wire", source_id = "wnba_transactions",
       source_url = NULL, observed_at = "2026-11-07T12:00:00Z", event_date = "2026-11-06",
       raw_text = "Official transaction wire entry - signed to a training camp contract.")
)

# ------------------------------------------------------------------------------
test_that("Happy path scores beat-feed items and ignores other source families", {
  res <- compute_media_sentiment_pulse(happy_items, scrape = FALSE)

  expect_true(res$available)
  expect_equal(res$articleCount, 3L)          # the league_wire item is excluded
  expect_equal(res$beatItemsSeen, 3L)
  expect_true(is.numeric(res$meanSentiment))
  expect_equal(res$scrapedCount, 0L)          # scrape = FALSE: no network at all
  expect_equal(res$fallbackCount, 3L)

  expect_true(grepl("Liberty", res$mostPositive$headline))
  expect_true(grepl("Mystics", res$mostNegative$headline))
  expect_gt(res$mostPositive$score, res$mostNegative$score)
  expect_identical(res$method, "syuzhet")

  # Headline derivation stops at the RSS " - " separator
  expect_identical(res$mostPositive$headline, "Liberty extend star forward")

  if (requireNamespace("tidytext", quietly = TRUE)) {
    expect_true(res$wordBreakdown$available)
    expect_gt(length(res$wordBreakdown$positive) + length(res$wordBreakdown$negative), 0)
  }
})

test_that("Zero beat-feed items returns a labelled empty result with no fabricated score", {
  res_empty <- compute_media_sentiment_pulse(list(), scrape = FALSE)
  expect_false(res_empty$available)
  expect_equal(res_empty$articleCount, 0L)
  expect_null(res_empty$meanSentiment)
  expect_true(grepl("no beat_feeds wire items", res_empty$reason))

  # Only non-beat families present => same labelled-empty outcome
  res_other <- compute_media_sentiment_pulse(list(happy_items[[4]]), scrape = FALSE)
  expect_false(res_other$available)
  expect_null(res_other$meanSentiment)
})

test_that("Missing syuzhet degrades to a labelled unavailable result (no placeholder number)", {
  # Simulate an uninstalled package by shadowing requireNamespace within the
  # function's lexical scope.
  fake_env <- new.env(parent = environment(compute_media_sentiment_pulse))
  assign("requireNamespace", function(pkg, ...) {
    if (pkg %in% c("syuzhet", "tidytext")) return(FALSE)
    base::requireNamespace(pkg, ...)
  }, envir = fake_env)

  fn <- compute_media_sentiment_pulse
  environment(fn) <- fake_env

  res <- fn(happy_items, scrape = FALSE)
  expect_false(res$available)
  expect_null(res$meanSentiment)
  expect_null(res$mostPositive)
  expect_true(grepl("syuzhet", res$reason))
  expect_false(res$wordBreakdown$available)
})

test_that("Unreachable source_url fails soft and falls back to the item's RSS text", {
  bad_items <- list(
    mk_item("beat_bad_1", "espn_wnba_beat",
            "Dominant win sparks optimism - A superb and encouraging performance delighted the home crowd.",
            url = "http://this-host-does-not-exist.invalid/article/1"),
    mk_item("beat_bad_2", "winsidr",
            "Injury setback clouds outlook - A terrible, worrying diagnosis frustrated the training staff.",
            url = "http://127.0.0.1:9/unreachable")
  )

  # Direct scraper contract: never raises, returns NULL on failure.
  expect_null(scrape_article_body("http://this-host-does-not-exist.invalid/x", timeout_sec = 3))
  expect_null(scrape_article_body(NULL))

  res <- compute_media_sentiment_pulse(bad_items, scrape = TRUE, timeout_sec = 3)
  expect_true(res$available)
  expect_equal(res$articleCount, 2L)
  expect_equal(res$scrapedCount, 0L)
  expect_equal(res$fallbackCount, 2L)
  expect_true(is.numeric(res$meanSentiment))
})

test_that("Memo renderer stays additive: absent argument changes nothing", {
  base_args <- list(
    week_number = 3,
    publish_date = "2026-11-09",
    elapsed_days = 7,
    baseline_date = "2026-11-02",
    sources_visited = list("https://www.wnba.com/news/transactions")
  )

  before <- do.call(render_7_block_memo, base_args)
  expect_false(grepl("Media Sentiment Pulse", before$markdown, fixed = TRUE))
  expect_null(render_block_media_sentiment(NULL))

  pulse <- compute_media_sentiment_pulse(happy_items, scrape = FALSE)
  after <- do.call(render_7_block_memo, c(base_args, list(media_sentiment_pulse = pulse)))
  expect_true(grepl("### Media Sentiment Pulse", after$markdown, fixed = TRUE))
  expect_true(grepl("Articles scored:** 3", after$markdown, fixed = TRUE))
  # The pre-existing 7 blocks are unchanged; the new section is strictly appended.
  expect_true(startsWith(after$markdown, before$markdown))
})

test_that("Unavailable pulse renders an explicit unavailable line, never a number", {
  blk <- render_block_media_sentiment(compute_media_sentiment_pulse(list(), scrape = FALSE))
  expect_true(grepl("unavailable", blk, fixed = TRUE))
  expect_false(grepl("Mean sentiment", blk, fixed = TRUE))
})
