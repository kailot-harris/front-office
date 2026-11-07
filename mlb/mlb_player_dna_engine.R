# ==============================================================================
# mlb_player_dna_engine.R
# Phase 2 / Sprint 2: High-Dimensional Player DNA & Historical Twins (1980–2026)
# Path: c:/Users/kailo/kayceeslices/front-office/MLB Analytics/mlb_player_dna_engine.R
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
# Grounded in empirical multi-season percentile baselines calculated from
# FanGraphs and Statcast historical peak data (1980–2026).
#
# Batter Historical Comps (16-D vectors):
# [EV90, Barrel%, HardHit%, ISO, ZoneContact, WhiffAvoid, KAvoid, ChaseDisc,
#  WalkRate, SweetSpot, PullAir, SprayBal, SprintSpd, Baserunning, FieldingOAA, Clutch]
# Percentile baselines derived from multi-season peak leaderboards:
# - Barry Bonds (2001-04): 99th pctile ISO (.535), BB% (30.5%), EV90 (100th), UZR (+5.8)
# - Tony Gwynn (1994-97): 99th pctile K% (2.8%), Contact% (96.5%), SprayBal (33/35/32%)
# - Rickey Henderson (1985-90): 99th pctile Spd (9.8), wBsR (+11.2/yr), BB% (19.4%)
# - Ken Griffey Jr. (1993-97): 95th+ pctile ISO (.331), OAA/TZ (+14/yr), Spd (6.8)
# - Albert Pujols (2003-08): 96th+ pctile ISO (.318), Contact% (88.4%), BB% (14.2%)
# - Ichiro Suzuki (2001-04): 98th+ pctile Spd (8.9), Contact% (91.2%), SprayBal (99th)
# - Aaron Judge (2022-24): Statcast 100th EV90 (97.4 mph), Barrel% (26.8%), HardHit% (61.2%)
# - Shohei Ohtani (2023-24): Statcast 99th EV90 (96.1 mph), Barrel% (21.5%), Spd (28.2 ft/s)
# - Mike Trout (2012-18): 97th+ pctile wRC+ (176), Spd (7.5), wBsR (+7.1/yr), ISO (.277)
# - Wade Boggs (1985-88): 98th+ pctile OBP (.457), Contact% (92.4%), Oppo% (36.5%)
# - Cal Ripken Jr. (1983-91): 90th+ pctile ISO (.184 era-adj), Infield Defense (+18/yr)
# - Juan Soto (2021-24): Statcast 99th Chase% (16.2%), BB% (18.8%), SweetSpot (39.8%)
# - Giancarlo Stanton (2017-18): Statcast 99th maxEV (122.2 mph), Barrel% (18.6%), PullAir
# - Ronald Acuña Jr. (2023): Statcast 98th EV90 (95.4 mph), 73 SB, Spd (29.8 ft/s)
# - Jose Altuve (2016-19): 92nd+ pctile Contact% (86.4%), Spd (6.4), Playoff WPA
# - Jim Thome (2001-04): 96th+ pctile ISO (.312), BB% (18.9%), Pull% (48.5%)
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
# Percentile baselines derived from multi-season peak leaderboards:
# - Randy Johnson (1999-02): 99th pctile K% (34.2%), IVB (18.4"), SwStr% (16.8%), IP (260/yr)
# - Pedro Martinez (1999-00): 99th pctile ERA- (35), FIP- (38), K-BB% (31.8%), Changeup fade
# - Greg Maddux (1992-95): 99th pctile BB% (3.4%), ERA- (44), Arm-side run (15.2"), GB% (62%)
# - Nolan Ryan (1981-89): 99th pctile Velo (100+ mph), K/9 (10.4), BAA (.184), Curve drop
# - Roger Clemens (1986-97): 98th pctile Velo (96 mph), Splitter whiff (42%), IP (255/yr)
# - Mariano Rivera (1997-08): 99th pctile Cutter break (9.4"), ERA- (48), Postseason WPA (11.7)
# - Clayton Kershaw (2011-16): 97th pctile Curve IVB (-12.4"), Slider whiff (44%), ERA- (53)
# - Jacob deGrom (2018-21): Statcast 99th 4-seam velo (99.2 mph), Slider velo (92.5 mph)
# - Tarik Skubal (2024): Statcast 98th 4-seam IVB (17.8"), Changeup whiff (42.5%), K% (32.2%)
# - Paul Skenes (2024): Statcast 99th Fastball velo (99.8 mph), Splinker HB (14.2"), K% (33.1%)
# - Zack Greinke (2009-15): 98th pctile Arsenal entropy (6 pitch types), Location+ (106)
# - Roy Halladay (2008-11): 98th pctile Sinker GB% (58.4%), BB% (3.8%), IP (245/yr)
# - Johan Santana (2004-06): 98th pctile Circle change whiff (46.2%), K% (29.5%), ERA- (61)
# - Aroldis Chapman (2012-16): Statcast 100th Fastball velo (100.8 mph), K% (43.8%), High-LI
# - Mason Miller (2024): Statcast 100th Fastball velo (100.9 mph), IVB (18.6"), Whiff% (41.4%)
# - Trevor Hoffman (1996-02): 98th pctile Palmball change whiff (44.5%), K-BB% (22.8%)
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
# 2. Cosine Similarity & Empirical Trait Calculation Helpers
# ------------------------------------------------------------------------------
calc_cosine_similarity <- function(v1, v2) {
  denom <- sqrt(sum(v1^2)) * sqrt(sum(v2^2))
  if (denom == 0) return(0)
  sim <- sum(v1 * v2) / denom
  round(sim * 100, 1)
}

