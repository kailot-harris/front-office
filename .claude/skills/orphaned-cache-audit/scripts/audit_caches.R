# Orphaned Cache Audit
#
# Mechanical half of the orphaned-cache-audit skill. For every CACHE_*-style config.R constant
# (plus known bare-literal exceptions), checks whether the repo actually contains a producer
# (saveRDS/write.csv) and a consumer (readRDS/read.csv/file.exists) beyond data_health_probe.R's
# own existence check -- the check that would have caught cache/features_cache.rds sitting with a
# constant, a health-probe check, and zero producer for 3 remediation waves.
#
# Usage: Rscript.exe audit_caches.R

PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_ROOT)

config_lines <- readLines(file.path(PROJECT_ROOT, "config.R"), warn = FALSE)

# Extract NAME <- file.path(...) / NAME <- "literal" constants pointing under cache/ or data/.
const_pattern <- "^([A-Za-z_][A-Za-z0-9_.]*)\\s*<-\\s*(.+?)\\s*(#.*)?$"
const_matches <- regmatches(config_lines, regexec(const_pattern, config_lines))
constants <- Filter(function(m) length(m) == 4 && grepl("cache|CACHE_DIR|data", m[3]), const_matches)

resolve_literal <- function(name, rhs) {
  # Best-effort: extract the trailing quoted filename component of a file.path(...) call, or a
  # bare quoted literal. Good enough to build a repo-wide grep pattern -- this is a heuristic
  # audit, not a real R evaluator.
  m <- regmatches(rhs, gregexpr('"[^"]+"', rhs))[[1]]
  if (length(m) == 0) return(NA_character_)
  gsub('"', "", m[length(m)])
}

const_df <- data.frame(
  name = vapply(constants, `[`, character(1), 2),
  literal = vapply(constants, function(m) resolve_literal(m[2], m[3]), character(1)),
  stringsAsFactors = FALSE
)
const_df <- const_df[!is.na(const_df$literal) & grepl("\\.(rds|csv|duckdb)$", const_df$literal), ]

# Known bare-literal exception documented in CLAUDE.md: no config.R constant at all, by design.
known_literals <- data.frame(
  name = "LITERAL ONLY",
  literal = "projected_wnba_standings.rds",
  stringsAsFactors = FALSE
)
const_df <- rbind(const_df, known_literals)

cat(sprintf("Checking %d cache path(s):\n", nrow(const_df)))
for (i in seq_len(nrow(const_df))) {
  cat(sprintf("  %-22s -> %s\n", const_df$name[i], const_df$literal[i]))
}
cat("\n")

# Scan targets: every *.R/*.r/*.py in the repo, excluding config.R and the audit script itself.
targets <- list.files(PROJECT_ROOT, pattern = "\\.(R|r|py)$", full.names = TRUE, recursive = TRUE)
targets <- targets[!grepl("/config\\.R$", targets, ignore.case = TRUE)]
targets <- targets[!grepl("/(cache|data|logs|\\.claude)/", targets)]

producer_pattern <- "saveRDS\\s*\\(|write\\.csv\\s*\\(|write_csv\\s*\\("
consumer_pattern <- "readRDS\\s*\\(|read\\.csv\\s*\\(|read_csv\\s*\\(|file\\.exists\\s*\\("

# Known-clean allowlist: caches that are legitimately producer-only or diagnostic-only for now.
# Any new entry here must be justified in this audit's own output, not silently excluded.
allowlist <- list()

results <- list()

for (i in seq_len(nrow(const_df))) {
  name <- const_df$name[i]
  lit  <- const_df$literal[i]
  producers <- character(0)
  consumers_health_probe_only <- TRUE
  consumers <- character(0)

  for (f in targets) {
    lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) NULL)
    if (is.null(lines)) next
    hit_lines <- lines[grepl(lit, lines, fixed = TRUE) | grepl(name, lines, fixed = TRUE)]
    if (length(hit_lines) == 0) next

    is_probe <- grepl("data_health_probe\\.R$", f)

    for (hl in hit_lines) {
      if (grepl(producer_pattern, hl)) {
        producers <- c(producers, sub(paste0(PROJECT_ROOT, "/?"), "", f, fixed = TRUE))
      }
      if (grepl(consumer_pattern, hl)) {
        consumers <- c(consumers, sub(paste0(PROJECT_ROOT, "/?"), "", f, fixed = TRUE))
        if (!is_probe) consumers_health_probe_only <- FALSE
      }
    }
  }

  producers <- unique(producers)
  consumers <- unique(consumers)
  real_consumer <- length(consumers) > 0 && !consumers_health_probe_only

  classification <- if (length(producers) > 0 && real_consumer) {
    "OK"
  } else if (length(producers) == 0 && length(consumers) > 0) {
    "ORPHANED"
  } else if (length(producers) > 0 && !real_consumer) {
    "DEAD"
  } else {
    "UNUSED"
  }

  if (name %in% names(allowlist) && classification == allowlist[[name]]) {
    classification <- paste0(classification, " (allowlisted)")
  }

  results[[length(results) + 1]] <- list(
    name = name, literal = lit, producers = producers, consumers = consumers,
    classification = classification
  )
}

cat("=== Findings ===\n\n")
n_ok <- 0L
for (r in results) {
  if (startsWith(r$classification, "OK")) n_ok <- n_ok + 1L
  cat(sprintf("[%s] %s (%s)\n", r$classification, r$name, r$literal))
  cat(sprintf("  producers: %s\n", if (length(r$producers)) paste(r$producers, collapse = ", ") else "(none)"))
  cat(sprintf("  consumers: %s\n\n", if (length(r$consumers)) paste(r$consumers, collapse = ", ") else "(none)"))
}

cat(sprintf(
  "VERDICT: %d/%d cache(s) OK. Review any ORPHANED/DEAD/UNUSED finding above by hand before acting --\n",
  n_ok, length(results)
))
cat("this is a name/literal-string grep, not a real call graph.\n")
