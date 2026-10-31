import { getTeamsData, getMetadata } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

export default function HomePage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-orange-400">NBA</span> Season Projections</span>
              <SeasonSourceBadge
                season={metadata.season_label ?? metadata.season}
                kind="projection"
                label="Projected season"
                title={SEASON_SOURCES.teamProjections.note}
              />
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Probabilistic 1,000-season Monte Carlo simulation results across all 30 teams and multi-model blend.
              Inputs include 2025-2026 observed RAPM and shot quality.
            </p>
          </div>
          <div className="flex items-center gap-3 text-xs text-slate-400">
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block">Total Simulated Games</span>
              <span className="text-white font-mono font-bold">1,230,000 Games</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block">Simulation Engines</span>
              <span className="text-white font-mono font-bold">4 Distinct Variants</span>
            </div>
          </div>
        </div>
        <div className="w-full h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent mt-4" />
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="visualizer" />
    </div>
  );
}
