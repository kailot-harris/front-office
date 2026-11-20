/**
 * Accessibility and keyboard interaction tests for /passing and /clutch SVGs (NFL#84).
 */
import React from 'react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import PassingExplorerClient from '../../components/PassingExplorerClient';
import ClutchClient from '../../components/ClutchClient';
import {
  clutch,
  passingIndex,
  passingMetadata,
  readQbPassingFile,
} from '../helpers/datasets';

const escapeRegex = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const originalFetch = global.fetch;

function stubPassingFetch() {
  const fetchMock = vi.fn<typeof fetch>().mockImplementation(async (input) => {
    const url = typeof input === 'string' ? input : input.toString();
    const match = url.match(/\/data\/passing\/([^/?]+)\.json/);
    if (match) {
      const qbId = match[1];
      const payload = readQbPassingFile(qbId);
      return {
        ok: true,
        status: 200,
        json: async () => payload,
      } as Response;
    }
    return {
      ok: false,
      status: 404,
      json: async () => ({ error: 'Not found' }),
    } as Response;
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

describe('PassingExplorerClient SVG & keyboard accessibility (NFL#84)', () => {
  const catalog = passingIndex();
  const metadata = passingMetadata();

  beforeEach(() => {
    stubPassingFetch();
  });

  afterEach(() => {
    vi.stubGlobal('fetch', originalFetch);
  });

  it('gives the throw-map SVG role="img" and a dynamic aria-label naming the selected QB', async () => {
    const firstQb = catalog[0];
    const secondQb = catalog.find((q) => q.player_id !== firstQb.player_id)!;

    render(
      <PassingExplorerClient
        catalog={catalog}
        metadata={metadata}
        initialPlayerId={firstQb.player_id}
      />
    );

    const svg = await screen.findByRole('img', {
      name: new RegExp(`passing throw map for ${escapeRegex(firstQb.player_name)}`, 'i'),
    });
    expect(svg.tagName.toLowerCase()).toBe('svg');
    expect(svg.getAttribute('aria-label')).toContain(firstQb.team);
    expect(svg.getAttribute('aria-label')).toContain(String(firstQb.total_passes));

    // Switch quarterback via the accessible QB selector
    const qbSelect = screen.getByLabelText('Select quarterback');
    fireEvent.change(qbSelect, { target: { value: secondQb.player_id } });

    const updatedSvg = await screen.findByRole('img', {
      name: new RegExp(`passing throw map for ${escapeRegex(secondQb.player_name)}`, 'i'),
    });
    expect(updatedSvg.getAttribute('aria-label')).toContain(secondQb.team);
    expect(updatedSvg.getAttribute('aria-label')).toContain(String(secondQb.total_passes));
  });

  it('supports keyboard zone selection on the throw-map via Enter and Space', async () => {
    const targetQb = catalog[0];
    const user = userEvent.setup();

    render(
      <PassingExplorerClient
        catalog={catalog}
        metadata={metadata}
        initialPlayerId={targetQb.player_id}
      />
    );

    const throwMap = await screen.findByRole('img', {
      name: new RegExp(`passing throw map for ${escapeRegex(targetQb.player_name)}`, 'i'),
    });

    const deepLeftZone = within(throwMap).getByRole('button', {
      name: /^Filter by Deep Left zone/i,
    });
    expect(deepLeftZone).toHaveAttribute('tabindex', '0');
    expect(deepLeftZone).toHaveAttribute('aria-pressed', 'false');

    // Focus and activate with Enter via userEvent
    act(() => {
      deepLeftZone.focus();
    });
    expect(deepLeftZone).toHaveFocus();
    await user.keyboard('{Enter}');

    await waitFor(() => {
      expect(deepLeftZone).toHaveAttribute('aria-pressed', 'true');
    });
    expect(screen.getByRole('button', { name: /Clear Filter/i })).toBeInTheDocument();
    expect(throwMap.getAttribute('aria-label')).toContain('filtered to Deep Left');

    // Toggle off with Space
    await user.keyboard(' ');
    await waitFor(() => {
      expect(deepLeftZone).toHaveAttribute('aria-pressed', 'false');
    });
    expect(screen.queryByRole('button', { name: /Clear Filter/i })).not.toBeInTheDocument();

    // Activate a second zone with Space via fireEvent.keyDown
    const shortMiddleZone = within(throwMap).getByRole('button', {
      name: /^Filter by Short Middle zone/i,
    });
    fireEvent.keyDown(shortMiddleZone, { key: ' ' });
    expect(shortMiddleZone).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: /Clear Filter/i })).toBeInTheDocument();
  });

  it('makes the 12 zone performance cards below the map accessible toggle buttons', async () => {
    const targetQb = catalog[0];

    render(
      <PassingExplorerClient
        catalog={catalog}
        metadata={metadata}
        initialPlayerId={targetQb.player_id}
      />
    );

    await screen.findByRole('img', {
      name: new RegExp(`passing throw map for ${escapeRegex(targetQb.player_name)}`, 'i'),
    });

    const deepRightCard = screen.getByRole('button', {
      name: /^Deep Right zone performance card/i,
    });
    expect(deepRightCard).toHaveAttribute('aria-pressed', 'false');
    fireEvent.click(deepRightCard);
    expect(deepRightCard).toHaveAttribute('aria-pressed', 'true');
    expect(screen.getByRole('button', { name: /Clear Filter/i })).toBeInTheDocument();
  });

  it('renders fallback accessible SVG label cleanly when catalog is empty', () => {
    const { container } = render(
      <PassingExplorerClient catalog={[]} metadata={metadata} />
    );
    const svg = screen.getByRole('img', {
      name: /NextGenStats quarterback passing throw map/i,
    });
    expect(svg.tagName.toLowerCase()).toBe('svg');
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('ClutchClient SVG scatter accessibility (NFL#84)', () => {
  const profiles = clutch();
  const qualified = profiles
    .filter((p) => p.provenance === 'REAL_CURRENT_SEASON' && p.clutchEpaDelta !== null)
    .sort((a, b) => (b.clutchEpaDelta ?? -99) - (a.clutchEpaDelta ?? -99));

  it('gives the scatter SVG role="img" and updates aria-label when selected QB changes via table or scatter click', () => {
    const defaultTop = qualified[0];
    const otherQb = qualified[1];

    const { container } = render(<ClutchClient initialProfiles={profiles} />);

    const svg = screen.getByRole('img', {
      name: new RegExp(`Selected QB:.*${escapeRegex(defaultTop.playerName)}`, 'i'),
    });
    expect(svg.tagName.toLowerCase()).toBe('svg');
    expect(svg.getAttribute('aria-label')).toContain(defaultTop.team);

    // Click another QB row in the leaderboard table
    const otherRow = Array.from(container.querySelectorAll('tbody tr')).find((tr) =>
      tr.textContent?.includes(otherQb.playerName)
    )!;
    fireEvent.click(otherRow);

    expect(svg.getAttribute('aria-label')).toContain(`Selected QB: ${otherQb.playerName}`);
    expect(svg.getAttribute('aria-label')).toContain(otherQb.team);

    // Click back to defaultTop's circle in the scatter SVG
    const circles = svg.querySelectorAll('g');
    const topScatterGroup = Array.from(circles).find((_, idx) => {
      // Scatter groups render in scatterQbs order (unsorted initialProfiles filtered to qualified)
      const scatterList = profiles.filter(
        (p) =>
          p.clutchEpa !== null &&
          p.baselineEpa !== null &&
          p.clutchEpaDelta !== null &&
          p.provenance === 'REAL_CURRENT_SEASON'
      );
      return scatterList[idx]?.playerId === defaultTop.playerId;
    })!;
    fireEvent.click(topScatterGroup);
    expect(svg.getAttribute('aria-label')).toContain(`Selected QB: ${defaultTop.playerName}`);
  });

  it('updates aria-label on scatter hover and filter/pool changes without NaN or undefined', () => {
    const scatterList = profiles.filter(
      (p) =>
        p.clutchEpa !== null &&
        p.baselineEpa !== null &&
        p.clutchEpaDelta !== null &&
        p.provenance === 'REAL_CURRENT_SEASON'
    );
    const hoverTarget = scatterList.find((p) => p.playerId !== qualified[0].playerId)!;
    const lowSampleQb = profiles.find((p) => p.provenance !== 'REAL_CURRENT_SEASON');

    const { container } = render(<ClutchClient initialProfiles={profiles} />);
    const svg = screen.getByRole('img', { name: /Clutch EPA vs\. baseline EPA scatter plot/i });

    const targetIdx = scatterList.findIndex((p) => p.playerId === hoverTarget.playerId);
    const targetGroup = svg.querySelectorAll('g')[targetIdx];
    fireEvent.mouseEnter(targetGroup);
    expect(svg.getAttribute('aria-label')).toContain(`Highlighted QB: ${hoverTarget.playerName}`);

    fireEvent.mouseLeave(targetGroup);
    expect(svg.getAttribute('aria-label')).toContain(`Selected QB: ${qualified[0].playerName}`);

    // Filter by team
    fireEvent.change(screen.getByLabelText('Filter leaderboard by team'), {
      target: { value: hoverTarget.team },
    });
    expect(svg.getAttribute('aria-label')).toContain(`table filtered to ${hoverTarget.team}`);

    // Switch to All view and select a low-sample QB if present
    fireEvent.change(screen.getByLabelText('Filter leaderboard by team'), {
      target: { value: 'ALL' },
    });
    fireEvent.click(within(container).getByText(/^All \(/));
    expect(svg.getAttribute('aria-label')).toContain('all QBs view');

    if (lowSampleQb) {
      const lowRow = Array.from(container.querySelectorAll('tbody tr')).find((tr) =>
        tr.textContent?.includes(lowSampleQb.playerName)
      )!;
      fireEvent.click(lowRow);
      expect(svg.getAttribute('aria-label')).toContain(lowSampleQb.playerName);
      expect(svg.getAttribute('aria-label')).toContain('below qualification threshold');
    }

    expect(svg.getAttribute('aria-label')).not.toMatch(/NaN|undefined/);
  });
});
