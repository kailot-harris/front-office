'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection, ModelMetadata } from '@/lib/types';
import { Trophy, TrendingUp, Filter, ArrowUpDown, ArrowUp, ArrowDown, ShieldAlert, Award } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { PlayoffContendersBoxWhisker } from '@/components/PlayoffContendersBoxWhisker';

interface StandingsClientProps {
  teams: TeamProjection[];
  metadata?: ModelMetadata;
}

export type StandingsSortField =
  | 'rank'
  | 'team'
  | 'conference'
  | 'division'
  | 'ensemble_mean_wins'
  | 'win_pct'
  | 'percentile_range'
  | 'ensemble_playoff_prob'
  | 'ensemble_title_prob';

export const StandingsClient: React.FC<StandingsClientProps> = ({ teams }) => {
  const [selectedConference, setSelectedConference] = useState<'All' | 'East' | 'West'>('All');
  const [selectedDivision, setSelectedDivision] = useState<string>('All');
  const [sortBy, setSortBy] = useState<StandingsSortField>('ensemble_mean_wins');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');

  const divisions = useMemo(() => {
    const set = new Set(teams.map((t) => t.division));
    return Array.from(set).sort();
  }, [teams]);

  const filteredTeams = useMemo(() => {
    return teams
      .filter((t) => {
        if (selectedConference !== 'All' && t.conference !== selectedConference) return false;
        if (selectedDivision !== 'All' && t.division !== selectedDivision) return false;
        return true;
      })
      .sort((a, b) => {
        let cmp = 0;
        if (sortBy === 'team') {
          cmp = a.team_name.localeCompare(b.team_name);
        } else if (sortBy === 'conference') {
          cmp = a.conference.localeCompare(b.conference) || b.ensemble_mean_wins - a.ensemble_mean_wins;
        } else if (sortBy === 'division') {
          cmp = a.division.localeCompare(b.division) || b.ensemble_mean_wins - a.ensemble_mean_wins;
        } else if (sortBy === 'rank') {
          cmp = (a.rank ?? 0) - (b.rank ?? 0);
        } else if (sortBy === 'percentile_range') {
          const rangeA = a.ensemble_p90 - a.ensemble_p10;
          const rangeB = b.ensemble_p90 - b.ensemble_p10;
          cmp = rangeA - rangeB;
        } else {
          const valA = (a[sortBy as keyof TeamProjection] as number) ?? 0;
          const valB = (b[sortBy as keyof TeamProjection] as number) ?? 0;
          cmp = valA - valB;
        }
        return sortOrder === 'desc' ? -cmp : cmp;
      });
  }, [teams, selectedConference, selectedDivision, sortBy, sortOrder]);

  const handleSort = (field: StandingsSortField) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      // Alphabetical and rank default to asc, stats default to desc
      if (field === 'team' || field === 'conference' || field === 'division' || field === 'rank') {
        setSortOrder('asc');
      } else {
        setSortOrder('desc');
      }
    }
  };

  const renderSortIndicator = (field: StandingsSortField) => {
    if (sortBy !== field) {
      return <ArrowUpDown className="w-3.5 h-3.5 text-slate-500 opacity-40 group-hover:opacity-100 transition-opacity" />;
    }
    return sortOrder === 'asc' ? (
      <ArrowUp className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    ) : (
      <ArrowDown className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    );
  };

  const topTitleFavorite = [...teams].sort((a, b) => b.ensemble_title_prob - a.ensemble_title_prob)[0];
  const topWinProjected = [...teams].sort((a, b) => b.ensemble_mean_wins - a.ensemble_mean_wins)[0];
  const mostVolatileTeam = [...teams].sort((a, b) => b.ensemble_sd_wins - a.ensemble_sd_wins)[0];

  return (
    <div className="space-y-6">
      {/* Top Stat Highlights */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topTitleFavorite?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Trophy className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Title Favorite</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topTitleFavorite?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0">
                {(topTitleFavorite?.ensemble_title_prob * 100).toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400">{topTitleFavorite?.ensemble_mean_wins.toFixed(1)} proj wins</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topWinProjected?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-emerald-500/20 text-emerald-400 rounded-md border border-emerald-500/30 shadow">
              <TrendingUp className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Top Projected Seed</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topWinProjected?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0">
                {topWinProjected?.ensemble_mean_wins.toFixed(1)}W
              </span>
            </div>
            <div className="text-xs text-slate-400">Win Pct {(topWinProjected?.win_pct * 100).toFixed(1)}%</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 text-indigo-400 rounded-lg flex-shrink-0">
            <Award className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Monte Carlo Iterations</div>
            <div className="text-xl font-bold text-white">1,000 Seasons</div>
            <div className="text-xs text-slate-400">1,230 Games / Iteration (4 Variants)</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={mostVolatileTeam?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-rose-500/20 text-rose-400 rounded-md border border-rose-500/30 shadow">
              <ShieldAlert className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">Highest Variance</div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{mostVolatileTeam?.team_name}</span>
              <span className="text-xs font-semibold text-rose-400 flex-shrink-0">
                ±{mostVolatileTeam?.ensemble_sd_wins.toFixed(1)} SD
              </span>
            </div>
            <div className="text-xs text-slate-400">Range: {mostVolatileTeam?.ensemble_p10.toFixed(0)} - {mostVolatileTeam?.ensemble_p90.toFixed(0)} wins</div>
          </div>
        </div>
      </div>

      {/* Filter and Control Bar */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="flex items-center gap-2 text-slate-400 text-sm font-medium">
            <Filter className="w-4 h-4" />
            <span>Filter By:</span>
          </div>

          {/* Conference filter pills */}
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            {(['All', 'East', 'West'] as const).map((conf) => (
              <button
                key={conf}
                onClick={() => setSelectedConference(conf)}
                className={`px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
                  selectedConference === conf
                    ? 'bg-indigo-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {conf} {conf !== 'All' ? 'Conf' : 'Leagues'}
              </button>
            ))}
          </div>

          {/* Division select dropdown */}
          <div className="flex items-center gap-2">
            <label className="text-xs text-slate-400">Division:</label>
            <select
              value={selectedDivision}
              onChange={(e) => setSelectedDivision(e.target.value)}
              className="bg-slate-950 border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-1.5 focus:outline-none focus:border-indigo-500"
            >
              <option value="All">All Divisions</option>
              {divisions.map((div) => (
                <option key={div} value={div}>
                  {div}
                </option>
              ))}
            </select>
          </div>
        </div>

        <div className="text-xs text-slate-400">
          Showing <span className="font-bold text-slate-200">{filteredTeams.length}</span> of 30 teams
        </div>
      </div>

      {/* Playoff Contenders Visualization Snapshot (Playoff Prob >= 40%) */}
      <PlayoffContendersBoxWhisker teams={teams} />

      {/* Main Standings Table */}
      <div className="bg-slate-900/70 border border-slate-800 rounded-xl shadow-xl overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead>
              <tr className="bg-slate-950/80 border-b border-slate-800 text-slate-400 font-medium text-xs select-none">
                <th
                  onClick={() => handleSort('rank')}
                  className="py-3.5 px-4 w-14 text-center cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort by rank"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span className={sortBy === 'rank' ? 'text-indigo-400 font-bold' : ''}>Rank</span>
                    {renderSortIndicator('rank')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('team')}
                  className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort alphabetically by team name"
                >
                  <div className="flex items-center gap-1.5">
                    <span className={sortBy === 'team' ? 'text-indigo-400 font-bold' : ''}>Team</span>
                    {renderSortIndicator('team')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('conference')}
                  className="py-3.5 px-3 text-center cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort by conference"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span className={sortBy === 'conference' ? 'text-indigo-400 font-bold' : ''}>Conf</span>
                    {renderSortIndicator('conference')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('division')}
                  className="py-3.5 px-3 text-center cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort by division"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span className={sortBy === 'division' ? 'text-indigo-400 font-bold' : ''}>Div</span>
                    {renderSortIndicator('division')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('ensemble_mean_wins')}
                  className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort by projected ensemble wins"
                >
                  <div className="flex items-center gap-1.5">
                    <span className={sortBy === 'ensemble_mean_wins' ? 'text-indigo-400 font-bold' : ''}>
                      Ensemble Wins
                    </span>
                    {renderSortIndicator('ensemble_mean_wins')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('win_pct')}
                  className="py-3.5 px-3 cursor-pointer hover:text-white transition-colors text-right group"
                  title="Click to sort by win percentage"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span className={sortBy === 'win_pct' ? 'text-indigo-400 font-bold' : ''}>Win %</span>
                    {renderSortIndicator('win_pct')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('percentile_range')}
                  className="py-3.5 px-4 min-w-[200px] cursor-pointer hover:text-white transition-colors group"
                  title="Click to sort by distribution width (p90 - p10 variance)"
                >
                  <div className="flex items-center gap-1.5">
                    <span className={sortBy === 'percentile_range' ? 'text-indigo-400 font-bold' : ''}>
                      10th - 90th Percentile Range
                    </span>
                    {renderSortIndicator('percentile_range')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('ensemble_playoff_prob')}
                  className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                  title="Click to sort by playoff probability"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span className={sortBy === 'ensemble_playoff_prob' ? 'text-indigo-400 font-bold' : ''}>
                      Playoffs
                    </span>
                    {renderSortIndicator('ensemble_playoff_prob')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('ensemble_title_prob')}
                  className="py-3.5 px-4 cursor-pointer hover:text-white transition-colors text-right group"
                  title="Click to sort by title probability"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span className={sortBy === 'ensemble_title_prob' ? 'text-indigo-400 font-bold' : ''}>
                      Title Prob
                    </span>
                    {renderSortIndicator('ensemble_title_prob')}
                  </div>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-sans">
              {filteredTeams.map((team, idx) => {
                const minScale = 15;
                const maxScale = 68;
                const rangeSpan = maxScale - minScale;
                const p10Pct = Math.max(0, Math.min(100, ((team.ensemble_p10 - minScale) / rangeSpan) * 100));
                const p90Pct = Math.max(0, Math.min(100, ((team.ensemble_p90 - minScale) / rangeSpan) * 100));
                const medianPct = Math.max(0, Math.min(100, ((team.ensemble_mean_wins - minScale) / rangeSpan) * 100));
                const barWidth = Math.max(2, p90Pct - p10Pct);

                const isPlayoffLock = team.ensemble_playoff_prob >= 0.85;
                const isPlayoffBubble = team.ensemble_playoff_prob >= 0.35 && team.ensemble_playoff_prob < 0.85;

                return (
                  <tr
                    key={team.team}
                    className="hover:bg-slate-800/40 transition-colors group text-slate-200"
                  >
                    <td className="py-3 px-4 text-center text-xs font-mono text-slate-400">
                      {idx + 1}
                    </td>
                    <td className="py-3 px-4">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-lg bg-slate-950/80 border border-slate-800 p-1 flex items-center justify-center flex-shrink-0 group-hover:border-slate-700 transition-colors">
                          <TeamLogo team={team.team} size="md" />
                        </div>
                        <div>
                          <div className="font-semibold text-white group-hover:text-indigo-400 transition-colors flex items-center gap-2">
                            <span>{team.team_name}</span>
                            <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800/80 text-amber-400 border border-slate-700/60 font-semibold">
                              {team.team}
                            </span>
                          </div>
                          <div className="text-xs text-slate-400">
                            {team.proj_wins.toFixed(1)}W - {team.proj_losses.toFixed(1)}L
                          </div>
                        </div>
                      </div>
                    </td>
                    <td className="py-3 px-3 text-center">
                      <span
                        className={`px-2 py-0.5 rounded text-xs font-semibold ${
                          team.conference === 'East'
                            ? 'bg-blue-500/10 text-blue-400 border border-blue-500/20'
                            : 'bg-red-500/10 text-red-400 border border-red-500/20'
                        }`}
                      >
                        {team.conference}
                      </span>
                    </td>
                    <td className="py-3 px-3 text-center text-xs text-slate-400">{team.division}</td>
                    <td className="py-3 px-4">
                      <div className="font-bold text-white text-base">
                        {team.ensemble_mean_wins.toFixed(1)}
                      </div>
                      <div className="text-xs text-slate-400 font-mono">
                        SD: ±{team.ensemble_sd_wins.toFixed(1)}
                      </div>
                    </td>
                    <td className="py-3 px-3 text-right font-mono font-medium text-slate-300">
                      {(team.win_pct * 100).toFixed(1)}%
                    </td>
                    <td className="py-3 px-4">
                      <div className="space-y-1">
                        <div className="flex items-center justify-between text-[11px] text-slate-400 font-mono">
                          <span>p10: {team.ensemble_p10.toFixed(0)}</span>
                          <span className="text-slate-300 font-semibold">{team.ensemble_mean_wins.toFixed(1)}</span>
                          <span>p90: {team.ensemble_p90.toFixed(0)}</span>
                        </div>
                        <div className="relative w-full h-2.5 bg-slate-800 rounded-full overflow-hidden">
                          {/* 10th to 90th percentile bar */}
                          <div
                            className="absolute top-0 bottom-0 bg-indigo-500/40 rounded-full"
                            style={{ left: `${p10Pct}%`, width: `${barWidth}%` }}
                          />
                          {/* Mean dot marker */}
                          <div
                            className="absolute top-0 bottom-0 w-1.5 bg-amber-400 rounded-full shadow"
                            style={{ left: `${medianPct}%` }}
                          />
                        </div>
                      </div>
                    </td>
                    <td className="py-3 px-4 text-right">
                      <span
                        className={`inline-block px-2.5 py-1 rounded-md text-xs font-bold font-mono ${
                          isPlayoffLock
                            ? 'bg-emerald-500/20 text-emerald-300 border border-emerald-500/30'
                            : isPlayoffBubble
                            ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                            : 'bg-slate-800 text-slate-400'
                        }`}
                      >
                        {(team.ensemble_playoff_prob * 100).toFixed(1)}%
                      </span>
                    </td>
                    <td className="py-3 px-4 text-right">
                      <span
                        className={`inline-block px-2 py-0.5 rounded text-xs font-bold font-mono ${
                          team.ensemble_title_prob >= 0.05
                            ? 'bg-amber-400/20 text-amber-300 border border-amber-400/30'
                            : 'text-slate-400'
                        }`}
                      >
                        {(team.ensemble_title_prob * 100).toFixed(1)}%
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
