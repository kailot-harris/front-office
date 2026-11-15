/**
 * Layer 1/2 — Game detail contract & mathematical invariants (v3 §6 item 6).
 *
 * Verifies every generated `web/public/data/games/<game_id>.json` against
 * `matchups_slates.json` and the `GameDetailEnvelope` contract in
 * `lib/gameDetailTypes.ts`.
 */
import fs from 'fs';
import path from 'path';
import { isDeepStrictEqual } from 'util';
import { describe, it, expect } from 'vitest';
import type { z } from 'zod';
import type {
  EfficiencyFactorItem,
  EnteringBaseline,
  GameDetailEnvelope,
  GameExplainabilityPayload,
  PlayerBoxRow,
  TeamBoxTotals,
  XgboostShapPayload,
} from '@/lib/gameDetailTypes';
import {
  DATA_DIR,
  GAMES_DIR,
  listGameDetailIds,
  readGameDetailFile,
  readJsonFile,
} from '../helpers/datasets';
import type { MatchupsDataset } from '@/lib/matchupTypes';
import { GameDetailEnvelopeSchema, GameExplainabilityPayloadSchema } from './schemas';

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

const FORBIDDEN_VERDICT_RE = /\b(favorites?|upsets?)\b/i;

const ALLOWED_LOG_SOURCES = new Set([
  'LOGGED_PREGAME',
  'BACKTEST_PREWEEK',
  'BACKTEST_SEEDED',
]);

// Commit 15decf5 landed P2-b component snapshots on 2026-11-15; rows logged
// before this cutoff (and all backtest rows) carry NA component columns and
// must keep margin_waterfall === null so current ratings never leak onto them.
const P2B_SNAPSHOT_CUTOFF_MS = Date.parse('2026-11-15T00:00:00Z');

const WATERFALL_CORE_KEYS = [
  'bottom_up',
  'rapm',
  'shot_fatigue',
  'embeddings',
  'home_court',
  'schedule',
] as const;

const ENTERING_FACTOR_KEYS = ['efg_pct', 'tov_pct', 'oreb_pct', 'fta_rate', 'ortg'] as const;

const XGBOOST_SHAP_FEATURES = new Set([
  'diff_roll_pts',
  'diff_roll_efg',
  'diff_roll_ts',
  'diff_roll_tovp',
  'diff_roll_oreb',
  'diff_roll_dreb',
  'diff_roll_ast',
  'diff_roll_stl',
  'diff_roll_blk',
  'diff_days_rest',
  'diff_fatigue_index',
  'diff_is_b2b',
  'style_similarity',
]);

/** Error function approximation (Abramowitz & Stegun 7.1.26, max error <= 1.5e-7). */
function erf(x: number): number {
  const sign = x < 0 ? -1 : 1;
  const ax = Math.abs(x);
  const t = 1 / (1 + 0.3275911 * ax);
  const y =
    1 -
    ((((1.061405429 * t - 1.453152027) * t + 1.421413741) * t - 0.284496736) * t +
      0.254829592) *
      t *
      Math.exp(-ax * ax);
  return sign * y;
}

function normalCdf(z: number): number {
  return 0.5 * (1 + erf(z / Math.SQRT2));
}

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

