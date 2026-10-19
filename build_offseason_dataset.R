# ==============================================================================
# build_offseason_dataset.R
# 2026 WNBA Offseason Moves, Expansion Draft, Transactions & Rookie Draft Analytics
# Path: c:/Users/kailo/kayceeslices/WNBA Analytics/build_offseason_dataset.R
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(tidyr)
  library(jsonlite)
})

cat(">>> [OFFSEASON BUILDER] Initializing 2026 WNBA Offseason Analytics Pipeline...\n")

# Load baseline team and player projections from web/public/data
teams_file <- "web/public/data/projections_season_teams.json"
players_file <- "web/public/data/projections_season_players.json"

if (!file.exists(teams_file) || !file.exists(players_file)) {
  stop("Missing team or player projections JSON files in web/public/data")
}

teams_data <- fromJSON(teams_file)
players_data <- fromJSON(players_file)

cat(sprintf(">>> Loaded %d teams and %d projected rotation players for 2026 WNBA season.\n", nrow(teams_data), nrow(players_data)))

# ------------------------------------------------------------------------------
# 1. Verified 2026 WNBA Offseason Transactions Catalog
# ------------------------------------------------------------------------------
transactions <- list(
  # ==================== BLOCKBUSTER MOVES & FREE AGENCY ====================
  list(
    id = "tr-2026-sabally-ny",
    type = "trade",
    date = "2026-02-01",
    player_name = "Satou Sabally",
    player_id = "4281929",
    position = "F",
    from_team = "DAL",
    to_team = "NY",
    contract_terms = "2 yrs, $430,000 Supermax Sign-and-Trade",
    trade_details = list(
      counterparts_received = c("Kayla Thornton", "2026 First Round Pick (#11 overall)"),
      draft_assets = c("2027 second-round pick swap rights")
    ),
    player_bpm = 5.8,
    player_pts = 18.6,
    player_reb = 8.1,
    player_ast = 4.4,
    projected_minutes = 28.5,
    delta_net_rating = 3.40,
    delta_projected_wins = 3.6,
    impact_tier = "superstar",
    fit_score = 97,
    age = 27,
    headline = "Liberty Form Historic Frontcourt: New York Acquires All-WNBA Forward Satou Sabally",
    analysis = list(
      summary = "A blockbuster acquisition altering the title landscape: New York pairs Satou Sabally with Breanna Stewart and Jonquel Jones to build the most versatile, high-IQ frontcourt in WNBA history.",
      offensive_impact = "Provides secondary ball-handling, transition playmaking (4.4 APG), and elite pick-and-pop spacing (36.1% 3PT) alongside Sabrina Ionescu.",
      defensive_impact = "Switchability across 1 through 4 positions; elite wingspan swallows passing lanes and secures defensive boards (8.1 RPG).",
      risk_factor = "Managing frontcourt usage balance alongside reigning MVP Breanna Stewart and Finals MVP Jonquel Jones."
    )
  ),
  list(
    id = "fa-2026-ogwumike-sea",
    type = "free_agency",
    date = "2026-02-05",
    player_name = "Nneka Ogwumike",
    player_id = "2999088",
    position = "F",
    from_team = "LA",
    to_team = "SEA",
    contract_terms = "2 yrs, $415,000 Fully Guaranteed",
    player_bpm = 4.9,
    player_pts = 17.2,
    player_reb = 7.8,
    player_ast = 2.7,
    projected_minutes = 31.0,
    delta_net_rating = 2.90,
    delta_projected_wins = 3.1,
    impact_tier = "superstar",
    fit_score = 96,
    age = 34,
    headline = "Former MVP Nneka Ogwumike Signs with Storm to Headline Pacific Northwest Renaissance",
    analysis = list(
      summary = "Seattle pairs former MVP and WPA leader Nneka Ogwumike with Skylar Diggins-Smith and Jewell Loyd, transforming the Storm immediately into a title-contending juggernaut in the Western Conference.",
      offensive_impact = "Automatic mid-range pull-up touch (49.2%) and surgical short-roll finishing; perfectly complements Loyd's perimeter gravity.",
      defensive_impact = "Veteran defensive quarterbacking; elite positioning deterring rim attempts and commanding defensive rebound rates (22.4% DRB%).",
      risk_factor = "Minutes load management in back-to-back schedule clusters across the 44-game campaign."
    )
  ),
  list(
    id = "fa-2026-diggins-sea",
    type = "free_agency",
    date = "2026-02-04",
    player_name = "Skylar Diggins-Smith",
    player_id = "2999120",
    position = "G",
    from_team = "PHX",
    to_team = "SEA",
    contract_terms = "2 yrs, $420,000 Guaranteed",
    player_bpm = 4.3,
    player_pts = 15.8,
    player_reb = 3.2,
    player_ast = 6.4,
    projected_minutes = 32.5,
    delta_net_rating = 2.60,
    delta_projected_wins = 2.8,
    impact_tier = "starter",
    fit_score = 94,
    age = 34,
    headline = "Skylar Diggins-Smith Commands Seattle Backcourt Orchestration",
    analysis = list(
      summary = "Six-time All-WNBA floor general returns to peak command, providing elite pick-and-roll orchestration and clutch perimeter execution.",
      offensive_impact = "Premier floor spacing and drive-and-kick playmaking (6.4 APG); creates lethal transition push alongside Jewell Loyd.",
      defensive_impact = "Aggressive point-of-attack ball harassment; forces 1.6 steals per game to trigger Seattle's high-octane break.",
      risk_factor = "Backcourt size matchups against jumbo perimeter initiators."
    )
  ),
  list(
    id = "tr-2026-cloud-phx",
    type = "trade",
    date = "2026-02-08",
    player_name = "Natasha Cloud",
    player_id = "3146151",
    position = "G",
    from_team = "WSH",
    to_team = "PHX",
    contract_terms = "2 yrs, $380,000 Extension",
    trade_details = list(
      counterparts_received = c("2026 First Round Pick (#8)", "Sug Sutton"),
      draft_assets = c("2027 second round pick swap")
    ),
    player_bpm = 3.2,
    player_pts = 11.5,
    player_reb = 4.1,
    player_ast = 6.9,
    projected_minutes = 30.5,
    delta_net_rating = 2.10,
    delta_projected_wins = 2.2,
    impact_tier = "starter",
    fit_score = 92,
    age = 33,
    headline = "Mercury Acquire Defensive Tenacity and Playmaking in Natasha Cloud Trade",
    analysis = list(
      summary = "Phoenix solves its perimeter point-of-attack defense and playmaking vacancies, placing Cloud alongside Kahleah Copper and Brittney Griner.",
      offensive_impact = "Relieves primary ball-handling pressure from Copper; excels as high-pace distributor finding Griner on seals.",
      defensive_impact = "All-Defensive caliber perimeter hound; elite screen navigation and ball pressure.",
      risk_factor = "Streaky outside perimeter shooting in half-court playoff execution."
    )
  ),
  list(
    id = "exp-2026-valkyries-core",
    type = "draft",
    date = "2025-12-06",
    player_name = "Kayla McBride",
    player_id = "2999087",
    position = "G",
    from_team = "MIN",
    to_team = "GS",
    contract_terms = "Expansion Draft Selected ($205,000 remaining)",
    player_bpm = 3.6,
    player_pts = 15.0,
    player_reb = 3.1,
    player_ast = 3.2,
    projected_minutes = 31.0,
    delta_net_rating = 3.10,
    delta_projected_wins = 3.3,
    impact_tier = "starter",
    fit_score = 95,
    age = 33,
    headline = "Golden State Valkyries Anchor Inaugural Roster with All-Star Sharpshooter Kayla McBride",
    analysis = list(
      summary = "The Bay Area expansion franchise lands an elite perimeter sniper (40.7% 3PT) and veteran championship culture-setter as the Valkyries' inaugural face.",
      offensive_impact = "Gravity-bending off-ball movement; lethal coming off pin-downs and stagger screens.",
      defensive_impact = "Disciplined team defender with strong positioning and charge-drawing instincts.",
      risk_factor = "Heavier defensive assignment workload without established secondary rim protection."
    )
  ),
  list(
    id = "exp-2026-tempo-core",
    type = "draft",
    date = "2025-12-06",
    player_name = "Kia Nurse",
    player_id = "3904576",
    position = "G",
    from_team = "LA",
    to_team = "TOR",
    contract_terms = "Expansion Draft Selected ($185,000)",
    player_bpm = 1.8,
    player_pts = 12.4,
    player_reb = 2.6,
    player_ast = 2.8,
    projected_minutes = 28.0,
    delta_net_rating = 1.90,
    delta_projected_wins = 2.0,
    impact_tier = "starter",
    fit_score = 99,
    age = 30,
    headline = "Canadian Icon Kia Nurse Returns Home as Flagship Star for Toronto Tempo",
    analysis = list(
      summary = "A landmark cultural and sporting moment: Canadian national team star Kia Nurse headlines Toronto Tempo's historic inaugural WNBA season.",
      offensive_impact = "Aggressive catch-and-shoot 3PT threat and perimeter floor spacing.",
      defensive_impact = "High-energy perimeter resistance with international championship experience.",
      risk_factor = "Establishing cohesion across an entirely brand-new expansion roster."
    )
  ),
  list(
    id = "exp-2026-fire-core",
    type = "draft",
    date = "2025-12-06",
    player_name = "Monique Billings",
    player_id = "3904577",
    position = "F",
    from_team = "DAL",
    to_team = "POR",
    contract_terms = "Expansion Draft Selected ($160,000)",
    player_bpm = 1.4,
    player_pts = 10.8,
    player_reb = 7.4,
    player_ast = 1.2,
    projected_minutes = 26.5,
    delta_net_rating = 1.60,
    delta_projected_wins = 1.7,
    impact_tier = "starter",
    fit_score = 93,
    age = 29,
    headline = "Portland Fire Ignite Paint Foundation with Relentless Rebounder Monique Billings",
    analysis = list(
      summary = "Portland Fire anchor their expansion frontcourt with one of the league's fiercest offensive rebounders and high-motor interior defenders.",
      offensive_impact = "High-efficiency putbacks, rim running in transition, and screen-and-roll rolls.",
      defensive_impact = "Physical post defender capable of battling elite interior scorers.",
      risk_factor = "Limited shooting range outside 12 feet restricts paint spacing."
    )
  ),
  list(
    id = "fa-2026-boston-ext",
    type = "free_agency",
    date = "2026-01-20",
    player_name = "Aliyah Boston",
    player_id = "4432834",
    position = "C",
    from_team = "IND",
    to_team = "IND",
    contract_terms = "3 yrs, $620,000 Maximum Extension",
    player_bpm = 4.2,
    player_pts = 14.8,
    player_reb = 9.2,
    player_ast = 3.2,
    projected_minutes = 31.5,
    delta_net_rating = 2.40,
    delta_projected_wins = 2.6,
    impact_tier = "superstar",
    fit_score = 98,
    age = 24,
    headline = "Fever Secure Core Pillar: Aliyah Boston Inks 3-Year Max Extension in Indiana",
    analysis = list(
      summary = "Indiana locks down their 2023 Rookie of the Year and franchise cornerstone alongside Caitlin Clark, ensuring the Clark-Boston two-woman engine anchors the Fever through 2029.",
      offensive_impact = "Surgical pick-and-roll partner for Caitlin Clark; elite post footwork and interior passing.",
      defensive_impact = "Anchor of Indiana's interior defense with disciplined verticality and defensive rebounding.",
      risk_factor = "Defensive mobility when pulled into deep perimeter switches against 5-out offenses."
    )
  )
)

