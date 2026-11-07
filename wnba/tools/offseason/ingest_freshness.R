# ==============================================================================
# ingest_freshness.R
# WNBA Offseason Dynamics Monitor — Ingestion Freshness & Gate Evaluation (Issue #163)
#
# Provides fail-closed gate evaluation for weekly ingestion manifests:
#   1. Freshness: Blocks on absent, unparseable, or stale timestamps (> max_age_hours).
#   2. Volume: Blocks when composite health is HEALTHY or DEGRADED but items == 0.
#   3. Status: Strictly validates status enums (HEALTHY, DEGRADED, FAILED); never defaults.
#   4. Earned-zero predicate: can_assert_quiet_week() requires fresh, healthy/degraded ingest,
#      non-zero items, and zero confirmed state transitions.
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

# Ensure user library is accessible even when running inside an isolated renv sandbox
user_lib <- Sys.getenv("R_LIBS_USER")
if (nzchar(user_lib) && dir.exists(user_lib) && !(user_lib %in% .libPaths())) {
  .libPaths(c(.libPaths(), user_lib))
} else {
  default_user_lib <- file.path(Sys.getenv("LOCALAPPDATA", file.path(Sys.getenv("USERPROFILE"), "AppData", "Local")), "R", "win-library", "4.5")
  if (dir.exists(default_user_lib) && !(default_user_lib %in% .libPaths())) {
    .libPaths(c(.libPaths(), default_user_lib))
  }
}

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    warning("jsonlite package not available; some JSON helper features may be limited.")
  }
})

# ------------------------------------------------------------------------------
# Constants
# ------------------------------------------------------------------------------
VALID_HEALTH_STATUSES <- c("HEALTHY", "DEGRADED", "FAILED")
DEFAULT_MAX_AGE_HOURS <- 168  # 7 days for weekly cadence

