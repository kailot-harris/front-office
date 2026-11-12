import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WNBA_TEAMS_METADATA, getTeamLogoUrl, getTeamColors } from '@/lib/teams';
import { BASE_PATH } from '@/lib/basePath';
import { PUBLIC_DIR, LOGOS_DIR, MEDIA_DIR, WNBA_TEAMS } from '../helpers/datasets';

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

describe('Static logo & image assets contract', () => {
  it('public/logos directory exists and has all 15 WNBA team logos mapped via getTeamLogoUrl()', () => {
    expect(fs.existsSync(LOGOS_DIR)).toBe(true);

    for (const abbr of WNBA_TEAMS) {
      const url = getTeamLogoUrl(abbr);
      expect(url, `getTeamLogoUrl(${abbr}) returned empty`).toBeTruthy();
      expect(url).toBe(`${BASE_PATH}/logos/${abbr}_logo.png`);

      const relativePath = url.startsWith(BASE_PATH) ? url.slice(BASE_PATH.length) : url;
      const filePath = path.join(PUBLIC_DIR, relativePath);
      expect(fs.existsSync(filePath), `Logo file missing: ${filePath}`).toBe(true);

      const stat = fs.statSync(filePath);
      expect(
        stat.size,
        `${abbr}_logo.png is suspiciously small (${stat.size} bytes)`
      ).toBeGreaterThan(500);

      const buf = fs.readFileSync(filePath);
      const header = buf.subarray(0, 8);
      expect(
        header.equals(PNG_MAGIC),
        `${abbr}_logo.png does not start with valid PNG magic bytes`
      ).toBe(true);
    }
  });

  it('WNBA_TEAMS_METADATA defines non-empty fullName, name, espnCode, and hex colors for all 15 teams', () => {
    for (const abbr of WNBA_TEAMS) {
      const meta = WNBA_TEAMS_METADATA[abbr];
      expect(meta, `Missing WNBA_TEAMS_METADATA[${abbr}]`).toBeDefined();
      expect(meta.abbr).toBe(abbr);
      expect(meta.fullName.length).toBeGreaterThan(4);
      expect(meta.name.length).toBeGreaterThan(2);
      expect(meta.espnCode.length).toBeGreaterThanOrEqual(2);
      expect(meta.colors.primary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.secondary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.accent).toMatch(/^#[0-9A-Fa-f]{6}$/);

      const colors = getTeamColors(abbr);
      expect(colors.primary).toBe(meta.colors.primary);
    }
  });
});

const GIF_MAGIC = Buffer.from('GIF89a', 'ascii');

/**
 * The net-rating trajectory media pair (issue #96).
 *
 * The bracket page renders this chart only when BOTH files are on disk, because
 * the <picture> serves the PNG to `prefers-reduced-motion` readers and the GIF to
 * everyone else — shipping one without the other shows a broken image to exactly
 * the audience that asked for less motion. The generator
 * (tools/build_net_rating_trajectory_gif.R) writes the pair or neither, and this
 * test is what stops a half-committed pair from reaching the site.
 *
 * Deliberately a PAIRED assertion, not two independent `existsSync` checks: the
 * media is a generated artifact produced outside the daily pipeline, so a
 * checkout with neither file is legitimate (the page just omits the chart) while
 * a checkout with exactly one is always a mistake.
 */
describe('Net-rating trajectory media pair contract', () => {
  const season = 2026;
  const gif = path.join(MEDIA_DIR, `net_rating_trajectory_${season}.gif`);
  const png = path.join(MEDIA_DIR, `net_rating_trajectory_${season}.png`);

  it('ships the animation and its reduced-motion still together, or neither', () => {
    const hasGif = fs.existsSync(gif);
    const hasPng = fs.existsSync(png);
    expect(
      hasGif,
      hasPng
        ? `Reduced-motion still exists but the animation is missing: ${gif}`
        : `Animation exists but the reduced-motion still is missing: ${png}`
    ).toBe(hasPng);
  });

  it('both files are real, non-trivial images when present', () => {
    if (!fs.existsSync(gif)) return; // neither-present is a valid checkout

    const gifBuf = fs.readFileSync(gif);
    expect(
      gifBuf.subarray(0, 6).equals(GIF_MAGIC),
      'net_rating_trajectory GIF does not start with GIF89a magic bytes'
    ).toBe(true);
    expect(gifBuf.length, 'trajectory GIF is suspiciously small').toBeGreaterThan(10_000);

    const pngBuf = fs.readFileSync(png);
    expect(
      pngBuf.subarray(0, 8).equals(PNG_MAGIC),
      'net_rating_trajectory still does not start with valid PNG magic bytes'
    ).toBe(true);
    expect(pngBuf.length, 'trajectory still is suspiciously small').toBeGreaterThan(5_000);
  });
});

/**
 * The 12 WNBA gallery charts (issue #147, phase 4), one per `*_GALLERY_ITEMS` entry in
 * GalleryClient.tsx. Each is rendered by `render_animated_artifact()` to a GIF/PNG pair in
 * `cache/` and mirrored to `web/public/media/`, except `gif_finals_closing_stretch`, which
 * legitimately has neither file yet because wehoop has not ingested that game's play-by-play
 * data — the chart is cataloged so its gallery entry appears once the data lands and the
 * script is re-run, but a checkout with neither file for that one chart is not a failure.
 *
 * Deliberately a PAIRED assertion per chart, not independent `existsSync` checks, for the same
 * reason as the net-rating trajectory contract above: the <picture> element in GalleryClient.tsx
 * serves the PNG to `prefers-reduced-motion` readers and the GIF to everyone else, so shipping
 * one without the other breaks exactly the audience that asked for less motion.
 */
describe('Gallery chart media pair contract', () => {
  const galleryChartIds = [
    'gif_elo_rank_bump',
    'gif_point_diff_race',
    'gif_standings_race',
    'gif_net_rating_quadrant',
    'gif_pace_efficiency_quadrant',
    'gif_shot_profile_shift',
    'gif_rapm_leaders_2026',
    'gif_rapm_leaders_by_season',
    'gif_upset_timeline',
    'gif_forecast_calibration',
    'gif_playoff_bracket_progression',
    'gif_finals_closing_stretch',
  ];

  it.each(galleryChartIds)('%s ships its GIF and PNG together, or neither', (chartId) => {
    const gif = path.join(MEDIA_DIR, `${chartId}.gif`);
    const png = path.join(MEDIA_DIR, `${chartId}.png`);
    const hasGif = fs.existsSync(gif);
    const hasPng = fs.existsSync(png);
    expect(
      hasGif,
      hasPng
        ? `Reduced-motion still exists but the animation is missing: ${gif}`
        : `Animation exists but the reduced-motion still is missing: ${png}`
    ).toBe(hasPng);
  });

  it.each(galleryChartIds)('%s is a real, non-trivial image pair when present', (chartId) => {
    const gif = path.join(MEDIA_DIR, `${chartId}.gif`);
    const png = path.join(MEDIA_DIR, `${chartId}.png`);
    if (!fs.existsSync(gif)) return; // neither-present is a valid checkout (e.g. gif_finals_closing_stretch)

    const gifBuf = fs.readFileSync(gif);
    expect(gifBuf.length, `${chartId}.gif is suspiciously small`).toBeGreaterThan(0);
    expect(
      gifBuf.subarray(0, 6).equals(GIF_MAGIC),
      `${chartId}.gif does not start with GIF89a magic bytes`
    ).toBe(true);

    const pngBuf = fs.readFileSync(png);
    expect(pngBuf.length, `${chartId}.png is suspiciously small`).toBeGreaterThan(0);
    expect(
      pngBuf.subarray(0, 8).equals(PNG_MAGIC),
      `${chartId}.png does not start with valid PNG magic bytes`
    ).toBe(true);
  });
});
