# Config Constant Drift Audit
#
# Mechanical half of the config-constant-drift-audit skill. Parses every top-level constant out
# of config.R, then greps the rest of the repo's R scripts for numeric literals sitting near an
# identifier that looks like one of those constant names, flagging any that don't match the
# current config.R value or that contradict a nearby comment. This is the check that would have
# caught the WNBA Analytics repo's Finding C-1 (a hardcoded HCA constant mismatched against a
# comment giving the correct value) immediately instead of via live-output inspection. Ported here
# so the same class of drift is caught in this repo before it ever produces a live incident.
#
# Usage: Rscript.exe audit_constants.R   (run from anywhere; PROJECT_ROOT below is fixed)

PROJECT_ROOT <- "C:/Users/kailo/kayceeslices/NFL Analytics"
setwd(PROJECT_ROOT)

config_lines <- readLines(file.path(PROJECT_ROOT, "config.R"), warn = FALSE)

# Extract NAME <- <numeric literal> constants (skip file.path()/Sys.getenv()/vector defs — those
# aren't the "magic number" class this audit targets).
const_pattern <- "^([A-Za-z_][A-Za-z0-9_.]*)\\s*<-\\s*(-?[0-9]+\\.?[0-9]*)\\s*(#.*)?$"
const_matches <- regmatches(config_lines, regexec(const_pattern, config_lines))
constants <- Filter(function(m) length(m) == 4, const_matches)
const_df <- data.frame(
  name  = vapply(constants, `[`, character(1), 2),
  value = vapply(constants, function(m) as.numeric(m[3]), numeric(1)),
  stringsAsFactors = FALSE
)

cat(sprintf("Parsed %d numeric constants from config.R:\n", nrow(const_df)))
for (i in seq_len(nrow(const_df))) {
  cat(sprintf("  %-22s = %s\n", const_df$name[i], const_df$value[i]))
}
cat("\n")

# Detect this repo's constant-naming prefix (if any) instead of hardcoding one sport's convention
# (e.g. "WNBA_", "NFL_"). Take the leading ALL-CAPS/digits token before the first underscore of
# each constant name and use whichever token is most common across all parsed constants, as long
# as it's shared by more than one constant (a prefix used by only a single constant is more likely
# a real first word of that constant's name than a repo-wide naming convention). This keeps the
# heuristic self-adapting if this script is ever ported to yet another sport's repo.
detected_prefix <- NA_character_
if (nrow(const_df) > 0) {
  leading_tokens <- sub("^([A-Z0-9]+)_.*$", "\\1", const_df$name)
  has_prefix <- grepl("^[A-Z0-9]+_", const_df$name)
  if (any(has_prefix)) {
    tok_counts <- table(leading_tokens[has_prefix])
    top_tok <- names(tok_counts)[which.max(tok_counts)]
    if (tok_counts[[top_tok]] > 1) detected_prefix <- top_tok
  }
}
if (!is.na(detected_prefix)) {
  cat(sprintf("Detected constant-name prefix: %s_ (stripped for name-proximity matching)\n\n", detected_prefix))
} else {
  cat("No shared constant-name prefix detected; matching on full constant names.\n\n")
}

# Scripts to scan: every *.R / *.r in the repo root and tools/, excluding config.R itself.
targets <- list.files(PROJECT_ROOT, pattern = "\\.[Rr]$", full.names = TRUE, recursive = TRUE)
targets <- targets[!grepl("/config\\.R$", targets, ignore.case = TRUE)]
targets <- targets[!grepl("/(cache|data|logs|\\.claude)/", targets)]

findings <- list()

numeric_literal_pattern <- "(?<![A-Za-z0-9_.])(-?[0-9]+\\.[0-9]+|-?[0-9]{2,})(?![A-Za-z0-9_.])"

for (f in targets) {
  lines <- tryCatch(readLines(f, warn = FALSE), error = function(e) NULL)
  if (is.null(lines)) next

  for (i in seq_along(lines)) {
    line <- lines[i]
    # Skip comment-only lines and config.R sourcing boilerplate.
    if (grepl("^\\s*#", line)) next

    for (j in seq_len(nrow(const_df))) {
      cname <- const_df$name[j]
      cval  <- const_df$value[j]
      # crude "name-like" token: strip the repo's detected constant-name prefix (if any),
      # lowercase, look for substring hits nearby
      short <- if (!is.na(detected_prefix)) {
        tolower(gsub(paste0("^", detected_prefix, "_"), "", cname))
      } else {
        tolower(cname)
      }
      window <- paste(lines[max(1, i - 3):min(length(lines), i + 3)], collapse = " ")
      if (!grepl(short, window, ignore.case = TRUE, fixed = TRUE)) next
      if (!grepl("<-|=|\\(", line)) next

      lits <- regmatches(line, gregexpr(numeric_literal_pattern, line, perl = TRUE))[[1]]
      if (length(lits) == 0) next

      for (lit in lits) {
        litval <- suppressWarnings(as.numeric(lit))
        if (is.na(litval)) next
        if (abs(litval - cval) > 1e-9) {
          # Check for a comment-vs-code mismatch signature: a comment stating the *correct*
          # config.R value directly attached to THIS line -- either a trailing comment on the
          # same line, or on the immediately preceding non-blank line. Deliberately NOT the wide
          # +/-3 name-proximity window used above: that window is fine for surfacing a candidate
          # at all, but escalating to HIGH severity off of it produces false positives whenever
          # an unrelated literal on an unrelated line merely sits a few lines away from a comment
          # that happens to mention the constant's value (caught by this skill's own test suite --
          # see the false-positive check in its SKILL.md).
          val_str <- format(cval, trim = TRUE)
          prev_line <- if (i > 1) lines[i - 1] else ""
          same_line_comment <- grepl(sprintf("#.*%s", val_str), line)
          prev_line_comment  <- grepl(sprintf("^\\s*#.*%s", val_str), prev_line)
          comment_has_correct_value <- same_line_comment || prev_line_comment
          findings[[length(findings) + 1]] <- list(
            file = sub(paste0(PROJECT_ROOT, "/?"), "", f, fixed = TRUE),
            line = i,
            constant = cname,
            expected = cval,
            found = litval,
            comment_flag = comment_has_correct_value,
            context = trimws(line)
          )
        }
      }
    }
  }
}

cat(sprintf("\n=== %d candidate finding(s) ===\n\n", length(findings)))
if (length(findings) == 0) {
  cat("No drift candidates found. (This is expected on a clean main branch.)\n")
} else {
  for (f in findings) {
    severity <- if (f$comment_flag) "HIGH (comment states expected value nearby)" else "review"
    cat(sprintf(
      "[%s] %s:%d\n  constant=%s expected=%s found=%s\n  > %s\n\n",
      severity, f$file, f$line, f$constant, f$expected, f$found, f$context
    ))
  }
}

cat(paste(
  "\nReminder: this is a name-proximity heuristic, not a type/scope-aware analyzer.",
  "Triage every finding by hand -- a mismatch may mean config.R is stale rather than the call",
  "site being wrong, and some findings will be unrelated numeric literals that happen to sit",
  "near a similarly-named identifier.\n"
))
