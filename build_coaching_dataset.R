# ==============================================================================
# build_coaching_dataset.R
# Ingests and compiles NBA coaching staff registries, ATO (After-Timeout) efficiency,
# in-game challenge/clock leverage, and talent-adjusted coaching impact metrics.
# Exports RDS caches and Next.js public JSON for web presentation.
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

  list(
    ato_off = agg_ppp(ato[ato$event_type == "ato_offense", , drop = FALSE]),
    ato_def = agg_ppp(ato[ato$event_type == "ato_defense", , drop = FALSE]),
    challenge = if (nrow(chal) > 0) {
      tapply(as.logical(chal$challenge_won), chal$team, mean, na.rm = TRUE)
    } else setNames(numeric(0), character(0)),
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
  msg <- paste0("Using SYNTHETIC_FALLBACK for PBP ATO timeout events and challenge records ",
                "(adhering to Issue #4 logging standards). These fields are drawn from ",
                "hand-assigned per-coach bands, not observed play-by-play.")
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
  set.seed(42) # Deterministic calibration
  
  metrics_list <- list()
  
  for (i in 1:nrow(reg)) {
    row <- reg[i, ]
    team <- row$team_abbr
    
    # 1. Talent baseline wins vs Projected wins
    # Bottom-up projection represents pure roster talent; ensemble adds market and schedule
    talent_wins <- 41.0
    ensemble_wins <- 41.0
    
    if (!is.null(teams_proj_df) && team %in% teams_proj_df$team) {
      t_match <- teams_proj_df %>% filter(team == !!team) %>% slice(1)
      talent_wins <- round(t_match$variant_bottom_up_mean_wins, 1)
      ensemble_wins <- round(t_match$ensemble_mean_wins, 1)
    }
    
    # Coaching wins added (delta between talent baseline and integrated model projection)
    coaching_wins_added <- round(ensemble_wins - talent_wins, 1)
    
    # 2. ATO Efficiency (Offensive PPP and Defensive PPP Allowed)
    # NBA League Average half-court PPP is ~0.96. Elite ATO offenses hit 1.08 - 1.18.
    # Elite ATO defenses suppress opponent ATOs below 0.90.
    base_ato_off <- case_when(
      row$head_coach %in% c("Joe Mazzulla", "Rick Carlisle", "Mark Daigneault", "Steve Kerr", "Tuomas Iisalo") ~ runif(1, 1.10, 1.18),
      row$head_coach %in% c("Erik Spoelstra", "Tyronn Lue", "Michael Malone", "Chris Finch", "Taylor Jenkins") ~ runif(1, 1.06, 1.14),
      row$head_coach %in% c("Kenny Atkinson", "Quin Snyder", "Ime Udoka", "JJ Redick", "Mitch Johnson", "Mike Brown", "Dusty May") ~ runif(1, 1.02, 1.09),
      TRUE ~ runif(1, 0.94, 1.04)
    )
    
    base_ato_def <- case_when(
      row$head_coach %in% c("Erik Spoelstra", "Ime Udoka", "Mark Daigneault", "Doug Christie") ~ runif(1, 0.88, 0.95),
      row$head_coach %in% c("Joe Mazzulla", "Chris Finch", "Mike Budenholzer", "Mitch Johnson", "Jamahl Mosley", "Sean Sweeney") ~ runif(1, 0.93, 0.99),
      row$head_coach %in% c("Rick Carlisle", "Quin Snyder") ~ runif(1, 1.02, 1.08),
      TRUE ~ runif(1, 0.97, 1.03)
    )
    
    # 3. Challenge Equity & WPA
    # Challenge success rate typically ranges from 45% to 75%
    challenge_success <- case_when(
      row$head_coach %in% c("Mark Daigneault", "Michael Malone", "Tyronn Lue") ~ runif(1, 0.68, 0.76),
      row$head_coach %in% c("Erik Spoelstra", "Joe Mazzulla", "Steve Kerr", "Mike Brown") ~ runif(1, 0.58, 0.67),
      TRUE ~ runif(1, 0.44, 0.57)
    )

    # Measured values override the per-coach bands wherever the tactical event cache
    # covers this team. Tracked per field so the export can say which is which.
    ato_source <- "synthetic_coach_band"
    challenge_source <- "synthetic_coach_band"
    if (has_pbp_cache) {
      m_off <- tactical_events$ato_off[team]
      m_def <- tactical_events$ato_def[team]
      m_chal <- tactical_events$challenge[team]
      if (!is.na(m_off) && !is.na(m_def) && length(m_off) == 1 && length(m_def) == 1) {
        base_ato_off <- as.numeric(m_off)
        base_ato_def <- as.numeric(m_def)
        ato_source <- "observed_pbp"
      }
      if (!is.na(m_chal) && length(m_chal) == 1) {
        challenge_success <- as.numeric(m_chal)
        challenge_source <- "observed_pbp"
      }
    }

    # Challenge WPA (Season Win Probability Added from overturned high-leverage calls)
    challenge_wpa <- round((challenge_success - 0.50) * 0.85 + runif(1, -0.05, 0.15), 3)
    
    # 4. Shot Quality Lift (eFG% lift generated by scheme spacing vs pure personnel)
    sq_lift <- case_when(
      row$head_coach %in% c("Joe Mazzulla", "Steve Kerr", "Rick Carlisle", "Kenny Atkinson", "Mike Brown", "Tuomas Iisalo") ~ runif(1, 0.024, 0.042),
      row$head_coach %in% c("Mark Daigneault", "Michael Malone", "Erik Spoelstra", "Dusty May") ~ runif(1, 0.015, 0.026),
      TRUE ~ runif(1, -0.015, 0.012)
    )
    
    # 5. Rotation Stagger Score (0-100: Star staggering vs bench bleed prevention)
    stagger_score <- case_when(
      row$head_coach %in% c("Mark Daigneault", "Chris Finch", "Erik Spoelstra", "Steve Kerr", "Taylor Jenkins") ~ round(runif(1, 88, 97)),
      row$head_coach %in% c("Joe Mazzulla", "Ime Udoka", "Mike Brown", "Mitch Johnson") ~ round(runif(1, 78, 87)),
      TRUE ~ round(runif(1, 55, 75))
    )
    
    # 6. Player Development Score (0-100: Young player YoY value growth)
    dev_score <- case_when(
      row$head_coach %in% c("Mark Daigneault", "Erik Spoelstra", "Jamahl Mosley", "Will Hardy", "Micah Nori", "Mitch Johnson") ~ round(runif(1, 90, 98)),
      row$head_coach %in% c("Kenny Atkinson", "Taylor Jenkins", "Ime Udoka", "Tiago Splitter", "Charles Lee") ~ round(runif(1, 82, 89)),
      TRUE ~ round(runif(1, 58, 80))
    )
    
    # Normalized 5 Radar Percentiles (1 to 99)
    p_ato <- min(99, max(1, round(50 + (base_ato_off - 1.02) * 350 - (base_ato_def - 0.98) * 250)))
    p_tac <- min(99, max(1, round(50 + sq_lift * 1200)))
    p_rot <- min(99, max(1, round(stagger_score)))
    p_wpa <- min(99, max(1, round(50 + challenge_wpa * 180)))
    p_dev <- min(99, max(1, round(dev_score)))
    
    # Composite Coach Impact Rating (CIR: 0 - 100)
    cir <- round(0.25 * p_ato + 0.25 * p_tac + 0.20 * p_rot + 0.15 * p_wpa + 0.15 * p_dev, 1)
    
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
        coachImpactRating = cir,
        talentExpectedWins = talent_wins,
        actualProjectedWins = ensemble_wins,
        coachingWinsAdded = coaching_wins_added,
        atoOffensivePpp = round(base_ato_off, 3),
        atoDefensivePppAllowed = round(base_ato_def, 3),
        challengeSuccessRate = round(challenge_success, 3),
        challengeWpa = challenge_wpa,
        shotQualityLiftEfg = round(sq_lift * 100, 2),
        rotationStaggerScore = stagger_score,
        playerDevelopmentScore = dev_score
      ),
      radarPercentiles = list(
        atoMastery = p_ato,
        tacticalInnovation = p_tac,
        rotationEfficiency = p_rot,
        inGameWpa = p_wpa,
        playerDevelopment = p_dev
      ),
      # Per-field provenance so the /coaches page can label what is measured.
      # coachingWinsAdded is a residual between two of this project's own model
      # variants (ensemble minus bottom-up), not an observation of coach effect --
      # see NBA #14 before presenting it as a causal bridge.
      provenance = list(
        atoMetrics = ato_source,
        challengeMetrics = challenge_source,
        coachingWinsAdded = "model_residual_ensemble_minus_bottom_up",
        shotQualityLift = "synthetic_coach_band",
        rotationAndDevelopment = "synthetic_coach_band",
        # The season span the observed_pbp fields were measured over. NULL when
        # nothing on this card is observed, so the UI shows no season label rather
        # than putting a real-looking span next to a synthetic band.
        observedSeasons = if (identical(ato_source, "observed_pbp") ||
                              identical(challenge_source, "observed_pbp")) {
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
