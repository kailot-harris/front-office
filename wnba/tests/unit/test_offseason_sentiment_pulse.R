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
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
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
  expect_identical(res$method, "sentimentr + udpipe")
  expect_identical(res$lexicon, "jockers_rinker")
  expect_true(res$posDisambiguated)
  expect_identical(res$modelVersion, SP_UDPIPE_MODEL_VERSION)

  # Headline derivation stops at the RSS " - " separator
  expect_identical(res$mostPositive$headline, "Liberty extend star forward")

  if (requireNamespace("lexicon", quietly = TRUE)) {
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

test_that("Missing udpipe degrades to a labelled unavailable result (no placeholder number)", {
  # Simulate an uninstalled package by shadowing requireNamespace within the
  # scorer-gate's lexical scope.
  fake_env <- new.env(parent = environment(.sp_scorer_unavailable_reason))
  assign("requireNamespace", function(pkg, ...) {
    if (pkg %in% c("udpipe", "sentimentr")) return(FALSE)
    base::requireNamespace(pkg, ...)
  }, envir = fake_env)

  gate <- .sp_scorer_unavailable_reason
  environment(gate) <- fake_env

  fn_env <- new.env(parent = environment(compute_media_sentiment_pulse))
  assign(".sp_scorer_unavailable_reason", gate, envir = fn_env)
  fn <- compute_media_sentiment_pulse
  environment(fn) <- fn_env

  res <- fn(happy_items, scrape = FALSE)
  expect_false(res$available)
  expect_null(res$meanSentiment)
  expect_null(res$mostPositive)
  expect_true(grepl("udpipe", res$reason))
  expect_false(res$wordBreakdown$available)
})

# ------------------------------------------------------------------------------
# Issue #171: the pinned-model fail-safe, with NO syuzhet fallback
# ------------------------------------------------------------------------------

test_that("A missing pinned udpipe model yields unavailable, never a fallback number", {
  # Point the model resolver at a path that does not exist. This is the
  # fresh-clone-without-the-artifact case and the corrupted-download case.
  env <- environment(.sp_scorer_unavailable_reason)
  saved <- get(".sp_udpipe_model_path", envir = env)
  on.exit(assign(".sp_udpipe_model_path", saved, envir = env), add = TRUE)
  assign(".sp_udpipe_model_path",
         function() file.path(tempdir(), "no-such-model.udpipe"), envir = env)

  res <- compute_media_sentiment_pulse(happy_items, scrape = FALSE)

  expect_false(res$available)
  expect_null(res$meanSentiment)
  expect_null(res$mostPositive)
  expect_null(res$mostNegative)
  expect_true(is.character(res$reason) && nzchar(res$reason))
  expect_true(grepl("missing", res$reason))
  expect_true(grepl(SP_UDPIPE_MODEL_VERSION, res$reason, fixed = TRUE))
  expect_false(res$wordBreakdown$available)
  # The published method string must never silently become the old scorer's.
  expect_false(grepl("syuzhet", res$method))
  expect_false(isTRUE(res$posDisambiguated))
})

test_that("An unreadable pinned udpipe model yields unavailable, not a fallback number", {
  # A file that exists but is not a udpipe model: udpipe_load_model() raises,
  # and the scorer must degrade rather than reach for syuzhet.
  bad <- file.path(tempdir(), "corrupt-model.udpipe")
  writeLines("this is not a udpipe model", bad)
  on.exit(unlink(bad), add = TRUE)

  env <- environment(.sp_scorer_unavailable_reason)
  saved <- get(".sp_udpipe_model_path", envir = env)
  on.exit(assign(".sp_udpipe_model_path", saved, envir = env), add = TRUE)
  assign(".sp_udpipe_model_path", function() bad, envir = env)

  res <- suppressWarnings(compute_media_sentiment_pulse(happy_items, scrape = FALSE))

  expect_false(res$available)
  expect_null(res$meanSentiment)
  expect_true(grepl("could not be loaded", res$reason))
  expect_false(grepl("syuzhet", res$method))
})

test_that("There is no syuzhet or bing scoring path left in the scorer", {
  src <- readLines(file.path("tools", "offseason", "sentiment_pulse.R"), warn = FALSE)
  code <- src[!grepl("^\\s*#", src)]   # drop comments/roxygen: history may name them
  expect_false(any(grepl("syuzhet::", code, fixed = TRUE)))
  expect_false(any(grepl("tidytext::", code, fixed = TRUE)))
  expect_false(any(grepl("get_sentiments", code, fixed = TRUE)))
  # And the real scorer is actually wired in.
  expect_true(any(grepl("sentimentr::sentiment", code, fixed = TRUE)))
  expect_true(any(grepl("udpipe::udpipe_annotate", code, fixed = TRUE)))
})

# ------------------------------------------------------------------------------
# Issue #171: negation / valence shifting -- the half sentimentr owns
# ------------------------------------------------------------------------------

test_that("Negation flips the sign, which syuzhet could not do at all", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")

  norm <- function(t) {
    s <- score_text_sentiment(t)
    expect_false(is.null(s))
    s$normalized
  }

  # "not good": a plain negator over a positive adjective.
  expect_gt(norm("The move is good for the roster."), 0)
  expect_lt(norm("The move is not good for the roster."), 0)

  # "hardly ideal": a negative-polarity adverb. sentimentr's stock table types
  # `hardly` as a de-amplifier, which left this POSITIVE (+0.0667); the
  # SP_NEGATOR_RETYPED correction is what makes the sign right.
  expect_gt(norm("The situation is ideal."), 0)
  expect_lt(norm("The situation is hardly ideal."), 0)

  # "never been better": emphatic comparative positive (Issue #172).
  expect_gt(norm("She has been better."), 0)
  expect_gt(norm("She has never been better."), 0)
})

