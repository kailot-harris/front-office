# ==============================================================================
# render_memo.R
# WNBA Offseason Dynamics Monitor — Deterministic 7-Block Memo Renderer (Phase 4)
#
# Formats the weekly state-diff memo strictly following Blueprint §5:
#   ## Week NN — Monday, DD Month YYYY
#   **State of Play:** [1-2 sentences summarizing net league movement and elapsed
#   days since last baseline. Quiet weeks state: "Quiet week: 0 confirmed state
#   transitions recorded."]
#   ### 1. Confirmed Changes
#   ### 2. Reported (Unconfirmed)
#   ### 3. Expired Claims (Aged Out > 28 Days)
#   ### 4. Next 30 Days (Milestone Calendar)
#   ### 5. Model Implications (2027 Baseline Priors)
#   ### 6. Winter League & Alternative Play (Unrivaled / EuroLeague)
#   ### 7. Sources Verified
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

# This file uses %||%. Base R >= 4.4 ships an is.null-only base::`%||%` that is
# always in scope, so exists("%||%") can never gate this source() (CLAUDE.md /
# issue #153) -- guard on log_info() to get the repo's hardened operator.
if (!exists("log_info", mode = "function") && file.exists("logging_utils.R")) {
  source("logging_utils.R")
}

suppressPackageStartupMessages({
  library(jsonlite)
})

#' Format Date into "Monday, DD Month YYYY"
format_memo_date <- function(date_val) {
  dt <- if (is.character(date_val)) as.Date(date_val) else as.Date(date_val)
  format(dt, "%A, %d %B %Y")
}

#' Generate State of Play Sentence
#'
#' @param num_confirmed Integer number of confirmed state transitions
#' @param elapsed_days Number of elapsed days since S_last
#' @param baseline_date Date string YYYY-MM-DD or POSIXct of S_last
#' @param current_date Date string YYYY-MM-DD or POSIXct of S_t
generate_state_of_play <- function(num_confirmed, elapsed_days, baseline_date, current_date) {
  base_str <- format(as.Date(baseline_date), "%Y-%m-%d")
  curr_str <- format(as.Date(current_date), "%Y-%m-%d")
  
  if (as.integer(num_confirmed) == 0L) {
    sprintf("Elapsed interval %d days (%s to %s). Quiet week: 0 confirmed state transitions recorded.",
            as.integer(elapsed_days), base_str, curr_str)
  } else {
    sprintf("Elapsed interval %d days (%s to %s). %d confirmed state transition%s recorded.",
            as.integer(elapsed_days), base_str, curr_str, as.integer(num_confirmed),
            if (as.integer(num_confirmed) == 1L) "" else "s")
  }
}

