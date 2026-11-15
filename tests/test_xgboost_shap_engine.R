# ==============================================================================
# tests/test_xgboost_shap_engine.R
#
# Unit, determinism, causal-leakage, bootstrap, and production cache contract
# tests for xgboost_shap_engine.R and config.R (Issue #124).
#
# Runs standalone synthetic tests in tempdir() even when cache/ is absent, and
# validates full production cache invariants when cache/ artifacts exist.
#
# Usage: Rscript tests/test_xgboost_shap_engine.R
# ==============================================================================

suppressPackageStartupMessages({
  library(tibble)
  library(dplyr)
  library(xgboost)
})

REPO_ROOT <- local({
  args <- commandArgs(trailingOnly = FALSE)
  f <- sub("^--file=", "", args[grepl("^--file=", args)])
  base <- if (length(f) == 1L) dirname(normalizePath(f)) else getwd()
  if (basename(base) == "tests") {
    normalizePath(file.path(base, ".."), winslash = "/", mustWork = FALSE)
  } else {
    normalizePath(base, winslash = "/", mustWork = FALSE)
  }
})

failures <- 0L
checks   <- 0L

ok <- function(label, cond) {
  checks <<- checks + 1L
  if (isTRUE(cond)) {
    cat(sprintf("  PASS  %s\n", label))
  } else {
    failures <<- failures + 1L
    cat(sprintf("  FAIL  %s\n", label))
  }
}

section <- function(title) cat(sprintf("\n== %s ==\n", title))
canon <- function(x) normalizePath(x, winslash = "/", mustWork = FALSE)

bootstrap_code <- function(path) {
  for (e in parse(path)) {
    if (is.call(e) && length(e) == 3L &&
        as.character(e[[1]]) %in% c("<-", "=") &&
        is.name(e[[2]]) && identical(as.character(e[[2]]), ".THIS_DIR")) {
      return(paste(deparse(e[[3]]), collapse = "\n"))
    }
  }
  NA_character_
}

assert_shap_entry_valid <- function(entry, label_prefix) {
  req_fields <- c(
    "model_id", "model_label", "train_seasons_label", "window_games",
    "away_prior_games_n", "home_prior_games_n", "base_value_log_odds",
    "total_log_odds", "predicted_home_win_prob", "factors"
  )
  has_fields <- all(req_fields %in% names(entry))
  if (!has_fields) return(list(ok = FALSE, reason = "missing top-level fields"))

  if (!identical(entry$model_id, "xgboost_feature_fusion_v1")) {
    return(list(ok = FALSE, reason = "bad model_id"))
  }
  if (!identical(entry$model_label, "XGBoost Feature Fusion (TreeSHAP)")) {
    return(list(ok = FALSE, reason = "bad model_label"))
  }
  if (!identical(as.integer(entry$window_games), 18L)) {
    return(list(ok = FALSE, reason = "window_games != 18L"))
  }
  if (!is.integer(entry$away_prior_games_n) || entry$away_prior_games_n < 1L ||
      !is.integer(entry$home_prior_games_n) || entry$home_prior_games_n < 1L) {
    return(list(ok = FALSE, reason = "prior_games_n < 1L or not integer"))
  }

  nums <- c(entry$base_value_log_odds, entry$total_log_odds, entry$predicted_home_win_prob)
  if (any(!is.finite(nums)) || entry$predicted_home_win_prob < 0 || entry$predicted_home_win_prob > 1) {
    return(list(ok = FALSE, reason = "non-finite summary numbers"))
  }

  factors <- entry$factors
  if (!is.list(factors) || length(factors) != 13L) {
    return(list(ok = FALSE, reason = "factors length != 13"))
  }

  shap_sum <- 0
  prev_abs <- Inf
  seen_features <- character(13L)
  for (idx in seq_along(factors)) {
    f <- factors[[idx]]
    f_req <- c("feature", "label", "feature_value", "z_score", "shap_log_odds", "shap_prob_approx")
    if (!all(f_req %in% names(f))) {
      return(list(ok = FALSE, reason = sprintf("factor %d missing keys", idx)))
    }
    f_nums <- c(f$feature_value, f$z_score, f$shap_log_odds, f$shap_prob_approx)
    if (any(!is.finite(f_nums))) {
      return(list(ok = FALSE, reason = sprintf("factor %s has non-finite value", f$feature)))
    }
    cur_abs <- abs(f$shap_log_odds)
    if (cur_abs > prev_abs + 1e-12) {
      return(list(ok = FALSE, reason = "factors not sorted descending by abs(shap_log_odds)"))
    }
    prev_abs <- cur_abs
    shap_sum <- shap_sum + f$shap_log_odds
    seen_features[idx] <- f$feature
  }

  if (length(unique(seen_features)) != 13L) {
    return(list(ok = FALSE, reason = "duplicate feature in factors"))
  }

  add_err <- abs((entry$base_value_log_odds + shap_sum) - entry$total_log_odds)
  if (add_err > 0.002) {
    return(list(ok = FALSE, reason = sprintf("additivity err %.6f > 0.002", add_err)))
  }
  prob_err <- abs(stats::plogis(entry$total_log_odds) - entry$predicted_home_win_prob)
  if (prob_err > 0.001) {
    return(list(ok = FALSE, reason = sprintf("prob err %.6f > 0.001", prob_err)))
  }

  list(ok = TRUE, reason = "")
}

