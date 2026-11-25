/**
 * Layer 2 — Domain & mathematical invariants across all datasets.
 */
import { describe, it, expect } from 'vitest';
import {
  NBA_TEAMS,
  EXPECTED_SHOT_ZONES,
  LEAGUE,
  loadAllDatasets,
  readPlayerShotFile,
} from '../helpers/datasets';
import { CLUTCH_MIN_FGA } from '@/lib/clutchTypes';

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0);

describe('Domain & mathematical invariants: projections_season_teams.json', () => {
  const { teams, metadata } = loadAllDatasets();

  it('contains all 30 unique NBA teams ranked 1..30', () => {
    expect(teams.map((t) => t.team).sort()).toEqual([...NBA_TEAMS].sort());
    expect(teams.map((t) => t.rank).sort((a, b) => a - b)).toEqual(
      Array.from({ length: 30 }, (_, i) => i + 1)
    );
  });

  it('has exactly 15 East teams and 15 West teams, 5 per division', () => {
    const east = teams.filter((t) => t.conference === 'East');
    const west = teams.filter((t) => t.conference === 'West');
    expect(east).toHaveLength(15);
    expect(west).toHaveLength(15);

    const divisions = ['Atlantic', 'Central', 'Southeast', 'Northwest', 'Pacific', 'Southwest'];
    for (const div of divisions) {
      expect(teams.filter((t) => t.division === div)).toHaveLength(5);
    }
  });

  it('proj_wins + proj_losses equals 82 for every team, and win_pct ≈ proj_wins / 82', () => {
    for (const t of teams) {
      expect(t.proj_wins + t.proj_losses, `${t.team} wins+losses`).toBeCloseTo(82, 1);
      expect(t.win_pct, `${t.team} win_pct`).toBeCloseTo(t.proj_wins / 82, 2);
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
        const p10 = (t as any)[`${v}_p10`];
        const p25 = (t as any)[`${v}_p25`];
        const p50 = (t as any)[`${v}_p50`];
        const p75 = (t as any)[`${v}_p75`];
        const p90 = (t as any)[`${v}_p90`];
        const mean = (t as any)[`${v}_mean_wins`];

        expect(p10, `${t.team} ${v} p10<=p25`).toBeLessThanOrEqual(p25);
        expect(p25, `${t.team} ${v} p25<=p50`).toBeLessThanOrEqual(p50);
        expect(p50, `${t.team} ${v} p50<=p75`).toBeLessThanOrEqual(p75);
        expect(p75, `${t.team} ${v} p75<=p90`).toBeLessThanOrEqual(p90);
        expect(mean, `${t.team} ${v} mean in [p10-0.5, p90+0.5]`).toBeGreaterThanOrEqual(p10 - 0.5);
        expect(mean, `${t.team} ${v} mean in [p10-0.5, p90+0.5]`).toBeLessThanOrEqual(p90 + 0.5);
      }
    }
  });

  it('zero-sum schedule conservation: sum of projected wins across 30 teams equals total_schedule_games (1230)', () => {
    const totalGames = metadata.total_schedule_games; // 30 * 82 / 2 = 1230
    expect(totalGames).toBe(1230);

    const sumProjWins = sum(teams.map((t) => t.proj_wins));
    const sumEnsembleWins = sum(teams.map((t) => t.ensemble_mean_wins));
    const sumBottomUpWins = sum(teams.map((t) => t.variant_bottom_up_mean_wins));
    const sumRapmWins = sum(teams.map((t) => t.variant_rapm_mean_wins));
    const sumShotFatigueWins = sum(teams.map((t) => t.variant_shot_fatigue_mean_wins));
    const sumEmbeddingsWins = sum(teams.map((t) => t.variant_embeddings_mean_wins));

    expect(Math.abs(sumProjWins - totalGames), `sum(proj_wins)=${sumProjWins}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(sumEnsembleWins - totalGames), `sum(ensemble_mean_wins)=${sumEnsembleWins}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(sumBottomUpWins - totalGames), `sum(bu_mean_wins)=${sumBottomUpWins}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(sumRapmWins - totalGames), `sum(rapm_mean_wins)=${sumRapmWins}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(sumShotFatigueWins - totalGames), `sum(shot_mean_wins)=${sumShotFatigueWins}`).toBeLessThanOrEqual(0.5);
    expect(Math.abs(sumEmbeddingsWins - totalGames), `sum(emb_mean_wins)=${sumEmbeddingsWins}`).toBeLessThanOrEqual(0.5);
  });

  it('probability conservation: 16 playoff spots (sum(playoff_prob) ≈ 16.0) and 1 champion (sum(title_prob) ≈ 1.0)', () => {
    const sumPlayoffProb = sum(teams.map((t) => t.ensemble_playoff_prob));
    const sumTitleProb = sum(teams.map((t) => t.ensemble_title_prob));

    expect(
      Math.abs(sumPlayoffProb - 16.0),
      `sum(ensemble_playoff_prob) = ${sumPlayoffProb.toFixed(4)}`
    ).toBeLessThanOrEqual(0.15);

    expect(
      Math.abs(sumTitleProb - 1.0),
      `sum(ensemble_title_prob) = ${sumTitleProb.toFixed(4)}`
    ).toBeLessThanOrEqual(0.03);
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
        `${t.team}: ensemble=${t.ensemble_mean_wins} vs blend=${expectedBlend.toFixed(2)}`
      ).toBeLessThanOrEqual(0.5);
    }
  });
});

