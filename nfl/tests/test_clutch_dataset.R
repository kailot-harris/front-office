# ==============================================================================
# tests/test_clutch_dataset.R
# Offline unit tests for build_clutch_dataset.R (NFL_analytics#168):
#   1. QB scrambles (qb_scramble == 1, passer_player_id = NA, matched on
#      rusher_player_id / rusher_player_name) are included in baseline and
#      clutch EPA/plays while keeping pass_attempt == 1 pass-attempts-only.
#   2. Designed runs (qb_scramble == 0) and different-ID rushers are excluded.
#   3. fourthDownConversionRate computes converted / total 4th-down QB plays
#      and emits NA_real_ (JSON null) when 0 4th-down plays exist, replacing
#      the misleading fourthDownAggressiveness field and 50.0 fallback.
#
# Runs via:
#   Rscript tests/test_clutch_dataset.R
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
})

root_dir <- if (file.exists("config.R")) {
  getwd()
} else if (file.exists("../config.R")) {
  normalizePath("..", winslash = "/")
} else {
  getwd()
}

source(file.path(root_dir, "config.R"))

failures <- 0L
ok <- function(label, cond, detail = NULL) {
  if (isTRUE(cond)) {
    cat(sprintf("[PASS] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
  } else {
    cat(sprintf("[FAIL] %s%s\n", label, if (!is.null(detail)) paste0("  -- ", detail) else ""))
    failures <<- failures + 1L
  }
}

load_ast_symbols <- function(path, symbols, env) {
  exprs <- parse(file = path, keep.source = FALSE)
  for (e in exprs) {
    if (is.call(e) && length(e) >= 3L &&
        as.character(e[[1L]]) %in% c("<-", "=") &&
        is.symbol(e[[2L]]) &&
        as.character(e[[2L]]) %in% symbols) {
      eval(e, envir = env)
    }
  }
  env
}

CLUTCH_ENV <- new.env(parent = globalenv())
CLUTCH_ENV$CURRENT_SEASON <- CURRENT_SEASON
load_ast_symbols(
  file.path(root_dir, "build_clutch_dataset.R"),
  c("is_flag_one", "add_clutch_flag", "extract_qb_clutch_plays", "compute_qb_clutch_profile"),
  CLUTCH_ENV
)

make_pbp_rows <- function(n, ...) {
  df <- data.frame(
    qtr = rep(2L, n),
    score_differential = rep(14L, n),
    half_seconds_remaining = rep(900L, n),
    wp = rep(0.50, n),
    down = rep(1L, n),
    pass = rep(1L, n),
    qb_dropback = rep(1L, n),
    pass_attempt = rep(1L, n),
    qb_scramble = rep(0L, n),
    passer_player_id = rep(NA_character_, n),
    passer_player_name = rep(NA_character_, n),
    rusher_player_id = rep(NA_character_, n),
    rusher_player_name = rep(NA_character_, n),
    epa = rep(0.0, n),
    success = rep(0L, n),
    cpoe = rep(NA_real_, n),
    interception = rep(0L, n),
    fumble_lost = rep(0L, n),
    fourth_down_converted = rep(NA_integer_, n),
    stringsAsFactors = FALSE
  )
  overrides <- list(...)
  for (nm in names(overrides)) {
    df[[nm]] <- overrides[[nm]]
  }
  df
}

cat("=== NFL Analytics Clutch Dataset Unit Tests (#168) ===\n\n")

gid <- "00-0034857"
pname <- "Josh Allen"

# 20 clutch pass attempts + 10 non-clutch baseline pass attempts
clutch_passes <- make_pbp_rows(
  20L,
  qtr = 4L,
  score_differential = 3L,
  half_seconds_remaining = 120L,
  wp = 0.45,
  down = 2L,
  passer_player_id = gid,
  passer_player_name = "J.Allen",
  epa = 0.10,
  success = 1L,
  cpoe = 4.0
)

base_passes <- make_pbp_rows(
  10L,
  qtr = 2L,
  score_differential = 14L,
  down = 1L,
  passer_player_id = gid,
  passer_player_name = "J.Allen",
  epa = 0.00,
  success = 0L,
  cpoe = 1.0
)

# 1 clutch scramble + 1 non-clutch scramble (passer_player_id = NA, matched via rusher_player_id)
clutch_scramble <- make_pbp_rows(
  1L,
  qtr = 4L,
  score_differential = -4L,
  half_seconds_remaining = 90L,
  wp = 0.40,
  down = 3L,
  pass = 1L,
  qb_dropback = 1L,
  pass_attempt = 0L,
  qb_scramble = 1L,
  passer_player_id = NA_character_,
  passer_player_name = NA_character_,
  rusher_player_id = gid,
  rusher_player_name = NA_character_,
  epa = 2.20,
  success = 1L,
  cpoe = NA_real_
)

base_scramble <- make_pbp_rows(
  1L,
  qtr = 1L,
  score_differential = 0L,
  down = 2L,
  pass = 1L,
  qb_dropback = 1L,
  pass_attempt = 0L,
  qb_scramble = 1L,
  passer_player_id = NA_character_,
  passer_player_name = NA_character_,
  rusher_player_id = gid,
  rusher_player_name = NA_character_,
  epa = 1.60,
  success = 1L,
  cpoe = NA_real_
)

# Distractors: designed run (qb_scramble == 0) + different-ID player sharing abbr_name
designed_run <- make_pbp_rows(
  1L,
  qtr = 4L,
  score_differential = 3L,
  down = 4L,
  pass = 0L,
  qb_dropback = 0L,
  pass_attempt = 0L,
  qb_scramble = 0L,
  rusher_player_id = gid,
  rusher_player_name = "J.Allen",
  epa = -5.0,
  fourth_down_converted = 0L
)

other_player_scramble <- make_pbp_rows(
  1L,
  qtr = 4L,
  score_differential = 3L,
  down = 4L,
  pass = 1L,
  qb_dropback = 1L,
  pass_attempt = 0L,
  qb_scramble = 1L,
  rusher_player_id = "00-9999999",
  rusher_player_name = "J.Allen",
  epa = -5.0,
  fourth_down_converted = 0L
)

pbp_with_scrambles <- rbind(
  clutch_passes,
  base_passes,
  clutch_scramble,
  base_scramble,
  designed_run,
  other_player_scramble
)

prof_scramble <- CLUTCH_ENV$compute_qb_clutch_profile(
  pbp = pbp_with_scrambles,
  pname = pname,
  pteam = "BUF",
  gid = gid,
  season = CURRENT_SEASON,
  through_week = 10L
)

expected_c_epa <- round((20 * 0.10 + 2.20) / 21, 3)
expected_b_epa <- round((20 * 0.10 + 10 * 0.00 + 2.20 + 1.60) / 32, 3)
expected_delta <- round(expected_c_epa - expected_b_epa, 3)

ok("SCRAMBLE-1 Pass attempts exclude scrambles while dropbacks/plays include them",
   prof_scramble$clutchAttempts == 20L &&
     prof_scramble$baselineAttempts == 30L &&
     prof_scramble$clutchPlays == 21L &&
     prof_scramble$baselinePlays == 32L,
   sprintf("clutchAtt=%d, clutchPlays=%d, baseAtt=%d, basePlays=%d",
           prof_scramble$clutchAttempts, prof_scramble$clutchPlays,
           prof_scramble$baselineAttempts, prof_scramble$baselinePlays))

ok("SCRAMBLE-2 Clutch and baseline EPA include qb_scramble == 1 (passer_player_id = NA, rusher_player_id = gid)",
   identical(prof_scramble$clutchEpa, expected_c_epa) &&
     identical(prof_scramble$baselineEpa, expected_b_epa) &&
     identical(prof_scramble$clutchEpaDelta, expected_delta) &&
     identical(prof_scramble$clutchCpoe, 4.0),
   sprintf("clutchEpa=%.3f (exp %.3f), baseEpa=%.3f (exp %.3f), cpoe=%.1f",
           prof_scramble$clutchEpa, expected_c_epa,
           prof_scramble$baselineEpa, expected_b_epa,
           prof_scramble$clutchCpoe))

# Name-fallback scramble test (rusher_player_id = NA, gid = NULL)
name_scramble <- make_pbp_rows(
  1L,
  qtr = 4L,
  score_differential = 2L,
  pass = 1L,
  qb_dropback = 1L,
  pass_attempt = 0L,
  qb_scramble = 1L,
  rusher_player_id = NA_character_,
  rusher_player_name = "J.Allen",
  epa = 1.50,
  success = 1L
)
pbp_name_only <- rbind(clutch_passes, name_scramble)
prof_name <- CLUTCH_ENV$compute_qb_clutch_profile(
  pbp = pbp_name_only,
  pname = pname,
  pteam = "BUF",
  gid = NULL,
  season = CURRENT_SEASON,
  through_week = 10L
)
ok("SCRAMBLE-3 Scramble matches via rusher_player_name when gid / rusher_player_id are absent",
   prof_name$clutchAttempts == 20L &&
     prof_name$clutchPlays == 21L &&
     identical(prof_name$clutchEpa, round((20 * 0.10 + 1.50) / 21, 3)),
   sprintf("clutchPlays=%d, clutchEpa=%.3f", prof_name$clutchPlays, prof_name$clutchEpa))

# 4th-down conversion tests:
# 0 fourth-down plays -> NA_real_ (not fabricated 50.0) and JSON null
ok("FOURTH-1 Zero 4th-down plays emits NA_real_ instead of 50.0, and omits fourthDownAggressiveness",
   identical(prof_scramble$fourthDownConversionRate, NA_real_) &&
     !("fourthDownAggressiveness" %in% names(prof_scramble)),
   sprintf("fourthDownConversionRate=%s", as.character(prof_scramble$fourthDownConversionRate)))

json_zero_4th <- jsonlite::toJSON(prof_scramble, na = "null", auto_unbox = TRUE)
ok("FOURTH-2 Zero 4th-down plays serializes fourthDownConversionRate as JSON null",
   grepl('"fourthDownConversionRate":null', json_zero_4th, fixed = TRUE) &&
     !grepl("fourthDownAggressiveness", json_zero_4th, fixed = TRUE),
   "JSON contains \"fourthDownConversionRate\":null")

# 3 fourth-down plays (2 passes + 1 scramble, 2 converted -> 66.7%)
fourth_passes <- make_pbp_rows(
  2L,
  qtr = 2L,
  down = 4L,
  passer_player_id = gid,
  passer_player_name = "J.Allen",
  epa = 0.5,
  success = c(1L, 0L),
  fourth_down_converted = c(1L, 0L)
)
fourth_scramble <- make_pbp_rows(
  1L,
  qtr = 4L,
  score_differential = -3L,
  down = 4L,
  pass = 1L,
  qb_dropback = 1L,
  pass_attempt = 0L,
  qb_scramble = 1L,
  rusher_player_id = gid,
  epa = 1.8,
  success = 1L,
  fourth_down_converted = 1L
)
pbp_with_4th <- rbind(clutch_passes, base_passes, fourth_passes, fourth_scramble)
prof_4th <- CLUTCH_ENV$compute_qb_clutch_profile(
  pbp = pbp_with_4th,
  pname = pname,
  pteam = "BUF",
  gid = gid,
  season = CURRENT_SEASON,
  through_week = 10L
)
ok("FOURTH-3 4th-down conversion rate includes 4th-down scrambles and rounds to 1 decimal (2/3 -> 66.7)",
   identical(prof_4th$fourthDownConversionRate, 66.7),
   sprintf("fourthDownConversionRate=%.1f", prof_4th$fourthDownConversionRate))

# Low-sample (< 20 clutch attempts) -> INSUFFICIENT_SAMPLE & NA_real_
prof_low <- CLUTCH_ENV$compute_qb_clutch_profile(
  pbp = base_passes,
  pname = pname,
  pteam = "BUF",
  gid = gid,
  season = CURRENT_SEASON,
  through_week = 10L
)
ok("SAMPLE-1 Insufficient sample (< 20 clutch attempts) emits INSUFFICIENT_SAMPLE and NA_real_ conversion rate",
   identical(prof_low$provenance, "INSUFFICIENT_SAMPLE") &&
     identical(prof_low$fourthDownConversionRate, NA_real_) &&
     identical(prof_low$clutchEpa, NA_real_),
   sprintf("provenance=%s", prof_low$provenance))

cat(sprintf("\n=== %s: %d failure(s) ===\n",
            if (failures == 0L) "ALL TESTS PASSED" else "TEST FAILURES", failures))
quit(status = if (failures == 0L) 0L else 1L)
