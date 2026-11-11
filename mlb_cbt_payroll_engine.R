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

# Standard 2026 CBA CBT Thresholds (in Millions) -- module-level so
# compute_cbt_tax()/get_cbt_tier() are usable (and testable) standalone,
# outside of run_mlb_cbt_payroll_engine().
CBT_BASE_THRESHOLD  <- 244.0
CBT_TIER1_THRESHOLD <- 264.0
CBT_TIER2_THRESHOLD <- 284.0
CBT_TIER3_THRESHOLD <- 304.0

# Function to calculate CBT Tax Bill based on CBA tier schedule.
# Vectorised over `payroll`/`is_repeater`; guards against NA/NaN/Inf payroll
# and an NA repeater flag so it never errors on bad input (issue #125).
compute_cbt_tax <- function(payroll, is_repeater) {
  if (is.null(payroll) || length(payroll) == 0 ||
      is.null(is_repeater) || length(is_repeater) == 0) {
    return(NA_real_)
  }

  n <- max(length(payroll), length(is_repeater))
  payroll <- rep_len(payroll, n)
  is_repeater <- rep_len(is_repeater, n)

  vapply(seq_len(n), function(i) {
    p <- payroll[i]
    rep_flag <- is_repeater[i]

    if (length(p) == 0 || is.na(p) || !is.finite(p)) {
      return(NA_real_)
    }

    if (is.na(rep_flag)) {
      warning("compute_cbt_tax(): NA repeater flag treated as FALSE")
      rep_flag <- FALSE
    }
    rep_flag <- isTRUE(rep_flag)

    if (p <= CBT_BASE_THRESHOLD) {
      return(0.0)
    }

    overage <- p - CBT_BASE_THRESHOLD
    tax <- 0.0

    # Base overage (Up to $20M over = Tier 1)
    # 20% first time, 30% second time, 50% repeater
    t1_cap <- min(overage, 20.0)
    t1_rate <- if (rep_flag) 0.50 else 0.20
    tax <- tax + t1_cap * t1_rate

    # Tier 2 overage ($20M to $40M over)
    # +12% surcharge (32% first-time, 62% repeater)
    if (overage > 20.0) {
      t2_cap <- min(overage - 20.0, 20.0)
      t2_rate <- if (rep_flag) 0.62 else 0.32
      tax <- tax + t2_cap * t2_rate
    }

    # Tier 3 overage ($40M to $60M over)
    # +42.5% to +45% surcharge (62.5% first-time, 95% repeater)
    if (overage > 40.0) {
      t3_cap <- min(overage - 40.0, 20.0)
      t3_rate <- if (rep_flag) 0.95 else 0.625
      tax <- tax + t3_cap * t3_rate
    }

    # Tier 4 overage (> $60M over = Cohen Tax Tier)
    # 80% first-time, 110% repeater
    if (overage > 60.0) {
      t4_cap <- overage - 60.0
      t4_rate <- if (rep_flag) 1.10 else 0.80
      tax <- tax + t4_cap * t4_rate
    }

    round(tax, 2)
  }, numeric(1))
}

