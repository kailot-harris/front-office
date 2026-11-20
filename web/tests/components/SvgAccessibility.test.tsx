import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import { AtoEfficiencyScatter } from '../../components/AtoEfficiencyScatter';
import { DiagnosticsClient } from '../../components/DiagnosticsClient';
import { DnaManifoldScatter } from '../../components/DnaManifoldScatter';
import { PressureResiliencePlot } from '../../components/PressureResiliencePlot';
import { VersatilityScatter } from '../../components/VersatilityScatter';
import type { CoachingStaffMetric } from '../../lib/coachingTypes';
import type { ClutchProfile } from '../../lib/clutchTypes';
import type { DefensiveProfile } from '../../lib/defenseTypes';
import type { PlayerDnaProfile } from '../../lib/playerDnaTypes';
import type { ModelDiagnostics, ModelMetadata } from '../../lib/types';

/**
 * Minimal inline fixtures modeled on the 2026 published JSON editions in
 * `web/public/data/` for each component under test.
 */
function makeCoach(overrides: Partial<CoachingStaffMetric> = {}): CoachingStaffMetric {
  return {
    season: 2026,
    teamAbbr: 'ATL',
    teamName: 'Atlanta Dream',
    headCoach: {
      name: 'Karl Smesko',
      tenureStart: 2025,
      tenureYears: 2,
      registrySeason: 2026,
      sourceCitation: 'WNBA.com Official Team Directories',
      sourceVerifiedDate: '2026-11-07',
    },
    metrics: {
      coachImpactRating: 58,
      talentExpectedWins: 26.1,
      actualProjectedWins: 26.6,
      coachingWinsAdded: 0.5,
      atoOffensivePpp: 0.944,
      atoDefensivePppAllowed: 1.003,
      challengeSuccessRate: 0.42,
      atoOffPossessions: 1189,
      atoDefPossessions: 1205,
      challengeAttempts: 157,
    },
    radarPercentiles: {
      atoMastery: 29,
      tacticalInnovation: 64,
      rotationEfficiency: 78,
      inGameWpa: 85,
      playerDevelopment: 85,
    },
    ...overrides,
  };
}

function makeDiagnostics(): ModelDiagnostics {
  return {
    generated_at: '2026-11-06T19:49:32Z',
    totalResolvedGames: 1902,
    overallAccuracy: 0.6509,
    brierScore: 0.221,
    logLoss: 0.6432,
    homeWinRate: 0.551,
    calibration: [
      {
        bin: '40-50%',
        midpoint: 0.45,
        count: 262,
        meanPredictedProb: 0.452,
        empiricalWinRate: 0.485,
      },
      {
        bin: '50-60%',
        midpoint: 0.55,
        count: 280,
        meanPredictedProb: 0.55,
        empiricalWinRate: 0.536,
      },
    ],
    accuracyDrift: [
      {
        season: '2026',
        games: 293,
        accuracy: 0.672,
        brierScore: 0.2162,
      },
    ],
    residualDistribution: [
      {
        bucket: '-0.2 to 0.2',
        count: 332,
        label: 'Well Calibrated',
      },
    ],
  };
}

function makeMetadata(): ModelMetadata {
  return {
    schema_version: '1.0',
    pipeline_stage: 'season_long_projections',
    generated_at: '2026-11-06T19:49:31Z',
    season: 2026,
    n_simulations: 1000,
    margin_sigma: 14,
    home_court_advantage: 2.4,
    total_schedule_games: 330,
    teams_count: 15,
    players_count: 221,
    models: {
      ensemble: {
        name: 'Multi-Model Ensemble Blend',
        weights: {
          variant_bottom_up: 0.35,
          variant_rapm: 0.25,
          variant_shot_fatigue: 0.2,
          variant_embeddings: 0.2,
        },
        description: 'Ensemble blend',
      },
      variant_bottom_up: { name: 'Bottom-Up', weight: 0.35, description: 'Bottom-up' },
      variant_rapm: { name: 'RAPM', weight: 0.25, description: 'RAPM' },
      variant_shot_fatigue: { name: 'Shot Fatigue', weight: 0.2, description: 'Shot fatigue' },
      variant_embeddings: { name: 'Embeddings', weight: 0.2, description: 'Embeddings' },
    },
  };
}

