import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import React from 'react';
import { MilestoneCalendar, OffseasonMonitorClient } from '../../components/OffseasonMonitorClient';
import { getOffseasonMonitorData } from '../../lib/data';

const rowDates = (group: HTMLElement) =>
  within(group)
    .getAllByTestId('milestone-row')
    .map((row) => row.querySelector('span')?.textContent);

describe('Block 4 milestone card', () => {
  it('Week 1 on the real page: lottery under Recently passed, never under Next 30 days', () => {
    const dataset = getOffseasonMonitorData();
    if (!dataset) throw new Error('offseason_monitor.json missing');
    const week1 = dataset.editions.find((e) => e.weekNumber === 1);
    expect(week1?.publishDate).toBe('2026-11-17');

    render(<OffseasonMonitorClient initialDataset={dataset} />);
    // The page opens on the latest edition; Week 1 is a frozen past edition.
    fireEvent.click(screen.getByRole('button', { name: /^Week 1/ }));

    const next30 = screen.getByTestId('milestones-next-30-days');
    const later = screen.getByTestId('milestones-later');
    const recent = screen.getByTestId('milestones-recently-passed');

    expect(within(recent).getByRole('heading').textContent).toBe('Recently passed (last 14 days)');
    expect(rowDates(recent)).toEqual(['2026-11-15']);
    expect(within(recent).getByText(/2027 WNBA Draft Lottery/)).toBeDefined();

    expect(within(next30).getByRole('heading').textContent).toBe('Next 30 days');
    expect(rowDates(next30)).toEqual(['Date TBD', 'Date TBD']);
    expect(within(next30).queryByText(/Draft Lottery/)).toBeNull();
    expect(within(next30).queryByText('2026-11-15')).toBeNull();

    expect(rowDates(later)).toEqual(['2027-04-12', '2027-04-25']);
  });

  it('shows Reported with its own badge, distinct from Tentative and Confirmed', () => {
    render(
      <MilestoneCalendar
        publishDate="2026-11-23"
        milestones={[
          { date: '2027-05-07', event: '2027 WNBA season window, reported, not confirmed', status: 'Reported' },
          { date: '2027-04-25', event: '2027 Training Camps Open', status: 'Tentative' },
          { date: '2027-04-12', event: '2027 WNBA Draft', status: 'Confirmed' },
        ]}
      />,
    );
    const badges = screen.getAllByTestId('milestone-status');
    expect(badges.map((b) => b.textContent)).toEqual(['Confirmed', 'Tentative', 'Reported']);
    const [confirmed, tentative, reported] = badges.map((b) => b.className);
    expect(reported).toContain('text-slate-400');
    expect(reported).not.toBe(tentative);
    expect(reported).not.toBe(confirmed);
  });

  it('keeps the empty state for the 30-day group and hides empty Later / Recently passed groups', () => {
    render(
      <MilestoneCalendar
        publishDate="2026-11-17"
        milestones={[{ date: '2026-10-01', event: 'Old event', status: 'Confirmed' }]}
      />,
    );
    expect(screen.getByText('No scheduled calendar events in next 30 days.')).toBeDefined();
    expect(screen.queryByTestId('milestones-later')).toBeNull();
    expect(screen.queryByTestId('milestones-recently-passed')).toBeNull();
    expect(screen.queryByText('Old event')).toBeNull();
  });
});
