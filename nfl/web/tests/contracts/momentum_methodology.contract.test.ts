/**
 * momentum_methodology.json contract (consumed by /momentum/methodology, #226).
 *
 * Written by tools/publish_momentum_methodology.R from the two study results
 * files. This suite re-applies every recorded extract to the results file in the
 * working tree and requires a deep-equal result, checks each file's recorded
 * sha256 (LF line endings), and checks the NBA-style comparison weights against
 * the NBA_W and GRID lines of tools/rolling_window_study.R: the script's git blob
 * sha1 must be the one recorded at the study commit, and re-parsing the lines must
 * give the published weights. It also checks the file carries no betting
 * vocabulary and no NaN or Infinity. (tests/test_momentum_methodology.R
 * additionally rebuilds the file from git when the study commits are reachable.)
 */
import crypto from 'crypto';
import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { DATA_DIR } from '../helpers/datasets';
import type { ExtractSpec, MethodologyComponent, MomentumMethodologyPayload } from '@/lib/momentumMethodologyTypes';
import type { MomentumPayload } from '@/lib/momentumTypes';

const REPO_ROOT = path.resolve(DATA_DIR, '..', '..', '..');
const lf = (s: string) => s.replace(/\r\n/g, '\n');
const readLf = (rel: string) => lf(fs.readFileSync(path.join(REPO_ROOT, rel), 'utf-8'));

const RAW = lf(fs.readFileSync(path.join(DATA_DIR, 'momentum_methodology.json'), 'utf-8'));
const DATA = JSON.parse(RAW) as MomentumMethodologyPayload;
const BOARD = JSON.parse(fs.readFileSync(path.join(DATA_DIR, 'momentum_board.json'), 'utf-8')) as MomentumPayload;
const SOURCES = ['rolling_window', 'momentum_measures'] as const;
const FORBIDDEN_BETTING_RE =
  /\b(odds|spreads?|picks?|props?|wagers?|edges?|bets?|betting|sportsbook|moneyline|parlay|vig|juice|handicap)\b/i;

function getPath(x: unknown, p: string): unknown {
  let v: unknown = x;
  for (const k of p.split('.')) {
    if (v === null || typeof v !== 'object' || Array.isArray(v) || !(k in (v as object))) return undefined;
    v = (v as Record<string, unknown>)[k];
  }
  return v;
}

/** The TypeScript twin of mmp_apply_extract() in the publisher. */
function applyExtract(src: unknown, spec: ExtractSpec): unknown {
  let v = getPath(src, spec.path);
  if (v === undefined) throw new Error(`results file has no '${spec.path}'`);
  if (spec.where) {
    const { field, values } = spec.where;
    v = (v as Record<string, unknown>[]).filter((r) => values.includes(String(r[field])));
  }
  if (spec.fields) {
    v = (v as Record<string, unknown>[]).map((r) => Object.fromEntries(spec.fields!.map((f) => [f, r[f]])));
  }
  return v;
}

const sha256 = (s: string) => crypto.createHash('sha256').update(s, 'utf8').digest('hex');
const gitBlobSha1 = (s: string) => {
  const body = Buffer.from(s, 'utf8');
  return crypto.createHash('sha1').update(Buffer.concat([Buffer.from(`blob ${body.length}\0`), body])).digest('hex');
};

/** Re-parse the comparison weights from the study script's GRID and NBA_W lines. */
function parseComparisonWeights(script: string): { weights: Record<MethodologyComponent, number>; nbaLine: number; gridLine: number } {
  const lines = script.split('\n');
  const gridIdx = lines.findIndex((l) => l.startsWith('GRID <- '));
  const nbaIdx = lines.findIndex((l) => l.startsWith('NBA_W <- '));
  if (gridIdx < 0 || nbaIdx < 0) throw new Error('GRID or NBA_W line not found');
  const grid = lines[gridIdx];
  const cols = [...grid.matchAll(/([a-z_]+) = 0:(\d+)/g)].map((m) => ({ name: m[1], steps: Number(m[2]) }));
  const rule = grid.match(/form \+ trend \+ resid \+ elo == (\d+)\)\) \/ (\d+)$/);
  if (cols.length !== 4 || !rule) throw new Error('GRID line is not a four-column sum-to-1 grid');
  const denom = Number(rule[2]);
  if (Number(rule[1]) !== denom || cols.some((c) => c.steps !== denom)) throw new Error('GRID is not a sum-to-1 grid');
  const conds = [...lines[nbaIdx].matchAll(/abs\(GRID\[, (\d)\] - ([0-9.]+)\) < 1e-9/g)].map((m) => ({
    col: Number(m[1]),
    units: Math.round(Number(m[2]) * denom),
  }));
  if (conds.length !== 3) throw new Error('NBA_W does not fix three grid columns');
  const units = [0, 0, 0, 0];
  for (const c of conds) units[c.col - 1] = c.units;
  const free = [0, 1, 2, 3].find((i) => !conds.some((c) => c.col - 1 === i))!;
  units[free] = denom - conds.reduce((a, c) => a + c.units, 0);
  const names: MethodologyComponent[] = ['form', 'trend', 'residual', 'elo_change'];
  const weights = Object.fromEntries(names.map((n, i) => [n, units[i] / denom])) as Record<MethodologyComponent, number>;
  return { weights, nbaLine: nbaIdx + 1, gridLine: gridIdx + 1 };
}