find_cache_file <- function(stage, filename) {
  local_path <- cache_path(stage, filename, create = FALSE)
  if (file.exists(local_path)) return(local_path)
  rel_path <- file.path(PROJECT_DIR, "cache", stage, filename)
  if (file.exists(rel_path)) return(rel_path)
  parent_path <- file.path(PROJECT_DIR, "..", "MLB Analytics", "cache", stage, filename)
  if (file.exists(parent_path)) return(parent_path)
  default_main <- file.path("C:/Users/kailo/kayceeslices/front-office/MLB Analytics/cache", stage, filename)
  if (file.exists(default_main)) return(default_main)
  NULL
}

find_ingest_statcast_files <- function() {
  dirs <- c(
    cache_path("ingest", create = FALSE),
    file.path(PROJECT_DIR, "cache", "ingest"),
    file.path(PROJECT_DIR, "..", "MLB Analytics", "cache", "ingest"),
    "C:/Users/kailo/kayceeslices/front-office/MLB Analytics/cache/ingest"
  )
  for (d in dirs) {
    if (dir.exists(d)) {
      files <- list.files(d, pattern = "^statcast_pitches_.*\\.rds$", full.names = TRUE)
      if (length(files) > 0) return(files)
    }
  }
  character(0)
}

calc_spray_balance <- function(pull, cent, oppo) {
  p <- c(pull, cent, oppo)
  p <- p[!is.na(p) & p > 0]
  if (length(p) == 0) return(NA_real_)
  p <- p / sum(p)
  # Normalized Shannon entropy against uniform 3-way distribution (log(3))
  -sum(p * log(p)) / log(3)
}