function assertWaterfallAndVeracity(
  label: string,
  ex: GameExplainabilityPayload,
  slateLogSource: string | null | undefined,
  isCompleted: boolean,
  failures: string[],
): { isPrimaryEnsemble: boolean; isLegacyLogged: boolean; hasWaterfall: boolean } {
  const isPrimaryEnsemble = ex.projection_basis === 'primary_ensemble';
  if (isPrimaryEnsemble) {
    if (ex.margin_waterfall === null) {
      failures.push(`${label}: primary_ensemble requires non-null margin_waterfall`);
    }
    if (ex.sigma_game === null || !Number.isFinite(ex.sigma_game) || ex.sigma_game <= 0) {
      failures.push(`${label}: primary_ensemble requires finite positive sigma_game, got ${ex.sigma_game}`);
    }
    if (ex.logged_forecast !== null) {
      failures.push(`${label}: primary_ensemble must have logged_forecast=null`);
    }
    if (slateLogSource !== null && slateLogSource !== undefined) {
      failures.push(`${label}: primary_ensemble must have null log_source, got ${slateLogSource}`);
    }
  }

  let isLegacyLogged = false;
  if (ex.logged_forecast !== null) {
    const lf = ex.logged_forecast;
    const ls = lf.log_source;
    if ((ls as string) === 'SEEDED_HINDSIGHT' || !ALLOWED_LOG_SOURCES.has(ls)) {
      failures.push(`${label}: invalid logged_forecast.log_source=${String(ls)}`);
    }
    if ((slateLogSource as string) === 'SEEDED_HINDSIGHT' || ls !== slateLogSource) {
      failures.push(`${label}: logged_forecast.log_source (${ls}) !== MatchupGame.log_source (${String(slateLogSource)})`);
    }

    const tsMs = Date.parse(lf.prediction_timestamp);
    if (!Number.isFinite(tsMs)) {
      failures.push(`${label}: unparseable logged_forecast.prediction_timestamp=${lf.prediction_timestamp}`);
    } else {
      isLegacyLogged =
        tsMs < P2B_SNAPSHOT_CUTOFF_MS ||
        ls === 'BACKTEST_PREWEEK' ||
        ls === 'BACKTEST_SEEDED';
      if (isLegacyLogged) {
        if (ex.margin_waterfall !== null) {
          failures.push(`${label}: legacy pre-P2-b logged row (${ls} @ ${lf.prediction_timestamp}) leaked non-null margin_waterfall`);
        }
        if (ex.sigma_game !== null) {
          failures.push(`${label}: legacy pre-P2-b logged row (${ls} @ ${lf.prediction_timestamp}) leaked non-null sigma_game`);
        }
      }
    }

    if (isCompleted) {
      if (lf.brier_component === null || lf.log_loss_component === null) {
        failures.push(`${label}: completed logged game missing brier_component or log_loss_component`);
      }
    } else if (lf.brier_component !== null || lf.log_loss_component !== null) {
      failures.push(`${label}: pending logged game must have null brier_component & log_loss_component`);
    }
  } else if (slateLogSource !== null && slateLogSource !== undefined) {
    failures.push(`${label}: non-null log_source=${slateLogSource} requires non-null logged_forecast`);
  }

  const hasWaterfall = ex.margin_waterfall !== null;
  if (ex.margin_waterfall !== null) {
    const wf = ex.margin_waterfall;
    const seenKeys = new Set<string>();
    const roundingSteps = wf.filter((s) => s.key === 'rounding');

    for (const step of wf) {
      if (seenKeys.has(step.key)) {
        failures.push(`${label}: duplicate margin_waterfall step key "${step.key}"`);
      }
      seenKeys.add(step.key);
    }
    for (const coreKey of WATERFALL_CORE_KEYS) {
      if (!seenKeys.has(coreKey)) {
        failures.push(`${label}: margin_waterfall missing core step "${coreKey}"`);
      }
    }
    for (const rs of roundingSteps) {
      if (Math.abs(rs.points) > 0.02) {
        failures.push(`${label}: margin_waterfall rounding step |${rs.points}| > 0.02`);
      }
    }

    if (ex.predicted_margin === null) {
      failures.push(`${label}: non-null margin_waterfall requires non-null predicted_margin`);
    } else {
      const stepSum = wf.reduce((acc, step) => acc + step.points, 0);
      if (Math.abs(stepSum - ex.predicted_margin) > 0.01) {
        failures.push(
          `${label}: margin_waterfall sum=${stepSum.toFixed(4)} deviates from predicted_margin=${ex.predicted_margin} by > 0.01`,
        );
      }
    }

    if (
      ex.sigma_game !== null &&
      ex.sigma_game > 0 &&
      ex.predicted_margin !== null &&
      ex.predicted_home_win_prob !== null
    ) {
      const cdfProb = normalCdf(ex.predicted_margin / ex.sigma_game);
      if (Math.abs(cdfProb - ex.predicted_home_win_prob) > 0.002) {
        failures.push(
          `${label}: normalCdf(${ex.predicted_margin}/${ex.sigma_game})=${cdfProb.toFixed(5)} vs predicted_home_win_prob=${ex.predicted_home_win_prob}`,
        );
      }
    }
  }

  return { isPrimaryEnsemble, isLegacyLogged, hasWaterfall };
}

