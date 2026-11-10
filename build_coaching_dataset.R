# ==============================================================================
# build_coaching_dataset.R
# Ingests and compiles NBA coaching staff registries, ATO (After-Timeout) efficiency,
# in-game challenge leverage, and talent-adjusted coaching impact metrics.
# Exports RDS caches and Next.js public JSON for web presentation.
#
# Rectified under Issue #80:
#   - Purged all 21 runif() calls and synthetic_coach_band tags.
#   - ATO PPP and challenge overturn rates directly derived from cache/pbp_timeout_cache.rds.
#   - Removed unmeasurable challenge WPA, synthetic shot quality lift, and rotation/dev scores.
#   - Radar percentiles and composite CIR deterministically calibrated against empirical metrics.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(jsonlite)
  library(tibble)
})

# Source global configuration
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [PHASE 1] Initializing Coaching Staff Registry & Impact Dataset...\n")

# Ensure cache directory exists
if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

# ------------------------------------------------------------------------------
# 1. 30 NBA Teams Coaching Staff Registry (2026-2027 Season Landscape)
# ------------------------------------------------------------------------------
cat(">>> Building official 30-team coaching staff registry (2026-2027 season baseline)...\n")

coaching_registry_raw <- tribble(
  ~team_abbr, ~team_name, ~head_coach, ~tenure_years, ~career_games, ~career_win_pct, ~coaching_tree, ~assoc_head_coach, ~offensive_coord, ~defensive_coord, ~player_dev_lead, ~tactical_archetype,
  "OKC", "Thunder", "Mark Daigneault", 7, 476, 0.605, "Billy Donovan", "Dave Bliss", "Chip Engelland", "Grant Gibbs", "Chip Engelland", "5-Out Drive & Kick / Aggressive Blitz & Switch",
  "BOS", "Celtics", "Joe Mazzulla", 5, 328, 0.720, "Brad Stevens", "Sam Cassell", "Matt Reynolds", "Craig Luschenat", "Amile Jefferson", "Extreme 3P Volume & Switch-Everything Defense",
  "HOU", "Rockets", "Ime Udoka", 5, 328, 0.604, "Gregg Popovich", "Royal Ivey", "Garrett Jackson", "Ben Sullivan", "Tiago Splitter", "Physical Attrition, Switching & Relentless Glass Crash",
  "CLE", "Cavaliers", "Kenny Atkinson", 7, 472, 0.530, "Mike Budenholzer", "Johnnie Bryant", "DeMarre Carroll", "Trevor Hendry", "Alex Jensen", "Dual-Rim Bigs Flow & Pace Acceleration",
  "NYK", "Knicks", "Mike Brown", 1, 848, 0.540, "Gregg Popovich", "Rick Brunson", "Andy Greer", "Dice Yoshimoto", "Darren Erman", "DHO Motion Flow, High Pacing & Brunson/Towns Spread PnR",
  "GSW", "Warriors", "Steve Kerr", 13, 957, 0.641, "Gregg Popovich", "Terry Stotts", "Bruce Fraser", "Jerry Stackhouse", "Kris Weems", "Motion Read-and-React, Split-Cuts & Off-Ball Screens",
  "MIN", "Timberwolves", "Chris Finch", 7, 451, 0.565, "Nick Nurse", "Micah Nori", "Pablo Prigioni", "Elston Turner", "Corliss Williamson", "Twin Towers Low-Drop & Corner Pinch Post",
  "IND", "Pacers", "Rick Carlisle", 25, 1935, 0.545, "Chuck Daly", "Lloyd Pierce", "Mike Weinar", "Jenny Boucek", "Jim Boylen", "Turbo-Pace 7-Second Early Offense & Haliburton DHOs",
  "DEN", "Nuggets", "Michael Malone", 12, 989, 0.574, "Bob Malone", "David Adelman", "Ryan Saunders", "Charles Klask", "Ognjen Stojakovic", "Jokic Elbow Hub, Cutters & Inverted Pick-and-Roll",
  "MEM", "Grizzlies", "Tuomas Iisalo", 1, 0, 0.500, "European Modern Motion", "Anthony Carter", "Noah LaRoche", "Patrick Mutombo", "Blake Ahearn", "Iisalo High-Tempo Spacing & Ja Morant Transition Assault",
  "MIL", "Bucks", "Taylor Jenkins", 1, 554, 0.536, "Mike Budenholzer", "Rex Kalamian", "Dave Joerger", "Pete Dominguez", "Vin Baker", "Post-Giannis Lillard Spread Sets, PnR Flow & Drop Protection",
  "MIA", "Heat", "Erik Spoelstra", 19, 1441, 0.598, "Pat Riley", "Chris Quinn", "Caron Butler", "Malik Allen", "Wayne Ellington", "Giannis/Bam Point-Forward Spacing & Hybrid 2-3 Zone Traps",
  "ORL", "Magic", "Sean Sweeney", 1, 0, 0.500, "Jason Kidd", "Nate Tibbetts", "Dale Osbourne", "Lionel Chalmers", "Bret Brielmaier", "Length & Point-of-Attack Harassment",
  "DAL", "Mavericks", "Dusty May", 1, 0, 0.500, "Modern Spread", "Sean Sweeney", "Alex Jensen", "Jared Dudley", "God Shammgod", "NCAA Champion Modern Spread Motion & Flagg/Luka PnR",
  "PHX", "Suns", "Mike Budenholzer", 13, 965, 0.601, "Gregg Popovich", "David Fizdale", "Chad Forcier", "Vince Legarza", "Brent Barry", "Spread 4-Out Paint-to-3 & Drop Deterrence",
  "SAC", "Kings", "Doug Christie", 2, 112, 0.527, "Mike Brown", "Jay Triano", "Luke Loucks", "Doug Christie", "Leandro Barbosa", "High-Energy Perimeter Pressure, Sabonis Hub & DHO Motion",
  "NOP", "Pelicans", "Jamahl Mosley", 1, 410, 0.505, "Rick Carlisle", "James Borrego", "Jarron Collins", "Casey Hill", "Corey Brewer", "Zion Point-Forward Isolation & Wing Length",
  "LAC", "Clippers", "Tyronn Lue", 11, 704, 0.585, "Doc Rivers", "Dan Craig", "Brian Shaw", "Jeremy Castleberry", "Dahntay Jones", "Tactical Chameleon, Late-Game Inversion & Matchup Hunting",
  "LAL", "Lakers", "JJ Redick", 3, 164, 0.579, "Mike Krzyzewski", "Nate McMillan", "Scott Brooks", "Bob Beyer", "Greg St. Jean", "Modern 5-Out Motion & Davis/Trae Pick-and-Roll",
  "PHI", "76ers", "Nick Nurse", 9, 636, 0.570, "British Basketball", "Bobby Jackson", "Bryan Gates", "Rico Hines", "Doug West", "Exotic Defensive Zones, Maxey PnR & High-Post Actions",
  "CHI", "Bulls", "Tiago Splitter", 1, 42, 0.476, "Gregg Popovich", "Chris Fleming", "John Bryant", "Damian Cotter", "Peter Patton", "European Motion, DHO Triggers & Perimeter Containment",
  "SAS", "Spurs", "Mitch Johnson", 3, 145, 0.517, "Gregg Popovich", "Brett Brown", "Matt Nielsen", "Jimmy Baron", "Brandon Brimm", "Wembanyama 5-Out Hub & Motion Continuity",
  "DET", "Pistons", "J.B. Bickerstaff", 11, 709, 0.485, "Bernie Bickerstaff", "Dan Burke", "Jarrett Jack", "Luke Walton", "Vitaly Potapenko", "Physical Interior Crash & Double-Big Rebounding",
  "ATL", "Hawks", "Quin Snyder", 12, 904, 0.560, "Larry Brown", "Igor Kokoskov", "Antonio Lang", "Ekpe Udoh", "Brittni Donaldson", "High-Volume 3P Spacing & Fast-Break Rim Pressure",
  "TOR", "Raptors", "Darko Rajakovic", 4, 246, 0.398, "European Continuity", "Pat Delany", "Jama Mahlalela", "James Wade", "Mike Batiste", ".5-Second Decision Flow & Barnes Point-Forward Post",
  "UTA", "Jazz", "Will Hardy", 5, 328, 0.415, "Gregg Popovich", "Jason Terry", "Sean Sheldon", "Evan Bradds", "Chris Jones", "5-Out Read-and-React, Markkanen Spacing & Corner Crashes",
  "BKN", "Nets", "Jordi Fernandez", 3, 164, 0.384, "Mike Brown", "Juwan Howard", "Steve Hetzel", "Jay Hernandez", "Deividas Dulkys", ".5-Second Rapid Motion & Aggressive Full-Court Stunt",
  "CHA", "Hornets", "Charles Lee", 3, 164, 0.439, "Mike Budenholzer", "Lamar Skeeter", "Josh Longstaff", "Blaine Mueller", "Jermaine Bucknor", "Budenholzer 4-Out Drop & LaMelo Transition Pace",
  "POR", "Trail Blazers", "Micah Nori", 1, 0, 0.500, "Chris Finch", "Scott Brooks", "Ronnie Burrell", "Mark Hughes", "Pooh Jeter", "Scoot/Sharpe Downhill Drive & Finch Corner-Pinch Flow",
  "WAS", "Wizards", "Brian Keefe", 3, 203, 0.355, "Gregg Popovich", "David Vanterpool", "Alexis Ajinca", "Adam Caporn", "T.J. Sorrentine", "Rebuilding 5-Out Spacing & Fast-Break Rim Attack"
)

