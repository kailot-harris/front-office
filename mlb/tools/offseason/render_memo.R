# ==============================================================================
# tools/offseason/render_memo.R
# MLB 2026-2027 Off-Season Dynamics Monitor: Dual-Mode Memo Renderer
# Path: tools/offseason/render_memo.R
#
# Generates deterministic Markdown memos for both NORMAL and TRANSACTION_FREEZE modes.
#   - NORMAL: 7-block executive memo layout (State of Play, Confirmed Changes,
#     Reported (Unconfirmed), Expired Claims, Next 30 Days, Model Implications,
#     Winter Leagues & Rehab Tracking, Sources Verified).
#   - TRANSACTION_FREEZE: Collapses Blocks 1-3 to frozen notice with day counter;
#     activates Block 8 (Labor Negotiation Tracking).
#
# Conforms to blueprint §§ 5, 6, 10 and Zero-Betting Policy.
# ==============================================================================

# GitHub issue #90: Project root resolution prelude.
PROJECT_DIR <- local({
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grepl("^--file=", args)])
  start <- if (length(file_arg)) {
    dirname(normalizePath(file_arg[1], winslash = "/", mustWork = FALSE))
  } else {
    getwd()
  }
  root <- start
  while (!file.exists(file.path(root, "config.R"))) {
    parent <- dirname(root)
    if (identical(parent, root)) {
      if (file.exists(file.path(getwd(), "config.R"))) {
        return(getwd())
      }
      stop(sprintf("render_memo.R: cannot locate repo root (no config.R at or above '%s')", start))
    }
    root <- parent
  }
  root
})
setwd(PROJECT_DIR)

if (dir.exists("C:/Users/kailo/AppData/Local/R/win-library/4.5")) {
  .libPaths(unique(c("C:/Users/kailo/AppData/Local/R/win-library/4.5", .libPaths())))
}

suppressPackageStartupMessages({
  library(jsonlite)
})

# Zero-betting policy guard check
FORBIDDEN_BETTING_TERMS <- c("sportsbook", "betmgm", "draftkings", "fanduel",
                             "caesars sportsbook", "pointsbet", "bovada", "bet365",
                             "moneyline", "runline", "over/under", "parlay",
                             "\\bvig\\b", "\\bjuice\\b", "\\bprop bet\\b")

validate_zero_betting <- function(text_vector) {
  for (pattern in FORBIDDEN_BETTING_TERMS) {
    matches <- grepl(pattern, text_vector, ignore.case = TRUE)
    if (any(matches)) {
      stop(sprintf("Zero-betting policy violation: found '%s' in memo text", pattern))
    }
  }
}

.format_date_heading <- function(date_str) {
  d <- tryCatch(as.Date(date_str), error = function(e) Sys.Date())
  if (is.na(d)) d <- Sys.Date()
  format(d, "%A, %d %B %Y")
}