function assertXgboostShap(
  label: string,
  shap: XgboostShapPayload,
  failures: string[],
): void {
  if (shap.away_prior_games_n < 1 || shap.home_prior_games_n < 1) {
    failures.push(
      `${label}: xgboost_shap requires prior_games_n >= 1 (away=${shap.away_prior_games_n}, home=${shap.home_prior_games_n})`,
    );
  }
  if (shap.factors.length !== 13) {
    failures.push(`${label}: xgboost_shap.factors length=${shap.factors.length}, expected 13`);
    return;
  }

  const seenFeatures = new Set<string>();
  let shapSum = 0;
  for (let i = 0; i < shap.factors.length; i++) {
    const f = shap.factors[i];
    if (!XGBOOST_SHAP_FEATURES.has(f.feature)) {
      failures.push(`${label}: unrecognized xgboost_shap feature "${f.feature}"`);
    }
    seenFeatures.add(f.feature);
    shapSum += f.shap_log_odds;

    if (i > 0) {
      const prevAbs = Math.abs(shap.factors[i - 1].shap_log_odds);
      const curAbs = Math.abs(f.shap_log_odds);
      if (curAbs > prevAbs + 1e-12) {
        failures.push(
          `${label}: xgboost_shap.factors not sorted descending by |shap_log_odds| at index ${i} (${curAbs} > ${prevAbs})`,
        );
      }
    }
  }
  if (seenFeatures.size !== 13) {
    failures.push(`${label}: xgboost_shap.factors has ${seenFeatures.size} unique features, expected 13`);
  }

  const additivityErr = Math.abs((shap.base_value_log_odds + shapSum) - shap.total_log_odds);
  if (additivityErr > 0.002) {
    failures.push(`${label}: xgboost_shap additivity error=${additivityErr.toFixed(6)} > 0.002`);
  }

  const logisticProb = 1 / (1 + Math.exp(-shap.total_log_odds));
  const probErr = Math.abs(logisticProb - shap.predicted_home_win_prob);
  if (probErr > 0.001) {
    failures.push(
      `${label}: sigmoid(total_log_odds)=${logisticProb.toFixed(5)} vs predicted_home_win_prob=${shap.predicted_home_win_prob} (err=${probErr.toFixed(5)} > 0.001)`,
    );
  }
}