# ------------------------------------------------------------------------------
section("1. Bootstrap, scratch-cwd loading, and config.R exports")
# ------------------------------------------------------------------------------

engine_path <- file.path(REPO_ROOT, "xgboost_shap_engine.R")
enhanced_path <- file.path(REPO_ROOT, "enhanced_model.R")

engine_lines <- readLines(engine_path, warn = FALSE)
code_lines <- sub("#.*$", "", engine_lines)

ok("xgboost_shap_engine.R exists", file.exists(engine_path))
ok("xgboost_shap_engine.R has no hardcoded authoring path",
   !any(grepl("kayceeslices", engine_lines, fixed = TRUE)))
ok("xgboost_shap_engine.R never calls setwd()",
   !any(grepl("setwd(", code_lines, fixed = TRUE)))
ok("xgboost_shap_engine.R has no cwd-relative source()",
   !any(startsWith(engine_lines, "source(\"")))
ok("xgboost_shap_engine.R .THIS_DIR matches enhanced_model.R exactly",
   identical(bootstrap_code(engine_path), bootstrap_code(enhanced_path)))

eng_env <- new.env(parent = globalenv())
scratch_dir <- file.path(tempdir(), "xgb_shap_scratch_cwd")
if (dir.exists(scratch_dir)) unlink(scratch_dir, recursive = TRUE)
dir.create(scratch_dir, recursive = TRUE)
on.exit(unlink(scratch_dir, recursive = TRUE), add = TRUE)

wd_home <- canon(getwd())
old_skip <- Sys.getenv("NBA_SKIP_STAGE_AUTORUN", unset = NA)
local({
  Sys.setenv(NBA_SKIP_STAGE_AUTORUN = "1")
  setwd(scratch_dir)
  on.exit({
    setwd(wd_home)
    if (is.na(old_skip)) Sys.unsetenv("NBA_SKIP_STAGE_AUTORUN")
    else Sys.setenv(NBA_SKIP_STAGE_AUTORUN = old_skip)
  }, add = TRUE)
  wd_during <<- canon(getwd())
  suppressMessages(suppressWarnings(
    capture.output(source(engine_path, local = eng_env))
  ))
  wd_after <<- canon(getwd())
})

ok("loaded xgboost_shap_engine.R from outside repo root", !identical(wd_during, canon(REPO_ROOT)))
ok("sourcing left working directory unchanged", identical(wd_after, wd_during))
ok("PROJECT_DIR resolved to repo checkout", identical(canon(eng_env$PROJECT_DIR), canon(REPO_ROOT)))
ok("CACHE_DIR resolved under repo checkout",
   identical(canon(eng_env$CACHE_DIR), canon(file.path(REPO_ROOT, "cache"))))
ok("run_xgboost_shap_engine() exported", is.function(eng_env$run_xgboost_shap_engine))
ok("config.R exports CACHE_XGBOOST_SHAP_MODEL",
   identical(canon(eng_env$CACHE_XGBOOST_SHAP_MODEL),
             canon(file.path(REPO_ROOT, "cache", "xgboost_shap_model.rds"))))