# ------------------------------------------------------------------------------
# Issue #172: 'never' + comparative polarity preservation
# ------------------------------------------------------------------------------

test_that("Issue #172: 'never' + comparative scores with expected polarity sign", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")

  norm <- function(t) {
    s <- score_text_sentiment(t)
    expect_false(is.null(s))
    s$normalized
  }
  raw <- function(t) {
    s <- score_text_sentiment(t)
    expect_false(is.null(s))
    s$raw
  }

  # Fixed cases:
  # "never been better" and "never looked better" score positive
  expect_gt(norm("She has never been better."), 0)
  expect_gt(raw("She has never been better."), 0)
  expect_gt(norm("The roster has never looked better."), 0)
  expect_gt(raw("The roster has never looked better."), 0)

  # "never been worse" scores negative
  expect_lt(norm("She has never been worse."), 0)
  expect_lt(raw("She has never been worse."), 0)

  # Controls:
  # Non-comparative negations maintain standard negative sign
  expect_lt(norm("The move is not good for the roster."), 0)
  expect_lt(norm("The situation is hardly ideal."), 0)
  expect_lt(norm("She has never been good."), 0)

  # Litotes / other comparative idioms maintain correct positive signs
  expect_gt(norm("The timing couldn't be better."), 0)
  expect_gt(norm("The coach couldn't be happier."), 0)
  expect_gt(norm("The season was not bad."), 0)
  expect_gt(norm("She has never been bad."), 0)
})

test_that("Negators and de-amplifiers survive the POS filter", {
  skip_if_not_installed("udpipe")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  # `not` is PART and `no` is DET -- both in SP_POS_FUNCTION_CLASSES. If the
  # valence-shifter exemption regressed, they would be dropped before
  # sentimentr ever saw them and negation would silently stop working.
  out <- .sp_pos_filter_text("The move is not good. There is no depth.")
  expect_false(is.null(out))
  expect_true("not" %in% out$tokens$token)
  expect_true("no" %in% out$tokens$token)
})

test_that("SP_NEGATOR_RETYPED is applied to the valence-shifter table", {
  skip_if_not_installed("sentimentr")
  skip_if_not_installed("lexicon")
  dt <- .sp_valence_shifter_table()
  skip_if(is.null(dt), "valence shifter table unavailable")
  df <- as.data.frame(dt)
  names(df)[1:2] <- c("x", "y")
  # Every retyped term the shifter table carries must be a negator. `scarcely`
  # is deliberately absent: the polarity lexicon claims it, and sentimentr
  # requires the two tables to be mutually exclusive.
  present <- intersect(SP_NEGATOR_RETYPED, df$x)
  expect_true(length(present) >= 4)
  for (w in present) {
    expect_identical(as.integer(df$y[df$x == w]), 1L,
                     info = paste(w, "must be typed as a negator"))
  }
  expect_false("scarcely" %in% df$x)
  # The stock table types these 3; this test fails loudly if a sentimentr
  # upgrade changes them, because that would silently move published numbers.
  stock <- as.data.frame(lexicon::hash_valence_shifters)
  names(stock)[1:2] <- c("x", "y")
  expect_identical(as.integer(stock$y[stock$x == "hardly"]), 3L)
})

