# ==============================================================================
# tests/test_cba_cap_no_synthetic_fallback.R
# Path: tests/test_cba_cap_no_synthetic_fallback.R
#
# Regression coverage for #75:
#   1. build_cba_cap_dataset.R must NOT contain FALLBACK_team_payrolls,
#      FALLBACK_verified_contracts, or the proportional-fill salary generator
#      (0.27 / 0.22 / ...).
#   2. When BBRef caches are missing, build_cba_cap_dataset.R must emit NA
#      (JSON null) for payroll/tax/tier fields, empty contracts (`[]`) for
#      every team, and explicit UNAVAILABLE provenance with a reason in
#      `cbaThresholdSources` -- never hardcoded Spotrac numbers.
#   3. When BBRef team payrolls exist but bbref_player_contracts.rds is missing,
#      contracts must remain empty (`[]`) with no proportional-fill synthesis.
#
# Runs against isolated temp CACHE_DIR and temp output JSON so committed
# web/public/data/cba_cap_sheet.json is never mutated.
#
# Usage: Rscript tests/test_cba_cap_no_synthetic_fallback.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (file.exists(file.path(base, "build_cba_cap_dataset.R"))) {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  } else if (file.exists(file.path(base, "..", "build_cba_cap_dataset.R"))) {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    getwd()
  }
})

cat("=== CBA Cap No-Synthetic-Fallback Test Suite (#75) ===\n")
script_path <- file.path(REPO_ROOT, "build_cba_cap_dataset.R")
stopifnot(file.exists(script_path))

# ------------------------------------------------------------------------------
# Test 1: Static source check -- fallback tables and proportional-fill gone
# ------------------------------------------------------------------------------
src_text <- paste(readLines(script_path, warn = FALSE), collapse = "\n")
stopifnot(!grepl("FALLBACK_team_payrolls", src_text, fixed = TRUE))
stopifnot(!grepl("FALLBACK_verified_contracts", src_text, fixed = TRUE))
stopifnot(!grepl("payroll * 0.27", src_text, fixed = TRUE))
stopifnot(!grepl("Proportional Fill", src_text, fixed = TRUE))
cat("  PASS: Static source check confirms Spotrac and proportional-fill fallbacks removed.\n")

# Helper: execute build_cba_cap_dataset.R in an isolated sandbox pointing to
# a custom temp cache_dir and temp output_json.
run_cba_builder_isolated <- function(cache_dir, output_json) {
  old_wd <- setwd(REPO_ROOT)
  on.exit(setwd(old_wd), add = TRUE)

  exprs <- parse(script_path)
  sandbox <- new.env(parent = globalenv())
  for (e in exprs) {
    call_text <- paste(deparse(e), collapse = " ")
    eval(e, envir = sandbox)
    if (grepl("source\\(config_path\\)", call_text)) {
      assign("CACHE_DIR", cache_dir, envir = sandbox)
      assign("WEB_JSON_CBA_CAP_SHEET", output_json, envir = sandbox)
    }
  }
  sandbox
}

# ------------------------------------------------------------------------------
# Test 2: Both BBRef caches missing -> explicit null/empty + UNAVAILABLE reason
# ------------------------------------------------------------------------------
tmp_dir_1 <- tempfile("cba_no_cache_")
dir.create(tmp_dir_1, recursive = TRUE)
tmp_json_1 <- tempfile("cba_out_1_", fileext = ".json")
on.exit(unlink(c(tmp_dir_1, tmp_json_1), recursive = TRUE, force = TRUE), add = TRUE)

sb1 <- run_cba_builder_isolated(tmp_dir_1, tmp_json_1)
stopifnot(file.exists(tmp_json_1))
stopifnot(!isTRUE(get("team_payrolls_sourced_from_bbref", envir = sb1)))
stopifnot(!isTRUE(get("verified_contracts_sourced_from_bbref", envir = sb1)))

payload1 <- fromJSON(tmp_json_1, simplifyVector = FALSE)
stopifnot(length(payload1$teams) == 30L)
stopifnot(is.null(payload1$averagePayroll))
stopifnot(is.null(payload1$totalLeagueTaxRevenue))
stopifnot(is.null(payload1$secondApronTeamCount))
stopifnot(is.null(payload1$firstApronTeamCount))
stopifnot(is.null(payload1$taxTeamCount))
stopifnot(is.null(payload1$capRoomTeamCount))
stopifnot(grepl("UNAVAILABLE", payload1$cbaThresholdSources, fixed = TRUE))
stopifnot(!grepl("Spotrac snapshot", payload1$cbaThresholdSources, fixed = TRUE))

for (tm in payload1$teams) {
  stopifnot(is.null(tm$totalPayroll2026))
  stopifnot(is.null(tm$totalPayroll2027))
  stopifnot(is.null(tm$totalPayroll2028))
  stopifnot(is.null(tm$luxuryTaxBill))
  stopifnot(is.null(tm$totalFinancialCommitment))
  stopifnot(is.null(tm$cbaTier))
  stopifnot(length(tm$contracts) == 0L)
}
cat("  PASS: Missing BBRef caches emit null payrolls, empty contracts, and UNAVAILABLE provenance.\n")

# ------------------------------------------------------------------------------
# Test 3: Payroll cache present, contracts cache missing -> empty contracts []
# ------------------------------------------------------------------------------
tmp_dir_2 <- tempfile("cba_payroll_only_")
dir.create(tmp_dir_2, recursive = TRUE)
tmp_json_2 <- tempfile("cba_out_2_", fileext = ".json")
on.exit(unlink(c(tmp_dir_2, tmp_json_2), recursive = TRUE, force = TRUE), add = TRUE)

teams_ref <- get("NBA_TEAMS_REF", envir = sb1)
fake_bbref_payroll <- data.frame(
  team_abbr = teams_ref$team_abbr,
  active_roster_salary_total = rep(180e6, nrow(teams_ref)),
  stringsAsFactors = FALSE
)
saveRDS(fake_bbref_payroll, file.path(tmp_dir_2, "bbref_team_payroll_active_roster.rds"))

sb2 <- run_cba_builder_isolated(tmp_dir_2, tmp_json_2)
stopifnot(isTRUE(get("team_payrolls_sourced_from_bbref", envir = sb2)))
stopifnot(!isTRUE(get("verified_contracts_sourced_from_bbref", envir = sb2)))

payload2 <- fromJSON(tmp_json_2, simplifyVector = FALSE)
stopifnot(length(payload2$teams) == 30L)
stopifnot(identical(as.numeric(payload2$averagePayroll), 180))
stopifnot(grepl("Per-player contract rows: UNAVAILABLE", payload2$cbaThresholdSources, fixed = TRUE))
for (tm in payload2$teams) {
  stopifnot(identical(as.numeric(tm$totalPayroll2026), 180))
  stopifnot(length(tm$contracts) == 0L)
}
cat("  PASS: Missing contracts cache emits empty contracts [] (no proportional-fill synthesis).\n")
cat("=== ALL CBA NO-SYNTHETIC-FALLBACK TESTS PASSED ===\n")
