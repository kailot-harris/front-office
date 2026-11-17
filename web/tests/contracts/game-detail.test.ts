import fs from 'fs';
import path from 'path';
import { describe, expect, it } from 'vitest';
import { gameDetailEnvelopeSchema } from './schemas';
import type { GameDetailEnvelope } from '../../lib/gameDetailTypes';

const REPO_WEB_ROOT = path.resolve(__dirname, '..', '..');
const GAMES_DIR = path.join(REPO_WEB_ROOT, 'public', 'data', 'games');
const MATCHUPS_FILE = path.join(REPO_WEB_ROOT, 'public', 'data', 'matchups_current_week.json');
const TYPES_FILE = path.join(REPO_WEB_ROOT, 'lib', 'gameDetailTypes.ts');
const MODAL_FILE = path.join(REPO_WEB_ROOT, 'components', 'GameDetailModal.tsx');

const gameFiles = fs.existsSync(GAMES_DIR)
  ? fs.readdirSync(GAMES_DIR).filter((f) => f.endsWith('.json')).sort()
  : [];

describe('Game Detail Contract Suite (All Game Files)', () => {
  it('finds at least 100 generated game detail JSON files', () => {
    expect(gameFiles.length).toBeGreaterThanOrEqual(100);
  });

  it('validates every game JSON file against gameDetailEnvelopeSchema', () => {
    for (const filename of gameFiles) {
      const fullPath = path.join(GAMES_DIR, filename);
      const rawText = fs.readFileSync(fullPath, 'utf8');
      const parsed = JSON.parse(rawText) as GameDetailEnvelope;

      const result = gameDetailEnvelopeSchema.safeParse(parsed);
      if (!result.success) {
        throw new Error(
          `${filename} failed schema validation: ${result.error.issues.map((i) => `${i.path.join('.')}: ${i.message}`).join(', ')}`
        );
      }
      expect(result.success).toBe(true);
      expect(parsed.schema_version).toBe('1.0');
      expect(parsed.sport).toBe('nfl');
      expect(parsed.endpoint).toBe('game_detail');
    }
  });

  it('asserts zero NaN or Infinity in any game JSON file', () => {
    for (const filename of gameFiles) {
      const fullPath = path.join(GAMES_DIR, filename);
      const rawText = fs.readFileSync(fullPath, 'utf8');

      expect(rawText).not.toMatch(/: ?NaN\b/);
      expect(rawText).not.toMatch(/: ?Infinity\b/);
      expect(rawText).not.toMatch(/: ?-Infinity\b/);
    }
  });

  it('asserts exact player-to-team counting stat reconciliation for every game file', () => {
    let checkedGames = 0;

    for (const filename of gameFiles) {
      const fullPath = path.join(GAMES_DIR, filename);
      const envelope = JSON.parse(fs.readFileSync(fullPath, 'utf8')) as GameDetailEnvelope;
      const data = envelope.data;

      if (!data.box_score) continue;
      checkedGames++;

      const awayPlayers = data.box_score.away_players || [];
      const homePlayers = data.box_score.home_players || [];
      const teamStats = data.team_stats || [];

      // Find team stats
      const awayPassingStat = teamStats.find((s) => s.stat_key === 'passing_yards');
      const homePassingStat = teamStats.find((s) => s.stat_key === 'passing_yards');
      const awayRushingStat = teamStats.find((s) => s.stat_key === 'rushing_yards');
      const homeRushingStat = teamStats.find((s) => s.stat_key === 'rushing_yards');
      const awayCompAttStat = teamStats.find((s) => s.stat_key === 'completions_attempts');
      const homeCompAttStat = teamStats.find((s) => s.stat_key === 'completions_attempts');

      // 1. Passing yards
      if (awayPassingStat && typeof awayPassingStat.away_value === 'number') {
        const awayPassSum = awayPlayers.reduce((acc, p) => acc + (p.passing_yards || 0), 0);
        expect(awayPassSum, `${filename} away passing yards mismatch`).toBe(awayPassingStat.away_value);
      }
      if (homePassingStat && typeof homePassingStat.home_value === 'number') {
        const homePassSum = homePlayers.reduce((acc, p) => acc + (p.passing_yards || 0), 0);
        expect(homePassSum, `${filename} home passing yards mismatch`).toBe(homePassingStat.home_value);
      }

      // 2. Rushing yards
      if (awayRushingStat && typeof awayRushingStat.away_value === 'number') {
        const awayRushSum = awayPlayers.reduce((acc, p) => acc + (p.rushing_yards || 0), 0);
        expect(awayRushSum, `${filename} away rushing yards mismatch`).toBe(awayRushingStat.away_value);
      }
      if (homeRushingStat && typeof homeRushingStat.home_value === 'number') {
        const homeRushSum = homePlayers.reduce((acc, p) => acc + (p.rushing_yards || 0), 0);
        expect(homeRushSum, `${filename} home rushing yards mismatch`).toBe(homeRushingStat.home_value);
      }

      // 3. Completions / attempts
      if (awayCompAttStat && typeof awayCompAttStat.away_value === 'string') {
        const [expComp, expAtt] = awayCompAttStat.away_value.split('/').map(Number);
        const awayCompSum = awayPlayers.reduce((acc, p) => acc + (p.completions || 0), 0);
        const awayAttSum = awayPlayers.reduce((acc, p) => acc + (p.attempts || 0), 0);
        expect(awayCompSum, `${filename} away completions mismatch`).toBe(expComp);
        expect(awayAttSum, `${filename} away attempts mismatch`).toBe(expAtt);
      }
      if (homeCompAttStat && typeof homeCompAttStat.home_value === 'string') {
        const [expComp, expAtt] = homeCompAttStat.home_value.split('/').map(Number);
        const homeCompSum = homePlayers.reduce((acc, p) => acc + (p.completions || 0), 0);
        const homeAttSum = homePlayers.reduce((acc, p) => acc + (p.attempts || 0), 0);
        expect(homeCompSum, `${filename} home completions mismatch`).toBe(expComp);
        expect(homeAttSum, `${filename} home attempts mismatch`).toBe(expAtt);
      }

      // 4. Player category integrity
      for (const p of [...awayPlayers, ...homePlayers]) {
        expect(p.playerId).toBeTruthy();
        expect(p.playerName).toBeTruthy();
        if (p.categories.includes('passing')) {
          expect(p.attempts).toBeGreaterThanOrEqual(0);
          expect(p.completions).toBeGreaterThanOrEqual(0);
        }
        if (p.categories.includes('rushing')) {
          expect(p.carries).toBeGreaterThanOrEqual(0);
        }
        if (p.categories.includes('receiving')) {
          expect(p.receptions).toBeGreaterThanOrEqual(0);
        }
      }
    }

    expect(checkedGames).toBe(gameFiles.length);
  });
});

