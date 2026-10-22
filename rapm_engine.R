# ==============================================================================
# rapm_engine.R
# Possession-Level Regularized Adjusted Plus-Minus (ORAPM / DRAPM)
# ==============================================================================
#
# WHAT CHANGED AND WHY
# --------------------
# This engine previously fit a STINT-level design built by build_stint_dataset.R:
# one row per substitution run, y = home margin per 100 possessions, the home five
# entering a design block at +1 and the away five a second block at -1. That design
# cannot separate offence from defence -- both blocks estimate the SAME quantity
# (total on-court impact) from the home and away halves of a player's minutes, which
# is why the old output columns were `rapm_home` / `rapm_away` and why their
# difference was meaningless (a sign error that once ranked Tyrese Maxey last in the
# league).
#
# A possession-level design does separate them. Each row is one possession; the five
# players on offence enter block 1 at +1, the five on defence enter block 2 at +1,
# and y is the points the offence scored on that possession. Block 1 is then genuinely
# offensive impact and block 2 genuinely defensive impact, so `rapm_home`/`rapm_away`
# are gone and ORAPM / DRAPM replace them.
#
# DATA SOURCE
# -----------
# hoopR::load_nba_stats_possessions() publishes exactly that table -- one row per
# possession with offense_team_id, defense_team_id, points, and the full 5v5 lineup
# (off_player_1..5 / def_player_1..5). No play-by-play parsing is needed here.
#
# SEASON NUMBERING -- there are TWO conventions in play, do not mix them up:
#   * The `season` COLUMN this loader returns, and RAPM_SEASON below, are hoopR's
#     END-year numbering, the same convention build_matchups_dataset.R uses:
#     season 2026 === the 2025-26 NBA season.
#   * The loader's `seasons =` ARGUMENT is the START year. Verified live:
#     load_nba_stats_possessions(seasons = 2025) downloads nba_possessions_2026.rds
#     and every returned row carries season == 2026.
#   RAPM_SEASON is the end-year; the -1 is applied at the call site and the returned
#   `season` column is asserted against it, so the off-by-one cannot drift silently.
#
# CURRENT-SEASON LIMIT: load_nba_stats_possessions(seasons = 2026) 404s --
# nba_possessions_2027.rds is not published, so the in-progress 2026-27 season has no
# possession table yet. RAPM is therefore fit on 2025-26 and labelled as such
# (`season_label`), which downstream consumers and the web UI surface. This costs
# little today (2026-27 is a handful of games old) but it is a real constraint to
# revisit once sportsdataverse publishes the current season.
#
# SIGN CONVENTION -- POSITIVE IS ALWAYS GOOD:
#   orapm       points created per 100 possessions above league average.
#   drapm       points PREVENTED per 100 possessions above league average. The raw
#               defensive coefficient is points ALLOWED, so it is negated on the way
#               out; a positive drapm is a good defender.
#   total_rapm  orapm + drapm.
# (The WNBA sibling engine at front-office-aggregator/wnba/rapm_engine.R keeps drapm
# as raw points allowed and computes orapm - drapm. Same model, opposite display
# convention -- do not copy a formula between the two files without checking this.)
#
# IDENTIFIABILITY -- THE O/D SPLIT HAS A DEGREE OF FREEDOM THE DATA CANNOT SEE.
# Every possession contributes five +1s to the offensive block and five +1s to the
# defensive block, so the vector v = (+1 on every offensive column, -1 on every
# defensive column) satisfies X v = 0 EXACTLY. Verified on the real 2025-26 matrix:
# max|Xv| = 0 across all 244,782 possessions. Adding c to every offensive coefficient
# and subtracting c from every defensive one therefore leaves the residual sum of
# squares bit-for-bit identical while moving every player's ORAPM and DRAPM by 100c.
# Differences BETWEEN players are estimable; the absolute level of either block is not.
#
# This is the textbook over-parameterised-model situation, and it is resolved the
# textbook way: with a side constraint on the non-estimable direction. We use
# SUM-TO-ZERO -- each block is centred on its own mean before export, so 0 means
# "league average" on both axes rather than "wherever the ridge prior happened to
# land". Two things to know about this choice:
#
#   * It is the published convention for possession-level RAPM. Kahn et al.,
#     "Possession-Level Player Impact in the Pre-Play-by-Play NBA Era"
#     (arXiv:2605.24056) S4.7 mean-centres "by computing the arithmetic mean of all
#     player coefficients within each block (offensive and defensive separately)",
#     because raw coefficients are "deviations from the ridge-shrinkage prior at zero,
#     not from the empirical league average"; their Remark 4 gives the reason as making
#     values "interpretable on an absolute scale relative to the league average rather
#     than relative to an arbitrary zero". Their total is ORAPM + DRAPM, as ours is.
#     (They reach the same sign convention by coding the defensive block -1 instead of
#     negating a +1-coded block as we do -- equivalent, not a difference in model.)
#   * It is the standard identifying constraint for any over-parameterised linear
#     model. See Meier, ANOVA and Experimental Design, S2 (ETH Zurich): a cell-means
#     model with a global term "is not identifiable anymore because we have g+1
#     parameters to model the g mean values", since shifting a constant between the
#     global term and the effects leaves every fitted value unchanged; the sum-to-zero
#     side constraint (sum alpha_i = 0, `contr.sum` in R) removes the extra parameter
#     and makes each effect read as a deviation from the global level. That note also
#     makes the point this comment exists to serve: "the values we get for the alpha_i
#     (heavily) depend on the side constraint that we use", so the constraint has to be
#     documented with the numbers or the numbers cannot be read.
#
# WHY BOTHER, GIVEN THE RIDGE ALREADY LANDS CLOSE. A ridge solution lies in the row
# space of X, which is orthogonal to v, so the solver cannot help but return
# mean(beta_off) = mean(beta_def) and hence mean(total_rapm) = 0. Centring y then puts
# each block within ~0.08 pts/100 of zero on its own. So the constraint below moves no
# player more than 0.0823 pts/100 and leaves total_rapm and every ranking untouched
# TODAY. It is enforced anyway because both of those guarantees are incidental: the
# orthogonality argument needs a uniform, symmetric penalty, and the per-axis level
# needs y centred. Give offence and defence separate lambdas, or shrink toward
# box-score priors instead of toward zero (both common next steps), and the penalty
# stops being invariant along v -- at which point the prior silently chooses the gauge.
# The sibling WNBA engine is the worked example of the second guarantee failing: it
# does not centre y, so league-average scoring lands inside every rating and both
# blocks sit around +7 instead of 0. Running THIS data through that setup reproduces
# it exactly (mean orapm = mean drapm = +7.665, against league 1.1604 pts/possession
# spread over 10 players). See check_rapm_gauge() below, which fails the run if the
# constraint ever stops holding.
#
# ID NAMESPACES: possessions and stats-shots use NBA-Stats person_id and team_id
# (1610612737..1610612766), NOT ESPN ids. The team_id -> tricode map and the
# person_id -> surname map are both derived live from load_nba_stats_shots(), which is
# in the same namespace; full names come from nba_commonallplayers(). None of these
# join to ESPN ids, so current-team re-attribution joins on normalized FULL NAME.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(Matrix)
})

