import { describe, expect, it } from 'vitest';
import {
  NBA_TEAMS_METADATA,
  getTeamColors,
  wcagContrastRatio,
  DARK_SURFACE_TOKENS,
} from '@/lib/teams';

/**
 * #133: team primary/secondary/accent colors are too dark for text/thin-
 * stroke use on this app's dark surface tokens (NBA: 29/30 primaries failed
 * 4.5:1 against #0a0920 / #14123a per the pre-launch review). Nothing reads
 * `primary`/`secondary`/`accent` for text today, so this is purely additive:
 * every team must expose an `onDark` color that actually clears WCAG 4.5:1
 * against both dark surfaces, computed via the real relative-luminance
 * formula, not a hand-picked guess.
 */
describe('lib/teams.ts onDark contrast (#133)', () => {
  const teamAbbrs = Object.keys(NBA_TEAMS_METADATA);

  it('has at least the 30 NBA franchises loaded', () => {
    expect(teamAbbrs.length).toBeGreaterThanOrEqual(30);
  });

  for (const abbr of teamAbbrs) {
    for (const surface of DARK_SURFACE_TOKENS) {
      it(`${abbr} onDark reaches >= 4.5:1 against ${surface}`, () => {
        const { onDark } = NBA_TEAMS_METADATA[abbr].colors;
        expect(typeof onDark).toBe('string');
        expect(onDark).toMatch(/^#[0-9A-F]{6}$/i);
        expect(wcagContrastRatio(onDark, surface)).toBeGreaterThanOrEqual(4.5);
      });
    }
  }

  it('does not change primary/secondary/accent for any team', () => {
    // #133 is additive only -- primary/secondary/accent must still be the
    // original hex values teams.ts has always shipped (spot-check a few).
    expect(NBA_TEAMS_METADATA.BOS.colors.primary).toBe('#007A33');
    expect(NBA_TEAMS_METADATA.LAL.colors.secondary).toBe('#FDB927');
    expect(NBA_TEAMS_METADATA.CHI.colors.accent).toBe('#FFFFFF');
  });

  it('getTeamColors() exposes onDark for a known team and for an unknown fallback', () => {
    const known = getTeamColors('BOS');
    expect(wcagContrastRatio(known.onDark, '#0a0920')).toBeGreaterThanOrEqual(4.5);
    expect(wcagContrastRatio(known.onDark, '#14123a')).toBeGreaterThanOrEqual(4.5);

    const fallback = getTeamColors('NOT_A_TEAM');
    expect(wcagContrastRatio(fallback.onDark, '#0a0920')).toBeGreaterThanOrEqual(4.5);
    expect(wcagContrastRatio(fallback.onDark, '#14123a')).toBeGreaterThanOrEqual(4.5);
  });
});
