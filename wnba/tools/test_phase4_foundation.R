# ==============================================================================
# tools/test_phase4_foundation.R
#
# Phase 4 Wave 1 (P4-C / agent_foundation) verification suite.
# Covers findings C-1 (WNBA_HCA constant), H-2 (join_rapm_to_roster), H-1 (log
# redaction), M-6 (canonical %||%), M-7 (log connection lifecycle), L-2 (config
# comment accuracy).
#
# Run:  "C:/Program Files/R/R-4.5.2/bin/Rscript.exe" tools/test_phase4_foundation.R
# Exits 0 only if every check PASSes.
# ==============================================================================

setwd("C:/Users/kailo/kayceeslices/WNBA Analytics")

suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
})

.fails <- 0L
ok <- function(label, cond, detail = "") {
  cond <- isTRUE(cond)
  if (!cond) .fails <<- .fails + 1L
  cat(sprintf("[%s] %s%s\n", if (cond) "PASS" else "FAIL", label,
              if (nzchar(detail)) paste0("  -- ", detail) else ""))
}

cat("=== Phase 4 Wave 1 foundation tests ===\n\n")

# ------------------------------------------------------------------------------
# CHECK 1 (C-1): WNBA_HCA exists in config.R and equals 2.40
# ------------------------------------------------------------------------------
source("config.R")
ok("CHECK 1 (C-1) config.R defines WNBA_HCA == 2.40",
   exists("WNBA_HCA") && is.numeric(WNBA_HCA) && isTRUE(all.equal(WNBA_HCA, 2.40)),
   sprintf("WNBA_HCA = %s (class %s)",
           if (exists("WNBA_HCA")) format(WNBA_HCA) else "<missing>",
           if (exists("WNBA_HCA")) class(WNBA_HCA) else "-"))

# ------------------------------------------------------------------------------
# CHECK 2 (H-2): join_rapm_to_roster() against the REAL caches
# ------------------------------------------------------------------------------
source("logging_utils.R")
source("rapm_join_utils.R")

rost <- readRDS(file.path(CACHE_DIR, "active_rosters_cache.rds"))
rapm <- readRDS(file.path(CACHE_DIR, "rapm_ratings.rds"))
cat(sprintf("\n  roster rows: %d   rapm rows: %d\n", nrow(rost), nrow(rapm)))
cat(sprintf("  raw player_id types -- roster: %s, rapm: %s; raw ID overlap: %d\n",
            class(rost$player_id)[1], class(rapm$player_id)[1],
            length(intersect(as.character(rost$player_id), as.character(rapm$player_id)))))

joined <- join_rapm_to_roster(rost, rapm)

# 2a. every WNBA_TEAMS abbreviation gets >= 1 matched player
per_team <- joined |> count(team_abbreviation, name = "matched")
missing_teams <- setdiff(names(WNBA_TEAMS), per_team$team_abbreviation)
cat("\n  matched players per team:\n")
print(as.data.frame(per_team), row.names = FALSE)
ok("CHECK 2a (H-2) all 15 WNBA_TEAMS have >= 1 matched player",
   length(missing_teams) == 0 && nrow(per_team) == length(WNBA_TEAMS) && all(per_team$matched >= 1),
   sprintf("%d/%d teams matched, min %d players/team; missing: %s",
           nrow(per_team), length(WNBA_TEAMS), min(per_team$matched),
           if (length(missing_teams)) paste(missing_teams, collapse = ",") else "none"))

# 2b. collision safety: ROSTER side must have 0 duplicate (team, last_name) groups,
#     and the helper's OUTPUT must be 1 row per roster player (no join fan-out).
rost_key <- rost |>
  mutate(last_name = normalize_rapm_last_name(player_name)) |>
  count(team_name, last_name)
roster_dups <- sum(rost_key$n > 1)

rapm_key <- rapm |>
  mutate(last_name = normalize_rapm_last_name(player_name, from_full_name = FALSE)) |>
  count(team, last_name)
rapm_dups <- sum(rapm_key$n > 1)

out_dups <- sum(joined |> count(team_abbreviation, player_id) |> pull(n) > 1)
cat(sprintf("\n  duplicate (team,last_name) groups -- roster side: %d | rapm side: %d\n",
            roster_dups, rapm_dups))
cat(sprintf("  helper output: %d rows for %d distinct roster players (%d ambiguous, deduped)\n",
            nrow(joined), n_distinct(joined$player_id), sum(joined$rapm_ambiguous)))
ok("CHECK 2b (H-2) 0 duplicate (team,last_name) on roster side; helper emits 1 row/player",
   roster_dups == 0 && out_dups == 0 && nrow(joined) == n_distinct(joined$player_id),
   sprintf("roster_dups=%d, output_dup_groups=%d (rapm side has %d collision groups, resolved by helper)",
           roster_dups, out_dups, rapm_dups))

