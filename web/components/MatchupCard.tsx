'use client';

import React from 'react';
import { TeamLogo } from '@/components/TeamLogo';
import { Matchup, ProjectionBasis } from '@/lib/matchupTypes';
import { Check, X, CircleDashed, Info } from 'lucide-react';

// How each projection basis is presented. The label is deliberately explicit
// about which model produced the number: `team_rating_differential` is a
// season-long rating difference plus a flat home-court constant, NOT the
// per-game model, and a reader must be able to tell the two apart at a glance.
// See build_matchups_dataset.R's PROJECTION BASES section.
const BASIS_META: Record<ProjectionBasis, { label: string; hint: string; className: string }> = {
  logged_model: {
    label: 'Model',
    hint: 'Per-game model prediction, logged before tip-off. This is the basis the accuracy log grades.',
    className: 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30',
  },
  logged_model_prob_only: {
    label: 'Model (margin derived)',
    hint: 'Same logged per-game model, but it recorded only a win probability; the margin shown is that probability inverted through margin = qnorm(p) x sigma.',
    className: 'bg-emerald-500/10 text-emerald-300 border-emerald-500/30',
  },
  team_rating_differential: {
    label: 'Rating differential',
    hint: 'Not the per-game model: a season-long net-rating difference plus a flat home-court constant, used to fill games the model never predicted. Never graded.',
    className: 'bg-slate-600/20 text-slate-400 border-slate-600/40',
  },
};

interface MatchupCardProps {
  game: Matchup;
}

export const MatchupCard: React.FC<MatchupCardProps> = ({ game }) => {
  const basis = game.projection_basis ? BASIS_META[game.projection_basis] : null;
  const homeWon = game.is_completed && (game.actual_margin ?? 0) > 0;

  // Three distinct states, never collapsed into two. A played game with no
  // logged prediction is NOT a miss -- see Matchup.has_logged_prediction.
  const gradeState: 'correct' | 'incorrect' | 'ungraded' = game.is_graded
    ? game.prediction_correct
      ? 'correct'
      : 'incorrect'
    : 'ungraded';

  const winProbPct =
    game.home_win_prob !== null ? Math.round(game.home_win_prob * 1000) / 10 : null;

  return (
    <div className="rounded-lg border border-slate-700 bg-slate-800/50 p-4 flex flex-col gap-3">
      {/* Header: date, season type, grade chip */}
      <div className="flex items-center justify-between gap-2">
        <div className="flex items-center gap-2 text-xs text-slate-400">
          <span className="font-mono">{game.game_date}</span>
          {game.season_type === 'postseason' && (
            <span className="px-1.5 py-0.5 rounded bg-amber-500/10 text-amber-300 border border-amber-500/30 font-semibold">
              Postseason
            </span>
          )}
        </div>

        {gradeState === 'correct' && (
          <span
            className="flex items-center gap-1 text-xs font-semibold text-emerald-300"
            title="The logged prediction picked the winner."
          >
            <Check className="w-3.5 h-3.5" aria-hidden="true" />
            Correct
          </span>
        )}
        {gradeState === 'incorrect' && (
          <span
            className="flex items-center gap-1 text-xs font-semibold text-rose-300"
            title="The logged prediction picked the losing side."
          >
            <X className="w-3.5 h-3.5" aria-hidden="true" />
            Miss
          </span>
        )}
        {gradeState === 'ungraded' && game.is_completed && (
          <span
            className="flex items-center gap-1 text-xs text-slate-500"
            title={
              game.has_logged_prediction
                ? 'The accuracy log has not resolved this game yet, so it is not graded.'
                : 'No prediction was recorded for this game, so there is nothing to grade. This is not a missed pick.'
            }
          >
            <CircleDashed className="w-3.5 h-3.5" aria-hidden="true" />
            {game.has_logged_prediction ? 'Not resolved' : 'No prediction logged'}
          </span>
        )}
        {!game.is_completed && (
          <span className="text-xs font-semibold text-sky-300">Scheduled</span>
        )}
      </div>

      {/* Teams. Away listed first, matching how a fixture is spoken ("X at Y"). */}
      <div className="flex flex-col gap-2">
        <TeamRow
          abbr={game.away_team}
          name={game.away_team_name}
          score={game.away_score}
          isWinner={game.is_completed && !homeWon}
          isCompleted={game.is_completed}
        />
        <TeamRow
          abbr={game.home_team}
          name={game.home_team_name}
          score={game.home_score}
          isWinner={homeWon}
          isCompleted={game.is_completed}
          isHome
        />
      </div>

      {/* Projection */}
      <div className="border-t border-slate-700/70 pt-3">
        {game.has_prediction && basis ? (
          <div className="flex flex-col gap-1.5">
            <div className="flex items-center justify-between gap-2 text-xs">
              <span className="text-slate-400">Projected</span>
              <span
                className={`px-1.5 py-0.5 rounded border font-medium inline-flex items-center gap-1 ${basis.className}`}
                title={basis.hint}
              >
                {basis.label}
                <Info className="w-3 h-3" aria-hidden="true" />
              </span>
            </div>
            <div className="flex items-baseline justify-between gap-3">
              <span className="text-sm text-slate-200">
                {game.predicted_winner ?? '—'}
                {game.projected_margin !== null && (
                  <span className="text-slate-400 font-mono ml-1.5">
                    by {Math.abs(game.projected_margin).toFixed(1)}
                  </span>
                )}
              </span>
              {winProbPct !== null && (
                <span className="text-xs text-slate-400 font-mono" title="Home win probability">
                  {game.home_team} {winProbPct.toFixed(1)}%
                </span>
              )}
            </div>
          </div>
        ) : (
          <p className="text-xs text-slate-500">
            No projection available for this game.
          </p>
        )}
      </div>
    </div>
  );
};

interface TeamRowProps {
  abbr: string;
  name: string;
  score: number | null;
  isWinner: boolean;
  isCompleted: boolean;
  isHome?: boolean;
}

const TeamRow: React.FC<TeamRowProps> = ({
  abbr,
  name,
  score,
  isWinner,
  isCompleted,
  isHome = false,
}) => (
  <div className="flex items-center justify-between gap-2">
    <div className="flex items-center gap-2 min-w-0">
      <TeamLogo team={abbr} size="sm" />
      <span
        className={`truncate text-sm ${
          isCompleted && isWinner ? 'text-white font-semibold' : 'text-slate-300'
        }`}
      >
        {name}
      </span>
      {isHome && (
        <span className="text-[10px] text-slate-500 font-mono flex-shrink-0" title="Home team">
          HOME
        </span>
      )}
    </div>
    <span
      className={`font-mono text-sm tabular-nums flex-shrink-0 ${
        isCompleted && isWinner ? 'text-white font-bold' : 'text-slate-400'
      }`}
    >
      {score ?? '—'}
    </span>
  </div>
);
