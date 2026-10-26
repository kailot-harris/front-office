# ==============================================================================
# build_offseason_dataset.R
# 2026-2027 NBA Season Offseason Moves, Transactions & Draft Analytics
# Path: c:/Users/kailo/kayceeslices/front-office/NBA Analytics/build_offseason_dataset.R
# ==============================================================================
#
# SOURCE-OF-TRUTH CONTRACT (issue #19)
# ------------------------------------------------------------------------------
# `web/public/data/offseason_transactions.json` is the canonical transaction
# catalog (183 records: 27 trades, 96 free-agent signings, 60 draft picks as of
# the 2026-27 build). This script READS and VALIDATES that catalog; it must never
# rebuild it from a smaller in-script seed.
#
# Team profiles are recomputed from the full catalog. `baseline_wins` is
# preserved from the existing offseason_teams.json and is updated only by
# tmp/sync_offseason_wins.R after projections change -- this builder never
# overwrites it from projections.

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

# Source global config (same idiom as build_cba_cap_dataset.R / playoff_simulator.R).
# Needed because this script names its input and output from config.R's WEB_JSON_*
# constants and is also run standalone, not only via run_full_pipeline.R's
# run_stage(), which sources config.R into the global environment first.
config_path <- if (file.exists("config.R")) "config.R" else "../config.R"
source(config_path)

cat(">>> [OFFSEASON BUILDER] Initializing 2026-2027 NBA Offseason Analytics Pipeline...\n")

teams_file         <- "web/public/data/projections_season_teams.json"
transactions_file  <- WEB_JSON_OFFSEASON_TRANSACTIONS  # config.R: an input catalog, not an output
teams_profile_file <- "web/public/data/offseason_teams.json"
out_dir            <- "web/public/data"

required_files <- c(teams_file, transactions_file, teams_profile_file)
missing_files <- required_files[!file.exists(required_files)]
if (length(missing_files) > 0) {
  stop(sprintf(
    "Missing required source-of-truth artifact(s): %s. Refusing to build team profiles from a partial catalog.",
    paste(missing_files, collapse = ", ")
  ))
}

teams_data        <- fromJSON(teams_file)
existing_profiles <- fromJSON(teams_profile_file, simplifyVector = FALSE)

cat(sprintf(">>> Loaded %d team projections and %d existing team profiles.\n",
            nrow(teams_data), length(existing_profiles)))

# ------------------------------------------------------------------------------
# 1. Load & Validate the Canonical Transaction Catalog
# ------------------------------------------------------------------------------
# Issue #19: this file used to hold a 30-record curated seed that was written
# over the 183-record public catalog. The catalog is now an input, not an output.
transactions <- fromJSON(transactions_file, simplifyVector = FALSE)

CATALOG_MIN_TRANSACTIONS <- 183L
CATALOG_DRAFT_PICKS      <- 60L

tx_field <- function(tx, field) {
  value <- tx[[field]]
  if (is.null(value) || length(value) == 0) return(NA_character_)
  value <- as.character(value)
  if (length(value) == 0 || is.na(value[[1]]) || !nzchar(value[[1]])) return(NA_character_)
  value[[1]]
}

tx_ids   <- vapply(transactions, tx_field, character(1), field = "id")
tx_types <- vapply(transactions, tx_field, character(1), field = "type")

if (length(transactions) < CATALOG_MIN_TRANSACTIONS) {
  stop(sprintf(
    "offseason_transactions.json has %d records; the canonical catalog requires at least %d. Refusing to write a reduced catalog.",
    length(transactions), CATALOG_MIN_TRANSACTIONS
  ))
}
if (anyNA(tx_ids) || anyDuplicated(tx_ids)) {
  stop("offseason_transactions.json contains a missing or duplicate transaction id.")
}
if (anyNA(tx_types) || !all(tx_types %in% c("trade", "free_agency", "draft"))) {
  stop("offseason_transactions.json contains an unknown or missing transaction type.")
}

draft_records <- transactions[tx_types == "draft"]
if (length(draft_records) != CATALOG_DRAFT_PICKS) {
  stop(sprintf(
    "offseason_transactions.json has %d draft records; expected exactly %d.",
    length(draft_records), CATALOG_DRAFT_PICKS
  ))
}

draft_pick_numbers <- vapply(
  draft_records,
  function(tx) as.integer(tx[["draft_pick"]][["pick"]]),
  integer(1)
)
if (!identical(sort(draft_pick_numbers), seq_len(CATALOG_DRAFT_PICKS))) {
  stop("offseason_transactions.json does not contain exactly one draft record for every pick 1..60.")
}

required_ids <- c(
  "tx-2026-giannis-antetokounmpo",
  "tx-2026-lebron-james",
  "dr-2026-pick-1-aj-dybantsa",
  "dr-2026-pick-60-malique-lewis"
)
missing_ids <- setdiff(required_ids, tx_ids)
if (length(missing_ids) > 0) {
  stop(sprintf("offseason_transactions.json is missing known transaction id(s): %s",
               paste(missing_ids, collapse = ", ")))
}

