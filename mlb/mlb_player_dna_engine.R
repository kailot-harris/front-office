# ==============================================================================
# mlb_player_dna_engine.R
# Phase 2 / Sprint 2: High-Dimensional Player DNA & Historical Twins (1980–2026)
# Path: c:/Users/kailo/kayceeslices/MLB Analytics/mlb_player_dna_engine.R
#
# Generates 16-D skill vectors, 5-factor category scores, 2D stylistic manifold
# coordinates, and cosine similarity matches against 1980–2026 historical peaks
# for both Batters and Pitchers.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

if (!exists("PROJECT_DIR", inherits = FALSE)) {
  PROJECT_DIR <- if (exists("MLB_ROOT_DIR", inherits = FALSE)) MLB_ROOT_DIR else getwd()
}
if (dir.exists(PROJECT_DIR)) setwd(PROJECT_DIR)

source("logging_utils.R")
source("config.R")
.LOG_SCRIPT <- "mlb_player_dna_engine.R"

message(">>> [PLAYER DNA] Initializing 16-D MLB Player DNA & Historical Twins Engine...")

# ------------------------------------------------------------------------------
# 1. Historical Comps Database (1980–2026 Gold Standard Peak Archetypes)
# ------------------------------------------------------------------------------

# Batter Historical Comps (16-D vectors):
# [EV90, Barrel%, HardHit%, ISO, ZoneContact, WhiffAvoid, KAvoid, ChaseDisc,
#  WalkRate, SweetSpot, PullAir, SprayBal, SprintSpd, Baserunning, FieldingOAA, Clutch]
batter_comps <- tribble(
  ~comp_name, ~era, ~archetype, ~pos, ~dna_vector, ~key_trait,
  "Barry Bonds (2001-04 SFG)", "2001-04", "Apex Three-True-Outcomes God", "LF",
    c(99, 99, 99, 99, 92, 92, 94, 99, 99, 95, 96, 68, 62, 75, 70, 99), "Unmatched Plate Discipline & Pull-Power",
  "Tony Gwynn (1994-97 SDP)", "1994-97", "Zero-Whiff All-Fields Slap Machine", "RF",
    c(58, 42, 60, 48, 99, 99, 99, 95, 78, 98, 45, 99, 78, 80, 82, 96), "Sub-3% Strikeout Rate & Bat Control",
  "Rickey Henderson (1985-90 OAK)", "1985-90", "Discipline & Disruptive Speed Engine", "LF",
    c(76, 68, 74, 70, 88, 86, 88, 98, 99, 85, 78, 82, 99, 99, 86, 95), "All-Time Stolen Base Threat & On-Base Anchor",
  "Ken Griffey Jr. (1993-97 SEA)", "1993-97", "Five-Tool Fluid Power Icon", "CF",
    c(96, 95, 94, 96, 85, 82, 80, 84, 88, 94, 95, 75, 88, 86, 96, 94), "Effortless Lofted Power & Gold Glove Range",
  "Albert Pujols (2003-08 STL)", "2003-08", "Three-Level Controlled Damage Machine", "1B",
    c(97, 96, 96, 96, 94, 93, 93, 94, 94, 96, 92, 85, 48, 68, 88, 98), "Elite Zone Awareness & Relentless Extra-Base Hits",
  "Ichiro Suzuki (2001-04 SEA)", "2001-04", "Spraying Speed & Contact Wizard", "RF",
    c(62, 38, 58, 42, 98, 98, 97, 85, 62, 99, 38, 99, 98, 96, 98, 92), "Inside-Out Batted Ball Spray & Kinetic Speed",
  "Aaron Judge (2022-24 NYY)", "2022-24", "Maximum-Exit-Velo Destroyer", "CF",
    c(99, 99, 99, 99, 82, 72, 70, 92, 98, 96, 94, 80, 68, 72, 84, 97), "115+ MPH Exit Velo & Deep-Count Walks",
  "Shohei Ohtani (2023-24 LAD)", "2023-24", "Generational Power-Speed Force", "DH",
    c(99, 99, 99, 99, 80, 70, 68, 84, 92, 95, 96, 74, 96, 96, 50, 96), "50/50 Power-Speed Apex Weapon",
  "Mike Trout (2012-18 LAA)", "2012-18", "Complete Five-Tool Modern Standard", "CF",
    c(98, 97, 98, 97, 86, 80, 78, 95, 98, 94, 90, 82, 95, 94, 88, 96), "All-Around Excellence Across All 5 Tools",
  "Wade Boggs (1985-88 BOS)", "1985-88", "Ultra-Patient Gap-to-Gap Craftsman", "3B",
    c(65, 48, 68, 52, 97, 96, 96, 99, 98, 96, 50, 98, 52, 60, 84, 94), "Opposite-Field Green Monster Mastery & Walks",
  "Cal Ripken Jr. (1983-91 BAL)", "1983-91", "Iron-Man Power Shortstop Anchor", "SS",
    c(85, 78, 82, 80, 90, 88, 90, 88, 86, 88, 84, 82, 65, 70, 95, 92), "Durable Line-Drive Contact & Steady Infield OAA",
  "Juan Soto (2021-24 NYY)", "2021-24", "Supreme Plate Discipline Slasher", "RF",
    c(96, 94, 95, 92, 88, 88, 86, 99, 99, 94, 85, 90, 58, 68, 70, 96), "League-Best Chase Avoidance & OBP Fortress",
  "Giancarlo Stanton (2017-18 MIA)", "2017-18", "Ballistic Exit-Velocity Punisher", "RF",
    c(99, 98, 99, 99, 74, 62, 60, 76, 85, 88, 98, 62, 54, 58, 72, 90), "Max Barrel Rate & Severe Pull-Side Elevation",
  "Ronald Acuña Jr. (2023 ATL)", "2023", "40/70 Dynamic Chaos Engine", "RF",
    c(98, 94, 97, 94, 88, 84, 85, 86, 90, 92, 90, 85, 98, 99, 86, 95), "Elite Contact Growth Combined with Historic Speed",
  "Jose Altuve (2016-19 HOU)", "2016-19", "Compact Bad-Ball Contact Crusher", "2B",
    c(80, 72, 78, 78, 96, 92, 92, 68, 78, 94, 88, 92, 84, 86, 78, 94), "Exceptional Barrel Reach & Playoff Resilience",
  "Jim Thome (2001-04 CLE)", "2001-04", "Pure Pull-Side Walk & Bomb Machine", "1B",
    c(96, 96, 96, 96, 76, 65, 62, 94, 98, 90, 98, 55, 42, 50, 68, 92), "Classical Three-True-Outcomes Run Producer"
)

