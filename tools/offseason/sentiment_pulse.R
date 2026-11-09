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
.sp_min_extreme_words <- function() {
  if (exists("OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS")) OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS else 40L
}

# ------------------------------------------------------------------------------
# WNBA vocabulary (derived from config.R's WNBA_TEAMS -- never a local copy)
# ------------------------------------------------------------------------------

#' Lowercase team-name vocabulary: full names, city phrases, and nicknames
#'
#' Derived from WNBA_TEAMS so an expansion franchise needs no edit here. Returns
#' the three forms separately because they are used differently: relevance
#' testing accepts any of them, masking replaces longest-first.
#'
#' @return list(full =, city =, nickname =, all =) character vectors, lowercase
wnba_team_vocabulary <- function() {
  if (!exists("WNBA_TEAMS")) {
    return(list(full = character(0), city = character(0),
                nickname = character(0), all = character(0)))
  }
  full <- tolower(unname(WNBA_TEAMS))
  parts <- strsplit(full, " ", fixed = TRUE)
  nickname <- vapply(parts, function(p) p[length(p)], character(1))
  city <- vapply(parts, function(p) paste(p[-length(p)], collapse = " "), character(1))
  city <- city[nzchar(city)]
  all_terms <- unique(c(full, city, nickname))
  # Longest first so "golden state valkyries" is consumed before "golden state".
  all_terms <- all_terms[order(nchar(all_terms), decreasing = TRUE)]
  list(full = full, city = city, nickname = nickname, all = all_terms)
}

# Perl lookarounds, not \\b: they do not consume the surrounding character, so
# adjacent team references ("Liberty Sky") both mask in a single pass.
.sp_term_pattern <- function(term) {
  paste0("(?<![[:alpha:]])", term, "(?![[:alpha:]])")
}

#' Replace WNBA team names, cities and nicknames with a neutral placeholder
#'
#' Team names are proper nouns that general-English polarity lexicons score as
#' ordinary words: on the 2026-11-07 live run "liberty" (40 occurrences) and
#' "golden" (19) were the largest positive terms in the bing breakdown, and
#' masking moved the weekly syuzhet mean from +0.0265 to +0.0217 (-18%). Both
#' the score and the word breakdown therefore read masked text.
#'
#' Known tradeoff: nicknames are common nouns, so a non-team use ("a fire sale")
#' is masked too. In beat coverage of this league those tokens overwhelmingly
#' denote the franchise, and leaving them scored is the larger error.
#'
#' @param txt character vector
#' @return character vector with team vocabulary replaced by a single space
mask_team_names <- function(txt) {
  if (is.null(txt) || length(txt) == 0) return(txt)
  vocab <- wnba_team_vocabulary()
  if (length(vocab$all) == 0) return(txt)
  out <- txt
  for (term in vocab$all) {
    out <- gsub(.sp_term_pattern(term), " ", out, perl = TRUE, ignore.case = TRUE)
  }
  gsub("[[:space:]]{2,}", " ", out)
}

# ------------------------------------------------------------------------------
# Basketball stat-sheet jargon (Issue #170)
#
# Genuinely new vocabulary with no upstream source, used by exactly one tool, and
# whose longest-first ordering is an implementation detail of the masker below --
# so it lives here rather than in config.R or a tracked data file (issue #170
# design decision 3). CLAUDE.md's "never hardcode a parallel team list" rule
# binds team vocabulary only; that still derives from WNBA_TEAMS via
# wnba_team_vocabulary() above.
# ------------------------------------------------------------------------------

