# Research: Prediction-Market Alpha (Kalshi WNBA contracts vs. this repo's models)
#
# Side-project feasibility research, NOT part of run_full_pipeline.R's DAG and not wired into any
# production script. See docs/prediction_market_alpha_research_plan.md for the full writeup,
# revenue-stream hypotheses, and next steps -- this script implements only the first next step:
# confirming a real, collision-free join key between Kalshi's WNBA game contracts and this repo's
# own WNBA_TEAMS (config.R), mirroring the CONN/CON join-key discipline CLAUDE.md already requires
# for wehoop. Kalshi's public market-data API needs no authentication (confirmed 2026-09-17).
#
# Usage: Rscript.exe tools/research_prediction_markets.R

PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_ROOT)
source("config.R")

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(purrr)
})

KALSHI_BASE <- "https://api.elections.kalshi.com/trade-api/v2"

# ------------------------------------------------------------------------------
# 1. Connectivity check (fail loudly here -- everything downstream assumes this works)
# ------------------------------------------------------------------------------
kalshi_get <- function(path, query = list()) {
  resp <- tryCatch(
    request(paste0(KALSHI_BASE, path)) |>
      req_url_query(!!!query) |>
      req_timeout(15) |>
      req_perform(),
    error = function(e) NULL
  )
  if (is.null(resp) || resp_status(resp) != 200) {
    stop(sprintf("Kalshi API call to %s failed (status: %s). Public read endpoints should need no auth -- check connectivity, not credentials.",
                 path, if (is.null(resp)) "no response" else resp_status(resp)))
  }
  resp_body_json(resp)
}

cat("[1/3] Checking Kalshi public market-data API connectivity...\n")
game_markets <- kalshi_get("/markets", list(series_ticker = "KXWNBAGAME", status = "open", limit = 100))$markets
cat(sprintf("      OK -- %d open KXWNBAGAME market(s) found.\n\n", length(game_markets)))

if (length(game_markets) == 0) {
  cat("No open game markets right now (off-season or between slates) -- falling back to settled markets for the join-key check.\n")
  game_markets <- kalshi_get("/markets", list(series_ticker = "KXWNBAGAME", status = "settled", limit = 200))$markets
}

# ------------------------------------------------------------------------------
# 2. Team-code join-key check -- the real gotcha found during initial feasibility research:
#    Kalshi's event tickers embed team codes (e.g. "...CONNDAL-CONN") that do NOT match
#    WNBA_TEAMS's names(...) 1:1 (CONN vs CON, same as wehoop), and its human-readable
#    yes_sub_title/no_sub_title fields are CITY-only ("Washington"), not full franchise names
#    ("Washington Mystics"). Verify the overlap empirically rather than assuming either mapping.
# ------------------------------------------------------------------------------
cat("[2/3] Building normalize_kalshi_team_code() and checking overlap against WNBA_TEAMS...\n")

# Kalshi ticker shape: KXWNBAGAME-<date><AWAY><HOME>-<SIDE>, e.g. KXWNBAGAME-26AUG30CONNDAL-DAL.
# The <SIDE> suffix is the authoritative team code for that specific market (one market per side).
extract_kalshi_side_code <- function(ticker) {
  sub("^.*-([A-Z]+)$", "\\1", ticker)
}

# Known Kalshi <-> WNBA_TEAMS code divergences found so far (extend as more are discovered --
# mirrors normalize_team_abbreviation()'s role for wehoop, don't reimplement this ad hoc elsewhere).
# CONN found via the ticker string itself; PDX found empirically by this script's own overlap
# check on its first real run (Kalshi uses the Portland Fire's city airport code, WNBA_TEAMS uses
# POR) -- left in as a worked example that this check catches real drift, not just the one gotcha
# already known from wehoop.
KALSHI_TEAM_CODE_MAP <- c(CONN = "CON", PDX = "POR")
normalize_kalshi_team_code <- function(code) {
  unname(ifelse(code %in% names(KALSHI_TEAM_CODE_MAP), KALSHI_TEAM_CODE_MAP[code], code))
}

side_codes <- vapply(game_markets, function(m) extract_kalshi_side_code(m$ticker), character(1))
normalized <- normalize_kalshi_team_code(unique(side_codes))

matched <- normalized[normalized %in% names(WNBA_TEAMS)]
unmatched <- setdiff(normalized, names(WNBA_TEAMS))

cat(sprintf("      %d distinct team code(s) seen in pulled markets: %s\n",
            length(normalized), paste(sort(normalized), collapse = ", ")))
cat(sprintf("      Matched to WNBA_TEAMS: %d/%d\n", length(matched), length(normalized)))
if (length(unmatched) > 0) {
  cat(sprintf("      UNMATCHED (needs a new normalize_kalshi_team_code() case, do not proceed to a real join until this is empty): %s\n",
              paste(unmatched, collapse = ", ")))
} else {
  cat("      Full match -- safe to join Kalshi contracts to WNBA_TEAMS-keyed caches by normalized code.\n")
}
cat("\n")

# ------------------------------------------------------------------------------
# 3. Spot-check: does a sample settled contract's price path make directional sense?
#    (Sanity check only, per this repo's "confirmed empirically, not assumed" convention --
#    NOT a divergence measurement. See docs/prediction_market_alpha_research_plan.md Next Steps
#    #2 for the actual model-vs-market divergence study, which is deliberately NOT done here.)
# ------------------------------------------------------------------------------
cat("[3/3] Spot-checking one settled market's resolution matches its declared result...\n")
settled <- kalshi_get("/markets", list(series_ticker = "KXWNBAGAME", status = "settled", limit = 5))$markets
if (length(settled) > 0) {
  s <- settled[[1]]
  cat(sprintf("      %s -> result=%s, final yes price=$%s (sanity: 'yes' should settle near $1.00, 'no' near $0.00)\n",
              s$ticker, s$result, s$last_price_dollars))
} else {
  cat("      No settled markets returned -- skip (not a failure, just no sample available right now).\n")
}

cat("\nDone. This script only verifies the join key and connectivity -- see docs/prediction_market_alpha_research_plan.md for the actual research plan and what's still deferred (divergence measurement, backtest, Polymarket check).\n")
