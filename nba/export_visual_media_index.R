# ==============================================================================
# export_visual_media_index.R
#
# Publishes web/public/data/visual_media_index.json, the index the Gallery page
# reads at build time and the landing slideshow reads in the browser
# (front-office#210).
#
# Per item: generated_at is when that file was really built (UTC ISO-8601), never the run's
# start time: media_generated_at() (R/media_generated_at.R). A tracked file unchanged against
# git HEAD shows the time of the last commit that changed it (its publish time, which may be
# later than the render, but a copy or fresh clone never makes an old file look new); a file
# re-rendered this run or not yet committed shows its mtime. duration_ms is one GIF loop (NA -> JSON null when the GIF
# cannot be read) and is absent for images. Only files actually present in the media
# directory AND described in NBA_MEDIA_METADATA are indexed: a metadata entry whose
# file is absent produces no item, and a file with no metadata is logged and omitted
# (no placeholder item is ever written). Needs R/gif_duration.R and R/media_generated_at.R sourced.
#
# Sourced by tests/test_visual_media_index.R (functions only) and run as a pipeline
# stage by run_full_pipeline.R (the stage calls run_export_visual_media_index()).
# ==============================================================================

# Titles, categories and descriptions moved verbatim from the former
# NBA_GALLERY_ITEMS list in web/components/GalleryClient.tsx; order is gallery order.
# gif_rookie_impact_race is intentionally absent. The only copy ever published was
# drawn from simulated box scores (tools/gif_rookie_impact_race.R had no real
# nba_player_box_2027.rds to read). Add the entry back once that script has rendered
# from real rookie-season data.
NBA_MEDIA_METADATA <- list(
  "gif_elo_rank_bump.gif" = list(
    title = "League-Wide Elo Rating & Rank Evolution",
    category = "standings",
    desc = "Animated bump chart illustrating all 30 NBA teams Elo rating movements and ranking transitions across the season."
  ),
  "gif_point_diff_race.gif" = list(
    title = "Cumulative Point Differential Race",
    category = "standings",
    desc = "Animated race chart displaying cumulative scoring differential trajectories across all 30 NBA franchises."
  ),
  "gif_division_standings_race.gif" = list(
    title = "Division Standings Wins Race",
    category = "standings",
    desc = "Animated cumulative regular season wins race faceted across all 6 NBA divisions."
  ),
  "gif_elo_heatmap.gif" = list(
    title = "Elo Rating & Momentum Heatmap Matrix",
    category = "standings",
    desc = "2D timeline tile matrix mapping weekly Elo rating evolution and momentum shifts across all 30 NBA teams."
  ),
  "gif_elo_delta_race.gif" = list(
    title = "Week-over-Week Elo Momentum Race",
    category = "standings",
    desc = "Power rankings Elo delta bar race displaying surging risers and fallers over time."
  ),
  "gif_net_rating_quadrant.gif" = list(
    title = "Offensive vs Defensive Efficiency Dynamics",
    category = "efficiency",
    desc = "Evolution of offensive rating vs defensive rating across the league with championship quadrant dividers."
  ),
  "gif_pace_efficiency_quadrant.gif" = list(
    title = "Pace vs Net Rating Efficiency Matrix",
    category = "efficiency",
    desc = "Pace (possessions/48 min) vs Net Rating scatter animating team tactical styles from fast & dominant to methodical grinders."
  ),
  "gif_pf_pa_scatter_elo.gif" = list(
    title = "Points Scored vs Allowed & Elo Bubble Matrix",
    category = "efficiency",
    desc = "Offensive output vs defensive resistance scatter with team bubbles dynamically scaled by Elo rating and parity diagonal."
  ),
  "gif_turnover_margin_race.gif" = list(
    title = "Turnover Differential & Ball Security Race",
    category = "efficiency",
    desc = "Cumulative turnover margin bar race tracking ball security and opponent turnovers forced across all 30 NBA teams."
  ),
  "gif_upset_timeline.gif" = list(
    title = "Underdog Upset Timeline & Giant-Killer Tracker",
    category = "standings",
    desc = "Chronological timeline of underdog upsets where pre-game win expectation was under 43%, tracking giant-killing franchises."
  ),
  "gif_playoff_prob_bump.gif" = list(
    title = "Playoff Probability Over Time",
    category = "playoffs",
    desc = "Model playoff probability at each published projection update this season, for the 14 teams whose odds have moved most."
  ),
  "gif_player_shot_chart.gif" = list(
    title = "Player Shot Evolution & Spatial Density Progression",
    category = "shots",
    desc = "Animated rolling shot distribution and field goal efficiency evolution on regulation NBA half-court with reduced-motion static PNG fallback."
  ),
  "nba_predictions_today.png" = list(
    title = "Daily Game Model Predictions & Win Probabilities",
    category = "predictions",
    desc = "Stylized game-day projection graphic illustrating model win probabilities and projected home/away differentials across slate matchups."
  ),
  "gif_rapm_race.gif" = list(
    title = "Top-10 Offensive & Defensive RAPM",
    category = "players",
    desc = "The top 10 players by Offensive and Defensive Regularized Adjusted Plus-Minus (ORAPM/DRAPM) from the full 2025-26 season, revealed from 10th to 1st."
  ),
  "gif_clutch_shot_worm.gif" = list(
    title = "Closing Stretch: Score Margin & Shot Locations",
    category = "shots",
    desc = "The score margin through the final five minutes of the most recent close game, paired with where each shot in that stretch was taken."
  ),
  "gif_shot_profile_shift.gif" = list(
    title = "Team Shot-Profile Shift: Three-Point Share vs Last Season",
    category = "shots",
    desc = "Share of each team's field-goal attempts taken from three this season against last season, classified by court location in both years and updated through the latest games."
  ),
  "gif_rotation_minutes_stream.gif" = list(
    title = "Rotation Minutes Stream",
    category = "players",
    desc = "Game-by-game split of minutes among the players on the team whose rotation has changed the most this season, measured by how many minutes change hands between consecutive games."
  ),
  "gif_proj_vs_actual_wins.gif" = list(
    title = "Pre-Season Projection vs Results So Far",
    category = "predictions",
    desc = "Each team's projected win rate as published before opening night against its actual win rate to date, with the average miss across the league."
  ),
  "gif_timeout_effect.gif" = list(
    title = "After-Timeout Execution: Offense vs Defense",
    category = "efficiency",
    desc = "Points per possession each team scored on the first possession after its own timeouts against what it allowed after opponent timeouts, across the last completed season."
  )

)