function assertEnteringBaselines(
  label: string,
  baselines: EnteringBaseline[] | null,
  isCompleted: boolean,
  awayAbbr: string,
  homeAbbr: string,
  efficiencyFactors: EfficiencyFactorItem[] | null,
  failures: string[],
): boolean {
  if (!isCompleted) {
    if (baselines !== null) {
      failures.push(`${label}: pending game must have entering_baselines=null`);
    }
    return false;
  }
  if (baselines === null) return false;

  if (baselines.length !== 2) {
    failures.push(`${label}: entering_baselines length=${baselines.length}, expected 2`);
    return true;
  }
  if (baselines[0].teamAbbr !== awayAbbr || baselines[1].teamAbbr !== homeAbbr) {
    failures.push(
      `${label}: entering_baselines order=[${baselines[0].teamAbbr}, ${baselines[1].teamAbbr}], expected [${awayAbbr}, ${homeAbbr}]`,
    );
  }

  const efByKey = efficiencyFactors
    ? new Map(efficiencyFactors.map((item) => [item.key, item]))
    : null;

  for (const [idx, side] of baselines.entries()) {
    if (side.prior_games_n < 1) {
      failures.push(`${label}.${side.teamAbbr}: prior_games_n=${side.prior_games_n} must be >= 1`);
    }
    const factorByKey = new Map(side.factors.map((f) => [f.key, f]));
    if (side.factors.length !== ENTERING_FACTOR_KEYS.length) {
      failures.push(`${label}.${side.teamAbbr}: entering_baselines factor count=${side.factors.length}, expected 5`);
    }
    for (const key of ENTERING_FACTOR_KEYS) {
      const f = factorByKey.get(key);
      if (!f) {
        failures.push(`${label}.${side.teamAbbr}: entering_baselines missing factor "${key}"`);
        continue;
      }
      if (f.entering !== null && f.realized !== null) {
        const expectedDiff = Math.round((f.realized - f.entering) * 10) / 10;
        if (f.difference === null || Math.abs(f.difference - expectedDiff) > 0.01) {
          failures.push(
            `${label}.${side.teamAbbr}.${key}: difference=${String(f.difference)} vs round(realized-entering, 1)=${expectedDiff}`,
          );
        }
      }
      if (efByKey) {
        const efItem = efByKey.get(key);
        const expectedRealized = idx === 0 ? efItem?.away_value : efItem?.home_value;
        if (f.realized !== expectedRealized) {
          failures.push(
            `${label}.${side.teamAbbr}.${key}: entering_baselines.realized=${String(f.realized)} !== efficiency_factors=${String(expectedRealized)}`,
          );
        }
      }
    }
  }

  return true;
}