# 2c. total_rapm present and usable
ok("CHECK 2c (H-2) output carries a numeric total_rapm with no NAs",
   "total_rapm" %in% names(joined) && is.numeric(joined$total_rapm) && !any(is.na(joined$total_rapm)),
   sprintf("range %.2f .. %.2f", min(joined$total_rapm), max(joined$total_rapm)))

# 2d. REGRESSION GUARD for agent_engine (Wave 2): the per-team max total_rapm that
#     market_odds_engine.R::calculate_matchup_delta() uses must be unchanged vs. the
#     legacy inline fan-out join it is replacing.
legacy <- rost |>
  mutate(last_name = tolower(trimws(gsub("[^a-zA-Z ]", "", word(player_name, -1))))) |>
  inner_join(rapm |> mutate(last_name = tolower(trimws(gsub("[^a-zA-Z ]", "", player_name)))),
             by = c("team_name" = "team", "last_name")) |>
  group_by(team_abbreviation) |> summarise(top = max(total_rapm), .groups = "drop")
newtop <- joined |> group_by(team_abbreviation) |> summarise(top = max(total_rapm), .groups = "drop")
cmp <- full_join(legacy, newtop, by = "team_abbreviation", suffix = c("_legacy", "_helper"))
ok("CHECK 2d (H-2) per-team top total_rapm identical to legacy market_odds_engine join",
   nrow(cmp) == length(WNBA_TEAMS) && isTRUE(all.equal(cmp$top_legacy, cmp$top_helper)),
   sprintf("max abs diff = %g across %d teams",
           max(abs(cmp$top_legacy - cmp$top_helper)), nrow(cmp)))

# 2e. fail-safe: bad input warns and returns 0 rows, never errors
safe <- tryCatch(suppressWarnings(join_rapm_to_roster(NULL, rapm)),
                 error = function(e) e)
ok("CHECK 2e (H-2) fail-safe on NULL input (warn + 0 rows, no error)",
   is.data.frame(safe) && nrow(safe) == 0,
   if (inherits(safe, "error")) paste("ERRORED:", conditionMessage(safe)) else "returned 0-row frame")

# ------------------------------------------------------------------------------
# CHECK 3 (H-1): secrets are redacted before reaching any log sink
# ------------------------------------------------------------------------------
SECRET  <- "SUPERSECRET123"
fake_url <- paste0("https://api.the-odds-api.com/v4/sports/basketball_wnba/odds/?",
                   "apiKey=", SECRET, "&regions=us,us2,eu&markets=h2h&oddsFormat=american")
fake_hook <- paste0("https://discord.com/api/webhooks/1234567890/", SECRET, "-more")

rendered <- .log_format_extra(list(call = "fetch_market_odds()", url = fake_url,
                                   condition_message = paste("GET failed for", fake_url)))
cat("\n  .log_format_extra() rendered ->", rendered, "\n")
ok("CHECK 3a (H-1) apiKey scrubbed from .log_format_extra() output",
   !grepl(SECRET, rendered, fixed = TRUE) && grepl("REDACTED", rendered),
   sprintf("secret present = %s", grepl(SECRET, rendered, fixed = TRUE)))

hook_red <- .log_redact(fake_hook)
cat("  .log_redact(discord webhook) ->", hook_red, "\n")
ok("CHECK 3b (H-1) Discord webhook path scrubbed",
   !grepl(SECRET, hook_red, fixed = TRUE) && grepl("REDACTED", hook_red))

# Full end-to-end: the line written to console/text log/DuckDB.
before_n <- tryCatch(DBI::dbGetQuery(.log_get_con(), "SELECT COUNT(*) n FROM logs")$n, error = function(e) NA)
cat("  -- log_error() end-to-end (line below is the real logger output) --\n")
line <- log_error("PHASE4 FOUNDATION TEST (H-1 redaction probe).",
                  script = "test_phase4_foundation.R",
                  call = "fetch_market_odds()", url = fake_url, webhook = fake_hook)
after_n <- tryCatch(DBI::dbGetQuery(.log_get_con(), "SELECT COUNT(*) n FROM logs")$n, error = function(e) NA)
db_row <- tryCatch(
  DBI::dbGetQuery(.log_get_con(),
                  "SELECT message, extra_json FROM logs WHERE message LIKE '%PHASE4 FOUNDATION TEST%' ORDER BY timestamp DESC LIMIT 1"),
  error = function(e) NULL)
tail_txt <- tryCatch(tail(readLines(LOG_FILE, warn = FALSE), 3), error = function(e) character(0))
db_clean  <- is.null(db_row) || nrow(db_row) == 0 || !any(grepl(SECRET, unlist(db_row), fixed = TRUE))
txt_clean <- !any(grepl(SECRET, tail_txt, fixed = TRUE))
ok("CHECK 3c (H-1) secret absent from text log AND logs.duckdb row",
   db_clean && txt_clean && !is.null(db_row) && nrow(db_row) == 1,
   sprintf("duckdb extra_json = %s",
           if (!is.null(db_row) && nrow(db_row)) substr(db_row$extra_json[1], 1, 120) else "<no row>"))

