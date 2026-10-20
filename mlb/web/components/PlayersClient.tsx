'use client';

import React, { useState, useMemo, useEffect } from 'react';
import { PlayerProjection, PlayerSpatialMap } from '@/lib/types';
import {
  Search,
  AlertTriangle,
  ArrowUpDown,
  Filter,
  Sparkles,
  UserCheck,
  Shield,
  Zap,
  ChevronDown,
  ChevronUp,
  Compass,
  Crosshair,
} from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { PlayerSpatialDropdown } from '@/components/PlayerSpatialDropdown';
import { BASE_PATH } from '@/lib/basePath';

interface PlayersClientProps {
  players: PlayerProjection[];
  initialSpatialMaps?: Record<string, PlayerSpatialMap>;
}

export const PlayersClient: React.FC<PlayersClientProps> = ({
  players,
  initialSpatialMaps,
}) => {
  const [activeGroup, setActiveGroup] = useState<'Batter' | 'Pitcher'>('Batter');
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTeam, setSelectedTeam] = useState<string>('All');
  const [pitcherRole, setPitcherRole] = useState<'All' | 'SP' | 'RP'>('All');
  const [onlyOutliers, setOnlyOutliers] = useState<boolean>(false);
  const [statMode, setStatMode] = useState<'pooled_rates' | 'marcel_totals'>('pooled_rates');
  const [sortBy, setSortBy] = useState<keyof PlayerProjection>('stat1_pooled');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');

  // Expanded dropdown map state & spatial telemetry dictionary
  const [expandedPlayerId, setExpandedPlayerId] = useState<string | null>(null);
  const [spatialMaps, setSpatialMaps] = useState<Record<string, PlayerSpatialMap>>(
    initialSpatialMaps || {}
  );

  useEffect(() => {
    if (!initialSpatialMaps || Object.keys(initialSpatialMaps).length === 0) {
      fetch(`${BASE_PATH}/data/player_spatial_maps.json`)
        .then((res) => {
          if (!res.ok) throw new Error('Failed to fetch player spatial maps');
          return res.json();
        })
        .then((data: Record<string, PlayerSpatialMap>) => setSpatialMaps(data))
        .catch((err) => console.warn('Could not load player spatial maps:', err));
    }
  }, [initialSpatialMaps]);


  const batters = useMemo(() => players.filter((p) => p.player_type === 'Batter'), [players]);
  const pitchers = useMemo(() => players.filter((p) => p.player_type === 'Pitcher'), [players]);

  const teams = useMemo(() => {
    const set = new Set(players.map((p) => p.team).filter((t) => t && t !== 'MLB'));
    return Array.from(set).sort();
  }, [players]);

  const outlierCount = useMemo(() => {
    const pool = activeGroup === 'Batter' ? batters : pitchers;
    return pool.filter((p) => p.is_outlier).length;
  }, [activeGroup, batters, pitchers]);

  const topBatter = useMemo(() => {
    return [...batters].sort((a, b) => b.composite_zscore - a.composite_zscore)[0];
  }, [batters]);

  const topPitcher = useMemo(() => {
    return [...pitchers]
      .filter((p) => p.position === 'SP')
      .sort((a, b) => a.stat1_pooled - b.stat1_pooled)[0];
  }, [pitchers]);

  const handleGroupSwitch = (group: 'Batter' | 'Pitcher') => {
    setActiveGroup(group);
    if (statMode === 'pooled_rates') {
      setSortBy('stat1_pooled');
      // For Batters wOBA: higher is better ('desc'). For Pitchers xFIP: lower is better ('asc').
      setSortOrder(group === 'Batter' ? 'desc' : 'asc');
    } else {
      setSortBy('count1_val');
      setSortOrder('desc');
    }
  };

  const filteredPlayers = useMemo(() => {
    const basePool = activeGroup === 'Batter' ? batters : pitchers;
    return basePool
      .filter((p) => {
        if (onlyOutliers && !p.is_outlier) return false;
        if (selectedTeam !== 'All' && p.team !== selectedTeam) return false;
        if (activeGroup === 'Pitcher' && pitcherRole !== 'All' && p.position !== pitcherRole) {
          return false;
        }
        if (searchTerm.trim() !== '') {
          const term = searchTerm.toLowerCase();
          const matchName = p.player_name.toLowerCase().includes(term);
          const matchTeam = p.team.toLowerCase().includes(term);
          if (!matchName && !matchTeam) return false;
        }
        return true;
      })
      .sort((a, b) => {
        const valA = (a[sortBy] as number) ?? 0;
        const valB = (b[sortBy] as number) ?? 0;
        return sortOrder === 'desc' ? valB - valA : valA - valB;
      });
  }, [
    activeGroup,
    batters,
    pitchers,
    onlyOutliers,
    selectedTeam,
    pitcherRole,
    searchTerm,
    sortBy,
    sortOrder,
  ]);

  const handleSort = (field: keyof PlayerProjection) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      // Lower is better for Pitcher xFIP / ERA
      if (
        activeGroup === 'Pitcher' &&
        (field === 'stat1_pooled' || field === 'stat1_raw' || field === 'stat2_pooled')
      ) {
        setSortOrder('asc');
      } else {
        setSortOrder('desc');
      }
    }
  };

  return (
    <div className="space-y-6">
      {/* Top-Level Batter / Pitcher Group Toggle */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 bg-slate-900/90 border border-slate-800 rounded-xl p-3 shadow-lg">
        <div className="inline-flex rounded-xl bg-slate-950 p-1 border border-slate-800">
          <button
            type="button"
            onClick={() => handleGroupSwitch('Batter')}
            className={`flex items-center gap-2.5 px-5 py-2.5 rounded-lg text-sm font-bold transition-all ${
              activeGroup === 'Batter'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Zap className="w-4 h-4" />
            <span>MLB Batters</span>
            <span
              className={`text-xs font-mono px-2 py-0.5 rounded-full ${
                activeGroup === 'Batter'
                  ? 'bg-white/20 text-white'
                  : 'bg-slate-800 text-slate-400'
              }`}
            >
              {batters.length} Hitters
            </span>
          </button>

          <button
            type="button"
            onClick={() => handleGroupSwitch('Pitcher')}
            className={`flex items-center gap-2.5 px-5 py-2.5 rounded-lg text-sm font-bold transition-all ${
              activeGroup === 'Pitcher'
                ? 'bg-emerald-600 text-white shadow-lg shadow-emerald-600/30'
                : 'text-slate-400 hover:text-white'
            }`}
          >
            <Shield className="w-4 h-4" />
            <span>MLB Pitchers (SP & RP)</span>
            <span
              className={`text-xs font-mono px-2 py-0.5 rounded-full ${
                activeGroup === 'Pitcher'
                  ? 'bg-white/20 text-white'
                  : 'bg-slate-800 text-slate-400'
              }`}
            >
              {pitchers.length} Arms
            </span>
          </button>
        </div>

        <div className="text-xs text-slate-400 px-2">
          {activeGroup === 'Batter' ? (
            <span>
              Showing <strong className="text-white">Empirical Bayes Pooled wOBA / ISO</strong> &{' '}
              <strong className="text-amber-400">Marcel 5/4/3 HR / OBP</strong> projections
            </span>
          ) : (
            <span>
              Showing <strong className="text-white">Empirical Bayes Pooled xFIP / K%</strong>,{' '}
              <strong className="text-sky-400">Starter rGS</strong> &{' '}
              <strong className="text-amber-400">Marcel ERA / SO</strong> projections
            </span>
          )}
        </div>
      </div>

      {/* Overview KPI Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-amber-500/10 text-amber-400 rounded-lg">
            <UserCheck className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">
              Active {activeGroup} Pool
            </div>
            <div className="text-2xl font-bold text-white">
              {activeGroup === 'Batter' ? `${batters.length} Hitters` : `${pitchers.length} Pitchers`}
            </div>
            <div className="text-xs text-slate-400">
              {activeGroup === 'Batter'
                ? 'Park-neutralized wOBA & ISO'
                : 'SP & RP xFIP, K% & rGS tracked'}
            </div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-rose-500/10 text-rose-400 rounded-lg">
            <AlertTriangle className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">
              Statistical Outliers (|z| ≥ 2.0)
            </div>
            <div className="text-2xl font-bold text-rose-400">{outlierCount} Players</div>
            <div className="text-xs text-slate-400">Post-shrinkage 95th-percentile tails</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 text-indigo-400 rounded-lg">
            <Sparkles className="w-6 h-6" />
          </div>
          <div className="min-w-0">
            <div className="text-xs text-slate-400 uppercase font-semibold">
              {activeGroup === 'Batter' ? 'Top Pooled Batter' : 'Top Pooled Starter'}
            </div>
            <div className="text-base font-bold text-white truncate">
              {activeGroup === 'Batter'
                ? `${topBatter?.player_name} (${topBatter?.team})`
                : `${topPitcher?.player_name} (${topPitcher?.team})`}
            </div>
            <div className="text-xs text-slate-400 font-mono">
              {activeGroup === 'Batter'
                ? `.${Math.round((topBatter?.stat1_pooled ?? 0.32) * 1000)} wOBA • ${topBatter?.count1_val} Proj HR`
                : `${topPitcher?.stat1_pooled.toFixed(2)} xFIP • ${topPitcher?.k_pct_pooled.toFixed(1)}% K`}
            </div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-emerald-500/10 text-emerald-400 rounded-lg">
            <Filter className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Filter Matches</div>
            <div className="text-2xl font-bold text-emerald-400">
              {filteredPlayers.length} {activeGroup}s
            </div>
            <div className="text-xs text-slate-400">Matching active query criteria</div>
          </div>
        </div>
      </div>

      {/* Control Panel: Search, Filters, Stat Mode */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-4 flex flex-wrap items-center justify-between gap-4">
        <div className="flex flex-wrap items-center gap-3 flex-1 min-w-[280px]">
          {/* Search Input */}
          <div className="relative flex-1 min-w-[200px]">
            <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder={`Search ${activeGroup.toLowerCase()} name or club...`}
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="w-full bg-slate-950 border border-slate-800 text-sm text-slate-200 rounded-lg pl-9 pr-3 py-1.5 focus:outline-none focus:border-indigo-500"
            />
          </div>

          {/* Team filter */}
          <select
            value={selectedTeam}
            onChange={(e) => setSelectedTeam(e.target.value)}
            className="bg-slate-950 border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-2 focus:outline-none focus:border-indigo-500"
          >
            <option value="All">All 30 Clubs</option>
            {teams.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>

          {/* Pitcher Role filter (shown whenPitchers tab is active) */}
          {activeGroup === 'Pitcher' && (
            <select
              value={pitcherRole}
              onChange={(e) => setPitcherRole(e.target.value as 'All' | 'SP' | 'RP')}
              className="bg-slate-950 border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-2 focus:outline-none focus:border-indigo-500"
            >
              <option value="All">All Roles (SP + RP)</option>
              <option value="SP">Starting Pitchers (SP)</option>
              <option value="RP">Relief Pitchers (RP)</option>
            </select>
          )}

          {/* Outlier filter toggle */}
          <button
            onClick={() => setOnlyOutliers(!onlyOutliers)}
            className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all ${
              onlyOutliers
                ? 'bg-rose-500/20 text-rose-300 border-rose-500/40 shadow-sm'
                : 'bg-slate-950 text-slate-400 border-slate-800 hover:text-white'
            }`}
          >
            <AlertTriangle className="w-3.5 h-3.5" />
            <span>Outliers Only (|z| ≥ 2.0)</span>
          </button>
        </div>

        {/* Empirical Bayes Pooled Rates vs Marcel Counting Totals Toggle */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-400 font-medium">Projection Engine:</span>
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            <button
              onClick={() => {
                setStatMode('pooled_rates');
                setSortBy('stat1_pooled');
                setSortOrder(activeGroup === 'Batter' ? 'desc' : 'asc');
              }}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                statMode === 'pooled_rates'
                  ? 'bg-emerald-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Empirical Bayes Rates
            </button>
            <button
              onClick={() => {
                setStatMode('marcel_totals');
                setSortBy('count1_val');
                setSortOrder('desc');
              }}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                statMode === 'marcel_totals'
                  ? 'bg-emerald-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Marcel Counting Totals
            </button>
          </div>
        </div>
      </div>

      {/* Player Projections Table */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left border-collapse">
            <thead>
              <tr className="border-b border-slate-800 bg-slate-950/90 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                <th className="py-3.5 px-4">Player</th>
                <th className="py-3.5 px-3 text-center">Spatial Map</th>
                <th className="py-3.5 px-3">Club / Role</th>
                <th
                  onClick={() => handleSort('proj_workload')}
                  className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>{activeGroup === 'Batter' ? 'Proj PA' : 'Proj IP'}</span>
                    <ArrowUpDown className="w-3 h-3 opacity-50" />
                  </div>
                </th>
                <th
                  onClick={() => handleSort('park_factor')}
                  className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>Park Factor</span>
                    <ArrowUpDown className="w-3 h-3 opacity-50" />
                  </div>
                </th>

                {statMode === 'pooled_rates' ? (
                  <>
                    <th
                      onClick={() => handleSort('stat1_raw')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Raw wOBA' : 'Raw xFIP'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('stat1_pooled')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white text-indigo-300"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Pooled wOBA' : 'Pooled xFIP'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-70" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('stat2_pooled')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Pooled ISO' : 'Marcel ERA'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('k_pct_pooled')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>K% / BB%</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('stat1_shrinkage')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Bayes Shrink</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                  </>
                ) : (
                  <>
                    <th
                      onClick={() => handleSort('count1_val')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white text-amber-300"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Proj HR' : 'Proj SO'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-70" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('count2_val')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>Proj BB</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('count3_val')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Proj SO' : 'Proj K/9'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th
                      onClick={() => handleSort('stat3_val')}
                      className="py-3.5 px-3 text-right cursor-pointer hover:text-white"
                    >
                      <div className="flex items-center justify-end gap-1">
                        <span>{activeGroup === 'Batter' ? 'Proj OBP' : 'Starter rGS'}</span>
                        <ArrowUpDown className="w-3 h-3 opacity-50" />
                      </div>
                    </th>
                    <th className="py-3.5 px-3 text-center">10th – 90th Quantile</th>
                  </>
                )}

                <th
                  onClick={() => handleSort('composite_zscore')}
                  className="py-3.5 px-4 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>Z-Score / Outlier</span>
                    <ArrowUpDown className="w-3 h-3 opacity-50" />
                  </div>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 text-sm">
              {filteredPlayers.slice(0, 150).map((p) => {
                const isExpanded = expandedPlayerId === p.player_id;
                return (
                  <React.Fragment key={p.player_id}>
                    <tr
                      onClick={() => setExpandedPlayerId(isExpanded ? null : p.player_id)}
                      className={`hover:bg-slate-800/40 transition-colors cursor-pointer ${
                        isExpanded ? 'bg-indigo-950/25 border-l-2 border-indigo-500' : ''
                      }`}
                    >
                      <td className="py-3 px-4">
                        <div className="font-bold text-white flex items-center gap-1.5">
                          <span>{p.player_name}</span>
                          {spatialMaps[p.player_id]?.is_statcast_tracked && (
                            <span
                              className="w-1.5 h-1.5 rounded-full bg-emerald-400 shrink-0"
                              title="Verified Statcast Tracked"
                            />
                          )}
                        </div>
                        <div className="text-[11px] text-slate-400 font-mono">
                          Age {p.age} • Obs {p.observed_workload}{' '}
                          {p.player_type === 'Batter' ? 'PA' : 'IP'}
                        </div>
                      </td>
                      <td className="py-3 px-3 text-center">
                        <button
                          type="button"
                          onClick={(e) => {
                            e.stopPropagation();
                            setExpandedPlayerId(isExpanded ? null : p.player_id);
                          }}
                          className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-mono font-medium transition-all ${
                            isExpanded
                              ? 'bg-indigo-600 text-white shadow-lg shadow-indigo-600/30 font-bold'
                              : 'bg-slate-800/80 hover:bg-slate-700 text-slate-300 hover:text-white border border-slate-700/60'
                          }`}
                          title={
                            isExpanded
                              ? 'Close map'
                              : p.player_type === 'Batter'
                              ? 'View Hit Spray Chart'
                              : 'View Strike Zone Pitches'
                          }
                        >
                          {p.player_type === 'Batter' ? (
                            <Compass className="w-3.5 h-3.5 text-emerald-400" />
                          ) : (
                            <Crosshair className="w-3.5 h-3.5 text-indigo-400" />
                          )}
                          <span>
                            {isExpanded
                              ? 'Close'
                              : p.player_type === 'Batter'
                              ? 'Spray'
                              : 'Zone'}
                          </span>
                          {isExpanded ? (
                            <ChevronUp className="w-3.5 h-3.5" />
                          ) : (
                            <ChevronDown className="w-3.5 h-3.5 opacity-60" />
                          )}
                        </button>
                      </td>
                      <td className="py-3 px-3">
                        <div className="flex items-center gap-2">
                          <TeamLogo team={p.team} size="xs" />
                          <span className="font-mono text-xs font-semibold text-slate-200">
                            {p.team}
                          </span>
                          <span
                            className={`text-[10px] font-mono px-1.5 py-0.2 rounded ${
                              p.position === 'B'
                                ? 'bg-indigo-500/15 text-indigo-300'
                                : p.position === 'SP'
                                ? 'bg-emerald-500/15 text-emerald-300'
                                : 'bg-amber-500/15 text-amber-300'
                            }`}
                          >
                            {p.position}
                          </span>
                        </div>
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-slate-200">
                        {p.proj_workload}
                      </td>
                      <td className="py-3 px-3 text-right font-mono text-xs text-slate-400">
                        {p.park_factor.toFixed(3)}
                      </td>

                      {statMode === 'pooled_rates' ? (
                        <>
                          <td className="py-3 px-3 text-right font-mono text-slate-400">
                            {p.player_type === 'Batter'
                              ? `.${Math.round(p.stat1_raw * 1000).toString().padStart(3, '0')}`
                              : p.stat1_raw.toFixed(2)}
                          </td>
                          <td className="py-3 px-3 text-right font-mono font-bold text-indigo-300 bg-indigo-950/20">
                            <div>
                              {p.player_type === 'Batter'
                                ? `.${Math.round(p.stat1_pooled * 1000).toString().padStart(3, '0')}`
                                : p.stat1_pooled.toFixed(2)}
                            </div>
                            <div className="text-[10px] text-slate-400 font-normal">
                              [{p.stat1_p10.toFixed(p.player_type === 'Batter' ? 3 : 2)}–
                              {p.stat1_p90.toFixed(p.player_type === 'Batter' ? 3 : 2)}]
                            </div>
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-slate-200">
                            {p.player_type === 'Batter'
                              ? `.${Math.round(p.stat2_pooled * 1000).toString().padStart(3, '0')}`
                              : p.stat2_pooled.toFixed(2)}
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-xs text-slate-300">
                            <span>{p.k_pct_pooled.toFixed(1)}%</span>
                            <span className="text-slate-500 mx-1">/</span>
                            <span>{p.bb_pct_pooled.toFixed(1)}%</span>
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-xs text-amber-400">
                            {p.stat1_shrinkage.toFixed(1)}%
                          </td>
                        </>
                      ) : (
                        <>
                          <td className="py-3 px-3 text-right font-mono font-bold text-amber-300 bg-amber-950/15">
                            {p.count1_val} {p.count1_label}
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-slate-200">
                            {p.count2_val}
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-slate-200">
                            {p.count3_val}
                          </td>
                          <td className="py-3 px-3 text-right font-mono text-sky-300 font-semibold">
                            {p.player_type === 'Batter'
                              ? `.${Math.round(p.stat3_val * 1000).toString().padStart(3, '0')}`
                              : p.stat3_val.toFixed(1)}
                          </td>
                          <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                            {p.count1_p10} – <strong className="text-white">{p.count1_p50}</strong> –{' '}
                            {p.count1_p90} {p.count1_label}
                          </td>
                        </>
                      )}

                      <td className="py-3 px-4 text-right font-mono">
                        <div className="flex items-center justify-end gap-2">
                          <span
                            className={`text-xs font-bold ${
                              p.composite_zscore >= 1.5
                                ? 'text-emerald-400'
                                : p.composite_zscore <= -1.5
                                ? 'text-rose-400'
                                : 'text-slate-300'
                            }`}
                          >
                            {p.composite_zscore > 0
                              ? `+${p.composite_zscore.toFixed(2)}σ`
                              : `${p.composite_zscore.toFixed(2)}σ`}
                          </span>
                          {p.is_outlier && (
                            <span className="px-1.5 py-0.5 text-[10px] rounded bg-rose-500/20 text-rose-300 border border-rose-500/30 font-bold">
                              OUTLIER
                            </span>
                          )}
                        </div>
                      </td>
                    </tr>

                    {/* Expandable Spatial Dropdown Row */}
                    {isExpanded && (
                      <tr key={`${p.player_id}-dropdown-map`} className="bg-slate-950/80">
                        <td colSpan={11} className="p-3 sm:p-5">
                          <PlayerSpatialDropdown
                            player={p}
                            spatialData={spatialMaps[p.player_id]}
                            onClose={() => setExpandedPlayerId(null)}
                          />
                        </td>
                      </tr>
                    )}
                  </React.Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
        {filteredPlayers.length > 150 && (
          <div className="p-3 bg-slate-950/80 border-t border-slate-800 text-center text-xs text-slate-400 font-mono">
            Showing top 150 of {filteredPlayers.length} matching {activeGroup.toLowerCase()}s — use search or club filter to narrow further.
          </div>
        )}
      </div>
    </div>
  );
};
