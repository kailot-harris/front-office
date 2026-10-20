'use client';

import React from 'react';
import { LeverageBreakdown } from '@/lib/clutchTypes';

interface LeverageDistributionBarProps {
  breakdown: LeverageBreakdown;
  avgLeverageIndex: number;
}

export const LeverageDistributionBar: React.FC<LeverageDistributionBarProps> = ({
  breakdown,
  avgLeverageIndex,
}) => {
  return (
    <div className="p-4 bg-surface/70 rounded-2xl border border-slate-800 shadow-xl space-y-3">
      <div className="flex items-center justify-between border-b border-slate-800/80 pb-2">
        <div>
          <h4 className="text-xs font-bold text-white uppercase tracking-wider font-mono">
            Leverage State Distribution (Tango LI)
          </h4>
          <p className="text-[11px] text-slate-400">Share of Season Plate Appearances / Batters Faced</p>
        </div>
        <div className="text-right font-mono">
          <span className="text-[10px] text-slate-400 block">Avg Leverage</span>
          <span className="text-sm font-black text-rose-400">{avgLeverageIndex.toFixed(2)} LI</span>
        </div>
      </div>

      {/* Segmented Horizontal Bar */}
      <div className="w-full bg-surface-raised h-3 rounded-full overflow-hidden flex shadow-inner">
        <div
          className="bg-slate-700 h-full transition-all duration-500"
          style={{ width: `${breakdown.lowPct}%` }}
          title={`Low Leverage (<0.85): ${breakdown.lowPct}%`}
        />
        <div
          className="bg-sky-600 h-full transition-all duration-500"
          style={{ width: `${breakdown.medPct}%` }}
          title={`Medium Leverage (0.85-1.50): ${breakdown.medPct}%`}
        />
        <div
          className="bg-amber-500 h-full transition-all duration-500"
          style={{ width: `${breakdown.highPct}%` }}
          title={`High Leverage (1.50-2.50): ${breakdown.highPct}%`}
        />
        <div
          className="bg-rose-500 h-full transition-all duration-500"
          style={{ width: `${breakdown.extremePct}%` }}
          title={`Extreme Leverage (>=2.50): ${breakdown.extremePct}%`}
        />
      </div>

      {/* Legend Grid */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs font-mono pt-1">
        <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/60">
          <div className="flex items-center gap-1.5 text-slate-400 text-[10.5px]">
            <span className="w-2 h-2 rounded-full bg-slate-500" />
            <span>Low (&lt;0.85)</span>
          </div>
          <span className="text-sm font-bold text-white block mt-0.5">{breakdown.lowPct}%</span>
        </div>

        <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/60">
          <div className="flex items-center gap-1.5 text-sky-400 text-[10.5px]">
            <span className="w-2 h-2 rounded-full bg-sky-500" />
            <span>Med (0.85-1.5)</span>
          </div>
          <span className="text-sm font-bold text-white block mt-0.5">{breakdown.medPct}%</span>
        </div>

        <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/60">
          <div className="flex items-center gap-1.5 text-amber-400 text-[10.5px]">
            <span className="w-2 h-2 rounded-full bg-amber-500" />
            <span>High (1.5-2.5)</span>
          </div>
          <span className="text-sm font-bold text-white block mt-0.5">{breakdown.highPct}%</span>
        </div>

        <div className="bg-surface-raised/80 p-2 rounded-lg border border-slate-800/60">
          <div className="flex items-center gap-1.5 text-rose-400 text-[10.5px]">
            <span className="w-2 h-2 rounded-full bg-rose-500" />
            <span>Extreme (&ge;2.5)</span>
          </div>
          <span className="text-sm font-bold text-rose-300 block mt-0.5">{breakdown.extremePct}%</span>
        </div>
      </div>
    </div>
  );
};
