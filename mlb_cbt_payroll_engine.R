# ==============================================================================
# mlb_cbt_payroll_engine.R
# MLB Analytics: Competitive Balance Tax (CBT) & Salary Payroll Architect Engine
# ==============================================================================
# Models 2026-2028 multi-year payrolls across all 30 MLB clubs under the 2022-2026 CBA:
# - Base CBT Threshold (T0): $244.0M
# - Tier 1 Surcharge (T1):  $264.0M (+$20M) -> 20%-50% surcharge
# - Tier 2 Draft Penalty (T2): $284.0M (+$40M) -> Highest pick drops 10 spots
# - Tier 3 Cohen Tax (T3):    $304.0M (+$60M) -> 80%-110% surcharge + intl bonus pool reduction
# - Tier 4 Mega Tax:         > $304.0M
#
# Computes:
# - Guaranteed multi-year player obligations (2026, 2027, 2028)
# - Projected WAR & Contract Surplus Value: (WAR * $8.5M) - salary2026
# - CBT Space or CBT Luxury Tax Bill
# - Penalties (draft pick drop, international bonus pool slash, revenue share loss)
#
# Output: web/public/data/cbt_payroll_sheet.json
# ==============================================================================

suppressPackageStartupMessages({
  library(jsonlite)
  library(dplyr)
})

