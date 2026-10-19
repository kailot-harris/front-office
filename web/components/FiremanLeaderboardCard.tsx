'use client';

import React from 'react';
import { ClutchProfile } from '@/lib/clutchTypes';
import { Flame, Crosshair } from 'lucide-react';

interface FiremanLeaderboardCardProps {
  profile: ClutchProfile;
}

export const FiremanLeaderboardCard: React.FC<FiremanLeaderboardCardProps> = ({ profile }) => {
  const isPitcher = profile.playerType === 'Pitcher';
  const fireman = profile.firemanStats;
  const risp = profile.rispSplit;

  if (isPitcher && fireman) {
    return (
      <div className="p-4 bg-slate-950/70 rounded-2xl border border-slate-800 shadow-xl space-y-3 font-mono">
        <div className="flex items-center justify-between border-b border-slate-800/80 pb-2">
          <div className="flex items-center gap-2">
            <Flame className="w-4 h-4 text-rose-400" />
            <h4 className="text-xs font-bold text-white uppercase tracking-wider">
              High-Leverage Relief Fireman Metrics
            </h4>
          </div>
          <span className="text-[10px] px-2 py-0.5 rounded-full bg-rose-500/10 text-rose-300 border border-rose-500/20 font-bold">
            Fireman Index {fireman.firemanIndex}
          </span>
        </div>

        <div className="grid grid-cols-2 gap-3 text-xs">
          <div className="bg-slate-900/80 p-2.5 rounded-xl border border-slate-800/60 space-y-1">
            <span className="text-[10px] text-slate-400 uppercase block">Inherited Strand Rate</span>
            <div className="flex items-baseline justify-between">
              <span className="text-xl font-black text-emerald-400">{fireman.strandRatePct}%</span>
              <span className="text-[11px] text-slate-400">
                {fireman.inheritedRunners - fireman.inheritedScored}/{fireman.inheritedRunners} Stranded
              </span>
            </div>
            <div className="w-full bg-slate-950 h-1.5 rounded-full overflow-hidden mt-1">
              <div className="bg-emerald-500 h-full rounded-full" style={{ width: `${fireman.strandRatePct}%` }} />
            </div>
          </div>

          <div className="bg-slate-900/80 p-2.5 rounded-xl border border-slate-800/60 space-y-1">
            <span className="text-[10px] text-slate-400 uppercase block">Shutdowns vs Meltdowns</span>
            <div className="flex items-baseline justify-between">
              <span className="text-xl font-black text-sky-400">{fireman.shutdowns} SD</span>
              <span className="text-xs font-bold text-rose-400">{fireman.meltdowns} MD</span>
            </div>
            <span className="text-[10px] text-slate-500 block">
              Ratio: {((fireman.shutdowns / Math.max(1, fireman.meltdowns))).toFixed(1)}:1
            </span>
          </div>
        </div>

        <div className="flex items-center justify-between p-2 rounded-lg bg-slate-900/60 border border-slate-800/50 text-[11px]">
          <span className="text-slate-400">High-LI WPA Generated:</span>
          <span className="font-bold text-white">+{profile.highLiWpa.toFixed(2)} Wins</span>
        </div>
      </div>
    );
  }

  // Batter 2-Out RISP Situation Split
  return (
    <div className="p-4 bg-slate-950/70 rounded-2xl border border-slate-800 shadow-xl space-y-3 font-mono">
      <div className="flex items-center justify-between border-b border-slate-800/80 pb-2">
        <div className="flex items-center gap-2">
          <Crosshair className="w-4 h-4 text-rose-400" />
          <h4 className="text-xs font-bold text-white uppercase tracking-wider">
            High-Stakes 2-Out RISP Conversion Split
          </h4>
        </div>
        <span className="text-[10px] text-slate-400">
          N = {risp.pa} Plate Appearances
        </span>
      </div>

      <div className="grid grid-cols-4 gap-2 text-center text-xs">
        <div className="bg-slate-900/80 p-2 rounded-xl border border-slate-800/60">
          <span className="text-[10px] text-slate-400 block">AVG</span>
          <span className="text-sm font-black text-white">{risp.avg.toFixed(3)}</span>
        </div>
        <div className="bg-slate-900/80 p-2 rounded-xl border border-slate-800/60">
          <span className="text-[10px] text-slate-400 block">OBP</span>
          <span className="text-sm font-black text-sky-400">{risp.obp.toFixed(3)}</span>
        </div>
        <div className="bg-slate-900/80 p-2 rounded-xl border border-slate-800/60">
          <span className="text-[10px] text-slate-400 block">SLG</span>
          <span className="text-sm font-black text-amber-400">{risp.slg.toFixed(3)}</span>
        </div>
        <div className="bg-slate-900/80 p-2 rounded-xl border border-slate-800/60">
          <span className="text-[10px] text-slate-400 block">OPS</span>
          <span className="text-sm font-black text-rose-400">{risp.ops.toFixed(3)}</span>
        </div>
      </div>

      <div className="flex items-center justify-between p-2 rounded-lg bg-slate-900/60 border border-slate-800/50 text-[11px]">
        <span className="text-slate-400">High-Leverage WPA Added:</span>
        <span className="font-bold text-white">+{profile.highLiWpa.toFixed(2)} Wins</span>
      </div>
    </div>
  );
};
