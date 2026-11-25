/**
 * Shape of web/public/data/player_leaders.json (NFL_analytics#230), written by
 * build_player_leaders.R in the 09:00 pipeline and rebuilt (non-model cards only)
 * by tools/refresh_live_results.R in the evening score refreshes.
 */

export type LeaderGroupKey = 'passing' | 'rushing' | 'receiving' | 'defense' | 'impact';
export type LeaderKind = 'total' | 'per_game' | 'rate';
export type LeaderUnit = 'season_total' | 'games' | 'dropbacks' | 'designed_carries' | 'targets';
/**
 * per_game: yards per game; count: season total; epa_play: EPA per play;
 * cpoe: percentage points; pct: share 0-1; yards_play: yards per carry;
 * epa_total: season EPA total.
 */
export type LeaderFormat = 'per_game' | 'count' | 'epa_play' | 'cpoe' | 'pct' | 'yards_play' | 'epa_total';
export type LeaderStatus = 'ok' | 'not_enough_games' | 'unavailable';

export interface LeaderRow {
  rank: number;
  player_id: string;
  player: string;
  team: string;
  position: string | null;
  value: number;
  /** Qualifying sample (games, dropbacks, designed carries or targets); null on totals. */
  sample: number | null;
  /** Scaled minimum this player had to reach; null on totals. */
  required: number | null;
  /** Games played by the player's current team in this card's source. */
  team_games_played: number;
}

export interface LeaderCard {
  key: string;
  label: string;
  group: LeaderGroupKey;
  kind: LeaderKind;
  format: LeaderFormat;
  lower_is_better: boolean;
  unit: LeaderUnit;
  unit_label: string;
  /** Owner's full-season (17-game) minimum; null on season totals (no minimum). */
  minimum_full_season: number | null;
  minimum_constant: string | null;
  through_date: string | null;
  through_date_null_reason: string | null;
  noise_note: boolean;
  noise_note_text: string | null;
  status: LeaderStatus;
  status_text: string | null;
  null_reason: string | null;
  source: string;
  refresh: 'pipeline_and_evening' | 'pipeline_only';
  formula: string;
  candidates: number;
  qualified_count: number;
  excluded_no_value: number;
  notes: string | null;
  leaders: LeaderRow[];
}

export interface LeaderMinimumRow {
  key: string;
  label: string;
  group: LeaderGroupKey;
  unit: LeaderUnit;
  unit_label: string;
  minimum_full_season: number | null;
  constant: string | null;
  lower_is_better: boolean;
  formula: string;
}

export interface PlayerLeadersMethods {
  scaling_rule: string;
  scaling_text: string;
  traded_players: string;
  ranking: string;
  impact_note: string;
  noise_note: string;
  definitions: string;
  refresh: string;
  sample: string;
  not_available: string;
  study_source_commit: string;
  base_games: number;
  minimums: LeaderMinimumRow[];
  diagnostics: Record<string, number | string | null>;
  nulls: string;
}

export interface PlayerLeadersPayload {
  schema_version: number;
  generated_at: string;
  season: string;
  season_type: 'REG';
  through_date: string | null;
  groups: { key: LeaderGroupKey; label: string }[];
  cards: LeaderCard[];
  methods: PlayerLeadersMethods;
  sources: Record<string, string>;
}
