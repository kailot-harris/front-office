// ==============================================================================
// web/lib/shotChartUtils.ts
// Statistical computations, Bayesian shrinkage, and spatial helpers for Shot Charts
// ==============================================================================

import { ShotRecord, ZoneLeagueAverage, ZoneMetric, ZoneStatus, HexBin } from './shotTypes';

/**
 * Filter the most recent N shots chronologically.
 */
export function filterPriorNShots(
  shots: ShotRecord[],
  n: number | 'all'
): ShotRecord[] {
  if (n === 'all' || n >= shots.length) {
    return shots;
  }
  return shots.slice(0, n);
}

/**
 * Coordinate mapping from half-court feet to SVG viewBox 0 0 500 470
 * x: -25 to +25 -> 0 to 500
 * y: 0 to 47 (baseline to half-court) -> 470 to 0 (baseline at bottom)
 */
export function toSvgX(xFt: number): number {
  return (xFt + 25) * 10;
}

export function toSvgY(yFt: number): number {
  return 470 - (Math.max(0, Math.min(47, yFt)) * 10);
}

/**
 * Calculate Empirical Bayes posterior and Binomial Z-score per zone
 */
export function computeZoneMetrics(
  shots: ShotRecord[],
  leagueAverages: ZoneLeagueAverage[],
  minAttempts: number = 4
): ZoneMetric[] {
  const lgMap = new Map<string, ZoneLeagueAverage>();
  for (const lg of leagueAverages) {
    lgMap.set(lg.zone, lg);
  }

  // Count player stats per zone
  const zoneStats = new Map<string, { fga: number; fgm: number; ppsTotal: number }>();
  const totalShots = Math.max(1, shots.length);

  for (const s of shots) {
    const current = zoneStats.get(s.zone) || { fga: 0, fgm: 0, ppsTotal: 0 };
    current.fga += 1;
    if (s.made) {
      current.fgm += 1;
      current.ppsTotal += s.val;
    }
    zoneStats.set(s.zone, current);
  }

  const allZones = leagueAverages.map((lg) => lg.zone);
  const M_PRIOR_WEIGHT = 15; // Empirical Bayes pseudo-prior sample size

  return allZones.map((zoneName) => {
    const stats = zoneStats.get(zoneName) || { fga: 0, fgm: 0, ppsTotal: 0 };
    const lg = lgMap.get(zoneName) || { total_fga: 1000, total_fgm: 400, lg_fg_pct: 0.4 };

    const fga = stats.fga;
    const fgm = stats.fgm;
    const fgPct = fga > 0 ? fgm / fga : 0;
    const freqPct = fga / totalShots;
    const lgPct = lg.lg_fg_pct;
    const deltaPct = fga > 0 ? fgPct - lgPct : 0;

    // Empirical Bayes shrinkage toward league baseline
    const shrunkPct = (fgm + M_PRIOR_WEIGHT * lgPct) / (fga + M_PRIOR_WEIGHT);

    // Standard error for Binomial z-score
    const se = Math.sqrt((lgPct * (1 - lgPct)) / Math.max(1, fga));
    const zScore = fga >= minAttempts ? (fgPct - lgPct) / se : 0;

    // Points Per Shot (PPS)
    const pps = fga > 0 ? stats.ppsTotal / fga : 0;
    const isThree = zoneName.includes('3');
    const shotValue = isThree ? 3 : 2;
    const lgPps = lgPct * shotValue;
    const deltaPps = fga > 0 ? pps - lgPps : 0;

    // Zone Classification
    let status: ZoneStatus = 'NEUTRAL';
    if (fga < minAttempts) {
      status = 'LOW_SAMPLE';
    } else if (zScore >= 1.3 || (deltaPct >= 0.05 && fga >= minAttempts)) {
      status = 'HOT';
    } else if (zScore <= -1.3 || (deltaPct <= -0.05 && fga >= minAttempts)) {
      status = 'COLD';
    }

    return {
      zone: zoneName,
      fga,
      fgm,
      fgPct,
      freqPct,
      lgPct,
      deltaPct,
      shrunkPct,
      zScore,
      status,
      pps,
      lgPps,
      deltaPps,
    };
  });
}

