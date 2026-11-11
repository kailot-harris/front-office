/**
 * Unit tests for `lib/teams.ts`'s `onDark` color derivation (#133).
 *
 * Team primaries are tuned for logos/swatches, not text-on-dark; 28/32 fail 4.5:1 against
 * this app's dark surfaces when used as text. `onDark` is a lightened variant that must
 * clear 4.5:1 against both `DARK_SURFACE_TOKENS` for every team — this is the acceptance
 * criterion for #133, asserted mechanically rather than by eyeballing swatches.
 */
import { describe, expect, it } from 'vitest';
import { NFL_TEAMS_METADATA, DARK_SURFACE_TOKENS, TEAM_ON_DARK_COLORS, getTeamColors } from '../../lib/teams';
import { contrastRatio } from '../../lib/colorContrast';

describe('team onDark colors meet WCAG 4.5:1 on dark surfaces', () => {
  const teamAbbrs = Object.keys(NFL_TEAMS_METADATA);

  it('derives an onDark color for every team', () => {
    expect(teamAbbrs.length).toBeGreaterThan(0);
    for (const abbr of teamAbbrs) {
      expect(TEAM_ON_DARK_COLORS[abbr]).toMatch(/^#[0-9A-F]{6}$/);
    }
  });

  it.each(teamAbbrs)('%s onDark >= 4.5:1 against both surface tokens', (abbr) => {
    const onDark = TEAM_ON_DARK_COLORS[abbr];
    for (const surface of DARK_SURFACE_TOKENS) {
      expect(contrastRatio(onDark, surface)).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('getTeamColors() exposes onDark alongside the existing primary/secondary/accent', () => {
    const colors = getTeamColors('KC');
    expect(colors.primary).toBe(NFL_TEAMS_METADATA.KC.colors.primary);
    expect(colors.onDark).toBe(TEAM_ON_DARK_COLORS.KC);
    for (const surface of DARK_SURFACE_TOKENS) {
      expect(contrastRatio(colors.onDark, surface)).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('getTeamColors() falls back gracefully for an unknown team code', () => {
    const colors = getTeamColors('ZZZ');
    expect(colors.onDark).toBeTruthy();
  });
});
