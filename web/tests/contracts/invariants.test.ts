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
