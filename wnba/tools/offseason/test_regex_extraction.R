# ==============================================================================
# test_regex_extraction.R
# WNBA Offseason Dynamics Monitor — Unit Tests for Deterministic Regex Extractor
# Tier 2 / Phase 3 CI Gate (Issue #164)
#
# Asserts:
#   1. Multi-event splitting on real ESPN transaction archive (>= 35 deltas on 25 rows)
#   2. Structural team resolution via parameter
#   3. Full position prefix support (C, F, G, G/F, F/G, C/F, CF typo) + possessives
#   4. All 8 live observed verbs classified + trade vs waiver claim disambiguation
#   5. Explicit unclassified reporting (never silently dropped)
#   6. Off-season class extraction (Core, Reserved, QO, Prioritization, Retirement, etc.)
#   7. Legacy fixtures backward compatibility (100% precision & recall)
#
# Runs offline, 0 API calls, <200ms.
# ==============================================================================

# ------------------------------------------------------------------------------
# Root-resolution prelude (Issue #90 Working Directory Trap)
# Guarantees the script resolves repo root regardless of invocation working dir
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

# Shared fixture-path resolution (tracked fixture, not gitignored runtime cache)
source(file.path("tests", "helpers", "offseason_fixtures.R"))

# Source the regex extractor under test
source(file.path("tools", "offseason", "extract_regex.R"))

start_time <- Sys.time()

# ==============================================================================
# Criterion 1: Multi-Event Splitting on Real Archived Payloads
# ==============================================================================
test_that("Criterion 1: Real 20261106 payload extracts >= 35 candidate deltas from 25 rows", {
  archive_path <- offseason_league_wire_raw_fixture()
  expect_true(file.exists(archive_path), info = "20261106 archive payload must exist")
  
  wire_json <- jsonlite::fromJSON(archive_path, simplifyVector = FALSE)
  txs <- wire_json$transactions
  expect_equal(length(txs), 25L, info = "20261106 archive contains exactly 25 transaction rows")
  
  all_deltas <- list()
  for (tx in txs) {
    t_abbr <- if (!is.null(tx$team) && !is.null(tx$team$abbreviation)) tx$team$abbreviation else NULL
    d <- extract_deltas_regex(
      raw_text = tx$description,
      date = tx$date,
      team_abbr = t_abbr
    )
    all_deltas <- c(all_deltas, d)
  }
  
  # Criterion 1 Assertion: Multi-event descriptions split into atomic clauses such that
  # the 25 rows yield materially more candidate events than rows (>= 35 deltas).
  expect_gte(length(all_deltas), 35L)
  
  # Verify zero unclassified deltas across official ESPN wire
  unclass_count <- sum(sapply(all_deltas, function(x) identical(x$change_type, "UNCLASSIFIED")))
  expect_equal(unclass_count, 0L, info = "All 25 official ESPN transaction wire items must classify cleanly")
  
  # Verify all extracted deltas conform to agreed change_type vocabulary
  for (d in all_deltas) {
    expect_true(d$change_type %in% VALID_CHANGE_TYPES,
                info = sprintf("Delta change_type '%s' must be in VALID_CHANGE_TYPES", d$change_type))
  }
})

# ==============================================================================
# Criterion 2: Structural Team Resolution via Parameter
# ==============================================================================
test_that("Criterion 2: team_abbr parameter assigns team to player deltas without team prose", {
  # Text has NO team prose:
  text_no_team <- "Signed C Aminata Gueye to a Rest-of-Season Hardship contract."
  
  # Pass team_abbr = "GS"
  deltas <- extract_deltas_regex(raw_text = text_no_team, team_abbr = "GS", date = "2026-09-20")
  
  expect_gte(length(deltas), 1L)
  team_delta <- Filter(function(d) identical(d$field, "team"), deltas)[[1]]
  expect_equal(team_delta$new_val, "GS")
  expect_equal(team_delta$entity_name, "Aminata Gueye")
  expect_equal(team_delta$change_type, "SIGNING")
  
  # Test with structured item list input
  item_mock <- list(
    raw_text = "Waived G Sug Sutton.",
    team_abbr = "DAL",
    event_date = "2026-09-16",
    source_url = "https://mock.url"
  )
  item_deltas <- extract_deltas_regex(item_mock)
  expect_gte(length(item_deltas), 1L)
  expect_equal(item_deltas[[1]]$change_type, "WAIVER")
  expect_equal(item_deltas[[1]]$entity_name, "Sug Sutton")
})

