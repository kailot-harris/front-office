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
# Method (issue #171, replaces the syuzhet/bing scorer): udpipe POS tagging
# feeds sentimentr. udpipe owns word sense (which tokens are eligible to carry
# polarity at all), sentimentr owns valence (negators, amplifiers, de-amplifiers)
# and therefore the mean. Summed valence-adjusted polarity per article,
# normalized by the POS-filtered word count, plus a `jockers_rinker`
# word-frequency breakdown drawn from the same filtered token stream so the
# memo's words and its number always agree. The udpipe model is a tracked,
# version-pinned artifact under data/udpipe/ -- there is no download at runtime
# and no fallback to syuzhet/bing. See
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
  "unrestricted free agent", "unrestricted free agents",
  "restricted free agent", "restricted free agents",
  "reserved free agent", "reserved free agents",
  "free agent market", "free agency period",
  "free agent", "free agents", "free agency",
  "free-agent", "free-agents", "free-agency",
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
#' masking jargon moved the weekly syuzhet mean from +0.0273 to +0.0280 (+2.7%),
#' cleared `defensive` (39), `steals` (22) and `offensive` (18) out of the bing
#' negative chips entirely, and dropped `free` from 36 occurrences (the #5
#' positive chip) to 4, off the list.
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
#' `free` (36 bare occurrences, +0.50 in syuzhet and positive in bing, the #5
#' positive chip before this change) is PHRASE-ONLY, by the same standard as
#' `break` and `cut`. 31 of the 36 are roster vocabulary -- "free agent" /
#' "free agents" (20, of which 4 unrestricted and 2 restricted) and "free
#' agency" (11) -- plus one "free throws"; the remaining 4 are ordinary English
#' and are left scored ("moves to free up space", "UFAs are free to discuss
#' terms", "player are free to negotiate", one bare possessive). Masking the
#' phrases alone therefore takes `free` off the chips without suppressing a
#' word whose plain-English sense really does appear in beat prose.
#'
#' Discourse filler (`like`, `right`) was deliberately out of scope here and was
#' handled by issue #171, which replaced the scorer: udpipe POS tagging now
#' separates `like`-as-preposition from `like`-as-verb structurally, so no
#' filler term was ever added to the lists above (see SP_POS_FUNCTION_CLASSES).
#'
#' RETAINED UNDER sentimentr/jockers_rinker -- measured, not assumed (issue #171
#' design decision 8). POS tagging cannot fix this masker's problem, because
#' box-score vocabulary is a lexicon-VALUE error, not a word-sense one: the
#' tokens are correctly tagged NOUN/ADJ and still carry the wrong polarity.
#' `jockers_rinker` in fact mis-scores this vocabulary more severely than
#' syuzhet/bing did -- `steal` -0.75, `stealing` -0.75, `foul` -0.75, `blocks`
#' -0.60, `defensive` -0.50, `offensive` -0.50, `offense` -0.50, `block`/
#' `blocked` -0.40, `shot` -0.40, `guard` -0.25 -- while scoring `defense`,
#' `defend` and `defending` at +0.25. The same concept therefore lands on
#' opposite chip lists by inflection, which is decisive on its own: on the
#' team-masked-but-jargon-unmasked run below, `defense` (54) was the #3 POSITIVE
#' chip while `defensive` (40) was the #3 NEGATIVE chip in the same table.
#'
#' Measured on the 2026-11-09 captured corpus (46 WNBA-relevant items, 25
#' scraped bodies), scored three ways under the new scorer:
#'   unmasked            +0.0644
#'   + mask_team_names() +0.0571  (-11.4%)   <- #156 still earns its place
#'   + this masker       +0.0590  (+3.4%)    <- #170 still earns its place
#' Neither masker is redundant, so both are retained. The jargon pass also
#' clears `guard` (41), `defensive` (40), `offense` (36), `shot` (22) and
#' `defense` (54) out of the published chips; the team pass clears `dream`
#' (133), `liberty` (120) and `golden` (111) from the positives and `fever`
#' (11) from the negatives.
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