ok("config.R exports CACHE_XGBOOST_GAME_SHAP(2027)",
   is.function(eng_env$CACHE_XGBOOST_GAME_SHAP) &&
     identical(canon(eng_env$CACHE_XGBOOST_GAME_SHAP(2027)),
               canon(file.path(REPO_ROOT, "cache", "xgboost_game_shap_2027.rds"))))

# ------------------------------------------------------------------------------
section("2. Synthetic deterministic, causal < game_date, and NULL guard tests")
# ------------------------------------------------------------------------------

fx_dir <- file.path(tempdir(), "xgb_shap_fixtures")
if (dir.exists(fx_dir)) unlink(fx_dir, recursive = TRUE)
dir.create(fx_dir, recursive = TRUE)
on.exit(unlink(fx_dir, recursive = TRUE), add = TRUE)

make_box_row <- function(gid, season, gdate, tid, tname, ha, pts, win,
                         fgm = 40, fga = 85, fg3m = 12, fta = 20, tov = 13,
                         oreb = 10, dreb = 32, ast = 25, stl = 8, blk = 5) {
  tibble(
    game_id = as.character(gid),
    season = as.integer(season),
    game_date = as.Date(gdate),
    team_id = as.integer(tid),
    team_short_display_name = as.character(tname),
    team_home_away = as.character(ha),
    team_score = as.numeric(pts),
    team_winner = as.logical(win),
    field_goals_made = as.numeric(fgm),
    field_goals_attempted = as.numeric(fga),
    three_point_field_goals_made = as.numeric(fg3m),
    free_throws_attempted = as.numeric(fta),
    total_turnovers = as.numeric(tov),
    offensive_rebounds = as.numeric(oreb),
    defensive_rebounds = as.numeric(dreb),
    assists = as.numeric(ast),
    steals = as.numeric(stl),
    blocks = as.numeric(blk)
  )
}

# Build synthetic prior-season training data (seasons 2025 & 2026) with 4 teams
team_ids   <- c(2L, 18L, 25L, 999L)
team_names <- c("Celtics", "Knicks", "Thunder", "UnknownClub")
train_rows <- list()
gid_seq <- 1000L
for (s in c(2025L, 2026L)) {
  base_d <- as.Date(sprintf("%d-11-01", s - 1L))
  for (round_idx in 1:12) {
    pairings <- list(c(1L, 2L), c(3L, 4L), c(2L, 3L), c(4L, 1L))
    for (p_idx in seq_along(pairings)) {
      gid_seq <- gid_seq + 1L
      h_i <- pairings[[p_idx]][1L]
      a_i <- pairings[[p_idx]][2L]
      gd <- base_d + (round_idx - 1L) * 2L + (p_idx %% 2L)
      # Home edge + team strength gradient
      h_pts <- 104 + (4 - h_i) * 4 + (round_idx %% 3)
      a_pts <- 100 + (4 - a_i) * 4 + ((round_idx + 1) %% 3)
      h_win <- h_pts >= a_pts
      train_rows[[length(train_rows) + 1L]] <- make_box_row(
        gid_seq, s, gd, team_ids[h_i], team_names[h_i], "home", h_pts, h_win,
        fgm = 38 + (4 - h_i), fga = 84, fg3m = 11 + (round_idx %% 3),
        fta = 18, tov = 11 + (h_i %% 3), oreb = 9 + h_i, dreb = 33, ast = 24 + (4 - h_i)
      )
      train_rows[[length(train_rows) + 1L]] <- make_box_row(
        gid_seq, s, gd, team_ids[a_i], team_names[a_i], "away", a_pts, !h_win,
        fgm = 37 + (4 - a_i), fga = 85, fg3m = 10 + (round_idx %% 2),
        fta = 19, tov = 12 + (a_i %% 3), oreb = 8 + a_i, dreb = 31, ast = 22 + (4 - a_i)
      )
    }
  }
}
syn_train_box <- bind_rows(train_rows)

# Embeddings fixture: include teams 2, 18, 25 (with Knicks matched by name)
# and omit team 999 ("UnknownClub") to verify 0.0 neutral fallback only when missing.
syn_emb <- tibble(
  team_id = c(2L, 18L, 25L),
  team_name = c("Celtics", "New York Knicks", "Oklahoma City Thunder"),
  team_abbreviation = c("BOS", "NY", "OKC"),
  emb_1 = c(0.8, 0.2, 0.6),
  emb_2 = c(0.1, 0.9, 0.4),
  emb_3 = c(0.5, 0.3, 0.7)
)

