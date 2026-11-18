# ==============================================================================
# tests/test_fatigue_schedule_context.R
#
# A team code missing from ARENA_DB leaves travel fatigue NA (#156). That must
# not blank the game's win probability or print NA in a summary: the schedule
# term is left out of the projection, the game is flagged
# schedule_context_available = FALSE, schedule_adjustment stays NA (never 0),
# and the game-detail waterfall says "Travel data unavailable" for that step.
# Games whose codes are all known must give exactly the numbers they gave before.
#
# No network, no caches.
#
# Usage: Rscript tests/test_fatigue_schedule_context.R
# ==============================================================================
REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
})
suppressPackageStartupMessages({ library(dplyr); library(tibble) })
Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")

n_fail <- 0L
check <- function(cond, label) {
  if (isTRUE(cond)) cat("  PASS:", label, "\n") else { n_fail <<- n_fail + 1L; cat("  FAIL:", label, "\n") }
}
near <- function(a, b, tol = 1e-8) length(a) == 1L && length(b) == 1L && is.finite(a) && is.finite(b) && abs(a - b) <= tol

pwp <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(
  source(file.path(REPO_ROOT, "tools", "project_week_predictions.R"), local = pwp))))
gd <- new.env(parent = globalenv())
invisible(capture.output(suppressMessages(
  source(file.path(REPO_ROOT, "build_game_details.R"), local = gd))))

# ------------------------------------------------------------------------------
cat("1. project_week_predictions: unknown team code\n")
# ------------------------------------------------------------------------------
ratings <- list(
  rating = c(Warriors = 3.20, Nuggets = 4.60, Lakers = 1.40, Zzzs = 0.50,
             GSW = 3.20, DEN = 4.60, LAL = 1.40, ZZZ = 0.50),
  sd = c(Warriors = 1.10, Nuggets = 0.80, Lakers = 1.50, Zzzs = 1.00,
         GSW = 1.10, DEN = 0.80, LAL = 1.50, ZZZ = 1.00),
  bottom_up = c(Warriors = 3, Nuggets = 5, Lakers = 1, Zzzs = 0.5, GSW = 3, DEN = 5, LAL = 1, ZZZ = 0.5),
  rapm = c(Warriors = 4, Nuggets = 4.5, Lakers = 2, Zzzs = 0.5, GSW = 4, DEN = 4.5, LAL = 2, ZZZ = 0.5),
  shot_fatigue = c(Warriors = 2.5, Nuggets = 4, Lakers = 1.5, Zzzs = 0.5, GSW = 2.5, DEN = 4, LAL = 1.5, ZZZ = 0.5),
  embeddings = c(Warriors = 3.25, Nuggets = 4.63, Lakers = 1.25, Zzzs = 0.5, GSW = 3.25, DEN = 4.63, LAL = 1.25, ZZZ = 0.5),
  abbr = c(Warriors = "GSW", Nuggets = "DEN", Lakers = "LAL", Zzzs = "ZZZ",
           GSW = "GSW", DEN = "DEN", LAL = "LAL", ZZZ = "ZZZ"),
  n = 4L
)
# S1/S2: known clubs only (S2 is the existing eastward back-to-back at altitude).
# S3/S4: the unknown club hosts, with a prior appearance, so its drag is computed.
spine <- tibble(
  game_id = c("S1", "S2", "S3", "S4"),
  game_date = as.Date(c("2026-10-20", "2026-10-21", "2026-10-22", "2026-10-24")),
  home_short_display_name = c("Warriors", "Nuggets", "Zzzs", "Nuggets"),
  away_short_display_name = c("Lakers", "Lakers", "Warriors", "Warriors")
)
warned <- character(0)
sched <- withCallingHandlers(
  pwp$.pwp_compute_schedule_adjustments(spine, abbr_lookup = ratings$abbr),
  message = function(m) { warned <<- c(warned, conditionMessage(m)); invokeRestart("muffleMessage") })