# ------------------------------------------------------------------------------
# The udpipe model: a tracked, version-pinned artifact (Issue #171)
#
# renv pins packages, not model files, so the English model needs a deliberate
# home or the weekly job breaks in a fresh clone and in CI. It is committed under
# data/udpipe/ for the same reasons .gitignore:88 keeps cache/ and data/ tracked
# on purpose. There is deliberately NO udpipe_download_model() call at runtime:
# a download-on-first-use path would make the published method depend on whether
# a fetch happened to succeed, which is the audit's Class C "substitutes
# silently" defect (issue #171 design decision 4).
#
# A model version bump is a published-value change and must be treated with the
# same care as changing a config.R seed (docs/REPRODUCIBILITY.md).
# ------------------------------------------------------------------------------

#' Pinned udpipe model version. Changing this changes published numbers.
SP_UDPIPE_MODEL_VERSION <- "english-ewt-ud-2.5-191206"

#' Absolute path to the pinned, tracked udpipe model artifact
.sp_udpipe_model_path <- function() {
  file.path("data", "udpipe", paste0(SP_UDPIPE_MODEL_VERSION, ".udpipe"))
}

# Loading the model costs ~0.5s, so it is memoized per session. The cache is
# keyed on the resolved path so a test that points at a missing file is not
# served a previously-loaded model.
.sp_model_cache <- new.env(parent = emptyenv())

#' Load the pinned udpipe model, or NULL if it cannot be loaded
#'
#' Never raises and never downloads. A missing or unreadable model means the
#' pulse is unavailable for the week (issue #171 design decision 5) -- it does
#' NOT mean a silent fall back to the old syuzhet scorer.
#'
#' @return a udpipe model object, or NULL
.sp_udpipe_model <- function(path = .sp_udpipe_model_path()) {
  if (!requireNamespace("udpipe", quietly = TRUE)) return(NULL)
  key <- paste0("m:", path)
  if (!is.null(.sp_model_cache[[key]])) return(.sp_model_cache[[key]])
  if (!file.exists(path)) return(NULL)
  mod <- tryCatch(udpipe::udpipe_load_model(path), error = function(e) NULL)
  if (is.null(mod)) return(NULL)
  .sp_model_cache[[key]] <- mod
  mod
}

#' Is the full scorer (package + pinned model) usable right now?
#'
#' @return NULL when usable, or a reason string explaining why not
.sp_scorer_unavailable_reason <- function() {
  if (!requireNamespace("udpipe", quietly = TRUE)) {
    return("package 'udpipe' is not installed; no sentiment score can be computed")
  }
  if (!requireNamespace("sentimentr", quietly = TRUE)) {
    return("package 'sentimentr' is not installed; no sentiment score can be computed")
  }
  path <- .sp_udpipe_model_path()
  if (!file.exists(path)) {
    return(sprintf("pinned udpipe model '%s' is missing at %s; no sentiment score can be computed",
                   SP_UDPIPE_MODEL_VERSION, path))
  }
  mod <- .sp_udpipe_model(path)
  if (is.null(mod)) {
    return(sprintf("pinned udpipe model '%s' at %s could not be loaded; no sentiment score can be computed",
                   SP_UDPIPE_MODEL_VERSION, path))
  }
  # udpipe_load_model() accepts a file that is not actually a model and only
  # fails later, per article, which would degrade to the much vaguer "no item
  # yielded a scorable body". One tiny probe annotation up front turns a
  # corrupted or truncated artifact into an accurate reason string.
  probe <- tryCatch(
    .sp_pos_filter_text("The move is good for the roster.", model = mod),
    error = function(e) NULL
  )
  if (is.null(probe) || !nzchar(probe$text %||% "")) {
    return(sprintf("pinned udpipe model '%s' at %s could not be loaded; it did not tag a probe sentence (truncated or corrupt artifact?)",
                   SP_UDPIPE_MODEL_VERSION, path))
  }
  NULL
}

# ------------------------------------------------------------------------------
# Word sense: which tokens are eligible to carry polarity (Issue #171)
#
# This is the half of the ticket udpipe owns, and it is what actually fixes the
# defect #171 was opened for. The old scorer was a bare lexicon lookup, so every
# occurrence of `like` scored +0.50 regardless of whether it meant "I like what
# I saw" (an opinion) or "played like a veteran" (a comparison). On the
# 2026-11-09 corpus that single conflation made `like` the #1 positive chip at
# 107 occurrences, ahead of `best` (77).
#
# The mechanism is a POS rule, NOT a word list. Issue #170's hand-maintained
# jargon list was the right tool for box-score vocabulary (a lexicon-VALUE
# problem); it is the wrong tool here, and #171 design decision 1 explicitly
# supersedes a third such list. The rule below enumerates grammatical classes,
# so it generalizes to words nobody has looked at yet.
# ------------------------------------------------------------------------------

