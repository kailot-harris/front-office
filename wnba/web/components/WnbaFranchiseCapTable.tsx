'use client';

import React from 'react';
import { WnbaFranchiseCbaProfile } from '@/lib/cbaTypes';
import { FileText } from 'lucide-react';

interface WnbaFranchiseCapTableProps {
  profile: WnbaFranchiseCbaProfile;
}

export const WnbaFranchiseCapTable: React.FC<WnbaFranchiseCapTableProps> = ({ profile }) => {
  const {
    contracts,
    totalPayroll2026,
    totalPayroll2027,
    totalPayroll2028,
    projectedCapSpace2027,
    projectedCapSpace2028,
  } = profile;

  const getContractBadge = (type: string) => {
    switch (type) {
      case 'Core Player':
        return 'bg-amber-500/10 text-amber-400 border-amber-500/30';
      case 'Veteran Max':
        return 'bg-purple-500/10 text-purple-400 border-purple-500/30';
      case 'Rookie Scale':
        return 'bg-sky-500/10 text-sky-400 border-sky-500/30';
      case 'Veteran Starter':
        return 'bg-emerald-500/10 text-emerald-400 border-emerald-500/30';
      case 'Team Option':
        return 'bg-indigo-500/10 text-indigo-400 border-indigo-500/30';
      default:
        return 'bg-slate-800 text-slate-400 border-slate-700';
    }
  };

  return (
    <div className="bg-slate-950/70 border border-slate-800 rounded-xl overflow-hidden shadow-lg space-y-3 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2 pb-2 border-b border-slate-800">
        <div>
          <h4 className="text-xs font-bold text-white tracking-tight flex items-center gap-1.5">
            <FileText className="w-3.5 h-3.5 text-indigo-400" />
            3-Year Salary Cap Book & Multi-Year Commitments
          </h4>
          <span className="text-[10px] text-slate-400">
            Player salary commitments, core designations, rookie wage ladders, and options.
          </span>
        </div>
        <div className="flex items-center gap-3 text-xs font-mono">
          <div>
            <span className="text-slate-400 text-[10px] mr-1">2027 Room:</span>
            <span className="font-bold text-emerald-400">
              ${(projectedCapSpace2027 * 1000).toFixed(0)}k
            </span>
          </div>
          <div>
            <span className="text-slate-400 text-[10px] mr-1">2028 Room:</span>
            <span className="font-bold text-emerald-400">
              ${(projectedCapSpace2028 * 1000).toFixed(0)}k
            </span>
          </div>
        </div>
      </div>

      {/* Contract Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-left text-xs border-collapse">
          <thead>
            <tr className="border-b border-slate-800 text-[10px] font-mono text-slate-400 uppercase tracking-wider bg-slate-900/40">
              <th className="py-2 px-2.5 font-semibold">Player</th>
              <th className="py-2 px-2.5 font-semibold text-center">Pos</th>
              <th className="py-2 px-2.5 font-semibold text-right">2026 Salary</th>
              <th className="py-2 px-2.5 font-semibold text-right">2027 Salary</th>
              <th className="py-2 px-2.5 font-semibold text-right">2028 Salary</th>
              <th className="py-2 px-2.5 font-semibold text-center">Contract Type</th>
              <th className="py-2 px-2.5 font-semibold">Notes</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-slate-800/60 font-mono">
            {contracts.map((c) => (
              <tr key={c.playerId} className="hover:bg-slate-900/50 transition-colors">
                <td className="py-2 px-2.5 font-sans font-medium text-white truncate max-w-[140px]">
                  {c.playerName}
                </td>
                <td className="py-2 px-2.5 text-center text-[10px] text-slate-400">
                  {c.position}
                </td>
                <td className="py-2 px-2.5 text-right font-bold text-slate-200">
                  ${(c.salary2026 * 1000).toFixed(0)}k
                </td>
                <td className="py-2 px-2.5 text-right text-slate-300">
                  {c.salary2027 > 0 ? (
                    `$${(c.salary2027 * 1000).toFixed(0)}k`
                  ) : (
                    <span className="text-slate-600">UFA</span>
                  )}
                </td>
                <td className="py-2 px-2.5 text-right text-slate-300">
                  {c.salary2028 > 0 ? (
                    `$${(c.salary2028 * 1000).toFixed(0)}k`
                  ) : (
                    <span className="text-slate-600">UFA</span>
                  )}
                </td>
                <td className="py-2 px-2.5 text-center">
                  <span
                    className={`text-[9px] px-2 py-0.5 rounded-full font-sans font-bold border ${getContractBadge(
                      c.contractType
                    )}`}
                  >
                    {c.contractType}
                  </span>
                </td>
                <td className="py-2 px-2.5 font-sans text-[11px] text-slate-400 truncate max-w-[170px]">
                  {c.notes}
                </td>
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="border-t-2 border-slate-800 bg-slate-900/70 font-mono font-bold text-xs text-white">
              <td className="py-2.5 px-2.5 font-sans">Total Guaranteed Commitments</td>
              <td className="py-2.5 px-2.5 text-center text-slate-400">{contracts.length}</td>
              <td className="py-2.5 px-2.5 text-right text-indigo-400">
                ${(totalPayroll2026 * 1000).toFixed(0)}k
              </td>
              <td className="py-2.5 px-2.5 text-right text-slate-300">
                ${(totalPayroll2027 * 1000).toFixed(0)}k
              </td>
              <td className="py-2.5 px-2.5 text-right text-slate-300">
                ${(totalPayroll2028 * 1000).toFixed(0)}k
              </td>
              <td colSpan={2} className="py-2.5 px-2.5 text-right text-[11px] text-slate-400 font-sans">
                Hard Cap Ceiling: $1,520,000
              </td>
            </tr>
          </tfoot>
        </table>
      </div>
    </div>
  );
};
