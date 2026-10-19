suppressPackageStartupMessages({
  library(dplyr)
})

box <- readRDS("cache/player_box_scores_cache.rds")
active <- readRDS("cache/active_rosters_cache.rds")

# Map team_name to standard abbreviation in active rosters
team_map <- c(
  "Hawks" = "ATL", "Celtics" = "BOS", "Nets" = "BKN", "Hornets" = "CHA", "Bulls" = "CHI",
  "Cavaliers" = "CLE", "Mavericks" = "DAL", "Nuggets" = "DEN", "Pistons" = "DET", "Warriors" = "GSW",
  "Rockets" = "HOU", "Pacers" = "IND", "Clippers" = "LAC", "Lakers" = "LAL", "Grizzlies" = "MEM",
  "Heat" = "MIA", "Bucks" = "MIL", "Timberwolves" = "MIN", "Pelicans" = "NOP", "Knicks" = "NYK",
  "Thunder" = "OKC", "Magic" = "ORL", "76ers" = "PHI", "Suns" = "PHX", "Trail Blazers" = "POR",
  "Kings" = "SAC", "Spurs" = "SAS", "Raptors" = "TOR", "Jazz" = "UTA", "Wizards" = "WAS"
)

active$active_abbr <- team_map[active$team_name]

# Latest team in historical box scores (2023-2024 / 2024-2025)
latest_box <- box %>%
  arrange(desc(game_date)) %>%
  distinct(athlete_id, .keep_all = TRUE) %>%
  select(athlete_id, athlete_display_name, box_team = team_abbreviation)

# Join by player_id
active_clean <- active %>%
  distinct(player_id, .keep_all = TRUE) %>%
  select(player_id, player_name, active_team = active_abbr)

merged <- inner_join(latest_box, active_clean, by = c("athlete_id" = "player_id"))
changed <- merged %>% filter(box_team != active_team)

cat(sprintf("=== GROUND TRUTH 2026-2027 ROSTER CHANGES ===\n"))
cat(sprintf("Total verified veteran player team moves in active_rosters_cache.rds: %d\n\n", nrow(changed)))

changed <- changed %>% arrange(player_name)
for (i in 1:nrow(changed)) {
  cat(sprintf("%-28s | Prior Box Team: %-4s -> 2026 Active Team: %-4s\n", changed$player_name[i], changed$box_team[i], changed$active_team[i]))
}

# Also check incoming rookies (players in active_rosters_cache who never appeared in box scores)
rookies <- anti_join(active_clean, latest_box, by = c("player_id" = "athlete_id"))
cat(sprintf("\nTotal incoming rookies/newcomers with no prior box scores: %d\n", nrow(rookies)))