#' Universal POS tags whose members never carry evaluative polarity
#'
#' Function words. A polarity lexicon that matches on surface form alone scores
#' them anyway, which is exactly how `like`-as-preposition ("played like a
#' veteran", ADP) and `like`-as-conjunction ("like I said", SCONJ) got counted
#' as opinions, and how a discourse-marker `well` ("Well, the team is young",
#' INTJ) scored +0.80. Verbal `like` is VERB and survives, so a genuine opinion
#' still scores.
#'
#' Valence shifters are exempt from this filter (see .sp_pos_filter_text): `not`
#' is PART and `no` is DET, and dropping them would destroy the negation
#' handling that is the whole point of using sentimentr.
SP_POS_FUNCTION_CLASSES <- c(
  "ADP", "SCONJ", "CCONJ", "DET", "PRON", "AUX", "PART",
  "INTJ", "PUNCT", "SYM", "NUM", "X"
)

#' Lemmas whose polarity is real in one POS and spurious in another
#'
#' The function-class rule above is the primary mechanism and needs no entries
#' here. This table covers the residue: a lemma whose evaluative sense belongs
#' to one content class while another content class is a degree/temporal
#' modifier. Each entry records a POS fact, not a sentiment judgement, which is
#' what keeps this from being the hand-maintained word list #171 ruled out.
#'
#' `right` (+0.80 in jockers_rinker -- tied for the highest positive value of
#' any word in the 2026-11-09 corpus, and the #5 positive chip at 38
#' occurrences) is evaluative only as an adjective: "she made the right call",
#' "her read was right" (ADJ). As an adverb it is a pure intensifier with no
#' opinion content -- "right now", "right there", "right from the start"
#' (ADV) -- which is every one of its high-frequency uses in beat prose.
#'
#' `well` deliberately gets NO entry: adverbial `well` ("the team is playing
#' well") really is evaluative, and its spurious discourse use is INTJ, which
#' SP_POS_FUNCTION_CLASSES already removes. Head-POS was tried as a generic
#' substitute for this table and rejected on measurement: udpipe attaches
#' "Right now the roster is unsettled" to the ADJ `unsettled`, so a head-POS
#' rule keeps the very token it was meant to drop.
SP_POS_POLAR_SENSE <- list(
  right = c("ADJ")
)

# ------------------------------------------------------------------------------
# Never + comparative polarity inversion fix (Issue #172)
#
# sentimentr applies a generic polarity flip when a negator precedes a polar
# word. That is correct for "not good" (negative) and "never good" (negative),
# but inverts negative-polarity comparative idioms built on "never" + comparative
# (e.g. "never been better", "never looked better", "never been worse"), where
# the negation asserts an emphatic maximum or nadir rather than reversing the sign.
# "She has never been better" means she is at her best (positive), but scored
# -0.8000; "She has never been worse" means she is at her worst (negative), but
# scored +0.7500; "The roster has never looked better" scored -0.8000.
#
# udpipe identifies comparative words via Degree=Cmp in feats, xpos in JJR/RBR,
# or irregular comparative lemmas/tokens (better, worse).
#
# When "never" governs a comparative in the same clause (within 1 to 4 tokens
# without intervening punctuation or coordinating conjunctions), "never" is
# replaced with "ever" in the scoring text tokens passed to sentimentr. "ever"
# is neither in lexicon::hash_sentiment_jockers_rinker nor
# lexicon::hash_valence_shifters, preserving token count and sentence structure
# while letting the comparative retain its true polarity sign.
# ------------------------------------------------------------------------------

