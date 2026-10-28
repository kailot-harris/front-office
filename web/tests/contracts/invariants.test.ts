/**
 * Layer 2 — Domain & mathematical invariants across all MLB datasets.
 */
import { describe, it, expect } from 'vitest';
import {
  MLB_TEAMS,
  MLB_DIVISIONS,
  LEAGUE,
  loadAllDatasets,
  readMatchupWeekFile,
} from '../helpers/datasets';

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

describe('Domain & mathematical invariants: projections_season_teams.json', () => {
  const { teams, metadata } = loadAllDatasets();

  it('contains all 30 unique MLB teams ranked 1..30', () => {
    expect(teams.map((t) => t.team).sort()).toEqual([...MLB_TEAMS].sort());
    expect(teams.map((t) => t.rank).sort((a, b) => a - b)).toEqual(
      Array.from({ length: 30 }, (_, i) => i + 1),
    );
  });

  it('has 15 AL teams and 15 NL teams, 5 per division', () => {
    const al = teams.filter((t) => t.league === 'AL');
    const nl = teams.filter((t) => t.league === 'NL');
    expect(al).toHaveLength(15);
    expect(nl).toHaveLength(15);

    for (const div of MLB_DIVISIONS) {
      expect(teams.filter((t) => t.division === div)).toHaveLength(5);
    }
  });

  it('proj_wins + proj_losses equals 162 for every team, and win_pct ≈ proj_wins / 162', () => {
    for (const t of teams) {
      expect(t.proj_wins + t.proj_losses, `${t.team} wins+losses`).toBeCloseTo(162, 1);
      expect(t.win_pct, `${t.team} win_pct`).toBeCloseTo(t.proj_wins / 162, 2);
    }
  });

  it('percentile ordering holds: p10 <= p25 <= p50 <= p75 <= p90 for every team across all variants', () => {
    const variants = [
      'ensemble',
      'variant_bottom_up',
      'variant_rapm',
      'variant_shot_fatigue',
      'variant_embeddings',
    ] as const;

    for (const t of teams) {
      for (const v of variants) {
        const row = t as unknown as Record<string, unknown>;
        const p10 = row[`${v}_p10`] as number;
        const p25 = row[`${v}_p25`] as number;
        const p50 = row[`${v}_p50`] as number;
        const p75 = row[`${v}_p75`] as number;
        const p90 = row[`${v}_p90`] as number;

        expect(p10, `${t.team} ${v} p10<=p25`).toBeLessThanOrEqual(p25);
        expect(p25, `${t.team} ${v} p25<=p50`).toBeLessThanOrEqual(p50);
        expect(p50, `${t.team} ${v} p50<=p75`).toBeLessThanOrEqual(p75);
        expect(p75, `${t.team} ${v} p75<=p90`).toBeLessThanOrEqual(p90);
      }
    }
  });

  it('zero-sum schedule conservation: sum of projected wins across 30 teams ≈ total_schedule_games (2430)', () => {
    const totalGames = metadata.total_schedule_games;
    expect(totalGames).toBe(LEAGUE.GAMES_PER_SEASON);

    const sumProjWins = sum(teams.map((t) => t.proj_wins));
    const sumEnsembleWins = sum(teams.map((t) => t.ensemble_mean_wins));

    expect(Math.abs(sumProjWins - totalGames), `sum(proj_wins)=${sumProjWins}`).toBeLessThanOrEqual(2.0);
    expect(Math.abs(sumEnsembleWins - totalGames), `sum(ensemble_mean_wins)=${sumEnsembleWins}`).toBeLessThanOrEqual(2.0);
  });

  it('probability conservation: 12 MLB playoff spots (sum(playoff_prob) ≈ 12.0)', () => {
    const sumPlayoffProb = sum(teams.map((t) => t.ensemble_playoff_prob));
    expect(
      Math.abs(sumPlayoffProb - LEAGUE.PLAYOFF_FIELD),
      `sum(ensemble_playoff_prob) = ${sumPlayoffProb.toFixed(4)}`,
    ).toBeLessThanOrEqual(0.25);
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
        diagnostics.calibration[i - 1].midpoint,
      );
    }
  });
});

describe('Domain & mathematical invariants: cbt_payroll_sheet.json', () => {
  const { cbtSheet } = loadAllDatasets();

  it('league CBT thresholds satisfy base < tier1 < tier2 < tier3', () => {
    expect(cbtSheet.baseThreshold).toBe(LEAGUE.CBT_2026.BASE);
    expect(cbtSheet.tier1Threshold).toBe(LEAGUE.CBT_2026.TIER1);
    expect(cbtSheet.tier2Threshold).toBe(LEAGUE.CBT_2026.TIER2);
    expect(cbtSheet.tier3Threshold).toBe(LEAGUE.CBT_2026.TIER3);
  });

  it('every team calculation for CBT space, tax bill, and total commitment is coherent', () => {
    for (const t of cbtSheet.teams) {
      expect(t.cbtSpace2026).toBeCloseTo(Math.max(0, cbtSheet.baseThreshold - t.payroll2026), 1);
      expect(t.totalCommitment).toBeCloseTo(t.payroll2026 + t.cbtTaxBill, 1);
      if (t.payroll2026 <= cbtSheet.baseThreshold) {
        expect(t.cbtTaxBill, `${t.teamAbbr} under CBT should have 0 tax`).toBe(0);
      }
    }
  });

  it('league summary payroll and luxury tax totals match franchise rollups', () => {
    const sumPayroll = sum(cbtSheet.teams.map((t) => t.payroll2026));
    const sumTax = sum(cbtSheet.teams.map((t) => t.cbtTaxBill));
    expect(cbtSheet.totalLeaguePayroll).toBeCloseTo(sumPayroll, 0);
    expect(cbtSheet.totalLuxuryTaxCollected).toBeCloseTo(sumTax, 0);
  });
});

describe('Domain & mathematical invariants: matchups_index.json & week slates', () => {
  const { matchupsIndex } = loadAllDatasets();

  it('week game_count, graded_count, and correct_count roll up to index totals', () => {
    const sumGames = sum(matchupsIndex.available_weeks.map((w) => w.game_count));
    const sumGraded = sum(matchupsIndex.available_weeks.map((w) => w.graded_count));
    const sumCorrect = sum(matchupsIndex.available_weeks.map((w) => w.correct_count));

    expect(sumGames).toBe(matchupsIndex.total_games);
    expect(sumGraded).toBe(matchupsIndex.graded_games);
    expect(sumCorrect).toBe(matchupsIndex.correct_picks);

    let completedAcrossWeeks = 0;
    for (const w of matchupsIndex.available_weeks) {
      const games = readMatchupWeekFile(w.week);
      completedAcrossWeeks += games.filter((g) => g.is_completed).length;
    }
    expect(completedAcrossWeeks).toBe(matchupsIndex.completed_games);
  });
});

describe('Domain & mathematical invariants: world_series.json', () => {
  const { worldSeries } = loadAllDatasets();

  it('completed games and series wins agree between top-level sides and game rows', () => {
    const completed = worldSeries.games.filter((g) => g.is_completed);
    expect(completed).toHaveLength(worldSeries.games_played);

    const hfWins = completed.filter((g) => g.winner === worldSeries.home_field.team).length;
    const chWins = completed.filter((g) => g.winner === worldSeries.challenger.team).length;
    expect(worldSeries.home_field.wins).toBe(hfWins);
    expect(worldSeries.challenger.wins).toBe(chWins);
  });
});
