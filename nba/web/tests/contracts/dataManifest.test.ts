/**
 * data_manifest.json contract (front-office#102 / #191).
 *
 * The sidecar written by tools/write_data_manifest.R must stamp every
 * top-level public/data/*.json payload and list nothing that is not on disk.
 * The publish gate (tools/publish_web.R assertion H) enforces schedule lag;
 * this suite enforces shape and completeness on the committed tree.
 */
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { listTopLevelDataFiles, readDataManifest } from '../helpers/datasets';

const UTC_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const ISO_DATE = /^\d{4}-\d{2}-\d{2}$/;

const utcIso = z
  .string()
  .regex(UTC_ISO, 'must be UTC ISO-8601 (YYYY-MM-DDTHH:MM:SSZ)')
  .refine((s) => !Number.isNaN(Date.parse(s)), 'must be a real timestamp');
const isoDate = z
  .string()
  .regex(ISO_DATE, 'must be YYYY-MM-DD')
  .refine((s) => !Number.isNaN(Date.parse(s)), 'must be a real date');

export const DataManifestEntrySchema = z
  .object({
    generated_at: utcIso,
    through_date: isoDate.nullable(),
    through_date_source: z
      .string()
      .regex(/^(payload:.+|not_game_dated|static)$/, 'payload:<field>, not_game_dated or static'),
    stamp_source: z.string().regex(/^(payload:.+|manifest:content_hash)$/),
    content_sha256: z.string().regex(/^[0-9a-f]{64}$/).nullable(),
    coverage_note: z.string().min(1).nullable(),
    source_season: z.string().regex(/^\d{4}-\d{2}$/),
    builder: z.string().regex(/^[A-Za-z0-9_]+\.R$/),
    max_lag_days: z.number().int().nonnegative(),
    static: z.boolean(),
    static_reason: z.string().min(1).nullable(),
  })
  .strict()
  .superRefine((e, ctx) => {
    if (e.static && !e.static_reason) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'static dataset needs a static_reason' });
    }
    if (!e.static && e.through_date === null && e.through_date_source !== 'not_game_dated') {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'game-dated dataset needs a through_date' });
    }
    if (e.through_date !== null && !e.through_date_source.startsWith('payload:')) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'through_date must be extracted from the payload' });
    }
    if (e.through_date_source === 'not_game_dated' && !e.coverage_note) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'not_game_dated dataset needs a coverage_note' });
    }
    if (e.stamp_source === 'manifest:content_hash' && e.content_sha256 === null) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'content-hash stamp needs content_sha256' });
    }
  });

export const DataManifestSchema = z
  .object({
    schema_version: z.literal(1),
    sport: z.literal('nba'),
    generated_at: utcIso,
    schedule_through_date: isoDate.nullable(),
    datasets: z.record(DataManifestEntrySchema),
  })
  .strict();

describe('data_manifest.json', () => {
  const raw = readDataManifest();

  it('matches DataManifestSchema', () => {
    const r = DataManifestSchema.safeParse(raw);
    const msg = r.success
      ? ''
      : r.error.issues.slice(0, 8).map((i) => `[${i.path.join('.')}] ${i.message}`).join('\n');
    expect(r.success, msg).toBe(true);
  });

  it('every top-level public/data/*.json is listed with a valid UTC ISO-8601 generated_at', () => {
    const m = DataManifestSchema.parse(raw);
    const missing = listTopLevelDataFiles().filter(
      (f) => !m.datasets[f] || !UTC_ISO.test(m.datasets[f].generated_at),
    );
    expect(missing, `Unlisted or unstamped: ${missing.join(', ')}`).toEqual([]);
  });

  it('lists no phantom datasets', () => {
    const m = DataManifestSchema.parse(raw);
    const onDisk = new Set(listTopLevelDataFiles());
    const phantom = Object.keys(m.datasets).filter((f) => !onDisk.has(f));
    expect(phantom, `Phantom entries: ${phantom.join(', ')}`).toEqual([]);
  });
});
