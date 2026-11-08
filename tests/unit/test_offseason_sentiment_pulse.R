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
  # beat_003 ("Draft lottery order set - The league confirmed...") names neither
  # the WNBA nor any franchise, so the relevance gate excludes it; the
  # league_wire item was never a beat item to begin with.
  expect_equal(res$articleCount, 2L)
  expect_equal(res$beatItemsSeen, 3L)
  expect_equal(res$offTopicExcluded, 1L)
  expect_true(is.numeric(res$meanSentiment))
  expect_equal(res$scrapedCount, 0L)          # scrape = FALSE: no network at all
  expect_equal(res$fallbackCount, 2L)

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
            "Aces dominant win lifts optimism - A superb and encouraging WNBA performance delighted the home crowd.",
            url = "http://this-host-does-not-exist.invalid/article/1"),
    mk_item("beat_bad_2", "winsidr",
            "Fever injury setback clouds outlook - A terrible, worrying diagnosis frustrated the Indiana training staff.",
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
  # 2, not 3: happy_items' beat_003 is excluded by the relevance gate
  expect_true(grepl("Articles scored:** 2", after$markdown, fixed = TRUE))
  # The pre-existing 7 blocks are unchanged; the new section is strictly appended.
  expect_true(startsWith(after$markdown, before$markdown))
})

test_that("Unavailable pulse renders an explicit unavailable line, never a number", {
  blk <- render_block_media_sentiment(compute_media_sentiment_pulse(list(), scrape = FALSE))
  expect_true(grepl("unavailable", blk, fixed = TRUE))
  expect_false(grepl("Mean sentiment", blk, fixed = TRUE))
})

# ==============================================================================
# Relevance gate, team-name masking, extreme word floor
# Added after the 2026-11-07 live run published a WTA/NCAA/PWHL-contaminated
# pulse whose extremes were short RSS titles and whose top "positive" words were
# franchise names.
# ==============================================================================

test_that("Team-name vocabulary is derived from config.R's WNBA_TEAMS, not a local list", {
  skip_if_not(exists("WNBA_TEAMS"), "config.R not loaded")
  vocab <- wnba_team_vocabulary()

  expect_equal(length(vocab$full), length(WNBA_TEAMS))
  expect_true(all(tolower(unname(WNBA_TEAMS)) %in% vocab$full))
  # Nicknames and cities are split off the same source strings
  expect_true("liberty" %in% vocab$nickname)
  expect_true("valkyries" %in% vocab$nickname)
  expect_true("new york" %in% vocab$city)
  expect_true("golden state" %in% vocab$city)
  # Longest-first ordering so a full name is consumed before its city prefix
  expect_true(which(vocab$all == "golden state valkyries") <
                which(vocab$all == "golden state"))
})

test_that("mask_team_names strips franchise vocabulary and nothing else", {
  masked <- mask_team_names("The New York Liberty beat the Golden State Valkyries in a brilliant game")
  expect_false(grepl("liberty", masked, ignore.case = TRUE))
  expect_false(grepl("valkyries", masked, ignore.case = TRUE))
  expect_false(grepl("new york", masked, ignore.case = TRUE))
  # Genuine sentiment vocabulary survives untouched
  expect_true(grepl("brilliant", masked, ignore.case = TRUE))

  # Adjacent team references both mask in one pass (lookaround, not \\b)
  both <- mask_team_names("Liberty Sky doubleheader")
  expect_false(grepl("liberty", both, ignore.case = TRUE))
  expect_false(grepl("sky", both, ignore.case = TRUE))

  # Substrings of longer words are not touched
  expect_true(grepl("liberties", mask_team_names("civil liberties"), ignore.case = TRUE))
  expect_true(grepl("firearm", mask_team_names("firearm"), ignore.case = TRUE))
})

test_that("Masking removes the franchise-name contribution to the score", {
  skip_if_not_installed("syuzhet")
  # "liberty" and "golden" are bing/syuzhet positives and were the two largest
  # positive terms in the live run, with no sentiment meaning here.
  txt <- "Liberty and Golden State met again"
  unmasked <- score_text_sentiment(txt)
  masked <- score_text_sentiment(mask_team_names(txt))

  expect_false(is.null(unmasked))
  expect_gt(unmasked$raw, 0)                 # scored positive purely on team names
  if (!is.null(masked)) expect_lt(masked$raw, unmasked$raw)
})

test_that("Off-topic items are excluded and counted, never scored", {
  items <- list(
    mk_item("rel_1", "espn_wnba_beat",
            "Storm extend their veteran guard - Seattle completed a strong and welcome re-signing."),
    mk_item("off_1", "just_womens_sports",
            "Elena Rybakina leads tennis's elite into the 2026 WTA Finals - a superb season."),
    mk_item("off_2", "the_next_hoops",
            "PWHL Detroit's guide to the world championship - hockey preview."),
    mk_item("off_3", "just_womens_sports",
            "Sienna Betts posts career-best 17 points as UCLA cruises past UC Irvine.")
  )

  expect_true(item_is_wnba_relevant(items[[1]]))
  expect_false(item_is_wnba_relevant(items[[2]]))
  expect_false(item_is_wnba_relevant(items[[3]]))
  expect_false(item_is_wnba_relevant(items[[4]]))

  res <- compute_media_sentiment_pulse(items, scrape = FALSE)
  expect_true(res$available)
  expect_equal(res$beatItemsSeen, 4L)
  expect_equal(res$articleCount, 1L)
  expect_equal(res$offTopicExcluded, 3L)
  # The tennis item was the most positive text in the set; it must not surface
  expect_false(grepl("Rybakina", res$mostPositive$headline, fixed = TRUE))
  expect_true(grepl("Storm", res$mostPositive$headline, fixed = TRUE))
})

