/**
 * League leaders panel (WNBA_analytics#268), against the real player_leaders.json
 * plus a hand-made empty card: grouped cards, top 3 expanding to top 10, the
 * position filter, through dates, noise notes, and "Not enough games yet".
 */
import React from 'react';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LeagueLeadersPanel, formatLeaderValue } from '@/components/LeagueLeadersPanel';
import type { PlayerLeadersPayload } from '@/lib/playerLeadersTypes';

const DATA: PlayerLeadersPayload = JSON.parse(
  fs.readFileSync(path.join(process.cwd(), 'public', 'data', 'player_leaders.json'), 'utf8'),
);
const card = (key: string) => screen.getByTestId(`leader-card-${key}`);
const names = (key: string) => within(card(key)).queryAllByTestId('leader-row').map((li) => li.textContent ?? '');

describe('LeagueLeadersPanel', () => {
  it('renders the six groups and one card per stat', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    for (const g of DATA.groups) expect(screen.getByTestId(`leader-group-${g.key}`)).toBeInTheDocument();
    for (const c of DATA.cards) expect(card(c.key)).toBeInTheDocument();
  });

  it('shows the top 3 and expands to the top 10', async () => {
    const pts = DATA.cards.find((c) => c.key === 'pts')!;
    render(<LeagueLeadersPanel data={DATA} />);
    expect(names('pts')).toHaveLength(Math.min(3, pts.leaders.all.length));
    await userEvent.click(within(card('pts')).getByRole('button', { name: /Show top 10/ }));
    expect(names('pts')).toHaveLength(Math.min(10, pts.leaders.all.length));
    expect(names('pts')[0]).toContain(pts.leaders.all[0].player);
    await userEvent.click(within(card('pts')).getByRole('button', { name: 'Show top 3' }));
    expect(names('pts')).toHaveLength(3);
  });

  it('position filter switches every card to that position list', async () => {
    render(<LeagueLeadersPanel data={DATA} />);
    await userEvent.click(screen.getByTestId('leader-filter-C'));
    expect(screen.getByTestId('leader-filter-C')).toHaveAttribute('aria-pressed', 'true');
    const reb = DATA.cards.find((c) => c.key === 'reb')!;
    expect(names('reb')[0]).toContain(reb.leaders.C[0].player);
    const blk = DATA.cards.find((c) => c.key === 'blk')!;
    expect(names('blk')[0]).toContain(blk.leaders.C[0].player);
  });

  it('every card shows a through date; noise-note cards carry the note', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    for (const c of DATA.cards) {
      expect(within(card(c.key)).getByTestId('leader-through')).toHaveTextContent(
        c.through_date ? `Through ${c.through_date}` : 'Through date unavailable',
      );
      expect(within(card(c.key)).queryByTestId('leader-noise-note') !== null).toBe(c.noise_note);
    }
  });

  it('an empty card shows "Not enough games yet" and its reason', () => {
    const empty = { ...DATA.cards[0], key: 'empty_test', status: 'not_enough_games' as const,
      null_reason: 'No player has reached the scaled minimum yet.', leaders: { all: [], G: [], F: [], C: [] },
      qualified_count: { all: 0, G: 0, F: 0, C: 0 } };
    render(<LeagueLeadersPanel data={{ ...DATA, cards: [empty] }} />);
    expect(within(card('empty_test')).getByTestId('leader-empty')).toHaveTextContent('Not enough games yet');
    expect(within(card('empty_test')).getByTestId('leader-empty')).toHaveTextContent('scaled minimum');
  });

  it('methods note states the scaling and traded-player rule and study commit', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    const methods = screen.getByTestId('leader-methods');
    expect(methods).toHaveTextContent('team games played / 44');
    expect(methods).toHaveTextContent('traded player');
    expect(methods).toHaveTextContent(DATA.methods.study_source_commit.slice(0, 12));
  });

  it('formats values by card format', () => {
    expect(formatLeaderValue(0.4123, 'pct')).toBe('41.2%');
    expect(formatLeaderValue(27.31, 'rate')).toBe('27.3%');
    expect(formatLeaderValue(1.234, 'rapm')).toBe('+1.23');
    expect(formatLeaderValue(31.06, 'per_game')).toBe('31.1');
  });

  it('missing file renders an unavailable note', () => {
    render(<LeagueLeadersPanel data={null} />);
    expect(screen.getByTestId('league-leaders')).toHaveTextContent('unavailable');
  });
});
