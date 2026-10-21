import { describe, it, expect } from 'vitest';
import {
  formatSeasonLabel,
  seasonEndYearLabel,
  SEASON_SOURCES,
} from '@/lib/season';

describe('lib/season.ts season labels', () => {
  it('expands short spans to full calendar years', () => {
    expect(formatSeasonLabel('2025-26')).toBe('2025-2026');
    expect(formatSeasonLabel('2026-27')).toBe('2026-2027');
    expect(formatSeasonLabel('2023-24')).toBe('2023-2024');
  });

  it('leaves full-year spans untouched', () => {
    expect(formatSeasonLabel('2025-2026')).toBe('2025-2026');
    expect(formatSeasonLabel('2026-2027')).toBe('2026-2027');
  });

  it('handles multiple pooled seasons', () => {
    expect(formatSeasonLabel('2025-26 + 2026-27')).toBe(
      '2025-2026 + 2026-2027'
    );
    expect(formatSeasonLabel('2024-2025 + 2025-2026')).toBe(
      '2024-2025 + 2025-2026'
    );
  });

  it('formats hoopR end years', () => {
    expect(formatSeasonLabel(2026)).toBe('2025-2026');
    expect(formatSeasonLabel(2027)).toBe('2026-2027');
    expect(seasonEndYearLabel(2026)).toBe('2025-2026');
  });

  it('returns null for empty input rather than guessing', () => {
    expect(formatSeasonLabel(null)).toBeNull();
    expect(formatSeasonLabel(undefined)).toBeNull();
    expect(formatSeasonLabel('')).toBeNull();
    expect(formatSeasonLabel('   ')).toBeNull();
  });

  it('publishes full-year labels for every canonical source', () => {
    for (const source of Object.values(SEASON_SOURCES)) {
      expect(source.season).toMatch(/^\d{4}-\d{4}( \+ \d{4}-\d{4})*$/);
      expect(source.note.length).toBeGreaterThan(10);
    }
  });

  it('uses the 2025-2026 fallback for data that cannot yet cover 2026-2027', () => {
    expect(SEASON_SOURCES.shots.season).toBe('2025-2026');
    expect(SEASON_SOURCES.coachesObserved.season).toBe('2025-2026');
    expect(SEASON_SOURCES.shots.kind).toBe('fallback');
    expect(SEASON_SOURCES.coachesObserved.kind).toBe('fallback');
  });
});
