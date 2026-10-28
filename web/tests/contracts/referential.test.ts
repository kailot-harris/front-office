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
    finalsGamePredictions,
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

  // --------------------------------------------------------------------------
  // finals_game_predictions_2026.json (GitHub issue #94)
  //
  // This payload names the same teams as the Finals row of the bracket payload,
  // from a different derivation path (seeds, not box-score round inference), so
  // the two agreeing is a real cross-check rather than a tautology.
  // --------------------------------------------------------------------------
  it('finals_game_predictions_2026.json teams resolve against WNBA_TEAMS_METADATA and match the bracket Finals row', () => {
    const f = finalsGamePredictions;
    const finalsRow = playoffBracket2026.series.find((s) => s.round === 'Finals');

    if (f.matchup === null) {
      // Empty state. Legitimate only when the bracket has no Finals row either.
      expect(finalsRow, 'no Finals forecast, but the bracket has a Finals row').toBeUndefined();
      return;
    }

    const canonical = new Set<string>([...WNBA_TEAMS]);
    const mismatches: string[] = [];

    for (const [abbr, fullName] of [
      [f.matchup.teamHighAbbr, f.matchup.teamHigh],
      [f.matchup.teamLowAbbr, f.matchup.teamLow],
    ] as const) {
      if (!canonical.has(abbr)) {
        mismatches.push(`"${abbr}" is not a canonical WNBA abbreviation`);
        continue;
      }
      const expectedFull =
        WNBA_TEAMS_METADATA[abbr as keyof typeof WNBA_TEAMS_METADATA].fullName;
      if (fullName !== expectedFull) {
        mismatches.push(`${abbr} full name = "${fullName}" (expected "${expectedFull}")`);
      }
    }

    // Every game's host must be one of the two Finals participants.
    for (const g of f.games) {
      if (g.hostAbbr !== f.matchup.teamHighAbbr && g.hostAbbr !== f.matchup.teamLowAbbr) {
        mismatches.push(`game ${g.game} host ${g.hostAbbr} is not a Finals participant`);
      }
      const expectedHostName = g.hostIsHighSeed ? f.matchup.teamHigh : f.matchup.teamLow;
      if (g.hostName !== expectedHostName) {
        mismatches.push(`game ${g.game} hostName "${g.hostName}" != "${expectedHostName}"`);
      }
    }

    // Same pairing as the bracket's Finals row, reached independently.
    if (finalsRow) {
      const forecasted = [f.matchup.teamHigh, f.matchup.teamLow].sort();
      const resolved = [finalsRow.teamNameA, finalsRow.teamNameB].sort();
      if (forecasted[0] !== resolved[0] || forecasted[1] !== resolved[1]) {
        mismatches.push(
          `per-game forecast covers ${forecasted.join(' / ')} but the bracket Finals is ${resolved.join(' / ')}`
        );
      }
      // Series state must agree across the two payloads.
      const bracketHighWins =
        finalsRow.teamA === f.matchup.teamHighAbbr ? finalsRow.winsA : finalsRow.winsB;
      if (bracketHighWins !== f.matchup.winsHigh) {
        mismatches.push(
          `wins for ${f.matchup.teamHighAbbr}: forecast says ${f.matchup.winsHigh}, bracket says ${bracketHighWins}`
        );
      }
      if (finalsRow.seriesComplete !== f.matchup.seriesComplete) {
        mismatches.push('seriesComplete disagrees between the two payloads');
      }
    }

    expect(
      mismatches,
      `finals_game_predictions_2026.json referential drift:\n  • ${mismatches.join('\n  • ')}`
    ).toEqual([]);
  });

  it('finals_game_predictions_2026.json teams have playoff_series_matchups.json profiles', () => {
    const f = finalsGamePredictions;
    if (f.matchup === null) return;
    const profileAbbrs = new Set(Object.keys(playoffSeries.teams));
    const missing = [f.matchup.teamHighAbbr, f.matchup.teamLowAbbr].filter(
      (a) => !profileAbbrs.has(a)
    );
    expect(
      missing,
      `finals_game_predictions_2026.json references teams with no profile: ${missing.join(', ')}`
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

describe('Cross-dataset referential integrity: matchups_slates.json', () => {
  const { matchups: m, metadata, teams } = loadAllDatasets();

  it('every team abbreviation and display name resolves against canonical WNBA_TEAMS_METADATA', () => {
    // The 2026 payload needs NO abbreviation fixup table -- the ESPN
    // abbreviations in the schedule cache, the box scores and this web app's
    // canonical set are identical. This test is what keeps that true: if ESPN
    // renames a franchise or the canonical set diverges, the page would
    // otherwise silently render fallback initials instead of a logo.
    for (const g of m.matchups) {
      for (const [abbr, name] of [
        [g.home_team, g.home_team_name],
        [g.away_team, g.away_team_name],
      ] as const) {
        const meta = WNBA_TEAMS_METADATA[abbr];
        expect(meta, `${abbr} is not in WNBA_TEAMS_METADATA`).toBeDefined();
        expect(name, `${abbr} display name`).toBe(meta.fullName);
      }
    }
  });

  it('the projection constants match projections_models_metadata.json', () => {
    // build_matchups_dataset.R reads WNBA_HCA and WNBA_MARGIN_SIGMA from
    // config.R and restates neither; export_web_json.R publishes the same two
    // constants into the metadata payload. They must therefore agree exactly.
    // A mismatch means one of the two stages ran against a different config,
    // which would make the rating-differential projections incomparable with
    // every other probability on the site.
    expect(m.provenance.hca_points).toBeCloseTo(metadata.home_court_advantage, 6);
    expect(m.provenance.margin_sigma).toBeCloseTo(metadata.margin_sigma, 6);
  });

  it('the season matches the rest of the published datasets', () => {
    expect(m.season).toBe(metadata.season);
  });

  it('every team in the league appears in the schedule, and no non-league team does', () => {
    const inSchedule = new Set(
      m.matchups.flatMap((g) => [g.home_team, g.away_team])
    );
    const canonical = new Set(teams.map((t) => t.team));
    expect([...inSchedule].sort()).toEqual([...canonical].sort());
  });
});