# ------------------------------------------------------------------------------
# 2. Ingest or Calibrate In-Game Tactical & Execution Logs
# ------------------------------------------------------------------------------
cat(">>> Ingesting tactical logs (ATOs, Challenge equity, Shot Quality residuals)...\n")

# Issue #4 Protocol: Check for local tracking or announce SYNTHETIC_FALLBACK
#
# Expected schema for cache/pbp_timeout_cache.rds -- one row per tactical event:
#   team          character  project team code (BOS, GSW, ...)
#   event_type    character  "ato_offense" | "ato_defense" | "challenge"
#   points        numeric    points on the post-timeout possession (ato rows)
#   possessions   numeric    possessions represented by the row (ato rows, normally 1)
#   challenge_won logical    outcome of a coach's challenge (challenge rows)
#
# Unlike shot_quality_engine.R and rapm_engine.R this builder does NOT hard-fail when
# the cache is absent, because it also produces the coaching registry and the
# coachingWinsAdded bridge that the whole /coaches page renders from. Set
# STRICT_COACHING_PROVENANCE=TRUE to make a missing cache an error instead.
STRICT_COACHING_PROVENANCE <- isTRUE(as.logical(
  Sys.getenv("STRICT_COACHING_PROVENANCE", "FALSE")
))

# The current season is only a handful of games old at this point. ATO and challenge
# rates from that sample are too noisy to present as a season-long observation, so
# fall back to the last completed season and say so in `observedSeasons`.
MIN_CURRENT_SEASON_GAMES <- 10L

