# ==============================================================================
# sentiment_pulse.R
# WNBA Offseason Dynamics Monitor — Media Sentiment Pulse (Issue #156)
#
# Scores the beat-feed wire items the monitor ALREADY ingests each week
# (source_family == "beat_feeds", produced by tools/offseason/ingest_sources.R's
# poll_beat_feeds()) for narrative sentiment, and returns a structured summary
# that tools/offseason/render_memo.R renders as an additional memo block.
#
# Design constraints (see CLAUDE.md + Issue #156 blocking comment):
#   - NO second RSS fetch path and no tidyRSS. The ingested items are the data of
#     record; article-body scraping via rvest is a best-effort ENRICHMENT on each
#     item's source_url, with the RSS `title - description` (raw_text) as fallback.
#   - Fail-soft end to end. A dead outlet, changed HTML markup, a network
#     timeout, or a missing sentiment package must never abort the weekly job;
#     every one of those degrades to a clearly-labelled result.
#   - NEVER fabricate a sentiment number. If scoring cannot run, the result is
#     available = FALSE with a reason string and NULL scores (issues #129,
#     #133-#135, epic #138 treat placeholder values as a publishing defect).
#
# Method: syuzhet::get_sentiment(method = "syuzhet") summed polarity per
# article, normalized by the article's word count, plus a tidytext `bing`
# lexicon word-frequency breakdown. See
# docs/internal/offseason_media_sentiment_pulse.md.
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

if (file.exists("config.R")) source("config.R")
# NOTE: do NOT guard this on `!exists("%||%")`. Base R >= 4.4 ships its own weaker
# is.null-only `%||%`, so that check always passes and silently leaves the wrong
# operator active (CLAUDE.md / issue #153). Guard on log_info() instead.
if (!exists("log_info", mode = "function") && file.exists("logging_utils.R")) {
  source("logging_utils.R")
}

# Defensive local fallbacks so this file stays usable if sourced stand-alone from
# a context where logging_utils.R is unavailable (fail-safe design).
if (!exists("log_info", mode = "function")) log_info <- function(...) invisible(NULL)
if (!exists("log_warn", mode = "function")) log_warn <- function(...) invisible(NULL)

# Constants live in config.R per CLAUDE.md; these accessors only fall back when
# this file is sourced without config.R present (never in the real DAG).
.sp_max_articles <- function() {
  if (exists("OFFSEASON_SENTIMENT_MAX_ARTICLES")) OFFSEASON_SENTIMENT_MAX_ARTICLES else 25L
}
.sp_timeout_sec <- function() {
  if (exists("OFFSEASON_SENTIMENT_SCRAPE_TIMEOUT_SEC")) OFFSEASON_SENTIMENT_SCRAPE_TIMEOUT_SEC else 8L
}
.sp_top_words <- function() {
  if (exists("OFFSEASON_SENTIMENT_TOP_WORDS")) OFFSEASON_SENTIMENT_TOP_WORDS else 8L
}
.sp_min_body_chars <- function() {
  if (exists("OFFSEASON_SENTIMENT_MIN_BODY_CHARS")) OFFSEASON_SENTIMENT_MIN_BODY_CHARS else 400L
}

# ------------------------------------------------------------------------------
# Item helpers
# ------------------------------------------------------------------------------

#' Extract the beat-feed items from a monitor wire-item collection
#'
#' @param wire_items list of wire items (docs/internal/offseason_wire_items_contract.md)
#' @return list of items whose source_family is exactly "beat_feeds"
filter_beat_feed_items <- function(wire_items) {
  if (is.null(wire_items) || length(wire_items) == 0) return(list())
  Filter(function(it) {
    is.list(it) && identical(as.character(it$source_family %||% ""), "beat_feeds")
  }, wire_items)
}

#' Headline for an item: the RSS title, i.e. raw_text up to the first " - "
sentiment_item_headline <- function(item) {
  raw <- trimws(as.character(item$raw_text %||% ""))
  if (!nzchar(raw)) return("(untitled beat item)")
  parts <- strsplit(raw, " - ", fixed = TRUE)[[1]]
  head_txt <- trimws(parts[1])
  if (!nzchar(head_txt)) head_txt <- raw
  if (nchar(head_txt) > 180L) head_txt <- paste0(substr(head_txt, 1, 177L), "...")
  head_txt
}

# ------------------------------------------------------------------------------
# Article body enrichment (best-effort, individually fail-soft)
# ------------------------------------------------------------------------------