function makeDnaPlayer(overrides: Partial<PlayerDnaProfile> = {}): PlayerDnaProfile {
  return {
    season: 2026,
    playerId: '3149391',
    playerName: "A'ja Wilson",
    team: 'LV',
    position: 'C',
    archetype: 'Interior Anchor & Glass Cleaner',
    dnaSource: 'observed_pbp_box',
    projPts: 26,
    projReb: 9.4,
    projAst: 3.2,
    projMpg: 32.1,
    overallRating: 71.3,
    manifoldX: -11.4,
    manifoldY: 25.5,
    skillVector: {
      rim_fg: 35.7,
      paint_power: 99,
      cns_3p: 47.6,
      pullup_3p: 60.5,
      ft_pct: 83.3,
      ast_pct: 68.1,
      tov_control: 82.9,
      rim_protection: 95.7,
      perimeter_havoc: 76.2,
      d_rapm: 36.7,
      oreb: 72.9,
      dreb: 97.6,
    },
    categoryScores: {
      finishing: 67.3,
      shooting: 63.8,
      playmaking: 75.5,
      defense: 69.5,
      rebounding: 85.2,
    },
    similarPlayers: [],
    ...overrides,
  };
}

function makeClutchProfile(overrides: Partial<ClutchProfile> = {}): ClutchProfile {
  return {
    season: 2026,
    playerId: '3149391',
    playerName: "A'ja Wilson",
    team: 'LV',
    position: 'C',
    clutchArchetype: 'Elite High-Volume Closer',
    clutchFga: 53,
    clutchPoints: 52,
    clutchFgPct: 69.8,
    clutchScoringPlays: 37,
    clutchPpp: 0.98,
    provenance: 'REAL_CURRENT_SEASON',
    ...overrides,
  };
}

function makeDefensiveProfile(overrides: Partial<DefensiveProfile> = {}): DefensiveProfile {
  return {
    season: 2026,
    playerId: '3149391',
    playerName: "A'ja Wilson",
    team: 'LV',
    position: 'C',
    projMpg: 32.1,
    defensiveRole: '1-Through-5 Switch Eraser',
    versatilityScore: 95.1,
    rimDfgDelta: -6.5,
    rimDeterrenceIndex: 1.1,
    dRapm: 1.53,
    dRapmSource: 'rapm_ridge_pooled',
    dRapmLowSample: false,
    dRapmAmbiguous: false,
    rimDefenseSource: 'wehoop_shots_lineups',
    rimDefenseSample: 4071,
    matchupSource: 'wehoop_possession_lineups',
    matchupSample: 13725,
    matchupDist: {
      pgPct: 18.7,
      sgPct: 20.5,
      sfPct: 32.2,
      pfPct: 20.6,
      cPct: 8,
    },
    ...overrides,
  };
}

function assertChartSvgAccessible(container: HTMLElement, expectedPattern: RegExp) {
  const chartSvgs = Array.from(container.querySelectorAll('svg[viewBox]')).filter(
    (el) => !el.classList.contains('lucide')
  );
  expect(chartSvgs).toHaveLength(1);
  const svg = chartSvgs[0];
  expect(svg).toHaveAttribute('role', 'img');
  expect(svg).not.toHaveAttribute('aria-hidden', 'true');

  const label = svg.getAttribute('aria-label')?.trim() ?? '';
  expect(label.length).toBeGreaterThan(0);
  expect(label).toMatch(expectedPattern);

  const byRole = screen.getByRole('img', { name: expectedPattern });
  expect(byRole).toBe(svg);
}