# ------------------------------------------------------------------------------
# Helper: Parse ISO 8601 Timestamps
# ------------------------------------------------------------------------------
#' Safely parse an ISO 8601 timestamp string into POSIXct (UTC)
#'
#' @param ts_str Character representation of timestamp or POSIXt object
#' @return POSIXct object in UTC, or NA POSIXct if unparseable
parse_iso_timestamp <- function(ts_str) {
  if (is.null(ts_str) || length(ts_str) == 0) {
    return(as.POSIXct(NA))
  }
  if (inherits(ts_str, "POSIXt")) {
    return(as.POSIXct(ts_str, tz = "UTC"))
  }
  if (!is.character(ts_str)) {
    ts_str <- as.character(ts_str)
  }
  raw_val <- trimws(ts_str[1])
  if (!nzchar(raw_val) || is.na(raw_val)) {
    return(as.POSIXct(NA))
  }

  safe_parse <- function(expr) {
    tryCatch({
      suppressWarnings(expr)
    }, error = function(e) as.POSIXct(NA))
  }

  # 1. Standard ISO UTC: 2026-11-06T23:59:00Z
  t <- safe_parse(as.POSIXct(raw_val, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"))
  if (!is.na(t)) return(t)

  # 2. ISO UTC with fractional seconds: 2026-11-06T23:59:00.123Z
  t <- safe_parse(as.POSIXct(raw_val, format = "%Y-%m-%dT%H:%M:%OSZ", tz = "UTC"))
  if (!is.na(t)) return(t)

  # 3. ISO with timezone offset: e.g. 2026-11-06T18:59:00-05:00 or +00:00
  # %z expects -0500 format without colon
  raw_norm <- sub("([+-]\\d{2}):(\\d{2})$", "\\1\\2", raw_val)
  t <- safe_parse(as.POSIXct(strptime(raw_norm, format = "%Y-%m-%dT%H:%M:%S%z", tz = "UTC")))
  if (!is.na(t)) return(as.POSIXct(t, tz = "UTC"))

  # 4. Standard SQL datetime: 2026-11-06 23:59:00
  t <- safe_parse(as.POSIXct(raw_val, format = "%Y-%m-%d %H:%M:%S", tz = "UTC"))
  if (!is.na(t)) return(t)

  # 5. ISO without Z or offset: 2026-11-06T23:59:00
  t <- safe_parse(as.POSIXct(raw_val, format = "%Y-%m-%dT%H:%M:%S", tz = "UTC"))
  if (!is.na(t)) return(t)

  # 6. Fallback generic parsing
  t <- safe_parse(as.POSIXct(raw_val, tz = "UTC"))
  if (!is.na(t)) {
    # Guard against date-only truncation (e.g., "invalid 2026-11-06")
    if (nchar(raw_val) >= 10 && grepl("^\\d{4}-\\d{2}-\\d{2}", raw_val)) {
      return(t)
    }
  }

  as.POSIXct(NA)
}

# ------------------------------------------------------------------------------
# Helper: Load and Coerce Manifest
# ------------------------------------------------------------------------------
#' Ensure manifest is parsed into an R list
#'
#' @param manifest List or filepath to JSON manifest
#' @return List representation of manifest, or NULL
coerce_manifest <- function(manifest) {
  if (is.null(manifest)) return(NULL)
  if (is.list(manifest)) return(manifest)
  if (is.character(manifest) && length(manifest) == 1) {
    if (file.exists(manifest)) {
      parsed <- tryCatch({
        jsonlite::fromJSON(manifest, simplifyVector = FALSE)
      }, error = function(e) NULL)
      return(parsed)
    }
    # Check if raw JSON string
    if (grepl("^\\s*\\{", manifest)) {
      parsed <- tryCatch({
        jsonlite::fromJSON(manifest, simplifyVector = FALSE)
      }, error = function(e) NULL)
      return(parsed)
    }
  }
  NULL
}

# ------------------------------------------------------------------------------
# Helper: Extract Total Items Count
# ------------------------------------------------------------------------------
#' Extract or calculate total volume of ingested items from manifest
#'
#' @param manifest List representation of manifest
#' @return Integer total items count
extract_manifest_items_count <- function(manifest) {
  if (is.null(manifest) || !is.list(manifest)) return(0L)

  # Explicit top-level fields
  if (!is.null(manifest$total_items) && is.numeric(manifest$total_items)) {
    return(max(0L, as.integer(manifest$total_items[1])))
  }
  if (!is.null(manifest$item_count) && is.numeric(manifest$item_count)) {
    return(max(0L, as.integer(manifest$item_count[1])))
  }
  if (!is.null(manifest$items_count) && is.numeric(manifest$items_count)) {
    return(max(0L, as.integer(manifest$items_count[1])))
  }
  if (!is.null(manifest$items) && (is.list(manifest$items) || is.data.frame(manifest$items))) {
    return(if (is.data.frame(manifest$items)) nrow(manifest$items) else length(manifest$items))
  }

  # Aggregate adapter counts
  if (!is.null(manifest$adapters) && is.list(manifest$adapters)) {
    total <- 0L
    for (ad in manifest$adapters) {
      if (!is.list(ad)) next
      if (!is.null(ad$items_found) && is.numeric(ad$items_found)) {
        total <- total + as.integer(ad$items_found[1])
      } else if (!is.null(ad$claims_found) && is.numeric(ad$claims_found)) {
        total <- total + as.integer(ad$claims_found[1])
      } else if (!is.null(ad$items_count) && is.numeric(ad$items_count)) {
        total <- total + as.integer(ad$items_count[1])
      } else if (!is.null(ad$item_count) && is.numeric(ad$item_count)) {
        total <- total + as.integer(ad$item_count[1])
      }
    }
    return(max(0L, total))
  }

  0L
}

# ------------------------------------------------------------------------------
# 1. Freshness Check: check_ingest_freshness()
# ------------------------------------------------------------------------------
#' Validate ingest timestamp staleness
#'
#' Blocks on absent, unparseable, or stale timestamps older than max_age_hours.
#'
#' @param manifest List or file path to manifest JSON
#' @param max_age_hours Maximum allowable manifest age in hours (default: 168)
#' @param now POSIXct or ISO string reference time (default: Sys.time())
#' @return List containing:
#'   - fresh: logical (TRUE if fresh)
#'   - allowed: logical (TRUE if fresh)
#'   - age_hours: numeric age in hours
#'   - timestamp: character raw timestamp string
#'   - reason: character diagnostic explanation
check_ingest_freshness <- function(manifest,
                                   max_age_hours = DEFAULT_MAX_AGE_HOURS,
                                   now = Sys.time()) {
  m <- coerce_manifest(manifest)
  if (is.null(m)) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = NA_real_,
      timestamp = NA_character_,
      reason = "Manifest is NULL, invalid, or unreadable."
    ))
  }

  ts_raw <- m$ingest_timestamp
  if (is.null(ts_raw) || length(ts_raw) == 0) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = NA_real_,
      timestamp = NA_character_,
      reason = "Freshness check failed: ingest_timestamp is absent from manifest."
    ))
  }

  ts_raw_str <- trimws(as.character(ts_raw)[1])
  if (!nzchar(ts_raw_str) || is.na(ts_raw_str)) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = NA_real_,
      timestamp = ts_raw_str,
      reason = "Freshness check failed: ingest_timestamp is empty or NA."
    ))
  }

  parsed_ts <- parse_iso_timestamp(ts_raw_str)
  if (is.na(parsed_ts)) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = NA_real_,
      timestamp = ts_raw_str,
      reason = sprintf("Freshness check failed: ingest_timestamp '%s' is unparseable.", ts_raw_str)
    ))
  }

  parsed_now <- parse_iso_timestamp(now)
  if (is.na(parsed_now)) {
    parsed_now <- as.POSIXct(Sys.time(), tz = "UTC")
  }

  age_hours <- as.numeric(difftime(parsed_now, parsed_ts, units = "hours"))

  # Clock drift / future guard (> 1.0 hour in future)
  if (!is.na(age_hours) && age_hours < -1.0) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = age_hours,
      timestamp = ts_raw_str,
      reason = sprintf("Freshness check failed: ingest_timestamp '%s' is %.2f hours in the future.",
                       ts_raw_str, abs(age_hours))
    ))
  }

  if (age_hours > max_age_hours) {
    return(list(
      fresh = FALSE,
      allowed = FALSE,
      age_hours = age_hours,
      timestamp = ts_raw_str,
      reason = sprintf("Freshness check failed: manifest is stale (%.2f hours old, max allowed: %.2f hours, timestamp: '%s').",
                       age_hours, as.numeric(max_age_hours), ts_raw_str)
    ))
  }

  list(
    fresh = TRUE,
    allowed = TRUE,
    age_hours = age_hours,
    timestamp = ts_raw_str,
    reason = sprintf("Ingest timestamp '%s' is fresh (%.2f hours old, max: %.2f hours).",
                     ts_raw_str, age_hours, as.numeric(max_age_hours))
  )
}

