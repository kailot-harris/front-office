'use client';

import React from 'react';
import { ClutchShotBreakdown } from '@/lib/clutchTypes';
import { Target } from 'lucide-react';

interface ClutchShotBreakdownCardProps {
  breakdown: ClutchShotBreakdown;
}

export const ClutchShotBreakdownCard: React.FC<ClutchShotBreakdownCardProps> = ({
  breakdown,
}) => {
  const zones = [
    {
      name: 'Rim (< 5ft)',
      fga: breakdown.rim.fga,
      fgm: breakdown.rim.fgm,
      pct: breakdown.rim.pct,
      color: 'bg-emerald-500',
      badge: 'bg-emerald-950/80 text-emerald-400 border-emerald-800',
    },
    {
      name: 'Mid-Range (10-22ft)',
      fga: breakdown.mid.fga,
      fgm: breakdown.mid.fgm,
      pct: breakdown.mid.pct,
      color: 'bg-amber-500',
      badge: 'bg-amber-950/80 text-amber-400 border-amber-800',
    },
    {
      name: 'Above-the-Break & Corner 3PT',
      fga: breakdown.three.fga,
      fgm: breakdown.three.fgm,
      pct: breakdown.three.pct,
      color: 'bg-indigo-500',
      badge: 'bg-indigo-950/80 text-indigo-400 border-indigo-800',
    },
  ];

  return (
    <div className="p-4 bg-surface/60 rounded-xl border border-slate-800/80 space-y-3">
      <div className="flex items-center justify-between">
        <h4 className="text-xs font-semibold text-slate-300 uppercase tracking-wider flex items-center gap-1.5">
          <Target className="w-3.5 h-3.5 text-rose-400" />
          Clutch Shot Generation Breakdown (High-Leverage &le; 5 pts)
        </h4>
        <span className="text-[10px] text-slate-500 font-mono">
          N = {breakdown.totalClutchFga} FGA (Season)
        </span>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
        {zones.map((z) => (
          <div key={z.name} className="p-3 rounded-lg bg-surface-raised/60 border border-slate-800/90 space-y-1.5">
            <div className="text-[11px] text-slate-400 font-medium truncate">{z.name}</div>
            <div className="flex items-baseline justify-between">
              <span className="text-xl font-extrabold text-slate-100">{z.pct.toFixed(1)}%</span>
              <span className={`text-[11px] font-mono px-1.5 py-0.5 rounded border ${z.badge}`}>
                {z.fgm}/{z.fga} FGM
              </span>
            </div>
            {/* Miniature progress bar */}
            <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
              <div className={`${z.color} h-full rounded-full`} style={{ width: `${Math.min(100, z.pct)}%` }} />
            </div>
          </div>
        ))}
      </div>
    </div>
  );
};