#' Neutralize 'never' when governing a comparative to prevent polarity inversion (Issue #172)
#'
#' @param ann annotated data.frame from udpipe::udpipe_annotate()
#' @return character vector of scoring tokens with 'never' neutralized before comparatives
.sp_neutralize_never_comparatives <- function(ann) {
  lemma_lc <- tolower(ifelse(is.na(ann$lemma), ann$token, ann$lemma))
  token_lc <- tolower(ann$token)
  upos <- ifelse(is.na(ann$upos), "X", ann$upos)
  feats <- ifelse(is.na(ann$feats), "", ann$feats)
  xpos <- ifelse(is.na(ann$xpos), "", ann$xpos)

  is_comp <- grepl("Degree=Cmp", feats) |
             xpos %in% c("JJR", "RBR") |
             lemma_lc %in% c("better", "worse") |
             token_lc %in% c("better", "worse")

  # Polar word vocabulary from jockers_rinker to detect direct non-comparative targets
  pol_words <- if (requireNamespace("lexicon", quietly = TRUE)) {
    tryCatch(
      tolower(as.character(as.data.frame(lexicon::hash_sentiment_jockers_rinker)[[1]])),
      error = function(e) character(0)
    )
  } else {
    character(0)
  }

  text_tokens <- ann$token
  sent_key <- paste(ann$doc_id, ann$paragraph_id, ann$sentence_id)

  for (sk in unique(sent_key)) {
    sub_idx <- which(sent_key == sk)
    never_pos <- which(token_lc[sub_idx] == "never" | lemma_lc[sub_idx] == "never")
    if (length(never_pos) > 0) {
      for (np in never_pos) {
        actual_i <- sub_idx[np]
        if (np < length(sub_idx)) {
          ahead <- seq(np + 1, min(np + 4, length(sub_idx)))
          for (j in ahead) {
            actual_j <- sub_idx[j]
            # Clause boundary or conjunction terminates lookahead
            if (upos[actual_j] %in% c("PUNCT", "CCONJ", "SCONJ")) break
            # Comparative word found: neutralize 'never' to 'ever' for sentiment text
            if (is_comp[actual_j]) {
              text_tokens[actual_i] <- "ever"
              break
            }
            # Non-comparative polar word encountered: 'never' directly modifies that word
            if (length(pol_words) > 0 && token_lc[actual_j] %in% pol_words && !is_comp[actual_j]) {
              break
            }
          }
        }
      }
    }
  }
  text_tokens
}

#' Tag one text blob and drop the tokens that cannot carry polarity
#'
#' Neutralized tokens are dropped rather than replaced in place. That keeps the
#' POS-filtered token count as both the scoring input and the normalization
#' denominator, so this matches the tradeoff mask_team_names() and
#' mask_basketball_jargon() already took (see their roxygen): a removed token
#' leaves the denominator as well as the numerator.
#'
#' @param txt character(1)
#' @param model a loaded udpipe model
#' @return list(text =, tokens = data.frame(token, lemma, upos)) or NULL
.sp_pos_filter_text <- function(txt, model = .sp_udpipe_model()) {
  if (is.null(model)) return(NULL)
  if (is.null(txt) || !nzchar(trimws(txt))) return(NULL)
  tryCatch({
    ann <- as.data.frame(udpipe::udpipe_annotate(model, x = as.character(txt)[1],
                                                 doc_id = "a"))
    if (nrow(ann) == 0) return(NULL)
    ann <- ann[!is.na(ann$token) & nzchar(ann$token), , drop = FALSE]
    if (nrow(ann) == 0) return(NULL)

    lemma_lc <- tolower(ifelse(is.na(ann$lemma), ann$token, ann$lemma))
    token_lc <- tolower(ann$token)
    upos <- ifelse(is.na(ann$upos), "X", ann$upos)

    # Neutralize 'never' when governing a comparative (Issue #172)
    text_tokens <- .sp_neutralize_never_comparatives(ann)

    # Valence shifters survive every filter: sentimentr needs them in place to
    # flip or scale the polar word they govern.
    shifters <- .sp_valence_shifter_words()
    is_shifter <- lemma_lc %in% shifters | token_lc %in% shifters

    keep <- is_shifter | !(upos %in% SP_POS_FUNCTION_CLASSES)

    # Per-lemma POS-sense dispositions (SP_POS_POLAR_SENSE).
    sense_hit <- !is_shifter & lemma_lc %in% names(SP_POS_POLAR_SENSE)
    if (any(sense_hit)) {
      allowed <- lapply(lemma_lc[sense_hit], function(l) SP_POS_POLAR_SENSE[[l]])
      ok <- mapply(function(u, a) u %in% a, upos[sense_hit], allowed)
      keep[sense_hit] <- keep[sense_hit] & ok
    }

    kept <- ann[keep, , drop = FALSE]
    kept_text_tokens <- text_tokens[keep]
    if (nrow(kept) == 0) return(NULL)

    # Rebuild sentence-delimited text so sentimentr still sees sentence
    # boundaries (its valence window does not reach across them).
    sent_key <- paste(kept$doc_id, kept$paragraph_id, kept$sentence_id)
    sentences <- vapply(split(kept_text_tokens, factor(sent_key, levels = unique(sent_key))),
                        function(tk) paste(tk, collapse = " "), character(1))
    sentences <- trimws(sentences)
    sentences <- sentences[nzchar(sentences)]
    if (length(sentences) == 0) return(NULL)

    list(
      text = paste0(sentences, collapse = ". "),
      tokens = data.frame(
        token = tolower(kept$token),
        lemma = tolower(ifelse(is.na(kept$lemma), kept$token, kept$lemma)),
        upos = ifelse(is.na(kept$upos), "X", kept$upos),
        stringsAsFactors = FALSE
      )
    )
  }, error = function(e) NULL)
}

