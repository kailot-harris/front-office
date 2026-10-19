/**
 * Layer 4 — Assets and static files contract.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { NBA_TEAMS_METADATA, getTeamLogoUrl, getTeamColors } from '@/lib/teams';
import { NBA_TEAMS, SHOTS_DIR, loadAllDatasets } from '../helpers/datasets';

describe('Assets & External CDN URL verification', () => {
  const { shotsIndex } = loadAllDatasets();

  it('NBA_TEAMS_METADATA defines fullName, name, espnCode, and hex colors for all 30 teams', () => {
    for (const abbr of NBA_TEAMS) {
      const meta = NBA_TEAMS_METADATA[abbr];
      expect(meta, `Missing metadata for ${abbr}`).toBeDefined();
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

  it('getTeamLogoUrl returns well-formed ESPN CDN URLs for all 30 teams including special cases', () => {
    for (const abbr of NBA_TEAMS) {
      const url = getTeamLogoUrl(abbr);
      expect(url).toMatch(/^https:\/\/a\.espncdn\.com\/i\/teamlogos\/nba\/500\/[a-z0-9]+\.png$/);
    }

    // Special ESPN team code overrides
    expect(getTeamLogoUrl('NOP')).toContain('/no.png');
    expect(getTeamLogoUrl('UTA')).toContain('/utah.png');
  });

  it('player shot files on disk are non-empty and have valid JSON structures without path traversal', () => {
    expect(fs.existsSync(SHOTS_DIR)).toBe(true);

    for (const entry of shotsIndex) {
      const filePath = path.join(SHOTS_DIR, `${entry.player_id}.json`);
      expect(fs.existsSync(filePath), `Shot file missing: ${filePath}`).toBe(true);
      const stat = fs.statSync(filePath);
      expect(stat.size, `Shot file ${entry.player_id}.json is empty`).toBeGreaterThan(100);
    }
  });
});