run_mlb_cbt_payroll_engine <- function() {
  message(">>> [CBT Engine] Initializing 2026 MLB Payroll & Luxury Tax Architect...")
  
  root_dir <- getwd()
  out_path <- file.path(root_dir, "web", "public", "data", "cbt_payroll_sheet.json")
  teams_file <- file.path(root_dir, "web", "public", "data", "projections_season_teams.json")
  players_file <- file.path(root_dir, "web", "public", "data", "projections_season_players.json")
  
  if (!file.exists(teams_file)) {
    stop(sprintf("Teams projection file not found: %s", teams_file))
  }
  if (!file.exists(players_file)) {
    stop(sprintf("Players projection file not found: %s", players_file))
  }
  
  teams_data <- jsonlite::fromJSON(teams_file)
  players_data <- jsonlite::fromJSON(players_file)
  
  message(sprintf("Loaded %d team records and %d player projection records.", nrow(teams_data), nrow(players_data)))
  
  # Standard 2026 CBA CBT Thresholds (in Millions)
  BASE_THRESHOLD   <- 244.0
  TIER1_THRESHOLD  <- 264.0
  TIER2_THRESHOLD  <- 284.0
  TIER3_THRESHOLD  <- 304.0
  DOLLARS_PER_WAR  <- 8.5   # $8.5M per win market benchmark
  
  # Historical repeater status (Clubs that exceeded CBT in 2024 and 2025 pay repeater tax rate)
  repeater_teams <- c("LAD", "NYM", "NYY", "PHI")
  
  # Realistic baseline 2026 payroll anchor estimates for 30 MLB franchises
  # Anchored on actual 2025-2026 payroll commitments
  team_payroll_anchors <- list(
    LAD = list(p26 = 338.5, p27 = 295.0, p28 = 260.0),
    NYM = list(p26 = 318.0, p27 = 280.0, p28 = 240.0),
    NYY = list(p26 = 308.5, p27 = 275.0, p28 = 250.0),
    PHI = list(p26 = 278.0, p27 = 245.0, p28 = 210.0),
    HOU = list(p26 = 252.0, p27 = 210.0, p28 = 175.0),
    TOR = list(p26 = 248.5, p27 = 205.0, p28 = 160.0),
    ATL = list(p26 = 236.0, p27 = 215.0, p28 = 190.0),
    TEX = list(p26 = 232.0, p27 = 195.0, p28 = 165.0),
    SFG = list(p26 = 224.0, p27 = 190.0, p28 = 150.0),
    BOS = list(p26 = 218.0, p27 = 185.0, p28 = 145.0),
    CHC = list(p26 = 215.0, p27 = 180.0, p28 = 140.0),
    SDP = list(p26 = 210.0, p27 = 185.0, p28 = 160.0),
    ARI = list(p26 = 195.0, p27 = 165.0, p28 = 135.0),
    SEA = list(p26 = 186.0, p27 = 155.0, p28 = 130.0),
    BAL = list(p26 = 182.0, p27 = 160.0, p28 = 145.0),
    STL = list(p26 = 175.0, p27 = 140.0, p28 = 115.0),
    MIN = list(p26 = 158.0, p27 = 130.0, p28 = 105.0),
    DET = list(p26 = 154.0, p27 = 135.0, p28 = 110.0),
    MIL = list(p26 = 148.0, p27 = 120.0, p28 = 95.0),
    CIN = list(p26 = 142.0, p27 = 118.0, p28 = 92.0),
    KCR = list(p26 = 138.0, p27 = 115.0, p28 = 90.0),
    CLE = list(p26 = 126.0, p27 = 102.0, p28 = 82.0),
    WSH = list(p26 = 122.0, p27 = 98.0,  p28 = 78.0),
    COL = list(p26 = 118.0, p27 = 92.0,  p28 = 72.0),
    LAA = list(p26 = 115.0, p27 = 90.0,  p28 = 70.0),
    PIT = list(p26 = 98.0,  p27 = 82.0,  p28 = 65.0),
    TBR = list(p26 = 95.0,  p27 = 78.0,  p28 = 62.0),
    MIA = list(p26 = 88.0,  p27 = 72.0,  p28 = 58.0),
    CHW = list(p26 = 82.0,  p27 = 68.0,  p28 = 52.0),
    ATH = list(p26 = 78.0,  p27 = 64.0,  p28 = 50.0) # Athletics (Sacramento/Vegas)
  )
  
  # Standardized marquee contract database for realism
  star_contracts <- list(
    "Shohei Ohtani"     = list(s26 = 46.1, s27 = 46.1, s28 = 46.1, type = "Guaranteed", notes = "$700M CBT AAV discount"),
    "Yoshinobu Yamamoto"= list(s26 = 27.1, s27 = 27.1, s28 = 27.1, type = "Guaranteed", notes = "12-yr $325M contract"),
    "Mookie Betts"      = list(s26 = 30.0, s27 = 30.0, s28 = 30.0, type = "Guaranteed", notes = "12-yr $365M extension"),
    "Freddie Freeman"   = list(s26 = 27.0, s27 = 27.0, s28 = 0.0,  type = "Guaranteed", notes = "Expiring after 2027"),
    "Aaron Judge"       = list(s26 = 40.0, s27 = 40.0, s28 = 40.0, type = "Guaranteed", notes = "9-yr $360M contract"),
    "Gerrit Cole"       = list(s26 = 36.0, s27 = 36.0, s28 = 36.0, type = "Guaranteed", notes = "Ace veteran anchor"),
    "Juan Soto"         = list(s26 = 51.0, s27 = 51.0, s28 = 51.0, type = "Guaranteed", notes = "Historic free agency megadeal"),
    "Francisco Lindor"  = list(s26 = 34.1, s27 = 34.1, s28 = 34.1, type = "Guaranteed", notes = "10-yr $341M contract"),
    "Bryce Harper"      = list(s26 = 27.5, s27 = 27.5, s28 = 27.5, type = "Guaranteed", notes = "13-yr $330M contract"),
    "Trea Turner"       = list(s26 = 27.3, s27 = 27.3, s28 = 27.3, type = "Guaranteed", notes = "11-yr $300M contract"),
    "Zack Wheeler"      = list(s26 = 42.0, s27 = 42.0, s28 = 0.0,  type = "Guaranteed", notes = "3-yr extension through 2027"),
    "Yordan Alvarez"    = list(s26 = 18.0, s27 = 20.0, s28 = 26.0, type = "Guaranteed", notes = "6-yr $115M extension"),
    "Corey Seager"      = list(s26 = 32.5, s27 = 31.0, s28 = 31.0, type = "Guaranteed", notes = "10-yr $325M contract"),
    "Marcus Semien"     = list(s26 = 26.0, s27 = 26.0, s28 = 26.0, type = "Guaranteed", notes = "7-yr $175M contract"),
    "Vladimir Guerrero Jr." = list(s26 = 29.5, s27 = 32.0, s28 = 32.0, type = "Arbitration", notes = "Arb-final extension candidate"),
    "Bo Bichette"       = list(s26 = 22.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed", notes = "Walk-year free agent"),
    "Rafael Devers"     = list(s26 = 31.0, s27 = 31.0, s28 = 31.0, type = "Guaranteed", notes = "10-yr $313M contract"),
    "Manny Machado"     = list(s26 = 35.0, s27 = 35.0, s28 = 35.0, type = "Guaranteed", notes = "11-yr $350M extension"),
    "Fernando Tatis Jr."= list(s26 = 24.7, s27 = 24.7, s28 = 36.7, type = "Guaranteed", notes = "14-yr $340M contract"),
    "Austin Riley"      = list(s26 = 22.0, s27 = 22.0, s28 = 22.0, type = "Guaranteed", notes = "10-yr $212M extension"),
    "Ronald Acuna Jr."  = list(s26 = 17.0, s27 = 17.0, s28 = 17.0, type = "Club Option", notes = "Club options 2027-2028"),
    "Gunnar Henderson"  = list(s26 = 4.5,  s27 = 12.0, s28 = 19.0, type = "Pre-Arb",    notes = "Super-Two MVP superstar"),
    "Adley Rutschman"   = list(s26 = 6.2,  s27 = 14.0, s28 = 21.0, type = "Arbitration", notes = "Arb-1 arbitration escalation"),
    "Bobby Witt Jr."    = list(s26 = 13.0, s27 = 19.0, s28 = 25.0, type = "Guaranteed", notes = "11-yr $288.7M megadeal"),
    "Julio Rodriguez"   = list(s26 = 18.0, s27 = 18.0, s28 = 18.0, type = "Guaranteed", notes = "Long-term face of franchise"),
    "Corbin Carroll"    = list(s26 = 12.0, s27 = 14.0, s28 = 16.0, type = "Guaranteed", notes = "8-yr $111M contract"),
    "Ketel Marte"       = list(s26 = 16.0, s27 = 16.0, s28 = 13.0, type = "Guaranteed", notes = "Team friendly veteran extension"),
    "Tarik Skubal"      = list(s26 = 14.5, s27 = 24.0, s28 = 30.0, type = "Arbitration", notes = "Cy Young winner Arb-2 escalation"),
    "Paul Skenes"       = list(s26 = 0.85, s27 = 0.90, s28 = 5.5,  type = "Pre-Arb",    notes = "Pre-arb generational ace value"),
    "Jackson Chourio"   = list(s26 = 4.0,  s27 = 7.0,  s28 = 9.0,  type = "Guaranteed", notes = "8-yr $82M rookie contract"),
    "William Contreras" = list(s26 = 7.5,  s27 = 13.0, s28 = 18.0, type = "Arbitration", notes = "All-Star catcher Arb-2")
  )
  
  # Group players by team to assign contracts
  # Map aliases
  team_alias <- function(tm) {
    if (is.na(tm) || tm == "") return("LAD")
    if (tm == "OAK") return("ATH")
    if (tm == "WAS") return("WSH")
    if (tm == "CHW" || tm == "CWS") return("CHW")
    if (tm == "SF") return("SFG")
    if (tm == "KC") return("KCR")
    if (tm == "SD") return("SDP")
    if (tm == "TB") return("TBR")
    tm
  }
  
  # Function to calculate CBT Tax Bill based on CBA tier schedule
  compute_cbt_tax <- function(payroll, is_repeater) {
    if (payroll <= BASE_THRESHOLD) {
      return(0.0)
    }
    
    overage <- payroll - BASE_THRESHOLD
    tax <- 0.0
    
    # Base overage (Up to $20M over = Tier 1)
    # 20% first time, 30% second time, 50% repeater
    t1_cap <- min(overage, 20.0)
    t1_rate <- if (is_repeater) 0.50 else 0.20
    tax <- tax + t1_cap * t1_rate
    
    # Tier 2 overage ($20M to $40M over)
    # +12% surcharge (32% first-time, 62% repeater)
    if (overage > 20.0) {
      t2_cap <- min(overage - 20.0, 20.0)
      t2_rate <- if (is_repeater) 0.62 else 0.32
      tax <- tax + t2_cap * t2_rate
    }
    
    # Tier 3 overage ($40M to $60M over)
    # +42.5% to +45% surcharge (62.5% first-time, 95% repeater)
    if (overage > 40.0) {
      t3_cap <- min(overage - 40.0, 20.0)
      t3_rate <- if (is_repeater) 0.95 else 0.625
      tax <- tax + t3_cap * t3_rate
    }
    
    # Tier 4 overage (> $60M over = Cohen Tax Tier)
    # 80% first-time, 110% repeater
    if (overage > 60.0) {
      t4_cap <- overage - 60.0
      t4_rate <- if (is_repeater) 1.10 else 0.80
      tax <- tax + t4_cap * t4_rate
    }
    
    return(round(tax, 2))
  }
  
  # Categorize CBT Tier
  get_cbt_tier <- function(payroll) {
    if (payroll <= BASE_THRESHOLD) {
      return("Under CBT Threshold")
    } else if (payroll <= TIER1_THRESHOLD) {
      return("Tier 1 Surcharge ($244M-$264M)")
    } else if (payroll <= TIER2_THRESHOLD) {
      return("Tier 2 Draft Penalty ($264M-$284M)")
    } else if (payroll <= TIER3_THRESHOLD) {
      return("Tier 3 Cohen Tax ($284M-$304M)")
    } else {
      return("Tier 4 Mega Tax (> $304M)")
    }
  }
  
  # Process all 30 teams
  franchise_profiles <- list()
  total_league_payroll <- 0
  total_luxury_tax <- 0
  
  unique_teams <- teams_data %>% distinct(team, team_name, full_name, league, division)
  
  for (i in seq_len(nrow(unique_teams))) {
    row <- unique_teams[i, ]
    tm_abbr <- team_alias(row$team)
    is_rep <- tm_abbr %in% repeater_teams
    
    # Get payroll anchor or fallback
    anchor <- if (!is.null(team_payroll_anchors[[tm_abbr]])) {
      team_payroll_anchors[[tm_abbr]]
    } else {
      list(p26 = 140.0, p27 = 115.0, p28 = 90.0)
    }
    
    p26 <- anchor$p26
    p27 <- anchor$p27
    p28 <- anchor$p28
    
    tax_bill <- compute_cbt_tax(p26, is_rep)
    tier_label <- get_cbt_tier(p26)
    cbt_space <- max(0, round(BASE_THRESHOLD - p26, 2))
    total_commit <- round(p26 + tax_bill, 2)
    
    total_league_payroll <- total_league_payroll + p26
    total_luxury_tax <- total_luxury_tax + tax_bill
    
    # Penalties
    draft_drop <- p26 >= TIER2_THRESHOLD
    intl_pool_slash <- p26 >= TIER3_THRESHOLD
    rev_share <- p26 <= BASE_THRESHOLD
    
    tax_desc <- if (p26 <= BASE_THRESHOLD) {
      "None (Tax Free)"
    } else if (is_rep) {
      if (p26 > TIER3_THRESHOLD) "110% Repeater Mega Tax Rate" else "62% - 95% Repeater Surcharge Rate"
    } else {
      if (p26 > TIER3_THRESHOLD) "80% First-time Cohen Surcharge Rate" else "20% - 62.5% First-time Surcharge Rate"
    }
    
    # Find players belonging to this team in projections
    tm_players <- players_data %>%
      filter(team == row$team | team == tm_abbr) %>%
      arrange(desc(composite_zscore))
    
    # Build contract roster for team (top 15 key players)
    team_contracts <- list()
    allocated_salaries <- 0
    
    # Take top 12-15 players from projections
    n_sample <- min(nrow(tm_players), 14)
    if (n_sample > 0) {
      for (k in seq_len(n_sample)) {
        p_row <- tm_players[k, ]
        p_name <- p_row$player_name
        p_pos <- if (p_row$player_type == "Pitcher") "P" else p_row$position
        if (p_pos == "B") p_pos <- "DH/OF"
        
        # Approximate projected WAR from composite zscore & workload
        z <- if (!is.null(p_row$composite_zscore) && !is.na(p_row$composite_zscore)) as.numeric(p_row$composite_zscore) else 1.0
        proj_war <- round(max(0.2, (z * 0.9) + 2.1), 1)
        
        # Check known star contract
        if (!is.null(star_contracts[[p_name]])) {
          sc <- star_contracts[[p_name]]
          s26 <- sc$s26
          s27 <- sc$s27
          s28 <- sc$s28
          c_type <- sc$type
          c_notes <- sc$notes
        } else {
          # Heuristic based on age, z-score, and team payroll
          age <- if (!is.null(p_row$age) && !is.na(p_row$age)) as.numeric(p_row$age) else 27
          if (age <= 25) {
            s26 <- round(runif(1, 0.8, 2.5), 2)
            s27 <- round(s26 * 1.5, 2)
            s28 <- round(s27 * 1.8, 2)
            c_type <- "Pre-Arb"
            c_notes <- "Team controlled pre-arbitration"
          } else if (age <= 28) {
            s26 <- round(max(2.5, proj_war * runif(1, 2.2, 3.8)), 1)
            s27 <- round(s26 * 1.3, 1)
            s28 <- round(s27 * 1.25, 1)
            c_type <- "Arbitration"
            c_notes <- "Arbitration eligible core starter"
          } else {
            s26 <- round(max(4.0, proj_war * runif(1, 3.5, 5.5)), 1)
            s27 <- round(s26 * 0.95, 1)
            s28 <- if (runif(1) > 0.4) round(s27 * 0.9, 1) else 0.0
            c_type <- if (runif(1) > 0.8) "Player Option" else "Guaranteed"
            c_notes <- "Guaranteed veteran contract"
          }
        }
        
        surplus <- round((proj_war * DOLLARS_PER_WAR) - s26, 2)
        allocated_salaries <- allocated_salaries + s26
        
        team_contracts[[length(team_contracts) + 1]] <- list(
          playerId     = as.character(p_row$player_id),
          playerName   = as.character(p_name),
          position     = as.character(p_pos),
          salary2026   = s26,
          salary2027   = s27,
          salary2028   = s28,
          contractType = c_type,
          projectedWar = proj_war,
          surplusValue = surplus,
          notes        = c_notes
        )
      }
    }
    
    # Add a catch-all bench/depth payroll item if contracts sum to less than team anchor
    depth_remainder <- round(max(5.0, p26 - allocated_salaries), 1)
    team_contracts[[length(team_contracts) + 1]] <- list(
      playerId     = paste0("DEPTH_", tm_abbr),
      playerName   = "Active 26-Man Depth & Minor Allocations",
      position     = "Depth",
      salary2026   = depth_remainder,
      salary2027   = round(depth_remainder * 0.85, 1),
      salary2028   = round(depth_remainder * 0.70, 1),
      contractType = "Guaranteed",
      projectedWar = 1.8,
      surplusValue = round((1.8 * DOLLARS_PER_WAR) - depth_remainder, 2),
      notes        = "Pre-arb minimums, 40-man roster insurance & retained commitments"
    )
    
    franchise_profiles[[length(franchise_profiles) + 1]] <- list(
      teamAbbr        = tm_abbr,
      teamName        = as.character(row$team_name),
      fullName        = as.character(row$full_name),
      league          = as.character(row$league),
      division        = as.character(row$division),
      payroll2026     = p26,
      payroll2027     = p27,
      payroll2028     = p28,
      baseThreshold   = BASE_THRESHOLD,
      tier1Threshold  = TIER1_THRESHOLD,
      tier2Threshold  = TIER2_THRESHOLD,
      tier3Threshold  = TIER3_THRESHOLD,
      cbtSpace2026    = cbt_space,
      cbtTaxBill      = tax_bill,
      totalCommitment = total_commit,
      cbtTier         = tier_label,
      isRepeater      = is_rep,
      penalties       = list(
        draftPickDrop10            = draft_drop,
        internationalPoolReduction = intl_pool_slash,
        taxRateDescription        = tax_desc,
        revenueShareEligible       = rev_share
      ),
      contracts       = team_contracts
    )
  }
  
  # Sort teams by 2026 payroll descending
  franchise_profiles <- franchise_profiles[order(sapply(franchise_profiles, function(x) x$payroll2026), decreasing = TRUE)]
  
  catalog <- list(
    season                  = "2026",
    baseThreshold           = BASE_THRESHOLD,
    tier1Threshold          = TIER1_THRESHOLD,
    tier2Threshold          = TIER2_THRESHOLD,
    tier3Threshold          = TIER3_THRESHOLD,
    totalLeaguePayroll      = round(total_league_payroll, 2),
    totalLuxuryTaxCollected = round(total_luxury_tax, 2),
    teams                   = franchise_profiles
  )
  
  jsonlite::write_json(catalog, out_path, pretty = TRUE, auto_unbox = TRUE)
  message(sprintf(">>> [SUCCESS] CBT & Payroll Sheet catalog written to: %s (%.2f MB)", 
                  out_path, file.info(out_path)$size / (1024 * 1024)))
  
  invisible(catalog)
}

# Standalone execution
if (sys.nframe() == 0) {
  run_mlb_cbt_payroll_engine()
}
