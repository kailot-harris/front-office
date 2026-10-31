'use client';

import React, { useState, useMemo } from 'react';
import { MatchupsPayload, Matchup, MatchupWeek } from '@/lib/matchupTypes';
import { MatchupCard } from '@/components/MatchupCard';
import { TeamLogo } from '@/components/TeamLogo';
import { LayoutGrid, Table2, Calendar, Check, X, CircleDashed } from 'lucide-react';

interface MatchupsClientProps {
  data: MatchupsPayload;
}

export const MatchupsClient: React.FC<MatchupsClientProps> = ({ data }) => {
  const [selectedWeek, setSelectedWeek] = useState<number>(data.active_week);
  const [viewMode, setViewMode] = useState<'cards' | 'table'>('cards');

  const weekById = useMemo(() => {
    const m = new Map<number, MatchupWeek>();
    data.weeks.forEach((w) => m.set(w.week, w));
    return m;
  }, [data.weeks]);

  const gamesByWeek = useMemo(() => {
    const m = new Map<number, Matchup[]>();
    data.matchups.forEach((g) => {
      const list = m.get(g.week);
      if (list) list.push(g);
      else m.set(g.week, [g]);
    });
    return m;
  }, [data.matchups]);

  const games = gamesByWeek.get(selectedWeek) ?? [];
  const week = weekById.get(selectedWeek);

  return (
    <div className="flex flex-col gap-6">
      <Header data={data} />

      {/* WEEK RIBBON.
          Iterates available_weeks, NOT 1..max(): the week index is a label and
          the range is not dense (the 2026 season has no week 18 at all -- the
          pre-playoff break). Building this from a range would render a phantom
          empty week. See MatchupsPayload.available_weeks. */}
      <nav aria-label="Week selector" className="flex flex-col gap-2">
        <div className="flex items-center gap-2 text-sm text-slate-400">
          <Calendar className="w-4 h-4" aria-hidden="true" />
          <span>Week</span>
        </div>
        <div className="flex gap-1.5 overflow-x-auto pb-2">
          {data.available_weeks.map((w) => {
            const meta = weekById.get(w);
            const isActive = w === selectedWeek;
            const isCurrent = w === data.active_week;
            const allPlayed = meta ? meta.completed_games === meta.total_games : false;
            const nonePlayed = meta ? meta.completed_games === 0 : false;

            return (
              <button
                key={w}
                type="button"
                onClick={() => setSelectedWeek(w)}
                aria-current={isActive ? 'true' : undefined}
                title={
                  meta
                    ? `${meta.start_date} to ${meta.end_date} — ${meta.total_games} games`
                    : undefined
                }
                className={`flex-shrink-0 px-3 py-2 rounded-md border text-sm transition-colors ${
                  isActive
                    ? 'bg-amber-500/20 border-amber-500/60 text-amber-200 font-semibold'
                    : 'bg-slate-800/60 border-slate-700 text-slate-300 hover:border-slate-500'
                }`}
              >
                <span className="font-mono">{w}</span>
                <span className="block text-[10px] leading-tight mt-0.5">
                  {nonePlayed ? (
                    <span className="text-sky-400">Upcoming</span>
                  ) : allPlayed ? (
                    <span className={isCurrent ? 'text-amber-300' : 'text-slate-500'}>
                      Final
                    </span>
                  ) : (
                    <span className="text-sky-400">In progress</span>
                  )}
                </span>
              </button>
            );
          })}
        </div>
      </nav>

      {/* Selected week summary + view toggle */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-col gap-0.5">
          <h2 className="text-xl font-bold text-white">
            Week {selectedWeek}
            {week && (
              <span className="text-slate-400 text-sm font-normal ml-2 font-mono">
                {week.start_date} – {week.end_date}
              </span>
            )}
          </h2>
          {week && <WeekAccuracy week={week} />}
        </div>

        <div className="flex gap-1 rounded-md border border-slate-700 p-1 bg-slate-800/60">
          <ViewButton
            active={viewMode === 'cards'}
            onClick={() => setViewMode('cards')}
            icon={<LayoutGrid className="w-4 h-4" aria-hidden="true" />}
            label="Cards"
          />
          <ViewButton
            active={viewMode === 'table'}
            onClick={() => setViewMode('table')}
            icon={<Table2 className="w-4 h-4" aria-hidden="true" />}
            label="Table"
          />
        </div>
      </div>

      {games.length === 0 ? (
        <p className="text-slate-400">No games in this week.</p>
      ) : viewMode === 'cards' ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {games.map((g) => (
            <MatchupCard key={g.game_id} game={g} />
          ))}
        </div>
      ) : (
        <MatchupTable games={games} />
      )}
    </div>
  );
};