#' Multi-word basketball phrases, masked before the single-token pass
#'
#' Ordered longest-first at use time so "offensive rebound" is consumed before
#' "offensive"/"rebound" and "point guard" before "guard".
SP_JARGON_PHRASES <- c(
  "effective field goal", "true shooting percentage", "full-court press",
  "offensive rebound", "offensive rebounds", "offensive rebounding",
  "defensive rebound", "defensive rebounds", "defensive rebounding",
  "offensive rating", "defensive rating", "offensive efficiency",
  "defensive efficiency", "assisted shot rate", "shot creation",
  "shot selection", "shot profile", "shot attempt", "shot attempts",
  "shot clock", "jump shot", "jump shots", "free throw", "free throws",
  "free-throw", "fast break", "fast breaks", "field goal", "field goals",
  "three-point", "three-pointer", "three-pointers", "point guard",
  "shooting guard", "combo guard", "wing guard", "personal foul",
  "personal fouls", "technical foul", "technical fouls", "flagrant foul",
  "double-double", "triple-double", "all-star break", "pick and roll",
  "double team", "backdoor cut", "turnover rate", "usage rate",
  "steals per game", "blocks per game", "points per game"
)

#' Unambiguous single-token stat-sheet vocabulary, masked bare
#'
#' Every term here denotes a box-score concept in beat prose with no realistic
#' non-basketball reading, so a phrase-only pass would leave it scoring (issue
#' #170 design decision 4: `defensive`, `steals` and `offensive` appear bare in
#' the corpus, which is exactly why the published chips showed them).
SP_JARGON_SINGLES <- c(
  "offensive", "offense", "defensive", "defense", "defend", "defending",
  "steal", "steals", "stealing",
  "block", "blocks", "blocked", "blocking",
  "foul", "fouls", "fouled", "fouling",
  "rebound", "rebounds", "rebounding",
  "assist", "assists", "assisted",
  "turnover", "turnovers",
  "layup", "layups", "dunk", "dunks", "jumper", "jumpers",
  "guard", "guards", "shot", "shots"
)