row_of <- function(id) sched[sched$game_id == id, , drop = FALSE]

check("schedule_context_available" %in% names(sched), "schedule table carries schedule_context_available")
check(isTRUE(row_of("S2")$schedule_context_available) && isTRUE(row_of("S1")$schedule_context_available),
      "known-code games are available")
check(identical(row_of("S3")$schedule_context_available, FALSE), "unknown-code game is not available")
check(is.na(row_of("S3")$schedule_adjustment), "unknown-code schedule_adjustment is NA, not 0")
check(any(grepl("'ZZZ'", warned, fixed = TRUE)), "the engine's [WARN] line names the code")

exp_drag <- as.numeric(pwp$calculate_travel_fatigue("DEN", "GSW", days_rest = 0L, is_back_to_back = TRUE)$fatigue_drag_pts)
check(near(row_of("S2")$schedule_adjustment, round(exp_drag, 2)), "known game keeps its schedule_adjustment")

proj <- suppressMessages(pwp$.pwp_build_week_projections(
  spine[spine$game_id %in% c("S2", "S3"), , drop = FALSE], spine, ratings,
  prediction_timestamp = as.POSIXct("2026-10-20 08:00:00")))
p2 <- proj[proj$game_id == "S2", ]; p3 <- proj[proj$game_id == "S3", ]

check(is.finite(p3$predicted_home_win_prob) && p3$predicted_home_win_prob > 0 && p3$predicted_home_win_prob < 1,
      "unknown-code win probability is finite")
check(is.finite(p3$predicted_margin) && is.finite(p3$sigma_game), "unknown-code margin and sigma are finite")
check(is.na(p3$comp_schedule), "log records the left-out schedule term as NA comp_schedule")
exp_margin3 <- (ratings$rating[["Zzzs"]] - ratings$rating[["Warriors"]]) + 2.40
check(near(p3$predicted_margin, round(exp_margin3, 2)), "margin = rating difference + home court only")
exp_sigma3 <- sqrt(11.8^2 + 1.0^2 + 1.1^2)
check(near(p3$predicted_home_win_prob, round(pnorm(exp_margin3 / exp_sigma3), 4)), "probability = pnorm(margin / sigma)")

exp_margin2 <- (4.60 - 1.40) + 2.40 + round(exp_drag, 2)
check(near(p2$predicted_margin, round(exp_margin2, 2)) && near(p2$comp_schedule, round(exp_drag, 2)),
      "known-code game: margin and comp_schedule unchanged")
check(near(p2$predicted_home_win_prob, round(pnorm(exp_margin2 / sqrt(11.8^2 + 0.80^2 + 1.50^2)), 4)),
      "known-code game: win probability unchanged")

# ------------------------------------------------------------------------------
cat("2. build_game_details: waterfall and payload flag\n")
# ------------------------------------------------------------------------------
ens <- data.frame(
  team = c("BOS", "NYK"), team_name = c("Celtics", "Knicks"),
  ensemble_net_rating = c(7.37, 2.00), rating_bottom_up = c(7.39, 2.00),
  rating_rapm = c(7.35, 2.00), rating_shot_fatigue = c(7.36, 2.00),
  rating_embeddings = c(7.38, 2.00), rating_disagreement_sd = c(1.25, 0.80),
  stringsAsFactors = FALSE)
base_margin <- (0.35 * (7.39 - 2) + 0.25 * (7.35 - 2) + 0.20 * (7.36 - 2) + 0.20 * (7.38 - 2)) + 2.40
mk_row <- function(adj, avail) list(
  game_id = "8001", game_date = "2026-11-20", home_team = "BOS", away_team = "NYK",
  home_name = "Celtics", away_name = "Knicks", is_completed = FALSE,
  projection_basis = "primary_ensemble",
  predicted_margin = round(base_margin + if (is.finite(adj)) adj else 0, 2),
  predicted_home_win_prob = 0.7,
  schedule_adjustment = adj, schedule_context_available = avail,
  home_fatigue_drag = if (avail) 0.15 else NA_real_, away_fatigue_drag = if (avail) 0.57 else NA_real_)