test_that("An all-off-topic week is labelled unavailable, not scored", {
  items <- list(
    mk_item("off_1", "just_womens_sports", "Tennis finals preview - a superb field assembles."),
    mk_item("off_2", "the_next_hoops", "Hockey East monthly recap: October 2026.")
  )
  res <- compute_media_sentiment_pulse(items, scrape = FALSE)
  expect_false(res$available)
  expect_null(res$meanSentiment)
  expect_null(res$mostPositive)
  expect_true(grepl("mentioned the WNBA", res$reason))
})

test_that("Extremes respect the word floor but every item still feeds the mean", {
  skip_if_not_installed("syuzhet")
  long_text <- paste(
    "Fever front office review -",
    "Indiana spent the week completing a steady and constructive set of roster moves that",
    "the staff described as a good outcome for the group, with a calm and favourable",
    "response from players, a positive tone around the facility, and a solid plan for the",
    "coming months that most observers called a reasonable and welcome direction overall."
  )
  items <- list(
    # Short, extreme per-word score: exactly the shape that won the live run
    mk_item("short_1", "her_hoop_stats", "Aces wonderful triumphant brilliant"),
    mk_item("long_1", "espn_wnba_beat", long_text),
    mk_item("long_2", "winsidr", paste("Mystics collapse review -",
            paste(rep("a bad and disappointing week for the roster and the staff overall", 6),
                  collapse = " ")))
  )

  res <- compute_media_sentiment_pulse(items, scrape = FALSE)
  expect_true(res$available)
  expect_equal(res$articleCount, 3L)                 # short item still counted
  expect_true(res$extremesFloorApplied)
  expect_equal(res$extremesMinWords, as.integer(OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS))
  expect_equal(res$extremesEligibleCount, 2L)

  # The 4-word item has the highest normalized score but is floor-ineligible
  expect_false(grepl("wonderful", res$mostPositive$headline, fixed = TRUE))
  expect_gte(res$mostPositive$words, as.integer(OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS))
  expect_gte(res$mostNegative$words, as.integer(OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS))
})

test_that("When nothing clears the floor the memo says so instead of hiding it", {
  skip_if_not_installed("syuzhet")
  items <- list(
    mk_item("s1", "espn_wnba_beat", "Liberty win again - a great result"),
    mk_item("s2", "winsidr", "Mystics lose again - a bad result")
  )
  res <- compute_media_sentiment_pulse(items, scrape = FALSE)
  expect_true(res$available)
  expect_false(res$extremesFloorApplied)
  expect_false(is.null(res$mostPositive))            # still reported, not dropped

  blk <- render_block_media_sentiment(res)
  expect_true(grepl("noise-prone", blk, fixed = TRUE))
})

test_that("An all-positive week labels its minimum 'Least positive', not 'Most negative'", {
  mk_pulse <- function(neg_score) list(
    available = TRUE, reason = NULL, articleCount = 10L, beatItemsSeen = 10L,
    offTopicExcluded = 0L, meanSentiment = 0.02, scrapedCount = 5L, fallbackCount = 5L,
    mostPositive = list(headline = "High", score = 0.06, rawScore = 2, words = 100L,
                        sourceId = "espn_wnba_beat", url = NA_character_, bodyScraped = TRUE),
    mostNegative = list(headline = "Low", score = neg_score, rawScore = 1, words = 100L,
                        sourceId = "winsidr", url = NA_character_, bodyScraped = TRUE),
    extremesMinWords = 40L, extremesFloorApplied = TRUE, extremesEligibleCount = 8L,
    teamNamesMasked = TRUE,
    wordBreakdown = list(available = TRUE, positive = list(), negative = list())
  )

  # Minimum is still positive -> the label must not claim a negative story
  blk_pos <- render_block_media_sentiment(mk_pulse(0.0043))
  expect_true(grepl("**Least positive:**", blk_pos, fixed = TRUE))
  expect_false(grepl("**Most negative:**", blk_pos, fixed = TRUE))

  # Genuinely negative minimum keeps the original label
  blk_neg <- render_block_media_sentiment(mk_pulse(-0.0210))
  expect_true(grepl("**Most negative:**", blk_neg, fixed = TRUE))
  expect_false(grepl("**Least positive:**", blk_neg, fixed = TRUE))
})

test_that("Memo block reports the exclusion count and the masking caveat", {
  skip_if_not_installed("syuzhet")
  pulse <- list(
    available = TRUE, reason = NULL, articleCount = 46L, beatItemsSeen = 70L,
    offTopicExcluded = 24L, meanSentiment = 0.0217, scrapedCount = 25L,
    fallbackCount = 21L,
    mostPositive = list(headline = "A", score = 0.05, rawScore = 2, words = 120L,
                        sourceId = "winsidr", url = NA_character_, bodyScraped = TRUE),
    mostNegative = list(headline = "B", score = -0.03, rawScore = -1.5, words = 90L,
                        sourceId = "espn_wnba_beat", url = NA_character_, bodyScraped = TRUE),
    extremesMinWords = 40L, extremesFloorApplied = TRUE, extremesEligibleCount = 33L,
    teamNamesMasked = TRUE,
    wordBreakdown = list(available = TRUE, positive = list(), negative = list())
  )
  blk <- render_block_media_sentiment(pulse)
  expect_true(grepl("24 off-topic items excluded of 70 ingested", blk, fixed = TRUE))
  expect_true(grepl("team names masked", blk, fixed = TRUE))
  expect_true(grepl("at least 40 words", blk, fixed = TRUE))
})
