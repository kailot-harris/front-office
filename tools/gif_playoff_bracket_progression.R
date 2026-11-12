# ==============================================================================
# tools/gif_playoff_bracket_progression.R
# Path: tools/gif_playoff_bracket_progression.R
#
# WNBA Playoff Bracket Progression animation. Gallery chart #11 of GitHub
# issue kailot-harris/front-office#146 ("gallery phase 3 -- postseason charts
# 11-12", part of #140's gallery-chart epic), built on #144's phase-1 shared
# viz plumbing (tools/viz_common.R / tools/viz_gallery_helpers.R).
#
# NO NBA COUNTERPART IS PORTED HERE. The NBA repo's closest-in-spirit script,
# gif_playoff_prob_bump.R, animates a projection-SNAPSHOT history over time
# (repeated pre-game win-probability estimates logged at different points in
# the season). This WNBA chart has a different real data source -- config.R's
# CACHE_PLAYOFF_BRACKET_CURRENT (cache/playoff_bracket_<CURRENT_SEASON>.rds,
# built by build_playoff_bracket_2026.R from real season_type == 3 box
# scores) -- which carries RESOLVED series results and real game dates, not a
# probability curve. So this script's structure was designed from that
# artifact's actual schema (read build_playoff_bracket_2026.R's header before
# touching this file) rather than translated from the NBA script line by
# line.
#
# ---- WHAT THIS CHART SHOWS ----
# A 3-column bracket tree (Round 1 / Semifinals / Finals, the WNBA's real
# single-table postseason structure -- no conferences or divisions since
# 2022, see CLAUDE.md). Each series is drawn as a two-row box (one row per
# team) carrying that team's abbreviation and its CURRENT win count in the
# series. The animation steps through the bracket's REAL chronological game
# dates (one frame per distinct date on which at least one postseason game
# was actually played, across every round, taken straight from each series'
# `games` list-column) and, at each step, shows the win counts as of that
# date. A series is drawn with a highlighted winner box only once its own
# `series_complete` flag (set by build_playoff_bracket_2026.R's
# mark_series_complete(), which checks the round's real win threshold, not
# just "ran out of recorded games") is TRUE as of that date -- so an
# in-progress series (e.g. a Finals at 1 game) is shown leading, never
# "won", matching the web /bracket-2026 route's own "leads" vs. "won"
# convention described in that script's header.
#
# Bracket tree structure (which Round 1 winners feed which Semifinal, etc.)
# is inferred directly from the data: a round-N+1 series' two teams are
# matched back to whichever round-N series contained either of those team
# abbreviations. Nothing about the matchup topology is hardcoded, since a
# future season's exact pairings are not known in advance.
#
# ---- ZERO-FALLBACK CONTRACT (issue #140/#144/#146, overriding CLAUDE.md's
# general "fall back to a clearly labeled synthetic value" house rule for
# this chart family specifically) ----
# If CACHE_PLAYOFF_BRACKET_CURRENT is missing, unreadable, empty, has no rows
# with a recognized round label, or those rows carry zero individual game
# records, this script stops via viz_stop_no_data() with nothing rendered.
# It never invents a series result, a game date, or a bracket pairing.
#
# Foundation & theme:
#   - sources tools/viz_common.R (theme_wnba_dark(), WNBA_TEAM_COLORS,
#     get_wnba_team_color(), viz_stop_no_data(), render_animated_artifact())
#   - sources tools/viz_gallery_helpers.R (viz_repo_root(), viz_cache_dir(),
#     viz_render_frames())
#   - renders dual artifacts via viz_render_frames():
#     gif_playoff_bracket_progression.gif and .png (reduced-motion static
#     final frame), written to cache/ and, when web/public/media exists,
#     mirrored there too.
#
# Data inputs:
#   - config.R's CACHE_PLAYOFF_BRACKET_CURRENT (cache/playoff_bracket_<season>.rds),
#     written by build_playoff_bracket_2026.R. cache/ is git-ignored, so a
#     fresh git worktree has no local copy -- find_bracket_cache() below
#     climbs to an ancestor checkout that does, mirroring the
#     WNBA_VIZ_CACHE_DIR convention viz_gallery_helpers.R::viz_cache_dir()
#     already documents for cache/. This locates the SAME real file, never a
#     substitute, and is overridable via the WNBA_VIZ_CACHE_DIR env var.
#
# Usage:
#   Rscript tools/gif_playoff_bracket_progression.R
# ==============================================================================

