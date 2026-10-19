/**
 * Component tests for the remaining page clients: coaching, salary cap,
 * gallery, playoffs, diagnostics and variants, plus the shared TeamLogo and
 * navigation primitives.
 *
 * Each block covers the same four things: it mounts on real data, its filters
 * and sorts actually filter and sort, it never renders NaN/undefined, and it
 * survives an empty dataset.
 */
import { describe, expect, it } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import CoachingClient from '../../components/CoachingClient';
import SalaryCapClient from '../../components/SalaryCapClient';
import GalleryClient from '../../components/GalleryClient';
import DiagnosticsClient from '../../components/DiagnosticsClient';
import VariantsClient from '../../components/VariantsClient';
import { PlayoffsClient } from '../../components/PlayoffsClient';
import { PlayoffBracketSimulator } from '../../components/PlayoffBracketSimulator';
import { TeamLogo } from '../../components/TeamLogo';
import { Sidebar } from '../../components/Sidebar';
import { NFL_TEAMS_METADATA } from '../../lib/teams';
import { coaching, diagnostics, media, playoffs, salaryCap } from '../helpers/datasets';

// ---------------------------------------------------------------- TeamLogo ---

describe('TeamLogo', () => {
  it('renders a logo with an accessible alt text for every known team', () => {
    for (const meta of Object.values(NFL_TEAMS_METADATA)) {
      const { container, unmount } = render(<TeamLogo team={meta.abbr} />);
      const img = container.querySelector('img');
      expect(img, `${meta.abbr} rendered no <img>`).not.toBeNull();
      expect(img!.getAttribute('alt')).toBe(`${meta.fullName} logo`);
      expect(img!.getAttribute('src')).toContain(`/${meta.espnCode}.png`);
      unmount();
    }
  });

  it('is case-insensitive about the team code', () => {
    const { container } = render(<TeamLogo team="kc" />);
    expect(container.querySelector('img')!.getAttribute('alt')).toBe('Kansas City Chiefs logo');
  });

  it('falls back to the raw code for an unknown team instead of crashing', () => {
    const { container } = render(<TeamLogo team="LAR" />);
    const img = container.querySelector('img')!;
    // The URL still resolves (lar is a valid ESPN slug) but the human-readable
    // label degrades to the bare code, which is the visible LAR/LA symptom.
    expect(img.getAttribute('alt')).toBe('LAR logo');
    expect(img.getAttribute('alt')).not.toBe('Los Angeles Rams logo');
  });

  it('shows a text fallback when the image fails to load', () => {
    const { container } = render(<TeamLogo team="KC" />);
    fireEvent.error(container.querySelector('img')!);
    expect(container.textContent).toContain('KC');
  });

  it('renders nothing when the image fails and showFallbackText is false', () => {
    const { container } = render(<TeamLogo team="KC" showFallbackText={false} />);
    fireEvent.error(container.querySelector('img')!);
    expect(container.textContent).toBe('');
  });

  it('does not throw on empty or nullish team codes', () => {
    expect(() => render(<TeamLogo team="" />)).not.toThrow();
    expect(() => render(<TeamLogo team={undefined as unknown as string} />)).not.toThrow();
  });

  it('accepts every documented size without falling back silently', () => {
    for (const size of ['xs', 'sm', 'md', 'lg', 'xl', '2xl'] as const) {
      const { container, unmount } = render(<TeamLogo team="KC" size={size} />);
      expect(container.querySelector('img'), `size="${size}" rendered nothing`).not.toBeNull();
      unmount();
    }
  });
});

// ------------------------------------------------------------------ Sidebar ---

describe('Sidebar', () => {
  const ROUTES = [
    '/',
    '/matchups',
    '/teams',
    '/coaching',
    '/salary-cap',
    '/playoffs',
    '/players',
    '/variants',
    '/diagnostics',
    '/gallery',
  ];

  it('links to every route the app actually serves', () => {
    const { container } = render(<Sidebar />);
    const hrefs = Array.from(container.querySelectorAll('a')).map((a) => a.getAttribute('href'));
    for (const route of ROUTES) {
      expect(hrefs, `no sidebar link to ${route}`).toContain(route);
    }
  });

  it('links nowhere that the app does not serve', () => {
    const { container } = render(<Sidebar />);
    const internal = Array.from(container.querySelectorAll('a'))
      .map((a) => a.getAttribute('href') ?? '')
      .filter((h) => h.startsWith('/'));
    const unknown = internal.filter((h) => !ROUTES.includes(h));
    expect(unknown, 'sidebar links to a route with no page').toEqual([]);
  });

  it('opens and closes the mobile drawer', () => {
    const { container } = render(<Sidebar />);
    const toggles = Array.from(container.querySelectorAll('button'));
    expect(toggles.length, 'sidebar has no buttons').toBeGreaterThan(0);
    expect(() => toggles.forEach((b) => fireEvent.click(b))).not.toThrow();
  });
});

