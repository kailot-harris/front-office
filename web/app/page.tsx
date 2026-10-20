import { getTeamsData, getMetadata } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';

export default function HomePage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>WNBA Season Projections</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
              Season 2026
            </span>
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            Probabilistic 1,000-season Monte Carlo simulation results across all 15 teams and multi-model blend.
          </p>
        </div>
        <div className="flex items-center gap-3 text-xs text-slate-400">
          <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
            <span className="text-slate-500 block">Total Schedule Games</span>
            <span className="text-white font-mono font-bold">330 Games</span>
          </div>
          <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
            <span className="text-slate-500 block">Simulation Engines</span>
            <span className="text-white font-mono font-bold">4 Distinct Variants</span>
          </div>
        </div>
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="visualizer" />
    </div>
  );
}