describe('Cross-Dataset Parity: games/<id>.json vs matchups_current_week.json', () => {
  it('asserts that has_game_detail and has_box_score match physical file existence for all matchups', () => {
    expect(fs.existsSync(MATCHUPS_FILE), 'matchups_current_week.json must exist').toBe(true);
    const rawMatchups = JSON.parse(fs.readFileSync(MATCHUPS_FILE, 'utf8')) as { matchups: any[] };
    const mismatches: string[] = [];

    for (const m of rawMatchups.matchups) {
      const gid = m.game_id;
      const gameFilePath = path.join(GAMES_DIR, `${gid}.json`);
      const fileExists = fs.existsSync(gameFilePath);

      if (Boolean(m.has_game_detail) !== fileExists) {
        mismatches.push(
          `[${gid}] has_game_detail (${m.has_game_detail}) does not match game file existence (${fileExists})`
        );
      }
      if (Boolean(m.has_box_score) !== fileExists) {
        mismatches.push(
          `[${gid}] has_box_score (${m.has_box_score}) does not match game file existence (${fileExists})`
        );
      }
    }

    expect(
      mismatches,
      `Reported ${mismatches.length} flag-to-file mismatch(es):\n${mismatches.join('\n')}`
    ).toEqual([]);
  });

  it('asserts complete parity across all games with has_game_detail=true without stopping at first mismatch', () => {
    expect(fs.existsSync(MATCHUPS_FILE), 'matchups_current_week.json must exist').toBe(true);
    const rawMatchups = JSON.parse(fs.readFileSync(MATCHUPS_FILE, 'utf8')) as { matchups: any[] };
    const matchupsWithDetail = rawMatchups.matchups.filter((m) => m.has_game_detail);

    expect(matchupsWithDetail.length).toBeGreaterThanOrEqual(100);

    const mismatches: string[] = [];

    for (const m of matchupsWithDetail) {
      const gid = m.game_id;
      const gameFilePath = path.join(GAMES_DIR, `${gid}.json`);

      if (!fs.existsSync(gameFilePath)) {
        mismatches.push(`[${gid}] has_game_detail=true but game detail file does not exist`);
        continue;
      }

      const env = JSON.parse(fs.readFileSync(gameFilePath, 'utf8')) as GameDetailEnvelope;
      const d = env.data;

      // 1. Scores
      if (d.home_team.score !== m.home_score) {
        mismatches.push(`[${gid}] home_score mismatch: game=${d.home_team.score} vs matchup=${m.home_score}`);
      }
      if (d.away_team.score !== m.away_score) {
        mismatches.push(`[${gid}] away_score mismatch: game=${d.away_team.score} vs matchup=${m.away_score}`);
      }

      // 2. Winner
      const expHomeWinner = m.home_score > m.away_score;
      const expAwayWinner = m.away_score > m.home_score;
      if (d.home_team.is_winner !== expHomeWinner) {
        mismatches.push(`[${gid}] home_team.is_winner mismatch: game=${d.home_team.is_winner} vs expected=${expHomeWinner}`);
      }
      if (d.away_team.is_winner !== expAwayWinner) {
        mismatches.push(`[${gid}] away_team.is_winner mismatch: game=${d.away_team.is_winner} vs expected=${expAwayWinner}`);
      }
      if (m.actual_winner) {
        const expWinnerName = expHomeWinner ? m.home_team_name : expAwayWinner ? m.away_team_name : 'Tie';
        if (m.actual_winner !== expWinnerName) {
          mismatches.push(`[${gid}] actual_winner mismatch: matchup=${m.actual_winner} vs expected=${expWinnerName}`);
        }
      }

      // 3. Shared forecast figures
      if (d.forecast) {
        if (d.forecast.projected_margin !== null && d.forecast.projected_margin !== undefined &&
            m.projected_margin !== null && m.projected_margin !== undefined) {
          if (Math.abs(d.forecast.projected_margin - m.projected_margin) > 0.05) {
            mismatches.push(`[${gid}] projected_margin mismatch: game=${d.forecast.projected_margin} vs matchup=${m.projected_margin}`);
          }
        }
        if (d.forecast.home_win_prob !== null && d.forecast.home_win_prob !== undefined &&
            m.home_win_prob !== null && m.home_win_prob !== undefined) {
          if (Math.abs(d.forecast.home_win_prob - m.home_win_prob) > 0.005) {
            mismatches.push(`[${gid}] home_win_prob mismatch: game=${d.forecast.home_win_prob} vs matchup=${m.home_win_prob}`);
          }
        }
        if (d.forecast.home_power_rating !== null && d.forecast.home_power_rating !== undefined &&
            m.home_power_rating !== null && m.home_power_rating !== undefined &&
            Math.abs(d.forecast.home_power_rating - m.home_power_rating) > 0.05) {
          mismatches.push(`[${gid}] home_power_rating mismatch: game=${d.forecast.home_power_rating} vs matchup=${m.home_power_rating}`);
        }
        if (d.forecast.away_power_rating !== null && d.forecast.away_power_rating !== undefined &&
            m.away_power_rating !== null && m.away_power_rating !== undefined &&
            Math.abs(d.forecast.away_power_rating - m.away_power_rating) > 0.05) {
          mismatches.push(`[${gid}] away_power_rating mismatch: game=${d.forecast.away_power_rating} vs matchup=${m.away_power_rating}`);
        }
      }
    }

    expect(
      mismatches,
      `Reported ${mismatches.length} parity mismatch(es) between games/*.json and matchups_current_week.json:\n${mismatches.join('\n')}`
    ).toEqual([]);
  });
});

