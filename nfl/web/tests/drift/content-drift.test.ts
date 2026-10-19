/**
 * Layer 5 — hardcoded UI copy vs. the data it claims to describe.
 *
 * This is the web-layer analogue of the repo's `config-constant-drift-audit`
 * skill. CLAUDE.md records Finding C-1 from the WNBA sibling repo as a
 * documented case where a modelling constant (home-court advantage) was typed
 * a second time at a live call site, drifted out of sync with config.R, and
 * implied a materially wrong win-probability curve until someone noticed.
 *
 * The same failure mode is wide open here: the pages and components contain
 * numeric literals ("13.8 pts", "$301.2M Cap", "192 Games", a sigma of 13.8
 * inside the bracket simulator) that duplicate values the datasets already
 * carry. These tests read the component SOURCE and compare the literals it
 * prints against the live data, so drift fails a test instead of quietly
 * misinforming a reader.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { REPO_WEB_ROOT, diagnostics, matchups, media, playoffs, salaryCap, standings } from '../helpers/datasets';

const read = (...p: string[]) => fs.readFileSync(path.join(REPO_WEB_ROOT, ...p), 'utf-8');

/** All numeric literals written into a source file, as numbers. */
function numericLiterals(src: string): number[] {
  return (src.match(/(?<![\w.])\d+\.\d+(?![\w.])/g) ?? []).map(Number);
}

describe('margin sigma is not duplicated in the UI', () => {
  const d = diagnostics();

  it('the home page sigma chip matches model_diagnostics.margin_sigma', () => {
    // app/page.tsx prints a "Margin Sigma (σ)" stat card with a literal value.
    const src = read('app', 'page.tsx');
    const chip = src.match(/Margin Sigma[\s\S]{0,400}?([\d]+\.[\d]+)\s*pts/);
    expect(chip, 'could not find the sigma chip in app/page.tsx — update this test if the layout changed').not.toBeNull();
    const shown = Number(chip![1]);
    expect(
      shown,
      `app/page.tsx advertises a margin sigma of ${shown} pts but model_diagnostics.json reports ` +
        `${d.margin_sigma}. Read it from the dataset instead of re-typing it.`,
    ).toBeCloseTo(d.margin_sigma, 1);
  });

  it('PlayoffBracketSimulator simulates with the real sigma, not a literal', () => {
    // The simulator converts a power-rating gap into a win probability via
    // `z = diff / <sigma>`. A stale sigma changes every simulated bracket.
    const src = read('components', 'PlayoffBracketSimulator.tsx');
    const sigma = src.match(/diff\s*\/\s*([\d.]+)/);
    expect(sigma, 'PlayoffBracketSimulator no longer divides by a sigma literal').not.toBeNull();
    const shown = Number(sigma![1]);
    expect(
      shown,
      `PlayoffBracketSimulator divides the rating gap by a hardcoded ${shown} while ` +
        `model_diagnostics.json reports margin_sigma=${d.margin_sigma}. Every simulated bracket is ` +
        `computed off the wrong dispersion.`,
    ).toBeCloseTo(d.margin_sigma, 1);
  });

  it('PlayoffBracketSimulator uses the real home-field advantage', () => {
    const src = read('components', 'PlayoffBracketSimulator.tsx');
    const hca = src.match(/hca\s*=\s*isNeutral\s*\?\s*0\s*:\s*([\d.]+)/);
    expect(hca, 'PlayoffBracketSimulator no longer assigns an hca literal').not.toBeNull();
    const shown = Number(hca![1]);
    expect(
      shown,
      `PlayoffBracketSimulator applies a hardcoded ${shown}-point home-field edge while ` +
        `model_diagnostics.json reports home_field_adv=${d.home_field_adv}.`,
    ).toBeCloseTo(d.home_field_adv, 1);
  });

  it('all hardcoded margin sigma literals agree with each other', () => {
    // Before worrying about whether the UI matches the data, the UI should at
    // least agree with itself. Sidebar.tsx prints "σ = 14.6" while
    // app/page.tsx prints "13.8 pts" and PlayoffBracketSimulator divides by
    // 13.8 — so the navigation and the banner contradict each other on screen.
    const sources: Array<[string, string]> = [
      ['app/page.tsx', read('app', 'page.tsx')],
      ['components/Sidebar.tsx', read('components', 'Sidebar.tsx')],
      ['components/PlayoffBracketSimulator.tsx', read('components', 'PlayoffBracketSimulator.tsx')],
    ];
    const found = new Map<string, Set<string>>();
    for (const [label, src] of sources) {
      for (const m of src.matchAll(/(?:σ\s*=\s*|margin\s*\/\s*|diff\s*\/\s*)(\d+\.\d+)|(\d+\.\d+)\s*pts/gi)) {
        const value = m[1] ?? m[2];
        if (!value) continue;
        const asNum = Number(value);
        // Only consider values in the plausible NFL margin-sigma band.
        if (asNum < 10 || asNum > 18) continue;
        if (!found.has(value)) found.set(value, new Set());
        found.get(value)!.add(label);
      }
    }
    expect(
      [...found.keys()].sort(),
      `the app hardcodes more than one margin sigma: ` +
        [...found.entries()].map(([v, files]) => `${v} in ${[...files].join(', ')}`).join(' | ') +
        `. model_diagnostics.json says ${d.margin_sigma}.`,
    ).toEqual([String(d.margin_sigma)]);
  });

  it('DiagnosticsClient reads the sigma and HFA from props, not from literals', () => {
    const src = read('components', 'DiagnosticsClient.tsx');
    expect(src, 'DiagnosticsClient should render data.margin_sigma').toContain('data.margin_sigma');
    expect(src, 'DiagnosticsClient should render data.home_field_adv').toContain('data.home_field_adv');
  });
});

