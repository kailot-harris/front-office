'use client';

import React, { useState, useMemo } from 'react';
import { MatchupsDataset } from '@/lib/types';
import { MatchupCard } from '@/components/MatchupCard';
import { TeamLogo } from '@/components/TeamLogo';
import {
  Calendar,
  Swords,
  Search,
  Grid,
  Table as TableIcon,
  Zap,
  Shield,
} from 'lucide-react';

interface MatchupsClientProps {
  dataset: MatchupsDataset;
}

export const MatchupsClient: React.FC<MatchupsClientProps> = ({ dataset }) => {
  const [selectedWeek, setSelectedWeek] = useState<number>(dataset.active_week);
  const [selectedDay, setSelectedDay] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [viewMode, setViewMode] = useState<'grid' | 'table'>('grid');

  // Filter matchups by selected week, day, and search query
  const weekMatchups = useMemo(() => {
    return dataset.matchups.filter((m) => m.week === selectedWeek);
  }, [dataset.matchups, selectedWeek]);

  const filteredMatchups = useMemo(() => {
    return weekMatchups.filter((m) => {
      if (selectedDay !== 'All' && m.weekday !== selectedDay) return false;
      if (searchQuery.trim().length > 0) {
        const q = searchQuery.toLowerCase();
        const matchHome = m.home_team_name.toLowerCase().includes(q) || m.home_team.toLowerCase().includes(q);
        const matchAway = m.away_team_name.toLowerCase().includes(q) || m.away_team.toLowerCase().includes(q);
        if (!matchHome && !matchAway) return false;
      }
      return true;
    });
  }, [weekMatchups, selectedDay, searchQuery]);

  // Unique weekdays in the current week
  const daysInWeek = useMemo(() => {
    const set = new Set(weekMatchups.map((m) => m.weekday));
    return ['All', ...Array.from(set)];
  }, [weekMatchups]);

  // Key stats highlights
  const largestFavorite = useMemo(() => {
    if (weekMatchups.length === 0) return null;
    return [...weekMatchups].sort((a, b) => Math.abs(b.projected_margin) - Math.abs(a.projected_margin))[0];
  }, [weekMatchups]);

  const closestGame = useMemo(() => {
    if (weekMatchups.length === 0) return null;
    return [...weekMatchups].sort((a, b) => Math.abs(a.projected_margin) - Math.abs(b.projected_margin))[0];
  }, [weekMatchups]);

  const biggestRestMismatch = useMemo(() => {
    if (weekMatchups.length === 0) return null;
    return [...weekMatchups].sort((a, b) => Math.abs(b.rest_diff) - Math.abs(a.rest_diff))[0];
  }, [weekMatchups]);

  return (
    <div className="space-y-6">
      {/* Week Selector Ribbon */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-3 flex items-center justify-between gap-3 overflow-x-auto">
        <div className="flex items-center gap-2 flex-shrink-0">
          <Calendar className="w-4 h-4 text-emerald-400" />
          <span className="text-xs font-mono font-bold uppercase text-slate-300">Select Slate:</span>
        </div>

        <div className="flex items-center gap-1.5 flex-nowrap">
          {dataset.available_weeks.map((wk) => (
            <button
              key={wk}
              onClick={() => setSelectedWeek(wk)}
              className={`cursor-pointer px-3 py-1.5 rounded-lg text-xs font-mono font-semibold transition-all whitespace-nowrap ${
                selectedWeek === wk
                  ? 'bg-emerald-600 text-white shadow-md shadow-emerald-600/30 font-bold'
                  : 'bg-slate-950 text-slate-400 hover:text-white hover:bg-slate-800 border border-slate-800'
              }`}
            >
              Week {wk} {wk === dataset.active_week ? '★' : ''}
            </button>
          ))}
        </div>
      </div>

      {/* Week Highlights Bar */}
      {largestFavorite && closestGame && (
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
          {/* Largest Projected Favorite */}
          <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-emerald-500/10 border border-emerald-500/20 flex items-center justify-center flex-shrink-0">
              <Zap className="w-5 h-5 text-emerald-400" />
            </div>
            <div className="min-w-0">
              <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                Largest Favorite
              </span>
              <span className="text-sm font-bold text-white block truncate">
                {largestFavorite.projected_margin > 0
                  ? `${largestFavorite.home_team} (-${largestFavorite.projected_margin.toFixed(1)})`
                  : `${largestFavorite.away_team} (-${Math.abs(largestFavorite.projected_margin).toFixed(1)})`}
              </span>
              <span className="text-[11px] font-mono text-slate-400">
                vs {largestFavorite.projected_margin > 0 ? largestFavorite.away_team : largestFavorite.home_team}
              </span>
            </div>
          </div>

          {/* Closest Matchup / Pick'em */}
          <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-cyan-500/10 border border-cyan-500/20 flex items-center justify-center flex-shrink-0">
              <Swords className="w-5 h-5 text-cyan-400" />
            </div>
            <div className="min-w-0">
              <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                Closest Projection
              </span>
              <span className="text-sm font-bold text-white block truncate">
                {closestGame.away_team} @ {closestGame.home_team}
              </span>
              <span className="text-[11px] font-mono text-cyan-400">
                Line: {Math.abs(closestGame.projected_margin).toFixed(1)} pts
              </span>
            </div>
          </div>

          {/* Rest / Travel Mismatch */}
          <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-3.5 flex items-center gap-3">
            <div className="w-10 h-10 rounded-lg bg-amber-500/10 border border-amber-500/20 flex items-center justify-center flex-shrink-0">
              <Shield className="w-5 h-5 text-amber-400" />
            </div>
            <div className="min-w-0">
              <span className="text-[10px] font-mono uppercase text-slate-400 block font-semibold">
                Rest Differential
              </span>
              <span className="text-sm font-bold text-white block truncate">
                {biggestRestMismatch && biggestRestMismatch.rest_diff !== 0
                  ? biggestRestMismatch.rest_diff > 0
                    ? `${biggestRestMismatch.home_team} +${biggestRestMismatch.rest_diff}d Rest`
                    : `${biggestRestMismatch.away_team} +${Math.abs(biggestRestMismatch.rest_diff)}d Rest`
                  : 'Balanced Slates'}
              </span>
              <span className="text-[11px] font-mono text-slate-400">
                {biggestRestMismatch ? `${biggestRestMismatch.away_team} @ ${biggestRestMismatch.home_team}` : ''}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Filter and View Mode Toolbar */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-3 flex flex-col md:flex-row md:items-center justify-between gap-3">
        {/* Day Pills */}
        <div className="flex items-center gap-1.5 overflow-x-auto">
          {daysInWeek.map((day) => (
            <button
              key={day}
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

        {/* Right Search & Grid/Table Toggle */}
        <div className="flex items-center gap-2.5">
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Filter team..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="bg-slate-950 border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500/50 w-36 sm:w-44"
            />
          </div>

          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            <button
              onClick={() => setViewMode('grid')}
              className={`p-1.5 rounded-md text-xs transition-colors ${
                viewMode === 'grid' ? 'bg-emerald-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
              title="Card Grid View"
            >
              <Grid className="w-4 h-4" />
            </button>
            <button
              onClick={() => setViewMode('table')}
              className={`p-1.5 rounded-md text-xs transition-colors ${
                viewMode === 'table' ? 'bg-emerald-600 text-white' : 'text-slate-400 hover:text-white'
              }`}
              title="Compact Table View"
            >
              <TableIcon className="w-4 h-4" />
            </button>
          </div>
        </div>
      </div>

      {/* Grid View */}
      {viewMode === 'grid' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filteredMatchups.map((matchup) => (
            <MatchupCard key={matchup.game_id} matchup={matchup} />
          ))}
        </div>
      )}

      {/* Compact Table View */}
      {viewMode === 'table' && (
        <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-950/90 text-[11px] font-mono uppercase tracking-wider text-slate-400 border-b border-slate-800">
                <tr>
                  <th className="py-3 px-3">Date / Time</th>
                  <th className="py-3 px-3">Away Team</th>
                  <th className="py-3 px-3 text-center">@</th>
                  <th className="py-3 px-3">Home Team</th>
                  <th className="py-3 px-3 text-center">Projected Margin</th>
                  <th className="py-3 px-3 text-center">Total</th>
                  <th className="py-3 px-3 text-right">Away Win %</th>
                  <th className="py-3 px-3 text-right">Home Win %</th>
                  <th className="py-3 px-3 text-center">Rest Advantage</th>
                  <th className="py-3 px-3 text-center">Key Margin</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 font-sans">
                {filteredMatchups.map((m) => {
                  const isHomeFav = m.projected_margin > 0;
                  const favTeam = isHomeFav ? m.home_team : m.away_team;
                  const margin = Math.abs(m.projected_margin).toFixed(1);

                  return (
                    <tr key={m.game_id} className="hover:bg-slate-800/40 transition-colors">
                      <td className="py-2.5 px-3 font-mono text-slate-400 whitespace-nowrap">
                        {m.weekday.slice(0, 3)} {m.gametime}
                      </td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={m.away_team} size="xs" />
                          <span className="font-bold text-white">{m.away_team}</span>
                          <span className="text-[10px] font-mono text-slate-500">
                            {m.away_power_rating > 0 ? `+${m.away_power_rating.toFixed(1)}` : m.away_power_rating.toFixed(1)}
                          </span>
                        </div>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono text-slate-500">@</td>
                      <td className="py-2.5 px-3">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={m.home_team} size="xs" />
                          <span className="font-bold text-white">{m.home_team}</span>
                          <span className="text-[10px] font-mono text-slate-500">
                            {m.home_power_rating > 0 ? `+${m.home_power_rating.toFixed(1)}` : m.home_power_rating.toFixed(1)}
                          </span>
                        </div>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono font-bold text-emerald-400">
                        {favTeam} +{margin}
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono text-slate-400">
                        {m.projected_total.toFixed(1)}
                      </td>
                      <td className="py-2.5 px-3 text-right font-mono font-bold">
                        <span className={!isHomeFav ? 'text-emerald-400' : 'text-slate-400'}>
                          {(m.away_win_prob * 100).toFixed(1)}%
                        </span>
                      </td>
                      <td className="py-2.5 px-3 text-right font-mono font-bold">
                        <span className={isHomeFav ? 'text-emerald-400' : 'text-slate-400'}>
                          {(m.home_win_prob * 100).toFixed(1)}%
                        </span>
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono text-xs">
                        {m.rest_diff !== 0 ? (
                          <span className={m.rest_diff > 0 ? 'text-emerald-400' : 'text-amber-400'}>
                            {m.rest_diff > 0 ? `${m.home_team} +${m.rest_diff}d` : `${m.away_team} +${Math.abs(m.rest_diff)}d`}
                          </span>
                        ) : (
                          <span className="text-slate-500">Even</span>
                        )}
                      </td>
                      <td className="py-2.5 px-3 text-center font-mono text-xs">
                        {m.key_number_flag !== 'Standard' ? (
                          <span className="px-1.5 py-0.5 rounded bg-amber-500/20 text-amber-400 font-bold text-[10px]">
                            {m.key_number_flag}
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