cat(sprintf(">>> Validated canonical catalog: %d transactions (%d trade, %d free agency, %d draft).\n",
            length(transactions),
            sum(tx_types == "trade"),
            sum(tx_types == "free_agency"),
            length(draft_records)))

# ------------------------------------------------------------------------------
# 2. 2026-2027 Rookie Draft Class Deep Dive
# ------------------------------------------------------------------------------
# The full 60-pick 2026-27 draft class. Kept as a compact table because the
# public artifact is one record per pick with array-valued strengths/swing
# skills; the expansion below preserves that shape while keeping the class
# readable and auditable here. `trade_note` is NA when the pick was not traded.
draft_class_raw <- tribble(
  ~pick, ~round, ~player_name, ~original_team, ~team, ~position,
  ~school_or_club, ~height, ~archetype, ~projected_bpm_prior, ~projected_mpg,
  ~upside_tier, ~trade_note, ~strengths, ~swing_skills, ~comp,
  1, 1, "AJ Dybantsa", "WAS", "WAS", "SF", "BYU", "6'9\"", "Generational Three-Level Alpha Wing", 0.8, 29.5, "Franchise Pillar", NA_character_, "Elite three-level scoring package|Downhill vertical burst and rim finishing|7'0 wingspan switchability", "Playmaking feel under traps|Off-ball defensive motor", "Tracy McGrady / Jayson Tatum",
  2, 1, "Darryn Peterson", "UTA", "UTA", "SG/PG", "KU", "6'5\"", "Complete Modern Combo Guard Virtuoso", 0.6, 28.5, "Franchise Pillar", NA_character_, "Off-the-dribble mid-range and 3PT shot creation|Fluid pick-and-roll pace|On-ball ball pressure", "Finishing through rim deterrence|Shot selection discipline", "Devin Booker / Brandon Roy",
  3, 1, "Cameron Boozer", "MEM", "MEM", "PF/C", "DUKE", "6'9\"", "High-Feel Point Forward and Paint Enforcer", 0.5, 28, "Franchise Pillar", NA_character_, "Pro-ready physical power frame|Phenomenal high-post passing|Tenacious two-way rebounding", "Lateral foot speed on switches|Rim protection vertical pop", "Paolo Banchero / Kevin Love",
  4, 1, "Caleb Wilson", "CHI", "CHI", "SF/PF", "UNC", "6'9\"", "High-Flying Slashing Point Forward", -0.2, 26, "Franchise Pillar", NA_character_, "Explosive vertical bounce|Switchable perimeter defense 2-through-4|High motor on defensive glass", "Spot-up 3PT consistency|Pull-up mid-range touch", "Aaron Gordon / Scottie Barnes",
  5, 1, "Keaton Wagler", "IND", "DET", "SG/PG", "ILL", "6'6\"", "Dynamic Scoring Guard and Playmaker", -0.4, 25, "Core Starter", "via IND", "Shot creation off the dribble|Pick-and-roll passing vision|Aggressive rim attacks", "Perimeter 3PT range|Point-of-attack discipline", "Tyler Herro / Austin Reaves",
  6, 1, "Mikel Brown Jr.", "BKN", "BKN", "PG", "LOU", "6'3\"", "Dazzling Pull-Up Shotmaker and Playmaker", -0.5, 26, "Franchise Pillar", NA_character_, "Crossover separation and shake|Deep pull-up 3PT range|Creative pick-and-roll vision", "Finishing through contact|Screen navigation", "Darius Garland / Kyrie Irving",
  7, 1, "Darius Acuff Jr.", "SAC", "SAC", "PG", "ARK", "6'3\"", "Electric Downhill Lead Scorer", -0.5, 25, "Core Starter", NA_character_, "Step-backs and hesitation drives|Paint finishing with either hand|Assist creation on kick-outs", "Defensive consistency|Turnover rate against traps", "Collin Sexton / Tyrese Maxey",
  8, 1, "Kingston Flemings", "NOP", "ATL", "PG", "HOU", "6'3\"", "Hyper-Speed Floor General and Pest", -0.6, 24.5, "Core Starter", "via NO", "Open-court transition speed|Blow-by first step|Full-court ball pressure", "Half-court 3PT mechanics|Floaters against drop bigs", "De'Aaron Fox / Dennis Schroder",
  9, 1, "Morez Johnson Jr.", "DAL", "DAL", "PF/C", "MICH", "6'9\"", "Tenacious Interior Finisher and Glass Cleaner", -0.7, 23.5, "Core Starter", NA_character_, "Physical box outs and offensive glass putbacks|Rim-running vertical pop|Positional paint defense", "Free throw stroke|Mid-range spacing", "Isaiah Stewart / Wendell Carter Jr.",
  10, 1, "Brayden Burries", "MIL", "MIL", "SG", "ARIZ", "6'5\"", "Physical Two-Way Scoring Wing", -0.6, 24, "Core Starter", NA_character_, "Stout frame powering through contact|Pull-up shooting off rhythm|Switchable backcourt defense", "Catch-and-shoot consistency|Playmaking out of double teams", "Josh Hart / Desmond Bane",
  11, 1, "Yaxel Lendeborg", "GSW", "GSW", "PF", "MICH", "6'9\"", "High-IQ Versatile Forward and Playmaker", -0.8, 22, "Core Starter", NA_character_, "High-post passing and DHOs|Active defensive hands|Mid-range face-up game", "3PT volume|Lateral speed against guards", "Kyle Anderson / Boris Diaw",
  12, 1, "Aday Mara", "LAC", "OKC", "C", "MICH", "7'3\"", "Towering Rim Protector and High-Post Hub", -0.7, 21, "Core Starter", "via LAC", "7'7 wingspan rim deterrence|Interior passing over defenses|Soft touch at basket", "Switch speed in space|Stamina over 82 games", "Brook Lopez / Marc Gasol",
  13, 1, "Nate Ament", "MIA", "MIL", "SF/PF", "TENN", "6'9\"", "Lanky Pure Shooter and Fluid Wing", -0.6, 24, "Core Starter", "Traded to MIL", "High-release catch-and-shoot 3s|Elevation over contests|Secondary rim contests", "Frame mass|Crowd traffic finishes", "Michael Porter Jr. / Trey Murphy III",
  14, 1, "Hannes Steinbach", "CHA", "CHA", "PF/C", "WASH", "6'10\"", "Modern European Stretch Big", -0.9, 20, "Specialist", NA_character_, "Pick-and-pop 3-pointers|Disciplined positioning and box outs|Short roll passing", "Vertical rim protection|Physicality against bruisers", "Daniel Theis / Moritz Wagner",
  15, 1, "Dailyn Swain", "POR", "CHI", "SG/SF", "TEX", "6'7\"", "Long Two-Way Disruptive Wing", -0.9, 20.5, "Core Starter", "via POR", "Length and lateral footwork on ball|Transition lane running|Deflections and steals", "Half-court form|Self-creation handle", "Mikal Bridges / Herb Jones",
  16, 1, "Bennett Stirtz", "MEM", "OKC", "PG", "IOWA", "6'4\"", "Crafty Playmaking Floor General", -0.9, 19.5, "Specialist", "Traded to OKC", "Floor awareness and PnR timing|Spot-up shooting efficiency|Poise vs press", "Vertical burst at rim|Point-of-attack containment", "Tyus Jones / T.J. McConnell",
  17, 1, "Ebuka Okorie", "OKC", "DET", "SG", "STAN", "6'5\"", "Explosive 3-and-D Backcourt Weapon", -1, 19, "Specialist", "Traded to DET via MEM", "Closeout recovery speed|Corner 3PT accuracy|Defensive energy", "Dribble drive creation|Pull-up consistency", "Kentavious Caldwell-Pope / Gary Harris",
  18, 1, "Christian Anderson Jr.", "ORL", "CHA", "PG", "TTU", "6'2\"", "Sharpshooting Microwave Combo Guard", -1, 18.5, "Specialist", "from ORL via PHX", "Deep pull-up range on breaks|Quick-trigger release off handoffs|Game management", "Defensive size against NBA guards|Finishing over length", "Seth Curry / Patty Mills",
  19, 1, "Allen Graves", "TOR", "TOR", "PF/SF", "SCU", "6'8\"", "Versatile High-Motor Hybrid Forward", -1.1, 18, "Developmental", NA_character_, "Non-stop motor on both ends|Multi-positional switchability|Offensive rebounding", "Spot-up 3PT stroke|Off-the-bounce creation", "Kenrich Williams / Jae Crowder",
  20, 1, "Jayden Quaintance", "ATL", "SAS", "PF/C", "UK", "6'10\"", "Hyper-Athletic Rim Wrecker and Lob Anchor", -0.6, 22.5, "Core Starter", "via ATL", "7'4 wingspan explosive vertical bounce|Fierce rim protection (2.6 BPG)|PnR screen-and-dive burst", "Mid-range touch|Free-throw discipline", "Onyeka Okongwu / Robert Williams III",
  21, 1, "Karim Lopez", "DET", "MEM", "SF/PF", "Mexico", "6'8\"", "Fluid International Scoring Wing", -1, 18, "Developmental", "Traded to MEM", "Smooth catch-and-shoot stroke|Positional size and awareness|Active cutting", "Functional strength vs wings|On-ball separation", "Bojan Bogdanovic / Deni Avdija",
  22, 1, "Labaron Philon Jr.", "HOU", "PHI", "PG", "ALA", "6'4\"", "Slick Point-of-Attack Floor General", -1, 18, "Specialist", "from HOU via OKC", "Shifty handle breaking down drops|High IQ unselfish distribution|Pesky on-ball stance", "Pull-up 3PT efficiency|Finishing through traffic", "Monte Morris / De'Anthony Melton",
  23, 1, "Zuby Ejiofor", "CLE", "ATL", "PF/C", "SJU", "6'9\"", "High-Motor Paint Battler and Rebounder", -1.1, 17.5, "Specialist", "via CLE", "Offensive putbacks and rim dives|Physical box-outs and toughness|Shot blocking recovery", "Perimeter shooting skill set|Free throw mechanics", "Precious Achiuwa / Kenneth Faried",
  24, 1, "Cameron Carr", "NYK", "LAL", "SG", "BAY", "6'5\"", "Silky Off-Screen Sharpshooter and Athlete", -0.9, 18.5, "Specialist", "Traded to LAL", "Textbook perimeter shooting stroke (39% 3PT)|Explosive leaping on back-cuts|Length on perimeter defense", "Playmaking under ball pressure|Frame bulk", "Malik Monk / Luke Kennard",
  25, 1, "Sergio De Larrea", "LAL", "DAL", "PG/SG", "Spain", "6'6\"", "Jumbo Spanish Point Guard and Maestro", -1, 18, "Developmental", "Traded to DAL via NYK", "6'6 tall playmaker seeing over defenses|European passing on skip passes|Poised pace and speed control", "Lateral foot speed vs speedy guards|3PT pull-up consistency", "Ricky Rubio / Tomas Satoransky",
  26, 1, "Tarris Reed Jr.", "DEN", "SAS", "C", "CONN", "6'10\"", "Bruising Interior Anchor and Post Defender", -1.1, 17, "Developmental", "Traded to SA", "Imposing frame sealing paint lanes|Fierce rim protection and contesting|Bruising screens freeing ballhandlers", "Floor spacing range|Foul trouble prevention", "Andre Drummond / Isaiah Stewart",
  27, 1, "Chris Cenac Jr.", "BOS", "BOS", "PF/C", "HOU", "6'10\"", "Two-Way Stretch Unicorn and Rim Eraser", -0.5, 24.5, "Franchise Pillar", NA_character_, "7'3 wingspan rim protection (2.4 BPG)|38.5% pick-and-pop 3-point release|Open-court handling", "Upper body strength vs bruisers|Low-post footwork", "Chet Holmgren / Jaren Jackson Jr.",
  28, 1, "Joshua Jefferson", "MIN", "BKN", "SF/PF", "ISU", "6'8\"", "Tough Multi-Positional Glue Forward", -1.1, 17.5, "Developmental", "Traded to BKN", "Relentless hustle and loose ball dives|Positional defense on forwards|High-low passing reads", "Jump shooting mechanics|Shot creation", "Grant Williams / Dean Wade",
  29, 1, "Alex Karaban", "CLE", "SAC", "SF/PF", "CONN", "6'8\"", "Championship-Pedigree High-IQ Stretch Wing", -0.7, 21, "Core Starter", "Traded to SAC", "Two-time NCAA Champion basketball IQ|Deadly 39.5% catch-and-shoot 3s|Flawless cutting timing", "Foot speed vs elite isolation wings|Self-creation burst", "Georges Niang / Harrison Barnes",
  30, 1, "Koa Peat", "DAL", "PHX", "PF/SF", "ARIZ", "6'8\"", "Physical Bully-Ball Playmaker and Rebounder", -0.2, 26, "Franchise Pillar", "Traded to PHX via NYK", "Brute-force interior rim attacks|Open-court transition pushing|Relentless physical motor on boards", "Perimeter 3PT consistency|Free throw mechanics", "Julius Randle / Ron Artest",
  31, 2, "Bruce Thornton", "NYK", "HOU", "PG", "OSU", "6'2\"", "Stocky Pick-and-Roll Lead Guard", -1.2, 16.5, "Specialist", "Traded to HOU", "Stout broad frame absorbing contact|Low turnover assist-to-turnover ratio|Pull-up mid-range rhythm", "Perimeter burst vs athletic guards|Defensive switchability", "Jalen Brunson (collegiate style) / Tyus Jones",
  32, 2, "Richie Saunders", "MEM", "MEM", "SG", "BYU", "6'5\"", "Relentless High-Motor Energy Wing", -1.3, 15.5, "Developmental", "from IND via MIL", "Fearless loose ball dives and crashing offensive glass|Spot-up corner 3PT accuracy|Full-court hustle", "Self-creation off live dribble|Lateral footwork on isolations", "Christian Braun / Alex Caruso",
  33, 2, "Isaiah Evans", "BKN", "MIN", "SG/SF", "DUKE", "6'6\"", "Lanky Shotmaking Scoring Guard", -1.1, 17, "Specialist", "Traded to MIN", "Tough contested shotmaking over length|Quick catch-and-shoot release|Confident microwave scoring", "Frame mass and functional strength|Point-of-attack screen navigation", "Bones Hyland / Kevin Martin",
  34, 2, "Meleek Thomas", "SAC", "CLE", "SG", "ARK", "6'4\"", "Three-Level Microwave Bucket Getter", -0.9, 18.5, "Core Starter", "Traded to CLE", "Fearless isolation scoring instincts|Silky step-back 3-pointer|Clutch gene and transition speed", "Shot selection patience|Defensive focus across 82 games", "Jamal Crawford / Lou Williams",
  35, 2, "Trevon Brazile", "SAS", "DEN", "PF/C", "ARK", "6'10\"", "Pogo-Stick Rim Runner and Lob Threat", -1.3, 15, "Developmental", "Traded to DEN", "40-inch vertical explosive lob catching|Weak-side shot swatting (1.8 BPG)|Corner 3-point touch", "Interior physical post defense|Consistent motor", "Kai Jones / Jaxson Hayes",
  36, 2, "Baba Miller", "IND", "LAC", "SF/PF", "CIN", "6'11\"", "Intriguing Spanish Point Forward Unicorn", -1.2, 16, "Developmental", "from MEM via ATL and UTA", "6'11 perimeter ball-handling and fluid stride|Transition grab-and-go vision|Versatile defensive length", "Aggressiveness attacking rim|Consistent jump shot release", "Lamar Odom / Nicolas Batum",
  37, 2, "Ryan Conwell", "OKC", "MIA", "SG", "LOU", "6'4\"", "Physical Shotmaker and Tough Defender", -1.3, 15.5, "Developmental", "Traded to MIA", "Burly guard frame walling off drives|Knockdown spot-up 3-point marksmanship|High basketball IQ", "Separation burst on isolations|Finishing over 7-footers", "Desmond Bane (rookie year) / Gary Trent Jr.",
  38, 2, "Braden Smith", "CHI", "IND", "PG", "PUR", "6'0\"", "Savant NCAA Floor General & Distributor", -1, 17.5, "Specialist", "Traded to IND", "Elite collegiate assist rate (7.5 APG)|Surgical pick-and-roll pocket passing|Knockdown 42% 3PT shooting", "Size and physical stature on defense|Finishing at NBA rim over length", "T.J. McConnell / Payton Pritchard",
  39, 2, "Jack Kayil", "HOU", "NYK", "PG", "Germany", "6'3\"", "Poised German Playmaker and Slasher", -1.4, 14.5, "Developmental", "Traded to NYK", "European tournament pedigree and pace|Low-error game management|Change-of-pace paint penetration", "NBA 3PT distance volume|Physical containment vs elite athletes", "Dennis Schroder / Vasilije Micic",
  40, 2, "Dillon Mitchell", "BOS", "BOS", "SF/PF", "SJU", "6'8\"", "Elite Hyper-Athletic Wing Stopper", -1.1, 16.5, "Specialist", "from MIL via ORL", "Explosive second bounce on boards and putbacks|Suffocating perimeter on-ball defense 1-through-4|Fast break rim runner", "Jump shooting range outside 8 feet|Free throws", "Derrick Jones Jr. / Jarred Vanderbilt",
  41, 2, "Otega Oweh", "MIA", "OKC", "SG", "UK", "6'5\"", "Relentless Downhill Slashing Guard", -1.2, 15.5, "Specialist", "Traded to OKC", "Brute-force paint attacks and drawing fouls|Tenacious point-of-attack ball pressure|Transition athleticism", "Spot-up 3PT stroke consistency|Mid-range pull-up", "Luguentz Dort / Bruce Brown",
  42, 2, "Ja'Kobi Gillespie", "SAS", "SAS", "PG", "TENN", "6'1\"", "Speedy Two-Way Playmaker and Thief", -1.3, 15, "Developmental", "from POR via NO", "Rapid ball pressure leading NCAA in steals|Electric quickness in transition|Savvy pocket passing", "Finishing against drop bigs|Perimeter shooting volume", "Jose Alvarado / Jevon Carter",
  43, 2, "Tyler Bilodeau", "BKN", "BKN", "PF", "UCLA", "6'9\"", "Skilled Face-Up Post Scorer and Spacer", -1.3, 15, "Developmental", "from LAC via HOU", "Clean shooting mechanics out to 3PT arc|Polished post footwork and hook shot|Physical defensive box outs", "Foot speed defending perimeter space|Rim protection bounce", "Mike Muscala / Dean Wade",
  44, 2, "Maliq Brown", "SAS", "SAS", "PF/C", "DUKE", "6'8\"", "Defensive Analytics Darling & Steals Anchor", -1.1, 16.5, "Specialist", "from MIA via IND", "Historic steal and deflection rates for a big|Switchability 1-through-5 across screens|Short roll lob connection", "Perimeter shooting capability|Scoring creation", "Draymond Green (defensive role) / Larry Nance Jr.",
  45, 2, "Emanuel Sharp", "SAC", "SAC", "SG", "HOU", "6'3\"", "Burly Kelvin Sampson Culture Marksman", -1.2, 15.5, "Specialist", "from CHA via SA, ATL and NYK", "Stout physical frame walling off drives|Knockdown clutch 3-point marksmanship|Fierce offensive rebounding from guard spot", "Explosive vertical athleticism|Mid-range creation", "Marcus Smart / De'Anthony Melton",
  46, 2, "Felix Okpara", "DET", "WAS", "C", "TENN", "6'11\"", "Imposing Rim Protector & Lob Finisher", -1.3, 14.5, "Developmental", "Traded to WSH", "7'3 wingspan elite shot-blocking timing|Vertical lob catch radius|High-energy paint deterrence", "Offensive post moves|Foul discipline", "Bismack Biyombo / Udoka Azubuike",
  47, 2, "Tyler Nickel", "PHX", "NYK", "SF", "VAN", "6'7\"", "Laser-Focused Perimeter Marksman", -1.3, 14.5, "Specialist", "Traded to NYK", "Quick-release 40% 3PT shooting stroke|Deep range on relocation triples|Competitive toughness", "Foot speed against quick wings|Dribble penetration", "Sam Hauser / Doug McDermott",
  48, 2, "Tobi Lawal", "DAL", "DAL", "PF", "VT", "6'8\"", "High-Flying Vertical Athlete & Cutter", -1.4, 14, "Developmental", "from PHX via WSH", "Outrageous vertical bounce and poster dunks|Fast-break rim runner|Active weak-side shot contests", "Perimeter shooting consistency|Defensive recognition", "Derrick Jones Jr. / Kenyon Martin Jr.",
  49, 2, "Bryce Hopkins", "DEN", "DEN", "SF/PF", "SJU", "6'7\"", "Physical Bully-Ball Forward & Slasher", -1.2, 15.5, "Developmental", "from ATL via BKN and GS", "Brute strength drawing fouls on drives|Physical mid-post mismatch punishing|Tenacious rebounding", "Consistent 3PT range|Durability following knee recovery", "Dillon Brooks / Eric Paschall",
  50, 2, "Jaden Bradley", "TOR", "TOR", "PG", "ARIZ", "6'3\"", "Poised Defensive Point Guard & Slasher", -1.1, 16, "Specialist", NA_character_, "Tough point-of-attack screen navigation|Pick-and-roll decision making|Finishing over contact", "3PT pull-up consistency|Perimeter shooting volume", "Ayo Dosunmu / Kris Dunn",
  51, 2, "Izaiyah Nelson", "WAS", "ORL", "PF/C", "USF", "6'10\"", "Athletic Shot Blocker & Rebounder", -1.4, 13.5, "Developmental", "Traded to ORL", "Top-tier block percentage (2.5 BPG)|Agile second jump on offensive rebounds|Rim running sprint", "Shooting range outside paint|Screen fundamentals", "Christian Koloko / Damian Jones",
  52, 2, "Henri Veesaar", "DET", "ATL", "C", "UNC", "7'0\"", "Skilled European 7-Foot Stretch Big", -1.3, 14.5, "Developmental", "Traded to ATL", "Smooth pick-and-pop 3PT touch|High basketball IQ and passing out of high post|Solid vertical contest timing", "Physical core strength in paint|Foul trouble discipline", "Kelly Olynyk / Moritz Wagner",
  53, 2, "Ugonna Onyenso", "HOU", "DET", "C", "UVA", "7'0\"", "Intimidating Shot Swatter & Rim Runner", -1.3, 14, "Developmental", "Traded to DET via NYK", "7'5 wingspan rim deterrence|Vertical lob catch radius|Paint recovery speed", "Offensive touch and screen firmness|Foul discipline", "Bismack Biyombo / Mitchell Robinson",
  54, 2, "Lajae Jones", "GSW", "GSW", "SG", "FSU", "6'7\"", "Long Athletic 3-and-D Wing", -1.4, 13.5, "Developmental", "from LAL via TOR, MIA and CLE", "Length and recovery stride on perimeter|Catch-and-shoot corner triples|Transition lane running", "Ball handling vs pressure|Free throw mechanics", "Moses Moody / Josh Minott",
  55, 2, "Nick Martinelli", "NYK", "LAC", "SF", "NU", "6'7\"", "Crafty Inside-Out Scoring Wing", -1.3, 14.5, "Developmental", "Traded to LAC via HOU", "Elite floater touch and paint maneuvering|Unorthodox cutting angles|High basketball feel", "3PT volume from NBA line|Lateral quickness on defense", "Sam Dekker / Jake LaRavia",
  56, 2, "Vsevolod Ishchenko", "CHI", "DAL", "PG/SG", "Russia", "6'4\"", "Dynamic International Lead Guard", -1.4, 13.5, "Developmental", "Traded to DAL via LAL", "Fast-break playmaking instincts|Crafty finishing with either hand|Aggressive defensive anticipation", "Perimeter shooting consistency|Adjustment to NBA physicality", "Aleksej Pokusevski (guard vision) / Milos Teodosic",
  57, 2, "Narcisse Ngoy", "ATL", "LAC", "SF/PF", "France", "6'9\"", "Raw French High-Ceiling Forward", -1.5, 13, "Developmental", "Traded to LAC", "7'2 wingspan and springy athletic frame|Aggressive rim attacks in transition|Defensive switch potential", "Half-court shooting fundamentals|Handle and decision-making", "Ousmane Dieng / Sidy Cissoko",
  58, 2, "Jaron Pierre Jr.", "NOP", "NOP", "SG", "SMU", "6'5\"", "Shot-Creating Microwave Guard", -1.4, 13.5, "Developmental", "from DET via NYK, BKN, PHX, ORL and LAC", "Confident off-the-dribble 3PT scoring|Quick first step on drives|Active hands on loose balls", "Shot selection in structured offense|Defensive discipline", "Jordan Nwora / Terence Davis",
  59, 2, "Trey Kaufman-Renn", "MIN", "MIN", "PF", "PUR", "6'9\"", "Physical Low-Post Technician and Battler", -1.3, 14, "Developmental", "from SA via IND", "Old-school low-post footwork and spin moves|Tenacious offensive rebounding|Physical screen setting", "Perimeter 3PT shooting range|Lateral speed on perimeter switches", "Grant Williams / Drew Timme",
  60, 2, "Malique Lewis", "WAS", "MIL", "SF/PF", "Trinidad & Tobago", "6'8\"", "International G-League Ignite Wing Prospect", -1.5, 12.5, "Developmental", "Traded to MIL via ORL", "Long athletic frame and transition running|Catch-and-shoot 3PT potential|Weak-side shot contesting", "Half-court playmaking feel|Functional strength", "Justin Anderson / Dalano Banton",
)