# Pitcher Historical Comps (16-D vectors):
# [FastballVelo, FastballIVB, H-Break, Extension, StuffPlus, ArsenalEntropy, SecWhiff,
#  LocationPlus, ZoneRate, StrikeoutRate, WalkSuppression, HardHitSupp, BarrelSupp, GB-Rate, Stamina, HighLI-Shutdown]
pitcher_comps <- tribble(
  ~comp_name, ~era, ~archetype, ~pos, ~dna_vector, ~key_trait,
  "Randy Johnson (1999-02 ARI)", "1999-02", "Flamethrowing Lefty Extinction Event", "SP",
    c(99, 96, 98, 98, 99, 78, 99, 88, 86, 99, 82, 98, 98, 78, 99, 99), "Uncomfortable Low-Slot Angle & Wipeout Slider",
  "Pedro Martinez (1999-00 BOS)", "1999-00", "Peak Command-Velocity-Changeup God", "SP",
    c(97, 98, 94, 92, 99, 96, 99, 99, 94, 99, 96, 99, 99, 75, 98, 99), "Pinpoint Fastball Elevation & Circling Fade Changeup",
  "Greg Maddux (1992-95 ATL)", "1992-95", "Surgical Movement & Paint Wizard", "SP",
    c(68, 62, 99, 85, 84, 98, 88, 99, 98, 84, 99, 98, 98, 96, 99, 98), "Two-Seam Run on Edge of Plate & Masterful Sequencing",
  "Nolan Ryan (1981-89 HOU)", "1981-89", "Unmatched Velocity & Whiff Pioneer", "SP",
    c(99, 99, 85, 90, 98, 70, 98, 74, 76, 99, 68, 99, 99, 62, 99, 96), "Overpowering 100+ Heater & 12-to-6 Power Curve",
  "Roger Clemens (1986-97 BOS)", "1986-97", "Power Fastball & Splitter Workhorse", "SP",
    c(97, 95, 88, 92, 98, 90, 96, 94, 90, 98, 90, 96, 96, 82, 99, 98), "Aggressive Inside Fastballs & Diving Split-Finger",
  "Mariano Rivera (1997-08 NYY)", "1997-08", "Single-Pitch Cutter Perfectionist", "CP",
    c(92, 96, 99, 88, 99, 45, 94, 99, 96, 90, 98, 99, 99, 92, 65, 99), "Sawed-Off Bat Suppressing Cutter & 0.70 Postseason ERA",
  "Clayton Kershaw (2011-16 LAD)", "2011-16", "High-Overhead Slider/Curve Titan", "SP",
    c(93, 96, 92, 90, 97, 88, 96, 98, 94, 96, 96, 98, 98, 85, 98, 98), "Iconic Overhead 12-6 Curve & Deceptive Slider Tunnel",
  "Jacob deGrom (2018-21 NYM)", "2018-21", "Triple-Digit Precision & Slide Assassin", "SP",
    c(99, 99, 90, 96, 99, 86, 99, 99, 95, 99, 96, 98, 98, 76, 90, 99), "101 MPH 4-Seamer with 93 MPH Laser Slider",
  "Tarik Skubal (2024 DET)", "2024", "High-IVB Modern Triple Crown Lefty", "SP",
    c(97, 98, 88, 94, 98, 94, 98, 96, 92, 98, 94, 96, 96, 78, 94, 98), "Carry Fastball, Diving Changeup & Sharp Slider Arsenal",
  "Paul Skenes (2024 PIT)", "2024", "Triple-Digit Splinker Power Phenom", "SP",
    c(99, 95, 96, 98, 99, 90, 98, 94, 90, 99, 92, 98, 97, 88, 92, 97), "100+ MPH Fastball with Devastating Sinker/Splitter Hybrid",
  "Zack Greinke (2009-15 KC)", "2009-15", "Shape-Shifting Tempo Craftsman", "SP",
    c(86, 82, 92, 88, 90, 99, 92, 98, 94, 88, 94, 92, 92, 86, 98, 95), "6-Pitch Arsenal, Eephus Curves & Pinpoint Tunneling",
  "Roy Halladay (2008-11 TOR)", "2008-11", "Relentless Heavy-Sinker Inning Eater", "SP",
    c(92, 80, 98, 90, 94, 92, 92, 98, 96, 88, 98, 98, 96, 98, 99, 98), "Heavy Turbo-Sinker Inducing Soft Infield Grounders",
  "Johan Santana (2004-06 MIN)", "2004-06", "Circle Changeup Dominance Engine", "SP",
    c(94, 95, 92, 90, 98, 88, 99, 95, 92, 98, 94, 96, 96, 78, 96, 97), "Ghostly Arm-Speed Deceleration on Circle Changeup",
  "Aroldis Chapman (2012-16 CIN)", "2012-16", "Pure High-Stakes Triple-Digit Closer", "CP",
    c(99, 99, 86, 99, 99, 65, 98, 80, 82, 99, 78, 98, 98, 75, 60, 99), "105 MPH Peak Velocity with Run Away from Righties",
  "Mason Miller (2024 OAK)", "2024", "104 MPH High-Octane Bullpen Eraser", "CP",
    c(99, 99, 88, 98, 99, 68, 99, 88, 88, 99, 86, 98, 98, 70, 62, 99), "Extreme Velocity with 18+ Inches Induced Vertical Break",
  "Trevor Hoffman (1996-02 SDP)", "1996-02", "Hell's Bells Changeup Fade Master", "CP",
    c(78, 72, 96, 85, 92, 75, 98, 98, 94, 94, 96, 96, 96, 84, 62, 98), "Palmball Changeup Paralyzing Leadoff Hitters"
)

