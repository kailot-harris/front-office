# Media Sentiment Pulse — method, lexicon, caps, failure modes (Issue #156)

Implemented by `tools/offseason/sentiment_pulse.R`; rendered as an optional extra
section of the weekly memo by `tools/offseason/render_memo.R`
(`render_block_media_sentiment()`); invoked from `build_offseason_monitor.R` Step 4.

## Data source: the items the monitor already ingests

The pulse does **not** fetch any RSS feed of its own and does **not** use `tidyRSS`.
It consumes `run_ingestion()$items` — the already-validated wire items described in
`docs/internal/offseason_wire_items_contract.md` — filtered to
`source_family == "beat_feeds"` (`filter_beat_feed_items()`). Those items are produced by
`poll_beat_feeds()` over the six outlets in `ingest_sources.R`'s `DEFAULT_BEAT_SOURCES`,
including the ESPN WNBA news feed that Issue #156 originally named. This sequencing was the
condition on #156 (after #159/#161) so that there is exactly one ingestion path of record.

Each item contributes:

- `raw_text` — the RSS `title - description`. This is the **baseline** text scored.
- `source_url` — used for a best-effort full-article body scrape (enrichment only).
- `source_id`, `item_id` — attribution/logging.

## Method

1. **Text selection per article.** If a body scrape succeeds and yields at least
   `OFFSEASON_SENTIMENT_MIN_BODY_CHARS` characters of paragraph text, that body is scored;
   otherwise the item's `raw_text` is scored. The number of each is reported
   (`scrapedCount` / `fallbackCount`) and rendered in the memo, so a reader can always tell
   how much of the week's score came from full text vs. RSS summaries.
2. **Polarity.** `syuzhet::get_sentences()` then
   `syuzhet::get_sentiment(..., method = "syuzhet")`, summed across sentences.
   This is the method the issue specified; there was no pre-existing sentiment code in the
   repo to stay consistent with.
3. **Normalization.** The summed polarity is divided by the article's word count, so the
   weekly mean is not dominated by long features. Reported as "per word".
   *Caveat:* short texts (an RSS title with no description) have high-variance normalized
   scores, so the most-positive / most-negative extremes can be short items; each rendered
   extreme therefore also carries its raw score and word count in the structured object.
4. **Word breakdown.** `tidytext::get_sentiments("bing")` joined against the tokenized
   scored texts, top `OFFSEASON_SENTIMENT_TOP_WORDS` words per polarity by frequency. The
   `bing` lexicon ships inside `tidytext`; `textdata` is **not** required. The breakdown is
   descriptive only — it never feeds the numeric score.

Lexicon note: `bing` is a general-English polarity lexicon, so basketball vocabulary gets
scored literally (`defensive`, `steals`, `block` read as negative). Treat the word lists as
a readable gloss on the week's vocabulary, not as a basketball-aware signal.

## Caps and timeouts (all in `config.R`)

| Constant | Value | Purpose |
| --- | --- | --- |
| `OFFSEASON_SENTIMENT_MAX_ARTICLES` | 25 | Max items given a live HTTP body fetch per run. Items past the cap are still scored, from RSS text. |
| `OFFSEASON_SENTIMENT_SCRAPE_TIMEOUT_SEC` | 8 | Per-request timeout (`httr::timeout()`). |
| `OFFSEASON_SENTIMENT_TOP_WORDS` | 8 | Words per polarity in the bing breakdown. |
| `OFFSEASON_SENTIMENT_MIN_BODY_CHARS` | 400 | Below this, a "body" is treated as a paywall/consent shell and the RSS text is used instead. |

Each has its derivation comment in `config.R`; read values from there, never from this table.

## Failure modes — all fail soft, none fabricate a number

| Condition | Behaviour |
| --- | --- |
| One article URL unreachable / times out / returns 4xx-5xx / markup changed so no paragraphs match | `scrape_article_body()` returns `NULL` (it catches both errors and warnings), a `log_warn` is emitted naming the item and URL, the loop continues, and that item is scored from its `raw_text`. |
| Items beyond `OFFSEASON_SENTIMENT_MAX_ARTICLES` | No HTTP request at all; scored from `raw_text`. |
| `dry_run = TRUE` | `build_offseason_monitor.R` passes `scrape = FALSE`, so the pass issues zero network requests. |
| `syuzhet` not installed | `available = FALSE`, `meanSentiment = NULL`, `reason` names the missing package; memo renders an explicit "Sentiment scoring unavailable this week (...)" line. |
| `tidytext` not installed | Scores still render; `wordBreakdown$available = FALSE` and the memo says the breakdown is unavailable with the reason. |
| Zero `beat_feeds` items ingested | `available = FALSE` with reason "no beat_feeds wire items were ingested this run"; no score. |
| No item yields scorable text | `available = FALSE` with reason "no beat-feed item yielded a scorable text body". |
| Anything unanticipated inside the pass | `build_offseason_monitor.R` wraps the call in `tryCatch`, logs a warning, and passes `NULL` to the renderer, which omits the section entirely. The weekly publish still completes. |

No placeholder, synthetic, or default numeric sentiment value exists anywhere in this path —
per issues #129 / #133-#135 (epic #138), a fabricated published number is a defect, so the
only alternative to a real score is the labelled absence of one.

## Outputs

- **Memo:** a `### Media Sentiment Pulse` section appended after Block 7. The renderer
  argument `media_sentiment_pulse` defaults to `NULL`, so any caller that omits it (including
  the existing unit tests) gets byte-identical 7-block output.
- **Edition JSON:** optional `mediaSentimentPulse` object on each edition in
  `web/public/data/offseason_monitor.json`; typed as the optional `MediaSentimentPulse`
  interface field in `web/lib/offseasonTypes.ts`. No new page or component consumes it yet.

## Tests

`tests/unit/test_offseason_sentiment_pulse.R` covers the populated happy path (including
that non-`beat_feeds` families are excluded), the zero-item case, the missing-package
degradation, deliberately unreachable `source_url`s, and the additivity of the memo block.
