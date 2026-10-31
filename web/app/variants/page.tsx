import { getTeamsData, getMetadata } from '@/lib/data';
import { VariantsClient } from '@/components/VariantsClient';

export default function VariantsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Sabermetric Model Variants Breakout</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                4 Engines + Ensemble
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Compare 162-game Monte Carlo projections across 4-Factor Starting-Pitcher Elo, Hierarchical Empirical Bayes Talent, Pythagenpat Run-Expectation, and Marcel/Bullpen Fatigue.
            </p>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <VariantsClient teams={teams} metadata={metadata} />
    </div>
  );
}
