import { describe, it, expect } from 'vitest';
import {
  WNBA_TEAMS,
  EXPECTED_SHOT_ZONES,
  loadAllDatasets,
  readPlayerShotFile,
} from '../helpers/datasets';

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

describe('Domain & mathematical invariants: projections_season_teams.json', () => {
  const { teams, metadata } = loadAllDatasets();

  it('contains all 15 unique WNBA teams ranked 1..15', () => {
    expect(teams.map((t) => t.team).sort()).toEqual([...WNBA_TEAMS].sort());
    expect(teams.map((t) => t.rank).sort((a, b) => a - b)).toEqual(
      Array.from({ length: 15 }, (_, i) => i + 1)
    );
  });

  it('has 7 East teams and 8 West teams', () => {
    const east = teams.filter((t) => t.conference === 'East');
    const west = teams.filter((t) => t.conference === 'West');
    expect(east).toHaveLength(7);
    expect(west).toHaveLength(8);
  });

  it('proj_wins + proj_losses equals 44 for every team, and win_pct ≈ proj_wins / 44', () => {
    for (const t of teams) {
      expect(t.proj_wins + t.proj_losses, `${t.team} wins+losses`).toBeCloseTo(44, 1);
      expect(t.win_pct, `${t.team} win_pct`).toBeCloseTo(t.proj_wins / 44, 2);
    }
  });

  it('percentile ordering holds: p10 <= p25 <= p50 <= p75 <= p90 for every team', () => {
    for (const t of teams) {
      expect(t.ensemble_p10, `${t.team} p10<=p25`).toBeLessThanOrEqual(t.ensemble_p25);
      expect(t.ensemble_p25, `${t.team} p25<=p50`).toBeLessThanOrEqual(t.ensemble_p50);
      expect(t.ensemble_p50, `${t.team} p50<=p75`).toBeLessThanOrEqual(t.ensemble_p75);
      expect(t.ensemble_p75, `${t.team} p75<=p90`).toBeLessThanOrEqual(t.ensemble_p90);
      expect(t.ensemble_mean_wins, `${t.team} mean in [p10, p90]`).toBeGreaterThanOrEqual(
        t.ensemble_p10 - 0.5
      );
      expect(t.ensemble_mean_wins, `${t.team} mean in [p10, p90]`).toBeLessThanOrEqual(
        t.ensemble_p90 + 0.5
      );
    }
  });

  it('zero-sum schedule conservation: sum of projected wins across 15 teams equals total_schedule_games (330)', () => {
    const totalGames = metadata.total_schedule_games; // 15 * 44 / 2 = 330
    expect(totalGames).toBe(330);

    const sumProjWins = sum(teams.map((t) => t.proj_wins));
    const sumEnsembleWins = sum(teams.map((t) => t.ensemble_mean_wins));
    const sumBottomUpWins = sum(teams.map((t) => t.variant_bottom_up_mean_wins));
    const sumRapmWins = sum(teams.map((t) => t.variant_rapm_mean_wins));
    const sumShotFatigueWins = sum(teams.map((t) => t.variant_shot_fatigue_mean_wins));
    const sumEmbeddingsWins = sum(teams.map((t) => t.variant_embeddings_mean_wins));

    expect(
      Math.abs(sumProjWins - totalGames),
      `sum(proj_wins)=${sumProjWins.toFixed(2)} vs ${totalGames} (expected ±0.5)`
    ).toBeLessThanOrEqual(0.5);
    expect(
      Math.abs(sumEnsembleWins - totalGames),
      `sum(ensemble_mean_wins)=${sumEnsembleWins.toFixed(2)} vs ${totalGames} (expected ±0.5)`
    ).toBeLessThanOrEqual(0.5);
    // Raw model variants prior to ensemble zero-sum normalization
    expect(sumBottomUpWins).toBeGreaterThan(250);
    expect(sumBottomUpWins).toBeLessThan(400);
    expect(sumRapmWins).toBeGreaterThan(250);
    expect(sumRapmWins).toBeLessThan(400);
    expect(sumShotFatigueWins).toBeGreaterThan(250);
    expect(sumShotFatigueWins).toBeLessThan(400);
    expect(sumEmbeddingsWins).toBeGreaterThan(250);
    expect(sumEmbeddingsWins).toBeLessThan(400);
  });

  it('probability conservation: 8 playoff spots (sum(playoff_prob) ≈ 8.0) and 1 champion (sum(title_prob) ≈ 1.0)', () => {
    const sumPlayoffProb = sum(teams.map((t) => t.ensemble_playoff_prob));
    const sumTitleProb = sum(teams.map((t) => t.ensemble_title_prob));

    expect(
      Math.abs(sumPlayoffProb - 8.0),
      `sum(ensemble_playoff_prob) = ${sumPlayoffProb.toFixed(4)} (expected 8.0 ± 0.5)`
    ).toBeLessThanOrEqual(0.5);

    expect(
      Math.abs(sumTitleProb - 1.0),
      `sum(ensemble_title_prob) = ${sumTitleProb.toFixed(4)} (expected 1.0 ± 0.2)`
    ).toBeLessThanOrEqual(0.2);
  });

  it('ensemble_mean_wins matches weighted linear combination of the 4 model variants', () => {
    const wBu = metadata.models.variant_bottom_up.weight ?? 0.35;
    const wRapm = metadata.models.variant_rapm.weight ?? 0.25;
    const wSf = metadata.models.variant_shot_fatigue.weight ?? 0.2;
    const wEmb = metadata.models.variant_embeddings.weight ?? 0.2;
    expect(wBu + wRapm + wSf + wEmb).toBeCloseTo(1.0, 5);

    for (const t of teams) {
      const expectedBlend =
        wBu * t.variant_bottom_up_mean_wins +
        wRapm * t.variant_rapm_mean_wins +
        wSf * t.variant_shot_fatigue_mean_wins +
        wEmb * t.variant_embeddings_mean_wins;
      expect(
        Math.abs(t.ensemble_mean_wins - expectedBlend),
        `${t.team}: ensemble_mean_wins=${t.ensemble_mean_wins} vs weighted blend=${expectedBlend.toFixed(2)}`
      ).toBeLessThanOrEqual(0.5);
    }
  });
});

