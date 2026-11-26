/**
 * League leaders panel unit tests (MLB-Analytics#163), using renderToStaticMarkup
 * against the real player_leaders.json plus an empty-card fixture.
 */
import fs from 'fs';
import path from 'path';
import { describe, expect, it, vi } from 'vitest';
import { renderToStaticMarkup } from 'react-dom/server';
import type { LeaderPositionKey, PlayerLeadersPayload } from '@/lib/playerLeadersTypes';

let mockExpanded: boolean | null = null;
let mockPosition: LeaderPositionKey | null = null;

vi.mock('react', async (importOriginal) => {
  const actual = await importOriginal<typeof import('react')>();
  const useState = ((init: unknown) => {
    if (typeof init === 'boolean' && mockExpanded !== null) {
      return [mockExpanded, () => {}];
    }
    if (init === 'all' && mockPosition !== null) {
      return [mockPosition, () => {}];
    }
    return actual.useState(init);
  }) as typeof actual.useState;
  return { ...actual, default: { ...actual, useState }, useState };
});

const { LeagueLeadersPanel, formatLeaderValue } = await import('@/components/LeagueLeadersPanel');

const DATA: PlayerLeadersPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'player_leaders.json'), 'utf8'),
);

function renderPanel(
  data: PlayerLeadersPayload | null,
  opts: { expanded?: boolean; position?: LeaderPositionKey } = {},
) {
  mockExpanded = opts.expanded ?? null;
  mockPosition = opts.position ?? null;
  try {
    return renderToStaticMarkup(<LeagueLeadersPanel data={data} />);
  } finally {
    mockExpanded = null;
    mockPosition = null;
  }
}

describe('LeagueLeadersPanel', () => {
  it('renders batting and pitching groups and all 17 stat cards', () => {
    const html = renderPanel(DATA);
    for (const g of DATA.groups) {
      expect(html).toContain(`data-testid="leader-group-${g.key}"`);
    }
    for (const c of DATA.cards) {
      expect(html).toContain(`data-testid="leader-card-${c.key}"`);
    }
  });

  it('shows the top 3 collapsed and top 10 when expanded', () => {
    const avg = DATA.cards.find((c) => c.key === 'avg')!;
    const collapsedHtml = renderPanel({ ...DATA, cards: [avg] }, { expanded: false });
    const collapsedRows = collapsedHtml.match(/data-testid="leader-row"/g) ?? [];
    expect(collapsedRows).toHaveLength(Math.min(3, avg.leaders.all.length));
    expect(collapsedHtml).toContain(`Show top ${Math.min(avg.leaders.all.length, 10)}`);

    const expandedHtml = renderPanel({ ...DATA, cards: [avg] }, { expanded: true });
    const expandedRows = expandedHtml.match(/data-testid="leader-row"/g) ?? [];
    expect(expandedRows).toHaveLength(Math.min(10, avg.leaders.all.length));
    expect(expandedHtml).toContain('Show top 3');
  });

  it('position and role filters switch the displayed leaders', () => {
    const avg = DATA.cards.find((c) => c.key === 'avg')!;
    const ifHtml = renderPanel({ ...DATA, cards: [avg] }, { position: 'IF' });
    expect(ifHtml).toContain('data-testid="leader-filter-IF"');
    if (avg.leaders.IF.length > 0) {
      expect(ifHtml).toContain(avg.leaders.IF[0].player);
    }

    const era = DATA.cards.find((c) => c.key === 'era')!;
    const spHtml = renderPanel({ ...DATA, cards: [era] }, { position: 'SP' });
    if (era.leaders.SP.length > 0) {
      expect(spHtml).toContain(era.leaders.SP[0].player);
    }
  });

  it('every card shows a through date and noise-note cards carry the note', () => {
    const html = renderPanel(DATA);
    for (const c of DATA.cards) {
      if (c.through_date) {
        expect(html).toContain(`Through ${c.through_date}`);
      }
    }
    expect(html).toContain('data-testid="leader-noise-note"');
  });

  it('an empty card shows "Not enough games yet" and its reason', () => {
    const empty = {
      ...DATA.cards[0],
      key: 'empty_test',
      status: 'not_enough_games' as const,
      null_reason: 'No player has reached the scaled minimum yet.',
      leaders: { all: [], IF: [], OF: [], C_DH: [], SP: [], RP: [] },
      qualified_count: { all: 0, IF: 0, OF: 0, C_DH: 0, SP: 0, RP: 0 },
    };
    const html = renderPanel({ ...DATA, cards: [empty] });
    expect(html).toContain('data-testid="leader-empty"');
    expect(html).toContain('Not enough games yet');
    expect(html).toContain('scaled minimum');
  });

  it('methods note states scaling, traded-player rule, and study commit', () => {
    const html = renderPanel(DATA);
    expect(html).toContain('data-testid="leader-methods"');
    expect(html).toContain('team games played / 162');
    expect(html).toContain('traded player');
    expect(html).toContain(DATA.methods.study_source_commit.slice(0, 12));
  });

  it('formats values by card format', () => {
    expect(formatLeaderValue(0.3124, 'avg')).toBe('.312');
    expect(formatLeaderValue(1.0452, 'avg')).toBe('1.045');
    expect(formatLeaderValue(2.451, 'era')).toBe('2.45');
    expect(formatLeaderValue(198.6667, 'ip')).toBe('198.2');
    expect(formatLeaderValue(0.2453, 'pct')).toBe('24.5%');
    expect(formatLeaderValue(42, 'int')).toBe('42');
  });

  it('missing file renders an unavailable note', () => {
    const html = renderPanel(null);
    expect(html).toContain('data-testid="league-leaders"');
    expect(html).toContain('unavailable');
  });
});