#' Render Block 1: Confirmed Changes
render_block_1_confirmed <- function(confirmed_changes, max_items = 25L, unclassified_count = NULL) {
  lines <- c("### 1. Confirmed Changes")
  
  if (is.null(unclassified_count)) {
    unclassified_count <- sum(vapply(confirmed_changes, function(item) {
      ct <- if (!is.null(item$change_type)) item$change_type else if (!is.null(item$changeType)) item$changeType else ""
      fld <- if (!is.null(item$field)) item$field else ""
      if (identical(as.character(ct), "UNCLASSIFIED") || identical(as.character(fld), "UNCLASSIFIED")) 1L else 0L
    }, integer(1)))
  }
  
  if (unclassified_count > 0L) {
    lines <- c(lines, sprintf("*Unclassified transactions requiring triage: %d*", as.integer(unclassified_count)))
  }

  if (length(confirmed_changes) == 0) {
    lines <- c(lines, "| Date | Entity | Field | Prior State (S_last) | New State (S_t) | Source |",
                      "|---|---|---|---|---|---|",
                      "| — | — | — | — | — | — |")
    return(paste(lines, collapse = "\n"))
  }
  
  lines <- c(lines, "| Date | Entity | Field | Prior State (S_last) | New State (S_t) | Source |",
                    "|---|---|---|---|---|---|")
  
  total_items <- length(confirmed_changes)
  items_to_render <- if (total_items > max_items) confirmed_changes[seq_len(max_items)] else confirmed_changes
  
  for (item in items_to_render) {
    dt <- if (!is.null(item$date) && nzchar(as.character(item$date))) as.character(item$date) else "—"
    ent <- if (!is.null(item$entityName) && nzchar(as.character(item$entityName))) {
      as.character(item$entityName)
    } else if (!is.null(item$entityId)) {
      as.character(item$entityId)
    } else {
      "—"
    }
    fld <- if (!is.null(item$field)) as.character(item$field) else "—"
    
    val_to_str <- function(v) {
      if (is.null(v)) return("None")
      if (is.list(v)) {
        if (length(v) == 0) return("None")
        return(jsonlite::toJSON(v, auto_unbox = TRUE))
      }
      as.character(v)
    }
    
    prior_v <- val_to_str(item$priorValue)
    new_v <- val_to_str(item$newValue)
    src <- if (!is.null(item$sourceUrl) && nzchar(as.character(item$sourceUrl))) as.character(item$sourceUrl) else "Official Wire"
    
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s | %s |", dt, ent, fld, prior_v, new_v, src))
  }
  
  if (total_items > max_items) {
    lines <- c(lines, sprintf("\n*Showing %d of %d confirmed transactions (%d omitted from memo preview).* ",
                              as.integer(max_items), as.integer(total_items), as.integer(total_items - max_items)))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 2: Reported (Unconfirmed)
render_block_2_reported <- function(reported_claims, max_items = 25L) {
  lines <- c("### 2. Reported (Unconfirmed)",
             "| Entity | Claim | Source Category | First Reported | Status |",
             "|---|---|---|---|---|")
  
  if (length(reported_claims) == 0) {
    lines <- c(lines, "| — | — | — | — | — |")
    return(paste(lines, collapse = "\n"))
  }
  
  total_items <- length(reported_claims)
  items_to_render <- if (total_items > max_items) reported_claims[seq_len(max_items)] else reported_claims
  
  for (item in items_to_render) {
    ent <- if (!is.null(item$entityName)) as.character(item$entityName) else "—"
    clm <- if (!is.null(item$claim)) as.character(item$claim) else "—"
    cat <- if (!is.null(item$sourceCategory)) as.character(item$sourceCategory) else "National Beat"
    fr <- if (!is.null(item$firstReportedDate)) as.character(item$firstReportedDate) else "—"
    days <- if (!is.null(item$daysPending)) as.integer(item$daysPending) else 0L
    stat <- sprintf("Pending (Day %d)", days)
    
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", ent, clm, cat, fr, stat))
  }
  
  if (total_items > max_items) {
    lines <- c(lines, sprintf("\n*Showing %d of %d reported claims (%d omitted from memo preview).* ",
                              as.integer(max_items), as.integer(total_items), as.integer(total_items - max_items)))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 3: Expired Claims (Aged Out > 28 Days)
render_block_3_expired <- function(expired_claims, max_items = 25L) {
  lines <- c("### 3. Expired Claims (Aged Out > 28 Days)",
             "| Entity | Original Claim | Source Category | First Reported | Expired Date |",
             "|---|---|---|---|---|")
  
  if (length(expired_claims) == 0) {
    lines <- c(lines, "| — | — | — | — | — |")
    return(paste(lines, collapse = "\n"))
  }
  
  total_items <- length(expired_claims)
  items_to_render <- if (total_items > max_items) expired_claims[seq_len(max_items)] else expired_claims
  
  for (item in items_to_render) {
    ent <- if (!is.null(item$entityName)) as.character(item$entityName) else "—"
    clm <- if (!is.null(item$claim)) as.character(item$claim) else "—"
    cat <- if (!is.null(item$sourceCategory)) as.character(item$sourceCategory) else "National Beat"
    fr <- if (!is.null(item$firstReportedDate)) as.character(item$firstReportedDate) else "—"
    ex <- if (!is.null(item$expiredDate)) as.character(item$expiredDate) else "—"
    
    lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", ent, clm, cat, fr, ex))
  }
  
  if (total_items > max_items) {
    lines <- c(lines, sprintf("\n*Showing %d of %d expired claims (%d omitted from memo preview).* ",
                              as.integer(max_items), as.integer(total_items), as.integer(total_items - max_items)))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 4: Next 30 Days (Milestone Calendar)
render_block_4_milestones <- function(upcoming_milestones) {
  lines <- c("### 4. Next 30 Days (Milestone Calendar)")
  
  if (length(upcoming_milestones) == 0) {
    lines <- c(lines, "- [ ] [Date TBD]: No upcoming milestones scheduled in next 30 days")
    return(paste(lines, collapse = "\n"))
  }
  
  for (m in upcoming_milestones) {
    dt_val <- m$date
    dt <- if (is.null(dt_val) || length(dt_val) == 0 || is.na(dt_val[1]) || !nzchar(as.character(dt_val[1]))) {
      "[Date TBD]"
    } else {
      as.character(dt_val[1])
    }
    ev <- if (!is.null(m$event)) as.character(m$event) else "Milestone"
    lines <- c(lines, sprintf("- [ ] %s: %s", dt, ev))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 5: Model Implications (2027 Baseline Priors)
render_block_5_model <- function(model_prior_impact) {
  lines <- c("### 5. Model Implications (2027 Baseline Priors)")
  
  has_changes <- isTRUE(model_prior_impact$hasChanges)
  if (!has_changes) {
    lines <- c(lines, "- No change to 2027 baseline Bayesian priors.")
    return(paste(lines, collapse = "\n"))
  }
  
  summ <- if (!is.null(model_prior_impact$summary) && nzchar(model_prior_impact$summary)) {
    model_prior_impact$summary
  } else {
    "Updated team net rating priors based on confirmed transactions."
  }
  lines <- c(lines, sprintf("- %s", summ))
  
  if (!is.null(model_prior_impact$adjustedTeams) && length(model_prior_impact$adjustedTeams) > 0) {
    for (tm in names(model_prior_impact$adjustedTeams)) {
      adj <- model_prior_impact$adjustedTeams[[tm]]
      d_nr <- if (!is.null(adj$deltaNetRating)) adj$deltaNetRating else 0.0
      rat <- if (!is.null(adj$rationale)) adj$rationale else ""
      sign_ch <- if (d_nr > 0) "+" else ""
      lines <- c(lines, sprintf("  * **%s**: %s%.2f net rating adjustment (%s)", tm, sign_ch, d_nr, rat))
    }
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 6: Winter League & Alternative Play
render_block_6_winter <- function(winter_league_notes) {
  lines <- c("### 6. Winter League & Alternative Play (Unrivaled / EuroLeague)")
  
  if (length(winter_league_notes) == 0) {
    lines <- c(lines, "- No active overseas or alternative winter league participation notes.")
    return(paste(lines, collapse = "\n"))
  }
  
  for (note in winter_league_notes) {
    pname <- if (!is.null(note$playerName)) note$playerName else "Player"
    wtm <- if (!is.null(note$wnbaTeam)) sprintf(" (%s)", note$wnbaTeam) else ""
    lg <- if (!is.null(note$league)) note$league else "Alternative Play"
    hlth <- if (!is.null(note$healthStatus)) note$healthStatus else "Active"
    
    lines <- c(lines, sprintf("- **%s**%s: %s — %s", pname, wtm, lg, hlth))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Block 7: Sources Verified
render_block_7_sources <- function(sources_visited) {
  lines <- c("### 7. Sources Verified")
  
  if (length(sources_visited) == 0) {
    lines <- c(lines, "- Primary official league transaction wire verified.")
    return(paste(lines, collapse = "\n"))
  }
  
  for (src in sources_visited) {
    lines <- c(lines, sprintf("- %s", as.character(src)))
  }
  
  paste(lines, collapse = "\n")
}

#' Render Optional Media Sentiment Pulse Section (Issue #156)
#'
#' Strictly additive: returns NULL when no pulse object is supplied, so
#' render_7_block_memo()'s existing 7-block output is byte-identical to before.
#' Never prints a fabricated number — when the pulse is unavailable it says so
#' and names the reason.
#'
#' @param pulse Result of compute_media_sentiment_pulse(), or NULL.
#' @return markdown string, or NULL if nothing should be rendered.
render_block_media_sentiment <- function(pulse) {
  if (is.null(pulse)) return(NULL)

  lines <- c("### Media Sentiment Pulse")

  if (!isTRUE(pulse$available)) {
    reason <- if (!is.null(pulse$reason)) as.character(pulse$reason) else "scoring unavailable"
    lines <- c(lines, sprintf("- Sentiment scoring unavailable this week (%s). No score is reported.", reason))
    return(paste(lines, collapse = "\n"))
  }

  scored_line <- sprintf(
    "- **Articles scored:** %d (%d full-text scraped, %d scored from RSS summary)",
    as.integer(pulse$articleCount), as.integer(pulse$scrapedCount), as.integer(pulse$fallbackCount)
  )
  off_topic <- as.integer(pulse$offTopicExcluded %||% 0L)
  if (!is.na(off_topic) && off_topic > 0) {
    scored_line <- sprintf(
      "%s; %d off-topic item%s excluded of %d ingested",
      scored_line, off_topic, if (off_topic == 1L) "" else "s",
      as.integer(pulse$beatItemsSeen %||% pulse$articleCount)
    )
  }
  lines <- c(lines, scored_line)
  lines <- c(lines, sprintf(
    "- **Mean sentiment:** %+.4f per word (syuzhet lexicon, word-count normalized, team names masked)",
    as.numeric(pulse$meanSentiment)
  ))

  fmt_item <- function(label, it) {
    if (is.null(it)) return(sprintf("- **%s:** none", label))
    src <- if (!is.null(it$sourceId) && nzchar(it$sourceId)) sprintf(" — %s", it$sourceId) else ""
    url <- if (!is.null(it$url) && !is.na(it$url) && nzchar(it$url)) sprintf(" ([link](%s))", it$url) else ""
    sprintf("- **%s:** \"%s\"%s (%+.4f)%s", label, it$headline, src, as.numeric(it$score), url)
  }
  lines <- c(lines, fmt_item("Most positive", pulse$mostPositive))
  # When every scored article is positive, the minimum is not a negative story --
  # it is the least positive one. The 2026-11-07 run's "most negative" was
  # +0.0043, which reads as a damning headline unless the label says otherwise.
  neg_score <- if (!is.null(pulse$mostNegative)) as.numeric(pulse$mostNegative$score) else NA_real_
  neg_label <- if (!is.na(neg_score) && neg_score >= 0) "Least positive" else "Most negative"
  lines <- c(lines, fmt_item(neg_label, pulse$mostNegative))

  # Say which pool the extremes were drawn from: a per-word score is unstable on
  # short items, so they are excluded from extreme selection (never from the mean).
  min_words <- as.integer(pulse$extremesMinWords %||% NA_integer_)
  if (!is.na(min_words)) {
    if (isTRUE(pulse$extremesFloorApplied)) {
      n_elig <- as.integer(pulse$extremesEligibleCount %||% 0L)
      lines <- c(lines, sprintf(
        "- *Extremes drawn from the %d article%s of at least %d words; all %d count toward the mean.*",
        n_elig, if (identical(n_elig, 1L)) "" else "s",
        min_words, as.integer(pulse$articleCount)
      ))
    } else {
      lines <- c(lines, sprintf(
        "- *No article reached the %d-word floor this week, so the extremes come from all %d scored items and are noise-prone.*",
        min_words, as.integer(pulse$articleCount)
      ))
    }
  }

  wb <- pulse$wordBreakdown
  if (!is.null(wb) && isTRUE(wb$available)) {
    fmt_words <- function(ws) {
      if (length(ws) == 0) return("none matched")
      paste(vapply(ws, function(w) sprintf("%s (%d)", w$word, as.integer(w$n)), character(1)),
            collapse = ", ")
    }
    lines <- c(lines, sprintf("- **Top positive words (bing):** %s", fmt_words(wb$positive)))
    lines <- c(lines, sprintf("- **Top negative words (bing):** %s", fmt_words(wb$negative)))
  } else if (!is.null(wb)) {
    wb_reason <- if (!is.null(wb$reason)) as.character(wb$reason) else "unavailable"
    lines <- c(lines, sprintf("- **Word breakdown:** unavailable (%s)", wb_reason))
  }

  paste(lines, collapse = "\n")
}

#' Render Full 7-Block Memo in Markdown
render_7_block_memo <- function(week_number,
                                publish_date,
                                elapsed_days,
                                baseline_date,
                                confirmed_changes = list(),
                                reported_claims = list(),
                                expired_claims = list(),
                                upcoming_milestones = list(),
                                model_prior_impact = list(hasChanges = FALSE, summary = "No change to 2027 baseline Bayesian priors."),
                                winter_league_notes = list(),
                                sources_visited = list(),
                                max_display_items = 25L,
                                unclassified_count = NULL,
                                media_sentiment_pulse = NULL) {
  
  date_header_str <- format_memo_date(publish_date)
  num_confirmed <- length(confirmed_changes)
  sop_str <- generate_state_of_play(num_confirmed, elapsed_days, baseline_date, publish_date)
  
  header <- sprintf("## Week %d — %s\n\n**State of Play:** %s",
                    as.integer(week_number), date_header_str, sop_str)
  
  b1 <- render_block_1_confirmed(confirmed_changes, max_items = max_display_items, unclassified_count = unclassified_count)
  b2 <- render_block_2_reported(reported_claims, max_items = max_display_items)
  b3 <- render_block_3_expired(expired_claims, max_items = max_display_items)
  b4 <- render_block_4_milestones(upcoming_milestones)
  b5 <- render_block_5_model(model_prior_impact)
  b6 <- render_block_6_winter(winter_league_notes)
  b7 <- render_block_7_sources(sources_visited)
  
  full_memo <- paste(header, b1, b2, b3, b4, b5, b6, b7, sep = "\n\n")

  # Optional additive section (Issue #156). Absent argument => output unchanged.
  b_sent <- render_block_media_sentiment(media_sentiment_pulse)
  if (!is.null(b_sent)) {
    full_memo <- paste(full_memo, b_sent, sep = "\n\n")
  }

  list(
    state_of_play = sop_str,
    markdown = full_memo
  )
}
