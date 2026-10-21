'use client';

import React, { useMemo, useState } from 'react';
import { MatchupsDataset } from '@/lib/matchupTypes';
import { MatchupCard } from '@/components/MatchupCard';
import { TeamLogo } from '@/components/TeamLogo';
import { exportToCsv } from '@/lib/exportToCsv';
import { formatSeasonLabel } from '@/lib/season';
import {
  Calendar,
  CheckCircle2,
  Clock,
  Download,
  Grid,
  Search,
  Table as TableIcon,
  Zap,
} from 'lucide-react';

interface MatchupsClientProps {
  dataset: MatchupsDataset;
}

/**
 * Slate granularity is week-of-season buckets throughout (see lib/matchupTypes.ts
 * DESIGN DECISION 1); this component never groups by individual date.
 */
export const MatchupsClient: React.FC<MatchupsClientProps> = ({ dataset }) => {
  const [selectedSlate, setSelectedSlate] = useState<number>(dataset.active_slate);
  const [selectedDay, setSelectedDay] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [viewMode, setViewMode] = useState<'grid' | 'table'>('grid');

  const slateMeta = useMemo(
    () => dataset.slates.find((s) => s.slate === selectedSlate) ?? null,
    [dataset.slates, selectedSlate],
  );

  const slateGames = useMemo(
    () => dataset.matchups.filter((m) => m.slate === selectedSlate),
    [dataset.matchups, selectedSlate],
  );

  const daysInSlate = useMemo(
    () => ['All', ...Array.from(new Set(slateGames.map((m) => m.weekday)))],
    [slateGames],
  );

  const filteredGames = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    return slateGames.filter((m) => {
      if (selectedDay !== 'All' && m.weekday !== selectedDay) return false;
      if (q.length === 0) return true;
      return (
        m.home_team.toLowerCase().includes(q) ||
        m.away_team.toLowerCase().includes(q) ||
        m.home_team_name.toLowerCase().includes(q) ||
        m.away_team_name.toLowerCase().includes(q)
      );
    });
  }, [slateGames, selectedDay, searchQuery]);

  /**
   * "X / Y correct (Z%)" over GRADED games only — never over scheduled games.
   *
   * ZERO-GRADED STATE: returns null when the week has no graded game, which
   * early in a season is the whole season (see lib/matchupTypes.ts GRADING
   * STATE and dataset.grading_state === 'no_games_graded_yet'). Rendering below
   * branches on that null to show an explicit "Not yet graded" message, so the
   * accuracy figure is never printed as 0 / 0, NaN% or a misleading 0%.
   */
  const gradedStats = useMemo(() => {
    const graded = slateGames.filter((m) => m.is_completed && m.prediction_correct !== null);
    if (graded.length === 0) return null;
    const correct = graded.filter((m) => m.prediction_correct).length;
    return {
      total: graded.length,
      correct,
      accuracy: ((correct / graded.length) * 100).toFixed(1),
    };
  }, [slateGames]);

  /**
   * "Largest projected edge" is ranked WITHIN ONE BASIS ONLY.
   *
   * The dataset carries projections from two different models (see
   * lib/matchupTypes.ts DESIGN DECISION 2): the logged slate model and the
   * simpler team-rating differential. Their margins are not on a common scale,
   * so sorting them together would make this card imply a relationship between
   * numbers computed from unrelated inputs — the defect NBA issue #14 is open
   * against. The logged model is preferred when the week has any logged game;
   * otherwise the ratings basis is used, and the card names whichever it ranked.
   */
  const biggestSpread = useMemo(() => {
    const byBasis = (ratings: boolean) =>
      slateGames.filter(
        (m) =>
          m.predicted_margin !== null &&
          (m.projection_basis === 'team_rating_differential') === ratings,
      );
    const logged = byBasis(false);
    const pool = logged.length > 0 ? logged : byBasis(true);
    if (pool.length === 0) return null;
    const top = [...pool].sort(
      (a, b) => Math.abs(b.predicted_margin!) - Math.abs(a.predicted_margin!),
    )[0];
    return {
      game: top,
      basisLabel:
        top.projection_basis === 'team_rating_differential'
          ? 'Team-ratings basis only'
          : 'Logged-model basis only',
      pooled: pool.length,
    };
  }, [slateGames]);

  const handleExportCsv = () => {
    exportToCsv(
      filteredGames as unknown as Record<string, unknown>[],
      [
        { key: 'game_date', label: 'Date' },
        { key: 'weekday', label: 'Weekday' },
        { key: 'away_team', label: 'Away' },
        { key: 'home_team', label: 'Home' },
        { key: 'predicted_margin', label: 'Projected Margin (Home)' },
        { key: 'projection_basis', label: 'Projection Basis' },
        { key: 'predicted_home_win_prob', label: 'Home Win Prob' },
        { key: 'away_score', label: 'Away Score' },
        { key: 'home_score', label: 'Home Score' },
        { key: 'prediction_correct', label: 'Model Correct' },
      ],
      `nba-matchups-slate-${selectedSlate}`,
    );
  };

  return (
    <div className="space-y-6">
      {/* Slate selector ribbon — spans every slate in the season, past to future */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-3 space-y-2">
        <div className="flex items-center gap-2">
          <Calendar className="w-4 h-4 text-accent-400" />
          <span className="text-xs font-mono font-bold uppercase text-slate-300">Select slate</span>
          {slateMeta && (
            <span className="text-xs font-mono text-slate-400">· {slateMeta.label}</span>
          )}
        </div>
        <div className="flex items-center gap-1.5 overflow-x-auto pb-1">
          {dataset.available_slates.map((s) => {
            const meta = dataset.slates.find((x) => x.slate === s);
            const isSelected = s === selectedSlate;
            return (
              <button
                key={s}
                type="button"
                onClick={() => setSelectedSlate(s)}
                title={meta?.label}
                aria-pressed={isSelected}
                className={`cursor-pointer px-3 py-1.5 rounded-lg text-xs font-mono font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 ${
                  isSelected
                    ? 'bg-accent-600 text-white shadow-md shadow-accent-600/30 font-bold'
                    : meta?.status === 'active'
                      ? 'bg-surface-raised text-accent-400 border border-accent-500/40 hover:bg-slate-800'
                      : 'bg-surface text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-800'
                }`}
              >
                <span>Wk {s}</span>
                {meta?.status === 'active' && (
                  <span className="text-amber-400 text-[10px]">★ Active</span>
                )}
                {/* A past week with nothing graded says so rather than "Final". */}
                {meta?.status === 'past' && (
                  <span className="text-[10px] text-slate-500 font-normal">
                    {meta.graded_total > 0 ? 'Final' : 'Ungraded'}
                  </span>
                )}
                {meta?.status === 'future' && (
                  <span className="text-[10px] text-slate-500 font-normal">Upcoming</span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Slate summary bar */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-accent-500/10 border border-accent-500/20 flex items-center justify-center flex-shrink-0">
            {gradedStats ? (
              <CheckCircle2 className="w-5 h-5 text-accent-400" />
            ) : (
              <Clock className="w-5 h-5 text-amber-400" />
            )}
          </div>
          <div className="min-w-0">
            <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
              Model record this slate
            </span>
            <span className="text-sm font-bold block truncate text-white">
              {gradedStats
                ? `${gradedStats.correct} / ${gradedStats.total} correct (${gradedStats.accuracy}%)`
                : 'Not yet graded'}
            </span>
            <span className="text-[11px] font-mono text-slate-400">
              {gradedStats
                ? 'Graded games only'
                : dataset.grading_state === 'no_games_graded_yet'
                  ? `No ${formatSeasonLabel(dataset.season_label) ?? dataset.season_label} game graded yet`
                  : 'No graded game in this week yet'}
            </span>
          </div>
        </div>

        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-accent-500/10 border border-accent-500/20 flex items-center justify-center flex-shrink-0">
            <Zap className="w-5 h-5 text-accent-400" />
          </div>
          <div className="min-w-0">
            <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
              Largest projected edge
            </span>
            {biggestSpread ? (
              <>
                <span className="text-sm font-bold text-white block truncate">
                  {biggestSpread.game.predicted_margin! >= 0
                    ? biggestSpread.game.home_team
                    : biggestSpread.game.away_team}{' '}
                  −{Math.abs(biggestSpread.game.predicted_margin!).toFixed(1)}
                </span>
                <span className="text-[11px] font-mono text-slate-400">
                  {biggestSpread.game.away_team} @ {biggestSpread.game.home_team} ·{' '}
                  {biggestSpread.basisLabel}
                </span>
              </>
            ) : (
              <span className="text-sm font-bold text-slate-400 block">No projection</span>
            )}
          </div>
        </div>

        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
          <div className="w-10 h-10 rounded-lg bg-accent-500/10 border border-accent-500/20 flex items-center justify-center flex-shrink-0">
            <Calendar className="w-5 h-5 text-accent-400" />
          </div>
          <div className="min-w-0">
            <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
              Slate window
            </span>
            <span className="text-sm font-bold text-white block truncate">
              {slateMeta ? `${slateMeta.start_date} → ${slateMeta.end_date}` : '—'}
            </span>
            <span className="text-[11px] font-mono text-slate-400">
              {slateGames.length} games · {formatSeasonLabel(dataset.season_label) ?? dataset.season_label} season
            </span>
          </div>
        </div>
      </div>

      {/*
        PROJECTION BASIS LEGEND — the reader-facing statement that this week's
        projections come from two different models, with the count from each.
        Required so neither the cards nor the table can be read as one model's
        output (see lib/matchupTypes.ts DESIGN DECISION 2 and NBA issue #14).
      */}
      {slateMeta && (
        <div
          className="bg-surface-raised/60 border border-slate-800 rounded-xl p-3 text-[11px] font-mono text-slate-400 space-y-1.5"
          data-testid="projection-basis-legend"
        >
          <span className="text-[10px] font-mono uppercase text-slate-300 font-bold block">
            Two projection bases — not interchangeable
          </span>
          <div className="flex flex-wrap items-center gap-x-4 gap-y-1">
            <span className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-accent-400 inline-block" />
              <span>
                <span className="text-accent-400 font-bold">Logged model</span> ·{' '}
                {slateMeta.logged_projection_total} game
                {slateMeta.logged_projection_total === 1 ? '' : 's'} — the graded slate model&apos;s
                pre-game projection
              </span>
            </span>
            <span className="flex items-center gap-1.5">
              <span className="w-2 h-2 rounded-full bg-sky-300 inline-block" />
              <span>
                <span className="text-sky-300 font-bold">Team ratings</span> ·{' '}
                {slateMeta.ratings_projection_total} game
                {slateMeta.ratings_projection_total === 1 ? '' : 's'} — net-rating difference plus
                flat home court, not the logged model
              </span>
            </span>
          </div>
          <span className="block text-slate-500">
            The two are produced from unrelated inputs, so they are never averaged together and
            never ranked against each other. Only the logged model is graded for accuracy.
          </span>
        </div>
      )}

      {/* Day pills, search, view toggle */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-3 flex flex-col md:flex-row md:items-center justify-between gap-3">
        <div className="flex items-center gap-1.5 overflow-x-auto">
          {daysInSlate.map((day) => (
            <button
              key={day}
              type="button"
              onClick={() => setSelectedDay(day)}
              className={`cursor-pointer px-2.5 py-1 rounded-md text-xs font-mono font-medium transition-all ${
                selectedDay === day
                  ? 'bg-slate-800 text-white border border-slate-700 shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              {day}
            </button>
          ))}
        </div>

        <div className="flex items-center gap-2.5">
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Filter team..."
              aria-label="Filter matchups by team"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="bg-surface border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-accent-500/50 w-36 sm:w-44"
            />
          </div>

          <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
            <button
              type="button"
              onClick={() => setViewMode('grid')}
              title="Card grid view"
              aria-label="Card grid view"
              className={`p-1.5 rounded-md text-xs transition-colors ${
                viewMode === 'grid' ? 'bg-accent-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
            >
              <Grid className="w-4 h-4" />
            </button>
            <button
              type="button"
              onClick={() => setViewMode('table')}
              title="Compact table view"
              aria-label="Compact table view"
              className={`p-1.5 rounded-md text-xs transition-colors ${
                viewMode === 'table' ? 'bg-accent-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
            >
              <TableIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {filteredGames.length === 0 && (
        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-8 text-center text-sm text-slate-400 font-mono">
          No games match this filter in week {selectedSlate}.
        </div>
      )}

      {viewMode === 'grid' && filteredGames.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredGames.map((m) => (
            <MatchupCard key={m.game_id} matchup={m} />
          ))}
        </div>
      )}

      {viewMode === 'table' && filteredGames.length > 0 && (
        <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
          <div className="flex items-center justify-end px-3 py-2 border-b border-slate-800">
            <button
              type="button"
              onClick={handleExportCsv}
              title="Export CSV"
              aria-label="Export matchups table as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs font-mono">
              <thead className="bg-surface text-slate-400 uppercase text-[10px]">
                <tr>
                  <th className="text-left px-3 py-2 font-semibold">Date</th>
                  <th className="text-left px-3 py-2 font-semibold">Matchup</th>
                  <th className="text-right px-3 py-2 font-semibold">Proj. margin</th>
                  <th className="text-left px-3 py-2 font-semibold">Basis</th>
                  <th className="text-right px-3 py-2 font-semibold">Home win %</th>
                  <th className="text-right px-3 py-2 font-semibold">Score</th>
                  <th className="text-right px-3 py-2 font-semibold">Result</th>
                </tr>
              </thead>
              <tbody>
                {filteredGames.map((m) => (
                  <tr key={m.game_id} className="border-t border-slate-800/80">
                    <td className="px-3 py-2 text-slate-400 whitespace-nowrap">
                      {m.weekday} {m.game_date}
                    </td>
                    <td className="px-3 py-2">
                      <span className="flex items-center gap-1.5 text-white">
                        <TeamLogo team={m.away_team} size="xs" />
                        <span>{m.away_team}</span>
                        <span className="text-slate-500">@</span>
                        <TeamLogo team={m.home_team} size="xs" />
                        <span>{m.home_team}</span>
                      </span>
                    </td>
                    <td className="px-3 py-2 text-right text-accent-400 tabular-nums">
                      {m.predicted_margin === null
                        ? '—'
                        : `${m.predicted_margin > 0 ? '+' : ''}${m.predicted_margin.toFixed(1)}`}
                    </td>
                    {/* Which model produced the margin in the cell to the left. */}
                    <td
                      className={`px-3 py-2 whitespace-nowrap ${
                        m.projection_basis === 'team_rating_differential'
                          ? 'text-sky-300'
                          : 'text-accent-400'
                      }`}
                      data-projection-basis={m.projection_basis ?? 'none'}
                    >
                      {m.projection_basis === null
                        ? '—'
                        : m.projection_basis === 'team_rating_differential'
                          ? 'Team ratings'
                          : 'Logged model'}
                    </td>
                    <td className="px-3 py-2 text-right text-slate-300 tabular-nums">
                      {m.predicted_home_win_prob === null
                        ? '—'
                        : `${(m.predicted_home_win_prob * 100).toFixed(1)}%`}
                    </td>
                    <td className="px-3 py-2 text-right text-white tabular-nums whitespace-nowrap">
                      {m.is_completed ? `${m.away_score}–${m.home_score}` : '—'}
                    </td>
                    <td className="px-3 py-2 text-right whitespace-nowrap">
                      {m.is_completed && m.prediction_correct !== null ? (
                        <span
                          className={
                            m.prediction_correct ? 'text-accent-400' : 'text-rose-400'
                          }
                        >
                          {m.prediction_correct ? 'Correct' : 'Miss'}
                        </span>
                      ) : (
                        <span className="text-slate-500">Pending</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};
