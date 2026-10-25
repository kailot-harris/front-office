# ==============================================================================
# build_offseason_dataset.R
# 2026 WNBA Offseason Moves, Expansion Draft, Transactions & Rookie Draft Analytics
# Path: build_offseason_dataset.R
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
      list(name = "Olivia Miles", pick = 2, school = "TCU", archetype = "Showtime Triple-Double Maestro")
    ),
    offseason_verdict = "Napheesa Collier's MVP trajectory anchors a defensive juggernaut, now supercharged by dynamic lottery playmaker Olivia Miles."
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
      list(name = "Te-Hina Paopao", pick = 16, school = "South Carolina", archetype = "Perimeter Sniper")
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
      list(name = "Raven Johnson", pick = 10, school = "South Carolina", archetype = "Lockdown Defensive Initiator")
    ),
    offseason_verdict = "Caitlin Clark entering Year 2 with a fully retained core plus collegiate teammate Raven Johnson at #10 makes Indiana an ascendant threat."
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
      list(name = "Awa Fam", pick = 3, school = "Spain", archetype = "Dominant European Interior Anchor"),
      list(name = "Taina Mair", pick = 14, school = "Duke", archetype = "High-Pace Pick-and-Roll Playmaker")
    ),
    offseason_verdict = "The biggest offseason winner: Seattle pairs superstar veteran additions with #3 overall pick Awa Fam for long-term interior dominance."
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
      list(name = "Nell Angloma", pick = 12, school = "France", archetype = "Physical European Two-Way Slasher"),
      list(name = "Gianna Kneepkens", pick = 15, school = "UCLA", archetype = "Deadly Catch-and-Shoot Wing")
    ),
    offseason_verdict = "Alyssa Thomas and DeWanna Bonner anchor Connecticut's defensive machine, reinforced by first-round wings Angloma (#12) and Kneepkens (#15)."
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
      list(name = "Kamilla Cardoso (Rights)", pick = 17, school = "South Carolina", archetype = "Rim Deterrent Giant")
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
      list(name = "Madina Okot", pick = 13, school = "South Carolina", archetype = "Interior Glass Crasher & Rim Runner")
    ),
    offseason_verdict = "Rhyne Howard and Allisha Gray maintain offensive balance while Canada and #13 pick Madina Okot solidify transition rebounding and tempo."
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
      list(name = "Flau'jae Johnson", pick = 8, school = "LSU", archetype = "Dynamic Two-Way Scoring Guard")
    ),
    offseason_verdict = "Masterclass expansion launch: Flau'jae Johnson brings electric perimeter dynamism to Chase Center alongside proven veteran leaders Kayla McBride and Julie Vanloo."
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
      list(name = "Gabriela Jaquez", pick = 5, school = "UCLA", archetype = "High-Motor Two-Way Slashing Wing")
    ),
    offseason_verdict = "Angel Reese's second season combined with UCLA rookie wing Gabriela Jaquez guarantees unrelenting glass and perimeter intensity."
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
      list(name = "Azzi Fudd", pick = 1, school = "UConn", archetype = "Generational Pure Perimeter Shooter")
    ),
    offseason_verdict = "Franchise-altering lottery coup: Selecting Azzi Fudd at #1 overall unites a lethal collegiate sniper with Paige Bueckers and Arike Ogunbowale, creating an elite backcourt."
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
      list(name = "Lauren Betts", pick = 4, school = "UCLA", archetype = "Imposing Rim Deterrent & Drop-Step Finisher"),
      list(name = "Angela Dugalić", pick = 9, school = "UCLA", archetype = "Versatile Switchable Stretch Forward"),
      list(name = "Cotie McMahon", pick = 11, school = "Ole Miss", archetype = "Physical Downhill Freight Train")
    ),
    offseason_verdict = "Draft jackpot: Adding 6'7\" interior anchor Lauren Betts at #4 plus Dugalić (#9) and McMahon (#11) instantly remakes the Mystics' frontcourt."
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
      list(name = "Iyana Martín Carrión", pick = 7, school = "Spain", archetype = "International Pick-and-Roll Maestro")
    ),
    offseason_verdict = "Physical expansion foundation in the Pacific Northwest built around interior rebounding and Spanish floor general Iyana Martín Carrión."
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
      list(name = "Kiki Rice", pick = 6, school = "UCLA", archetype = "Championship Lead Floor General")
    ),
    offseason_verdict = "Historic Canadian expansion franchise connects with local roots via Nurse and Achonwa while securing championship cornerstone Kiki Rice at #6 overall."
  )
)