# Pipe-delimited strengths/swing skills become the arrays the frontend expects.
# NA trade notes are retained so jsonlite emits an explicit null for untraded picks.
draft_prospects <- lapply(seq_len(nrow(draft_class_raw)), function(i) {
  row <- draft_class_raw[i, ]
  list(
    pick = row$pick,
    round = row$round,
    player_name = row$player_name,
    original_team = row$original_team,
    team = row$team,
    position = row$position,
    school_or_club = row$school_or_club,
    height = row$height,
    archetype = row$archetype,
    projected_bpm_prior = row$projected_bpm_prior,
    projected_mpg = row$projected_mpg,
    upside_tier = row$upside_tier,
    trade_note = row$trade_note,
    strengths = strsplit(row$strengths, "|", fixed = TRUE)[[1]],
    swing_skills = strsplit(row$swing_skills, "|", fixed = TRUE)[[1]],
    comp = row$comp
  )
})

# A complete class is 60 picks: 30 in each round, numbered 1..60.
stopifnot(
  length(draft_prospects) == 60L,
  identical(as.integer(vapply(draft_prospects, `[[`, numeric(1), "pick")), 1:60),
  sum(vapply(draft_prospects, `[[`, numeric(1), "round") == 1) == 30
)

# ------------------------------------------------------------------------------
# 3. Compute 30-Team 2026-2027 Offseason Impact Profiles from the Full Catalog
# ------------------------------------------------------------------------------
# JS Math.round semantics: floor(x + 0.5), including for negative values.
js_round <- function(x) floor(x + 0.5)
round1 <- function(x) js_round(x * 10) / 10