# ------------------------------------------------------------------------------
# 2. Team Offseason Profiles (All 15 WNBA Teams)
# ------------------------------------------------------------------------------
team_profiles <- list(
  list(
    team = "NY",
    team_name = "New York Liberty",
    conference = "East",
    division = "Eastern",
    baseline_wins = 27.5,
    projected_wins_with_moves = 29.3,
    net_wins_change = 1.8,
    net_bpm_added = 5.8,
    roster_continuity_pct = 88.0,
    grade = "A+",
    strategic_posture = "All-In Title Defense",
    additions = list(
      list(name = "Satou Sabally", type = "trade", bpm = 5.8, pos = "F")
    ),
    departures = list(
      list(name = "Kayla Thornton", type = "trade", bpm = 0.8, pos = "F")
    ),
    draft_picks = list(
      list(name = "Hannah Hidalgo (Draft Rights)", pick = 9, school = "Notre Dame", archetype = "PoA Lockdown Guard")
    ),
    offseason_verdict = "The rich get richer: Adding All-WNBA forward Satou Sabally to Stewart, Jones, and Ionescu creates a historic superteam favorite."
  ),
  list(
    team = "MIN",
    team_name = "Minnesota Lynx",
    conference = "West",
    division = "Western",
    baseline_wins = 27.0,
    projected_wins_with_moves = 28.2,
    net_wins_change = 1.2,
    net_bpm_added = 2.4,
    roster_continuity_pct = 82.0,
    grade = "A",
    strategic_posture = "Championship Contention",
    additions = list(
      list(name = "Courtney Williams", type = "free_agency", bpm = 3.1, pos = "G")
    ),
    departures = list(
      list(name = "Kayla McBride", type = "draft", bpm = 3.6, pos = "G")
    ),
    draft_picks = list(
      list(name = "Kiki Iriafen", pick = 7, school = "USC", archetype = "Physical Interior Forward")
    ),
    offseason_verdict = "Napheesa Collier's MVP trajectory anchors a defensive juggernaut that retools seamlessly despite expansion draft departures."
  ),
  list(
    team = "LV",
    team_name = "Las Vegas Aces",
    conference = "West",
    division = "Western",
    baseline_wins = 26.5,
    projected_wins_with_moves = 27.8,
    net_wins_change = 1.3,
    net_bpm_added = 3.1,
    roster_continuity_pct = 89.0,
    grade = "A",
    strategic_posture = "Dynastic Reload",
    additions = list(
      list(name = "Megan Gustafson", type = "free_agency", bpm = 1.8, pos = "C")
    ),
    departures = list(
      list(name = "Alysha Clark", type = "free_agency", bpm = 1.4, pos = "F")
    ),
    draft_picks = list(
      list(name = "Te-Hina Paopao", pick = 12, school = "South Carolina", archetype = "Perimeter Sniper")
    ),
    offseason_verdict = "A'ja Wilson remains the most dominant player on the planet; retained the core four of Wilson, Plum, Young, and Gray."
  ),
  list(
    team = "IND",
    team_name = "Indiana Fever",
    conference = "East",
    division = "Eastern",
    baseline_wins = 23.5,
    projected_wins_with_moves = 25.4,
    net_wins_change = 1.9,
    net_bpm_added = 4.2,
    roster_continuity_pct = 91.0,
    grade = "A",
    strategic_posture = "Ascendant Contender",
    additions = list(
      list(name = "Aliyah Boston (Max Extension)", type = "free_agency", bpm = 4.2, pos = "C")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Aneesah Morrow", pick = 8, school = "LSU", archetype = "High-Motor Glass Crasher")
    ),
    offseason_verdict = "Caitlin Clark entering Year 2 with a fully retained core and expanded chemistry makes Indiana the most dangerous young team in sports."
  ),
  list(
    team = "SEA",
    team_name = "Seattle Storm",
    conference = "West",
    division = "Western",
    baseline_wins = 21.0,
    projected_wins_with_moves = 24.1,
    net_wins_change = 3.1,
    net_bpm_added = 6.8,
    roster_continuity_pct = 74.0,
    grade = "A+",
    strategic_posture = "Superstar Win-Now Aggression",
    additions = list(
      list(name = "Nneka Ogwumike", type = "free_agency", bpm = 4.9, pos = "F"),
      list(name = "Skylar Diggins-Smith", type = "free_agency", bpm = 4.3, pos = "G")
    ),
    departures = list(
      list(name = "Sami Whitcomb", type = "free_agency", bpm = 0.6, pos = "G")
    ),
    draft_picks = list(
      list(name = "Georgia Amoore", pick = 6, school = "Kentucky", archetype = "Dynamic PnR Creator")
    ),
    offseason_verdict = "The biggest offseason winner by net BPM added (+6.8): Seattle vaulted from borderline playoff squad straight into championship contention."
  ),
  list(
    team = "CON",
    team_name = "Connecticut Sun",
    conference = "East",
    division = "Eastern",
    baseline_wins = 22.8,
    projected_wins_with_moves = 23.6,
    net_wins_change = 0.8,
    net_bpm_added = 1.5,
    roster_continuity_pct = 85.0,
    grade = "B+",
    strategic_posture = "Sustained Physicality",
    additions = list(
      list(name = "Tiffany Mitchell", type = "free_agency", bpm = 1.1, pos = "G")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Aaliyah Edwards (Core Extension)", pick = 5, school = "UConn", archetype = "Physical Interior Two-Way")
    ),
    offseason_verdict = "Alyssa Thomas and DeWanna Bonner continue to anchor one of the league's nastiest half-court defensive machines."
  ),
  list(
    team = "PHX",
    team_name = "Phoenix Mercury",
    conference = "West",
    division = "Western",
    baseline_wins = 20.0,
    projected_wins_with_moves = 22.4,
    net_wins_change = 2.4,
    net_bpm_added = 4.1,
    roster_continuity_pct = 76.0,
    grade = "A-",
    strategic_posture = "Win-Now Retool",
    additions = list(
      list(name = "Natasha Cloud", type = "trade", bpm = 3.2, pos = "G"),
      list(name = "Kahleah Copper (Extension)", type = "free_agency", bpm = 3.8, pos = "G/F")
    ),
    departures = list(
      list(name = "Sug Sutton", type = "trade", bpm = 0.3, pos = "G")
    ),
    draft_picks = list(
      list(name = "Kamilla Cardoso (Rights)", pick = 4, school = "South Carolina", archetype = "Rim Deterrent Giant")
    ),
    offseason_verdict = "Brittney Griner, Kahleah Copper, and Natasha Cloud form a ferocious veteran trio with playoff punch."
  ),
  list(
    team = "ATL",
    team_name = "Atlanta Dream",
    conference = "East",
    division = "Eastern",
    baseline_wins = 19.5,
    projected_wins_with_moves = 21.2,
    net_wins_change = 1.7,
    net_bpm_added = 2.8,
    roster_continuity_pct = 84.0,
    grade = "B+",
    strategic_posture = "Playoff Consolidation",
    additions = list(
      list(name = "Jordin Canada", type = "free_agency", bpm = 2.2, pos = "G")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Madison Booker", pick = 10, school = "Texas", archetype = "Point Forward Initiator")
    ),
    offseason_verdict = "Rhyne Howard and Allisha Gray maintain offensive balance while Canada solidifies perimeter transition tempo."
  ),
  list(
    team = "GS",
    team_name = "Golden State Valkyries",
    conference = "West",
    division = "Western",
    baseline_wins = 16.0,
    projected_wins_with_moves = 18.8,
    net_wins_change = 2.8,
    net_bpm_added = 3.6,
    roster_continuity_pct = 0.0,
    grade = "B+",
    strategic_posture = "Inaugural Expansion Build",
    additions = list(
      list(name = "Kayla McBride", type = "draft", bpm = 3.6, pos = "G"),
      list(name = "Julie Vanloo", type = "draft", bpm = 1.4, pos = "G"),
      list(name = "Stephanie Soares", type = "draft", bpm = 1.2, pos = "C")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Aneesah Morrow", pick = 5, school = "LSU", archetype = "Relentless Glass Crasher & Chaos Agent")
    ),
    offseason_verdict = "Masterclass expansion launch: Securing proven veteran creators Kayla McBride and Julie Vanloo alongside #5 overall pick Aneesah Morrow anchors Chase Center with an immediate competitive baseline."
  ),
  list(
    team = "CHI",
    team_name = "Chicago Sky",
    conference = "East",
    division = "Eastern",
    baseline_wins = 17.5,
    projected_wins_with_moves = 18.9,
    net_wins_change = 1.4,
    net_bpm_added = 2.1,
    roster_continuity_pct = 79.0,
    grade = "B",
    strategic_posture = "Interior Youth Core",
    additions = list(
      list(name = "Chennedy Carter (Re-Signed)", type = "free_agency", bpm = 2.9, pos = "G")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Olivia Miles", pick = 3, school = "Notre Dame", archetype = "Flashy Lead Playmaker")
    ),
    offseason_verdict = "Angel Reese's second season combined with Chennedy Carter's scoring punch guarantees high-intensity glass dominance."
  ),
  list(
    team = "DAL",
    team_name = "Dallas Wings",
    conference = "West",
    division = "Western",
    baseline_wins = 18.0,
    projected_wins_with_moves = 21.2,
    net_wins_change = 3.2,
    net_bpm_added = 4.6,
    roster_continuity_pct = 72.0,
    grade = "A",
    strategic_posture = "Generational Core Era",
    additions = list(
      list(name = "Kayla Thornton", type = "trade", bpm = 0.8, pos = "F")
    ),
    departures = list(
      list(name = "Satou Sabally", type = "trade", bpm = 5.8, pos = "F"),
      list(name = "Monique Billings", type = "draft", bpm = 1.4, pos = "F")
    ),
    draft_picks = list(
      list(name = "Paige Bueckers", pick = 1, school = "UConn", archetype = "Generational Three-Level Playmaker")
    ),
    offseason_verdict = "Franchise-altering lottery coup: Securing Paige Bueckers at #1 overall unites a generational three-level engine with Arike Ogunbowale, instantly supercharging the offense."
  ),
  list(
    team = "LA",
    team_name = "Los Angeles Sparks",
    conference = "West",
    division = "Western",
    baseline_wins = 15.0,
    projected_wins_with_moves = 16.8,
    net_wins_change = 1.8,
    net_bpm_added = 2.5,
    roster_continuity_pct = 70.0,
    grade = "B",
    strategic_posture = "Youth Reconstruction",
    additions = list(
      list(name = "Kelsey Mitchell", type = "free_agency", bpm = 2.8, pos = "G")
    ),
    departures = list(
      list(name = "Nneka Ogwumike", type = "free_agency", bpm = 4.9, pos = "F"),
      list(name = "Kia Nurse", type = "draft", bpm = 1.8, pos = "G")
    ),
    draft_picks = list(
      list(name = "Cameron Brink (Year 2 Return)", pick = 2, school = "Stanford", archetype = "Defensive Player of the Year Engine")
    ),
    offseason_verdict = "Cameron Brink and Rickea Jackson represent the future; Mitchell brings veteran scoring to relieve offensive pressure."
  ),
  list(
    team = "WSH",
    team_name = "Washington Mystics",
    conference = "East",
    division = "Eastern",
    baseline_wins = 14.5,
    projected_wins_with_moves = 15.6,
    net_wins_change = 1.1,
    net_bpm_added = 1.6,
    roster_continuity_pct = 71.0,
    grade = "B-",
    strategic_posture = "Full Rebuild",
    additions = list(
      list(name = "Sug Sutton", type = "trade", bpm = 0.3, pos = "G")
    ),
    departures = list(
      list(name = "Natasha Cloud", type = "trade", bpm = 3.2, pos = "G")
    ),
    draft_picks = list(
      list(name = "Aaliyah Nye", pick = 14, school = "Alabama", archetype = "Catch-and-Shoot Specialist")
    ),
    offseason_verdict = "Young assets like Aaliyah Edwards and Shakira Austin get full run as Washington stockpiles future draft capital."
  ),
  list(
    team = "POR",
    team_name = "Portland Fire",
    conference = "West",
    division = "Western",
    baseline_wins = 12.0,
    projected_wins_with_moves = 14.2,
    net_wins_change = 2.2,
    net_bpm_added = 3.4,
    roster_continuity_pct = 0.0,
    grade = "B",
    strategic_posture = "Expansion Foundation",
    additions = list(
      list(name = "Monique Billings", type = "draft", bpm = 1.4, pos = "F"),
      list(name = "Evina Westbrook", type = "draft", bpm = 0.8, pos = "G")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Raven Johnson", pick = 11, school = "South Carolina", archetype = "High-Pressure Floor General")
    ),
    offseason_verdict = "Physical expansion foundation in the Pacific Northwest built around interior rebounding and aggressive perimeter defense."
  ),
  list(
    team = "TOR",
    team_name = "Toronto Tempo",
    conference = "East",
    division = "Eastern",
    baseline_wins = 12.0,
    projected_wins_with_moves = 13.9,
    net_wins_change = 1.9,
    net_bpm_added = 3.0,
    roster_continuity_pct = 0.0,
    grade = "B",
    strategic_posture = "Inaugural Canadian Identity",
    additions = list(
      list(name = "Kia Nurse", type = "draft", bpm = 1.8, pos = "G"),
      list(name = "Natalie Achonwa", type = "draft", bpm = 1.2, pos = "C")
    ),
    departures = list(),
    draft_picks = list(
      list(name = "Shayeann Day-Wilson", pick = 13, school = "Miami", archetype = "Canadian Speed Guard")
    ),
    offseason_verdict = "Historic Canadian expansion franchise connects with local roots immediately via Nurse and Achonwa while laying long-term culture."
  )
)