# ------------------------------------------------------------------------------
# Issue #171: word sense -- the half udpipe owns, and the defect #171 was opened for
# ------------------------------------------------------------------------------

test_that("`like` scores as a verb but not as a preposition or conjunction", {
  skip_if_not_installed("udpipe")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")

  # ADP: a comparison, not an opinion. This single conflation made `like` the
  # #1 positive chip (107 occurrences) on the 2026-11-09 corpus.
  prep <- .sp_pos_filter_text("She played like a veteran out there.")
  expect_false("like" %in% prep$tokens$token)

  # SCONJ: a discourse marker.
  conj <- .sp_pos_filter_text("It was the move, like I said earlier.")
  expect_false("like" %in% conj$tokens$token)

  # VERB: a genuine opinion, which must still score.
  verb <- .sp_pos_filter_text("I like what I saw from the rookie.")
  expect_true("like" %in% verb$tokens$token)
})

test_that("`right` scores as an adjective but not as an adverb", {
  skip_if_not_installed("udpipe")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")

  # ADV: a temporal/degree intensifier. `right` is +0.80 in jockers_rinker and
  # was the #5 positive chip (38 occurrences).
  expect_false("right" %in% .sp_pos_filter_text("Right now the roster is unsettled.")$tokens$token)
  expect_false("right" %in% .sp_pos_filter_text("She was right there from the start.")$tokens$token)

  # ADJ: a real evaluation, which must still score.
  expect_true("right" %in% .sp_pos_filter_text("She made the right call in the fourth.")$tokens$token)
})

test_that("Discourse-marker `well` is dropped but adverbial `well` still scores", {
  skip_if_not_installed("udpipe")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  # INTJ, caught by the generic function-class rule with no entry in
  # SP_POS_POLAR_SENSE -- which is the point of preferring a POS rule to a list.
  expect_false("well" %in% .sp_pos_filter_text("Well, the roster is young.")$tokens$token)
  expect_true("well" %in% .sp_pos_filter_text("The team is playing well.")$tokens$token)
})

test_that("The published chips come from the POS-filtered tokens, so `like` cannot reappear", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")

  items <- list(
    mk_item("ws_1", "espn_wnba_beat",
            "Liberty extend star forward - She played like a veteran, like I said all year, and it looks like a good deal."),
    mk_item("ws_2", "winsidr",
            "Mystics shake up the front office - Right now it is unsettled, but they got the right coach right away.")
  )
  res <- compute_media_sentiment_pulse(items, scrape = FALSE)
  expect_true(res$available)
  pos_words <- vapply(res$wordBreakdown$positive, function(w) w$word, character(1))

  # `like` appears 3x in ws_1: ADP, SCONJ, and "looks like" -- none an opinion.
  expect_false("like" %in% pos_words)
  # `right` appears 3x in ws_2, of which exactly one ("the right coach") is ADJ,
  # so if it charts at all it must be at n = 1, never 3.
  right_n <- vapply(res$wordBreakdown$positive, function(w) w$n, integer(1))[pos_words == "right"]
  if (length(right_n) == 1) expect_equal(right_n[[1]], 1L)
})

