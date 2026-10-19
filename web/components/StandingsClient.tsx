'use client';

import React, { useState, useMemo, useEffect } from 'react';
import { StandingsDataset } from '@/lib/types';
import {
  Trophy,
  Filter,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  Award,
  BarChart2,
  Table as TableIcon,
  Grid,
  Zap,
  TrendingUp,
  Search,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { WinDistributionBoxWhisker } from '@/components/WinDistributionBoxWhisker';

interface StandingsClientProps {
  dataset: StandingsDataset;
  initialTab?: 'visualizer' | 'table' | 'divisions';
}

export type StandingsSortField =
  | 'rank'
  | 'team'
  | 'division'
  | 'projected_wins'
  | 'point_diff'
  | 'power_rating'
  | 'net_epa_roll'
  | 'playoff_prob'
  | 'division_title_prob'
  | 'super_bowl_prob';

export const StandingsClient: React.FC<StandingsClientProps> = ({ dataset, initialTab = 'visualizer' }) => {
  const [activeTab, setActiveTab] = useState<'visualizer' | 'table' | 'divisions'>(initialTab);
  const [selectedConference, setSelectedConference] = useState<'All' | 'AFC' | 'NFC'>('All');
  const [selectedDivision, setSelectedDivision] = useState<string>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [sortBy, setSortBy] = useState<StandingsSortField>('projected_wins');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');

  const teams = dataset.teams;

  useEffect(() => {
    if (typeof window !== 'undefined') {
      const params = new URLSearchParams(window.location.search);
      const tabParam = params.get('view') || params.get('tab');
      if (tabParam === 'table' || tabParam === 'visualizer' || tabParam === 'divisions') {
        setActiveTab(tabParam);
      }
    }
  }, []);

  const handleTabChange = (tab: 'visualizer' | 'table' | 'divisions') => {
    setActiveTab(tab);
    if (typeof window !== 'undefined') {
      const url = new URL(window.location.href);
      url.searchParams.set('view', tab);
      url.searchParams.delete('tab');
      window.history.replaceState(null, '', url.toString());
    }
  };

  const divisions = useMemo(() => {
    const set = new Set(teams.map((t) => t.division));
    return Array.from(set).sort();
  }, [teams]);

  const filteredTeams = useMemo(() => {
    return teams
      .filter((t) => {
        if (selectedConference !== 'All' && t.conference !== selectedConference) return false;
        if (selectedDivision !== 'All' && t.division !== selectedDivision) return false;
        if (searchQuery.trim().length > 0) {
          const q = searchQuery.toLowerCase();
          const matchName = t.team_name.toLowerCase().includes(q);
          const matchAbbr = t.team.toLowerCase().includes(q);
          const matchDiv = t.division.toLowerCase().includes(q);
          if (!matchName && !matchAbbr && !matchDiv) return false;
        }
        return true;
      })
      .sort((a, b) => {
        let cmp = 0;
        if (sortBy === 'team') {
          cmp = a.team_name.localeCompare(b.team_name);
        } else if (sortBy === 'division') {
          cmp = a.division.localeCompare(b.division) || b.projected_wins - a.projected_wins;
        } else if (sortBy === 'rank') {
          cmp = a.rank - b.rank;
        } else {
          const valA = (a[sortBy] as number) ?? 0;
          const valB = (b[sortBy] as number) ?? 0;
          cmp = valA - valB;
        }
        return sortOrder === 'desc' ? -cmp : cmp;
      });
  }, [teams, selectedConference, selectedDivision, searchQuery, sortBy, sortOrder]);

  const handleSort = (field: StandingsSortField) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      if (field === 'team' || field === 'division' || field === 'rank') {
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
      <ArrowUp className="w-3.5 h-3.5 text-emerald-400 font-bold" />
    ) : (
      <ArrowDown className="w-3.5 h-3.5 text-emerald-400 font-bold" />
    );
  };

  // Highlights
  const topSbFavorite = useMemo(() => [...teams].sort((a, b) => b.super_bowl_prob - a.super_bowl_prob)[0], [teams]);
  const topPowerTeam = useMemo(() => [...teams].sort((a, b) => b.power_rating - a.power_rating)[0], [teams]);
  const topPointDiffTeam = useMemo(() => [...teams].sort((a, b) => b.point_diff - a.point_diff)[0], [teams]);
  const topPlayoffLock = useMemo(() => [...teams].sort((a, b) => b.playoff_prob - a.playoff_prob)[0], [teams]);

  return (
    <div className="space-y-6">
      {/* Top Stat Highlights */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Super Bowl Favorite */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5 shadow-sm">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topSbFavorite?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Trophy className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">Super Bowl Favorite</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topSbFavorite?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0 font-mono">
                {(topSbFavorite?.super_bowl_prob * 100).toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">{topSbFavorite?.projected_wins.toFixed(1)} proj wins</div>
          </div>
        </div>

        {/* Highest Power Rating */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5 shadow-sm">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topPowerTeam?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-emerald-500/20 text-emerald-400 rounded-md border border-emerald-500/30 shadow">
              <Zap className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">#1 Power Rating</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topPowerTeam?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0 font-mono">
                +{topPowerTeam?.power_rating.toFixed(2)} pts
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">Net EPA: +{topPowerTeam?.net_epa_roll.toFixed(3)}/play</div>
          </div>
        </div>

        {/* Best Point Differential */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5 shadow-sm">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topPointDiffTeam?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-cyan-500/20 text-cyan-400 rounded-md border border-cyan-500/30 shadow">
              <TrendingUp className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">Top Point Differential</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topPointDiffTeam?.team_name}</span>
              <span className="text-xs font-semibold text-cyan-400 flex-shrink-0 font-mono">
                +{topPointDiffTeam?.point_diff} pts
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">
              {topPointDiffTeam?.points_for} PF / {topPointDiffTeam?.points_against} PA
            </div>
          </div>
        </div>

        {/* Playoff Lock */}
        <div className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5 shadow-sm">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-slate-950/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topPlayoffLock?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-purple-500/20 text-purple-400 rounded-md border border-purple-500/30 shadow">
              <Award className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">Playoff Equity Leader</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topPlayoffLock?.team_name}</span>
              <span className="text-xs font-semibold text-purple-400 flex-shrink-0 font-mono">
                {(topPlayoffLock?.playoff_prob * 100).toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">
              Bye: {(topPlayoffLock?.first_round_bye_prob * 100).toFixed(0)}%
            </div>
          </div>
        </div>
      </div>

      {/* Navigation View Switcher & Filters Bar */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-3.5 flex flex-col md:flex-row md:items-center justify-between gap-4">
        {/* View Switcher Tabs */}
        <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
          <button
            onClick={() => handleTabChange('visualizer')}
            className={`cursor-pointer select-none flex items-center gap-2 px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
              activeTab === 'visualizer'
                ? 'bg-emerald-600 text-white shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <BarChart2 className="w-4 h-4" />
            <span>Distribution Visualizer</span>
          </button>
          <button
            onClick={() => handleTabChange('table')}
            className={`cursor-pointer select-none flex items-center gap-2 px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
              activeTab === 'table'
                ? 'bg-emerald-600 text-white shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <TableIcon className="w-4 h-4" />
            <span>Full 32 Table</span>
          </button>
          <button
            onClick={() => handleTabChange('divisions')}
            className={`cursor-pointer select-none flex items-center gap-2 px-3 py-1.5 text-xs font-semibold rounded-md transition-all ${
              activeTab === 'divisions'
                ? 'bg-emerald-600 text-white shadow-sm'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Grid className="w-4 h-4" />
            <span>8 Divisions</span>
          </button>
        </div>

        {/* Filter Controls */}
        <div className="flex flex-wrap items-center gap-2.5">
          {/* Search box */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Search franchise..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="bg-slate-950 border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500/50 w-40 sm:w-48"
            />
          </div>

          {/* Conference filter */}
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            {(['All', 'AFC', 'NFC'] as const).map((conf) => (
              <button
                key={conf}
                onClick={() => setSelectedConference(conf)}
                className={`cursor-pointer select-none px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                  selectedConference === conf
                    ? 'bg-emerald-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {conf}
              </button>
            ))}
          </div>

          {/* Division dropdown */}
          <div className="flex items-center gap-1.5">
            <Filter className="w-3.5 h-3.5 text-slate-500" />
            <select
              value={selectedDivision}
              onChange={(e) => setSelectedDivision(e.target.value)}
              className="bg-slate-950 border border-slate-800 text-slate-300 rounded-lg px-2.5 py-1.5 text-xs focus:outline-none focus:border-emerald-500/50"
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
      </div>

      {/* Tab 1: Visualizer */}
      {activeTab === 'visualizer' && (
        <div className="space-y-6">
          <WinDistributionBoxWhisker teams={teams} />

          {/* Franchise Cards Grid */}
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <h3 className="text-sm font-bold text-white uppercase tracking-wider font-mono">
                Franchise Power Ranks & Win Projections ({filteredTeams.length} Teams)
              </h3>
            </div>

            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
              {filteredTeams.map((team) => (
                <div
                  key={team.team}
                  className="bg-slate-900/70 border border-slate-800 rounded-xl p-4 space-y-3 hover:border-emerald-500/40 transition-all shadow-sm"
                >
                  <div className="flex items-center justify-between border-b border-slate-800/80 pb-2.5">
                    <div className="flex items-center gap-2.5 min-w-0">
                      <TeamLogo team={team.team} size="md" />
                      <div className="min-w-0">
                        <span className="font-bold text-sm text-white block truncate">{team.team_name}</span>
                        <span className="text-[10px] text-slate-400 font-mono">
                          {team.division} • Rank #{team.rank}
                        </span>
                      </div>
                    </div>
                    <span
                      className={`text-[11px] font-mono font-bold px-2 py-0.5 rounded ${
                        team.power_rating > 0
                          ? 'bg-emerald-500/10 text-emerald-400 border border-emerald-500/20'
                          : 'bg-red-500/10 text-red-400 border border-red-500/20'
                      }`}
                    >
                      {(team.power_rating ?? 0) > 0 ? `+${(team.power_rating ?? 0).toFixed(1)}` : (team.power_rating ?? 0).toFixed(1)}
                    </span>
                  </div>

                  <div className="grid grid-cols-2 gap-2 text-xs font-mono">
                    <div className="bg-slate-950/60 p-2 rounded-lg border border-slate-800/60">
                      <span className="text-[10px] text-slate-500 block uppercase">Proj Wins</span>
                      <span className="text-white font-bold text-sm">{team.projected_wins.toFixed(1)}W</span>
                      <span className="text-[10px] text-slate-500 block">
                        ({team.wins_p10.toFixed(0)} - {team.wins_p90.toFixed(0)})
                      </span>
                    </div>
                    <div className="bg-slate-950/60 p-2 rounded-lg border border-slate-800/60">
                      <span className="text-[10px] text-slate-500 block uppercase">Playoff Prob</span>
                      <span
                        className={`font-bold text-sm ${
                          team.playoff_prob >= 0.7
                            ? 'text-emerald-400'
                            : team.playoff_prob >= 0.4
                            ? 'text-cyan-400'
                            : 'text-amber-400'
                        }`}
                      >
                        {(team.playoff_prob * 100).toFixed(0)}%
                      </span>
                      <span className="text-[10px] text-slate-500 block">
                        Div: {(team.division_title_prob * 100).toFixed(0)}%
                      </span>
                    </div>
                  </div>

                  <div className="flex items-center justify-between text-[11px] font-mono text-slate-400 border-t border-slate-800/80 pt-2">
                    <span>
                      Net EPA:{' '}
                      <strong className={team.net_epa_roll > 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {team.net_epa_roll > 0 ? `+${team.net_epa_roll.toFixed(3)}` : team.net_epa_roll.toFixed(3)}
                      </strong>
                    </span>
                    <span>
                      Point Diff: <strong className="text-slate-200">{team.point_diff > 0 ? `+${team.point_diff}` : team.point_diff}</strong>
                    </span>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* Tab 2: Full 32 Table */}
      {activeTab === 'table' && (
        <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs">
              <thead className="bg-slate-950/90 text-[11px] font-mono uppercase tracking-wider text-slate-400 border-b border-slate-800">
                <tr>
                  <th
                    onClick={() => handleSort('rank')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white"
                  >
                    <div className="flex items-center gap-1.5">
                      <span>#</span>
                      {renderSortIndicator('rank')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('team')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white"
                  >
                    <div className="flex items-center gap-1.5">
                      <span>Franchise</span>
                      {renderSortIndicator('team')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('division')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white"
                  >
                    <div className="flex items-center gap-1.5">
                      <span>Division</span>
                      {renderSortIndicator('division')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('power_rating')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Power Rating</span>
                      {renderSortIndicator('power_rating')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('net_epa_roll')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Net EPA/Play</span>
                      {renderSortIndicator('net_epa_roll')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('point_diff')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Point Diff</span>
                      {renderSortIndicator('point_diff')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('projected_wins')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Proj Wins</span>
                      {renderSortIndicator('projected_wins')}
                    </div>
                  </th>
                  <th className="py-3.5 px-3 font-semibold text-center">
                    <span>p10 - p90 Range</span>
                  </th>
                  <th
                    onClick={() => handleSort('playoff_prob')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Playoff %</span>
                      {renderSortIndicator('playoff_prob')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('division_title_prob')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Div Title %</span>
                      {renderSortIndicator('division_title_prob')}
                    </div>
                  </th>
                  <th
                    onClick={() => handleSort('super_bowl_prob')}
                    className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                  >
                    <div className="flex items-center justify-end gap-1.5">
                      <span>Super Bowl %</span>
                      {renderSortIndicator('super_bowl_prob')}
                    </div>
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 font-sans">
                {filteredTeams.map((team, idx) => (
                  <tr
                    key={team.team}
                    className="hover:bg-slate-800/40 transition-colors group"
                  >
                    <td className="py-3 px-3 font-mono text-slate-500 font-bold text-center">
                      {idx + 1}
                    </td>
                    <td className="py-3 px-3">
                      <div className="flex items-center gap-2.5">
                        <TeamLogo team={team.team} size="sm" />
                        <div>
                          <span className="font-bold text-white group-hover:text-emerald-400 transition-colors block">
                            {team.team_name}
                          </span>
                          <span className="text-[10px] font-mono text-slate-500">
                            {team.team}
                          </span>
                        </div>
                      </div>
                    </td>
                    <td className="py-3 px-3 font-mono text-slate-400">
                      {team.division}
                    </td>
                    <td className="py-3 px-3 text-right font-mono font-bold">
                      <span className={(team.power_rating ?? 0) > 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {(team.power_rating ?? 0) > 0 ? `+${(team.power_rating ?? 0).toFixed(2)}` : (team.power_rating ?? 0).toFixed(2)}
                      </span>
                    </td>
                    <td className="py-3 px-3 text-right font-mono">
                      <span className={team.net_epa_roll > 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {team.net_epa_roll > 0 ? `+${team.net_epa_roll.toFixed(3)}` : team.net_epa_roll.toFixed(3)}
                      </span>
                    </td>
                    <td className="py-3 px-3 text-right font-mono">
                      <span className={team.point_diff > 0 ? 'text-cyan-400' : team.point_diff < 0 ? 'text-amber-400' : 'text-slate-400'}>
                        {team.point_diff > 0 ? `+${team.point_diff}` : team.point_diff}
                      </span>
                    </td>
                    <td className="py-3 px-3 text-right font-mono font-bold text-white text-sm">
                      {team.projected_wins.toFixed(1)}
                    </td>
                    <td className="py-3 px-3 text-center font-mono text-slate-400 text-[11px]">
                      {team.wins_p10.toFixed(0)} - {team.wins_p90.toFixed(0)} W
                    </td>
                    <td className="py-3 px-3 text-right font-mono font-bold">
                      <span
                        className={
                          team.playoff_prob >= 0.70
                            ? 'text-emerald-400'
                            : team.playoff_prob >= 0.40
                            ? 'text-cyan-400'
                            : 'text-amber-400'
                        }
                      >
                        {(team.playoff_prob * 100).toFixed(1)}%
                      </span>
                    </td>
                    <td className="py-3 px-3 text-right font-mono text-slate-300">
                      {(team.division_title_prob * 100).toFixed(1)}%
                    </td>
                    <td className="py-3 px-3 text-right font-mono font-bold text-amber-400">
                      {(team.super_bowl_prob * 100).toFixed(1)}%
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Tab 3: 8 Divisions View */}
      {activeTab === 'divisions' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {divisions.map((divName) => {
              const divTeams = teams
                .filter((t) => t.division === divName)
                .sort((a, b) => b.projected_wins - a.projected_wins);
              const isAfc = divName.startsWith('AFC');

              return (
                <div
                  key={divName}
                  className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-md flex flex-col justify-between"
                >
                  <div className="p-3 bg-slate-950/80 border-b border-slate-800 flex items-center justify-between">
                    <span className="font-bold text-xs text-white font-mono flex items-center gap-1.5">
                      <span className={`w-2 h-2 rounded-full ${isAfc ? 'bg-red-500' : 'bg-blue-500'}`} />
                      {divName}
                    </span>
                    <span className="text-[10px] font-mono text-slate-500">4 Teams</span>
                  </div>

                  <div className="p-2 space-y-1.5 divide-y divide-slate-800/40">
                    {divTeams.map((team, idx) => (
                      <div
                        key={team.team}
                        className="pt-1.5 first:pt-0 flex items-center justify-between hover:bg-slate-800/40 p-1.5 rounded-lg transition-colors"
                      >
                        <div className="flex items-center gap-2 min-w-0">
                          <span className="text-[10px] font-mono text-slate-500 font-bold w-3">
                            {idx + 1}
                          </span>
                          <TeamLogo team={team.team} size="sm" />
                          <div className="min-w-0">
                            <span className="font-semibold text-xs text-white block truncate">
                              {team.team_name}
                            </span>
                            <span className="text-[10px] font-mono text-slate-400">
                              PO: {(team.playoff_prob * 100).toFixed(0)}% • Div: {(team.division_title_prob * 100).toFixed(0)}%
                            </span>
                          </div>
                        </div>

                        <div className="text-right flex-shrink-0">
                          <span className="text-xs font-mono font-bold text-white block">
                            {team.projected_wins.toFixed(1)}W
                          </span>
                          <span
                            className={`text-[10px] font-mono ${
                              team.power_rating > 0 ? 'text-emerald-400' : 'text-red-400'
                            }`}
                          >
                            {(team.power_rating ?? 0) > 0 ? `+${(team.power_rating ?? 0).toFixed(1)}` : (team.power_rating ?? 0).toFixed(1)}
                          </span>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </div>
  );
};
