/**
 * player_leaders.json (MLB-Analytics#163), written by build_player_leaders.R and
 * patched with newly finished regular-season games by tools/refresh_live_results.R.
 * Read at build time by app/players/page.tsx and rendered by LeagueLeadersPanel.tsx.
 */

export type LeaderPositionKey = 'all' | 'IF' | 'OF' | 'C_DH' | 'SP' | 'RP';

export type LeaderGroupKey = 'batting' | 'pitching';

/**
 * avg: 3-decimal batting/slugging/wOBA/OPS (.312 or 1.045);
 * era: 2-decimal pitching rate (2.45);
 * ip: baseball innings pitched (198.2);
 * pct: 0-1 fraction shown as percentage (24.5%);
 * int: counting integer (42).
 */
export type LeaderFormat = 'avg' | 'era' | 'ip' | 'pct' | 'int';

export interface LeaderRow {
  rank: number;
  player_id: string;
  player: string;
  team: string;
  position?: string | null;
  position_group?: 'IF' | 'OF' | 'C_DH' | 'SP' | 'RP' | null;
  value: number;
  /** Player's sample in the card's unit (PA, BF, appearances, or relief appearances). */
  sample: number;
  /** Scaled minimum the player had to reach. */
  required: number;
  team_games_played: number;
}

export interface LeaderCard {
  key: string;
  label: string;
  group: LeaderGroupKey;
  kind: 'rate' | 'counting' | 'statcast';
  format: LeaderFormat;
  lower_is_better: boolean;
  unit: 'pa' | 'bf' | 'app' | 'relief_app';
  unit_label: string;
  minimum_full_season: number;
  minimum_constant: string;
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
  group: LeaderGroupKey;
  unit: string;
  unit_label: string;
  minimum_full_season: number;
  constant: string;
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
    guts: Record<string, number>;
    team_games: Record<string, (string | number)[]>;
    batters: Record<string, (string | number | null)[]>;
    pitchers: Record<string, (string | number | null)[]>;
  };
}