# ------------------------------------------------------------------------------
# Valence shifters: the half of the ticket sentimentr owns (Issue #171)
# ------------------------------------------------------------------------------

#' Negative-polarity adverbs reclassified from de-amplifier to negator
#'
#' sentimentr's `hash_valence_shifters` types these 3 (de-amplifier), which only
#' shrinks the magnitude of the word they govern: "hardly ideal" came out
#' **+0.0667** on the default table, i.e. still positive. In English these are
#' negative-polarity items -- "hardly ideal" means "not ideal", "barely adequate"
#' means "inadequate" -- so a downtoner reading gives the wrong sign, not merely
#' a smaller number. Retyping them 1 (negator) makes the contract uniform:
#' a negator governing a positive word yields a negative score.
#'
#' This is a correction to a general-English table, not a domain word list; it
#' is pinned here because it changes published numbers.
SP_NEGATOR_RETYPED <- c("hardly", "barely", "scarcely", "rarely", "seldom")

#' sentimentr's valence-shifter table with SP_NEGATOR_RETYPED applied
#'
#' Memoized: rebuilding it per article would dominate the scoring cost.
.sp_valence_shifter_table <- function() {
  if (!is.null(.sp_model_cache[["vs_dt"]])) return(.sp_model_cache[["vs_dt"]])
  if (!requireNamespace("lexicon", quietly = TRUE) ||
      !requireNamespace("sentimentr", quietly = TRUE)) {
    return(NULL)
  }
  out <- tryCatch({
    vs <- as.data.frame(lexicon::hash_valence_shifters,
                        stringsAsFactors = FALSE)
    names(vs)[1:2] <- c("x", "y")
    vs$x <- tolower(as.character(vs$x))
    vs$y <- as.integer(vs$y)
    vs$y[vs$x %in% SP_NEGATOR_RETYPED] <- 1L
    # `scarcely` is absent from the stock shifter table entirely. It can only be
    # added if it is not also a polarity word: sentimentr requires polarity_dt
    # and valence_shifters_dt to be mutually exclusive and errors out if a term
    # appears in both ("`polarity_dt` & `valence_shifters_dt` not mutually
    # exclusive"). Terms the polarity lexicon already claims are left to it.
    pol <- tryCatch(
      tolower(as.character(as.data.frame(lexicon::hash_sentiment_jockers_rinker)[[1]])),
      error = function(e) character(0)
    )
    addable <- setdiff(setdiff(SP_NEGATOR_RETYPED, vs$x), pol)
    if (length(addable) > 0) {
      vs <- rbind(vs, data.frame(x = addable, y = 1L, stringsAsFactors = FALSE))
    }
    vs <- vs[order(vs$x), , drop = FALSE]
    sentimentr::as_key(vs, comparison = NULL, sentiment = FALSE)
  }, error = function(e) NULL)
  if (is.null(out)) return(NULL)
  .sp_model_cache[["vs_dt"]] <- out
  out
}

#' The valence-shifter surface forms sentimentr recognizes
.sp_valence_shifter_words <- function() {
  if (!requireNamespace("lexicon", quietly = TRUE)) {
    # Minimal negator set so negation survives even without the lexicon package.
    return(c("not", "no", "never", "none", "nobody", "nothing", "neither",
             "nowhere", "cannot", "cant", "can't", "don't", "dont", "isn't",
             "isnt", "wasn't", "wasnt", "aren't", "arent", "hardly", "barely",
             "scarcely", "seldom", "rarely", "very", "really", "extremely"))
  }
  tryCatch({
    vs <- as.data.frame(lexicon::hash_valence_shifters)
    tolower(as.character(vs[[1]]))
  }, error = function(e) c("not", "no", "never", "hardly", "barely", "very"))
}