if (file.exists("config.R")) source("config.R")
if (!dir.exists("cache")) dir.create("cache", recursive = TRUE)

message(">>> [RAPM] Initializing Possession-Level ORAPM/DRAPM Ridge Regression Engine...")

.cache_dir <- if (exists("CACHE_DIR")) CACHE_DIR else "cache"

.coalesce_null <- function(a, b) if (is.null(a)) b else a

# Synthetic possessions are opt-in only. Without real data this engine fails loudly
# rather than writing invented ratings: season_simulator.R weights total_rapm into
# Variant 2 of the ensemble at 25%.
ALLOW_SYNTHETIC_RAPM <- isTRUE(as.logical(Sys.getenv("ALLOW_SYNTHETIC_RAPM", "FALSE")))

# Target season in hoopR END-year numbering (2026 === the 2025-26 season). See the
# SEASON NUMBERING note above before changing this.
RAPM_SEASON <- as.integer(Sys.getenv("RAPM_SEASON", "2026"))

# NBA-Stats game_id prefixes: 001 preseason, 002 regular season, 003 all-star,
# 004 playoffs, 005 play-in, 006 in-season tournament. Regular season only by
# default -- preseason lineups are not rotation lineups, and playoff possessions would
# weight contenders' rotations more heavily than everyone else's.
RAPM_GAME_PREFIXES <- trimws(strsplit(Sys.getenv("RAPM_GAME_PREFIXES", "002"), ",")[[1]])

# Ridge penalty. Chosen by 5-fold cross-validation over held-out possessions when
# RAPM_TUNE_LAMBDA=TRUE; otherwise the stored value below, which is what that CV
# selected on the 2025-26 table (see the note on tune_lambda_cv()).
RAPM_LAMBDA      <- as.numeric(Sys.getenv("RAPM_LAMBDA", "3000"))
RAPM_TUNE_LAMBDA <- isTRUE(as.logical(Sys.getenv("RAPM_TUNE_LAMBDA", "FALSE")))

# Expected schema for the possession table this engine fits. One row per possession.
POSSESSION_REQUIRED_COLS <- c(
  "game_id", "season", "offense_team_id", "defense_team_id", "points",
  paste0("off_player_", 1:5), paste0("def_player_", 1:5)
)

