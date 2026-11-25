import { describe, expect, it } from 'vitest';
import { NAV_GROUPS, NAV_ORDER, groupNavItems, orderNavItems } from '@/lib/navOrder';

const items = [
  { label: 'Visual Gallery' },
  { label: 'Retrospective' },
  { label: 'Matchups' },
  { label: 'Offseason Moves' },
  { label: 'Season Standings' },
];
const labels = (xs: { label: string }[]) => xs.map((x) => x.label);

describe('NAV_GROUPS & NAV_ORDER (#230)', () => {
  it('defines the 5 canonical groups in exact order with unique labels', () => {
    expect(NAV_GROUPS.map((g) => g.id)).toEqual([
      'season-games',
      'player',
      'front-office',
      'visualizations',
      'models',
    ]);
    expect(NAV_GROUPS.map((g) => g.label)).toEqual([
      'Season & Games',
      'Player',
      'Front Office',
      'Visualizations',
      'Models',
    ]);
    const allLabels = NAV_GROUPS.flatMap((g) => g.labels);
    expect(new Set(allLabels).size).toBe(allLabels.length);
    expect(NAV_ORDER).toEqual(allLabels);
  });
});

describe('groupNavItems (#230)', () => {
  it('groups items in canonical order, omits empty groups, and sets season-games defaultOpen in regular season', () => {
    const grouped = groupNavItems(items, 'regular');
    expect(grouped.map((g) => g.id)).toEqual(['season-games', 'front-office', 'visualizations', 'models']);
    expect(grouped.map((g) => g.defaultOpen)).toEqual([false, false, false, false]);
    expect(labels(grouped[0].items)).toEqual(['Season Standings', 'Matchups']);
    expect(labels(grouped[1].items)).toEqual(['Offseason Moves']);
    expect(labels(grouped[2].items)).toEqual(['Visual Gallery']);
    expect(labels(grouped[3].items)).toEqual(['Retrospective']);
  });

  it('moves Front Office to top with defaultOpen: true in offseason without moving tabs across groups', () => {
    const grouped = groupNavItems(items, 'offseason');
    expect(grouped.map((g) => g.id)).toEqual(['front-office', 'season-games', 'visualizations', 'models']);
    expect(grouped.map((g) => g.defaultOpen)).toEqual([true, false, false, false]);
    expect(labels(grouped[0].items)).toEqual(['Offseason Moves']);
    expect(labels(grouped[3].items)).toEqual(['Retrospective']);
  });

  it('falls back to regular order when seasonState is undefined', () => {
    expect(groupNavItems(items, undefined)).toEqual(groupNavItems(items, 'regular'));
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => groupNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });

  it('does not mutate the input array', () => {
    const copy = [...items];
    groupNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});

describe('orderNavItems (#221, #230)', () => {
  it('sorts by NAV_ORDER in the regular season and when state is missing', () => {
    expect(labels(orderNavItems(items, 'regular'))).toEqual([
      'Season Standings',
      'Matchups',
      'Offseason Moves',
      'Visual Gallery',
      'Retrospective',
    ]);
    expect(labels(orderNavItems(items, undefined))).toEqual(labels(orderNavItems(items, 'regular')));
  });

  it('places Front Office items first in the offseason while keeping Retrospective in Models', () => {
    expect(labels(orderNavItems(items, 'offseason'))).toEqual([
      'Offseason Moves',
      'Season Standings',
      'Matchups',
      'Visual Gallery',
      'Retrospective',
    ]);
  });

  it('throws on a label not in NAV_GROUPS', () => {
    expect(() => orderNavItems([{ label: 'Mystery Page' }], undefined)).toThrow(/Mystery Page/);
  });
});
