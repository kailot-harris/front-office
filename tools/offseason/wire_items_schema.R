# ==============================================================================
# wire_items_schema.R
# Canonical Offseason Wire Items Contract & Schema Validator (Issue #159 / Unit A)
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
if (!exists("log_info", mode = "function") && file.exists("logging_utils.R")) source("logging_utils.R")

suppressPackageStartupMessages({
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    warning("jsonlite package not available; some JSON helper features may be limited.")
  }
})

# ------------------------------------------------------------------------------
# Schema Constants
# ------------------------------------------------------------------------------
WIRE_ITEM_REQUIRED_FIELDS <- c(
  "item_id",
  "source_family",
  "source_id",
  "source_url",
  "observed_at",
  "event_date",
  "raw_text",
  "team_abbr"
)

WIRE_ITEM_ALLOWED_FAMILIES <- c(
  "league_wire",
  "beat_feeds",
  "team_releases"
)

# ISO 8601 regex pattern for timestamps (e.g. 2026-11-06T11:42:45Z or with offsets)
ISO_TIMESTAMP_PATTERN <- "^\\d{4}-\\d{2}-\\d{2}[T ]\\d{2}:\\d{2}(:\\d{2})?(\\.\\d+)?(Z|[+-]\\d{2}:?\\d{2})?$"

# Date regex pattern (e.g. 2026-10-23 or ISO timestamp prefix)
DATE_PATTERN <- "^\\d{4}-\\d{2}-\\d{2}"

# ------------------------------------------------------------------------------
# Constructor Helper: create_wire_item()
# ------------------------------------------------------------------------------
#' Construct a single canonical wire item object
#'
#' @param item_id Unique identifier for the item (character)
#' @param source_family One of "league_wire", "beat_feeds", "team_releases"
#' @param source_id Adapter or outlet identifier (character)
#' @param source_url Canonical URL or NULL
#' @param observed_at Ingestion snapshot ISO 8601 UTC timestamp (character)
#' @param event_date Event date or timestamp (character)
#' @param raw_text Unparsed description or headline text (character)
#' @param team_abbr Structural sibling team abbreviation (character, optional)
#' @return A named list adhering to the wire item contract
create_wire_item <- function(item_id,
                             source_family,
                             source_id,
                             source_url = NULL,
                             observed_at,
                             event_date,
                             raw_text,
                             team_abbr = NA_character_) {
  item <- list(
    item_id = as.character(item_id %||% ""),
    source_family = as.character(source_family %||% ""),
    source_id = as.character(source_id %||% ""),
    source_url = if (is.null(source_url) || is.na(source_url)) NULL else as.character(source_url),
    observed_at = as.character(observed_at %||% ""),
    event_date = as.character(event_date %||% ""),
    raw_text = as.character(raw_text %||% ""),
    team_abbr = if (is.null(team_abbr) || is.na(team_abbr)) NULL else as.character(team_abbr)
  )
  item
}

