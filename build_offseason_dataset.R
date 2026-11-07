# ==============================================================================
# build_offseason_dataset.R
# Deterministic WNBA Offseason Datasets Exporter (Issue #152 / Epic #138)
#
# Replaces the legacy hand-typed offseason generator (which fabricated gmQuote,
# execQuote, offseason_verdict, analysis,rnorm/heuristic winSharesDelta and
# delta_projected_wins, fictional Feb/March 2026 transactions, and 15 hand-authored
# 2026 draft scouting reports) with a deterministic real-data exporter.
#
# Upstream Real Data Sources:
#   - web/public/data/projections_season_teams.json (or cache/projected_wnba_standings.rds)
#   - web/public/data/projections_season_players.json (or cache/active_rosters_cache.rds)
#   - cache/league_state_baseline.json & cache/league_state_staged.json
#   - cache/raw_ingest_archive/*/wire_items_normalized.json (via tools/offseason/extract_regex.R)
#   - Optional RDS overrides if present: cache/offseason/transactions_log.rds,
#     cache/offseason/roster_baseline_2026.rds, cache/power_ratings.rds
#
# Outputs:
#   - web/public/data/offseason_transactions.json (+ cache/offseason_transactions.json)
#   - web/public/data/offseason_teams.json        (+ cache/offseason_teams.json)
#   - web/public/data/offseason_draft.json        (+ cache/offseason_draft.json)
# ==============================================================================

source("config.R")
suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
})

if (file.exists(file.path("tools", "offseason", "extract_regex.R"))) {
  source(file.path("tools", "offseason", "extract_regex.R"))
}

# Normalize raw wire position tokens (e.g. "G/F", "F/G", "C/F") to canonical G/F/C
normalize_wnba_pos <- function(pos_val) {
  if (is.null(pos_val) || length(pos_val) == 0 || is.na(pos_val[1]) || !nzchar(trimws(pos_val[1]))) {
    return("F")
  }
  p <- toupper(trimws(as.character(pos_val[1])))
  if (grepl("^G", p)) return("G")
  if (grepl("^C", p)) return("C")
  if (grepl("^F", p)) return("F")
  "F"
}

