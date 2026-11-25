/**
 * League leaders panel (NFL_analytics#230), against the real player_leaders.json
 * plus hand-made empty cards: grouped cards, top 3 expanding to top 10, a
 * through date per card, noise notes, "Not enough games yet", and no link to a
 * methodology page.
 */
import React from 'react';
import { describe, expect, it } from 'vitest';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { LeagueLeadersPanel, formatLeaderValue } from '../../components/LeagueLeadersPanel';
import type { LeaderCard, PlayerLeadersPayload } from '../../lib/playerLeadersTypes';
import { loadRaw } from '../helpers/datasets';

const DATA = loadRaw('player_leaders.json') as PlayerLeadersPayload;
const card = (key: string) => screen.getByTestId(`leader-card-${key}`);
const rows = (key: string) => within(card(key)).queryAllByTestId('leader-row').map((li) => li.textContent ?? '');
const big = DATA.cards.find((c) => c.leaders.length === 10) as LeaderCard;

describe('LeagueLeadersPanel', () => {
  it('renders the five groups and one card per stat', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    for (const g of DATA.groups) expect(screen.getByTestId(`leader-group-${g.key}`)).toBeInTheDocument();
    for (const c of DATA.cards) expect(card(c.key)).toBeInTheDocument();
  });

  it('shows the top 3 and expands to the top 10', async () => {
    render(<LeagueLeadersPanel data={DATA} />);
    expect(rows(big.key)).toHaveLength(3);
    await userEvent.click(within(card(big.key)).getByRole('button', { name: 'Show top 10' }));
    expect(rows(big.key)).toHaveLength(10);
    expect(rows(big.key)[0]).toContain(big.leaders[0].player);
    await userEvent.click(within(card(big.key)).getByRole('button', { name: 'Show top 3' }));
    expect(rows(big.key)).toHaveLength(3);
  });

  it('every card shows its through date; noise-note cards carry the note', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    for (const c of DATA.cards) {
      expect(within(card(c.key)).getByTestId('leader-through')).toHaveTextContent(
        c.through_date ? `Through ${c.through_date}` : 'No through date',
      );
      expect(within(card(c.key)).queryByTestId('leader-noise-note') !== null).toBe(c.noise_note);
    }
  });

  it('marks the lowest-leads cards', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    for (const k of ['sack_rate', 'int_rate']) expect(card(k)).toHaveTextContent('(lowest leads)');
    expect(card('pass_epa')).not.toHaveTextContent('(lowest leads)');
  });

  it('an empty card shows "Not enough games yet" and its reason', () => {
    const empty: LeaderCard = {
      ...DATA.cards[0], key: 'empty_test', status: 'not_enough_games', status_text: 'Not enough games yet',
      null_reason: 'No player has reached the scaled minimum yet.', leaders: [], qualified_count: 0,
    };
    render(<LeagueLeadersPanel data={{ ...DATA, cards: [empty] }} />);
    const el = within(card('empty_test')).getByTestId('leader-empty');
    expect(el).toHaveTextContent('Not enough games yet');
    expect(el).toHaveTextContent('scaled minimum');
    expect(within(card('empty_test')).queryByRole('button')).toBeNull();
  });

  it('an unavailable PFR card says so with the reason and no through date', () => {
    const base = DATA.cards.find((c) => c.key === 'pressures') as LeaderCard;
    const off: LeaderCard = {
      ...base, status: 'unavailable', status_text: 'Data not available',
      null_reason: 'nflreadr::load_pfr_advstats() could not be fetched for 2026: HTTP 404',
      through_date: null, through_date_null_reason: 'fetch failed', leaders: [], qualified_count: 0,
    };
    render(<LeagueLeadersPanel data={{ ...DATA, cards: [off] }} />);
    expect(within(card('pressures')).getByTestId('leader-empty')).toHaveTextContent('Data not available');
    expect(within(card('pressures')).getByTestId('leader-empty')).toHaveTextContent('could not be fetched');
    expect(within(card('pressures')).getByTestId('leader-through')).toHaveTextContent('No through date');
  });

  it('methods note states the scaling, traded-player and total EPA rules, with no link anywhere', () => {
    render(<LeagueLeadersPanel data={DATA} />);
    const methods = screen.getByTestId('leader-methods');
    expect(methods).toHaveTextContent('team games played / 17');
    expect(methods).toHaveTextContent('traded player');
    expect(methods).toHaveTextContent('Total EPA is the impact measure');
    expect(screen.getByTestId('league-leaders').querySelectorAll('a')).toHaveLength(0);
    expect(screen.getByTestId('league-leaders')).not.toHaveTextContent(/methodology/i);
  });

  it('formats values by card format', () => {
    expect(formatLeaderValue(0.4123, 'pct')).toBe('41.2%');
    expect(formatLeaderValue(9.674, 'cpoe')).toBe('+9.7');
    expect(formatLeaderValue(0.3551, 'epa_play')).toBe('+0.36');
    expect(formatLeaderValue(114.438, 'epa_total')).toBe('+114.4');
    expect(formatLeaderValue(11.5, 'count')).toBe('11.5');
    expect(formatLeaderValue(29, 'count')).toBe('29');
    expect(formatLeaderValue(309.46, 'per_game')).toBe('309.5');
  });

  it('missing file renders an unavailable note', () => {
    render(<LeagueLeadersPanel data={null} />);
    expect(screen.getByTestId('league-leaders')).toHaveTextContent('unavailable');
  });
});