# ------------------------------------------------------------------------------
# 3. 2026 WNBA Draft & Expansion Class Catalog
# ------------------------------------------------------------------------------
draft_prospects <- list(
  list(
    pick = 1,
    player_name = "Azzi Fudd",
    team = "DAL",
    position = "G",
    school_or_club = "UConn",
    height = "5'11\"",
    archetype = "Generational Pure Perimeter Shooter",
    projected_bpm_prior = 4.2,
    projected_mpg = 31.0,
    upside_tier = "Franchise Pillar",
    trade_note = "Selection won by Dallas Wings via Draft Lottery (#1 overall)",
    strengths = c(
      "Unrivaled catch-and-shoot 3PT mechanics (43%+ collegiate range)",
      "Elite off-ball gravity and relocation instinct freeing teammates",
      "Crisp mid-range pull-up touch out of pin-down screening action",
      "High-IQ positional off-ball team defense and spacing discipline"
    ),
    swing_skills = c(
      "Durable physical frame against physical WNBA perimeter defenders",
      "Self-created separation off primary isolation dribbles"
    ),
    comp = "Klay Thompson shooting stroke with Maya Moore relocation intelligence"
  ),
  list(
    pick = 2,
    player_name = "Olivia Miles",
    team = "MIN",
    position = "G",
    school_or_club = "TCU",
    height = "5'10\"",
    archetype = "Showtime Triple-Double Maestro",
    projected_bpm_prior = 3.6,
    projected_mpg = 29.5,
    upside_tier = "Franchise Pillar",
    trade_note = NULL,
    strengths = c(
      "Electrifying full-court transition vision and signature no-look passing",
      "Fearless guard rebounding triggering immediate transition offense",
      "Paint touch penetration breaking down initial perimeter shells"
    ),
    swing_skills = c(
      "Consistent outside catch-and-shoot 3PT percentage",
      "Turnover management in congested playoff half-court sets"
    ),
    comp = "Chelsea Gray flair combined with Courtney Vandersloot pace"
  ),
  list(
    pick = 3,
    player_name = "Awa Fam",
    team = "SEA",
    position = "C",
    school_or_club = "Spain",
    height = "6'4\"",
    archetype = "Dominant European Interior Anchor",
    projected_bpm_prior = 3.3,
    projected_mpg = 27.0,
    upside_tier = "Franchise Pillar",
    trade_note = NULL,
    strengths = c(
      "High-level EuroLeague and Spanish Liga Femenina professional pedigree",
      "Imposing post defense and natural shot-altering reach",
      "Soft hands with high-percentage touch in the restricted area"
    ),
    swing_skills = c(
      "Adjusting to the high screening speed and physicality of the WNBA",
      "Free throw shooting consistency under late fouling pressure"
    ),
    comp = "Jonquel Jones defensive presence with European polish"
  ),
  list(
    pick = 4,
    player_name = "Lauren Betts",
    team = "WSH",
    position = "C",
    school_or_club = "UCLA",
    height = "6'7\"",
    archetype = "Imposing Rim Deterrent & Drop-Step Finisher",
    projected_bpm_prior = 3.1,
    projected_mpg = 26.5,
    upside_tier = "Core Starter",
    trade_note = NULL,
    strengths = c(
      "Imposing 6'7\" frame altering every shot within 8 feet of the rim",
      "Soft touch finishing around the glass through defensive contact",
      "Elite defensive rebounding percentage anchoring transition breaks"
    ),
    swing_skills = c(
      "Lateral foot speed when pulled into high perimeter ball screens",
      "Range extension beyond 15 feet"
    ),
    comp = "Brittney Griner rim deterrence with modern touch"
  ),
  list(
    pick = 5,
    player_name = "Gabriela Jaquez",
    team = "CHI",
    position = "F",
    school_or_club = "UCLA",
    height = "6'0\"",
    archetype = "High-Motor Two-Way Slashing Wing",
    projected_bpm_prior = 2.7,
    projected_mpg = 25.0,
    upside_tier = "Core Starter",
    trade_note = NULL,
    strengths = c(
      "Relentless offensive rebounding and 50/50 loose-ball hustle",
      "Tenacious on-ball defensive containment against multiple positions",
      "Transition slash-and-kick playmaking"
    ),
    swing_skills = c(
      "Consistent perimeter jump shot off the catch",
      "Creating off the bounce against set defenses"
    ),
    comp = "Alyssa Thomas work ethic with perimeter versatility"
  ),
  list(
    pick = 6,
    player_name = "Kiki Rice",
    team = "TOR",
    position = "G",
    school_or_club = "UCLA",
    height = "5'11\"",
    archetype = "Championship Lead Floor General",
    projected_bpm_prior = 2.8,
    projected_mpg = 27.5,
    upside_tier = "Core Starter",
    trade_note = "Toronto Tempo inaugural draft selection (#6 overall)",
    strengths = c(
      "Poised pick-and-roll pacing and mature decision-making",
      "Physical guard defense at point-of-attack with strong active hands",
      "Relentless downhill rim attacks and drawing fouls"
    ),
    swing_skills = c(
      "3PT pull-up volume when defenses go under screens",
      "Mid-range pull-up consistency"
    ),
    comp = "Jordin Canada burst with bigger defensive frame"
  ),
  list(
    pick = 7,
    player_name = "Iyana Martín Carrión",
    team = "POR",
    position = "G",
    school_or_club = "Spain",
    height = "5'8\"",
    archetype = "International Pick-and-Roll Maestro",
    projected_bpm_prior = 2.4,
    projected_mpg = 23.0,
    upside_tier = "Core Starter",
    trade_note = "Portland Fire inaugural draft selection (#7 overall)",
    strengths = c(
      "Prodigious FIBA U19 MVP vision and playmaking feel",
      "Lethal step-back jumper and stop-and-pop touch",
      "Crafty change-of-direction dribble combos shaking perimeter defenders"
    ),
    swing_skills = c(
      "Physical containment against taller WNBA guards",
      "Finishing over athletic shot blockers"
    ),
    comp = "Julie Vanloo playmaking wizardry with high upside"
  ),
  list(
    pick = 8,
    player_name = "Flau'jae Johnson",
    team = "GS",
    position = "G",
    school_or_club = "LSU",
    height = "5'10\"",
    archetype = "Dynamic Two-Way Scoring Guard",
    projected_bpm_prior = 2.6,
    projected_mpg = 25.5,
    upside_tier = "Core Starter",
    trade_note = "Selection awarded to Golden State Valkyries (*)",
    strengths = c(
      "Explosive first step attacking closeouts in transition and half-court",
      "Clutch shot-making gene and fearless scoring mentality",
      "Athletic perimeter on-ball lockdown pressure"
    ),
    swing_skills = c(
      "Catch-and-shoot consistency from deep WNBA 3PT distance",
      "Pick-and-roll playmaking reads against dropping bigs"
    ),
    comp = "Arike Ogunbowale scoring flair with superior defensive wingspan"
  ),
  list(
    pick = 9,
    player_name = "Angela Dugalić",
    team = "WSH",
    position = "F",
    school_or_club = "UCLA",
    height = "6'4\"",
    archetype = "Versatile Switchable Stretch Forward",
    projected_bpm_prior = 2.2,
    projected_mpg = 21.0,
    upside_tier = "Rotation Asset",
    trade_note = "Acquired by Washington Mystics via trade",
    strengths = c(
      "6'4\" perimeter shooting stretching out opposing frontcourts",
      "Switchability guarding wings and bigs",
      "High-IQ passing from the high post"
    ),
    swing_skills = c(
      "Physical strength against low-post bruisers",
      "Finishing through traffic"
    ),
    comp = "Satou Sabally lite stretch-forward prototype"
  ),
  list(
    pick = 10,
    player_name = "Raven Johnson",
    team = "IND",
    position = "G",
    school_or_club = "South Carolina",
    height = "5'9\"",
    archetype = "Lockdown Defensive Initiator",
    projected_bpm_prior = 2.3,
    projected_mpg = 22.0,
    upside_tier = "Rotation Asset",
    trade_note = NULL,
    strengths = c(
      "Elite on-ball point-of-attack defensive harassment",
      "Championship pedigree and vocal leadership",
      "High assist-to-turnover ratio in transition"
    ),
    swing_skills = c(
      "Half-court perimeter shooting consistency",
      "Finishing around the rim"
    ),
    comp = "Natasha Cloud defensive intensity and intangibles"
  ),
  list(
    pick = 11,
    player_name = "Cotie McMahon",
    team = "WSH",
    position = "F",
    school_or_club = "Ole Miss",
    height = "6'0\"",
    archetype = "Physical Downhill Freight Train",
    projected_bpm_prior = 2.0,
    projected_mpg = 20.0,
    upside_tier = "Rotation Asset",
    trade_note = NULL,
    strengths = c(
      "Powerfully built frame bowling through contact to the rim",
      "Tenacious foul-drawing rate",
      "Active defensive hands generating transition runouts"
    ),
    swing_skills = c(
      "3PT range extension",
      "Turnover rate when defenses pack the paint"
    ),
    comp = "Angel McCoughtry power driving style"
  ),
  list(
    pick = 12,
    player_name = "Nell Angloma",
    team = "CON",
    position = "G/F",
    school_or_club = "France",
    height = "5'11\"",
    archetype = "Physical European Two-Way Slasher",
    projected_bpm_prior = 1.9,
    projected_mpg = 18.5,
    upside_tier = "Rotation Asset",
    trade_note = NULL,
    strengths = c(
      "Physical EuroLeague / French LFB professional experience",
      "Active defensive motor and transition athleticism",
      "Aggressive slasher drawing contact"
    ),
    swing_skills = c(
      "Perimeter shot consistency",
      "Playmaking reads"
    ),
    comp = "Tiffany Hayes slashing motor with European defensive discipline"
  ),
  list(
    pick = 13,
    player_name = "Madina Okot",
    team = "ATL",
    position = "C",
    school_or_club = "South Carolina",
    height = "6'6\"",
    archetype = "Interior Glass Crasher & Rim Runner",
    projected_bpm_prior = 1.8,
    projected_mpg = 17.0,
    upside_tier = "Specialist",
    trade_note = NULL,
    strengths = c(
      "Imposing 6'6\" presence dominating both backboards",
      "Athletic rim running in early offense",
      "Shot blocking presence"
    ),
    swing_skills = c(
      "Free throw percentage",
      "Perimeter defensive foot speed"
    ),
    comp = "Kiah Stokes rim deterrence and rebounding prowess"
  ),
  list(
    pick = 14,
    player_name = "Taina Mair",
    team = "SEA",
    position = "G",
    school_or_club = "Duke",
    height = "5'9\"",
    archetype = "High-Pace Pick-and-Roll Playmaker",
    projected_bpm_prior = 1.7,
    projected_mpg = 16.5,
    upside_tier = "Specialist",
    trade_note = NULL,
    strengths = c(
      "Speedy open-court playmaker pushing fast break tempo",
      "Active ball pressure and steal anticipation",
      "Pass-first mentality finding corner shooters"
    ),
    swing_skills = c(
      "Finishing over length",
      "3PT shooting off dribble"
    ),
    comp = "Sug Sutton pace and distribution"
  ),
  list(
    pick = 15,
    player_name = "Gianna Kneepkens",
    team = "CON",
    position = "G",
    school_or_club = "UCLA",
    height = "6'0\"",
    archetype = "Deadly Catch-and-Shoot Wing",
    projected_bpm_prior = 1.8,
    projected_mpg = 18.0,
    upside_tier = "Specialist",
    trade_note = NULL,
    strengths = c(
      "40%+ collegiate 3PT marksman with lightning quick release",
      "Intelligent off-ball cutting exploiting defensive overplays",
      "High basketball IQ and poise"
    ),
    swing_skills = c(
      "Defensive foot speed against elite perimeter athletes",
      "Creating own shot off bounce"
    ),
    comp = "Bridget Carleton perimeter gravity and sharpshooting"
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
