/**
 * momentum_methodology.json contract (consumed by /momentum/methodology).
 *
 * Written by tools/publish_momentum_methodology.R, which copies the momentum
 * measures study's results file byte for byte and splices three provenance
 * keys in after the opening brace. This suite checks that the published file
 * is still exactly that: removing the provenance block gives back bytes whose
 * sha256 is the recorded source_sha256. It also checks the study's own rules
 * hold row by row, and that the file carries no betting vocabulary.
 */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { DATA_DIR } from '../helpers/datasets';
import type { MomentumMethodologyPayload } from '@/lib/momentumMethodologyTypes';

const FILE = path.join(DATA_DIR, 'momentum_methodology.json');
// LF-normalised: the study file is LF, and a CRLF checkout must not read as a changed file.
const RAW = fs.readFileSync(FILE, 'utf-8').replace(/\r\n/g, '\n');
const DATA = JSON.parse(RAW) as MomentumMethodologyPayload;
const PROVENANCE_KEYS = ['source_commit', 'source_sha256', 'published_at'] as const;
const FORBIDDEN_BETTING_RE =
  /\b(odds|spread|spreads|bet|bets|betting|wager|wagers|parlay|sportsbook|moneyline|over_under|vig|juice|handicap)\b/i;

describe('momentum_methodology.json contract', () => {
  it('starts with exactly the three provenance keys', () => {
    expect(Object.keys(DATA).slice(0, PROVENANCE_KEYS.length)).toEqual([...PROVENANCE_KEYS]);
  });

  it('minus the provenance block, is byte-identical to the study file it names (sha256)', () => {
    const block = new RegExp(
      `^\\{\\n  "source_commit": "${DATA.source_commit}",\\n  "source_sha256": "${DATA.source_sha256}",\\n  "published_at": "${DATA.published_at}",`,
    );
    expect(RAW).toMatch(block);
    const original = RAW.replace(block, '{');
    const sha = crypto.createHash('sha256').update(original, 'utf8').digest('hex');
    expect(sha).toBe(DATA.source_sha256);
  });

  it('has one result row per series x measure x target, none repeated', () => {
    const n = DATA.series.length * DATA.measures.length * DATA.targets.length;
    expect(DATA.single_feature_results.length).toBe(n);
    const keys = new Set(DATA.single_feature_results.map((r) => `${r.series}|${r.measure}|${r.target}`));
    expect(keys.size).toBe(n);
    const ids = {
      series: new Set(DATA.series.map((s) => s.id)),
      measure: new Set(DATA.measures.map((m) => m.id)),
      target: new Set(DATA.targets.map((t) => t.id)),
    };
    for (const r of DATA.single_feature_results) {
      expect(ids.series.has(r.series), r.feature).toBe(true);
      expect(ids.measure.has(r.measure), r.feature).toBe(true);
      expect(ids.target.has(r.target), r.feature).toBe(true);
      expect(r.feature).toBe(`${r.series}__${r.measure}`);
    }
  });

  it('has exactly one primary target, and the combination search scores it', () => {
    const primaries = DATA.targets.filter((t) => t.primary);
    expect(primaries).toHaveLength(1);
    expect(DATA.combination_search.target).toBe(primaries[0].id);
  });

  it('every verdict follows the study rule: kept needs an interval above zero, discarded a gain at or below zero', () => {
    for (const r of DATA.single_feature_results) {
      if (r.verdict === 'kept') expect(r.ci_95[0], r.feature).toBeGreaterThan(0);
      if (r.verdict === 'discarded') expect(r.r2_gain, r.feature).toBeLessThanOrEqual(0);
      if (r.verdict === 'inconclusive') {
        expect(r.r2_gain, r.feature).toBeGreaterThan(0);
        expect(r.ci_95[0] <= 0 || r.fdr_q_value >= 0.05, r.feature).toBe(true);
      }
    }
  });

  it('correlation grids are square and follow the measure / series order', () => {
    const m = DATA.measures.map((x) => x.id);
    const s = DATA.series.map((x) => x.id);
    expect(Object.keys(DATA.families.measure_mean_abs_r)).toEqual(m);
    expect(Object.keys(DATA.families.series_mean_abs_r)).toEqual(s);
    for (const row of Object.values(DATA.families.measure_mean_abs_r)) expect(row).toHaveLength(m.length);
    for (const row of Object.values(DATA.families.series_mean_abs_r)) expect(row).toHaveLength(s.length);
  });

  it('contains no betting vocabulary and no NaN/Infinity/"NA" values', () => {
    expect(RAW).not.toMatch(FORBIDDEN_BETTING_RE);
    expect(RAW).not.toMatch(/:\s*NaN\b/);
    expect(RAW).not.toMatch(/:\s*-?Infinity\b/);
    expect(RAW).not.toMatch(/:\s*"NA"/);
  });
});