describe('Game detail dataset contracts (v3 §6 item 6)', () => {
  const matchups = readJsonFile<MatchupsDataset>('matchups_slates.json');
  const rawSlates = fs.readFileSync(path.join(DATA_DIR, 'matchups_slates.json'), 'utf-8');
  const gameIds = listGameDetailIds();
  const gameById = new Map(matchups.matchups.map((g) => [g.game_id, g]));
  const loadedGames: { gameId: string; raw: string; envelope: GameDetailEnvelope }[] = gameIds.map(
    (gameId) => ({
      gameId,
      raw: fs.readFileSync(path.join(GAMES_DIR, `${gameId}.json`), 'utf-8'),
      envelope: readGameDetailFile(gameId),
    }),
  );
  const detailById = new Map(loadedGames.map((g) => [g.gameId, g.envelope]));

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

  it('8. zero-betting & neutral-verdict compliance: no forbidden betting or verdict terms appear in games/*.json or matchups_slates.json', () => {
    const hits: string[] = [];
    for (const { gameId, raw } of loadedGames) {
      const betMatch = raw.match(FORBIDDEN_BETTING_RE);
      if (betMatch) {
        hits.push(`${gameId}: matched forbidden betting term "${betMatch[0]}"`);
      }
      const verdictMatch = raw.match(FORBIDDEN_VERDICT_RE);
      if (verdictMatch) {
        hits.push(`${gameId}: matched forbidden verdict term "${verdictMatch[0]}"`);
      }
    }
    const slatesBetMatch = rawSlates.match(FORBIDDEN_BETTING_RE);
    if (slatesBetMatch) {
      hits.push(`matchups_slates.json: matched forbidden betting term "${slatesBetMatch[0]}"`);
    }
    const slatesVerdictMatch = rawSlates.match(FORBIDDEN_VERDICT_RE);
    if (slatesVerdictMatch) {
      hits.push(`matchups_slates.json: matched forbidden verdict term "${slatesVerdictMatch[0]}"`);
    }
    expect(hits, hits.slice(0, 10).join('\n')).toEqual([]);
  });

  it('9. Phase 2 presence & slates parity (P2-c): non-null explainability on all games/*.json and projected MatchupGame rows, deep-equal when has_game_detail=true', () => {
    const failures: string[] = [];
    let detailExplCount = 0;
    let projectedExplCount = 0;
    let parityCheckedCount = 0;

    for (const { gameId, envelope } of loadedGames) {
      const ex = envelope.data.explainability;
      if (ex === null) {
        failures.push(`games/${gameId}.json: expected non-null explainability`);
        continue;
      }
      detailExplCount++;
    }

    for (const g of matchups.matchups) {
      if (!g.has_projection) continue;
      const ex = g.explainability;
      if (ex === null || ex === undefined) {
        failures.push(`matchups[${g.game_id}]: projected game missing non-null explainability`);
        continue;
      }
      const parsed = GameExplainabilityPayloadSchema.safeParse(ex);
      if (!parsed.success) {
        failures.push(`matchups[${g.game_id}].explainability:\n${formatIssues(parsed.error.issues)}`);
        continue;
      }
      projectedExplCount++;

      if (g.projection_basis !== 'team_rating_differential') {
        if (ex.projection_basis !== g.projection_basis) {
          failures.push(`matchups[${g.game_id}]: explainability.projection_basis=${String(ex.projection_basis)} !== ${String(g.projection_basis)}`);
        }
        if (ex.predicted_margin !== g.predicted_margin) {
          failures.push(`matchups[${g.game_id}]: explainability.predicted_margin=${String(ex.predicted_margin)} !== ${String(g.predicted_margin)}`);
        }
        if (ex.predicted_home_win_prob !== g.predicted_home_win_prob) {
          failures.push(`matchups[${g.game_id}]: explainability.predicted_home_win_prob=${String(ex.predicted_home_win_prob)} !== ${String(g.predicted_home_win_prob)}`);
        }
      }

      if (g.has_game_detail) {
        const detail = detailById.get(g.game_id);
        if (!detail) {
          failures.push(`matchups[${g.game_id}]: has_game_detail=true but missing games/${g.game_id}.json`);
          continue;
        }
        parityCheckedCount++;
        if (!isDeepStrictEqual(ex, detail.data.explainability)) {
          expect(ex, `matchups[${g.game_id}].explainability disagrees with games/${g.game_id}.json`).toEqual(
            detail.data.explainability,
          );
          failures.push(`matchups[${g.game_id}]: explainability disagrees with games/${g.game_id}.json`);
        }
      }
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
    expect(detailExplCount).toBe(loadedGames.length);
    expect(projectedExplCount).toBe(matchups.games_with_projection);
    expect(parityCheckedCount).toBe(loadedGames.length);
  });

  it('10. waterfall veracity & Normal CDF invariants across games/*.json and matchups_slates.json', () => {
    const failures: string[] = [];
    let primaryEnsembleCount = 0;
    let waterfallCount = 0;
    let legacyLoggedCount = 0;

    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      if (!d.explainability) {
        failures.push(`games/${gameId}.json: null explainability`);
        continue;
      }
      const slateGame = gameById.get(gameId);
      assertWaterfallAndVeracity(
        `games/${gameId}.json`,
        d.explainability,
        slateGame?.log_source ?? null,
        d.is_completed,
        failures,
      );
    }

    for (const g of matchups.matchups) {
      if (!g.explainability) {
        failures.push(`matchups[${g.game_id}]: null explainability`);
        continue;
      }
      const stats = assertWaterfallAndVeracity(
        `matchups[${g.game_id}]`,
        g.explainability,
        g.log_source ?? null,
        g.is_completed,
        failures,
      );
      if (stats.isPrimaryEnsemble) primaryEnsembleCount++;
      if (stats.hasWaterfall) waterfallCount++;
      if (stats.isLegacyLogged) legacyLoggedCount++;
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
    expect(primaryEnsembleCount).toBeGreaterThan(0);
    expect(waterfallCount).toBeGreaterThan(0);
    expect(legacyLoggedCount).toBeGreaterThanOrEqual(219);
  });

  it('11. secondary diagnostic xgboost_shap invariants & 0-prior-history null guard', () => {
    const failures: string[] = [];
    let detailShapScoredCount = 0;
    let detailShapNullCount = 0;
    let slateShapScoredCount = 0;
    let slateShapNullCount = 0;

    // Index completed game dates per team so we can enforce that 0-prior-history
    // games strictly have xgboost_shap === null (no causal leakage / synthetic backfill).
    const completedDatesByTeam = new Map<string, string[]>();
    for (const g of matchups.matchups) {
      if (!g.is_completed) continue;
      for (const team of [g.away_team, g.home_team]) {
        const dates = completedDatesByTeam.get(team);
        if (dates) dates.push(g.game_date);
        else completedDatesByTeam.set(team, [g.game_date]);
      }
    }

    for (const { gameId, envelope } of loadedGames) {
      const shap = envelope.data.explainability?.xgboost_shap ?? null;
      if (shap === null) {
        detailShapNullCount++;
      } else {
        detailShapScoredCount++;
        assertXgboostShap(`games/${gameId}.json`, shap, failures);
      }
    }

    for (const g of matchups.matchups) {
      const awayPrior = (completedDatesByTeam.get(g.away_team) ?? []).filter((d) => d < g.game_date).length;
      const homePrior = (completedDatesByTeam.get(g.home_team) ?? []).filter((d) => d < g.game_date).length;
      const hasZeroPrior = awayPrior === 0 || homePrior === 0;
      const shap = g.explainability?.xgboost_shap ?? null;

      if (shap === null) {
        slateShapNullCount++;
      } else {
        slateShapScoredCount++;
        if (hasZeroPrior) {
          failures.push(
            `matchups[${g.game_id}] (${g.game_date} ${g.away_team}@${g.home_team}): 0-prior-history game (away=${awayPrior}, home=${homePrior}) must have xgboost_shap=null`,
          );
        }
        assertXgboostShap(`matchups[${g.game_id}]`, shap, failures);
      }
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
    expect(detailShapNullCount).toBeGreaterThanOrEqual(1);
    expect(detailShapScoredCount).toBeGreaterThan(0);
    expect(slateShapNullCount).toBeGreaterThanOrEqual(1);
    expect(slateShapScoredCount).toBeGreaterThan(0);
    if (matchups.season === 2027) {
      expect(detailShapNullCount).toBe(16);
      expect(slateShapNullCount).toBe(16);
      expect(slateShapScoredCount).toBe(1184);
    }
  });

  it('12. entering_baselines pooled factor invariants across games/*.json and matchups_slates.json', () => {
    const failures: string[] = [];
    let detailEbCount = 0;
    let slateEbCount = 0;

    for (const { gameId, envelope } of loadedGames) {
      const d = envelope.data;
      const hasEb = assertEnteringBaselines(
        `games/${gameId}.json`,
        d.explainability?.entering_baselines ?? null,
        d.is_completed,
        d.away_team.teamAbbr,
        d.home_team.teamAbbr,
        d.efficiency_factors,
        failures,
      );
      if (hasEb) detailEbCount++;
    }

    for (const g of matchups.matchups) {
      const hasEb = assertEnteringBaselines(
        `matchups[${g.game_id}]`,
        g.explainability?.entering_baselines ?? null,
        g.is_completed,
        g.away_team,
        g.home_team,
        null,
        failures,
      );
      if (hasEb) slateEbCount++;
    }

    expect(failures, failures.slice(0, 10).join('\n')).toEqual([]);
    expect(detailEbCount).toBeGreaterThanOrEqual(172);
    expect(slateEbCount).toBeGreaterThanOrEqual(172);
  });
});
