import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import CalibrationCurve from '../../components/CalibrationCurve';
import { FootballIcon } from '../../components/FootballIcon';
import PlayerDnaClient from '../../components/PlayerDnaClient';
import { diagnostics, dnaDataset } from '../helpers/datasets';

function findDirectoryButton(container: HTMLElement, playerName: string): HTMLButtonElement {
  const btn = Array.from(container.querySelectorAll('button')).find(
    (el) =>
      el.textContent?.includes('Rating') &&
      Array.from(el.querySelectorAll('span')).some((span) => span.textContent?.trim() === playerName)
  );
  if (!btn) {
    throw new Error(`Directory button not found for ${playerName}`);
  }
  return btn;
}

describe('Remaining NFL SVG accessibility', () => {
  describe('CalibrationCurve', () => {
    const bins = diagnostics().calibration_curve;
    const gradedGames = bins.reduce(
      (sum, bin) => sum + (Number.isFinite(bin.count) ? bin.count : 0),
      0
    );

    it('renders the calibration chart svg with role="img" and dynamic aria-label', () => {
      const { container } = render(<CalibrationCurve bins={bins} />);
      const svg = container.querySelector('svg[viewBox="0 0 500 350"]');
      expect(svg).not.toBeNull();
      expect(svg).toHaveAttribute('role', 'img');
      expect(svg).not.toHaveAttribute('aria-hidden', 'true');

      const label = svg!.getAttribute('aria-label') ?? '';
      expect(label).toContain('Reliability calibration curve');
      expect(label).toContain(`${bins.length} probability`);
      expect(label).toContain(`${gradedGames} graded games`);
      expect(screen.getByRole('img', { name: label })).toBe(svg);
    });

    it('keeps a descriptive accessible label when rendered with no bins', () => {
      const { container } = render(<CalibrationCurve bins={[]} />);
      const svg = container.querySelector('svg[viewBox="0 0 500 350"]');
      expect(svg).not.toBeNull();
      expect(svg).toHaveAttribute('role', 'img');
      expect(svg).not.toHaveAttribute('aria-hidden', 'true');
      expect(svg!.getAttribute('aria-label')).toContain('no calibration bins available');
    });
  });

  describe('FootballIcon', () => {
    it('renders the football emblem svg with role="img" and descriptive aria-label', () => {
      const { container } = render(<FootballIcon className="w-10 h-10" size={40} />);
      const svg = container.querySelector('svg[viewBox="0 0 24 24"]');
      expect(svg).not.toBeNull();
      expect(svg).toHaveAttribute('role', 'img');
      expect(svg).not.toHaveAttribute('aria-hidden', 'true');

      const label = svg!.getAttribute('aria-label') ?? '';
      expect(label).toBe('NFL football emblem');
      expect(screen.getByRole('img', { name: label })).toBe(svg);
    });

    it('supports a custom ariaLabel override while defaulting blank overrides safely', () => {
      const { rerender, container } = render(<FootballIcon ariaLabel="League crest emblem" />);
      const svg = container.querySelector('svg[viewBox="0 0 24 24"]');
      expect(svg).toHaveAttribute('role', 'img');
      expect(svg).toHaveAttribute('aria-label', 'League crest emblem');

      rerender(<FootballIcon ariaLabel="   " />);
      expect(svg).toHaveAttribute('aria-label', 'NFL football emblem');
    });
  });

  describe('PlayerDnaClient RadarChart', () => {
    const dataset = dnaDataset();
    const subset = dataset.profiles.slice(0, 24);
    const defaultPlayer =
      subset.find((p) => p.playerName === 'P.Mahomes') ?? subset[0];
    const altPlayer = subset.find(
      (p) => p.playerId !== defaultPlayer.playerId && p.playerName !== defaultPlayer.playerName
    )!;

    it('renders the radar chart svg with role="img" and updates aria-label dynamically on selection and comparison', () => {
      const { container } = render(
        <PlayerDnaClient
          initialProfiles={subset}
          season={dataset.season}
          throughWeek={dataset.throughWeek}
          generatedAt={dataset.generatedAt}
        />
      );

      const svg = container.querySelector('svg[viewBox="0 0 320 320"]');
      expect(svg).not.toBeNull();
      expect(svg).toHaveAttribute('role', 'img');
      expect(svg).not.toHaveAttribute('aria-hidden', 'true');

      const initialLabel = svg!.getAttribute('aria-label') ?? '';
      expect(initialLabel).toContain(defaultPlayer.playerName);
      expect(initialLabel).toContain(defaultPlayer.position);
      expect(initialLabel).toContain(defaultPlayer.team);
      expect(initialLabel).toContain(`${defaultPlayer.radarAxes.length} empirical skill dimensions`);
      expect(screen.getByRole('img', { name: initialLabel })).toBe(svg);

      // Select another player from the directory and verify dynamic aria-label update.
      fireEvent.click(findDirectoryButton(container, altPlayer.playerName));
      const switchedLabel = svg!.getAttribute('aria-label') ?? '';
      expect(switchedLabel).toContain(altPlayer.playerName);
      expect(switchedLabel).toContain(altPlayer.position);
      expect(switchedLabel).toContain(altPlayer.team);

      // Enable compare mode and select the initial player as comparison target.
      fireEvent.click(screen.getByRole('button', { name: /Compare 2 Players/i }));
      fireEvent.click(findDirectoryButton(container, defaultPlayer.playerName));
      const compareLabel = svg!.getAttribute('aria-label') ?? '';
      expect(compareLabel).toContain('comparing');
      expect(compareLabel).toContain(altPlayer.playerName);
      expect(compareLabel).toContain(defaultPlayer.playerName);
    });
  });
});
