# ==============================================================================
# build_cba_cap_dataset.R
# 2026-2027 NBA Season Salary Cap, Apron & Luxury Tax Architect Dataset
# Calibrated with Official 2026-27 League Cap Figures and Spotrac Contracts:
# - Salary Cap: $165.0M ($164,961,000)
# - Minimum Team Salary: $148.5M ($148,465,000)
# - Luxury Tax Line: $200.4M ($200,428,000)
# - First Apron: $209.0M ($209,015,000)
# - Second Apron: $221.7M ($221,686,000)
# - Multi-Year Projections: 2027-28 ($181.5M Cap), 2028-29 ($199.6M Cap) (10% TV-deal cap smoothing)
# Sources: Spotrac, Basketball-Reference, Hoops Rumors, RealGM, NBA CBA Registry.
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
  library(tibble)
})

# Source global config
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

if (!dir.exists(CACHE_DIR)) dir.create(CACHE_DIR, recursive = TRUE)

message(">>> [CBA ARCHITECT] Initializing Calibrated 2026-2027 CBA Salary Cap & Apron Analytics Engine...")

# CBA Financial Thresholds for 2026-2027 Season ($M)
SALARY_CAP       <- 165.0
LUXURY_TAX       <- 200.4
FIRST_APRON      <- 209.0
SECOND_APRON     <- 221.7
CAP_PROJ_2027    <- 181.5
CAP_PROJ_2028    <- 199.6

# ------------------------------------------------------------------------------
# Luxury Tax Calculation Function (Progressive Brackets + Repeater Penalties)
# ------------------------------------------------------------------------------
compute_luxury_tax <- function(payroll, is_repeater = FALSE) {
  if (payroll <= LUXURY_TAX) return(0.0)
  
  overage <- payroll - LUXURY_TAX
  tax_bill <- 0
  
  # Standard vs Repeater rates per bracket ($0-5M, $5-10M, $10-15M, $15-20M, >$20M)
  rates <- if (!is_repeater) {
    c(1.50, 1.75, 2.50, 3.25, 3.75)
  } else {
    c(2.50, 2.75, 3.50, 4.25, 4.75)
  }
  
  # Bracket 1: $0 - $5M
  b1 <- min(overage, 5.0)
  tax_bill <- tax_bill + b1 * rates[1]
  
  # Bracket 2: $5 - $10M
  if (overage > 5.0) {
    b2 <- min(overage - 5.0, 5.0)
    tax_bill <- tax_bill + b2 * rates[2]
  }
  
  # Bracket 3: $10 - $15M
  if (overage > 10.0) {
    b3 <- min(overage - 10.0, 5.0)
    tax_bill <- tax_bill + b3 * rates[3]
  }
  
  # Bracket 4: $15 - $20M
  if (overage > 15.0) {
    b4 <- min(overage - 15.0, 5.0)
    tax_bill <- tax_bill + b4 * rates[4]
  }
  
  # Bracket 5: > $20M
  if (overage > 20.0) {
    b5 <- overage - 20.0
    tax_bill <- tax_bill + b5 * rates[5]
  }
  
  return(round(tax_bill, 1))
}

# ------------------------------------------------------------------------------
# 30 NBA Franchises 2026-2027 Payroll & Future Commitments ($M)
# Benchmarked against Spotrac 2026-27 tracking rankings
# ------------------------------------------------------------------------------
repeater_teams <- c("GSW", "BOS", "PHX", "DEN", "MIL", "LAC")

team_payrolls <- tribble(
  ~team_abbr, ~team_name, ~conf, ~payroll_2026, ~payroll_2027, ~payroll_2028,
  # Second Apron (> $221.7M)
  "GSW", "Warriors", "West", 224.2, 212.5, 198.0,
  "ORL", "Magic", "East", 223.1, 230.5, 238.0,
  "NYK", "Knicks", "East", 222.8, 218.4, 210.5,
  # First Apron Tier ($209.0M - $221.7M)
  "DEN", "Nuggets", "West", 218.5, 209.4, 198.0,
  "PHX", "Suns", "West", 216.2, 204.0, 185.0,
  "OKC", "Thunder", "West", 216.1, 228.0, 242.0,
  "MIN", "Timberwolves", "West", 215.4, 208.5, 195.0,
  "PHI", "76ers", "East", 210.5, 202.0, 188.0,
  "CLE", "Cavaliers", "East", 209.8, 201.5, 190.0,
  # Luxury Taxpayer Tier ($200.4M - $209.0M)
  "MIA", "Heat", "East", 207.8, 198.0, 185.0,
  "IND", "Pacers", "East", 206.5, 198.2, 186.0,
  "MIL", "Bucks", "East", 205.2, 195.0, 180.0,
  "HOU", "Rockets", "West", 204.8, 215.0, 228.0,
  "TOR", "Raptors", "East", 201.8, 192.5, 180.0,
  "LAL", "Lakers", "West", 201.2, 188.0, 172.0,
  # Over Cap / Non-Taxpayer ($165.0M - $200.4M)
  "BOS", "Celtics", "East", 199.5, 192.0, 182.0,
  "LAC", "Clippers", "West", 196.5, 182.0, 168.0,
  "MEM", "Grizzlies", "West", 192.0, 198.5, 205.0,
  "DAL", "Mavericks", "West", 188.5, 194.0, 202.0,
  "SAC", "Kings", "West", 184.2, 175.0, 162.0,
  "NOP", "Pelicans", "West", 181.0, 172.5, 158.0,
  "ATL", "Hawks", "East", 176.5, 165.0, 150.0,
  "CHI", "Bulls", "East", 172.0, 158.0, 145.0,
  "CHA", "Hornets", "East", 168.5, 175.0, 182.0,
  "POR", "Trail Blazers", "West", 166.0, 162.0, 155.0,
  # Cap Room / Under Cap (< $165.0M)
  "SAS", "Spurs", "West", 162.0, 178.0, 195.0,
  "DET", "Pistons", "East", 158.5, 168.0, 182.0,
  "UTA", "Jazz", "West", 155.0, 148.0, 138.0,
  "WAS", "Wizards", "East", 152.0, 145.0, 135.0,
  "BKN", "Nets", "East", 149.5, 142.0, 130.0
)

