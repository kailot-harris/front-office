'use client';

import React from 'react';
import { Download } from 'lucide-react';
import { FranchiseCbaProfile } from '@/lib/cbaTypes';
import { exportToCsv } from '@/lib/exportToCsv';

interface FranchiseCapTableProps {
  profile: FranchiseCbaProfile;
}

export const FranchiseCapTable: React.FC<FranchiseCapTableProps> = ({ profile }) => {
  const { contracts, totalPayroll2026, totalPayroll2027, totalPayroll2028, projectedCapSpace2027, projectedCapSpace2028 } = profile;

  const handleExportCsv = () => {
    exportToCsv(
      contracts as unknown as Record<string, unknown>[],
      [
        { key: 'playerName', label: 'Player' },
        { key: 'position', label: 'Pos' },
        { key: 'salary2026', label: '2026-27 ($M)' },
        { key: 'salary2027', label: '2027-28 ($M)' },
        { key: 'salary2028', label: '2028-29 ($M)' },
        { key: 'contractType', label: 'Status' },
      ],
      `${profile.teamAbbr || 'team'}-cap-book`
    );
  };

  return (
    <div className="bg-surface/70 border border-slate-800 rounded-xl overflow-hidden shadow-lg space-y-3 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2 pb-2 border-b border-slate-800">
        <div>
          <h4 className="text-xs font-bold text-white tracking-tight">
            3-Year Salary Cap Book & Option Sheet
          </h4>
          <span className="text-[10px] text-slate-400">
            Player salary commitments, player options (PO), and team options (TO). Sourced from official Spotrac & Basketball-Reference 2026-27 CBA filings.
          </span>
        </div>
        <div className="flex items-center gap-3 text-xs font-mono">
          <button
            type="button"
            onClick={handleExportCsv}
            title="Export CSV"
            aria-label="Export table as CSV"
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
          <div>
            <span className="text-slate-400 text-[10px] mr-1">2027 Room:</span>
            <span className={`font-bold ${projectedCapSpace2027 > 0 ? 'text-emerald-400' : 'text-slate-500'}`}>
              {projectedCapSpace2027 > 0 ? `+$${projectedCapSpace2027}M` : '$0.0M'}
            </span>
          </div>
          <div>
            <span className="text-slate-400 text-[10px] mr-1">2028 Room:</span>
            <span className={`font-bold ${projectedCapSpace2028 > 0 ? 'text-emerald-400' : 'text-slate-500'}`}>
              {projectedCapSpace2028 > 0 ? `+$${projectedCapSpace2028}M` : '$0.0M'}
            </span>
          </div>
        </div>
      </div>

      {/* Contract Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-left text-xs">
          <thead>
            <tr className="border-b border-slate-800 text-[10px] font-mono text-slate-400 uppercase tracking-wider">
              <th className="pb-2 font-semibold">Player</th>
              <th className="pb-2 font-semibold text-center">Pos</th>
              <th className="pb-2 font-semibold text-right">2026-27 ($M)</th>
              <th className="pb-2 font-semibold text-right">2027-28 ($M)</th>
              <th className="pb-2 font-semibold text-right">2028-29 ($M)</th>
              <th className="pb-2 font-semibold text-center">Status</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-850 font-mono">
            {contracts.map((c) => (
              <tr key={c.playerId} className="hover:bg-surface-raised/50 transition-colors">
                <td className="py-2 font-sans font-medium text-white truncate max-w-[140px]">
                  {c.playerName}
                </td>
                <td className="py-2 text-center text-[10px] text-slate-400">
                  {c.position}
                </td>
                <td className="py-2 text-right font-bold text-slate-200">
                  ${c.salary2026.toFixed(1)}M
                </td>
                <td className="py-2 text-right text-slate-300">
                  {c.salary2027 > 0 ? `$${c.salary2027.toFixed(1)}M` : <span className="text-slate-600">UFA</span>}
                </td>
                <td className="py-2 text-right text-slate-300">
                  {c.salary2028 > 0 ? `$${c.salary2028.toFixed(1)}M` : <span className="text-slate-600">UFA</span>}
                </td>
                <td className="py-2 text-center">
                  <span
                    className={`text-[9px] px-1.5 py-0.5 rounded font-sans font-semibold ${
                      c.contractType === 'Guaranteed'
                        ? 'bg-slate-800 text-slate-300 border border-slate-700'
                        : c.contractType === 'Player Option'
                        ? 'bg-amber-500/10 text-amber-400 border border-amber-500/20'
                        : 'bg-indigo-500/10 text-indigo-400 border border-indigo-500/20'
                    }`}
                  >
                    {c.contractType}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-slate-800 font-mono font-bold text-xs bg-surface-raised/80">
              <td className="py-2.5 font-sans text-white">Total Guaranteed Payroll</td>
              <td className="py-2.5 text-center text-slate-500">—</td>
              <td className="py-2.5 text-right text-amber-400">${totalPayroll2026.toFixed(1)}M</td>
              <td className="py-2.5 text-right text-slate-200">${totalPayroll2027.toFixed(1)}M</td>
              <td className="py-2.5 text-right text-slate-200">${totalPayroll2028.toFixed(1)}M</td>
              <td className="py-2.5 text-center text-slate-500">—</td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
};