step <- function(ex, key) Filter(function(s) identical(s$key, key), ex$margin_waterfall)[[1]]

ex_na <- gd$build_game_explainability(mk_row(NA_real_, FALSE), ensemble_ratings = ens)
check(!is.null(ex_na$margin_waterfall), "waterfall is still built when travel is unavailable")
check(identical(ex_na$schedule_context_available, FALSE), "payload flag is FALSE")
check(identical(step(ex_na, "schedule")$detail, "Travel data unavailable") && step(ex_na, "schedule")$points == 0,
      "schedule step is labelled and contributes 0 points")
check(abs(sum(vapply(ex_na$margin_waterfall, `[[`, numeric(1), "points")) - ex_na$predicted_margin) <= 0.02,
      "steps still reconcile to predicted_margin")

ex_ok <- gd$build_game_explainability(mk_row(0.42, TRUE), ensemble_ratings = ens)
check(identical(ex_ok$schedule_context_available, TRUE) && near(step(ex_ok, "schedule")$points, 0.42),
      "known-code game: flag TRUE, schedule step unchanged")

# Logged row: one NA comp_schedule with the other components present is a gap;
# a row with every component NA is a legacy row and keeps a NULL waterfall.
logged <- function(sched_v, others = 1) list(
  game_id = "L1", prediction_timestamp = as.POSIXct("2026-10-25 18:00:00", tz = "UTC"),
  log_source = "LOGGED_PREGAME", predicted_margin = 4.0, predicted_home_win_prob = 0.62,
  comp_bottom_up = 1.0 * others, comp_rapm = 0.8 * others, comp_shot_fatigue = 0.5 * others,
  comp_embeddings = 0.3 * others, comp_home_court = 2.4 * others, comp_schedule = sched_v,
  sigma_game = 11.9)
lrow <- list(game_id = "L1", home_team = "BOS", away_team = "NYK", home_name = "Celtics",
             away_name = "Knicks", is_completed = FALSE, projection_basis = "logged_model_margin",
             predicted_margin = 5.0)
ex_l <- gd$build_game_explainability(lrow, ensemble_ratings = ens, log_row = logged(NA_real_))
check(!is.null(ex_l$margin_waterfall) && identical(ex_l$schedule_context_available, FALSE) &&
        identical(step(ex_l, "schedule")$detail, "Travel data unavailable"),
      "logged row with NA comp_schedule: waterfall built, step labelled")
legacy <- logged(NA_real_); for (k in grep("^comp_", names(legacy), value = TRUE)) legacy[[k]] <- NA_real_
ex_leg <- gd$build_game_explainability(lrow, ensemble_ratings = ens, log_row = legacy)
check(is.null(ex_leg$margin_waterfall), "all-NA legacy logged row still has no waterfall")

# ------------------------------------------------------------------------------
cat("3. build_matchups_dataset.R (stage script; asserted on its source)\n")
# ------------------------------------------------------------------------------
src <- readLines(file.path(REPO_ROOT, "build_matchups_dataset.R"), warn = FALSE)
has <- function(x) any(grepl(x, src, fixed = TRUE))
check(has("games$schedule_context_available <-"), "per-game schedule_context_available is computed")
check(has("games without travel context"), "summary line reports games without travel context")
check(has(".sched_ok <- games$schedule_adjustment[games$schedule_context_available]"),
      "summary statistics use only games with travel context")
check(has("if (isTRUE(g$schedule_context_available)) as.numeric(g$schedule_adjustment) else 0"),
      "margin adds the schedule term only where it is available")

cat(sprintf("\n%s (%d failure(s))\n", if (n_fail == 0L) "ALL PASSED" else "FAILED", n_fail))
quit(status = if (n_fail == 0L) 0L else 1L)