# Synthetic 2027 schedule:
# - g1 (2026-10-20): Celtics vs Knicks (0 prior games each -> NULL)
# - g2 (2026-10-22): Thunder vs Celtics (away=Celtics has 1 prior, home=Thunder has 0 -> NULL)
# - g3 (2026-10-24): Knicks vs Celtics (both have 1 prior -> SCORED!)
# - g4 (2026-10-26): Celtics vs UnknownClub (both have >=1 prior -> SCORED, style_similarity == 0)
# - g5 (2026-10-28): Celtics vs Thunder (Knicks/Celtics later + NA poison test separately)
# - g_tbd: TBD placeholder (excluded from output)
syn_sched <- tibble(
  game_id = c("g1", "g2", "g3", "g4", "g5", "g_tbd"),
  season = rep(2027L, 6L),
  game_date = as.Date(c("2026-10-20", "2026-10-22", "2026-10-24", "2026-10-26", "2026-10-28", "2026-12-05")),
  home_id = c(2L, 25L, 18L, 2L, 2L, -1L),
  away_id = c(18L, 2L, 2L, 999L, 25L, -2L),
  home_short_display_name = c("Celtics", "Thunder", "Knicks", "Celtics", "Celtics", "TBD"),
  away_short_display_name = c("Knicks", "Celtics", "Celtics", "UnknownClub", "Thunder", "TBD")
)

# Box scores played up to 2026-10-24 (g1, g2, g3 played; g4, g5 upcoming)
syn_2027_box <- bind_rows(
  make_box_row("g1", 2027L, "2026-10-20", 2L,  "Celtics", "home", 115, TRUE),
  make_box_row("g1", 2027L, "2026-10-20", 18L, "Knicks",  "away", 104, FALSE),
  make_box_row("g2", 2027L, "2026-10-22", 25L, "Thunder", "home", 112, TRUE),
  make_box_row("g2", 2027L, "2026-10-22", 2L,  "Celtics", "away", 108, FALSE),
  make_box_row("g3", 2027L, "2026-10-24", 18L, "Knicks",  "home", 109, TRUE),
  make_box_row("g3", 2027L, "2026-10-24", 2L,  "Celtics", "away", 107, FALSE),
  make_box_row("g4_u", 2027L, "2026-10-23", 999L, "UnknownClub", "home", 98, FALSE)
)

p_train_box <- file.path(fx_dir, "train_box.rds")
p_sched     <- file.path(fx_dir, "sched_2027.rds")
p_sbox      <- file.path(fx_dir, "sbox_2027.rds")
p_model     <- file.path(fx_dir, "model.rds")
p_out       <- file.path(fx_dir, "game_shap.rds")

saveRDS(syn_train_box, p_train_box)
saveRDS(syn_sched, p_sched)
saveRDS(syn_2027_box, p_sbox)

res_run1 <- suppressMessages(capture.output(
  out1 <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = TRUE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))

ok("synthetic run drops TBD games (length == 5)", length(out1) == 5L && !("g_tbd" %in% names(out1)))
ok("g1 (0 prior games both sides) is NULL", is.null(out1[["g1"]]))
ok("g2 (home has 0 prior games) is NULL", is.null(out1[["g2"]]))
ok("g3 (both sides >= 1 prior game strictly < 2026-10-24) is scored", !is.null(out1[["g3"]]))
ok("g3 exact prior counts (away=2, home=1)",
   !is.null(out1[["g3"]]) &&
     identical(out1[["g3"]]$away_prior_games_n, 2L) &&
     identical(out1[["g3"]]$home_prior_games_n, 1L))
ok("g3 train_seasons_label derived from training seasons (2024-25..2025-26)",
   identical(out1[["g3"]]$train_seasons_label, "2024-25..2025-26"))

g3_chk <- assert_shap_entry_valid(out1[["g3"]], "synthetic g3")
ok(sprintf("g3 TreeSHAP contract valid (%s)", g3_chk$reason), g3_chk$ok)