# ------------------------------------------------------------------------------
# 2. Volume Check: check_ingest_volume()
# ------------------------------------------------------------------------------
#' Enforce non-zero volume gate on healthy/degraded ingest
#'
#' Blocks when composite health is HEALTHY or DEGRADED but total items count is zero.
#' Strictly verifies status enum and never defaults to HEALTHY.
#'
#' @param manifest List or file path to manifest JSON
#' @return List containing:
#'   - valid: logical (TRUE if non-zero volume or acceptable condition)
#'   - allowed: logical
#'   - total_items: integer count of items ingested
#'   - composite_health: character status enum
#'   - reason: character diagnostic explanation
check_ingest_volume <- function(manifest) {
  m <- coerce_manifest(manifest)
  if (is.null(m)) {
    return(list(
      valid = FALSE,
      allowed = FALSE,
      total_items = 0L,
      composite_health = NA_character_,
      reason = "Manifest is NULL, invalid, or unreadable."
    ))
  }

  health_raw <- m$composite_health
  health <- if (!is.null(health_raw) && length(health_raw) > 0) as.character(health_raw)[1] else NA_character_

  # Strict status enum verification — never default to HEALTHY
  if (is.na(health) || !(health %in% VALID_HEALTH_STATUSES)) {
    return(list(
      valid = FALSE,
      allowed = FALSE,
      total_items = extract_manifest_items_count(m),
      composite_health = health,
      reason = sprintf("Status verification failed: invalid composite_health '%s'. Expected one of: %s.",
                       as.character(health), paste(VALID_HEALTH_STATUSES, collapse = ", "))
    ))
  }

  total_items <- extract_manifest_items_count(m)

  # Zero volume gate: blocks when composite health is HEALTHY or DEGRADED but total items is 0
  if (total_items == 0L) {
    if (health %in% c("HEALTHY", "DEGRADED")) {
      return(list(
        valid = FALSE,
        allowed = FALSE,
        total_items = 0L,
        composite_health = health,
        reason = sprintf("Zero-volume gate blocked: composite_health is %s but total items count is 0.", health)
      ))
    } else {
      # FAILED
      return(list(
        valid = FALSE,
        allowed = FALSE,
        total_items = 0L,
        composite_health = health,
        reason = "Volume check failed: composite_health is FAILED with 0 items captured."
      ))
    }
  }

  list(
    valid = TRUE,
    allowed = TRUE,
    total_items = total_items,
    composite_health = health,
    reason = sprintf("Volume check passed: %d items captured (composite_health=%s).", total_items, health)
  )
}