test_that("Scoring the same text twice is bit-identical (no RNG on this path)", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  txt <- "The move is not good, but the young core looks like a real strength right now."
  a <- score_text_sentiment(txt)
  b <- score_text_sentiment(txt)
  expect_false(is.null(a))
  expect_identical(a$normalized, b$normalized)
  expect_identical(a$raw, b$raw)
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

test_that("mask_basketball_jargon strips the unambiguous stat-sheet vocabulary", {
  txt <- paste("Her defensive instincts are brilliant: 3 steals, 2 blocks and a block",
               "plus an offensive foul, strong offense and defense, and one steal.")
  masked <- mask_basketball_jargon(txt)
  for (w in c("defensive", "steals", "offensive", "steal", "foul",
              "offense", "defense", "block", "blocks")) {
    expect_false(grepl(paste0("(?<![[:alpha:]])", w, "(?![[:alpha:]])"),
                       masked, perl = TRUE, ignore.case = TRUE),
                 info = paste("token survived masking:", w))
  }
  # Genuine sentiment vocabulary survives untouched
  expect_true(grepl("brilliant", masked, ignore.case = TRUE))
  expect_true(grepl("strong", masked, ignore.case = TRUE))
  # Whitespace runs are collapsed
  expect_false(grepl("  ", masked, fixed = TRUE))
})

test_that("mask_basketball_jargon is phrase-first with the longest match winning", {
  # "offensive rebound" is consumed as a phrase, not twice as two singles
  expect_false(grepl("rebound", mask_basketball_jargon("an offensive rebound"),
                     ignore.case = TRUE))
  # Line-wrapped phrases still mask as phrases
  expect_false(grepl("guard", mask_basketball_jargon("a point\nguard"), ignore.case = TRUE))
  # Adjacent terms both mask in one pass (lookaround, not \\b)
  both <- mask_basketball_jargon("steals blocks")
  expect_false(grepl("steals", both, ignore.case = TRUE))
  expect_false(grepl("blocks", both, ignore.case = TRUE))
  # Substrings of longer words are untouched
  expect_true(grepl("defensively", mask_basketball_jargon("defensively"), ignore.case = TRUE))
  expect_true(grepl("blockade", mask_basketball_jargon("blockade"), ignore.case = TRUE))
})

test_that("The five ambiguous singles follow their documented dispositions", {
  # guard / shot: masked bare
  expect_false(grepl("guard", mask_basketball_jargon("the veteran guard"), ignore.case = TRUE))
  expect_false(grepl("shot", mask_basketball_jargon("she shot well"), ignore.case = TRUE))
  # break / cut: phrase-only -- bare uses survive, jargon phrases do not
  expect_true(grepl("break", mask_basketball_jargon("after the FIBA break"), ignore.case = TRUE))
  expect_false(grepl("break", mask_basketball_jargon("off a fast break"), ignore.case = TRUE))
  expect_true(grepl("cut", mask_basketball_jargon("saw her time cut"), ignore.case = TRUE))
  # miss: left scored entirely
  expect_true(grepl("miss", mask_basketball_jargon("she will miss the season"),
                    ignore.case = TRUE))
})

test_that("`free` is masked as roster jargon but survives in ordinary English", {
  # Free-agency vocabulary is masked, including the restricted/unrestricted
  # qualifiers, which the longest-first phrase pass consumes with the phrase.
  for (p in c("she is a free agent", "two cheap free agents", "during free agency",
              "an unrestricted free agent", "is a restricted free agent",
              "the free agency period", "a free-agent splash")) {
    masked <- mask_basketball_jargon(p)
    expect_false(grepl("free", masked, ignore.case = TRUE),
                 info = paste("`free` survived in:", p))
  }
  expect_false(grepl("unrestricted", mask_basketball_jargon("an unrestricted free agent"),
                     ignore.case = TRUE))
  # Ordinary English uses are left scored (phrase-only, like `break` and `cut`)
  expect_true(grepl("free", mask_basketball_jargon("moves to free up space"),
                    ignore.case = TRUE))
  expect_true(grepl("free", mask_basketball_jargon("they are free to negotiate"),
                    ignore.case = TRUE))
})

test_that("mask_basketball_jargon is fail-safe and never raises", {
  expect_null(mask_basketball_jargon(NULL))
  expect_identical(mask_basketball_jargon(character(0)), character(0))
  expect_identical(mask_basketball_jargon(""), "")
  # A broken term list degrades to unmasked text rather than aborting the pulse
  env <- environment(mask_basketball_jargon)
  saved <- get("SP_JARGON_SINGLES", envir = env)
  on.exit(assign("SP_JARGON_SINGLES", saved, envir = env), add = TRUE)
  assign("SP_JARGON_SINGLES", c("((("), envir = env)
  # suppressWarnings: the bad pattern also emits a PCRE compile warning, which is
  # deliberately left visible in production and only muted for this assertion.
  expect_identical(suppressWarnings(mask_basketball_jargon("a defensive stand")),
                   "a defensive stand")
})

test_that("A failure inside jargon masking does not crash the pulse", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  items <- list(
    mk_item("fs_1", "espn_wnba_beat",
            "Storm re-sign their veteran guard - a strong and welcome defensive addition."),
    mk_item("fs_2", "winsidr",
            "Liberty add offensive depth - the front office is pleased with the steals numbers.")
  )
  env <- environment(mask_basketball_jargon)
  saved <- get("SP_JARGON_SINGLES", envir = env)
  on.exit(assign("SP_JARGON_SINGLES", saved, envir = env), add = TRUE)
  assign("SP_JARGON_SINGLES", c("((("), envir = env)

  res <- suppressWarnings(compute_media_sentiment_pulse(items, scrape = FALSE))
  expect_true(res$available)
  expect_equal(res$articleCount, 2L)
  expect_true(is.numeric(res$meanSentiment))
  expect_true(res$jargonMasked)
})

