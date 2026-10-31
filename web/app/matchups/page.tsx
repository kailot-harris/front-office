import React from 'react';
import { Metadata } from 'next';
import { getMatchupsIndex, getMatchupsWeek } from '@/lib/data';
import { MatchupsClient } from '@/components/MatchupsClient';
import { Swords } from 'lucide-react';

export const metadata: Metadata = {
  title: 'Weekly Matchups & Elo Projections | MLB Analytics',
  description:
    'Every game of the season grouped into weekly slates, with pre-game Elo win probabilities graded against results.',
};

export default function MatchupsPage() {
  const dataset = getMatchupsIndex();
  // Only the opening slate is inlined into the HTML; the rest load on demand.
  const initialMatchups = getMatchupsWeek(dataset.active_week);
  const accuracyPct =
    dataset.overall_accuracy !== null ? `${(dataset.overall_accuracy * 100).toFixed(1)}%` : '—';

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* Header Banner */}
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-accent-500/10 text-accent-400 border border-accent-500/20 font-mono flex items-center gap-1.5">
                <Swords className="w-3.5 h-3.5" />
                <span>Weekly Slate Engine</span>
              </span>
              <span className="text-xs text-slate-400 font-mono">
                {dataset.available_weeks.length} weeks · {dataset.total_games} games
              </span>
            </div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Weekly Matchups</span>
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-3xl">
              Every {dataset.season} game grouped into Monday-anchored weekly slates. Completed games
              are graded against the Elo engine&apos;s walk-forward pre-game win probability — the
              number the model produced before the game, never a hindsight recomputation. Games
              without a result carry a forward projection from current team Elo.
            </p>
          </div>

          {/* Context Chips */}
          <div className="flex items-center gap-2.5 text-xs font-mono flex-shrink-0">
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Active Slate</span>
              <span className="text-white font-bold">Week {dataset.active_week}</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Season Record</span>
              <span className="text-emerald-400 font-bold">
                {dataset.correct_picks} / {dataset.graded_games} ({accuracyPct})
              </span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <MatchupsClient index={dataset} initialMatchups={initialMatchups} />
    </div>
  );
}