# ------------------------------------------------------------------------------
# Validator: validate_wire_items()
# ------------------------------------------------------------------------------
#' Validate a set of wire items against the Issue #159 schema
#'
#' Evaluates whether the provided wire items adhere to the canonical schema.
#' Enforces fail-closed validation: rejects missing item_id, missing or malformed
#' observed_at, empty raw_text, missing required schema fields, and invalid source families.
#'
#' @param items A JSON file path, a list of item lists, or a data.frame
#' @param stop_on_error Logical. If TRUE, halts with an error on validation failure.
#' @param detailed Logical. If TRUE, returns a diagnostic list with validation details.
#' @param allow_empty Logical. If TRUE, an empty collection (0 items) is considered valid.
#' @return Boolean TRUE if valid, FALSE otherwise (with attr "errors" containing messages),
#'         or diagnostic list if detailed = TRUE.
validate_wire_items <- function(items,
                                stop_on_error = FALSE,
                                detailed = FALSE,
                                allow_empty = FALSE) {
  errors <- character(0)

  # Check for file path input
  if (is.character(items) && length(items) == 1) {
    if (!file.exists(items)) {
      err <- sprintf("Wire items file does not exist: %s", items)
      if (stop_on_error) stop(err)
      res <- structure(FALSE, errors = err, item_count = 0L)
      return(if (detailed) list(valid = FALSE, errors = err, item_count = 0L) else res)
    }

    parsed <- tryCatch({
      jsonlite::fromJSON(items, simplifyVector = FALSE)
    }, error = function(e) {
      sprintf("Failed to parse JSON file '%s': %s", items, e$message)
    })

    if (is.character(parsed)) {
      if (stop_on_error) stop(parsed)
      res <- structure(FALSE, errors = parsed, item_count = 0L)
      return(if (detailed) list(valid = FALSE, errors = parsed, item_count = 0L) else res)
    }
    items <- parsed
  }

  # Convert data.frame input into a list of row lists
  if (is.data.frame(items)) {
    if (nrow(items) == 0) {
      items_list <- list()
    } else {
      items_list <- lapply(seq_len(nrow(items)), function(i) {
        row_list <- as.list(items[i, , drop = FALSE])
        lapply(row_list, function(val) {
          if (is.vector(val) && length(val) == 1 && is.na(val)) NULL else val
        })
      })
    }
    items <- items_list
  }

  # Input must be a list
  if (!is.list(items)) {
    err <- sprintf("Invalid input type: expected list, data.frame, or JSON filepath, got %s", typeof(items))
    if (stop_on_error) stop(err)
    res <- structure(FALSE, errors = err, item_count = 0L)
    return(if (detailed) list(valid = FALSE, errors = err, item_count = 0L) else res)
  }

  # Check if a single item dictionary was passed instead of a list of items
  if (length(items) > 0 && !is.null(names(items)) && "item_id" %in% names(items)) {
    items <- list(items)
  }

  item_count <- length(items)

  # Check empty collection
  if (item_count == 0) {
    if (!allow_empty) {
      errors <- c(errors, "Wire items collection is empty (allow_empty is FALSE)")
    }
    is_valid <- length(errors) == 0
    if (!is_valid && stop_on_error) stop(paste(errors, collapse = "\n"))
    res <- structure(is_valid, errors = errors, item_count = 0L)
    return(if (detailed) list(valid = is_valid, errors = errors, item_count = 0L) else res)
  }

  # Validate each item
  for (idx in seq_along(items)) {
    item <- items[[idx]]
    item_desc <- sprintf("Item[%d]", idx)

    if (!is.list(item)) {
      errors <- c(errors, sprintf("%s is not a structured record/list (type: %s)", item_desc, typeof(item)))
      next
    }

    item_names <- names(item)
    if (is.null(item_names)) {
      errors <- c(errors, sprintf("%s has no named fields", item_desc))
      next
    }

    # 1. item_id (required, non-empty string)
    if (!("item_id" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'item_id'", item_desc))
    } else {
      val <- item[["item_id"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'item_id' must be a non-empty character string", item_desc))
      } else {
        item_desc <- sprintf("Item[%d] (id='%s')", idx, val)
      }
    }

    # 2. source_family (required, must be one of WIRE_ITEM_ALLOWED_FAMILIES)
    if (!("source_family" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'source_family'", item_desc))
    } else {
      val <- item[["source_family"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'source_family' must be a non-empty character string", item_desc))
      } else if (!(val %in% WIRE_ITEM_ALLOWED_FAMILIES)) {
        errors <- c(errors, sprintf("%s: 'source_family' ('%s') must be one of: %s",
                                    item_desc, val, paste(WIRE_ITEM_ALLOWED_FAMILIES, collapse = ", ")))
      }
    }

    # 3. source_id (required, non-empty string)
    if (!("source_id" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'source_id'", item_desc))
    } else {
      val <- item[["source_id"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'source_id' must be a non-empty character string", item_desc))
      }
    }

    # 4. source_url (nullable, character if present)
    if ("source_url" %in% item_names) {
      val <- item[["source_url"]]
      if (!is.null(val) && !is.na(val) && (!is.character(val) || length(val) != 1)) {
        errors <- c(errors, sprintf("%s: 'source_url' must be character string or null", item_desc))
      }
    }

    # 5. observed_at (required, non-empty ISO timestamp)
    if (!("observed_at" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'observed_at'", item_desc))
    } else {
      val <- item[["observed_at"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'observed_at' must be a non-empty ISO 8601 timestamp string", item_desc))
      } else if (!grepl(ISO_TIMESTAMP_PATTERN, trimws(val), perl = TRUE)) {
        errors <- c(errors, sprintf("%s: 'observed_at' ('%s') does not match ISO 8601 pattern", item_desc, val))
      }
    }

    # 6. event_date (required, non-empty date string)
    if (!("event_date" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'event_date'", item_desc))
    } else {
      val <- item[["event_date"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'event_date' must be a non-empty date string", item_desc))
      } else if (!grepl(DATE_PATTERN, trimws(val), perl = TRUE)) {
        errors <- c(errors, sprintf("%s: 'event_date' ('%s') does not match date format YYYY-MM-DD", item_desc, val))
      }
    }

    # 7. raw_text (required, non-empty character)
    if (!("raw_text" %in% item_names)) {
      errors <- c(errors, sprintf("%s is missing required field 'raw_text'", item_desc))
    } else {
      val <- item[["raw_text"]]
      if (is.null(val) || is.na(val) || !is.character(val) || length(val) != 1 || !nzchar(trimws(val))) {
        errors <- c(errors, sprintf("%s: 'raw_text' must be a non-empty character string", item_desc))
      }
    }

    # 8. team_abbr (nullable structural sibling field; character if present)
    if ("team_abbr" %in% item_names) {
      val <- item[["team_abbr"]]
      if (!is.null(val) && !is.na(val)) {
        if (!is.character(val) || length(val) != 1) {
          errors <- c(errors, sprintf("%s: 'team_abbr' must be character string or null", item_desc))
        } else if (nzchar(trimws(val)) && !grepl("^[A-Za-z0-9]{2,4}$", trimws(val))) {
          errors <- c(errors, sprintf("%s: 'team_abbr' ('%s') must be a 2-4 alphanumeric code or null", item_desc, val))
        }
      }
    }
  }

  is_valid <- length(errors) == 0

  if (!is_valid && stop_on_error) {
    stop(sprintf("Wire items validation failed with %d error(s):\n%s",
                 length(errors),
                 paste(paste0("  - ", errors), collapse = "\n")))
  }

  res <- structure(is_valid, errors = errors, item_count = as.integer(item_count))
  if (detailed) {
    list(
      valid = is_valid,
      errors = errors,
      item_count = as.integer(item_count),
      items = items
    )
  } else {
    res
  }
}

# ------------------------------------------------------------------------------
# I/O Helpers: read_wire_items() & write_wire_items()
# ------------------------------------------------------------------------------
#' Read wire items from a JSON file with optional validation
#'
#' @param path Path to JSON file
#' @param validate Logical. If TRUE, runs validate_wire_items(..., stop_on_error = TRUE).
#' @return A list of wire item lists
read_wire_items <- function(path, validate = TRUE) {
  if (!file.exists(path)) {
    stop("File not found: ", path)
  }
  items <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  if (validate) {
    validate_wire_items(items, stop_on_error = TRUE)
  }
  items
}

#' Write wire items to a JSON file with optional validation
#'
#' @param items A list of wire items
#' @param path Destination JSON file path
#' @param validate Logical. If TRUE, validates before writing.
#' @param pretty Logical. If TRUE, writes indented JSON.
#' @return The normalized JSON string invisibly
write_wire_items <- function(items, path, validate = TRUE, pretty = TRUE) {
  if (validate) {
    validate_wire_items(items, stop_on_error = TRUE)
  }
  dir.create(dirname(normalizePath(path, mustWork = FALSE)), recursive = TRUE, showWarnings = FALSE)
  json_str <- jsonlite::toJSON(items, auto_unbox = TRUE, pretty = pretty, null = "null")
  writeLines(json_str, con = path, useBytes = TRUE)
  invisible(json_str)
}
