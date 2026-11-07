# ==============================================================================
# wire_items_schema.R — Wire-Items Data Contract Validator
# ==============================================================================
# Shared validation seam for the offseason wire-items artifact
# (cache/offseason_wire_items.json). The contract itself is specified in
# docs/internal/offseason_wire_items_contract.md.
#
# Producer side (issue #57): validate the in-memory item list BEFORE persisting
# the artifact, and abort the ingest stage on failure.
# Consumer side (issue #58): validate AFTER parsing the artifact, and abort the
# extract stage on failure. A schema drift must fail loudly here rather than
# degrade into "zero deltas extracted" further downstream.
#
# PURITY CONTRACT: this module is deliberately dependency-free. It performs no
# network calls, no disk access, and consults no config.R globals. It uses base
# R only, so it can be loaded in a bare `Rscript --vanilla` session and called
# from the pipeline, from either side of the seam, and from tests.
# Callers are responsible for parsing JSON (e.g. jsonlite with
# simplifyVector = FALSE) and for handing the resulting list to this validator.
# ==============================================================================

# Canonical field order of a wire item, per the contract doc.
WIRE_ITEM_FIELDS <- c(
  "transaction_id",
  "raw_text",
  "date",
  "source_url",
  "team_id",
  "from_team_id",
  "mlbam_id",
  "player_name",
  "type_code",
  "type_desc",
  "roster_tier"
)

WIRE_ITEM_REQUIRED_FIELDS <- c(
  "transaction_id",
  "raw_text",
  "date",
  "source_url",
  "team_id",
  "type_code",
  "type_desc",
  "roster_tier"
)

# from_team_id is absent on non-transfer transactions (free-agency
# declarations, assignments, retirements). mlbam_id / player_name are absent
# whenever the upstream statsapi record carries no `person` object at all
# (archived example: transaction_id 947461). They are co-required: a record that
# names a player must also carry that player's MLBAM id.
WIRE_ITEM_OPTIONAL_FIELDS <- c("from_team_id", "mlbam_id", "player_name")

WIRE_ITEM_ROSTER_TIERS <- c("MAJOR_40_MAN", "MINOR_LEAGUE")

# ------------------------------------------------------------------------------
# Internal scalar predicates
# ------------------------------------------------------------------------------

.wire_is_present <- function(record, field) {
  field %in% names(record) && !is.null(record[[field]])
}

.wire_is_scalar_chr <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(trimws(x))
}

.wire_is_scalar_id <- function(x) {
  if (length(x) != 1L || is.na(x)) return(FALSE)
  if (!is.numeric(x)) return(FALSE)
  x == trunc(x) && x > 0
}

.wire_is_iso_date <- function(x) {
  .wire_is_scalar_chr(x) && grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x)
}

.wire_type_label <- function(x) {
  if (is.null(x)) return("NULL")
  sprintf("%s[%d]", class(x)[1], length(x))
}

# Human-readable label for the offending record: prefer its transaction_id so
# diagnostics are actionable against the upstream feed, and fall back to the
# positional index when the id is itself missing or malformed.
.wire_record_label <- function(record, index) {
  tid <- if (is.list(record)) record[["transaction_id"]] else NULL
  if (!is.null(tid) && length(tid) == 1L && !is.na(tid)) {
    return(sprintf("record transaction_id=%s (index %d)", format(tid, scientific = FALSE), index))
  }
  sprintf("record index %d (transaction_id missing)", index)
}

