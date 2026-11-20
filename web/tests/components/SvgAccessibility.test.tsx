import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/react';
import { AtoEfficiencyScatter } from '@/components/AtoEfficiencyScatter';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { DnaManifoldScatter } from '@/components/DnaManifoldScatter';
import { HalloweenBasketball } from '@/components/HalloweenBasketball';
import { PressureResiliencePlot } from '@/components/PressureResiliencePlot';
import { VersatilityScatter } from '@/components/VersatilityScatter';
import { loadAllDatasets } from '../helpers/datasets';

const { coaches, diagnostics, metadata, playerDna, clutch, defense } = loadAllDatasets();

function assertAccessibleSvg(container: HTMLElement, expectedPattern: RegExp) {
  const svgs = Array.from(container.querySelectorAll('svg[viewBox]')).filter(
    (el) => !el.classList.contains('lucide'),
  );
  expect(svgs.length).toBeGreaterThanOrEqual(1);

  const chartSvg = svgs[0];
  expect(chartSvg).toHaveAttribute('role', 'img');
  expect(chartSvg).not.toHaveAttribute('aria-hidden', 'true');

  const ariaLabel = chartSvg.getAttribute('aria-label')?.trim() ?? '';
  expect(ariaLabel.length).toBeGreaterThan(0);
  expect(ariaLabel).toMatch(expectedPattern);

  const accessibleImg = screen.getByRole('img', { name: expectedPattern });
  expect(accessibleImg).toBe(chartSvg);
  return chartSvg;
}

describe('SVG accessibility across NBA visualization components', () => {
  it('AtoEfficiencyScatter exposes role="img" and dynamic aria-label with and without a selected coach', () => {
    const selectedCoach =
      coaches.find(
        (c) => c.metrics.atoOffensivePpp !== null && c.metrics.atoDefensivePppAllowed !== null,
      ) ?? coaches[0];

    const { container, rerender } = render(
      <AtoEfficiencyScatter
        coaches={coaches}
        selectedCoach={selectedCoach}
        onSelectCoach={vi.fn()}
      />,
    );

    const selectedSvg = assertAccessibleSvg(
      container,
      new RegExp(`ATO offensive vs\\. defensive PPP.*${selectedCoach.teamAbbr}`, 'i'),
    );
    expect(selectedSvg.getAttribute('aria-label')).toContain(selectedCoach.headCoach.name);

    rerender(
      <AtoEfficiencyScatter
        coaches={coaches}
        selectedCoach={null}
        onSelectCoach={vi.fn()}
      />,
    );

    assertAccessibleSvg(container, /ATO offensive vs\. defensive PPP scatter plot \(\d+ teams\)/i);
  });

  it('DiagnosticsClient calibration chart SVG exposes role="img" and descriptive aria-label', () => {
    const { container } = render(
      <DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />,
    );

    const svg = assertAccessibleSvg(
      container,
      new RegExp(
        `Probability calibration curve.*${diagnostics.calibration.length} probability bins`,
        'i',
      ),
    );
    expect(svg.getAttribute('aria-label')).toContain(
      diagnostics.totalResolvedGames.toLocaleString(),
    );
  });

  it('DnaManifoldScatter exposes role="img" and dynamic aria-label with selected player', () => {
    const selectedPlayer =
      playerDna.find((p) => p.manifoldX !== null && p.manifoldY !== null) ?? playerDna[0];

    const { container } = render(
      <DnaManifoldScatter
        players={playerDna}
        selectedPlayer={selectedPlayer}
        onSelectPlayer={vi.fn()}
      />,
    );

    const svg = assertAccessibleSvg(
      container,
      new RegExp(
        `2D player DNA stylistic manifold.*${playerDna.length} players.*${selectedPlayer.team}`,
        'i',
      ),
    );
    expect(svg.getAttribute('aria-label')).toContain(selectedPlayer.playerName);
  });

  it('HalloweenBasketball exposes role="img" and descriptive aria-label', () => {
    const { container } = render(<HalloweenBasketball size={48} className="w-12 h-12" />);

    assertAccessibleSvg(container, /October Halloween jack-o'-lantern basketball/i);
  });

  it('PressureResiliencePlot exposes role="img" and dynamic aria-label with selected closer', () => {
    const selectedProfile =
      clutch.find((p) => p.clutchTsPct !== null && p.tovFragility !== null) ?? clutch[0];

    const { container } = render(
      <PressureResiliencePlot
        profiles={clutch}
        selectedProfile={selectedProfile}
        onSelectProfile={vi.fn()}
      />,
    );

    const svg = assertAccessibleSvg(
      container,
      new RegExp(`Pressure resilience scatter plot.*${selectedProfile.team}`, 'i'),
    );
    expect(svg.getAttribute('aria-label')).toContain(selectedProfile.playerName);
  });

  it('VersatilityScatter exposes role="img" and dynamic aria-label with selected defender', () => {
    const selectedProfile =
      defense.find((p) => p.versatilityScore !== null && p.rimDfgDelta !== null) ?? defense[0];

    const { container } = render(
      <VersatilityScatter
        profiles={defense}
        selectedProfile={selectedProfile}
        onSelectProfile={vi.fn()}
      />,
    );

    const svg = assertAccessibleSvg(
      container,
      new RegExp(`Defensive versatility vs\\. rim deterrence.*${selectedProfile.team}`, 'i'),
    );
    expect(svg.getAttribute('aria-label')).toContain(selectedProfile.playerName);
  });
});
