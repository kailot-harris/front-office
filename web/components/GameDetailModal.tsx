'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Award,
  ChevronDown,
  ChevronUp,
  Clock,
  GitBranch,
  Info,
  Layers,
  Loader2,
  RotateCcw,
  ShieldCheck,
  X,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import { MISSING_VALUE, num } from '@/lib/format';
import {
  ContextSplitItem,
  EfficiencyFactorItem,
  EnteringBaseline,
  GameDetailEnvelope,
  GameDetailPayload,
  GameExplainabilityPayload,
  InactivePlayerRow,
  MarginWaterfallStep,
  PlayerBoxRow,
  TeamBoxTotals,
  XgboostShapFactor,
  XgboostShapPayload,
} from '@/lib/gameDetailTypes';
import { MatchupGame, ProjectionBasis } from '@/lib/matchupTypes';
import { TeamLogo } from '@/components/TeamLogo';

export interface GameDetailModalProps {
  matchup: MatchupGame | null;
  slateLabel?: string | null;
  onClose: () => void;
  returnFocusTo?: HTMLElement | null;
}

type SortField =
  | 'minutes'
  | 'points'
  | 'fg_pct'
  | 'fg3_pct'
  | 'ft_pct'
  | 'oreb'
  | 'dreb'
  | 'reb'
  | 'ast'
  | 'stl'
  | 'blk'
  | 'tov'
  | 'pf'
  | 'plus_minus'
  | 'efg_pct'
  | 'ts_pct'
  | 'game_score';

type SortDirection = 'asc' | 'desc';

type DetailSectionTab = 'box_score' | 'four_factors' | 'context_splits' | 'attribution';

interface BoxColumnDef {
  key: SortField;
  shortLabel: string;
  ariaLabel: string;
}

const SORTABLE_COLUMNS: readonly BoxColumnDef[] = [
  { key: 'minutes', shortLabel: 'MIN', ariaLabel: 'Minutes (MIN)' },
  { key: 'points', shortLabel: 'PTS', ariaLabel: 'Points (PTS)' },
  { key: 'reb', shortLabel: 'REB', ariaLabel: 'Rebounds (REB)' },
  { key: 'ast', shortLabel: 'AST', ariaLabel: 'Assists (AST)' },
  { key: 'stl', shortLabel: 'STL', ariaLabel: 'Steals (STL)' },
  { key: 'blk', shortLabel: 'BLK', ariaLabel: 'Blocks (BLK)' },
  { key: 'tov', shortLabel: 'TOV', ariaLabel: 'Turnovers (TOV)' },
  { key: 'pf', shortLabel: 'PF', ariaLabel: 'Personal fouls (PF)' },
  { key: 'plus_minus', shortLabel: '+/-', ariaLabel: 'Plus-minus (+/-)' },
  { key: 'efg_pct', shortLabel: 'eFG%', ariaLabel: 'Effective field goal percentage (eFG%)' },
  { key: 'ts_pct', shortLabel: 'TS%', ariaLabel: 'True shooting percentage (TS%)' },
  { key: 'game_score', shortLabel: 'GmSc', ariaLabel: 'Game Score (GmSc)' },
];

const BASIS_LABEL: Record<ProjectionBasis, { short: string; tone: string }> = {
  logged_model_margin: {
    short: 'Logged model',
    tone: 'bg-accent-500/10 text-accent-400 border-accent-500/30',
  },
  margin_from_logged_win_prob: {
    short: 'Logged model',
    tone: 'bg-accent-500/10 text-accent-400 border-accent-500/30',
  },
  primary_ensemble: {
    short: 'Primary ensemble',
    tone: 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30',
  },
  team_rating_differential: {
    short: 'Team ratings',
    tone: 'bg-sky-500/10 text-sky-300 border-sky-500/30',
  },
};

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ');

function getFocusableElements(container: HTMLElement): HTMLElement[] {
  const candidates = Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR));
  return candidates.filter((el) => {
    if (el.hasAttribute('disabled')) return false;
    if (el.closest('[hidden], [inert]')) return false;
    const style = window.getComputedStyle(el);
    return style.display !== 'none' && style.visibility !== 'hidden';
  });
}

function isFiniteNum(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function formatPct(value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  return `${value.toFixed(1)}%`;
}

function formatFactorValue(
  value: number | null | undefined,
  unit: EfficiencyFactorItem['unit'],
): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  if (unit === 'pct') return `${value.toFixed(1)}%`;
  return value.toFixed(1);
}

function formatFactorUnit(unit: EfficiencyFactorItem['unit']): string {
  switch (unit) {
    case 'pct':
      return '%';
    case 'per100fga':
      return 'per 100 FGA';
    case 'per100poss':
      return 'per 100 poss';
    case 'poss48':
      return 'poss / 48m';
  }
}

function resolveFactorLabel(item: EfficiencyFactorItem): string {
  if (
    item.key === 'fta_rate' &&
    !item.label.toLowerCase().includes('attempts per 100 field-goal attempts')
  ) {
    return 'Free-throw attempt rate (attempts per 100 field-goal attempts)';
  }
  return item.label;
}

function formatSplitValue(value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  return Number.isInteger(value) ? String(value) : value.toFixed(1);
}

function formatPlayerMinutes(minutes: number | null | undefined): string {
  if (!isFiniteNum(minutes)) return MISSING_VALUE;
  if (minutes === 0) return '<1';
  return Number.isInteger(minutes) ? String(minutes) : minutes.toFixed(1);
}

function formatPlusMinus(value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  if (value > 0) return `+${value}`;
  return String(value);
}

function unwrapEnvelope(raw: unknown): GameDetailPayload {
  if (raw && typeof raw === 'object' && 'data' in raw) {
    const candidate = (raw as GameDetailEnvelope).data;
    if (candidate && typeof candidate === 'object' && 'game_id' in candidate) {
      return candidate;
    }
  }
  return raw as GameDetailPayload;
}

function sortPlayers(
  players: PlayerBoxRow[],
  field: SortField,
  direction: SortDirection,
): PlayerBoxRow[] {
  return [...players].sort((a, b) => {
    const aVal = a[field];
    const bVal = b[field];
    const aValid = isFiniteNum(aVal);
    const bValid = isFiniteNum(bVal);

    if (!aValid && !bValid) {
      return b.minutes - a.minutes || b.points - a.points || a.playerName.localeCompare(b.playerName);
    }
    if (!aValid) return 1;
    if (!bValid) return -1;
    if (aVal !== bVal) {
      return direction === 'asc' ? aVal - bVal : bVal - aVal;
    }
    return b.minutes - a.minutes || b.points - a.points || a.playerName.localeCompare(b.playerName);
  });
}

function getFactorAdvantage(item: EfficiencyFactorItem): 'away' | 'home' | 'even' {
  if (item.higher_is_better === null) return 'even';
  if (!isFiniteNum(item.away_value) || !isFiniteNum(item.home_value)) return 'even';
  if (item.away_value === item.home_value) return 'even';
  const awayHigher = item.away_value > item.home_value;
  if (item.higher_is_better) {
    return awayHigher ? 'away' : 'home';
  }
  return awayHigher ? 'home' : 'away';
}

interface FactorComparisonRowProps {
  item: EfficiencyFactorItem;
  awayAbbr: string;
  homeAbbr: string;
}

const FactorComparisonRow: React.FC<FactorComparisonRowProps> = ({
  item,
  awayAbbr,
  homeAbbr,
}) => {
  const advantage = getFactorAdvantage(item);
  const awayVal = isFiniteNum(item.away_value) ? Math.max(0, item.away_value) : 0;
  const homeVal = isFiniteNum(item.home_value) ? Math.max(0, item.home_value) : 0;
  const maxVal = Math.max(awayVal, homeVal);
  const scaleMax = maxVal > 0 ? maxVal * 1.12 : 1;
  const awayBarPct = isFiniteNum(item.away_value) ? Math.min(100, (awayVal / scaleMax) * 100) : 0;
  const homeBarPct = isFiniteNum(item.home_value) ? Math.min(100, (homeVal / scaleMax) * 100) : 0;

  return (
    <tr className="border-t border-slate-800/80 align-top">
      <th scope="row" className="py-2 px-3 text-left font-normal">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold text-white">{resolveFactorLabel(item)}</span>
          <span className="text-xs font-mono text-slate-400 px-1.5 py-0.5 rounded bg-surface border border-slate-800">
            {formatFactorUnit(item.unit)}
          </span>
        </div>
        <p className="text-xs text-slate-400 mt-0.5 leading-snug">{item.description}</p>
      </th>
      <td
        className={`py-2 px-3 text-right font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'away' ? 'text-emerald-400 font-bold' : 'text-slate-200'
        }`}
      >
        {formatFactorValue(item.away_value, item.unit)}
      </td>
      <td className="py-2 px-3 min-w-[140px] sm:min-w-[180px]" aria-hidden="true">
        <div className="flex items-center gap-1 h-4 mt-0.5">
          <div className="w-1/2 h-2.5 bg-surface rounded-l-full overflow-hidden flex justify-end border border-slate-800/80 border-r-0">
            <div
              className={`h-full rounded-l-full transition-all ${
                advantage === 'away'
                  ? 'bg-emerald-400'
                  : item.higher_is_better === null
                    ? 'bg-accent-400'
                    : 'bg-slate-500'
              }`}
              style={{ width: `${awayBarPct}%` }}
            />
          </div>
          <div className="w-px h-4 bg-slate-600 flex-shrink-0" />
          <div className="w-1/2 h-2.5 bg-surface rounded-r-full overflow-hidden flex justify-start border border-slate-800/80 border-l-0">
            <div
              className={`h-full rounded-r-full transition-all ${
                advantage === 'home'
                  ? 'bg-emerald-400'
                  : item.higher_is_better === null
                    ? 'bg-accent-400'
                    : 'bg-slate-500'
              }`}
              style={{ width: `${homeBarPct}%` }}
            />
          </div>
        </div>
        <div className="flex justify-between text-xs font-mono text-slate-500 mt-0.5">
          <span>{awayAbbr}</span>
          <span>{homeAbbr}</span>
        </div>
      </td>
      <td
        className={`py-2 px-3 text-left font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'home' ? 'text-emerald-400 font-bold' : 'text-slate-200'
        }`}
      >
        {formatFactorValue(item.home_value, item.unit)}
      </td>
    </tr>
  );
};