season_label_for <- function(end_year) {
  sprintf("%d-%02d", end_year - 1L, end_year %% 100L)
}

# ESPN team_id -> project team code. cache/active_rosters_cache.rds keys its rows on
# this id, and the canonical table is season_simulator.R's NBA_TEAMS tribble -- which
# this stage does not source, so the 30 pairs are mirrored here. Kept in the same
# order as that tribble so the two can be diffed by eye if a franchise ever moves.
ESPN_TEAM_ID_TO_CODE <- c(
  "1"  = "ATL", "2"  = "BOS", "3"  = "NOP", "4"  = "CHI", "5"  = "CLE",
  "6"  = "DAL", "7"  = "DEN", "8"  = "DET", "9"  = "GSW", "10" = "HOU",
  "11" = "IND", "12" = "LAC", "13" = "LAL", "14" = "MIA", "15" = "MIL",
  "16" = "MIN", "17" = "BKN", "18" = "NYK", "19" = "ORL", "20" = "PHI",
  "21" = "PHX", "22" = "POR", "23" = "SAC", "24" = "SAS", "25" = "OKC",
  "26" = "UTA", "27" = "WAS", "28" = "TOR", "29" = "MEM", "30" = "CHA"
)

# ------------------------------------------------------------------------------
# Regularized Regression (Ridge via Normal Equations) -- unchanged from the
# stint-level engine; the solver is design-agnostic.
# ------------------------------------------------------------------------------
solve_ridge_rapm <- function(X, y, weights, lambda = 2000) {
  W <- Diagonal(x = sqrt(weights))
  X_w <- W %*% X
  y_w <- W %*% y

  I_reg <- Diagonal(ncol(X), lambda)

  # Normal Equations: (X'WX + lambda*I) beta = X'Wy
  XtX <- crossprod(X_w) + I_reg
  Xty <- crossprod(X_w, y_w)

  as.vector(solve(XtX, Xty))
}

# ------------------------------------------------------------------------------
# Live ingestion. Pulls the published possession table plus the two lookups that
# share its id namespace, and caches all of it so repeat runs are offline.
# ------------------------------------------------------------------------------
load_or_build_possession_cache <- function(season = RAPM_SEASON, force_refresh = FALSE) {
  cache_path <- file.path(.cache_dir, sprintf("nba_possessions_%d.rds", season))

  if (file.exists(cache_path) && !force_refresh) {
    got <- tryCatch(readRDS(cache_path), error = function(e) {
      message(sprintf(">>> [WARN] '%s' exists but could not be read: %s",
                      cache_path, conditionMessage(e)))
      NULL
    })
    if (!is.null(got) && !is.null(got$possessions) && nrow(got$possessions) > 0) {
      message(sprintf(">>> [RAPM] Loaded %s cached possessions from %s.",
                      format(nrow(got$possessions), big.mark = ","), basename(cache_path)))
      return(got)
    }
    message(sprintf(">>> [WARN] '%s' is present but empty; re-fetching.", cache_path))
  }

  if (!requireNamespace("hoopR", quietly = TRUE)) {
    message(">>> [RAPM] hoopR is not installed; cannot pull possession data.")
    return(NULL)
  }

  # The loader's argument is the START year; see the SEASON NUMBERING header note.
  arg_season <- season - 1L
  message(sprintf(">>> [RAPM] Fetching hoopR::load_nba_stats_possessions(seasons = %d) for the %s season...",
                  arg_season, season_label_for(season)))

  poss <- tryCatch(hoopR::load_nba_stats_possessions(seasons = arg_season),
                   error = function(e) {
                     message(sprintf(">>> [WARN] possession pull failed: %s", conditionMessage(e)))
                     NULL
                   })
  if (is.null(poss) || nrow(poss) == 0) {
    message(sprintf(paste0(">>> [RAPM] No possession data published for the %s season -- ",
                           "nba_possessions_%d.rds does not exist upstream."),
                    season_label_for(season), season))
    return(NULL)
  }

  returned <- unique(as.integer(poss$season))
  if (!identical(returned, as.integer(season))) {
    stop(sprintf(paste0("Season numbering drifted: asked load_nba_stats_possessions(seasons = %d) ",
                        "expecting the %s season (season column == %d) but got season column %s. ",
                        "Re-check the SEASON NUMBERING note at the top of rapm_engine.R."),
                 arg_season, season_label_for(season), season, paste(returned, collapse = ", ")))
  }

  # load_nba_stats_shots() is the only loader in the SAME id namespace as the
  # possession table, so it is what the team_id -> tricode map is derived from rather
  # than guessed. load_nba_team_crosswalk() looks like it should serve here but its
  # nba_team_id column is entirely NA -- in practice it is an ESPN-only table.
  shots <- tryCatch(hoopR::load_nba_stats_shots(seasons = arg_season),
                    error = function(e) NULL)
  team_map <- if (!is.null(shots) && nrow(shots) > 0) {
    tm <- shots %>%
      distinct(team_id, team_tricode) %>%
      filter(!is.na(team_id), !is.na(team_tricode))
    setNames(as.character(tm$team_tricode), as.character(tm$team_id))
  } else {
    character(0)
  }

  # The shots feed carries surnames only; nba_commonallplayers() is the live endpoint
  # with DISPLAY_FIRST_LAST against the same PERSON_ID.
  full_names <- tryCatch({
    idx <- hoopR::nba_commonallplayers(season = season_label_for(season), league_id = "00")[[1]]
    tibble::tibble(player_id   = as.character(idx$PERSON_ID),
                   player_name = as.character(idx$DISPLAY_FIRST_LAST)) %>%
      filter(!is.na(player_id), !is.na(player_name), player_name != "") %>%
      distinct(player_id, .keep_all = TRUE)
  }, error = function(e) {
    message(sprintf(">>> [WARN] nba_commonallplayers() unavailable (%s); falling back to surnames.",
                    conditionMessage(e)))
    NULL
  })

  surnames <- if (!is.null(shots) && nrow(shots) > 0) {
    shots %>%
      distinct(person_id, player_name) %>%
      transmute(player_id = as.character(person_id), surname = as.character(player_name)) %>%
      distinct(player_id, .keep_all = TRUE)
  } else {
    tibble::tibble(player_id = character(0), surname = character(0))
  }

  result <- list(
    possessions  = poss,
    team_map     = team_map,
    full_names   = full_names,
    surnames     = surnames,
    season       = season,
    season_label = season_label_for(season),
    pulled_at    = Sys.time()
  )
  saveRDS(result, cache_path)
  message(sprintf(">>> [RAPM] Cached %s possessions (%d teams, %d named players) to %s.",
                  format(nrow(poss), big.mark = ","), length(team_map),
                  if (is.null(full_names)) 0L else nrow(full_names), basename(cache_path)))
  result
}

