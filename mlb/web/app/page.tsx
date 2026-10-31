import Link from 'next/link';
import { getTeamsData, getMetadata } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';
import { TeamLogo } from '@/components/TeamLogo';

export default function HomePage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* 2026 World Series Champions Banner */}
      <section
        aria-label="2026 World Series Champion announcement"
        className="relative overflow-hidden rounded-xl border border-amber-500/30 bg-gradient-to-r from-slate-900 via-amber-950/20 to-slate-900 p-4 sm:p-5 text-slate-200 shadow-sm"
      >
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-3.5">
            <div className="p-1 rounded-lg bg-amber-500/10 border border-amber-500/20">
              <TeamLogo team="MIL" size="lg" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-[11px] font-mono uppercase tracking-wider font-semibold px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30">
                  2026 World Series Champions
                </span>
                <span className="text-xs text-slate-400">October 28, 2026</span>
              </div>
              <h2 className="text-base sm:text-lg font-semibold text-white tracking-tight mt-1">
                Milwaukee Brewers capture the 2026 Commissioner&apos;s Trophy
              </h2>
              <p className="text-xs sm:text-sm text-slate-300/90 mt-0.5">
                The fall classic concludes in Milwaukee. Postseason simulation brackets, leverage paths, and championship run metrics are now locked.
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2.5 sm:self-center self-start pl-1 sm:pl-0">
            <Link
              href="/postseason"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-amber-500/10 hover:bg-amber-500/20 text-amber-200 border border-amber-500/30 transition-colors"
            >
              Postseason Audit &rarr;
            </Link>
            <Link
              href="/teams?team=MIL"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition-colors"
            >
              Brewers Profile
            </Link>
          </div>
        </div>
      </section>

      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Season & Postseason Projections</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
                162-Game Slate
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Probabilistic Monte Carlo simulation results across all 30 MLB franchises combining 4-Factor Pitcher Elo, Empirical Bayes, Pythagenpat, and Marcel/Bullpen models.
            </p>
          </div>
          <div className="flex items-center gap-3 text-xs text-slate-400">
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block">Total Simulated Games</span>
              <span className="text-white font-mono font-bold">2,430,000 Games</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-500 block">Sabermetric Engines</span>
              <span className="text-white font-mono font-bold">4 Distinct Variants</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="visualizer" />
    </div>
  );
}