build_offseason_datasets <- function(
  teams_json_path = "web/public/data/projections_season_teams.json",
  players_json_path = "web/public/data/projections_season_players.json",
  baseline_state_path = "cache/league_state_baseline.json",
  transactions_rds_path = "cache/offseason/transactions_log.rds",
  roster_rds_path = "cache/offseason/roster_baseline_2026.rds",
  power_rds_path = "cache/power_ratings.rds",
  out_dir = "web/public/data",
  cache_dir = "cache",
  persist = TRUE
) {
  message(">>> Building deterministic WNBA Offseason datasets from real pipeline caches (Issue #152)...")

  if (!file.exists(teams_json_path) || !file.exists(players_json_path)) {
    stop("Required projection files missing in web/public/data/. Run export_web_datasets.R first.")
  }

  teams_df <- fromJSON(teams_json_path)
  players_df <- fromJSON(players_json_path)

  # Optional RDS overrides if present on disk
  roster_baseline <- if (file.exists(roster_rds_path)) {
    readRDS(roster_rds_path)
  } else if (file.exists("cache/active_rosters_cache.rds")) {
    readRDS("cache/active_rosters_cache.rds")
  } else {
    players_df
  }

  baseline_state <- if (file.exists(baseline_state_path)) {
    tryCatch(fromJSON(baseline_state_path, simplifyVector = FALSE), error = function(e) NULL)
  } else {
    NULL
  }

  # Lookup maps from real player projections
  player_pos_map <- setNames(as.character(players_df$position), tolower(trimws(players_df$player_name)))
  player_id_map <- setNames(as.character(players_df$player_id), tolower(trimws(players_df$player_name)))

  # ----------------------------------------------------------------------------
  # 1. Build Offseason Transactions from Real Wire Ingestion
  # ----------------------------------------------------------------------------
  transactions_list <- list()

  if (file.exists(transactions_rds_path)) {
    tx_rds <- readRDS(transactions_rds_path)
    if (is.data.frame(tx_rds) && nrow(tx_rds) > 0) {
      for (i in seq_len(nrow(tx_rds))) {
        r <- tx_rds[i, ]
        p_name <- as.character(r$player_name)
        p_key <- tolower(trimws(p_name))
        p_id <- if ("player_id" %in% names(r) && !is.na(r$player_id)) as.character(r$player_id) else unname(player_id_map[p_key])
        if (is.na(p_id) || !nzchar(p_id)) p_id <- paste0("p_", gsub("[^a-z0-9]+", "_", p_key))
        pos <- if ("position" %in% names(r) && !is.na(r$position)) normalize_wnba_pos(r$position) else normalize_wnba_pos(player_pos_map[p_key])
        transactions_list[[length(transactions_list) + 1L]] <- list(
          id = as.character(r$id),
          type = as.character(r$type),
          date = substr(as.character(r$date), 1, 10),
          player_name = p_name,
          player_id = p_id,
          position = pos,
          from_team = if ("from_team" %in% names(r) && !is.na(r$from_team) && nzchar(r$from_team)) as.character(r$from_team) else NA_character_,
          to_team = as.character(r$to_team),
          contract_terms = if ("contract_terms" %in% names(r) && !is.na(r$contract_terms)) as.character(r$contract_terms) else "Official league transaction wire",
          headline = if ("headline" %in% names(r) && !is.na(r$headline)) as.character(r$headline) else paste0(r$to_team, ": ", p_name),
          source_url = if ("source_url" %in% names(r) && !is.na(r$source_url)) as.character(r$source_url) else "https://www.espn.com/wnba/transactions"
        )
      }
    }
  } else {
    # Locate latest normalized wire archive from tools/offseason/ingest_sources.R
    archive_files <- sort(Sys.glob("cache/raw_ingest_archive/*/wire_items_normalized.json"), decreasing = TRUE)
    if (length(archive_files) > 0 && exists("extract_deltas_regex")) {
      wire_items <- fromJSON(archive_files[1], simplifyVector = FALSE)
      seen_keys <- character(0)

      for (item in wire_items) {
        if (!identical(item$source_family, "league_wire")) next
        item_date <- substr(as.character(item$event_date), 1, 10)
        item_url <- as.character(item$source_url)
        item_team <- as.character(item$team_abbr)
        item_text <- as.character(item$raw_text)

        deltas <- extract_deltas_regex(
          raw_text = item,
          date = item_date,
          source_url = item_url,
          baseline_state = baseline_state,
          team_abbr = item_team
        )

        if (length(deltas) == 0) next

        for (d in deltas) {
          if (!identical(d$entity_type, "player")) next
          ct <- as.character(d$change_type)
          # Only emit primary roster transaction events (avoid duplicate contractStatus pair on SIGNING)
          if (ct %in% c("SIGNING", "TRADE", "WAIVER_CLAIM") && !identical(d$field, "team")) next
          if (!(ct %in% c("SIGNING", "TRADE", "WAIVER_CLAIM", "WAIVER", "RELEASE"))) next

          p_name <- trimws(as.character(d$entity_name))
          p_name <- sub("^/[A-Za-z]+\\s+", "", p_name)
          if (!nzchar(p_name) || nchar(p_name) < 3) next
          if (grepl(",|\\band\\b", p_name, ignore.case = TRUE)) next
          if (!grepl("\\s", p_name)) next
          p_key <- tolower(p_name)

          to_tm <- if (ct %in% c("SIGNING", "TRADE", "WAIVER_CLAIM")) {
            as.character(d$new_val)
          } else {
            item_team
          }
          if (is.null(to_tm) || length(to_tm) == 0 || is.na(to_tm) || !(to_tm %in% names(WNBA_TEAMS))) {
            to_tm <- item_team
          }
          if (is.null(to_tm) || length(to_tm) == 0 || is.na(to_tm) || !(to_tm %in% names(WNBA_TEAMS))) next

          from_tm <- if (ct %in% c("TRADE", "WAIVER_CLAIM") && !is.null(d$prior_val) && length(d$prior_val) == 1 && !is.na(d$prior_val) && (as.character(d$prior_val) %in% names(WNBA_TEAMS))) {
            as.character(d$prior_val)
          } else if (ct %in% c("WAIVER", "RELEASE")) {
            to_tm
          } else {
            NA_character_
          }

          dedup_key <- paste(item_date, p_key, ct, to_tm, sep = "|")
          if (dedup_key %in% seen_keys) next
          seen_keys <- c(seen_keys, dedup_key)

          tx_type <- switch(
            ct,
            "TRADE" = "trade",
            "SIGNING" = "free_agency",
            "WAIVER_CLAIM" = "waiver_claim",
            "WAIVER" = "waiver",
            "RELEASE" = "release",
            "free_agency"
          )

          p_id <- if (!is.null(d$entity_id) && nzchar(as.character(d$entity_id))) {
            as.character(d$entity_id)
          } else if (p_key %in% names(player_id_map)) {
            unname(player_id_map[p_key])
          } else {
            paste0("p_", gsub("[^a-z0-9]+", "_", p_key))
          }

          pos <- if (!is.null(d$position) && !is.na(d$position)) {
            normalize_wnba_pos(d$position)
          } else if (p_key %in% names(player_pos_map)) {
            normalize_wnba_pos(player_pos_map[p_key])
          } else {
            "F"
          }

          terms_str <- if (!is.null(d$contract) && nzchar(as.character(d$contract))) {
            as.character(d$contract)
          } else {
            switch(
              ct,
              "TRADE" = "Official trade wire transaction",
              "SIGNING" = "Official contract signing",
              "WAIVER_CLAIM" = "Claimed off waivers",
              "WAIVER" = "Waived",
              "RELEASE" = "Released",
              "Official wire transaction"
            )
          }

          tx_id <- sprintf("wire-%s-%s-%03d", gsub("-", "", item_date), tolower(to_tm), length(transactions_list) + 1L)

          transactions_list[[length(transactions_list) + 1L]] <- list(
            id = tx_id,
            type = tx_type,
            date = item_date,
            player_name = p_name,
            player_id = p_id,
            position = pos,
            from_team = from_tm,
            to_team = to_tm,
            contract_terms = terms_str,
            headline = item_text,
            source_url = item_url
          )
        }
      }
    }
  }

  # ----------------------------------------------------------------------------
  # 2. Build Offseason Teams from Real Projections + Real Wire Transactions
  # ----------------------------------------------------------------------------
  teams_list <- list()
  teams_ordered <- teams_df %>% arrange(team)

  for (i in seq_len(nrow(teams_ordered))) {
    t_row <- teams_ordered[i, ]
    t_abbr <- as.character(t_row$team)

    full_name <- if (t_abbr %in% names(WNBA_TEAMS)) {
      unname(WNBA_TEAMS[t_abbr])
    } else if ("_row" %in% names(t_row) && !is.na(t_row$`_row`) && nzchar(t_row$`_row`)) {
      as.character(t_row$`_row`)
    } else {
      as.character(t_row$team_name)
    }

    t_roster_count <- sum(players_df$team == t_abbr, na.rm = TRUE)
    base_wins <- round(as.numeric(t_row$ensemble_mean_wins), 1)

    # Filter real wire additions and departures for this franchise
    t_adds <- list()
    t_deps <- list()
    for (tx in transactions_list) {
      if (identical(tx$to_team, t_abbr) && tx$type %in% c("free_agency", "trade", "waiver_claim", "extension")) {
        t_adds[[length(t_adds) + 1L]] <- list(
          name = tx$player_name,
          type = tx$type,
          pos = tx$position
        )
      } else if (
        (identical(tx$from_team, t_abbr) && tx$type %in% c("trade", "waiver", "release")) ||
        (identical(tx$to_team, t_abbr) && tx$type %in% c("waiver", "release"))
      ) {
        t_deps[[length(t_deps) + 1L]] <- list(
          name = tx$player_name,
          type = tx$type,
          pos = tx$position
        )
      }
    }

    teams_list[[i]] <- list(
      team = t_abbr,
      team_name = full_name,
      conference = as.character(t_row$conference),
      division = as.character(t_row$division),
      baseline_wins = base_wins,
      projected_wins_with_moves = base_wins,
      net_wins_change = 0,
      roster_count = as.integer(t_roster_count),
      confirmed_transactions_count = as.integer(length(t_adds) + length(t_deps)),
      additions = t_adds,
      departures = t_deps,
      draft_picks = list()
    )
  }

  # ----------------------------------------------------------------------------
  # 3. Build Offseason Draft Order from Inverse Projected Standings (No Fake Scouting)
  # ----------------------------------------------------------------------------
  # Sort by ascending ensemble_mean_wins (worst record = Pick #1), tie-break by team abbr
  draft_teams <- teams_df %>%
    arrange(ensemble_mean_wins, team)

  draft_list <- list()
  for (pick_idx in seq_len(nrow(draft_teams))) {
    dt_row <- draft_teams[pick_idx, ]
    t_abbr <- as.character(dt_row$team)
    full_name <- if (t_abbr %in% names(WNBA_TEAMS)) {
      unname(WNBA_TEAMS[t_abbr])
    } else {
      as.character(dt_row$team_name)
    }

    draft_list[[pick_idx]] <- list(
      pick = as.integer(pick_idx),
      team = t_abbr,
      team_name = full_name,
      conference = as.character(dt_row$conference),
      proj_wins = round(as.numeric(dt_row$proj_wins), 1),
      proj_losses = round(as.numeric(dt_row$proj_losses), 1),
      win_pct = round(as.numeric(dt_row$win_pct), 3),
      prospect_status = "UNPOPULATED_NO_SCOUTING_FEED"
    )
  }

  # ----------------------------------------------------------------------------
  # 4. Write JSON Artifacts to web/public/data/ and cache/
  # ----------------------------------------------------------------------------
  if (isTRUE(persist)) {
    dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
    dir.create(cache_dir, recursive = TRUE, showWarnings = FALSE)

    write_json(transactions_list, file.path(out_dir, "offseason_transactions.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    write_json(teams_list, file.path(out_dir, "offseason_teams.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    write_json(draft_list, file.path(out_dir, "offseason_draft.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")

    write_json(transactions_list, file.path(cache_dir, "offseason_transactions.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    write_json(teams_list, file.path(cache_dir, "offseason_teams.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")
    write_json(draft_list, file.path(cache_dir, "offseason_draft.json"), auto_unbox = TRUE, pretty = TRUE, null = "null", na = "null")

    message(sprintf(
      ">>> Successfully wrote offseason datasets: %d transactions, %d teams, %d draft order slots.",
      length(transactions_list), length(teams_list), length(draft_list)
    ))
  }

  invisible(list(
    transactions = transactions_list,
    teams = teams_list,
    draft = draft_list
  ))
}

if (sys.nframe() == 0L) {
  build_offseason_datasets()
}