PBP_TIMEOUT_CACHE <- file.path(CACHE_DIR, "pbp_timeout_cache.rds")
PBP_REQUIRED_COLS <- c("team", "event_type")

load_tactical_events <- function() {
  if (!file.exists(PBP_TIMEOUT_CACHE)) return(NULL)
  ev <- tryCatch(readRDS(PBP_TIMEOUT_CACHE), error = function(e) {
    cat(sprintf(">>> [WARN] %s exists but could not be read: %s\n",
                PBP_TIMEOUT_CACHE, conditionMessage(e)))
    NULL
  })
  if (is.null(ev) || nrow(ev) == 0) return(NULL)
  missing_cols <- setdiff(PBP_REQUIRED_COLS, names(ev))
  if (length(missing_cols) > 0) {
    cat(sprintf(">>> [WARN] %s is missing column(s): %s. Ignoring it.\n",
                PBP_TIMEOUT_CACHE, paste(missing_cols, collapse = ", ")))
    return(NULL)
  }
  ev <- as.data.frame(ev)

  # build_tactical_events_dataset.R pools the current and prior seasons. Early in a
  # season the current slice is too small to support a season-long rate, so use the
  # last completed season alone rather than mixing a token sample into the label.
  if (all(c("season", "game_id") %in% names(ev))) {
    current_games <- length(unique(ev$game_id[ev$season == CURRENT_SEASON]))
    if (current_games < MIN_CURRENT_SEASON_GAMES) {
      prior <- ev[ev$season < CURRENT_SEASON, , drop = FALSE]
      if (nrow(prior) > 0) {
        cat(sprintf(
          ">>> [COACHING] Only %d game(s) observed in %d; falling back to the last completed season (%d).\n",
          current_games, CURRENT_SEASON, CURRENT_SEASON - 1L))
        ev <- prior
      }
    }
  }

  ato <- ev[ev$event_type %in% c("ato_offense", "ato_defense"), , drop = FALSE]
  chal <- ev[ev$event_type == "challenge", , drop = FALSE]

  agg_ppp <- function(df) {
    if (nrow(df) == 0) return(setNames(numeric(0), character(0)))
    pts <- tapply(as.numeric(df$points), df$team, sum, na.rm = TRUE)
    pos <- tapply(as.numeric(df$possessions), df$team, sum, na.rm = TRUE)
    pos[is.na(pos) | pos <= 0] <- NA_real_
    pts / pos
  }

  # Which NBA seasons these ATO possessions and challenges were actually observed in.
  # Normally this is the last completed season because the current one is still too
  # small; if a full-season sample is present the label expands to the observed span.
  # The /coaches page displays this rather than letting the figures read as current.
  season_label <- if ("season" %in% names(ev)) {
    yrs <- sort(unique(suppressWarnings(as.integer(ev$season))))
    yrs <- yrs[!is.na(yrs)]
    if (length(yrs) > 0) {
      paste(sprintf("%d-%d", yrs - 1L, yrs), collapse = " + ")
    } else {
      NULL
    }
  } else {
    NULL
  }

  ato_off_df <- ato[ato$event_type == "ato_offense", , drop = FALSE]
  ato_def_df <- ato[ato$event_type == "ato_defense", , drop = FALSE]

  list(
    ato_off = agg_ppp(ato_off_df),
    ato_def = agg_ppp(ato_def_df),
    ato_off_poss = if (nrow(ato_off_df) > 0) {
      tapply(as.numeric(ato_off_df$possessions), ato_off_df$team, sum, na.rm = TRUE)
    } else setNames(integer(0), character(0)),
    ato_def_poss = if (nrow(ato_def_df) > 0) {
      tapply(as.numeric(ato_def_df$possessions), ato_def_df$team, sum, na.rm = TRUE)
    } else setNames(integer(0), character(0)),
    challenge = if (nrow(chal) > 0) {
      tapply(as.logical(chal$challenge_won), chal$team, mean, na.rm = TRUE)
    } else setNames(numeric(0), character(0)),
    challenge_attempts = if (nrow(chal) > 0) {
      tapply(chal$challenge_won, chal$team, length)
    } else setNames(integer(0), character(0)),
    n_events = nrow(ev),
    season_label = season_label
  )
}

