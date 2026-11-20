import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, it, expect } from 'vitest';
import { BaseballCrest } from '@/components/BaseballCrest';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { DnaManifoldScatter } from '@/components/DnaManifoldScatter';
import { PressureResiliencePlot } from '@/components/PressureResiliencePlot';
import { SurplusValueCalculator } from '@/components/SurplusValueCalculator';
import type { ModelDiagnostics, ModelMetadata } from '@/lib/types';
import type { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import type { ClutchProfile } from '@/lib/clutchTypes';

function extractAttr(attrs: string, name: string): string | null {
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const match = attrs.match(new RegExp(`\\b${escaped}="([^"]*)"`));
  return match ? match[1] : null;
}

function findSvgTags(html: string, viewBox: string): string[] {
  const tags: string[] = [];
  const regex = /<svg\b([^>]*)>/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(html)) !== null) {
    const attrs = match[1] ?? '';
    if (extractAttr(attrs, 'viewBox') === viewBox) {
      tags.push(attrs);
    }
  }
  return tags;
}

function findRangeInputTags(html: string): string[] {
  const tags: string[] = [];
  const regex = /<input\b([^>]*)\/?>/g;
  let match: RegExpExecArray | null;
  while ((match = regex.exec(html)) !== null) {
    const attrs = match[1] ?? '';
    if (extractAttr(attrs, 'type') === 'range') {
      tags.push(attrs);
    }
  }
  return tags;
}

const sampleDiagnostics: ModelDiagnostics = {
  generated_at: '2026-10-01T00:00:00Z',
  totalResolvedGames: 2430,
  overallAccuracy: 0.584,
  brierScore: 0.2391,
  logLoss: 0.6712,
  homeWinRate: 0.538,
  weightedCalibError: 0.018,
  calibrationStatus: 'OPTIMAL',
  calibration: [
    { bin: '30-40%', midpoint: 0.35, count: 210, meanPredictedProb: 0.35, empiricalWinRate: 0.34 },
    { bin: '40-50%', midpoint: 0.45, count: 520, meanPredictedProb: 0.45, empiricalWinRate: 0.46 },
    { bin: '50-60%', midpoint: 0.55, count: 980, meanPredictedProb: 0.55, empiricalWinRate: 0.56 },
    { bin: '60-70%', midpoint: 0.65, count: 720, meanPredictedProb: 0.65, empiricalWinRate: 0.64 },
  ],
  accuracyDrift: [
    { season: 'Early (Apr-May)', games: 810, accuracy: 0.57, brierScore: 0.242 },
  ],
  residualDistribution: [
    { bucket: '[-0.2, 0.2]', count: 900, label: 'Tight fit' },
  ],
};

const sampleMetadata: ModelMetadata = {
  schema_version: '1.0',
  pipeline_stage: 'season',
  generated_at: '2026-10-01T00:00:00Z',
  season: 2026,
  n_simulations: 1000,
  postseason_sims: 10000,
  margin_sigma: 4.1,
  home_court_advantage: 24,
  pythag_exponent: 1.83,
  total_schedule_games: 2430,
  teams_count: 30,
  players_count: 1200,
  batters_count: 600,
  pitchers_count: 600,
  models: {
    ensemble: { name: 'Ensemble', weights: { bottom_up: 0.4 }, description: 'Weighted ensemble' },
    variant_bottom_up: { name: 'Bottom-Up', weight: 0.4, description: 'Roster aggregation' },
    variant_rapm: { name: 'RAPM', weight: 0.2, description: 'Ridge adjusted' },
    variant_shot_fatigue: { name: 'Fatigue', weight: 0.2, description: 'Bullpen fatigue' },
    variant_embeddings: { name: 'Embeddings', weight: 0.2, description: 'Player vectors' },
  },
};

const sampleBatterDna: PlayerDnaProfile = {
  playerId: 'b1',
  mlbamId: '592450',
  playerName: 'Sample Slugger',
  team: 'NYY',
  playerType: 'Batter',
  position: 'RF',
  age: 30,
  archetype: 'Power Anchor',
  headlineStats: {
    stat1Label: 'wOBA',
    stat1Val: '.410',
    stat2Label: 'ISO',
    stat2Val: '.300',
    stat3Label: 'BB%',
    stat3Val: '16.0%',
    countLabel: 'PA',
    countVal: 650,
  },
  compositeZscore: 2.1,
  overallRating: 96,
  manifoldX: 22,
  manifoldY: 18,
  skillVector: {
    exit_velo_90: 98,
    barrel_pct: 99,
    hard_hit_pct: 97,
    iso_power: 99,
    zone_contact: 72,
    whiff_avoidance: 65,
    strikeout_avoidance: 64,
    chase_discipline: 91,
    walk_rate: 96,
    sweet_spot_pct: 84,
    pull_air_pct: 86,
    all_fields_spray: 70,
    sprint_speed: 55,
    baserunning_val: 58,
    fielding_range: 62,
    clutch_resilience: 82,
  },
  categoryScores: {
    power: 98,
    contact: 69,
    discipline: 94,
    batted_ball: 85,
    athleticism: 60,
  },
  historicalTwins: [],
};