/**
 * Summary KPI Rollup
 */
export function computeOverallStats(shots: ShotRecord[], zoneMetrics: ZoneMetric[]) {
  const totalFga = shots.length;
  const totalFgm = shots.filter((s) => s.made).length;
  const fgPct = totalFga > 0 ? totalFgm / totalFga : 0;

  // Effective Field Goal Percentage (eFG% = (FGM + 0.5 * 3PM) / FGA)
  const threeMade = shots.filter((s) => s.made && s.val === 3).length;
  const eFgPct = totalFga > 0 ? (totalFgm + 0.5 * threeMade) / totalFga : 0;

  // Shot distribution frequencies
  const threeAtt = shots.filter((s) => s.val === 3).length;
  const rimAtt = shots.filter((s) => s.zone === 'Restricted Area').length;
  const midAtt = shots.filter((s) => s.zone.includes('Mid')).length;

  const threeFreq = totalFga > 0 ? threeAtt / totalFga : 0;
  const rimFreq = totalFga > 0 ? rimAtt / totalFga : 0;
  const midFreq = totalFga > 0 ? midAtt / totalFga : 0;

  const hotCount = zoneMetrics.filter((z) => z.status === 'HOT').length;
  const coldCount = zoneMetrics.filter((z) => z.status === 'COLD').length;

  return {
    totalFga,
    totalFgm,
    fgPct,
    eFgPct,
    threeMade,
    threeAtt,
    threeFreq,
    rimFreq,
    midFreq,
    hotCount,
    coldCount,
  };
}

/**
 * Generate 2D Hexagonal Bins across the court
 */
export function generateHexbins(shots: ShotRecord[], hexRadius: number = 16): HexBin[] {
  const bins = new Map<string, { fga: number; fgm: number; xSum: number; ySum: number }>();
  const totalShots = Math.max(1, shots.length);

  // Hexagonal grid spacing
  const dx = hexRadius * Math.sqrt(3);
  const dy = hexRadius * 1.5;

  for (const s of shots) {
    const sx = toSvgX(s.x);
    const sy = toSvgY(s.y);

    // Approximate hex column and row
    const col = Math.round(sx / dx);
    const row = Math.round(sy / dy);
    const hexId = `${col}_${row}`;

    const current = bins.get(hexId) || { fga: 0, fgm: 0, xSum: 0, ySum: 0 };
    current.fga += 1;
    if (s.made) current.fgm += 1;
    current.xSum += sx;
    current.ySum += sy;
    bins.set(hexId, current);
  }

  const result: HexBin[] = [];

  bins.forEach((data, id) => {
    const fga = data.fga;
    const fgm = data.fgm;
    const fgPct = fgm / fga;
    const freqPct = fga / totalShots;

    // Center of this bin
    const cx = data.xSum / fga;
    const cy = data.ySum / fga;

    // Radius dynamic based on shot frequency (Kirk Goldsberry style)
    const scaledR = Math.min(hexRadius * 1.15, Math.max(hexRadius * 0.45, hexRadius * Math.sqrt(freqPct * 8)));

    // Generate 6 polygon points
    const points: string[] = [];
    for (let i = 0; i < 6; i++) {
      const angle = (Math.PI / 180) * (60 * i - 30);
      const px = cx + scaledR * Math.cos(angle);
      const py = cy + scaledR * Math.sin(angle);
      points.push(`${px.toFixed(1)},${py.toFixed(1)}`);
    }

    // Baseline ~40% for relative hex color
    const lgPct = 0.42;
    const deltaPct = fgPct - lgPct;

    result.push({
      id,
      x: cx,
      y: cy,
      fga,
      fgm,
      fgPct,
      lgPct,
      deltaPct,
      freqPct,
      points: points.join(' '),
    });
  });

  return result;
}

