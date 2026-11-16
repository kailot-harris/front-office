'use client';

import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertCircle,
  ArrowDown,
  ArrowUp,
  ArrowUpDown,
  Calendar,
  CheckCircle2,
  Clock,
  HelpCircle,
  Layers,
  Loader2,
  Shield,
  UserCheck,
  UserX,
  X,
} from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import { num, percent } from '@/lib/format';
import type {
  CategoryLeader,
  GameDetailEnvelope,
  InjuryDesignationRow,
  NflBoxCategory,
  NflEfficiencyFactorItem,
  NflGameDetailPayload,
  NflPlayerBoxRow,
  NflTeamComparisonItem,
} from '@/lib/gameDetailTypes';
import type { MatchupGame } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';

export interface GameDetailModalProps {
  matchup: MatchupGame | null;
  onClose: () => void;
  returnFocusTo?: HTMLElement | null;
}

export type DetailTab = 'overview' | 'comparison' | 'box_score';

type SortDirection = 'asc' | 'desc';

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

function unwrapEnvelope(raw: unknown): NflGameDetailPayload | null {
  if (raw && typeof raw === 'object' && 'data' in raw) {
    const candidate = (raw as GameDetailEnvelope).data;
    if (candidate && typeof candidate === 'object' && 'game_id' in candidate) {
      return candidate;
    }
  }
  if (raw && typeof raw === 'object' && 'game_id' in raw) {
    return raw as NflGameDetailPayload;
  }
  return null;
}

function formatFactorValue(val: number | null | undefined, unit: NflEfficiencyFactorItem['unit']): string {
  if (!isFiniteNum(val)) return '—';
  if (unit === 'pct') return `${val.toFixed(1)}%`;
  if (unit === 'yards') return `${val.toFixed(1)} yds`;
  return `${val > 0 ? '+' : ''}${val.toFixed(2)}`;
}

function getFactorAdvantage(item: NflEfficiencyFactorItem): 'away' | 'home' | 'even' {
  if (!isFiniteNum(item.away_value) || !isFiniteNum(item.home_value)) return 'even';
  if (item.away_value === item.home_value) return 'even';
  const awayHigher = item.away_value > item.home_value;
  if (item.higher_is_better) {
    return awayHigher ? 'away' : 'home';
  }
  return awayHigher ? 'home' : 'away';
}

interface FactorRowProps {
  item: NflEfficiencyFactorItem;
  awayAbbr: string;
  homeAbbr: string;
}

const FactorRow: React.FC<FactorRowProps> = ({ item, awayAbbr, homeAbbr }) => {
  const advantage = getFactorAdvantage(item);
  const awayVal = isFiniteNum(item.away_value) ? Math.max(0, item.away_value) : 0;
  const homeVal = isFiniteNum(item.home_value) ? Math.max(0, item.home_value) : 0;
  const maxVal = Math.max(awayVal, homeVal);
  const scaleMax = maxVal > 0 ? maxVal * 1.15 : 1;
  const awayBarPct = isFiniteNum(item.away_value) ? Math.min(100, (awayVal / scaleMax) * 100) : 0;
  const homeBarPct = isFiniteNum(item.home_value) ? Math.min(100, (homeVal / scaleMax) * 100) : 0;

  return (
    <tr className="border-t border-slate-800/80 align-middle hover:bg-slate-800/20">
      <th scope="row" className="py-2.5 px-3 text-left font-normal">
        <div className="flex flex-wrap items-center gap-2">
          <span className="text-xs font-semibold text-white">{item.label}</span>
          <span className="text-[10px] font-mono text-slate-400 px-1.5 py-0.5 rounded bg-slate-800/80 border border-slate-700/60 uppercase">
            {item.unit}
          </span>
        </div>
        {item.description && (
          <p className="text-[11px] text-slate-400 mt-0.5 leading-snug">{item.description}</p>
        )}
      </th>
      <td
        className={`py-2.5 px-3 text-right font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'away' ? 'text-emerald-400 font-bold' : 'text-slate-300'
        }`}
      >
        {formatFactorValue(item.away_value, item.unit)}
      </td>
      <td className="py-2.5 px-3 min-w-[130px] sm:min-w-[180px]" aria-hidden="true">
        <div className="flex items-center gap-1 h-3 mt-0.5">
          <div className="w-1/2 h-2 bg-slate-800 rounded-l-full overflow-hidden flex justify-end border border-slate-700/50 border-r-0">
            <div
              className={`h-full rounded-l-full transition-all ${
                advantage === 'away' ? 'bg-emerald-400' : 'bg-slate-600'
              }`}
              style={{ width: `${awayBarPct}%` }}
            />
          </div>
          <div className="w-px h-3.5 bg-slate-600 flex-shrink-0" />
          <div className="w-1/2 h-2 bg-slate-800 rounded-r-full overflow-hidden flex justify-start border border-slate-700/50 border-l-0">
            <div
              className={`h-full rounded-r-full transition-all ${
                advantage === 'home' ? 'bg-emerald-400' : 'bg-slate-600'
              }`}
              style={{ width: `${homeBarPct}%` }}
            />
          </div>
        </div>
        <div className="flex justify-between text-[10px] font-mono text-slate-500 mt-0.5">
          <span>{awayAbbr}</span>
          <span>{homeAbbr}</span>
        </div>
      </td>
      <td
        className={`py-2.5 px-3 text-left font-mono text-xs tabular-nums whitespace-nowrap ${
          advantage === 'home' ? 'text-emerald-400 font-bold' : 'text-slate-300'
        }`}
      >
        {formatFactorValue(item.home_value, item.unit)}
      </td>
    </tr>
  );
};