#' Valence-adjusted polarity for one text blob, POS-filtered first
#'
#' udpipe decides which tokens may carry polarity (.sp_pos_filter_text), then
#' sentimentr scores the survivors with its valence shifters applied, which is
#' what makes "not good" negative -- something syuzhet could not do at all.
#'
#' `raw` is the summed valence-adjusted polarity across sentences. sentimentr
#' reports each sentence as sum(polarity) / sqrt(word_count), so the sqrt is
#' multiplied back out to recover a summed-polarity quantity comparable in kind
#' to what the old scorer returned; `normalized` then divides by the article's
#' POS-filtered word count, exactly as before.
#'
#' Measured effect of replacing the scorer, on one live `scrape = TRUE` run of
#' 2026-11-09 (72 beat items ingested, 46 WNBA-relevant after
#' filter_wnba_relevant_items(), 25 with scraped bodies and 21 on RSS
#' fallback). Because scrape_article_body() never persists a body, the corpus
#' was captured ONCE to a temp file outside the repo and then scored TWICE --
#' once through the old syuzhet/bing path, once through this one -- so the two
#' numbers describe the same 46 articles rather than two different corpora:
#'
#'   syuzhet + bing  +0.0286  ->  sentimentr + udpipe  +0.0590  (+106%)
#'
#' Both figures are post-masking (mask_team_names() + mask_basketball_jargon()),
#' i.e. measured against the post-#170 baseline as issue #171's dependency note
#' requires. The earlier RSS-archive-only "+1.7%" figure is NOT comparable and
#' is not cited here: re-scoring cache/raw_ingest_archive/ yields RSS text for
#' every item, which is a different corpus from one with 25 scraped bodies.
#'
#' The rise is expected and is not the scorer "getting more positive": the old
#' mean was depressed by function-word and word-sense noise scoring in both
#' directions, and sentimentr normalizes per sentence before summing. The
#' headline result of the change is the chips, not the mean -- `like` (107
#' occurrences, the #1 positive chip under bing) and `right` (38, #5) both leave
#' the breakdown entirely because udpipe tags their high-frequency uses ADP /
#' SCONJ / ADV. Top positive chips went
#'   like 107, best 77, win 54, good 40, right 38, won 37, work 35, well 31
#' to
#'   league 88, best 77, win 52, new 45, good 40, young 36, deal 35, work 35.
#'
#' Determinism (issue #171 acceptance 8, docs/REPRODUCIBILITY.md): the captured
#' corpus scored twice in one session returned 0.0590003121 both times,
#' identical() == TRUE. There is no RNG on this path; udpipe tagging and the
#' sentimentr lookup are both deterministic given the pinned model.
#'
#' @return list(raw =, words =, normalized =, text =, tokens =) or NULL
score_text_sentiment <- function(txt, model = .sp_udpipe_model()) {
  if (!requireNamespace("sentimentr", quietly = TRUE)) return(NULL)
  if (is.null(txt) || !nzchar(trimws(txt))) return(NULL)
  filtered <- .sp_pos_filter_text(txt, model = model)
  if (is.null(filtered)) return(NULL)
  tryCatch({
    vs_dt <- .sp_valence_shifter_table()
    sent <- as.data.frame(if (is.null(vs_dt)) {
      sentimentr::sentiment(filtered$text)
    } else {
      sentimentr::sentiment(filtered$text, valence_shifters_dt = vs_dt)
    })
    if (nrow(sent) == 0) return(NULL)
    vals <- sent$sentiment * sqrt(pmax(as.numeric(sent$word_count), 0))
    vals <- vals[is.finite(vals)]
    if (length(vals) == 0) return(NULL)
    raw <- sum(vals)
    n_words <- .sp_word_count(filtered$text)
    if (n_words == 0) return(NULL)
    list(raw = raw, words = n_words, normalized = raw / n_words,
         text = filtered$text, tokens = filtered$tokens)
  }, error = function(e) NULL)
}

