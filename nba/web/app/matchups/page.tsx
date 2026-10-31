import React from 'react';
import { Swords } from 'lucide-react';
import { getMatchupsData } from '@/lib/data';
import { MatchupsClient } from '@/components/MatchupsClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { formatSeasonLabel, SEASON_SOURCES } from '@/lib/season';

export const metadata = {
  title: 'Matchups: Weekly Slates, Projections & Graded Results | NBA Quantitative Analytics',
  description:
    'Per-game NBA matchup slates for the whole season: live model projections for the current week, final scores with graded prediction results for past weeks, and pending projections for upcoming weeks.',
};

export default function MatchupsPage() {
  const dataset = getMatchupsData();
  const activeSlate = dataset.slates.find((s) => s.slate === dataset.active_slate) ?? null;
  const seasonLabel =
    formatSeasonLabel(dataset.season_label) ?? dataset.season_label;

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs font-bold uppercase tracking-wider px-2.5 py-0.5 rounded-full bg-accent-500/10 text-accent-400 border border-accent-500/20 font-mono flex items-center gap-1.5">
                <Swords className="w-3.5 h-3.5" />
                <span>Per-Game Projection Engine</span>
              </span>
              <span className="text-xs text-slate-400 font-mono">
                {seasonLabel} season · {dataset.available_slates.length} weekly slates ·{' '}
                {dataset.total_games} games
              </span>
              <SeasonSourceBadge
                season={seasonLabel}
                kind="projection"
                label="Season"
                title={SEASON_SOURCES.matchups.note}
              />
            </div>
            <h1 className="text-3xl font-black tracking-tight text-white"><span className="text-orange-400">NBA</span> Matchup Slates</h1>
            <p className="text-slate-400 text-sm mt-1 max-w-3xl">
              Every game of the {seasonLabel} season — and only that season — bucketed into
              weekly slates. Past weeks show the real final score next to the model&apos;s pre-game
              pick and whether it graded out correct; the active week shows live projections; upcoming
              weeks show the pending projection with no score or result.
            </p>
            {/*
              Two different models produce the projections on this page. Saying so
              here, and labelling every card and table row with its basis, is what
              keeps the page from implying the two numbers are comparable.
            */}
            <p className="text-slate-500 text-xs mt-2 max-w-3xl font-mono">
              Projection basis: {dataset.games_logged_basis} game
              {dataset.games_logged_basis === 1 ? '' : 's'} carry the logged slate model&apos;s own
              pre-game projection — the only basis that is graded for accuracy —
              and {dataset.games_ensemble_basis ?? dataset.games_ratings_basis} are projected from
              the primary 4-model ensemble ({dataset.ratings_source}). The two come from unrelated
              inputs, are never averaged, and every game is labelled with the one that produced it.
            </p>
          </div>

          <div className="flex items-center gap-2.5 text-xs font-mono">
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">Active Slate</span>
              <span className="text-white font-bold">Week {dataset.active_slate}</span>
            </div>
            {/* With nothing graded yet, say so instead of printing a bare "0 /". */}
            <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
              <span className="text-slate-500 block text-[10px] uppercase">
                {dataset.graded_games_available ? 'Graded / Pending' : 'Grading'}
              </span>
              <span className="text-accent-400 font-bold">
                {dataset.graded_games_available
                  ? `${dataset.completed_games} / ${dataset.pending_games}`
                  : 'Not yet graded'}
              </span>
            </div>
            {activeSlate && (
              <div className="bg-surface-raised border border-slate-800 rounded-xl px-3 py-2 text-right">
                <span className="text-slate-500 block text-[10px] uppercase">Window</span>
                <span className="text-white font-bold">{activeSlate.start_date}</span>
              </div>
            )}
          </div>
        </div>
        <div className="w-full h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent mt-4" />
      </div>

      <MatchupsClient dataset={dataset} />
    </div>
  );
}
