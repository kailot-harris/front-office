/**
 * Layer 1 — every dataset in public/data/ parses and matches its schema.
 *
 * `lib/data.ts` casts raw JSON with `as T` and does no validation, so a shape
 * change in `tools/export_web_datasets.R` would otherwise reach the browser as
 * an `undefined.toFixed()` crash at render time. This suite is the gate.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { DATASET_SCHEMAS } from './schemas';
import { DATA_DIR, DATASET_FILES, loadRaw } from '../helpers/datasets';

describe('dataset files exist and are well-formed JSON', () => {
  it.each(Object.entries(DATASET_FILES))(
    'lib/data.ts %s() has a file to read: %s',
    (_getter, filename) => {
      const p = path.join(DATA_DIR, filename);
      expect(fs.existsSync(p), `missing ${p}`).toBe(true);
      expect(() => JSON.parse(fs.readFileSync(p, 'utf-8'))).not.toThrow();
    },
  );

  it('ships no dataset file that the app never reads', () => {
    const onDisk = fs.readdirSync(DATA_DIR).filter((f) => f.endsWith('.json'));
    const referenced = new Set<string>(Object.values(DATASET_FILES));
    const orphans = onDisk.filter((f) => !referenced.has(f));
    expect(orphans, `orphaned dataset files in public/data/: ${orphans.join(', ')}`).toEqual([]);
  });
});

describe('dataset schema conformance', () => {
  it.each(Object.keys(DATASET_SCHEMAS))('%s matches its declared contract', (filename) => {
    const schema = DATASET_SCHEMAS[filename as keyof typeof DATASET_SCHEMAS];
    const result = schema.safeParse(loadRaw(filename));

    if (!result.success) {
      // Compact, actionable failure text: path + message, deduped, capped.
      const issues = result.error.issues
        .map((i) => `  ${i.path.join('.') || '(root)'}: ${i.message}`)
        .filter((line, idx, arr) => arr.indexOf(line) === idx)
        .slice(0, 25);
      throw new Error(
        `${filename} failed schema validation (${result.error.issues.length} issue(s)):\n${issues.join('\n')}`,
      );
    }
    expect(result.success).toBe(true);
  });
});

describe('declared counts match actual array lengths', () => {
  it('standings_projections.total_teams === teams.length', () => {
    const d = loadRaw('standings_projections.json') as { total_teams: number; teams: unknown[] };
    expect(d.total_teams).toBe(d.teams.length);
  });

  it('matchups_current_week.total_games === matchups.length', () => {
    const d = loadRaw('matchups_current_week.json') as { total_games: number; matchups: unknown[] };
    expect(d.total_games).toBe(d.matchups.length);
  });

  it('value_bets.total_bets === active_bets.length', () => {
    const d = loadRaw('value_bets.json') as { total_bets: number; active_bets: unknown[] };
    expect(d.total_bets).toBe(d.active_bets.length);
  });
});
