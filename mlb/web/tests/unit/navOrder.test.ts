import { describe, expect, it } from 'vitest';
import {
  NAV_GROUPS,
  NAV_ORDER,
  groupNavItems,
  orderNavItems,
  validateNavGroups,
} from '@/lib/navOrder';

const items = [
  'Visual Gallery',
  'Offseason Moves',
  'Season Standings',
  'Retrospective',
  'Payroll & Cap',
  'Matchups',
  'Player Ratings & Projections',
  'Model Variants',
].map((label) => ({ label }));

describe('NAV_GROUPS and groupNavItems (front-office #230)', () => {
  it('defines the 5 canonical groups in exact order', () => {
    expect(NAV_GROUPS.map((g) => ({ id: g.id, label: g.label }))).toEqual([
      { id: 'season-games', label: 'Season & Games' },
      { id: 'player', label: 'Player' },
      { id: 'front-office', label: 'Front Office' },
      { id: 'visualizations', label: 'Visualizations' },
      { id: 'models', label: 'Models' },
    ]);
    expect(NAV_ORDER).toEqual(NAV_GROUPS.flatMap((g) => g.labels));
  });

  it('groups items in canonical order in the regular season with defaultOpen=false', () => {
    const groups = groupNavItems(items, 'regular');
    expect(groups.map((g) => g.id)).toEqual([
      'season-games',
      'player',
      'front-office',
      'visualizations',
      'models',
    ]);
    expect(groups.every((g) => g.defaultOpen === false)).toBe(true);
    expect(groups[0].items.map((i) => i.label)).toEqual(['Season Standings', 'Matchups']);
    expect(groups[2].items.map((i) => i.label)).toEqual(['Payroll & Cap', 'Offseason Moves']);
    expect(groups[4].items.map((i) => i.label)).toEqual(['Model Variants', 'Retrospective']);
  });

  it('moves Front Office to the top with defaultOpen=true in the offseason without moving tabs across groups', () => {
    const groups = groupNavItems(items, 'offseason');
    expect(groups.map((g) => g.id)).toEqual([
      'front-office',
      'season-games',
      'player',
      'visualizations',
      'models',
    ]);
    expect(groups[0].defaultOpen).toBe(true);
    expect(groups.slice(1).every((g) => g.defaultOpen === false)).toBe(true);
    // Retrospective stays in Models; Season Standings stays in Season & Games.
    expect(groups[0].items.map((i) => i.label)).toEqual(['Payroll & Cap', 'Offseason Moves']);
    expect(groups[4].items.map((i) => i.label)).toEqual(['Model Variants', 'Retrospective']);
  });

  it('omits groups with zero items for that sport', () => {
    const subset = [{ label: 'Season Standings' }, { label: 'Diagnostics' }];
    const groups = groupNavItems(subset, 'regular');
    expect(groups.map((g) => g.id)).toEqual(['season-games', 'models']);
  });

  it('throws on duplicate labels in validateNavGroups', () => {
    expect(() =>
      validateNavGroups([
        { id: 'season-games', label: 'Season & Games', labels: ['Matchups'] },
        { id: 'player', label: 'Player', labels: ['Matchups'] },
      ]),
    ).toThrow(/duplicate.*Matchups/i);
  });

  it('throws on a label that is not in NAV_GROUPS', () => {
    expect(() => groupNavItems([{ label: 'Mystery Page' }], 'offseason')).toThrow(/Mystery Page/);
  });
});

describe('orderNavItems (front-office #221, #230)', () => {
  it('sorts by NAV_ORDER in the regular season', () => {
    expect(orderNavItems(items, 'regular').map((i) => i.label)).toEqual([
      'Season Standings',
      'Matchups',
      'Player Ratings & Projections',
      'Payroll & Cap',
      'Offseason Moves',
      'Visual Gallery',
      'Model Variants',
      'Retrospective',
    ]);
  });

  it('puts Front Office group first in the offseason while keeping tabs in their groups', () => {
    expect(orderNavItems(items, 'offseason').map((i) => i.label)).toEqual([
      'Payroll & Cap',
      'Offseason Moves',
      'Season Standings',
      'Matchups',
      'Player Ratings & Projections',
      'Visual Gallery',
      'Model Variants',
      'Retrospective',
    ]);
  });

  it('falls back to plain NAV_ORDER when season state is missing', () => {
    const labels = orderNavItems(items, undefined).map((i) => i.label);
    expect(labels).toEqual([...labels].sort((a, b) => NAV_ORDER.indexOf(a) - NAV_ORDER.indexOf(b)));
    expect(labels[0]).toBe('Season Standings');
  });

  it('does not mutate its input', () => {
    const copy = [...items];
    orderNavItems(items, 'offseason');
    expect(items).toEqual(copy);
  });
});