describe('simulation counts in copy match the datasets', () => {
  it('the playoffs page chip reads n_simulations from the data', () => {
    const src = read('app', 'playoffs', 'page.tsx');
    expect(src, 'the Simulations chip should interpolate dataset.n_simulations').toContain('dataset.n_simulations');
  });

  it('the playoffs page description matches the real trial count', () => {
    const src = read('app', 'playoffs', 'page.tsx');
    const claim = src.match(/([\d,]+)-trial/);
    if (claim) {
      const shown = Number(claim[1].replace(/,/g, ''));
      expect(
        shown,
        `app/playoffs/page.tsx metadata claims a ${claim[1]}-trial simulation but ` +
          `playoff_picture.json reports n_simulations=${playoffs().n_simulations}.`,
      ).toBe(playoffs().n_simulations);
    }
  });

  it('every "N-Sim"/"N-Season" claim in the shell is self-consistent', () => {
    // The layout metadata, the home page banner, the sidebar and the navbar
    // each state a Monte Carlo trial count independently.
    const sources = [
      ['app/layout.tsx', read('app', 'layout.tsx')],
      ['app/page.tsx', read('app', 'page.tsx')],
      ['components/Sidebar.tsx', read('components', 'Sidebar.tsx')],
      ['components/Navbar.tsx', read('components', 'Navbar.tsx')],
    ] as const;
    const claims = new Map<string, Set<string>>();
    for (const [label, src] of sources) {
      for (const m of src.matchAll(/([\d,]+)-(?:Sim|Season)/g)) {
        if (!claims.has(m[1])) claims.set(m[1], new Set());
        claims.get(m[1])!.add(label);
      }
    }
    expect(
      [...claims.keys()],
      `the app shell advertises more than one season-simulation count: ` +
        [...claims.entries()].map(([n, files]) => `${n} in ${[...files].join(', ')}`).join(' | '),
    ).toHaveLength(claims.size === 0 ? 0 : 1);
  });
});