# Known environment quirk on this machine (confirmed across every phase-2
# chart): the active R installation's renv project library (both this
# worktree's and the main checkout's) is missing packages this script needs
# (dplyr/ggplot2/gifski), while a complete, working set is installed in the
# ordinary user library. Prepend it so library() calls below resolve there
# too, without disabling renv outright.
.user_lib <- "C:/Users/kailo/AppData/Local/R/win-library/4.5"
if (dir.exists(.user_lib)) .libPaths(c(.user_lib, .libPaths()))

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
})

SCRIPT_NAME <- "tools/gif_playoff_bracket_progression.R"

# ------------------------------------------------------------------------------
# 0. Resolve repo root and source shared plumbing. Per CLAUDE.md, tools/
#    scripts setwd() to the absolute project root before source()-ing
#    siblings by bare filename.
# ------------------------------------------------------------------------------
.args  <- commandArgs(trailingOnly = FALSE)
.fpath <- sub("^--file=", "", .args[grepl("^--file=", .args)])
SCRIPT_DIR <- if (length(.fpath) == 1L) {
  dirname(normalizePath(.fpath, winslash = "/", mustWork = FALSE))
} else {
  file.path(getwd(), "tools")
}
PROJECT_ROOT <- normalizePath(file.path(SCRIPT_DIR, ".."), winslash = "/", mustWork = FALSE)
if (dir.exists(PROJECT_ROOT)) setwd(PROJECT_ROOT)

source("config.R")
source("tools/viz_common.R")
source("tools/viz_gallery_helpers.R")

VIZ_ROOT      <- viz_repo_root()
VIZ_CACHE_DIR <- viz_cache_dir(VIZ_ROOT)

# ------------------------------------------------------------------------------
# 1. Locate the real bracket cache (see header comment above).
# ------------------------------------------------------------------------------
find_bracket_cache <- function() {
  env_dir <- Sys.getenv("WNBA_VIZ_CACHE_DIR", "")
  fname <- if (exists("CACHE_PLAYOFF_BRACKET_CURRENT")) {
    basename(CACHE_PLAYOFF_BRACKET_CURRENT)
  } else {
    sprintf("playoff_bracket_%d.rds", if (exists("CURRENT_SEASON")) CURRENT_SEASON else 2026)
  }
  candidates <- c(
    if (nzchar(env_dir)) file.path(env_dir, fname) else NA_character_,
    file.path(VIZ_CACHE_DIR, fname),
    if (exists("CACHE_PLAYOFF_BRACKET_CURRENT")) CACHE_PLAYOFF_BRACKET_CURRENT else NA_character_
  )
  anc <- PROJECT_ROOT
  for (i in 1:4) {
    anc <- dirname(anc)
    candidates <- c(candidates, file.path(anc, "cache", fname))
  }
  candidates <- candidates[!is.na(candidates)]
  for (cand in candidates) {
    if (file.exists(cand)) return(normalizePath(cand, winslash = "/"))
  }
  NULL
}

bracket_file <- find_bracket_cache()
if (is.null(bracket_file)) {
  viz_stop_no_data(SCRIPT_NAME, "playoff_bracket_<season>.rds (config.R's CACHE_PLAYOFF_BRACKET_CURRENT, written by build_playoff_bracket_2026.R) is missing.")
}

bracket <- tryCatch(readRDS(bracket_file), error = function(e) NULL)
if (is.null(bracket) || !is.data.frame(bracket) || nrow(bracket) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf("%s exists but contains no series rows (empty bracket artifact).", basename(bracket_file)))
}

REQUIRED_COLS <- c("team_a", "team_b", "team_a_abb", "team_b_abb", "wins_a", "wins_b",
                   "games_played", "winner_abb", "games", "round", "series_complete")
missing_cols <- setdiff(REQUIRED_COLS, names(bracket))
if (length(missing_cols) > 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s is missing expected column(s): %s. Schema may have changed upstream in build_playoff_bracket_2026.R.",
    basename(bracket_file), paste(missing_cols, collapse = ", ")))
}

