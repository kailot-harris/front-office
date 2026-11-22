import { describe, expect, it } from 'vitest';
import { NAV_ORDER, orderNavItems } from '../../lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Retrospective' },
  { label: 'Offseason Moves' },
  { label: 'Matchups' },
  { label: 'Season Standings' },
];

describe('orderNavItems', () => {
  it('sorts by NAV_ORDER in season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings', 'Matchups', 'Offseason Moves', 'Retrospective', 'Visual Gallery',
    ]);
  });
  it('puts OFFSEASON_FIRST items on top in the offseason', () => {
    expect(orderNavItems(items, 'offseason').map((i) => i.label)).toEqual([
      'Offseason Moves', 'Retrospective', 'Season Standings', 'Matchups', 'Visual Gallery',
    ]);
  });
  it('uses plain NAV_ORDER when the season state is missing', () => {
    expect(orderNavItems(items, undefined).map((i) => i.label)).toEqual(
      NAV_ORDER.filter((l) => items.some((i) => i.label === l)),
    );
  });
  it('throws on a label not in NAV_ORDER', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });
  it('does not mutate its input', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});