build_state_of_play_summary <- function(edition) {
  # 1. Transaction freeze handling
  if (isTRUE(edition$isFrozenWeek) || identical(edition$leagueOperatingStatus, "TRANSACTION_FREEZE")) {
    freeze_count <- if (!is.null(edition$freezeDayCount)) edition$freezeDayCount else 1
    minor_league_count <- 0
    if (!is.null(edition$confirmedChanges) && length(edition$confirmedChanges) > 0) {
      for (ch in edition$confirmedChanges) {
        if (identical(ch$rosterTier, "MINOR_LEAGUE")) {
          minor_league_count <- minor_league_count + 1
        }
      }
    }
    summary_text <- sprintf("Transactions frozen by lockout, day %d. No major-league state transitions are possible. Minor-league signings this window: %d (does not affect 40-man state).",
                            freeze_count, minor_league_count)
    validate_zero_betting(summary_text)
    return(summary_text)
  }

  # 2. Quiet week handling
  if (isTRUE(edition$isQuietWeek) || is.null(edition$confirmedChanges) || length(edition$confirmedChanges) == 0) {
    summary_text <- "Quiet week: 0 confirmed state transitions recorded."
    validate_zero_betting(summary_text)
    return(summary_text)
  }

  # 3. Active normal window with structured aggregation
  changes <- edition$confirmedChanges
  total_count <- if (!is.null(edition$totalConfirmedCount)) as.integer(edition$totalConfirmedCount) else length(changes)
  
  # Roster tier counts
  n_40man <- sum(vapply(changes, function(ch) identical(ch$rosterTier, "MAJOR_40_MAN"), integer(1)))
  n_minor <- sum(vapply(changes, function(ch) identical(ch$rosterTier, "MINOR_LEAGUE"), integer(1)))
  
  # Unique clubs involved
  clubs <- unique(vapply(changes, function(ch) if (!is.null(ch$team) && nzchar(ch$team)) ch$team else "FA", character(1)))
  n_clubs <- length(clubs)
  
  # Transaction type breakdown
  tx_types <- vapply(changes, function(ch) {
    if (!is.null(ch$transactionType) && nzchar(ch$transactionType)) ch$transactionType else "OTHER"
  }, character(1))
  tx_table <- sort(table(tx_types), decreasing = TRUE)
  
  format_type_name <- function(t) {
    lookup <- c(
      "FREE_AGENCY"        = "Free Agency",
      "TRADE"              = "Trade",
      "WAIVER_CLAIM"       = "Waiver Claim",
      "OUTRIGHT"           = "Outright",
      "DFA"                = "Designated for Assignment",
      "OPTION_EXERCISED"   = "Option Exercised",
      "OPTION_DECLINED"    = "Option Declined",
      "QUALIFYING_OFFER"   = "Qualifying Offer",
      "NON_TENDER"         = "Non-Tender",
      "RELEASE"            = "Release",
      "CONTRACT_EXTENSION" = "Extension"
    )
    if (t %in% names(lookup)) lookup[[t]] else gsub("_", " ", tools::toTitleCase(tolower(t)))
  }
  
  type_items <- vapply(names(tx_table), function(nm) {
    sprintf("%d %s", tx_table[[nm]], format_type_name(nm))
  }, character(1))
  type_summary <- paste(type_items, collapse = ", ")
  
  # Notable moves (prioritize 40-man tier, limit to top 3)
  major_moves <- Filter(function(ch) identical(ch$rosterTier, "MAJOR_40_MAN"), changes)
  candidate_moves <- if (length(major_moves) > 0) major_moves else changes
  
  notable_list <- character(0)
  for (ch in candidate_moves) {
    if (length(notable_list) >= 3) break
    pl <- if (!is.null(ch$playerName) && nzchar(ch$playerName)) ch$playerName else "Player"
    tm <- if (!is.null(ch$team) && nzchar(ch$team)) ch$team else "FA"
    tx <- if (!is.null(ch$transactionType)) format_type_name(ch$transactionType) else ""
    notable_list <- c(notable_list, sprintf("%s (%s, %s)", pl, tm, tx))
  }
  notable_summary <- if (length(notable_list) > 0) paste(notable_list, collapse = ", ") else "None"
  
  lead_sentence <- sprintf("%s confirmed state transitions recorded across %d club(s) (%s 40-man roster moves, %s minor-league moves).",
                           format(total_count, big.mark = ","),
                           n_clubs,
                           format(n_40man, big.mark = ","),
                           format(n_minor, big.mark = ","))
  
  summary_text <- sprintf("%s By transaction type: %s. Notable moves: %s.",
                          lead_sentence, type_summary, notable_summary)
  
  validate_zero_betting(summary_text)
  return(summary_text)
}

