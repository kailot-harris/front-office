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

describe('In-Repo Zero-Betting Vocabulary Term Guard', () => {
  const FORBIDDEN_BETTING_RE =
    /\b(spread|projected_spread|point_spread|moneyline|sportsbook|over_under|parlay|wager|sharp_book|key_number_flag)\b/i;

  it('asserts zero banned betting terminology in all 145 game files', () => {
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
