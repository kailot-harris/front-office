import React from 'react';
import { getMatchupsData } from '@/lib/data';
import { MatchupsClient } from '@/components/MatchupsClient';
import { Swords } from 'lucide-react';

export const metadata = {
  title: 'Weekly NFL Matchups & Projections | NFL Analytics',
  description:
    'Game-by-game projected margins, totals, win probabilities, and situational fatigue adjustments for all weekly NFL matchups.',
};

export default function MatchupsPage() {
  const dataset = getMatchupsData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header Banner */}
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-mono flex items-center gap-1.5">
                <Swords className="w-3.5 h-3.5" />
                <span>Weekly Projection Engine</span>
              </span>
              <span className="text-xs text-slate-400 font-mono">Weeks 1 – 18 (272 Games)</span>
            </div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-emerald-400">NFL</span> Weekly Matchup Projections</span>
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-3xl">
              Model-projected victory margins, game totals, and win probabilities powered by Ridge regression, Elo ratings, and situational fatigue adjustments (rest days, short weeks, and travel mileage).
            </p>
          </div>

          {/* Quick Context Chips */}
          <div className="flex items-center gap-2.5 text-xs font-mono">
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Active Slate</span>
              <span className="text-white font-bold">Week {dataset.active_week}</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Key Margin Alerts</span>
              <span className="text-emerald-400 font-bold">3, 7, 6, 10, 4</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      {/* Main Interactive Client */}
      <MatchupsClient dataset={dataset} />
    </div>
  );
}
