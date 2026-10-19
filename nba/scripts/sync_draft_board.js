const fs = require('fs');
const path = require('path');

const draftProspects = [
  {
    pick: 1,
    player_name: "AJ Dybantsa",
    original_team: "WAS",
    team: "WAS",
    position: "SF",
    school_or_club: "BYU",
    height: "6'9\"",
    archetype: "Generational Three-Level Alpha Wing",
    projected_bpm_prior: 0.8,
    projected_mpg: 29.5,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "Elite three-level scoring package with step-back 3s",
      "Unstoppable downhill vertical burst and rim finishing",
      "7'0 wingspan defensive switchability 1-through-4"
    ],
    swing_skills: [
      "Playmaking feel under aggressive traps",
      "Consistent motor on off-ball defensive rotations"
    ],
    comp: "Tracy McGrady / Jayson Tatum"
  },
  {
    pick: 2,
    player_name: "Darryn Peterson",
    original_team: "UTA",
    team: "UTA",
    position: "SG/PG",
    school_or_club: "KU",
    height: "6'5\"",
    archetype: "Complete Modern Combo Guard Virtuoso",
    projected_bpm_prior: 0.6,
    projected_mpg: 28.5,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "Surgical off-the-dribble mid-range and 3PT shot creation",
      "Fluid pick-and-roll pace with ambidextrous passing",
      "Long wingspan on-ball defensive ball pressure"
    ],
    swing_skills: [
      "Finishing through interior shot blockers",
      "Shot selection discipline"
    ],
    comp: "Devin Booker / Brandon Roy"
  },
  {
    pick: 3,
    player_name: "Cameron Boozer",
    original_team: "MEM",
    team: "MEM",
    position: "PF/C",
    school_or_club: "DUKE",
    height: "6'9\"",
    archetype: "High-Feel Point Forward and Paint Enforcer",
    projected_bpm_prior: 0.5,
    projected_mpg: 28.0,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "Pro-ready physical power frame and footwork",
      "Phenomenal high-post passing and decision-making cadence",
      "Tenacious two-way rebounding"
    ],
    swing_skills: [
      "Lateral foot speed against quick perimeter isolations",
      "Rim protection vertical pop"
    ],
    comp: "Paolo Banchero / Kevin Love"
  },
  {
    pick: 4,
    player_name: "Caleb Wilson",
    original_team: "CHI",
    team: "CHI",
    position: "SF/PF",
    school_or_club: "UNC",
    height: "6'9\"",
    archetype: "High-Flying Slashing Point Forward",
    projected_bpm_prior: -0.2,
    projected_mpg: 26.0,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "Explosive above-the-rim vertical bounce",
      "Switchable perimeter defense 2-through-4",
      "High motor on defensive glass"
    ],
    swing_skills: [
      "Spot-up 3PT consistency",
      "Pull-up mid-range touch"
    ],
    comp: "Aaron Gordon / Scottie Barnes"
  },
  {
    pick: 5,
    player_name: "Keaton Wagler",
    original_team: "IND",
    team: "DET",
    position: "SG/PG",
    school_or_club: "ILL",
    height: "6'6\"",
    archetype: "Dynamic Scoring Guard and Playmaker",
    projected_bpm_prior: -0.4,
    projected_mpg: 25.0,
    upside_tier: "Core Starter",
    trade_note: "via IND",
    strengths: [
      "High-level shot creation off the dribble",
      "Pick-and-roll passing vision",
      "Aggressive rim attacks"
    ],
    swing_skills: [
      "Consistent perimeter 3PT range",
      "Defensive point-of-attack discipline"
    ],
    comp: "Tyler Herro / Austin Reaves"
  },
  {
    pick: 6,
    player_name: "Mikel Brown Jr.",
    original_team: "BKN",
    team: "BKN",
    position: "PG",
    school_or_club: "LOU",
    height: "6'3\"",
    archetype: "Dazzling Pull-Up Shotmaker and Playmaker",
    projected_bpm_prior: -0.5,
    projected_mpg: 26.0,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "Blinding crossover separation and shake",
      "Deep pull-up 3PT range beyond 28 feet",
      "Creative pick-and-roll vision"
    ],
    swing_skills: [
      "Finishing through contact against physical 7-footers",
      "Point-of-attack screen navigation"
    ],
    comp: "Darius Garland / Kyrie Irving"
  },
  {
    pick: 7,
    player_name: "Darius Acuff Jr.",
    original_team: "SAC",
    team: "SAC",
    position: "PG",
    school_or_club: "ARK",
    height: "6'3\"",
    archetype: "Electric Downhill Lead Scorer",
    projected_bpm_prior: -0.5,
    projected_mpg: 25.0,
    upside_tier: "Core Starter",
    trade_note: null,
    strengths: [
      "Explosive step-backs and hesitation drives",
      "Fearless paint finishing with either hand",
      "High assist creation on kick-outs"
    ],
    swing_skills: [
      "Defensive consistency",
      "Turnover rate against zone traps"
    ],
    comp: "Collin Sexton / Tyrese Maxey"
  },
  {
    pick: 8,
    player_name: "Kingston Flemings",
    original_team: "NOP",
    team: "ATL",
    position: "PG",
    school_or_club: "HOU",
    height: "6'3\"",
    archetype: "Hyper-Speed Floor General and Pest",
    projected_bpm_prior: -0.6,
    projected_mpg: 24.5,
    upside_tier: "Core Starter",
    trade_note: "via NO",
    strengths: [
      "Top 1% end-to-end open-court transition speed",
      "Blow-by first step collapsing defenses",
      "Tenacious full-court ball pressure"
    ],
    swing_skills: [
      "Half-court 3PT shooting mechanics",
      "Floaters against drop bigs"
    ],
    comp: "De'Aaron Fox / Dennis Schroder"
  },
  {
    pick: 9,
    player_name: "Morez Johnson Jr.",
    original_team: "DAL",
    team: "DAL",
    position: "PF/C",
    school_or_club: "MICH",
    height: "6'9\"",
    archetype: "Tenacious Interior Finisher and Glass Cleaner",
    projected_bpm_prior: -0.7,
    projected_mpg: 23.5,
    upside_tier: "Core Starter",
    trade_note: null,
    strengths: [
      "Physical box outs and offensive glass putbacks",
      "Explosive rim-running vertical pop",
      "Positional paint defense"
    ],
    swing_skills: [
      "Free throw stroke",
      "Mid-range floor spacing"
    ],
    comp: "Isaiah Stewart / Wendell Carter Jr."
  },
  {
    pick: 10,
    player_name: "Brayden Burries",
    original_team: "MIL",
    team: "MIL",
    position: "SG",
    school_or_club: "ARIZ",
    height: "6'5\"",
    archetype: "Physical Two-Way Scoring Wing",
    projected_bpm_prior: -0.6,
    projected_mpg: 24.0,
    upside_tier: "Core Starter",
    trade_note: null,
    strengths: [
      "Stout frame powering through contact at the rim",
      "Pull-up shooting off rhythm dribbles",
      "Switchable backcourt defense"
    ],
    swing_skills: [
      "Off-ball catch-and-shoot consistency",
      "Playmaking reads out of double teams"
    ],
    comp: "Josh Hart / Desmond Bane"
  },
  {
    pick: 11,
    player_name: "Yaxel Lendeborg",
    original_team: "GSW",
    team: "GSW",
    position: "PF",
    school_or_club: "MICH",
    height: "6'9\"",
    archetype: "High-IQ Versatile Forward and Playmaker",
    projected_bpm_prior: -0.8,
    projected_mpg: 22.0,
    upside_tier: "Core Starter",
    trade_note: null,
    strengths: [
      "Seamless high-post passing and dribble hand-offs",
      "Active defensive hands disrupting passing lanes",
      "Reliable mid-range face-up game"
    ],
    swing_skills: [
      "3PT shooting volume from NBA distance",
      "Lateral speed against small guards"
    ],
    comp: "Kyle Anderson / Boris Diaw"
  },
  {
    pick: 12,
    player_name: "Aday Mara",
    original_team: "LAC",
    team: "OKC",
    position: "C",
    school_or_club: "MICH",
    height: "7'3\"",
    archetype: "Towering Rim Protector and High-Post Hub",
    projected_bpm_prior: -0.7,
    projected_mpg: 21.0,
    upside_tier: "Core Starter",
    trade_note: "via LAC",
    strengths: [
      "7'7 wingspan elite rim deterrence",
      "Savant-level interior passing over defenses",
      "Soft touch around the basket"
    ],
    swing_skills: [
      "Foot speed in space on perimeter switches",
      "Stamina over 82-game grind"
    ],
    comp: "Brook Lopez / Marc Gasol"
  },
  {
    pick: 13,
    player_name: "Nate Ament",
    original_team: "MIA",
    team: "MIL",
    position: "SF/PF",
    school_or_club: "TENN",
    height: "6'9\"",
    archetype: "Lanky Pure Shooter and Fluid Wing",
    projected_bpm_prior: -0.6,
    projected_mpg: 24.0,
    upside_tier: "Core Starter",
    trade_note: "Traded to MIL",
    strengths: [
      "High-release catch-and-shoot marksmanship (40% 3PT)",
      "Smooth elevation over closing defenders",
      "Active secondary rim contests"
    ],
    swing_skills: [
      "Physical frame mass",
      "Finishing in heavy crowd traffic"
    ],
    comp: "Michael Porter Jr. / Trey Murphy III"
  },
  {
    pick: 14,
    player_name: "Hannes Steinbach",
    original_team: "CHA",
    team: "CHA",
    position: "PF/C",
    school_or_club: "WASH",
    height: "6'10\"",
    archetype: "Modern European Stretch Big",
    projected_bpm_prior: -0.9,
    projected_mpg: 20.0,
    upside_tier: "Specialist",
    trade_note: null,
    strengths: [
      "Clean mechanics on pick-and-pop 3-pointers",
      "Disciplined defensive positioning and box outs",
      "Smart passing out of short rolls"
    ],
    swing_skills: [
      "Vertical explosive rim protection",
      "Physicality against bruising centers"
    ],
    comp: "Daniel Theis / Moritz Wagner"
  },
  {
    pick: 15,
    player_name: "Dailyn Swain",
    original_team: "POR",
    team: "CHI",
    position: "SG/SF",
    school_or_club: "TEX",
    height: "6'7\"",
    archetype: "Long Two-Way Disruptive Wing",
    projected_bpm_prior: -0.9,
    projected_mpg: 20.5,
    upside_tier: "Core Starter",
    trade_note: "via POR",
    strengths: [
      "Smothering length and lateral footwork on perimeter ballhandlers",
      "Transition lane running and above-rim finishes",
      "Active deflections and steals"
    ],
    swing_skills: [
      "Consistent half-court shooting form",
      "Self-creation handle"
    ],
    comp: "Mikal Bridges / Herb Jones"
  },
  {
    pick: 16,
    player_name: "Bennett Stirtz",
    original_team: "MEM",
    team: "OKC",
    position: "PG",
    school_or_club: "IOWA",
    height: "6'4\"",
    archetype: "Crafty Playmaking Floor General",
    projected_bpm_prior: -0.9,
    projected_mpg: 19.5,
    upside_tier: "Specialist",
    trade_note: "Traded to OKC",
    strengths: [
      "Uncanny floor awareness and pick-and-roll timing",
      "Knockdown spot-up shooting efficiency",
      "Poise against full-court press"
    ],
    swing_skills: [
      "Vertical burst at the rim",
      "Point-of-attack containment against hyper athletes"
    ],
    comp: "Tyus Jones / T.J. McConnell"
  },
  {
    pick: 17,
    player_name: "Ebuka Okorie",
    original_team: "OKC",
    team: "DET",
    position: "SG",
    school_or_club: "STAN",
    height: "6'5\"",
    archetype: "Explosive 3-and-D Backcourt Weapon",
    projected_bpm_prior: -1.0,
    projected_mpg: 19.0,
    upside_tier: "Specialist",
    trade_note: "Traded to DET via MEM",
    strengths: [
      "Blazing recovery speed on closeouts",
      "Laser-focused corner 3PT accuracy",
      "High-energy defensive intensity"
    ],
    swing_skills: [
      "Dribble drive creation",
      "Mid-range pull-up consistency"
    ],
    comp: "Kentavious Caldwell-Pope / Gary Harris"
  },
  {
    pick: 18,
    player_name: "Christian Anderson Jr.",
    original_team: "ORL",
    team: "CHA",
    position: "PG",
    school_or_club: "TTU",
    height: "6'2\"",
    archetype: "Sharpshooting Microwave Combo Guard",
    projected_bpm_prior: -1.0,
    projected_mpg: 18.5,
    upside_tier: "Specialist",
    trade_note: "from ORL via PHX",
    strengths: [
      "Deep pull-up range on fast breaks",
      "Quick-trigger release off handoffs",
      "Confident game management"
    ],
    swing_skills: [
      "Defensive size against physical NBA backcourts",
      "Finishing over length at rim"
    ],
    comp: "Seth Curry / Patty Mills"
  },
  {
    pick: 19,
    player_name: "Allen Graves",
    original_team: "TOR",
    team: "TOR",
    position: "PF/SF",
    school_or_club: "SCU",
    height: "6'8\"",
    archetype: "Versatile High-Motor Hybrid Forward",
    projected_bpm_prior: -1.1,
    projected_mpg: 18.0,
    upside_tier: "Developmental",
    trade_note: null,
    strengths: [
      "Non-stop motor on both ends of the floor",
      "Multi-positional switchability",
      "Tenacious offensive rebounding"
    ],
    swing_skills: [
      "Spot-up 3PT stroke",
      "Off-the-bounce creation"
    ],
    comp: "Kenrich Williams / Jae Crowder"
  },
  {
    pick: 20,
    player_name: "Jayden Quaintance",
    original_team: "ATL",
    team: "SAS",
    position: "PF/C",
    school_or_club: "UK",
    height: "6'10\"",
    archetype: "Hyper-Athletic Rim Wrecker and Lob Anchor",
    projected_bpm_prior: -0.6,
    projected_mpg: 22.5,
    upside_tier: "Core Starter",
    trade_note: "via ATL",
    strengths: [
      "7'4 wingspan explosive vertical bounce",
      "Fierce rim protection (2.6 BPG in EYBL)",
      "Terrific pick-and-roll screen-and-dive burst"
    ],
    swing_skills: [
      "Mid-range touch",
      "Free-throw shooting discipline"
    ],
    comp: "Onyeka Okongwu / Robert Williams III"
  },
  {
    pick: 21,
    player_name: "Karim Lopez",
    original_team: "DET",
    team: "MEM",
    position: "SF/PF",
    school_or_club: "Mexico",
    height: "6'8\"",
    archetype: "Fluid International Scoring Wing",
    projected_bpm_prior: -1.0,
    projected_mpg: 18.0,
    upside_tier: "Developmental",
    trade_note: "Traded to MEM",
    strengths: [
      "Smooth stroke on catch-and-shoot looks",
      "Excellent positional size and court awareness",
      "Active cutter without the ball"
    ],
    swing_skills: [
      "Functional strength against NBA physical wings",
      "On-ball creation separation"
    ],
    comp: "Bojan Bogdanovic / Deni Avdija"
  },
  {
    pick: 22,
    player_name: "Labaron Philon Jr.",
    original_team: "HOU",
    team: "PHI",
    position: "PG",
    school_or_club: "ALA",
    height: "6'4\"",
    archetype: "Slick Point-of-Attack Floor General",
    projected_bpm_prior: -1.0,
    projected_mpg: 18.0,
    upside_tier: "Specialist",
    trade_note: "from HOU via OKC",
    strengths: [
      "Shifty handle that breaks down drop coverages",
      "High basketball IQ and unselfish distribution",
      "Pesky on-ball defensive stance"
    ],
    swing_skills: [
      "Consistent pull-up 3PT efficiency",
      "Finishing in traffic through contact"
    ],
    comp: "Monte Morris / De'Anthony Melton"
  },
  {
    pick: 23,
    player_name: "Zuby Ejiofor",
    original_team: "CLE",
    team: "ATL",
    position: "PF/C",
    school_or_club: "SJU",
    height: "6'9\"",
    archetype: "High-Motor Paint Battler and Rebounder",
    projected_bpm_prior: -1.1,
    projected_mpg: 17.5,
    upside_tier: "Specialist",
    trade_note: "via CLE",
    strengths: [
      "Aggressive offensive putbacks and rim dives",
      "Physical box-outs and paint toughness",
      "Shot blocking recovery speed"
    ],
    swing_skills: [
      "Perimeter shooting skill set",
      "Free throw mechanics"
    ],
    comp: "Precious Achiuwa / Kenneth Faried"
  },
  {
    pick: 24,
    player_name: "Cameron Carr",
    original_team: "NYK",
    team: "LAL",
    position: "SG",
    school_or_club: "BAY",
    height: "6'5\"",
    archetype: "Silky Off-Screen Sharpshooter and Athlete",
    projected_bpm_prior: -0.9,
    projected_mpg: 18.5,
    upside_tier: "Specialist",
    trade_note: "Traded to LAL",
    strengths: [
      "Pure textbook perimeter shooting stroke (39% 3PT)",
      "Explosive leaping ability on back-cuts",
      "Good length on perimeter defense"
    ],
    swing_skills: [
      "Playmaking under defensive ball pressure",
      "Frame bulk"
    ],
    comp: "Malik Monk / Luke Kennard"
  },
  {
    pick: 25,
    player_name: "Sergio De Larrea",
    original_team: "LAL",
    team: "DAL",
    position: "PG/SG",
    school_or_club: "Spain",
    height: "6'6\"",
    archetype: "Jumbo Spanish Point Guard and Maestro",
    projected_bpm_prior: -1.0,
    projected_mpg: 18.0,
    upside_tier: "Developmental",
    trade_note: "Traded to DAL via NYK",
    strengths: [
      "6'6 tall playmaker seeing over defenses",
      "Elite European passing instincts on skip passes",
      "Poised pace and change of speed"
    ],
    swing_skills: [
      "Lateral foot speed against speedy NBA guards",
      "3PT pull-up consistency"
    ],
    comp: "Ricky Rubio / Tomas Satoransky"
  },
  {
    pick: 26,
    player_name: "Tarris Reed Jr.",
    original_team: "DEN",
    team: "SAS",
    position: "C",
    school_or_club: "CONN",
    height: "6'10\"",
    archetype: "Bruising Interior Anchor and Post Defender",
    projected_bpm_prior: -1.1,
    projected_mpg: 17.0,
    upside_tier: "Developmental",
    trade_note: "Traded to SA",
    strengths: [
      "Imposing physical frame that seals paint lanes",
      "Fierce rim protection and shot contesting",
      "Bruising screens freeing up ballhandlers"
    ],
    swing_skills: [
      "Floor spacing shooting range",
      "Foul trouble prevention"
    ],
    comp: "Andre Drummond / Isaiah Stewart"
  },
  {
    pick: 27,
    player_name: "Chris Cenac Jr.",
    original_team: "BOS",
    team: "BOS",
    position: "PF/C",
    school_or_club: "HOU",
    height: "6'10\"",
    archetype: "Two-Way Stretch Unicorn and Rim Eraser",
    projected_bpm_prior: -0.5,
    projected_mpg: 24.5,
    upside_tier: "Franchise Pillar",
    trade_note: null,
    strengths: [
      "7'3 wingspan rim protection (2.4 BPG in prep)",
      "Fluid 38.5% pick-and-pop 3-point release",
      "Open-court grab-and-go handling"
    ],
    swing_skills: [
      "Upper body strength against NBA post bruisers",
      "Low-post footwork"
    ],
    comp: "Chet Holmgren / Jaren Jackson Jr."
  },
  {
    pick: 28,
    player_name: "Joshua Jefferson",
    original_team: "MIN",
    team: "BKN",
    position: "SF/PF",
    school_or_club: "ISU",
    height: "6'8\"",
    archetype: "Tough Multi-Positional Glue Forward",
    projected_bpm_prior: -1.1,
    projected_mpg: 17.5,
    upside_tier: "Developmental",
    trade_note: "Traded to BKN",
    strengths: [
      "Relentless hustle, diving for loose balls",
      "Solid positional defense against forwards",
      "Smart high-low passing reads"
    ],
    swing_skills: [
      "Consistent jump shooting mechanics",
      "Shot creation"
    ],
    comp: "Grant Williams / Dean Wade"
  },
  {
    pick: 29,
    player_name: "Alex Karaban",
    original_team: "CLE",
    team: "SAC",
    position: "SF/PF",
    school_or_club: "CONN",
    height: "6'8\"",
    archetype: "Championship-Pedigree High-IQ Stretch Wing",
    projected_bpm_prior: -0.7,
    projected_mpg: 21.0,
    upside_tier: "Core Starter",
    trade_note: "Traded to SAC",
    strengths: [
      "Two-time NCAA Champion basketball IQ",
      "Deadly 39.5% catch-and-shoot 3-point stroke",
      "Flawless cutting timing and ball movement"
    ],
    swing_skills: [
      "Foot speed against elite isolation wings",
      "Self-creation burst"
    ],
    comp: "Georges Niang / Harrison Barnes"
  },
  {
    pick: 30,
    player_name: "Koa Peat",
    original_team: "DAL",
    team: "PHX",
    position: "PF/SF",
    school_or_club: "ARIZ",
    height: "6'8\"",
    archetype: "Physical Bully-Ball Playmaker and Rebounder",
    projected_bpm_prior: -0.2,
    projected_mpg: 26.0,
    upside_tier: "Franchise Pillar",
    trade_note: "Traded to PHX via NYK",
    strengths: [
      "Brute-force interior rim attacks and post-up scoring",
      "Grab-and-go open-court transition pushing",
      "Relentless physical motor on the boards"
    ],
    swing_skills: [
      "Perimeter 3PT consistency (swing skill)",
      "Free throw mechanics"
    ],
    comp: "Julius Randle / Ron Artest"
  }
];

const destFile = path.resolve('web/public/data/offseason_draft.json');
fs.writeFileSync(destFile, JSON.stringify(draftProspects, null, 2), 'utf8');
console.log(`[SUCCESS] Wrote ${draftProspects.length} exact draft picks to: ${destFile}`);
