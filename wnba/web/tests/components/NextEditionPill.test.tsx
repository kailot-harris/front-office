import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import React from 'react';
import {
  NextEditionPill,
  OffseasonMonitorClient,
  formatProjectedDate,
} from '../../components/OffseasonMonitorClient';
import { getOffseasonMonitorData } from '../../lib/data';

// nextEdition as emitted for the published Week 1 edition (publishDate 2026-11-17).
const nextEdition = { weekNumber: 2, projectedPublishDate: '2026-11-23' };

describe('Next edition slot in the edition selector', () => {
  it('formats the projected date as weekday, day, month', () => {
    expect(formatProjectedDate('2026-11-23')).toBe('Mon 23 Nov');
  });

  it('shows a disabled, non-selectable pill with the projected date before it is due', () => {
    render(
      <NextEditionPill
        nextEdition={nextEdition}
        publishedWeeks={[1]}
        today={new Date(2026, 10, 20, 12)}
      />,
    );
    const pill = screen.getByTestId('next-edition-pill');
    expect(pill.textContent).toBe('Week 2 · expected Mon 23 Nov');
    expect(pill.hasAttribute('disabled')).toBe(true);
    expect(pill.getAttribute('aria-disabled')).toBe('true');
  });

  it('still shows the plain projected date on the projected day itself', () => {
    render(
      <NextEditionPill nextEdition={nextEdition} publishedWeeks={[1]} today={new Date(2026, 10, 23, 23)} />,
    );
    expect(screen.getByTestId('next-edition-pill').textContent).toBe('Week 2 · expected Mon 23 Nov');
  });

  it('says the edition is late once the projected date passes unpublished', () => {
    render(
      <NextEditionPill nextEdition={nextEdition} publishedWeeks={[1]} today={new Date(2026, 10, 24, 8)} />,
    );
    expect(screen.getByTestId('next-edition-pill').textContent).toBe(
      'Week 2 · expected Mon 23 Nov, not yet published',
    );
  });

  it('renders nothing when nextEdition is absent (older JSON)', () => {
    const { container } = render(
      <NextEditionPill nextEdition={undefined} publishedWeeks={[1]} today={new Date(2026, 10, 20)} />,
    );
    expect(container.innerHTML).toBe('');
    expect(screen.queryByTestId('next-edition-pill')).toBeNull();
  });

  it('renders nothing once that week has been published', () => {
    render(<NextEditionPill nextEdition={nextEdition} publishedWeeks={[1, 2]} today={new Date(2026, 10, 30)} />);
    expect(screen.queryByTestId('next-edition-pill')).toBeNull();
  });

  it('appears after the published pills on the real page and cannot change the selected edition', () => {
    const dataset = getOffseasonMonitorData();
    expect(dataset?.nextEdition).toEqual(nextEdition);
    render(<OffseasonMonitorClient initialDataset={dataset} />);

    const week1 = screen.getByRole('button', { name: /^Week 1/ });
    const pill = screen.getByTestId('next-edition-pill');
    expect(pill.textContent).toMatch(/^Week 2 · expected Mon 23 Nov/);
    expect(week1.compareDocumentPosition(pill) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();

    fireEvent.click(pill);
    expect(week1.className).toContain('bg-violet-600');
  });

  it('is absent from the page when the dataset has no nextEdition', () => {
    const dataset = getOffseasonMonitorData();
    if (!dataset) throw new Error('offseason_monitor.json missing');
    const { nextEdition: _omit, ...older } = dataset;
    void _omit;
    render(<OffseasonMonitorClient initialDataset={older} />);
    expect(screen.getByRole('button', { name: /^Week 1/ })).toBeDefined();
    expect(screen.queryByTestId('next-edition-pill')).toBeNull();
  });
});
