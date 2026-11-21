'use client';

import React from 'react';
import { PeerComp, MULTI_TEAM_LABEL, MULTI_TEAM_NOTE } from '@/lib/playerDnaTypes';
import { Sparkles } from 'lucide-react';

interface PeerCompCardProps {
  comp: PeerComp;
  rank: number;
}

export const PeerCompCard: React.FC<PeerCompCardProps> = ({ comp, rank }) => {
  const getBadgeColor = (pct: number) => {
    if (pct >= 90) return 'bg-emerald-950/80 text-emerald-400 border-emerald-800/80';
    if (pct >= 80) return 'bg-sky-950/80 text-sky-400 border-sky-800/80';
    if (pct >= 70) return 'bg-amber-950/80 text-amber-400 border-amber-800/80';
    return 'bg-surface-raised text-slate-400 border-slate-800';
  };

  return (
    <div data-testid="dna-peer-comp" className="flex items-center justify-between p-3.5 bg-surface-raised/60 rounded-xl border border-slate-800/80 hover:border-slate-700 transition-colors">
      <div className="flex items-center gap-3">
        <div className="flex items-center justify-center w-7 h-7 rounded-lg bg-slate-800 text-slate-300 font-bold text-xs font-mono">
          #{rank}
        </div>
        <div>
          <div className="flex items-center gap-2">
            <span className="font-bold text-sm text-white">{comp.compName}</span>
            {comp.position && (
              <span className="text-[11px] sm:text-[10px] uppercase font-mono tracking-wider px-1.5 py-0.5 rounded bg-slate-800 text-slate-300 font-medium">
                {comp.position}
              </span>
            )}
            <span
              className="text-[11px] sm:text-[10px] font-mono text-slate-400"
              data-testid="dna-team"
              title={comp.team ? undefined : MULTI_TEAM_NOTE}
            >
              {comp.team ?? MULTI_TEAM_LABEL}
            </span>
          </div>
          {comp.archetype && (
            <div className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
              <Sparkles className="w-3 h-3 text-sky-400" />
              <span className="font-semibold text-slate-300">{comp.archetype}</span>
            </div>
          )}
          <div className="text-[11px] text-slate-400 mt-0.5">
            {comp.keySharedTrait}
          </div>
        </div>
      </div>

      <div className="flex flex-col items-end gap-1.5 pl-3">
        <div className={`px-2.5 py-0.5 rounded-md text-xs font-bold font-mono border ${getBadgeColor(comp.similarityPct)}`}>
          {comp.similarityPct.toFixed(1)}% Match
        </div>
        <div className="w-24 bg-slate-800 rounded-full h-1.5 overflow-hidden">
          <div
            className="bg-sky-500 h-full rounded-full"
            style={{ width: `${Math.max(0, Math.min(100, comp.similarityPct))}%` }}
          />
        </div>
      </div>
    </div>
  );
};