# Check style_similarity: g3 (Knicks vs Celtics, both in syn_emb) != 0; g4 (UnknownClub missing) == 0
g3_sim <- Filter(function(f) f$feature == "style_similarity", out1[["g3"]]$factors)[[1]]$feature_value
g4_sim <- Filter(function(f) f$feature == "style_similarity", out1[["g4"]]$factors)[[1]]$feature_value
ok("style_similarity non-zero for normalized embedding pair (g3)", abs(g3_sim) > 0.01)
ok("style_similarity neutral 0.0 when team missing after normalization (g4)", identical(g4_sim, 0))

# Determinism test: retrain from scratch with force_retrain = TRUE and compare bit-for-bit
dummy <- suppressMessages(capture.output(
  out2 <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = TRUE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))
ok("determinism: force_retrain=TRUE produces identical predictions and SHAP", identical(out1, out2))

# Cache reuse test: without force_retrain, model file mtime stays unchanged
mtime_before <- file.info(p_model)$mtime
Sys.sleep(1.1)
dummy <- suppressMessages(capture.output(
  out_reuse <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = FALSE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))
mtime_after <- file.info(p_model)$mtime
ok("model cache reused when newer than CACHE_TEAM_BOX", identical(mtime_before, mtime_after))

# Cache invalidation test: when CACHE_TEAM_BOX is newer than model cache, retrain automatically
Sys.setFileTime(p_model, as.POSIXct(mtime_before) - 60)
old_mtime <- file.info(p_model)$mtime
dummy <- suppressMessages(capture.output(
  out_retrained <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = FALSE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))
mtime_retrained <- file.info(p_model)$mtime
ok("model cache retrained automatically when CACHE_TEAM_BOX is newer",
   mtime_retrained > old_mtime && identical(out1, out_retrained))

# Pipeline wiring check: xgboost_shap_engine.R wired directly before build_matchups_dataset.R
pipe_lines <- readLines(file.path(REPO_ROOT, "run_full_pipeline.R"), warn = FALSE)
xgb_line <- grep("xgboost_shap_engine\\.R", pipe_lines)
mat_line <- grep("build_matchups_dataset\\.R", pipe_lines)
ok("run_full_pipeline.R runs xgboost_shap_engine.R directly before build_matchups_dataset.R",
   length(xgb_line) >= 1L && length(mat_line) >= 1L && min(xgb_line) < min(mat_line))

# Strict < game_date causal leakage test:
# Add/modify box scores on g3's own date (2026-10-24) and future date (2026-10-25),
# and verify g3's output is 100% unchanged!
syn_2027_box_mut <- syn_2027_box
syn_2027_box_mut$team_score[syn_2027_box_mut$game_id == "g3"] <- c(199, 55)
syn_2027_box_mut <- bind_rows(
  syn_2027_box_mut,
  make_box_row("g_future", 2027L, "2026-10-25", 2L,  "Celtics", "home", 150, TRUE),
  make_box_row("g_future", 2027L, "2026-10-25", 18L, "Knicks",  "away",  80, FALSE)
)
saveRDS(syn_2027_box_mut, p_sbox)

dummy <- suppressMessages(capture.output(
  out_causal <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = FALSE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))
ok("strict < game_date cutoff: same-date and future box scores do not alter g3",
   identical(out1[["g3"]], out_causal[["g3"]]))

# Non-finite input guard test: inject NA into Thunder's g2 box score -> g5 must become NULL
syn_2027_box_na <- syn_2027_box
syn_2027_box_na$team_score[syn_2027_box_na$game_id == "g2" & syn_2027_box_na$team_id == 25L] <- NA_real_
saveRDS(syn_2027_box_na, p_sbox)
dummy <- suppressMessages(capture.output(
  out_na <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = FALSE,
    team_box_path = p_train_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_model,
    output_path = p_out,
    team_emb = syn_emb
  )
))
ok("non-finite rolling feature causes g5 entry to be NULL", is.null(out_na[["g5"]]))