interface ContextSplitCardProps {
  item: ContextSplitItem;
  awayAbbr: string;
  homeAbbr: string;
}

const ContextSplitCard: React.FC<ContextSplitCardProps> = ({ item, awayAbbr, homeAbbr }) => {
  const awayValid = isFiniteNum(item.away_value);
  const homeValid = isFiniteNum(item.home_value);
  const awayBetter = awayValid && homeValid && item.away_value! > item.home_value!;
  const homeBetter = awayValid && homeValid && item.home_value! > item.away_value!;
  const total =
    (awayValid ? Math.max(0, item.away_value!) : 0) +
    (homeValid ? Math.max(0, item.home_value!) : 0);
  const awayShare = total > 0 && awayValid ? (Math.max(0, item.away_value!) / total) * 100 : 50;

  return (
    <div className="bg-surface/70 border border-slate-800 rounded-xl p-3 space-y-2">
      <div className="text-xs font-semibold text-slate-300">{item.label}</div>
      <div className="flex items-baseline justify-between font-mono tabular-nums">
        <div className="flex items-baseline gap-1.5">
          <span className="text-xs text-slate-500">{awayAbbr}</span>
          <span className={`text-sm font-bold ${awayBetter ? 'text-emerald-400' : 'text-white'}`}>
            {formatSplitValue(item.away_value)}
          </span>
        </div>
        <div className="flex items-baseline gap-1.5">
          <span className={`text-sm font-bold ${homeBetter ? 'text-emerald-400' : 'text-white'}`}>
            {formatSplitValue(item.home_value)}
          </span>
          <span className="text-xs text-slate-500">{homeAbbr}</span>
        </div>
      </div>
      <div className="w-full h-1.5 rounded-full bg-slate-800 overflow-hidden flex" aria-hidden="true">
        {awayValid || homeValid ? (
          <>
            <div
              className={`h-full ${awayBetter ? 'bg-emerald-400' : 'bg-accent-400/70'}`}
              style={{ width: `${awayShare}%` }}
            />
            <div
              className={`h-full ${homeBetter ? 'bg-emerald-400' : 'bg-slate-600'}`}
              style={{ width: `${100 - awayShare}%` }}
            />
          </>
        ) : null}
      </div>
    </div>
  );
};

interface PlayerTableRowsProps {
  players: PlayerBoxRow[];
  showStarterTag: boolean;
}

const PlayerTableRows: React.FC<PlayerTableRowsProps> = ({ players, showStarterTag }) => (
  <>
    {players.map((p) => (
      <tr key={p.playerId} className="border-t border-slate-800/80 hover:bg-slate-800/30">
        <th
          scope="row"
          className="sticky left-0 z-10 bg-surface-raised/95 px-2.5 py-1.5 text-left font-medium text-white whitespace-nowrap border-r border-slate-800/60"
        >
          <div className="flex items-center gap-1.5">
            <span>{p.playerName}</span>
            {p.jersey && <span className="text-xs font-mono text-slate-500">#{p.jersey}</span>}
            {p.position && (
              <span className="text-xs font-mono text-slate-400 px-1 rounded bg-surface border border-slate-800">
                {p.position}
              </span>
            )}
            {showStarterTag && p.starter && (
              <span className="text-xs font-mono text-accent-400 px-1 rounded bg-accent-500/10 border border-accent-500/20">
                S
              </span>
            )}
          </div>
        </th>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {formatPlayerMinutes(p.minutes)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums font-bold text-white whitespace-nowrap">
          {p.points}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.fgm}-{p.fga}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.fg_pct)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.fg3m}-{p.fg3a}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.fg3_pct)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.ftm}-{p.fta}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.ft_pct)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.oreb}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.dreb}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {p.reb}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {p.ast}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.stl}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.blk}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.tov}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.pf}
        </td>
        <td
          className={`px-1.5 py-1.5 text-right font-mono tabular-nums whitespace-nowrap ${
            !isFiniteNum(p.plus_minus) || p.plus_minus === 0
              ? 'text-slate-400'
              : p.plus_minus > 0
                ? 'text-emerald-400'
                : 'text-rose-400'
          }`}
        >
          {formatPlusMinus(p.plus_minus)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.efg_pct)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.ts_pct)}
        </td>
        <td className="px-1.5 py-1.5 text-right font-mono tabular-nums text-accent-400 font-semibold whitespace-nowrap">
          {num(p.game_score, 1)}
        </td>
      </tr>
    ))}
  </>
);

function renderSortIcon(isSorted: boolean, direction: SortDirection): React.ReactNode {
  if (!isSorted) {
    return <ArrowUpDown className="w-3 h-3 text-slate-500 flex-shrink-0" aria-hidden="true" />;
  }
  return direction === 'asc' ? (
    <ArrowUp className="w-3 h-3 text-accent-400 flex-shrink-0" aria-hidden="true" />
  ) : (
    <ArrowDown className="w-3 h-3 text-accent-400 flex-shrink-0" aria-hidden="true" />
  );
}

const PROVENANCE_META: Record<
  NonNullable<GameExplainabilityPayload['logged_forecast']>['log_source'],
  { pill: string; badgeClass: string; containerClass: string }
> = {
  LOGGED_PREGAME: {
    pill: 'Logged Pre-Game',
    badgeClass: 'bg-emerald-500/15 text-emerald-300 border-emerald-500/30',
    containerClass: 'bg-emerald-500/5 border-emerald-500/25',
  },
  BACKTEST_PREWEEK: {
    pill: 'Backtest · Pre-Week',
    badgeClass: 'bg-amber-500/15 text-amber-300 border-amber-500/30',
    containerClass: 'bg-amber-500/5 border-amber-500/25',
  },
  BACKTEST_SEEDED: {
    pill: 'Backtest · Seeded',
    badgeClass: 'bg-slate-700/70 text-slate-200 border-slate-600',
    containerClass: 'bg-slate-800/50 border-slate-700',
  },
};

const BASELINE_FACTOR_ORDER = ['efg_pct', 'tov_pct', 'oreb_pct', 'fta_rate', 'ortg'] as const;

const BASELINE_FACTOR_META: Record<string, { label: string; isPct: boolean }> = {
  efg_pct: { label: 'Effective FG% (eFG%)', isPct: true },
  tov_pct: { label: 'Turnover Rate (TOV%)', isPct: true },
  oreb_pct: { label: 'Offensive Reb% (OREB%)', isPct: true },
  fta_rate: { label: 'FT Attempt Rate (FTA/FGA)', isPct: false },
  ortg: { label: 'Offensive Rating (ORtg)', isPct: false },
};

/** Formats finite signed decimals without `-0.00` artifacts. */
function formatSignedNumber(value: number | null | undefined, decimals = 2): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  const absFixed = Math.abs(value).toFixed(decimals);
  if (Number(absFixed) === 0) return absFixed;
  return `${value > 0 ? '+' : '-'}${absFixed}`;
}

/** Formats probability in `[0, 1]` as percentage string with one decimal. */
function formatProbPct(value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  return `${(value * 100).toFixed(1)}%`;
}

/** Returns verbatim Section 4.2 provenance banner copy for logged/backtest forecasts. */
function getProvenanceMessage(explainability: GameExplainabilityPayload): string | null {
  const logged = explainability.logged_forecast;
  if (!logged) return null;

  switch (logged.log_source) {
    case 'LOGGED_PREGAME':
      return explainability.margin_waterfall === null
        ? 'Forecast recorded before the game. The ratings behind it were not stored, so only the recorded forecast is shown.'
        : 'Forecast recorded before the game.';
    case 'BACKTEST_PREWEEK':
      return 'Backtest. Logging was unavailable that day; this forecast was rebuilt afterwards from ratings published before the game.';
    case 'BACKTEST_SEEDED':
      return 'Backtest computed after the game from later ratings. Not a pre-game forecast.';
  }
}

function formatBaselineMetric(key: string, value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  return BASELINE_FACTOR_META[key]?.isPct ? `${value.toFixed(1)}%` : value.toFixed(1);
}

function formatBaselineDiff(key: string, value: number | null | undefined): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  const signed = formatSignedNumber(value, 1);
  return BASELINE_FACTOR_META[key]?.isPct ? `${signed}%` : signed;
}

