/**
 * Layer 4 — Assets and static files contract.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { MLB_TEAMS_METADATA, getTeamLogoUrl, getTeamColors } from '@/lib/teams';
import { MLB_TEAMS, PUBLIC_DIR, MATCHUPS_DIR, loadAllDatasets } from '../helpers/datasets';

describe('Assets & static team logos verification', () => {
  const { matchupsIndex } = loadAllDatasets();

  it('MLB_TEAMS_METADATA defines fullName, name, teamId, league, division, and hex colors for all 30 teams', () => {
    for (const abbr of MLB_TEAMS) {
      const meta = MLB_TEAMS_METADATA[abbr];
      expect(meta, `Missing metadata for ${abbr}`).toBeDefined();
      expect(meta.abbr).toBe(abbr);
      expect(meta.teamId).toBeGreaterThan(100);
      expect(meta.fullName.length).toBeGreaterThan(4);
      expect(meta.name.length).toBeGreaterThan(2);
      expect(meta.colors.primary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.secondary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.accent).toMatch(/^#[0-9A-Fa-f]{6}$/);

      const colors = getTeamColors(abbr);
      expect(colors.primary).toBe(meta.colors.primary);
    }
  });

  it('public/logos/<teamId>.png exists and is non-empty for all 30 MLB franchises', () => {
    for (const abbr of MLB_TEAMS) {
      const meta = MLB_TEAMS_METADATA[abbr];
      const logoPath = path.join(PUBLIC_DIR, 'logos', `${meta.teamId}.png`);
      expect(fs.existsSync(logoPath), `Logo file missing for ${abbr}: ${logoPath}`).toBe(true);
      const stat = fs.statSync(logoPath);
      expect(stat.size, `Logo file for ${abbr} is empty`).toBeGreaterThan(100);

      const url = getTeamLogoUrl(abbr);
      expect(url).toContain(`/logos/${meta.teamId}.png`);
    }
  });

  it('every available_weeks slate in matchups_index.json has a non-empty matchups/week-NN.json file on disk', () => {
    expect(fs.existsSync(MATCHUPS_DIR)).toBe(true);
    for (const w of matchupsIndex.available_weeks) {
      const fileName = `week-${String(w.week).padStart(2, '0')}.json`;
      const filePath = path.join(MATCHUPS_DIR, fileName);
      expect(fs.existsSync(filePath), `Matchup week file missing: ${filePath}`).toBe(true);
      const stat = fs.statSync(filePath);
      expect(stat.size, `Matchup week file ${fileName} is empty`).toBeGreaterThan(50);
    }
  });
});
