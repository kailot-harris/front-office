/**
 * /clutch board (NFL#80): sample minimum, honest count labels, season and
 * threshold stated on the page.
 */
import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import ClutchClient from '../../components/ClutchClient';
import { clutch } from '../helpers/datasets';

describe('ClutchClient', () => {
  const profiles = clutch();
  const min = profiles[0].minClutchAttempts;

  it('names both count columns and drops the old labels', () => {
    const { container } = render(<ClutchClient initialProfiles={profiles} />);
    const headers = Array.from(container.querySelectorAll('thead th')).map((th) => th.textContent?.trim());
    expect(headers).toContain('Clutch att');
    expect(headers).toContain('Clutch dropbacks');
    expect(headers).not.toContain('Att');
    expect(container.textContent).not.toContain('Total Drops');
    expect(container.textContent).toContain('Baseline dropbacks');
  });

  it('states the season, week and threshold from the data', () => {
    render(<ClutchClient initialProfiles={profiles} />);
    const window = screen.getByTestId('clutch-data-window');
    expect(window.textContent).toContain(`${profiles[0].season} season`);
    expect(window.textContent).toContain(`through week ${profiles[0].throughWeek}`);
    expect(window.textContent).toContain(`≥ ${min} clutch pass attempts`);
  });

  it('never ranks a low-sample QB, even in the All view sorted by fewest attempts', () => {
    const { container } = render(<ClutchClient initialProfiles={profiles} />);
    fireEvent.click(within(container).getByText(/^All \(/));
    const attHeader = within(container).getByText('Clutch att');
    fireEvent.click(attHeader); // sort by clutch attempts, descending
    fireEvent.click(attHeader); // then ascending: low samples must still sit below every qualified QB
    const rows = Array.from(container.querySelectorAll('tbody tr'));
    expect(rows).toHaveLength(profiles.length);
    const qualifiedCount = profiles.filter((p) => p.provenance === 'REAL_CURRENT_SEASON').length;
    rows.forEach((row, i) => {
      const rank = row.querySelector('td')?.textContent;
      expect(rank).toBe(i < qualifiedCount ? String(i + 1) : '—');
    });
  });

  it('labels the metric "4th Down Conversion %" and never "4th Down Aggressiveness"', () => {
    const { container } = render(<ClutchClient initialProfiles={profiles} />);
    expect(container.textContent).toContain('4th Down Conversion %');
    expect(container.textContent).not.toContain('4th Down Aggressiveness');
  });

  it('reads fourthDownConversionRate (including null as "—") and stays backward-compatible with fourthDownAggressiveness', () => {
    const base = profiles.find((p) => p.provenance === 'REAL_CURRENT_SEASON')!;
    const { fourthDownAggressiveness: _legacy, ...baseWithoutLegacy } = base;
    const fixtures = [
      {
        ...baseWithoutLegacy,
        playerId: 'QB-NEW-HIGH',
        playerName: 'New Format High',
        clutchEpaDelta: 0.25,
        fourthDownConversionRate: 62.5,
      },
      {
        ...baseWithoutLegacy,
        playerId: 'QB-NEW-ZERO',
        playerName: 'New Format Zero',
        clutchEpaDelta: 0.1,
        fourthDownConversionRate: 0,
      },
      {
        ...baseWithoutLegacy,
        playerId: 'QB-NEW-NULL',
        playerName: 'New Format No4th',
        clutchEpaDelta: 0.05,
        fourthDownConversionRate: null,
      },
      {
        ...baseWithoutLegacy,
        playerId: 'QB-LEGACY',
        playerName: 'Legacy Format QB',
        clutchEpaDelta: 0.01,
        fourthDownAggressiveness: 75.0,
      },
    ];

    const { container } = render(<ClutchClient initialProfiles={fixtures} />);
    // Default selected is QB-NEW-HIGH (highest clutchEpaDelta), showing 62.5% in inspector.
    expect(container.textContent).toContain('62.5%');

    const rows = Array.from(container.querySelectorAll('tbody tr'));
    expect(rows.map((r) => r.querySelector('td:last-child')?.textContent)).toEqual([
      '62.5%',
      '0.0%',
      '—',
      '75.0%',
    ]);

    // Click New Format No4th row and verify inspector renders "—" instead of "0.0%" or "50.0%".
    fireEvent.click(rows[2]);
    const inspectorLabel = within(container).getByText('4th Down Conversion %');
    expect(inspectorLabel.nextElementSibling?.textContent).toBe('—');

    // Sorting by 4th Conv % puts Legacy Format QB (75.0%) first descending, 0.0% first ascending,
    // and keeps null at bottom in both directions.
    fireEvent.click(within(container).getByText('4th Conv %'));
    const sortedDesc = Array.from(container.querySelectorAll('tbody tr')).map(
      (r) => r.querySelector('td:last-child')?.textContent
    );
    expect(sortedDesc).toEqual(['75.0%', '62.5%', '0.0%', '—']);

    fireEvent.click(within(container).getByText('4th Conv %'));
    const sortedAsc = Array.from(container.querySelectorAll('tbody tr')).map(
      (r) => r.querySelector('td:last-child')?.textContent
    );
    expect(sortedAsc).toEqual(['0.0%', '62.5%', '75.0%', '—']);
  });
});