describe('WNBA chart SVG accessibility', () => {
  it('AtoEfficiencyScatter exposes role="img" and dynamic aria-label with selected coach context', () => {
    const atlCoach = makeCoach();
    const chiCoach = makeCoach({
      teamAbbr: 'CHI',
      teamName: 'Chicago Sky',
      headCoach: {
        ...atlCoach.headCoach,
        name: 'Tyler Marsh',
      },
    });

    const { container } = render(
      <AtoEfficiencyScatter
        coaches={[atlCoach, chiCoach]}
        selectedCoach={atlCoach}
        onSelectCoach={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /ATO efficiency scatter plot across 2 coaching staffs, highlighting Karl Smesko \(ATL\)/i
    );
  });

  it('AtoEfficiencyScatter omits selection suffix when selectedCoach is null', () => {
    const { container } = render(
      <AtoEfficiencyScatter
        coaches={[makeCoach()]}
        selectedCoach={null}
        onSelectCoach={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /^In-game ATO efficiency scatter plot across 1 coaching staff$/i
    );
  });

  it('DiagnosticsClient calibration SVG exposes role="img" and descriptive aria-label', () => {
    const { container } = render(
      <DiagnosticsClient diagnostics={makeDiagnostics()} metadata={makeMetadata()} />
    );

    assertChartSvgAccessible(
      container,
      /Probability calibration reliability diagram across 2 bins and 1,902 resolved games \(2026 model\)/i
    );
  });

  it('DnaManifoldScatter exposes role="img" and dynamic aria-label with selected player context', () => {
    const wilson = makeDnaPlayer();
    const boston = makeDnaPlayer({
      playerId: '4432831',
      playerName: 'Aliyah Boston',
      team: 'IND',
      manifoldX: -8.2,
      manifoldY: 19.4,
    });

    const { container } = render(
      <DnaManifoldScatter
        players={[wilson, boston]}
        selectedPlayer={wilson}
        onSelectPlayer={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /2D stylistic manifold scatter plot of 2 players, highlighting A'ja Wilson \(LV\)/i
    );
  });

  it('PressureResiliencePlot exposes role="img" and dynamic aria-label for qualified closers', () => {
    const wilson = makeClutchProfile();
    const mitchell = makeClutchProfile({
      playerId: '3142191',
      playerName: 'Kelsey Mitchell',
      team: 'IND',
      position: 'G',
      clutchFga: 86,
      clutchFgPct: 53.5,
    });
    const lowVolume = makeClutchProfile({
      playerId: '9999999',
      playerName: 'Bench Reserve',
      team: 'SEA',
      clutchFga: 3,
      clutchFgPct: null,
    });

    const { container } = render(
      <PressureResiliencePlot
        profiles={[wilson, mitchell, lowVolume]}
        selectedPlayerId="3149391"
        onSelectPlayer={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /Clutch field goal percentage vs shot attempts scatter plot for 2 qualified players, highlighting A'ja Wilson \(LV\)/i
    );
  });

  it('PressureResiliencePlot omits highlight suffix when no qualified player is selected', () => {
    const { container } = render(
      <PressureResiliencePlot
        profiles={[makeClutchProfile()]}
        selectedPlayerId=""
        onSelectPlayer={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /^Clutch field goal percentage vs shot attempts scatter plot for 1 qualified player$/i
    );
  });

  it('VersatilityScatter exposes role="img" and dynamic aria-label with selected defender context', () => {
    const wilson = makeDefensiveProfile();
    const mitchell = makeDefensiveProfile({
      playerId: '3142191',
      playerName: 'Kelsey Mitchell',
      team: 'IND',
      position: 'G',
    });

    const { container } = render(
      <VersatilityScatter
        profiles={[wilson, mitchell]}
        selectedProfile={wilson}
        onSelectProfile={vi.fn()}
      />
    );

    assertChartSvgAccessible(
      container,
      /Defensive versatility vs rim deterrence scatter plot for 2 defenders, highlighting A'ja Wilson \(LV\)/i
    );
  });
});