# Constant feature SD guard test: ensure zero-SD training column uses SD=1.0 cleanly
const_train <- syn_train_box |> mutate(blocks = 5.0)
p_const_box <- file.path(fx_dir, "train_const_box.rds")
p_const_mod <- file.path(fx_dir, "model_const.rds")
saveRDS(const_train, p_const_box)
saveRDS(syn_2027_box, p_sbox)
dummy <- suppressMessages(capture.output(
  out_const <- eng_env$run_xgboost_shap_engine(
    season = 2027L,
    force_retrain = TRUE,
    team_box_path = p_const_box,
    schedule_path = p_sched,
    season_box_path = p_sbox,
    model_cache_path = p_const_mod,
    output_path = p_out,
    team_emb = syn_emb
  )
))
const_mod <- readRDS(p_const_mod)
ok("zero-SD training feature guarded with SD = 1.0",
   identical(unname(const_mod$feature_sds[["diff_roll_blk"]]), 1.0) &&
     !is.null(out_const[["g3"]]) &&
     assert_shap_entry_valid(out_const[["g3"]], "const-sd g3")$ok)

# ------------------------------------------------------------------------------
section("3. Live cache verification (cache/xgboost_shap_model.rds & 2027 SHAP)")
# ------------------------------------------------------------------------------

prod_model_path <- eng_env$CACHE_XGBOOST_SHAP_MODEL
prod_shap_path  <- eng_env$CACHE_XGBOOST_GAME_SHAP(2027L)
prod_sched_path <- eng_env$CACHE_MATCHUPS_SCHEDULE(2027L)
prod_sbox_path  <- eng_env$CACHE_MATCHUPS_TEAM_BOX(2027L)

if (file.exists(prod_model_path) && file.exists(prod_shap_path) &&
    file.exists(prod_sched_path) && file.exists(prod_sbox_path)) {
  m <- readRDS(prod_model_path)
  ok("cached model has raw booster and 13 features",
     is.raw(m$booster_raw) && length(m$feature_names) == 13L &&
       length(m$feature_labels) == 13L &&
       length(m$feature_means) == 13L && length(m$feature_sds) == 13L &&
       all(is.finite(m$feature_means)) && all(is.finite(m$feature_sds)) &&
       all(m$feature_sds > 0) && identical(as.integer(m$window_games), 18L))

  shap_list <- readRDS(prod_shap_path)
  sched_raw <- readRDS(prod_sched_path)
  sbox_raw  <- readRDS(prod_sbox_path)

  clean_sched <- eng_env$.prepare_clean_schedule(sched_raw, 2027L)
  ok("game SHAP keys match non-TBD schedule game_ids",
     identical(names(shap_list), clean_sched$game_id))

  sbox_dates <- as.Date(as.character(sbox_raw$game_date))
  sbox_tids  <- as.integer(sbox_raw$team_id)

  bad_entries <- character()
  bad_null_mismatch <- character()
  for (i in seq_len(nrow(clean_sched))) {
    gid <- clean_sched$game_id[i]
    gd  <- clean_sched$game_date[i]
    h_n <- sum(sbox_tids == clean_sched$home_id[i] & sbox_dates < gd, na.rm = TRUE)
    a_n <- sum(sbox_tids == clean_sched$away_id[i] & sbox_dates < gd, na.rm = TRUE)
    ent <- shap_list[[gid]]
    if (is.null(ent)) {
      if (h_n > 0L && a_n > 0L) {
        bad_null_mismatch <- c(bad_null_mismatch, gid)
      }
    } else {
      if (!identical(ent$away_prior_games_n, as.integer(a_n)) ||
          !identical(ent$home_prior_games_n, as.integer(h_n))) {
        bad_entries <- c(bad_entries, sprintf("%s: prior count mismatch", gid))
      } else {
        chk <- assert_shap_entry_valid(ent, gid)
        if (!chk$ok) bad_entries <- c(bad_entries, sprintf("%s: %s", gid, chk$reason))
      }
    }
  }

  ok("every 0-prior-game schedule entry is NULL (and non-0-prior games are non-NULL)",
     length(bad_null_mismatch) == 0L)
  ok(sprintf("all %d non-null 2027 TreeSHAP entries pass additivity, prob, order, and finite checks",
             sum(!vapply(shap_list, is.null, logical(1)))),
     length(bad_entries) == 0L)
  if (length(bad_entries) > 0L) {
    cat("  First failing entry:", bad_entries[1L], "\n")
  }
} else {
  cat("  SKIP  live cache checks (production cache artifacts not present)\n")
}

cat(sprintf("\n%d checks, %d failure(s).\n", checks, failures))
if (failures > 0L) quit(status = 1L)
cat("ALL CHECKS PASSED\n")
