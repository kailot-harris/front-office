import fs from 'fs';
import path from 'path';
import { OffseasonMonitorDataset, SeasonMode } from './offseasonTypes';

export function getOffseasonMonitorData(): OffseasonMonitorDataset | null {
  const filePath = path.join(process.cwd(), 'public', 'data', 'offseason_monitor.json');
  if (!fs.existsSync(filePath)) return null;
  const fileContent = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(fileContent) as OffseasonMonitorDataset;
}

/**
 * Determine seasonMode ('offseason' | 'inseason') dynamically based on
 * baseline state, environment configuration, or default posture.
 */
export function getSeasonMode(): SeasonMode {
  // 1. Explicit environment variable override
  if (process.env.NEXT_PUBLIC_SEASON_MODE === 'inseason' || process.env.SEASON_MODE === 'inseason') {
    return 'inseason';
  }
  if (process.env.NEXT_PUBLIC_SEASON_MODE === 'offseason' || process.env.SEASON_MODE === 'offseason') {
    return 'offseason';
  }

  // 2. State baseline check (cache/league_state_baseline.json)
  try {
    const baselinePath = path.join(process.cwd(), '..', 'cache', 'league_state_baseline.json');
    if (fs.existsSync(baselinePath)) {
      const baseline = JSON.parse(fs.readFileSync(baselinePath, 'utf-8'));
      if (baseline.seasonStatus === '2027_SPRING_TRAINING' || baseline.seasonStatus === '2027_REGULAR_SEASON') {
        return 'inseason';
      }
    }
  } catch {
    // Fall back to default
  }

  // 3. Default to offseason during 2026-2027 winter period
  return 'offseason';
}