# ------------------------------------------------------------------------------
# Cleaning + sparse design assembly.
# y is points on the possession, CENTERED on the league mean. Without centering the
# penalty has nowhere to put league-average scoring (~1.13 points/possession) except
# the player coefficients, which would hand every player the same large positive
# offset in both blocks. Centered, each coefficient reads as a deviation from average.
#
# No home-court term: the published table does not say which side is home, and a
# player's minutes are close to a 50/50 home/away split over a full season, so league
# HCA lands in the (removed) intercept rather than in anyone's rating.
# ------------------------------------------------------------------------------
build_possession_design_matrix <- function(possessions, team_map) {
  missing_cols <- setdiff(POSSESSION_REQUIRED_COLS, names(possessions))
  if (length(missing_cols) > 0) {
    stop(sprintf("Possession table is missing required column(s): %s. Expected schema: %s.",
                 paste(missing_cols, collapse = ", "),
                 paste(POSSESSION_REQUIRED_COLS, collapse = ", ")))
  }

  off_names <- paste0("off_player_", 1:5)
  def_names <- paste0("def_player_", 1:5)
  n_raw <- nrow(possessions)
  valid_team_ids <- names(team_map)

  clean <- possessions %>%
    filter(substr(as.character(game_id), 1, 3) %in% RAPM_GAME_PREFIXES) %>%
    filter(as.character(offense_team_id) %in% valid_team_ids,
           as.character(defense_team_id) %in% valid_team_ids) %>%
    filter(if_all(all_of(c(off_names, def_names)), ~ !is.na(.x))) %>%
    filter(!is.na(points), points >= 0, points <= 8)

  if ("count_as_possession" %in% names(clean)) {
    clean <- filter(clean, is.na(count_as_possession) | count_as_possession)
  }

  if (nrow(clean) == 0) stop("No usable possessions survived filtering.")

  message(sprintf(paste0(">>> [RAPM] %s of %s raw possessions kept (game types %s, %d NBA teams; ",
                         "dropped non-NBA teams, NA lineups, out-of-range points)."),
                  format(nrow(clean), big.mark = ","), format(n_raw, big.mark = ","),
                  paste(RAPM_GAME_PREFIXES, collapse = "/"), length(team_map)))

  off_cols <- as.matrix(clean %>% select(all_of(off_names)))
  def_cols <- as.matrix(clean %>% select(all_of(def_names)))

  all_players <- sort(unique(c(as.vector(off_cols), as.vector(def_cols))))
  n_players <- length(all_players)
  player_idx <- setNames(seq_len(n_players), as.character(all_players))

  n_poss <- nrow(clean)
  j_off <- matrix(player_idx[as.character(off_cols)], nrow = n_poss)
  j_def <- matrix(player_idx[as.character(def_cols)], nrow = n_poss) + n_players

  X <- sparseMatrix(
    i = rep(seq_len(n_poss), 10),
    j = c(as.vector(j_off), as.vector(j_def)),
    x = rep(1, n_poss * 10),
    dims = c(n_poss, 2 * n_players)
  )

  league_ppp <- mean(clean$points)

  off_votes <- clean %>%
    select(all_of(off_names), team_id = offense_team_id) %>%
    pivot_longer(all_of(off_names), values_to = "player_id") %>%
    count(player_id, team_id, name = "n")
  def_votes <- clean %>%
    select(all_of(def_names), team_id = defense_team_id) %>%
    pivot_longer(all_of(def_names), values_to = "player_id") %>%
    count(player_id, team_id, name = "n")

  list(
    X             = X,
    y             = matrix(clean$points - league_ppp, ncol = 1),
    weights       = rep(1, n_poss),
    all_players   = all_players,
    n_players     = n_players,
    n_possessions = n_poss,
    league_ppp    = league_ppp,
    n_games       = dplyr::n_distinct(clean$game_id),
    off_counts    = table(as.vector(off_cols)),
    def_counts    = table(as.vector(def_cols)),
    team_votes    = bind_rows(off_votes, def_votes) %>%
      group_by(player_id, team_id) %>%
      summarise(n = sum(n), .groups = "drop") %>%
      group_by(player_id) %>%
      slice_max(n, n = 1, with_ties = FALSE) %>%
      ungroup()
  )
}