#' Replace basketball stat-sheet jargon with a neutral placeholder
#'
#' General-English polarity lexicons score box-score vocabulary as emotion:
#' syuzhet and bing both read `defensive`/`offensive` as negative affect and
#' `steal`/`steals` as theft, so a routine scouting paragraph reads as hostile.
#' On the 2026-11-09 live run (47 WNBA-relevant beat items, 25 with scraped
#' bodies) the unmasked corpus carried `defense` 53x, `guard` 41x, `defensive`
#' 39x, `offense` 37x, `rebounds` 35x, `steals` 22x, `shot` 22x, `shots` 19x,
#' `offensive` 18x and `assists` 24x -- and `defensive`, `steals` and
#' `offensive` were three of the published card's top negative words.
#'
#' Measured effect, scoring that one captured live corpus twice -- once through
#' mask_team_names() alone, once through mask_team_names() + this masker:
#' masking jargon moved the weekly syuzhet mean from +0.0273 to +0.0282 (+3.4%),
#' and cleared `defensive` (39), `steals` (22) and `offensive` (18) out of the
#' bing negative chips entirely.
#'
#' Mechanics: phrases first with the longest match winning, then a single-token
#' pass; case-insensitive; each match becomes a single space and whitespace runs
#' collapse. Patterns come from .sp_term_pattern()'s Perl lookarounds rather than
#' \\b so adjacent jargon terms ("offensive rebound steal") all mask in one pass.
#'
#' Known tradeoff (shared with mask_team_names()): masking removes tokens from
#' .sp_word_count()'s denominator as well as the numerator, so every surviving
#' token weighs more in the per-article normalized mean. That is accepted rather
#' than engineered around -- the alternative, neutralizing in place, would
#' require forking the lexicon, and mask_team_names() already took this
#' tradeoff. It is also why the measured shift above is a small *rise* rather
#' than a drop: the removed vocabulary was net-negative, and a smaller
#' denominator amplifies the (net-positive) tokens that survive.
#'
#' The five ambiguous singles, decided against the 2026-11-09 corpus above:
#'   - `guard` (41 occurrences): MASKED BARE. All 41 uses are basketball --
#'     positional ("point guard", "combo guard", "a guard out of Kentucky") or
#'     verbal ("able to guard without fouling"); the only idiomatic use, "old
#'     guard", is a single instance. `guard` is in syuzhet but absent from bing,
#'     so it moved the headline mean while never appearing in the chips.
#'   - `shot` (22) / `shots` (19): MASKED BARE. 18 of 22 `shot` uses are
#'     shooting ("she shot 40%", "shot profile", "individual shot creation")
#'     against 4 of the "a shot at the title" kind. Also syuzhet-only, not bing.
#'   - `break` (18): PHRASE-ONLY. The dominant use is the calendar, not the
#'     stat sheet -- 15 of 18 are "All-Star break", "the FIBA/World Cup break",
#'     "she took the break to unplug". Only "fast break" is jargon, so `break`
#'     is masked just inside the phrases above.
#'   - `cut` (6): PHRASE-ONLY. 5 of 6 are roster/minutes cuts ("getting cut
#'     from the W", "saw her time cut"), which are real negative news a reader
#'     should see scored; only "they cut down passing lanes" is jargon.
#'   - `miss` (1): LEFT SCORED, not masked at all. Its single occurrence ("saw
#'     her miss the whole of") is an injury absence, genuinely negative, and one
#'     token cannot justify suppressing a word with heavy non-basketball use.
#'
#' Discourse filler (`like`, `right`) is deliberately out of scope here and
#' tracked separately as issue #171.
#'
#' Fail-safe: any error inside the substitution returns the input unchanged, so
#' a bad pattern degrades to unmasked scoring rather than aborting the pulse.
#'
#' @param txt character vector
#' @return character vector with basketball jargon replaced by a single space
mask_basketball_jargon <- function(txt) {
  if (is.null(txt) || length(txt) == 0) return(txt)
  tryCatch({
    out <- txt
    phrases <- SP_JARGON_PHRASES[order(nchar(SP_JARGON_PHRASES), decreasing = TRUE)]
    for (term in phrases) {
      # Allow a newline or run of spaces wherever the phrase has one, so a
      # line-wrapped "offensive\nrebound" still masks as a phrase.
      flexible <- gsub(" ", "[[:space:]]+", term, fixed = TRUE)
      out <- gsub(.sp_term_pattern(flexible), " ", out, perl = TRUE, ignore.case = TRUE)
    }
    singles <- SP_JARGON_SINGLES[order(nchar(SP_JARGON_SINGLES), decreasing = TRUE)]
    for (term in singles) {
      out <- gsub(.sp_term_pattern(term), " ", out, perl = TRUE, ignore.case = TRUE)
    }
    gsub("[[:space:]]{2,}", " ", out)
  }, error = function(e) {
    log_warn(paste("sentiment_pulse: jargon masking failed; scoring unmasked text -",
                   conditionMessage(e)),
             script = "sentiment_pulse.R")
    txt
  })
}

#' Does this item actually concern the WNBA?
#'
#' The beat outlets in DEFAULT_BEAT_SOURCES are women's-basketball and
#' women's-sports feeds, not WNBA-only wires. On the 2026-11-07 live run 24 of
#' 70 ingested items were off-topic -- WTA tennis, PWHL and ECAC hockey, NCAA
#' game recaps, FIBA World Cup -- and one of them (a Florida-UCF college recap)
#' was published as the week's most negative WNBA story. An item counts as
#' relevant when it names the league or any franchise, city or nickname.
#'
#' Accepted false negative: a WNBA-adjacent item that names neither (e.g. an
#' Unrivaled roster story, or a Hall-of-Fame class item naming only players) is
#' excluded. Excluding it is the conservative error; the count is reported so a
#' reader can see how much was filtered.
#'
#' @param item one wire item
#' @return TRUE/FALSE
item_is_wnba_relevant <- function(item) {
  txt <- tolower(paste(
    as.character(item$raw_text %||% ""),
    as.character(item$source_url %||% "")
  ))
  if (!nzchar(trimws(txt))) return(FALSE)
  if (grepl(.sp_term_pattern("wnba"), txt, perl = TRUE)) return(TRUE)
  vocab <- wnba_team_vocabulary()
  for (term in vocab$all) {
    if (grepl(.sp_term_pattern(term), txt, perl = TRUE)) return(TRUE)
  }
  FALSE
}

