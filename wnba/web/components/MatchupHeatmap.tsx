'use client';

import React from 'react';
import { MatchupDist } from '@/lib/defenseTypes';

interface MatchupHeatmapProps {
  dist: MatchupDist;
  playerName: string;
}

export const MatchupHeatmap: React.FC<MatchupHeatmapProps> = ({ dist }) => {
  const positions = [
    { label: 'PG', val: dist.pgPct, name: 'Point Guards' },
    { label: 'SG', val: dist.sgPct, name: 'Shooting Guards' },
    { label: 'SF', val: dist.sfPct, name: 'Small Forwards' },
    { label: 'PF', val: dist.pfPct, name: 'Power Forwards' },
    { label: 'C', val: dist.cPct, name: 'Centers' },
  ];

  const getHeatBg = (pct: number) => {
    if (pct >= 35) return 'bg-indigo-600 text-white font-bold border-indigo-400';
    if (pct >= 25) return 'bg-indigo-700/80 text-indigo-100 font-semibold border-indigo-500';
    if (pct >= 15) return 'bg-indigo-950/80 text-indigo-300 border-indigo-800';
    if (pct >= 8) return 'bg-slate-800/80 text-slate-300 border-slate-700';
    return 'bg-slate-900/60 text-slate-500 border-slate-800';
  };

  return (
    <div className="p-4 bg-slate-950/60 rounded-xl border border-slate-800/80 space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider">
          Defensive Matchup Distribution (Tracking Shares)
        </h4>
        <span className="text-[10px] text-slate-500 font-mono">100% Normalized</span>
      </div>

      <div className="grid grid-cols-5 gap-2">
        {positions.map((pos) => (
          <div
            key={pos.label}
            className={`flex flex-col items-center justify-center p-2.5 rounded-lg border transition-all ${getHeatBg(
              pos.val
            )}`}
          >
            <div className="text-xs font-bold uppercase">{pos.label}</div>
            <div className="text-sm font-extrabold mt-0.5">{pos.val.toFixed(1)}%</div>
            <div className="text-[9px] opacity-75 mt-0.5 truncate max-w-full text-center">
              {pos.name}
            </div>
          </div>
        ))}
      </div>

      {/* Visual Stacked Bar */}
      <div className="w-full h-3 rounded-full overflow-hidden flex bg-slate-900 border border-slate-800 mt-2">
        <div style={{ width: `${dist.pgPct}%` }} className="bg-indigo-400 h-full" title={`PG: ${dist.pgPct}%`} />
        <div style={{ width: `${dist.sgPct}%` }} className="bg-violet-400 h-full" title={`SG: ${dist.sgPct}%`} />
        <div style={{ width: `${dist.sfPct}%` }} className="bg-amber-400 h-full" title={`SF: ${dist.sfPct}%`} />
        <div style={{ width: `${dist.pfPct}%` }} className="bg-orange-400 h-full" title={`PF: ${dist.pfPct}%`} />
        <div style={{ width: `${dist.cPct}%` }} className="bg-rose-500 h-full" title={`C: ${dist.cPct}%`} />
      </div>
    </div>
  );
};
