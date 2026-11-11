import React from 'react';
import { getTeamEpaProfiles } from '@/lib/data';
import { TeamsClient } from '@/components/TeamsClient';
import { ShieldCheck } from 'lucide-react';
import { GlossaryButton, GlossaryTerm } from '@/components/Glossary';
import { HowToRead } from '@/components/HowToRead';

export const metadata = {
  title: 'Team Power Ratings & EPA Profiles',
  description:
    'Expected Points Added (EPA) per play, passing CPOE, early vs. money down splits, red zone efficiency, and 2D quadrant scatter for all 32 NFL franchises.',
};

export default function TeamsPage() {
  const teams = getTeamEpaProfiles();
  const generatedAt = teams[0]?.generated_at;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header Banner */}
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-cyan-500/10 text-cyan-400 border border-cyan-500/20 font-mono flex items-center gap-1.5">
                <ShieldCheck className="w-3.5 h-3.5" />
                <span>Advanced EPA Efficiency</span>
              </span>
              <span className="text-xs text-slate-400 font-mono">32 NFL Franchises</span>
            </div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-emerald-400">NFL</span> Team Ratings & EPA Profiles</span>
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-3xl">
              Granular down-by-down and situational efficiency: <GlossaryTerm term="EPA" className="text-slate-300" /> per play,
              Success Rate, <GlossaryTerm term="CPOE" className="text-slate-300" />, and 4-quadrant efficiency mapping.
            </p>
          </div>

          {/* Quick Context Chips */}
          <div className="flex items-center gap-2.5 text-xs font-mono">
            <GlossaryButton />
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[11px] sm:text-[10px] uppercase">Evaluation Window</span>
              <span className="text-white font-bold">Rolling 4 Games</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[11px] sm:text-[10px] uppercase">Efficiency Model</span>
              <span className="text-emerald-400 font-bold">nflverse PBP Engine</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      <HowToRead pageKey="teams-epa">
        <p>
          <strong>EPA/play</strong> measures how many points each play was worth relative to the average outcome in
          that situation &mdash; positive is good offense, negative is good defense. The quadrant scatter plots
          offensive EPA against defensive EPA, so the top-right corner is the league&apos;s best all-around teams.
          <strong> CPOE</strong> isolates quarterback accuracy from the QB&apos;s decision-making, independent of
          how hard the throw was.
        </p>
      </HowToRead>

      {/* Main Interactive Client */}
      <TeamsClient teams={teams} generatedAt={generatedAt} />
    </div>
  );
}
