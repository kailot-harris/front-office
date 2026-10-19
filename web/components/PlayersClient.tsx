'use client';

import React, { useState, useMemo } from 'react';
import { PlayerProjection } from '@/lib/types';
import { Search, AlertTriangle, ArrowUpDown, Filter, Sparkles, UserCheck, Crosshair, ChevronUp } from 'lucide-react';
import { TeamLogo } from '@/components/TeamLogo';
import { InlinePlayerShotCard } from '@/components/InlinePlayerShotCard';

interface PlayersClientProps {
  players: PlayerProjection[];
}

export const PlayersClient: React.FC<PlayersClientProps> = ({ players }) => {
  const [searchTerm, setSearchTerm] = useState('');
  const [selectedTeam, setSelectedTeam] = useState<string>('All');
  const [selectedPosition, setSelectedPosition] = useState<string>('All');
  const [onlyOutliers, setOnlyOutliers] = useState<boolean>(false);
  const [statMode, setStatMode] = useState<'per_game' | 'totals'>('per_game');
  const [sortBy, setSortBy] = useState<keyof PlayerProjection>('proj_pts');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [expandedPlayerId, setExpandedPlayerId] = useState<string | null>(null);

  const teams = useMemo(() => {
    const set = new Set(players.map((p) => p.team));
    return Array.from(set).sort();
  }, [players]);

  const outlierCount = useMemo(() => {
    return players.filter((p) => p.is_outlier).length;
  }, [players]);

  const filteredPlayers = useMemo(() => {
    return players
      .filter((p) => {
        if (onlyOutliers && !p.is_outlier) return false;
        if (selectedTeam !== 'All' && p.team !== selectedTeam) return false;
        if (selectedPosition !== 'All' && p.position !== selectedPosition) return false;
        if (searchTerm.trim() !== '') {
          const term = searchTerm.toLowerCase();
          const matchName = p.player_name.toLowerCase().includes(term);
          const matchTeam = p.team.toLowerCase().includes(term);
          if (!matchName && !matchTeam) return false;
        }
        return true;
      })
      .sort((a, b) => {
        const valA = a[sortBy] as number;
        const valB = b[sortBy] as number;
        return sortOrder === 'desc' ? valB - valA : valA - valB;
      });
  }, [players, onlyOutliers, selectedTeam, selectedPosition, searchTerm, sortBy, sortOrder]);

  const handleSort = (field: keyof PlayerProjection) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      setSortOrder('desc');
    }
  };

  return (
    <div className="space-y-6">
      {/* Overview Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-amber-500/10 text-amber-400 rounded-lg">
            <UserCheck className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Active Rotation Pool</div>
            <div className="text-2xl font-bold text-white">330 Players</div>
            <div className="text-xs text-slate-400">11 Rotation Players × 30 Teams</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-rose-500/10 text-rose-400 rounded-lg">
            <AlertTriangle className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Statistical Outliers (|z| &gt; 2.0)</div>
            <div className="text-2xl font-bold text-rose-400">{outlierCount} Players</div>
            <div className="text-xs text-slate-400">Extreme 95th-percentile tails</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 text-indigo-400 rounded-lg">
            <Sparkles className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Scoring Leader Projection</div>
            <div className="text-lg font-bold text-white">Luka Doncic (33.1 PPG)</div>
            <div className="text-xs text-slate-400">2,263 Proj Total Pts • 35.4 MPG</div>
          </div>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-4 flex items-center gap-4">
          <div className="p-3 bg-emerald-500/10 text-emerald-400 rounded-lg">
            <Filter className="w-6 h-6" />
          </div>
          <div>
            <div className="text-xs text-slate-400 uppercase font-semibold">Filter Matches</div>
            <div className="text-2xl font-bold text-emerald-400">{filteredPlayers.length} Players</div>
            <div className="text-xs text-slate-400">Matching active criteria</div>
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
              placeholder="Search player name or team..."
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
            <option value="All">All Teams</option>
            {teams.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>

          {/* Position filter */}
          <select
            value={selectedPosition}
            onChange={(e) => setSelectedPosition(e.target.value)}
            className="bg-slate-950 border border-slate-800 text-xs text-slate-200 rounded-lg px-3 py-2 focus:outline-none focus:border-indigo-500"
          >
            <option value="All">All Positions</option>
            <option value="G">Guard (G)</option>
            <option value="F">Forward (F)</option>
            <option value="C">Center (C)</option>
          </select>

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
            <span>Outliers Only (|z| &gt; 2.0)</span>
          </button>
        </div>

        {/* Per-Game vs Totals Toggle */}
        <div className="flex items-center gap-2">
          <span className="text-xs text-slate-400 font-medium">Stat Mode:</span>
          <div className="inline-flex rounded-lg bg-slate-950 p-1 border border-slate-800">
            <button
              onClick={() => {
                setStatMode('per_game');
                if (sortBy === 'proj_pts_total') setSortBy('proj_pts');
                if (sortBy === 'proj_reb_total') setSortBy('proj_reb');
                if (sortBy === 'proj_ast_total') setSortBy('proj_ast');
              }}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                statMode === 'per_game'
                  ? 'bg-indigo-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Per Game
            </button>
            <button
              onClick={() => {
                setStatMode('totals');
                if (sortBy === 'proj_pts') setSortBy('proj_pts_total');
                if (sortBy === 'proj_reb') setSortBy('proj_reb_total');
                if (sortBy === 'proj_ast') setSortBy('proj_ast_total');
              }}
              className={`px-3 py-1 text-xs font-semibold rounded-md transition-all ${
                statMode === 'totals'
                  ? 'bg-indigo-600 text-white shadow-sm'
                  : 'text-slate-400 hover:text-white'
              }`}
            >
              Season Totals
            </button>
          </div>
        </div>
      </div>

      {/* Players Projections Table */}
      <div className="bg-slate-900/70 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm border-collapse">
            <thead>
              <tr className="bg-slate-950/80 border-b border-slate-800 text-slate-400 text-xs">
                <th className="py-3 px-4 w-12 text-center">Rank</th>
                <th className="py-3 px-4">Player</th>
                <th className="py-3 px-3 text-center">Team</th>
                <th className="py-3 px-3 text-center">Pos</th>
                <th
                  onClick={() => handleSort('proj_games')}
                  className="py-3 px-3 text-center cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span>Games</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  onClick={() => handleSort('proj_mpg')}
                  className="py-3 px-3 text-center cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span>MPG</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  onClick={() =>
                    handleSort(statMode === 'per_game' ? 'proj_pts' : 'proj_pts_total')
                  }
                  className="py-3 px-4 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>{statMode === 'per_game' ? 'PTS/G' : 'Total PTS'}</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  onClick={() =>
                    handleSort(statMode === 'per_game' ? 'proj_reb' : 'proj_reb_total')
                  }
                  className="py-3 px-4 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>{statMode === 'per_game' ? 'REB/G' : 'Total REB'}</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  onClick={() =>
                    handleSort(statMode === 'per_game' ? 'proj_ast' : 'proj_ast_total')
                  }
                  className="py-3 px-4 text-right cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-end gap-1">
                    <span>{statMode === 'per_game' ? 'AST/G' : 'Total AST'}</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th
                  onClick={() => handleSort('pra_zscore')}
                  className="py-3 px-3 text-center cursor-pointer hover:text-white"
                >
                  <div className="flex items-center justify-center gap-1">
                    <span>PRA z-score</span>
                    <ArrowUpDown className="w-3 h-3" />
                  </div>
                </th>
                <th className="py-3 px-4 text-center">Status / Outlier</th>
                <th className="py-3 px-4 text-center">Shot Telemetry</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-sans">
              {filteredPlayers.flatMap((player, idx) => {
                const isOutlier = player.is_outlier;
                const isExpanded = expandedPlayerId === player.player_id;
                const ptsDisplay =
                  statMode === 'per_game' ? player.proj_pts.toFixed(1) : player.proj_pts_total.toFixed(0);
                const rebDisplay =
                  statMode === 'per_game' ? player.proj_reb.toFixed(1) : player.proj_reb_total.toFixed(0);
                const astDisplay =
                  statMode === 'per_game' ? player.proj_ast.toFixed(1) : player.proj_ast_total.toFixed(0);

                const playerRow = (
                  <tr
                    key={player.player_id}
                    className={`hover:bg-slate-800/40 transition-colors text-slate-200 ${
                      isExpanded
                        ? 'bg-indigo-950/30 border-l-4 border-indigo-500'
                        : isOutlier
                        ? 'bg-rose-950/10'
                        : ''
                    }`}
                  >
                    <td className="py-3 px-4 text-center text-xs font-mono text-slate-500">
                      {idx + 1}
                    </td>
                    <td
                      className="py-3 px-4 cursor-pointer group"
                      onClick={() =>
                        setExpandedPlayerId((prev) => (prev === player.player_id ? null : player.player_id))
                      }
                    >
                      <div className="font-semibold text-white group-hover:text-indigo-300 transition-colors flex items-center gap-2">
                        <span>{player.player_name}</span>
                        {isOutlier && (
                          <span
                            title="Statistical Outlier (|z| > 2.0)"
                            className="inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-bold bg-rose-500/20 text-rose-300 border border-rose-500/30"
                          >
                            OUTLIER
                          </span>
                        )}
                        <span className="text-[10px] text-slate-500 opacity-0 group-hover:opacity-100 transition-opacity">
                          (click to {isExpanded ? 'close' : 'view'} shots)
                        </span>
                      </div>
                      <div className="text-[11px] text-slate-400 font-mono">
                        p10-p90 PTS: {player.pts_p10.toFixed(1)} - {player.pts_p90.toFixed(1)}
                      </div>
                    </td>
                    <td className="py-3 px-3 text-center">
                      <div className="inline-flex items-center gap-1.5 px-2 py-0.5 rounded bg-slate-950/80 border border-slate-800">
                        <TeamLogo team={player.team} size="xs" />
                        <span className="font-mono font-bold text-xs text-amber-400">{player.team}</span>
                      </div>
                    </td>
                    <td className="py-3 px-3 text-center text-xs font-semibold text-slate-300">
                      {player.position}
                    </td>
                    <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                      {player.proj_games.toFixed(1)}
                    </td>
                    <td className="py-3 px-3 text-center font-mono text-xs text-slate-300">
                      {player.proj_mpg.toFixed(1)}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-bold text-white text-sm">
                      {ptsDisplay}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-medium text-slate-300 text-sm">
                      {rebDisplay}
                    </td>
                    <td className="py-3 px-4 text-right font-mono font-medium text-slate-300 text-sm">
                      {astDisplay}
                    </td>
                    <td className="py-3 px-3 text-center font-mono text-xs">
                      <span
                        className={`font-semibold ${
                          player.pra_zscore > 2.0
                            ? 'text-rose-400'
                            : player.pra_zscore > 1.0
                            ? 'text-amber-400'
                            : player.pra_zscore < -1.0
                            ? 'text-slate-500'
                            : 'text-slate-300'
                        }`}
                      >
                        {player.pra_zscore > 0 ? `+${player.pra_zscore.toFixed(2)}` : player.pra_zscore.toFixed(2)}
                      </span>
                    </td>
                    <td className="py-3 px-4 text-center">
                      {isOutlier ? (
                        <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-bold bg-rose-500/20 text-rose-300 border border-rose-500/30">
                          <AlertTriangle className="w-3 h-3" />
                          <span>|z| &gt; 2.0</span>
                        </span>
                      ) : (
                        <span className="text-xs text-slate-500">Normal</span>
                      )}
                    </td>
                    <td className="py-3 px-4 text-center">
                      <button
                        type="button"
                        onClick={(e) => {
                          e.preventDefault();
                          e.stopPropagation();
                          setExpandedPlayerId((prev) => (prev === player.player_id ? null : player.player_id));
                        }}
                        className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-lg text-xs font-semibold transition-all shadow-sm ${
                          isExpanded
                            ? 'bg-indigo-600 text-white shadow-indigo-600/30'
                            : 'bg-indigo-600/20 text-indigo-300 border border-indigo-500/30 hover:bg-indigo-600 hover:text-white'
                        }`}
                      >
                        {isExpanded ? (
                          <>
                            <ChevronUp className="w-3.5 h-3.5" />
                            <span>Close</span>
                          </>
                        ) : (
                          <>
                            <Crosshair className="w-3.5 h-3.5 text-indigo-400" />
                            <span>Hot Zones</span>
                          </>
                        )}
                      </button>
                    </td>
                  </tr>
                );

                if (!isExpanded) {
                  return [playerRow];
                }

                const expandedRow = (
                  <tr key={`${player.player_id}-expanded`} className="bg-slate-950/80 border-b border-indigo-500/40">
                    <td colSpan={12} className="p-3 sm:p-5">
                      <InlinePlayerShotCard
                        playerId={player.player_id}
                        playerName={player.player_name}
                        playerTeam={player.team}
                        onClose={() => setExpandedPlayerId(null)}
                      />
                    </td>
                  </tr>
                );

                return [playerRow, expandedRow];
              })}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
