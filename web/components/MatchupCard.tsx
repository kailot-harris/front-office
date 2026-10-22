'use client';

import React from 'react';
import { Matchup } from '@/lib/matchupTypes';
import { TeamLogo } from '@/components/TeamLogo';
import { Calendar, CheckCircle2, XCircle, Clock, MapPin } from 'lucide-react';

interface MatchupCardProps {
  matchup: Matchup;
}

const formatGameDate = (iso: string): string => {
  const [y, m, d] = iso.split('-').map(Number);
  if (!y || !m || !d) return iso;
  return new Date(Date.UTC(y, m - 1, d)).toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    timeZone: 'UTC',
  });
};

const pct = (p: number): string => `${(p * 100).toFixed(1)}%`;

export const MatchupCard: React.FC<MatchupCardProps> = ({ matchup }) => {
  const isHomeFavored = matchup.home_win_prob > 0.5;
  const favoredTeam = isHomeFavored ? matchup.home_team : matchup.away_team;
  const favoredProb = isHomeFavored ? matchup.home_win_prob : matchup.away_win_prob;
  const isGraded = matchup.prediction_correct !== null;
  const homeWon =
    matchup.is_completed && matchup.home_score !== null && matchup.away_score !== null
      ? matchup.home_score > matchup.away_score
      : false;
  const awayWon =
    matchup.is_completed && matchup.home_score !== null && matchup.away_score !== null
      ? matchup.away_score > matchup.home_score
      : false;

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden hover:border-accent-500/40 transition-all shadow-md flex flex-col justify-between">
      {/* Card Header */}
      <div className="p-3 bg-surface/80 border-b border-slate-800 flex items-center justify-between gap-2 text-xs font-mono text-slate-400">
        <div className="flex items-center gap-2 min-w-0">
          <Calendar className="w-3.5 h-3.5 text-slate-500 flex-shrink-0" />
          <span className="font-semibold text-slate-300 whitespace-nowrap">
            {formatGameDate(matchup.game_date)}
          </span>
          {matchup.game_type !== 'R' && (
            <span className="px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-400 border border-amber-500/20 text-[10px] font-bold truncate">
              {matchup.series_description}
            </span>
          )}
        </div>

        {/* Graded result, or the game's pending status */}
        {isGraded ? (
          matchup.prediction_correct ? (
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 flex items-center gap-1 flex-shrink-0">
              <CheckCircle2 className="w-2.5 h-2.5" /> Correct
            </span>
          ) : (
            <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center gap-1 flex-shrink-0">
              <XCircle className="w-2.5 h-2.5" /> Miss
            </span>
          )
        ) : matchup.is_completed ? (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700/50 flex-shrink-0">
            Final
          </span>
        ) : (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700/50 flex items-center gap-1 flex-shrink-0">
            <Clock className="w-2.5 h-2.5" /> {matchup.status_detail}
          </span>
        )}
      </div>

      {/* Matchup Body */}
      <div className="p-4 space-y-3">
        <div className="grid grid-cols-5 items-center gap-2">
          {/* Away */}
          <div className="col-span-2 flex items-center gap-2.5 min-w-0">
            <TeamLogo team={matchup.away_team} size="lg" />
            <div className="min-w-0">
              <span className="text-[10px] font-mono text-slate-500 block uppercase">Away</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.away_team_name}
              </span>
              <span
                className={`text-[11px] font-mono ${
                  !isHomeFavored ? 'text-accent-400 font-bold' : 'text-slate-400'
                }`}
              >
                {pct(matchup.away_win_prob)}
              </span>
            </div>
          </div>

          {/* Center: final score, or VS for anything not yet played */}
          <div className="col-span-1 flex flex-col items-center justify-center text-center px-1">
            {matchup.is_completed ? (
              <>
                <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
                  Final
                </span>
                <div className="bg-surface px-2 py-1 rounded-md border border-slate-800 text-xs font-mono font-black shadow-inner whitespace-nowrap">
                  <span className={awayWon ? 'text-emerald-400' : 'text-slate-400'}>
                    {matchup.away_score}
                  </span>
                  <span className="text-slate-600 mx-1">-</span>
                  <span className={homeWon ? 'text-emerald-400' : 'text-slate-400'}>
                    {matchup.home_score}
                  </span>
                </div>
              </>
            ) : (
              <>
                <span className="text-[9px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
                  Proj
                </span>
                <span className="text-sm font-black text-slate-500 font-mono">@</span>
              </>
            )}
          </div>

          {/* Home */}
          <div className="col-span-2 flex items-center gap-2.5 justify-end text-right min-w-0">
            <div className="min-w-0">
              <span className="text-[10px] font-mono text-slate-500 block uppercase">Home</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.home_team_name}
              </span>
              <span
                className={`text-[11px] font-mono ${
                  isHomeFavored ? 'text-accent-400 font-bold' : 'text-slate-400'
                }`}
              >
                {pct(matchup.home_win_prob)}
              </span>
            </div>
            <TeamLogo team={matchup.home_team} size="lg" />
          </div>
        </div>

        {/* Win probability bar */}
        <div className="space-y-1">
          <div className="h-1.5 w-full rounded-full bg-slate-800 overflow-hidden flex">
            <div
              className="h-full bg-slate-600"
              style={{ width: `${matchup.away_win_prob * 100}%` }}
            />
            <div className="h-full bg-accent-500" style={{ width: `${matchup.home_win_prob * 100}%` }} />
          </div>
          <div className="flex items-center justify-between text-[10px] font-mono text-slate-500">
            <span className="flex items-center gap-1 min-w-0 truncate">
              <MapPin className="w-2.5 h-2.5 flex-shrink-0" />
              <span className="truncate">{matchup.venue_name}</span>
            </span>
            <span className="whitespace-nowrap">
              {matchup.projection_source === 'walk_forward' ? 'Pre-game' : 'Current Elo'}:{' '}
              <strong className="text-slate-300">{favoredTeam}</strong> {pct(favoredProb)}
            </span>
          </div>
        </div>
      </div>
    </div>
  );
};