interface TeamComparisonRowProps {
  item: NflTeamComparisonItem;
  awayAbbr: string;
  homeAbbr: string;
}

const TeamComparisonRow: React.FC<TeamComparisonRowProps> = ({ item, awayAbbr, homeAbbr }) => {
  const awayNum = isFiniteNum(item.away_value) ? item.away_value : null;
  const homeNum = isFiniteNum(item.home_value) ? item.home_value : null;
  const isNumeric = awayNum !== null && homeNum !== null;
  const awayAdvantage = isNumeric && awayNum! > homeNum!;
  const homeAdvantage = isNumeric && homeNum! > awayNum!;

  const sumVal = isNumeric ? Math.max(1, Math.abs(awayNum!) + Math.abs(homeNum!)) : 1;
  const awayWidthPct = isNumeric ? Math.min(100, Math.max(5, (Math.abs(awayNum!) / sumVal) * 100)) : 50;
  const homeWidthPct = isNumeric ? Math.min(100, Math.max(5, (Math.abs(homeNum!) / sumVal) * 100)) : 50;

  return (
    <div className="bg-slate-950/40 border border-slate-800 rounded-xl p-3.5 space-y-2.5">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold text-slate-200">{item.label}</span>
      </div>
      <div className="flex items-baseline justify-between font-mono tabular-nums">
        <div className="flex items-baseline gap-1.5">
          <span className="text-[11px] text-slate-500">{awayAbbr}</span>
          <span className={`text-sm font-bold ${awayAdvantage ? 'text-emerald-400' : 'text-white'}`}>
            {item.away_value != null ? String(item.away_value) : '—'}
          </span>
        </div>
        <div className="flex items-baseline gap-1.5">
          <span className={`text-sm font-bold ${homeAdvantage ? 'text-emerald-400' : 'text-white'}`}>
            {item.home_value != null ? String(item.home_value) : '—'}
          </span>
          <span className="text-[11px] text-slate-500">{homeAbbr}</span>
        </div>
      </div>
      {isNumeric && (
        <div className="w-full h-1.5 rounded-full bg-slate-800 overflow-hidden flex" aria-hidden="true">
          <div
            className={`h-full ${awayAdvantage ? 'bg-emerald-400' : 'bg-slate-600'}`}
            style={{ width: `${awayWidthPct}%` }}
          />
          <div
            className={`h-full ${homeAdvantage ? 'bg-emerald-400' : 'bg-slate-700'}`}
            style={{ width: `${homeWidthPct}%` }}
          />
        </div>
      )}
    </div>
  );
};

