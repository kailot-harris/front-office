suppressPackageStartupMessages({
  library(dplyr)
})

box <- readRDS("cache/player_box_scores_cache.rds")
active <- readRDS("cache/active_rosters_cache.rds")

team_map <- c(
  "Hawks" = "ATL", "Celtics" = "BOS", "Nets" = "BKN", "Hornets" = "CHA", "Bulls" = "CHI",
  "Cavaliers" = "CLE", "Mavericks" = "DAL", "Nuggets" = "DEN", "Pistons" = "DET", "Warriors" = "GSW",
  "Rockets" = "HOU", "Pacers" = "IND", "Clippers" = "LAC", "Lakers" = "LAL", "Grizzlies" = "MEM",
  "Heat" = "MIA", "Bucks" = "MIL", "Timberwolves" = "MIN", "Pelicans" = "NOP", "Knicks" = "NYK",
  "Thunder" = "OKC", "Magic" = "ORL", "76ers" = "PHI", "Suns" = "PHX", "Trail Blazers" = "POR",
  "Kings" = "SAC", "Spurs" = "SAS", "Raptors" = "TOR", "Jazz" = "UTA", "Wizards" = "WAS"
)

# Standardize abbreviations
box_map <- c(
  "GS" = "GSW", "NY" = "NYK", "NO" = "NOP", "SA" = "SAS", "UTAH" = "UTA", "WSH" = "WAS"
)

box$box_std <- ifelse(box$team_abbreviation %in% names(box_map), box_map[box$team_abbreviation], box$team_abbreviation)
active$active_std <- team_map[active$team_name]

latest_box <- box %>%
  arrange(desc(game_date)) %>%
  distinct(athlete_id, .keep_all = TRUE) %>%
  select(athlete_id, athlete_display_name, box_team = box_std)

active_clean <- active %>%
  distinct(player_id, .keep_all = TRUE) %>%
  select(player_id, player_name, active_team = active_std)

merged <- inner_join(latest_box, active_clean, by = c("athlete_id" = "player_id"))
real_changes <- merged %>% filter(box_team != active_team) %>% arrange(player_name)

cat(sprintf("TRUE 2026-2027 ROSTER CHANGES (Standardized): %d\n\n", nrow(real_changes)))

out_lines <- character(nrow(real_changes))
for (i in 1:nrow(real_changes)) {
  out_lines[i] <- sprintf("%-28s | 2025-26: %-4s -> Summer 2026: %-4s", real_changes$player_name[i], real_changes$box_team[i], real_changes$active_team[i])
}
cat(paste(out_lines, collapse = "\n"), "\n")

# Save to a json for node script processing
jsonlite::write_json(real_changes, "cache/verified_2026_moves.json", pretty = TRUE)