#' Scrape the visible article body for one URL
#'
#' Every failure mode (packages absent, bad URL, DNS failure, timeout, non-200,
#' changed markup yielding no paragraph text) returns NULL so the caller falls
#' back to the item's RSS raw_text. Never raises.
#'
#' @return character(1) body text, or NULL
scrape_article_body <- function(url, timeout_sec = .sp_timeout_sec()) {
  if (is.null(url) || !nzchar(as.character(url)[1])) return(NULL)
  if (!requireNamespace("rvest", quietly = TRUE) ||
      !requireNamespace("httr", quietly = TRUE)) {
    return(NULL)
  }

  tryCatch({
    resp <- httr::GET(
      as.character(url)[1],
      httr::timeout(as.numeric(timeout_sec)),
      httr::user_agent("WNBA-Analytics-OffseasonMonitor/1.0 (+issue156 sentiment pulse)")
    )
    if (httr::status_code(resp) < 200 || httr::status_code(resp) >= 400) return(NULL)

    html_txt <- httr::content(resp, as = "text", encoding = "UTF-8")
    if (is.null(html_txt) || !nzchar(html_txt)) return(NULL)

    doc <- rvest::read_html(html_txt)
    paras <- rvest::html_text2(rvest::html_elements(doc, "article p, .article-body p, p"))
    paras <- trimws(paras[!is.na(paras)])
    paras <- paras[nchar(paras) > 40L]
    if (length(paras) == 0) return(NULL)

    body <- paste(unique(paras), collapse = " ")
    if (nchar(body) < .sp_min_body_chars()) return(NULL)
    body
  }, error = function(e) {
    NULL
  }, warning = function(w) {
    NULL
  })
}

# ------------------------------------------------------------------------------
# Scoring
# ------------------------------------------------------------------------------

#' Word count used for normalization
.sp_word_count <- function(txt) {
  toks <- unlist(strsplit(trimws(txt), "[[:space:]]+"))
  length(toks[nzchar(toks)])
}

#' Normalized syuzhet polarity for one text blob
#'
#' @return list(raw =, words =, normalized =) or NULL if syuzhet is unavailable
score_text_sentiment <- function(txt) {
  if (!requireNamespace("syuzhet", quietly = TRUE)) return(NULL)
  if (is.null(txt) || !nzchar(trimws(txt))) return(NULL)
  tryCatch({
    sentences <- syuzhet::get_sentences(txt)
    vals <- syuzhet::get_sentiment(sentences, method = "syuzhet")
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0) return(NULL)
    raw <- sum(vals)
    n_words <- .sp_word_count(txt)
    if (n_words == 0) return(NULL)
    list(raw = raw, words = n_words, normalized = raw / n_words)
  }, error = function(e) NULL)
}

#' bing-lexicon positive/negative word frequency breakdown
#'
#' @return list(available =, reason =, positive = list of {word, n}, negative = ...)
summarize_bing_words <- function(texts, top_n = .sp_top_words()) {
  if (!requireNamespace("tidytext", quietly = TRUE)) {
    return(list(available = FALSE, reason = "package 'tidytext' is not installed",
                positive = list(), negative = list()))
  }
  texts <- texts[!is.na(texts) & nzchar(texts)]
  if (length(texts) == 0) {
    return(list(available = FALSE, reason = "no text to tokenize",
                positive = list(), negative = list()))
  }

  tryCatch({
    bing <- as.data.frame(tidytext::get_sentiments("bing"))
    words <- tolower(unlist(strsplit(paste(texts, collapse = " "), "[^A-Za-z']+")))
    words <- words[nzchar(words)]
    if (length(words) == 0) {
      return(list(available = FALSE, reason = "no tokens",
                  positive = list(), negative = list()))
    }
    joined <- merge(data.frame(word = words, stringsAsFactors = FALSE), bing, by = "word")
    if (nrow(joined) == 0) {
      return(list(available = TRUE, reason = NULL, positive = list(),
                  negative = list(), matchedWords = 0L))
    }
    pick <- function(pol) {
      sub <- joined[joined$sentiment == pol, , drop = FALSE]
      if (nrow(sub) == 0) return(list())
      tb <- sort(table(sub$word), decreasing = TRUE)
      tb <- tb[seq_len(min(length(tb), as.integer(top_n)))]
      lapply(seq_along(tb), function(i) list(word = names(tb)[i], n = as.integer(tb[[i]])))
    }
    list(available = TRUE, reason = NULL,
         positive = pick("positive"), negative = pick("negative"),
         matchedWords = nrow(joined))
  }, error = function(e) {
    list(available = FALSE,
         reason = paste("bing breakdown failed:", conditionMessage(e)),
         positive = list(), negative = list())
  })
}

# ------------------------------------------------------------------------------
# Public entry point
# ------------------------------------------------------------------------------