# ------------------------------------------------------------------------------
# 3. Earned-Zero Predicate: can_assert_quiet_week()
# ------------------------------------------------------------------------------
#' Evaluates whether a quiet week can be programmatically asserted
#'
#' Requires:
#'   1. Ingest timestamp is fresh (<= max_age_hours).
#'   2. Composite health is acceptable (HEALTHY or DEGRADED; FAILED prohibited).
#'   3. Non-zero items were ingested across feeds.
#'   4. Zero confirmed state transitions occurred (earned-zero).
#'
#' @param manifest List or file path to manifest JSON
#' @param confirmed_changes Integer count, list, or data frame of confirmed state deltas
#' @param max_age_hours Maximum allowable manifest age in hours (default: 168)
#' @param now Reference timestamp (default: Sys.time())
#' @return Logical TRUE if quiet week assertion is earned, FALSE otherwise
can_assert_quiet_week <- function(manifest,
                                  confirmed_changes = 0,
                                  max_age_hours = DEFAULT_MAX_AGE_HOURS,
                                  now = Sys.time()) {
  m <- coerce_manifest(manifest)
  if (is.null(m)) return(FALSE)

  # 1. Freshness check
  fresh_res <- check_ingest_freshness(m, max_age_hours = max_age_hours, now = now)
  if (!isTRUE(fresh_res$fresh)) return(FALSE)

  # 2. Strict status enum and acceptable health verification
  health_raw <- m$composite_health
  health <- if (!is.null(health_raw) && length(health_raw) > 0) as.character(health_raw)[1] else NA_character_
  if (is.na(health) || !(health %in% c("HEALTHY", "DEGRADED"))) {
    return(FALSE)
  }

  # 3. Non-zero volume check
  vol_res <- check_ingest_volume(m)
  if (!isTRUE(vol_res$valid) || vol_res$total_items <= 0L) {
    return(FALSE)
  }

  # 4. Confirmed changes count must be zero
  n_changes <- if (is.data.frame(confirmed_changes)) {
    nrow(confirmed_changes)
  } else if (is.list(confirmed_changes)) {
    length(confirmed_changes)
  } else if (is.numeric(confirmed_changes)) {
    as.integer(confirmed_changes[1])
  } else if (is.null(confirmed_changes)) {
    0L
  } else {
    length(confirmed_changes)
  }

  if (is.na(n_changes) || n_changes != 0L) {
    return(FALSE)
  }

  TRUE
}

