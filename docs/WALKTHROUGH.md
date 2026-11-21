# Walkthrough: Finding Your Way Around Front Office

Front Office has 56 pages across four leagues. Rather than touring them one by one, this guide starts from the questions people usually bring to the site and points to the pages that answer them.

**Live site:** https://kailot-harris.github.io/front-office/

---

## Getting around

- **Search everything.** On the home page, press `/` and type a word such as `clutch`, `cap`, `shots` or `playoff`. Matching pages from all four leagues appear instantly. Press `Enter` to jump to the first result, or `Esc` to clear.
- **In season or offseason?** Each league card on the home page shows its status. In-season leagues (currently NFL and NBA) update daily, with score updates in the evening and overnight. Offseason leagues (currently WNBA and MLB) keep their full season available as an archive and add a weekly offseason report.
- **Same layout everywhere.** Each league has a sidebar with the same core pages in roughly the same order.
- **"How to read this page."** Most pages open with a short, collapsible explanation of the charts and columns. Underlined terms show a definition when you hover over them.
- **Take the data with you.** Tables can be downloaded as CSV and charts as PNG.

---

## "Who's going to win tonight, and why?"

**Go to:** [NBA Matchups](https://kailot-harris.github.io/front-office/nba/matchups/) · [NFL Matchups](https://kailot-harris.github.io/front-office/nfl/matchups/)

Pick a day or week from the ribbon at the top, then click any game. The detail panel shows each team's win probability and a chart breaking that probability into its ingredients: overall team strength, home court or field, rest, travel and injuries. Past slates show the forecast next to the final score, so you can see what the model got right and wrong.

## "How good is my team, really?"

**Go to:** each league's **Standings** page ([NFL](https://kailot-harris.github.io/front-office/nfl/) · [NBA](https://kailot-harris.github.io/front-office/nba/) · [WNBA](https://kailot-harris.github.io/front-office/wnba/) · [MLB](https://kailot-harris.github.io/front-office/mlb/)) and [NFL Team Ratings](https://kailot-harris.github.io/front-office/nfl/teams/)

Standings pages pair current records with a rating of underlying team quality and a projected final record. A team that's winning more than its play suggests, or less, will show up here.

## "Who's making the playoffs?"

**Go to:** [NFL Playoff Machine](https://kailot-harris.github.io/front-office/nfl/playoffs/) · [NBA Playoff Simulator](https://kailot-harris.github.io/front-office/nba/series/) · [WNBA Playoff Simulator](https://kailot-harris.github.io/front-office/wnba/series/) · [MLB Playoff Simulator](https://kailot-harris.github.io/front-office/mlb/series/)

These pages play out the rest of the season and the postseason thousands of times. The percentages show how often each team reached each round.

## "Which players play like this one?"

**Go to:** [NBA Player DNA](https://kailot-harris.github.io/front-office/nba/player-dna/) · [WNBA Player DNA](https://kailot-harris.github.io/front-office/wnba/player-dna/) · [MLB Player DNA](https://kailot-harris.github.io/front-office/mlb/player-dna/) · [NFL Player DNA](https://kailot-harris.github.io/front-office/nfl/dna/)

Choose a player to see their skill profile as a radar chart, where they sit on a map of playing styles and the players most similar to them. MLB comparisons reach back through decades of history. The basketball leagues compare against current players.

## "Who delivers when the game is on the line?"

**Go to:** the **Clutch** page in any league ([NBA](https://kailot-harris.github.io/front-office/nba/clutch/) · [WNBA](https://kailot-harris.github.io/front-office/wnba/clutch/) · [NFL](https://kailot-harris.github.io/front-office/nfl/clutch/) · [MLB](https://kailot-harris.github.io/front-office/mlb/clutch/))

"Clutch" means something specific here: the final minutes of close games in basketball and football, and high-pressure situations in baseball. The pages show who creates their own shots, who holds up under pressure and which relievers strand inherited runners.

## "Where does a player do their damage?"

**Go to:** [NBA Shot Charts](https://kailot-harris.github.io/front-office/nba/shots/) · [WNBA Shot Charts](https://kailot-harris.github.io/front-office/wnba/shots/) · [NFL Passing Charts](https://kailot-harris.github.io/front-office/nfl/passing/) · [MLB Spatial Analytics](https://kailot-harris.github.io/front-office/mlb/spatial/)

Shot locations on the court, pass depth and direction for quarterbacks, and spray charts and pitch movement for more than 1,200 MLB players.

## "How much room does my team have under the cap?"

**Go to:** [NBA Cap & Aprons](https://kailot-harris.github.io/front-office/nba/cap-sheet/) · [MLB Payroll & Luxury Tax](https://kailot-harris.github.io/front-office/mlb/cap-sheet/) · [NFL Salary Cap](https://kailot-harris.github.io/front-office/nfl/salary-cap/)

See each team's payroll against its league's limits: the NBA's tax line and the two "aprons" that restrict trades and signings, MLB's luxury-tax tiers, and NFL cap space. The MLB page includes a calculator that weighs a contract's cost against the wins a player is expected to add.

## "What happened this offseason?"

**Go to:** [MLB Offseason Monitor](https://kailot-harris.github.io/front-office/mlb/offseason-monitor/) · [WNBA Offseason Monitor](https://kailot-harris.github.io/front-office/wnba/offseason-monitor/) · [NBA Offseason Moves](https://kailot-harris.github.io/front-office/nba/offseason/)

A weekly report that separates confirmed transactions from rumors, with a short summary of the week. The WNBA version also tracks the tone of coverage across six beat-writer feeds. Use the edition picker to read past weeks.

## "Can I trust these numbers?"

**Go to:** the **Diagnostics** page in any league ([NFL](https://kailot-harris.github.io/front-office/nfl/diagnostics/) · [NBA](https://kailot-harris.github.io/front-office/nba/diagnostics/) · [WNBA](https://kailot-harris.github.io/front-office/wnba/diagnostics/) · [MLB](https://kailot-harris.github.io/front-office/mlb/diagnostics/)) and **Model Variants** ([NFL](https://kailot-harris.github.io/front-office/nfl/variants/) · [MLB](https://kailot-harris.github.io/front-office/mlb/variants/))

Diagnostics grades past forecasts. Do teams given a 70% chance actually win about 70% of the time? Forecasts made before games were played are reported separately from forecasts reconstructed after the fact, so the accuracy shown isn't flattered by hindsight. Model Variants lets you compare several different modeling approaches side by side.

---

## Quick glossary

| Term | What it means |
| :--- | :--- |
| **Win probability** | How often a team would be expected to win this game if it were played many times. |
| **EPA (NFL)** | Expected points added: how much a play improved a team's scoring chances, given down, distance and field position. |
| **CPOE (NFL)** | Completion percentage over expected: how often a quarterback completes passes compared with what the difficulty of their throws would predict. |
| **Plus-minus rating (NBA/WNBA)** | A player's impact on scoring per 100 possessions, adjusted for who else was on the floor. |
| **Expected shooting (NBA/WNBA)** | How well a player "should" shoot based on where they shoot from. The gap from their actual shooting hints at luck. |
| **Elo (MLB)** | A team-strength rating that rises with wins and falls with losses, adjusted here for the day's starting pitcher, travel and rest. |
| **Player DNA** | A player's skills expressed as percentiles, used to find players with similar styles. |
| **Leverage (MLB)** | How much a given moment can swing the game's outcome. |
| **Calibration** | Whether forecasts mean what they say: 60% calls should come true about 60% of the time. |
| **Luxury tax / aprons** | Payroll thresholds that cost teams money or restrict roster moves once crossed. |

For how these are calculated, see [How the Models Work](HOW_IT_WORKS.md).
