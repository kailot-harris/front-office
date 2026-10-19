/**
 * Layer 3 — Cross-dataset referential integrity.
 */
import fs from 'fs';
import { describe, it, expect } from 'vitest';
import { NBA_TEAMS_METADATA } from '@/lib/teams';
import {
  NBA_TEAMS,
  SHOTS_DIR,
  LEAGUE,
  loadAllDatasets,
} from '../helpers/datasets';

describe('Cross-dataset referential integrity', () => {
  const {
    teams,
    players,
    metadata,
    cbaCapSheet,
    clutch,
    coaches,
    defense,
    playerDna,
    offseasonDraft,
    offseasonTeams,
    playoffSeries,
    shotsIndex,
  } = loadAllDatasets();

  it('all 30 canonical team abbreviations appear identically across teams, cbaCapSheet, coaches, offseasonTeams, playoffSeries, and NBA_TEAMS_METADATA', () => {
    const canonical = [...NBA_TEAMS].sort();
    expect(teams.map((t) => t.team).sort()).toEqual(canonical);
    expect(cbaCapSheet.teams.map((t) => t.teamAbbr).sort()).toEqual(canonical);
    expect(coaches.map((c) => c.teamAbbr).sort()).toEqual(canonical);
    expect(offseasonTeams.map((t) => t.team).sort()).toEqual(canonical);
    expect(Object.keys(playoffSeries.teams).sort()).toEqual(canonical);
    expect(Object.keys(NBA_TEAMS_METADATA).sort()).toEqual(canonical);
  });

  it('conference assignments (East vs West) agree across all team-level datasets and NBA_TEAMS_METADATA', () => {
    const byTeam = new Map(teams.map((t) => [t.team, t.conference]));
    for (const abbr of NBA_TEAMS) {
      const conf = byTeam.get(abbr);
      expect(conf, `Missing conference for ${abbr}`).toBeDefined();
      const cbaTeam = cbaCapSheet.teams.find((t) => t.teamAbbr === abbr)!;
      expect(cbaTeam.conference, `${abbr} cba conference`).toBe(conf);
      const offTeam = offseasonTeams.find((t) => t.team === abbr)!;
      expect(offTeam.conference, `${abbr} offseason conference`).toBe(conf);
      const poTeam = playoffSeries.teams[abbr];
      expect(poTeam.conference, `${abbr} playoffSeries conference`).toBe(conf);
    }
  });

  it('franchise mascot names (team_name / teamName) agree across team datasets and match NBA_TEAMS_METADATA[abbr].name', () => {
    for (const abbr of NBA_TEAMS) {
      const expectedName = NBA_TEAMS_METADATA[abbr].name;
      const seasonTeam = teams.find((t) => t.team === abbr)!;
      const cbaTeam = cbaCapSheet.teams.find((t) => t.teamAbbr === abbr)!;
      const coachTeam = coaches.find((c) => c.teamAbbr === abbr)!;
      const offTeam = offseasonTeams.find((t) => t.team === abbr)!;
      const poTeam = playoffSeries.teams[abbr];

      expect(seasonTeam.team_name, `season team name for ${abbr}`).toBe(expectedName);
      expect(cbaTeam.teamName, `cba team name for ${abbr}`).toBe(expectedName);
      expect(coachTeam.teamName, `coach team name for ${abbr}`).toBe(expectedName);
      expect(offTeam.team_name, `offseason team name for ${abbr}`).toBe(expectedName);
      expect(poTeam.teamName, `playoff series team name for ${abbr}`).toBe(expectedName);
    }
  });

  it('projections_models_metadata.json teams_count and players_count match actual dataset array lengths', () => {
    expect(metadata.teams_count).toBe(teams.length);
    expect(metadata.players_count).toBe(players.length);
  });

  it('player datasets (players, clutch, defense, playerDna) share the exact same 330-player roster pool', () => {
    expect(clutch).toHaveLength(players.length);
    expect(defense).toHaveLength(players.length);
    expect(playerDna).toHaveLength(players.length);

    const playerById = new Map(players.map((p) => [p.player_id, p]));
    for (const c of clutch) {
      const base = playerById.get(c.playerId);
      expect(base, `Clutch player ${c.playerId} missing in players`).toBeDefined();
      expect(c.playerName).toBe(base!.player_name);
      expect(c.team).toBe(base!.team);
      expect(c.position).toBe(base!.position);
    }
    for (const d of defense) {
      const base = playerById.get(d.playerId);
      expect(base, `Defense player ${d.playerId} missing in players`).toBeDefined();
      expect(d.playerName).toBe(base!.player_name);
      expect(d.team).toBe(base!.team);
      expect(d.position).toBe(base!.position);
    }
    for (const dna of playerDna) {
      const base = playerById.get(dna.playerId);
      expect(base, `PlayerDNA ${dna.playerId} missing in players`).toBeDefined();
      expect(dna.playerName).toBe(base!.player_name);
      expect(dna.team).toBe(base!.team);
      expect(dna.position).toBe(base!.position);
    }
  });

  it('every entry in shots_index.json has a corresponding public/data/shots/<player_id>.json file on disk and no orphans exist', () => {
    const indexIds = new Set(shotsIndex.map((s) => s.player_id));
    expect(indexIds.size).toBe(shotsIndex.length);

    const diskFiles = fs
      .readdirSync(SHOTS_DIR)
      .filter((f) => f.endsWith('.json'))
      .map((f) => f.replace(/\.json$/, ''));
    const diskIds = new Set(diskFiles);

    const missingOnDisk = [...indexIds].filter((id) => !diskIds.has(id));
    const orphanOnDisk = [...diskIds].filter((id) => !indexIds.has(id));

    expect(missingOnDisk, `Missing shot JSON files on disk: ${missingOnDisk.join(', ')}`).toEqual([]);
    expect(orphanOnDisk, `Orphan shot JSON files not in shots_index.json: ${orphanOnDisk.join(', ')}`).toEqual([]);
  });

  it('team projected wins agree across projections_season_teams, coaching_metrics, playoff_series_matchups, and offseason_teams', () => {
    const teamMap = new Map(teams.map((t) => [t.team, t]));
    for (const abbr of NBA_TEAMS) {
      const base = teamMap.get(abbr)!;
      const coach = coaches.find((c) => c.teamAbbr === abbr)!;
      const po = playoffSeries.teams[abbr];
      const off = offseasonTeams.find((t) => t.team === abbr)!;

      expect(coach.metrics.actualProjectedWins, `${abbr} coach actualProjectedWins`).toBeCloseTo(base.proj_wins, 1);
      expect(po.regularWins, `${abbr} playoffSeries regularWins`).toBeCloseTo(base.proj_wins, 1);
      expect(off.baseline_wins, `${abbr} offseason baseline_wins`).toBeCloseTo(base.proj_wins, 1);
    }
  });

  it('offseason_draft.json team and original_team abbreviations are valid NBA teams', () => {
    const teamSet = new Set<string>(NBA_TEAMS);
    for (const pick of offseasonDraft) {
      expect(teamSet.has(pick.team), `${pick.team} in draft pick ${pick.pick}`).toBe(true);
      if (pick.original_team) {
        expect(teamSet.has(pick.original_team), `${pick.original_team} in draft pick ${pick.pick}`).toBe(true);
      }
    }
  });
});