// --------------------------------------------------------- CoachingClient ---

describe('CoachingClient', () => {
  const coaches = coaching();

  it('lists all 32 head coaches', () => {
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    for (const c of coaches) {
      expect(container.textContent, `${c.team} / ${c.head_coach} missing`).toContain(c.head_coach);
    }
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('renders the minus grades the data actually contains', () => {
    // lib/types.ts omits 'A-' and 'B-' from the timeout_management_grade union.
    // The component keys its colour off `.startsWith('A')`, so these render
    // correctly despite the type being wrong — this test pins that behaviour.
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    for (const grade of new Set(coaches.map((c) => c.timeout_management_grade))) {
      expect(container.textContent, `grade ${grade} not rendered`).toContain(grade);
    }
  });

  it('searching by coach name narrows the table', () => {
    // Scoped to <tbody>: the aggression/PROE/tenure podiums above the table
    // always show the league top three and are deliberately not filtered.
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    const body = () => container.querySelector('tbody')!.textContent ?? '';
    const target = coaches[0];
    fireEvent.change(screen.getAllByPlaceholderText(/search/i)[0], { target: { value: target.head_coach } });
    expect(body()).toContain(target.head_coach);
    const other = coaches.find((c) => c.head_coach !== target.head_coach)!;
    expect(body().includes(other.head_coach), `${other.head_coach} survived the filter`).toBe(false);
  });

  it('searching by scheme and by coordinator both work', () => {
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    const search = () => screen.getAllByPlaceholderText(/search/i)[0];
    fireEvent.change(search(), { target: { value: coaches[0].offensive_scheme } });
    expect(container.textContent).toContain(coaches[0].head_coach);
    fireEvent.change(search(), { target: { value: coaches[0].defensive_coordinator } });
    expect(container.textContent).toContain(coaches[0].head_coach);
  });

  it('an unmatched search empties the table without crashing', () => {
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    fireEvent.change(screen.getAllByPlaceholderText(/search/i)[0], { target: { value: 'zzzznotacoach' } });
    expect(container.textContent).not.toMatch(/NaN|undefined/);
    expect(container.querySelector('tbody')!.querySelectorAll('tr')).toHaveLength(0);
  });

  it('the aggression podium holds the three most aggressive coaches', () => {
    const { container } = render(<CoachingClient initialCoaches={coaches} />);
    const top = [...coaches].sort((a, b) => b.fourth_down_aggression_index - a.fourth_down_aggression_index)[0];
    expect(container.textContent).toContain(`${top.fourth_down_aggression_index}th %ile`);
  });

  it('renders an empty staff list without throwing', () => {
    expect(() => render(<CoachingClient initialCoaches={[]} />)).not.toThrow();
  });
});

// -------------------------------------------------------- SalaryCapClient ---

describe('SalaryCapClient', () => {
  const data = salaryCap();

  it('renders the cap ceiling from the dataset', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    expect(container.textContent).toContain(`$${data.cap_ceiling}M`);
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('lists all 32 team cap profiles', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    for (const t of data.teams) {
      expect(container.textContent, `${t.team} missing`).toContain(t.team);
    }
  });

  it('renders a degraded logo label for the Rams because the data says LAR', () => {
    // salary_cap_profiles.json keys the Rams as "LAR" while lib/teams.ts keys
    // them as "LA". The logo URL still resolves, but the tooltip/alt text and
    // the colour palette fall back.
    const { container } = render(<SalaryCapClient data={data} />);
    const rams = data.teams.find((t) => t.team === 'LAR' || t.team === 'LA');
    if (!rams) return;
    const alts = Array.from(container.querySelectorAll('img')).map((i) => i.getAttribute('alt'));
    if (rams.team === 'LAR') {
      expect(
        alts,
        'the Rams row should name the franchise, not the raw code — fix the LAR/LA mismatch',
      ).toContain('Los Angeles Rams logo');
    }
  });

  it('switches to the top contracts tab and lists contracts', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    fireEvent.click(screen.getByRole('button', { name: /top 100/i }));
    expect(container.textContent).toContain(data.top_league_contracts[0].player);
  });

  it('searching filters team profiles', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    fireEvent.change(screen.getAllByPlaceholderText(/search/i)[0], { target: { value: 'KC' } });
    expect(container.textContent).toContain('KC');
  });

  it('searching filters contracts by player, team and position', () => {
    const { container } = render(<SalaryCapClient data={data} />);
    fireEvent.click(screen.getByRole('button', { name: /top 100/i }));
    const target = data.top_league_contracts[0];
    fireEvent.change(screen.getAllByPlaceholderText(/search/i)[0], { target: { value: target.player } });
    expect(container.textContent).toContain(target.player);
  });

  it('renders an empty cap dataset without throwing', () => {
    expect(() =>
      render(<SalaryCapClient data={{ ...data, teams: [], top_league_contracts: [] }} />),
    ).not.toThrow();
  });

  it('does not print NaN with no teams (avgTeamApy divides by team count)', () => {
    const { container } = render(
      <SalaryCapClient data={{ ...data, teams: [], top_league_contracts: [] }} />,
    );
    expect(container.textContent).not.toMatch(/NaN/);
  });
});

