# ==============================================================================
# market_provenance.R
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/market_provenance.R
#
# The single provenance gate for market/value-bet rows. Sourced by every stage
# that consumes the value-bets cache -- today mlb_notify_bets.R (Discord) and
# tools/export_web_data.R (the web JSON). There must be exactly one
# implementation of this decision: a second copy would drift, and the drift
# would be invisible until something fabricated got published.
#
# Why this exists. Two upstream paths can put fabricated rows into the
# value-bets data frame: generate_synthetic_mlb_slate() in mlb_notify_bets.R,
# and mlb_market_odds_engine.R's own fallback, which writes SYNTHETIC_FALLBACK
# rows into cache/latest_value_bets.rds when the live odds feed returns nothing.
# On 2026-10-25 the second path put six invented bets -- invented game_ids and
# prices, on teams already eliminated -- into the cache, and run_notify_bets()
# broadcast three of them to Discord (status 204). The rows were correctly
# labelled; nothing downstream read the label. This is that check.
#
# Fails CLOSED: a row whose market_data_source is missing, NA or anything other
# than LIVE_ODDS_API is treated as untrusted and dropped. A bet whose provenance
# cannot be established is exactly the kind that must not be sent or published.
#
# Kept as a pure function so the decision is unit-testable without a cache, a
# webhook or log scraping -- see tests/testthat/test-notify-provenance.R and
# tests/testthat/test-value-bets-export.R.
# ==============================================================================

LIVE_PROVENANCE <- "LIVE_ODDS_API"

filter_live_provenance <- function(df) {
  if (is.null(df) || nrow(df) == 0) {
    return(list(kept = df, n_before = 0L, n_dropped = 0L, dropped_sources = character(0)))
  }
  n_before <- nrow(df)
  src <- if ("market_data_source" %in% names(df)) as.character(df$market_data_source) else rep(NA_character_, n_before)
  is_live <- !is.na(src) & src == LIVE_PROVENANCE
  dropped <- src[!is_live]
  dropped[is.na(dropped)] <- "<missing>"
  list(
    kept = df[is_live, , drop = FALSE],
    n_before = n_before,
    n_dropped = n_before - sum(is_live),
    dropped_sources = dropped
  )
}