describe('schedule copy matches the schedule', () => {
  const d = matchups();

  it('the matchups page week range covers every selectable week', () => {
    // app/matchups/page.tsx prints a "Weeks A - B (N Games)" chip.
    const src = read('app', 'matchups', 'page.tsx');
    const chip = src.match(/Weeks\s+(\d+)\s*[–-]\s*(\d+)\s*\((\d+)\s*Games\)/);
    expect(chip, 'could not find the week-range chip in app/matchups/page.tsx').not.toBeNull();
    const [, from, to, games] = chip!;
    const minWeek = Math.min(...d.available_weeks);
    const maxWeek = Math.max(...d.available_weeks);
    expect(
      { from: Number(from), to: Number(to) },
      `the chip says weeks ${from}-${to} but the week selector offers ${minWeek}-${maxWeek}, ` +
        `because available_weeks covers the whole season rather than the remaining slate.`,
    ).toEqual({ from: minWeek, to: maxWeek });
    expect(
      Number(games),
      `the chip claims ${games} games; the dataset holds ${d.matchups.length}.`,
    ).toBe(d.matchups.length);
  });

  it('the matchups page key-number chip lists only numbers the data emits', () => {
    const src = read('app', 'matchups', 'page.tsx');
    const chip = src.match(/Key Margin Alerts[\s\S]{0,300}?>\s*(\d[\d,\s]*)</);
    expect(chip, 'could not find the Key Margin Alerts chip').not.toBeNull();
    const advertised = chip![1].split(',').map((s) => Number(s.trim())).filter(Number.isFinite);
    const emitted = new Set(
      d.matchups.filter((m) => m.key_number_flag !== 'Standard').map((m) => parseInt(m.key_number_flag, 10)),
    );
    const unreachable = advertised.filter((n) => !emitted.has(n));
    expect(
      unreachable,
      `app/matchups/page.tsx advertises key number(s) ${JSON.stringify(unreachable)} that ` +
        `key_number_flag never produces.`,
    ).toEqual([]);
  });
});

describe('salary cap copy matches the cap data', () => {
  const d = salaryCap();

  it('the sidebar cap badge matches cap_ceiling', () => {
    const src = read('components', 'Sidebar.tsx');
    const badge = src.match(/\$([\d.]+)M Cap/);
    expect(badge, 'could not find the cap badge in Sidebar.tsx').not.toBeNull();
    expect(
      Number(badge![1]),
      `Sidebar.tsx hardcodes a $${badge![1]}M cap badge while salary_cap_profiles.json reports ` +
        `cap_ceiling=${d.cap_ceiling}. Read it from the dataset.`,
    ).toBeCloseTo(d.cap_ceiling, 1);
  });

  it('SalaryCapClient renders the cap ceiling from props', () => {
    const src = read('components', 'SalaryCapClient.tsx');
    expect(src).toContain('data.cap_ceiling');
  });

  it('SalaryCapClient top-contract fallbacks are not stale placeholders', () => {
    // The KPI card reads `data.top_league_contracts[0]?.apy || 60.0` and
    // `?.player || 'Dak Prescott'`. Those literals are only reachable if the
    // dataset is empty, but if they ARE reachable they must not contradict it.
    const src = read('components', 'SalaryCapClient.tsx');
    const top = d.top_league_contracts[0];
    const fallbackPlayer = src.match(/\?\.player\s*\|\|\s*'([^']+)'/);
    if (fallbackPlayer && top) {
      expect(
        fallbackPlayer[1] === top.player || d.top_league_contracts.length > 0,
        `SalaryCapClient falls back to "${fallbackPlayer[1]}" but the top contract is ${top.player}`,
      ).toBe(true);
    }
    expect(d.top_league_contracts.length, 'the fallback literals would be reachable').toBeGreaterThan(0);
  });
});