tx_to_team   <- vapply(transactions, tx_field, character(1), field = "to_team")
tx_from_team <- vapply(transactions, tx_field, character(1), field = "from_team")
tx_bpm <- vapply(transactions, function(tx) {
  bpm <- tx[["player_bpm"]]
  if (is.null(bpm) || length(bpm) == 0 || is.na(bpm)) 0 else as.numeric(bpm)
}, numeric(1))

existing_by_team <- setNames(
  existing_profiles,
  vapply(existing_profiles, tx_field, character(1), field = "team")
)

grade_for_net_wins <- function(net_wins) {
  if (net_wins >= 5.0) "A+" else
  if (net_wins >= 3.5) "A" else
  if (net_wins >= 2.0) "A-" else
  if (net_wins >= 1.0) "B+" else
  if (net_wins >= 0.0) "B" else
  if (net_wins >= -1.0) "B-" else
  if (net_wins >= -2.5) "C+" else
  if (net_wins >= -4.0) "C" else
  if (net_wins >= -5.5) "C-" else
  if (net_wins >= -7.0) "D+" else "D"
}

# Legacy fallbacks, used only if an existing profile is missing a field.
legacy_continuity <- function(n_moves) {
  round(pmax(0.48, pmin(0.92, 0.82 - (n_moves * 0.048))), 3)
}
legacy_posture <- function(net_wins, base_wins) {
  if (net_wins >= 3.0 && base_wins >= 45) "Win-Now Contender" else
  if (net_wins >= 1.0) "Aggressive Retool" else
  if (net_wins <= -2.0) "Asset Accumulation / Rebuild" else "Cap Preservation / Steady"
}

