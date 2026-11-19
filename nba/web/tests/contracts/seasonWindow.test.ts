/**
 * front-office#191 — clutch, defense and Player DNA publish the season they were
 * built from, and their pages read it from the data instead of typing it.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WEB_ROOT, loadAllDatasets } from '../helpers/datasets';

const { metadata, clutchWindow, defenseWindow, playerDnaWindow, playerDna } = loadAllDatasets();

/** hoopR end-year (2027) -> '2026-27', the same derivation as season_label() in config.R. */
const endYear = (metadata as unknown as { season: number }).season;
const currentLabel = `${endYear - 1}-${String(endYear % 100).padStart(2, '0')}`;

const windows = [
  ['clutch_leverage_metrics.json', clutchWindow],
  ['defensive_metrics.json', defenseWindow],
  ['player_dna_profiles.json', playerDnaWindow],
] as const;

describe('Season window metadata (#191)', () => {
  it.each(windows)('%s season matches the current-season label', (_file, w) => {
    expect(w.season).toBe(currentLabel);
  });

  it.each(windows)('%s has a throughDate that is a real date and not in the future', (_file, w) => {
    expect(w.throughDate).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    const t = Date.parse(`${w.throughDate}T00:00:00Z`);
    expect(Number.isNaN(t)).toBe(false);
    expect(t).toBeLessThanOrEqual(Date.parse(w.generatedAt));
  });

  it('the three payloads cover the same play-by-play window', () => {
    expect(defenseWindow.throughDate).toBe(clutchWindow.throughDate);
    expect(playerDnaWindow.throughDate).toBe(clutchWindow.throughDate);
  });

  it('Player DNA peer comps are labelled with the payload season', () => {
    for (const p of playerDna) for (const c of p.peerComps) expect(c.era).toBe(playerDnaWindow.season);
  });

  it('a RAPM season that differs from the payload season is disclosed via rapmSeason', () => {
    // rapm_ratings.rds is last-completed-season; the payload must say so rather than imply current-season.
    for (const w of [defenseWindow, playerDnaWindow]) expect(w.rapmSeason).toMatch(/^\d{4}-\d{2}$/);
  });
});

describe('No hand-typed season in the clutch / defense / Player DNA pages', () => {
  const sources = [
    'app/clutch/page.tsx',
    'components/ClutchClient.tsx',
    'app/defense/page.tsx',
    'components/DefenseClient.tsx',
    'app/player-dna/page.tsx',
    'components/PlayerDnaClient.tsx',
  ];
  it.each(sources)('%s has no season literal', (rel) => {
    const src = fs.readFileSync(path.join(WEB_ROOT, rel), 'utf-8');
    expect(src).not.toMatch(/\b20\d{2}-(20)?\d{2}\b/);
  });
});