# ------------------------------------------------------------------------------
# 5-fold cross-validated lambda selection on held-out possessions.
# The stint engine's lambda (1850) was tuned against a target of points per 100
# possessions (sd ~14.5). Here y is points on a single possession (sd ~1.2), a target
# two orders of magnitude smaller, so that value does not carry over and had to be
# re-selected rather than reused. This is out-of-sample MSE, not the coarse
# eyeball-the-spread grid the WNBA sibling engine used.
# ------------------------------------------------------------------------------
tune_lambda_cv <- function(dm, grid = c(250, 500, 1000, 2000, 3000, 5000, 8000, 12000, 20000),
                           k = 5, seed = 20260101) {
  set.seed(seed)
  folds <- sample(rep_len(seq_len(k), dm$n_possessions))
  p <- ncol(dm$X)

  # X'X and X'y depend only on the fold, not on lambda, and they are by far the
  # expensive part (a 200k x 1.2k sparse crossprod). Build them once per fold and
  # re-solve per lambda, instead of refitting from scratch for every combination.
  parts <- lapply(seq_len(k), function(f) {
    tr <- folds != f
    Xtr <- dm$X[tr, , drop = FALSE]
    ytr <- dm$y[tr, , drop = FALSE]
    list(XtX = crossprod(Xtr), Xty = crossprod(Xtr, ytr),
         Xte = dm$X[!tr, , drop = FALSE], yte = dm$y[!tr, 1])
  })

  mse <- numeric(length(grid))
  for (gi in seq_along(grid)) {
    lam <- grid[gi]
    sse <- 0
    n_held <- 0
    for (f in seq_len(k)) {
      beta <- as.vector(solve(parts[[f]]$XtX + Diagonal(p, lam), parts[[f]]$Xty))
      pred <- as.vector(parts[[f]]$Xte %*% beta)
      sse <- sse + sum((parts[[f]]$yte - pred)^2)
      n_held <- n_held + length(pred)
    }
    mse[gi] <- sse / n_held
    message(sprintf(">>> [RAPM]   lambda = %7.0f  ->  held-out MSE %.6f", lam, mse[gi]))
  }

  best <- grid[which.min(mse)]
  message(sprintf(">>> [RAPM] %d-fold CV selected lambda = %g.", k, best))
  best
}

# ------------------------------------------------------------------------------
# Current-team re-attribution.
# Ratings are fit on a completed season, but season_simulator.R aggregates them into a
# rating for the season being projected, so a player's `team` must be the team they
# are on NOW, not the one they played those possessions for. Possession-modal team is
# the starting point; cache/active_rosters_cache.rds overrides it wherever a
# normalized full name matches exactly one current roster slot. Ambiguous or unmatched
# names keep the modal team. No-op (with a warning) if the roster cache is missing, so
# this never breaks the run.
# ------------------------------------------------------------------------------
normalize_player_name <- function(x) {
  x <- tolower(as.character(x))
  x <- iconv(x, to = "ASCII//TRANSLIT", sub = "")
  x <- gsub("\\b(jr|sr|ii|iii|iv)\\.?\\s*$", "", x)
  x <- gsub("[^a-z ]", "", x)
  trimws(gsub("\\s+", " ", x))
}

