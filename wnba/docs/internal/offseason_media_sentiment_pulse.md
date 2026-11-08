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

### Relevance gate (added after the first live run)

`DEFAULT_BEAT_SOURCES` are women's-basketball and women's-sports feeds, **not** WNBA-only
wires. `filter_wnba_relevant_items()` therefore keeps only items whose `raw_text` or
`source_url` names the league or any franchise — full name, city, or nickname, all derived
from `config.R`'s `WNBA_TEAMS` via `wnba_team_vocabulary()`, so an expansion team needs no
edit here.

Measured on the 2026-11-07 live run (70 beat items, the first real run of this path):

| Source | Kept | Ingested |
| --- | --- | --- |
| `espn_wnba_beat` | 19 | 20 |
| `winsidr` | 10 | 10 |
| `her_hoop_stats` | 10 | 20 |
| `the_next_hoops` | 6 | 10 |
| `just_womens_sports` | 1 | 10 |
| **total** | **46** | **70** |

The 24 excluded items were WTA tennis, PWHL and ECAC hockey, NCAA game recaps, and FIBA
World Cup coverage. Before the gate existed, one of them — a Florida–UCF college recap —
was published as the week's most negative *WNBA* story.

**Accepted false negative:** a WNBA-adjacent item that names neither the league nor a
franchise is excluded too. On that run those were an Unrivaled roster story and a Hall of
Fame class item that named only players. Excluding them is the conservative error, and
`offTopicExcluded` is reported in the artifact and rendered in the memo so the size of the
filter is always visible rather than silent.

## Method

1. **Text selection per article.** If a body scrape succeeds and yields at least
   `OFFSEASON_SENTIMENT_MIN_BODY_CHARS` characters of paragraph text, that body is scored;
   otherwise the item's `raw_text` is scored. The number of each is reported
   (`scrapedCount` / `fallbackCount`) and rendered in the memo, so a reader can always tell
   how much of the week's score came from full text vs. RSS summaries.
2. **Team-name masking.** `mask_team_names()` replaces every franchise full name, city and
   nickname with a space *before* scoring. Team names are proper nouns that general-English
   lexicons score as ordinary words: on the 2026-11-07 run `liberty` (40 occurrences) and
   `golden` (19) were the two largest positive terms in the bing breakdown, and only three
   team tokens are bing entries at all (`liberty`, `golden`, `fever`). Scoring that run's
   items from **RSS text only**, masking moved the mean from **+0.0265 to +0.0217, a 18%
   reduction** — nearly a fifth of the "positive sentiment" in short items was franchise
   names. On the full corpus the effect is smaller (+0.0282 unmasked → +0.0268 masked,
   measured across runs in which the relevance gate also changed the item set, so the two
   are not cleanly separable): scraped bodies run to hundreds of words, which dilutes a
   handful of team mentions. The short-item case is where it mattered most, and that is
   also where the extremes are drawn from. After masking, `liberty` and `golden` no longer
   appear in the week's top positive words at all. The same masked string feeds both the
   score and the word breakdown, so the memo's numbers and its word lists agree.
   *Tradeoff:* nicknames are common nouns, so a non-team use ("a fire sale") is masked too.
   In beat coverage of this league those tokens overwhelmingly denote the franchise, and
   leaving them scored is the larger error. Substrings are safe — `civil liberties` and
   `firearm` are untouched, because masking uses Perl lookarounds rather than `\b`
   (lookarounds do not consume the boundary character, so adjacent team references like
   "Liberty Sky" both mask in one pass).
3. **Polarity.** `syuzhet::get_sentences()` then
   `syuzhet::get_sentiment(..., method = "syuzhet")`, summed across sentences.
   This is the method the issue specified; there was no pre-existing sentiment code in the
   repo to stay consistent with.
4. **Normalization.** The summed polarity is divided by the article's word count, so the
   weekly mean is not dominated by long features. Reported as "per word".
5. **Extreme selection floor.** Because the score is a per-word mean, short texts have
   high-variance normalized scores and win the extremes on noise. The first live run
   published a **9-word RSS title at +0.1278/word** as "most positive" — roughly 5x the
   weekly mean, unreachable by any full-length article. Extremes are therefore drawn only
   from items of at least `OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS` words. **Every relevant
   item still contributes to the mean** — the floor governs selection only. If nothing
   clears the floor, the extremes fall back to the full set and the memo says so in words
   (`extremesFloorApplied = FALSE`) rather than presenting a noisy pick as a finding. Each
   rendered extreme still carries its raw score and word count in the structured object.
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
| `OFFSEASON_SENTIMENT_MIN_EXTREME_WORDS` | 40 | Minimum words for an item to be eligible as a most-positive/most-negative extreme. Does not affect the mean. |

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
| Beat items ingested but none WNBA-relevant | `available = FALSE` with a reason naming how many were filtered; no score. A week of pure college/hockey coverage reports an honest absence rather than a sentiment number for other sports. |
| No item clears the extreme word floor | Extremes fall back to all scored items, `extremesFloorApplied = FALSE`, a `log_warn` is emitted, and the memo labels the picks noise-prone. The mean is unaffected. |
| No item yields scorable text | `available = FALSE` with reason "no beat-feed item yielded a scorable text body". |
| Anything unanticipated inside the pass | `build_offseason_monitor.R` wraps the call in `tryCatch`, logs a warning, and passes `NULL` to the renderer, which omits the section entirely. The weekly publish still completes. |

No placeholder, synthetic, or default numeric sentiment value exists anywhere in this path —
per issues #129 / #133-#135 (epic #138), a fabricated published number is a defect, so the
only alternative to a real score is the labelled absence of one.

## Sign of the extremes

A quiet, positive news week can leave *every* scored article above zero, in which case the
minimum is not a negative story — it is the least positive one. The 2026-11-07 run's
lowest-scoring article was **+0.0043**, a long retrospective feature, which reads as a
damning headline under a "Most negative" label. `render_block_media_sentiment()` therefore
labels that row **"Least positive"** whenever the minimum score is >= 0, and keeps
"Most negative" only when it is genuinely below zero.

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
