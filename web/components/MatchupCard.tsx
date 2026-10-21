'use client';

import React from 'react';
import { TeamLogo } from '@/components/TeamLogo';
import { MatchupGame } from '@/lib/matchupTypes';
import { CheckCircle2, XCircle, Clock } from 'lucide-react';

interface MatchupCardProps {
  matchup: MatchupGame;
}

const pct = (p: number | null): string => (p === null ? '—' : `${(p * 100).toFixed(1)}%`);

const signed = (n: number | null): string => {
  if (n === null) return '—';
  return `${n > 0 ? '+' : ''}${n.toFixed(1)}`;
};

export const MatchupCard: React.FC<MatchupCardProps> = ({ matchup: m }) => {
  const homeFavored = m.predicted_margin !== null && m.predicted_margin >= 0;
  const favorite = m.predicted_margin === null ? null : homeFavored ? m.home_team : m.away_team;
  const graded = m.is_completed && m.prediction_correct !== null;

  return (
    <div
      className={`bg-surface-raised/80 border rounded-xl p-4 flex flex-col gap-3 transition-colors ${
        graded
          ? m.prediction_correct
            ? 'border-accent-500/40'
            : 'border-rose-500/40'
          : 'border-slate-800 hover:border-accent-500/40'
      }`}
      data-testid="matchup-card"
    >
      {/* Date + status chip */}
      <div className="flex items-center justify-between text-[10px] font-mono uppercase tracking-wider">
        <span className="text-slate-400">
          {m.weekday} · {m.game_date}
        </span>
        {m.is_completed ? (
          <span className="px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
            Final
          </span>
        ) : (
          <span className="px-2 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 flex items-center gap-1">
            <Clock className="w-3 h-3" />
            <span>Scheduled</span>
          </span>
        )}
      </div>

      {/* Teams */}
      <div className="space-y-2">
        {([
          ['away', m.away_team, m.away_team_name, m.away_score, m.predicted_away_win_prob] as const,
          ['home', m.home_team, m.home_team_name, m.home_score, m.predicted_home_win_prob] as const,
        ]).map(([side, abbr, name, score, winProb]) => {
          const isWinner = m.actual_winner !== null && m.actual_winner === abbr;
          return (
            <div key={side} className="flex items-center gap-2.5">
              <TeamLogo team={abbr} size="md" />
              <div className="min-w-0 flex-1">
                <span
                  className={`text-sm font-bold block truncate ${
                    isWinner ? 'text-white' : m.is_completed ? 'text-slate-400' : 'text-white'
                  }`}
                >
                  {name}
                  {side === 'away' && <span className="text-slate-500 font-normal text-xs"> @</span>}
                </span>
                <span className="text-[11px] font-mono text-slate-400">
                  Win prob {pct(winProb)}
                  {favorite === abbr && <span className="text-accent-400"> · Projected favorite</span>}
                </span>
              </div>
              <span
                className={`text-lg font-black font-mono tabular-nums ${
                  score === null ? 'text-slate-600' : isWinner ? 'text-white' : 'text-slate-400'
                }`}
              >
                {score === null ? '–' : score}
              </span>
            </div>
          );
        })}
      </div>

      {/* Projection + grade footer */}
      <div className="border-t border-slate-800 pt-2.5 flex items-center justify-between gap-2">
        <div className="min-w-0">
          <span className="text-[10px] font-mono uppercase text-slate-500 block">
            Projected margin
          </span>
          <span className="text-sm font-bold font-mono text-accent-400">
            {favorite === null ? 'No projection' : `${favorite} ${signed(Math.abs(m.predicted_margin!) * -1)}`}
          </span>
          {m.projection_basis === 'margin_from_logged_win_prob' && (
            <span className="text-[10px] font-mono text-slate-500 block">
              margin derived from logged win prob
            </span>
          )}
        </div>

        {graded ? (
          <span
            className={`flex items-center gap-1.5 text-xs font-mono font-bold px-2 py-1 rounded-lg border ${
              m.prediction_correct
                ? 'bg-accent-500/10 text-accent-400 border-accent-500/30'
                : 'bg-rose-500/10 text-rose-400 border-rose-500/30'
            }`}
          >
            {m.prediction_correct ? (
              <CheckCircle2 className="w-3.5 h-3.5" />
            ) : (
              <XCircle className="w-3.5 h-3.5" />
            )}
            <span>{m.prediction_correct ? 'Correct' : 'Miss'}</span>
          </span>
        ) : (
          <span className="text-xs font-mono text-slate-500">Pending</span>
        )}
      </div>
    </div>
  );
};
