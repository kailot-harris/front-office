PROJECT_DIR <- "c:/Users/kailo/kayceeslices/WNBA Analytics"
setwd(PROJECT_DIR)
suppressPackageStartupMessages(library(dplyr))
pbp <- wehoop::load_wnba_pbp(seasons = 2025)
made_shots <- pbp %>% filter(scoring_play == TRUE, shooting_play == TRUE)
cat("made shots:", nrow(made_shots), " athlete_id_2 non-NA among them:", sum(!is.na(made_shots$athlete_id_2)), "\n")
print(head(made_shots %>% filter(!is.na(athlete_id_2)) %>% select(text, athlete_name_1, athlete_name_2), 10))
cat("\nsample text with 'assist':\n")
print(head(pbp$text[grepl("assist", pbp$text, ignore.case = TRUE)], 10))
