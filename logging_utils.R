# ==============================================================================
# logging_utils.R (WNBA — Production Hardened)
# Path: logging_utils.R
#
# Structured logging utility for the WNBA pipeline.
# Now implements dual-logging: (1) Standard append-only text logs for fast tailing,
# and (2) A DuckDB relational store for analytical auditing and pipeline health.
# ==============================================================================

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- here::here()   # issue #90: derived portably; never hardcode the repo root
}

LOG_DIR       <- file.path(PROJECT_DIR, "logs")
LOG_FILE      <- file.path(LOG_DIR, "wnba_pipeline.log")
LOG_DB_FILE   <- file.path(LOG_DIR, "logs.duckdb")
LOG_MAX_BYTES <- 5 * 1024 * 1024  # 5 MB rotation threshold

suppressPackageStartupMessages({
  library(duckdb)
})

# ------------------------------------------------------------------------------------------
# FINDING M-6: canonical `%||%`. THIS IS THE ONE AND ONLY DEFINITION in the repo.
# It is a SCALAR null/NA-coalescing operator (see CLAUDE.md). The `is.na(a)[1]` subscript is
# load-bearing: the unhardened `!is.na(a)` variants that used to also live in app.R:50 and
# market_odds_engine.R:60 hard-error on R 4.3+ when applied to a column/vector, because `&&`
# requires a length-1 operand. Because logging_utils.R is sourced by nearly every script,
# duplicate local definitions made "which `%||%` wins" depend on source order.
# For per-row NA-fill on a column use `dplyr::coalesce()`, never this operator.
# ------------------------------------------------------------------------------------------
`%||%` <- function(a, b) if (!is.null(a) && length(a) > 0 && !is.na(a)[1]) a else b

.log_ensure_dir <- function() {
  if (!dir.exists(LOG_DIR)) dir.create(LOG_DIR, recursive = TRUE)
}

# ------------------------------------------------------------------------------------------
# FINDING H-1: secret redaction at the logging chokepoint.
# market_odds_engine.R builds its Odds API URL with `apiKey=<secret>` interpolated into the
# string and passes that whole URL into log_error()'s `...`. .log_write() fans every `...`
# value out to THREE sinks (console, logs/wnba_pipeline.log, logs.duckdb), none of which are
# safe places for a live credential; the same applies to DISCORD_WEBHOOK URLs. Redacting here
# rather than only at the call site means every future call site inherits the protection.
# (The call-site fix — never interpolating the key into a string at all — is agent_engine's.)
# ------------------------------------------------------------------------------------------
.LOG_REDACT_PARAMS <- c("apikey", "api_key", "api-key", "token", "access_token", "auth",
                        "webhook", "secret", "password", "passwd", "signature", "key")

.log_redact <- function(x) {
  if (is.null(x) || length(x) == 0) return(x)
  s <- as.character(x)
  s[is.na(s)] <- NA_character_
  ok <- !is.na(s)
  if (!any(ok)) return(s)
  v <- s[ok]

  # 1. Query-string / form params:  ...?apiKey=SECRET&...  -> apiKey=***REDACTED***
  #    Terminates at &, whitespace, quote, comma, semicolon or end-of-string.
  v <- gsub(sprintf("(?i)\\b(%s)(\\s*=\\s*)([^&\\s\"',;]+)", paste(.LOG_REDACT_PARAMS, collapse = "|")),
            "\\1=***REDACTED***", v, perl = TRUE)

  # 2. JSON / R-list style:  "token": "SECRET"  |  token = 'SECRET'
  v <- gsub(sprintf("(?i)([\"']?)\\b(%s)\\1(\\s*:\\s*)([\"'])[^\"']*\\4",
                    paste(.LOG_REDACT_PARAMS, collapse = "|")),
            "\\1\\2\\1\\3\"***REDACTED***\"", v, perl = TRUE)

  # 3. Discord webhook paths: https://discord(app).com/api/webhooks/<id>/<token>
  v <- gsub("(?i)(https?://(?:canary\\.|ptb\\.)?discord(?:app)?\\.com/api/(?:v\\d+/)?webhooks)/[^\\s\"',;]+",
            "\\1/***REDACTED***", v, perl = TRUE)

  # 4. Bearer / Basic authorization headers.
  v <- gsub("(?i)\\b(bearer|basic)\\s+[A-Za-z0-9._~+/=-]{8,}", "\\1 ***REDACTED***", v, perl = TRUE)

  s[ok] <- v
  s
}

# ------------------------------------------------------------------------------------------
# FINDING M-7 (logging half): connection lifecycle.
# .log_write() used to open and close a fresh dbConnect(duckdb(), LOG_DB_FILE) for EVERY log
# line. DuckDB allows one writing process per file, so concurrent future_lapply workers could
# have their connection refused, and the tryCatch swallowed that into a console line while the
# row was silently lost. We now hold ONE connection for the process lifetime and reuse it.
# The connection is created lazily on first write, revalidated with dbIsValid() each time, and
# transparently re-established if it was invalidated. Console error spam is throttled so a
# locked DB cannot flood the run output.
# ------------------------------------------------------------------------------------------
.log_state <- new.env(parent = emptyenv())
.log_state$con <- NULL
.log_state$last_db_error_at <- 0