describe('momentum_methodology.json contract', () => {
  it('is schema version 1 for board issue 226', () => {
    expect(DATA.schema_version).toBe(1);
    expect(DATA.board_issue).toBe(226);
  });

  for (const key of SOURCES) {
    describe(key, () => {
      const src = DATA.sources[key];
      const text = readLf(src.file);
      const results = JSON.parse(text);

      it('records the sha256 of the results file (LF line endings)', () => {
        expect(src.sha256_lf).toBe(sha256(text));
      });

      it('records a full commit sha', () => {
        expect(src.commit).toMatch(/^[0-9a-f]{40}$/);
      });

      it('every extract equals the results file', () => {
        expect(src.extracts.length).toBeGreaterThan(0);
        for (const spec of src.extracts) {
          expect(getPath(DATA[key], spec.path), spec.path).toEqual(applyExtract(results, spec));
        }
      });

      it('publishes nothing under the study key beyond its extracts', () => {
        const top = new Set(src.extracts.map((s) => s.path.split('.')[0]));
        expect(Object.keys(DATA[key]).filter((k) => !top.has(k))).toEqual([]);
      });
    });
  }

  describe('NBA-style comparison weights', () => {
    const nba = DATA.sources.rolling_window.nba_comparison_weights;
    const script = readLf(nba.provenance.file);

    it('the study script is the blob recorded at the study commit', () => {
      expect(nba.provenance.commit).toBe(DATA.sources.rolling_window.commit);
      expect(gitBlobSha1(script)).toBe(nba.provenance.blob_sha1);
    });

    it('re-parsing the GRID and NBA_W lines gives the published weights', () => {
      const parsed = parseComparisonWeights(script);
      expect({ form: nba.form, trend: nba.trend, residual: nba.residual, elo_change: nba.elo_change }).toEqual(parsed.weights);
      expect(nba.provenance.line).toBe(parsed.nbaLine);
      expect(nba.provenance.grid_line).toBe(parsed.gridLine);
      const lines = script.split('\n');
      expect(nba.provenance.line_text).toBe(lines[parsed.nbaLine - 1]);
      expect(nba.provenance.grid_line_text).toBe(lines[parsed.gridLine - 1]);
    });

    it('the derived share is the remainder of a sum-to-1 grid', () => {
      const sum = nba.form + nba.trend + nba.residual + nba.elo_change;
      expect(Math.abs(sum - 1)).toBeLessThan(1e-12);
      expect(nba.provenance.derived_component).toBe('elo_change');
    });
  });

  describe('board block', () => {
    it('names the board windows, carry method and the weight rows they select', () => {
      expect(DATA.board.windows).toEqual(BOARD.windows);
      expect(DATA.board.carry_method).toBe(BOARD.methods.carry_over.method);
      for (const w of DATA.board.windows) {
        const rows = DATA.rolling_window.weights.detail.filter(
          (r) => r.method === DATA.board.carry_method && r.window === String(w) && r.target === DATA.board.weights_target,
        );
        expect(rows, `window ${w}`).toHaveLength(1);
        const inUse = BOARD.methods.combined_score.weights[String(w)];
        expect(rows[0].best_weights, `window ${w}`).toEqual(DATA.board.weights_order.map((c) => inUse[c]));
      }
    });
  });

  it('carries no betting vocabulary', () => {
    expect(RAW).not.toMatch(FORBIDDEN_BETTING_RE);
  });

  it('carries no NaN, Infinity or "NA" values', () => {
    expect(RAW).not.toMatch(/:\s*(NaN|-?Infinity|"NA")/);
  });
});
