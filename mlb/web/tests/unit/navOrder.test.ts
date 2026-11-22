import { describe, expect, it } from 'vitest';
import { NAV_ORDER, OFFSEASON_FIRST, orderNavItems } from '@/lib/navOrder';

const items = [
  'Visual Gallery',
  'Offseason Moves',
  'Season Standings',
  'Retrospective',
  'Payroll & Cap',
  'Matchups',
].map((label) => ({ label }));

describe('orderNavItems (front-office #221)', () => {
  it('sorts by NAV_ORDER in the regular season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings',
      'Matchups',
      'Payroll & Cap',
      'Offseason Moves',
      'Retrospective',
      'Visual Gallery',
    ]);
  });

  it('puts OFFSEASON_FIRST on top in the offseason', () => {
    expect(orderNavItems(items, 'offseason').map((i) => i.label)).toEqual([
      ...OFFSEASON_FIRST,
      'Season Standings',
      'Matchups',
      'Payroll & Cap',
      'Visual Gallery',
    ]);
  });

  it('falls back to plain NAV_ORDER when season state is missing', () => {
    const labels = orderNavItems(items, undefined).map((i) => i.label);
    expect(labels).toEqual([...labels].sort((a, b) => NAV_ORDER.indexOf(a) - NAV_ORDER.indexOf(b)));
    expect(labels[0]).toBe('Season Standings');
  });

  it('throws on a label that is not in NAV_ORDER', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], 'offseason')).toThrow(/Mystery Page/);
  });

  it('does not mutate its input', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});