#' jockers_rinker positive/negative word frequency breakdown
#'
#' Counts only tokens udpipe left eligible to carry polarity, so the chips are
#' drawn from precisely the token stream that produced the mean. This is why
#' `like`-as-preposition and `right`-as-adverb cannot reappear in the chips
#' while being excluded from the number, or the reverse.
#'
#' @param token_frames list of per-article token data.frames from score_text_sentiment()
#' @return list(available =, reason =, positive = list of {word, n}, negative = ...)
summarize_sentiment_words <- function(token_frames, top_n = .sp_top_words()) {
  if (!requireNamespace("lexicon", quietly = TRUE)) {
    return(list(available = FALSE, reason = "package 'lexicon' is not installed",
                positive = list(), negative = list()))
  }
  token_frames <- Filter(function(d) is.data.frame(d) && nrow(d) > 0, token_frames %||% list())
  if (length(token_frames) == 0) {
    return(list(available = FALSE, reason = "no POS-tagged tokens to summarize",
                positive = list(), negative = list()))
  }

  tryCatch({
    lex <- as.data.frame(lexicon::hash_sentiment_jockers_rinker)
    names(lex)[1:2] <- c("word", "y")
    lex$word <- tolower(as.character(lex$word))

    words <- unlist(lapply(token_frames, function(d) d$token), use.names = FALSE)
    words <- words[nzchar(words)]
    if (length(words) == 0) {
      return(list(available = FALSE, reason = "no tokens",
                  positive = list(), negative = list()))
    }
    joined <- merge(data.frame(word = words, stringsAsFactors = FALSE), lex, by = "word")
    joined <- joined[is.finite(joined$y) & joined$y != 0, , drop = FALSE]
    if (nrow(joined) == 0) {
      return(list(available = TRUE, reason = NULL, positive = list(),
                  negative = list(), matchedWords = 0L))
    }
    pick <- function(positive) {
      sub <- if (positive) joined[joined$y > 0, , drop = FALSE] else joined[joined$y < 0, , drop = FALSE]
      if (nrow(sub) == 0) return(list())
      tb <- sort(table(sub$word), decreasing = TRUE)
      tb <- tb[seq_len(min(length(tb), as.integer(top_n)))]
      lapply(seq_along(tb), function(i) list(word = names(tb)[i], n = as.integer(tb[[i]])))
    }
    list(available = TRUE, reason = NULL,
         positive = pick(TRUE), negative = pick(FALSE),
         matchedWords = nrow(joined))
  }, error = function(e) {
    list(available = FALSE,
         reason = paste("word breakdown failed:", conditionMessage(e)),
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
#' Note on `words` (changed by issue #171): per-item word counts, and therefore
#' the `extremesMinWords` eligibility floor, are counted on the POS-FILTERED
#' token stream -- the same denominator the normalized score divides by. An
#' article's reported `words` is consequently lower than its surface word count
#' by roughly the share of function words, and the floor is correspondingly
#' stricter than it was under the old scorer. Keeping the floor and the
#' normalization on one quantity is deliberate: the floor exists because a
#' per-word mean is unstable when the denominator is small, so it has to be the
#' denominator that is tested.
#'
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
      posDisambiguated = FALSE,
      modelVersion = SP_UDPIPE_MODEL_VERSION,
      lexicon = "jockers_rinker",
      method = "sentimentr + udpipe"
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

  # Packages AND the pinned model are checked up front, before any scraping, so
  # an unusable scorer costs no network traffic. There is deliberately no
  # fallback to syuzhet/bing here (issue #171 design decision 5): an unreadable
  # model means no sentiment number this week, which is preferred over a number
  # whose method varies by runtime conditions.
  scorer_reason <- .sp_scorer_unavailable_reason()
  if (!is.null(scorer_reason)) return(unavailable(scorer_reason))
  model <- .sp_udpipe_model()

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
    # same string (issue #170), so the mean and the chips stay in agreement.
    # Masking is still required under jockers_rinker -- see this file's
    # measurement note in mask_basketball_jargon()'s roxygen.
    text_used <- mask_basketball_jargon(mask_team_names(text_used))
    if (!nzchar(trimws(text_used))) next

    sc <- score_text_sentiment(text_used, model = model)
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
      tokens = sc$tokens,
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

  # Chips come from the POS-filtered tokens the scorer already produced, not a
  # re-tokenization of the text: re-tokenizing would discard the word-sense work
  # and let `like`-as-preposition back into the breakdown.
  breakdown <- summarize_sentiment_words(lapply(rows, function(r) r$tokens),
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
    posDisambiguated = TRUE,
    modelVersion = SP_UDPIPE_MODEL_VERSION,
    wordBreakdown = breakdown,
    lexicon = "jockers_rinker",
    method = "sentimentr + udpipe"
  )
}
