/**
 * Layer 1/2 — Game detail contract & mathematical invariants (v3 §6 item 6).
 *
 * Verifies every generated `web/public/data/games/<game_id>.json` against
 * `matchups_slates.json` and the `GameDetailEnvelope` contract in
 * `lib/gameDetailTypes.ts`.
 */
import fs from 'fs';
import path from 'path';
import { describe, it, expect } from 'vitest';
import type { z } from 'zod';
import type { GameDetailEnvelope, PlayerBoxRow, TeamBoxTotals } from '@/lib/gameDetailTypes';
import {
  GAMES_DIR,
  listGameDetailIds,
  readGameDetailFile,
  readJsonFile,
} from '../helpers/datasets';
import type { MatchupsDataset } from '@/lib/matchupTypes';
import { GameDetailEnvelopeSchema } from './schemas';

const EXACT_COUNTING_STATS = [
  'points',
  'fgm',
  'fga',
  'fg3m',
  'fg3a',
  'ftm',
  'fta',
  'ast',
  'stl',
  'blk',
  'tov',
  'pf',
] as const;

const REBOUND_STATS = ['oreb', 'dreb', 'reb'] as const;

const FORBIDDEN_BETTING_RE =
  /\b(spread|moneyline|odds|parlay|wager|betting|sportsbook|covered|favorite|upset|over_under|sharp_book|implied_probability|market_odds|value_bets)\b/i;

function formatIssues(issues: z.ZodIssue[], max = 6): string {
  return (
    issues
      .slice(0, max)
      .map((i) => `  • [${i.path.join('.')}] ${i.message} (${i.code})`)
      .join('\n') + (issues.length > max ? `\n  ... and ${issues.length - max} more` : '')
  );
}

function sumStat(players: PlayerBoxRow[], stat: keyof PlayerBoxRow): number {
  return players.reduce((acc, row) => acc + (row[stat] as number), 0);
}

function collectNonFiniteNumbers(val: unknown, trail = 'root', out: string[] = []): string[] {
  if (typeof val === 'number') {
    if (!Number.isFinite(val)) out.push(`${trail}=${String(val)}`);
    return out;
  }
  if (Array.isArray(val)) {
    for (let i = 0; i < val.length; i++) {
      collectNonFiniteNumbers(val[i], `${trail}[${i}]`, out);
    }
    return out;
  }
  if (val !== null && typeof val === 'object') {
    for (const [k, v] of Object.entries(val)) {
      collectNonFiniteNumbers(v, `${trail}.${k}`, out);
    }
  }
  return out;
}

function assertShootingDenomNulls(
  row: Pick<
    TeamBoxTotals | PlayerBoxRow,
    'fga' | 'fg_pct' | 'fg3a' | 'fg3_pct' | 'fta' | 'ft_pct' | 'efg_pct' | 'ts_pct'
  >,
  label: string,
  failures: string[],
  allowZeroEfgTs: boolean,
): void {
  const pctChecks: [string, number | null, number, number][] = [
    ['fg_pct', row.fg_pct, 0, 100],
    ['fg3_pct', row.fg3_pct, 0, 100],
    ['ft_pct', row.ft_pct, 0, 100],
  ];
  for (const [field, val, lo, hi] of pctChecks) {
    if (val !== null && (!Number.isFinite(val) || val < lo || val > hi)) {
      failures.push(`${label} ${field}=${val} outside [${lo}, ${hi}]`);
    }
  }

  for (const field of ['efg_pct', 'ts_pct'] as const) {
    const val = row[field];
    if (val === null) continue;
    const inRange = Number.isFinite(val) && val <= 150 && (allowZeroEfgTs ? val >= 0 : val > 0);
    if (!inRange) {
      failures.push(
        `${label} ${field}=${val} outside ${allowZeroEfgTs ? '[0, 150]' : '(0, 150]'}`,
      );
    }
  }

  if (row.fga === 0) {
    if (row.fg_pct !== null) failures.push(`${label} fga=0 requires fg_pct=null, got ${row.fg_pct}`);
    if (row.efg_pct !== null) failures.push(`${label} fga=0 requires efg_pct=null, got ${row.efg_pct}`);
  } else {
    if (row.fg_pct === null) failures.push(`${label} fga=${row.fga} > 0 had fg_pct=null`);
    if (row.efg_pct === null) failures.push(`${label} fga=${row.fga} > 0 had efg_pct=null`);
  }

  if (row.fg3a === 0 && row.fg3_pct !== null) {
    failures.push(`${label} fg3a=0 requires fg3_pct=null, got ${row.fg3_pct}`);
  } else if (row.fg3a > 0 && row.fg3_pct === null) {
    failures.push(`${label} fg3a=${row.fg3a} > 0 had fg3_pct=null`);
  }

  if (row.fta === 0 && row.ft_pct !== null) {
    failures.push(`${label} fta=0 requires ft_pct=null, got ${row.ft_pct}`);
  } else if (row.fta > 0 && row.ft_pct === null) {
    failures.push(`${label} fta=${row.fta} > 0 had ft_pct=null`);
  }

  if (row.fga === 0 && row.fta === 0) {
    if (row.ts_pct !== null) failures.push(`${label} fga=0 & fta=0 requires ts_pct=null, got ${row.ts_pct}`);
  } else if (row.ts_pct === null) {
    failures.push(`${label} fga=${row.fga}, fta=${row.fta} had ts_pct=null`);
  }
}

