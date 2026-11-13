# Fetches Basketball-Reference's NBA salary-cap-history table for GitHub issue #99
# (Phase 2b of the Basketball-Reference cap-data automation effort; see #97/Phase 1 for
# the reachability/structure research this script implements, and #75 for the underlying
# audit question this effort answers).
#
# SOURCE TABLE SCOPE (per #97's Phase 1 findings, confirmed live 2026-11-13): this table
# contains ONLY the base nominal salary cap ("Salary Cap") and its inflation-adjusted
# equivalent ("2025 Dollars") for each season, 1984-85 to present (43 rows as of Phase 1).
# It does NOT contain luxury tax, first apron, or second apron figures anywhere. Any
# tax/apron work (Phase 3/4) MUST come from a different Basketball-Reference page or a
# different source entirely — do not expect this script's output to ever carry those
# columns.
#
# Mechanics: Basketball-Reference wraps this table in an HTML comment (`<!-- ... -->`) in
# the raw response. We fetch with httr2, strip the comment markers with stringr, then parse
# the uncommented fragment with rvest. Per Phase 1's robots.txt findings, this path
# (`/contracts/salary-cap-history.html`) is not disallowed, but `Crawl-delay: 3` is
# specified for `User-agent: *` — this script is a single request, so there is no second
# request to delay before, but any caller that re-runs this script in a loop must leave at
# least 3 seconds between invocations.
#
# Output: cache/bbref_salary_cap_history.rds — a data frame with columns:
#   season          chr   e.g. "2026-27"
#   salary_cap      dbl   nominal salary cap, dollars (no "$"/commas)
#   salary_cap_2025 dbl   inflation-adjusted ("2025 Dollars") equivalent, dollars
#   fetched_at      POSIXct, UTC, time this script ran
#
# Usage: Rscript tools/fetch_bbref_salary_cap_history.R
setwd("c:/Users/kailo/kayceeslices/front-office/NBA Analytics")

suppressPackageStartupMessages({
  library(httr2)
  library(rvest)
  library(stringr)
  library(dplyr)
})

URL <- "https://www.basketball-reference.com/contracts/salary-cap-history.html"
OUT_PATH <- file.path("cache", "bbref_salary_cap_history.rds")
TABLE_ID <- "salary_cap_history"
EXPECTED_MIN_ROWS <- 40L  # Phase 1 observed 43 (1984-85 to present); allow modest slack
                          # for season-boundary timing without masking a real break.

dollars_to_numeric <- function(x) {
  as.numeric(str_remove_all(x, "[\\$,]"))
}

fail <- function(fmt, ...) {
  stop(sprintf(paste0("fetch_bbref_salary_cap_history: ", fmt), ...), call. = FALSE)
}

# --- 1. Fetch -----------------------------------------------------------------------
resp <- tryCatch(
  request(URL) |>
    req_user_agent(
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) "
      ) |>
    req_timeout(30000) |>
    req_perform(),
  error = function(e) {
    fail("could not reach %s (page unreachable or network error): %s", URL, conditionMessage(e))
  }
)

if (resp_status(resp) != 200) {
  fail("unexpected HTTP status %d fetching %s", resp_status(resp), URL)
}

raw_html <- resp_body_string(resp)

# --- 2. Strip the HTML-comment wrapper and locate the table --------------------------
# Basketball-Reference hides this table inside an HTML comment. If BBRef changes this
# markup pattern (comment removed, table moved, id renamed), the fragment below will
# simply fail to contain our target table id, and we fail loudly rather than silently
# emitting an empty/garbage data frame.
uncommented <- str_remove_all(raw_html, "<!--|-->")

page <- tryCatch(
  read_html(uncommented),
  error = function(e) {
    fail("comment-stripping produced unparseable HTML (BBRef may have changed its markup): %s",
         conditionMessage(e))
  }
)

tbl_node <- html_element(page, sprintf("#%s", TABLE_ID))
if (inherits(tbl_node, "xml_missing") || is.na(as.character(tbl_node))) {
  fail(
    paste0(
      "table id '#%s' not found after stripping HTML comments — Basketball-Reference ",
      "likely changed its comment-wrapping trick or the table's id. Inspect %s manually."
    ),
    TABLE_ID, URL
  )
}

raw_tbl <- tryCatch(
  html_table(tbl_node, header = TRUE),
  error = function(e) {
    fail("found table '#%s' but html_table() failed to parse it: %s", TABLE_ID, conditionMessage(e))
  }
)

# --- 3. Validate columns --------------------------------------------------------------
expected_cols <- c("Year", "Salary Cap", "2025 Dollars")
if (!all(expected_cols %in% names(raw_tbl))) {
  fail(
    "parsed table is missing expected column(s); got %s, expected %s",
    paste(names(raw_tbl), collapse = ", "), paste(expected_cols, collapse = ", ")
  )
}

cap_history <- raw_tbl |>
  transmute(
    season          = as.character(.data[["Year"]]),
    salary_cap      = dollars_to_numeric(.data[["Salary Cap"]]),
    salary_cap_2025 = dollars_to_numeric(.data[["2025 Dollars"]])
  ) |>
  filter(!is.na(salary_cap), season != "", !str_detect(season, "^(Year)$")) |>
  distinct(season, .keep_all = TRUE)

if (nrow(cap_history) < EXPECTED_MIN_ROWS) {
  fail(
    "parsed only %d season rows (expected at least %d, Phase 1 observed 43) — comment-stripping ",
    "or column parsing may be silently dropping rows",
    nrow(cap_history), EXPECTED_MIN_ROWS
  )
}

if (anyNA(cap_history$salary_cap)) {
  fail("salary_cap contains NA after numeric coercion — dollar-string parsing broke")
}
# NOTE: salary_cap_2025 ("2025 Dollars") legitimately comes back blank from BBRef for the
# most recent season(s) — they haven't been inflation-indexed yet — so NA there is expected,
# not a parsing failure. Only flag it if ALL rows are NA, which would indicate the whole
# column failed to parse rather than a couple of trailing current seasons.
if (all(is.na(cap_history$salary_cap_2025))) {
  fail("salary_cap_2025 is entirely NA after numeric coercion — dollar-string parsing broke")
}

cap_history$fetched_at <- as.POSIXct(Sys.time(), tz = "UTC")

# --- 4. Write --------------------------------------------------------------------------
dir.create("cache", showWarnings = FALSE)
saveRDS(cap_history, OUT_PATH)

cat(sprintf(
  "fetch_bbref_salary_cap_history: wrote %d rows (%s) to %s\n",
  nrow(cap_history),
  paste(range(cap_history$season), collapse = " .. "),
  normalizePath(OUT_PATH)
))
