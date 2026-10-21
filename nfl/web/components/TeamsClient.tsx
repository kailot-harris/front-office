'use client';

import React, { useState, useMemo } from 'react';
import { TeamEpaProfile } from '@/lib/types';
import { EpaQuadrantScatter } from '@/components/EpaQuadrantScatter';
import { TeamLogo } from '@/components/TeamLogo';
import {
  ShieldCheck,
  Search,
  ArrowUpDown,
  ArrowUp,
  ArrowDown,
  X,
  Zap,
  Activity,
  Flame,
  Target,
  Download,
} from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';

interface TeamsClientProps {
  teams: TeamEpaProfile[];
}

export type EpaSortField =
  | 'team'
  | 'division'
  | 'net_epa_per_play'
  | 'off_epa_per_play'
  | 'def_epa_per_play'
  | 'off_success_rate'
  | 'def_success_rate'
  | 'off_cpoe'
  | 'off_money_down_epa'
  | 'off_redzone_success'
  | 'off_explosive_rate';

export const TeamsClient: React.FC<TeamsClientProps> = ({ teams }) => {
  const [selectedConf, setSelectedConf] = useState<'All' | 'AFC' | 'NFC'>('All');
  const [searchQuery, setSearchQuery] = useState<string>('');
  const [sortBy, setSortBy] = useState<EpaSortField>('net_epa_per_play');
  const [sortOrder, setSortOrder] = useState<'asc' | 'desc'>('desc');
  const [selectedTeam, setSelectedTeam] = useState<TeamEpaProfile | null>(null);

  const filteredTeams = useMemo(() => {
    return teams
      .filter((t) => {
        if (selectedConf !== 'All' && t.conference !== selectedConf) return false;
        if (searchQuery.trim().length > 0) {
          const q = searchQuery.toLowerCase();
          const matchName = t.team_name.toLowerCase().includes(q) || t.team.toLowerCase().includes(q);
          const matchDiv = t.division.toLowerCase().includes(q);
          if (!matchName && !matchDiv) return false;
        }
        return true;
      })
      .sort((a, b) => {
        let cmp = 0;
        if (sortBy === 'team') {
          cmp = a.team_name.localeCompare(b.team_name);
        } else if (sortBy === 'division') {
          cmp = a.division.localeCompare(b.division) || b.net_epa_per_play - a.net_epa_per_play;
        } else if (sortBy === 'def_epa_per_play') {
          // For defense, lower is better
          cmp = a.def_epa_per_play - b.def_epa_per_play;
        } else {
          const valA = (a[sortBy] as number) ?? 0;
          const valB = (b[sortBy] as number) ?? 0;
          cmp = valA - valB;
        }
        return sortOrder === 'desc' ? -cmp : cmp;
      });
  }, [teams, selectedConf, searchQuery, sortBy, sortOrder]);

  const handleSort = (field: EpaSortField) => {
    if (sortBy === field) {
      setSortOrder(sortOrder === 'asc' ? 'desc' : 'asc');
    } else {
      setSortBy(field);
      if (field === 'team' || field === 'division' || field === 'def_epa_per_play') {
        setSortOrder('asc');
      } else {
        setSortOrder('desc');
      }
    }
  };

  const renderSortIndicator = (field: EpaSortField) => {
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
  const topOffense = useMemo(() => [...teams].sort((a, b) => b.off_epa_per_play - a.off_epa_per_play)[0], [teams]);
  const topDefense = useMemo(() => [...teams].sort((a, b) => a.def_epa_per_play - b.def_epa_per_play)[0], [teams]);
  const topSuccessRate = useMemo(() => [...teams].sort((a, b) => b.off_success_rate - a.off_success_rate)[0], [teams]);
  const topExplosive = useMemo(() => [...teams].sort((a, b) => b.off_explosive_rate - a.off_explosive_rate)[0], [teams]);

  const handleExportCsv = () => {
    exportToCsv(
      filteredTeams as unknown as Record<string, unknown>[],
      [
        { key: 'team_name', label: 'Team' },
        { key: 'division', label: 'Division' },
        { key: 'net_epa_per_play', label: 'Net EPA/Play' },
        { key: 'off_epa_per_play', label: 'Off EPA/Play' },
        { key: 'def_epa_per_play', label: 'Def EPA Allowed' },
        { key: 'off_success_rate', label: 'Success %' },
        { key: 'off_cpoe', label: 'CPOE' },
        { key: 'off_money_down_epa', label: '3rd/4th Down EPA' },
        { key: 'off_redzone_success', label: 'Red Zone %' },
        { key: 'off_explosive_rate', label: 'Explosive %' },
      ],
      'nfl-team-epa-profiles'
    );
  };

  return (
    <div className="space-y-6">
      {/* Top EPA Leaders Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Top Offense */}
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topOffense?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-emerald-500/20 text-emerald-400 rounded-md border border-emerald-500/30 shadow">
              <Flame className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">#1 Offensive EPA</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topOffense?.team_name}</span>
              <span className="text-xs font-semibold text-emerald-400 flex-shrink-0 font-mono">
                +{topOffense?.off_epa_per_play.toFixed(3)}
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">Success: {topOffense?.off_success_rate.toFixed(1)}%</div>
          </div>
        </div>

        {/* Top Defense */}
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topDefense?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-cyan-500/20 text-cyan-400 rounded-md border border-cyan-500/30 shadow">
              <ShieldCheck className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">#1 Defensive EPA</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topDefense?.team_name}</span>
              <span className="text-xs font-semibold text-cyan-400 flex-shrink-0 font-mono">
                {topDefense?.def_epa_per_play.toFixed(3)}
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">Allowed: {topDefense?.def_success_rate.toFixed(1)}%</div>
          </div>
        </div>

        {/* Top Success Rate */}
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topSuccessRate?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-purple-500/20 text-purple-400 rounded-md border border-purple-500/30 shadow">
              <Target className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">#1 Success Rate</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topSuccessRate?.team_name}</span>
              <span className="text-xs font-semibold text-purple-400 flex-shrink-0 font-mono">
                {topSuccessRate?.off_success_rate.toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">CPOE: {topSuccessRate?.off_cpoe.toFixed(1)}</div>
          </div>
        </div>

        {/* Top Explosive Rate */}
        <div className="bg-surface-raised/70 border border-slate-800 rounded-xl p-4 flex items-center gap-3.5">
          <div className="relative flex-shrink-0">
            <div className="w-12 h-12 rounded-xl bg-surface/80 border border-slate-800 flex items-center justify-center p-1.5 shadow-inner">
              <TeamLogo team={topExplosive?.team} size="lg" />
            </div>
            <div className="absolute -bottom-1 -right-1 p-1 bg-amber-500/20 text-amber-400 rounded-md border border-amber-500/30 shadow">
              <Zap className="w-3.5 h-3.5" />
            </div>
          </div>
          <div className="min-w-0">
            <div className="text-[11px] text-slate-400 uppercase font-semibold font-mono">#1 Explosive Rate</div>
            <div className="text-base font-bold text-white flex items-baseline gap-2 truncate">
              <span className="truncate">{topExplosive?.team_name}</span>
              <span className="text-xs font-semibold text-amber-400 flex-shrink-0 font-mono">
                {topExplosive?.off_explosive_rate.toFixed(1)}%
              </span>
            </div>
            <div className="text-xs text-slate-400 font-mono">Redzone: {topExplosive?.off_redzone_success.toFixed(1)}%</div>
          </div>
        </div>
      </div>

      {/* Quadrant Scatter Component */}
      <EpaQuadrantScatter
        teams={teams}
        selectedTeam={selectedTeam?.team}
        onSelectTeam={(team) => setSelectedTeam(team)}
      />

      {/* Advanced EPA Table Toolbar */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-3.5 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <div className="flex items-center gap-2">
          <Activity className="w-4 h-4 text-emerald-400" />
          <span className="font-bold text-xs uppercase font-mono text-white">
            Granular EPA Profiles ({filteredTeams.length} Teams)
          </span>
        </div>

        <div className="flex items-center gap-2.5">
          <div className="relative">
            <Search className="w-3.5 h-3.5 absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-500" />
            <input
              type="text"
              placeholder="Search team..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              className="bg-surface border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500/50 w-40 sm:w-48"
            />
          </div>

          <div className="inline-flex rounded-lg bg-surface p-1 border border-slate-800">
            {(['All', 'AFC', 'NFC'] as const).map((conf) => (
              <button
                key={conf}
                onClick={() => setSelectedConf(conf)}
                className={`cursor-pointer select-none px-2.5 py-1 text-xs font-semibold rounded-md transition-all ${
                  selectedConf === conf
                    ? 'bg-accent-600 text-white shadow-sm'
                    : 'text-slate-400 hover:text-white'
                }`}
              >
                {conf}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Advanced EPA Table */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl overflow-hidden shadow-lg">
        <div className="flex items-center justify-end px-3 py-2 border-b border-slate-800">
          <button
            type="button"
            onClick={handleExportCsv}
            title="Export CSV"
            aria-label="Export EPA profiles table as CSV"
            data-export-exclude
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-surface/90 text-[11px] font-mono uppercase tracking-wider text-slate-400 border-b border-slate-800">
              <tr>
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
                  onClick={() => handleSort('net_epa_per_play')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Net EPA/Play</span>
                    {renderSortIndicator('net_epa_per_play')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_epa_per_play')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Off EPA</span>
                    {renderSortIndicator('off_epa_per_play')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('def_epa_per_play')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Def EPA Allowed</span>
                    {renderSortIndicator('def_epa_per_play')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_success_rate')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Success %</span>
                    {renderSortIndicator('off_success_rate')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_cpoe')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>CPOE</span>
                    {renderSortIndicator('off_cpoe')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_money_down_epa')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>3rd/4th Down EPA</span>
                    {renderSortIndicator('off_money_down_epa')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_redzone_success')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Red Zone %</span>
                    {renderSortIndicator('off_redzone_success')}
                  </div>
                </th>
                <th
                  onClick={() => handleSort('off_explosive_rate')}
                  className="cursor-pointer py-3.5 px-3 font-semibold hover:text-white text-right"
                >
                  <div className="flex items-center justify-end gap-1.5">
                    <span>Explosive %</span>
                    {renderSortIndicator('off_explosive_rate')}
                  </div>
                </th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-sans">
              {filteredTeams.map((t) => (
                <tr
                  key={t.team}
                  onClick={() => setSelectedTeam(t)}
                  className={`hover:bg-slate-800/40 transition-colors cursor-pointer group ${
                    selectedTeam?.team === t.team ? 'bg-accent-950/20' : ''
                  }`}
                >
                  <td className="py-2.5 px-3">
                    <div className="flex items-center gap-2.5">
                      <TeamLogo team={t.team} size="sm" />
                      <div>
                        <span className="font-bold text-white group-hover:text-emerald-400 transition-colors block">
                          {t.team_name}
                        </span>
                        <span className="text-[10px] font-mono text-slate-500">
                          {t.team}
                        </span>
                      </div>
                    </div>
                  </td>
                  <td className="py-2.5 px-3 font-mono text-slate-400">
                    {t.division}
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono font-bold">
                    <span className={t.net_epa_per_play > 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {t.net_epa_per_play > 0 ? `+${t.net_epa_per_play.toFixed(3)}` : t.net_epa_per_play.toFixed(3)}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono">
                    <span className={t.off_epa_per_play > 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {t.off_epa_per_play > 0 ? `+${t.off_epa_per_play.toFixed(3)}` : t.off_epa_per_play.toFixed(3)}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono">
                    <span className={t.def_epa_per_play < 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {t.def_epa_per_play > 0 ? `+${t.def_epa_per_play.toFixed(3)}` : t.def_epa_per_play.toFixed(3)}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono text-white">
                    {t.off_success_rate.toFixed(1)}%
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono font-bold">
                    <span className={t.off_cpoe > 0 ? 'text-emerald-400' : t.off_cpoe < 0 ? 'text-amber-400' : 'text-slate-400'}>
                      {t.off_cpoe > 0 ? `+${t.off_cpoe.toFixed(1)}` : t.off_cpoe.toFixed(1)}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono">
                    <span className={t.off_money_down_epa > 0 ? 'text-emerald-400' : 'text-red-400'}>
                      {t.off_money_down_epa > 0 ? `+${t.off_money_down_epa.toFixed(3)}` : t.off_money_down_epa.toFixed(3)}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono text-slate-300">
                    {t.off_redzone_success.toFixed(1)}%
                  </td>
                  <td className="py-2.5 px-3 text-right font-mono text-amber-400 font-semibold">
                    {t.off_explosive_rate.toFixed(1)}%
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {/* Team Deep-Dive Modal */}
      {selectedTeam && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/70 backdrop-blur-sm animate-in fade-in duration-200">
          <div
            className="bg-surface-raised border border-slate-700/80 rounded-2xl w-full max-w-2xl overflow-hidden shadow-2xl space-y-4"
            onClick={(e) => e.stopPropagation()}
          >
            {/* Modal Header */}
            <div className="p-4 bg-surface border-b border-slate-800 flex items-center justify-between">
              <div className="flex items-center gap-3">
                <TeamLogo team={selectedTeam.team} size="lg" />
                <div>
                  <h2 className="text-lg font-bold text-white flex items-center gap-2">
                    <span>{selectedTeam.team_name}</span>
                    <span className="text-xs font-mono px-2 py-0.5 rounded bg-slate-800 text-slate-400 border border-slate-700">
                      {selectedTeam.team}
                    </span>
                  </h2>
                  <p className="text-xs text-slate-400 font-mono">
                    {selectedTeam.conference} • {selectedTeam.division} • {selectedTeam.games_in_sample} Games Evaluated
                  </p>
                </div>
              </div>
              <button
                onClick={() => setSelectedTeam(null)}
                className="p-1.5 rounded-lg bg-slate-800 text-slate-400 hover:text-white hover:bg-slate-700 transition-colors"
              >
                <X className="w-5 h-5" />
              </button>
            </div>

            {/* Modal Content */}
            <div className="p-5 space-y-4">
              {/* Primary Metric Chips */}
              <div className="grid grid-cols-3 gap-3 font-mono text-center">
                <div className="bg-surface/70 p-3 rounded-xl border border-slate-800">
                  <span className="text-[10px] text-slate-500 uppercase block">Net EPA/Play</span>
                  <span
                    className={`text-lg font-black ${
                      selectedTeam.net_epa_per_play > 0 ? 'text-emerald-400' : 'text-red-400'
                    }`}
                  >
                    {selectedTeam.net_epa_per_play > 0
                      ? `+${selectedTeam.net_epa_per_play.toFixed(3)}`
                      : selectedTeam.net_epa_per_play.toFixed(3)}
                  </span>
                </div>
                <div className="bg-surface/70 p-3 rounded-xl border border-slate-800">
                  <span className="text-[10px] text-slate-500 uppercase block">Offense Success</span>
                  <span className="text-lg font-black text-white">
                    {selectedTeam.off_success_rate.toFixed(1)}%
                  </span>
                </div>
                <div className="bg-surface/70 p-3 rounded-xl border border-slate-800">
                  <span className="text-[10px] text-slate-500 uppercase block">Passing CPOE</span>
                  <span
                    className={`text-lg font-black ${
                      selectedTeam.off_cpoe > 0 ? 'text-emerald-400' : 'text-amber-400'
                    }`}
                  >
                    {selectedTeam.off_cpoe > 0
                      ? `+${selectedTeam.off_cpoe.toFixed(1)}`
                      : selectedTeam.off_cpoe.toFixed(1)}
                  </span>
                </div>
              </div>

              {/* Situational Splits Breakdown */}
              <div className="space-y-2">
                <h3 className="text-xs font-bold text-slate-300 uppercase tracking-wider font-mono">
                  Situational Splits & Down Efficiency
                </h3>
                <div className="grid grid-cols-2 gap-3 text-xs font-mono">
                  <div className="bg-surface/50 p-3 rounded-lg border border-slate-800/80 space-y-2">
                    <span className="font-bold text-slate-300 block border-b border-slate-800 pb-1">
                      Offensive Leverage
                    </span>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Early Down EPA (1st/2nd):</span>
                      <strong className={selectedTeam.off_early_down_epa > 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {selectedTeam.off_early_down_epa > 0 ? `+${selectedTeam.off_early_down_epa.toFixed(3)}` : selectedTeam.off_early_down_epa.toFixed(3)}
                      </strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Money Down EPA (3rd/4th):</span>
                      <strong className={selectedTeam.off_money_down_epa > 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {selectedTeam.off_money_down_epa > 0 ? `+${selectedTeam.off_money_down_epa.toFixed(3)}` : selectedTeam.off_money_down_epa.toFixed(3)}
                      </strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Red Zone Success Rate:</span>
                      <strong className="text-white">{selectedTeam.off_redzone_success.toFixed(1)}%</strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Explosive Play Rate:</span>
                      <strong className="text-amber-400">{selectedTeam.off_explosive_rate.toFixed(1)}%</strong>
                    </div>
                  </div>

                  <div className="bg-surface/50 p-3 rounded-lg border border-slate-800/80 space-y-2">
                    <span className="font-bold text-slate-300 block border-b border-slate-800 pb-1">
                      Defensive Resistance
                    </span>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Early Down Allowed:</span>
                      <strong className={selectedTeam.def_early_down_epa < 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {selectedTeam.def_early_down_epa > 0 ? `+${selectedTeam.def_early_down_epa.toFixed(3)}` : selectedTeam.def_early_down_epa.toFixed(3)}
                      </strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Money Down Allowed:</span>
                      <strong className={selectedTeam.def_money_down_epa < 0 ? 'text-emerald-400' : 'text-red-400'}>
                        {selectedTeam.def_money_down_epa > 0 ? `+${selectedTeam.def_money_down_epa.toFixed(3)}` : selectedTeam.def_money_down_epa.toFixed(3)}
                      </strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Red Zone Stop Rate:</span>
                      <strong className="text-white">{(100 - selectedTeam.def_redzone_success).toFixed(1)}%</strong>
                    </div>
                    <div className="flex justify-between">
                      <span className="text-slate-400">Explosive Allowed:</span>
                      <strong className="text-slate-300">{selectedTeam.def_explosive_rate.toFixed(1)}%</strong>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            {/* Modal Footer */}
            <div className="p-3 bg-surface border-t border-slate-800 text-right">
              <button
                onClick={() => setSelectedTeam(null)}
                className="px-4 py-1.5 rounded-lg bg-emerald-600 hover:bg-emerald-500 text-white text-xs font-semibold font-mono transition-colors"
              >
                Close Profile
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