ROUND_ORDER <- c("Round 1", "Semifinals", "Finals")

bracket_known <- bracket %>%
  filter(!is.na(round), round %in% ROUND_ORDER)

if (nrow(bracket_known) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s has %d series row(s) but none carry a recognized round label (%s).",
    basename(bracket_file), nrow(bracket), paste(ROUND_ORDER, collapse = "/")))
}

bracket_known$series_id <- paste(bracket_known$round, bracket_known$team_a_abb,
                                 bracket_known$team_b_abb, sep = "_")
season_val <- attr(bracket, "season")
if (is.null(season_val)) season_val <- if (exists("CURRENT_SEASON")) CURRENT_SEASON else NA_integer_

# ------------------------------------------------------------------------------
# 2. Flatten every series' `games` list-column into one row per actually
#    played game, with the winning team's abbreviation resolved by matching
#    the game record's own team labels back to the series row's team_a/
#    team_b (a game's team_a/team_b slot order is NOT guaranteed to match the
#    series row's team_a/team_b order -- see build_playoff_bracket_2026.R's
#    game_level summarise()).
# ------------------------------------------------------------------------------
extract_events <- function(bk) {
  out <- vector("list", nrow(bk))
  for (i in seq_len(nrow(bk))) {
    g_list <- bk$games[[i]]
    if (length(g_list) == 0) next
    rows <- vector("list", length(g_list))
    for (j in seq_along(g_list)) {
      g <- g_list[[j]]
      if (identical(g$team_a, bk$team_a[i])) {
        sa <- g$score_a; sb <- g$score_b
      } else {
        sa <- g$score_b; sb <- g$score_a
      }
      winner_abb <- if (isTRUE(sa > sb)) bk$team_a_abb[i] else bk$team_b_abb[i]
      rows[[j]] <- data.frame(
        series_id  = bk$series_id[i],
        round      = bk$round[i],
        game_num   = j,
        game_date  = as.Date(g$game_date),
        winner_abb = winner_abb,
        stringsAsFactors = FALSE
      )
    }
    out[[i]] <- bind_rows(rows)
  }
  bind_rows(out)
}

events_all <- extract_events(bracket_known)
if (nrow(events_all) == 0) {
  viz_stop_no_data(SCRIPT_NAME, sprintf(
    "%s has %d recognized-round series but none carry any individual game records in their `games` list-column.",
    basename(bracket_file), nrow(bracket_known)))
}

events_all <- events_all %>% arrange(game_date, series_id, game_num)
frame_dates <- sort(unique(events_all$game_date))

# ------------------------------------------------------------------------------
# 3. Bracket tree layout: x by round, y inferred from feeder matchups so the
#    tree visually connects (a round-N+1 series' y is the mean of the
#    round-N series' y whose teams fed into it; falls back to even spacing
#    when no feeder can be matched, e.g. the first round or a missing link).
# ------------------------------------------------------------------------------
rounds_present <- ROUND_ORDER[ROUND_ORDER %in% unique(bracket_known$round)]
round_x <- setNames(seq_along(rounds_present), rounds_present)

series_meta <- bracket_known %>%
  select(series_id, round, team_a, team_a_abb, team_b, team_b_abb,
         wins_a, wins_b, games_played, winner_abb, series_complete) %>%
  distinct(series_id, .keep_all = TRUE)

y_map <- list()
for (r_idx in seq_along(rounds_present)) {
  rname <- rounds_present[r_idx]
  ids <- series_meta %>% filter(round == rname) %>% arrange(series_id) %>% pull(series_id)
  n_ids <- length(ids)
  if (r_idx == 1 || length(y_map) == 0) {
    y_vals <- setNames(seq(n_ids, 1) / (n_ids + 1), ids)
  } else {
    prev_rname <- rounds_present[r_idx - 1]
    prev_meta  <- series_meta %>% filter(round == prev_rname)
    y_vals <- setNames(rep(NA_real_, n_ids), ids)
    for (id in ids) {
      row <- series_meta[series_meta$series_id == id, ][1, ]
      teams_here <- c(row$team_a_abb, row$team_b_abb)
      feeders <- prev_meta %>%
        filter(team_a_abb %in% teams_here | team_b_abb %in% teams_here) %>%
        pull(series_id)
      feeder_y <- y_map[[prev_rname]][feeders]
      if (length(feeder_y) > 0 && any(!is.na(feeder_y))) {
        y_vals[id] <- mean(feeder_y, na.rm = TRUE)
      }
    }
    na_idx <- which(is.na(y_vals))
    if (length(na_idx) > 0) {
      fill_vals <- seq(n_ids, 1) / (n_ids + 1)
      y_vals[na_idx] <- fill_vals[na_idx]
    }
  }
  y_map[[rname]] <- y_vals
}

