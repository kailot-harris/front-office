PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(dplyr))

feats <- readRDS("cache/player_pbp_features.rds")
roster <- readRDS("cache/active_rosters_cache.rds")

cat("=== nrow check ===\n")
cat("features nrow:", nrow(feats), " roster nrow (distinct player_id):", n_distinct(roster$player_id), "\n\n")

cat("=== NA leakage check (player_id/team_abbreviation/data_source) ===\n")
cat("NA player_id:", sum(is.na(feats$player_id)), "\n")
cat("NA team_abbreviation:", sum(is.na(feats$team_abbreviation)), "\n")
cat("NA data_source:", sum(is.na(feats$data_source)), "\n\n")

cat("=== column list ===\n")
print(names(feats))

cat("\n=== data_source distribution ===\n")
print(table(feats$data_source, useNA = "ifany"))

cat("\n=== Top 10 by clutch_points ===\n")
feats %>% arrange(desc(clutch_points)) %>%
  select(player_name, team_abbreviation, data_source, clutch_points, clutch_fga, clutch_fg_pct, clutch_scoring_plays) %>%
  head(10) %>% print(n = 10)

cat("\n=== Top 10 by pct_three (min fga_total >= 20) ===\n")
feats %>% filter(fga_total >= 20) %>% arrange(desc(pct_three)) %>%
  select(player_name, team_abbreviation, data_source, fga_total, pct_three, pct_rim, pct_off_dribble_jumper, pct_catch_shoot_jumper) %>%
  head(10) %>% print(n = 10)

cat("\n=== Top 10 by assists ===\n")
feats %>% arrange(desc(assists)) %>%
  select(player_name, team_abbreviation, data_source, assists) %>%
  head(10) %>% print(n = 10)
