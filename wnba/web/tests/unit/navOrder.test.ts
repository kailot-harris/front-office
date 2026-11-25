import { describe, expect, it } from 'vitest';
import { NAV_GROUPS, NAV_ORDER, groupNavItems, orderNavItems } from '../../lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Retrospective' },
  { label: 'Offseason Moves' },
  { label: 'Matchups' },
  { label: 'Season Standings' },
];

describe('NAV_GROUPS', () => {
  it('defines the 5 groups in exact order with unique labels', () => {
    expect(NAV_GROUPS.map((g) => g.id)).toEqual([
      'season-games',
      'player',
      'front-office',
      'visualizations',
      'models',
    ]);
    const allLabels = NAV_GROUPS.flatMap((g) => g.labels);
    expect(new Set(allLabels).size).toBe(allLabels.length);
    expect(NAV_ORDER).toEqual(allLabels);
  });
});

describe('groupNavItems', () => {
  it('orders groups by NAV_GROUPS in season with Season & Games defaultOpen', () => {
    const groups = groupNavItems(items, 'regular');
    expect(groups.map((g) => g.id)).toEqual([
      'season-games',
      'front-office',
      'visualizations',
      'models',
    ]);
    expect(groups.map((g) => g.defaultOpen)).toEqual([true, false, false, false]);
    expect(groups[0].items.map((i) => i.label)).toEqual(['Season Standings', 'Matchups']);
  });

  it('promotes Front Office to top with defaultOpen: true in offseason without moving tabs across groups', () => {
    const groups = groupNavItems(items, 'offseason');
    expect(groups.map((g) => g.id)).toEqual([
      'front-office',
      'season-games',
      'visualizations',
      'models',
    ]);
    expect(groups.map((g) => g.defaultOpen)).toEqual([true, false, false, false]);
    expect(groups.find((g) => g.id === 'front-office')?.items.map((i) => i.label)).toEqual([
      'Offseason Moves',
    ]);
    expect(groups.find((g) => g.id === 'models')?.items.map((i) => i.label)).toEqual([
      'Retrospective',
    ]);
  });

  it('omits groups with zero items', () => {
    const groups = groupNavItems([{ label: 'Matchups' }], undefined);
    expect(groups).toHaveLength(1);
    expect(groups[0].id).toBe('season-games');
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => groupNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });

  it('does not mutate its input', () => {
    const copy = [...items];
    groupNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});

describe('orderNavItems', () => {
  it('sorts by NAV_ORDER in season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings',
      'Matchups',
      'Offseason Moves',
      'Visual Gallery',
      'Retrospective',
    ]);
  });

  it('puts Front Office items first in the offseason while keeping Retrospective in Models', () => {
    expect(orderNavItems(items, 'offseason').map((i) => i.label)).toEqual([
      'Offseason Moves',
      'Season Standings',
      'Matchups',
      'Visual Gallery',
      'Retrospective',
    ]);
  });

  it('uses plain NAV_ORDER when the season state is missing', () => {
    expect(orderNavItems(items, undefined).map((i) => i.label)).toEqual(
      NAV_ORDER.filter((l) => items.some((i) => i.label === l)),
    );
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });

  it('does not mutate its input', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});