#' Compute the weekly Media Sentiment Pulse from already-ingested wire items
#'
#' @param wire_items The monitor's wire-item list (run_ingestion()$items).
#' @param max_articles Cap on how many beat items get a live body scrape.
#' @param timeout_sec Per-request scrape timeout, seconds.
#' @param scrape Logical; FALSE scores RSS raw_text only (no network at all).
#' @param top_n_words Size of the bing word breakdown per polarity.
#' @return list with: available (logical), reason (chr or NULL), articleCount (int),
#'   meanSentiment (num or NULL), scrapedCount, fallbackCount, mostPositive /
#'   mostNegative (list(headline, score, sourceId, url) or NULL), wordBreakdown.
compute_media_sentiment_pulse <- function(wire_items,
                                          max_articles = .sp_max_articles(),
                                          timeout_sec = .sp_timeout_sec(),
                                          scrape = TRUE,
                                          top_n_words = .sp_top_words()) {

  unavailable <- function(reason) {
    log_warn(paste("sentiment_pulse: Media Sentiment Pulse unavailable -", reason),
             script = "sentiment_pulse.R")
    list(
      available = FALSE,
      reason = reason,
      articleCount = 0L,
      meanSentiment = NULL,
      scrapedCount = 0L,
      fallbackCount = 0L,
      mostPositive = NULL,
      mostNegative = NULL,
      wordBreakdown = list(available = FALSE, positive = list(), negative = list()),
      lexicon = "syuzhet + bing",
      method = "syuzhet"
    )
  }

  items <- filter_beat_feed_items(wire_items)
  if (length(items) == 0) {
    return(unavailable("no beat_feeds wire items were ingested this run"))
  }

  if (!requireNamespace("syuzhet", quietly = TRUE)) {
    return(unavailable("package 'syuzhet' is not installed; no sentiment score can be computed"))
  }

  n_cap <- max(0L, as.integer(max_articles))
  scraped <- 0L
  fallback <- 0L
  rows <- list()

  for (i in seq_along(items)) {
    item <- items[[i]]
    rss_text <- trimws(as.character(item$raw_text %||% ""))
    body <- NULL

    if (isTRUE(scrape) && i <= n_cap) {
      body <- scrape_article_body(item$source_url, timeout_sec = timeout_sec)
      if (is.null(body)) {
        log_warn(sprintf("sentiment_pulse: body scrape failed/empty for %s (%s); falling back to RSS text.",
                         as.character(item$item_id %||% "?"),
                         as.character(item$source_url %||% "no-url")),
                 script = "sentiment_pulse.R")
      }
    }

    text_used <- if (!is.null(body)) body else rss_text
    if (!nzchar(text_used)) next
    if (!is.null(body)) scraped <- scraped + 1L else fallback <- fallback + 1L

    sc <- score_text_sentiment(text_used)
    if (is.null(sc)) {
      log_warn(sprintf("sentiment_pulse: scoring returned no usable value for %s; item skipped.",
                       as.character(item$item_id %||% "?")),
               script = "sentiment_pulse.R")
      next
    }

    rows[[length(rows) + 1L]] <- list(
      item_id = as.character(item$item_id %||% ""),
      source_id = as.character(item$source_id %||% ""),
      url = if (is.null(item$source_url)) NA_character_ else as.character(item$source_url)[1],
      headline = sentiment_item_headline(item),
      text = text_used,
      scraped = !is.null(body),
      raw = sc$raw,
      words = sc$words,
      normalized = sc$normalized
    )
  }

  if (length(rows) == 0) {
    return(unavailable("no beat-feed item yielded a scorable text body"))
  }

  norm <- vapply(rows, function(r) r$normalized, numeric(1))
  mean_norm <- mean(norm)
  idx_pos <- which.max(norm)
  idx_neg <- which.min(norm)

  mk <- function(r) list(
    headline = r$headline,
    score = round(r$normalized, 4),
    rawScore = round(r$raw, 3),
    words = as.integer(r$words),
    sourceId = r$source_id,
    url = r$url,
    bodyScraped = isTRUE(r$scraped)
  )

  breakdown <- summarize_bing_words(vapply(rows, function(r) r$text, character(1)),
                                    top_n = top_n_words)

  log_info(sprintf("sentiment_pulse: Scored %d beat-feed articles (%d scraped, %d RSS fallback); mean normalized sentiment %.4f.",
                   length(rows), scraped, fallback, mean_norm),
           script = "sentiment_pulse.R")

  list(
    available = TRUE,
    reason = NULL,
    articleCount = length(rows),
    beatItemsSeen = length(items),
    meanSentiment = round(mean_norm, 4),
    scrapedCount = scraped,
    fallbackCount = fallback,
    mostPositive = mk(rows[[idx_pos]]),
    mostNegative = mk(rows[[idx_neg]]),
    wordBreakdown = breakdown,
    lexicon = "syuzhet + bing",
    method = "syuzhet"
  )
}
