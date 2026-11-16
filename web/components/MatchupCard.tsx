'use client';

import React, { useEffect, useMemo, useState } from 'react';
import { MatchupGame } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { Clock, Calendar, Plane, Shield, AlertCircle, ChevronRight } from 'lucide-react';
import { BASE_PATH } from '@/lib/basePath';
import type { GameDetailEnvelope, NflGameDetailPayload } from '@/lib/gameDetailTypes';

export interface MatchupCardProps {
  matchup: MatchupGame;
  onSelect?: (matchup: MatchupGame, element: HTMLElement) => void;
}

/** Accessible label shared by clickable matchup cards and table rows. */
export function formatMatchupInspectLabel(matchup: MatchupGame): string {
  return `Inspect game detail: ${matchup.away_team_name} (${matchup.away_team}) at ${matchup.home_team_name} (${matchup.home_team}) on ${matchup.gameday}`;
}

const gameDetailCache = new Map<string, Promise<NflGameDetailPayload | null>>();

export function clearGameDetailCache(): void {
  gameDetailCache.clear();
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

export function fetchGameDetail(gameId: string): Promise<NflGameDetailPayload | null> {
  const cached = gameDetailCache.get(gameId);
  if (cached) return cached;

  const promise = (async () => {
    try {
      const res = await fetch(`${BASE_PATH}/data/games/${gameId}.json`);
      if (!res.ok) return null;
      const json = await res.json();
      return unwrapEnvelope(json);
    } catch {
      return null;
    }
  })();

  gameDetailCache.set(gameId, promise);
  return promise;
}

export const MatchupCard: React.FC<MatchupCardProps> = ({ matchup, onSelect }) => {
  const hasProjection = matchup.has_projection !== false && matchup.projected_margin != null;
  const isHomeFavored = hasProjection ? matchup.projected_margin! > 0 : false;
  const favoredTeam = hasProjection ? (isHomeFavored ? matchup.home_team : matchup.away_team) : null;
  const marginValue = hasProjection ? Math.abs(matchup.projected_margin!) : null;

  // Margin formatting string (e.g. "KC +3.5")
  const marginDisplay = hasProjection && favoredTeam && marginValue != null ? `${favoredTeam} +${marginValue.toFixed(1)}` : null;

  // Kickoff time formatter
  const formattedTime = matchup.gametime ? `${matchup.gametime} ET` : 'TBD';

  const isInteractive = Boolean(onSelect && matchup.is_completed);
  const cardLabel = formatMatchupInspectLabel(matchup);

  const [detail, setDetail] = useState<NflGameDetailPayload | null>(null);

  useEffect(() => {
    let cancelled = false;
    if (matchup.is_completed && matchup.has_box_score !== false) {
      fetchGameDetail(matchup.game_id).then((data) => {
        if (!cancelled && data) {
          setDetail(data);
        }
      });
    }
    return () => {
      cancelled = true;
    };
  }, [matchup.game_id, matchup.is_completed, matchup.has_box_score]);

  const awayPassingLeader = useMemo(() => {
    return detail?.leaders?.find(
      (l) => l.category === 'passing' && l.teamAbbr === matchup.away_team
    ) ?? null;
  }, [detail, matchup.away_team]);

  const homePassingLeader = useMemo(() => {
    return detail?.leaders?.find(
      (l) => l.category === 'passing' && l.teamAbbr === matchup.home_team
    ) ?? null;
  }, [detail, matchup.home_team]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (!onSelect || !isInteractive) return;
    if (e.key === 'Enter' || e.key === ' ') {
      e.preventDefault();
      onSelect(matchup, e.currentTarget);
    }
  };

  return (
    <div
      className={`bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden transition-all shadow-md group flex flex-col justify-between ${
        isInteractive
          ? 'cursor-pointer hover:border-emerald-500/60 hover:bg-surface-raised focus:outline-none focus:ring-2 focus:ring-emerald-400'
          : 'hover:border-emerald-500/40'
      }`}
      data-testid="matchup-card"
      role={isInteractive ? 'button' : undefined}
      tabIndex={isInteractive ? 0 : undefined}
      aria-label={isInteractive ? cardLabel : undefined}
      onClick={isInteractive ? (e) => onSelect?.(matchup, e.currentTarget) : undefined}
      onKeyDown={isInteractive ? handleKeyDown : undefined}
    >
      {/* Card Header */}
      <div className="p-3 bg-surface/80 border-b border-slate-800 flex items-center justify-between text-xs font-mono text-slate-400">
        <div className="flex items-center gap-2">
          <Calendar className="w-3.5 h-3.5 text-slate-500" />
          <span className="font-semibold text-slate-300">
            {matchup.weekday.slice(0, 3)}, {matchup.gameday}
          </span>
          <span className="text-slate-600">•</span>
          {matchup.is_completed ? (
            <span className="px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 font-bold text-[11px] sm:text-[10px] tracking-wide border border-slate-700">
              FINAL
            </span>
          ) : (
            <div className="flex items-center gap-1 text-slate-300">
              <Clock className="w-3 h-3 text-emerald-400" />
              <span>{formattedTime}</span>
            </div>
          )}
        </div>

        {/* Prediction Result Badge */}
        <div className="flex items-center gap-1.5">
          {matchup.is_completed ? (
            matchup.prediction_correct === true ? (
              <span className="text-[11px] sm:text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center gap-1">
                ✓ Model Correct
              </span>
            ) : matchup.prediction_correct === false ? (
              <span className="text-[11px] sm:text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center gap-1">
                ✗ Upset
              </span>
            ) : (
              <span className="text-[11px] sm:text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700/50">
                Week {matchup.week}
              </span>
            )
          ) : (
            <span className="text-[11px] sm:text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700/50">
              Week {matchup.week}
            </span>
          )}
          {isInteractive && (
            <ChevronRight
              className="w-3.5 h-3.5 text-slate-500 group-hover:text-emerald-400 transition-colors"
              aria-hidden="true"
            />
          )}
        </div>
      </div>

      {/* Main Matchup Arena */}
      <div className="p-4 space-y-4">
        {/* Away vs Home Grid */}
        <div className="grid grid-cols-5 items-center gap-2">
          {/* Away Team (Col 1-2) */}
          <div className="col-span-2 flex items-center gap-3">
            <TeamLogo team={matchup.away_team} size="lg" />
            <div className="min-w-0">
              <span className="text-[11px] sm:text-[10px] font-mono text-slate-400 block uppercase">Away</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.away_team_name}
              </span>
              {matchup.is_completed ? (
                <span className="text-[11px] font-mono font-bold text-slate-300">
                  Pts: <strong className="text-white text-xs">{matchup.away_score}</strong>
                </span>
              ) : (
                <span className="text-[11px] font-mono text-slate-400">
                  Pwr:{' '}
                  {matchup.away_power_rating != null ? (
                    <strong className={matchup.away_power_rating > 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {matchup.away_power_rating > 0 ? `+${matchup.away_power_rating.toFixed(1)}` : matchup.away_power_rating.toFixed(1)}
                    </strong>
                  ) : (
                    <span className="text-slate-500">—</span>
                  )}
                </span>
              )}
            </div>
          </div>

          {/* Center VS / Margin / Score Box (Col 3) */}
          <div className="col-span-1 flex flex-col items-center justify-center text-center px-1">
            {matchup.is_completed ? (
              <>
                <span className="text-[11px] sm:text-[10px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
                  Final
                </span>
                <div className="bg-surface px-2 py-1 rounded-md border border-slate-800 text-xs font-mono font-black text-white shadow-inner whitespace-nowrap">
                  <span className={Number(matchup.away_score) > Number(matchup.home_score) ? 'text-emerald-400' : 'text-slate-400'}>
                    {matchup.away_score}
                  </span>
                  <span className="text-slate-600 mx-1">-</span>
                  <span className={Number(matchup.home_score) > Number(matchup.away_score) ? 'text-emerald-400' : 'text-slate-400'}>
                    {matchup.home_score}
                  </span>
                </div>
                {marginDisplay && (
                  <span className="text-[11px] sm:text-[9px] font-mono text-slate-500 mt-1 truncate max-w-full">
                    Proj: {marginDisplay}
                  </span>
                )}
              </>
            ) : hasProjection ? (
              <>
                <span className="text-[11px] sm:text-[10px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
                  Proj Margin
                </span>
                <div className="bg-surface px-2 py-1 rounded-md border border-slate-800 text-xs font-mono font-black text-emerald-400 shadow-inner whitespace-nowrap">
                  {marginDisplay}
                </div>
              </>
            ) : (
              <>
                <span className="text-[11px] sm:text-[10px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
                  Matchup
                </span>
                <span className="text-[10px] text-slate-500 font-mono italic">No forecast recorded</span>
              </>
            )}
          </div>

          {/* Home Team (Col 4-5) */}
          <div className="col-span-2 flex items-center justify-end gap-3 text-right">
            <div className="min-w-0">
              <span className="text-[11px] sm:text-[10px] font-mono text-slate-400 block uppercase">Home</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.home_team_name}
              </span>
              {matchup.is_completed ? (
                <span className="text-[11px] font-mono font-bold text-slate-300">
                  Pts: <strong className="text-white text-xs">{matchup.home_score}</strong>
                </span>
              ) : (
                <span className="text-[11px] font-mono text-slate-400">
                  Pwr:{' '}
                  {matchup.home_power_rating != null ? (
                    <strong className={matchup.home_power_rating > 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {matchup.home_power_rating > 0 ? `+${matchup.home_power_rating.toFixed(1)}` : matchup.home_power_rating.toFixed(1)}
                    </strong>
                  ) : (
                    <span className="text-slate-500">—</span>
                  )}
                </span>
              )}
            </div>
            <TeamLogo team={matchup.home_team} size="lg" />
          </div>
        </div>

        {/* Win Probability Bar */}
        {hasProjection && matchup.away_win_prob != null && matchup.home_win_prob != null ? (
          <div className="space-y-1.5 pt-1">
            <div className="flex items-center justify-between text-xs font-mono">
              <span className={`font-bold ${!isHomeFavored ? 'text-emerald-400' : 'text-slate-400'}`}>
                {(matchup.away_win_prob * 100).toFixed(1)}% Win
              </span>
              <span className="text-[11px] sm:text-[10px] text-slate-400 uppercase font-semibold">Model Win Probability</span>
              <span className={`font-bold ${isHomeFavored ? 'text-emerald-400' : 'text-slate-400'}`}>
                {(matchup.home_win_prob * 100).toFixed(1)}% Win
              </span>
            </div>

            <div className="h-2 w-full bg-surface rounded-full overflow-hidden flex border border-slate-800">
              <div
                className={`h-full transition-all duration-500 ${
                  !isHomeFavored ? 'bg-emerald-500' : 'bg-slate-700'
                }`}
                style={{ width: `${matchup.away_win_prob * 100}%` }}
                title={`${matchup.away_team} win prob: ${(matchup.away_win_prob * 100).toFixed(1)}%`}
              />
              <div
                className={`h-full transition-all duration-500 ${
                  isHomeFavored ? 'bg-emerald-500' : 'bg-slate-700'
                }`}
                style={{ width: `${matchup.home_win_prob * 100}%` }}
                title={`${matchup.home_team} win prob: ${(matchup.home_win_prob * 100).toFixed(1)}%`}
              />
            </div>
          </div>
        ) : (
          <div className="pt-1 text-center text-xs font-mono text-slate-500 italic">
            No forecast recorded
          </div>
        )}
      </div>

      {/* Passing Leaders Summary Strip (completed games with data) */}
      {matchup.is_completed && (awayPassingLeader || homePassingLeader) && (
        <div
          className="px-4 py-2 bg-surface/50 border-t border-slate-800/80 text-xs font-mono"
          data-testid="passing-leaders-strip"
        >
          <div className="flex items-center justify-between text-[10px] text-slate-500 uppercase tracking-wider font-semibold mb-1">
            <span>Passing Leader</span>
            <span>Passing Leader</span>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div className="min-w-0">
              <span className="text-slate-200 font-semibold truncate block text-xs">
                {awayPassingLeader ? awayPassingLeader.playerName : '—'}
              </span>
              <span className="text-emerald-400/90 text-[11px] truncate block">
                {awayPassingLeader?.stat_line ?? '—'}
              </span>
            </div>
            <div className="min-w-0 text-right">
              <span className="text-slate-200 font-semibold truncate block text-xs">
                {homePassingLeader ? homePassingLeader.playerName : '—'}
              </span>
              <span className="text-emerald-400/90 text-[11px] truncate block">
                {homePassingLeader?.stat_line ?? '—'}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Fatigue & Travel Metrics Footer */}
      <div className="p-3 bg-surface/60 border-t border-slate-800/80 flex flex-wrap items-center justify-between gap-2 text-xs font-mono">
        {/* Rest differential */}
        <div className="flex items-center gap-1.5 text-slate-400">
          <Shield className="w-3.5 h-3.5 text-slate-500" />
          <span>Rest:</span>
          {matchup.rest_diff !== 0 ? (
            <span
              className={`font-semibold ${
                matchup.rest_diff > 0 ? 'text-emerald-400' : 'text-amber-400'
              }`}
            >
              {matchup.rest_diff > 0
                ? `${matchup.home_team} +${matchup.rest_diff}d`
                : `${matchup.away_team} +${Math.abs(matchup.rest_diff)}d`}
            </span>
          ) : (
            <span className="text-slate-500">Even (7d vs 7d)</span>
          )}
        </div>

        {/* Travel miles */}
        <div className="flex items-center gap-1.5 text-slate-400">
          <Plane className="w-3.5 h-3.5 text-slate-500" />
          <span>Travel:</span>
          {matchup.away_travel_miles > 0 ? (
            <span
              className={
                matchup.away_travel_miles >= 1500
                  ? 'text-amber-400 font-semibold'
                  : 'text-slate-300'
              }
            >
              {matchup.away_travel_miles.toLocaleString()} mi
            </span>
          ) : (
            <span className="text-slate-500">0 mi</span>
          )}
        </div>

        {/* Short week warning */}
        {(matchup.home_rest_days < 7 || matchup.away_rest_days < 7) && (
          <div className="flex items-center gap-1 text-[11px] sm:text-[10px] text-red-400 bg-red-500/10 border border-red-500/20 px-1.5 py-0.5 rounded">
            <AlertCircle className="w-3 h-3" />
            <span>Short Week</span>
          </div>
        )}
      </div>
    </div>
  );
};