reattribute_to_current_roster <- function(rapm_df) {
  roster_path <- file.path(.cache_dir, "active_rosters_cache.rds")
  if (!file.exists(roster_path)) {
    message(">>> [WARN] active_rosters_cache.rds not found; `team` stays the ",
            "possession-modal team from the fitted season (stale for anyone who has moved).")
    return(mutate(rapm_df, on_current_roster = NA))
  }
  roster <- tryCatch(readRDS(roster_path), error = function(e) NULL)
  if (is.null(roster) || !is.data.frame(roster) ||
      !all(c("player_name", "team_id") %in% names(roster))) {
    message(">>> [WARN] active_rosters_cache.rds malformed; skipping current-team re-attribution.")
    return(mutate(rapm_df, on_current_roster = NA))
  }

  # team_id on the roster cache is the ESPN team id (1..30) that season_simulator.R's
  # NBA_TEAMS tribble is keyed on, not a tricode. NBA_TEAMS is defined in
  # season_simulator.R, which this stage does not source, so prefer it when a caller
  # has it loaded and otherwise fall back to the local copy above.
  team_by_id <- if (exists("NBA_TEAMS") && is.data.frame(NBA_TEAMS) &&
                    all(c("team_id", "team") %in% names(NBA_TEAMS))) {
    setNames(NBA_TEAMS$team, as.character(NBA_TEAMS$team_id))
  } else {
    ESPN_TEAM_ID_TO_CODE
  }

  unambiguous <- roster %>%
    mutate(.key  = normalize_player_name(player_name),
           .team = unname(team_by_id[as.character(team_id)])) %>%
    filter(!is.na(.team), .key != "") %>%
    count(.key, .team, name = "n") %>%
    group_by(.key) %>%
    filter(dplyr::n_distinct(.team) == 1) %>%
    ungroup() %>%
    distinct(.key, .team)

  lookup <- setNames(unambiguous$.team, unambiguous$.key)

  keys    <- normalize_player_name(rapm_df$player_name)
  hit     <- unname(lookup[keys])
  matched <- !is.na(hit)
  moved   <- matched & (hit != rapm_df$team)

  out <- rapm_df %>%
    mutate(team = dplyr::coalesce(hit, team),
           on_current_roster = matched)

  message(sprintf(paste0(">>> [RAPM] Current-roster match: %d of %d rated players are on a ",
                         "current roster; %d re-attributed away from the team they played for."),
                  sum(matched), nrow(out), sum(moved)))
  out
}

# ------------------------------------------------------------------------------
# Gauge guard. The sum-to-zero constraint is trivially true the instant it is
# applied, so on its own this check proves nothing. What it is for is the NEXT
# change: separate lambdas per block, possession weights, a non-zero shrinkage
# target, or a port of the solver all break the orthogonality argument that keeps
# mean(total_rapm) at 0, and any of them would otherwise slide the whole leaderboard
# by a constant with nothing to notice it. A hard stop here is the cheapest way to
# make that failure loud instead of silent -- an unlabelled gauge shift is how the
# WNBA engine came to report both blocks at +7 and a 0.77 O/D correlation that read
# as a modelling bug rather than a missing constant.
# ------------------------------------------------------------------------------
# Tolerance has to clear the rounding noise in the EXPORTED columns, not just the
# full-precision vectors this is called on inside the fit. orapm/drapm ship rounded to
# 2dp, which leaves a mean of order 1e-4 across ~580 players, so a tolerance of 1e-8
# would reject the engine's own output if anyone re-checked the saved artifact. 1e-3
# sits ~10x above that rounding floor and ~80x below the smallest real gauge shift
# observed here (0.0823), so it accepts rounding and nothing else.
RAPM_GAUGE_TOL <- 1e-3

check_rapm_gauge <- function(orapm, drapm, tol = RAPM_GAUGE_TOL) {
  offenders <- c(ORAPM = abs(mean(orapm)), DRAPM = abs(mean(drapm)),
                 total = abs(mean(orapm + drapm)))
  bad <- offenders[offenders > tol]
  if (length(bad) > 0) {
    stop(sprintf(paste0("RAPM gauge constraint violated (%s). Each block must average 0 ",
                        "after centring -- see the IDENTIFIABILITY note at the top of this ",
                        "file. A non-zero mean here means the O/D split is being read on an ",
                        "arbitrary scale, so no rating in the output is comparable to 0."),
                 paste(sprintf("mean(%s) = %.3g", names(bad), bad), collapse = "; ")))
  }
  invisible(TRUE)
}