# ------------------------------------------------------------------------------
# validate_wire_items()
# ------------------------------------------------------------------------------
# items : an unnamed list of wire-item records, each itself a named list.
#         (The artifact is a bare JSON array, so a parsed artifact is passed
#         straight through.) A single bare record is also accepted and treated
#         as a one-element list.
# require_unique_transaction_ids : the contract mandates exactly one record per
#         wire transaction. statsapi emits mirrored rows for trades (the same
#         `id` once per club), so the producer must collapse them; leave this
#         TRUE unless validating a deliberately partial batch.
# allow_unknown_fields : FALSE by default. Unknown keys are an error because the
#         benchmark fixture's test scaffolding (`id`, `_note`,
#         `expected_tuples`) must never reach the production artifact.
#
# Returns a list:
#   $pass            logical, TRUE when zero errors
#   $n_records       integer
#   $n_errors        integer
#   $errors          list of list(index, record, field, code, message)
#   $messages        character vector of the rendered diagnostics
#   $summary         single-line character summary
# ------------------------------------------------------------------------------
validate_wire_items <- function(items,
                                require_unique_transaction_ids = TRUE,
                                allow_unknown_fields = FALSE) {
  errors <- list()
  add_error <- function(index, record, field, code, message) {
    label <- if (is.null(index)) "artifact root" else .wire_record_label(record, index)
    errors[[length(errors) + 1L]] <<- list(
      index = index,
      record = label,
      field = field,
      code = code,
      message = sprintf("[%s] field `%s`: %s", label, field, message)
    )
  }

  # --- Envelope shape -------------------------------------------------------
  if (is.null(items)) {
    add_error(NULL, NULL, "<root>", "ROOT_NULL", "wire items payload is NULL; expected a JSON array of records.")
    return(.wire_result(errors, 0L))
  }
  if (is.list(items) && !is.null(names(items)) && any(WIRE_ITEM_FIELDS %in% names(items))) {
    items <- list(items)  # tolerate a single bare record
  }
  if (!is.list(items)) {
    add_error(NULL, NULL, "<root>", "ROOT_NOT_LIST",
              sprintf("expected a list of records, got %s.", .wire_type_label(items)))
    return(.wire_result(errors, 0L))
  }
  if (length(items) == 0L) {
    add_error(NULL, NULL, "<root>", "ROOT_EMPTY",
              "wire items payload contains zero records; an empty artifact cannot be distinguished from a silent ingest failure.")
    return(.wire_result(errors, 0L))
  }

  # --- Per-record field checks ----------------------------------------------
  for (i in seq_along(items)) {
    record <- items[[i]]

    if (!is.list(record) || is.null(names(record))) {
      add_error(i, NULL, "<record>", "RECORD_NOT_OBJECT",
                sprintf("expected a named object, got %s.", .wire_type_label(record)))
      next
    }

    # Required presence
    for (field in WIRE_ITEM_REQUIRED_FIELDS) {
      if (!.wire_is_present(record, field)) {
        detail <- if (field %in% names(record)) "present but NULL/empty" else "absent"
        add_error(i, record, field, "REQUIRED_MISSING",
                  sprintf("required field is %s.", detail))
      }
    }

    # Unknown keys (test scaffolding, typos, upstream drift)
    if (!allow_unknown_fields) {
      unknown <- setdiff(names(record), WIRE_ITEM_FIELDS)
      for (field in unknown) {
        add_error(i, record, field, "UNKNOWN_FIELD",
                  "field is not part of the wire-items contract (benchmark-fixture scaffolding such as `id`, `_note` or `expected_tuples` must not appear in the production artifact).")
      }
    }

    # Types / domains
    if (.wire_is_present(record, "transaction_id") && !.wire_is_scalar_id(record$transaction_id)) {
      add_error(i, record, "transaction_id", "BAD_TYPE",
                sprintf("expected a single positive integer, got %s.", .wire_type_label(record$transaction_id)))
    }
    if (.wire_is_present(record, "raw_text") && !.wire_is_scalar_chr(record$raw_text)) {
      add_error(i, record, "raw_text", "BAD_TYPE",
                sprintf("expected a single non-empty string (the statsapi `description` prose), got %s.", .wire_type_label(record$raw_text)))
    }
    if (.wire_is_present(record, "date") && !.wire_is_iso_date(record$date)) {
      add_error(i, record, "date", "BAD_FORMAT",
                sprintf("expected a single YYYY-MM-DD string, got %s.", .wire_type_label(record$date)))
    }
    if (.wire_is_present(record, "source_url") && !grepl("^https?://", if (.wire_is_scalar_chr(record$source_url)) record$source_url else "")) {
      add_error(i, record, "source_url", "BAD_FORMAT",
                "expected a single absolute http(s) URL (the statsapi transactions endpoint used as build_wire_source_url()'s default_url).")
    }
    if (.wire_is_present(record, "team_id") && !.wire_is_scalar_id(record$team_id)) {
      add_error(i, record, "team_id", "BAD_TYPE",
                sprintf("expected a single positive integer statsapi team id, got %s.", .wire_type_label(record$team_id)))
    }
    if (.wire_is_present(record, "from_team_id") && !.wire_is_scalar_id(record$from_team_id)) {
      add_error(i, record, "from_team_id", "BAD_TYPE",
                sprintf("optional field, but when present must be a single positive integer statsapi team id; got %s.", .wire_type_label(record$from_team_id)))
    }
    if (.wire_is_present(record, "mlbam_id") && !.wire_is_scalar_id(record$mlbam_id)) {
      add_error(i, record, "mlbam_id", "BAD_TYPE",
                sprintf("optional field, but when present must be a single positive integer MLBAM person id; got %s.", .wire_type_label(record$mlbam_id)))
    }
    if (.wire_is_present(record, "player_name") && !.wire_is_scalar_chr(record$player_name)) {
      add_error(i, record, "player_name", "BAD_TYPE",
                sprintf("optional field, but when present must be a single non-empty string; got %s.", .wire_type_label(record$player_name)))
    }
    for (field in c("type_code", "type_desc")) {
      if (.wire_is_present(record, field) && !.wire_is_scalar_chr(record[[field]])) {
        add_error(i, record, field, "BAD_TYPE",
                  sprintf("expected a single non-empty string, got %s.", .wire_type_label(record[[field]])))
      }
    }
    if (.wire_is_present(record, "roster_tier")) {
      tier <- record$roster_tier
      if (!.wire_is_scalar_chr(tier) || !(tier %in% WIRE_ITEM_ROSTER_TIERS)) {
        add_error(i, record, "roster_tier", "BAD_ENUM",
                  sprintf("expected one of %s, got %s.",
                          paste(WIRE_ITEM_ROSTER_TIERS, collapse = " | "),
                          if (.wire_is_scalar_chr(tier)) sprintf("'%s'", tier) else .wire_type_label(tier)))
      }
    }

    # Co-requirement: a record that names a player must identify that player.
    has_name <- .wire_is_present(record, "player_name")
    has_id <- .wire_is_present(record, "mlbam_id")
    if (has_name && !has_id) {
      add_error(i, record, "mlbam_id", "PERSON_INCOMPLETE",
                "record carries `player_name` (upstream statsapi `person` object present), so `mlbam_id` is required; it is absent.")
    }
    if (has_id && !has_name) {
      add_error(i, record, "player_name", "PERSON_INCOMPLETE",
                "record carries `mlbam_id` (upstream statsapi `person` object present), so `player_name` is required; it is absent.")
    }
  }

  # --- Cross-record: one record per wire transaction ------------------------
  if (require_unique_transaction_ids) {
    ids <- vapply(items, function(r) {
      if (is.list(r) && .wire_is_present(r, "transaction_id") && .wire_is_scalar_id(r$transaction_id)) {
        as.character(trunc(r$transaction_id))
      } else {
        NA_character_
      }
    }, character(1))
    dupes <- unique(ids[!is.na(ids) & duplicated(ids)])
    for (dup in dupes) {
      positions <- which(ids == dup)
      add_error(positions[1L], items[[positions[1L]]], "transaction_id", "DUPLICATE_ID",
                sprintf("transaction_id %s appears %d times (indices %s); the contract mandates exactly one record per wire transaction, so mirrored statsapi trade rows must be collapsed by the producer.",
                        dup, length(positions), paste(positions, collapse = ", ")))
    }
  }

  .wire_result(errors, length(items))
}

.wire_result <- function(errors, n_records) {
  messages <- if (length(errors)) vapply(errors, function(e) e$message, character(1)) else character(0)
  pass <- length(errors) == 0L
  list(
    pass = pass,
    n_records = as.integer(n_records),
    n_errors = length(errors),
    errors = errors,
    messages = messages,
    summary = sprintf("validate_wire_items: %s — %d record(s), %d error(s)",
                      if (pass) "PASS" else "FAIL", as.integer(n_records), length(errors))
  )
}
