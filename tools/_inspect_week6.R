setwd("c:/Users/kailo/kayceeslices/front-office/nfl analytics")
x <- readRDS("cache/projected_matchups.rds")
cat("cols:", paste(names(x), collapse=", "), "\n")
cat("weeks present:", paste(sort(unique(x$week)), collapse=","), "\n")
w6 <- x[x$week == 6, ]
cat("n week6 rows:", nrow(w6), "\n")
print(w6[order(-w6$home_win_prob), c("home_team","away_team","home_win_prob","projected_margin")])