# ------------------------------------------------------------------------------
# Fit
# ------------------------------------------------------------------------------
estimate_rapm_from_possessions <- function(cache, lambda = RAPM_LAMBDA, source_tag = NULL) {
  dm <- build_possession_design_matrix(cache$possessions, cache$team_map)

  if (RAPM_TUNE_LAMBDA) lambda <- tune_lambda_cv(dm)

  message(sprintf(">>> [RAPM] Solving ridge across %s possessions (%d games) and %d player parameters (lambda = %g)...",
                  format(dm$n_possessions, big.mark = ","), dm$n_games, 2 * dm$n_players, lambda))

  coefficients <- solve_ridge_rapm(dm$X, dm$y, weights = dm$weights, lambda = lambda)

  # Scaled to points per 100 possessions. The defensive block's raw coefficient is
  # points ALLOWED above average, so it is negated: positive drapm == good defender.
  orapm <- coefficients[1:dm$n_players] * 100
  drapm <- -coefficients[(dm$n_players + 1):(2 * dm$n_players)] * 100

  # Sum-to-zero side constraint on each block -- the identifying constraint for the
  # null direction documented in the IDENTIFIABILITY header note. After this, 0 is
  # the league-average player on each axis by construction rather than by accident.
  gauge_shift <- c(orapm = mean(orapm), drapm = mean(drapm))
  orapm <- orapm - gauge_shift[["orapm"]]
  drapm <- drapm - gauge_shift[["drapm"]]
  message(sprintf(paste0(">>> [RAPM] Sum-to-zero constraint applied: ORAPM shifted %+.4f, ",
                         "DRAPM shifted %+.4f pts/100 (rankings unaffected)."),
                  -gauge_shift[["orapm"]], -gauge_shift[["drapm"]]))
  check_rapm_gauge(orapm, drapm)

  pid <- as.character(dm$all_players)

  off_n <- as.integer(dm$off_counts[pid]); off_n[is.na(off_n)] <- 0L
  def_n <- as.integer(dm$def_counts[pid]); def_n[is.na(def_n)] <- 0L

  modal_team <- setNames(
    unname(cache$team_map[as.character(dm$team_votes$team_id)]),
    as.character(dm$team_votes$player_id)
  )

  # Full names first: `[` on a named vector returns the FIRST match, so the
  # nba_commonallplayers() entry wins and the shots feed's surname is only the
  # fallback for anyone that index does not cover.
  name_lookup <- c(
    if (!is.null(cache$full_names)) setNames(cache$full_names$player_name,
                                             cache$full_names$player_id) else NULL,
    setNames(cache$surnames$surname, cache$surnames$player_id)
  )
  player_name <- unname(name_lookup[pid])
  unnamed <- is.na(player_name) | player_name == ""
  player_name[unnamed] <- paste0("Player_", pid[unnamed])

  rapm_df <- tibble(
    player_id       = pid,
    player_name     = player_name,
    team            = unname(modal_team[pid]),
    off_possessions = off_n,
    def_possessions = def_n,
    possessions     = off_n + def_n,
    orapm           = round(orapm, 2),
    drapm           = round(drapm, 2),
    total_rapm      = round(orapm + drapm, 2)
  ) %>%
    filter(!is.na(team))

  rapm_df <- reattribute_to_current_roster(rapm_df)

  rapm_df <- rapm_df %>%
    mutate(
      # Under ~500 combined possessions a rating is mostly the ridge prior, not the player.
      low_sample_flag = possessions < 500,
      data_source     = .coalesce_null(
        source_tag,
        sprintf("hoopR::load_nba_stats_possessions (%s)", cache$season_label)),
      season          = cache$season,
      season_label    = cache$season_label,
      lambda          = lambda,
      league_ppp      = round(dm$league_ppp, 4),
      n_possessions   = dm$n_possessions,
      n_games         = dm$n_games,
      generated_at    = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
    ) %>%
    select(player_id, player_name, team, off_possessions, def_possessions, possessions,
           orapm, drapm, total_rapm, low_sample_flag, on_current_roster, data_source,
           season, season_label, lambda, league_ppp, n_possessions, n_games, generated_at) %>%
    arrange(desc(total_rapm))

  out_path <- file.path(.cache_dir, "rapm_ratings.rds")
  saveRDS(rapm_df, out_path)
  message(sprintf(">>> [RAPM] Saved %d %s ORAPM/DRAPM ratings to %s (%d flagged low-sample).",
                  nrow(rapm_df), rapm_df$season_label[1], out_path, sum(rapm_df$low_sample_flag)))
  rapm_df
}

