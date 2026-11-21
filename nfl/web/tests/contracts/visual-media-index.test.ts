/**
 * visual_media_index.json contract: the landing slideshow reads this file in the
 * browser, filtering by `generated_at` and timing GIF slides by `duration_ms`.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';

const PUBLIC_DIR = path.join(__dirname, '..', '..', 'public');
const items: Record<string, unknown>[] = JSON.parse(
  fs.readFileSync(path.join(PUBLIC_DIR, 'data', 'visual_media_index.json'), 'utf-8'),
);
const REQUIRED = ['filename', 'title', 'category', 'description', 'type', 'size_bytes', 'generated_at'];

describe('visual_media_index.json', () => {
  it('is a non-empty array', () => {
    expect(Array.isArray(items)).toBe(true);
    expect(items.length).toBeGreaterThan(0);
  });

  it('every item has filename, title, category, description, type, size_bytes, generated_at', () => {
    const bad = items.filter((i) => REQUIRED.some((k) => i[k] === undefined || i[k] === null || i[k] === ''));
    expect(bad.map((i) => i.filename)).toEqual([]);
  });

  it('generated_at matches ISO-8601 UTC seconds', () => {
    const bad = items.filter((i) => !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(String(i.generated_at)));
    expect(bad.map((i) => i.filename)).toEqual([]);
  });

  it('gif items have duration_ms that is a positive integer or null', () => {
    const gifs = items.filter((i) => i.type === 'gif');
    expect(gifs.length).toBeGreaterThan(0);
    const bad = gifs.filter(
      (i) => !(i.duration_ms === null || (Number.isInteger(i.duration_ms) && (i.duration_ms as number) > 0)),
    );
    expect(bad.map((i) => i.filename)).toEqual([]);
  });

  it('non-gif items carry no duration_ms', () => {
    const bad = items.filter((i) => i.type !== 'gif' && i.duration_ms !== undefined && i.duration_ms !== null);
    expect(bad.map((i) => i.filename)).toEqual([]);
  });

  it('no item uses the placeholder description', () => {
    const bad = items.filter((i) => String(i.description).includes('Pipeline generated visual artifact.'));
    expect(bad.map((i) => i.filename)).toEqual([]);
  });

  it('every filename exists in public/animations', () => {
    const missing = items.filter((i) => !fs.existsSync(path.join(PUBLIC_DIR, 'animations', String(i.filename))));
    expect(missing.map((i) => i.filename)).toEqual([]);
  });
});
