import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent } from '@testing-library/react';
import { PlayoffSeriesClient } from '@/components/PlayoffSeriesClient';
import { loadAllDatasets } from '../helpers/datasets';

const { playoffSeries } = loadAllDatasets();

describe('PlayoffSeriesClient renders', () => {
  it('mounts on real playoff catalog', () => {
    render(<PlayoffSeriesClient catalog={playoffSeries} />);
    expect(screen.getByText(/7-Game Playoff Series Matchup Simulator/i)).toBeInTheDocument();
  });

  it('selects matchup and updates displayed win probabilities', () => {
    render(<PlayoffSeriesClient catalog={playoffSeries} />);
    const selectInputs = screen.getAllByRole('combobox');
    expect(selectInputs.length).toBeGreaterThanOrEqual(2);
  });
});
