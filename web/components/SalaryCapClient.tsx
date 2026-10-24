'use client';

import { useState, useMemo } from 'react';
import { SalaryCapDataset, TeamCapProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import { Search, DollarSign, PieChart, Layers, Award, Download } from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';

interface SalaryCapClientProps {
  data: SalaryCapDataset;
}

export default function SalaryCapClient({ data }: SalaryCapClientProps) {
  const [activeTab, setActiveTab] = useState<'teams' | 'top_contracts'>('teams');
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTeam, setSelectedTeam] = useState<TeamCapProfile | null>(data.teams[0] || null);
  const [sortField, setSortField] = useState<keyof TeamCapProfile>('total_active_apy');
  const [sortAsc, setSortAsc] = useState(false);

  // Filtered Teams
  const filteredTeams = useMemo(() => {
    return data.teams
      .filter((t) => t.team.toLowerCase().includes(searchQuery.toLowerCase()))
      .sort((a, b) => {
        const aVal = a[sortField];
        const bVal = b[sortField];
        if (typeof aVal === 'number' && typeof bVal === 'number') {
          return sortAsc ? aVal - bVal : bVal - aVal;
        }
        return 0;
      });
  }, [data.teams, searchQuery, sortField, sortAsc]);

  // Filtered Top Contracts
  const filteredContracts = useMemo(() => {
    return data.top_league_contracts.filter(
      (c) =>
        c.player.toLowerCase().includes(searchQuery.toLowerCase()) ||
        c.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
        c.position.toLowerCase().includes(searchQuery.toLowerCase()) ||
        c.pos_group.toLowerCase().includes(searchQuery.toLowerCase())
    );
  }, [data.top_league_contracts, searchQuery]);

  // League Spending Summary
  const totalLeagueApy = useMemo(() => {
    return data.teams.reduce((acc, t) => acc + t.total_active_apy, 0);
  }, [data.teams]);

  const avgTeamApy = totalLeagueApy / (data.teams.length || 1);

  const handleExportTeamsCsv = () => {
    exportToCsv(
      filteredTeams as unknown as Record<string, unknown>[],
      [
        { key: 'team', label: 'Team' },
        { key: 'total_active_contracts', label: 'Active Contracts' },
        { key: 'total_active_apy', label: 'Active APY ($M)' },
        { key: 'total_guaranteed', label: 'Guaranteed ($M)' },
      ],
      'nfl-team-cap-profiles'
    );
  };

  const handleExportContractsCsv = () => {
    exportToCsv(
      filteredContracts as unknown as Record<string, unknown>[],
      [
        { key: 'player', label: 'Player' },
        { key: 'position', label: 'Position' },
        { key: 'team', label: 'Team' },
        { key: 'apy', label: 'APY ($M)' },
        { key: 'value', label: 'Total Value ($M)' },
        { key: 'guaranteed', label: 'Guaranteed ($M)' },
        { key: 'apy_cap_pct', label: 'Cap % at Signing' },
        { key: 'years', label: 'Years' },
        { key: 'year_signed', label: 'Signed' },
      ],
      'nfl-top-contracts'
    );
  };

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
            Salary Cap & Roster Valuation
          </span>
          <span className="text-xs font-mono text-slate-400">
            2026 NFL Cap Ceiling: ${data.cap_ceiling}M (OverTheCap)
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
          Positional Cap Allocation & Contract Valuation
        </h1>
        <p className="text-slate-400 text-sm mt-1 max-w-3xl">
          Comprehensive salary cap analytics across all 32 NFL franchises: active cash APY, positional spending distributions,
          dead money burdens, and league-wide top contract guarantees.
        </p>
      </div>

      {/* KPI Stats */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">NFL Cap Ceiling</span>
            <DollarSign className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-emerald-400">
            ${data.cap_ceiling}M
          </div>
          <p className="text-[11px] text-slate-400 mt-1">Official 2026 limit per franchise</p>
        </div>

        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Avg Active Roster APY</span>
            <PieChart className="w-4 h-4 text-cyan-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-cyan-400">
            ${avgTeamApy.toFixed(1)}M
          </div>
          <p className="text-[11px] text-slate-400 mt-1">Average annualized commitments</p>
        </div>

        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Top League Contract</span>
            <Award className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-indigo-400">
            ${data.top_league_contracts[0]?.apy || 60.0}M
          </div>
          <p className="text-[11px] text-slate-400 mt-1 truncate">
            {data.top_league_contracts[0]?.player || 'Dak Prescott'} ({data.top_league_contracts[0]?.team || 'DAL'})
          </p>
        </div>

        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Active OTC Contracts</span>
            <Layers className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-amber-400">
            {data.teams.reduce((acc, t) => acc + t.total_active_contracts, 0)}
          </div>
          <p className="text-[11px] text-slate-400 mt-1">Tracked across 32 active rosters</p>
        </div>
      </div>

      {/* View Switcher Ribbon & Search */}
      <div className="flex flex-col sm:flex-row gap-3 items-center justify-between bg-surface-raised/90 border border-slate-800 p-3.5 rounded-xl">
        <div className="flex items-center gap-2 w-full sm:w-auto">
          <button
            onClick={() => setActiveTab('teams')}
            className={`px-3.5 py-1.5 rounded-lg text-xs font-mono font-medium transition-all ${
              activeTab === 'teams'
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-md'
                : 'bg-surface text-slate-400 hover:text-white border border-slate-800'
            }`}
          >
            32 Team Cap Profiles
          </button>
          <button
            onClick={() => setActiveTab('top_contracts')}
            className={`px-3.5 py-1.5 rounded-lg text-xs font-mono font-medium transition-all ${
              activeTab === 'top_contracts'
                ? 'bg-emerald-500 text-slate-950 font-bold shadow-md'
                : 'bg-surface text-slate-400 hover:text-white border border-slate-800'
            }`}
          >
            Top 100 League Contracts
          </button>
        </div>

        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder={activeTab === 'teams' ? 'Search team code...' : 'Search player, team, position...'}
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500"
          />
        </div>
      </div>

      {/* View 1: 32 Team Cap Profiles Table & Breakdown */}
      {activeTab === 'teams' && (
        <div className="space-y-6">
          <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
            {/* Team Table */}
            <div className="lg:col-span-2 bg-surface-raised/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
              <div className="flex items-center justify-end px-4 py-2 border-b border-slate-800">
                <button
                  type="button"
                  onClick={handleExportTeamsCsv}
                  title="Export CSV"
                  aria-label="Export team cap profiles as CSV"
                  data-export-exclude
                  className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
                >
                  <Download className="w-3.5 h-3.5" />
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="w-full text-left text-xs font-mono">
                  <thead className="bg-surface/80 text-slate-400 uppercase text-[10px] tracking-wider border-b border-slate-800">
                    <tr>
                      <th className="px-4 py-3">Team</th>
                      <th
                        className="px-3 py-3 text-right cursor-pointer hover:text-white"
                        onClick={() => {
                          if (sortField === 'total_active_apy') setSortAsc(!sortAsc);
                          else {
                            setSortField('total_active_apy');
                            setSortAsc(false);
                          }
                        }}
                      >
                        Active APY ($M) {sortField === 'total_active_apy' && (sortAsc ? '↑' : '↓')}
                      </th>
                      <th
                        className="px-3 py-3 text-right cursor-pointer hover:text-white"
                        onClick={() => {
                          if (sortField === 'total_guaranteed') setSortAsc(!sortAsc);
                          else {
                            setSortField('total_guaranteed');
                            setSortAsc(false);
                          }
                        }}
                      >
                        Guaranteed ($M) {sortField === 'total_guaranteed' && (sortAsc ? '↑' : '↓')}
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-800/60">
                    {filteredTeams.map((t) => {
                      const isSelected = selectedTeam?.team === t.team;
                      return (
                        <tr
                          key={t.team}
                          onClick={() => setSelectedTeam(t)}
                          className={`hover:bg-slate-800/40 transition-colors cursor-pointer ${
                            isSelected ? 'bg-accent-950/20 border-l-2 border-accent-500' : ''
                          }`}
                        >
                          <td className="px-4 py-2.5">
                            <div className="flex items-center gap-2">
                              <TeamLogo team={t.team} size="xs" />
                              <span className="font-bold text-white">{t.team}</span>
                              <span className="text-[10px] text-slate-500 font-sans">
                                ({t.total_active_contracts} deals)
                              </span>
                            </div>
                          </td>
                          <td className="px-3 py-2.5 text-right font-bold text-white">
                            ${t.total_active_apy.toFixed(1)}M
                          </td>
                          <td className="px-3 py-2.5 text-right text-slate-300">
                            ${t.total_guaranteed.toFixed(1)}M
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>

            {/* Selected Team Positional Spending Sunburst/Bar Breakdown */}
            {selectedTeam && (
              <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl flex flex-col justify-between">
                <div>
                  <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
                    <div className="flex items-center gap-3">
                      <TeamLogo team={selectedTeam.team} size="md" />
                      <div>
                        <h2 className="text-base font-bold text-white">
                          {selectedTeam.team} Cap Allocation
                        </h2>
                        <p className="text-xs text-slate-400 font-mono">
                          Active Cash APY: ${selectedTeam.total_active_apy.toFixed(1)}M
                        </p>
                      </div>
                    </div>
                  </div>

                  {/* Positional Bars */}
                  <div className="space-y-3">
                    <span className="text-[10px] font-mono uppercase text-slate-500 font-bold block">
                      Spending by Position Group
                    </span>

                    {Object.entries(selectedTeam.positional_spending)
                      .sort((a, b) => b[1].apy - a[1].apy)
                      .map(([pos, item]) => (
                        <div key={pos} className="space-y-1">
                          <div className="flex justify-between items-center text-xs">
                            <span className="text-slate-300 font-medium">
                              {pos} <span className="text-[10px] text-slate-500 font-mono">({item.count})</span>
                            </span>
                            <span className="font-mono text-slate-300">
                              ${item.apy.toFixed(1)}M ({item.pct}%)
                            </span>
                          </div>
                          <div className="h-1.5 w-full bg-surface rounded-full overflow-hidden border border-slate-800">
                            <div
                              className="h-full bg-emerald-500 rounded-full"
                              style={{ width: `${Math.min(item.pct * 2.5, 100)}%` }}
                            />
                          </div>
                        </div>
                      ))}
                  </div>

                  {/* Top 3 Highest Paid on Team */}
                  <div className="mt-5 pt-4 border-t border-slate-800 space-y-2">
                    <span className="text-[10px] font-mono uppercase text-slate-500 font-bold block">
                      Top Paid Cornerstones
                    </span>
                    {selectedTeam.top_paid_players.map((p, i) => (
                      <div
                        key={i}
                        className="flex items-center justify-between p-2 rounded-lg bg-surface/60 border border-slate-800 text-xs font-mono"
                      >
                        <div className="flex items-center gap-2">
                          <span className="text-slate-500 font-bold">#{i + 1}</span>
                          <span className="text-white font-sans font-medium">{p.player}</span>
                          <span className="text-[10px] text-slate-400">({p.position})</span>
                        </div>
                        <span className="text-emerald-400 font-bold">${p.apy}M/yr</span>
                      </div>
                    ))}
                  </div>
                </div>

                <div className="pt-4 border-t border-slate-800 text-[11px] text-slate-500 font-mono">
                  Guaranteed Liabilities: ${selectedTeam.total_guaranteed.toFixed(1)}M
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {/* View 2: Top 100 League Contracts Table */}
      {activeTab === 'top_contracts' && (
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
          <div className="flex items-center justify-end px-4 py-2 border-b border-slate-800">
            <button
              type="button"
              onClick={handleExportContractsCsv}
              title="Export CSV"
              aria-label="Export top contracts as CSV"
              data-export-exclude
              className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
            >
              <Download className="w-3.5 h-3.5" />
            </button>
          </div>
          <div className="overflow-x-auto">
            <table className="w-full text-left text-xs font-mono">
              <thead className="bg-surface/80 text-slate-400 uppercase text-[10px] tracking-wider border-b border-slate-800">
                <tr>
                  <th className="px-4 py-3">Rank</th>
                  <th className="px-4 py-3">Player</th>
                  <th className="px-3 py-3">Pos</th>
                  <th className="px-3 py-3">Team</th>
                  <th className="px-3 py-3 text-right">APY ($M)</th>
                  <th className="px-3 py-3 text-right">Total Value</th>
                  <th className="px-3 py-3 text-right">Guaranteed ($M)</th>
                  <th className="px-3 py-3 text-right">Cap % at Signing</th>
                  <th className="px-3 py-3 text-center">Years</th>
                  <th className="px-4 py-3 text-center">Signed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60">
                {filteredContracts.map((c, idx) => (
                  <tr key={idx} className="hover:bg-slate-800/40 transition-colors">
                    <td className="px-4 py-2.5 text-slate-500 font-bold">#{idx + 1}</td>
                    <td className="px-4 py-2.5 font-sans font-bold text-white">{c.player}</td>
                    <td className="px-3 py-2.5 text-cyan-400">{c.position}</td>
                    <td className="px-3 py-2.5">
                      <div className="flex items-center gap-1.5">
                        <TeamLogo team={c.team} size="xs" />
                        <span className="text-slate-300 font-semibold">{c.team}</span>
                      </div>
                    </td>
                    <td className="px-3 py-2.5 text-right font-bold text-emerald-400">
                      ${c.apy.toFixed(2)}M
                    </td>
                    <td className="px-3 py-2.5 text-right text-slate-300">
                      ${c.value.toFixed(1)}M
                    </td>
                    <td className="px-3 py-2.5 text-right text-slate-300">
                      ${c.guaranteed.toFixed(1)}M
                    </td>
                    <td className="px-3 py-2.5 text-right font-bold text-indigo-400">
                      {c.apy_cap_pct}%
                    </td>
                    <td className="px-3 py-2.5 text-center text-slate-400">{c.years}y</td>
                    <td className="px-4 py-2.5 text-center text-slate-400">{c.year_signed}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}
    </div>
  );
}