node_xy <- bind_rows(lapply(rounds_present, function(rname) {
  data.frame(series_id = names(y_map[[rname]]), round = rname,
             x = round_x[[rname]], y = unname(y_map[[rname]]),
             stringsAsFactors = FALSE)
}))

# Static connector segments between a series and its real feeder(s) in the
# previous round -- drawn identically in every frame since the bracket's
# TOPOLOGY (who plays whom) is known from the start, independent of which
# games have been played yet.
connectors <- bind_rows(lapply(seq_along(rounds_present), function(r_idx) {
  if (r_idx == 1) return(NULL)
  rname <- rounds_present[r_idx]
  prev_rname <- rounds_present[r_idx - 1]
  ids <- series_meta %>% filter(round == rname) %>% pull(series_id)
  bind_rows(lapply(ids, function(id) {
    row <- series_meta[series_meta$series_id == id, ][1, ]
    teams_here <- c(row$team_a_abb, row$team_b_abb)
    feeders <- series_meta %>%
      filter(round == prev_rname, team_a_abb %in% teams_here | team_b_abb %in% teams_here) %>%
      pull(series_id)
    if (length(feeders) == 0) return(NULL)
    cur_xy <- node_xy[node_xy$series_id == id, ]
    data.frame(
      x    = round_x[[prev_rname]] + 0.17, y = node_xy$y[node_xy$series_id %in% feeders],
      xend = cur_xy$x - 0.17,              yend = cur_xy$y,
      stringsAsFactors = FALSE
    )
  }))
}))

# ------------------------------------------------------------------------------
# 4. Per-frame state: cumulative wins as of each real game date, plus which
#    series newly became decided that frame (for the subtitle highlight).
# ------------------------------------------------------------------------------
build_frame_state <- function(cutoff_date) {
  events_upto <- if (is.null(cutoff_date)) events_all[0, ] else events_all %>% filter(game_date <= cutoff_date)
  wins_tbl <- if (nrow(events_upto) > 0) {
    events_upto %>% count(series_id, winner_abb, name = "n")
  } else {
    data.frame(series_id = character(0), winner_abb = character(0), n = integer(0))
  }
  series_meta %>%
    rowwise() %>%
    mutate(
      cum_a = { w <- wins_tbl$n[wins_tbl$series_id == series_id & wins_tbl$winner_abb == team_a_abb]; if (length(w) == 0) 0L else as.integer(w[1]) },
      cum_b = { w <- wins_tbl$n[wins_tbl$series_id == series_id & wins_tbl$winner_abb == team_b_abb]; if (length(w) == 0) 0L else as.integer(w[1]) }
    ) %>%
    ungroup() %>%
    mutate(
      games_so_far = cum_a + cum_b,
      decided = (games_so_far >= games_played) & isTRUE(series_complete) & games_so_far > 0 &
                vapply(seq_along(series_id), function(i) isTRUE(series_complete[i]), logical(1))
    )
}

frame_steps <- c(list(NULL), as.list(frame_dates))
frame_labels <- c("Bracket Set", format(frame_dates, "%b %d"))