describe('Domain & mathematical invariants: projections_season_players.json', () => {
  const { players } = loadAllDatasets();

  it('has unique player_ids and exactly 11 players per team across all 30 teams (330 total)', () => {
    expect(players).toHaveLength(LEAGUE.ACTIVE_PLAYER_POOL);
    const ids = players.map((p) => p.player_id);
    expect(new Set(ids).size).toBe(ids.length);

    const counts = players.reduce((acc, p) => {
      acc[p.team] = (acc[p.team] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    for (const team of NBA_TEAMS) {
      expect(counts[team], `${team} player count`).toBe(11);
    }
  });

  it('season totals match per-game * proj_games, percentiles are monotonic, and is_outlier matches |z| >= 2.0', () => {
    for (const p of players) {
      // season_simulator.R derives the per-game rate from the same unrounded
      // simulation means as the total, so total == per_game * games holds
      // EXACTLY before publishing. All three figures are then published to one
      // decimal, and multiplying two independently rounded numbers inflates the
      // error by their magnitudes: a half-unit of the last decimal on each of
      // per_game and games is +/- 0.05 * (games + per_game). That product, not
      // a flat constant, is the contract - it is far tighter than a magic 5 for
      // a bench player and correctly looser for a 70-game, 26-point starter.
      const totalTolerance = (perGame: number) => 0.05 * (p.proj_games + perGame) + 0.1;

      expect(
        Math.abs(p.proj_pts_total - p.proj_pts * p.proj_games),
        `${p.player_name} pts_total`,
      ).toBeLessThanOrEqual(totalTolerance(p.proj_pts));
      expect(
        Math.abs(p.proj_reb_total - p.proj_reb * p.proj_games),
        `${p.player_name} reb_total`,
      ).toBeLessThanOrEqual(totalTolerance(p.proj_reb));
      expect(
        Math.abs(p.proj_ast_total - p.proj_ast * p.proj_games),
        `${p.player_name} ast_total`,
      ).toBeLessThanOrEqual(totalTolerance(p.proj_ast));

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
      expect(p.is_outlier, `${p.player_name} outlier flag vs max|z|=${maxAbsZ}`).toBe(maxAbsZ >= 2.0);
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
      expect(diagnostics.calibration[i].midpoint).toBeGreaterThan(diagnostics.calibration[i - 1].midpoint);
    }
  });
});

describe('Domain & mathematical invariants: cba_cap_sheet.json', () => {
  const { cbaCapSheet } = loadAllDatasets();

  it('league cap thresholds satisfy salaryCap < luxuryTaxThreshold < firstApron < secondApron', () => {
    expect(cbaCapSheet.salaryCap).toBe(165.0);
    expect(cbaCapSheet.luxuryTaxThreshold).toBe(200.4);
    expect(cbaCapSheet.firstApron).toBe(209.0);
    expect(cbaCapSheet.secondApron).toBe(221.7);
  });

  it('every team calculation for space, tax, and total financial commitment is coherent', () => {
    for (const t of cbaCapSheet.teams) {
      if (t.totalPayroll2026 === null) {
        expect(t.capSpace2026).toBeNull();
        expect(t.taxSpace2026).toBeNull();
        expect(t.firstApronSpace2026).toBeNull();
        expect(t.secondApronSpace2026).toBeNull();
        expect(t.luxuryTaxBill).toBeNull();
        expect(t.totalFinancialCommitment).toBeNull();
        continue;
      }
      expect(t.capSpace2026).toBeCloseTo(Math.max(0, cbaCapSheet.salaryCap - t.totalPayroll2026), 1);
      expect(t.taxSpace2026).toBeCloseTo(cbaCapSheet.luxuryTaxThreshold - t.totalPayroll2026, 1);
      expect(t.firstApronSpace2026).toBeCloseTo(cbaCapSheet.firstApron - t.totalPayroll2026, 1);
      expect(t.secondApronSpace2026).toBeCloseTo(cbaCapSheet.secondApron - t.totalPayroll2026, 1);
      expect(t.totalFinancialCommitment).toBeCloseTo(t.totalPayroll2026 + (t.luxuryTaxBill ?? 0), 1);

      if (t.totalPayroll2026 <= cbaCapSheet.luxuryTaxThreshold) {
        expect(t.luxuryTaxBill, `${t.teamAbbr} under tax should have 0 tax bill`).toBe(0);
      }
    }
  });

  it('league summary team counts and totals match franchise rollups', () => {
    const teamsWithPayroll = cbaCapSheet.teams.filter((t) => t.totalPayroll2026 !== null);
    if (teamsWithPayroll.length === 0) {
      expect(cbaCapSheet.secondApronTeamCount).toBeNull();
      expect(cbaCapSheet.firstApronTeamCount).toBeNull();
      expect(cbaCapSheet.taxTeamCount).toBeNull();
      expect(cbaCapRoomTeamCount(cbaCapSheet)).toBeNull();
      expect(cbaCapSheet.totalLeagueTaxRevenue).toBeNull();
      expect(cbaCapSheet.averagePayroll).toBeNull();
      return;
    }

    const secondApronCount = cbaCapSheet.teams.filter((t) => t.cbaTier === 'Second Apron Restricted').length;
    const firstApronCount = cbaCapSheet.teams.filter((t) => t.cbaTier === 'First Apron Team').length;
    const taxCount = cbaCapSheet.teams.filter((t) => t.totalPayroll2026 !== null && t.totalPayroll2026 > cbaCapSheet.luxuryTaxThreshold).length;
    const capRoomCount = cbaCapSheet.teams.filter((t) => t.capSpace2026 !== null && t.capSpace2026 > 0).length;

    expect(cbaCapSheet.secondApronTeamCount).toBe(secondApronCount);
    expect(cbaCapSheet.firstApronTeamCount).toBe(firstApronCount);
    expect(cbaCapSheet.taxTeamCount).toBe(taxCount);
    expect(cbaCapRoomTeamCount(cbaCapSheet)).toBe(capRoomCount);

    const totalTaxRevenue = sum(cbaCapSheet.teams.map((t) => t.luxuryTaxBill ?? 0));
    expect(cbaCapSheet.totalLeagueTaxRevenue).toBeCloseTo(totalTaxRevenue, 1);

    const avgPayroll = sum(teamsWithPayroll.map((t) => t.totalPayroll2026 as number)) / teamsWithPayroll.length;
    expect(cbaCapSheet.averagePayroll).toBeCloseTo(avgPayroll, 1);
  });

  function cbaCapRoomTeamCount(cba: typeof cbaCapSheet) {
    return cba.capRoomTeamCount;
  }
});

describe('Domain & mathematical invariants: clutch, defense, playerDna, coaches, offseason, playoffSeries, shots', () => {
  const {
    clutch,
    defense,
    playerDna,
    coaches,
    offseasonDraft,
    offseasonTeams,
    offseasonTransactions,
    playoffSeries,
    shotsIndex,
    shotsMetadata,
    matchups,
  } = loadAllDatasets();

  it('clutch_leverage_metrics.json: tsDelta ≈ clutchTsPct - baseTsPct and shot breakdowns are coherent', () => {
    const mismatches: string[] = [];
    for (const p of clutch) {
      if (p.clutchTsPct === null || p.tsDelta === null || p.baseTsPct === null) continue;
      const expectedTsDelta = p.clutchTsPct - p.baseTsPct;
      if (Math.abs(p.tsDelta - expectedTsDelta) > 0.25) {
        mismatches.push(`${p.playerName}: tsDelta=${p.tsDelta} vs ${expectedTsDelta.toFixed(1)}`);
      }
    }
    // Track known drift in baseline
    expect(mismatches, `Clutch tsDelta mismatches:\n${mismatches.slice(0, 10).join('\n')}`).toEqual([]);
  });

  it(`clutch_leverage_metrics.json: archetypes and ranks only at clutchFga >= ${CLUTCH_MIN_FGA} (NBA#90)`, () => {
    const labelledUnderMin: string[] = [];
    const rankedUnderMin: string[] = [];
    const qualifiedMismatch: string[] = [];
    for (const p of clutch) {
      if (p.clutchArchetype != null && !(p.clutchFga >= CLUTCH_MIN_FGA)) {
        labelledUnderMin.push(`${p.playerName}: "${p.clutchArchetype}" on ${p.clutchFga} FGA`);
      }
      if (p.clutchRank != null && !(p.clutchFga >= CLUTCH_MIN_FGA)) {
        rankedUnderMin.push(`${p.playerName}: rank ${p.clutchRank} on ${p.clutchFga} FGA`);
      }
      if (p.qualified !== (p.clutchFga >= CLUTCH_MIN_FGA)) {
        qualifiedMismatch.push(`${p.playerName}: qualified=${p.qualified} on ${p.clutchFga} FGA`);
      }
    }
    expect(labelledUnderMin, `Archetype under ${CLUTCH_MIN_FGA} FGA:\n${labelledUnderMin.slice(0, 10).join('\n')}`).toEqual([]);
    expect(rankedUnderMin, `Rank under ${CLUTCH_MIN_FGA} FGA:\n${rankedUnderMin.slice(0, 10).join('\n')}`).toEqual([]);
    expect(qualifiedMismatch, `qualified flag mismatch:\n${qualifiedMismatch.slice(0, 10).join('\n')}`).toEqual([]);

    // Every qualified player is ranked, ranks start at 1, and the attempt count
    // matches the published shot breakdown.
    const qualified = clutch.filter((p) => p.qualified);
    for (const p of qualified) {
      expect(p.clutchRank, `${p.playerName} qualified but unranked`).not.toBeNull();
      expect(p.clutchArchetype, `${p.playerName} qualified but no archetype`).not.toBeNull();
    }
    if (qualified.length > 0) {
      expect(Math.min(...qualified.map((p) => p.clutchRank as number))).toBe(1);
    }
    for (const p of clutch) {
      expect(p.clutchFga, `${p.playerName} clutchFga vs shotBreakdown`).toBe(p.shotBreakdown.totalClutchFga);
    }
  });

  it('defensive_metrics.json: matchupDist pgPct+sgPct+sfPct+pfPct+cPct sums to ~100%', () => {
    for (const p of defense) {
      if (p.matchupDist === null) continue;
      const distSum =
        p.matchupDist.pgPct +
        p.matchupDist.sgPct +
        p.matchupDist.sfPct +
        p.matchupDist.pfPct +
        p.matchupDist.cPct;
      expect(distSum, `${p.playerName} matchupDist sum`).toBeCloseTo(100, 0);
    }
  });

  it('player_dna_profiles.json: peer comps are sorted descending; players with data get 5', () => {
    for (const p of playerDna) {
      if (p.peerComps.length > 0) expect(p.peerComps.length).toBe(5);
      for (let i = 1; i < p.peerComps.length; i++) {
        expect(p.peerComps[i - 1].similarityPct).toBeGreaterThanOrEqual(p.peerComps[i].similarityPct);
      }
    }
  });

  const BOX_DERIVED_DIMS = [
    'rim_fg', 'dunks', 'paint_touches', 'cns_3p', 'pullup_3p', 'ft_pct', 'ast_pct',
    'tov_control', 'drive_ast', 'rim_protection', 'perimeter_havoc', 'oreb', 'dreb',
  ] as const;

  it('player_dna_profiles.json: no two players share an identical full skillVector unless it has no box-derived data', () => {
    const seen = new Map<string, string>();
    for (const p of playerDna) {
      // Vectors with no box-derived dim are skipped: only a tie-prone switchability
      // percentile can remain, which is not a fabricated shared vector.
      if (BOX_DERIVED_DIMS.every((d) => p.skillVector[d] === null)) continue;
      const key = JSON.stringify(p.skillVector);
      expect(seen.has(key), `${p.playerName} duplicates skillVector of ${seen.get(key)}`).toBe(false);
      seen.set(key, p.playerName);
    }
  });

  it('player_dna_profiles.json: empty peerComps implies null box-derived dims and never appears as a peer', () => {
    const empty = playerDna.filter((p) => p.peerComps.length === 0);
    for (const p of empty) {
      for (const d of BOX_DERIVED_DIMS) {
        expect(p.skillVector[d], `${p.playerName} ${d} should be null`).toBeNull();
      }
    }
    const emptyIds = new Set(empty.map((p) => p.playerId));
    const emptyNames = new Set(empty.map((p) => p.playerName));
    for (const p of playerDna) {
      for (const c of p.peerComps) {
        expect(emptyIds.has(c.playerId), `${p.playerName} lists no-data player ${c.compName}`).toBe(false);
        expect(emptyNames.has(c.compName)).toBe(false);
      }
    }
    // Inverse: a player with any non-null box-derived dim has comps.
    for (const p of playerDna) {
      if (BOX_DERIVED_DIMS.some((d) => p.skillVector[d] !== null)) {
        expect(p.peerComps.length, `${p.playerName} has box data but no comps`).toBeGreaterThan(0);
      }
    }
  });

  it('player_dna_profiles.json: archetype is null exactly for players with no box-derived data; skillVector has 15 dims', () => {
    for (const p of playerDna) {
      const noBox = BOX_DERIVED_DIMS.every((d) => p.skillVector[d] === null);
      expect(p.archetype === null, `${p.playerName} archetype nullness`).toBe(noBox);
      expect(Object.keys(p.skillVector).length).toBe(15);
      expect(Object.keys(p.skillVector)).not.toContain('pot_ast');
    }
  });

  it('player_dna_profiles.json: overallRating null iff <8 of 15 dims non-null; category null iff <half of its dims non-null', () => {
    const groups: Record<string, string[]> = {
      finishing: ['rim_fg', 'dunks', 'paint_touches'],
      shooting: ['cns_3p', 'pullup_3p', 'ft_pct'],
      playmaking: ['ast_pct', 'tov_control', 'drive_ast'],
      defense: ['switchability', 'rim_protection', 'perimeter_havoc', 'd_rapm'],
      rebounding: ['oreb', 'dreb'],
    };
    const sv = (p: (typeof playerDna)[number]) => p.skillVector as unknown as Record<string, number | null>;
    const cs = (p: (typeof playerDna)[number]) => p.categoryScores as unknown as Record<string, number | null>;
    for (const p of playerDna) {
      const nn = Object.values(p.skillVector).filter((v) => v !== null).length;
      expect(p.overallRating === null, `${p.playerName} overallRating nullness (non-null dims=${nn})`).toBe(nn < 8);
      for (const [cat, dims] of Object.entries(groups)) {
        const k = dims.filter((d) => sv(p)[d] !== null).length;
        expect(cs(p)[cat] === null, `${p.playerName} ${cat} nullness (non-null dims=${k}/${dims.length})`).toBe(k * 2 < dims.length);
      }
    }
  });

  it('player_dna_profiles.json: every peer comp is another player present in the same payload', () => {
    const names = new Set(playerDna.map((p) => p.playerName));
    const ids = new Set(playerDna.map((p) => p.playerId));
    for (const p of playerDna) {
      for (const c of p.peerComps) {
        expect(names.has(c.compName), `${p.playerName} comp ${c.compName} not in payload`).toBe(true);
        expect(ids.has(c.playerId), `${p.playerName} comp id ${c.playerId} not in payload`).toBe(true);
        expect(c.compName, `${p.playerName} lists itself as a comp`).not.toBe(p.playerName);
        expect(c.playerId, `${p.playerName} lists itself as a comp`).not.toBe(p.playerId);
      }
    }
  });

  it('coaching_metrics.json: talentExpectedWins + coachingWinsAdded ≈ actualProjectedWins for all 30 staffs', () => {
    for (const c of coaches) {
      expect(
        c.metrics.talentExpectedWins + c.metrics.coachingWinsAdded,
        `${c.teamAbbr} talent bridge`
      ).toBeCloseTo(c.metrics.actualProjectedWins, 1);
    }
  });

  it('coaching_metrics.json: unobserved or zero-sample ATO/challenge rates must be null (#200)', () => {
    for (const c of coaches) {
      const hasAtoRate =
        c.metrics.atoOffensivePpp !== null || c.metrics.atoDefensivePppAllowed !== null;
      if (c.provenance.atoMetrics === 'unobserved') {
        expect(c.metrics.atoOffensivePpp, `${c.teamAbbr} unobserved atoOffensivePpp`).toBeNull();
        expect(c.metrics.atoDefensivePppAllowed, `${c.teamAbbr} unobserved atoDefensivePppAllowed`).toBeNull();
        expect(c.radarPercentiles.atoMastery, `${c.teamAbbr} unobserved atoMastery`).toBeNull();
        expect(c.metrics.coachImpactRating, `${c.teamAbbr} unobserved coachImpactRating`).toBeNull();
      }
      if (hasAtoRate) {
        expect(c.metrics.atoOffPossessions, `${c.teamAbbr} atoOffPossessions >= 1`).toBeGreaterThanOrEqual(1);
        expect(c.metrics.atoDefPossessions, `${c.teamAbbr} atoDefPossessions >= 1`).toBeGreaterThanOrEqual(1);
      }
      if (c.provenance.challengeMetrics === 'unobserved') {
        expect(c.metrics.challengeSuccessRate, `${c.teamAbbr} unobserved challengeSuccessRate`).toBeNull();
        expect(c.radarPercentiles.inGameWpa, `${c.teamAbbr} unobserved inGameWpa`).toBeNull();
        expect(c.metrics.coachImpactRating, `${c.teamAbbr} unobserved coachImpactRating`).toBeNull();
      }
      if (c.metrics.challengeSuccessRate !== null) {
        expect(c.metrics.challengeAttempts, `${c.teamAbbr} challengeAttempts >= 1`).toBeGreaterThanOrEqual(1);
      }
    }
  });

  it('coaching_metrics.json: omits unverified hand-typed registry fields (#188)', () => {
    const forbiddenTopKeys = [
      'careerGames',
      'careerWinPct',
      'headCoach',
      'assistants',
      'tenureYears',
      'coachingTree',
      'tacticalArchetype',
      'associateHC',
      'offensiveCoord',
      'defensiveCoord',
      'playerDevLead',
    ];
    for (const c of coaches) {
      const topKeys = Object.keys(c as unknown as Record<string, unknown>);
      for (const k of forbiddenTopKeys) {
        expect(topKeys, `${c.teamAbbr} top-level ${k}`).not.toContain(k);
      }
    }
  });

  it('offseason_draft.json: picks are sequential 1..60 across rounds 1 and 2', () => {
    expect(offseasonDraft.map((p) => p.pick)).toEqual(Array.from({ length: 60 }, (_, i) => i + 1));
    expect(offseasonDraft.slice(0, 30).every((p) => p.round === 1)).toBe(true);
    expect(offseasonDraft.slice(30).every((p) => p.round === 2)).toBe(true);
  });

  it('offseason_teams.json: baseline_wins + net_wins_change ≈ projected_wins_with_moves for all 30 teams', () => {
    for (const t of offseasonTeams) {
      expect(t.baseline_wins + t.net_wins_change, `${t.team} offseason wins delta`).toBeCloseTo(
        t.projected_wins_with_moves,
        1
      );
    }
  });

  it('offseason_transactions.json: canonical 183+ record catalog is preserved and drives team profiles', () => {
    // The offseason builder reads this catalog as read-only input. A regression
    // once replaced it with a 30-record subset, silently dropping most moves.
    expect(offseasonTransactions.length).toBeGreaterThanOrEqual(183);

    const ids = offseasonTransactions.map((t) => t.id);
    expect(new Set(ids).size, 'duplicate transaction ids').toBe(ids.length);

    const draftPicks = offseasonTransactions.filter((t) => t.type === 'draft');
    expect(draftPicks).toHaveLength(LEAGUE.DRAFT_PICKS);
    expect(draftPicks.map((t) => t.draft_pick?.pick).sort((a, b) => a! - b!)).toEqual(
      Array.from({ length: LEAGUE.DRAFT_PICKS }, (_, i) => i + 1)
    );
    for (const t of draftPicks) {
      const profile = offseasonDraft.find((p) => p.pick === t.draft_pick?.pick);
      expect(profile?.player_name, `draft pick ${t.draft_pick?.pick}`).toBe(t.player_name);
    }

    const knownIds = [
      'tx-2026-giannis-antetokounmpo',
      'tx-2026-lebron-james',
      'dr-2026-pick-1-aj-dybantsa',
      'dr-2026-pick-60-malique-lewis',
    ];
    for (const id of knownIds) {
      expect(ids, `missing canonical transaction ${id}`).toContain(id);
    }

    // Every roster move summarized in offseason_teams.json must come from the
    // full catalog, not a subset generated alongside the team profiles.
    const catalogNames = new Set(offseasonTransactions.map((t) => t.player_name));
    const orphans: string[] = [];
    for (const team of offseasonTeams) {
      for (const move of [...team.additions, ...team.departures]) {
        if (!catalogNames.has(move.name)) orphans.push(`${team.team}: ${move.name}`);
      }
    }
    expect(orphans, `team moves missing from catalog:\n${orphans.slice(0, 10).join('\n')}`).toEqual([]);
  });

  it('playoff_series_matchups.json: 8-player playoff rotations sum to ~240 team minutes, and sampleMatchups win probabilities sum to 1', () => {
    const profileList = Object.values(playoffSeries.teams);
    expect(profileList).toHaveLength(30);

    for (const team of profileList) {
      const playoffMpgSum = sum(team.rotation.map((r) => r.playoffMpg));
      expect(Math.abs(playoffMpgSum - 240), `${team.teamAbbr} rotation mins=${playoffMpgSum}`).toBeLessThanOrEqual(1);
      expect(team.playoffNetRtg).toBeCloseTo(team.regularNetRtg + team.top3TalentBump, 2);
    }

    for (const m of playoffSeries.sampleMatchups) {
      expect(m.winProbA + m.winProbB, `${m.teamA} vs ${m.teamB} winProb sum`).toBeCloseTo(1.0, 2);
      const distSum = sum(m.gameDistributions.map((g) => g.probPct));
      expect(Math.abs(distSum - 100), `${m.teamA} vs ${m.teamB} distSum=${distSum}`).toBeLessThanOrEqual(0.5);
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

  it('matchups_slates.json: all 1,200 games carry projections and probabilities sum to 1.0', () => {
    expect(matchups.total_games).toBe(1200);
    expect(matchups.games_without_projection).toBe(0);
    expect(matchups.matchups).toHaveLength(1200);
    expect(matchups.slates).toHaveLength(25);

    for (const m of matchups.matchups) {
      expect(m.has_projection, `Game ${m.game_id} (${m.away_team} @ ${m.home_team}) must have projection`).toBe(true);
      expect(m.projection_basis).not.toBeNull();
      expect(['logged_model_margin', 'margin_from_logged_win_prob', 'primary_ensemble', 'team_rating_differential']).toContain(m.projection_basis);
      if (m.predicted_home_win_prob !== null && m.predicted_away_win_prob !== null) {
        expect(m.predicted_home_win_prob + m.predicted_away_win_prob, `Game ${m.game_id} win probs`).toBeCloseTo(1.0, 3);
      }
      if (m.is_completed) {
        expect(m.home_score).not.toBeNull();
        expect(m.away_score).not.toBeNull();
        expect(m.actual_margin).toBe(m.home_score! - m.away_score!);
      }
    }
  });
});
