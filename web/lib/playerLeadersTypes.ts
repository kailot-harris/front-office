/**
 * player_leaders.json (NBA_analytics#254), written by build_player_leaders.R and
 * patched with new box scores by tools/refresh_live_results.R. Read at build time
 * by app/players/page.tsx and shown by components/LeagueLeadersPanel.tsx.
 */

export type LeaderPositionKey = 'all' | 'G' | 'F' | 'C';

export type LeaderGroupKey = 'scoring' | 'shooting' | 'playmaking' | 'rebounding' | 'defense' | 'impact';

/** per_game: average; pct: a 0-1 fraction shown as a percentage; rate: already 0-100; rapm: points per 100 possessions. */
export type LeaderFormat = 'per_game' | 'pct' | 'rate' | 'rapm';

export interface LeaderRow {
  rank: number;
  player_id: string;
  player: string;
  team: string;
  position?: string | null;
  position_group?: 'G' | 'F' | 'C' | null;
  value: number;
  /** The player's sample in the card's unit (games, attempts, minutes or possessions per side). */
  sample: number;
  /** The scaled minimum the player had to reach. */
  required: number;
  team_games_played: number;
}

export interface LeaderCard {
  key: string;
  label: string;
  group: LeaderGroupKey;
  kind: 'per_game' | 'shooting' | 'rate' | 'rapm';
  format: LeaderFormat;
  lower_is_better: boolean;
  unit: string;
  unit_label: string;
  minimum_full_season: number;
  minimum_constant: string;
  /** A second bar in minutes (turnovers per game only). */
  minimum_minutes_full_season?: number | null;
  minimum_minutes_constant?: string | null;
  through_date: string | null;
  through_date_null_reason?: string | null;
  noise_note: boolean;
  noise_note_text?: string | null;
  status: 'ok' | 'not_enough_games';
  status_text?: string | null;
  null_reason?: string | null;
  candidates: number;
  qualified_count: Record<LeaderPositionKey, number>;
  leaders: Record<LeaderPositionKey, LeaderRow[]>;
}

export interface LeaderMinimum {
  key: string;
  label: string;
  unit: string;
  unit_label: string;
  minimum_full_season: number;
  constant: string;
  minimum_minutes_full_season?: number | null;
  minimum_minutes_constant?: string | null;
}

export interface LeaderMethods {
  scaling_rule: string;
  scaling_text: string;
  traded_players: string;
  position_note: string;
  ranking: string;
  noise_note: string;
  rate_formulas: Record<string, string>;
  refresh: string;
  sample: string;
  study_source_commit: string;
  base_games: number;
  minimums: LeaderMinimum[];
  nulls: string;
}

export interface PlayerLeadersPayload {
  schema_version: number;
  generated_at: string;
  season: string;
  through_date: string | null;
  position_filters: { key: LeaderPositionKey; label: string }[];
  groups: { key: LeaderGroupKey; label: string }[];
  cards: LeaderCard[];
  methods: LeaderMethods;
  sources: Record<string, string>;
  season_totals: {
    description: string;
    game_ids: string[];
    team_games: Record<string, (string | number)[]>;
    players: Record<string, (string | number | null)[]>;
  };
}
