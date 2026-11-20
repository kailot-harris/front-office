/**
 * Sidecar data manifest contract (front-office#102, gate: front-office#191).
 *
 * web/public/data/data_manifest.json must parse against a strict Zod schema
 * and list exactly the top-level public/data/*.json payloads on disk (both
 * directions), each with a UTC ISO-8601 generated_at.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { z } from 'zod';
import { DATA_DIR, DATA_MANIFEST_FILE } from '../helpers/datasets';

const UTC_ISO = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const YMD = /^\d{4}-\d{2}-\d{2}$/;

const DatasetEntrySchema = z
  .object({
    file: z.string().regex(/^[^\/\\]+\.json$/),
    generated_at: z.string().regex(UTC_ISO),
    // FO#102: payload-embedded stamp or content-hash carry-forward only;
    // never file mtime, git history, or a sibling payload's stamp.
    stamp_source: z.string().regex(/^(payload:.+|manifest:content_hash)$/),
    content_sha256: z.string().regex(/^[0-9a-f]{64}$/).nullable(),
    // FO#191: through_date comes from game dates in the payload content.
    through_date: z.string().regex(YMD).nullable(),
    through_date_source: z.string().regex(/^(payload:.+|not_game_dated)$/),
    coverage_note: z.string().min(1).nullable(),
    static: z.boolean(),
    static_reason: z.string().min(1).nullable(),
    builder: z.string().min(1),
  })
  .strict()
  .refine((e) => !e.static || (e.static_reason ?? '').trim().length > 0, {
    message: 'static: true requires a non-empty static_reason',
  })
  .refine(
    (e) =>
      e.through_date_source === 'not_game_dated'
        ? e.through_date === null && (e.coverage_note ?? '').length > 0
        : e.through_date !== null,
    { message: 'through_date must be extracted from payload content, or null with a coverage_note' },
  )
  .refine((e) => e.stamp_source !== 'manifest:content_hash' || e.content_sha256 !== null, {
    message: 'content-hash stamps require content_sha256',
  });

export const DataManifestSchema = z
  .object({
    schema_version: z.literal(1),
    sport: z.literal('mlb'),
    generated_at: z.string().regex(UTC_ISO),
    schedule_through_date: z.string().regex(YMD).nullable(),
    datasets: z.array(DatasetEntrySchema).min(1),
  })
  .strict();

function topLevelPayloads(): string[] {
  return fs
    .readdirSync(DATA_DIR)
    .filter((f) => f.endsWith('.json') && f !== DATA_MANIFEST_FILE)
    .sort();
}

describe('data_manifest.json sidecar', () => {
  const fullPath = path.join(DATA_DIR, DATA_MANIFEST_FILE);

  it('exists and parses', () => {
    expect(fs.existsSync(fullPath), `Missing ${fullPath}`).toBe(true);
    expect(() => JSON.parse(fs.readFileSync(fullPath, 'utf-8'))).not.toThrow();
  });

  const manifest = JSON.parse(fs.readFileSync(fullPath, 'utf-8')) as unknown;

  it('matches DataManifestSchema', () => {
    const r = DataManifestSchema.safeParse(manifest);
    expect(r.success, r.success ? '' : JSON.stringify(r.error.issues.slice(0, 8), null, 2)).toBe(true);
  });

  const parsed = DataManifestSchema.safeParse(manifest);
  const files = parsed.success ? parsed.data.datasets.map((d) => d.file) : [];

  it('has no duplicate entries', () => {
    expect(new Set(files).size).toBe(files.length);
  });

  it('every top-level public/data json is listed and stamped', () => {
    const unlisted = topLevelPayloads().filter((f) => !files.includes(f));
    expect(unlisted, `Unlisted in manifest: ${unlisted.join(', ')}`).toEqual([]);
  });

  it('every manifest entry exists on disk', () => {
    const onDisk = new Set(topLevelPayloads());
    const ghosts = files.filter((f) => !onDisk.has(f));
    expect(ghosts, `Listed but absent: ${ghosts.join(', ')}`).toEqual([]);
  });

  it('generated_at stamps are real UTC instants', () => {
    if (!parsed.success) throw new Error('manifest failed schema');
    for (const d of [parsed.data, ...parsed.data.datasets]) {
      expect(Number.isNaN(Date.parse(d.generated_at)), d.generated_at).toBe(false);
    }
  });

  it('schema rejects unstamped, mtime/sibling-stamped, unexplained static, and generated_at-derived coverage entries', () => {
    const base = {
      schema_version: 1,
      sport: 'mlb',
      generated_at: '2026-01-01T00:00:00Z',
      schedule_through_date: null,
      datasets: [
        {
          file: 'x.json',
          generated_at: '2026-01-01T00:00:00Z',
          stamp_source: 'payload:generated_at',
          content_sha256: null as string | null,
          through_date: '2026-01-01' as string | null,
          through_date_source: 'payload:games[].game_date',
          coverage_note: null as string | null,
          static: false,
          static_reason: null,
          builder: 'tools/write_data_manifest.R',
        },
      ],
    };
    expect(DataManifestSchema.safeParse(base).success).toBe(true);
    const unstamped = structuredClone(base);
    (unstamped.datasets[0] as Record<string, unknown>).generated_at = '2026-01-01 00:00:00';
    expect(DataManifestSchema.safeParse(unstamped).success).toBe(false);
    const staticNoReason = structuredClone(base);
    staticNoReason.datasets[0].static = true;
    expect(DataManifestSchema.safeParse(staticNoReason).success).toBe(false);
    const mtime = structuredClone(base);
    mtime.datasets[0].stamp_source = 'file_mtime';
    expect(DataManifestSchema.safeParse(mtime).success).toBe(false);
    const sibling = structuredClone(base);
    sibling.datasets[0].stamp_source = 'sibling:projections_models_metadata.json';
    expect(DataManifestSchema.safeParse(sibling).success).toBe(false);
    const undatedWithDate = structuredClone(base);
    undatedWithDate.datasets[0].through_date_source = 'not_game_dated';
    expect(DataManifestSchema.safeParse(undatedWithDate).success).toBe(false);
    undatedWithDate.datasets[0].through_date = null;
    undatedWithDate.datasets[0].coverage_note = 'catalog; no game dates';
    expect(DataManifestSchema.safeParse(undatedWithDate).success).toBe(true);
  });
});
