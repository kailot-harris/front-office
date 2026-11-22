import { describe, it, expect } from 'vitest';
import { NAV_ORDER, OFFSEASON_FIRST, orderNavItems } from '@/lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Offseason Moves' },
  { label: 'Season Standings' },
  { label: 'Diagnostics' },
  { label: 'Payroll & Cap' },
  { label: 'Matchups' },
];

describe('orderNavItems', () => {
  it('sorts by NAV_ORDER in the regular season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings', 'Matchups', 'Payroll & Cap', 'Offseason Moves', 'Diagnostics', 'Visual Gallery',
    ]);
  });
  it('puts OFFSEASON_FIRST items first in the offseason', () => {
    const withRetro = [...items, { label: 'Retrospective' }];
    expect(orderNavItems(withRetro, 'offseason').map((i) => i.label)).toEqual([
      'Offseason Moves', 'Retrospective', 'Season Standings', 'Matchups', 'Payroll & Cap', 'Diagnostics', 'Visual Gallery',
    ]);
  });
  it('uses plain NAV_ORDER when season state is missing', () => {
    expect(orderNavItems(items, undefined).map((i) => i.label)).toEqual(
      orderNavItems(items, 'regular').map((i) => i.label),
    );
  });
  it('throws on a label not in NAV_ORDER', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });
  it('does not mutate input and OFFSEASON_FIRST is a subset of NAV_ORDER', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
    for (const l of OFFSEASON_FIRST) expect(NAV_ORDER).toContain(l);
  });
});
