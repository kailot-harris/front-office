pbox <- readRDS("cache/player_box_scores_cache.rds")

stats <- list(
  "PTS"  = pbox$points,
  "REB"  = pbox$rebounds,
  "AST"  = pbox$assists,
  "FG3M" = pbox$three_point_field_goals_made,
  "STL"  = pbox$steals,
  "BLK"  = pbox$blocks
)

results <- lapply(stats, function(x) {
  mu <- mean(x, na.rm = TRUE)
  var_x <- var(x, na.rm = TRUE)
  pi_0 <- mean(x == 0, na.rm = TRUE)

  # For NB: theta = mu^2 / (var - mu)
  theta <- if (var_x > mu) mu^2 / (var_x - mu) else 100.0

  list(mu = mu, var = var_x, pi_0 = pi_0, theta = theta)
})

print(results)