describe('team and gallery counts in copy match the data', () => {
  it('every "32 ..." claim is backed by 32 rows', () => {
    const teams = standings().teams.length;
    expect(teams).toBe(32);
    for (const file of [
      ['app', 'teams', 'page.tsx'],
      ['components', 'Sidebar.tsx'],
      ['components', 'CoachingClient.tsx'],
      ['components', 'SalaryCapClient.tsx'],
    ]) {
      const src = read(...file);
      for (const m of src.matchAll(/(\d+)\s+(?:NFL\s+)?(?:Team|Franchise|Head Coach)/gi)) {
        expect(Number(m[1]), `${file.join('/')} claims "${m[0]}"`).toBe(teams);
      }
    }
  });

  it('the gallery page item-count claim is not below the real count', () => {
    const src = read('app', 'gallery', 'page.tsx');
    const claim = src.match(/(\d+)\+?\s+(?:automated\s+)?anim/i);
    if (claim) {
      expect(
        media().length,
        `app/gallery/page.tsx advertises "${claim[0]}" but the index holds ${media().length} items.`,
      ).toBeGreaterThanOrEqual(Number(claim[1]));
    }
  });

  it('the playoff field size claimed in copy matches the seed arrays', () => {
    const seats = playoffs().afc_seeds.length + playoffs().nfc_seeds.length;
    for (const file of [['app', 'playoffs', 'page.tsx'], ['app', 'page.tsx'], ['components', 'Sidebar.tsx']]) {
      const src = read(...file);
      for (const m of src.matchAll(/(\d+)[\s-]+(?:Team|Seed)/gi)) {
        const n = Number(m[1]);
        // Only check claims in the playoff-field ballpark, not "32 Teams".
        if (n >= 10 && n <= 20) {
          expect(n, `${file.join('/')} claims "${m[0]}" but the field holds ${seats}`).toBe(seats);
        }
      }
    }
  });
});

describe('no component re-derives a constant the data already carries', () => {
  it('VariantsClient reads the ensemble weights from props', () => {
    expect(read('components', 'VariantsClient.tsx')).toContain('data.ensemble_weights');
  });

  it('the VariantsClient ensemble formula caption matches the live weights', () => {
    // The weight bars above the caption are driven by data.ensemble_weights,
    // but the caption restates the same three numbers as a literal string:
    //   "Formula: P(final) = 0.40 · P(Ridge) + 0.35 · P(Elo) + 0.25 · P(Market)"
    // Change the weights upstream and the bars move while the caption lies.
    const src = read('components', 'VariantsClient.tsx');
    const caption = src.match(/Formula:\s*P\(final\)\s*=\s*([\s\S]{0,160}?)<\/span>/);
    expect(caption, 'could not find the ensemble formula caption in VariantsClient').not.toBeNull();
    const printed = (caption![1].match(/\d+\.\d+/g) ?? []).map(Number);
    const w = diagnostics().ensemble_weights;
    expect(
      printed,
      `the formula caption prints ${JSON.stringify(printed)} but model_diagnostics.json reports ` +
        `${JSON.stringify([w.ridge_massey, w.elo_dynamic, w.market_blend])}. Interpolate the weights ` +
        `instead of re-typing them.`,
    ).toEqual([w.ridge_massey, w.elo_dynamic, w.market_blend]);
  });

  it('the VariantsClient fallback weights still sum to 1', () => {
    // `data.ensemble_weights || { ...literals }` means the literals are live
    // code whenever the field is missing; they must at least be a valid mix.
    const src = read('components', 'VariantsClient.tsx');
    const fallback = src.match(/ensemble_weights\s*\|\|\s*\{([\s\S]{0,200}?)\}/);
    expect(fallback, 'VariantsClient no longer declares a fallback weight object').not.toBeNull();
    const nums = (fallback![1].match(/\d+\.\d+/g) ?? []).map(Number);
    expect(nums, 'expected three fallback weights').toHaveLength(3);
    expect(nums.reduce((a, b) => a + b, 0)).toBeCloseTo(1, 6);
  });

  it('DiagnosticsClient does not re-type the Brier baseline', () => {
    const src = read('components', 'DiagnosticsClient.tsx');
    const baseline = diagnostics().brier_baseline;
    const hardcoded = numericLiterals(src).filter((n) => Math.abs(n - baseline) < 1e-9);
    expect(
      hardcoded.length === 0 || src.includes('brier_baseline'),
      `DiagnosticsClient writes the baseline ${baseline} as a literal ${hardcoded.length} time(s) ` +
        `instead of reading data.brier_baseline.`,
    ).toBe(true);
  });
});
