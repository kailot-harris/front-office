/**
 * Layer 4 — static asset integrity.
 *
 * /gallery renders straight from `visual_media_index.json`, so an index entry
 * without a matching file on disk is a broken <img> in production. The reverse
 * (a file nothing references) is dead weight in the deployed bundle.
 */
import { describe, expect, it } from 'vitest';
import fs from 'fs';
import path from 'path';
import { ANIMATIONS_DIR, REPO_WEB_ROOT, media, qbs } from '../helpers/datasets';

const nextConfig = fs.readFileSync(path.join(REPO_WEB_ROOT, 'next.config.mjs'), 'utf-8');

describe('gallery media index matches the files on disk', () => {
  const items = media();
  const onDisk = fs.readdirSync(ANIMATIONS_DIR);

  it('every indexed file exists in public/animations/', () => {
    const missing = items.filter((i) => !onDisk.includes(i.filename)).map((i) => `${i.filename} ("${i.title}")`);
    expect(missing, 'these gallery tiles would render a broken image').toEqual([]);
  });

  it('every file on disk is referenced by the index', () => {
    const referenced = new Set(items.map((i) => i.filename));
    const orphans = onDisk.filter((f) => !referenced.has(f));
    expect(orphans, 'unreferenced assets are shipped but unreachable from the UI').toEqual([]);
  });

  it('size_bytes matches the real file size', () => {
    const drifted = items
      .map((i) => ({ i, actual: fs.statSync(path.join(ANIMATIONS_DIR, i.filename)).size }))
      .filter(({ i, actual }) => Math.abs(actual - i.size_bytes) > 1024)
      .map(({ i, actual }) => `${i.filename}: index says ${i.size_bytes}, disk says ${actual}`);
    expect(drifted, 'the index is stale relative to the regenerated assets').toEqual([]);
  });

  it('declared type agrees with the file extension', () => {
    const mismatched = items
      .filter((i) => (i.filename.toLowerCase().endsWith('.gif') ? 'gif' : 'image') !== i.type)
      .map((i) => `${i.filename} declared type="${i.type}"`);
    expect(mismatched).toEqual([]);
  });

  it('filenames are unique', () => {
    const names = items.map((i) => i.filename);
    expect(names.filter((n, idx) => names.indexOf(n) !== idx)).toEqual([]);
  });

  it('titles are unique (the gallery keys tiles on them)', () => {
    const titles = items.map((i) => i.title);
    expect(titles.filter((t, idx) => titles.indexOf(t) !== idx)).toEqual([]);
  });

  it('no filename can escape public/animations/', () => {
    const unsafe = items.filter((i) => i.filename.includes('/') || i.filename.includes('\\') || i.filename.includes('..'));
    expect(unsafe.map((i) => i.filename)).toEqual([]);
  });

  it('every category is populated (no empty filter chip)', () => {
    const counts = new Map<string, number>();
    for (const i of items) counts.set(i.category, (counts.get(i.category) ?? 0) + 1);
    const empty = [...counts.entries()].filter(([, n]) => n === 0);
    expect(empty).toEqual([]);
    expect(counts.size, 'gallery has no categories to filter by').toBeGreaterThan(1);
  });

  it('every item carries a non-empty description', () => {
    expect(items.filter((i) => !i.description.trim()).map((i) => i.filename)).toEqual([]);
  });
});

describe('remote image hosts are allow-listed for next/image', () => {
  it('every QB headshot host appears in next.config.mjs remotePatterns', () => {
    const hosts = [...new Set(qbs().map((q) => new URL(q.headshot_url).host))];
    const missing = hosts.filter((h) => !nextConfig.includes(h));
    expect(
      missing,
      `next/image rejects un-listed hosts at runtime; add these to next.config.mjs: ${missing.join(', ')}`,
    ).toEqual([]);
  });

  it('the ESPN logo host used by lib/teams.ts is allow-listed', () => {
    expect(nextConfig).toContain('a.espncdn.com');
  });

  it('all remote images are https', () => {
    const insecure = qbs().filter((q) => !q.headshot_url.startsWith('https://')).map((q) => q.player_name);
    expect(insecure).toEqual([]);
  });
});

describe('app shell assets', () => {
  it('a favicon is present', () => {
    expect(fs.existsSync(path.join(REPO_WEB_ROOT, 'app', 'favicon.ico'))).toBe(true);
  });

  it('public/ contains no stray large file outside animations/ and data/', () => {
    const entries = fs.readdirSync(path.join(REPO_WEB_ROOT, 'public'), { withFileTypes: true });
    const unexpected = entries.filter((e) => e.isFile()).map((e) => e.name);
    expect(unexpected, 'loose files in public/ bypass the gallery index').toEqual([]);
  });
});