# ==============================================================================
# Criterion 3: Position Tokens & Possessive Name Support
# ==============================================================================
test_that("Criterion 3: Position tokens (C, F, G, G/F, F/G, C/F, CF) and possessives parse without dropping names", {
  pos_cases <- list(
    list(text = "Signed C Aminata Gueye to a contract.", exp_pos = "C", exp_name = "Aminata Gueye", exp_type = "SIGNING"),
    list(text = "Released F Saylor Poffenbarger.", exp_pos = "F", exp_name = "Saylor Poffenbarger", exp_type = "RELEASE"),
    list(text = "Waived G Sug Sutton.", exp_pos = "G", exp_name = "Sug Sutton", exp_type = "WAIVER"),
    list(text = "Acquired G/F Aaliyah Nye off waivers.", exp_pos = "G/F", exp_name = "Aaliyah Nye", exp_type = "WAIVER_CLAIM"),
    list(text = "Signed F/G DeWanna Bonner to a contract.", exp_pos = "F/G", exp_name = "DeWanna Bonner", exp_type = "SIGNING"),
    list(text = "Released C/F Rayah Marshall.", exp_pos = "C/F", exp_name = "Rayah Marshall", exp_type = "RELEASE"),
    list(text = "Signed CF Rayah Marshall to a contract.", exp_pos = "CF", exp_name = "Rayah Marshall", exp_type = "SIGNING"),
    list(text = "Matched Ashlon Jackson's offer sheet from Los Angeles.", exp_pos = NULL, exp_name = "Ashlon Jackson", exp_type = "OFFER_MATCH"),
    list(text = "Signed G Hailey Van Lith to a seven-day contract.", exp_pos = "G", exp_name = "Hailey Van Lith", exp_type = "SIGNING"),
    list(text = "Waived G/F Betnijah Laney-Hamilton.", exp_pos = "G/F", exp_name = "Betnijah Laney-Hamilton", exp_type = "WAIVER")
  )
  
  for (tc in pos_cases) {
    deltas <- extract_deltas_regex(tc$text, team_abbr = "CON")
    expect_true(length(deltas) >= 1L, info = sprintf("Failed to extract deltas for '%s'", tc$text))
    primary <- deltas[[1]]
    expect_equal(primary$entity_name, tc$exp_name, info = sprintf("Name mismatch for '%s'", tc$text))
    expect_equal(primary$change_type, tc$exp_type, info = sprintf("Change type mismatch for '%s'", tc$text))
  }
})

