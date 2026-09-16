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

cor_mat <- cor(pbox_rot |> select(points, rebounds, assists), use = "pairwise.complete.obs")
print(cor_mat)