test_that("Jargon masking removes the stat-sheet contribution to the score", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  txt <- "She had three steals, two blocks, and a defensive foul in a strong offensive stretch."
  unmasked <- score_text_sentiment(txt)
  masked <- score_text_sentiment(mask_basketball_jargon(txt))
  expect_false(is.null(unmasked))
  expect_lt(unmasked$raw, 0)   # scored negative purely on box-score vocabulary
  if (!is.null(masked)) expect_gt(masked$raw, unmasked$raw)
})

test_that("Masking removes the franchise-name contribution to the score", {
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
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
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  # NOTE (issue #171): `words` is the POS-FILTERED token count -- the same
  # denominator the normalized score uses -- so these fixtures carry well over
  # 40 surface words to clear a 40-word floor once function words are dropped.
  long_text <- paste(
    "Fever front office review -",
    "Indiana spent the week completing a steady and constructive set of roster moves that",
    "the staff described as a good outcome for the group, with a calm and favourable",
    "response from players, a positive tone around the facility, and a solid plan for the",
    "coming months that most observers called a reasonable and welcome direction overall.",
    "Veteran leaders praised the clear communication, the honest feedback, the thoughtful",
    "scheduling, and the genuine respect shown throughout a productive and encouraging",
    "stretch that strengthened morale, improved conditioning, and delivered real progress."
  )
  items <- list(
    # Short, extreme per-word score: exactly the shape that won the live run
    mk_item("short_1", "her_hoop_stats", "Aces wonderful triumphant brilliant"),
    mk_item("long_1", "espn_wnba_beat", long_text),
    mk_item("long_2", "winsidr", paste("Mystics collapse review -",
            paste(rep("a bad and disappointing week for the tired roster and the frustrated staff overall",
                      10),
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
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
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
    teamNamesMasked = TRUE, jargonMasked = TRUE,
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
  skip_if_not_installed("udpipe")
  skip_if_not_installed("sentimentr")
  skip_if(is.null(.sp_udpipe_model()), "pinned udpipe model not present")
  pulse <- list(
    available = TRUE, reason = NULL, articleCount = 46L, beatItemsSeen = 70L,
    offTopicExcluded = 24L, meanSentiment = 0.0217, scrapedCount = 25L,
    fallbackCount = 21L,
    mostPositive = list(headline = "A", score = 0.05, rawScore = 2, words = 120L,
                        sourceId = "winsidr", url = NA_character_, bodyScraped = TRUE),
    mostNegative = list(headline = "B", score = -0.03, rawScore = -1.5, words = 90L,
                        sourceId = "espn_wnba_beat", url = NA_character_, bodyScraped = TRUE),
    extremesMinWords = 40L, extremesFloorApplied = TRUE, extremesEligibleCount = 33L,
    teamNamesMasked = TRUE, jargonMasked = TRUE,
    wordBreakdown = list(available = TRUE, positive = list(), negative = list())
  )
  blk <- render_block_media_sentiment(pulse)
  expect_true(grepl("24 off-topic items excluded of 70 ingested", blk, fixed = TRUE))
  expect_true(grepl("team names and basketball jargon masked", blk, fixed = TRUE))
  expect_true(grepl("at least 40 words", blk, fixed = TRUE))
})