const Header: React.FC<{ data: MatchupsPayload }> = ({ data }) => {
  const s = data.summary;

  return (
    <header className="relative flex flex-col gap-3 pb-6">
      <div>
        <h1 className="text-3xl font-bold text-white">
          <span className="text-accent-400">WNBA</span> Matchups
        </h1>
        <p className="text-slate-400 text-sm mt-1">
          {data.season} season · {s.total_games} games · {data.season_start} to{' '}
          {data.season_end}
        </p>
      </div>

      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat label="Played" value={`${s.completed_games} / ${s.total_games}`} />
        <Stat label="Scheduled" value={s.pending_games} />
        <Stat label="Graded" value={s.graded_games} />
        {/* Accuracy is shown ONLY when something is graded. The payload sets
            accuracy_pct to null otherwise, so there is no 0% / NaN% branch. */}
        <Stat
          label="Model accuracy"
          value={
            s.graded_games_available && s.accuracy_pct !== null
              ? `${s.accuracy_pct}%`
              : 'Not yet graded'
          }
          sub={
            s.graded_games_available && s.correct_games !== null
              ? `${s.correct_games} of ${s.graded_games} correct`
              : undefined
          }
        />
      </div>

      {/* COVERAGE DISCLOSURE. Not decoration: for 2026, 308 of 352 played games
          have no logged prediction, because prediction_accuracy_logger.R only
          began writing on 2026-09-17. Without this note the accuracy figure
          reads as a season-long record when it covers ~6 weeks. */}
      {s.played_without_logged_prediction > 0 && (
        <div className="rounded-lg border border-slate-700 bg-slate-800/40 px-4 py-3 text-sm text-slate-300">
          <p>
            <span className="font-semibold text-slate-200">
              Prediction coverage:
            </span>{' '}
            {s.graded_games} of {s.completed_games} played games carry a model
            prediction that was logged before tip-off. The other{' '}
            {s.played_without_logged_prediction} show their final score only —
            no prediction was recorded for them, so they are not counted as
            misses and the accuracy figure above does not cover them.
          </p>
          <p className="text-slate-400 text-xs mt-1.5">
            Games without a logged prediction display a rating-differential
            estimate instead, labelled as such on each card. It is a season-long
            net-rating difference plus a flat home-court constant, not the
            per-game model, and it is never graded.
          </p>
        </div>
      )}
      <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
    </header>
  );
};

const WeekAccuracy: React.FC<{ week: MatchupWeek }> = ({ week }) => {
  // Null accuracy_pct means this week graded nothing. Say so rather than
  // rendering 0%, which would read as "the model got every game wrong".
  if (week.graded_games === 0 || week.accuracy_pct === null) {
    return (
      <p className="text-sm text-slate-500">
        {week.completed_games} of {week.total_games} played · no graded
        predictions this week
      </p>
    );
  }

  return (
    <p className="text-sm text-slate-400">
      {week.completed_games} of {week.total_games} played ·{' '}
      <span className="text-slate-200 font-semibold">
        {week.correct_games} / {week.graded_games} correct ({week.accuracy_pct}%)
      </span>
    </p>
  );
};

const Stat: React.FC<{ label: string; value: React.ReactNode; sub?: string }> = ({
  label,
  value,
  sub,
}) => (
  <div className="rounded-lg border border-slate-700 bg-slate-800/50 px-4 py-3">
    <p className="text-xs uppercase tracking-wide text-slate-500">{label}</p>
    <p className="text-lg font-bold text-white mt-0.5">{value}</p>
    {sub && <p className="text-xs text-slate-400 mt-0.5">{sub}</p>}
  </div>
);