describe('Domain & mathematical invariants: projections_season_players.json', () => {
  const { players } = loadAllDatasets();

  it('has unique player_ids across all 15 teams', () => {
    const ids = players.map((p) => p.player_id);
    expect(new Set(ids).size).toBe(ids.length);
    const teamsRepresented = new Set(players.map((p) => p.team));
    expect([...teamsRepresented].sort()).toEqual([...WNBA_TEAMS].sort());
  });

  it('season totals match per-game * proj_games, percentiles are monotonic, and is_outlier matches |z| > 2.0', () => {
    for (const p of players) {
      expect(
        Math.abs(p.proj_pts_total - p.proj_pts * p.proj_games),
        `${p.player_name} pts_total`
      ).toBeLessThanOrEqual(5);
      expect(
        Math.abs(p.proj_reb_total - p.proj_reb * p.proj_games),
        `${p.player_name} reb_total`
      ).toBeLessThanOrEqual(5);
      expect(
        Math.abs(p.proj_ast_total - p.proj_ast * p.proj_games),
        `${p.player_name} ast_total`
      ).toBeLessThanOrEqual(5);

      expect(p.pts_p10).toBeLessThanOrEqual(p.pts_p25);
      expect(p.pts_p25).toBeLessThanOrEqual(p.pts_p50);
      expect(p.pts_p50).toBeLessThanOrEqual(p.pts_p75);
      expect(p.pts_p75).toBeLessThanOrEqual(p.pts_p90);

      const maxAbsZ = Math.max(
        Math.abs(p.pts_zscore),
        Math.abs(p.reb_zscore),
        Math.abs(p.ast_zscore),
        Math.abs(p.pra_zscore)
      );
      if (p.is_outlier) {
        expect(maxAbsZ, `${p.player_name} marked is_outlier but max |z| <= 2.0`).toBeGreaterThan(
          1.95
        );
      }
    }
  });
});

describe('Domain & mathematical invariants: projections_diagnostics.json', () => {
  const { diagnostics } = loadAllDatasets();

  it('calibration bins, accuracyDrift seasons, and residualDistribution buckets each sum to totalResolvedGames', () => {
    const total = diagnostics.totalResolvedGames;
    const calSum = sum(diagnostics.calibration.map((b) => b.count));
    const driftSum = sum(diagnostics.accuracyDrift.map((s) => s.games));
    const residSum = sum(diagnostics.residualDistribution.map((r) => r.count));

    expect(calSum).toBe(total);
    expect(driftSum).toBe(total);
    expect(residSum).toBe(total);
  });

  it('calibration bin midpoints are strictly increasing', () => {
    for (let i = 1; i < diagnostics.calibration.length; i++) {
      expect(diagnostics.calibration[i].midpoint).toBeGreaterThan(
        diagnostics.calibration[i - 1].midpoint
      );
    }
  });
});

