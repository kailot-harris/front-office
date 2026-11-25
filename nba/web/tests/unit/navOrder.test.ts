import { describe, it, expect } from 'vitest';
import { NAV_GROUPS, NAV_ORDER, groupNavItems, orderNavItems } from '@/lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Offseason Moves' },
  { label: 'Season Standings' },
  { label: 'Diagnostics' },
  { label: 'Payroll & Cap' },
  { label: 'Matchups' },
];

describe('NAV_GROUPS & NAV_ORDER', () => {
  it('defines the five shared groups in exact order with unique labels', () => {
    expect(NAV_GROUPS.map((g) => [g.id, g.label])).toEqual([
      ['season-games', 'Season & Games'],
      ['player', 'Player'],
      ['front-office', 'Front Office'],
      ['visualizations', 'Visualizations'],
      ['models', 'Models'],
    ]);

    const seen = new Set<string>();
    for (const group of NAV_GROUPS) {
      for (const label of group.labels) {
        expect(seen.has(label)).toBe(false);
        seen.add(label);
      }
    }
    expect(NAV_ORDER).toEqual(NAV_GROUPS.flatMap((g) => g.labels));
  });
});

describe('groupNavItems', () => {
  it('groups items in NAV_GROUPS order and omits empty groups in regular season', () => {
    const grouped = groupNavItems(items, 'regular');
    expect(grouped.map((g) => g.id)).toEqual([
      'season-games',
      'front-office',
      'visualizations',
      'models',
    ]);
    expect(grouped.every((g) => g.defaultOpen === false)).toBe(true);
    expect(grouped[0].items.map((i) => i.label)).toEqual(['Season Standings', 'Matchups']);
    expect(grouped[1].items.map((i) => i.label)).toEqual(['Payroll & Cap', 'Offseason Moves']);
    expect(grouped[2].items.map((i) => i.label)).toEqual(['Visual Gallery']);
    expect(grouped[3].items.map((i) => i.label)).toEqual(['Diagnostics']);
  });

  it('moves Front Office to the top with defaultOpen: true in offseason without moving tabs across groups', () => {
    const withRetro = [...items, { label: 'Retrospective' }];
    const grouped = groupNavItems(withRetro, 'offseason');
    expect(grouped.map((g) => g.id)).toEqual([
      'front-office',
      'season-games',
      'visualizations',
      'models',
    ]);
    expect(grouped[0].defaultOpen).toBe(true);
    expect(grouped.slice(1).every((g) => g.defaultOpen === false)).toBe(true);
    expect(grouped[0].items.map((i) => i.label)).toEqual(['Payroll & Cap', 'Offseason Moves']);
    expect(grouped[3].items.map((i) => i.label)).toEqual(['Diagnostics', 'Retrospective']);
  });

  it('uses regular group order when seasonState is undefined', () => {
    expect(groupNavItems(items, undefined)).toEqual(groupNavItems(items, 'regular'));
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => groupNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });
});

describe('orderNavItems', () => {
  it('sorts by NAV_ORDER in the regular season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings', 'Matchups', 'Payroll & Cap', 'Offseason Moves', 'Visual Gallery', 'Diagnostics',
    ]);
  });

  it('leads with Front Office group in the offseason while keeping tabs in their groups', () => {
    const withRetro = [...items, { label: 'Retrospective' }];
    expect(orderNavItems(withRetro, 'offseason').map((i) => i.label)).toEqual([
      'Payroll & Cap', 'Offseason Moves', 'Season Standings', 'Matchups', 'Visual Gallery', 'Diagnostics', 'Retrospective',
    ]);
  });

  it('uses plain NAV_ORDER when season state is missing', () => {
    expect(orderNavItems(items, undefined).map((i) => i.label)).toEqual(
      orderNavItems(items, 'regular').map((i) => i.label),
    );
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });

  it('does not mutate input', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});
