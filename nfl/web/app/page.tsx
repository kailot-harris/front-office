import React from 'react';
import { getStandingsData } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';
import { Swords, Activity, Award } from 'lucide-react';
import Link from 'next/link';

export default function HomePage() {
  const dataset = getStandingsData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-8">
      {/* Header Banner */}
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-mono">
                Season 2026 Live
              </span>
              <span className="text-xs text-slate-400 font-mono">1,000-Sim Monte Carlo</span>
            </div>
            <h1 className="text-3xl sm:text-4xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-emerald-400">NFL</span> Season Projections</span>
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-2xl">
              Probabilistic simulation engine across all 32 NFL franchises, synthesizing Ridge regression, Elo ratings, EPA/play efficiency, situational fatigue, and market lines.
            </p>
          </div>

          {/* Quick Stats Grid */}
          <div className="flex items-center gap-3 text-xs text-slate-400 flex-wrap">
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase font-mono">Total Simulations</span>
              <span className="text-white font-mono font-bold text-sm">1,000 Seasons</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase font-mono">Playoff Field</span>
              <span className="text-emerald-400 font-mono font-bold text-sm">14 Seeds (7/Conf)</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase font-mono">Margin Sigma (σ)</span>
              <span className="text-white font-mono font-bold text-sm">14.6 pts</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      {/* Feature Highlights Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <Link
          href="/matchups"
          className="group p-4 bg-surface-raised/60 hover:bg-slate-800/60 border border-slate-800 hover:border-emerald-500/40 rounded-xl transition-all shadow-sm"
        >
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-emerald-400 font-bold">Matchup Engine</span>
            <Swords className="w-4 h-4 text-slate-400 group-hover:text-emerald-400 transition-colors" />
          </div>
          <h2 className="text-base font-bold text-white mb-1 group-hover:text-emerald-300 transition-colors">
            Weekly Matchup Projections
          </h2>
          <p className="text-xs text-slate-400 leading-relaxed">
            Projected margins, totals, win probabilities, and rest/travel fatigue adjustments for current week games.
          </p>
        </Link>

        <Link
          href="/teams"
          className="group p-4 bg-surface-raised/60 hover:bg-slate-800/60 border border-slate-800 hover:border-emerald-500/40 rounded-xl transition-all shadow-sm"
        >
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-cyan-400 font-bold">Advanced EPA</span>
            <Activity className="w-4 h-4 text-slate-400 group-hover:text-cyan-400 transition-colors" />
          </div>
          <h2 className="text-base font-bold text-white mb-1 group-hover:text-cyan-300 transition-colors">
            Team Power Tiers & Scatter
          </h2>
          <p className="text-xs text-slate-400 leading-relaxed">
            Offensive vs. defensive EPA quadrant scatter, CPOE, early vs. late down splits, and Elo rating trajectory.
          </p>
        </Link>

        <Link
          href="/playoffs"
          className="group p-4 bg-surface-raised/60 hover:bg-slate-800/60 border border-slate-800 hover:border-emerald-500/40 rounded-xl transition-all shadow-sm"
        >
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-mono uppercase tracking-wider text-amber-400 font-bold">Postseason</span>
            <Award className="w-4 h-4 text-slate-400 group-hover:text-amber-400 transition-colors" />
          </div>
          <h2 className="text-base font-bold text-white mb-1 group-hover:text-amber-300 transition-colors">
            14-Team Playoff Machine
          </h2>
          <p className="text-xs text-slate-400 leading-relaxed">
            Provisional seeding, official NFL tiebreakers, and 1,000-trial Monte Carlo bracket advancement probabilities.
          </p>
        </Link>
      </div>

      {/* Standings Interactive Client Dashboard */}
      <StandingsClient dataset={dataset} initialTab="visualizer" />
    </div>
  );
}