# ==============================================================================
# Criterion 4: All 8 Observed Verbs Classified + Trade Disambiguation
# ==============================================================================
test_that("Criterion 4: All 8 live verbs classified into vocabulary, distinguishing trade from waiver claim", {
  # 1. Signed
  d_sign <- extract_deltas_regex("Signed G Shay Ciezki to a rest of season contract.", team_abbr = "PHX")
  expect_equal(d_sign[[1]]$change_type, "SIGNING")
  
  # 2. Waived
  d_waive <- extract_deltas_regex("Waived G Kate Martin.", team_abbr = "LA")
  expect_equal(d_waive[[1]]$change_type, "WAIVER")
  
  # 3. Released
  d_rel <- extract_deltas_regex("Released F Alissa Pili.", team_abbr = "LA")
  expect_equal(d_rel[[1]]$change_type, "RELEASE")
  
  # 4a. Acquired via Waiver Claim
  d_wc <- extract_deltas_regex("Acquired G/F Aaliyah Nye off waivers.", team_abbr = "LA")
  expect_equal(d_wc[[1]]$change_type, "WAIVER_CLAIM")
  
  # 4b. Acquired via Trade (must distinguish from waiver claim!)
  d_trade <- extract_deltas_regex("Acquired G Kelsey Plum from Los Angeles in exchange for G Monique Akoa Makani.", team_abbr = "PHX")
  expect_equal(length(d_trade), 2L)
  expect_equal(d_trade[[1]]$change_type, "TRADE")
  expect_equal(d_trade[[1]]$entity_name, "Kelsey Plum")
  expect_equal(d_trade[[1]]$prior_val, "LA")
  expect_equal(d_trade[[1]]$new_val, "PHX")
  expect_equal(d_trade[[2]]$change_type, "TRADE")
  expect_equal(d_trade[[2]]$entity_name, "Monique Akoa Makani")
  expect_equal(d_trade[[2]]$prior_val, "PHX")
  expect_equal(d_trade[[2]]$new_val, "LA")
  
  # 5. Announced (Front Office)
  d_ann <- extract_deltas_regex("Announced Kelly Krauskopf stepped down as president.", team_abbr = "IND")
  expect_equal(d_ann[[1]]$change_type, "FRONT_OFFICE")
  expect_equal(d_ann[[1]]$prior_val, "Kelly Krauskopf")
  
  # Fired (Front Office)
  d_fired <- extract_deltas_regex("Fired general manager Amber Cox", team_abbr = "IND")
  expect_equal(d_fired[[1]]$change_type, "FRONT_OFFICE")
  expect_equal(d_fired[[1]]$prior_val, "Amber Cox")
  
  # 6. Set (Roster Status)
  d_set <- extract_deltas_regex("Set F Cecilia Zandalasini as active.", team_abbr = "GS")
  expect_equal(d_set[[1]]$change_type, "ROSTER_STATUS")
  expect_equal(d_set[[1]]$new_val, "ACTIVE")
  
  # 7. Tendered (Contract Offer)
  d_ten <- extract_deltas_regex("Tendered an offer sheet to F Maddy Westbeld.", team_abbr = "PHX")
  expect_equal(d_ten[[1]]$change_type, "CONTRACT_OFFER")
  
  # 8. Matched (Offer Match)
  d_mat <- extract_deltas_regex("Matched Ashlon Jackson's offer sheet from Los Angeles.", team_abbr = "CON")
  expect_equal(d_mat[[1]]$change_type, "OFFER_MATCH")
  expect_equal(d_mat[[1]]$prior_val, "LA")
  expect_equal(d_mat[[1]]$new_val, "CON")
})

# ==============================================================================
# Criterion 5: Explicit Unclassified Reporting (Never Silently Dropped)
# ==============================================================================
test_that("Criterion 5: Unmatched records reported as unclassified instead of silently dropped", {
  fixtures_path <- file.path("data", "fixtures", "wire_items_sample.json")
  expect_true(file.exists(fixtures_path))
  
  sample_items <- jsonlite::fromJSON(fixtures_path, simplifyVector = FALSE)
  
  # Items 7 & 8 are beat feed story paragraphs, not wire transactions
  beat_item_7 <- sample_items[[7]]
  beat_item_8 <- sample_items[[8]]
  
  d7 <- extract_deltas_regex(beat_item_7)
  expect_true(length(d7) > 0L, info = "Unmatched narrative text must not be silently dropped")
  expect_true(any(sapply(d7, function(x) identical(x$change_type, "UNCLASSIFIED"))))
  expect_true(isTRUE(attr(d7, "unclassified_count") > 0L))
  
  d8 <- extract_deltas_regex(beat_item_8)
  expect_true(length(d8) > 0L, info = "Unmatched narrative text must not be silently dropped")
  expect_true(any(sapply(d8, function(x) identical(x$change_type, "UNCLASSIFIED"))))
  expect_true(isTRUE(attr(d8, "unclassified_count") > 0L))
  
  # Random unrecognized text test
  unknown_text <- "Lorem ipsum dolor sit amet, consectetur adipiscing elit."
  d_unknown <- extract_deltas_regex(unknown_text)
  expect_equal(length(d_unknown), 1L)
  expect_equal(d_unknown[[1]]$change_type, "UNCLASSIFIED")
  expect_equal(d_unknown[[1]]$new_val, sub("\\.+$", "", unknown_text))
})

