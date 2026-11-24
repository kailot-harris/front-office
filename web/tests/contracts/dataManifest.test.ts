import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR, MANIFEST_FILE, listTopLevelDataFiles } from '../helpers/datasets';

// Contract for web/public/data/data_manifest.json (front-office#102 / #191).
const UtcIso = z.string().regex(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/, 'UTC ISO-8601 (YYYY-MM-DDTHH:MM:SSZ)');
const IsoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/);

const DatasetEntrySchema = z
  .object({
    file: z.string().regex(/^[^/\\]+\.json$/),
    generated_at: UtcIso,
    stamp_source: z.string().regex(/^(payload:.+|manifest:content_hash)$/),
    content_sha256: z.string().regex(/^[0-9a-f]{64}$/).nullable(),
    through_date: IsoDate.nullable(),
    through_date_source: z.string().regex(/^(payload:.+|not_game_dated)$/),
    coverage_note: z.string().min(1).nullable(),
    builder: z.string().min(1),
    static: z.boolean(),
    static_reason: z.string().min(1).optional(),
    lag_days: z.number().int().optional(),
    lifecycle: z.enum(['live', 'season_final', 'archived']).optional(),
    season: z.union([z.number().int(), z.string().min(1)]).optional(),
    final_through_date: IsoDate.optional(),
    frozen_sha256: z.string().regex(/^[0-9a-f]{64}$/).optional(),
    frozen_at: UtcIso.optional(),
  })
  .strict()
  .refine(
    (e) =>
      e.lifecycle !== 'season_final' ||
      (e.season !== undefined &&
        e.final_through_date !== undefined &&
        e.frozen_sha256 !== undefined &&
        e.frozen_at !== undefined),
    { message: 'season_final entries require season, final_through_date, frozen_sha256, and frozen_at' }
  )
  .refine(
    (e) =>
      e.through_date_source === 'not_game_dated'
        ? e.through_date === null && (e.coverage_note ?? '').trim().length > 0
        : e.through_date !== null,
    { message: 'not_game_dated needs null through_date + coverage_note; payload sources need a through_date' }
  )
  .refine((e) => !e.static || (e.static_reason ?? '').trim().length > 0, {
    message: 'static: true requires a non-empty static_reason',
  });

export const DataManifestSchema = z
  .object({
    schema_version: z.literal(1),
    sport: z.literal('wnba'),
    generated_at: UtcIso,
    schedule_through_date: IsoDate.nullable(),
    datasets: z.array(DatasetEntrySchema).min(1),
  })
  .strict();

const manifest = JSON.parse(fs.readFileSync(path.join(DATA_DIR, MANIFEST_FILE), 'utf-8'));

describe('data_manifest.json contract', () => {
  it('matches DataManifestSchema', () => {
    const r = DataManifestSchema.safeParse(manifest);
    expect(r.success, r.success ? '' : JSON.stringify(r.error.issues.slice(0, 5))).toBe(true);
  });

  it('lists every top-level public/data/*.json exactly once (no unlisted files)', () => {
    const listed: string[] = manifest.datasets.map((d: { file: string }) => d.file);
    expect(new Set(listed).size).toBe(listed.length);
    const unlisted = listTopLevelDataFiles().filter((f) => !listed.includes(f));
    expect(unlisted, `Unlisted in data_manifest.json: ${unlisted.join(', ')}`).toEqual([]);
    const phantom = listed.filter((f) => !listTopLevelDataFiles().includes(f));
    expect(phantom, `Listed but absent on disk: ${phantom.join(', ')}`).toEqual([]);
  });

  it('every listed dataset is stamped with a UTC generated_at', () => {
    const unstamped = manifest.datasets
      .filter((d: { generated_at?: unknown }) => !UtcIso.safeParse(d.generated_at).success)
      .map((d: { file: string }) => d.file);
    expect(unstamped).toEqual([]);
  });

  it('rejects an unstamped entry and a static entry without a reason', () => {
    const base = manifest.datasets[0];
    const bad1 = { ...manifest, datasets: [{ ...base, generated_at: '2026-10-30 12:00' }] };
    const bad2 = { ...manifest, datasets: [{ ...base, static: true, static_reason: undefined }] };
    expect(DataManifestSchema.safeParse(bad1).success).toBe(false);
    expect(DataManifestSchema.safeParse(bad2).success).toBe(false);
    const bad3 = { ...manifest, datasets: [{ ...base, stamp_source: 'file_mtime' }] };
    const bad4 = {
      ...manifest,
      datasets: [{ ...base, through_date: null, through_date_source: 'not_game_dated', coverage_note: null }],
    };
    expect(DataManifestSchema.safeParse(bad3).success).toBe(false);
    expect(DataManifestSchema.safeParse(bad4).success).toBe(false);
  });

  it('validates optional lifecycle values and requires season_final fields when lifecycle is season_final', () => {
    const base = {
      schema_version: 1 as const,
      sport: 'wnba' as const,
      generated_at: '2026-11-24T00:00:00Z',
      schedule_through_date: '2026-10-31',
      datasets: [
        {
          file: 'matchups_slates.json',
          generated_at: '2026-11-01T00:00:00Z',
          stamp_source: 'manifest:content_hash',
          content_sha256: 'e'.repeat(64),
          through_date: '2026-10-31',
          through_date_source: 'payload:schedule[].date',
          coverage_note: null as string | null,
          builder: 'tools/write_data_manifest.R',
          static: false,
        } as Record<string, unknown>,
      ],
    };

    expect(DataManifestSchema.safeParse(base).success).toBe(true);

    for (const lc of ['live', 'archived']) {
      const ok = structuredClone(base);
      ok.datasets[0].lifecycle = lc;
      expect(DataManifestSchema.safeParse(ok).success).toBe(true);
    }

    const badLc = structuredClone(base);
    badLc.datasets[0].lifecycle = 'stale';
    expect(DataManifestSchema.safeParse(badLc).success).toBe(false);

    const incompleteFrozen = structuredClone(base);
    incompleteFrozen.datasets[0].lifecycle = 'season_final';
    incompleteFrozen.datasets[0].season = 2026;
    expect(DataManifestSchema.safeParse(incompleteFrozen).success).toBe(false);

    const fullFrozen = structuredClone(base);
    fullFrozen.datasets[0].lifecycle = 'season_final';
    fullFrozen.datasets[0].season = 2026;
    fullFrozen.datasets[0].final_through_date = '2026-10-31';
    fullFrozen.datasets[0].frozen_sha256 = 'a'.repeat(64);
    fullFrozen.datasets[0].frozen_at = '2026-11-24T04:00:00Z';
    expect(DataManifestSchema.safeParse(fullFrozen).success).toBe(true);
  });
});