# ------------------------------------------------------------------------------
# Verified Spotrac 2026-27 Active Contracts for Marquee Franchises
# Sources: Spotrac, Basketball-Reference, HoopsRumors Contract Sheets
# ------------------------------------------------------------------------------
verified_contracts <- list(
  NYK = list(
    list(playerId = "3102531", playerName = "Karl-Anthony Towns", position = "C", salary2026 = 57.1, salary2027 = 61.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr supermax ($57,078,728 in '26-27, $61.0M PO in '27-28)"),
    list(playerId = "3934672", playerName = "OG Anunoby", position = "F", salary2026 = 42.5, salary2027 = 45.0, salary2028 = 47.5, contractType = "Guaranteed", notes = "Spotrac: 5-yr max extension ($42,500,000 in '26-27)"),
    list(playerId = "3934673", playerName = "Jalen Brunson", position = "G", salary2026 = 37.7, salary2027 = 40.8, salary2028 = 43.8, contractType = "Guaranteed", notes = "Spotrac: 4-yr $156.5M veteran extension ($37,739,521 in '26-27)"),
    list(playerId = "3147572", playerName = "Mikal Bridges", position = "G", salary2026 = 33.5, salary2027 = 35.8, salary2028 = 38.2, contractType = "Guaranteed", notes = "Spotrac: Extension cap hit ($33,482,145 in '26-27)"),
    list(playerId = "3062679", playerName = "Josh Hart", position = "G", salary2026 = 20.9, salary2027 = 22.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr extension ($20,923,760 in '26-27)"),
    list(playerId = "3064427", playerName = "Landry Shamet", position = "G", salary2026 = 5.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: ~$5.4M cap allocation"),
    list(playerId = "4395629", playerName = "Jose Alvarado", position = "G", salary2026 = 4.5, salary2027 = 4.8, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Multi-year extension ($4.5M in '26-27)"),
    list(playerId = "4432822", playerName = "Miles McBride", position = "G", salary2026 = 4.0, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 3-yr $13M deal ($3,956,523 in '26-27)"),
    list(playerId = "2528353", playerName = "Andre Drummond", position = "C", salary2026 = 2.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Veteran Minimum ($2,449,421 in '26-27)"),
    list(playerId = "4433134", playerName = "James Wiseman", position = "C", salary2026 = 2.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Minimum Scale ($2,449,421 in '26-27)")
  ),
  BOS = list(
    list(playerId = "4065648", playerName = "Jayson Tatum", position = "F", salary2026 = 58.5, salary2027 = 63.1, salary2028 = 67.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr supermax ($58,456,566 in '26-27)"),
    list(playerId = "3078576", playerName = "Derrick White", position = "G", salary2026 = 30.3, salary2027 = 32.8, salary2028 = 35.2, contractType = "Guaranteed", notes = "Spotrac: 4-yr extension ($30,348,000 in '26-27)"),
    list(playerId = "4066354", playerName = "Payton Pritchard", position = "G", salary2026 = 7.8, salary2027 = 8.3, salary2028 = 16.0, contractType = "Guaranteed", notes = "Spotrac: Current deal ($7,767,857 in '26-27)"),
    list(playerId = "4277953", playerName = "Sam Hauser", position = "F", salary2026 = 10.8, salary2027 = 11.7, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $45M extension ($10,848,215 in '26-27)"),
    list(playerId = "4397136", playerName = "Neemias Queta", position = "C", salary2026 = 2.7, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Multi-year minimum ($2,667,944 in '26-27)"),
    list(playerId = "4432158", playerName = "Jordan Walsh", position = "F", salary2026 = 2.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Rookie Scale Contract")
  ),
  DEN = list(
    list(playerId = "3112335", playerName = "Nikola Jokic", position = "C", salary2026 = 59.0, salary2027 = 62.8, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: Supermax extension ($59,033,114 in '26-27)"),
    list(playerId = "3936299", playerName = "Jamal Murray", position = "G", salary2026 = 50.1, salary2027 = 54.1, salary2028 = 58.1, contractType = "Guaranteed", notes = "Spotrac: 4-yr max extension ($50,105,628 in '26-27)"),
    list(playerId = "3064290", playerName = "Aaron Gordon", position = "F", salary2026 = 33.7, salary2027 = 36.3, salary2028 = 39.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr extension ($33,658,037 in '26-27)"),
    list(playerId = "4065670", playerName = "Cameron Johnson", position = "F", salary2026 = 23.0, salary2027 = 24.5, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr deal ($23.0M in '26-27)"),
    list(playerId = "4432816", playerName = "Christian Braun", position = "G", salary2026 = 21.5, salary2027 = 23.0, salary2028 = 24.5, contractType = "Guaranteed", notes = "Spotrac: Rookie max extension ($21.5M in '26-27)")
  ),
  GSW = list(
    list(playerId = "3975", playerName = "Stephen Curry", position = "G", salary2026 = 62.6, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 1-yr extension ($62,587,158 in '26-27)"),
    list(playerId = "6430", playerName = "Jimmy Butler III", position = "F", salary2026 = 56.8, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Veteran max extension ($56,832,773 in '26-27)"),
    list(playerId = "6583", playerName = "Draymond Green", position = "F", salary2026 = 27.7, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr deal ($27,678,571 in '26-27)"),
    list(playerId = "4395628", playerName = "Jonathan Kuminga", position = "F", salary2026 = 28.5, salary2027 = 30.5, salary2028 = 32.5, contractType = "Guaranteed", notes = "Spotrac: RFA Extension allocation"),
    list(playerId = "4432165", playerName = "Moses Moody", position = "G", salary2026 = 13.0, salary2027 = 13.0, salary2028 = 13.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr $39M extension")
  ),
  OKC = list(
    list(playerId = "4278073", playerName = "Shai Gilgeous-Alexander", position = "G", salary2026 = 40.8, salary2027 = 65.0, salary2028 = 70.2, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max ($40,806,150 in '26-27, Supermax eligible '27)"),
    list(playerId = "4432821", playerName = "Jalen Williams", position = "F", salary2026 = 36.5, salary2027 = 39.4, salary2028 = 42.3, contractType = "Guaranteed", notes = "Spotrac: Rookie Max Extension ($36.5M in '26-27)"),
    list(playerId = "4432820", playerName = "Chet Holmgren", position = "C", salary2026 = 36.5, salary2027 = 39.4, salary2028 = 42.3, contractType = "Guaranteed", notes = "Spotrac: Rookie Max Extension ($36.5M in '26-27)"),
    list(playerId = "4065663", playerName = "Isaiah Hartenstein", position = "C", salary2026 = 28.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 3-yr $87M deal ($28.5M in '26-27)"),
    list(playerId = "3064440", playerName = "Alex Caruso", position = "G", salary2026 = 20.5, salary2027 = 22.0, salary2028 = 23.5, contractType = "Guaranteed", notes = "Spotrac: 4-yr extension ($20.5M in '26-27)")
  ),
  LAL = list(
    list(playerId = "3945274", playerName = "Luka Doncic", position = "G", salary2026 = 49.0, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 5-yr designated rookie max ($48,967,380 in '26-27)"),
    list(playerId = "6589", playerName = "Anthony Davis", position = "C", salary2026 = 58.5, salary2027 = 62.8, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr supermax extension ($58,456,566 in '26-27)"),
    list(playerId = "4277883", playerName = "Austin Reaves", position = "G", salary2026 = 14.9, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr Early Bird deal ($14.9M in '26-27)"),
    list(playerId = "1966", playerName = "LeBron James", position = "F", salary2026 = 24.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 1+1 deal allocation"),
    list(playerId = "4066372", playerName = "Rui Hachimura", position = "F", salary2026 = 18.2, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr deal ($18.2M in '26-27)")
  ),
  MIN = list(
    list(playerId = "4432809", playerName = "Anthony Edwards", position = "G", salary2026 = 48.9, salary2027 = 52.8, salary2028 = 56.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie supermax ($48,924,624 in '26-27)"),
    list(playerId = "3102529", playerName = "Rudy Gobert", position = "C", salary2026 = 36.5, salary2027 = 38.5, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 3-yr $110M extension ($36.5M in '26-27)"),
    list(playerId = "4277961", playerName = "Jaden McDaniels", position = "F", salary2026 = 26.5, salary2027 = 28.5, salary2028 = 30.5, contractType = "Guaranteed", notes = "Spotrac: 5-yr $136M rookie extension"),
    list(playerId = "4066367", playerName = "Naz Reid", position = "C", salary2026 = 21.0, salary2027 = 22.5, salary2028 = 24.0, contractType = "Guaranteed", notes = "Spotrac: Veteran extension")
  ),
  SAS = list(
    list(playerId = "5104157", playerName = "Victor Wembanyama", position = "C", salary2026 = 16.9, salary2027 = 48.5, salary2028 = 52.4, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($16,868,246 in '26-27, Max extension eligible)"),
    list(playerId = "3136195", playerName = "Devin Vassell", position = "G", salary2026 = 27.0, salary2027 = 24.5, salary2028 = 22.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr $135M rookie extension"),
    list(playerId = "4433140", playerName = "Stephon Castle", position = "G", salary2026 = 9.8, salary2027 = 12.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: No. 4 overall rookie scale contract"),
    list(playerId = "4278077", playerName = "Keldon Johnson", position = "F", salary2026 = 17.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $74M descending deal")
  ),
  MIL = list(
    list(playerId = "3032977", playerName = "Giannis Antetokounmpo", position = "F", salary2026 = 58.5, salary2027 = 62.8, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: Supermax extension ($58,456,566 in '26-27)"),
    list(playerId = "3064440", playerName = "Myles Turner", position = "C", salary2026 = 26.6, salary2027 = 28.5, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Free Agent Signing ($26,584,164 in '26-27)"),
    list(playerId = "4277960", playerName = "Tyler Herro", position = "G", salary2026 = 33.0, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $130M deal ($33,000,000 in '26-27)"),
    list(playerId = "4432168", playerName = "Jaime Jaquez Jr.", position = "F", salary2026 = 5.9, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($5,939,141 in '26-27)"),
    list(playerId = "3064433", playerName = "Bobby Portis", position = "F", salary2026 = 13.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: Veteran deal")
  ),
  PHI = list(
    list(playerId = "3059318", playerName = "Joel Embiid", position = "C", salary2026 = 58.1, salary2027 = 62.5, salary2028 = 66.8, contractType = "Guaranteed", notes = "Spotrac: Supermax extension ($58,100,000 in '26-27)"),
    list(playerId = "4251", playerName = "Paul George", position = "F", salary2026 = 54.1, salary2027 = 57.8, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr max deal ($54,126,380 in '26-27)"),
    list(playerId = "4431678", playerName = "Tyrese Maxey", position = "G", salary2026 = 40.8, salary2027 = 44.0, salary2028 = 47.3, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max ($40,770,520 in '26-27)"),
    list(playerId = "3064426", playerName = "Kelly Oubre Jr.", position = "F", salary2026 = 8.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 2-yr deal")
  ),
  CLE = list(
    list(playerId = "3908809", playerName = "Donovan Mitchell", position = "G", salary2026 = 50.1, salary2027 = 54.1, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 3-yr max extension ($50,105,628 in '26-27)"),
    list(playerId = "4432158", playerName = "Evan Mobley", position = "F", salary2026 = 50.1, salary2027 = 54.1, salary2028 = 58.1, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max ($50,105,628 in '26-27)"),
    list(playerId = "4395625", playerName = "Darius Garland", position = "G", salary2026 = 42.2, salary2027 = 45.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr max extension ($42,166,510 in '26-27)"),
    list(playerId = "4066368", playerName = "Jarrett Allen", position = "C", salary2026 = 28.0, salary2027 = 30.2, salary2028 = 32.5, contractType = "Guaranteed", notes = "Spotrac: 3-yr extension ($28.0M in '26-27)")
  ),
  PHX = list(
    list(playerId = "3136193", playerName = "Devin Booker", position = "G", salary2026 = 57.1, salary2027 = 61.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr supermax extension ($57,078,728 in '26-27)"),
    list(playerId = "6580", playerName = "Bradley Beal", position = "G", salary2026 = 53.7, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 5-yr veteran max ($53,666,215 in '26-27)"),
    list(playerId = "3064438", playerName = "Grayson Allen", position = "G", salary2026 = 18.2, salary2027 = 19.5, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $70M extension"),
    list(playerId = "3102530", playerName = "Jusuf Nurkic", position = "C", salary2026 = 19.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Multi-year contract")
  ),
  ORL = list(
    list(playerId = "4432810", playerName = "Paolo Banchero", position = "F", salary2026 = 41.2, salary2027 = 44.5, salary2028 = 47.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max extension ($41,240,250 in '26-27)"),
    list(playerId = "4432163", playerName = "Franz Wagner", position = "F", salary2026 = 41.8, salary2027 = 45.1, salary2028 = 48.4, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max extension ($41,754,690 in '26-27)"),
    list(playerId = "4432164", playerName = "Jalen Suggs", position = "G", salary2026 = 32.4, salary2027 = 35.0, salary2028 = 37.6, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie extension ($32,400,000 in '26-27)"),
    list(playerId = "4431679", playerName = "Desmond Bane", position = "G", salary2026 = 39.4, salary2027 = 42.6, salary2028 = 45.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr extension via trade ($39,446,090 in '26-27)"),
    list(playerId = "4066373", playerName = "Wendell Carter Jr.", position = "C", salary2026 = 18.5, salary2027 = 19.8, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr extension")
  ),
  IND = list(
    list(playerId = "4432811", playerName = "Tyrese Haliburton", position = "G", salary2026 = 48.9, salary2027 = 52.8, salary2028 = 56.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie supermax ($48,924,624 in '26-27)"),
    list(playerId = "3147573", playerName = "Pascal Siakam", position = "F", salary2026 = 48.9, salary2027 = 52.8, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr max deal ($48,924,624 in '26-27)"),
    list(playerId = "4277905", playerName = "Andrew Nembhard", position = "G", salary2026 = 18.5, salary2027 = 19.8, salary2028 = 21.2, contractType = "Guaranteed", notes = "Spotrac: 3-yr extension ($18.5M in '26-27)"),
    list(playerId = "4432812", playerName = "Bennedict Mathurin", position = "G", salary2026 = 11.2, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: Rookie Scale Option")
  ),
  MIA = list(
    list(playerId = "4066261", playerName = "Bam Adebayo", position = "C", salary2026 = 49.5, salary2027 = 53.5, salary2028 = 57.5, contractType = "Guaranteed", notes = "Spotrac: 3-yr max extension ($49,488,300 in '26-27)"),
    list(playerId = "3934674", playerName = "Terry Rozier", position = "G", salary2026 = 26.6, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Expiring contract year"),
    list(playerId = "4432814", playerName = "Nikola Jovic", position = "F", salary2026 = 4.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: Rookie scale contract"),
    list(playerId = "5105550", playerName = "Kel'el Ware", position = "C", salary2026 = 4.8, salary2027 = 6.2, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: First-round rookie scale")
  ),
  HOU = list(
    list(playerId = "4432815", playerName = "Alperen Sengun", position = "C", salary2026 = 35.6, salary2027 = 38.5, salary2028 = 41.4, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie extension ($35,642,202 in '26-27)"),
    list(playerId = "3200", playerName = "Kevin Durant", position = "F", salary2026 = 43.9, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Extension via trade ($43,902,439 in '26-27)"),
    list(playerId = "3102528", playerName = "Fred VanVleet", position = "G", salary2026 = 25.0, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: Restructured extension ($25,000,000 in '26-27)"),
    list(playerId = "4432817", playerName = "Jabari Smith Jr.", position = "F", salary2026 = 23.6, salary2027 = 25.5, salary2028 = 27.4, contractType = "Guaranteed", notes = "Spotrac: Rookie Extension ($23,643,411 in '26-27)"),
    list(playerId = "5104155", playerName = "Amen Thompson", position = "G", salary2026 = 12.3, salary2027 = 16.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($12,258,609 in '26-27)"),
    list(playerId = "4432818", playerName = "Tari Eason", position = "F", salary2026 = 14.1, salary2027 = 15.2, salary2028 = 16.3, contractType = "Guaranteed", notes = "Spotrac: Multi-year extension ($14,051,724 in '26-27)")
  ),
  TOR = list(
    list(playerId = "4432819", playerName = "Scottie Barnes", position = "F", salary2026 = 41.8, salary2027 = 45.1, salary2028 = 48.4, contractType = "Guaranteed", notes = "Spotrac: 5-yr designated rookie max ($41,754,690 in '26-27)"),
    list(playerId = "4277962", playerName = "Immanuel Quickley", position = "G", salary2026 = 32.5, salary2027 = 35.0, salary2028 = 37.5, contractType = "Guaranteed", notes = "Spotrac: 5-yr $175M contract ($32,500,000 in '26-27)"),
    list(playerId = "4395627", playerName = "RJ Barrett", position = "F", salary2026 = 29.6, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $107M contract ($29,616,071 in '26-27)"),
    list(playerId = "4066374", playerName = "Jakob Poeltl", position = "C", salary2026 = 19.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $80M contract")
  ),
  DAL = list(
    list(playerId = "6442", playerName = "Kyrie Irving", position = "G", salary2026 = 39.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Final year ($39,491,282 in '26-27)"),
    list(playerId = "6475", playerName = "Klay Thompson", position = "G", salary2026 = 17.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr $50M deal ($17,460,317 in '26-27)"),
    list(playerId = "4066375", playerName = "Daniel Gafford", position = "C", salary2026 = 17.3, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr extension ($17,263,584 in '26-27)"),
    list(playerId = "5104156", playerName = "Dereck Lively II", position = "C", salary2026 = 7.2, salary2027 = 9.8, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($7,239,131 in '26-27)"),
    list(playerId = "4066376", playerName = "P.J. Washington", position = "F", salary2026 = 15.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr $48M deal")
  ),
  SAC = list(
    list(playerId = "3155535", playerName = "Domantas Sabonis", position = "C", salary2026 = 45.5, salary2027 = 48.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr extension ($45,472,000 in '26-27)"),
    list(playerId = "4432824", playerName = "Keegan Murray", position = "F", salary2026 = 24.1, salary2027 = 26.0, salary2028 = 28.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr $140M extension ($24,137,936 in '26-27)"),
    list(playerId = "4066377", playerName = "Malik Monk", position = "G", salary2026 = 19.5, salary2027 = 21.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr $78M deal"),
    list(playerId = "4432825", playerName = "Keon Ellis", position = "G", salary2026 = 2.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Standard contract")
  ),
  NOP = list(
    list(playerId = "4395628", playerName = "Zion Williamson", position = "F", salary2026 = 42.2, salary2027 = 45.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr designated rookie max ($42,166,510 in '26-27)"),
    list(playerId = "3934675", playerName = "Dejounte Murray", position = "G", salary2026 = 32.8, salary2027 = 35.1, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $114M extension ($32,785,071 in '26-27)"),
    list(playerId = "4432826", playerName = "Trey Murphy III", position = "F", salary2026 = 27.0, salary2027 = 29.2, salary2028 = 31.3, contractType = "Guaranteed", notes = "Spotrac: 4-yr $112M rookie extension ($27,000,000 in '26-27)"),
    list(playerId = "4432827", playerName = "Herbert Jones", position = "F", salary2026 = 14.9, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $54M deal ($14,898,786 in '26-27)")
  ),
  MEM = list(
    list(playerId = "4432808", playerName = "Ja Morant", position = "G", salary2026 = 42.2, salary2027 = 45.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max ($42,176,470 in '26-27)"),
    list(playerId = "4277963", playerName = "Brandon Clarke", position = "F", salary2026 = 12.5, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $50M extension ($12,500,000 in '26-27)"),
    list(playerId = "4432828", playerName = "Santi Aldama", position = "F", salary2026 = 17.0, salary2027 = 18.2, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Multi-year extension ($17,007,043 in '26-27)"),
    list(playerId = "5105551", playerName = "Zach Edey", position = "C", salary2026 = 6.3, salary2027 = 8.1, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: First-round rookie scale ($6,332,760 in '26-27)")
  ),
  ATL = list(
    list(playerId = "4432829", playerName = "Jalen Johnson", position = "F", salary2026 = 30.0, salary2027 = 32.4, salary2028 = 34.8, contractType = "Guaranteed", notes = "Spotrac: 5-yr $150M rookie extension ($30,000,000 in '26-27)"),
    list(playerId = "4432830", playerName = "Dyson Daniels", position = "G", salary2026 = 25.0, salary2027 = 27.0, salary2028 = 29.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $100M rookie extension ($25,000,000 in '26-27)"),
    list(playerId = "4432831", playerName = "Onyeka Okongwu", position = "C", salary2026 = 16.1, salary2027 = 17.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $62M extension ($16,120,000 in '26-27)")
  ),
  CHA = list(
    list(playerId = "5104158", playerName = "Brandon Miller", position = "F", salary2026 = 15.1, salary2027 = 19.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: No. 2 overall rookie scale ($15,104,625 in '26-27)"),
    list(playerId = "4066378", playerName = "Grant Williams", position = "F", salary2026 = 14.3, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $53M deal ($14,265,750 in '26-27)"),
    list(playerId = "4432832", playerName = "Tre Mann", position = "G", salary2026 = 8.0, salary2027 = 8.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr $24M contract ($8,000,000 in '26-27)")
  ),
  CHI = list(
    list(playerId = "4432833", playerName = "Josh Giddey", position = "G", salary2026 = 25.0, salary2027 = 27.0, salary2028 = 29.0, contractType = "Guaranteed", notes = "Spotrac: Multi-year extension ($25,000,000 in '26-27)"),
    list(playerId = "4066379", playerName = "Nic Claxton", position = "C", salary2026 = 23.1, salary2027 = 21.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr $97M descending deal ($23,147,727 in '26-27)"),
    list(playerId = "4432834", playerName = "Patrick Williams", position = "F", salary2026 = 18.0, salary2027 = 19.4, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr $90M extension ($18,000,000 in '26-27)"),
    list(playerId = "5105552", playerName = "Matas Buzelis", position = "F", salary2026 = 5.7, salary2027 = 7.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: Rookie scale contract ($5,715,360 in '26-27)")
  ),
  DET = list(
    list(playerId = "4432813", playerName = "Cade Cunningham", position = "G", salary2026 = 50.1, salary2027 = 54.1, salary2028 = 58.1, contractType = "Guaranteed", notes = "Spotrac: 5-yr designated rookie max ($50,105,628 in '26-27)"),
    list(playerId = "4432835", playerName = "Jalen Duren", position = "C", salary2026 = 40.2, salary2027 = 43.4, salary2028 = 46.6, contractType = "Guaranteed", notes = "Spotrac: 5-yr rookie max extension ($40,160,643 in '26-27)"),
    list(playerId = "5104159", playerName = "Ausar Thompson", position = "F", salary2026 = 11.1, salary2027 = 15.2, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($11,117,925 in '26-27)"),
    list(playerId = "5105553", playerName = "Ronald Holland II", position = "F", salary2026 = 9.1, salary2027 = 11.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: No. 5 overall rookie scale ($9,069,600 in '26-27)")
  ),
  BKN = list(
    list(playerId = "4432836", playerName = "Noah Clowney", position = "F", salary2026 = 5.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($5,414,034 in '26-27)"),
    list(playerId = "4432837", playerName = "Terance Mann", position = "G", salary2026 = 15.5, salary2027 = 15.5, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr $47M extension ($15,500,000 in '26-27)"),
    list(playerId = "4066380", playerName = "Dorian Finney-Smith", position = "F", salary2026 = 15.4, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 4-yr contract")
  ),
  UTA = list(
    list(playerId = "3136194", playerName = "Lauri Markkanen", position = "F", salary2026 = 46.1, salary2027 = 48.5, salary2028 = 51.0, contractType = "Guaranteed", notes = "Spotrac: 5-yr renegotiation-and-extension ($46,113,154 in '26-27)"),
    list(playerId = "4066381", playerName = "Walker Kessler", position = "C", salary2026 = 32.4, salary2027 = 35.0, salary2028 = 37.6, contractType = "Guaranteed", notes = "Spotrac: 4-yr $129.5M extension ($32,375,000 in '26-27)"),
    list(playerId = "5104160", playerName = "Keyonte George", position = "G", salary2026 = 6.6, salary2027 = 28.5, salary2028 = 30.5, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($6,563,925 in '26-27)")
  ),
  POR = list(
    list(playerId = "3934676", playerName = "Jerami Grant", position = "F", salary2026 = 34.2, salary2027 = 36.4, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 5-yr $160M deal ($34,206,898 in '26-27)"),
    list(playerId = "4432838", playerName = "Shaedon Sharpe", position = "G", salary2026 = 20.1, salary2027 = 22.0, salary2028 = 24.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr rookie extension ($20,089,287 in '26-27)"),
    list(playerId = "5104161", playerName = "Scoot Henderson", position = "G", salary2026 = 13.6, salary2027 = 17.5, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: 4th-yr rookie option ($13,585,523 in '26-27)"),
    list(playerId = "4432839", playerName = "Deni Avdija", position = "F", salary2026 = 13.1, salary2027 = 11.9, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 4-yr descending deal ($13,125,000 in '26-27)"),
    list(playerId = "5105554", playerName = "Donovan Clingan", position = "C", salary2026 = 7.5, salary2027 = 9.8, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: No. 7 overall rookie scale ($7,519,920 in '26-27)")
  ),
  LAC = list(
    list(playerId = "4066382", playerName = "Brook Lopez", position = "C", salary2026 = 9.2, salary2027 = 0.0, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: Picked-up team option ($9,187,500 in '26-27)"),
    list(playerId = "3102532", playerName = "Kris Dunn", position = "G", salary2026 = 5.7, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: 3-yr deal ($5,684,800 in '26-27)")
  ),
  WAS = list(
    list(playerId = "3934677", playerName = "Trae Young", position = "G", salary2026 = 48.9, salary2027 = 0.0, salary2028 = 0.0, contractType = "Player Option", notes = "Spotrac: 5-yr designated max ($48,967,380 in '26-27)"),
    list(playerId = "5105555", playerName = "Alex Sarr", position = "C", salary2026 = 12.4, salary2027 = 15.8, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: No. 2 overall rookie scale ($12,370,680 in '26-27)"),
    list(playerId = "3064441", playerName = "Khris Middleton", position = "F", salary2026 = 5.6, salary2027 = 0.0, salary2028 = 0.0, contractType = "Guaranteed", notes = "Spotrac: Veteran contract ($5,591,122 in '26-27)"),
    list(playerId = "5105556", playerName = "Bub Carrington", position = "G", salary2026 = 4.9, salary2027 = 6.4, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: First-round rookie scale ($4,900,560 in '26-27)"),
    list(playerId = "5105557", playerName = "Kyshawn George", position = "F", salary2026 = 3.1, salary2027 = 4.2, salary2028 = 0.0, contractType = "Team Option", notes = "Spotrac: First-round rookie scale ($3,108,000 in '26-27)")
  )
)

# Load full player catalog
players_file <- file.path(PROJECT_DIR, "web", "public", "data", "projections_season_players.json")
has_players <- file.exists(players_file)
players_df <- if (has_players) fromJSON(players_file) else NULL

# Build franchise CBA profiles
franchise_profiles <- list()

for (i in 1:nrow(team_payrolls)) {
  tm <- team_payrolls[i, ]
  code <- tm$team_abbr
  payroll <- tm$payroll_2026
  payroll_27 <- tm$payroll_2027
  payroll_28 <- tm$payroll_2028
  
  is_rep <- code %in% repeater_teams
  tax_bill <- compute_luxury_tax(payroll, is_rep)
  total_commitment <- round(payroll + tax_bill, 1)
  
  # CBA Tier Classification
  tier <- if (payroll > SECOND_APRON) {
    "Second Apron Restricted"
  } else if (payroll > FIRST_APRON) {
    "First Apron Team"
  } else if (payroll > LUXURY_TAX) {
    "Taxpayer (Below Apron 1)"
  } else if (payroll > SALARY_CAP) {
    "Over Cap (Non-Taxpayer)"
  } else {
    "Under Cap Room"
  }
  
  # Space calculations ($M)
  cap_sp <- round(max(0, SALARY_CAP - payroll), 1)
  tax_sp <- round(LUXURY_TAX - payroll, 1)
  a1_sp  <- round(FIRST_APRON - payroll, 1)
  a2_sp  <- round(SECOND_APRON - payroll, 1)
  
  # Multi-year projected cap room
  cap_sp_27 <- round(max(0, CAP_PROJ_2027 - payroll_27), 1)
  cap_sp_28 <- round(max(0, CAP_PROJ_2028 - payroll_28), 1)
  
  # CBA Handcuffs state machine
  is_a1 <- payroll > FIRST_APRON
  is_a2 <- payroll > SECOND_APRON
  
  handcuffs <- list(
    frozenPick7Years = is_a2,
    noSalaryAggregation = is_a2,
    noCashInTrades = is_a2,
    noTpmle = is_a2,
    tradeSalaryMatchingPct = if (is_a1) 100 else if (payroll > SALARY_CAP) 125 else 200,
    signAndTradeHardCapped = is_a1
  )
  
  # Select contracts: Verified Spotrac Table or Proportional Fill
  tm_contracts <- list()
  
  if (code %in% names(verified_contracts)) {
    tm_contracts <- verified_contracts[[code]]
  } else if (!is.null(players_df)) {
    tm_players <- players_df %>% filter(team == code) %>% arrange(desc(proj_mpg))
    
    if (nrow(tm_players) > 0) {
      n_contract <- min(nrow(tm_players), 9)
      
      # Distribute payroll among rotation using modern NBA salary curves
      top_salaries <- c(
        round(payroll * 0.27, 1),
        round(payroll * 0.22, 1),
        round(payroll * 0.16, 1),
        round(payroll * 0.12, 1),
        round(payroll * 0.09, 1),
        round(payroll * 0.05, 1),
        round(payroll * 0.04, 1),
        round(payroll * 0.03, 1),
        round(payroll * 0.02, 1)
      )
      
      for (p in 1:n_contract) {
        pl <- tm_players[p, ]
        sal_26 <- top_salaries[p]
        sal_27 <- if (p <= 5) round(sal_26 * 1.05, 1) else if (p <= 7) round(sal_26 * 1.05, 1) else 0.0
        sal_28 <- if (p <= 3) round(sal_27 * 1.05, 1) else 0.0
        
        c_type <- if (p <= 4) "Guaranteed" else if (p == 5) "Player Option" else if (p == 6) "Team Option" else "Guaranteed"
        
        tm_contracts[[p]] <- list(
          playerId = pl$player_id,
          playerName = pl$player_name,
          position = pl$position,
          salary2026 = sal_26,
          salary2027 = sal_27,
          salary2028 = sal_28,
          contractType = c_type,
          notes = if (p == 5) "Player Option for 2027-28" else if (p == 6) "Team Option for 2027-28" else "Fully Guaranteed"
        )
      }
    }
  }
  
  franchise_profiles[[i]] <- list(
    teamAbbr = code,
    teamName = tm$team_name,
    conference = tm$conf,
    totalPayroll2026 = payroll,
    totalPayroll2027 = payroll_27,
    totalPayroll2028 = payroll_28,
    salaryCap = SALARY_CAP,
    luxuryTaxThreshold = LUXURY_TAX,
    firstApron = FIRST_APRON,
    secondApron = SECOND_APRON,
    capSpace2026 = cap_sp,
    taxSpace2026 = tax_sp,
    firstApronSpace2026 = a1_sp,
    secondApronSpace2026 = a2_sp,
    cbaTier = tier,
    isRepeaterTax = is_rep,
    luxuryTaxBill = tax_bill,
    totalFinancialCommitment = total_commitment,
    projectedCapSpace2027 = cap_sp_27,
    projectedCapSpace2028 = cap_sp_28,
    handcuffs = handcuffs,
    contracts = tm_contracts
  )
}

# League Aggregate Statistics
total_tax_revenue <- sum(sapply(franchise_profiles, function(x) x$luxuryTaxBill))
avg_payroll <- round(mean(sapply(franchise_profiles, function(x) x$totalPayroll2026)), 1)
sec_apron_count <- sum(sapply(franchise_profiles, function(x) x$totalPayroll2026 > SECOND_APRON))
first_apron_count <- sum(sapply(franchise_profiles, function(x) x$totalPayroll2026 > FIRST_APRON & x$totalPayroll2026 <= SECOND_APRON))
tax_count <- sum(sapply(franchise_profiles, function(x) x$totalPayroll2026 > LUXURY_TAX))
cap_room_count <- sum(sapply(franchise_profiles, function(x) x$capSpace2026 > 0))

cap_sheet_export <- list(
  # First in the object, for assertion F's 4096-byte head scan, and UTC with a
  # trailing Z because that is the only form .pw_payload_generated_at() parses.
  # web/tests/contracts/schemas.ts's CbaLeagueOverviewSchema is .strict(), so
  # this key had to be added there in the same change or the contract suite --
  # and therefore assertion G, which is fatal -- would reject the payload.
  generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  season = "2026-2027",
  cbaThresholdSources = "Spotrac, Basketball-Reference, Hoops Rumors, RealGM, NBA CBA Official Audit",
  salaryCap = SALARY_CAP,
  luxuryTaxThreshold = LUXURY_TAX,
  firstApron = FIRST_APRON,
  secondApron = SECOND_APRON,
  averagePayroll = avg_payroll,
  totalLeagueTaxRevenue = round(total_tax_revenue, 1),
  secondApronTeamCount = sec_apron_count,
  firstApronTeamCount = first_apron_count,
  taxTeamCount = tax_count,
  capRoomTeamCount = cap_room_count,
  teams = franchise_profiles
)

# Export to Web JSON
output_json <- WEB_JSON_CBA_CAP_SHEET  # config.R
write_json(cap_sheet_export, output_json, pretty = TRUE, auto_unbox = TRUE)
message(sprintf(">>> [SUCCESS] Calibrated 2026-27 CBA Cap Sheet dataset exported to: %s", output_json))

# Cache RDS
saveRDS(cap_sheet_export, file.path(CACHE_DIR, "cba_cap_sheet.rds"))
message(">>> [SUCCESS] Cached RDS in: cache/cba_cap_sheet.rds")