describe('Game detail dataset contracts (v3 §6 item 6)', () => {
  const matchups = readJsonFile<MatchupsDataset>('matchups_slates.json');
  const gameIds = listGameDetailIds();
  const gameById = new Map(matchups.matchups.map((g) => [g.game_id, g]));
  const loadedGames: { gameId: string; raw: string; envelope: GameDetailEnvelope }[] = gameIds.map(
    (gameId) => ({
      gameId,
      raw: fs.readFileSync(path.join(GAMES_DIR, `${gameId}.json`), 'utf-8'),
      envelope: readGameDetailFile(gameId),
    }),
  );

  it('1. envelope & strict schema parity: every games/<game_id>.json satisfies GameDetailEnvelope without predictedWinProb', () => {
    expect(fs.existsSync(GAMES_DIR), `Missing games directory: ${GAMES_DIR}`).toBe(true);
    expect(loadedGames.length, 'Expected at least one game detail file').toBeGreaterThan(0);

    const schemaFailures: string[] = [];
    const metadataFailures: string[] = [];

    for (const { gameId, raw, envelope } of loadedGames) {
      expect(raw).not.toMatch(/:\s*NaN\b/);
      expect(raw).not.toMatch(/:\s*-?Infinity\b/);
      expect(raw).not.toMatch(/:\s*"NA"/);

      const parsed = GameDetailEnvelopeSchema.safeParse(envelope);
      if (!parsed.success) {
        schemaFailures.push(`games/${gameId}.json:\n${formatIssues(parsed.error.issues)}`);
        continue;
      }

      const d = envelope.data;
      if (envelope.schema_version !== '1.0') metadataFailures.push(`${gameId}: schema_version=${envelope.schema_version}`);
      if (envelope.endpoint !== 'game_detail') metadataFailures.push(`${gameId}: endpoint=${envelope.endpoint}`);
      if (envelope.sport !== 'nba') metadataFailures.push(`${gameId}: sport=${envelope.sport}`);
      if (typeof envelope.season !== 'number' || envelope.season !== matchups.season) {
        metadataFailures.push(`${gameId}: season=${envelope.season} vs ${matchups.season}`);
      }
      if (!envelope.season_label || envelope.season_label !== matchups.season_label) {
        metadataFailures.push(`${gameId}: season_label=${envelope.season_label} vs ${matchups.season_label}`);
      }
      if (!envelope.generated_at) metadataFailures.push(`${gameId}: empty generated_at`);
      if (d.explainability !== null) metadataFailures.push(`${gameId}: explainability must be null in Phase 1`);
      if (d.game_flow !== null) metadataFailures.push(`${gameId}: game_flow must be null in Phase 1`);
      if ('predictedWinProb' in d.away_team || 'predictedWinProb' in d.home_team) {
        metadataFailures.push(`${gameId}: GameTeamSummary must not carry predictedWinProb`);
      }
      if (d.game_id !== gameId) {
        metadataFailures.push(`${gameId}: payload game_id=${d.game_id} disagrees with filename`);
      }

      const slateGame = gameById.get(gameId);
      if (slateGame) {
        if (d.slate !== slateGame.slate) metadataFailures.push(`${gameId}: slate ${d.slate} vs ${slateGame.slate}`);
        if (d.game_date !== slateGame.game_date) {
          metadataFailures.push(`${gameId}: game_date ${d.game_date} vs ${slateGame.game_date}`);
        }
        if (d.away_team.teamAbbr !== slateGame.away_team) {
          metadataFailures.push(`${gameId}: away_team ${d.away_team.teamAbbr} vs ${slateGame.away_team}`);
        }
        if (d.home_team.teamAbbr !== slateGame.home_team) {
          metadataFailures.push(`${gameId}: home_team ${d.home_team.teamAbbr} vs ${slateGame.home_team}`);
        }
        if (d.away_team.score !== slateGame.away_score || d.home_team.score !== slateGame.home_score) {
          metadataFailures.push(`${gameId}: team score disagrees with matchups_slates.json`);
        }
      }
    }

    expect(schemaFailures, schemaFailures.slice(0, 5).join('\n')).toEqual([]);
    expect(metadataFailures, metadataFailures.slice(0, 10).join('\n')).toEqual([]);
  });

  it('2. file bijection: has_game_detail === true iff games/<game_id>.json exists, and unplayed games have no box score or detail', () => {
    const flaggedIds = new Set(
      matchups.matchups.filter((g) => g.has_game_detail === true).map((g) => g.game_id),
    );
    const diskIds = new Set(gameIds);

    const missingOnDisk = [...flaggedIds].filter((id) => !diskIds.has(id));
    const orphanOnDisk = [...diskIds].filter((id) => !flaggedIds.has(id));

    expect(missingOnDisk, `Games with has_game_detail=true missing files: ${missingOnDisk.join(', ')}`).toEqual([]);
    expect(orphanOnDisk, `Orphan files in public/data/games/: ${orphanOnDisk.join(', ')}`).toEqual([]);

    const flagViolations: string[] = [];
    for (const g of matchups.matchups) {
      if (!g.is_completed) {
        if (g.has_box_score !== false || g.has_game_detail !== false) {
          flagViolations.push(
            `${g.game_id}: is_completed=false requires has_box_score=false & has_game_detail=false`,
          );
        }
      }
      if (g.has_game_detail && (!g.is_completed || !g.has_box_score)) {
        flagViolations.push(`${g.game_id}: has_game_detail=true requires is_completed & has_box_score`);
      }
    }
    expect(flagViolations, flagViolations.slice(0, 10).join('\n')).toEqual([]);
  });

  it('3. box score presence invariant: box_score, efficiency_factors, and context_splits are non-null iff has_box_score === true', () => {
    const violations: string[] = [];
    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      if ((d.box_score !== null) !== d.has_box_score) {
        violations.push(`${gameId}: box_score nullability disagrees with has_box_score=${d.has_box_score}`);
      }
      if ((d.efficiency_factors !== null) !== d.has_box_score) {
        violations.push(`${gameId}: efficiency_factors nullability disagrees with has_box_score=${d.has_box_score}`);
      }
      if ((d.context_splits !== null) !== d.has_box_score) {
        violations.push(`${gameId}: context_splits nullability disagrees with has_box_score=${d.has_box_score}`);
      }
    }
    expect(violations, violations.join('\n')).toEqual([]);
  });

  it('4. numeric sanity & zero-denominator nulls across team totals, efficiency factors, and player box rows', () => {
    const failures: string[] = [];

    for (const { gameId, envelope } of loadedGames) {
      const nonFinite = collectNonFiniteNumbers(envelope, gameId);
      if (nonFinite.length > 0) {
        failures.push(...nonFinite);
        continue;
      }

      const d = envelope.data;
      if (!d.has_box_score || !d.box_score || !d.efficiency_factors) continue;

      for (const side of ['away', 'home'] as const) {
        const totals = d.box_score[`${side}_totals`];
        const players = d.box_score[`${side}_players`];

        assertShootingDenomNulls(totals, `${gameId}.${side}_totals`, failures, false);

        for (const rateKey of ['ortg', 'drtg', 'pace', 'possessions_est'] as const) {
          const val = totals[rateKey];
          if (val !== null && val <= 0) {
            failures.push(`${gameId}.${side}_totals.${rateKey}=${val} must be > 0`);
          }
        }

        for (const p of players) {
          assertShootingDenomNulls(
            p,
            `${gameId}.${side}_players[${p.playerName}]`,
            failures,
            true,
          );
        }
      }

      for (const ef of d.efficiency_factors) {
        for (const side of ['away_value', 'home_value'] as const) {
          const val = ef[side];
          if (val === null) continue;
          if (ef.key === 'tov_pct' || ef.key === 'oreb_pct') {
            if (val < 0 || val > 100) failures.push(`${gameId}.${ef.key}.${side}=${val} outside [0, 100]`);
          } else if (ef.key === 'efg_pct' || ef.key === 'ts_pct') {
            if (val <= 0 || val > 150) failures.push(`${gameId}.${ef.key}.${side}=${val} outside (0, 150]`);
          } else if (ef.key === 'ortg' || ef.key === 'drtg' || ef.key === 'pace') {
            if (val <= 0) failures.push(`${gameId}.${ef.key}.${side}=${val} must be > 0`);
          } else if (ef.key === 'fta_rate') {
            if (val < 0) failures.push(`${gameId}.${ef.key}.${side}=${val} must be >= 0`);
          }
        }
      }
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
  });

  it('5. exact counting-stat conservation: sum(active_players) === team_totals (and points === team.score)', () => {
    const mismatches: string[] = [];

    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      if (!d.has_box_score || !d.box_score) continue;

      for (const side of ['away', 'home'] as const) {
        const team = d[`${side}_team`];
        const totals = d.box_score[`${side}_totals`];
        const players = d.box_score[`${side}_players`];
        const inactive = d.box_score[`${side}_inactive`];

        if (totals.points !== team.score) {
          mismatches.push(`${gameId}.${side}: totals.points=${totals.points} vs team.score=${team.score}`);
        }

        for (const stat of EXACT_COUNTING_STATS) {
          const playerSum = sumStat(players, stat);
          if (playerSum !== totals[stat]) {
            mismatches.push(
              `${gameId}.${side}.${stat}: sum(active_players)=${playerSum} vs totals=${totals[stat]}`,
            );
          }
        }

        // Active players list must be disjoint from inactive list and exclude 0-min/0-all rows.
        const inactiveIds = new Set(inactive.map((p) => p.playerId));
        for (const p of players) {
          if (inactiveIds.has(p.playerId)) {
            mismatches.push(`${gameId}.${side}: playerId ${p.playerId} appears in both active and inactive`);
          }
          const zeroCounting =
            p.points === 0 &&
            p.reb === 0 &&
            p.oreb === 0 &&
            p.dreb === 0 &&
            p.ast === 0 &&
            p.stl === 0 &&
            p.blk === 0 &&
            p.tov === 0 &&
            p.pf === 0 &&
            p.fgm === 0 &&
            p.fga === 0 &&
            p.fg3m === 0 &&
            p.fg3a === 0 &&
            p.ftm === 0 &&
            p.fta === 0;
          if (p.minutes === 0 && zeroCounting) {
            mismatches.push(`${gameId}.${side}: inactive 0-min/0-stat row ${p.playerName} in active list`);
          }
        }

        const benchSplit = d.context_splits?.find((s) => s.key === 'bench_points');
        if (benchSplit) {
          const benchSum = players.filter((p) => !p.starter).reduce((acc, p) => acc + p.points, 0);
          const expectedBench = side === 'away' ? benchSplit.away_value : benchSplit.home_value;
          if (benchSum !== expectedBench) {
            mismatches.push(`${gameId}.${side}: bench_points=${expectedBench} vs sum(!starter)=${benchSum}`);
          }
        }
      }
    }

    expect(mismatches, mismatches.slice(0, 10).join('\n')).toEqual([]);
  });

  it('6. rebound feed tolerance (±1 with diagnostic output): |sum(active_players) - team_totals| <= 1 for oreb, dreb, reb', () => {
    const outOfTolerance: string[] = [];
    const diffs: string[] = [];

    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      if (!d.has_box_score || !d.box_score) continue;

      for (const side of ['away', 'home'] as const) {
        const totals = d.box_score[`${side}_totals`];
        const players = d.box_score[`${side}_players`];

        for (const stat of REBOUND_STATS) {
          const playerSum = sumStat(players, stat);
          const diff = playerSum - totals[stat];
          if (diff !== 0) {
            const msg = `${gameId} (${side} ${d[`${side}_team`].teamAbbr}) ${stat}: players=${playerSum} vs team=${totals[stat]} (diff=${diff > 0 ? `+${diff}` : diff})`;
            diffs.push(msg);
            if (Math.abs(diff) > 1) {
              outOfTolerance.push(msg);
            }
          }
        }
      }
    }

    if (diffs.length > 0) {
      console.warn(
        `[game_detail.contract] Observed ${diffs.length} rebound feed ±1 discrepancy(ies) across ${loadedGames.length} games:\n  - ${diffs.join('\n  - ')}`,
      );
    }

    expect(outOfTolerance, outOfTolerance.join('\n')).toEqual([]);
  });

  it('7. orthogonal efficiency symmetry: away_totals.drtg === home_totals.ortg and home_totals.drtg === away_totals.ortg, matching efficiency_factors', () => {
    const failures: string[] = [];

    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      if (!d.has_box_score || !d.box_score || !d.efficiency_factors) continue;

      const { away_totals: away, home_totals: home } = d.box_score;
      if (away.drtg !== home.ortg) {
        failures.push(`${gameId}: away_totals.drtg=${away.drtg} !== home_totals.ortg=${home.ortg}`);
      }
      if (home.drtg !== away.ortg) {
        failures.push(`${gameId}: home_totals.drtg=${home.drtg} !== away_totals.ortg=${away.ortg}`);
      }

      const factorByKey = new Map(d.efficiency_factors.map((f) => [f.key, f]));
      for (const key of ['efg_pct', 'ts_pct', 'ortg', 'drtg', 'pace'] as const) {
        const item = factorByKey.get(key);
        if (!item) {
          failures.push(`${gameId}: efficiency_factors missing ${key}`);
          continue;
        }
        if (item.away_value !== away[key]) {
          failures.push(`${gameId}: efficiency_factors.${key}.away_value=${item.away_value} !== away_totals.${key}=${away[key]}`);
        }
        if (item.home_value !== home[key]) {
          failures.push(`${gameId}: efficiency_factors.${key}.home_value=${item.home_value} !== home_totals.${key}=${home[key]}`);
        }
      }
      const paceFactor = factorByKey.get('pace');
      if (paceFactor && paceFactor.away_value !== paceFactor.home_value) {
        failures.push(`${gameId}: pace away (${paceFactor.away_value}) !== home (${paceFactor.home_value})`);
      }
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
  });

  it('8. zero-betting compliance: no forbidden betting terms appear in any games/<game_id>.json payload', () => {
    const hits: string[] = [];
    for (const { gameId, raw } of loadedGames) {
      const m = raw.match(FORBIDDEN_BETTING_RE);
      if (m) {
        hits.push(`${gameId}: matched forbidden term "${m[0]}"`);
      }
    }
    expect(hits, hits.slice(0, 10).join('\n')).toEqual([]);
  });
});
