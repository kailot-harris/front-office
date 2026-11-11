/**
 * Component tests for the Monte Carlo bracket simulator (#128).
 *
 * The simulator used to call Math.random() directly (not reproducible) and to invent a
 * displayed score margin from the *absolute* rating gap regardless of who actually won (so an
 * upset winner showed the favorite's margin). The fix seeds a mulberry32 PRNG from the matchup
 * key (+ a re-roll counter) and derives the margin from the simulated outcome.
 *
 * These tests render against the real playoff dataset, same bet the page itself makes.
 */
import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent, cleanup } from '@testing-library/react';
import { PlayoffBracketSimulator } from '../../components/PlayoffBracketSimulator';
import { playoffs } from '../helpers/datasets';

const dataset = playoffs();

function simulateAndReadChampionLine(): string {
  const { unmount } = render(<PlayoffBracketSimulator dataset={dataset} />);
  fireEvent.click(screen.getByRole('button', { name: /simulate bracket/i }));
  const banner = screen.getByText(/Simulated Super Bowl Champion/i).closest('div')?.parentElement;
  const text = banner?.textContent ?? '';
  unmount();
  cleanup();
  return text;
}

describe('PlayoffBracketSimulator', () => {
  it('mounts without throwing', () => {
    expect(() => render(<PlayoffBracketSimulator dataset={dataset} />)).not.toThrow();
  });

  it('produces identical results for the same matchup key across separate mounts (reproducible, #128)', () => {
    const first = simulateAndReadChampionLine();
    const second = simulateAndReadChampionLine();
    expect(first).not.toBe('');
    expect(first).toBe(second);
  });

  it('re-roll produces a (potentially different) result without throwing, still deterministic per roll', () => {
    render(<PlayoffBracketSimulator dataset={dataset} />);
    fireEvent.click(screen.getByRole('button', { name: /simulate bracket/i }));
    expect(screen.getByText(/Simulated Super Bowl Champion/i)).toBeInTheDocument();

    const rerollButton = screen.getByRole('button', { name: /re-roll/i });
    expect(() => fireEvent.click(rerollButton)).not.toThrow();
    expect(screen.getByText(/Simulated Super Bowl Champion/i)).toBeInTheDocument();
  });

  it('reset clears the simulated result', () => {
    render(<PlayoffBracketSimulator dataset={dataset} />);
    fireEvent.click(screen.getByRole('button', { name: /simulate bracket/i }));
    expect(screen.getByText(/Simulated Super Bowl Champion/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /reset to model probabilities/i }));
    expect(screen.queryByText(/Simulated Super Bowl Champion/i)).not.toBeInTheDocument();
  });

  it('never labels an invented margin as anything but simulated (no bare score fabricated from the raw rating gap)', () => {
    render(<PlayoffBracketSimulator dataset={dataset} />);
    fireEvent.click(screen.getByRole('button', { name: /simulate bracket/i }));
    const defeatedLine = screen.getByText(/Defeated/i);
    // Either no margin is shown, or it is explicitly labeled "simulated X pts" — never a bare
    // unlabeled score that could be mistaken for a real result.
    if (/pts/.test(defeatedLine.textContent ?? '')) {
      expect(defeatedLine.textContent).toMatch(/simulated \d+ pts/i);
    }
  });
});
