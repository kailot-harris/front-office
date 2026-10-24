import fs from 'fs';
import { describe, it, expect } from 'vitest';
import { WNBA_TEAMS_METADATA } from '@/lib/teams';
import {
  WNBA_TEAMS,
  SHOTS_DIR,
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
    playoffBracket2026,
    shotsIndex,
  } = loadAllDatasets();

  it('all 15 canonical team abbreviations appear identically across teams, cbaCapSheet, coaches, offseasonTeams, playoffSeries, and WNBA_TEAMS_METADATA', () => {
    const canonical = [...WNBA_TEAMS].sort();
    expect(teams.map((t) => t.team).sort()).toEqual(canonical);
    expect(cbaCapSheet.teams.map((t) => t.teamAbbr).sort()).toEqual(canonical);
    expect(coaches.map((c) => c.teamAbbr).sort()).toEqual(canonical);
    expect(offseasonTeams.map((t) => t.team).sort()).toEqual(canonical);
    expect(Object.keys(playoffSeries.teams).sort()).toEqual(canonical);
    expect(Object.keys(WNBA_TEAMS_METADATA).sort()).toEqual(canonical);
  });

  it('conference assignments (East vs West) agree across all team-level datasets and WNBA_TEAMS_METADATA', () => {
    const byTeam = new Map(teams.map((t) => [t.team, t.conference]));
    for (const abbr of WNBA_TEAMS) {
      const conf = byTeam.get(abbr);
      expect(WNBA_TEAMS_METADATA[abbr].conference, `${abbr} metadata conference`).toBe(conf);
      const cbaTeam = cbaCapSheet.teams.find((t) => t.teamAbbr === abbr)!;
      expect(cbaTeam.conference, `${abbr} cba conference`).toBe(conf);
      const offTeam = offseasonTeams.find((t) => t.team === abbr)!;
      expect(offTeam.conference, `${abbr} offseason conference`).toBe(conf);
      const poTeam = playoffSeries.teams[abbr];
      expect(poTeam.conference, `${abbr} playoffSeries conference`).toBe(conf);
    }
  });

  it('full franchise display names (team_name / teamName) agree with canonical WNBA_TEAMS_METADATA[team].fullName across all team datasets', () => {
    const mismatches: string[] = [];
    for (const abbr of WNBA_TEAMS) {
      const expectedFull = WNBA_TEAMS_METADATA[abbr].fullName;
      const expectedShort = WNBA_TEAMS_METADATA[abbr].name;
      const seasonTeam = teams.find((t) => t.team === abbr)!;
      if (seasonTeam.team_name !== expectedFull && seasonTeam.team_name !== expectedShort) {
        mismatches.push(
          `projections_season_teams.json[${abbr}].team_name = "${seasonTeam.team_name}" (expected "${expectedFull}" or "${expectedShort}")`
        );
      }
      const cbaTeam = cbaCapSheet.teams.find((t) => t.teamAbbr === abbr)!;
      if (cbaTeam.teamName !== expectedFull) {
        mismatches.push(
          `cba_cap_sheet.json[${abbr}].teamName = "${cbaTeam.teamName}" (expected "${expectedFull}")`
        );
      }
      const coachTeam = coaches.find((c) => c.teamAbbr === abbr)!;
      if (coachTeam.teamName !== expectedFull) {
        mismatches.push(
          `coaching_metrics.json[${abbr}].teamName = "${coachTeam.teamName}" (expected "${expectedFull}")`
        );
      }
      const offTeam = offseasonTeams.find((t) => t.team === abbr)!;
      if (offTeam.team_name !== expectedFull) {
        mismatches.push(
          `offseason_teams.json[${abbr}].team_name = "${offTeam.team_name}" (expected "${expectedFull}")`
        );
      }
      const poTeam = playoffSeries.teams[abbr];
      if (poTeam.teamName !== expectedFull) {
        mismatches.push(
          `playoff_series_matchups.json[${abbr}].teamName = "${poTeam.teamName}" (expected "${expectedFull}")`
        );
      }
    }
    expect(
      mismatches,
      `Franchise display name drift across team datasets:\n  • ${mismatches.join('\n  • ')}`
    ).toEqual([]);
  });

  it('playoff_bracket_2026.json abbreviations and full names resolve against WNBA_TEAMS_METADATA', () => {
    const canonical = new Set<string>([...WNBA_TEAMS]);
    const mismatches: string[] = [];

    const checkTeam = (abbr: string, fullName: string, where: string) => {
      if (!canonical.has(abbr)) {
        mismatches.push(`${where}: "${abbr}" is not a canonical WNBA abbreviation`);
        return;
      }
      const expectedFull = WNBA_TEAMS_METADATA[abbr as keyof typeof WNBA_TEAMS_METADATA].fullName;
      if (fullName !== expectedFull) {
        mismatches.push(`${where}: ${abbr} full name = "${fullName}" (expected "${expectedFull}")`);
      }
    };

    for (const s of playoffBracket2026.series) {
      const where = `playoff_bracket_2026.json[${s.round}] ${s.teamA} vs ${s.teamB}`;
      checkTeam(s.teamA, s.teamNameA, where);
      checkTeam(s.teamB, s.teamNameB, where);
      checkTeam(s.winner, s.winnerName, `${where} winner`);

      // Every game must be between the two teams the series says it is between.
      for (const g of s.games) {
        for (const abbr of [g.teamA, g.teamB]) {
          if (abbr !== s.teamA && abbr !== s.teamB) {
            mismatches.push(`${where}: game on ${g.gameDate} involves ${abbr}, not a series participant`);
          }
        }
      }

      // The prediction's two sides must be the same two teams as the result's.
      const f = s.prediction.forecast;
      if (f) {
        const predicted = [f.teamHigh, f.teamLow].sort();
        const actual = [s.teamNameA, s.teamNameB].sort();
        if (predicted[0] !== actual[0] || predicted[1] !== actual[1]) {
          mismatches.push(
            `${where}: prediction covers ${predicted.join(' / ')} but the series is ${actual.join(' / ')}`
          );
        }
      }
    }

    expect(
      mismatches,
      `playoff_bracket_2026.json referential drift:\n  • ${mismatches.join('\n  • ')}`
    ).toEqual([]);
  });

  it('playoff_bracket_2026.json teams are a subset of the playoff_series_matchups.json team profiles', () => {
    const profileAbbrs = new Set(Object.keys(playoffSeries.teams));
    const bracketAbbrs = new Set<string>();
    for (const s of playoffBracket2026.series) {
      bracketAbbrs.add(s.teamA);
      bracketAbbrs.add(s.teamB);
    }
    const missing = [...bracketAbbrs].filter((a) => !profileAbbrs.has(a));
    expect(
      missing,
      `playoff_bracket_2026.json references teams with no playoff_series_matchups.json profile: ${missing.join(', ')}`
    ).toEqual([]);
  });

  it('projections_models_metadata.json teams_count and players_count match the actual array lengths', () => {
    expect(metadata.teams_count).toBe(teams.length);
    expect(metadata.players_count).toBe(players.length);
  });

  it('player datasets (players, clutch, defense, playerDna) share the exact same 221-player roster pool (playerId, playerName, team, position)', () => {
    expect(clutch).toHaveLength(players.length);
    expect(defense).toHaveLength(players.length);
    expect(playerDna).toHaveLength(players.length);

    const playerById = new Map(players.map((p) => [p.player_id, p]));
    for (const c of clutch) {
      const base = playerById.get(c.playerId);
      expect(base, `Clutch player ${c.playerId} (${c.playerName}) missing in players`).toBeDefined();
      expect(c.playerName).toBe(base!.player_name);
      expect(c.team).toBe(base!.team);
      expect(c.position).toBe(base!.position);
    }
    for (const d of defense) {
      const base = playerById.get(d.playerId);
      expect(base, `Defense player ${d.playerId} (${d.playerName}) missing in players`).toBeDefined();
      expect(d.playerName).toBe(base!.player_name);
      expect(d.team).toBe(base!.team);
      expect(d.position).toBe(base!.position);
    }
    for (const dna of playerDna) {
      const base = playerById.get(dna.playerId);
      expect(base, `PlayerDNA ${dna.playerId} (${dna.playerName}) missing in players`).toBeDefined();
      expect(dna.playerName).toBe(base!.player_name);
      expect(dna.team).toBe(base!.team);
      expect(dna.position).toBe(base!.position);
    }
  });

  it('every entry in shots_index.json has a corresponding public/data/shots/<player_id>.json file on disk and no orphan shot files exist', () => {
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

  it('team projected ensemble wins agree across projections_season_teams, coaching_metrics, and playoff_series_matchups', () => {
    const teamMap = new Map(teams.map((t) => [t.team, t]));
    for (const abbr of WNBA_TEAMS) {
      const base = teamMap.get(abbr)!;
      const coach = coaches.find((c) => c.teamAbbr === abbr)!;
      const po = playoffSeries.teams[abbr];

      expect(
        coach.metrics.actualProjectedWins,
        `${abbr} coach.metrics.actualProjectedWins`
      ).toBeCloseTo(base.ensemble_mean_wins, 1);
      expect(po.regularWins, `${abbr} playoffSeries.regularWins`).toBeCloseTo(
        base.ensemble_mean_wins,
        1
      );
    }
  });

  it('offseason_draft.json team abbreviations are valid WNBA teams', () => {
    const teamSet = new Set<string>(WNBA_TEAMS);
    for (const pick of offseasonDraft) {
      expect(teamSet.has(pick.team)).toBe(true);
    }
  });
});