describe('In-Repo Zero-Betting Vocabulary Term Guard', () => {
  const FORBIDDEN_BETTING_RE =
    /\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\b/i;

  it('asserts zero banned betting terminology in all completed game files', () => {
    const violations: string[] = [];

    for (const filename of gameFiles) {
      const fullPath = path.join(GAMES_DIR, filename);
      const rawText = fs.readFileSync(fullPath, 'utf8');
      const match = rawText.match(FORBIDDEN_BETTING_RE);
      if (match) {
        violations.push(`${filename}: matched forbidden betting term '${match[0]}'`);
      }
    }

    expect(violations).toEqual([]);
  });

  it('asserts zero banned betting terminology in matchups_current_week.json', () => {
    if (!fs.existsSync(MATCHUPS_FILE)) return;
    const rawText = fs.readFileSync(MATCHUPS_FILE, 'utf8');
    const match = rawText.match(FORBIDDEN_BETTING_RE);
    expect(match, `matchups_current_week.json contains forbidden term: ${match?.[0]}`).toBeNull();
  });

  it('asserts zero banned betting terminology in gameDetailTypes.ts', () => {
    if (!fs.existsSync(TYPES_FILE)) return;
    const rawText = fs.readFileSync(TYPES_FILE, 'utf8');
    const match = rawText.match(FORBIDDEN_BETTING_RE);
    expect(match, `gameDetailTypes.ts contains forbidden term: ${match?.[0]}`).toBeNull();
  });

  it('asserts zero banned betting terminology in GameDetailModal.tsx', () => {
    if (!fs.existsSync(MODAL_FILE)) return;
    const rawText = fs.readFileSync(MODAL_FILE, 'utf8');
    const match = rawText.match(FORBIDDEN_BETTING_RE);
    expect(match, `GameDetailModal.tsx contains forbidden term: ${match?.[0]}`).toBeNull();
  });
});
