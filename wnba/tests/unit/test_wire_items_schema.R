# ==============================================================================
# test_wire_items_schema.R
# Unit Tests for Offseason Wire Items Contract & Validator (Issue #159 / Unit A)
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
  library(jsonlite)
})

# Source schema implementation
source(file.path("tools", "offseason", "wire_items_schema.R"))

test_that("wire_items_schema.R exports expected public interface", {
  expect_true(exists("WIRE_ITEM_REQUIRED_FIELDS"))
  expect_true(exists("WIRE_ITEM_ALLOWED_FAMILIES"))
  expect_true(exists("create_wire_item"))
  expect_true(exists("validate_wire_items"))
  expect_true(exists("read_wire_items"))
  expect_true(exists("write_wire_items"))
})

test_that("sample fixture data/fixtures/wire_items_sample.json is valid", {
  fixture_path <- file.path("data", "fixtures", "wire_items_sample.json")
  expect_true(file.exists(fixture_path))

  # Test via path validation
  is_valid <- validate_wire_items(fixture_path)
  expect_true(is_valid)
  expect_equal(attr(is_valid, "item_count"), 8L)

  # Test via parsed object validation
  items <- read_wire_items(fixture_path, validate = TRUE)
  expect_equal(length(items), 8L)

  # Verify structural team_abbr sibling field exists on ESPN items and is NULL on beat feeds
  espn_item <- items[[1]]
  expect_equal(espn_item$item_id, "espn_wire_20261023_ind_001")
  expect_equal(espn_item$source_family, "league_wire")
  expect_equal(espn_item$team_abbr, "IND")

  beat_item <- items[[7]]
  expect_equal(beat_item$item_id, "beat_espn_50368306")
  expect_equal(beat_item$source_family, "beat_feeds")
  expect_true(is.null(beat_item$team_abbr) || is.na(beat_item$team_abbr))

  # Verify multi-event item preserved as single wire item
  multi_event_item <- items[[2]]
  expect_equal(multi_event_item$item_id, "espn_wire_20260920_gs_002")
  expect_match(multi_event_item$raw_text, "Aminata Gueye")
  expect_match(multi_event_item$raw_text, "Nadia Fingall")
})

test_that("create_wire_item constructs valid item", {
  item <- create_wire_item(
    item_id = "test_item_001",
    source_family = "league_wire",
    source_id = "espn",
    source_url = "https://example.com/tx",
    observed_at = "2026-11-06T11:42:45Z",
    event_date = "2026-10-23",
    raw_text = "Signed player to a contract.",
    team_abbr = "IND"
  )

  expect_true(validate_wire_items(list(item)))
  expect_equal(item$team_abbr, "IND")
  expect_equal(item$source_family, "league_wire")
})

test_that("validate_wire_items rejects records missing item_id", {
  invalid_item <- list(
    # missing item_id
    source_family = "league_wire",
    source_id = "espn",
    observed_at = "2026-11-06T11:42:45Z",
    event_date = "2026-10-23",
    raw_text = "Sample transaction text"
  )

  res <- validate_wire_items(list(invalid_item), detailed = TRUE)
  expect_false(res$valid)
  expect_true(any(grepl("missing required field 'item_id'", res$errors)))

  # Also test empty string item_id
  invalid_item_empty <- invalid_item
  invalid_item_empty$item_id <- "   "
  res_empty <- validate_wire_items(list(invalid_item_empty), detailed = TRUE)
  expect_false(res_empty$valid)
  expect_true(any(grepl("item_id.*must be a non-empty", res_empty$errors)))
})

test_that("validate_wire_items rejects records missing observed_at", {
  invalid_item <- list(
    item_id = "test_002",
    source_family = "league_wire",
    source_id = "espn",
    # missing observed_at
    event_date = "2026-10-23",
    raw_text = "Sample transaction text"
  )

  res <- validate_wire_items(list(invalid_item), detailed = TRUE)
  expect_false(res$valid)
  expect_true(any(grepl("missing required field 'observed_at'", res$errors)))

  # Test malformed observed_at
  invalid_item_bad_ts <- invalid_item
  invalid_item_bad_ts$observed_at <- "not-an-iso-timestamp"
  res_bad_ts <- validate_wire_items(list(invalid_item_bad_ts), detailed = TRUE)
  expect_false(res_bad_ts$valid)
  expect_true(any(grepl("does not match ISO 8601 pattern", res_bad_ts$errors)))
})

test_that("validate_wire_items rejects invalid source_family and empty raw_text", {
  invalid_family <- list(
    item_id = "test_003",
    source_family = "unsupported_family",
    source_id = "espn",
    observed_at = "2026-11-06T11:42:45Z",
    event_date = "2026-10-23",
    raw_text = "Sample transaction text"
  )
  res_fam <- validate_wire_items(list(invalid_family), detailed = TRUE)
  expect_false(res_fam$valid)
  expect_true(any(grepl("must be one of: league_wire, beat_feeds, team_releases", res_fam$errors)))

  invalid_text <- list(
    item_id = "test_004",
    source_family = "league_wire",
    source_id = "espn",
    observed_at = "2026-11-06T11:42:45Z",
    event_date = "2026-10-23",
    raw_text = "   "
  )
  res_txt <- validate_wire_items(list(invalid_text), detailed = TRUE)
  expect_false(res_txt$valid)
  expect_true(any(grepl("raw_text.*must be a non-empty", res_txt$errors)))
})

test_that("validate_wire_items fails closed with stop_on_error = TRUE", {
  bad_item <- list(item_id = "bad_001")
  expect_error(
    validate_wire_items(list(bad_item), stop_on_error = TRUE),
    "Wire items validation failed"
  )
})

test_that("read_wire_items and write_wire_items round-trip with temporary file", {
  tmp_file <- tempfile(fileext = ".json")
  on.exit(unlink(tmp_file), add = TRUE)

  fixture_path <- file.path("data", "fixtures", "wire_items_sample.json")
  items <- read_wire_items(fixture_path, validate = TRUE)

  write_wire_items(items, tmp_file, validate = TRUE)
  expect_true(file.exists(tmp_file))

  roundtrip_items <- read_wire_items(tmp_file, validate = TRUE)
  expect_equal(length(roundtrip_items), length(items))
  expect_equal(roundtrip_items[[1]]$item_id, items[[1]]$item_id)
  expect_equal(roundtrip_items[[1]]$raw_text, items[[1]]$raw_text)
})
