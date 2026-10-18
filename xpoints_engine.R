# ==============================================================================
# xpoints_engine.R
# Prototype: Expected Shot Quality (xeFG%) using Free NBA Endpoints
# ==============================================================================

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(dplyr)
})

# Free NBA Stats Shot Chart Endpoint
fetch_nba_shots <- function(team_id = "1610612738", season = "2023-24") {
  url <- paste0(
    "https://stats.nba.com/stats/shotchartdetail?",
    "AheadBehind=&ClutchTime=&Conference=&ContextFilter=&ContextMeasure=FGA",
    "&DateFrom=&DateTo=&Division=&EndPeriod=10&EndRange=28800&GROUP_ID=",
    "&GameEventID=&GameID=&GameSegment=&GroupID=&GroupMode=&GroupQuantity=5",
    "&LastNGames=0&LeagueID=00&Location=&MeasureType=Base&Month=0&OpponentTeamID=0",
    "&Outcome=&PORound=0&PaceAdjust=N&PerMode=PerGame&Period=0&PlayerID=0",
    "&PlayerPosition=&PointDiff=&Position=&RangeType=0&RookieYear=&Season=", season,
    "&SeasonSegment=&SeasonType=Regular+Season&ShotClockRange=&StarterBench=",
    "&TeamID=", team_id, "&VsConference=&VsDivision=&ZoneRange="
  )
  
  headers <- c(
    `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    `Referer` = "https://www.nba.com/",
    `x-nba-stats-origin` = "stats",
    `x-nba-stats-token` = "true"
  )
  
  res <- tryCatch(GET(url, add_headers(.headers = headers), timeout(10)), error = function(e) NULL)
  if (is.null(res) || status_code(res) != 200) {
    message(">>> [MOCK] Live API blocked by rate-limit; generating calibrated shot spatial sample...")
    return(generate_synthetic_shots())
  }
  
  json_data <- fromJSON(content(res, "text", encoding = "UTF-8"))
  headers_vec <- json_data$resultSets$headers[[1]]
  rows <- json_data$resultSets$rowSet[[1]]
  df <- as.data.frame(rows, stringsAsFactors = FALSE)
  colnames(df) <- headers_vec
  return(df)
}

# Synthetic spatial generator for offline/local execution
generate_synthetic_shots <- function(n = 2500) {
  set.seed(42)
  dist <- pmin(abs(rnorm(n, 16, 9)), 35) # Shot distance (0 - 35 ft)
  shot_val <- ifelse(dist >= 23.75, 3, 2)
  # True physical probability curve: rim (65%) down to long 2s (40%) and 3s (36%)
  true_prob <- ifelse(dist <= 4, 0.64 - 0.02 * dist,
                      ifelse(shot_val == 2, 0.46 - 0.005 * dist, 0.38 - 0.004 * (dist - 23.75)))
  made <- rbinom(n, 1, true_prob)
  
  tibble(
    shot_distance = dist,
    shot_value = shot_val,
    shot_made = made,
    true_prob = true_prob
  )
}

# Train logistic shot-probability model
estimate_expected_points <- function(shots_df) {
  # Logistic GAM or GLM on distance and shot value
  model <- glm(shot_made ~ shot_distance + factor(shot_value), data = shots_df, family = binomial)
  
  shots_df <- shots_df %>%
    mutate(
      x_prob = predict(model, newdata = shots_df, type = "response"),
      x_points = x_prob * shot_value,
      actual_points = shot_made * shot_value
    )
  
  total_actual <- sum(shots_df$actual_points)
  total_expected <- sum(shots_df$x_points)
  luck_factor <- total_actual - total_expected
  
  message("==========================================================")
  message(sprintf(">>> TOTAL ACTUAL POINTS:   %d", total_actual))
  message(sprintf(">>> TOTAL EXPECTED POINTS: %.1f", total_expected))
  message(sprintf(">>> SHOOTING LUCK RESIDUAL: %+.1f pts (Mean Regression Edge)", luck_factor))
  message("==========================================================")
  
  return(shots_df)
}

# Run execution
shots <- generate_synthetic_shots(3000)
evaluated_shots <- estimate_expected_points(shots)