export const GameDetailModal: React.FC<GameDetailModalProps> = ({
  matchup,
  onClose,
  returnFocusTo,
}) => {
  const [detail, setDetail] = useState<NflGameDetailPayload | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [fetchError, setFetchError] = useState<string | null>(null);
  const [activeTab, setActiveTab] = useState<DetailTab>('overview');
  const [boxCategory, setBoxCategory] = useState<NflBoxCategory>('passing');
  const [boxTeamFilter, setBoxTeamFilter] = useState<'both' | 'away' | 'home'>('both');
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDirection>('desc');

  const dialogRef = useRef<HTMLDivElement | null>(null);
  const closeButtonRef = useRef<HTMLButtonElement | null>(null);
  const openerRef = useRef<HTMLElement | null>(null);
  const restoredFocusRef = useRef<boolean>(false);
  const prevOpenRef = useRef<boolean>(false);

  const isOpen = matchup !== null;
  const gameId = matchup?.game_id ?? null;

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

  // Deep-link sync: sync ?game={game_id} in URL search params without page reload; remove on close.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    const url = new URL(window.location.href);
    const existing = url.searchParams.get('game');

    if (gameId) {
      if (existing !== gameId) {
        url.searchParams.set('game', gameId);
        window.history.replaceState(null, '', url.toString());
      }
    } else if (existing !== null) {
      url.searchParams.delete('game');
      const searchStr = url.searchParams.toString();
      const nextPath = url.pathname + (searchStr ? `?${searchStr}` : '') + url.hash;
      window.history.replaceState(null, '', nextPath);
    }
  }, [gameId]);

  useEffect(() => {
    return () => {
      if (typeof window === 'undefined') return;
      const url = new URL(window.location.href);
      if (url.searchParams.has('game')) {
        url.searchParams.delete('game');
        const searchStr = url.searchParams.toString();
        const nextPath = url.pathname + (searchStr ? `?${searchStr}` : '') + url.hash;
        window.history.replaceState(null, '', nextPath);
      }
    };
  }, []);

  // Opener focus capture & initial focus
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
    } else if (!isOpen && wasOpen) {
      restoreOpenerFocus();
    }
  }, [isOpen, returnFocusTo, restoreOpenerFocus]);

  // Trap Tab and Escape key inside modal
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

  // Fetch game detail payload
  useEffect(() => {
    if (!gameId) {
      setDetail(null);
      setLoading(false);
      setFetchError(null);
      return;
    }

    let cancelled = false;
    setLoading(true);
    setFetchError(null);

    const fetchDetail = async () => {
      try {
        const res = await fetch(`${BASE_PATH}/data/games/${gameId}.json`);
        if (!res.ok) {
          throw new Error(`HTTP ${res.status}`);
        }
        const raw = await res.json();
        const payload = unwrapEnvelope(raw);
        if (!cancelled) {
          setDetail(payload);
          setLoading(false);
        }
      } catch (err: unknown) {
        if (!cancelled) {
          const msg = err instanceof Error ? err.message : 'Failed to load';
          setFetchError(msg);
          setDetail(null);
          setLoading(false);
        }
      }
    };

    fetchDetail();

    return () => {
      cancelled = true;
    };
  }, [gameId]);

  // Reset tab selection on game change
  useEffect(() => {
    setActiveTab('overview');
    setBoxCategory('passing');
    setBoxTeamFilter('both');
    setSortKey(null);
    setSortDir('desc');
  }, [gameId]);

  // Derived state
  const isCompleted = matchup?.is_completed ?? detail?.is_completed ?? false;
  const hasBoxScore = (matchup?.has_box_score !== false) && (detail?.has_box_score !== false) && !fetchError;
  const weekLabel = detail?.week_label ?? (matchup?.week ? `Week ${matchup.week}` : 'Matchup');

  // Forecast data from detail or matchup
  const forecast = detail?.forecast ?? null;
  const hasProjection =
    (matchup?.has_projection && matchup?.projected_margin != null) ||
    (forecast?.projected_margin != null);

  const homePowerRating = forecast?.home_power_rating ?? matchup?.home_power_rating ?? null;
  const awayPowerRating = forecast?.away_power_rating ?? matchup?.away_power_rating ?? null;
  const projMargin = forecast?.projected_margin ?? matchup?.projected_margin ?? null;

  // Efficiency factors
  const efficiencyFactors = detail?.efficiency_factors ?? null;
  const teamStats = detail?.team_stats ?? null;
  const leaders = detail?.leaders ?? null;

  // Box score players
  const awayPlayers = useMemo(() => detail?.box_score?.away_players ?? [], [detail]);
  const homePlayers = useMemo(() => detail?.box_score?.home_players ?? [], [detail]);

  const displayedPlayers = useMemo(() => {
    let pool: NflPlayerBoxRow[] = [];
    if (boxTeamFilter === 'both') {
      pool = [...awayPlayers, ...homePlayers];
    } else if (boxTeamFilter === 'away') {
      pool = awayPlayers;
    } else {
      pool = homePlayers;
    }

    // Filter by active category
    const filtered = pool.filter((p) => {
      if (p.categories && p.categories.includes(boxCategory)) return true;
      if (boxCategory === 'passing') return (p.attempts ?? 0) > 0 || (p.passing_yards ?? 0) > 0;
      if (boxCategory === 'rushing') return (p.carries ?? 0) > 0 || (p.rushing_yards ?? 0) > 0;
      if (boxCategory === 'receiving') return (p.targets ?? 0) > 0 || (p.receptions ?? 0) > 0;
      if (boxCategory === 'defense') {
        return (
          (p.def_tackles_solo ?? 0) > 0 ||
          (p.def_tackle_assists ?? 0) > 0 ||
          (p.def_sacks ?? 0) > 0 ||
          (p.def_interceptions ?? 0) > 0
        );
      }
      if (boxCategory === 'kicking') return (p.fg_att ?? 0) > 0 || (p.pat_att ?? 0) > 0;
      return false;
    });

    if (!sortKey) return filtered;

    return [...filtered].sort((a, b) => {
      const aVal = (a as unknown as Record<string, unknown>)[sortKey];
      const bVal = (b as unknown as Record<string, unknown>)[sortKey];
      const aNum = isFiniteNum(aVal) ? (aVal as number) : null;
      const bNum = isFiniteNum(bVal) ? (bVal as number) : null;

      if (aNum === null && bNum === null) return a.playerName.localeCompare(b.playerName);
      if (aNum === null) return 1;
      if (bNum === null) return -1;
      return sortDir === 'asc' ? aNum - bNum : bNum - aNum;
    });
  }, [awayPlayers, homePlayers, boxCategory, boxTeamFilter, sortKey, sortDir]);

  const injuryDesignations: InjuryDesignationRow[] = detail?.injury_designations ?? [];

  const handleSort = (key: string) => {
    if (sortKey === key) {
      setSortDir((prev) => (prev === 'asc' ? 'desc' : 'asc'));
    } else {
      setSortKey(key);
      setSortDir('desc');
    }
  };

  const renderSortIndicator = (key: string) => {
    if (sortKey !== key) {
      return <ArrowUpDown className="w-3 h-3 text-slate-500 inline ml-1" aria-hidden="true" />;
    }
    return sortDir === 'asc' ? (
      <ArrowUp className="w-3 h-3 text-emerald-400 inline ml-1" aria-hidden="true" />
    ) : (
      <ArrowDown className="w-3 h-3 text-emerald-400 inline ml-1" aria-hidden="true" />
    );
  };

  if (!isOpen || !matchup) return null;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-2 sm:p-4 bg-slate-950/80 backdrop-blur-sm transition-opacity"
      onClick={handleClose}
      data-testid="game-detail-backdrop"
    >
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="game-detail-modal-title"
        className="bg-slate-900 border border-slate-800 rounded-2xl w-full max-w-4xl max-h-[92vh] flex flex-col shadow-2xl overflow-hidden focus:outline-none"
        tabIndex={-1}
        onClick={(e) => e.stopPropagation()}
      >
        {/* Modal Header */}
        <div className="p-4 sm:p-5 bg-slate-950/70 border-b border-slate-800 relative flex-shrink-0">
          <button
            ref={closeButtonRef}
            type="button"
            onClick={handleClose}
            aria-label="Close modal"
            className="absolute top-4 right-4 p-1.5 rounded-lg text-slate-400 hover:text-white hover:bg-slate-800 transition-colors focus:outline-none focus:ring-2 focus:ring-emerald-500/60"
          >
            <X className="w-5 h-5" />
          </button>

          {/* Subheader info: week, date, kickoff/final */}
          <div className="flex flex-wrap items-center gap-2 text-xs font-mono text-slate-400 mb-3 pr-8">
            <span className="px-2 py-0.5 rounded bg-slate-800 text-slate-300 font-semibold border border-slate-700/60">
              {weekLabel}
            </span>
            <span className="text-slate-600">•</span>
            <span className="flex items-center gap-1 text-slate-300">
              <Calendar className="w-3.5 h-3.5 text-slate-500" />
              {matchup.weekday ? `${matchup.weekday.slice(0, 3)}, ` : ''}
              {matchup.gameday}
            </span>
            <span className="text-slate-600">•</span>
            {isCompleted ? (
              <span className="px-1.5 py-0.5 rounded bg-slate-800 text-emerald-400 font-bold border border-slate-700 tracking-wide text-[11px]">
                FINAL
              </span>
            ) : (
              <span className="flex items-center gap-1 text-slate-300">
                <Clock className="w-3.5 h-3.5 text-emerald-400" />
                {matchup.gametime ? `${matchup.gametime} ET` : 'TBD'}
              </span>
            )}
          </div>

          {/* Teams Arena Banner */}
          <div className="grid grid-cols-5 items-center gap-2">
            {/* Away Team */}
            <div className="col-span-2 flex items-center gap-3">
              <TeamLogo team={matchup.away_team} size="lg" />
              <div className="min-w-0">
                <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block">
                  Away
                </span>
                <span className="text-sm sm:text-base font-bold text-white block truncate leading-tight">
                  {matchup.away_team_name}
                </span>
                {awayPowerRating != null && (
                  <span className="text-[11px] font-mono text-slate-400">
                    Pwr:{' '}
                    <strong className={awayPowerRating > 0 ? 'text-emerald-400' : 'text-slate-300'}>
                      {awayPowerRating > 0 ? `+${awayPowerRating.toFixed(1)}` : awayPowerRating.toFixed(1)}
                    </strong>
                  </span>
                )}
              </div>
            </div>

            {/* Center Score / Proj Margin */}
            <div className="col-span-1 flex flex-col items-center justify-center text-center px-1">
              <h2 id="game-detail-modal-title" className="sr-only">
                {matchup.away_team_name} vs {matchup.home_team_name} Game Details
              </h2>
              {isCompleted ? (
                <>
                  <div className="bg-slate-950 px-3 py-1 rounded-md border border-slate-800 text-sm sm:text-base font-mono font-black text-white shadow-inner whitespace-nowrap">
                    <span
                      className={
                        matchup.away_score != null && matchup.home_score != null && matchup.away_score > matchup.home_score
                          ? 'text-emerald-400'
                          : 'text-slate-200'
                      }
                    >
                      {matchup.away_score ?? '—'}
                    </span>
                    <span className="text-slate-600 mx-1.5">-</span>
                    <span
                      className={
                        matchup.home_score != null && matchup.away_score != null && matchup.home_score > matchup.away_score
                          ? 'text-emerald-400'
                          : 'text-slate-200'
                      }
                    >
                      {matchup.home_score ?? '—'}
                    </span>
                  </div>
                  {hasProjection && projMargin != null && (
                    <span className="text-[10px] font-mono text-slate-400 mt-1 truncate">
                      Proj Margin: {projMargin > 0 ? `+${projMargin.toFixed(1)}` : projMargin.toFixed(1)}
                    </span>
                  )}
                </>
              ) : hasProjection && projMargin != null ? (
                <>
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 font-semibold mb-0.5">
                    Proj Margin
                  </span>
                  <div className="bg-slate-950 px-2.5 py-1 rounded-md border border-slate-800 text-xs sm:text-sm font-mono font-black text-emerald-400 shadow-inner whitespace-nowrap">
                    {projMargin > 0 ? `+${projMargin.toFixed(1)}` : projMargin.toFixed(1)}
                  </div>
                </>
              ) : (
                <div className="flex flex-col items-center">
                  <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 font-semibold mb-0.5">
                    Matchup
                  </span>
                  <span className="text-[10px] font-mono text-slate-500 italic">No forecast recorded</span>
                </div>
              )}
            </div>

            {/* Home Team */}
            <div className="col-span-2 flex items-center justify-end gap-3 text-right">
              <div className="min-w-0">
                <span className="text-[10px] font-mono text-slate-400 uppercase tracking-wider block">
                  Home
                </span>
                <span className="text-sm sm:text-base font-bold text-white block truncate leading-tight">
                  {matchup.home_team_name}
                </span>
                {homePowerRating != null && (
                  <span className="text-[11px] font-mono text-slate-400">
                    Pwr:{' '}
                    <strong className={homePowerRating > 0 ? 'text-emerald-400' : 'text-slate-300'}>
                      {homePowerRating > 0 ? `+${homePowerRating.toFixed(1)}` : homePowerRating.toFixed(1)}
                    </strong>
                  </span>
                )}
              </div>
              <TeamLogo team={matchup.home_team} size="lg" />
            </div>
          </div>
        </div>

        {/* Tab Navigation */}
        <div className="border-b border-slate-800 bg-slate-950/40 px-4 sm:px-6 flex items-center gap-2 overflow-x-auto flex-shrink-0">
          <div role="tablist" aria-label="Game Detail Sections" className="flex gap-1 py-2">
            <button
              role="tab"
              id="tab-overview"
              aria-controls="panel-overview"
              aria-selected={activeTab === 'overview'}
              onClick={() => setActiveTab('overview')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                activeTab === 'overview'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Overview & Efficiency
            </button>
            <button
              role="tab"
              id="tab-comparison"
              aria-controls="panel-comparison"
              aria-selected={activeTab === 'comparison'}
              onClick={() => setActiveTab('comparison')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                activeTab === 'comparison'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Team Comparison
            </button>
            <button
              role="tab"
              id="tab-box-score"
              aria-controls="panel-box-score"
              aria-selected={activeTab === 'box_score'}
              onClick={() => setActiveTab('box_score')}
              className={`px-3 py-1.5 rounded-lg text-xs font-medium transition-colors whitespace-nowrap focus:outline-none focus:ring-2 focus:ring-emerald-500/50 ${
                activeTab === 'box_score'
                  ? 'bg-slate-800 text-white font-semibold border border-slate-700/70 shadow-sm'
                  : 'text-slate-400 hover:text-slate-200 hover:bg-slate-800/40'
              }`}
            >
              Player Box Score
            </button>
          </div>
        </div>

        {/* Tab Content Panels */}
        <div className="overflow-y-auto p-4 sm:p-6 flex-1 space-y-6">
          {loading && (
            <div className="py-12 flex flex-col items-center justify-center text-slate-400 gap-3">
              <Loader2 className="w-6 h-6 animate-spin text-emerald-400" />
              <span className="text-xs font-mono">Loading game details...</span>
            </div>
          )}

          {!loading && (!hasBoxScore || fetchError || !detail) && (
            <div className="py-12 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center space-y-3">
              <AlertCircle className="w-8 h-8 text-amber-400 mx-auto" />
              <div className="space-y-1">
                <p className="text-sm font-semibold text-slate-200">
                  {isCompleted ? 'Final. Box score is added on a later data refresh.' : 'Box score is added on a later data refresh.'}
                </p>
                <p className="text-xs text-slate-400">
                  Data from nflreadr will populate automatically once finalized and ingested.
                </p>
              </div>
            </div>
          )}

          {!loading && hasBoxScore && detail && (
            <>
              {/* Tab 1: Overview & Efficiency */}
              {activeTab === 'overview' && (
                <div role="tabpanel" id="panel-overview" aria-labelledby="tab-overview" className="space-y-6">
                  {/* Category Leaders */}
                  {leaders && leaders.length > 0 && (
                    <div className="space-y-3">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Category Leaders
                      </h3>
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
                        {leaders.map((ldr, idx) => (
                          <div
                            key={`${ldr.teamAbbr}-${ldr.category}-${idx}`}
                            className="bg-slate-950/60 border border-slate-800 rounded-xl p-3 space-y-1.5"
                          >
                            <div className="flex items-center justify-between text-[11px] font-mono text-slate-400">
                              <span className="uppercase font-semibold text-emerald-400">
                                {ldr.category}
                              </span>
                              <span className="px-1.5 py-0.5 rounded bg-slate-800 border border-slate-700/60 text-slate-300">
                                {ldr.teamAbbr}
                              </span>
                            </div>
                            <div className="font-bold text-white text-sm truncate">{ldr.playerName}</div>
                            <div className="text-xs font-mono text-slate-300 truncate">{ldr.stat_line}</div>
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Efficiency Factors Table */}
                  <div className="space-y-3">
                    <div className="flex items-center justify-between">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Efficiency Factors
                      </h3>
                      <span className="text-[11px] font-mono text-slate-500">nflreadr play-by-play metrics</span>
                    </div>

                    {efficiencyFactors && efficiencyFactors.length > 0 ? (
                      <div className="border border-slate-800 rounded-xl overflow-hidden bg-slate-950/40">
                        <table className="w-full text-left text-xs">
                          <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                            <tr>
                              <th scope="col" className="py-2 px-3">
                                Factor
                              </th>
                              <th scope="col" className="py-2 px-3 text-right">
                                {matchup.away_team}
                              </th>
                              <th scope="col" className="py-2 px-3 text-center">
                                Comparison
                              </th>
                              <th scope="col" className="py-2 px-3 text-left">
                                {matchup.home_team}
                              </th>
                            </tr>
                          </thead>
                          <tbody>
                            {efficiencyFactors.map((item) => (
                              <FactorRow
                                key={item.key}
                                item={item}
                                awayAbbr={matchup.away_team}
                                homeAbbr={matchup.home_team}
                              />
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <div className="py-6 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-400">
                        Efficiency factors will appear once play-by-play calculations complete.
                      </div>
                    )}
                  </div>
                </div>
              )}

              {/* Tab 2: Team Comparison */}
              {activeTab === 'comparison' && (
                <div role="tabpanel" id="panel-comparison" aria-labelledby="tab-comparison" className="space-y-4">
                  <div className="flex items-center justify-between">
                    <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                      Team Statistics Comparison
                    </h3>
                    <span className="text-[11px] font-mono text-slate-500">
                      {matchup.away_team} vs {matchup.home_team}
                    </span>
                  </div>

                  {teamStats && teamStats.length > 0 ? (
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      {teamStats.map((item) => (
                        <TeamComparisonRow
                          key={item.stat_key}
                          item={item}
                          awayAbbr={matchup.away_team}
                          homeAbbr={matchup.home_team}
                        />
                      ))}
                    </div>
                  ) : (
                    <div className="py-8 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-400">
                      Team statistics are added on a later data refresh.
                    </div>
                  )}
                </div>
              )}

              {/* Tab 3: Player Box Score */}
              {activeTab === 'box_score' && (
                <div role="tabpanel" id="panel-box-score" aria-labelledby="tab-box-score" className="space-y-6">
                  {/* Category & Team Filters */}
                  <div className="flex flex-wrap items-center justify-between gap-3">
                    {/* Category tabs */}
                    <div className="flex flex-wrap items-center gap-1 bg-slate-950/60 p-1 rounded-xl border border-slate-800">
                      {(['passing', 'rushing', 'receiving', 'defense', 'kicking'] as const).map((cat) => (
                        <button
                          key={cat}
                          type="button"
                          onClick={() => {
                            setBoxCategory(cat);
                            setSortKey(null);
                          }}
                          className={`px-2.5 py-1 rounded-lg text-xs font-medium capitalize transition-colors ${
                            boxCategory === cat
                              ? 'bg-slate-800 text-emerald-400 font-semibold border border-slate-700'
                              : 'text-slate-400 hover:text-slate-200'
                          }`}
                        >
                          {cat}
                        </button>
                      ))}
                    </div>

                    {/* Team Filter */}
                    <div className="flex items-center gap-1 bg-slate-950/60 p-1 rounded-xl border border-slate-800 text-xs font-mono">
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('both')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'both' ? 'bg-slate-800 text-white font-bold' : 'text-slate-400'
                        }`}
                      >
                        All
                      </button>
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('away')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'away' ? 'bg-slate-800 text-emerald-400 font-bold' : 'text-slate-400'
                        }`}
                      >
                        {matchup.away_team}
                      </button>
                      <button
                        type="button"
                        onClick={() => setBoxTeamFilter('home')}
                        className={`px-2 py-1 rounded-lg transition-colors ${
                          boxTeamFilter === 'home' ? 'bg-slate-800 text-emerald-400 font-bold' : 'text-slate-400'
                        }`}
                      >
                        {matchup.home_team}
                      </button>
                    </div>
                  </div>

                  {/* Players Table */}
                  <div className="border border-slate-800 rounded-xl overflow-x-auto bg-slate-950/40">
                    <table className="w-full text-left text-xs whitespace-nowrap">
                      <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                        <tr>
                          <th scope="col" className="py-2 px-3">
                            Player
                          </th>
                          <th scope="col" className="py-2 px-2 text-center">
                            Pos
                          </th>
                          <th scope="col" className="py-2 px-2 text-center">
                            Tm
                          </th>
                          <th scope="col" className="py-2 px-2 text-right">
                            Snap%
                          </th>

                          {boxCategory === 'passing' && (
                            <>
                              <th scope="col" className="py-2 px-2 text-right">
                                C/ATT
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_yards')}
                              >
                                YDS{renderSortIndicator('passing_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_tds')}
                              >
                                TD{renderSortIndicator('passing_tds')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_interceptions')}
                              >
                                INT{renderSortIndicator('passing_interceptions')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                SCK
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('passing_epa')}
                              >
                                EPA (nflreadr){renderSortIndicator('passing_epa')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                CPOE
                              </th>
                            </>
                          )}

                          {boxCategory === 'rushing' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('carries')}
                              >
                                CAR{renderSortIndicator('carries')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_yards')}
                              >
                                YDS{renderSortIndicator('rushing_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_tds')}
                              >
                                TD{renderSortIndicator('rushing_tds')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                1stD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FUM
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('rushing_epa')}
                              >
                                EPA (nflreadr){renderSortIndicator('rushing_epa')}
                              </th>
                            </>
                          )}

                          {boxCategory === 'receiving' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receptions')}
                              >
                                REC{renderSortIndicator('receptions')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('targets')}
                              >
                                TGTS{renderSortIndicator('targets')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_yards')}
                              >
                                YDS{renderSortIndicator('receiving_yards')}
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_tds')}
                              >
                                TD{renderSortIndicator('receiving_tds')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                1stD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FUM
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('receiving_epa')}
                              >
                                EPA (nflreadr){renderSortIndicator('receiving_epa')}
                              </th>
                            </>
                          )}

                          {boxCategory === 'defense' && (
                            <>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_tackles_solo')}
                              >
                                SOLO{renderSortIndicator('def_tackles_solo')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                AST
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_sacks')}
                              >
                                SCK{renderSortIndicator('def_sacks')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                TFL
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                QBH
                              </th>
                              <th
                                scope="col"
                                className="py-2 px-2 text-right cursor-pointer hover:text-white"
                                onClick={() => handleSort('def_interceptions')}
                              >
                                INT{renderSortIndicator('def_interceptions')}
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                PD
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FF
                              </th>
                            </>
                          )}

                          {boxCategory === 'kicking' && (
                            <>
                              <th scope="col" className="py-2 px-2 text-right">
                                FG (M/ATT)
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                FG%
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                LONG
                              </th>
                              <th scope="col" className="py-2 px-2 text-right">
                                PAT (M/ATT)
                              </th>
                            </>
                          )}
                        </tr>
                      </thead>
                      <tbody className="divide-y divide-slate-800/80 font-mono">
                        {displayedPlayers.length > 0 ? (
                          displayedPlayers.map((p) => (
                            <tr key={p.playerId} className="hover:bg-slate-800/30">
                              <td className="py-2 px-3 font-sans font-medium text-white">{p.playerName}</td>
                              <td className="py-2 px-2 text-center text-slate-400">{p.position ?? '—'}</td>
                              <td className="py-2 px-2 text-center text-slate-400">{p.teamAbbr}</td>
                              <td className="py-2 px-2 text-right text-slate-400">
                                {p.snap_pct != null ? `${p.snap_pct}%` : '—'}
                              </td>

                              {boxCategory === 'passing' && (
                                <>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.completions ?? 0}/{p.attempts ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.passing_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.passing_tds ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.passing_interceptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.sacks_suffered ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.passing_epa)
                                      ? `${p.passing_epa > 0 ? '+' : ''}${p.passing_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.passing_cpoe) ? `${p.passing_cpoe.toFixed(1)}%` : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'rushing' && (
                                <>
                                  <td className="py-2 px-2 text-right text-slate-300">{p.carries ?? 0}</td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.rushing_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.rushing_tds ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.rushing_first_downs ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.rushing_fumbles ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.rushing_epa)
                                      ? `${p.rushing_epa > 0 ? '+' : ''}${p.rushing_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'receiving' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.receptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">{p.targets ?? 0}</td>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.receiving_yards ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">
                                    {p.receiving_tds ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.receiving_first_downs ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.receiving_fumbles ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {isFiniteNum(p.receiving_epa)
                                      ? `${p.receiving_epa > 0 ? '+' : ''}${p.receiving_epa.toFixed(2)}`
                                      : '—'}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'defense' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.def_tackles_solo ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_tackle_assists ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-emerald-400">{p.def_sacks ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.def_tackles_for_loss ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">{p.def_qb_hits ?? 0}</td>
                                  <td className="py-2 px-2 text-right text-amber-400">
                                    {p.def_interceptions ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_pass_defended ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.def_fumbles_forced ?? 0}
                                  </td>
                                </>
                              )}

                              {boxCategory === 'kicking' && (
                                <>
                                  <td className="py-2 px-2 text-right font-bold text-white">
                                    {p.fg_made ?? 0}/{p.fg_att ?? 0}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.fg_att && p.fg_att > 0
                                      ? `${(((p.fg_made ?? 0) / p.fg_att) * 100).toFixed(1)}%`
                                      : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-400">
                                    {p.fg_long != null ? p.fg_long : '—'}
                                  </td>
                                  <td className="py-2 px-2 text-right text-slate-300">
                                    {p.pat_made ?? 0}/{p.pat_att ?? 0}
                                  </td>
                                </>
                              )}
                            </tr>
                          ))
                        ) : (
                          <tr>
                            <td colSpan={10} className="py-8 text-center text-slate-500 font-sans text-xs">
                              No {boxCategory} statistics recorded for this selection.
                            </td>
                          </tr>
                        )}
                      </tbody>
                    </table>
                  </div>

                  {/* Footnote on EPA estimate */}
                  <p className="text-[11px] text-slate-500 italic">
                    Note: EPA is a model estimate published by nflreadr.
                  </p>

                  {/* Injury Designations Table */}
                  <div className="space-y-3 pt-3 border-t border-slate-800">
                    <div className="flex items-center justify-between">
                      <h3 className="text-xs font-mono font-bold uppercase tracking-wider text-slate-400">
                        Injury report designations entering the game
                      </h3>
                      <span className="text-[11px] font-mono text-slate-500">Official pre-kickoff status</span>
                    </div>

                    {injuryDesignations.length > 0 ? (
                      <div className="border border-slate-800 rounded-xl overflow-hidden bg-slate-950/40">
                        <table className="w-full text-left text-xs whitespace-nowrap">
                          <thead className="bg-slate-950/80 text-[11px] font-mono text-slate-400 border-b border-slate-800">
                            <tr>
                              <th scope="col" className="py-2 px-3">
                                Player
                              </th>
                              <th scope="col" className="py-2 px-2 text-center">
                                Pos
                              </th>
                              <th scope="col" className="py-2 px-3 text-center">
                                Designation
                              </th>
                              <th scope="col" className="py-2 px-3">
                                Injury
                              </th>
                              <th scope="col" className="py-2 px-3 text-right">
                                Game Status
                              </th>
                            </tr>
                          </thead>
                          <tbody className="divide-y divide-slate-800/80 font-mono">
                            {injuryDesignations.map((inj, idx) => (
                              <tr key={`${inj.playerName}-${idx}`} className="hover:bg-slate-800/30">
                                <td className="py-2 px-3 font-sans font-medium text-white">{inj.playerName}</td>
                                <td className="py-2 px-2 text-center text-slate-400">{inj.position ?? '—'}</td>
                                <td className="py-2 px-3 text-center">
                                  <span
                                    className={`px-2 py-0.5 rounded text-[10px] font-semibold uppercase ${
                                      inj.designation === 'Out' || inj.designation === 'IR'
                                        ? 'bg-rose-500/10 text-rose-400 border border-rose-500/20'
                                        : inj.designation === 'Doubtful'
                                        ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                                        : 'bg-slate-800 text-slate-300 border border-slate-700'
                                    }`}
                                  >
                                    {inj.designation}
                                  </span>
                                </td>
                                <td className="py-2 px-3 text-slate-300 font-sans">{inj.body_part ?? '—'}</td>
                                <td className="py-2 px-3 text-right">
                                  {inj.played ? (
                                    <span className="inline-flex items-center gap-1 text-emerald-400 text-[11px] font-semibold">
                                      <CheckCircle2 className="w-3.5 h-3.5" /> Played
                                    </span>
                                  ) : (
                                    <span className="inline-flex items-center gap-1 text-slate-500 text-[11px]">
                                      Did Not Play
                                    </span>
                                  )}
                                </td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </div>
                    ) : (
                      <div className="py-6 px-4 rounded-xl bg-slate-950/40 border border-slate-800 text-center text-xs text-slate-500">
                        No injury designations recorded for this matchup.
                      </div>
                    )}
                  </div>
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
};
