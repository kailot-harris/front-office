import { describe, expect, it } from 'vitest';
import { render } from '@testing-library/react';
import { PressureResiliencePlot } from '@/components/PressureResiliencePlot';
import { ClutchProfile, ClutchShotBreakdown } from '@/lib/clutchTypes';

const emptyShotBreakdown: ClutchShotBreakdown = {
  totalClutchFga: 0,
  rim: { fga: 0, fgm: 0, pct: 0 },
  mid: { fga: 0, fgm: 0, pct: 0 },
  three: { fga: 0, fgm: 0, pct: 0 },
};

function makeProfile(overrides: Partial<ClutchProfile>): ClutchProfile {
  return {
    playerId: 'p1',
    playerName: 'Test Player',
    team: 'TST',
    position: 'G',
    clutchArchetype: 'Closer',
    clutchMpg: 5,
    clutchUsgPct: 25,
    clutchTsPct: 55,
    baseTsPct: 55,
    tsDelta: 0,
    usciScore: 0,
    unassistedFgmPct: 0,
    clutchPpp: 1,
    tovFragility: 0,
    cDwpa: 0,
    shotBreakdown: emptyShotBreakdown,
    ...overrides,
  };
}

/**
 * Issue #87: the chart's axis domains were hard-coded to the old, clamped
 * data range (x: +/-4.5, y: 44-68). #81 replaced the underlying formulas
 * with play-by-play derivations whose values run far wider (observed
 * tovFragility -22.5..28.1, clutchTsPct 12.5..100), so points for those
 * profiles were drawn outside the plot rectangle.
 *
 * This locks in that the domain is derived from the data: a profile with
 * values well outside the old hard-coded bounds must still land inside the
 * padded plot box, not off the edge of the SVG viewBox.
 */
describe('PressureResiliencePlot', () => {
  const width = 500;
  const height = 300;
  const padding = 40;

  it('keeps an out-of-old-domain profile inside the padded plot box', () => {
    const outOfOldDomain = makeProfile({
      playerId: 'outlier',
      playerName: 'Outlier Player',
      tovFragility: -22.5,
      clutchTsPct: 100,
    });
    const normalProfile = makeProfile({ playerId: 'normal' });
    const profiles = [normalProfile, outOfOldDomain];

    const { container } = render(
      <PressureResiliencePlot
        profiles={profiles}
        selectedProfile={normalProfile}
        onSelectProfile={() => {}}
      />,
    );

    const circles = Array.from(container.querySelectorAll('circle[cx]'));
    expect(circles.length).toBeGreaterThan(0);

    for (const circle of circles) {
      const cx = Number(circle.getAttribute('cx'));
      const cy = Number(circle.getAttribute('cy'));
      expect(cx).toBeGreaterThanOrEqual(padding);
      expect(cx).toBeLessThanOrEqual(width - padding);
      expect(cy).toBeGreaterThanOrEqual(padding);
      expect(cy).toBeLessThanOrEqual(height - padding);
    }
  });

  it('keeps the 55% TS and 0% TOV reference lines inside the chart domain', () => {
    const outOfOldDomain = makeProfile({
      playerId: 'outlier',
      tovFragility: 28.1,
      clutchTsPct: 12.5,
    });
    const profiles = [outOfOldDomain];

    const { container } = render(
      <PressureResiliencePlot
        profiles={profiles}
        selectedProfile={outOfOldDomain}
        onSelectProfile={() => {}}
      />,
    );

    const lines = Array.from(container.querySelectorAll('line'));
    expect(lines.length).toBe(2);
    for (const line of lines) {
      const x1 = Number(line.getAttribute('x1'));
      const y1 = Number(line.getAttribute('y1'));
      expect(x1).toBeGreaterThanOrEqual(padding);
      expect(x1).toBeLessThanOrEqual(width - padding);
      expect(y1).toBeGreaterThanOrEqual(padding);
      expect(y1).toBeLessThanOrEqual(height - padding);
    }
  });
});
