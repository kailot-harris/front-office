library(dplyr)
pbox <- readRDS("cache/player_box_scores_cache.rds")
rosters <- readRDS("cache/active_rosters_cache.rds")

rotation_ids <- rosters |>
  left_join(pbox |> group_by(athlete_id) |> summarise(avg_min = mean(minutes, na.rm = TRUE)),
            by = c("player_id" = "athlete_id")) |>
  group_by(team_name) |>
  arrange(desc(avg_min)) |>
  slice_head(n = 8) |>
  pull(player_id)

pbox_rot <- pbox |> filter(athlete_id %in% rotation_ids)

stats <- list(
  "PTS"  = pbox_rot$points,
  "REB"  = pbox_rot$rebounds,
  "AST"  = pbox_rot$assists,
  "FG3M" = pbox_rot$three_point_field_goals_made,
  "STL"  = pbox_rot$steals,
  "BLK"  = pbox_rot$blocks
)

results <- lapply(stats, function(x) {
  mu <- mean(x, na.rm = TRUE)
  var_x <- var(x, na.rm = TRUE)
  pi_0 <- mean(x == 0, na.rm = TRUE)
  theta <- if (var_x > mu) mu^2 / (var_x - mu) else 100.0
  list(mu = mu, var = var_x, pi_0 = pi_0, theta = theta)
})

print(results)