.log_disconnect <- function() {
  con <- .log_state$con
  .log_state$con <- NULL
  if (!is.null(con)) {
    tryCatch(dbDisconnect(con, shutdown = TRUE), error = function(e) invisible(NULL))
  }
  invisible(NULL)
}

.log_get_con <- function() {
  con <- .log_state$con
  if (!is.null(con) && isTRUE(tryCatch(dbIsValid(con), error = function(e) FALSE))) {
    return(con)
  }
  .log_state$con <- NULL
  con <- dbConnect(duckdb(), LOG_DB_FILE)
  dbExecute(con, "
    CREATE TABLE IF NOT EXISTS logs (
      timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      level VARCHAR,
      script VARCHAR,
      message TEXT,
      extra_json TEXT
    )
  ")
  .log_state$con <- con
  # Close cleanly when the R process exits so the DB file is not left locked.
  reg.finalizer(.log_state, function(e) .log_disconnect(), onexit = TRUE)
  con
}

.log_init_db <- function() {
  tryCatch({
    .log_get_con()
    invisible(TRUE)
  }, error = function(e) {
    cat(sprintf("[LOG DB ERROR] init failed: %s\n", .log_redact(conditionMessage(e))), sep = "")
    invisible(FALSE)
  })
}

# M-7 addendum: DuckDB allows exactly ONE writing process per file. Holding the connection for
# the process lifetime (above) removes per-line connection churn in the parent, but it also means
# a second process — a future_lapply worker, or the Shiny app running alongside the pipeline —
# cannot open logs.duckdb at all while the parent lives. Previously such a row was swallowed by
# the tryCatch and lost outright. Instead of dropping it, spill it to a per-PID TSV that can be
# merged into the logs table afterward, so the logging subsystem never silently loses a record.
# (The complementary half of M-7 — having workers buffer and return their rows to the parent —
# belongs to agent_pipeline in run_full_pipeline.R.)
LOG_SPILL_FILE <- function() file.path(LOG_DIR, sprintf("logs_pending_%s.tsv", Sys.getpid()))

.log_spill <- function(ts, level, script, msg, extra_json) {
  tryCatch({
    .log_ensure_dir()
    clean <- function(s) gsub("[\t\r\n]+", " ", as.character(s))
    cat(paste(clean(ts), clean(level), clean(script), clean(msg), clean(extra_json), sep = "\t"),
        "\n", sep = "", file = LOG_SPILL_FILE(), append = TRUE)
  }, error = function(e) invisible(NULL))
  invisible(NULL)
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
    # H-1: scrub credentials before this reaches console / text log / DuckDB.
    val_chr <- .log_redact(val_chr)
    sprintf("%s: %s", nm, val_chr)
  }, character(1))
  paste0(" | ", paste(parts, collapse = " | "))
}

.log_write <- function(level, msg, script, extra_list = list()) {
  .log_rotate_if_needed()
  ts   <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  # H-1: the message itself can carry a secret too (e.g. a condition message that embedded the
  # request URL), so redact it as well as the `...` extras.
  msg  <- .log_redact(msg)
  line <- sprintf("[%s] [%s] [%s] %s%s", ts, level, script, msg, .log_format_extra(extra_list))

  # 1. Console output
  cat(line, "\n", sep = "")

  # 2. Text file append
  cat(line, "\n", sep = "", file = LOG_FILE, append = TRUE)

  # Convert extra_list to a simple JSON-like string for storage.
  # H-1: same redaction pass as the text sink — this string lands in logs.duckdb.
  extra_json <- if (length(extra_list) > 0) {
    paste(vapply(names(extra_list),
                 function(n) sprintf("%s=%s", n, .log_redact(paste(as.character(extra_list[[n]]), collapse = "; "))),
                 character(1)), collapse = "; ")
  } else {
    ""
  }

  # 3. DuckDB Store (M-7: reuses one process-lifetime connection, see .log_get_con)
  tryCatch({
    con <- .log_get_con()
    dbExecute(con, "INSERT INTO logs (level, script, message, extra_json) VALUES (?, ?, ?, ?)",
              params = list(level, script, msg, extra_json))
  }, error = function(e) {
    # Fallback: do not crash the pipeline if DB write fails.
    # M-7: drop the possibly-broken connection so the next call re-establishes it, preserve the
    # record in the per-PID spill file rather than losing it, and throttle the console message to
    # once per 60s so a locked DB cannot flood the run output.
    .log_disconnect()
    .log_spill(ts, level, script, msg, extra_json)
    now <- as.numeric(Sys.time())
    if (now - .log_state$last_db_error_at > 60) {
      .log_state$last_db_error_at <- now
      cat(sprintf("[LOG DB ERROR] %s\n", .log_redact(conditionMessage(e))), sep = "")
    }
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