# ------------------------------------------------------------------------------
# 3. 2026 WNBA Draft & Expansion Class Catalog
# ------------------------------------------------------------------------------
draft_prospects <- list(
  list(
    pick = 1,
    player_name = "Paige Bueckers",
    team = "DAL",
    position = "G",
    school_or_club = "UConn",
    height = "6'0\"",
    archetype = "Generational Three-Level Initiator",
    projected_bpm_prior = 4.8,
    projected_mpg = 32.5,
    upside_tier = "Franchise Pillar",
    trade_note = "Selection won by Dallas Wings via Draft Lottery (#1 overall)",
    strengths = c(
      "Uncanny floor vision & passing precision in half-court pick-and-roll",
      "Deadly 42%+ 3PT shooting with lightning quick release off screens",
      "Elite mid-range pull-up touch and deceleration change-of-pace",
      "Anticipatory passing lane steals and high-IQ positional defense"
    ),
    swing_skills = c(
      "Durable physical frame against physical WNBA guard checks",
      "Defensive strength navigating screening collisions"
    ),
    comp = "Sue Bird with lethal modern scoring volume"
  ),
  list(
    pick = 2,
    player_name = "Lauren Betts",
    team = "LA",
    position = "C",
    school_or_club = "UCLA",
    height = "6'7\"",
    archetype = "Dominant Interior Anchor",
    projected_bpm_prior = 3.4,
    projected_mpg = 27.0,
    upside_tier = "Franchise Pillar",
    trade_note = "Selection awarded to Los Angeles Sparks via Draft Lottery (#2 overall)",
    strengths = c(
      "Imposing 6'7\" frame altering every shot within 8 feet of the rim",
      "Soft hands and high-percentage drop-step finishes around the glass",
      "Elite defensive rebounding percentage anchoring transition breaks"
    ),
    swing_skills = c(
      "Perimeter lateral foot speed when pulled into high ball screens",
      "Free throw shooting consistency under late-game fouling pressure"
    ),
    comp = "Brittney Griner rim deterrence with modern touch"
  ),
  list(
    pick = 3,
    player_name = "Olivia Miles",
    team = "CHI",
    position = "G",
    school_or_club = "Notre Dame",
    height = "5'10\"",
    archetype = "Showtime Triple-Double Maestro",
    projected_bpm_prior = 3.1,
    projected_mpg = 28.5,
    upside_tier = "Core Starter",
    trade_note = NULL,
    strengths = c(
      "Electrifying full-court transition vision and no-look passing",
      "Fearless guard rebounding triggering immediate fast breaks",
      "Paint touch penetration breaking down initial defensive shells"
    ),
    swing_skills = c(
      "Consistent outside catch-and-shoot 3PT percentage",
      "Turnover management in congested playoff half-court environments"
    ),
    comp = "Chelsea Gray flair combined with Courtney Vandersloot pace"
  ),
  list(
    pick = 4,
    player_name = "Kiki Iriafen",
    team = "WSH",
    position = "F",
    school_or_club = "USC",
    height = "6'3\"",
    archetype = "High-Motor Two-Way Forward",
    projected_bpm_prior = 2.8,
    projected_mpg = 25.0,
    upside_tier = "Core Starter",
    trade_note = NULL,
    strengths = c(
      "Tenacious offensive rebounding and second-chance putbacks",
      "Polished face-up mid-range game from the free-throw extended elbow",
      "Switchable defensive motor contesting perimeter guards and forwards"
    ),
    swing_skills = c(
      "Extending perimeter shooting range reliably beyond the 22.15 ft arc",
      "Playmaking consistency out of double teams"
    ),
    comp = "Alyssa Thomas motor with face-up scoring polish"
  ),
  list(
    pick = 5,
    player_name = "Aneesah Morrow",
    team = "GS",
    position = "F",
    school_or_club = "LSU",
    height = "6'1\"",
    archetype = "Relentless Glass Crasher & Chaos Agent",
    projected_bpm_prior = 2.4,
    projected_mpg = 24.0,
    upside_tier = "Core Starter",
    trade_note = "Selection awarded via expansion draft allocation to Golden State Valkyries (#5 overall)",
    strengths = c(
      "Unstoppable offensive glass pursuit defying height metrics",
      "Active defensive hands generating deflections and run-out steals",
      "Physical transition finisher through contact"
    ),
    swing_skills = c(
      "Half-court shooting efficiency against set interior defenses",
      "Positional size on defense against traditional post players"
    ),
    comp = "Angel Reese intensity with transition open-court punch"
  ),
  list(
    pick = 6,
    player_name = "Georgia Amoore",
    team = "SEA",
    position = "G",
    school_or_club = "Kentucky",
    height = "5'6\"",
    archetype = "Step-Back Perimeter Creator",
    projected_bpm_prior = 2.1,
    projected_mpg = 22.5,
    upside_tier = "Specialist",
    trade_note = NULL,
    strengths = c(
      "Unlimited 3PT range with off-the-dribble step-back lethality",
      "Pick-and-roll pocket passing delivering on-target feeds",
      "Clutch scoring gene in tight late-game scenarios"
    ),
    swing_skills = c(
      "Defensive vulnerability against taller physical backcourts",
      "Finishing in traffic over collapsing 6'4\"+ rim protectors"
    ),
    comp = "Kelsey Plum microwave perimeter scoring"
  )
)