# ------------------------------------------------------------------------------
# 4. Top-Level Gate Evaluator: evaluate_ingestion_gate()
# ------------------------------------------------------------------------------
#' Top-level fail-closed ingestion gate evaluation
#'
#' Orchestrates freshness check, volume gate, strict status enum verification,
#' and publication permission policy.
#'
#' @param manifest List or file path to manifest JSON
#' @param allow_degraded Logical override allowing degraded/failed runs with frozen promotion
#' @param max_age_hours Maximum allowable manifest age in hours (default: 168)
#' @param now Reference timestamp (default: Sys.time())
#' @return List containing:
#'   - allowed: logical (whether publication is permitted)
#'   - advisory: logical (whether advisory banner is required)
#'   - promotion_frozen: logical (whether baseline state promotion is prohibited)
#'   - reason: character diagnostic explanation
#'   - composite_health: character status enum
#'   - freshness: list from check_ingest_freshness()
#'   - volume: list from check_ingest_volume()
evaluate_ingestion_gate <- function(manifest,
                                    allow_degraded = FALSE,
                                    max_age_hours = DEFAULT_MAX_AGE_HOURS,
                                    now = Sys.time()) {
  m <- coerce_manifest(manifest)
  if (is.null(m)) {
    return(list(
      allowed = FALSE,
      advisory = FALSE,
      promotion_frozen = TRUE,
      reason = "Publication blocked: Manifest is NULL, unreadable, or invalid JSON.",
      composite_health = NA_character_,
      freshness = NULL,
      volume = NULL
    ))
  }

  # Strict status verification — never default to HEALTHY
  health_raw <- m$composite_health
  health <- if (!is.null(health_raw) && length(health_raw) > 0) as.character(health_raw)[1] else NA_character_
  if (is.na(health) || !(health %in% VALID_HEALTH_STATUSES)) {
    return(list(
      allowed = FALSE,
      advisory = FALSE,
      promotion_frozen = TRUE,
      reason = sprintf("Publication blocked: Invalid or missing composite_health '%s'. Expected HEALTHY, DEGRADED, or FAILED.",
                       as.character(health)),
      composite_health = health,
      freshness = NULL,
      volume = NULL
    ))
  }

  # Freshness evaluation: blocks on absent, unparseable, or stale timestamps
  fresh_res <- check_ingest_freshness(m, max_age_hours = max_age_hours, now = now)
  if (!isTRUE(fresh_res$fresh)) {
    return(list(
      allowed = FALSE,
      advisory = FALSE,
      promotion_frozen = TRUE,
      reason = paste0("Publication blocked: ", fresh_res$reason),
      composite_health = health,
      freshness = fresh_res,
      volume = NULL
    ))
  }

  # Volume evaluation: blocks when HEALTHY/DEGRADED but total items == 0
  vol_res <- check_ingest_volume(m)
  if (!isTRUE(vol_res$valid)) {
    return(list(
      allowed = FALSE,
      advisory = FALSE,
      promotion_frozen = TRUE,
      reason = paste0("Publication blocked: ", vol_res$reason),
      composite_health = health,
      freshness = fresh_res,
      volume = vol_res
    ))
  }

  # Health and Feed status evaluation
  wire_failed <- !is.null(m$adapters$league_wire$status) &&
    identical(as.character(m$adapters$league_wire$status), "FAILED")
  is_failed <- (health == "FAILED") || wire_failed

  if (is_failed) {
    if (!allow_degraded) {
      return(list(
        allowed = FALSE,
        advisory = FALSE,
        promotion_frozen = TRUE,
        reason = sprintf("Publication blocked: Ingestion status is FAILED (composite_health=%s, league_wire=%s). Operator override required via --allow-degraded.",
                         health, if (wire_failed) "FAILED" else "OK"),
        composite_health = health,
        freshness = fresh_res,
        volume = vol_res
      ))
    } else {
      return(list(
        allowed = TRUE,
        advisory = TRUE,
        promotion_frozen = TRUE,
        reason = sprintf("Publication allowed under --allow-degraded (composite_health=%s). Advisory banner required; baseline promotion PROHIBITED.", health),
        composite_health = health,
        freshness = fresh_res,
        volume = vol_res
      ))
    }
  }

  if (identical(health, "DEGRADED")) {
    return(list(
      allowed = TRUE,
      advisory = TRUE,
      promotion_frozen = FALSE,
      reason = "Publication allowed with advisory: composite_health is DEGRADED, volume and freshness verified.",
      composite_health = health,
      freshness = fresh_res,
      volume = vol_res
    ))
  }

  # HEALTHY
  list(
    allowed = TRUE,
    advisory = FALSE,
    promotion_frozen = FALSE,
    reason = "Publication allowed: Ingestion healthy, fresh, and non-zero volume verified.",
    composite_health = health,
    freshness = fresh_res,
    volume = vol_res
  )
}

# ------------------------------------------------------------------------------
# CLI Invocation Guard
# ------------------------------------------------------------------------------
if (sys.nframe() == 0) {
  cmd_args <- commandArgs(trailingOnly = TRUE)
  allow_degraded <- "--allow-degraded" %in% cmd_args

  manifest_arg <- grep("^--manifest=", cmd_args, value = TRUE)
  manifest_path <- if (length(manifest_arg) > 0) {
    sub("^--manifest=", "", manifest_arg[1])
  } else {
    file.path("cache", "ingestion_manifest.json")
  }

  max_age_arg <- grep("^--max-age-hours=", cmd_args, value = TRUE)
  max_age <- if (length(max_age_arg) > 0) {
    as.numeric(sub("^--max-age-hours=", "", max_age_arg[1]))
  } else {
    DEFAULT_MAX_AGE_HOURS
  }

  gate_res <- evaluate_ingestion_gate(
    manifest = manifest_path,
    allow_degraded = allow_degraded,
    max_age_hours = max_age
  )

  if (!gate_res$allowed) {
    message(">>> [GATE BLOCKED] ", gate_res$reason)
    quit(status = 1)
  } else if (isTRUE(gate_res$advisory)) {
    message(">>> [GATE ADVISORY] ", gate_res$reason)
    quit(status = 0)
  } else {
    message(">>> [GATE OK] ", gate_res$reason)
    quit(status = 0)
  }
}
