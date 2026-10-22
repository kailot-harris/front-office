'use client';

import React, { useState, useMemo } from 'react';
import { MatchupsDataset, SlateStatus } from '@/lib/matchupTypes';
import { MatchupCard } from '@/components/MatchupCard';
import { TeamLogo } from '@/components/TeamLogo';
import {
  Calendar,
  Search,
  Grid,
  Table as TableIcon,
  CheckCircle2,
  XCircle,
  Clock,
  Radio,
  Target,
} from 'lucide-react';

interface MatchupsClientProps {
  dataset: MatchupsDataset;
}

const STATUS_COPY: Record<SlateStatus, string> = {
  past: 'Completed slate — graded against the pre-game model',
  active: 'Most recent slate with results',
  future: 'Upcoming slate — projections pending',
};

const pct = (p: number): string => `${(p * 100).toFixed(1)}%`;

export const MatchupsClient: React.FC<MatchupsClientProps> = ({ dataset }) => {
  const [selectedWeek, setSelectedWeek] = useState<number>(dataset.active_week);
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [viewMode, setViewMode] = useState<'grid' | 'table'>('grid');

  const selectedSlate = useMemo(
    () => dataset.available_weeks.find((w) => w.week === selectedWeek) ?? null,
    [dataset.available_weeks, selectedWeek]
  );

  const weekMatchups = useMemo(
    () => dataset.matchups.filter((m) => m.week === selectedWeek),
    [dataset.matchups, selectedWeek]
  );

  const filteredMatchups = useMemo(() => {
    const q = searchQuery.trim().toLowerCase();
    if (q.length === 0) return weekMatchups;
    return weekMatchups.filter(
      (m) =>
        m.home_team_name.toLowerCase().includes(q) ||
        m.away_team_name.toLowerCase().includes(q) ||
        m.home_team.toLowerCase().includes(q) ||
        m.away_team.toLowerCase().includes(q)
    );
  }, [weekMatchups, searchQuery]);

  // Per-slate model record, over the games carrying a gradeable pre-game pick.
  const gradedStats = useMemo(() => {
    const graded = weekMatchups.filter((m) => m.prediction_correct !== null);
    if (graded.length === 0) return null;
    const correct = graded.filter((m) => m.prediction_correct === true).length;
    return {
      total: graded.length,
      correct,
      accuracy: ((correct / graded.length) * 100).toFixed(1),
    };
  }, [weekMatchups]);

  const pendingCount = useMemo(
    () => weekMatchups.filter((m) => !m.is_completed).length,
    [weekMatchups]
  );

  const biggestMismatch = useMemo(() => {
    if (weekMatchups.length === 0) return null;
    return [...weekMatchups].sort(
      (a, b) => Math.abs(b.home_win_prob - 0.5) - Math.abs(a.home_win_prob - 0.5)
    )[0];
  }, [weekMatchups]);

  const slateStatus: SlateStatus = selectedSlate?.status ?? 'future';

  return (
    <div className="space-y-6">
      {/* Slate Ribbon */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-3 space-y-2">
        <div className="flex items-center gap-2">
          <Calendar className="w-4 h-4 text-accent-400" />
          <span className="text-xs font-mono font-bold uppercase text-slate-300">Select Slate</span>
          <span className="text-[11px] font-mono text-slate-500">
            {dataset.available_weeks.length} weeks · {dataset.total_games} games
          </span>
        </div>

        <div className="flex items-center gap-1.5 overflow-x-auto pb-1">
          {dataset.available_weeks.map((wk) => {
            const isSelected = selectedWeek === wk.week;
            return (
              <button
                key={wk.week}
                type="button"
                onClick={() => setSelectedWeek(wk.week)}
                title={`${wk.label} — ${STATUS_COPY[wk.status]}`}
                className={`cursor-pointer px-3 py-1.5 rounded-lg text-xs font-mono font-semibold transition-all whitespace-nowrap flex items-center gap-1.5 border ${
                  isSelected
                    ? 'bg-accent-600 text-white border-accent-500 shadow-md shadow-accent-600/30 font-bold'
                    : wk.status === 'active'
                    ? 'bg-surface-raised text-accent-400 border-accent-500/40 hover:bg-slate-800'
                    : 'bg-surface text-slate-400 border-slate-800 hover:text-white hover:bg-slate-800'
                }`}
              >
                <span>Wk {wk.week}</span>
                {wk.status === 'active' && <span className="text-amber-400 text-[10px]">★</span>}
                {wk.status === 'future' && !isSelected && (
                  <span className="text-[10px] text-slate-500 font-normal">·</span>
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* Slate Summary — the past / active / future branch */}
      {selectedSlate && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* Slate identity */}
          <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
            <div
              className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 border ${
                slateStatus === 'active'
                  ? 'bg-accent-500/10 border-accent-500/20'
                  : slateStatus === 'future'
                  ? 'bg-slate-500/10 border-slate-500/20'
                  : 'bg-emerald-500/10 border-emerald-500/20'
              }`}
            >
              {slateStatus === 'active' ? (
                <Radio className="w-5 h-5 text-accent-400" />
              ) : slateStatus === 'future' ? (
                <Clock className="w-5 h-5 text-slate-400" />
              ) : (
                <CheckCircle2 className="w-5 h-5 text-emerald-400" />
              )}
            </div>
            <div className="min-w-0">
              <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                Week {selectedSlate.week} · {slateStatus}
              </span>
              <span className="text-sm font-bold text-white block truncate">
                {selectedSlate.label}
              </span>
              <span className="text-[11px] font-mono text-slate-400">
                {selectedSlate.game_count} games
              </span>
            </div>
          </div>

          {/* Model record for graded slates, pending notice otherwise */}
          {gradedStats ? (
            <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center flex-shrink-0">
                <Target className="w-5 h-5 text-emerald-400" />
              </div>
              <div className="min-w-0">
                <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                  Model Record
                </span>
                <span className="text-sm font-bold text-emerald-400 block truncate">
                  {gradedStats.correct} / {gradedStats.total} correct ({gradedStats.accuracy}%)
                </span>
                <span className="text-[11px] font-mono text-slate-400">
                  Walk-forward pre-game picks
                </span>
              </div>
            </div>
          ) : (
            <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-slate-500/10 border border-slate-500/20 flex items-center justify-center flex-shrink-0">
                <Clock className="w-5 h-5 text-slate-400" />
              </div>
              <div className="min-w-0">
                <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                  Model Record
                </span>
                <span className="text-sm font-bold text-slate-300 block truncate">Pending</span>
                <span className="text-[11px] font-mono text-slate-400">
                  {pendingCount} game{pendingCount === 1 ? '' : 's'} awaiting results
                </span>
              </div>
            </div>
          )}

          {/* Strongest projected edge */}
          {biggestMismatch && (
            <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
              <div className="w-10 h-10 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-center flex-shrink-0">
                <Target className="w-5 h-5 text-amber-400" />
              </div>
              <div className="min-w-0">
                <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                  Largest Edge
                </span>
                <span className="text-sm font-bold text-white block truncate">
                  {biggestMismatch.home_win_prob > 0.5
                    ? biggestMismatch.home_team
                    : biggestMismatch.away_team}{' '}
                  {pct(Math.max(biggestMismatch.home_win_prob, biggestMismatch.away_win_prob))}
                </span>
                <span className="text-[11px] font-mono text-slate-400 truncate block">
                  {biggestMismatch.away_team} @ {biggestMismatch.home_team}
                </span>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Toolbar */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-3 flex flex-col md:flex-row md:items-center justify-between gap-3">
        <span className="text-xs font-mono text-slate-400">
          Showing {filteredMatchups.length} of {weekMatchups.length} games
        </span>

        <div className="flex items-center gap-2.5">
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Filter team..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="bg-surface border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-accent-500/50 w-36 sm:w-44"
            />
          </div>

          <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
            <button
              type="button"
              onClick={() => setViewMode('grid')}
              className={`p-1.5 rounded-md transition-colors ${
                viewMode === 'grid' ? 'bg-accent-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
              title="Card view"
              aria-label="Card view"
            >
              <Grid className="w-4 h-4" />
            </button>
            <button
              type="button"
              onClick={() => setViewMode('table')}
              className={`p-1.5 rounded-md transition-colors ${
                viewMode === 'table' ? 'bg-accent-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
              title="Table view"
              aria-label="Table view"
            >
              <TableIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {filteredMatchups.length === 0 && (
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-8 text-center text-sm text-slate-400 font-mono">
          No games match this filter for week {selectedWeek}.
        </div>
      )}

      {/* Card Grid */}
      {viewMode === 'grid' && filteredMatchups.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredMatchups.map((m) => (
            <MatchupCard key={m.game_pk} matchup={m} />
          ))}
        </div>
      )}

      {/* Table */}
      {viewMode === 'table' && filteredMatchups.length > 0 && (
        <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-surface/90 text-[11px] font-mono uppercase tracking-wider text-slate-400 border-b border-slate-800">
                <tr>
                  <th className="py-3 px-3">Date</th>
                  <th className="py-3 px-3">Away</th>
                  <th className="py-3 px-3 text-center">@</th>
                  <th className="py-3 px-3">Home</th>
                  <th className="py-3 px-3 text-center">Score</th>
                  <th className="py-3 px-3 text-right">Away Win %</th>
                  <th className="py-3 px-3 text-right">Home Win %</th>
                  <th className="py-3 px-3 text-center">Model</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {filteredMatchups.map((m) => {
                  const isHomeFavored = m.home_win_prob > 0.5;
                  return (
                    <tr key={m.game_pk} className="hover:bg-slate-800/40 transition-colors">
                      <td className="py-2.5 px-3 font-mono text-slate-300 whitespace-nowrap">
                        {m.game_date}
                      </td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={m.away_team} size="xs" />
                          <span className="font-bold text-white whitespace-nowrap">
                            {m.away_team}
                          </span>
                        </div>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono text-slate-500">@</td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={m.home_team} size="xs" />
                          <span className="font-bold text-white whitespace-nowrap">
                            {m.home_team}
                          </span>
                        </div>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono">
                        {m.is_completed ? (
                          <span className="font-bold text-white bg-surface px-2 py-0.5 rounded border border-slate-800 whitespace-nowrap">
                            {m.away_score} - {m.home_score}
                          </span>
                        ) : (
                          <span className="text-slate-600">—</span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 text-right font-mono font-bold">
                        <span className={!isHomeFavored ? 'text-accent-400' : 'text-slate-400'}>
                          {pct(m.away_win_prob)}
                        </span>
                      </td>
                      <td className="py-2.5 px-3 text-right font-mono font-bold">
                        <span className={isHomeFavored ? 'text-accent-400' : 'text-slate-400'}>
                          {pct(m.home_win_prob)}
                        </span>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono">
                        {m.prediction_correct === true ? (
                          <span className="text-emerald-400 font-bold px-1.5 py-0.5 rounded bg-emerald-500/10 border border-emerald-500/20 text-[10px] inline-flex items-center gap-1">
                            <CheckCircle2 className="w-2.5 h-2.5" /> Correct
                          </span>
                        ) : m.prediction_correct === false ? (
                          <span className="text-amber-400 font-bold px-1.5 py-0.5 rounded bg-amber-500/10 border border-amber-500/20 text-[10px] inline-flex items-center gap-1">
                            <XCircle className="w-2.5 h-2.5" /> Miss
                          </span>
                        ) : (
                          <span className="text-slate-600">—</span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
};
