'use client';

import React from 'react';
import { MatchupGame } from '@/lib/types';
import { TeamLogo } from '@/components/TeamLogo';
import { Clock, Calendar, Plane, Shield, Zap, AlertCircle } from 'lucide-react';

interface MatchupCardProps {
  matchup: MatchupGame;
}

export const MatchupCard: React.FC<MatchupCardProps> = ({ matchup }) => {
  const isHomeFavored = matchup.projected_margin > 0;
  const favoredTeam = isHomeFavored ? matchup.home_team : matchup.away_team;
  const marginValue = Math.abs(matchup.projected_margin);

  // Margin formatting string (e.g. "KC +3.5")
  const marginDisplay = `${favoredTeam} +${marginValue.toFixed(1)}`;

  // Kickoff time formatter
  const formattedTime = matchup.gametime ? `${matchup.gametime} ET` : 'TBD';

  return (
    <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden hover:border-emerald-500/40 transition-all shadow-md group flex flex-col justify-between">
      {/* Card Header */}
      <div className="p-3 bg-slate-950/80 border-b border-slate-800 flex items-center justify-between text-xs font-mono text-slate-400">
        <div className="flex items-center gap-2">
          <Calendar className="w-3.5 h-3.5 text-slate-500" />
          <span>
            {matchup.weekday}, {matchup.gameday}
          </span>
          <span className="text-slate-600">•</span>
          <div className="flex items-center gap-1 text-slate-300">
            <Clock className="w-3 h-3 text-emerald-400" />
            <span>{formattedTime}</span>
          </div>
        </div>

        {/* Key Margin or Window Badge */}
        {matchup.key_number_flag !== 'Standard' ? (
          <span className="text-[10px] font-bold px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center gap-1">
            <Zap className="w-2.5 h-2.5" />
            {matchup.key_number_flag.replace('Key', 'Margin')}
          </span>
        ) : (
          <span className="text-[10px] px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700/50">
            Week {matchup.week}
          </span>
        )}
      </div>

      {/* Main Matchup Arena */}
      <div className="p-4 space-y-4">
        {/* Away vs Home Grid */}
        <div className="grid grid-cols-5 items-center gap-2">
          {/* Away Team (Col 1-2) */}
          <div className="col-span-2 flex items-center gap-3">
            <TeamLogo team={matchup.away_team} size="lg" />
            <div className="min-w-0">
              <span className="text-[10px] font-mono text-slate-400 block uppercase">Away</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.away_team_name}
              </span>
              <span className="text-[11px] font-mono text-slate-400">
                Pwr:{' '}
                <strong className={matchup.away_power_rating > 0 ? 'text-emerald-400' : 'text-red-400'}>
                  {matchup.away_power_rating > 0 ? `+${matchup.away_power_rating.toFixed(1)}` : matchup.away_power_rating.toFixed(1)}
                </strong>
              </span>
            </div>
          </div>

          {/* Center VS & Projected Margin Box (Col 3) */}
          <div className="col-span-1 flex flex-col items-center justify-center text-center px-1">
            <span className="text-[10px] font-mono uppercase tracking-wider text-slate-500 font-bold mb-0.5">
              Proj Margin
            </span>
            <div className="bg-slate-950 px-2 py-1 rounded-md border border-slate-800 text-xs font-mono font-black text-emerald-400 shadow-inner whitespace-nowrap">
              {marginDisplay}
            </div>
            <span className="text-[10px] font-mono text-slate-400 mt-1">Total {matchup.projected_total.toFixed(1)}</span>
          </div>

          {/* Home Team (Col 4-5) */}
          <div className="col-span-2 flex items-center justify-end gap-3 text-right">
            <div className="min-w-0">
              <span className="text-[10px] font-mono text-slate-400 block uppercase">Home</span>
              <span className="text-sm font-bold text-white block truncate leading-tight">
                {matchup.home_team_name}
              </span>
              <span className="text-[11px] font-mono text-slate-400">
                Pwr:{' '}
                <strong className={matchup.home_power_rating > 0 ? 'text-emerald-400' : 'text-red-400'}>
                  {matchup.home_power_rating > 0 ? `+${matchup.home_power_rating.toFixed(1)}` : matchup.home_power_rating.toFixed(1)}
                </strong>
              </span>
            </div>
            <TeamLogo team={matchup.home_team} size="lg" />
          </div>
        </div>

        {/* Win Probability Bar */}
        <div className="space-y-1.5 pt-1">
          <div className="flex items-center justify-between text-xs font-mono">
            <span className={`font-bold ${!isHomeFavored ? 'text-emerald-400' : 'text-slate-400'}`}>
              {(matchup.away_win_prob * 100).toFixed(1)}% Win
            </span>
            <span className="text-[10px] text-slate-400 uppercase font-semibold">Model Win Probability</span>
            <span className={`font-bold ${isHomeFavored ? 'text-emerald-400' : 'text-slate-400'}`}>
              {(matchup.home_win_prob * 100).toFixed(1)}% Win
            </span>
          </div>

          <div className="h-2 w-full bg-slate-950 rounded-full overflow-hidden flex border border-slate-800">
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
      </div>

      {/* Fatigue & Travel Metrics Footer */}
      <div className="p-3 bg-slate-950/60 border-t border-slate-800/80 flex flex-wrap items-center justify-between gap-2 text-xs font-mono">
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
          <div className="flex items-center gap-1 text-[10px] text-red-400 bg-red-500/10 border border-red-500/20 px-1.5 py-0.5 rounded">
            <AlertCircle className="w-3 h-3" />
            <span>Short Week</span>
          </div>
        )}
      </div>
    </div>
  );
};
