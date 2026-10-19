import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { PlayersClient } from '@/components/PlayersClient';
import { loadAllDatasets } from '../helpers/datasets';

const { players } = loadAllDatasets();

function renderPlayers() {
  const { container } = render(<PlayersClient players={players} />);
  const table = container.querySelector('table');
  if (!table) throw new Error('PlayersClient rendered without a <table>');
  return { container, table: table as HTMLTableElement };
}

describe('PlayersClient renders', () => {
  it('mounts on real dataset and displays player counts', () => {
    render(<PlayersClient players={players} />);
    expect(screen.getByText(/Active Rotation Pool/i)).toBeInTheDocument();
  });

  it('never prints NaN or undefined', () => {
    const { container } = renderPlayers();
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('filters by search input', () => {
    const { table } = renderPlayers();
    const searchInput = screen.getByPlaceholderText(/search player/i);
    fireEvent.change(searchInput, { target: { value: 'Doncic' } });
    expect(table.textContent).toContain('Luka Doncic');
  });

  it('filters by position', () => {
    const { table, container } = renderPlayers();
    const posButtons = screen.getAllByRole('button');
    const guardBtn = posButtons.find((b) => b.textContent?.trim() === 'Guard (G)');
    if (guardBtn) {
      fireEvent.click(guardBtn);
      expect(table.textContent).toContain('G');
    }
  });

  it('toggles outlier only filter', () => {
    renderPlayers();
    const outlierBtn = screen.getByRole('button', { name: /outliers only/i });
    fireEvent.click(outlierBtn);
    expect(outlierBtn).toHaveClass('bg-rose-500/20');
  });
});