prev_decided <- character(0)
frame_states <- vector("list", length(frame_steps))
frame_highlights <- character(length(frame_steps))
for (k in seq_along(frame_steps)) {
  st <- build_frame_state(frame_steps[[k]])
  frame_states[[k]] <- st
  now_decided <- st$series_id[st$decided]
  newly <- setdiff(now_decided, prev_decided)
  if (length(newly) > 0) {
    msgs <- vapply(newly, function(id) {
      r <- st[st$series_id == id, ][1, ]
      winner_full <- if (identical(r$winner_abb, r$team_a_abb)) r$team_a else r$team_b
      sprintf("%s wins %s (%d-%d)", winner_full, r$round, max(r$cum_a, r$cum_b), min(r$cum_a, r$cum_b))
    }, character(1))
    frame_highlights[k] <- paste(msgs, collapse = "; ")
  } else {
    frame_highlights[k] <- if (k == 1) "Postseason bracket set" else "No series decided yet"
  }
  prev_decided <- now_decided
}

# ------------------------------------------------------------------------------
# 5. Render one ggplot frame per real game date.
# ------------------------------------------------------------------------------
all_abbrs <- unique(c(series_meta$team_a_abb, series_meta$team_b_abb))
team_colors <- setNames(
  vapply(all_abbrs, function(ab) get_wnba_team_color(ab, "primary"), FUN.VALUE = character(1)),
  all_abbrs
)

round_label_df <- data.frame(x = unname(round_x), label = names(round_x), stringsAsFactors = FALSE)

render_frame <- function(state_df, date_label, highlight) {
  box_df <- bind_rows(lapply(seq_len(nrow(state_df)), function(i) {
    r <- state_df[i, ]
    xy <- node_xy[node_xy$series_id == r$series_id, ]
    data.frame(
      series_id = r$series_id, x = xy$x,
      y    = c(xy$y + 0.055, xy$y - 0.055),
      team = c(r$team_a_abb, r$team_b_abb),
      wins = c(r$cum_a, r$cum_b),
      is_winner = c(
        isTRUE(r$decided) && identical(r$winner_abb, r$team_a_abb),
        isTRUE(r$decided) && identical(r$winner_abb, r$team_b_abb)
      ),
      stringsAsFactors = FALSE
    )
  }))
  box_df$label_str <- sprintf("%s  %d", box_df$team, box_df$wins)
  box_df$face <- ifelse(box_df$is_winner, "bold", "plain")

  p <- ggplot() +
    { if (!is.null(connectors) && nrow(connectors) > 0)
        geom_segment(data = connectors, aes(x = x, y = y, xend = xend, yend = yend),
                    color = WNBA_COLORS$grid, linewidth = 0.5)
      else NULL } +
    geom_tile(data = box_df, aes(x = x, y = y, fill = team), width = 0.34, height = 0.085,
             color = WNBA_COLORS$border, alpha = 0.92) +
    geom_tile(data = box_df[box_df$is_winner, ], aes(x = x, y = y), width = 0.34, height = 0.085,
             fill = NA, color = WNBA_COLORS$accent, linewidth = 1.1) +
    geom_text(data = box_df, aes(x = x, y = y, label = label_str, fontface = face),
             color = WNBA_COLORS$text, size = 3.1) +
    geom_text(data = round_label_df, aes(x = x, y = 1.12, label = label),
             color = WNBA_COLORS$subtext, fontface = "bold", size = 3.6) +
    scale_fill_manual(values = team_colors, guide = "none") +
    scale_x_continuous(limits = c(0.4, max(round_x) + 0.6)) +
    scale_y_continuous(limits = c(-0.05, 1.18)) +
    theme_wnba_dark(base_size = 10) +
    theme(
      axis.text = element_blank(), axis.ticks = element_blank(),
      axis.title = element_blank(), panel.grid = element_blank()
    ) +
    labs(
      title    = sprintf("%s WNBA Playoff Bracket Progression", if (is.na(season_val)) "" else season_val),
      subtitle = sprintf("Through %s \u2014 %s", date_label, highlight),
      caption  = "Real series results and game dates from box scores (season_type == 3); accent border = series decided"
    )
  p
}

plots <- vector("list", length(frame_steps))
for (k in seq_along(frame_steps)) {
  plots[[k]] <- render_frame(frame_states[[k]], frame_labels[k], frame_highlights[k])
}

viz_render_frames(
  plots      = plots,
  name       = "gif_playoff_bracket_progression",
  root       = VIZ_ROOT,
  cache_dir  = VIZ_CACHE_DIR,
  fps        = 1.5,
  hold_last_frames = 6,
  width      = 1000,
  height     = 700
)