describe('Domain & mathematical invariants: cba_cap_sheet.json', () => {
  const { cbaCapSheet } = loadAllDatasets();

  it('league cap constants satisfy rookieMin < vetMin < vetMax < supermax < capFloor < hardSalaryCap', () => {
    expect(cbaCapSheet.rookieMinSalary).toBeLessThan(cbaCapSheet.vetMinSalary);
    expect(cbaCapSheet.vetMinSalary).toBeLessThan(cbaCapSheet.vetMaxSalary);
    expect(cbaCapSheet.vetMaxSalary).toBeLessThan(cbaCapSheet.supermaxSalary);
    expect(cbaCapSheet.supermaxSalary).toBeLessThan(cbaCapSheet.capFloor);
    expect(cbaCapSheet.capFloor).toBeLessThan(cbaCapSheet.hardSalaryCap);
    expect(cbaCapSheet.capFloor).toBeCloseTo(cbaCapSheet.hardSalaryCap * 0.9, 3);
  });

  it('every team obeys the WNBA Hard Cap ($1.52M) and contract rollups equal team totals', () => {
    for (const t of cbaCapSheet.teams) {
      expect(t.contracts.length).toBeGreaterThanOrEqual(11);
      expect(t.contracts.length).toBeLessThanOrEqual(18);
      expect(t.totalPayroll2026, `${t.teamAbbr} exceeds hard cap`).toBeLessThanOrEqual(
        cbaCapSheet.hardSalaryCap + 0.001
      );

      const contractSum2026 = sum(t.contracts.map((c) => c.salary2026));
      expect(contractSum2026, `${t.teamAbbr} contract sum vs totalPayroll2026`).toBeCloseTo(
        t.totalPayroll2026,
        2
      );
      expect(
        cbaCapSheet.hardSalaryCap - t.totalPayroll2026,
        `${t.teamAbbr} capSpace2026`
      ).toBeCloseTo(t.capSpace2026, 2);
    }
  });

  it('league summary counts match team roster counts', () => {
    const elevenCount = cbaCapSheet.teams.filter((t) => t.rosterCount === 11).length;
    const twelveCount = cbaCapSheet.teams.filter((t) => t.rosterCount === 12).length;
    expect(elevenCount + twelveCount).toBe(15);
    expect(cbaCapSheet.hardCapSqueezeTeamCount).toBe(elevenCount);
    expect(cbaCapSheet.twelvePlayerTeamCount).toBe(twelveCount);
  });
});

