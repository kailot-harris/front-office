# ==============================================================================
# ingest_freshness.R — Ingestion Manifest Freshness & Volume Gate
# ==============================================================================
# Normative contract reference: docs/internal/offseason_wire_items_contract.md §6
# Work unit: GitHub issue #59 (closes #59, refs #64)
#
# Asserts that the ingestion manifest (cache/ingestion_manifest.json) is fresh,
# healthy, and reports live volume (> 0 items) before pipeline promotion.
#
# PURITY CONTRACT: this module is deliberately dependency-free. It performs no
# network calls, no disk access, and consults no configuration globals.
# It uses base R only, so it can be loaded in a bare `Rscript --vanilla` session.
# The caller is responsible for supplying the already-parsed manifest list.
# ==============================================================================

# Internal helper to parse UTC ISO-8601 strings ("%Y-%m-%dT%H:%M:%SZ") strictly as UTC
.parse_utc_iso8601 <- function(ts_str) {
  if (!is.character(ts_str) || length(ts_str) != 1L || is.na(ts_str)) {
    return(NULL)
  }
  trimmed <- trimws(ts_str)
  if (!nzchar(trimmed)) {
    return(NULL)
  }
  # Strict ISO-8601 UTC regex matching the format produced by ingest_sources.R:427
  if (!grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", trimmed)) {
    return(NULL)
  }
  parsed <- strptime(trimmed, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  if (is.na(parsed)) {
    return(NULL)
  }
  as.POSIXct(parsed, tz = "UTC")
}

# Internal helper to resolve 'now' parameter to a UTC POSIXct instant
.resolve_now_utc <- function(now) {
  if (inherits(now, "POSIXt")) {
    return(as.POSIXct(as.numeric(as.POSIXct(now)), origin = "1970-01-01", tz = "UTC"))
  }
  if (is.character(now) && length(now) == 1L && !is.na(now)) {
    trimmed <- trimws(now)
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", trimmed)) {
      return(as.POSIXct(strptime(trimmed, format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), tz = "UTC"))
    }
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", trimmed)) {
      return(as.POSIXct(strptime(paste0(trimmed, "T00:00:00Z"), format = "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), tz = "UTC"))
    }
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}", trimmed)) {
      clean_str <- sub("T", " ", trimmed)
      return(as.POSIXct(clean_str, tz = "UTC"))
    }
  }
  if (is.numeric(now) && length(now) == 1L && !is.na(now)) {
    return(as.POSIXct(now, origin = "1970-01-01", tz = "UTC"))
  }
  as.POSIXct(now, tz = "UTC")
}

# Construct return list and handle stop / loud advisory logic
.build_freshness_verdict <- function(status, age_hours, max_age_hours, reason, allow_stale) {
  verdict <- list(
    status = as.character(status),
    age_hours = if (identical(status, "MISSING") || is.na(age_hours)) NA_real_ else as.numeric(age_hours),
    max_age_hours = as.numeric(max_age_hours),
    reason = as.character(reason)
  )

  if (!identical(status, "FRESH")) {
    if (!allow_stale) {
      stop(reason, call. = FALSE)
    } else {
      warning(sprintf("[ADVISORY PASS] assert_ingest_freshness: %s", reason), call. = FALSE)
    }
  }

  verdict
}