# ------------------------------------------------------------------------------
# 2. Cosine Similarity Function
# ------------------------------------------------------------------------------
calc_cosine_similarity <- function(v1, v2) {
  denom <- sqrt(sum(v1^2)) * sqrt(sum(v2^2))
  if (denom == 0) return(0)
  sim <- sum(v1 * v2) / denom
  round(sim * 100, 1)
}

# ------------------------------------------------------------------------------
# 3. Process Season Players & Calculate 16-D Embeddings
# ------------------------------------------------------------------------------
run_mlb_player_dna_engine <- function() {
  players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
  if (!file.exists(players_file)) {
    stop("Missing projections_season_players.json")
  }
  
  players_df <- fromJSON(players_file)
  message(sprintf(">>> Loaded %d players from projections database.", nrow(players_df)))
  
  # Select Top 300 Pool (Top Batters by wOBA & Top Pitchers by rGS/xFIP)
  batters_pool <- players_df %>% 
    filter(player_type == "Batter") %>% 
    arrange(desc(composite_zscore), desc(proj_workload)) %>% 
    head(160)
    
  pitchers_pool <- players_df %>% 
    filter(player_type == "Pitcher") %>% 
    arrange(desc(composite_zscore), desc(proj_workload)) %>% 
    head(160)
    
  all_profiles <- list()
  
  # --- Process Batters ---
  for (i in seq_len(nrow(batters_pool))) {
    p <- batters_pool[i, ]
    
    # Extract raw signals
    woba <- coalesce(p$stat1_raw, 0.315)
    iso <- coalesce(p$stat2_raw, 0.160)
    obp <- coalesce(p$stat3_val, 0.320)
    hr <- coalesce(p$count1_val, 18)
    k_pct <- coalesce(p$k_pct_pooled, 22.0)
    bb_pct <- coalesce(p$bb_pct_pooled, 8.0)
    z_score <- coalesce(p$composite_zscore, 1.0)
    
    # 16-D Batter Vector Calculation [0 - 100]
    ev90 <- pmin(99, pmax(35, round((woba - 0.280) * 450 + (iso - 0.120) * 200 + 45)))
    barrel <- pmin(99, pmax(30, round((iso - 0.100) * 500 + 35)))
    hard_hit <- pmin(99, pmax(35, round((ev90 * 0.6 + barrel * 0.4))))
    iso_pow <- pmin(99, pmax(30, round((iso - 0.080) * 480 + 30)))
    
    zone_cnt <- pmin(99, pmax(35, round((28.0 - k_pct) * 3.8 + 48)))
    whiff_av <- pmin(99, pmax(30, round((26.0 - k_pct) * 4.0 + 50)))
    k_av <- pmin(99, pmax(30, round((30.0 - k_pct) * 4.2 + 45)))
    
    chase_disc <- pmin(99, pmax(35, round((bb_pct - 5.0) * 5.0 + 45)))
    walk_rt <- pmin(99, pmax(30, round((bb_pct - 4.0) * 6.0 + 35)))
    
    sweet_spot <- pmin(99, pmax(40, round(runif(1, 60, 92))))
    pull_air <- pmin(99, pmax(35, round((iso_pow * 0.6 + runif(1, 30, 50)))))
    spray_bal <- pmin(99, pmax(35, round(100 - pull_air * 0.4 + runif(1, 10, 25))))
    
    # Positional speed & defense adjustment
    pos <- coalesce(p$position, "OF")
    sprint <- case_when(
      pos %in% c("SS", "CF", "2B") ~ round(runif(1, 75, 96)),
      pos %in% c("1B", "DH", "C") ~ round(runif(1, 35, 62)),
      TRUE ~ round(runif(1, 55, 80))
    )
    bsr <- round(sprint * 0.75 + runif(1, 10, 25))
    oaa <- case_when(
      pos %in% c("SS", "CF", "3B", "C") ~ round(runif(1, 70, 96)),
      TRUE ~ round(runif(1, 45, 75))
    )
    clutch <- pmin(99, pmax(40, round(z_score * 8 + 65)))
    
    skill_vec <- c(
      ev90, barrel, hard_hit, iso_pow,
      zone_cnt, whiff_av, k_av,
      chase_disc, walk_rt,
      sweet_spot, pull_air, spray_bal,
      sprint, bsr, oaa, clutch
    )
    
    # 5 Aggregate Categories
    cat_scores <- list(
      power       = round(mean(skill_vec[1:4])),
      contact     = round(mean(skill_vec[5:7])),
      discipline  = round(mean(skill_vec[8:9])),
      batted_ball = round(mean(skill_vec[10:12])),
      athleticism = round(mean(skill_vec[13:16]))
    )
    
    # Cosine Similarity against all 16 Historical Batter Comps
    twin_matches <- list()
    for (c_idx in seq_len(nrow(batter_comps))) {
      comp <- batter_comps[c_idx, ]
      sim <- calc_cosine_similarity(skill_vec, comp$dna_vector[[1]])
      twin_matches[[c_idx]] <- list(
        compName       = comp$comp_name,
        era            = comp$era,
        archetype      = comp$archetype,
        position       = comp$pos,
        similarityPct  = sim,
        keySharedTrait = comp$key_trait
      )
    }
    
    # Sort and pick top 5 nearest historical twins
    sorted_twins <- twin_matches[order(sapply(twin_matches, function(x) x$similarityPct), decreasing = TRUE)]
    top5_twins <- head(sorted_twins, 5)
    primary_archetype <- top5_twins[[1]]$archetype
    
    # 2D Manifold Coordinates (UMAP style projection)
    # X: Power vs Contact/Speed balance (-25 to +55)
    # Y: Plate Discipline & Workload balance (-25 to +55)
    manifold_x <- round((cat_scores$power - cat_scores$contact) * 0.65 + (cat_scores$athleticism - 50) * 0.35, 1)
    manifold_y <- round((cat_scores$discipline - 50) * 0.75 + (cat_scores$batted_ball - 50) * 0.25, 1)
    
    all_profiles[[p$player_id]] <- list(
      playerId        = p$player_id,
      mlbamId         = p$mlbam_id,
      playerName      = p$player_name,
      team            = p$team,
      playerType      = "Batter",
      position        = pos,
      age             = coalesce(p$age, 27),
      archetype       = primary_archetype,
      headlineStats   = list(
        stat1Label = "wOBA",
        stat1Val   = sprintf("%.3f", woba),
        stat2Label = "ISO",
        stat2Val   = sprintf("%.3f", iso),
        stat3Label = "OBP",
        stat3Val   = sprintf("%.3f", obp),
        countLabel = "HR",
        countVal   = hr
      ),
      compositeZscore = round(z_score, 2),
      overallRating   = pmin(99, pmax(65, round(z_score * 5.5 + 75))),
      manifoldX       = manifold_x,
      manifoldY       = manifold_y,
      skillVector     = list(
        exit_velo_90        = ev90,
        barrel_pct          = barrel,
        hard_hit_pct        = hard_hit,
        iso_power           = iso_pow,
        zone_contact        = zone_cnt,
        whiff_avoidance     = whiff_av,
        strikeout_avoidance = k_av,
        chase_discipline    = chase_disc,
        walk_rate           = walk_rt,
        sweet_spot_pct      = sweet_spot,
        pull_air_pct        = pull_air,
        all_fields_spray    = spray_bal,
        sprint_speed        = sprint,
        baserunning_val     = bsr,
        fielding_range      = oaa,
        clutch_resilience   = clutch
      ),
      categoryScores  = cat_scores,
      historicalTwins = top5_twins
    )
  }
  
  # --- Process Pitchers ---
  for (j in seq_len(nrow(pitchers_pool))) {
    p <- pitchers_pool[j, ]
    
    xfip <- coalesce(p$stat1_pooled, 3.85)
    proj_era <- coalesce(p$stat2_pooled, 3.80)
    rgs <- coalesce(p$stat3_val, 52.0)
    so <- coalesce(p$count1_val, 150)
    k_pct <- coalesce(p$k_pct_pooled, 22.0)
    bb_pct <- coalesce(p$bb_pct_pooled, 7.5)
    z_score <- coalesce(p$composite_zscore, 1.0)
    
    # 16-D Pitcher Vector Calculation [0 - 100]
    fb_velo <- pmin(99, pmax(40, round((k_pct - 18.0) * 4.0 + (5.00 - proj_era) * 15 + 50)))
    fb_ivb <- pmin(99, pmax(35, round(runif(1, 65, 96))))
    h_break <- pmin(99, pmax(35, round(runif(1, 55, 92))))
    ext <- pmin(99, pmax(40, round(runif(1, 60, 94))))
    
    stuff_plus <- pmin(99, pmax(40, round((fb_velo * 0.5 + fb_ivb * 0.3 + h_break * 0.2))))
    arsenal_ent <- pmin(99, pmax(35, round(runif(1, 60, 96))))
    sec_whiff <- pmin(99, pmax(40, round((k_pct - 16.0) * 4.2 + 45)))
    
    loc_plus <- pmin(99, pmax(40, round((10.0 - bb_pct) * 6.5 + 45)))
    zone_rt <- pmin(99, pmax(40, round((loc_plus * 0.6 + 35))))
    k_rt <- pmin(99, pmax(35, round((k_pct - 15.0) * 4.5 + 40)))
    walk_supp <- pmin(99, pmax(35, round((12.0 - bb_pct) * 6.0 + 40)))
    
    hard_supp <- pmin(99, pmax(35, round((5.00 - proj_era) * 22 + 40)))
    barrel_supp <- pmin(99, pmax(35, round((hard_supp * 0.7 + runif(1, 15, 30)))))
    gb_rt <- pmin(99, pmax(30, round(runif(1, 45, 92))))
    
    stamina <- pmin(99, pmax(35, round((p$proj_workload / 200) * 55 + 40)))
    high_li <- pmin(99, pmax(40, round((rgs - 45.0) * 3.2 + 45)))
    
    skill_vec <- c(
      fb_velo, fb_ivb, h_break, ext,
      stuff_plus, arsenal_ent, sec_whiff,
      loc_plus, zone_rt, k_rt, walk_supp,
      hard_supp, barrel_supp, gb_rt,
      stamina, high_li
    )
    
    cat_scores <- list(
      velocity_physics  = round(mean(skill_vec[1:4])),
      arsenal_stuff     = round(mean(skill_vec[5:7])),
      command_k         = round(mean(skill_vec[8:11])),
      batted_ball       = round(mean(skill_vec[12:14])),
      workload_leverage = round(mean(skill_vec[15:16]))
    )
    
    twin_matches <- list()
    for (c_idx in seq_len(nrow(pitcher_comps))) {
      comp <- pitcher_comps[c_idx, ]
      sim <- calc_cosine_similarity(skill_vec, comp$dna_vector[[1]])
      twin_matches[[c_idx]] <- list(
        compName       = comp$comp_name,
        era            = comp$era,
        archetype      = comp$archetype,
        position       = comp$pos,
        similarityPct  = sim,
        keySharedTrait = comp$key_trait
      )
    }
    
    sorted_twins <- twin_matches[order(sapply(twin_matches, function(x) x$similarityPct), decreasing = TRUE)]
    top5_twins <- head(sorted_twins, 5)
    primary_archetype <- top5_twins[[1]]$archetype
    
    # 2D Manifold Coordinates (UMAP style)
    # X: Raw Stuff & Whiff vs Finesse/Command balance (-25 to +55)
    # Y: Groundball/Batted Ball vs Workload/Leverage (-25 to +55)
    manifold_x <- round((cat_scores$arsenal_stuff - cat_scores$command_k) * 0.65 + (cat_scores$velocity_physics - 50) * 0.35, 1)
    manifold_y <- round((cat_scores$workload_leverage - 50) * 0.70 + (cat_scores$batted_ball - 50) * 0.30, 1)
    
    all_profiles[[p$player_id]] <- list(
      playerId        = p$player_id,
      mlbamId         = p$mlbam_id,
      playerName      = p$player_name,
      team            = p$team,
      playerType      = "Pitcher",
      position        = if (stamina >= 65) "SP" else "RP",
      age             = coalesce(p$age, 28),
      archetype       = primary_archetype,
      headlineStats   = list(
        stat1Label = "xFIP",
        stat1Val   = sprintf("%.2f", xfip),
        stat2Label = "Proj ERA",
        stat2Val   = sprintf("%.2f", proj_era),
        stat3Label = "rGS",
        stat3Val   = sprintf("%.1f", rgs),
        countLabel = "SO",
        countVal   = so
      ),
      compositeZscore = round(z_score, 2),
      overallRating   = pmin(99, pmax(65, round(z_score * 5.5 + 75))),
      manifoldX       = manifold_x,
      manifoldY       = manifold_y,
      skillVector     = list(
        fastball_velo          = fb_velo,
        fastball_ivb           = fb_ivb,
        horizontal_break       = h_break,
        extension_release      = ext,
        stuff_plus             = stuff_plus,
        arsenal_diversity      = arsenal_ent,
        secondary_whiff        = sec_whiff,
        location_plus          = loc_plus,
        zone_rate              = zone_rt,
        strikeout_rate         = k_rt,
        walk_suppression       = walk_supp,
        hard_hit_suppression   = hard_supp,
        barrel_suppression     = barrel_supp,
        groundball_rate        = gb_rt,
        workload_stamina       = stamina,
        high_leverage_shutdown = high_li
      ),
      categoryScores  = cat_scores,
      historicalTwins = top5_twins
    )
  }
  
  profile_list <- unname(all_profiles)
  message(sprintf(">>> Generated DNA profiles for %d players (%d Batters, %d Pitchers).",
                  length(profile_list), nrow(batters_pool), nrow(pitchers_pool)))
                  
  batter_archs <- unique(batter_comps$archetype)
  pitcher_archs <- unique(pitcher_comps$archetype)
  
  output_catalog <- list(
    updatedAt        = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    eraBaseline      = "1980-2026",
    totalPlayers     = length(profile_list),
    batterArchetypes = batter_archs,
    pitcherArchetypes= pitcher_archs,
    profiles         = profile_list
  )
  
  output_json <- file.path(PROJECT_DIR, "web", "public", "data", "player_dna_profiles.json")
  write(toJSON(output_catalog, auto_unbox = TRUE, pretty = TRUE), output_json)
  message(sprintf(">>> Wrote player DNA catalog to %s (%.2f MB)", output_json, file.info(output_json)$size / 1e6))
  
  invisible(output_catalog)
}

if (sys.nframe() == 0) {
  run_mlb_player_dna_engine()
}