#' @param dir      media directory
#' @param metadata named list keyed by basename: list(title, category, desc)
#' @param repo     git repo root containing `dir`, for media_generated_at()
#' @return list of items in metadata order (possibly empty)
build_media_index <- function(dir, metadata, repo = ".") {
  present <- if (dir.exists(dir)) list.files(dir) else character(0)
  unknown <- setdiff(present, names(metadata))
  # A described GIF's still frame (<stem>.png) is its reduced-motion companion, not unknown.
  stems <- sub("[.]gif$", "", grep("[.]gif$", names(metadata), value = TRUE))
  unknown <- setdiff(unknown, paste0(stems, ".png"))
  if (length(unknown) > 0L) {
    warning(sprintf("build_media_index: no metadata for %d file(s), omitted from visual_media_index: %s",
                    length(unknown), paste(unknown, collapse = ", ")), call. = FALSE)
  }
  index <- list()
  git_state <- if (length(present)) media_git_state(dir, repo) else NULL
  for (bname in intersect(names(metadata), present)) {
    f <- file.path(dir, bname)
    meta <- metadata[[bname]]
    is_gif <- grepl("[.]gif$", bname, ignore.case = TRUE)
    item <- list(
      id           = sub("[.][^.]+$", "", bname),
      generated_at = media_generated_at(f, repo = repo, git_state = git_state),
      filename     = bname,
      title        = meta$title,
      category     = meta$category,
      description  = meta$desc,
      type         = if (is_gif) "gif" else "image",
      size_bytes   = file.size(f)
    )
    if (is_gif) item$duration_ms <- gif_duration_ms(f)
    index[[length(index) + 1L]] <- item
  }
  index
}

# NA must publish as null (never the string "NA"); scoped to this index only.
visual_media_index_json <- function(index) {
  as.character(jsonlite::toJSON(index, auto_unbox = TRUE, pretty = TRUE,
                                null = "null", na = "null"))
}

run_export_visual_media_index <- function(media_dir = file.path("web", "public", "media"),
                                          out_file = file.path("web", "public", "data", "visual_media_index.json")) {
  if (!exists("gif_duration_ms", mode = "function")) source("R/gif_duration.R")
  if (!exists("media_generated_at", mode = "function")) source("R/media_generated_at.R")
  index <- build_media_index(media_dir, NBA_MEDIA_METADATA)
  if (length(index) == 0L) stop("visual_media_index: no indexable media found in ", media_dir)
  writeLines(visual_media_index_json(index), out_file, useBytes = TRUE)
  message(sprintf(">>> visual_media_index.json: %d items", length(index)))
  invisible(index)
}