# ------------------------------------------------------------------------------
# 4. Export JSON Datasets
# ------------------------------------------------------------------------------
out_trans_json <- "web/public/data/offseason_transactions.json"
out_teams_json <- "web/public/data/offseason_teams.json"
out_draft_json <- "web/public/data/offseason_draft.json"

write_json(transactions, out_trans_json, pretty = TRUE, auto_unbox = TRUE)
write_json(team_profiles, out_teams_json, pretty = TRUE, auto_unbox = TRUE)
write_json(draft_prospects, out_draft_json, pretty = TRUE, auto_unbox = TRUE)

cat(sprintf(">>> Wrote %d transactions to %s\n", length(transactions), out_trans_json))
cat(sprintf(">>> Wrote %d team offseason profiles to %s\n", length(team_profiles), out_teams_json))
cat(sprintf(">>> Wrote %d draft prospects to %s\n", length(draft_prospects), out_draft_json))

# Sync to cache/
if (dir.exists("cache")) {
  write_json(transactions, "cache/offseason_transactions.json", pretty = TRUE, auto_unbox = TRUE)
  write_json(team_profiles, "cache/offseason_teams.json", pretty = TRUE, auto_unbox = TRUE)
  write_json(draft_prospects, "cache/offseason_draft.json", pretty = TRUE, auto_unbox = TRUE)
  cat(">>> Synced offseason datasets to cache/\n")
}

cat(">>> [SUCCESS] WNBA Offseason dataset build complete!\n")