team_profiles <- lapply(seq_len(nrow(teams_data)), function(i) {
  tm <- teams_data[i, ]
  abbr <- tm$team
  existing <- existing_by_team[[abbr]]

  is_veteran <- tx_types != "draft"
  add_idx <- which(is_veteran & !is.na(tx_to_team) & tx_to_team == abbr)
  dep_idx <- which(is_veteran & !is.na(tx_from_team) & tx_from_team == abbr)

  adds <- transactions[add_idx]
  deps <- transactions[dep_idx]

  net_bpm <- round1(sum(tx_bpm[add_idx]) - sum(tx_bpm[dep_idx]))
  net_wins_delta <- round1(net_bpm * 1.35)

  baseline_wins <- if (!is.null(existing) && !is.null(existing[["baseline_wins"]])) {
    as.numeric(existing[["baseline_wins"]])
  } else {
    warning(sprintf("No existing baseline_wins for %s; falling back to projections.", abbr))
    as.numeric(tm$proj_wins)
  }

  continuity <- if (!is.null(existing) && !is.null(existing[["roster_continuity_pct"]])) {
    as.numeric(existing[["roster_continuity_pct"]])
  } else {
    legacy_continuity(length(adds) + length(deps))
  }

  posture <- if (!is.null(existing) && !is.null(existing[["strategic_posture"]])) {
    as.character(existing[["strategic_posture"]])
  } else {
    legacy_posture(net_wins_delta, baseline_wins)
  }

  verdict <- if (!is.null(existing) && !is.null(existing[["offseason_verdict"]]) &&
                 nzchar(as.character(existing[["offseason_verdict"]]))) {
    as.character(existing[["offseason_verdict"]])
  } else {
    sprintf("Preserved high roster stability (%.1f%% continuity) with targeted depth additions and rookie development.",
            continuity * 100)
  }

  adds_summary <- lapply(adds, function(tx) list(
    name = tx$player_name,
    type = tx$type,
    bpm = as.numeric(tx$player_bpm),
    pos = tx$position
  ))
  deps_summary <- lapply(deps, function(tx) list(
    name = tx$player_name,
    type = tx$type,
    bpm = as.numeric(tx$player_bpm),
    pos = tx$position
  ))

  team_draft_picks <- Filter(
    function(p) identical(as.character(p$team), as.character(abbr)),
    draft_prospects
  )
  drafts_summary <- lapply(team_draft_picks, function(p) list(
    name = p$player_name,
    pick = p$pick,
    school = paste0(
      p$school_or_club,
      if (!is.null(p$trade_note) && length(p$trade_note) > 0 &&
          !is.na(p$trade_note) && nzchar(as.character(p$trade_note))) {
        sprintf(" [%s]", p$trade_note)
      } else {
        ""
      }
    ),
    archetype = p$archetype
  ))

  list(
    team = abbr,
    team_name = tm$team_name,
    conference = tm$conference,
    division = tm$division,
    baseline_wins = baseline_wins,
    projected_wins_with_moves = round1(baseline_wins + net_wins_delta),
    net_wins_change = net_wins_delta,
    net_bpm_added = net_bpm,
    roster_continuity_pct = continuity,
    grade = grade_for_net_wins(net_wins_delta),
    strategic_posture = posture,
    additions = adds_summary,
    departures = deps_summary,
    draft_picks = drafts_summary,
    offseason_verdict = verdict
  )
})