describe('Domain & mathematical invariants: clutch, defense, playerDna, coaches, offseason, playoffSeries, shots', () => {
  const {
    clutch,
    defense,
    playerDna,
    coaches,
    offseasonDraft,
    offseasonTeams,
    playoffSeries,
    playoffBracket2026,
    finalsGamePredictions,
    shotsIndex,
    shotsMetadata,
  } = loadAllDatasets();

  it('clutch_leverage_metrics.json: shotBreakdown zone fga/fgm and pct ranges are valid', () => {
    for (const p of clutch) {
      expect(p.tsDelta).toBeDefined();
      expect(Number.isFinite(p.tsDelta)).toBe(true);

      const zones = [
        ['rim', p.shotBreakdown.rim],
        ['mid', p.shotBreakdown.mid],
        ['three', p.shotBreakdown.three],
      ] as const;
      for (const [_, split] of zones) {
        expect(split.fga).toBeGreaterThanOrEqual(0);
        expect(split.fgm).toBeGreaterThanOrEqual(0);
        expect(split.fgm).toBeLessThanOrEqual(split.fga);
        expect(split.pct).toBeGreaterThanOrEqual(0);
        expect(split.pct).toBeLessThanOrEqual(100);
      }
    }
  });

  it('defensive_metrics.json: matchupDist pgPct+sgPct+sfPct+pfPct+cPct sums to ~100%', () => {
    for (const p of defense) {
      const distSum =
        p.matchupDist.pgPct +
        p.matchupDist.sgPct +
        p.matchupDist.sfPct +
        p.matchupDist.pfPct +
        p.matchupDist.cPct;
      expect(distSum, `${p.playerName} matchupDist sum`).toBeCloseTo(100, 0);
    }
  });

  it('player_dna_profiles.json: every player has 3 historical twins with similarityPct sorted descending', () => {
    for (const p of playerDna) {
      expect(p.historicalTwins.length).toBeGreaterThanOrEqual(3);
      for (let i = 1; i < p.historicalTwins.length; i++) {
        expect(p.historicalTwins[i - 1].similarityPct).toBeGreaterThanOrEqual(
          p.historicalTwins[i].similarityPct
        );
      }
    }
  });

  it('coaching_metrics.json: talentExpectedWins + coachingWinsAdded ≈ actualProjectedWins for all 15 staffs', () => {
    for (const c of coaches) {
      expect(
        c.metrics.talentExpectedWins + c.metrics.coachingWinsAdded,
        `${c.teamAbbr} talent bridge`
      ).toBeCloseTo(c.metrics.actualProjectedWins, 1);
    }
  });

  it('offseason_draft.json: picks are 1..15', () => {
    expect(offseasonDraft.map((p) => p.pick)).toEqual(
      Array.from({ length: 15 }, (_, i) => i + 1)
    );
  });

  it('offseason_teams.json: baseline_wins + net_wins_change ≈ projected_wins_with_moves', () => {
    for (const t of offseasonTeams) {
      expect(
        t.baseline_wins + t.net_wins_change,
        `${t.team} offseason wins delta`
      ).toBeCloseTo(t.projected_wins_with_moves, 1);
    }
  });

  it('playoff_series_matchups.json: 8-player playoff rotations sum to ~200 team minutes, and sampleMatchups winProbA + winProbB = 1', () => {
    const profileList = Object.values(playoffSeries.teams);
    expect(profileList).toHaveLength(15);

    for (const team of profileList) {
      const playoffMpgSum = sum(team.rotation.map((r) => r.playoffMpg));
      expect(
        Math.abs(playoffMpgSum - 200),
        `${team.teamAbbr} 8-player rotation minutes=${playoffMpgSum.toFixed(1)}`
      ).toBeLessThanOrEqual(5);
    }

    for (const m of playoffSeries.sampleMatchups) {
      expect(m.winProbA + m.winProbB, `${m.teamA} vs ${m.teamB} winProb sum`).toBeCloseTo(1.0, 2);
      const distSum = sum(m.gameDistributions.map((g) => g.probPct));
      expect(
        Math.abs(distSum - 100),
        `${m.teamA} vs ${m.teamB} gameDistributions sum=${distSum.toFixed(1)}`
      ).toBeLessThanOrEqual(1.0);
    }
  });

  it('playoff_bracket_2026.json: series arithmetic is self-consistent and prediction distributions are proper', () => {
    const bracket = playoffBracket2026;
    const maxWinsByRound: Record<string, number> = { 'Round 1': 2, Semifinals: 3, Finals: 4 };

    for (const s of bracket.series) {
      const label = `${s.teamA} vs ${s.teamB} (${s.round})`;

      // Resolved half: wins must account for every game played, and the
      // winner/leader column must be the side that actually has more wins.
      expect(s.winsA + s.winsB, `${label} wins do not sum to gamesPlayed`).toBe(s.gamesPlayed);
      expect(s.seriesLength, `${label} seriesLength != gamesPlayed`).toBe(s.gamesPlayed);
      expect(s.games, `${label} games[] length != gamesPlayed`).toHaveLength(s.gamesPlayed);
      const leader = s.winsA > s.winsB ? s.teamA : s.teamB;
      expect(s.winner, `${label} winner is not the side with more wins`).toBe(leader);

      // seriesComplete must agree with the round's win threshold rather than
      // being implied by games played — the in-progress Finals depends on this.
      const threshold = maxWinsByRound[s.round];
      expect(threshold, `${label} unexpected round label`).toBeDefined();
      expect(s.seriesComplete, `${label} seriesComplete disagrees with win threshold`).toBe(
        Math.max(s.winsA, s.winsB) >= threshold
      );

      const f = s.prediction.forecast;
      if (f === null) continue;

      expect(f.pHighSeedWin + f.pLowSeedWin, `${label} win probs do not sum to 1`).toBeCloseTo(1, 6);
      const distSum = sum(f.lengthDistribution.map((d) => d.probability));
      expect(distSum, `${label} lengthDistribution sums to ${distSum}`).toBeCloseTo(1, 4);

      // expectedGames must be the mean of the distribution it ships with.
      const mean = sum(f.lengthDistribution.map((d) => d.length * d.probability));
      expect(f.expectedGames, `${label} expectedGames != mean of lengthDistribution`).toBeCloseTo(mean, 3);

      // predictedWinner must be whichever side the probability actually favours.
      const favoured = f.pHighSeedWin >= 0.5 ? f.teamHigh : f.teamLow;
      expect(f.predictedWinnerName, `${label} predictedWinnerName is not the favoured side`).toBe(favoured);

      // resultStatus must reflect the real outcome, and must be 'pending'
      // (never 'incorrect') while the series is still being played.
      const expected = !s.seriesComplete
        ? 'pending'
        : f.predictedWinnerName === s.winnerName
          ? 'correct'
          : 'incorrect';
      expect(f.resultStatus, `${label} resultStatus is wrong`).toBe(expected);
    }
  });

  it('playoff_bracket_2026.json: each round carries its own prediction provenance, and none claims to be held out', () => {
    const bracket = playoffBracket2026;
    expect(bracket.series.length, 'bracket has no series').toBeGreaterThan(0);

    const round1 = bracket.series.filter((s) => s.round === 'Round 1');
    const semis = bracket.series.filter((s) => s.round === 'Semifinals');
    expect(round1.length, 'expected 4 Round 1 series').toBe(4);
    expect(semis.length, 'expected 2 Semifinals series').toBe(2);

    // Round 1 has no archived forecast and is a reconstruction; the Semifinals
    // carry the dated pre-series archive. The two rounds use different ratings
    // bases on purpose (the archive pooled postseason games into its ratings),
    // so each must state its own basis and they must not be interchangeable.
    for (const s of round1) {
      expect(s.prediction.provenance, `${s.teamA} vs ${s.teamB}`).toBe('round1_reconstruction');
      expect(s.prediction.forecast!.asOf, 'a reconstruction has no as-of date').toBe('');
      expect(s.prediction.forecast!.ratingBasis).toContain('season_type == 2');
    }
    for (const s of semis) {
      expect(s.prediction.provenance, `${s.teamA} vs ${s.teamB}`).toBe('archived_forecast');
      expect(s.prediction.forecast!.asOf, 'an archived forecast must be dated').toMatch(
        /^\d{4}-\d{2}-\d{2}$/
      );
    }
    const bases = new Set(bracket.series.filter((s) => s.prediction.forecast).map((s) => s.prediction.forecast!.ratingBasis));
    expect(bases.size, 'Round 1 and the Semifinals must not share one ratings basis').toBeGreaterThan(1);

    // Neither round is a clean held-out test: Round 1 is retrodicted after the
    // fact, and the archived semifinal ratings pooled in Round 1's playoff games.
    // No label in the payload may claim otherwise. The phrase is matched as a
    // regex rather than written out, so this guard does not itself plant the
    // very wording it exists to forbid.
    const haystack = JSON.stringify(bracket).toLowerCase();
    expect(haystack, 'a prediction label claims a held-out sample').not.toMatch(
      /out[-\s]of[-\s]sample/
    );
  });

  // --------------------------------------------------------------------------
  // finals_game_predictions_2026.json (GitHub issue #94)
  //
  // The whole point of this payload is that each game carries TWO numbers that
  // answer different questions, so these guard the relationship between them --
  // that is where a producer change would silently break the section's meaning.
  // --------------------------------------------------------------------------
  it('finals_game_predictions_2026.json: P(game played) is 1 through game 4, then strictly decreasing, and matches the series-length tail', () => {
    const f = finalsGamePredictions;
    if (f.matchup === null) {
      expect(f.games, 'no matchup must mean no games').toHaveLength(0);
      return;
    }
    expect(f.games, 'a best-of-7 has seven game rows').toHaveLength(7);
    expect(f.games.map((g) => g.game)).toEqual([1, 2, 3, 4, 5, 6, 7]);

    for (const g of f.games.slice(0, 4)) {
      expect(g.pGamePlayed, `game ${g.game} is always played in a best-of-7`).toBeCloseTo(1, 9);
    }
    for (const g of f.games.slice(4)) {
      expect(g.pGamePlayed, `game ${g.game} may never be played`).toBeLessThan(1);
    }
    // Strictly decreasing across 5, 6, 7: each further game needs the series to
    // have stayed alive one game longer.
    const tail = f.games.slice(4).map((g) => g.pGamePlayed);
    for (let i = 1; i < tail.length; i++) {
      expect(tail[i], `P(game ${i + 6} played) must be below P(game ${i + 5} played)`).toBeLessThan(
        tail[i - 1]
      );
    }

    // The consistency relation the DP guarantees by construction:
    //   P(game g played) == sum of P(series length >= g).
    for (const g of f.games) {
      const expected = f.lengthDistribution
        .filter((d) => d.length >= g.game)
        .reduce((acc, d) => acc + d.probability, 0);
      expect(
        g.pGamePlayed,
        `game ${g.game}: P(played) must equal P(series length >= ${g.game})`
      ).toBeCloseTo(expected, 6);
    }
  });

  it('finals_game_predictions_2026.json: host assignment follows the 2-2-1-1-1 pattern and the HCA sign flips with it', () => {
    const f = finalsGamePredictions;
    if (f.matchup === null) return;

    // PLAYOFF_FORMATS$bo7$home_flags = c(TRUE, TRUE, FALSE, FALSE, TRUE, FALSE, TRUE).
    expect(f.games.map((g) => g.hostIsHighSeed)).toEqual([
      true,
      true,
      false,
      false,
      true,
      false,
      true,
    ]);
    for (const g of f.games) {
      const expectedHost = g.hostIsHighSeed ? f.matchup.teamHighAbbr : f.matchup.teamLowAbbr;
      expect(g.hostAbbr, `game ${g.game} host`).toBe(expectedHost);
    }

    // Home court is worth something: the home-court side's win probability must be
    // strictly higher in the games it hosts than in the games it does not.
    const hosted = f.games.filter((g) => g.hostIsHighSeed).map((g) => g.pHighSeedWinHca);
    const away = f.games.filter((g) => !g.hostIsHighSeed).map((g) => g.pHighSeedWinHca);
    expect(Math.min(...hosted), 'hosting must help the home-court side').toBeGreaterThan(
      Math.max(...away)
    );
    // Within a basis, every hosted game shares one probability and every away game
    // another: the only per-game input to the HCA-only figure is the host flag.
    expect(new Set(hosted.map((p) => p.toFixed(9))).size).toBe(1);
    expect(new Set(away.map((p) => p.toFixed(9))).size).toBe(1);
  });

  it('finals_game_predictions_2026.json: played games carry a result and a verdict, unplayed games carry neither', () => {
    const f = finalsGamePredictions;
    if (f.matchup === null) return;

    const played = f.games.filter((g) => g.resultAvailable);
    const unplayed = f.games.filter((g) => !g.resultAvailable);

    for (const g of played) {
      expect(g.scoreHigh, `game ${g.game} score`).not.toBeNull();
      expect(g.scoreLow, `game ${g.game} score`).not.toBeNull();
      expect(g.resultStatus, `game ${g.game} verdict`).not.toBe('pending');
      expect(g.gameDate, `game ${g.game} date`).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      // The verdict must follow from the score and the forecast, not float free.
      const highWon = (g.scoreHigh as number) > (g.scoreLow as number);
      const highFavoured = g.pHighSeedWinHca >= 0.5;
      expect(g.resultStatus).toBe(highWon === highFavoured ? 'correct' : 'incorrect');
    }
    for (const g of unplayed) {
      expect(g.scoreHigh, `game ${g.game} must have no score`).toBeNull();
      expect(g.scoreLow, `game ${g.game} must have no score`).toBeNull();
      expect(g.resultStatus, `game ${g.game} must have no verdict`).toBe('pending');
    }
    // Games resolve in order, so the played games are a prefix of the seven.
    expect(played.map((g) => g.game)).toEqual(
      Array.from({ length: played.length }, (_, i) => i + 1)
    );
    // Wins on record must add up to the games actually resolved.
    expect(f.matchup.winsHigh + f.matchup.winsLow).toBeGreaterThanOrEqual(played.length);
  });

  it('finals_game_predictions_2026.json: the rest adjustment is applied per game and only moves the probability when the two sides differ', () => {
    const f = finalsGamePredictions;
    if (f.matchup === null || !f.restApplied) return;

    for (const g of f.games.filter((x) => x.restApplied)) {
      expect(g.fatigueDragHigh, `game ${g.game} drag`).not.toBeNull();
      expect(g.fatigueDragLow, `game ${g.game} drag`).not.toBeNull();
      expect(g.pHighSeedWinWithRest, `game ${g.game} rest-adjusted p`).not.toBeNull();

      const equalDrag =
        Math.abs((g.fatigueDragHigh as number) - (g.fatigueDragLow as number)) < 1e-9;
      if (equalDrag) {
        // Symmetric fatigue cancels in the rating difference, so it must not move
        // the number at all -- a drift here would mean rest is being double-counted.
        expect(
          g.pHighSeedWinWithRest as number,
          `game ${g.game}: equal fatigue must not change the probability`
        ).toBeCloseTo(g.pHighSeedWinHca, 6);
      } else {
        // Whichever side is less fatigued must be the side the adjustment helps.
        const highIsFresher = (g.fatigueDragHigh as number) < (g.fatigueDragLow as number);
        const moved = (g.pHighSeedWinWithRest as number) - g.pHighSeedWinHca;
        expect(
          highIsFresher ? moved : -moved,
          `game ${g.game}: rest must favour the fresher side`
        ).toBeGreaterThan(0);
      }
      expect((g.pHighSeedWinWithRest as number) + (g.pLowSeedWinWithRest as number)).toBeCloseTo(
        1,
        6
      );
    }
  });

  it('shots_metadata.json & shots_index.json: 14 canonical zones and player shot file lengths match catalog total_shots', () => {
    expect(shotsMetadata.zones).toEqual([...EXPECTED_SHOT_ZONES]);
    expect(shotsMetadata.league_averages).toHaveLength(14);
    for (const z of shotsMetadata.league_averages) {
      expect(z.lg_fg_pct, `${z.zone} lg_fg_pct`).toBeCloseTo(z.total_fgm / z.total_fga, 2);
    }

    for (const entry of shotsIndex.slice(0, 15)) {
      const fileData = readPlayerShotFile(entry.player_id);
      expect(fileData.total_shots).toBe(entry.total_shots);
      expect(fileData.shots).toHaveLength(entry.total_shots);
    }
  });
});