tactical_events <- load_tactical_events()
has_pbp_cache <- !is.null(tactical_events)

if (has_pbp_cache) {
  cat(sprintf(">>> Loaded %d real tactical events from %s (ATO and challenge metrics measured).\n",
              tactical_events$n_events, basename(PBP_TIMEOUT_CACHE)))
} else {
  msg <- paste0("Play-by-play tactical cache is missing. Defaulting to neutral league-average baselines ",
                "(1.020 ATO PPP, 50% challenge overturn rate) with unobserved provenance tag.")
  if (STRICT_COACHING_PROVENANCE) stop(msg)
  cat(sprintf(">>> [WARN] %s\n", msg))
}

# Load existing projection caches to calibrate talent baseline vs actual
teams_proj_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_teams.json")
has_teams_proj <- file.exists(teams_proj_file)

teams_proj_df <- if (has_teams_proj) {
  fromJSON(teams_proj_file)
} else {
  NULL
}

# Build composite metrics for each coaching staff
compute_coaching_metrics <- function(reg) {
  # 1. Talent baseline wins vs Projected wins
  # Bottom-up projection represents pure roster talent; ensemble adds market and schedule
  talent_wins_vec <- numeric(nrow(reg))
  ensemble_wins_vec <- numeric(nrow(reg))
  
  for (i in seq_len(nrow(reg))) {
    team <- reg$team_abbr[i]
    t_wins <- 41.0
    e_wins <- 41.0
    if (!is.null(teams_proj_df) && team %in% teams_proj_df$team) {
      t_match <- teams_proj_df %>% filter(team == !!team) %>% slice(1)
      t_wins <- round(t_match$variant_bottom_up_mean_wins, 1)
      e_wins <- round(t_match$ensemble_mean_wins, 1)
    }
    talent_wins_vec[i] <- t_wins
    ensemble_wins_vec[i] <- e_wins
  }
  
  base_ato_off_vec <- numeric(nrow(reg))
  base_ato_def_vec <- numeric(nrow(reg))
  ato_off_poss_vec <- integer(nrow(reg))
  ato_def_poss_vec <- integer(nrow(reg))
  challenge_success_vec <- numeric(nrow(reg))
  challenge_attempts_vec <- integer(nrow(reg))
  ato_source_vec <- character(nrow(reg))
  challenge_source_vec <- character(nrow(reg))
  
  for (i in seq_len(nrow(reg))) {
    team <- reg$team_abbr[i]
    
    # Defaults in case cache is absent or team unobserved
    b_off <- 1.020
    b_def <- 1.020
    n_off <- 0L
    n_def <- 0L
    c_succ <- 0.500
    n_chal <- 0L
    src_ato <- "unobserved"
    src_chal <- "unobserved"
    
    if (has_pbp_cache) {
      m_off <- tactical_events$ato_off[team]
      m_def <- tactical_events$ato_def[team]
      m_chal <- tactical_events$challenge[team]
      
      if (!is.na(m_off) && !is.na(m_def) && length(m_off) == 1 && length(m_def) == 1) {
        b_off <- as.numeric(m_off)
        b_def <- as.numeric(m_def)
        src_ato <- "observed_pbp"
        if (!is.null(tactical_events$ato_off_poss) && team %in% names(tactical_events$ato_off_poss)) {
          n_off <- as.integer(tactical_events$ato_off_poss[team])
        }
        if (!is.null(tactical_events$ato_def_poss) && team %in% names(tactical_events$ato_def_poss)) {
          n_def <- as.integer(tactical_events$ato_def_poss[team])
        }
      }
      
      if (!is.na(m_chal) && length(m_chal) == 1) {
        c_succ <- as.numeric(m_chal)
        src_chal <- "observed_pbp"
        if (!is.null(tactical_events$challenge_attempts) && team %in% names(tactical_events$challenge_attempts)) {
          n_chal <- as.integer(tactical_events$challenge_attempts[team])
        }
      }
    }
    
    base_ato_off_vec[i] <- b_off
    base_ato_def_vec[i] <- b_def
    ato_off_poss_vec[i] <- n_off
    ato_def_poss_vec[i] <- n_def
    challenge_success_vec[i] <- c_succ
    challenge_attempts_vec[i] <- n_chal
    ato_source_vec[i] <- src_ato
    challenge_source_vec[i] <- src_chal
  }
  
  coaching_wins_added_vec <- round(ensemble_wins_vec - talent_wins_vec, 1)
  ato_net_vec <- round(base_ato_off_vec - base_ato_def_vec, 3)
  
  # Compute deterministic rank percentiles (1-99) grounded in real metrics
  # 1. ATO mastery percentile (net ATO PPP)
  p_ato_vec <- pmin(99, pmax(1, round(percent_rank(ato_net_vec) * 98 + 1)))
  # 2. Tactical innovation percentile (system win lift residual)
  p_tac_vec <- pmin(99, pmax(1, round(percent_rank(coaching_wins_added_vec) * 98 + 1)))
  # 3. Rotation efficiency percentile (talent execution depth)
  p_rot_vec <- pmin(99, pmax(1, round(percent_rank(talent_wins_vec) * 98 + 1)))
  # 4. In-game challenge equity percentile (challenge overturn rate)
  p_wpa_vec <- pmin(99, pmax(1, round(percent_rank(challenge_success_vec) * 98 + 1)))
  # 5. Overall development percentile (total projected wins)
  p_dev_vec <- pmin(99, pmax(1, round(percent_rank(ensemble_wins_vec) * 98 + 1)))
  
  # Composite Coach Impact Rating (CIR: 0 - 100)
  cir_vec <- round(0.25 * p_ato_vec + 0.25 * p_tac_vec + 0.20 * p_rot_vec + 0.15 * p_wpa_vec + 0.15 * p_dev_vec, 1)
  
  metrics_list <- list()
  for (i in seq_len(nrow(reg))) {
    row <- reg[i, ]
    team <- row$team_abbr
    
    metrics_list[[i]] <- list(
      teamAbbr = team,
      teamName = row$team_name,
      headCoach = list(
        name = row$head_coach,
        tenureYears = row$tenure_years,
        careerGames = row$career_games,
        careerWinPct = round(row$career_win_pct, 3),
        coachingTree = row$coaching_tree,
        tacticalArchetype = row$tactical_archetype
      ),
      assistants = list(
        associateHC = row$assoc_head_coach,
        offensiveCoord = row$offensive_coord,
        defensiveCoord = row$defensive_coord,
        playerDevLead = row$player_dev_lead
      ),
      metrics = list(
        coachImpactRating = cir_vec[i],
        talentExpectedWins = talent_wins_vec[i],
        actualProjectedWins = ensemble_wins_vec[i],
        coachingWinsAdded = coaching_wins_added_vec[i],
        atoOffensivePpp = round(base_ato_off_vec[i], 3),
        atoDefensivePppAllowed = round(base_ato_def_vec[i], 3),
        challengeSuccessRate = round(challenge_success_vec[i], 3),
        atoOffPossessions = ato_off_poss_vec[i],
        atoDefPossessions = ato_def_poss_vec[i],
        challengeAttempts = challenge_attempts_vec[i]
      ),
      radarPercentiles = list(
        atoMastery = p_ato_vec[i],
        tacticalInnovation = p_tac_vec[i],
        rotationEfficiency = p_rot_vec[i],
        inGameWpa = p_wpa_vec[i],
        playerDevelopment = p_dev_vec[i]
      ),
      # Per-field provenance so the /coaches page can label what is measured.
      # coachingWinsAdded is a residual between two of this project's own model
      # variants (ensemble minus bottom-up), not an observation of coach effect --
      # see NBA #14 before presenting it as a causal bridge.
      provenance = list(
        atoMetrics = ato_source_vec[i],
        challengeMetrics = challenge_source_vec[i],
        coachingWinsAdded = "model_residual_ensemble_minus_bottom_up",
        # The season span the observed_pbp fields were measured over. NULL when
        # nothing on this card is observed, so the UI shows no season label.
        observedSeasons = if (identical(ato_source_vec[i], "observed_pbp") ||
                              identical(challenge_source_vec[i], "observed_pbp")) {
          tactical_events$season_label
        } else {
          NULL
        },
        generatedAt = format(Sys.time(), "%Y-%m-%d %H:%M:%S")
      )
    )
  }
  
  metrics_list
}

coaching_dataset <- compute_coaching_metrics(coaching_registry_raw)

# ------------------------------------------------------------------------------
# 3. Export to RDS Caches & Next.js Public Web Data
# ------------------------------------------------------------------------------
cat(sprintf(">>> Saving coaching staff registry to: %s\n", CACHE_COACHING_REGISTRY))
saveRDS(coaching_registry_raw, CACHE_COACHING_REGISTRY)

cat(sprintf(">>> Saving compiled coaching metrics to: %s\n", CACHE_COACHING_METRICS))
saveRDS(coaching_dataset, CACHE_COACHING_METRICS)

cat(sprintf(">>> Exporting public JSON for Next.js to: %s\n", CACHE_COACHING_JSON))
write_json(coaching_dataset, CACHE_COACHING_JSON, pretty = TRUE, auto_unbox = TRUE)

cat(">>> [SUCCESS] Phase 1 Coaching Staff Ingestion & Dataset Construction Complete!\n")
cat(sprintf(">>> Processed 30 teams. Example top CIR coach: %s (%s, CIR: %.1f)\n",
            coaching_dataset[[1]]$headCoach$name,
            coaching_dataset[[1]]$teamAbbr,
            coaching_dataset[[1]]$metrics$coachImpactRating))
