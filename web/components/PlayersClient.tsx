'use client';

import { useState, useMemo, useEffect } from 'react';
import { QbProfile } from '@/lib/types';
import { TeamLogo } from './TeamLogo';
import QbEfficiencyScatter from './QbEfficiencyScatter';
import { Search, Award, TrendingUp, Download } from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';

interface PlayersClientProps {
  initialQbs: QbProfile[];
}

export default function PlayersClient({ initialQbs }: PlayersClientProps) {
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedTeam, setSelectedTeam] = useState('ALL');
  const [sortField, setSortField] = useState<'off_epa_roll' | 'off_cpoe_roll' | 'years_exp'>('off_epa_roll');
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('desc');
  const [selectedQb, setSelectedQb] = useState<QbProfile | null>(null);
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState<number | 'ALL'>(25);

  useEffect(() => {
    setCurrentPage(1);
  }, [searchQuery, selectedTeam]);

  // Teams list for filter
  const teams = useMemo(() => {
    const set = new Set(initialQbs.map((q) => q.team).filter(Boolean));
    return Array.from(set).sort();
  }, [initialQbs]);

  // Filtering & Sorting
  const filteredQbs = useMemo(() => {
    return initialQbs
      .filter((qb) => {
        const matchesSearch =
          qb.player_name.toLowerCase().includes(searchQuery.toLowerCase()) ||
          qb.team.toLowerCase().includes(searchQuery.toLowerCase()) ||
          (qb.college && qb.college.toLowerCase().includes(searchQuery.toLowerCase()));

        const matchesTeam = selectedTeam === 'ALL' || qb.team === selectedTeam;
        return matchesSearch && matchesTeam;
      })
      .sort((a, b) => {
        const aVal = a[sortField] ?? 0;
        const bVal = b[sortField] ?? 0;
        return sortDirection === 'desc' ? (bVal as number) - (aVal as number) : (aVal as number) - (bVal as number);
      });
  }, [initialQbs, searchQuery, selectedTeam, sortField, sortDirection]);

  // Pagination calculation
  const totalPages = pageSize === 'ALL' ? 1 : Math.ceil(filteredQbs.length / pageSize);
  const paginatedQbs = useMemo(() => {
    if (pageSize === 'ALL') return filteredQbs;
    const start = (currentPage - 1) * pageSize;
    return filteredQbs.slice(start, start + pageSize);
  }, [filteredQbs, currentPage, pageSize]);

  // Leaders (qualified starters or QBs with >= 35 attempts)
  const topEpa = useMemo(() => {
    return [...initialQbs]
      .filter((q) => (q.is_starter || (q.attempts_2026 ?? 0) >= 35) && typeof q.off_epa_roll === 'number' && !isNaN(q.off_epa_roll))
      .sort((a, b) => b.off_epa_roll - a.off_epa_roll)
      .slice(0, 3);
  }, [initialQbs]);

  const topCpoe = useMemo(() => {
    return [...initialQbs]
      .filter((q) => (q.is_starter || (q.attempts_2026 ?? 0) >= 35) && typeof q.off_cpoe_roll === 'number' && !isNaN(q.off_cpoe_roll))
      .sort((a, b) => b.off_cpoe_roll - a.off_cpoe_roll)
      .slice(0, 3);
  }, [initialQbs]);

  const handleExportCsv = () => {
    exportToCsv(
      filteredQbs as unknown as Record<string, unknown>[],
      [
        { key: 'player_name', label: 'Player' },
        { key: 'team', label: 'Team' },
        { key: 'depth_position', label: 'Position' },
        { key: 'jersey_number', label: 'Jersey #' },
        { key: 'years_exp', label: 'Experience (Years)' },
        { key: 'college', label: 'College' },
        { key: 'off_epa_roll', label: 'EPA / Play' },
        { key: 'off_cpoe_roll', label: 'CPOE %' },
        { key: 'status', label: 'Status' },
      ],
      'nfl-quarterbacks'
    );
  };

  return (
    <div className="space-y-8">
      {/* Page Header */}
      <div className="relative pb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
              Player & QB Analytics
            </span>
            <span className="text-xs font-mono text-slate-400">
              {initialQbs.length} Active Quarterbacks Tracked
            </span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
            <span className="text-emerald-400">NFL</span> Quarterback Composite Ratings & Depth Chart
          </h1>
          <p className="text-slate-400 text-sm mt-1 max-w-3xl">
            Rolling per-dropback Expected Points Added (EPA) and Completion Percentage Over Expected (CPOE)
            derived from play-by-play tracking. Integrated with backup quarterback injury penalties and rookie usage ramps.
          </p>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      {/* Leadership KPI Banners */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {/* Top EPA Leaders */}
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <TrendingUp className="w-4 h-4 text-emerald-400" />
              <h2 className="text-sm font-semibold text-white">EPA / Play Leaders</h2>
            </div>
            <span className="text-[11px] font-mono text-slate-400">Efficiency</span>
          </div>
          <div className="space-y-2">
            {topEpa.map((qb, i) => (
              <div
                key={qb.player_name}
                onClick={() => setSelectedQb(qb)}
                className="flex items-center justify-between p-2 rounded-lg bg-surface/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4 text-center">
                    #{i + 1}
                  </span>
                  <TeamLogo team={qb.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white flex items-center gap-1.5">
                      {qb.player_name}
                      <span className="text-[10px] font-mono text-slate-400">({qb.team})</span>
                    </div>
                    <div className="text-[10px] text-slate-400 font-mono">
                      Exp: {qb.years_exp}y • {qb.college || 'N/A'}
                    </div>
                  </div>
                </div>
                <div className="text-right">
                  <span className="text-xs font-mono font-bold text-emerald-400">
                    +{qb.off_epa_roll.toFixed(3)}
                  </span>
                  <div className="text-[10px] font-mono text-slate-400">
                    CPOE: {qb.off_cpoe_roll > 0 ? '+' : ''}
                    {qb.off_cpoe_roll.toFixed(1)}%
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Top CPOE Leaders */}
        <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
            <div className="flex items-center gap-2">
              <Award className="w-4 h-4 text-cyan-400" />
              <h2 className="text-sm font-semibold text-white">CPOE Leaders</h2>
            </div>
            <span className="text-[11px] font-mono text-slate-400">Ball Placement</span>
          </div>
          <div className="space-y-2">
            {topCpoe.map((qb, i) => (
              <div
                key={qb.player_name}
                onClick={() => setSelectedQb(qb)}
                className="flex items-center justify-between p-2 rounded-lg bg-surface/50 hover:bg-slate-800/60 cursor-pointer border border-slate-800/60 transition-colors"
              >
                <div className="flex items-center gap-3">
                  <span className="text-xs font-mono font-bold text-slate-500 w-4 text-center">
                    #{i + 1}
                  </span>
                  <TeamLogo team={qb.team} size="sm" />
                  <div>
                    <div className="text-xs font-medium text-white flex items-center gap-1.5">
                      {qb.player_name}
                      <span className="text-[10px] font-mono text-slate-400">({qb.team})</span>
                    </div>
                    <div className="text-[10px] text-slate-400 font-mono">
                      Exp: {qb.years_exp}y • {qb.college || 'N/A'}
                    </div>
                  </div>
                </div>
                <div className="text-right">
                  <span className="text-xs font-mono font-bold text-cyan-400">
                    +{qb.off_cpoe_roll.toFixed(1)}%
                  </span>
                  <div className="text-[10px] font-mono text-slate-400">
                    EPA: {qb.off_epa_roll > 0 ? '+' : ''}
                    {qb.off_epa_roll.toFixed(3)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* 2D Interactive Scatter Chart */}
      <QbEfficiencyScatter
        qbs={initialQbs}
        selectedQb={selectedQb}
        onSelectQb={(qb) => setSelectedQb(qb)}
      />

      {/* Filter and Search Bar */}
      <div className="flex flex-col sm:flex-row gap-3 items-center justify-between bg-surface-raised/90 border border-slate-800 p-3.5 rounded-xl">
        <div className="relative w-full sm:w-80">
          <Search className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
          <input
            type="text"
            placeholder="Search quarterback, team, or college..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="w-full bg-surface border border-slate-800 rounded-lg pl-9 pr-3 py-1.5 text-xs text-white placeholder-slate-500 focus:outline-none focus:border-emerald-500"
          />
        </div>

        <div className="flex items-center gap-2 w-full sm:w-auto overflow-x-auto pb-1 sm:pb-0">
          <label className="text-xs font-mono text-slate-400 whitespace-nowrap">Filter Team:</label>
          <select
            aria-label="Filter by team"
            value={selectedTeam}
            onChange={(e) => setSelectedTeam(e.target.value)}
            className="bg-surface border border-slate-800 rounded-lg px-2.5 py-1.5 text-xs text-white focus:outline-none focus:border-emerald-500 font-mono"
          >
            <option value="ALL">All 32 Teams</option>
            {teams.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Quarterback Roster Table */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
        <div className="flex items-center justify-end px-4 py-2 border-b border-slate-800">
          <button
            type="button"
            onClick={handleExportCsv}
            title="Export CSV"
            aria-label="Export quarterback table as CSV"
            data-export-exclude
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead className="bg-surface/80 text-slate-400 font-mono uppercase text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="px-4 py-3">Player</th>
                <th className="px-3 py-3">Team</th>
                <th className="px-3 py-3">Pos / #</th>
                <th className="px-3 py-3">Experience</th>
                <th className="px-3 py-3">College</th>
                <th
                  className="px-3 py-3 text-right cursor-pointer hover:text-white"
                  onClick={() => {
                    if (sortField === 'off_epa_roll') {
                      setSortDirection(sortDirection === 'desc' ? 'asc' : 'desc');
                    } else {
                      setSortField('off_epa_roll');
                      setSortDirection('desc');
                    }
                  }}
                >
                  EPA / Play {sortField === 'off_epa_roll' && (sortDirection === 'desc' ? '↓' : '↑')}
                </th>
                <th
                  className="px-3 py-3 text-right cursor-pointer hover:text-white"
                  onClick={() => {
                    if (sortField === 'off_cpoe_roll') {
                      setSortDirection(sortDirection === 'desc' ? 'asc' : 'desc');
                    } else {
                      setSortField('off_cpoe_roll');
                      setSortDirection('desc');
                    }
                  }}
                >
                  CPOE % {sortField === 'off_cpoe_roll' && (sortDirection === 'desc' ? '↓' : '↑')}
                </th>
                <th className="px-4 py-3 text-center">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60 font-mono">
              {paginatedQbs.map((qb) => {
                const isSelected = selectedQb?.player_name === qb.player_name;
                const epa = qb.off_epa_roll ?? 0;
                const cpoe = qb.off_cpoe_roll ?? 0;

                return (
                  <tr
                    key={`${qb.player_name}-${qb.team}`}
                    onClick={() => setSelectedQb(qb)}
                    className={`hover:bg-slate-800/40 transition-colors cursor-pointer ${
                      isSelected ? 'bg-accent-950/20 border-l-2 border-accent-500' : ''
                    }`}
                  >
                    <td className="px-4 py-2.5">
                      <div className="flex items-center gap-2.5">
                        {qb.headshot_url ? (
                          <div className="w-7 h-7 rounded-full overflow-hidden bg-slate-800 flex-shrink-0 border border-slate-700">
                            {/* eslint-disable-next-line @next/next/no-img-element */}
                            <img
                              src={qb.headshot_url}
                              alt={qb.player_name}
                              loading="lazy"
                              decoding="async"
                              className="w-full h-full object-cover object-top"
                              onError={(e) => {
                                (e.target as HTMLElement).style.display = 'none';
                              }}
                            />
                          </div>
                        ) : (
                          <div className="w-7 h-7 rounded-full bg-slate-800 flex items-center justify-center text-slate-400 text-[10px] font-sans font-bold">
                            {qb.player_name.slice(0, 2)}
                          </div>
                        )}
                        <div className="flex items-center gap-1.5 flex-wrap">
                          <span className="font-sans font-medium text-white">{qb.player_name}</span>
                          {qb.is_starter ? (
                            <span className="px-1.5 py-0.2 rounded text-[9px] font-mono bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-bold">
                              Starter
                            </span>
                          ) : (
                            <span className="px-1.5 py-0.2 rounded text-[9px] font-mono bg-slate-800 text-slate-400 border border-slate-700/60 font-normal">
                              Backup
                            </span>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-3 py-2.5">
                      <div className="flex items-center gap-1.5">
                        <TeamLogo team={qb.team} size="xs" />
                        <span className="text-slate-300 font-semibold">{qb.team}</span>
                      </div>
                    </td>
                    <td className="px-3 py-2.5 text-slate-400">
                      {qb.depth_position || 'QB'} #{qb.jersey_number ?? '-'}
                    </td>
                    <td className="px-3 py-2.5 text-slate-400">
                      {qb.years_exp === 0 ? 'Rookie' : `${qb.years_exp} yrs`}
                    </td>
                    <td className="px-3 py-2.5 text-slate-400 font-sans truncate max-w-[140px]">
                      {qb.college || '—'}
                    </td>
                    <td className="px-3 py-2.5 text-right font-bold">
                      <span className={epa >= 0.05 ? 'text-emerald-400' : epa < 0 ? 'text-rose-400' : 'text-slate-300'}>
                        {epa > 0 ? '+' : ''}
                        {epa.toFixed(3)}
                      </span>
                    </td>
                    <td className="px-3 py-2.5 text-right font-bold">
                      <span className={cpoe >= 1.0 ? 'text-cyan-400' : cpoe < 0 ? 'text-amber-400' : 'text-slate-300'}>
                        {cpoe > 0 ? '+' : ''}
                        {cpoe.toFixed(1)}%
                      </span>
                    </td>
                    <td className="px-4 py-2.5 text-center">
                      <span className="inline-block px-2 py-0.5 rounded text-[10px] font-mono bg-emerald-950/60 border border-emerald-800 text-emerald-400">
                        {qb.status || 'ACT'}
                      </span>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>

        {/* Pagination Footer */}
        <div className="p-3 bg-surface/80 border-t border-slate-800 flex flex-col sm:flex-row items-center justify-between gap-3 text-xs font-mono text-slate-400">
          <div className="flex items-center gap-2">
            <span>Rows per page:</span>
            <select
              aria-label="Rows per page"
              value={pageSize}
              onChange={(e) => {
                const val = e.target.value === 'ALL' ? 'ALL' : Number(e.target.value);
                setPageSize(val);
                setCurrentPage(1);
              }}
              className="bg-surface-raised border border-slate-800 rounded px-2 py-1 text-white"
            >
              <option value={25}>25</option>
              <option value={50}>50</option>
              <option value="ALL">All ({filteredQbs.length})</option>
            </select>
            <span className="text-slate-500">
              Showing {pageSize === 'ALL' ? filteredQbs.length : Math.min(filteredQbs.length, (currentPage - 1) * pageSize + 1)}–
              {pageSize === 'ALL' ? filteredQbs.length : Math.min(filteredQbs.length, currentPage * pageSize)} of {filteredQbs.length} QBs
            </span>
          </div>

          {pageSize !== 'ALL' && totalPages > 1 && (
            <div className="flex items-center gap-1.5">
              <button
                onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                disabled={currentPage === 1}
                className="px-2.5 py-1 rounded bg-surface-raised border border-slate-800 text-slate-300 disabled:opacity-30 disabled:cursor-not-allowed hover:bg-slate-800"
              >
                Previous
              </button>
              <span className="px-2 text-slate-300 font-bold">
                Page {currentPage} of {totalPages}
              </span>
              <button
                onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage === totalPages}
                className="px-2.5 py-1 rounded bg-surface-raised border border-slate-800 text-slate-300 disabled:opacity-30 disabled:cursor-not-allowed hover:bg-slate-800"
              >
                Next
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Selected QB Detailed Drawer/Card */}
      {selectedQb && (
        <div className="bg-surface-raised/90 border border-emerald-500/50 rounded-xl p-5 shadow-2xl relative">
          <div className="flex flex-col sm:flex-row items-start sm:items-center justify-between pb-4 border-b border-slate-800 gap-4">
            <div className="flex items-center gap-4">
              {selectedQb.headshot_url ? (
                <div className="relative w-14 h-14 rounded-full overflow-hidden bg-slate-800 border-2 border-emerald-500/60">
                  {/* eslint-disable-next-line @next/next/no-img-element */}
                  <img
                    src={selectedQb.headshot_url}
                    alt={selectedQb.player_name}
                    className="w-full h-full object-cover object-top"
                    onError={(e) => {
                      (e.target as HTMLElement).style.display = 'none';
                    }}
                  />
                </div>
              ) : (
                <TeamLogo team={selectedQb.team} size="xl" />
              )}
              <div>
                <h2 className="text-lg font-bold text-white flex items-center gap-2">
                  {selectedQb.player_name}
                  <span className="text-xs font-mono font-normal text-slate-400">
                    #{selectedQb.jersey_number ?? '-'} • {selectedQb.team}
                  </span>
                </h2>
                <p className="text-xs text-slate-400">
                  {selectedQb.college} • {selectedQb.years_exp === 0 ? 'Rookie Season' : `${selectedQb.years_exp} Years Experience`}
                </p>
              </div>
            </div>

            <button
              onClick={() => setSelectedQb(null)}
              className="text-xs font-mono text-slate-400 hover:text-white px-2 py-1 rounded bg-slate-800"
            >
              Dismiss
            </button>
          </div>

          <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 pt-4">
            <div className="bg-surface/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Offensive EPA / Play</span>
              <span className="text-base font-mono font-bold text-emerald-400">
                {(selectedQb.off_epa_roll ?? 0) > 0 ? '+' : ''}
                {(selectedQb.off_epa_roll ?? 0).toFixed(3)}
              </span>
            </div>
            <div className="bg-surface/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Completion % Over Expected</span>
              <span className="text-base font-mono font-bold text-cyan-400">
                {(selectedQb.off_cpoe_roll ?? 0) > 0 ? '+' : ''}
                {(selectedQb.off_cpoe_roll ?? 0).toFixed(1)}%
              </span>
            </div>
            <div className="bg-surface/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Backup WAR Penalty</span>
              <span className="text-base font-mono font-bold text-amber-400">
                -3.2 Pts Spread
              </span>
            </div>
            <div className="bg-surface/60 p-3 rounded-lg border border-slate-800">
              <span className="text-[10px] font-mono uppercase text-slate-500 block">Roster Depth</span>
              <span className="text-base font-mono font-bold text-white">
                Starter (Tier {selectedQb.off_epa_roll > 0.08 ? '1' : selectedQb.off_epa_roll > 0 ? '2' : '3'})
              </span>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