// ---------------------------------------------------------------------------
// matchups_slates.json (build_matchups_dataset.R, issue #74).
//
// The Zod schema in schemas.ts already enforces per-record shape and the
// within-record consistency rules. What is here instead is the arithmetic that
// crosses records: the summary and per-week rollups must be RECOMPUTABLE from
// the matchups array, so a rollup can never drift away from the games it
// claims to describe.
// ---------------------------------------------------------------------------
describe('Domain & mathematical invariants: matchups_slates.json', () => {
  const { matchups: m } = loadAllDatasets();

  it('summary counts are exactly recomputable from the matchups array', () => {
    const completed = m.matchups.filter((g) => g.is_completed);
    const graded = m.matchups.filter((g) => g.is_graded);
    const correct = graded.filter((g) => g.prediction_correct === true);

    expect(m.summary.total_games).toBe(m.matchups.length);
    expect(m.summary.completed_games).toBe(completed.length);
    expect(m.summary.pending_games).toBe(m.matchups.length - completed.length);
    expect(m.summary.graded_games).toBe(graded.length);

    if (graded.length > 0) {
      expect(m.summary.correct_games).toBe(correct.length);
      expect(m.summary.accuracy_pct).toBeCloseTo((100 * correct.length) / graded.length, 1);
    } else {
      expect(m.summary.correct_games).toBeNull();
      expect(m.summary.accuracy_pct).toBeNull();
    }

    // The honest-coverage figure the page renders. If this drifts, the page
    // understates how much of the season the model never predicted.
    expect(m.summary.played_without_logged_prediction).toBe(
      completed.filter((g) => !g.has_logged_prediction).length
    );
  });

  it('every week rollup is recomputable from that week\'s games, and the weeks partition the games exactly', () => {
    const weekNumbers = m.weeks.map((w) => w.week);
    expect(new Set(weekNumbers).size).toBe(m.weeks.length);
    expect(weekNumbers).toEqual([...weekNumbers].sort((a, b) => a - b));

    // available_weeks must be exactly the weeks that have games -- no phantom
    // entries, nothing missing. This is what lets the ribbon iterate it.
    const weeksInGames = [...new Set(m.matchups.map((g) => g.week))].sort((a, b) => a - b);
    expect(m.available_weeks).toEqual(weeksInGames);
    expect(weekNumbers).toEqual(weeksInGames);

    let covered = 0;
    for (const w of m.weeks) {
      const games = m.matchups.filter((g) => g.week === w.week);
      covered += games.length;
      const completed = games.filter((g) => g.is_completed);
      const graded = games.filter((g) => g.is_graded);
      const correct = graded.filter((g) => g.prediction_correct === true);

      expect(w.total_games, `week ${w.week} total_games`).toBe(games.length);
      expect(w.completed_games, `week ${w.week} completed_games`).toBe(completed.length);
      expect(w.pending_games, `week ${w.week} pending_games`).toBe(
        games.length - completed.length
      );
      expect(w.graded_games, `week ${w.week} graded_games`).toBe(graded.length);

      if (graded.length > 0) {
        expect(w.correct_games, `week ${w.week} correct_games`).toBe(correct.length);
        expect(w.accuracy_pct, `week ${w.week} accuracy_pct`).toBeCloseTo(
          (100 * correct.length) / graded.length,
          1
        );
      } else {
        expect(w.correct_games, `week ${w.week} correct_games`).toBeNull();
        expect(w.accuracy_pct, `week ${w.week} accuracy_pct`).toBeNull();
      }

      const dates = games.map((g) => g.game_date).sort();
      expect(w.start_date, `week ${w.week} start_date`).toBe(dates[0]);
      expect(w.end_date, `week ${w.week} end_date`).toBe(dates[dates.length - 1]);
      expect(
        [...w.season_types].sort(),
        `week ${w.week} season_types`
      ).toEqual([...new Set(games.map((g) => g.season_type))].sort());
    }
    // Partition, not merely a cover: every game belongs to exactly one week.
    expect(covered).toBe(m.matchups.length);
  });

  it('the week bucket of every game follows floor((date - season_start) / 7) + 1', () => {
    // The definition in build_matchups_dataset.R (DESIGN DECISION 1). Pinned
    // here because the ribbon, the rollups and active_week all assume it.
    const start = Date.parse(`${m.season_start}T00:00:00Z`);
    for (const g of m.matchups) {
      const days = (Date.parse(`${g.game_date}T00:00:00Z`) - start) / 86_400_000;
      expect(g.week, `${g.game_date} ${g.away_team}@${g.home_team}`).toBe(
        Math.floor(days / 7) + 1
      );
    }
  });

  it('season_start and season_end bound every game date', () => {
    const dates = m.matchups.map((g) => g.game_date).sort();
    expect(m.season_start).toBe(dates[0]);
    expect(m.season_end).toBe(dates[dates.length - 1]);
  });

  it('active_week is the last week containing a played game', () => {
    const playedWeeks = m.matchups.filter((g) => g.is_completed).map((g) => g.week);
    if (playedWeeks.length > 0) {
      expect(m.active_week).toBe(Math.max(...playedWeeks));
    } else {
      expect(m.active_week).toBe(Math.min(...m.available_weeks));
    }
  });

  it('provenance basis_counts and logged-prediction count match the games', () => {
    const counts: Record<string, number> = {
      logged_model: 0,
      logged_model_prob_only: 0,
      team_rating_differential: 0,
      none: 0,
    };
    for (const g of m.matchups) {
      counts[g.projection_basis ?? 'none'] += 1;
    }
    for (const [basis, n] of Object.entries(counts)) {
      expect(m.provenance.basis_counts[basis] ?? 0, `basis ${basis}`).toBe(n);
    }
    // Every game is accounted for by exactly one basis (or none).
    expect(Object.values(m.provenance.basis_counts).reduce((a, b) => a + b, 0)).toBe(
      m.matchups.length
    );

    expect(m.provenance.games_with_logged_prediction).toBe(
      m.matchups.filter((g) => g.has_logged_prediction).length
    );
    expect(m.provenance.log_match_pct).toBeCloseTo(
      (100 * m.provenance.logged_predictions_matched) /
        m.provenance.logged_predictions_in_window,
      1
    );
  });

  it('only the logged model basis is ever graded, and every graded game is a logged one', () => {
    // The central honesty invariant of this payload: the rating-differential
    // fill is weaker and must never enter the accuracy figure. Asserted in
    // aggregate here as well as per-record in the Zod schema, because this is
    // the property that would silently inflate the published accuracy.
    for (const g of m.matchups) {
      if (g.projection_basis === 'team_rating_differential') {
        expect(g.is_graded, `${g.game_id} graded on the rating basis`).toBe(false);
        expect(g.prediction_correct, `${g.game_id} graded on the rating basis`).toBeNull();
      }
    }
    expect(m.summary.graded_games).toBe(
      m.matchups.filter((g) => g.is_graded && g.has_logged_prediction).length
    );
  });

  it('scores, margins and winners are mutually consistent for every played game', () => {
    for (const g of m.matchups.filter((x) => x.is_completed)) {
      const label = `${g.game_date} ${g.away_team}@${g.home_team}`;
      expect(g.actual_margin, label).toBe((g.home_score as number) - (g.away_score as number));
      expect(g.actual_winner, label).toBe(
        (g.actual_margin as number) > 0 ? g.home_team : g.away_team
      );
    }
  });

  it('predicted_winner agrees with the sign of projected_margin and names one of the two teams', () => {
    for (const g of m.matchups) {
      if (g.predicted_winner === null) continue;
      const label = `${g.game_date} ${g.away_team}@${g.home_team}`;
      expect([g.home_team, g.away_team], label).toContain(g.predicted_winner);
      // Only checked for the rating basis: a LOGGED predicted_winner is copied
      // verbatim from the accuracy log and is the log's own call, so a
      // disagreement there is the logger's to explain, not this stage's.
      if (g.projection_basis === 'team_rating_differential' && g.projected_margin !== null) {
        expect(g.predicted_winner, label).toBe(
          g.projected_margin > 0 ? g.home_team : g.away_team
        );
      }
    }
  });

  it('game_ids are unique, so no fixture is double-counted in any rollup', () => {
    const ids = m.matchups.map((g) => g.game_id);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