# ------------------------------------------------------------------------------
# assert_ingest_freshness()
# ------------------------------------------------------------------------------
# manifest       : parsed cache/ingestion_manifest.json list or manifest element
#                  from ingest_all()
# now            : POSIXct or UTC string instant for recency evaluation
# max_age_hours  : threshold in hours (default 26 per contract §6)
# allow_stale    : logical; if FALSE, any non-FRESH verdict stops execution;
#                  if TRUE, returns the non-FRESH verdict as an advisory pass
#
# Returns a list with exactly:
#   $status         : "FRESH" | "STALE" | "MISSING" | "FAILED" | "DEGRADED"
#   $age_hours      : numeric age in hours (NA_real_ when status == "MISSING")
#   $max_age_hours  : numeric threshold applied (default 26)
#   $reason         : single-sentence human-readable diagnostic description
# ------------------------------------------------------------------------------
assert_ingest_freshness <- function(manifest,
                                    now = Sys.time(),
                                    max_age_hours = 26,
                                    allow_stale = FALSE) {
  # Validate threshold parameter
  if (!is.numeric(max_age_hours) || length(max_age_hours) != 1L || is.na(max_age_hours) || max_age_hours <= 0) {
    stop("assert_ingest_freshness: 'max_age_hours' must be a single positive numeric value.", call. = FALSE)
  }

  # 1. Envelope validation: manifest must be a non-null named list
  if (is.null(manifest)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is NULL; expected parsed JSON manifest list.",
      allow_stale = allow_stale
    ))
  }

  if (!is.list(manifest)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest root must be a list, got %s.", class(manifest)[1]),
      allow_stale = allow_stale
    ))
  }

  # 2. Ingest timestamp presence
  if (!("ingest_timestamp" %in% names(manifest)) || is.null(manifest$ingest_timestamp)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required field 'ingest_timestamp'.",
      allow_stale = allow_stale
    ))
  }

  raw_ts <- manifest$ingest_timestamp
  if (is.character(raw_ts) && !nzchar(trimws(raw_ts))) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required field 'ingest_timestamp'.",
      allow_stale = allow_stale
    ))
  }

  # 3. Ingest timestamp parseability (strict UTC ISO-8601)
  ts_utc <- .parse_utc_iso8601(raw_ts)
  if (is.null(ts_utc)) {
    raw_preview <- if (length(raw_ts) == 0L) "character(0)" else as.character(raw_ts)[1]
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest 'ingest_timestamp' is malformed and could not be parsed as UTC ISO-8601: '%s'.", raw_preview),
      allow_stale = allow_stale
    ))
  }

  # 4. Composite health presence
  if (!("composite_health" %in% names(manifest)) || is.null(manifest$composite_health)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required field 'composite_health'.",
      allow_stale = allow_stale
    ))
  }

  raw_health <- manifest$composite_health
  if (is.character(raw_health) && !nzchar(trimws(raw_health))) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required field 'composite_health'.",
      allow_stale = allow_stale
    ))
  }

  # Calculate age against now (both in UTC)
  now_utc <- .resolve_now_utc(now)
  age_hours <- as.numeric(difftime(now_utc, ts_utc, units = "hours"))

  # 5. Recency / Staleness assertion
  if (age_hours > max_age_hours) {
    return(.build_freshness_verdict(
      status = "STALE",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Ingest is stale: age %.1fh exceeds threshold %.1fh (status STALE).", age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  # 6. Composite health state evaluation
  health_val <- as.character(raw_health)[1]
  if (identical(health_val, "FAILED")) {
    return(.build_freshness_verdict(
      status = "FAILED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest composite_health is FAILED (age %.1fh, threshold %.1fh).", age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  if (identical(health_val, "DEGRADED")) {
    return(.build_freshness_verdict(
      status = "DEGRADED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest composite_health is DEGRADED (age %.1fh, threshold %.1fh).", age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  if (!identical(health_val, "HEALTHY")) {
    return(.build_freshness_verdict(
      status = "FAILED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest composite_health is unrecognized: '%s' (age %.1fh, threshold %.1fh).", health_val, age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  # 7. Volume assertion on league_wire adapter
  if (!("adapters" %in% names(manifest)) || is.null(manifest$adapters) || !is.list(manifest$adapters)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required 'adapters' object.",
      allow_stale = allow_stale
    ))
  }

  adapters <- manifest$adapters
  if (!("league_wire" %in% names(adapters)) || is.null(adapters$league_wire) || !is.list(adapters$league_wire)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest is missing required adapter 'league_wire'.",
      allow_stale = allow_stale
    ))
  }

  league_wire <- adapters$league_wire
  if (!("items_found" %in% names(league_wire)) || is.null(league_wire$items_found)) {
    return(.build_freshness_verdict(
      status = "MISSING",
      age_hours = NA_real_,
      max_age_hours = max_age_hours,
      reason = "Manifest adapter 'league_wire' is missing required field 'items_found'.",
      allow_stale = allow_stale
    ))
  }

  items_found <- league_wire$items_found
  if (!is.numeric(items_found) || length(items_found) != 1L || is.na(items_found)) {
    return(.build_freshness_verdict(
      status = "FAILED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest adapter 'league_wire' field 'items_found' must be a numeric integer, got %s.", class(items_found)[1]),
      allow_stale = allow_stale
    ))
  }

  if (items_found == 0) {
    return(.build_freshness_verdict(
      status = "FAILED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest reports zero items found for adapter 'league_wire' (items_found = 0, age %.1fh, threshold %.1fh).", age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  if (items_found < 0) {
    return(.build_freshness_verdict(
      status = "FAILED",
      age_hours = age_hours,
      max_age_hours = max_age_hours,
      reason = sprintf("Manifest reports negative items found for adapter 'league_wire' (items_found = %d, age %.1fh, threshold %.1fh).", as.integer(items_found), age_hours, max_age_hours),
      allow_stale = allow_stale
    ))
  }

  # 8. All assertions satisfied -> FRESH
  .build_freshness_verdict(
    status = "FRESH",
    age_hours = age_hours,
    max_age_hours = max_age_hours,
    reason = sprintf("Ingest is fresh: age %.1fh is within threshold %.1fh (status FRESH).", age_hours, max_age_hours),
    allow_stale = allow_stale
  )
}