const sampleClutchProfile: ClutchProfile = {
  playerId: 'c1',
  mlbamId: '660271',
  playerName: 'Sample Closer',
  team: 'LAD',
  playerType: 'Pitcher',
  position: 'RP',
  clutchArchetype: 'High-Leverage Fireman',
  baseMetricLabel: 'Base wOBA Against',
  baseMetricVal: 0.275,
  clutchMetricLabel: 'High-LI wOBA Against',
  clutchMetricVal: 0.235,
  deltaClutch: -0.04,
  clutchScore: 1.45,
  wpaTotal: 2.8,
  highLiWpa: 2.1,
  avgLeverageIndex: 1.92,
  leverageBreakdown: {
    lowPct: 18,
    medPct: 27,
    highPct: 35,
    extremePct: 20,
  },
  rispSplit: {
    pa: 90,
    avg: 0.195,
    obp: 0.255,
    slg: 0.285,
    wOBA: 0.24,
    ops: 0.54,
  },
};

describe('MLB SVG and range-slider SSR accessibility', () => {
  it('BaseballCrest renders <svg> with role="img", descriptive aria-label, and no aria-hidden', () => {
    const html = renderToStaticMarkup(React.createElement(BaseballCrest));
    const svgs = findSvgTags(html, '0 0 64 64');
    expect(svgs).toHaveLength(1);
    const attrs = svgs[0];
    expect(extractAttr(attrs, 'role')).toBe('img');
    expect(extractAttr(attrs, 'aria-hidden')).toBeNull();
    const label = extractAttr(attrs, 'aria-label');
    expect(label).toBeTruthy();
    expect(label!.toLowerCase()).toContain('crest');
  });

  it('DiagnosticsClient renders calibration <svg> with role="img", dynamic aria-label, and no aria-hidden', () => {
    const html = renderToStaticMarkup(
      React.createElement(DiagnosticsClient, {
        diagnostics: sampleDiagnostics,
        metadata: sampleMetadata,
      })
    );
    const svgs = findSvgTags(html, '0 0 400 400');
    expect(svgs).toHaveLength(1);
    const attrs = svgs[0];
    expect(extractAttr(attrs, 'role')).toBe('img');
    expect(extractAttr(attrs, 'aria-hidden')).toBeNull();
    const label = extractAttr(attrs, 'aria-label');
    expect(label).toBeTruthy();
    expect(label).toContain('4');
    expect(label).toContain('2,430');
    expect(label!.toLowerCase()).toContain('calibration');
  });

  it('DnaManifoldScatter renders scatter <svg> with role="img", dynamic aria-label, and no aria-hidden', () => {
    const html = renderToStaticMarkup(
      React.createElement(DnaManifoldScatter, {
        players: [sampleBatterDna],
        selectedPlayer: sampleBatterDna,
        onSelectPlayer: () => {},
        playerType: 'Batter',
      })
    );
    const svgs = findSvgTags(html, '0 0 500 280');
    expect(svgs).toHaveLength(1);
    const attrs = svgs[0];
    expect(extractAttr(attrs, 'role')).toBe('img');
    expect(extractAttr(attrs, 'aria-hidden')).toBeNull();
    const label = extractAttr(attrs, 'aria-label');
    expect(label).toBeTruthy();
    expect(label).toContain('Sample Slugger');
    expect(label).toContain('Batter');
  });

  it('PressureResiliencePlot renders plot <svg> with role="img", dynamic aria-label, and no aria-hidden', () => {
    const html = renderToStaticMarkup(
      React.createElement(PressureResiliencePlot, {
        profiles: [sampleClutchProfile],
        selectedProfile: sampleClutchProfile,
        onSelectProfile: () => {},
        playerType: 'Pitcher',
      })
    );
    const svgs = findSvgTags(html, '0 0 500 280');
    expect(svgs).toHaveLength(1);
    const attrs = svgs[0];
    expect(extractAttr(attrs, 'role')).toBe('img');
    expect(extractAttr(attrs, 'aria-hidden')).toBeNull();
    const label = extractAttr(attrs, 'aria-label');
    expect(label).toBeTruthy();
    expect(label).toContain('Sample Closer');
    expect(label).toContain('Pitcher');
  });

  it('SurplusValueCalculator renders all 3 range sliders with distinct descriptive aria-label attributes', () => {
    const html = renderToStaticMarkup(React.createElement(SurplusValueCalculator));
    const inputs = findRangeInputTags(html);
    expect(inputs).toHaveLength(3);

    const labels = inputs.map((attrs) => extractAttr(attrs, 'aria-label'));
    for (const label of labels) {
      expect(label).toBeTruthy();
      expect(label!.trim().length).toBeGreaterThan(5);
    }

    expect(new Set(labels).size).toBe(3);
    expect(labels[0]!.toLowerCase()).toContain('salary');
    expect(labels[1]!.toLowerCase()).toContain('war');
    expect(labels[2]!.toLowerCase()).toContain('market');
  });
});