function formatShapFeatureValue(value: number): string {
  if (!isFiniteNum(value)) return MISSING_VALUE;
  return Number.isInteger(value) ? String(value) : value.toFixed(2);
}

function sortBaselineFactors(
  factors: EnteringBaseline['factors'],
): EnteringBaseline['factors'] {
  const rankMap = new Map<string, number>(BASELINE_FACTOR_ORDER.map((k, idx) => [k, idx]));
  return [...factors].sort((a, b) => {
    const ra = rankMap.get(a.key) ?? BASELINE_FACTOR_ORDER.length;
    const rb = rankMap.get(b.key) ?? BASELINE_FACTOR_ORDER.length;
    if (ra !== rb) return ra - rb;
    return a.key.localeCompare(b.key);
  });
}

interface AttributionSectionProps {
  explainability: GameExplainabilityPayload;
  awayAbbr: string;
  homeAbbr: string;
  isCompleted: boolean;
  hasBoxScoreData: boolean;
  missingBoxMessage: string;
}

const ProvenanceBanner: React.FC<{ explainability: GameExplainabilityPayload }> = ({
  explainability,
}) => {
  const logged = explainability.logged_forecast;
  const isPrimaryLive = explainability.projection_basis === 'primary_ensemble';

  if (!logged && !isPrimaryLive) return null;

  if (!logged) {
    return (
      <section
        aria-label="Forecast provenance"
        className="rounded-xl border border-emerald-500/25 bg-emerald-500/5 px-3.5 py-2.5 flex flex-wrap items-center justify-between gap-2"
      >
        <div className="flex items-center gap-2">
          <ShieldCheck className="w-4 h-4 text-emerald-300 flex-shrink-0" aria-hidden="true" />
          <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold border bg-emerald-500/15 text-emerald-300 border-emerald-500/30">
            Live Primary Ensemble Ratings
          </span>
        </div>
        <span className="text-xs text-slate-300">
          Computed directly from active Primary Ensemble team and roster ratings.
        </span>
      </section>
    );
  }

  const meta = PROVENANCE_META[logged.log_source];
  const provenanceCopy = getProvenanceMessage(explainability);
  const hasBrier = isFiniteNum(logged.brier_component);
  const hasLogLoss = isFiniteNum(logged.log_loss_component);

  return (
    <section
      aria-label="Forecast provenance"
      className={`rounded-xl border px-3.5 py-2.5 space-y-1.5 ${meta.containerClass}`}
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <ShieldCheck className="w-4 h-4 text-slate-200 flex-shrink-0" aria-hidden="true" />
          <span
            className={`px-2 py-0.5 rounded-full text-xs font-mono font-semibold border ${meta.badgeClass}`}
          >
            {meta.pill}
          </span>
          {isPrimaryLive && (
            <span className="px-2 py-0.5 rounded-full text-xs font-mono border bg-slate-800/80 text-slate-200 border-slate-700">
              Live Primary Ensemble Ratings
            </span>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-3 text-xs font-mono tabular-nums text-slate-300">
          <span>Recorded: {logged.prediction_timestamp}</span>
          {hasBrier && <span>Brier: {logged.brier_component!.toFixed(4)}</span>}
          {hasLogLoss && <span>Log Loss: {logged.log_loss_component!.toFixed(4)}</span>}
        </div>
      </div>
      {provenanceCopy && <p className="text-xs text-slate-200 leading-relaxed">{provenanceCopy}</p>}
    </section>
  );
};

const PrimaryWaterfallCard: React.FC<{
  explainability: GameExplainabilityPayload;
  awayAbbr: string;
  homeAbbr: string;
}> = ({ explainability, awayAbbr, homeAbbr }) => {
  const steps: MarginWaterfallStep[] = explainability.margin_waterfall ?? [];
  const hasSteps = steps.length > 0;
  const maxAbs = hasSteps ? Math.max(...steps.map((s) => Math.abs(s.points)), 0.5) : 1;

  return (
    <section
      aria-labelledby="primary-waterfall-heading"
      className="bg-surface/60 border border-slate-800 rounded-xl p-3.5 space-y-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <Layers className="w-4 h-4 text-emerald-400 flex-shrink-0" aria-hidden="true" />
          <h3 id="primary-waterfall-heading" className="text-sm font-bold text-white">
            Primary Ensemble Margin Waterfall
          </h3>
          <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold border bg-emerald-500/15 text-emerald-300 border-emerald-500/30">
            Primary Ensemble
          </span>
        </div>

        <div className="flex flex-wrap items-center gap-2 text-xs font-mono tabular-nums">
          <span className="px-2 py-0.5 rounded bg-slate-900/80 border border-slate-800 text-slate-200">
            {homeAbbr} Margin: {formatSignedNumber(explainability.predicted_margin, 2)} pts
          </span>
          <span className="px-2 py-0.5 rounded bg-slate-900/80 border border-slate-800 text-slate-200">
            {homeAbbr} Win Prob: {formatProbPct(explainability.predicted_home_win_prob)}
          </span>
          <span className="px-2 py-0.5 rounded bg-slate-900/80 border border-slate-800 text-slate-300">
            σ = {isFiniteNum(explainability.sigma_game) ? explainability.sigma_game.toFixed(1) : MISSING_VALUE}{' '}
            · Φ(margin / sigma_game)
          </span>
        </div>
      </div>

      {hasSteps ? (
        <div className="space-y-2">
          <div className="flex items-center justify-between text-[11px] font-mono text-slate-400 px-1">
            <span>← Toward {awayAbbr}</span>
            <span>0.0 pts</span>
            <span>Toward {homeAbbr} →</span>
          </div>

          <div className="divide-y divide-slate-800/80 border border-slate-800 rounded-lg overflow-hidden bg-slate-950/35">
            {steps.map((step) => {
              const widthPct = Math.min(50, (Math.abs(step.points) / maxAbs) * 50);
              const isPositive = step.points >= 0;
              const isRounding = step.key === 'rounding';

              return (
                <div
                  key={step.key}
                  aria-label={`${step.label}: ${formatSignedNumber(step.points, 2)} points`}
                  className="px-3 py-2 grid grid-cols-1 sm:grid-cols-12 items-center gap-2 text-xs"
                >
                  <div className="sm:col-span-5 min-w-0">
                    <div className="flex flex-wrap items-center gap-1.5">
                      <span className="font-semibold text-slate-200">{step.label}</span>
                      {isRounding && (
                        <span className="px-1.5 py-0.5 rounded text-[10px] font-mono bg-slate-800 text-slate-300 border border-slate-700">
                          Arithmetic residual
                        </span>
                      )}
                    </div>
                    {step.detail && (
                      <p className="text-[11px] text-slate-400 truncate" title={step.detail}>
                        {step.detail}
                      </p>
                    )}
                  </div>

                  <div className="sm:col-span-5 flex items-center" aria-hidden="true">
                    <div className="relative w-full h-2.5 rounded-full bg-slate-900 overflow-hidden">
                      <div className="absolute left-1/2 top-0 bottom-0 w-px bg-slate-700" />
                      {isPositive ? (
                        <div
                          className="absolute top-0 bottom-0 bg-emerald-400/80 rounded-r-full"
                          style={{ left: '50%', width: `${widthPct}%` }}
                        />
                      ) : (
                        <div
                          className="absolute top-0 bottom-0 bg-sky-400/80 rounded-l-full"
                          style={{ left: `${50 - widthPct}%`, width: `${widthPct}%` }}
                        />
                      )}
                    </div>
                  </div>

                  <div
                    className={`sm:col-span-2 text-right font-mono tabular-nums font-semibold ${
                      isPositive ? 'text-emerald-300' : 'text-sky-300'
                    }`}
                  >
                    {formatSignedNumber(step.points, 2)} pts
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      ) : (
        <div className="px-3 py-2.5 rounded-lg bg-slate-900/60 border border-slate-800 text-xs text-slate-300">
          Component waterfall steps are unavailable for this projection. The stored{' '}
          {homeAbbr} margin ({formatSignedNumber(explainability.predicted_margin, 2)} pts) and win
          probability ({formatProbPct(explainability.predicted_home_win_prob)}) shown above reflect
          the recorded forecast.
        </div>
      )}
    </section>
  );
};

const SecondaryShapCard: React.FC<{
  xgboostShap: XgboostShapPayload | null | undefined;
  awayAbbr: string;
  homeAbbr: string;
}> = ({ xgboostShap, awayAbbr, homeAbbr }) => {
  const [showAllShap, setShowAllShap] = useState<boolean>(false);

  const sortedFactors: XgboostShapFactor[] = useMemo(() => {
    if (!xgboostShap) return [];
    return [...xgboostShap.factors].sort(
      (a, b) => Math.abs(b.shap_log_odds) - Math.abs(a.shap_log_odds),
    );
  }, [xgboostShap]);

  const maxAbsShap = useMemo(() => {
    if (sortedFactors.length === 0) return 0.25;
    return Math.max(...sortedFactors.map((f) => Math.abs(f.shap_log_odds)), 0.05);
  }, [sortedFactors]);

  const visibleFactors = showAllShap ? sortedFactors : sortedFactors.slice(0, 6);

  return (
    <section
      aria-labelledby="secondary-shap-heading"
      className="bg-surface/60 border border-violet-500/25 rounded-xl p-3.5 space-y-3"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div className="flex flex-wrap items-center gap-2">
          <GitBranch className="w-4 h-4 text-violet-300 flex-shrink-0" aria-hidden="true" />
          <h3 id="secondary-shap-heading" className="text-sm font-bold text-white">
            Secondary Diagnostic Model: XGBoost Feature Fusion (TreeSHAP)
          </h3>
          <span className="px-2 py-0.5 rounded-full text-xs font-mono font-semibold border bg-violet-500/15 text-violet-300 border-violet-500/30">
            Secondary Diagnostic Model
          </span>
        </div>

        {xgboostShap && (
          <div className="flex flex-wrap items-center gap-2 text-xs font-mono tabular-nums">
            <span className="px-2 py-0.5 rounded bg-violet-500/10 border border-violet-500/30 text-violet-200 font-semibold">
              {homeAbbr} Diagnostic Win Prob: {formatProbPct(xgboostShap.predicted_home_win_prob)}
            </span>
          </div>
        )}
      </div>

      <p className="px-2.5 py-1.5 rounded-lg bg-violet-500/5 border border-violet-500/20 text-[11px] text-slate-300 leading-relaxed">
        Independent 13-feature XGBoost diagnostic trained on prior seasons — reported strictly for
        feature attribution and never blended or averaged into Primary Ensemble projections.
      </p>

      {xgboostShap ? (
        <div className="space-y-2.5">
          <div className="flex flex-wrap items-center justify-between gap-2 text-xs font-mono tabular-nums text-slate-300">
            <span>
              {xgboostShap.model_label} · Trained: {xgboostShap.train_seasons_label} · L
              {xgboostShap.window_games} window ({awayAbbr} {xgboostShap.away_prior_games_n}g /{' '}
              {homeAbbr} {xgboostShap.home_prior_games_n}g)
            </span>
            <span>
              Base logit {formatSignedNumber(xgboostShap.base_value_log_odds, 3)} → Total logit{' '}
              {formatSignedNumber(xgboostShap.total_log_odds, 3)}
            </span>
          </div>

          <div className="overflow-x-auto border border-slate-800 rounded-lg bg-slate-950/35">
            <table
              className="w-full text-xs border-collapse"
              aria-label="Secondary Diagnostic Model TreeSHAP feature contributions"
            >
              <thead>
                <tr className="bg-slate-900/70 text-[11px] font-mono uppercase text-slate-400 border-b border-slate-800">
                  <th scope="col" className="text-left px-3 py-1.5 font-semibold">
                    Feature
                  </th>
                  <th scope="col" className="text-right px-2.5 py-1.5 font-semibold whitespace-nowrap">
                    Raw Value
                  </th>
                  <th
                    scope="col"
                    className="text-center px-2.5 py-1.5 font-semibold hidden sm:table-cell"
                  >
                    Direction ({awayAbbr} / {homeAbbr})
                  </th>
                  <th scope="col" className="text-right px-2.5 py-1.5 font-semibold whitespace-nowrap">
                    SHAP Logit
                  </th>
                  <th scope="col" className="text-right px-3 py-1.5 font-semibold whitespace-nowrap">
                    Δ Prob (pp)
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/70">
                {visibleFactors.map((factor) => {
                  const widthPct = Math.min(50, (Math.abs(factor.shap_log_odds) / maxAbsShap) * 50);
                  const isPositive = factor.shap_log_odds >= 0;

                  return (
                    <tr key={factor.feature} className="hover:bg-slate-800/30">
                      <td className="px-3 py-1.5 font-medium text-slate-200">{factor.label}</td>
                      <td className="px-2.5 py-1.5 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
                        {formatShapFeatureValue(factor.feature_value)}
                      </td>
                      <td className="px-2.5 py-1.5 hidden sm:table-cell w-36" aria-hidden="true">
                        <div className="relative w-full h-2 rounded-full bg-slate-900 overflow-hidden">
                          <div className="absolute left-1/2 top-0 bottom-0 w-px bg-slate-700" />
                          {isPositive ? (
                            <div
                              className="absolute top-0 bottom-0 bg-violet-400/85 rounded-r-full"
                              style={{ left: '50%', width: `${widthPct}%` }}
                            />
                          ) : (
                            <div
                              className="absolute top-0 bottom-0 bg-sky-400/85 rounded-l-full"
                              style={{ left: `${50 - widthPct}%`, width: `${widthPct}%` }}
                            />
                          )}
                        </div>
                      </td>
                      <td
                        className={`px-2.5 py-1.5 text-right font-mono tabular-nums whitespace-nowrap ${
                          isPositive ? 'text-violet-300' : 'text-sky-300'
                        }`}
                      >
                        {formatSignedNumber(factor.shap_log_odds, 3)}
                      </td>
                      <td
                        className={`px-3 py-1.5 text-right font-mono tabular-nums whitespace-nowrap font-semibold ${
                          isPositive ? 'text-violet-200' : 'text-sky-200'
                        }`}
                      >
                        {formatSignedNumber(factor.shap_prob_approx * 100, 1)} pp
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          {sortedFactors.length > 6 && (
            <div className="flex justify-end">
              <button
                type="button"
                aria-expanded={showAllShap}
                onClick={() => setShowAllShap((prev) => !prev)}
                className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg bg-slate-800/80 hover:bg-slate-800 border border-slate-700 text-xs font-mono text-slate-200 transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
              >
                {showAllShap ? (
                  <>
                    <ChevronUp className="w-3.5 h-3.5" aria-hidden="true" />
                    <span>Show top 6</span>
                  </>
                ) : (
                  <>
                    <ChevronDown className="w-3.5 h-3.5" aria-hidden="true" />
                    <span>Show all {sortedFactors.length}</span>
                  </>
                )}
              </button>
            </div>
          )}
        </div>
      ) : (
        <div className="px-3 py-2.5 rounded-lg bg-slate-900/60 border border-slate-800 text-xs text-slate-300">
          Secondary XGBoost TreeSHAP diagnostic is unavailable for this matchup due to insufficient
          prior-season or entering-game rolling history (prior_games_n = 0 early in the season).
        </div>
      )}
    </section>
  );
};

const EnteringBaselinesCard: React.FC<{
  baselines: EnteringBaseline[] | null;
  isCompleted: boolean;
}> = ({ baselines, isCompleted }) => {
  const hasBaselines = Boolean(baselines && baselines.length > 0);

  return (
    <section
      aria-labelledby="entering-baselines-heading"
      className="bg-surface/60 border border-slate-800 rounded-xl p-3.5 space-y-2.5"
    >
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 id="entering-baselines-heading" className="text-sm font-bold text-white">
          Entering Baselines vs Realized Four Factors
        </h3>
        <span className="text-[11px] font-mono text-slate-400">
          {isCompleted
            ? 'Entering pre-game baselines vs realized box-score efficiency'
            : 'Entering pre-game baselines (realized values fill after final box score)'}
        </span>
      </div>

      {hasBaselines && baselines ? (
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-3">
          {baselines.map((team) => {
            const orderedFactors = sortBaselineFactors(team.factors);
            return (
              <div
                key={team.teamAbbr}
                className="border border-slate-800 rounded-lg overflow-hidden bg-slate-950/35"
              >
                <div className="px-3 py-1.5 bg-slate-900/80 border-b border-slate-800 flex items-center justify-between">
                  <span className="text-xs font-bold text-white font-mono">{team.teamAbbr}</span>
                  <span className="text-[11px] font-mono text-slate-300">
                    Prior games: {team.prior_games_n}
                  </span>
                </div>
                <table
                  className="w-full text-xs border-collapse"
                  aria-label={`${team.teamAbbr} entering baselines vs realized Four Factors`}
                >
                  <thead>
                    <tr className="text-[11px] font-mono uppercase text-slate-400 border-b border-slate-800">
                      <th scope="col" className="text-left px-3 py-1.5 font-semibold">
                        Factor
                      </th>
                      <th scope="col" className="text-right px-2 py-1.5 font-semibold">
                        Entering
                      </th>
                      <th scope="col" className="text-right px-2 py-1.5 font-semibold">
                        Realized
                      </th>
                      <th scope="col" className="text-right px-3 py-1.5 font-semibold">
                        Diff
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/70">
                    {orderedFactors.map((factor) => (
                      <tr key={factor.key}>
                        <td className="px-3 py-1.5 text-slate-200 font-medium">
                          {BASELINE_FACTOR_META[factor.key]?.label ?? factor.key}
                        </td>
                        <td className="px-2 py-1.5 text-right font-mono tabular-nums text-slate-300">
                          {formatBaselineMetric(factor.key, factor.entering)}
                        </td>
                        <td className="px-2 py-1.5 text-right font-mono tabular-nums text-white font-semibold">
                          {formatBaselineMetric(factor.key, factor.realized)}
                        </td>
                        <td
                          className={`px-3 py-1.5 text-right font-mono tabular-nums ${
                            isFiniteNum(factor.difference)
                              ? factor.difference > 0
                                ? 'text-emerald-300'
                                : factor.difference < 0
                                  ? 'text-sky-300'
                                  : 'text-slate-400'
                              : 'text-slate-500'
                          }`}
                        >
                          {formatBaselineDiff(factor.key, factor.difference)}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="px-3 py-2.5 rounded-lg bg-slate-900/60 border border-slate-800 text-xs text-slate-300">
          Entering baselines are unavailable for season openers or games with zero prior team
          history (prior_games_n = 0).
        </div>
      )}
    </section>
  );
};

const AttributionSection: React.FC<AttributionSectionProps> = ({
  explainability,
  awayAbbr,
  homeAbbr,
  isCompleted,
  hasBoxScoreData,
  missingBoxMessage,
}) => (
  <div
    id="section-panel-attribution"
    role="tabpanel"
    aria-labelledby="section-tab-attribution"
    className="space-y-3"
  >
    {!hasBoxScoreData && (
      <div className="px-3 py-2 rounded-lg bg-surface/60 border border-slate-800 flex items-center gap-2 text-xs text-slate-300">
        <Info className="w-4 h-4 text-accent-400 flex-shrink-0" aria-hidden="true" />
        <span>{missingBoxMessage}</span>
      </div>
    )}

    <ProvenanceBanner explainability={explainability} />

    <PrimaryWaterfallCard
      explainability={explainability}
      awayAbbr={awayAbbr}
      homeAbbr={homeAbbr}
    />

    <SecondaryShapCard
      xgboostShap={explainability.xgboost_shap}
      awayAbbr={awayAbbr}
      homeAbbr={homeAbbr}
    />

    <EnteringBaselinesCard
      baselines={explainability.entering_baselines}
      isCompleted={isCompleted}
    />
  </div>
);

/**
 * Accessible modal displaying empirical game box score, efficiency & Four
 * Factors, play-style context splits, and top performers per MatchupGame.
 */
export const GameDetailModal: React.FC<GameDetailModalProps> = ({
  matchup,
  slateLabel,
  onClose,
  returnFocusTo,
}) => {
  const [detail, setDetail] = useState<GameDetailPayload | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [retryToken, setRetryToken] = useState<number>(0);
  const [activeSection, setActiveSection] = useState<DetailSectionTab>('box_score');
  const [activeTeam, setActiveTeam] = useState<'away' | 'home'>('away');
  const [sortField, setSortField] = useState<SortField | null>(null);
  const [sortDirection, setSortDirection] = useState<SortDirection>('desc');

  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const restoredFocusRef = useRef<boolean>(false);
  const prevOpenRef = useRef<boolean>(false);

  const isOpen = matchup !== null;
  const gameId = matchup?.game_id ?? null;
  const hasGameDetail = matchup?.has_game_detail === true;
  const inlineExplainability = matchup?.explainability ?? null;
  const hasInlineExplainabilityOnly = Boolean(!hasGameDetail && inlineExplainability);

  const restoreOpenerFocus = useCallback(() => {
    if (restoredFocusRef.current) return;
    const target = returnFocusTo ?? openerRef.current;
    if (target && target.isConnected) {
      target.focus();
    }
    restoredFocusRef.current = true;
    openerRef.current = null;
  }, [returnFocusTo]);

  const handleClose = useCallback(() => {
    restoreOpenerFocus();
    onClose();
  }, [restoreOpenerFocus, onClose]);

  const handleRetry = useCallback(() => {
    closeButtonRef.current?.focus();
    setRetryToken((prev) => prev + 1);
  }, []);

  // Reset per-game UI state when switching games or closing.
  useEffect(() => {
    setDetail(null);
    setError(null);
    setActiveSection(hasInlineExplainabilityOnly ? 'attribution' : 'box_score');
    setActiveTeam('away');
    setSortField(null);
    setSortDirection('desc');
  }, [gameId, hasInlineExplainabilityOnly]);

  // If a detail file arrives without box_score while explainability is present,
  // default cleanly into Attribution & SHAP instead of leaving an empty box view.
  useEffect(() => {
    if (hasGameDetail && !loading && !error && detail && !detail.box_score) {
      if (detail.explainability ?? inlineExplainability) {
        setActiveSection('attribution');
      }
    }
  }, [hasGameDetail, loading, error, detail, inlineExplainability]);

  // Capture opener focus when opening and move focus inside the dialog;
  // restore focus if closed externally via `matchup={null}`.
  useEffect(() => {
    const wasOpen = prevOpenRef.current;
    prevOpenRef.current = isOpen;

    if (isOpen && !wasOpen) {
      restoredFocusRef.current = false;
      const activeEl = document.activeElement;
      if (returnFocusTo) {
        openerRef.current = returnFocusTo;
      } else if (
        activeEl instanceof HTMLElement &&
        (!dialogRef.current || !dialogRef.current.contains(activeEl))
      ) {
        openerRef.current = activeEl;
      }

      if (dialogRef.current && !dialogRef.current.contains(document.activeElement)) {
        if (closeButtonRef.current) {
          closeButtonRef.current.focus();
        } else {
          dialogRef.current.focus();
        }
      }
    } else if (isOpen && dialogRef.current && !dialogRef.current.contains(document.activeElement)) {
      if (closeButtonRef.current) {
        closeButtonRef.current.focus();
      } else {
        dialogRef.current.focus();
      }
    } else if (!isOpen && wasOpen) {
      restoreOpenerFocus();
    }
  }, [isOpen, returnFocusTo, restoreOpenerFocus]);

  // Trap Tab / Shift+Tab inside the dialog and handle Escape to close.
  useEffect(() => {
    if (!isOpen) return;

    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        handleClose();
        return;
      }

      if (e.key === 'Tab') {
        const dialogEl = dialogRef.current;
        if (!dialogEl) return;

        const focusables = getFocusableElements(dialogEl);
        if (focusables.length === 0) {
          e.preventDefault();
          dialogEl.focus();
          return;
        }

        const first = focusables[0];
        const last = focusables[focusables.length - 1];
        const active = document.activeElement instanceof HTMLElement ? document.activeElement : null;

        if (e.shiftKey) {
          if (!active || !dialogEl.contains(active) || active === first || active === dialogEl) {
            e.preventDefault();
            last.focus();
          }
        } else if (!active || !dialogEl.contains(active) || active === last) {
          e.preventDefault();
          first.focus();
        }
      }
    };

    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, [isOpen, handleClose]);

  // Conditionally fetch game detail ONLY when matchup.has_game_detail === true.
  useEffect(() => {
    if (!gameId || !hasGameDetail) {
      setLoading(false);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setError(null);

    const loadDetail = async () => {
      try {
        const res = await fetch(`${BASE_PATH}/data/games/${gameId}.json`);
        if (!res.ok) {
          if (res.status === 404 && hasGameDetail) {
            console.error(
              `[GameDetailModal] Contract violation: HTTP 404 for game ${gameId} while has_game_detail is true.`,
            );
          }
          throw new Error(`Unable to load game detail (HTTP ${res.status}).`);
        }

        const raw: unknown = await res.json();
        const payload = unwrapEnvelope(raw);
        if (!cancelled) {
          setDetail(payload);
          setLoading(false);
        }
      } catch (err: unknown) {
        if (!cancelled) {
          const message = err instanceof Error ? err.message : 'Failed to load game detail.';
          setError(message);
          setLoading(false);
        }
      }
    };

    void loadDetail();

    return () => {
      cancelled = true;
    };
  }, [gameId, hasGameDetail, retryToken]);

  const handleSortClick = useCallback(
    (field: SortField) => {
      if (sortField === field) {
        setSortDirection((prev) => (prev === 'desc' ? 'asc' : 'desc'));
      } else {
        setSortField(field);
        setSortDirection('desc');
      }
    },
    [sortField],
  );

  const activeBoxView = useMemo(() => {
    if (!detail?.box_score) return null;
    const isAway = activeTeam === 'away';
    const players = isAway ? detail.box_score.away_players : detail.box_score.home_players;
    const totals: TeamBoxTotals = isAway ? detail.box_score.away_totals : detail.box_score.home_totals;
    const inactive: InactivePlayerRow[] = isAway
      ? detail.box_score.away_inactive
      : detail.box_score.home_inactive;

    const starters = players.filter((p) => p.starter);
    const bench = players.filter((p) => !p.starter);
    const sortedAll = sortField ? sortPlayers(players, sortField, sortDirection) : null;

    return { players, starters, bench, sortedAll, totals, inactive };
  }, [detail, activeTeam, sortField, sortDirection]);

  if (!matchup) return null;

  const awayAbbr = detail?.away_team.teamAbbr ?? matchup.away_team;
  const homeAbbr = detail?.home_team.teamAbbr ?? matchup.home_team;
  const awayName = detail?.away_team.teamName ?? matchup.away_team_name;
  const homeName = detail?.home_team.teamName ?? matchup.home_team_name;
  const awayScore = detail?.away_team.score ?? matchup.away_score;
  const homeScore = detail?.home_team.score ?? matchup.home_score;
  const isCompleted = detail?.is_completed ?? matchup.is_completed;
  const gameDate = detail?.game_date ?? matchup.game_date;
  const weekday = detail?.weekday ?? matchup.weekday;
  const resolvedSlateLabel = detail?.slate_label ?? slateLabel ?? `Week ${matchup.slate}`;

  const awayIsWinner =
    detail?.away_team.is_winner ??
    (matchup.actual_winner !== null ? matchup.actual_winner === matchup.away_team : null);
  const homeIsWinner =
    detail?.home_team.is_winner ??
    (matchup.actual_winner !== null ? matchup.actual_winner === matchup.home_team : null);

  const winnerAbbr = awayIsWinner ? awayAbbr : homeIsWinner ? homeAbbr : matchup.actual_winner;

  const modelAheadTeam =
    matchup.predicted_winner ??
    (matchup.predicted_margin !== null
      ? matchup.predicted_margin >= 0
        ? matchup.home_team
        : matchup.away_team
      : null);

  const modelAheadProb =
    modelAheadTeam === matchup.home_team
      ? matchup.predicted_home_win_prob
      : modelAheadTeam === matchup.away_team
        ? matchup.predicted_away_win_prob
        : null;

  const basisInfo = matchup.projection_basis ? BASIS_LABEL[matchup.projection_basis] : null;
  const explainability = detail?.explainability ?? matchup.explainability ?? null;
  const hasExplainability = explainability !== null;
  const hasBoxScoreData = Boolean(hasGameDetail && !loading && !error && detail && detail.box_score);
  const showSectionTabs = Boolean(hasBoxScoreData || (!loading && !error && hasExplainability));
  const hasEfficiencyFactors = Boolean(
    hasBoxScoreData && detail?.efficiency_factors && detail.efficiency_factors.length > 0,
  );
  const hasContextSplits = Boolean(
    hasBoxScoreData && detail?.context_splits && detail.context_splits.length > 0,
  );
  const missingBoxMessage = !isCompleted
    ? 'Box score appears after the game.'
    : 'Final score recorded. The full box score is added on a later data refresh, usually within a day.';
  const columnMap = new Map(SORTABLE_COLUMNS.map((c) => [c.key, c]));

  const renderSortableHeader = (key: SortField) => {
    const col = columnMap.get(key)!;
    const isSorted = sortField === key;
    const ariaSort: 'ascending' | 'descending' | 'none' = isSorted
      ? sortDirection === 'asc'
        ? 'ascending'
        : 'descending'
      : 'none';

    return (
      <th
        key={key}
        scope="col"
        aria-sort={ariaSort}
        className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap"
      >
        <button
          type="button"
          onClick={() => handleSortClick(key)}
          aria-label={col.ariaLabel}
          className={`inline-flex items-center justify-end gap-1 rounded px-1 py-0.5 transition-colors hover:text-white focus:outline-none focus:ring-2 focus:ring-accent-400 ${
            isSorted ? 'text-accent-400 font-bold' : 'text-slate-300'
          }`}
        >
          <span>{col.shortLabel}</span>
          {renderSortIcon(isSorted, sortDirection)}
        </button>
      </th>
    );
  };

  return (
    <div
      data-testid="game-detail-backdrop"
      onClick={(e) => {
        if (e.target === e.currentTarget) handleClose();
      }}
      className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4 bg-surface/85 backdrop-blur-md"
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="game-detail-modal-title"
        tabIndex={-1}
        className={`relative w-full max-w-4xl ${
          showSectionTabs
            ? 'sm:h-[78vh] sm:max-h-[640px] max-h-[88vh]'
            : 'max-h-[80vh]'
        } bg-surface-raised border border-slate-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col focus:outline-none`}
      >
        {/* Modal Header */}
        <div
          className={`relative px-4 sm:px-5 pt-3.5 ${
            showSectionTabs ? 'pb-0' : 'pb-3.5'
          } bg-surface/70 border-b border-slate-800 space-y-2.5`}
        >
          <div className="flex flex-wrap items-center justify-between gap-2">
            <div className="flex flex-wrap items-center gap-2 text-xs font-mono">
              <span className="text-slate-300 font-semibold">
                {weekday} · {gameDate}
              </span>
              <span className="text-slate-500">·</span>
              <span className="text-slate-400">{resolvedSlateLabel}</span>
              {isCompleted ? (
                <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-200 border border-slate-700 uppercase">
                  Final
                </span>
              ) : (
                <span className="px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 inline-flex items-center gap-1 uppercase">
                  <Clock className="w-3 h-3" aria-hidden="true" />
                  <span>Scheduled</span>
                </span>
              )}
              {basisInfo && (
                <span
                  className={`px-2 py-0.5 rounded-full border text-xs font-mono ${basisInfo.tone}`}
                >
                  {basisInfo.short}
                </span>
              )}
            </div>

            <button
              ref={closeButtonRef}
              type="button"
              onClick={handleClose}
              aria-label="Close game detail modal"
              className="p-1.5 text-slate-400 hover:text-white hover:bg-slate-800 rounded-xl transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
            >
              <X className="w-5 h-5" aria-hidden="true" />
            </button>
          </div>

          <div className="flex flex-col md:flex-row md:items-center justify-between gap-3">
            <div className="flex-1 flex flex-wrap items-center justify-between gap-3">
              {/* Away Team */}
              <div className="flex items-center gap-2.5 min-w-0">
                <TeamLogo team={awayAbbr} size="md" />
                <div className="min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono uppercase text-slate-400">Away</span>
                    {awayIsWinner === true && (
                      <span className="text-xs font-mono font-semibold px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                        Winner
                      </span>
                    )}
                  </div>
                  <div
                    className={`text-sm sm:text-base font-bold truncate ${
                      awayIsWinner === true
                        ? 'text-white'
                        : isCompleted
                          ? 'text-slate-300'
                          : 'text-white'
                    }`}
                  >
                    {awayName} <span className="text-xs font-mono text-slate-400">({awayAbbr})</span>
                  </div>
                </div>
                <div
                  className={`text-xl sm:text-2xl font-black font-mono tabular-nums ml-2 ${
                    awayScore === null
                      ? 'text-slate-600'
                      : awayIsWinner === true
                        ? 'text-white'
                        : 'text-slate-400'
                  }`}
                >
                  {awayScore === null ? '–' : awayScore}
                </div>
              </div>

              <div className="text-center px-2">
                <h2
                  id="game-detail-modal-title"
                  className="text-sm sm:text-base font-bold text-slate-200 tracking-tight"
                >
                  {awayName} @ {homeName}
                </h2>
                <div className="text-xs font-mono text-slate-400 mt-0.5 flex flex-wrap items-center justify-center gap-1.5">
                  {modelAheadTeam && isFiniteNum(matchup.predicted_margin) ? (
                    <span>
                      Model had <strong className="text-accent-400">{modelAheadTeam}</strong> ahead
                      by {Math.abs(matchup.predicted_margin).toFixed(1)} pts
                      {isFiniteNum(modelAheadProb)
                        ? ` (${(modelAheadProb * 100).toFixed(1)}% win prob)`
                        : ''}
                    </span>
                  ) : (
                    <span>No pre-game projection recorded</span>
                  )}
                  {isCompleted && winnerAbbr && (
                    <span>
                      · <strong className="text-white">{winnerAbbr}</strong> won
                    </span>
                  )}
                  {isCompleted && matchup.prediction_correct !== null && (
                    <span
                      className={`px-1.5 py-0.5 rounded border text-xs font-semibold ${
                        matchup.prediction_correct
                          ? 'bg-accent-500/10 text-accent-400 border-accent-500/30'
                          : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
                      }`}
                    >
                      {matchup.prediction_correct ? 'Correct' : 'Miss'}
                    </span>
                  )}
                </div>
              </div>

              {/* Home Team */}
              <div className="flex items-center gap-2.5 min-w-0">
                <div
                  className={`text-xl sm:text-2xl font-black font-mono tabular-nums mr-2 ${
                    homeScore === null
                      ? 'text-slate-600'
                      : homeIsWinner === true
                        ? 'text-white'
                        : 'text-slate-400'
                  }`}
                >
                  {homeScore === null ? '–' : homeScore}
                </div>
                <div className="min-w-0 text-left md:text-right">
                  <div className="flex items-center md:justify-end gap-2">
                    {homeIsWinner === true && (
                      <span className="text-xs font-mono font-semibold px-1.5 py-0.5 rounded bg-emerald-500/15 text-emerald-400 border border-emerald-500/30">
                        Winner
                      </span>
                    )}
                    <span className="text-xs font-mono uppercase text-slate-400">Home</span>
                  </div>
                  <div
                    className={`text-sm sm:text-base font-bold truncate ${
                      homeIsWinner === true
                        ? 'text-white'
                        : isCompleted
                          ? 'text-slate-300'
                          : 'text-white'
                    }`}
                  >
                    {homeName} <span className="text-xs font-mono text-slate-400">({homeAbbr})</span>
                  </div>
                </div>
                <TeamLogo team={homeAbbr} size="md" />
              </div>
            </div>
          </div>

          {/* Section Tabs Bar */}
          {showSectionTabs && (
            <div
              role="tablist"
              aria-label="Game detail sections"
              className="flex items-center gap-1 pt-1 -mb-px overflow-x-auto"
            >
              <button
                type="button"
                role="tab"
                id="section-tab-box-score"
                aria-selected={activeSection === 'box_score'}
                aria-controls="section-panel-box-score"
                onClick={() => setActiveSection('box_score')}
                className={`px-3.5 py-2 text-xs font-bold uppercase tracking-wider border-b-2 transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                  activeSection === 'box_score'
                    ? 'border-accent-400 text-accent-400 bg-accent-500/10 rounded-t-lg'
                    : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
                }`}
              >
                Box Score
              </button>
              {hasEfficiencyFactors && (
                <button
                  type="button"
                  role="tab"
                  id="section-tab-four-factors"
                  aria-selected={activeSection === 'four_factors'}
                  aria-controls="section-panel-four-factors"
                  onClick={() => setActiveSection('four_factors')}
                  className={`px-3.5 py-2 text-xs font-bold uppercase tracking-wider border-b-2 transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                    activeSection === 'four_factors'
                      ? 'border-accent-400 text-accent-400 bg-accent-500/10 rounded-t-lg'
                      : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
                  }`}
                >
                  Four Factors
                </button>
              )}
              {hasContextSplits && (
                <button
                  type="button"
                  role="tab"
                  id="section-tab-context-splits"
                  aria-selected={activeSection === 'context_splits'}
                  aria-controls="section-panel-context-splits"
                  onClick={() => setActiveSection('context_splits')}
                  className={`px-3.5 py-2 text-xs font-bold uppercase tracking-wider border-b-2 transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                    activeSection === 'context_splits'
                      ? 'border-accent-400 text-accent-400 bg-accent-500/10 rounded-t-lg'
                      : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
                  }`}
                >
                  Context Splits
                </button>
              )}
              {hasExplainability && (
                <button
                  type="button"
                  role="tab"
                  id="section-tab-attribution"
                  aria-selected={activeSection === 'attribution'}
                  aria-controls="section-panel-attribution"
                  onClick={() => setActiveSection('attribution')}
                  className={`px-3.5 py-2 text-xs font-bold uppercase tracking-wider border-b-2 transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                    activeSection === 'attribution'
                      ? 'border-accent-400 text-accent-400 bg-accent-500/10 rounded-t-lg'
                      : 'border-transparent text-slate-400 hover:text-slate-200 hover:border-slate-700'
                  }`}
                >
                  Attribution &amp; SHAP
                </button>
              )}
            </div>
          )}
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-4 sm:p-5 space-y-4">
          {/* Missing-data states (no fetch issued when explainability is absent) */}
          {!hasGameDetail && !hasExplainability && (
            <div className="py-12 px-4 flex flex-col items-center justify-center text-center gap-3 bg-surface/50 border border-slate-800 rounded-xl">
              <Info className="w-9 h-9 text-accent-400" aria-hidden="true" />
              <p className="text-sm font-semibold text-white max-w-md">{missingBoxMessage}</p>
            </div>
          )}

          {/* Loading state */}
          {hasGameDetail && loading && (
            <div
              role="status"
              className="py-16 flex flex-col items-center justify-center gap-3 text-slate-300"
            >
              <Loader2 className="w-8 h-8 animate-spin text-accent-400" aria-hidden="true" />
              <p className="text-sm font-medium">Loading empirical box score and efficiency factors...</p>
            </div>
          )}

          {/* Fetch Error / 404 Retry state */}
          {hasGameDetail && !loading && error && (
            <div
              role="alert"
              className="py-12 px-4 flex flex-col items-center justify-center text-center gap-4 bg-surface/50 border border-rose-500/30 rounded-xl"
            >
              <AlertCircle className="w-9 h-9 text-rose-400" aria-hidden="true" />
              <div className="space-y-1">
                <p className="text-sm font-semibold text-white">{error}</p>
                <p className="text-xs text-slate-400">
                  Game detail file could not be retrieved for {awayAbbr} @ {homeAbbr}.
                </p>
              </div>
              <button
                type="button"
                onClick={handleRetry}
                className="inline-flex items-center gap-2 px-4 py-2 rounded-lg bg-accent-600 hover:bg-accent-500 text-white text-xs font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
              >
                <RotateCcw className="w-3.5 h-3.5" aria-hidden="true" />
                <span>Retry</span>
              </button>
            </div>
          )}

          {/* Defensive fallback when detail file loaded without box_score or explainability */}
          {hasGameDetail && !loading && !error && detail && !detail.box_score && !hasExplainability && (
            <div className="py-12 px-4 flex flex-col items-center justify-center text-center gap-3 bg-surface/50 border border-slate-800 rounded-xl">
              <Info className="w-9 h-9 text-accent-400" aria-hidden="true" />
              <p className="text-sm font-semibold text-white max-w-md">{missingBoxMessage}</p>
            </div>
          )}

          {/* Missing Box Score tab panel when explainability enables tabs without box score */}
          {!loading && !error && !hasBoxScoreData && hasExplainability && activeSection === 'box_score' && (
            <div
              id="section-panel-box-score"
              role="tabpanel"
              aria-labelledby="section-tab-box-score"
              className="py-12 px-4 flex flex-col items-center justify-center text-center gap-3 bg-surface/50 border border-slate-800 rounded-xl"
            >
              <Info className="w-9 h-9 text-accent-400" aria-hidden="true" />
              <p className="text-sm font-semibold text-white max-w-md">{missingBoxMessage}</p>
            </div>
          )}

          {/* Empirical Phase 1 Detail */}
          {hasGameDetail && !loading && !error && detail && detail.box_score && (
            <>
              {/* Tab 1: Box Score + Top Performers */}
              {activeSection === 'box_score' && (
                <section
                  id="section-panel-box-score"
                  aria-labelledby="section-tab-box-score"
                  className="space-y-3.5"
                >
                  {/* Top Performers Strip */}
                  {detail.box_score.top_performers && detail.box_score.top_performers.length > 0 && (
                    <div className="space-y-2">
                      <div className="flex items-center gap-1.5 text-xs font-mono uppercase tracking-wider text-slate-400">
                        <Award className="w-3.5 h-3.5 text-amber-400" aria-hidden="true" />
                        <span>Top Performers · Hollinger Game Score</span>
                      </div>
                      <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                        {detail.box_score.top_performers.map((tp) => (
                          <div
                            key={`${tp.teamAbbr}-${tp.playerId}`}
                            className="bg-surface/60 border border-slate-800 rounded-xl px-3 py-2 flex items-center justify-between gap-2"
                          >
                            <div className="min-w-0">
                              <div className="flex items-center gap-1.5">
                                <span className="text-xs font-mono font-bold text-accent-400">
                                  {tp.teamAbbr}
                                </span>
                                <span className="text-xs font-semibold text-white truncate">
                                  {tp.playerName}
                                </span>
                              </div>
                              <div className="text-xs font-mono text-slate-400 tabular-nums mt-0.5">
                                {tp.points} PTS · {tp.reb} REB · {tp.ast} AST
                              </div>
                            </div>
                            <div className="text-right flex-shrink-0">
                              <div className="text-xs font-mono text-slate-500">GmSc</div>
                              <div className="text-sm font-bold font-mono text-amber-400 tabular-nums">
                                {num(tp.game_score, 1)}
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Player Box Score */}
                  {activeBoxView && (
                    <div aria-labelledby="player-box-score-heading" className="space-y-3">
                      <div className="flex flex-wrap items-center justify-between gap-2.5">
                        <div>
                          <h3
                            id="player-box-score-heading"
                            className="text-sm font-bold text-white uppercase tracking-wider font-mono"
                          >
                            Player Box Score
                          </h3>
                          <p className="text-xs text-slate-400 mt-0.5">
                            Click any stat header to sort active players. Active players under 30 seconds appear as &lt;1 min.
                          </p>
                        </div>

                        <div className="flex flex-wrap items-center gap-2">
                          {sortField !== null && (
                            <button
                              type="button"
                              onClick={() => {
                                setSortField(null);
                                setSortDirection('desc');
                              }}
                              className="px-2.5 py-1 rounded-lg text-xs font-mono text-slate-300 hover:text-white bg-surface border border-slate-700 transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
                            >
                              Group: Starters / Bench
                            </button>
                          )}

                          <div
                            role="tablist"
                            aria-label="Team box score"
                            className="inline-flex rounded-lg bg-surface p-1 border border-slate-800"
                          >
                            <button
                              type="button"
                              role="tab"
                              id="box-tab-away"
                              aria-selected={activeTeam === 'away'}
                              aria-controls="box-score-tabpanel"
                              onClick={() => setActiveTeam('away')}
                              className={`px-2.5 py-1 rounded-md text-xs font-mono font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                                activeTeam === 'away'
                                  ? 'bg-accent-600 text-white shadow-sm'
                                  : 'text-slate-400 hover:text-white'
                              }`}
                            >
                              {awayAbbr} · {awayName}
                            </button>
                            <button
                              type="button"
                              role="tab"
                              id="box-tab-home"
                              aria-selected={activeTeam === 'home'}
                              aria-controls="box-score-tabpanel"
                              onClick={() => setActiveTeam('home')}
                              className={`px-2.5 py-1 rounded-md text-xs font-mono font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400 ${
                                activeTeam === 'home'
                                  ? 'bg-accent-600 text-white shadow-sm'
                                  : 'text-slate-400 hover:text-white'
                              }`}
                            >
                              {homeAbbr} · {homeName}
                            </button>
                          </div>
                        </div>
                      </div>

                      <div
                        id="box-score-tabpanel"
                        role="tabpanel"
                        aria-labelledby={activeTeam === 'away' ? 'box-tab-away' : 'box-tab-home'}
                        className="space-y-3"
                      >
                        <div className="overflow-x-auto border border-slate-800 rounded-xl bg-surface/50">
                          <table className="w-full text-xs">
                            <caption className="sr-only">
                              {activeTeam === 'away' ? awayName : homeName} player box score
                            </caption>
                            <thead className="bg-surface text-slate-400 font-mono uppercase">
                              <tr>
                                <th
                                  scope="col"
                                  className="sticky left-0 z-20 bg-surface px-2.5 py-1.5 text-left font-semibold whitespace-nowrap border-r border-slate-800/60"
                                >
                                  Player
                                </th>
                                {renderSortableHeader('minutes')}
                                {renderSortableHeader('points')}
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  FG
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  FG%
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  3PT
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  3P%
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  FT
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  FT%
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  OREB
                                </th>
                                <th scope="col" className="px-1.5 py-1.5 text-right font-semibold whitespace-nowrap">
                                  DREB
                                </th>
                                {renderSortableHeader('reb')}
                                {renderSortableHeader('ast')}
                                {renderSortableHeader('stl')}
                                {renderSortableHeader('blk')}
                                {renderSortableHeader('tov')}
                                {renderSortableHeader('pf')}
                                {renderSortableHeader('plus_minus')}
                                {renderSortableHeader('efg_pct')}
                                {renderSortableHeader('ts_pct')}
                                {renderSortableHeader('game_score')}
                              </tr>
                            </thead>

                            {activeBoxView.sortedAll ? (
                              <tbody>
                                <PlayerTableRows players={activeBoxView.sortedAll} showStarterTag={true} />
                              </tbody>
                            ) : (
                              <>
                                {activeBoxView.starters.length > 0 && (
                                  <tbody>
                                    <tr className="bg-surface/80 border-t border-slate-800">
                                      <th
                                        colSpan={21}
                                        scope="rowgroup"
                                        className="px-2.5 py-1 text-left text-xs font-mono font-bold uppercase tracking-wider text-accent-400"
                                      >
                                        Starters
                                      </th>
                                    </tr>
                                    <PlayerTableRows players={activeBoxView.starters} showStarterTag={false} />
                                  </tbody>
                                )}
                                {activeBoxView.bench.length > 0 && (
                                  <tbody>
                                    <tr className="bg-surface/80 border-t border-slate-800">
                                      <th
                                        colSpan={21}
                                        scope="rowgroup"
                                        className="px-2.5 py-1 text-left text-xs font-mono font-bold uppercase tracking-wider text-slate-400"
                                      >
                                        Bench
                                      </th>
                                    </tr>
                                    <PlayerTableRows players={activeBoxView.bench} showStarterTag={false} />
                                  </tbody>
                                )}
                              </>
                            )}

                            <tfoot className="bg-surface/90 border-t-2 border-slate-700 font-mono tabular-nums font-bold text-white">
                              <tr>
                                <th
                                  scope="row"
                                  className="sticky left-0 z-10 bg-surface px-2.5 py-2 text-left whitespace-nowrap border-r border-slate-800/60"
                                >
                                  Team Totals
                                </th>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.minutes}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.points}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.fgm}-{activeBoxView.totals.fga}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {formatPct(activeBoxView.totals.fg_pct)}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.fg3m}-{activeBoxView.totals.fg3a}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {formatPct(activeBoxView.totals.fg3_pct)}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.ftm}-{activeBoxView.totals.fta}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {formatPct(activeBoxView.totals.ft_pct)}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.oreb}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.dreb}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.reb}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.ast}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.stl}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.blk}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.total_tov}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {activeBoxView.totals.pf}
                                </td>
                                <td className="px-1.5 py-2 text-right text-slate-500 whitespace-nowrap">
                                  {MISSING_VALUE}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {formatPct(activeBoxView.totals.efg_pct)}
                                </td>
                                <td className="px-1.5 py-2 text-right whitespace-nowrap">
                                  {formatPct(activeBoxView.totals.ts_pct)}
                                </td>
                                <td className="px-1.5 py-2 text-right text-slate-500 whitespace-nowrap">
                                  {MISSING_VALUE}
                                </td>
                              </tr>
                            </tfoot>
                          </table>
                        </div>

                        {activeBoxView.totals.team_tov > 0 && (
                          <p className="text-xs font-mono text-slate-400">
                            Note: Team Totals TOV ({activeBoxView.totals.total_tov}) includes{' '}
                            {activeBoxView.totals.team_tov} team turnover
                            {activeBoxView.totals.team_tov === 1 ? '' : 's'} not attributed to an
                            individual player ({activeBoxView.totals.tov} player +{' '}
                            {activeBoxView.totals.team_tov} team).
                          </p>
                        )}

                        {/* Collapsible Inactive Players List */}
                        {activeBoxView.inactive.length > 0 && (
                          <details className="group bg-surface/60 border border-slate-800 rounded-xl overflow-hidden">
                            <summary className="flex items-center justify-between px-3.5 py-2.5 cursor-pointer select-none text-xs font-mono font-bold uppercase tracking-wider text-slate-400 hover:text-slate-200 focus:outline-none focus:ring-2 focus:ring-accent-400">
                              <span>
                                Inactive / Did Not Play ({activeBoxView.inactive.length})
                              </span>
                              <ChevronDown
                                className="w-4 h-4 text-slate-500 transition-transform group-open:rotate-180"
                                aria-hidden="true"
                              />
                            </summary>
                            <div className="px-3.5 pb-3 pt-2 border-t border-slate-800/60">
                              <ul className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
                                {activeBoxView.inactive.map((row) => (
                                  <li
                                    key={row.playerId}
                                    className="flex items-center justify-between gap-2 text-xs bg-surface-raised/70 border border-slate-800/80 rounded-lg px-2.5 py-1.5"
                                  >
                                    <span className="text-slate-200 font-medium truncate">
                                      {row.playerName}
                                      {row.position ? (
                                        <span className="text-slate-500 font-mono ml-1.5">
                                          ({row.position})
                                        </span>
                                      ) : null}
                                    </span>
                                    <span className="text-slate-400 font-mono text-xs flex-shrink-0">
                                      {row.reason ?? 'No reason listed'}
                                    </span>
                                  </li>
                                ))}
                              </ul>
                            </div>
                          </details>
                        )}
                      </div>
                    </div>
                  )}
                </section>
              )}

              {/* Tab 2: Efficiency & Four Factors */}
              {activeSection === 'four_factors' && hasEfficiencyFactors && detail.efficiency_factors && (
                <section
                  id="section-panel-four-factors"
                  role="tabpanel"
                  aria-labelledby="section-tab-four-factors"
                  className="space-y-3"
                >
                  <div>
                    <h3
                      id="efficiency-factors-heading"
                      className="text-sm font-bold text-white uppercase tracking-wider font-mono"
                    >
                      Efficiency &amp; Four Factors
                    </h3>
                    <p className="text-xs text-slate-400 mt-0.5">
                      Team efficiency metrics and Dean Oliver Four Factors computed directly from box-score totals.
                    </p>
                  </div>

                  <div className="overflow-x-auto border border-slate-800 rounded-xl bg-surface/50">
                    <table className="w-full text-xs">
                      <caption className="sr-only">
                        Team Efficiency and Four Factors comparison between {awayName} and {homeName}
                      </caption>
                      <thead className="bg-surface text-slate-400 font-mono uppercase">
                        <tr>
                          <th scope="col" className="py-2 px-3 text-left font-semibold">
                            Factor &amp; Formula
                          </th>
                          <th scope="col" className="py-2 px-3 text-right font-semibold">
                            {awayAbbr}
                          </th>
                          <th
                            scope="col"
                            className="py-2 px-3 text-center font-semibold"
                            aria-hidden="true"
                          >
                            Comparison
                          </th>
                          <th scope="col" className="py-2 px-3 text-left font-semibold">
                            {homeAbbr}
                          </th>
                        </tr>
                      </thead>
                      <tbody>
                        {detail.efficiency_factors.map((item) => (
                          <FactorComparisonRow
                            key={item.key}
                            item={item}
                            awayAbbr={awayAbbr}
                            homeAbbr={homeAbbr}
                          />
                        ))}
                      </tbody>
                    </table>
                  </div>
                </section>
              )}

              {/* Tab 3: Play-Style & Context Splits */}
              {activeSection === 'context_splits' && hasContextSplits && detail.context_splits && (
                <section
                  id="section-panel-context-splits"
                  role="tabpanel"
                  aria-labelledby="section-tab-context-splits"
                  className="space-y-3"
                >
                  <div>
                    <h3
                      id="context-splits-heading"
                      className="text-sm font-bold text-white uppercase tracking-wider font-mono"
                    >
                      Play-Style &amp; Context Splits
                    </h3>
                    <p className="text-xs text-slate-400 mt-0.5">
                      Empirical game-flow scoring sources, bench production, and defensive activity.
                    </p>
                  </div>
                  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                    {detail.context_splits.map((split) => (
                      <ContextSplitCard
                        key={split.key}
                        item={split}
                        awayAbbr={awayAbbr}
                        homeAbbr={homeAbbr}
                      />
                    ))}
                  </div>
                </section>
              )}
            </>
          )}

          {/* Tier 2b Explainability Tab: Attribution & SHAP */}
          {!loading &&
            !error &&
            hasExplainability &&
            explainability &&
            activeSection === 'attribution' && (
              <AttributionSection
                key={gameId ?? 'none'}
                explainability={explainability}
                awayAbbr={awayAbbr}
                homeAbbr={homeAbbr}
                isCompleted={isCompleted}
                hasBoxScoreData={hasBoxScoreData}
                missingBoxMessage={missingBoxMessage}
              />
            )}
        </div>
      </div>
    </div>
  );
};