render_memo_normal <- function(edition) {
  week_num <- if (!is.null(edition$weekNumber)) edition$weekNumber else 1
  pub_date <- if (!is.null(edition$publishDate)) edition$publishDate else format(Sys.Date(), "%Y-%m-%d")
  date_heading <- .format_date_heading(pub_date)
  
  state_of_play <- if (!is.null(edition$stateOfPlay) && nzchar(trimws(edition$stateOfPlay)) &&
                       !grepl("free agency declarations, contract option filings", edition$stateOfPlay, fixed = TRUE)) {
    validate_zero_betting(edition$stateOfPlay)
    edition$stateOfPlay
  } else {
    build_state_of_play_summary(edition)
  }
  
  lines <- character(0)
  lines <- c(lines, sprintf("## Week %02d — %s", week_num, date_heading), "")
  lines <- c(lines, sprintf("**State of Play:** %s", state_of_play), "")
  
  # Block 1. Confirmed Changes
  lines <- c(lines, "### 1. Confirmed Changes")
  changes <- edition$confirmedChanges
  if (is.null(changes) || length(changes) == 0) {
    lines <- c(lines, "*No confirmed changes recorded this window.*", "")
  } else {
    max_table_rows <- 50L
    displayed_changes <- head(changes, max_table_rows)
    lines <- c(lines, "| Date | Team | Player | Transaction | Prior (S_last) | New (S_t) | Terms / AAV | Source |")
    lines <- c(lines, "|---|---|---|---|---|---|---|---|")
    for (ch in displayed_changes) {
      dt <- if (!is.null(ch$date)) ch$date else ""
      tm <- if (!is.null(ch$team)) ch$team else ""
      pl <- if (!is.null(ch$playerName)) ch$playerName else ""
      tx <- if (!is.null(ch$transactionType)) ch$transactionType else ""
      pr <- if (!is.null(ch$priorValue)) ch$priorValue else ""
      nw <- if (!is.null(ch$newValue)) ch$newValue else ""
      tr <- if (!is.null(ch$contractTerms) && nzchar(ch$contractTerms)) ch$contractTerms else "—"
      src <- if (!is.null(ch$sourceUrl) && nzchar(ch$sourceUrl)) ch$sourceUrl else "Wire"
      lines <- c(lines, sprintf("| %s | %s | %s | %s | %s | %s | %s | %s |", dt, tm, pl, tx, pr, nw, tr, src))
    }
    lines <- c(lines, "")
    if (length(changes) > max_table_rows) {
      lines <- c(lines, sprintf("*Showing first %d of %d confirmed changes in memo. Full ledger available in the Off-Season Dynamics Monitor.*",
                                length(displayed_changes), length(changes)), "")
    }
  }
  
  # Block 2. Reported (Unconfirmed)
  lines <- c(lines, "### 2. Reported (Unconfirmed)")
  reported <- edition$reportedClaims
  if (is.null(reported) || length(reported) == 0) {
    lines <- c(lines, "*No unconfirmed reports in the pending queue.*", "")
  } else {
    lines <- c(lines, "| Team | Claim | Source Category | First Reported | Status |")
    lines <- c(lines, "|---|---|---|---|---|")
    for (rep in reported) {
      tm <- if (!is.null(rep$team)) rep$team else ""
      clm <- if (!is.null(rep$claim)) rep$claim else ""
      src <- if (!is.null(rep$sourceCategory)) rep$sourceCategory else "Beat"
      fr <- if (!is.null(rep$firstReportedDate)) rep$firstReportedDate else ""
      dp <- if (!is.null(rep$daysPending)) rep$daysPending else 0
      lines <- c(lines, sprintf("| %s | %s | %s | %s | Pending (Day %d) |", tm, clm, src, fr, dp))
    }
    lines <- c(lines, "")
  }
  
  # Block 3. Expired Claims (Aged Out > 28 Days)
  lines <- c(lines, "### 3. Expired Claims (Aged Out > 28 Days)")
  expired <- edition$expiredClaims
  if (is.null(expired) || length(expired) == 0) {
    lines <- c(lines, "*No claims aged out (>28 days) this window.*", "")
  } else {
    lines <- c(lines, "| Team | Original Claim | Source Category | First Reported | Expired |")
    lines <- c(lines, "|---|---|---|---|---|")
    for (exp in expired) {
      tm <- if (!is.null(exp$team)) exp$team else ""
      clm <- if (!is.null(exp$claim)) exp$claim else ""
      src <- if (!is.null(exp$sourceCategory)) exp$sourceCategory else ""
      fr <- if (!is.null(exp$firstReportedDate)) exp$firstReportedDate else ""
      exd <- if (!is.null(exp$expiredDate)) exp$expiredDate else ""
      lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", tm, clm, src, fr, exd))
    }
    lines <- c(lines, "")
  }
  
  # Block 4. Next 30 Days (Milestone Calendar)
  lines <- c(lines, "### 4. Next 30 Days (Milestone Calendar)")
  milestones <- edition$upcomingMilestones
  if (is.null(milestones) || length(milestones) == 0) {
    lines <- c(lines, "- [ ] No upcoming milestones scheduled in the next 30 days.", "")
  } else {
    for (m in milestones) {
      dt <- if (!is.null(m$date)) m$date else "TBD"
      ev <- if (!is.null(m$event)) m$event else ""
      st <- if (!is.null(m$status) && !identical(m$status, "Confirmed")) sprintf(" (%s)", tolower(m$status)) else ""
      lines <- c(lines, sprintf("- [ ] %s: %s%s", dt, ev, st))
    }
    lines <- c(lines, "")
  }
  
  # Block 5. Model Implications (2027 Marcel / Pythagorean Priors)
  lines <- c(lines, "### 5. Model Implications (2027 Marcel / Pythagorean Priors)")
  impact <- edition$modelPriorImpact
  if (!is.null(impact) && isTRUE(impact$hasChanges)) {
    summary_txt <- if (!is.null(impact$summary)) impact$summary else "Adjustments to projected win totals recorded."
    lines <- c(lines, sprintf("- %s", summary_txt))
    if (!is.null(impact$adjustedTeams) && length(impact$adjustedTeams) > 0) {
      for (tm_name in names(impact$adjustedTeams)) {
        adj <- impact$adjustedTeams[[tm_name]]
        lines <- c(lines, sprintf("  * **%s**: Delta Wins %+0.1f, Net WAR %+0.1f (%s)",
                                  tm_name, adj$deltaWins, adj$netWarAdded, adj$rationale))
      }
    }
    lines <- c(lines, "")
  } else {
    lines <- c(lines, "- No change to 2027 baseline Marcel priors.", "")
  }
  
  # Block 6. Winter Leagues & Rehab Tracking (AFL / LIDOM / Post-Op)
  lines <- c(lines, "### 6. Winter Leagues & Rehab Tracking (AFL / LIDOM / Post-Op)")
  winter <- edition$winterLeagueNotes
  if (is.null(winter) || length(winter) == 0) {
    lines <- c(lines, "*No notable winter league assignments or major rehab events recorded.*", "")
  } else {
    for (w in winter) {
      pl <- if (!is.null(w$playerName)) w$playerName else ""
      tm <- if (!is.null(w$mlbTeam)) w$mlbTeam else ""
      lg <- if (!is.null(w$league)) w$league else ""
      nt <- if (!is.null(w$notes)) w$notes else ""
      lines <- c(lines, sprintf("- **%s** (%s, %s): %s", pl, tm, lg, nt))
    }
    lines <- c(lines, "")
  }
  
  # Block 7. Sources Verified
  lines <- c(lines, "### 7. Sources Verified")
  sources <- edition$sourcesVisited
  if (is.null(sources) || length(sources) == 0) {
    lines <- c(lines, "- MLB Official Transaction Wire (`statsapi.mlb.com`)",
               "- 30 Club Press Releases & Media Portals",
               "- Credited National & Local Beat Feeds")
  } else {
    for (s in sources) {
      lines <- c(lines, sprintf("- %s", s))
    }
  }
  lines <- c(lines, "")
  
  rendered <- paste(lines, collapse = "\n")
  validate_zero_betting(rendered)
  rendered
}

