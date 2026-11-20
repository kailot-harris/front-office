import { describe, expect, it } from 'vitest';
import { render, screen } from '@testing-library/react';
import React from 'react';
import { FinalsSeriesBacktest } from '../../components/FinalsSeriesBacktest';
import type { FinalsSeriesBacktestSet } from '../../lib/playoffTypes';

function makeInfoSet(
  label: string,
  cutoffDate: string,
  gamesPlayed: number,
  stateHigh: number,
  stateLow: number,
  pHighSeries: number
) {
  return {
    label,
    cutoffDate,
    gamesPlayed,
    stateHigh,
    stateLow,
    nGamesHigh: 50 + gamesPlayed,
    nGamesLow: 49 + gamesPlayed,
    netRawHigh: 7.06,
    netRawLow: 7.14,
    netAdjHigh: 8.63,
    netAdjLow: 8.76,
    pHighSeries,
    pLowSeries: 1 - pHighSeries,
    expectedLength: 6.1,
    lengthDistribution: [
      { length: 6, probability: 0.48 },
      { length: 7, probability: 0.52 },
    ],
    pHighSeriesFromZero: 0.51,
    pHighSeriesRegularSeasonOnly: 0.53,
  };
}

function makeBacktestFixture(overrides: Partial<FinalsSeriesBacktestSet> = {}): FinalsSeriesBacktestSet {
  return {
    generated_at: '2026-11-19T12:00:00Z',
    season: 2026,
    generatedAt: '2026-11-19 12:00:00',
    sourceNote: 'Walk-forward series forecasts, replayed from the games available at each point.',
    provenance:
      'RECONSTRUCTION, not an archived forecast. Computed 2026-11-19. Each row sees only games strictly before its cutoff date.',
    matchup: {
      teamHigh: 'Golden State Valkyries',
      teamHighAbbr: 'GS',
      teamLow: 'Atlanta Dream',
      teamLowAbbr: 'ATL',
    },
    games: [
      { game: 1, gameDate: '2026-10-17', scoreHigh: 68, scoreLow: 64, highWon: true },
      { game: 2, gameDate: '2026-10-19', scoreHigh: 65, scoreLow: 79, highWon: false },
      { game: 3, gameDate: '2026-10-21', scoreHigh: 71, scoreLow: 97, highWon: false },
      { game: 4, gameDate: '2026-10-24', scoreHigh: 67, scoreLow: 62, highWon: true },
      { game: 5, gameDate: '2026-10-26', scoreHigh: 64, scoreLow: 55, highWon: true },
      { game: 6, gameDate: '2026-10-29', scoreHigh: 69, scoreLow: 80, highWon: false },
      { game: 7, gameDate: '2026-10-31', scoreHigh: 68, scoreLow: 63, highWon: true },
    ],
    infoSets: [
      makeInfoSet('pre-series', '2026-10-17', 0, 0, 0, 0.513),
      makeInfoSet('after G1', '2026-10-19', 1, 1, 0, 0.659),
      makeInfoSet('after G2', '2026-10-21', 2, 1, 1, 0.447),
      makeInfoSet('after G3', '2026-10-24', 3, 1, 2, 0.25),
      makeInfoSet('after G4', '2026-10-26', 4, 2, 2, 0.48),
      makeInfoSet('after G5', '2026-10-29', 5, 3, 2, 0.72),
      makeInfoSet('after G6', '2026-10-31', 6, 3, 3, 0.54),
    ],
    ...overrides,
  };
}

