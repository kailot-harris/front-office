import { describe, expect, it } from 'vitest';
import { NAV_ORDER, OFFSEASON_FIRST, orderNavItems } from '@/lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Retrospective' },
  { label: 'Matchups' },
  { label: 'Offseason Moves' },
  { label: 'Season Standings' },
];
const labels = (xs: { label: string }[]) => xs.map((x) => x.label);

describe('orderNavItems (#221)', () => {
  it('sorts by NAV_ORDER in the regular season', () => {
    expect(labels(orderNavItems(items, 'regular'))).toEqual([
      'Season Standings', 'Matchups', 'Offseason Moves', 'Retrospective', 'Visual Gallery',
    ]);
  });
  it('puts OFFSEASON_FIRST on top in the offseason', () => {
    expect(labels(orderNavItems(items, 'offseason'))).toEqual([
      'Offseason Moves', 'Retrospective', 'Season Standings', 'Matchups', 'Visual Gallery',
    ]);
  });
  it('falls back to NAV_ORDER when the state is missing', () => {
    expect(labels(orderNavItems(items, undefined))).toEqual(labels(orderNavItems(items, 'regular')));
  });
  it('throws on a label not in NAV_ORDER', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });
  it('does not mutate the input and keeps OFFSEASON_FIRST within NAV_ORDER', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
    for (const l of OFFSEASON_FIRST) expect(NAV_ORDER).toContain(l);
  });
});