# Sort by net wins, breaking ties by the existing profile order so a rerun is
# idempotent (and produces no diff when the catalog has not changed).
profile_net_wins <- vapply(team_profiles, function(x) x$net_wins_change, numeric(1))
profile_tie_rank <- match(
  vapply(team_profiles, function(x) x$team, character(1)),
  names(existing_by_team)
)
profile_tie_rank[is.na(profile_tie_rank)] <- length(existing_by_team) + seq_len(sum(is.na(profile_tie_rank)))
team_profiles <- team_profiles[order(-profile_net_wins, profile_tie_rank)]

profile_teams <- vapply(team_profiles, function(x) x$team, character(1))
if (!identical(sort(profile_teams), sort(teams_data$team))) {
  stop("Team profile build did not produce exactly one profile for all 30 teams.")
}
if (any(vapply(team_profiles, function(x) {
  abs(x$baseline_wins + x$net_wins_change - x$projected_wins_with_moves) > 0.051
}, logical(1)))) {
  stop("Team profile invariant failed: baseline_wins + net_wins_change != projected_wins_with_moves.")
}

# ------------------------------------------------------------------------------
# 4. Output JSON Artifacts to web/public/data/
# ------------------------------------------------------------------------------
# offseason_transactions.json is intentionally NOT written here: it is the
# validated source of truth loaded in section 1. Only derived artifacts are
# emitted, so a builder run cannot wholesale replace the catalog.
if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

teams_json <- file.path(out_dir, "offseason_teams.json")
write_json(team_profiles, teams_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d 2026-2027 team offseason profiles to: %s\n",
            length(team_profiles), teams_json))

draft_json <- file.path(out_dir, "offseason_draft.json")
write_json(draft_prospects, draft_json, pretty = TRUE, auto_unbox = TRUE)
cat(sprintf(">>> [SUCCESS] Wrote %d 2026-2027 draft prospect models to: %s\n",
            length(draft_prospects), draft_json))

cat(sprintf(">>> [CONTRACT] Catalog left untouched: %d transactions (%d draft picks).\n",
            length(transactions), length(draft_records)))
cat(">>> [OFFSEASON BUILDER] 2026-2027 Offseason Analytics Dataset Build Complete!\n")