describe('FinalsSeriesBacktest — series outcome, matchup, and covered dates', () => {
  it('renders the matchup, 4-3 winner outcome, and full date span for a 7-game Finals payload', () => {
    render(<FinalsSeriesBacktest data={makeBacktestFixture()} />);

    expect(screen.getByTestId('finals-backtest-matchup').textContent).toContain(
      'Golden State Valkyries'
    );
    expect(screen.getByTestId('finals-backtest-matchup').textContent).toContain('Atlanta Dream');
    expect(screen.getByTestId('finals-backtest-record').textContent).toContain('GS 4–3 ATL');
    expect(screen.getByTestId('finals-backtest-outcome').textContent).toBe(
      'Golden State Valkyries won 4–3'
    );
    expect(screen.getByTestId('finals-backtest-games-count').textContent).toBe('7 covered games');
    expect(screen.getByTestId('finals-backtest-dates').textContent).toContain(
      '2026-10-17 to 2026-10-31'
    );
  });

  it('reports an in-progress tied series accurately without prematurely crowning a winner', () => {
    const partial = makeBacktestFixture({
      games: [
        { game: 1, gameDate: '2026-10-17', scoreHigh: 68, scoreLow: 64, highWon: true },
        { game: 2, gameDate: '2026-10-19', scoreHigh: 65, scoreLow: 79, highWon: false },
        { game: 3, gameDate: '2026-10-21', scoreHigh: 71, scoreLow: 97, highWon: false },
        { game: 4, gameDate: '2026-10-24', scoreHigh: 67, scoreLow: 62, highWon: true },
      ],
      infoSets: [
        makeInfoSet('pre-series', '2026-10-17', 0, 0, 0, 0.513),
        makeInfoSet('after G1', '2026-10-19', 1, 1, 0, 0.659),
        makeInfoSet('after G2', '2026-10-21', 2, 1, 1, 0.447),
        makeInfoSet('after G3', '2026-10-24', 3, 1, 2, 0.25),
        makeInfoSet('after G4', '2026-10-25', 4, 2, 2, 0.48),
      ],
    });

    render(<FinalsSeriesBacktest data={partial} />);

    expect(screen.getByTestId('finals-backtest-record').textContent).toContain('GS 2–2 ATL');
    expect(screen.getByTestId('finals-backtest-outcome').textContent).toBe('Series tied 2–2');
    expect(screen.getByTestId('finals-backtest-games-count').textContent).toBe('4 covered games');
    expect(screen.getByTestId('finals-backtest-dates').textContent).toContain(
      '2026-10-17 to 2026-10-24'
    );
  });

  it('derives matchup, lower-seed winner, and dates dynamically from non-default props', () => {
    const custom = makeBacktestFixture({
      matchup: {
        teamHigh: 'New York Liberty',
        teamHighAbbr: 'NY',
        teamLow: 'Minnesota Lynx',
        teamLowAbbr: 'MIN',
      },
      games: [
        { game: 1, gameDate: '2027-10-08', scoreHigh: 85, scoreLow: 80, highWon: true },
        { game: 2, gameDate: '2027-10-10', scoreHigh: 72, scoreLow: 78, highWon: false },
        { game: 3, gameDate: '2027-10-13', scoreHigh: 70, scoreLow: 81, highWon: false },
        { game: 4, gameDate: '2027-10-15', scoreHigh: 88, scoreLow: 82, highWon: true },
        { game: 5, gameDate: '2027-10-18', scoreHigh: 69, scoreLow: 74, highWon: false },
        { game: 6, gameDate: '2027-10-21', scoreHigh: 75, scoreLow: 79, highWon: false },
      ],
      infoSets: [
        makeInfoSet('pre-series', '2027-10-08', 0, 0, 0, 0.55),
        makeInfoSet('after G1', '2027-10-10', 1, 1, 0, 0.68),
      ],
    });

    render(<FinalsSeriesBacktest data={custom} />);

    expect(screen.getByTestId('finals-backtest-matchup').textContent).toContain('New York Liberty');
    expect(screen.getByTestId('finals-backtest-matchup').textContent).toContain('Minnesota Lynx');
    expect(screen.getByTestId('finals-backtest-record').textContent).toContain('NY 2–4 MIN');
    expect(screen.getByTestId('finals-backtest-outcome').textContent).toBe('Minnesota Lynx won 4–2');
    expect(screen.getByTestId('finals-backtest-dates').textContent).toContain(
      '2027-10-08 to 2027-10-21'
    );
  });

  it('renders the empty state sourceNote when matchup or infoSets are absent', () => {
    render(
      <FinalsSeriesBacktest
        data={makeBacktestFixture({
          matchup: null,
          games: [],
          infoSets: [],
          sourceNote: 'The Finals series backtest has not been generated yet.',
        })}
      />
    );

    expect(
      screen.getByText('The Finals series backtest has not been generated yet.')
    ).toBeDefined();
    expect(screen.queryByTestId('finals-backtest-summary')).toBeNull();
  });
});