#' Keep only the WNBA-relevant items
filter_wnba_relevant_items <- function(items) {
  if (is.null(items) || length(items) == 0) return(list())
  Filter(item_is_wnba_relevant, items)
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
      beatItemsSeen = 0L,
      offTopicExcluded = 0L,
      extremesMinWords = as.integer(.sp_min_extreme_words()),
      extremesFloorApplied = FALSE,
      teamNamesMasked = TRUE,
      jargonMasked = TRUE,
      lexicon = "syuzhet + bing",
      method = "syuzhet"
    )
  }

  beat_items <- filter_beat_feed_items(wire_items)
  if (length(beat_items) == 0) {
    return(unavailable("no beat_feeds wire items were ingested this run"))
  }

  items <- filter_wnba_relevant_items(beat_items)
  off_topic <- length(beat_items) - length(items)
  if (off_topic > 0) {
    log_info(sprintf("sentiment_pulse: Excluded %d of %d beat items as off-topic (no WNBA or franchise mention).",
                     off_topic, length(beat_items)),
             script = "sentiment_pulse.R")
  }
  if (length(items) == 0) {
    return(unavailable(sprintf(
      "none of the %d beat_feeds items this run mentioned the WNBA or any franchise",
      length(beat_items))))
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

    # Score the masked text, not the raw text: franchise proper nouns are
    # lexicon-scored otherwise (see mask_team_names()). The same masked string
    # feeds the bing breakdown, so the memo's words and its number agree.
    # Basketball stat-sheet vocabulary is masked in the same breath and on the
    # same string (issue #170), so the mean and the bing chips stay in agreement.
    text_used <- mask_basketball_jargon(mask_team_names(text_used))
    if (!nzchar(trimws(text_used))) next

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

  # Extremes come only from items long enough for a per-word mean to be stable
  # (OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS). Every item still counts toward the
  # mean. If nothing clears the floor, fall back to the full set and say so
  # rather than reporting no extreme at all.
  words_vec <- vapply(rows, function(r) as.integer(r$words), integer(1))
  floor_words <- as.integer(.sp_min_extreme_words())
  eligible <- which(words_vec >= floor_words)
  floor_applied <- length(eligible) > 0
  pool <- if (floor_applied) eligible else seq_along(rows)
  if (!floor_applied) {
    log_warn(sprintf("sentiment_pulse: no item reached the %d-word extreme floor; extremes drawn from all %d scored items.",
                     floor_words, length(rows)),
             script = "sentiment_pulse.R")
  }
  idx_pos <- pool[which.max(norm[pool])]
  idx_neg <- pool[which.min(norm[pool])]

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

  log_info(sprintf("sentiment_pulse: Scored %d WNBA-relevant beat articles of %d ingested (%d off-topic excluded; %d scraped, %d RSS fallback); mean normalized sentiment %.4f.",
                   length(rows), length(beat_items), off_topic, scraped, fallback, mean_norm),
           script = "sentiment_pulse.R")

  list(
    available = TRUE,
    reason = NULL,
    articleCount = length(rows),
    beatItemsSeen = length(beat_items),
    offTopicExcluded = as.integer(off_topic),
    meanSentiment = round(mean_norm, 4),
    scrapedCount = scraped,
    fallbackCount = fallback,
    mostPositive = mk(rows[[idx_pos]]),
    mostNegative = mk(rows[[idx_neg]]),
    extremesMinWords = floor_words,
    extremesFloorApplied = floor_applied,
    extremesEligibleCount = length(eligible),
    teamNamesMasked = TRUE,
    jargonMasked = TRUE,
    wordBreakdown = breakdown,
    lexicon = "syuzhet + bing",
    method = "syuzhet"
  )
}
