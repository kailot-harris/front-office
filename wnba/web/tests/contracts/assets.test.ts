import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { WNBA_TEAMS_METADATA, getTeamLogoUrl, getTeamColors } from '@/lib/teams';
import { PUBLIC_DIR, LOGOS_DIR, WNBA_TEAMS } from '../helpers/datasets';

const PNG_MAGIC = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

describe('Static logo & image assets contract', () => {
  it('public/logos directory exists and has all 15 WNBA team logos mapped via getTeamLogoUrl()', () => {
    expect(fs.existsSync(LOGOS_DIR)).toBe(true);

    for (const abbr of WNBA_TEAMS) {
      const url = getTeamLogoUrl(abbr);
      expect(url, `getTeamLogoUrl(${abbr}) returned empty`).toBeTruthy();
      expect(url).toBe(`/logos/${abbr}_logo.png`);

      const filePath = path.join(PUBLIC_DIR, url);
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
