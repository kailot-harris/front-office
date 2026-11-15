'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Award,
  Clock,
  Info,
  Loader2,
  RotateCcw,
  X,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import { MISSING_VALUE, num } from '@/lib/format';
import {
  ContextSplitItem,
  EfficiencyFactorItem,
  GameDetailEnvelope,
  GameDetailPayload,
  InactivePlayerRow,
  PlayerBoxRow,
  TeamBoxTotals,
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
      <th scope="row" className="py-3 px-3 text-left font-normal">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold text-white">{resolveFactorLabel(item)}</span>
          <span className="text-xs font-mono text-slate-400 px-1.5 py-0.5 rounded bg-surface border border-slate-800">
            {formatFactorUnit(item.unit)}
          </span>
        </div>
        <p className="text-xs text-slate-400 mt-1 leading-relaxed">{item.description}</p>
      </th>
      <td
        className={`py-3 px-3 text-right font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'away' ? 'text-emerald-400 font-bold' : 'text-slate-200'
        }`}
      >
        {formatFactorValue(item.away_value, item.unit)}
      </td>
      <td className="py-3 px-3 min-w-[150px] sm:min-w-[200px]" aria-hidden="true">
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
        <div className="flex justify-between text-xs font-mono text-slate-500 mt-1">
          <span>{awayAbbr}</span>
          <span>{homeAbbr}</span>
        </div>
      </td>
      <td
        className={`py-3 px-3 text-left font-mono text-xs tabular-nums whitespace-nowrap ${
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
          className="sticky left-0 z-10 bg-surface-raised/95 px-3 py-2 text-left font-medium text-white whitespace-nowrap border-r border-slate-800/60"
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
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {formatPlayerMinutes(p.minutes)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums font-bold text-white whitespace-nowrap">
          {p.points}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.fgm}-{p.fga}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.fg_pct)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.fg3m}-{p.fg3a}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.fg3_pct)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.ftm}-{p.fta}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.ft_pct)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.oreb}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.dreb}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {p.reb}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-200 whitespace-nowrap">
          {p.ast}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.stl}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.blk}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {p.tov}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-400 whitespace-nowrap">
          {p.pf}
        </td>
        <td
          className={`px-2 py-2 text-right font-mono tabular-nums whitespace-nowrap ${
            !isFiniteNum(p.plus_minus) || p.plus_minus === 0
              ? 'text-slate-400'
              : p.plus_minus > 0
                ? 'text-emerald-400'
                : 'text-rose-400'
          }`}
        >
          {formatPlusMinus(p.plus_minus)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.efg_pct)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-slate-300 whitespace-nowrap">
          {formatPct(p.ts_pct)}
        </td>
        <td className="px-2 py-2 text-right font-mono tabular-nums text-accent-400 font-semibold whitespace-nowrap">
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
    setActiveTeam('away');
    setSortField(null);
    setSortDirection('desc');
  }, [gameId]);

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
        className="px-2 py-2 text-right font-semibold whitespace-nowrap"
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
      className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-6 bg-surface/85 backdrop-blur-md"
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="game-detail-modal-title"
        tabIndex={-1}
        className="relative w-full max-w-6xl max-h-[92vh] bg-surface-raised border border-slate-800 rounded-2xl shadow-2xl overflow-hidden flex flex-col focus:outline-none"
      >
        {/* Modal Header */}
        <div className="relative px-4 sm:px-6 py-4 bg-surface/70 border-b border-slate-800 space-y-4">
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
              className="p-2 text-slate-400 hover:text-white hover:bg-slate-800 rounded-xl transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
            >
              <X className="w-5 h-5" aria-hidden="true" />
            </button>
          </div>

          <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
            <div className="flex-1 flex flex-wrap items-center justify-between gap-4">
              {/* Away Team */}
              <div className="flex items-center gap-3 min-w-0">
                <TeamLogo team={awayAbbr} size="lg" />
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
                    className={`text-base sm:text-lg font-bold truncate ${
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
                  className={`text-2xl sm:text-3xl font-black font-mono tabular-nums ml-2 ${
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
                <div className="text-xs font-mono text-slate-400 mt-1 flex flex-wrap items-center justify-center gap-2">
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
              <div className="flex items-center gap-3 min-w-0">
                <div
                  className={`text-2xl sm:text-3xl font-black font-mono tabular-nums mr-2 ${
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
                    className={`text-base sm:text-lg font-bold truncate ${
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
                <TeamLogo team={homeAbbr} size="lg" />
              </div>
            </div>
          </div>

          {/* Top Performers Strip */}
          {detail?.box_score && detail.box_score.top_performers.length > 0 && (
            <div className="pt-2 border-t border-slate-800/80 space-y-2">
              <div className="flex items-center gap-1.5 text-xs font-mono uppercase tracking-wider text-slate-400">
                <Award className="w-3.5 h-3.5 text-amber-400" aria-hidden="true" />
                <span>Top Performers · Hollinger Game Score</span>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-2.5">
                {detail.box_score.top_performers.map((tp) => (
                  <div
                    key={`${tp.teamAbbr}-${tp.playerId}`}
                    className="bg-surface-raised/80 border border-slate-800 rounded-xl px-3 py-2 flex items-center justify-between gap-2"
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
        </div>

        {/* Modal Body */}
        <div className="flex-1 overflow-y-auto p-4 sm:p-6 space-y-6">
          {/* Missing-data states (no fetch issued) */}
          {!hasGameDetail && (
            <div className="py-12 px-4 flex flex-col items-center justify-center text-center gap-3 bg-surface/50 border border-slate-800 rounded-xl">
              <Info className="w-9 h-9 text-accent-400" aria-hidden="true" />
              <p className="text-sm font-semibold text-white max-w-md">
                {!matchup.is_completed
                  ? 'Box score appears after the game.'
                  : 'Final score recorded. The full box score is added on a later data refresh, usually within a day.'}
              </p>
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

          {/* Defensive fallback when detail file loaded without box_score */}
          {hasGameDetail && !loading && !error && detail && !detail.box_score && (
            <div className="py-12 px-4 flex flex-col items-center justify-center text-center gap-3 bg-surface/50 border border-slate-800 rounded-xl">
              <Info className="w-9 h-9 text-accent-400" aria-hidden="true" />
              <p className="text-sm font-semibold text-white max-w-md">
                {!detail.is_completed
                  ? 'Box score appears after the game.'
                  : 'Final score recorded. The full box score is added on a later data refresh, usually within a day.'}
              </p>
            </div>
          )}

          {/* Empirical Phase 1 Detail */}
          {hasGameDetail && !loading && !error && detail && detail.box_score && (
            <>
              {/* Efficiency & Four Factors */}
              {detail.efficiency_factors && detail.efficiency_factors.length > 0 && (
                <section aria-labelledby="efficiency-factors-heading" className="space-y-3">
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
                          <th scope="col" className="py-2.5 px-3 text-left font-semibold">
                            Factor &amp; Formula
                          </th>
                          <th scope="col" className="py-2.5 px-3 text-right font-semibold">
                            {awayAbbr}
                          </th>
                          <th
                            scope="col"
                            className="py-2.5 px-3 text-center font-semibold"
                            aria-hidden="true"
                          >
                            Comparison
                          </th>
                          <th scope="col" className="py-2.5 px-3 text-left font-semibold">
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

              {/* Play-Style & Context Splits */}
              {detail.context_splits && detail.context_splits.length > 0 && (
                <section aria-labelledby="context-splits-heading" className="space-y-3">
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

              {/* Player Box Score */}
              {activeBoxView && (
                <section aria-labelledby="player-box-score-heading" className="space-y-3">
                  <div className="flex flex-wrap items-center justify-between gap-3">
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
                          className="px-2.5 py-1.5 rounded-lg text-xs font-mono text-slate-300 hover:text-white bg-surface border border-slate-700 transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400"
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
                          className={`px-3 py-1.5 rounded-md text-xs font-mono font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400 ${
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
                          className={`px-3 py-1.5 rounded-md text-xs font-mono font-semibold transition-colors focus:outline-none focus:ring-2 focus:ring-accent-400 ${
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
                    className="space-y-4"
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
                              className="sticky left-0 z-20 bg-surface px-3 py-2 text-left font-semibold whitespace-nowrap border-r border-slate-800/60"
                            >
                              Player
                            </th>
                            {renderSortableHeader('minutes')}
                            {renderSortableHeader('points')}
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              FG
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              FG%
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              3PT
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              3P%
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              FT
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              FT%
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
                              OREB
                            </th>
                            <th scope="col" className="px-2 py-2 text-right font-semibold whitespace-nowrap">
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
                                    className="px-3 py-1.5 text-left text-xs font-mono font-bold uppercase tracking-wider text-accent-400"
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
                                    className="px-3 py-1.5 text-left text-xs font-mono font-bold uppercase tracking-wider text-slate-400"
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
                              className="sticky left-0 z-10 bg-surface px-3 py-2.5 text-left whitespace-nowrap border-r border-slate-800/60"
                            >
                              Team Totals
                            </th>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.minutes}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.points}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.fgm}-{activeBoxView.totals.fga}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {formatPct(activeBoxView.totals.fg_pct)}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.fg3m}-{activeBoxView.totals.fg3a}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {formatPct(activeBoxView.totals.fg3_pct)}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.ftm}-{activeBoxView.totals.fta}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {formatPct(activeBoxView.totals.ft_pct)}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.oreb}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.dreb}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.reb}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.ast}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.stl}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.blk}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.total_tov}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {activeBoxView.totals.pf}
                            </td>
                            <td className="px-2 py-2.5 text-right text-slate-500 whitespace-nowrap">
                              {MISSING_VALUE}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {formatPct(activeBoxView.totals.efg_pct)}
                            </td>
                            <td className="px-2 py-2.5 text-right whitespace-nowrap">
                              {formatPct(activeBoxView.totals.ts_pct)}
                            </td>
                            <td className="px-2 py-2.5 text-right text-slate-500 whitespace-nowrap">
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

                    {/* Inactive Players List */}
                    {activeBoxView.inactive.length > 0 && (
                      <div className="bg-surface/60 border border-slate-800 rounded-xl p-3 space-y-2">
                        <div className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                          Inactive / Did Not Play ({activeBoxView.inactive.length})
                        </div>
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
                    )}
                  </div>
                </section>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