render_memo_frozen <- function(edition) {
  week_num <- if (!is.null(edition$weekNumber)) edition$weekNumber else 1
  pub_date <- if (!is.null(edition$publishDate)) edition$publishDate else format(Sys.Date(), "%Y-%m-%d")
  date_heading <- .format_date_heading(pub_date)
  freeze_count <- if (!is.null(edition$freezeDayCount)) edition$freezeDayCount else 1
  
  minor_league_count <- 0
  if (!is.null(edition$confirmedChanges) && length(edition$confirmedChanges) > 0) {
    for (ch in edition$confirmedChanges) {
      if (identical(ch$rosterTier, "MINOR_LEAGUE")) {
        minor_league_count <- minor_league_count + 1
      }
    }
  }
  
  state_of_play <- if (!is.null(edition$stateOfPlay) && nzchar(trimws(edition$stateOfPlay)) &&
                       !grepl("free agency declarations, contract option filings", edition$stateOfPlay, fixed = TRUE)) {
    validate_zero_betting(edition$stateOfPlay)
    edition$stateOfPlay
  } else {
    build_state_of_play_summary(edition)
  }
  
  lines <- character(0)
  lines <- c(lines, sprintf("## Week %02d — %s", week_num, date_heading), "")
  lines <- c(lines, sprintf("**State of Play:** %s", state_of_play), "")
  
  # Blocks 1-3. Transactions — Frozen
  lines <- c(lines, "### 1-3. Transactions — Frozen")
  freeze_start <- if (!is.null(edition$freezeStartDate)) edition$freezeStartDate else "2026-12-02"
  lines <- c(lines, sprintf("No major-league transactions permitted since %s.", freeze_start))
  lines <- c(lines, sprintf("Minor-league signings this window: %d (does not affect 40-man state).", minor_league_count), "")
  
  # Block 4. Next 30 Days
  lines <- c(lines, "### 4. Next 30 Days")
  milestones <- edition$upcomingMilestones
  if (is.null(milestones) || length(milestones) == 0) {
    lines <- c(lines, "- [ ] Scheduled bargaining sessions and any announced deadlines", "")
  } else {
    for (m in milestones) {
      dt <- if (!is.null(m$date)) m$date else "TBD"
      ev <- if (!is.null(m$event)) m$event else ""
      st <- if (!is.null(m$status) && !identical(m$status, "Confirmed")) sprintf(" (%s)", tolower(m$status)) else ""
      lines <- c(lines, sprintf("- [ ] %s: %s%s", dt, ev, st))
    }
    lines <- c(lines, "")
  }
  
  # Block 5. Model Implications
  lines <- c(lines, "### 5. Model Implications")
  lines <- c(lines, "- Priors held at the pre-freeze baseline; no roster change to incorporate.", "")
  
  # Block 8. Labor Negotiation Tracking
  lines <- c(lines, "### 8. Labor Negotiation Tracking")
  labor <- edition$laborEvents
  if (is.null(labor) || length(labor) == 0) {
    lines <- c(lines, "*No labor negotiation events or formal bargaining sessions recorded this window.*", "")
  } else {
    lines <- c(lines, "| Date | Event | Parties | Source Category | Outcome |")
    lines <- c(lines, "|---|---|---|---|---|")
    for (ev in labor) {
      dt <- if (!is.null(ev$date)) ev$date else ""
      evt <- if (!is.null(ev$event)) ev$event else ""
      pty <- if (!is.null(ev$parties)) ev$parties else ""
      src <- if (!is.null(ev$sourceCategory)) ev$sourceCategory else ""
      outc <- if (!is.null(ev$outcome)) ev$outcome else ""
      lines <- c(lines, sprintf("| %s | %s | %s | %s | %s |", dt, evt, pty, src, outc))
    }
    lines <- c(lines, "")
  }
  
  # Block 7. Sources Verified
  lines <- c(lines, "### 7. Sources Verified")
  sources <- edition$sourcesVisited
  if (is.null(sources) || length(sources) == 0) {
    lines <- c(lines, "- MLB Official Transaction Wire (`statsapi.mlb.com`)",
               "- Joint Labor Bargaining Press Bulletins (MLB / MLBPA)",
               "- Credited National Labor & Beat Coverage")
  } else {
    for (s in sources) {
      lines <- c(lines, sprintf("- %s", s))
    }
  }
  lines <- c(lines, "")
  
  rendered <- paste(lines, collapse = "\n")
  validate_zero_betting(rendered)
  rendered
}

render_memo <- function(edition, operating_status = "NORMAL") {
  if (identical(operating_status, "TRANSACTION_FREEZE")) {
    render_memo_frozen(edition)
  } else {
    render_memo_normal(edition)
  }
}
