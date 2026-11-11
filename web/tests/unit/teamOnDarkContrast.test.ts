import { describe, it, expect } from 'vitest';
import { WNBA_TEAMS_METADATA, getTeamColors, contrastRatio } from '@/lib/teams';

// Issue #133: `colors.primary` was computed for use on light/neutral
// backgrounds, so 13/15 WNBA team primaries fail the WCAG 2.2 4.5:1 text
// contrast minimum against this app's dark surface tokens
// (surface #100a22 / surface-raised #1d1440). getTeamColors() now also
// returns `onDark`, a lightened variant of the primary guaranteed to clear
// 4.5:1 against both surfaces.

const DARK_SURFACES = ['#100a22', '#1d1440'];

describe("getTeamColors().onDark — issue #133 WCAG contrast", () => {
  const abbrs = Object.keys(WNBA_TEAMS_METADATA);

  it('covers all 15 WNBA teams', () => {
    expect(abbrs.length).toBe(15);
  });

  for (const abbr of abbrs) {
    it(`${abbr}: onDark reaches >= 4.5:1 against both surface tokens`, () => {
      const { onDark } = getTeamColors(abbr);
      expect(onDark).toBeTruthy();
      for (const surface of DARK_SURFACES) {
        const ratio = contrastRatio(onDark as string, surface);
        expect(ratio).toBeGreaterThanOrEqual(4.5);
      }
    });
  }

  it('is purely additive: primary/secondary/accent are unchanged', () => {
    const colors = getTeamColors('ATL');
    const original = WNBA_TEAMS_METADATA.ATL.colors;
    expect(colors.primary).toBe(original.primary);
    expect(colors.secondary).toBe(original.secondary);
    expect(colors.accent).toBe(original.accent);
  });
});