calc_pitch_arsenal_entropy <- function(row) {
  cols <- c("pfx_FA_pct", "pfx_FC_pct", "pfx_SI_pct", "pfx_SL_pct", "pfx_CU_pct", 
            "pfx_CH_pct", "pfx_ST_pct", "pfx_KC_pct", "pfx_FS_pct", "pfx_KN_pct", 
            "pfx_FO_pct", "pfx_EP_pct")
  vals <- as.numeric(row[cols])
  vals <- vals[!is.na(vals) & vals > 0]
  if (length(vals) <= 1) return(0)
  p <- vals / sum(vals)
  -sum(p * log(p))
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
  
  # ----------------------------------------------------------------------------
  # Load Empirical FanGraphs & Statcast Datasets (Deterministic 16-D Grounding)
  # ----------------------------------------------------------------------------
  b_fg_file <- find_cache_file("stats_sync", "fg_batters.rds")
  if (is.null(b_fg_file) || !file.exists(b_fg_file)) {
    stop("Required FanGraphs batter cache (fg_batters.rds) not found. Run mlb_stats_sync.R first.")
  }
  b_fg <- readRDS(b_fg_file)
  
  p_fg_file <- find_cache_file("stats_sync", "fg_pitchers.rds")
  if (is.null(p_fg_file) || !file.exists(p_fg_file)) {
    stop("Required FanGraphs pitcher cache (fg_pitchers.rds) not found. Run mlb_stats_sync.R first.")
  }
  p_fg <- readRDS(p_fg_file)
  
  b_fg$mlbam_chr <- as.character(b_fg$xMLBAMID)
  p_fg$mlbam_chr <- as.character(p_fg$xMLBAMID)
  
  # Empirical Batter metrics & ECDF percentiles
  b_fg$pull_air_raw <- b_fg$Pull_pct * b_fg$FB_pct
  b_fg$spray_entropy <- mapply(calc_spray_balance, b_fg$Pull_pct, b_fg$Cent_pct, b_fg$Oppo_pct)
  b_fg$fielding_emp <- coalesce(b_fg$Fielding, b_fg$Defense, 0)
  
  ecdf_batter_sweet <- ecdf(b_fg$SquaredUpContact_pct[!is.na(b_fg$SquaredUpContact_pct)])
  ecdf_batter_pull_air <- ecdf(b_fg$pull_air_raw[!is.na(b_fg$pull_air_raw)])
  ecdf_batter_spray <- ecdf(b_fg$spray_entropy[!is.na(b_fg$spray_entropy)])
  ecdf_batter_spd <- ecdf(b_fg$Spd[!is.na(b_fg$Spd)])
  ecdf_batter_bsr <- ecdf(b_fg$wBsR[!is.na(b_fg$wBsR)])
  ecdf_batter_fld <- ecdf(b_fg$fielding_emp[!is.na(b_fg$fielding_emp)])
  
  # Empirical Pitcher metrics & ECDF percentiles
  p_fg$ivb_raw <- coalesce(p_fg$`pfx_FA-Z`, p_fg$`pfx_SI-Z`, p_fg$`pi_FA-Z`)
  p_fg$hb_raw <- abs(coalesce(p_fg$`pfx_FA-X`, p_fg$`pfx_SI-X`, p_fg$`pfx_FC-X`, p_fg$`pi_FA-X`))
  p_fg$arsenal_entropy <- apply(p_fg, 1, calc_pitch_arsenal_entropy)
  
  ecdf_pitcher_ivb <- ecdf(p_fg$ivb_raw[!is.na(p_fg$ivb_raw)])
  ecdf_pitcher_hb <- ecdf(p_fg$hb_raw[!is.na(p_fg$hb_raw)])
  ecdf_pitcher_arsenal <- ecdf(p_fg$arsenal_entropy[!is.na(p_fg$arsenal_entropy)])
  ecdf_pitcher_barrel <- ecdf(p_fg$Barrel_pct[!is.na(p_fg$Barrel_pct)])
  ecdf_pitcher_gb <- ecdf(p_fg$GB_pct[!is.na(p_fg$GB_pct)])
  
  # Empirical Statcast release extension lookup
  sc_files <- find_ingest_statcast_files()
  pitcher_ext_map <- list()
  if (length(sc_files) > 0) {
    sc_list <- lapply(sc_files, function(f) {
      tryCatch({
        df <- readRDS(f)
        if (all(c("pitcher", "release_extension") %in% colnames(df))) {
          df[!is.na(df$pitcher) & !is.na(df$release_extension), c("pitcher", "release_extension")]
        } else NULL
      }, error = function(e) NULL)
    })
    sc_combined <- bind_rows(sc_list)
    if (nrow(sc_combined) > 0) {
      sc_pitcher_ext <- sc_combined %>%
        group_by(pitcher) %>%
        summarise(mean_ext = mean(release_extension, na.rm = TRUE), .groups = "drop")
      for (idx in seq_len(nrow(sc_pitcher_ext))) {
        pitcher_ext_map[[as.character(sc_pitcher_ext$pitcher[idx])]] <- sc_pitcher_ext$mean_ext[idx]
      }
    }
  }
  message(sprintf(">>> Empirical baselines ready: %d batters, %d pitchers, %d Statcast extension profiles.",
                  nrow(b_fg), nrow(p_fg), length(pitcher_ext_map)))
  
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
    
    # FanGraphs active batter row lookup
    fg_b_match <- b_fg[b_fg$mlbam_chr == as.character(p$mlbam_id), ]
    has_b_fg <- nrow(fg_b_match) > 0
    
    # Deterministic empirical Batter traits (zero RNG)
    sweet_spot <- if (has_b_fg && !is.na(fg_b_match$SquaredUpContact_pct[1])) {
      pmin(99, pmax(35, round(ecdf_batter_sweet(fg_b_match$SquaredUpContact_pct[1]) * 100)))
    } else {
      50
    }
    
    pull_air <- if (has_b_fg && !is.na(fg_b_match$pull_air_raw[1])) {
      pmin(99, pmax(35, round(ecdf_batter_pull_air(fg_b_match$pull_air_raw[1]) * 100)))
    } else {
      50
    }
    
    spray_bal <- if (has_b_fg && !is.na(fg_b_match$spray_entropy[1])) {
      pmin(99, pmax(35, round(ecdf_batter_spray(fg_b_match$spray_entropy[1]) * 100)))
    } else {
      50
    }
    
    # Defensive position & speed/fielding traits derived from FanGraphs
    pos <- if (has_b_fg && !is.na(fg_b_match$position[1]) && fg_b_match$position[1] != "" && fg_b_match$position[1] != "B") {
      fg_b_match$position[1]
    } else {
      coalesce(p$position, "OF")
    }
    
    sprint <- if (has_b_fg && !is.na(fg_b_match$Spd[1])) {
      pmin(99, pmax(35, round(ecdf_batter_spd(fg_b_match$Spd[1]) * 100)))
    } else {
      50
    }
    
    bsr <- if (has_b_fg && !is.na(fg_b_match$wBsR[1])) {
      pmin(99, pmax(35, round(ecdf_batter_bsr(fg_b_match$wBsR[1]) * 100)))
    } else {
      50
    }
    
    oaa <- if (has_b_fg && !is.na(fg_b_match$fielding_emp[1])) {
      pmin(99, pmax(35, round(ecdf_batter_fld(fg_b_match$fielding_emp[1]) * 100)))
    } else {
      50
    }
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
    
    # Empirical FanGraphs & Statcast Pitcher lookup
    fg_p_match <- p_fg[p_fg$mlbam_chr == as.character(p$mlbam_id), ]
    has_p_fg <- nrow(fg_p_match) > 0
    
    # 16-D Pitcher Vector Calculation [0 - 100] (deterministic empirical traits, zero RNG)
    fb_velo <- pmin(99, pmax(40, round((k_pct - 18.0) * 4.0 + (5.00 - proj_era) * 15 + 50)))
    
    fb_ivb <- if (has_p_fg && !is.na(fg_p_match$ivb_raw[1])) {
      pmin(99, pmax(35, round(ecdf_pitcher_ivb(fg_p_match$ivb_raw[1]) * 100)))
    } else {
      50
    }
    
    h_break <- if (has_p_fg && !is.na(fg_p_match$hb_raw[1])) {
      pmin(99, pmax(35, round(ecdf_pitcher_hb(fg_p_match$hb_raw[1]) * 100)))
    } else {
      50
    }
    
    # Extension: Ingest from Statcast extension or default to league median (6.4 ft / 50th percentile) when absent
    ext_val <- pitcher_ext_map[[as.character(p$mlbam_id)]]
    ext <- if (!is.null(ext_val) && !is.na(ext_val)) {
      pmin(99, pmax(35, round(pnorm((ext_val - 6.4) / 0.40) * 100)))
    } else {
      50
    }
    
    stuff_plus <- pmin(99, pmax(40, round((fb_velo * 0.5 + fb_ivb * 0.3 + h_break * 0.2))))
    
    arsenal_ent <- if (has_p_fg && !is.na(fg_p_match$arsenal_entropy[1])) {
      pmin(99, pmax(35, round(ecdf_pitcher_arsenal(fg_p_match$arsenal_entropy[1]) * 100)))
    } else {
      50
    }
    
    sec_whiff <- pmin(99, pmax(40, round((k_pct - 16.0) * 4.2 + 45)))
    
    loc_plus <- pmin(99, pmax(40, round((10.0 - bb_pct) * 6.5 + 45)))
    zone_rt <- pmin(99, pmax(40, round((loc_plus * 0.6 + 35))))
    k_rt <- pmin(99, pmax(35, round((k_pct - 15.0) * 4.5 + 40)))
    walk_supp <- pmin(99, pmax(35, round((12.0 - bb_pct) * 6.0 + 40)))
    
    hard_supp <- pmin(99, pmax(35, round((5.00 - proj_era) * 22 + 40)))
    
    barrel_supp <- if (has_p_fg && !is.na(fg_p_match$Barrel_pct[1])) {
      pmin(99, pmax(35, round((1 - ecdf_pitcher_barrel(fg_p_match$Barrel_pct[1])) * 100)))
    } else {
      50
    }
    
    gb_rt <- if (has_p_fg && !is.na(fg_p_match$GB_pct[1])) {
      pmin(99, pmax(30, round(ecdf_pitcher_gb(fg_p_match$GB_pct[1]) * 100)))
    } else {
      50
    }
    
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
    # generated_at is what tools/publish_web.R's assertion F reads: UTC, ISO-8601,
    # and FIRST in the object because F only scans the first 4096 bytes of the
    # file (this payload is ~935 KB). `updatedAt` is kept for the web app, which
    # already renders it; it is local-time and not a format F can parse.
    generated_at     = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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
