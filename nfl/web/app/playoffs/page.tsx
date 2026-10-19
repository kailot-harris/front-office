import React from 'react';
import { getPlayoffPicture } from '@/lib/data';
import { PlayoffsClient } from '@/components/PlayoffsClient';
import { Award } from 'lucide-react';

export const metadata = {
  title: 'NFL Playoff Machine & 14-Team Bracket Simulator | NFL Analytics',
  description:
    '14-team provisional NFL playoff field (Seeds 1–7), official tiebreaker resolution, bubble contenders, and 10,000-trial Monte Carlo bracket simulation from Wild Card through the Super Bowl.',
};

export default function PlayoffsPage() {
  const dataset = getPlayoffPicture();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20 font-mono flex items-center gap-1.5">
              <Award className="w-3.5 h-3.5" />
              <span>Postseason Seeding Engine</span>
            </span>
            <span className="text-xs text-slate-400 font-mono">14 Seeds (7 AFC / 7 NFC)</span>
          </div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Playoff Machine & Bracket Simulator</span>
          </h1>
          <p className="text-slate-400 text-sm mt-1 max-w-3xl">
            Provisional 14-team postseason field resolved via real NFL tiebreakers (head-to-head, division, common games, conference, SOV, and SOS). Includes round-by-round Monte Carlo advancement equity and single-trial simulation.
          </p>
        </div>

        {/* Quick Context Chips */}
        <div className="flex items-center gap-2.5 text-xs font-mono">
          <div className="bg-slate-900 border border-slate-800 rounded-xl px-3 py-2 text-right">
            <span className="text-slate-500 block text-[10px] uppercase">Simulations</span>
            <span className="text-white font-bold">{dataset.n_simulations.toLocaleString()} Trials</span>
          </div>
          <div className="bg-slate-900 border border-slate-800 rounded-xl px-3 py-2 text-right">
            <span className="text-slate-500 block text-[10px] uppercase">Seeding Format</span>
            <span className="text-amber-400 font-bold">14 Teams (4 Div + 3 WC)</span>
          </div>
        </div>
      </div>

      {/* Main Interactive Client */}
      <PlayoffsClient dataset={dataset} />
    </div>
  );
}