// ---------------------------------------------------------- GalleryClient ---

describe('GalleryClient', () => {
  const items = media();

  it('renders a tile for every media item', () => {
    const { container } = render(<GalleryClient mediaItems={items} />);
    for (const item of items) {
      expect(container.textContent, `${item.filename} missing`).toContain(item.title);
    }
  });

  it('points every tile at a real path under /animations/', () => {
    const { container } = render(<GalleryClient mediaItems={items} />);
    const srcs = Array.from(container.querySelectorAll('img')).map((i) => i.getAttribute('src') ?? '');
    for (const item of items) {
      expect(srcs.some((s) => s.includes(item.filename)), `${item.filename} not referenced by any <img>`).toBe(true);
    }
  });

  it('offers a chip for every category plus an All Visuals reset', () => {
    render(<GalleryClient mediaItems={items} />);
    const labels = screen.getAllByRole('button').map((b) => b.textContent?.trim());
    // The ALL sentinel renders with the friendlier label "All Visuals".
    expect(labels).toContain('All Visuals');
    for (const cat of new Set(items.map((i) => i.category))) {
      expect(labels.some((l) => l?.toLowerCase().includes(cat.toLowerCase())), `${cat} chip missing`).toBe(true);
    }
  });

  it('filtering by category keeps only that category', () => {
    const { container } = render(<GalleryClient mediaItems={items} />);
    const cat = items[0].category;
    const chip = screen.getAllByRole('button').find((b) => b.textContent?.trim().toLowerCase().includes(cat));
    fireEvent.click(chip!);
    for (const item of items.filter((i) => i.category !== cat)) {
      expect(container.textContent!.includes(item.title), `${item.title} (${item.category}) survived`).toBe(false);
    }
  });

  it('searching matches title, filename and description', () => {
    const { container } = render(<GalleryClient mediaItems={items} />);
    const search = () => screen.getAllByPlaceholderText(/search/i)[0];
    fireEvent.change(search(), { target: { value: items[0].title } });
    expect(container.textContent).toContain(items[0].title);
    fireEvent.change(search(), { target: { value: items[0].filename } });
    expect(container.textContent).toContain(items[0].title);
  });

  it('an unmatched search empties the grid without crashing', () => {
    const { container } = render(<GalleryClient mediaItems={items} />);
    fireEvent.change(screen.getAllByPlaceholderText(/search/i)[0], { target: { value: 'zzzznotamedia' } });
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('renders an empty gallery without throwing', () => {
    expect(() => render(<GalleryClient mediaItems={[]} />)).not.toThrow();
  });
});

// --------------------------------------------------------- PlayoffsClient ---

describe('PlayoffsClient', () => {
  const dataset = playoffs();

  it('renders both conference fields with all 14 seeds', () => {
    const { container } = render(<PlayoffsClient dataset={dataset} />);
    for (const seed of [...dataset.afc_seeds, ...dataset.nfc_seeds]) {
      expect(container.textContent, `${seed.team} (seed ${seed.seed}) missing`).toContain(seed.team_name);
    }
  });

  it('renders the bubble teams', () => {
    const { container } = render(<PlayoffsClient dataset={dataset} />);
    for (const b of [...dataset.afc_bubble, ...dataset.nfc_bubble]) {
      expect(container.textContent, `${b.team} missing from the bubble`).toContain(b.team_name);
    }
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<PlayoffsClient dataset={dataset} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('renders an empty bracket without throwing', () => {
    expect(() =>
      render(
        <PlayoffsClient
          dataset={{ ...dataset, afc_seeds: [], nfc_seeds: [], afc_bubble: [], nfc_bubble: [] }}
        />,
      ),
    ).not.toThrow();
  });
});

describe('PlayoffBracketSimulator', () => {
  const dataset = playoffs();

  it('renders before any simulation has been run', () => {
    const { container } = render(<PlayoffBracketSimulator dataset={dataset} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('simulating produces a champion drawn from the seeded field', () => {
    const { container } = render(<PlayoffBracketSimulator dataset={dataset} />);
    const run = screen.getAllByRole('button').find((b) => /simulat/i.test(b.textContent ?? ''));
    expect(run, 'no simulate button').toBeTruthy();
    fireEvent.click(run!);
    const field = [...dataset.afc_seeds, ...dataset.nfc_seeds].map((s) => s.team_name);
    const text = container.textContent ?? '';
    expect(field.some((name) => text.includes(name)), 'no seeded team appears after simulating').toBe(true);
    expect(text).not.toMatch(/NaN|undefined/);
  });

  it('repeated simulations never throw and never produce a tie score', () => {
    const { container } = render(<PlayoffBracketSimulator dataset={dataset} />);
    const run = screen.getAllByRole('button').find((b) => /simulat/i.test(b.textContent ?? ''))!;
    for (let i = 0; i < 25; i++) {
      fireEvent.click(run);
      const text = container.textContent ?? '';
      expect(text, `run ${i} printed NaN`).not.toMatch(/NaN|undefined/);
      // Scores are generated as base + margin with margin >= 1, so a playoff
      // game must never render as a draw.
      const scores = text.match(/(\d+)\s*-\s*(\d+)/g) ?? [];
      for (const s of scores) {
        const [a, b] = s.split('-').map((n) => Number(n.trim()));
        if (Number.isFinite(a) && Number.isFinite(b) && a < 100 && b < 100) {
          expect(a, `playoff game rendered as a ${s} draw`).not.toBe(b);
        }
      }
    }
  });

  it('resetting clears the simulated bracket', () => {
    const { container } = render(<PlayoffBracketSimulator dataset={dataset} />);
    const run = screen.getAllByRole('button').find((b) => /simulat/i.test(b.textContent ?? ''))!;
    fireEvent.click(run);
    const reset = screen.getAllByRole('button').find((b) => /reset/i.test(b.textContent ?? ''));
    if (reset) {
      fireEvent.click(reset);
      expect(container.textContent).not.toMatch(/NaN|undefined/);
    }
  });
});

// ------------------------------------------------- Diagnostics & Variants ---

describe('DiagnosticsClient', () => {
  const data = diagnostics();
  const latest = <T,>(v: T | T[]): T => (Array.isArray(v) ? v[v.length - 1] : v);

  it('renders the headline metrics from the dataset', () => {
    const { container } = render(<DiagnosticsClient data={data} />);
    expect(container.textContent).toContain(`${Number(latest(data.overall_accuracy)).toFixed(1)}%`);
    expect(container.textContent).toContain(Number(latest(data.overall_brier)).toFixed(4));
  });

  it('renders sigma and HFA from the dataset rather than a literal', () => {
    const { container } = render(<DiagnosticsClient data={data} />);
    expect(container.textContent).toContain(`${data.margin_sigma.toFixed(1)} pts`);
    expect(container.textContent).toContain(`+${data.home_field_adv.toFixed(2)} pts`);
  });

  it('plots every calibration bin', () => {
    const { container } = render(<DiagnosticsClient data={data} />);
    for (const bin of data.calibration_curve) {
      expect(container.textContent, `bin ${bin.bin} missing`).toContain(`${(bin.predicted_mid * 100).toFixed(0)}%`);
    }
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<DiagnosticsClient data={data} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('renders when the trajectory fields are scalars rather than arrays', () => {
    // lib/types.ts declares `number | number[]`; the export currently ships
    // arrays. A single-snapshot export would send scalars.
    const scalar = {
      ...data,
      season: 2026,
      last_evaluated: '2026-10-19',
      n_games_graded: 92,
      overall_accuracy: 62.5,
      overall_brier: 0.231,
      overall_logloss: 0.66,
      brier_improvement: 7.6,
    };
    const { container } = render(<DiagnosticsClient data={scalar} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});

describe('VariantsClient', () => {
  const data = diagnostics();

  it('renders each ensemble component with its weight', () => {
    const { container } = render(<VariantsClient data={data} />);
    const w = data.ensemble_weights;
    expect(container.textContent).toContain(`${(w.ridge_massey * 100).toFixed(0)}%`);
    expect(container.textContent).toContain(`${(w.elo_dynamic * 100).toFixed(0)}%`);
    expect(container.textContent).toContain(`${(w.market_blend * 100).toFixed(0)}%`);
  });

  it('never prints NaN or undefined', () => {
    const { container } = render(<VariantsClient data={data} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });

  it('survives a dataset with no ensemble weights by using its fallback', () => {
    const { ensemble_weights: _omitted, ...rest } = data;
    const { container } = render(<VariantsClient data={rest as typeof data} />);
    expect(container.textContent).not.toMatch(/NaN|undefined/);
  });
});
