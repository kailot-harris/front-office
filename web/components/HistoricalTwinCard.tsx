'use client';

import React from 'react';
import { HistoricalTwin } from '@/lib/playerDnaTypes';
import { Sparkles } from 'lucide-react';

interface HistoricalTwinCardProps {
  twin: HistoricalTwin;
  rank: number;
}

export const HistoricalTwinCard: React.FC<HistoricalTwinCardProps> = ({ twin, rank }) => {
  const getBadgeColor = (pct: number) => {
    if (pct >= 98) return 'bg-emerald-950/80 text-emerald-400 border-emerald-800';
    if (pct >= 96) return 'bg-indigo-950/80 text-indigo-400 border-indigo-800';
    if (pct >= 94) return 'bg-amber-950/80 text-amber-400 border-amber-800';
    return 'bg-surface-raised text-slate-400 border-slate-800';
  };

  return (
    <div className="flex items-center justify-between p-3.5 bg-surface-raised/60 rounded-xl border border-slate-800/80 hover:border-slate-700/80 transition-colors">
      <div className="flex items-center gap-3">
        <div className="flex items-center justify-center w-7 h-7 rounded-lg bg-slate-800 text-slate-300 font-bold text-xs">
          #{rank}
        </div>
        <div>
          <div className="flex items-center gap-2">
            <span className="font-semibold text-sm text-slate-100">{twin.compName}</span>
            <span className="text-[10px] uppercase tracking-wider px-1.5 py-0.5 rounded bg-slate-800 text-slate-400 font-medium">
              {twin.position}
            </span>
          </div>
          <div className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
            <Sparkles className="w-3 h-3 text-indigo-400" />
            <span>{twin.archetype}</span>
          </div>
          <div className="text-[11px] text-slate-500 mt-0.5">
            {twin.keySharedTrait}
          </div>
        </div>
      </div>

      <div className="flex flex-col items-end gap-1">
        <div className={`px-2.5 py-1 rounded-md text-xs font-bold border ${getBadgeColor(twin.similarityPct)}`}>
          {twin.similarityPct.toFixed(1)}% Match
        </div>
        <div className="w-24 bg-slate-800 rounded-full h-1.5 overflow-hidden">
          <div
            className="bg-indigo-500 h-full rounded-full"
            style={{ width: `${Math.max(0, (twin.similarityPct - 90) * 10)}%` }}
          />
        </div>
      </div>
    </div>
  );
};
