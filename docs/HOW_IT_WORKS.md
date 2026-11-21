# How the Models Work

This page explains, in plain terms, how Front Office turns public sports data into ratings, forecasts and player comparisons, and where the data runs out. The formulas are collected in an [appendix](#appendix-formulas) at the end.

---

## At a glance

- **4 leagues, 56 interactive pages:** NFL, NBA, WNBA and MLB.
- **15+ public data sources:** league statistics feeds, open-source sports data packages, contract databases and news feeds.
- **Updated automatically:** every morning for in-season leagues, with evening and overnight score updates, and weekly during the offseason.
- **Graded in public:** every league has a page that scores the accuracy of past forecasts.

---

## From raw data to the page

1. **Collect.** Each league's pipeline downloads schedules, box scores, play-by-play, rosters, injuries and contracts. When a source is unavailable, it falls back to a secondary source or reuses the last verified data rather than publishing gaps.
2. **Match players across sources.** Different sources use different player IDs. MLB alone uses five systems. The pipeline links them so one player's stats from several sources end up in the same profile.
3. **Model.** Ratings, simulations and player profiles are rebuilt from the updated data.
4. **Check.** Before anything is published, automated tests confirm the results are fresh, complete and consistent with the schedule. If a check fails, the site keeps its last good version.
5. **Publish.** The results go out as a static website, split into small files so pages load quickly.

---

## Team ratings and win probabilities

Every forecast starts with a rating of how strong each team is. Each sport measures strength differently:

- **NFL.** Ratings are built from expected points added (EPA): how much each play improves a team's scoring chances given down, distance and field position. Early in the season, when there are only a few games to go on, ratings lean on last season's level and shift toward current play as games accumulate.
- **NBA and WNBA.** Ratings are built up from players. Each player's impact is estimated from every possession they've played, adjusted for the other nine players on the floor. Team strength then reflects who's actually available, so injuries and rest matter.
- **MLB.** Teams carry an Elo rating that rises with wins and falls with losses. Before each game it's adjusted for home field, travel, rest and, most importantly, the day's starting pitcher.

A game's win probability comes from the gap between two teams' ratings, plus home advantage. In the NFL and NBA, a second model also weighs rest, travel and recent form. That model can show how much each factor moved a specific game's forecast, which is the breakdown you see in the matchup panels.

## Season and playoff simulations

Standings projections and playoff odds come from simulating the rest of the season, and then the postseason, about 10,000 times using the game-by-game win probabilities. A team's playoff odds are simply the share of simulations in which it got in. Each league's real playoff format is followed, including the number of games per series.

## Player projections

- **Basketball.** Player projections combine the possession-based impact ratings above with expected shooting: how well a player should shoot given where they shoot from. Hot or cold streaks that location can't explain are treated as partly luck and expected to fade.
- **Baseball.** Projections blend three seasons of history (the most recent counts most), adjusted for age and pulled toward average when a player has little playing time.
- **Football.** Quarterback ratings use EPA and completion percentage over expected (CPOE). Quarterbacks with few attempts are pulled toward the typical level for their experience.

The rule across all three: **small samples get pulled toward average.** Ten great at-bats shouldn't outweigh a career.

## Player DNA and similar players

Each player is described by about 15 skills, such as finishing, shooting, playmaking, defense and speed (or exit velocity, plate discipline and fielding in baseball). Each skill is expressed as a percentile against the league. Two players are "similar" when their profiles stand out from average in the same directions. If a skill wasn't tracked for a player, it's left out of the comparison rather than guessed.

## Clutch

Clutch stats only count high-pressure moments: the last five minutes of a close basketball game, the end of a close football game, or high-leverage situations in baseball. Within those moments, the pages measure things like self-created scoring, whether a player's efficiency holds up or slips, and, for relievers, how often inherited runners are stranded. Clutch samples are small by nature, so a minimum number of attempts is required to appear.

## Defense and versatility (NBA, WNBA)

Defensive versatility measures how evenly a defender's plays (blocks, steals, contested shots) are spread across the five positions they guard. A high score means they can guard anyone. It's shown alongside the defensive half of the impact rating.

## Payroll and cap

Cap pages apply each league's actual rules to current contracts: the NBA's tax line and the two "aprons" that restrict trades, MLB's luxury-tax tiers and their surcharges for repeat offenders, and NFL cap space. MLB's contract calculator compares a player's salary with the market value of the wins they're projected to add.

## Offseason monitors

When a league is in its offseason, the site switches from daily forecasts to a weekly report. Each week it collects the league's official transactions and items from team and beat-writer news feeds, sorts confirmed moves from rumors and updates every roster from the previous week's state. If a feed fails, the report won't claim it was a quiet week. It only reports "no moves" when every source was checked successfully.

## How accuracy is measured

Every forecast is graded after the game. Two scores are used. Both reward confident forecasts that turn out right and penalize confident forecasts that turn out wrong. A forecast that always says 50/50 makes a useful baseline to beat. Forecasts are also grouped by confidence, all the roughly 70% calls together for example, to check that they came true about as often as claimed.

Forecasts made **before** a game are kept separate from forecasts **reconstructed afterward** to test the model on past seasons. Only the first kind shows how the model performs live.

---

## Limits of the data

All of Front Office is built on free, public data. That keeps it open and reproducible, but it also sets real limits on what the numbers can say.

**What the sources don't capture**

- **No player-tracking data for basketball or football defense.** Public sources record events (shots, passes, fouls), not where all ten or twenty-two players are on every play. Defensive ratings and "who guarded whom" are inferred from events, so off-ball defense and spacing are under-measured.
- **NFL offensive line and coverage play.** Line play and coverage assignments are mostly invisible in public data, so a quarterback's numbers partly reflect their blockers and receivers.
- **Injuries are binary.** Reports say whether a player is out, doubtful and so on, not how limited they are. Players listed as playing are assumed to be at full strength.
- **Contract details.** Public contract databases cover salaries and guarantees well but miss some details (incentives, option conditions, some dead-money rules), so payroll figures are close estimates, not official ledgers.
- **Coaching history.** Some coaching background, such as tenure and career records, comes from reference compilations rather than a live feed.
- **Rumors.** News-feed items are labeled as rumors until an official transaction confirms them. The tone tracking on the WNBA monitor reflects how coverage reads, not whether it's accurate.

**What the numbers can and can't support**

- **Forecasts are probabilities, not predictions.** A 70% favorite should lose about three times in ten. One upset doesn't mean the model was wrong. A long run of them would.
- **Small samples are noisy.** Early-season ratings, clutch stats and players with few minutes or plate appearances carry wide uncertainty, even after being pulled toward average.
- **Similar players aren't destinies.** A player's closest comparisons share a style. They don't promise a similar career.
- **Cross-league comparisons don't hold.** Each league's ratings are on their own scale. A WNBA rating and an NBA rating, or an NFL and MLB forecast, aren't directly comparable.
- **History reflects its era.** Rules, pace and the three-point shot have changed a lot, so historical comparisons are best read within their own period.

**Ideas for closing the gaps**

- Bring in public tracking datasets where they're released (for example, NFL Big Data Bowl samples) to improve defensive and line-play measures.
- Show uncertainty ranges alongside projections, not just single numbers.
- Add playing-time projections that react to injury reports rather than treating them as on/off.
- Track how much each forecast moved after injury news, to measure how sensitive the models are to availability.
- Extend historical player comparisons in basketball beyond the current season.

---

## Appendix: formulas

For readers who want the details.

**Win probability (NFL).** The rating gap plus home advantage, scaled by how much NFL results vary from game to game:

$$P(\text{home win}) = \Phi\left(\frac{\Delta\text{Rating} + \text{HFA}}{\sigma}\right)$$

where $\Phi$ is the standard normal distribution and $\sigma$ is estimated from past schedules.

**Pulling small samples toward average.** A rating based on $g$ games is weighted against its prior by

$$w = \frac{g}{g + K}$$

so it relies more on current data as games accumulate.

**MLB starting-pitcher adjustment.** Team Elo is shifted by the gap between the starter's recent Game Score and the team's typical starter:

$$\Delta R_{\text{SP}} = 4.7 \times (\text{rGS}_{\text{pitcher}} - \text{rGS}_{\text{team}})$$

**Expected win percentage from runs (Pythagenpat).**

$$W\% = \frac{R^\gamma}{R^\gamma + RA^\gamma}, \qquad \gamma = (R_{\text{per game}} + RA_{\text{per game}})^{0.287}$$

**Player similarity.** With each player's skills as percentiles $\mathbf{a}$ and $\mathbf{b}$, centered at the league average of 50:

$$\text{Similarity} = \max\left(0,\ \frac{(\mathbf{a}-50)\cdot(\mathbf{b}-50)}{\lVert\mathbf{a}-50\rVert\,\lVert\mathbf{b}-50\rVert}\right) \times 100\%$$

**Defensive versatility.** With $p_k$ the share of a defender's plays against position $k$:

$$H = -\frac{1}{\ln 5}\sum_{k=1}^{5} p_k \ln p_k$$

ranging from 0 (guards one position) to 1 (spread evenly across all five).

**Forecast accuracy.** For $N$ forecasts $\hat{p}_i$ and outcomes $y_i \in \{0, 1\}$:

$$\text{Brier score} = \frac{1}{N}\sum_{i=1}^{N} (\hat{p}_i - y_i)^2 \qquad \text{Log loss} = -\frac{1}{N}\sum_{i=1}^{N} \big[y_i \ln \hat{p}_i + (1 - y_i)\ln(1 - \hat{p}_i)\big]$$

Lower is better for both. Always forecasting 50% gives a Brier score of 0.25.
