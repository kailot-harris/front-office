import { describe, it, expect } from 'vitest';
import { MLB_TEAMS_METADATA, getTeamColors } from '@/lib/teams';

// The two dark surface tokens `onDark` must stay readable against
// (issue #133): the app shell background and the raised card background.
const DARK_SURFACES = ['#040a1a', '#0b1530'];

function hexToRgb(hex: string) {
  const h = hex.replace('#', '');
  return {
    r: parseInt(h.slice(0, 2), 16),
    g: parseInt(h.slice(2, 4), 16),
    b: parseInt(h.slice(4, 6), 16),
  };
}

// WCAG 2.x relative luminance (https://www.w3.org/TR/WCAG21/#dfn-relative-luminance)
function srgbChannelToLinear(c: number) {
  const cs = c / 255;
  return cs <= 0.03928 ? cs / 12.92 : Math.pow((cs + 0.055) / 1.055, 2.4);
}

function relativeLuminance({ r, g, b }: { r: number; g: number; b: number }) {
  return 0.2126 * srgbChannelToLinear(r) + 0.7152 * srgbChannelToLinear(g) + 0.0722 * srgbChannelToLinear(b);
}

// WCAG 2.x contrast ratio (https://www.w3.org/TR/WCAG21/#dfn-contrast-ratio)
function contrastRatio(hexA: string, hexB: string) {
  const l1 = relativeLuminance(hexToRgb(hexA));
  const l2 = relativeLuminance(hexToRgb(hexB));
  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

describe('lib/teams.ts onDark team colors (issue #133 — WCAG 4.5:1 on dark surfaces)', () => {
  it('every team in MLB_TEAMS_METADATA has an onDark color', () => {
    const teams = Object.values(MLB_TEAMS_METADATA);
    expect(teams.length).toBeGreaterThan(0);
    for (const team of teams) {
      expect(team.colors.onDark).toMatch(/^#[0-9A-Fa-f]{6}$/);
    }
  });

  it('every team onDark color reaches >= 4.5:1 contrast against both dark surface tokens', () => {
    const failures: string[] = [];
    for (const [abbr, team] of Object.entries(MLB_TEAMS_METADATA)) {
      for (const surface of DARK_SURFACES) {
        const ratio = contrastRatio(team.colors.onDark, surface);
        if (ratio < 4.5) {
          failures.push(`${abbr}: onDark=${team.colors.onDark} vs ${surface} => ${ratio.toFixed(2)}:1`);
        }
      }
    }
    expect(failures).toEqual([]);
  });

  it('getTeamColors() exposes onDark for a known team and for the unknown-team fallback', () => {
    const known = getTeamColors('NYY');
    expect(known.onDark).toMatch(/^#[0-9A-Fa-f]{6}$/);
    for (const surface of DARK_SURFACES) {
      expect(contrastRatio(known.onDark, surface)).toBeGreaterThanOrEqual(4.5);
    }

    const fallback = getTeamColors('NOT_A_REAL_TEAM');
    expect(fallback.onDark).toMatch(/^#[0-9A-Fa-f]{6}$/);
    for (const surface of DARK_SURFACES) {
      expect(contrastRatio(fallback.onDark, surface)).toBeGreaterThanOrEqual(4.5);
    }
  });

  it('onDark is purely additive: primary/secondary/accent are unchanged from before', () => {
    // Spot-check a couple of teams to ensure this was an additive field,
    // not a rewrite of the existing (unused-as-text) primary colors.
    expect(MLB_TEAMS_METADATA.NYY.colors.primary).toBe('#003087');
    expect(MLB_TEAMS_METADATA.LAD.colors.primary).toBe('#005A9C');
  });
});
