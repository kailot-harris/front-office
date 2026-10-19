import { describe, it, expect } from 'vitest';
import {
  filterPriorNShots,
  computeZoneMetrics,
  computeOverallStats,
  generateHexbins,
  getThermalColor,
  getStatusBadge,
  getZoneDisplayName,
  toSvgX,
  toSvgY,
} from '@/lib/shotChartUtils';
import type { ShotRecord, ZoneLeagueAverage } from '@/lib/shotTypes';

const SAMPLE_PRIORS: ZoneLeagueAverage[] = [
  { zone: 'Restricted Area', total_fga: 81033, total_fgm: 49805, lg_fg_pct: 0.615 },
  { zone: 'Paint (Low / Floater)', total_fga: 33450, total_fgm: 13218, lg_fg_pct: 0.395 },
  { zone: 'Paint (High / FT)', total_fga: 21656, total_fgm: 8666, lg_fg_pct: 0.4 },
  { zone: 'Left Baseline Mid', total_fga: 10122, total_fgm: 3767, lg_fg_pct: 0.372 },
  { zone: 'Right Baseline Mid', total_fga: 9390, total_fgm: 3451, lg_fg_pct: 0.368 },
  { zone: 'Left Wing Mid', total_fga: 6013, total_fgm: 2033, lg_fg_pct: 0.338 },
  { zone: 'Center Mid', total_fga: 11203, total_fgm: 4178, lg_fg_pct: 0.373 },
  { zone: 'Right Wing Mid', total_fga: 6207, total_fgm: 2212, lg_fg_pct: 0.356 },
  { zone: 'Left Corner 3', total_fga: 10935, total_fgm: 3949, lg_fg_pct: 0.361 },
  { zone: 'Right Corner 3', total_fga: 8991, total_fgm: 3309, lg_fg_pct: 0.368 },
  { zone: 'Left Wing 3', total_fga: 26485, total_fgm: 9276, lg_fg_pct: 0.35 },
  { zone: 'Center 3', total_fga: 13997, total_fgm: 4833, lg_fg_pct: 0.345 },
  { zone: 'Right Wing 3', total_fga: 24574, total_fgm: 8495, lg_fg_pct: 0.346 },
  { zone: 'Deep / Logo 3', total_fga: 3591, total_fgm: 702, lg_fg_pct: 0.195 },
];

function makeShot(overrides: Partial<ShotRecord> = {}): ShotRecord {
  return {
    x: 0,
    y: 4,
    dist: 2,
    val: 2,
    made: true,
    zone: 'Restricted Area',
    type: 'Driving Layup Shot',
    period: 1,
    clock: '08:00',
    ...overrides,
  };
}

describe('lib/shotChartUtils.ts spatial & Bayesian shot analytics', () => {
  it('filterPriorNShots() slices from the start of the most-recent-first array', () => {
    const shots = Array.from({ length: 10 }, (_, i) => makeShot({ dist: i + 1 }));
    expect(filterPriorNShots(shots, 'all')).toHaveLength(10);
    expect(filterPriorNShots(shots, 25)).toHaveLength(10);
    expect(filterPriorNShots(shots, 4).map((s) => s.dist)).toEqual([1, 2, 3, 4]);
  });

  it('computeZoneMetrics() applies Beta-Binomial Empirical Bayes shrinkage and z-score classification', () => {
    const hotRimShots = Array.from({ length: 20 }, () =>
      makeShot({ zone: 'Restricted Area', made: true, val: 2 })
    );
    const coldThreeShots = Array.from({ length: 20 }, () =>
      makeShot({
        zone: 'Center 3',
        made: false,
        val: 3,
        x: 0,
        y: 25,
        dist: 25,
      })
    );

    const metrics = computeZoneMetrics([...hotRimShots, ...coldThreeShots], SAMPLE_PRIORS, 4);
    expect(metrics).toHaveLength(14);

    const rim = metrics.find((m) => m.zone === 'Restricted Area')!;
    expect(rim.fga).toBe(20);
    expect(rim.fgm).toBe(20);
    expect(rim.fgPct).toBe(1.0);
    expect(rim.status).toBe('HOT');
    expect(rim.zScore).toBeGreaterThan(1.3);

    const center3 = metrics.find((m) => m.zone === 'Center 3')!;
    expect(center3.fga).toBe(20);
    expect(center3.fgm).toBe(0);
    expect(center3.status).toBe('COLD');
    expect(center3.zScore).toBeLessThan(-1.3);

    const cornerL = metrics.find((m) => m.zone === 'Left Corner 3')!;
    expect(cornerL.fga).toBe(0);
    expect(cornerL.shrunkPct).toBeCloseTo(0.361, 4);
    expect(cornerL.status).toBe('LOW_SAMPLE');

    const overall = computeOverallStats([...hotRimShots, ...coldThreeShots], metrics);
    expect(overall.totalFga).toBe(40);
    expect(overall.totalFgm).toBe(20);
    expect(overall.fgPct).toBeCloseTo(0.5, 4);
    expect(overall.hotCount).toBeGreaterThanOrEqual(1);
    expect(overall.coldCount).toBeGreaterThanOrEqual(1);
  });

  it('generateHexbins(), coordinate converters, and badge/color helpers return valid outputs', () => {
    const shots = [
      makeShot({ x: 0, y: 4, made: true }),
      makeShot({ x: 0.5, y: 4.2, made: false }),
    ];
    const bins = generateHexbins(shots, 16);
    expect(bins.length).toBeGreaterThanOrEqual(1);
    expect(bins[0].fga).toBe(2);
    expect(bins[0].fgm).toBe(1);

    expect(toSvgX(-25)).toBe(0);
    expect(toSvgX(0)).toBe(250);
    expect(toSvgX(25)).toBe(500);
    expect(toSvgY(0)).toBe(470);
    expect(toSvgY(47)).toBe(0);

    expect(getThermalColor(0, 'LOW_SAMPLE')).toContain('rgba');
    expect(getThermalColor(0.12, 'HOT')).toContain('239, 68, 68');
    expect(getThermalColor(-0.12, 'COLD')).toContain('6, 182, 212');
    expect(getStatusBadge('HOT').label).toBe('HOT');
    expect(getStatusBadge('COLD').label).toBe('COLD');
    expect(getZoneDisplayName('Restricted Area').name).toBe('Restricted Area');
  });
});