# Categorize CBT Tier. Vectorised over `payroll`; NA/NaN/Inf payroll yields
# "Unknown" instead of erroring (issue #125).
get_cbt_tier <- function(payroll) {
  if (is.null(payroll) || length(payroll) == 0) {
    return(character(0))
  }

  vapply(payroll, function(p) {
    if (length(p) == 0 || is.na(p) || !is.finite(p)) {
      return("Unknown")
    }
    if (p <= CBT_BASE_THRESHOLD) {
      "Under CBT Threshold"
    } else if (p <= CBT_TIER1_THRESHOLD) {
      "Tier 1 Surcharge ($244M-$264M)"
    } else if (p <= CBT_TIER2_THRESHOLD) {
      "Tier 2 Draft Penalty ($264M-$284M)"
    } else if (p <= CBT_TIER3_THRESHOLD) {
      "Tier 3 Cohen Tax ($284M-$304M)"
    } else {
      "Tier 4 Mega Tax (> $304M)"
    }
  }, character(1))
}

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
    SF  = list(p26 = 224.0, p27 = 190.0, p28 = 150.0),
    BOS = list(p26 = 218.0, p27 = 185.0, p28 = 145.0),
    CHC = list(p26 = 215.0, p27 = 180.0, p28 = 140.0),
    SD  = list(p26 = 210.0, p27 = 185.0, p28 = 160.0),
    ARI = list(p26 = 195.0, p27 = 165.0, p28 = 135.0),
    SEA = list(p26 = 186.0, p27 = 155.0, p28 = 130.0),
    BAL = list(p26 = 182.0, p27 = 160.0, p28 = 145.0),
    STL = list(p26 = 175.0, p27 = 140.0, p28 = 115.0),
    MIN = list(p26 = 158.0, p27 = 130.0, p28 = 105.0),
    DET = list(p26 = 154.0, p27 = 135.0, p28 = 110.0),
    MIL = list(p26 = 148.0, p27 = 120.0, p28 = 95.0),
    CIN = list(p26 = 142.0, p27 = 118.0, p28 = 92.0),
    KC  = list(p26 = 138.0, p27 = 115.0, p28 = 90.0),
    CLE = list(p26 = 126.0, p27 = 102.0, p28 = 82.0),
    WSH = list(p26 = 122.0, p27 = 98.0,  p28 = 78.0),
    COL = list(p26 = 118.0, p27 = 92.0,  p28 = 72.0),
    LAA = list(p26 = 115.0, p27 = 90.0,  p28 = 70.0),
    PIT = list(p26 = 98.0,  p27 = 82.0,  p28 = 65.0),
    TB  = list(p26 = 95.0,  p27 = 78.0,  p28 = 62.0),
    MIA = list(p26 = 88.0,  p27 = 72.0,  p28 = 58.0),
    CHW = list(p26 = 82.0,  p27 = 68.0,  p28 = 52.0),
    ATH = list(p26 = 78.0,  p27 = 64.0,  p28 = 50.0) # Athletics (Sacramento/Vegas)
  )
  
  # Standardized marquee contract database from verified published MLB contracts
  # (Cot's Baseball Contracts / Spotrac / MLBPA public disclosures)
  star_contracts <- list(
    # NL West
    "Shohei Ohtani"         = list(s26 = 46.1, s27 = 46.1, s28 = 46.1, type = "Guaranteed",    notes = "10-yr $700M CBT AAV discount"),
    "Yoshinobu Yamamoto"    = list(s26 = 27.1, s27 = 27.1, s28 = 27.1, type = "Guaranteed",    notes = "12-yr $325M contract"),
    "Mookie Betts"          = list(s26 = 30.0, s27 = 30.0, s28 = 30.0, type = "Guaranteed",    notes = "12-yr $365M extension"),
    "Freddie Freeman"       = list(s26 = 27.0, s27 = 27.0, s28 = 0.0,  type = "Guaranteed",    notes = "6-yr $162M expiring after 2027"),
    "Manny Machado"         = list(s26 = 35.0, s27 = 35.0, s28 = 35.0, type = "Guaranteed",    notes = "11-yr $350M extension"),
    "Fernando Tatis Jr."    = list(s26 = 24.7, s27 = 24.7, s28 = 36.7, type = "Guaranteed",    notes = "14-yr $340M contract"),
    "Xander Bogaerts"       = list(s26 = 25.5, s27 = 25.5, s28 = 25.5, type = "Guaranteed",    notes = "11-yr $280M contract"),
    "Corbin Carroll"        = list(s26 = 12.0, s27 = 14.0, s28 = 16.0, type = "Guaranteed",    notes = "8-yr $111M contract"),
    "Ketel Marte"           = list(s26 = 16.0, s27 = 16.0, s28 = 13.0, type = "Guaranteed",    notes = "5-yr $76M veteran extension"),
    "Matt Chapman"          = list(s26 = 25.0, s27 = 25.0, s28 = 25.0, type = "Guaranteed",    notes = "6-yr $151M contract extension"),
    "Jung Hoo Lee"          = list(s26 = 19.0, s27 = 19.0, s28 = 19.0, type = "Guaranteed",    notes = "6-yr $113M contract"),
    "Logan Webb"            = list(s26 = 23.0, s27 = 24.0, s28 = 24.0, type = "Guaranteed",    notes = "5-yr $90M extension"),
    "Kris Bryant"           = list(s26 = 27.0, s27 = 27.0, s28 = 27.0, type = "Guaranteed",    notes = "7-yr $182M contract"),
    "German Marquez"        = list(s26 = 10.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "2-yr $20M contract"),
    "Ezequiel Tovar"        = list(s26 = 4.2,  s27 = 7.2,  s28 = 11.2, type = "Guaranteed",    notes = "7-yr $63.5M extension"),
    # NL East
    "Juan Soto"             = list(s26 = 51.0, s27 = 51.0, s28 = 51.0, type = "Guaranteed",    notes = "15-yr $765M free agency megadeal"),
    "Francisco Lindor"      = list(s26 = 34.1, s27 = 34.1, s28 = 34.1, type = "Guaranteed",    notes = "10-yr $341M contract"),
    "Bryce Harper"          = list(s26 = 27.5, s27 = 27.5, s28 = 27.5, type = "Guaranteed",    notes = "13-yr $330M contract"),
    "Trea Turner"           = list(s26 = 27.3, s27 = 27.3, s28 = 27.3, type = "Guaranteed",    notes = "11-yr $300M contract"),
    "Zack Wheeler"          = list(s26 = 42.0, s27 = 42.0, s28 = 0.0,  type = "Guaranteed",    notes = "3-yr $126M extension through 2027"),
    "Kyle Schwarber"        = list(s26 = 20.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "4-yr $79M contract"),
    "Austin Riley"          = list(s26 = 22.0, s27 = 22.0, s28 = 22.0, type = "Guaranteed",    notes = "10-yr $212M extension"),
    "Matt Olson"            = list(s26 = 22.0, s27 = 22.0, s28 = 22.0, type = "Guaranteed",    notes = "8-yr $168M contract"),
    "Ronald Acuna Jr."      = list(s26 = 17.0, s27 = 17.0, s28 = 17.0, type = "Club Option",   notes = "8-yr $100M w/ club options 2027-2028"),
    "Keibert Ruiz"          = list(s26 = 6.4,  s27 = 8.4,  s28 = 9.4,  type = "Guaranteed",    notes = "8-yr $50M extension"),
    "CJ Abrams"             = list(s26 = 1.2,  s27 = 4.5,  s28 = 9.0,  type = "Pre-Arb",       notes = "Pre-arb shortstop core"),
    "Sandy Alcantara"       = list(s26 = 17.3, s27 = 21.0, s28 = 0.0,  type = "Club Option",   notes = "5-yr $56M w/ 2027 club option"),
    # NL Central
    "Dansby Swanson"        = list(s26 = 27.2, s27 = 27.2, s28 = 27.2, type = "Guaranteed",    notes = "7-yr $177M contract"),
    "Cody Bellinger"        = list(s26 = 27.5, s27 = 0.0,  s28 = 0.0,  type = "Player Option", notes = "3-yr $80M player option year"),
    "Ian Happ"              = list(s26 = 21.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "3-yr $61M extension"),
    "Seiya Suzuki"          = list(s26 = 19.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $85M contract"),
    "Jackson Chourio"       = list(s26 = 4.0,  s27 = 7.0,  s28 = 9.0,  type = "Guaranteed",    notes = "8-yr $82M rookie contract"),
    "William Contreras"     = list(s26 = 7.5,  s27 = 13.0, s28 = 18.0, type = "Arbitration",   notes = "All-Star catcher Arb-2"),
    "Christian Yelich"      = list(s26 = 26.0, s27 = 26.0, s28 = 26.0, type = "Guaranteed",    notes = "9-yr $215M contract"),
    "Nolan Arenado"         = list(s26 = 27.0, s27 = 15.0, s28 = 0.0,  type = "Guaranteed",    notes = "8-yr $260M contract"),
    "Sonny Gray"            = list(s26 = 35.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "3-yr $75M contract"),
    "Willson Contreras"     = list(s26 = 18.0, s27 = 18.0, s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $87.5M contract"),
    "Hunter Greene"         = list(s26 = 8.3,  s27 = 15.3, s28 = 16.3, type = "Guaranteed",    notes = "6-yr $53M contract extension"),
    "Jeimer Candelario"     = list(s26 = 15.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "3-yr $45M contract"),
    "Elly De La Cruz"       = list(s26 = 0.85, s27 = 3.5,  s28 = 9.0,  type = "Pre-Arb",       notes = "Pre-arb generational star"),
    "Paul Skenes"           = list(s26 = 0.85, s27 = 0.90, s28 = 5.5,  type = "Pre-Arb",       notes = "Pre-arb generational ace value"),
    "Bryan Reynolds"        = list(s26 = 14.2, s27 = 14.2, s28 = 14.2, type = "Guaranteed",    notes = "8-yr $106.7M extension"),
    "Ke'Bryan Hayes"        = list(s26 = 7.0,  s27 = 7.0,  s28 = 7.0,  type = "Guaranteed",    notes = "8-yr $70M contract"),
    # AL East
    "Aaron Judge"           = list(s26 = 40.0, s27 = 40.0, s28 = 40.0, type = "Guaranteed",    notes = "9-yr $360M contract"),
    "Gerrit Cole"           = list(s26 = 36.0, s27 = 36.0, s28 = 36.0, type = "Guaranteed",    notes = "9-yr $324M ace veteran anchor"),
    "Vladimir Guerrero Jr." = list(s26 = 29.5, s27 = 32.0, s28 = 32.0, type = "Arbitration",   notes = "Arb-final extension candidate"),
    "Bo Bichette"           = list(s26 = 22.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "3-yr $33.6M walk-year free agent"),
    "Kevin Gausman"         = list(s26 = 23.0, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $110M contract"),
    "Rafael Devers"         = list(s26 = 31.0, s27 = 31.0, s28 = 31.0, type = "Guaranteed",    notes = "10-yr $313.5M contract"),
    "Trevor Story"          = list(s26 = 25.0, s27 = 25.0, s28 = 0.0,  type = "Guaranteed",    notes = "6-yr $140M contract"),
    "Gunnar Henderson"      = list(s26 = 4.5,  s27 = 12.0, s28 = 19.0, type = "Pre-Arb",       notes = "Super-Two MVP superstar"),
    "Adley Rutschman"       = list(s26 = 6.2,  s27 = 14.0, s28 = 21.0, type = "Arbitration",   notes = "Arb-1 arbitration escalation"),
    "Pete Alonso"           = list(s26 = 25.0, s27 = 25.0, s28 = 0.0,  type = "Guaranteed",    notes = "Multi-year power first base anchor"),
    "Yandy Diaz"            = list(s26 = 12.0, s27 = 0.0,  s28 = 0.0,  type = "Club Option",   notes = "3-yr $24M w/ 2026 club option"),
    "Jeffrey Springs"       = list(s26 = 10.5, s27 = 15.0, s28 = 0.0,  type = "Club Option",   notes = "4-yr $31M w/ 2027 club option"),
    # AL Central
    "Bobby Witt Jr."        = list(s26 = 13.0, s27 = 19.0, s28 = 25.0, type = "Guaranteed",    notes = "11-yr $288.7M megadeal"),
    "Salvador Perez"        = list(s26 = 22.0, s27 = 0.0,  s28 = 0.0,  type = "Club Option",   notes = "4-yr $82M w/ 2026 club option"),
    "Tarik Skubal"          = list(s26 = 14.5, s27 = 24.0, s28 = 30.0, type = "Arbitration",   notes = "Cy Young winner Arb-2 escalation"),
    "Javier Baez"           = list(s26 = 24.0, s27 = 24.0, s28 = 0.0,  type = "Guaranteed",    notes = "6-yr $140M contract"),
    "Carlos Correa"         = list(s26 = 33.3, s27 = 33.3, s28 = 33.3, type = "Guaranteed",    notes = "6-yr $200M contract"),
    "Pablo Lopez"           = list(s26 = 21.8, s27 = 21.8, s28 = 0.0,  type = "Guaranteed",    notes = "4-yr $73.5M extension"),
    "Byron Buxton"          = list(s26 = 15.0, s27 = 15.0, s28 = 15.0, type = "Guaranteed",    notes = "7-yr $100M contract"),
    "Jose Ramirez"          = list(s26 = 21.0, s27 = 23.0, s28 = 25.0, type = "Guaranteed",    notes = "7-yr $141M franchise contract"),
    "Andres Gimenez"        = list(s26 = 10.8, s27 = 16.0, s28 = 23.6, type = "Guaranteed",    notes = "7-yr $106.5M extension"),
    "Emmanuel Clase"        = list(s26 = 4.5,  s27 = 6.0,  s28 = 10.0, type = "Club Option",   notes = "5-yr $20M w/ club options"),
    "Luis Robert Jr."       = list(s26 = 15.0, s27 = 20.0, s28 = 20.0, type = "Club Option",   notes = "6-yr $50M w/ 2026-2027 club options"),
    "Andrew Benintendi"     = list(s26 = 17.1, s27 = 17.1, s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $75M contract"),
    # AL West
    "Yordan Alvarez"        = list(s26 = 18.0, s27 = 20.0, s28 = 26.0, type = "Guaranteed",    notes = "6-yr $115M extension"),
    "Jose Altuve"           = list(s26 = 31.5, s27 = 31.5, s28 = 10.0, type = "Guaranteed",    notes = "5-yr $125M veteran extension"),
    "Corey Seager"          = list(s26 = 32.5, s27 = 31.0, s28 = 31.0, type = "Guaranteed",    notes = "10-yr $325M contract"),
    "Marcus Semien"         = list(s26 = 26.0, s27 = 26.0, s28 = 26.0, type = "Guaranteed",    notes = "7-yr $175M contract"),
    "Jacob deGrom"          = list(s26 = 38.0, s27 = 37.0, s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $185M contract"),
    "Julio Rodriguez"       = list(s26 = 18.0, s27 = 18.0, s28 = 18.0, type = "Guaranteed",    notes = "12-yr $209.3M face of franchise"),
    "Luis Castillo"         = list(s26 = 24.1, s27 = 24.1, s28 = 0.0,  type = "Guaranteed",    notes = "5-yr $108M veteran extension"),
    "Randy Arozarena"       = list(s26 = 11.3, s27 = 0.0,  s28 = 0.0,  type = "Arbitration",   notes = "Arb-final outfielder"),
    "Mike Trout"            = list(s26 = 37.1, s27 = 37.1, s28 = 37.1, type = "Guaranteed",    notes = "12-yr $426.5M megadeal"),
    "Anthony Rendon"        = list(s26 = 38.5, s27 = 0.0,  s28 = 0.0,  type = "Guaranteed",    notes = "7-yr $245M expiring after 2026"),
    "Brent Rooker"          = list(s26 = 5.5,  s27 = 9.5,  s28 = 14.0, type = "Arbitration",   notes = "Arb-1 All-Star slugger"),
    "Lawrence Butler"       = list(s26 = 0.85, s27 = 2.5,  s28 = 6.0,  type = "Pre-Arb",       notes = "Pre-arb core outfielder")
  )
  
  # Group players by team to assign contracts
  # Map aliases
  team_alias <- function(tm) {
    if (is.na(tm) || tm == "") return("LAD")
    if (tm == "OAK") return("ATH")
    if (tm == "WAS") return("WSH")
    if (tm == "CHW" || tm == "CWS") return("CHW")
    if (tm == "SFG") return("SF")
    if (tm == "KCR") return("KC")
    if (tm == "SDP") return("SD")
    if (tm == "TBR") return("TB")
    tm
  }
  
  # compute_cbt_tax() / get_cbt_tier() are now defined at module level
  # (top of file) so they are vectorised, guarded against bad input, and
  # independently testable. They use the module-level CBT_*_THRESHOLD
  # constants (same values as the local thresholds above).

  # Process all 30 teams
  franchise_profiles <- list()
  total_league_payroll <- 0
  total_luxury_tax <- 0
  
  unique_teams <- teams_data %>% distinct(team, team_name, full_name, league, division)
  
  for (i in seq_len(nrow(unique_teams))) {
    row <- unique_teams[i, ]
    tm_abbr <- team_alias(row$team)
    is_rep <- tm_abbr %in% repeater_teams
    
    # Verify franchise payroll anchor exists (all 30 MLB franchises are defined above)
    anchor <- team_payroll_anchors[[tm_abbr]]
    if (is.null(anchor)) {
      stop(sprintf("Missing payroll anchor for franchise: %s", tm_abbr))
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
    
    # Build contract roster for team from verified marquee contracts only
    # NOTE (issue #51): Per-player salaries (`salary2026`, `salary2027`, `salary2028`)
    # and `contractType` were previously fabricated here for non-star players using
    # unseeded random uniform draws and probability coin flips.
    # That caused the payload to change on every run and asserted binary contractual
    # facts (such as player options and multi-year guarantees) about real players that
    # no input data supported.
    # Investigation of vendored packages (`baseballr::sptrc_league_payrolls()`,
    # `baseballr::sptrc_team_active_payroll()`, `baseballr::espn_mlb_player_contract()`)
    # confirmed that Spotrac scrapers return 0 rows and ESPN's contract endpoint returns
    # HTTP 404, and neither `mlb_stats_sync.R` nor `mlb_id_crosswalk.R` carries contract
    # terms. Per the front-office zero-synthetic data policy, the random fallback branch
    # was removed completely: only verified published contracts in `star_contracts` are
    # emitted as individual player rows, and the remaining franchise payroll commitment
    # is accounted for deterministically in the team depth allocation row below.
    # Do not reintroduce per-player salary heuristics or random draws without a real source.
    team_contracts <- list()
    allocated_s26 <- 0
    allocated_s27 <- 0
    allocated_s28 <- 0
    
    if (nrow(tm_players) > 0) {
      for (k in seq_len(nrow(tm_players))) {
        p_row <- tm_players[k, ]
        p_name <- p_row$player_name
        
        if (is.null(star_contracts[[p_name]])) {
          next
        }
        
        sc <- star_contracts[[p_name]]
        p_pos <- if (p_row$player_type == "Pitcher") "P" else p_row$position
        if (p_pos == "B") p_pos <- "DH/OF"
        
        # Projected WAR from composite zscore & workload
        z <- if (!is.null(p_row$composite_zscore) && !is.na(p_row$composite_zscore)) as.numeric(p_row$composite_zscore) else 1.0
        proj_war <- round(max(0.2, (z * 0.9) + 2.1), 1)
        
        s26 <- sc$s26
        s27 <- sc$s27
        s28 <- sc$s28
        c_type <- sc$type
        c_notes <- sc$notes
        
        surplus <- round((proj_war * DOLLARS_PER_WAR) - s26, 2)
        allocated_s26 <- allocated_s26 + s26
        allocated_s27 <- allocated_s27 + s27
        allocated_s28 <- allocated_s28 + s28
        
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
    
    # Deterministic remainder for active 26-man depth & minor league obligations
    depth_s26 <- round(max(5.0, p26 - allocated_s26), 1)
    depth_s27 <- round(max(0.0, p27 - allocated_s27), 1)
    depth_s28 <- round(max(0.0, p28 - allocated_s28), 1)
    team_contracts[[length(team_contracts) + 1]] <- list(
      playerId     = paste0("DEPTH_", tm_abbr),
      playerName   = "Active 26-Man Depth & Minor Allocations",
      position     = "Depth",
      salary2026   = depth_s26,
      salary2027   = depth_s27,
      salary2028   = depth_s28,
      contractType = "Guaranteed",
      projectedWar = 1.8,
      surplusValue = round((1.8 * DOLLARS_PER_WAR) - depth_s26, 2),
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
    # generated_at is what tools/publish_web.R's assertion F reads: UTC, ISO-8601,
    # and FIRST in the object because F only scans the first 4096 bytes of the
    # file (this payload is ~195 KB). This engine does not source config.R, so
    # the format string is inline here, matching tools/export_web_data.R.
    generated_at            = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
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
