/**
 * Unit tests for `lib/data.ts` — the single I/O boundary of the whole app.
 *
 * Every page is a server component that calls one of these getters at build
 * time, so a throw here is a failed `next build`, not a runtime error page.
 */
import { afterEach, describe, expect, it, vi } from 'vitest';
import fs from 'fs';
import * as data from '../../lib/data';
import { DATASET_FILES } from '../helpers/datasets';

afterEach(() => vi.restoreAllMocks());

describe('every getter reads its file and returns parsed data', () => {
  const getters = Object.keys(DATASET_FILES) as Array<keyof typeof DATASET_FILES>;
  const parameterizedGetters = ['getGameDetail'];

  it.each(getters)('%s() does not throw', (name) => {
    const fn = data[name] as () => unknown;
    expect(typeof fn, `lib/data.ts does not export ${name}`).toBe('function');
    expect(() => fn()).not.toThrow();
    expect(fn()).toBeTruthy();
  });

  it('exports exactly the getters the pages import, and no more', () => {
    const exported = Object.keys(data).filter((k) => typeof (data as Record<string, unknown>)[k] === 'function').sort();
    expect(exported).toEqual([...getters, ...parameterizedGetters].sort());
  });

  it('getGameDetail returns envelope or null', () => {
    expect(typeof data.getGameDetail).toBe('function');
    const existing = data.getGameDetail('2026_01_ARI_LAC');
    expect(existing).toBeTruthy();
    expect(existing?.game_id).toBe('2026_01_ARI_LAC');
    const missing = data.getGameDetail('nonexistent_game_id');
    expect(missing).toBeNull();
  });

  it('getStandingsData returns the dataset wrapper, not a bare array', () => {
    const d = data.getStandingsData();
    expect(Array.isArray(d)).toBe(false);
    expect(d.teams.length).toBeGreaterThan(0);
  });

  it('getTeamEpaProfiles returns a bare array, not a wrapper', () => {
    expect(Array.isArray(data.getTeamEpaProfiles())).toBe(true);
  });

  it('repeated calls return equal data (no mutation between reads)', () => {
    expect(data.getStandingsData()).toEqual(data.getStandingsData());
  });
});

describe('error handling when a dataset is absent', () => {
  it('throws a message naming the file and the fix', () => {
    vi.spyOn(fs, 'existsSync').mockReturnValue(false);
    expect(() => data.getStandingsData()).toThrow(/standings_projections\.json/);
    expect(() => data.getStandingsData()).toThrow(/export_web_datasets\.R/);
  });

  it('surfaces malformed JSON rather than returning a partial object', () => {
    vi.spyOn(fs, 'existsSync').mockReturnValue(true);
    vi.spyOn(fs, 'readFileSync').mockReturnValue('{ "teams": [' as never);
    expect(() => data.getStandingsData()).toThrow();
  });
});
