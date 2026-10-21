'use client';

import React, { useState, useMemo } from 'react';
import { Search, ArrowUpDown, TrendingUp, TrendingDown, DollarSign, Download } from 'lucide-react';
import { MlbPlayerContract } from '@/lib/cbtTypes';
import { exportToCsv } from '@/lib/exportToCsv';

interface FranchisePayrollTableProps {
  contracts: MlbPlayerContract[];
  teamName: string;
}

type SortField = 'salary2026' | 'salary2027' | 'salary2028' | 'projectedWar' | 'surplusValue' | 'playerName';

export const FranchisePayrollTable: React.FC<FranchisePayrollTableProps> = ({
  contracts,
  teamName,
}) => {
  const [search, setSearch] = useState('');
  const [contractTypeFilter, setContractTypeFilter] = useState<string>('ALL');
  const [sortField, setSortField] = useState<SortField>('salary2026');
  const [sortAsc, setSortAsc] = useState<boolean>(false);

  const contractTypes = ['ALL', 'Guaranteed', 'Arbitration', 'Pre-Arb', 'Player Option', 'Club Option'];

  const filteredContracts = useMemo(() => {
    return contracts
      .filter((c) => {
        const matchesSearch = c.playerName.toLowerCase().includes(search.toLowerCase()) ||
          c.position.toLowerCase().includes(search.toLowerCase());
        const matchesType = contractTypeFilter === 'ALL' || c.contractType === contractTypeFilter;
        return matchesSearch && matchesType;
      })
      .sort((a, b) => {
        const aVal = a[sortField];
        const bVal = b[sortField];
        if (typeof aVal === 'string' && typeof bVal === 'string') {
          return sortAsc ? aVal.localeCompare(bVal) : bVal.localeCompare(aVal);
        }
        return sortAsc ? (aVal as number) - (bVal as number) : (bVal as number) - (aVal as number);
      });
  }, [contracts, search, contractTypeFilter, sortField, sortAsc]);

  const handleExportCsv = () => {
    exportToCsv(
      filteredContracts as unknown as Record<string, unknown>[],
      [
        { key: 'playerName', label: 'Player' },
        { key: 'position', label: 'Position' },
        { key: 'contractType', label: 'Status' },
        { key: 'salary2026', label: '2026 Salary ($M)' },
        { key: 'salary2027', label: '2027 Salary ($M)' },
        { key: 'salary2028', label: '2028 Salary ($M)' },
        { key: 'projectedWar', label: 'Proj WAR' },
        { key: 'surplusValue', label: 'Surplus Value ($M)' },
      ],
      `${teamName || 'team'}-payroll`
    );
  };

  const toggleSort = (field: SortField) => {
    if (sortField === field) {
      setSortAsc(!sortAsc);
    } else {
      setSortField(field);
      setSortAsc(false);
    }
  };

  const getContractBadge = (type: MlbPlayerContract['contractType']) => {
    switch (type) {
      case 'Guaranteed':
        return 'bg-sky-500/10 text-sky-400 border-sky-500/20';
      case 'Arbitration':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/20';
      case 'Pre-Arb':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20';
      case 'Player Option':
        return 'bg-purple-500/10 text-purple-400 border-purple-500/20';
      case 'Club Option':
        return 'bg-indigo-500/10 text-indigo-400 border-indigo-500/20';
      default:
        return 'bg-slate-800 text-slate-300 border-slate-700';
    }
  };

  return (
    <div className="bg-surface-raised/90 border border-slate-800 rounded-xl overflow-hidden shadow-xl">
      {/* Table Header Controls */}
      <div className="p-4 border-b border-slate-800 flex flex-col md:flex-row md:items-center justify-between gap-3 bg-surface/40">
        <div>
          <h3 className="font-bold text-white text-base flex items-center gap-2">
            <span>{teamName} Contract Architecture</span>
            <span className="text-xs font-mono font-normal text-slate-400">({filteredContracts.length} items)</span>
          </h3>
          <p className="text-xs text-slate-400 mt-0.5">
            3-Year payroll commitments, projected WAR & contract surplus value ($8.5M/win)
          </p>
        </div>

        <div className="flex flex-wrap items-center gap-2.5">
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
          {/* Search Box */}
          <div className="relative">
            <Search className="w-3.5 h-3.5 text-slate-400 absolute left-2.5 top-1/2 -translate-y-1/2" />
            <input
              type="text"
              placeholder="Search player or pos..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="bg-surface border border-slate-800 rounded-lg pl-8 pr-3 py-1.5 text-xs text-slate-200 placeholder-slate-400 focus:outline-none focus:border-sky-500 w-44"
            />
          </div>

          {/* Filter Pills */}
          <div className="flex items-center gap-1 bg-surface p-1 rounded-lg border border-slate-800">
            {contractTypes.map((t) => (
              <button
                key={t}
                onClick={() => setContractTypeFilter(t)}
                className={`px-2 py-1 text-[11px] font-medium rounded transition-colors ${
                  contractTypeFilter === t
                    ? 'bg-accent-600 text-white shadow'
                    : 'text-slate-400 hover:text-slate-200 hover:bg-slate-850'
                }`}
              >
                {t}
              </button>
            ))}
          </div>
        </div>
      </div>

      {/* Roster Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-left text-xs">
          <thead>
            <tr className="bg-surface/80 border-b border-slate-800 text-[11px] font-semibold text-slate-400 uppercase tracking-wider">
              <th className="py-3 px-4">
                <button
                  onClick={() => toggleSort('playerName')}
                  className="flex items-center gap-1 hover:text-slate-200"
                >
                  Player / Commitment
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
              <th className="py-3 px-3">Position</th>
              <th className="py-3 px-3">Status</th>
              <th className="py-3 px-3 text-right">
                <button
                  onClick={() => toggleSort('salary2026')}
                  className="flex items-center gap-1 ml-auto hover:text-slate-200"
                >
                  2026 Salary
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
              <th className="py-3 px-3 text-right">
                <button
                  onClick={() => toggleSort('salary2027')}
                  className="flex items-center gap-1 ml-auto hover:text-slate-200"
                >
                  2027
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
              <th className="py-3 px-3 text-right">
                <button
                  onClick={() => toggleSort('salary2028')}
                  className="flex items-center gap-1 ml-auto hover:text-slate-200"
                >
                  2028
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
              <th className="py-3 px-3 text-right">
                <button
                  onClick={() => toggleSort('projectedWar')}
                  className="flex items-center gap-1 ml-auto hover:text-slate-200"
                >
                  Proj WAR
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
              <th className="py-3 px-4 text-right">
                <button
                  onClick={() => toggleSort('surplusValue')}
                  className="flex items-center gap-1 ml-auto hover:text-slate-200"
                >
                  Surplus ROI
                  <ArrowUpDown className="w-3 h-3" />
                </button>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/60 font-mono">
            {filteredContracts.map((c) => {
              const isSurplusPositive = c.surplusValue >= 0;
              return (
                <tr
                  key={c.playerId}
                  className="hover:bg-slate-800/30 transition-colors group"
                >
                  <td className="py-3 px-4 font-sans">
                    <div className="font-semibold text-white group-hover:text-sky-300 transition-colors">
                      {c.playerName}
                    </div>
                    {c.notes && (
                      <div className="text-[10px] text-slate-400 font-sans truncate max-w-xs">
                        {c.notes}
                      </div>
                    )}
                  </td>
                  <td className="py-3 px-3 font-sans">
                    <span className="px-1.5 py-0.5 rounded bg-slate-800 border border-slate-700 text-slate-300 font-mono text-[10.5px]">
                      {c.position}
                    </span>
                  </td>
                  <td className="py-3 px-3 font-sans">
                    <span className={`px-2 py-0.5 rounded text-[10.5px] border font-medium ${getContractBadge(c.contractType)}`}>
                      {c.contractType}
                    </span>
                  </td>
                  <td className="py-3 px-3 text-right font-bold text-slate-200">
                    ${c.salary2026.toFixed(1)}M
                  </td>
                  <td className="py-3 px-3 text-right text-slate-400">
                    {c.salary2027 > 0 ? `$${c.salary2027.toFixed(1)}M` : <span className="text-slate-400">FA</span>}
                  </td>
                  <td className="py-3 px-3 text-right text-slate-400">
                    {c.salary2028 > 0 ? `$${c.salary2028.toFixed(1)}M` : <span className="text-slate-400">FA</span>}
                  </td>
                  <td className="py-3 px-3 text-right text-sky-400 font-bold">
                    {c.projectedWar.toFixed(1)}
                  </td>
                  <td className="py-3 px-4 text-right">
                    <span
                      className={`inline-flex items-center gap-1 px-2 py-0.5 rounded border text-[11px] font-semibold ${
                        isSurplusPositive
                          ? 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20'
                          : 'bg-rose-500/10 text-rose-400 border-rose-500/20'
                      }`}
                    >
                      {isSurplusPositive ? (
                        <TrendingUp className="w-3 h-3 text-emerald-400" />
                      ) : (
                        <TrendingDown className="w-3 h-3 text-rose-400" />
                      )}
                      {isSurplusPositive ? '+' : ''}${c.surplusValue.toFixed(1)}M
                    </span>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Footer Summary Bar */}
      <div className="p-3 bg-surface/80 border-t border-slate-800 flex flex-wrap items-center justify-between text-xs text-slate-400 px-4">
        <div className="flex items-center gap-4">
          <span>Market Baseline: <strong className="text-slate-200 font-mono">$8.5M / WAR</strong></span>
          <span>Guaranteed Total: <strong className="text-white font-mono">${contracts.reduce((sum, c) => sum + c.salary2026, 0).toFixed(1)}M</strong></span>
        </div>
        <div className="flex items-center gap-1.5 text-sky-400 font-mono">
          <DollarSign className="w-3.5 h-3.5" />
          <span>Net Surplus: <strong>{contracts.reduce((sum, c) => sum + c.surplusValue, 0) >= 0 ? '+' : ''}${contracts.reduce((sum, c) => sum + c.surplusValue, 0).toFixed(1)}M</strong></span>
        </div>
      </div>
    </div>
  );
};