# ------------------------------------------------------------------------------
# CHECK 3d (M-7): one connection reused for the process lifetime
# ------------------------------------------------------------------------------
c1 <- .log_get_con(); invisible(log_info("PHASE4 M-7 connection reuse probe.", script = "test_phase4_foundation.R"))
c2 <- .log_get_con()
ok("CHECK 3d (M-7) .log_write() reuses one process-lifetime DuckDB connection",
   identical(c1, c2) && DBI::dbIsValid(c2) && !is.na(after_n) && after_n == before_n + 1,
   sprintf("same connection object = %s; rows %s -> %s across one log_error()",
           identical(c1, c2), before_n, after_n))

# 3e (M-7): a DB write failure must SPILL the record, not drop it, and must not redact-leak.
if (file.exists(LOG_SPILL_FILE())) unlink(LOG_SPILL_FILE())
local({
  # Simulate a locked/unavailable DB by forcing .log_get_con() to fail for one call.
  orig <- .log_get_con
  assign(".log_get_con", function() stop("simulated: DB locked by another process"),
         envir = globalenv())
  on.exit(assign(".log_get_con", orig, envir = globalenv()), add = TRUE)
  invisible(log_error("PHASE4 M-7 spill probe.", script = "test_phase4_foundation.R", url = fake_url))
})
spill_ok <- file.exists(LOG_SPILL_FILE())
spill_txt <- if (spill_ok) readLines(LOG_SPILL_FILE(), warn = FALSE) else character(0)
cat("  spill file ->", LOG_SPILL_FILE(), "\n  spill line ->",
    if (length(spill_txt)) substr(spill_txt[1], 1, 140) else "<none>", "\n")
ok("CHECK 3e (M-7) DB write failure spills the record to disk instead of dropping it",
   spill_ok && length(spill_txt) == 1 && grepl("M-7 spill probe", spill_txt[1]) &&
     !grepl(SECRET, spill_txt[1], fixed = TRUE),
   sprintf("spilled=%d line(s), secret leaked=%s",
           length(spill_txt), any(grepl(SECRET, spill_txt, fixed = TRUE))))
if (spill_ok) unlink(LOG_SPILL_FILE())

# ------------------------------------------------------------------------------
# CHECK 4 (M-6): canonical %||% survives both a scalar and a full NA vector
# ------------------------------------------------------------------------------
scalar_res <- tryCatch(list(v = (NULL %||% "fallback"), e = NULL), error = function(e) list(e = e))
scalar_res2 <- tryCatch(list(v = (NA %||% 7), e = NULL), error = function(e) list(e = e))
vec <- c(NA_real_, NA_real_, NA_real_)          # the exact crash class in CLAUDE.md
vec_res <- tryCatch(list(v = (vec %||% 0), e = NULL), error = function(e) list(e = e))
mixed   <- tryCatch(list(v = (c(1, NA, 3) %||% 0), e = NULL), error = function(e) list(e = e))
cat(sprintf("\n  NULL %%||%% 'fallback' -> %s ; NA %%||%% 7 -> %s ; c(NA,NA,NA) %%||%% 0 -> %s\n",
            scalar_res$v, scalar_res2$v, paste(vec_res$v, collapse = ",")))
ok("CHECK 4 (M-6) canonical %||% handles scalar and full-NA vector without erroring",
   is.null(scalar_res$e) && is.null(scalar_res2$e) && is.null(vec_res$e) && is.null(mixed$e) &&
     identical(scalar_res$v, "fallback") && identical(scalar_res2$v, 7) && identical(vec_res$v, 0),
   paste(c(if (!is.null(vec_res$e)) conditionMessage(vec_res$e),
           if (!is.null(mixed$e)) conditionMessage(mixed$e)), collapse = " / "))

# ------------------------------------------------------------------------------
# CHECK 5 (L-2): config.R comment citations point at files that exist
# ------------------------------------------------------------------------------
cfg <- readLines("config.R", warn = FALSE)
cited <- unique(unlist(regmatches(cfg, gregexpr("(data|cache)/window_sweep_[A-Za-z0-9_]+\\.(rds|csv)", cfg))))
exists_all <- length(cited) > 0 && all(file.exists(cited))
flagged <- any(grepl("STALENESS FLAG", cfg, fixed = TRUE))
cat(sprintf("\n  config.R cites: %s (all exist = %s)\n", paste(cited, collapse = ", "), exists_all))
ok("CHECK 5 (L-2) window-sweep citations resolve to real files + offseason staleness flagged",
   exists_all && flagged,
   sprintf("citations_exist=%s, offseason_staleness_flag=%s", exists_all, flagged))

cat(sprintf("\n=== %s: %d check(s) failed ===\n",
            if (.fails == 0L) "ALL CHECKS PASSED" else "FAILURES", .fails))
quit(status = if (.fails == 0L) 0L else 1L)
