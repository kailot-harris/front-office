import { describe, expect, it } from 'vitest';
import table from '../e2e/switcher-table.fixture.json';
import { resolveSwitch, switchHref, COMMON_PATHS, type SwitcherTable } from '@/components/SportSwitcher';

// front-office#212 resolver rules, checked against a copy of the aggregator's
// nav/switcher.json. Identical in all four sport repos.
const T = table as SwitcherTable;

describe('sport switcher resolver (#212)', () => {
  it('rule 1: same address when the target has it', () => {
    expect(resolveSwitch(T, 'nba', 'wnba', '/shots/')).toEqual({ path: '/shots' });
    expect(resolveSwitch(T, 'mlb', 'nfl', '/players')).toEqual({ path: '/players' });
  });
  it('rule 2: related page with a note', () => {
    expect(resolveSwitch(T, 'nba', 'nfl', '/shots')).toEqual({ path: '/passing', note: ['Shot Charts', 'Passing Charts'] });
    expect(resolveSwitch(T, 'nfl', 'mlb', '/passing')).toEqual({ path: '/spatial', note: ['Passing Charts', 'Spatial Analytics'] });
    expect(resolveSwitch(T, 'wnba', 'nfl', '/bracket-2026')).toEqual({ path: '/playoffs', note: ['2026 Bracket', 'Playoff Simulator'] });
  });
  it('rule 3: Season Standings with a note', () => {
    expect(resolveSwitch(T, 'nba', 'mlb', '/coaches')).toEqual({ path: '/', note: ['Coaching Staffs', 'Season Standings'] });
    expect(resolveSwitch(T, 'nfl', 'wnba', '/cap-sheet')).toEqual({ path: '/offseason', note: ['Payroll & Cap', 'Offseason Moves'] });
  });
  it('table failure: common pages keep the address, the rest go to standings', () => {
    expect(resolveSwitch(null, 'nba', 'nfl', '/players/')).toEqual({ path: '/players' });
    expect(resolveSwitch(null, 'nba', 'nfl', '/shots/')).toEqual({ path: '/' });
    for (const p of COMMON_PATHS) {
      for (const s of ['nfl', 'nba', 'wnba', 'mlb']) expect(T.sports[s].pages).toHaveProperty([p]);
    }
  });
  it('hrefs end in a slash and carry the note', () => {
    expect(switchHref('nfl', { path: '/' })).toMatch(/\/nfl\/$/);
    expect(switchHref('nfl', { path: '/passing', note: ['Shot Charts', 'Passing Charts'] }))
      .toMatch(/\/nfl\/passing\/\?from=Shot\+Charts&to=Passing\+Charts$/);
  });
});
