/**
 * Sidecar data manifest contract (front-office#102, front-office#191).
 *
 * `public/data/data_manifest.json` is written by `tools/write_data_manifest.R`
 * and read by the publish gate's assertion H. This suite fails when the
 * manifest's shape drifts, or when any top-level `public/data/*.json` is
 * unlisted or carries no valid UTC ISO-8601 `generated_at`.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import { z } from 'zod';
import { DATA_DIR, DATA_MANIFEST_FILE, loadRaw } from '../helpers/datasets';

const isoUtc = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, 'expected YYYY-MM-DDTHH:MM:SSZ');
const ymd = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'expected YYYY-MM-DD');

const sha256 = z.string().regex(/^[0-9a-f]{64}$/, 'expected a sha256 hex digest');

// stamp_source: the payload's own stamp, or content-hash carry-forward. Never
// file mtime / git time (FO#102).
const stampSource = z.string().regex(/^(payload:.+|manifest:content_hash)$/);

const lifecycleEnum = z.enum(['live', 'season_final', 'archived']);
const seasonFinalFields = ['season', 'final_through_date', 'frozen_sha256', 'frozen_at'] as const;

const baseEntry = {
  builder: z.string().min(1),
  generated_at: isoUtc,
  stamp_source: stampSource,
  content_sha256: sha256.nullable(),
  // Optional in Zod during in-season rollout (NFL_analytics#214); publish gate
  // assertion L enforces presence on disk.
  lifecycle: lifecycleEnum.optional(),
  season: z.union([z.number().int().positive(), z.string().min(1)]).optional(),
  final_through_date: ymd.optional(),
  frozen_sha256: sha256.optional(),
  frozen_at: isoUtc.optional(),
};

// through_date comes from the payload's own content, or is explicitly null
// with a coverage_note (FO#191). Never derived from generated_at.
const coverage = z.union([
  z.object({ through_date: ymd, through_date_source: z.string().regex(/^payload:.+/), coverage_note: z.string().nullable() }),
  z.object({ through_date: z.null(), through_date_source: z.literal('not_game_dated'), coverage_note: z.string().min(1) }),
]);

const activeEntry = z.object({
  ...baseEntry,
  through_date: ymd.nullable(),
  through_date_source: z.string(),
  coverage_note: z.string().nullable(),
  static: z.literal(false),
  max_lag_days: z.number().int().positive(),
}).strict();

const staticEntry = z.object({
  ...baseEntry,
  through_date: ymd.nullable(),
  through_date_source: z.string(),
  coverage_note: z.string().nullable(),
  static: z.literal(true),
  static_reason: z.string().min(1),
}).strict();

const entrySchema = z.discriminatedUnion('static', [activeEntry, staticEntry])
  .superRefine((e, ctx) => {
    const r = coverage.safeParse({ through_date: e.through_date, through_date_source: e.through_date_source, coverage_note: e.coverage_note });
    if (!r.success) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'through_date must be payload-sourced, or null + not_game_dated + coverage_note' });
    if (e.lifecycle === 'season_final') {
      for (const k of seasonFinalFields) {
        if (e[k] === undefined) {
          ctx.addIssue({
            code: z.ZodIssueCode.custom,
            path: [k],
            message: `${k} is required when lifecycle is 'season_final'`,
          });
        }
      }
    }
  });

export const DataManifestSchema = z.object({
  schema_version: z.literal(1),
  sport: z.literal('nfl'),
  generated_at: isoUtc,
  schedule_through_date: ymd.nullable(),
  datasets: z.record(z.string().regex(/\.json$/), entrySchema),
}).strict();

const manifest = () => DataManifestSchema.parse(loadRaw(DATA_MANIFEST_FILE));

describe('data_manifest.json', () => {
  it('matches the manifest schema', () => {
    const res = DataManifestSchema.safeParse(loadRaw(DATA_MANIFEST_FILE));
    if (!res.success) throw new Error(JSON.stringify(res.error.issues.slice(0, 10)));
    expect(res.success).toBe(true);
  });

  it('lists every top-level dataset file, and nothing that is not on disk', () => {
    const onDisk = fs.readdirSync(DATA_DIR)
      .filter((f) => f.endsWith('.json') && f !== DATA_MANIFEST_FILE)
      .sort();
    const listed = Object.keys(manifest().datasets).sort();
    const unlisted = onDisk.filter((f) => !listed.includes(f));
    const phantom = listed.filter((f) => !onDisk.includes(f));
    expect(unlisted, `unlisted in ${DATA_MANIFEST_FILE}: ${unlisted.join(', ')}`).toEqual([]);
    expect(phantom, `listed but absent: ${phantom.join(', ')}`).toEqual([]);
  });

  it('every entry carries a parseable generated_at', () => {
    for (const [file, e] of Object.entries(manifest().datasets)) {
      expect(Number.isNaN(Date.parse(e.generated_at)), `${file} generated_at`).toBe(false);
    }
  });

  it('accepts optional lifecycle and season_final metadata under .strict()', () => {
    const sha = 'a'.repeat(64);
    const sample = {
      schema_version: 1,
      sport: 'nfl',
      generated_at: '2026-11-24T05:00:00Z',
      schedule_through_date: '2026-11-23',
      datasets: {
        'standings_projections.json': {
          builder: 'export_web_datasets.R',
          generated_at: '2026-11-24T05:00:00Z',
          stamp_source: 'payload:generated_at',
          content_sha256: sha,
          through_date: null,
          through_date_source: 'not_game_dated',
          coverage_note: 'No game date',
          static: false,
          max_lag_days: 8,
          lifecycle: 'live',
        },
        'salary_cap_profiles.json': {
          builder: 'export_web_datasets.R',
          generated_at: '2026-11-24T05:00:00Z',
          stamp_source: 'payload:generated_at',
          content_sha256: sha,
          through_date: null,
          through_date_source: 'not_game_dated',
          coverage_note: 'Annual cap snapshot',
          static: true,
          static_reason: 'Annual NFL salary cap snapshot',
          lifecycle: 'live',
        },
        'matchups_current_week.json': {
          builder: 'export_web_datasets.R',
          generated_at: '2026-11-24T05:00:00Z',
          stamp_source: 'payload:generated_at',
          content_sha256: sha,
          through_date: '2026-11-23',
          through_date_source: 'payload:matchups[is_completed].gameday',
          coverage_note: null,
          static: false,
          max_lag_days: 8,
          lifecycle: 'season_final',
          season: 2026,
          final_through_date: '2026-11-23',
          frozen_sha256: sha,
          frozen_at: '2026-11-24T06:00:00Z',
        },
      },
    };
    expect(DataManifestSchema.safeParse(sample).success).toBe(true);
  });

  it('rejects unknown lifecycle and incomplete season_final metadata', () => {
    const sha = 'b'.repeat(64);
    const base = {
      schema_version: 1,
      sport: 'nfl',
      generated_at: '2026-11-24T05:00:00Z',
      schedule_through_date: '2026-11-23',
    };
    const entryBase = {
      builder: 'export_web_datasets.R',
      generated_at: '2026-11-24T05:00:00Z',
      stamp_source: 'payload:generated_at',
      content_sha256: sha,
      through_date: null,
      through_date_source: 'not_game_dated',
      coverage_note: 'No game date',
      static: false,
      max_lag_days: 8,
    };

    const badEnum = { ...base, datasets: { 'a.json': { ...entryBase, lifecycle: 'unknown' } } };
    expect(DataManifestSchema.safeParse(badEnum).success).toBe(false);

    for (const missingKey of seasonFinalFields) {
      const full = {
        ...entryBase,
        lifecycle: 'season_final',
        season: 2026,
        final_through_date: '2026-11-23',
        frozen_sha256: sha,
        frozen_at: '2026-11-24T06:00:00Z',
      };
      delete (full as Record<string, unknown>)[missingKey];
      const badFrozen = { ...base, datasets: { 'a.json': full } };
      expect(DataManifestSchema.safeParse(badFrozen).success, `missing ${missingKey}`).toBe(false);
    }
  });
});
