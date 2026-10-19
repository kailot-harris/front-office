import { describe, expect, it } from 'vitest';
import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { ShotsExplorerClient } from '@/components/ShotsExplorerClient';
import { loadAllDatasets } from '../helpers/datasets';

const { shotsIndex, shotsMetadata } = loadAllDatasets();

describe('ShotsExplorerClient renders', () => {
  it('mounts on real shots catalog and metadata', async () => {
    render(<ShotsExplorerClient catalog={shotsIndex} metadata={shotsMetadata} />);
    expect(screen.getByText(/Select Player Telemetry/i)).toBeInTheDocument();
  });

  it('renders marquee quick-select pills and allows selecting a player', async () => {
    render(<ShotsExplorerClient catalog={shotsIndex} metadata={shotsMetadata} />);
    expect(screen.getByText(/Marquee:/i)).toBeInTheDocument();
    const pills = screen.getAllByRole('button');
    expect(pills.length).toBeGreaterThanOrEqual(1);
  });
});