/**
 * Returns thermal fill color for delta against league average
 */
export function getThermalColor(deltaPct: number, status?: ZoneStatus): string {
  if (status === 'LOW_SAMPLE') {
    return 'rgba(100, 116, 139, 0.25)'; // Muted slate
  }
  if (status === 'HOT') {
    return deltaPct >= 0.10 ? 'rgba(239, 68, 68, 0.75)' : 'rgba(244, 63, 94, 0.65)';
  }
  if (status === 'COLD') {
    return deltaPct <= -0.10 ? 'rgba(6, 182, 212, 0.75)' : 'rgba(59, 130, 246, 0.65)';
  }
  if (deltaPct >= 0.02) {
    return 'rgba(249, 115, 22, 0.35)'; // Gentle warm amber tint
  }
  if (deltaPct <= -0.02) {
    return 'rgba(99, 102, 241, 0.35)'; // Gentle cool indigo tint
  }
  return 'rgba(148, 163, 184, 0.22)'; // Translucent Neutral Slate
}

export function getStatusBadge(status: ZoneStatus) {
  switch (status) {
    case 'HOT':
      return {
        label: 'HOT',
        bg: 'bg-rose-500/20 text-rose-300 border-rose-500/40',
        dot: 'bg-rose-500',
      };
    case 'COLD':
      return {
        label: 'COLD',
        bg: 'bg-cyan-500/20 text-cyan-300 border-cyan-500/40',
        dot: 'bg-cyan-500',
      };
    case 'LOW_SAMPLE':
      return {
        label: 'LOW VOL',
        bg: 'bg-slate-800 text-slate-400 border-slate-700',
        dot: 'bg-slate-500',
      };
    default:
      return {
        label: 'NEUTRAL',
        bg: 'bg-slate-800/80 text-slate-300 border-slate-700',
        dot: 'bg-slate-400',
      };
  }
}

/**
 * Descriptive label and sub-label for discrete court zones
 */
export function getZoneDisplayName(zone: string): { name: string; subtitle: string } {
  switch (zone) {
    case 'Center 3':
      return { name: 'Top of Key 3', subtitle: 'Straight-Away 3PT' };
    case 'Center Mid':
      return { name: 'Top of Key Mid', subtitle: 'Free Throw / Elbow' };
    case 'Deep / Logo 3':
      return { name: 'Deep / Logo 3', subtitle: 'Top of Key (28+ ft)' };
    case 'Left Wing 3':
      return { name: 'Left Wing 3', subtitle: 'Above Break Left' };
    case 'Right Wing 3':
      return { name: 'Right Wing 3', subtitle: 'Above Break Right' };
    case 'Left Corner 3':
      return { name: 'Left Corner 3', subtitle: 'Baseline Corner' };
    case 'Right Corner 3':
      return { name: 'Right Corner 3', subtitle: 'Baseline Corner' };
    case 'Left Wing Mid':
      return { name: 'Left Wing Mid', subtitle: 'Left High Mid' };
    case 'Right Wing Mid':
      return { name: 'Right Wing Mid', subtitle: 'Right High Mid' };
    case 'Left Baseline Mid':
      return { name: 'Left Baseline Mid', subtitle: 'Short Corner Left' };
    case 'Right Baseline Mid':
      return { name: 'Right Baseline Mid', subtitle: 'Short Corner Right' };
    case 'Paint (High / FT)':
      return { name: 'Paint (High / FT)', subtitle: 'Free Throw Pocket' };
    case 'Paint (Low / Floater)':
      return { name: 'Paint (Low / Floater)', subtitle: 'Non-RA Floater Zone' };
    case 'Restricted Area':
      return { name: 'Restricted Area', subtitle: 'Under Rim (< 4.2 ft)' };
    default:
      return { name: zone, subtitle: '' };
  }
}