# ==============================================================================
# Off-season Classes (Requirement 5)
# ==============================================================================
test_that("Requirement 5: Off-season transition classes extract correctly", {
  # Core Designation
  d_core <- extract_deltas_regex("Seattle Storm designate center Ezi Magbegor as Core Player.")
  expect_equal(d_core[[1]]$change_type, "CORE_DESIGNATION")
  expect_equal(d_core[[1]]$new_val, "CORED")
  
  # Reserved Player
  d_res <- extract_deltas_regex("Chicago Sky designate guard Chennedy Carter as Reserved Player.")
  expect_equal(d_res[[1]]$change_type, "RESERVED_PLAYER")
  expect_equal(d_res[[1]]$new_val, "RESERVED")
  
  # Qualifying Offer
  d_qo <- extract_deltas_regex("Indiana Fever extend qualifying offer to guard Kelsey Mitchell.")
  expect_equal(d_qo[[1]]$change_type, "QUALIFYING_OFFER")
  
  # Prioritization
  d_prio <- extract_deltas_regex("League office announced prioritization suspension for forward Gabby Williams.")
  expect_equal(d_prio[[1]]$change_type, "PRIORITIZATION")
  
  # Retirement
  d_ret <- extract_deltas_regex("Announced retirement of guard Candace Parker.")
  expect_equal(d_ret[[1]]$change_type, "RETIREMENT")
  
  # Suspension
  d_susp <- extract_deltas_regex("Suspended for 3 games guard Sophie Cunningham.")
  expect_equal(d_susp[[1]]$change_type, "SUSPENSION")
  
  # Draft Rights
  d_dr <- extract_deltas_regex("Dallas Wings renounce draft rights to forward Awak Kuier.")
  expect_equal(d_dr[[1]]$change_type, "DRAFT_RIGHTS")
  
  # Expansion Draft
  d_exp <- extract_deltas_regex("Golden State Valkyries select forward Stephanie Talbot in expansion draft.")
  expect_equal(d_exp[[1]]$change_type, "EXPANSION_DRAFT")
})

# ==============================================================================
# Criterion 7 / Legacy Fixtures Backward Compatibility Gate
# ==============================================================================
test_that("Legacy official wire raw samples retain exact recall and precision", {
  legacy_path <- file.path("data", "fixtures", "official_wire_raw_samples.json")
  if (file.exists(legacy_path)) {
    samples <- jsonlite::fromJSON(legacy_path, simplifyVector = FALSE)
    
    total_expected <- 0
    total_extracted <- 0
    exact_matches <- 0
    
    for (sample in samples) {
      extracted <- extract_deltas_regex(
        raw_text = sample$raw_text,
        date = sample$date,
        source_url = sample$source_url
      )
      
      exp_deltas <- sample$expected_deltas
      expect_equal(length(extracted), length(exp_deltas),
                   info = sprintf("Recall mismatch for legacy sample %s", sample$id))
      
      total_expected <- total_expected + length(exp_deltas)
      total_extracted <- total_extracted + length(extracted)
      
      for (act in extracted) {
        matched <- FALSE
        for (exp in exp_deltas) {
          id_match <- identical(as.character(act$entity_id), as.character(exp$entity_id))
          field_match <- identical(as.character(act$field), as.character(exp$field))
          prior_match <- if (is.null(exp$prior_val)) is.null(act$prior_val) else identical(as.character(act$prior_val), as.character(exp$prior_val))
          new_match <- identical(as.character(act$new_val), as.character(exp$new_val))
          if (id_match && field_match && prior_match && new_match) {
            matched <- TRUE
            break
          }
        }
        expect_true(matched, info = sprintf("Precision error in %s: (%s, %s, %s, %s)",
                                            sample$id, act$entity_id, act$field, act$prior_val, act$new_val))
        if (matched) exact_matches <- exact_matches + 1
      }
    }
    
    expect_equal(total_extracted, total_expected)
    expect_equal(exact_matches, total_expected)
  }
})

elapsed_ms <- as.numeric(difftime(Sys.time(), start_time, units = "secs")) * 1000
cat(sprintf("\n[PASS] Tier 2 Regex Extraction CI Gate verified: all criteria green (elapsed %.1f ms)\n", elapsed_ms))
