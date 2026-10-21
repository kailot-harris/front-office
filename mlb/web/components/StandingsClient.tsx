'use client';

import React, { useState, useMemo } from 'react';
import { TeamProjection, ModelMetadata } from '@/lib/types';
import {
  Trophy,
  TrendingUp,
  Filter,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  ShieldAlert,
  Award,
  BarChart2,
  Table,
  ArrowRight,
  Download,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { PlayoffContendersBoxWhisker } from '@/components/PlayoffContendersBoxWhisker';
import { exportToCsv } from '@/lib/exportToCsv';

interface StandingsClientProps {
  teams: TeamProjection[];
  metadata?: ModelMetadata;
  initialTab?: 'visualizer' | 'table';
}

export type StandingsSortField =
  | 'rank'
  | 'team'
  | 'league'
  | 'division'
  | 'ensemble_mean_wins'
  | 'win_pct'
  | 'elo_rating'
  | 'luck_wins'
  | 'percentile_range'
  | 'ensemble_playoff_prob'
  | 'ensemble_title_prob';

export const StandingsClient: React.FC<StandingsClientProps> = ({
  teams,
  initialTab = 'visualizer',
}) => {
  const [activeTab, setActiveTab] = useState<'visualizer' | 'table'>(initialTab);
  const [selectedLeague, setSelectedLeague] = useState<'All' | 'AL' | 'NL'>('All');
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
        if (selectedLeague !== 'All' && t.league !== selectedLeague) return false;
        if (selectedDivision !== 'All' && t.division !== selectedDivision) return false;
        return true;
      })
      .sort((a, b) => {
        let cmp = 0;
        if (sortBy === 'team') {
          cmp = a.team_name.localeCompare(b.team_name);
        } else if (sortBy === 'league') {
          cmp = a.league.localeCompare(b.league) || b.ensemble_mean_wins - a.ensemble_mean_wins;
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
  }, [teams, selectedLeague, selectedDivision, sortBy, sortOrder]);

  const handleSort = (field: StandingsSortField) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      if (field === 'team' || field === 'league' || field === 'division' || field === 'rank') {
        setSortOrder('asc');
      } else {
        setSortOrder('desc');
      }
    }
  };

  const renderSortIndicator = (field: StandingsSortField) => {
    if (sortBy !== field) {
      return (
        <ArrowUpDown className="w-3.5 h-3.5 text-slate-500 opacity-40 group-hover:opacity-100 transition-opacity" />
      );
    }
    return sortOrder === 'asc' ? (
      <ArrowUp className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    ) : (
      <ArrowDown className="w-3.5 h-3.5 text-indigo-400 font-bold" />
    );
  };

  const handleExportCsv = () => {
    exportToCsv(
      filteredTeams as unknown as Record<string, unknown>[],
      [
        { key: 'rank', label: 'Rank' },
        { key: 'full_name', label: 'Franchise' },
        { key: 'division', label: 'Division' },
        { key: 'ensemble_mean_wins', label: 'Proj Wins' },
        { key: 'proj_losses', label: 'Proj Losses' },
        { key: 'win_pct', label: 'Win %' },
        { key: 'elo_rating', label: 'Elo' },
        { key: 'luck_wins', label: 'Pythag Luck' },
        { key: 'ensemble_p10', label: 'P10 Wins' },
        { key: 'ensemble_p50', label: 'P50 Wins' },
        { key: 'ensemble_p90', label: 'P90 Wins' },
        { key: 'ensemble_playoff_prob', label: 'Playoff %' },
        { key: 'ensemble_title_prob', label: 'World Series %' },
      ],
      'mlb-standings'
    );
  };

  const topTitleFavorite = [...teams].sort(
    (a, b) => b.ensemble_title_prob - a.ensemble_title_prob
  )[0];
  const topWinProjected = [...teams].sort(
    (a, b) => b.ensemble_mean_wins - a.ensemble_mean_wins
  )[0];
  const mostVolatileTeam = [...teams].sort(
    (a, b) => b.ensemble_sd_wins - a.ensemble_sd_wins
  )[0];

  return (
    <div className="space-y-6">
      {/* Top Stat Highlights */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topTitleFavorite?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Trophy className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">
              World Series Favorite
            </div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topTitleFavorite?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0">
                {(topTitleFavorite?.ensemble_title_prob * 100).toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400">
              {topTitleFavorite?.ensemble_mean_wins.toFixed(1)}W • Pennant{' '}
              {(topTitleFavorite?.win_pennant_prob * 100).toFixed(1)}%
            </div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topWinProjected?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-emerald-500/20 text-emerald-400 rounded-md border border-emerald-500/30 shadow">
              <TrendingUp className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">
              Top Projected Club
            </div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topWinProjected?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0">
                {topWinProjected?.ensemble_mean_wins.toFixed(1)}W
              </span>
            </div>
            <div className="text-xs text-slate-400">
              Win Pct .{Math.round((topWinProjected?.win_pct ?? 0.5) * 1000)} • Elo{' '}
              {topWinProjected?.elo_rating.toFixed(0)}
            </div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 text-indigo-400 rounded-lg flex-shrink-0">
            <Award className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">
              Monte Carlo Engine
            </div>
            <div className="text-xl font-bold text-white">10K Bracket / 1K Season</div>
            <div className="text-xs text-slate-400">2,430 Games / Season (4 Variants)</div>
          </div>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={mostVolatileTeam?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-rose-500/20 text-rose-400 rounded-md border border-rose-500/30 shadow">
              <ShieldAlert className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">
              Highest Season Variance
            </div>
            <div className="text-lg font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{mostVolatileTeam?.team_name}</span>
              <span className="text-xs font-semibold text-rose-400 flex-shrink-0">
                ±{mostVolatileTeam?.ensemble_sd_wins.toFixed(1)} SD
              </span>
            </div>
            <div className="text-xs text-slate-400">
              Range: {mostVolatileTeam?.ensemble_p10.toFixed(0)} –{' '}
              {mostVolatileTeam?.ensemble_p90.toFixed(0)} wins
            </div>
          </div>
        </div>
      </div>

      {/* View Switcher: Playoff Contenders Snapshot vs Full League Standings Table */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800 pb-3">
        <div
          className="flex flex-wrap sm:inline-flex rounded-xl bg-surface p-1.5 border border-slate-800/80 shadow-inner relative z-20 w-full sm:w-auto gap-1 sm:gap-0"
          role="tablist"
        >
          <button
            type="button"
            role="tab"
            id="tab-btn-visualizer"
            aria-selected={activeTab === 'visualizer'}
            onClick={() => setActiveTab('visualizer')}
            className={`cursor-pointer select-none touch-manipulation flex-1 sm:flex-initial flex items-center justify-center gap-2.5 px-4 sm:px-5 py-2.5 rounded-lg text-xs sm:text-sm font-bold transition-all relative z-20 ${
              activeTab === 'visualizer'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/40 ring-1 ring-accent-400/50'
                : 'text-slate-400 hover:text-white hover:bg-surface-raised'
            }`}
          >
            <BarChart2 className="w-4 h-4 pointer-events-none" />
            <span className="pointer-events-none">Postseason Contenders (Box-Whisker)</span>
            <span
              className={`text-[10px] px-2 py-0.5 rounded font-mono pointer-events-none ${
                activeTab === 'visualizer'
                  ? 'bg-white/20 text-white font-bold'
                  : 'bg-slate-800 text-slate-400'
              }`}
            >
              Visualizer
            </span>
          </button>

          <button
            type="button"
            role="tab"
            id="tab-btn-table"
            aria-selected={activeTab === 'table'}
            onClick={() => setActiveTab('table')}
            className={`cursor-pointer select-none touch-manipulation flex-1 sm:flex-initial flex items-center justify-center gap-2.5 px-4 sm:px-5 py-2.5 rounded-lg text-xs sm:text-sm font-bold transition-all relative z-20 ${
              activeTab === 'table'
                ? 'bg-accent-600 text-white shadow-lg shadow-accent-600/40 ring-1 ring-accent-400/50'
                : 'text-slate-400 hover:text-white hover:bg-surface-raised'
            }`}
          >
            <Table className="w-4 h-4 pointer-events-none" />
            <span className="pointer-events-none">Full MLB Standings (30 Clubs)</span>
            <span
              className={`text-[10px] px-2 py-0.5 rounded font-mono pointer-events-none ${
                activeTab === 'table' ? 'bg-white/20 text-white font-bold' : 'bg-slate-800 text-slate-400'
              }`}
            >
              Full Table
            </span>
          </button>
        </div>

        {activeTab === 'visualizer' && (
          <button
            type="button"
            onClick={() => setActiveTab('table')}
            className="text-xs text-indigo-400 hover:text-indigo-300 font-semibold flex items-center gap-1 self-end sm:self-auto"
          >
            <span>Explore all 30 franchises & Pythagenpat / Elo metrics</span>
            <ArrowRight className="w-3.5 h-3.5" />
          </button>
        )}
      </div>

      {/* Tab 1: Box-Whisker Visualizer */}
      {activeTab === 'visualizer' && <PlayoffContendersBoxWhisker teams={teams} />}

      {/* Tab 2: Full Standings Table */}
      {activeTab === 'table' && (
        <div className="space-y-4">
          {/* Filter & Sort Controls */}
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex flex-wrap items-center gap-3">
              <div className="flex items-center gap-2 text-xs text-slate-400">
                <Filter className="w-4 h-4 text-indigo-400" />
                <span className="font-semibold uppercase">League:</span>
              </div>
              <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
                {(['All', 'AL', 'NL'] as const).map((lg) => (
                  <button
                    key={lg}
                    onClick={() => {
                      setSelectedLeague(lg);
                      setSelectedDivision('All');
                    }}
                    className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                      selectedLeague === lg
                        ? 'bg-accent-600 text-white shadow-sm'
                        : 'text-slate-400 hover:text-white'
                    }`}
                  >
                    {lg === 'All' ? 'All MLB' : lg}
                  </button>
                ))}
              </div>

              <select
                value={selectedDivision}
                onChange={(e) => setSelectedDivision(e.target.value)}
                className="bg-surface border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-1.5 focus:outline-none focus:border-indigo-500"
              >
                <option value="All">All 6 Divisions</option>
                {divisions.map((d) => (
                  <option key={d} value={d}>
                    {d}
                  </option>
                ))}
              </select>
            </div>

            <div className="flex items-center gap-3">
              <div className="text-xs text-slate-400 font-mono">
                Showing <span className="text-white font-bold">{filteredTeams.length}</span> of 30 MLB
                Franchises
              </div>
              <button
                type="button"
                onClick={handleExportCsv}
                title="Export CSV"
                aria-label="Export table as CSV"
                data-export-exclude
                className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
              >
                <Download className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>

          {/* Main Standings Table */}
          <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
            <div className="overflow-x-auto">
              <table className="w-full text-left border-collapse">
                <thead>
                  <tr className="border-b border-slate-800 bg-surface/80 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                    <th
                      onClick={() => handleSort('rank')}
                      className="py-3.5 px-3 cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center gap-1">
                        <span>Rk</span>
                        {renderSortIndicator('rank')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('team')}
                      className="py-3.5 px-4 cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center gap-1">
                        <span>Franchise</span>
                        {renderSortIndicator('team')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('division')}
                      className="py-3.5 px-3 cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center gap-1">
                        <span>Div</span>
                        {renderSortIndicator('division')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('ensemble_mean_wins')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Proj W-L</span>
                        {renderSortIndicator('ensemble_mean_wins')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('win_pct')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Win%</span>
                        {renderSortIndicator('win_pct')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('elo_rating')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Elo (rGS)</span>
                        {renderSortIndicator('elo_rating')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('luck_wins')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Pythag Luck</span>
                        {renderSortIndicator('luck_wins')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('percentile_range')}
                      className="py-3.5 px-4 text-center cursor-pointer hover:text-white group select-none min-w-[170px]"
                    >
                      <div className="flex items-center justify-center gap-1">
                        <span>10th – 90th Pct Range</span>
                        {renderSortIndicator('percentile_range')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('ensemble_playoff_prob')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Playoff %</span>
                        {renderSortIndicator('ensemble_playoff_prob')}
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('ensemble_title_prob')}
                      className="py-3.5 px-4 text-right cursor-pointer hover:text-white group select-none"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>World Series %</span>
                        {renderSortIndicator('ensemble_title_prob')}
                      </div>
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60 text-sm">
                  {filteredTeams.map((team) => {
                    const minBar = 55;
                    const maxBar = 112;
                    const span = maxBar - minBar;
                    const leftPct = Math.max(0, Math.min(100, ((team.ensemble_p10 - minBar) / span) * 100));
                    const widthPct = Math.max(
                      4,
                      Math.min(100 - leftPct, ((team.ensemble_p90 - team.ensemble_p10) / span) * 100)
                    );
                    const medianPct = Math.max(
                      0,
                      Math.min(100, ((team.ensemble_p50 - minBar) / span) * 100)
                    );

                    return (
                      <tr
                        key={team.team}
                        className="hover:bg-slate-800/40 transition-colors"
                      >
                        <td className="py-3 px-3 font-mono text-xs text-slate-400">
                          #{team.rank}
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex items-center gap-3">
                            <TeamLogo team={team.team} size="md" />
                            <div>
                              <div className="font-bold text-white flex items-center gap-1.5">
                                <span>{team.full_name}</span>
                                <span className="text-[10px] font-mono text-slate-400">
                                  ({team.team})
                                </span>
                              </div>
                              <div className="text-[11px] text-slate-400 font-mono">
                                wOBA {team.team_woba_pooled.toFixed(3)} • xFIP{' '}
                                {team.team_xfip_pooled.toFixed(2)}
                              </div>
                            </div>
                          </div>
                        </td>
                        <td className="py-3 px-3">
                          <span
                            className={`text-xs font-mono px-2 py-0.5 rounded border ${
                              team.league === 'AL'
                                ? 'bg-sky-500/10 text-sky-300 border-sky-500/20'
                                : 'bg-amber-500/10 text-amber-300 border-amber-500/20'
                            }`}
                          >
                            {team.division}
                          </span>
                        </td>
                        <td className="py-3 px-3 text-right font-mono">
                          <span className="font-bold text-white">
                            {team.ensemble_mean_wins.toFixed(1)}
                          </span>
                          <span className="text-slate-400">
                            –{team.proj_losses.toFixed(1)}
                          </span>
                        </td>
                        <td className="py-3 px-3 text-right font-mono text-slate-300">
                          .{Math.round(team.win_pct * 1000).toString().padStart(3, '0')}
                        </td>
                        <td className="py-3 px-3 text-right font-mono">
                          <div className="text-white font-semibold">
                            {team.elo_rating.toFixed(0)}
                          </div>
                          <div className="text-[10px] text-slate-400">
                            rGS {team.team_rgs.toFixed(1)}
                          </div>
                        </td>
                        <td className="py-3 px-3 text-right font-mono text-xs">
                          <span
                            className={
                              team.luck_wins > 1.5
                                ? 'text-amber-400 font-semibold'
                                : team.luck_wins < -1.5
                                ? 'text-emerald-400 font-semibold'
                                : 'text-slate-400'
                            }
                          >
                            {team.luck_wins > 0 ? `+${team.luck_wins.toFixed(1)}` : team.luck_wins.toFixed(1)}W
                          </span>
                        </td>
                        <td className="py-3 px-4">
                          <div className="flex flex-col gap-1">
                            <div className="relative h-2 bg-surface rounded-full overflow-hidden border border-slate-800">
                              <div
                                className="absolute top-0 bottom-0 bg-indigo-500/50 rounded-full"
                                style={{ left: `${leftPct}%`, width: `${widthPct}%` }}
                              />
                              <div
                                className="absolute top-0 bottom-0 w-1 bg-amber-400 rounded-full -translate-x-1/2"
                                style={{ left: `${medianPct}%` }}
                              />
                            </div>
                            <div className="flex justify-between text-[10px] font-mono text-slate-400">
                              <span>p10: {team.ensemble_p10.toFixed(0)}W</span>
                              <span className="text-amber-400 font-semibold">
                                p50: {team.ensemble_p50.toFixed(0)}W
                              </span>
                              <span>p90: {team.ensemble_p90.toFixed(0)}W</span>
                            </div>
                          </div>
                        </td>
                        <td className="py-3 px-3 text-right font-mono">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-bold ${
                              team.ensemble_playoff_prob >= 0.8
                                ? 'bg-emerald-500/15 text-emerald-400'
                                : team.ensemble_playoff_prob >= 0.35
                                ? 'bg-indigo-500/15 text-indigo-300'
                                : 'text-slate-500'
                            }`}
                          >
                            {(team.ensemble_playoff_prob * 100).toFixed(1)}%
                          </span>
                        </td>
                        <td className="py-3 px-4 text-right font-mono">
                          <span
                            className={`px-2 py-0.5 rounded text-xs font-bold ${
                              team.ensemble_title_prob >= 0.1
                                ? 'bg-amber-500/20 text-amber-300 border border-amber-500/30'
                                : team.ensemble_title_prob >= 0.03
                                ? 'text-slate-200'
                                : 'text-slate-500'
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
      )}
    </div>
  );
};