# ------------------------------------------------------------------------------
# Synthetic possessions (opt-in only -- see ALLOW_SYNTHETIC_RAPM).
# Generates a fake possession table in the real loader's schema and runs it through
# the SAME estimator, so the output columns and sign conventions cannot drift apart
# from the real path. The old engine kept a second hand-written estimator here, and
# that is how the rapm_home/rapm_away sign error stayed hidden: the generator used the
# same inverted convention as the fit, so the synthetic output looked self-consistent.
# ------------------------------------------------------------------------------
estimate_rapm_synthetic <- function(lambda = RAPM_LAMBDA) {
  message(">>> [WARN] Using SYNTHETIC_FALLBACK: generating a fake possession table.")

  teams <- c("ATL", "BOS", "NOP", "CHI", "CLE", "DAL", "DEN", "DET", "GSW", "HOU",
             "IND", "LAC", "LAL", "MIA", "MIL", "MIN", "BKN", "NYK", "ORL", "PHI",
             "PHX", "POR", "SAC", "SAS", "OKC", "UTA", "WAS", "TOR", "MEM", "CHA")
  team_ids <- as.character(1610612737:(1610612737 + length(teams) - 1))
  team_map <- setNames(teams, team_ids)

  players_per_team <- 12
  n_players  <- length(teams) * players_per_team
  player_ids <- 900000 + seq_len(n_players)

  set.seed(42)
  n_poss   <- 60000
  true_off <- rnorm(n_players, 0, 0.022)
  true_def <- rnorm(n_players, 0, 0.019)

  off_t <- sample(seq_along(teams), n_poss, replace = TRUE)
  def_t <- ((off_t - 1 + sample(1:29, n_poss, replace = TRUE)) %% 30) + 1

  pick5 <- function(ti) as.integer((ti - 1) * players_per_team + sample(players_per_team, 5))
  off_idx <- t(vapply(off_t, pick5, integer(5)))
  def_idx <- t(vapply(def_t, pick5, integer(5)))

  lat <- rowSums(matrix(true_off[off_idx], ncol = 5)) -
         rowSums(matrix(true_def[def_idx], ncol = 5))
  pts <- pmax(0, pmin(8, round(rnorm(n_poss, mean = 1.13 + lat, sd = 1.2))))

  poss <- tibble(
    game_id             = sprintf("002%08d", rep(seq_len(ceiling(n_poss / 200)),
                                                 each = 200)[seq_len(n_poss)]),
    season              = RAPM_SEASON,
    offense_team_id     = team_ids[off_t],
    defense_team_id     = team_ids[def_t],
    points              = pts,
    count_as_possession = TRUE
  )
  for (k in 1:5) {
    poss[[paste0("off_player_", k)]] <- player_ids[off_idx[, k]]
    poss[[paste0("def_player_", k)]] <- player_ids[def_idx[, k]]
  }

  cache <- list(
    possessions  = poss,
    team_map     = team_map,
    full_names   = tibble(
      player_id   = as.character(player_ids),
      player_name = paste0(rep(teams, each = players_per_team), "_P",
                           rep(seq_len(players_per_team), times = length(teams)))),
    surnames     = tibble(player_id = character(0), surname = character(0)),
    season       = RAPM_SEASON,
    season_label = season_label_for(RAPM_SEASON)
  )

  estimate_rapm_from_possessions(cache, lambda = lambda, source_tag = "SYNTHETIC_FALLBACK")
}

# ------------------------------------------------------------------------------
# Entry point
# ------------------------------------------------------------------------------
estimate_rapm_ratings <- function(lambda = RAPM_LAMBDA, season = RAPM_SEASON,
                                  force_refresh = FALSE) {
  cache <- tryCatch(load_or_build_possession_cache(season, force_refresh = force_refresh),
                    error = function(e) {
                      message(">>> [RAPM] possession ingest errored: ", conditionMessage(e))
                      NULL
                    })

  if (!is.null(cache) && !is.null(cache$possessions) && nrow(cache$possessions) > 0 &&
      length(cache$team_map) > 0) {
    return(estimate_rapm_from_possessions(cache, lambda = lambda))
  }

  msg <- sprintf(paste0(
    "No real possession data for the %s season. Refusing to write synthetic RAPM ratings: ",
    "season_simulator.R weights total_rapm into Variant 2 of the ensemble as if it were ",
    "observed. Point RAPM_SEASON at a published season (load_nba_stats_possessions has no ",
    "table for a season still in progress) or set ALLOW_SYNTHETIC_RAPM=TRUE for offline testing."),
    season_label_for(season))
  if (!ALLOW_SYNTHETIC_RAPM) stop(msg)
  message(">>> [WARN] ", msg)
  estimate_rapm_synthetic(lambda)
}

if (!interactive()) {
  invisible(estimate_rapm_ratings())
}
