/**
 * Layer 3 — Cross-dataset referential integrity & asset contracts.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import { MLB_TEAMS_METADATA, getTeamLogoUrl, getTeamColors } from '@/lib/teams';
import {
  MLB_TEAMS,
  LOGOS_DIR,
  loadAllDatasets,
} from '../helpers/datasets';

describe('Cross-dataset referential integrity', () => {
  const {
    teams,
    players,
    metadata,
    cbtSheet,
    clutch,
    playerDna,
    playoffSeries,
    postseasonOps,
  } = loadAllDatasets();

  it('all 30 canonical MLB team abbreviations appear across teams, cbtSheet, playoffSeries, bullpen_status, and MLB_TEAMS_METADATA', () => {
    const canonical = [...MLB_TEAMS].sort();
    expect(teams.map((t) => t.team).sort()).toEqual(canonical);
    expect(cbtSheet.teams.map((t) => t.teamAbbr).sort()).toEqual(canonical);
    expect(Object.keys(playoffSeries.teams).sort()).toEqual(canonical);
    expect(postseasonOps.bullpen_status.map((b) => b.team).sort()).toEqual(canonical);
    for (const abbr of canonical) {
      expect(MLB_TEAMS_METADATA[abbr], `MLB_TEAMS_METADATA[${abbr}]`).toBeDefined();
    }
  });

  it('league and division assignments agree across team-level datasets and MLB_TEAMS_METADATA', () => {
    const byTeam = new Map(teams.map((t) => [t.team, t]));
    for (const abbr of MLB_TEAMS) {
      const base = byTeam.get(abbr)!;
      const meta = MLB_TEAMS_METADATA[abbr];
      const cbtTeam = cbtSheet.teams.find((t) => t.teamAbbr === abbr)!;
      const poTeam = playoffSeries.teams[abbr];
      const bpTeam = postseasonOps.bullpen_status.find((b) => b.team === abbr)!;

      expect(base.league, `${abbr} league vs metadata`).toBe(meta.league);
      expect(base.division, `${abbr} division vs metadata`).toBe(meta.division);
      expect(cbtTeam.league, `${abbr} cbt league`).toBe(base.league);
      expect(cbtTeam.division, `${abbr} cbt division`).toBe(base.division);
      expect(poTeam.league, `${abbr} playoffSeries league`).toBe(base.league);
      expect(poTeam.division, `${abbr} playoffSeries division`).toBe(base.division);
      expect(bpTeam.league, `${abbr} bullpen league`).toBe(base.league);
      expect(bpTeam.division, `${abbr} bullpen division`).toBe(base.division);
    }
  });

  it('projections_models_metadata.json counts match actual dataset lengths', () => {
    expect(metadata.teams_count).toBe(teams.length);
    expect(metadata.players_count).toBe(players.length);
    const batters = players.filter((p) => p.player_type === 'Batter').length;
    const pitchers = players.filter((p) => p.player_type === 'Pitcher').length;
    expect(metadata.batters_count).toBe(batters);
    expect(metadata.pitchers_count).toBe(pitchers);
  });

  it('clutch and playerDna catalog total counts match their profiles array lengths', () => {
    expect(clutch.totalProfiles).toBe(clutch.profiles.length);
    expect(playerDna.totalPlayers).toBe(playerDna.profiles.length);
  });

  it('team logos and hex color metadata are valid for all 30 franchises', () => {
    for (const abbr of MLB_TEAMS) {
      const meta = MLB_TEAMS_METADATA[abbr];
      expect(meta.colors.primary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.secondary).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(meta.colors.accent).toMatch(/^#[0-9A-Fa-f]{6}$/);
      expect(getTeamColors(abbr).primary).toBe(meta.colors.primary);
      expect(getTeamLogoUrl(abbr)).toContain(`/logos/${meta.teamId}.png`);
      const logoFile = path.join(LOGOS_DIR, `${meta.teamId}.png`);
      expect(fs.existsSync(logoFile), `Missing logo file: ${logoFile}`).toBe(true);
    }
  });
});