const ViewButton: React.FC<{
  active: boolean;
  onClick: () => void;
  icon: React.ReactNode;
  label: string;
}> = ({ active, onClick, icon, label }) => (
  <button
    type="button"
    onClick={onClick}
    aria-pressed={active}
    className={`flex items-center gap-1.5 px-3 py-1.5 rounded text-sm transition-colors ${
      active
        ? 'bg-amber-500/20 text-amber-200 font-semibold'
        : 'text-slate-400 hover:text-slate-200'
    }`}
  >
    {icon}
    {label}
  </button>
);

const MatchupTable: React.FC<{ games: Matchup[] }> = ({ games }) => (
  <div className="overflow-x-auto rounded-lg border border-slate-700">
    <table className="w-full text-sm">
      <thead className="bg-slate-800/80 text-slate-400 text-xs uppercase tracking-wide">
        <tr>
          <th className="px-3 py-2 text-left font-medium">Date</th>
          <th className="px-3 py-2 text-left font-medium">Matchup</th>
          <th className="px-3 py-2 text-right font-medium">Score</th>
          <th className="px-3 py-2 text-left font-medium">Projected</th>
          <th className="px-3 py-2 text-right font-medium">Home win %</th>
          <th className="px-3 py-2 text-center font-medium">Result</th>
        </tr>
      </thead>
      <tbody className="divide-y divide-slate-700/70">
        {games.map((g) => (
          <tr key={g.game_id} className="hover:bg-slate-800/40">
            <td className="px-3 py-2 font-mono text-xs text-slate-400 whitespace-nowrap">
              {g.game_date}
            </td>
            <td className="px-3 py-2">
              <div className="flex items-center gap-1.5 whitespace-nowrap">
                <TeamLogo team={g.away_team} size="xs" />
                <span className="text-slate-300">{g.away_team}</span>
                <span className="text-slate-500">@</span>
                <TeamLogo team={g.home_team} size="xs" />
                <span className="text-slate-300">{g.home_team}</span>
              </div>
            </td>
            <td className="px-3 py-2 text-right font-mono tabular-nums whitespace-nowrap">
              {g.is_completed ? (
                <span className="text-slate-200">
                  {g.away_score} – {g.home_score}
                </span>
              ) : (
                <span className="text-slate-500">—</span>
              )}
            </td>
            <td className="px-3 py-2 whitespace-nowrap">
              {g.predicted_winner ? (
                <span className="text-slate-300">
                  {g.predicted_winner}
                  {g.projected_margin !== null && (
                    <span className="text-slate-500 font-mono ml-1">
                      by {Math.abs(g.projected_margin).toFixed(1)}
                    </span>
                  )}
                  {/* The weaker basis is marked inline so a reader scanning the
                      table can tell the two models apart without opening a card. */}
                  {g.projection_basis === 'team_rating_differential' && (
                    <span
                      className="text-slate-600 ml-1.5 text-xs"
                      title="Rating differential, not the per-game model. Never graded."
                    >
                      (rating)
                    </span>
                  )}
                </span>
              ) : (
                <span className="text-slate-500">—</span>
              )}
            </td>
            <td className="px-3 py-2 text-right font-mono tabular-nums text-slate-400">
              {g.home_win_prob !== null
                ? `${(g.home_win_prob * 100).toFixed(1)}%`
                : '—'}
            </td>
            <td className="px-3 py-2 text-center">
              {g.is_graded ? (
                g.prediction_correct ? (
                  <Check
                    className="w-4 h-4 text-emerald-400 inline"
                    aria-label="Correct"
                  />
                ) : (
                  <X className="w-4 h-4 text-rose-400 inline" aria-label="Miss" />
                )
              ) : (
                <CircleDashed
                  className="w-4 h-4 text-slate-600 inline"
                  aria-label={
                    g.has_logged_prediction ? 'Not resolved' : 'No prediction logged'
                  }
                />
              )}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  </div>
);
