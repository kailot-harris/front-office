# ==============================================================================
# logging_utils.R (WNBA — Production Hardened)
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/logging_utils.R
#
# Structured logging utility for the WNBA pipeline.
# Now implements dual-logging: (1) Standard append-only text logs for fast tailing,
# and (2) A DuckDB relational store for analytical auditing and pipeline health.
# ==============================================================================

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
}

LOG_DIR       <- file.path(PROJECT_DIR, "logs")
LOG_FILE      <- file.path(LOG_DIR, "wnba_pipeline.log")
LOG_DB_FILE   <- file.path(LOG_DIR, "logs.duckdb")
LOG_MAX_BYTES <- 5 * 1024 * 1024  # 5 MB rotation threshold

suppressPackageStartupMessages({
  library(duckdb)
})

`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)[1]) a else b

.log_ensure_dir <- function() {
  if (!dir.exists(LOG_DIR)) dir.create(LOG_DIR, recursive = TRUE)
}

.log_init_db <- function() {
  con <- dbConnect(duckdb(), LOG_DB_FILE)
  on.exit(dbDisconnect(con, immediate = TRUE))

  # Create logs table if not exists
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS logs (
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      level VARCHAR,
      script VARCHAR,
      message TEXT,
      extra_json TEXT
    )
  ")
}

.log_rotate_if_needed <- function() {
  .log_ensure_dir()
  if (file.exists(LOG_FILE)) {
    sz <- tryCatch(file.info(LOG_FILE)$size, error = function(e) 0)
    if (!is.na(sz) && sz > LOG_MAX_BYTES) {
      backup <- file.path(LOG_DIR, sprintf("wnba_pipeline_%s.log", format(Sys.time(), "%Y%m%d_%H%M%S")))
      file.rename(LOG_FILE, backup)
    }
  }
}

.log_script_name <- function(script = NULL) {
  if (!is.null(script)) return(script)
  if (exists(".LOG_SCRIPT", envir = .GlobalEnv, inherits = FALSE)) {
    return(get(".LOG_SCRIPT", envir = .GlobalEnv, inherits = FALSE))
  }
  "R"
}

.log_format_extra <- function(extra_list) {
  extra_list <- extra_list[!vapply(extra_list, is.null, logical(1))]
  if (length(extra_list) == 0) return("")
  parts <- vapply(names(extra_list), function(nm) {
    val <- extra_list[[nm]]
    val_chr <- paste(as.character(val), collapse = "; ")
    val_chr <- gsub("[\r\n]+", " ", val_chr)
    sprintf("%s: %s", nm, val_chr)
  }, character(1))
  paste0(" | ", paste(parts, collapse = " | "))
}

.log_write <- function(level, msg, script, extra_list = list()) {
  .log_rotate_if_needed()
  ts   <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  line <- sprintf("[%s] [%s] [%s] %s%s", ts, level, script, msg, .log_format_extra(extra_list))

  # 1. Console output
  cat(line, "\n", sep = "")

  # 2. Text file append
  cat(line, "\n", sep = "", file = LOG_FILE, append = TRUE)

  # 3. DuckDB Store
  tryCatch({
    con <- dbConnect(duckdb(), LOG_DB_FILE)
    # Convert extra_list to a simple JSON-like string for storage
    extra_json <- if (length(extra_list) > 0) {
      paste(vapply(names(extra_list), function(n) sprintf("%s=%s", n, as.character(extra_list[[n]])), character(1)), collapse = "; ")
    } else {
      ""
    }
    dbExecute(con, "INSERT INTO logs (level, script, message, extra_json) VALUES (?, ?, ?, ?)",
              params = list(level, script, msg, extra_json))
    dbDisconnect(con, immediate = TRUE)
  }, error = function(e) {
    # Fallback: do not crash the pipeline if DB write fails
    cat(sprintf("[LOG DB ERROR] %s\n", e$message), sep = "")
  })

  invisible(line)
}

# Ensure DB is ready
.log_init_db()

log_info <- function(msg, script = NULL, ...) {
  .log_write("INFO", msg, .log_script_name(script), list(...))
}

log_warn <- function(msg, script = NULL, ...) {
  .log_write("WARN", msg, .log_script_name(script), list(...))
}

log_error <- function(msg, condition = NULL, script = NULL, ...) {
  extra <- list(...)
  if (!is.null(condition)) {
    extra$condition_class   <- paste(class(condition), collapse = "/")
    extra$condition_message <- conditionMessage(condition)
    cc <- tryCatch(conditionCall(condition), error = function(e) NULL)
    if (!is.null(cc) && is.null(extra$call)) {
      extra$call <- paste(deparse(cc), collapse = " ")
    }
  }
  .log_write("ERROR", msg, .log_script_name(script), extra)
}

log_live_call <- function(description, expr, script = NULL) {
  script <- .log_script_name(script)
  result <- tryCatch(
    list(ok = TRUE, value = eval.parent(substitute(expr))),
    error = function(e) {
      # log_error handles condition extraction
      log_error(sprintf("%s failed.", description), condition = e, script = script)
      NULL
    }
  )
  if (!is.null(result$value)) {
    n <- tryCatch(if (is.data.frame(result$value)) nrow(result$value) else length(result$value), error = function(e) NA)
    log_info(sprintf("%s succeeded.", description), script = script, rows = n)
    return(result$value)
  } else {
    return(NULL)
  }
}

invisible(NULL)
