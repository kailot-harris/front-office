import { describe, it, expect } from 'vitest';
import { gameDetailEnvelopeSchema } from './schemas';
import { GameDetailEnvelope } from '@/lib/gameDetailTypes';

describe('GameDetailEnvelope schema validation', () => {
  it('validates a complete synthetic NFL GameDetailEnvelope', () => {
    const sample: GameDetailEnvelope = {
      schema_version: '1.0',
      generated_at: '2026-11-16T00:00:00Z',
      sport: 'nfl',
      endpoint: 'game_detail',
      season: 2026,
      season_label: '2026-2027',
      game_id: '2026_01_ARI_LAC',
      data: {
        game_id: '2026_01_ARI_LAC',
        season: 2026,
        season_label: '2026-2027',
        week: 1,
        week_label: 'Week 1',
        gameday: '2026-09-13',
        weekday: 'Sunday',
        gametime: '13:00',
        is_completed: true,
        has_box_score: true,
        away_team: {
          teamAbbr: 'ARI',
          teamName: 'Arizona Cardinals',
          score: 28,
          is_winner: true,
        },
        home_team: {
          teamAbbr: 'LAC',
          teamName: 'Los Angeles Chargers',
          score: 21,
          is_winner: false,
        },
        forecast: {
          projected_margin: -3.5,
          home_win_prob: 0.42,
          away_win_prob: 0.58,
          home_power_rating: 1.2,
          away_power_rating: 3.4,
          prediction_correct: true,
        },
        efficiency_factors: [
          {
            key: 'epa_per_play',
            label: 'EPA / Play',
            away_value: 0.12,
            home_value: -0.05,
            unit: 'epa',
            higher_is_better: true,
            description: 'Expected Points Added per offensive play',
          },
        ],
        team_stats: [
          {
            stat_key: 'total_yards',
            label: 'Total Yards',
            away_value: 393,
            home_value: 310,
          },
        ],
        leaders: [
          {
            category: 'passing',
            teamAbbr: 'ARI',
            playerId: '00-0035228',
            playerName: 'Kyler Murray',
            stat_line: '27/37, 277 YDS, 1 TD',
          },
        ],
        box_score: {
          away_players: [
            {
              playerId: '00-0035228',
              playerName: 'Kyler Murray',
              teamAbbr: 'ARI',
              position: 'QB',
              categories: ['passing', 'rushing'],
              snap_pct: 100,
              completions: 27,
              attempts: 37,
              passing_yards: 277,
              passing_tds: 1,
              passing_interceptions: 0,
              sacks_suffered: 1,
              sack_yards_lost: 0,
              passing_epa: 9.01,
              passing_cpoe: 4.61,
            },
          ],
          home_players: [],
        },
        injury_designations: [
          {
            playerId: '00-0036358',
            playerName: 'Justin Herbert',
            position: 'QB',
            designation: 'Questionable',
            body_part: 'Ankle',
            played: true,
          },
        ],
        explainability: null,
      },
    };

    const parseResult = gameDetailEnvelopeSchema.safeParse(sample);
    expect(parseResult.success).toBe(true);
  });
});
