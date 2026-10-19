setwd("c:/Users/kailo/kayceeslices/NFL Analytics")
x <- readRDS("cache/projected_matchups.rds")
cat("cols:", paste(names(x), collapse=", "), "\n")
cat("weeks present:", paste(sort(unique(x$week)), collapse=","), "\n")
w5 <- x[x$week == 5, ]
cat("n week5 rows:", nrow(w5), "\n")
print(w5[order(-w5$home_win_prob), c("home_team","away_team","home_win_prob","projected_margin")])
