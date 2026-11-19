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
});
