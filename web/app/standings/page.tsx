import { Metadata } from 'next';
import { getTeamsData, getMetadata, getActualTeamRecords } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';

export const metadata: Metadata = {
  title: 'Standings & Projections vs. Actual',
  description:
    'Live WNBA regular-season standings benchmarked against preseason 44-game Monte Carlo projections, win pace, point differential, and performance delta.',
};

export default function StandingsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();
  const actualRecords = getActualTeamRecords();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-accent-400">WNBA</span> Standings &amp; Projections Tracker
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
                Season {metadata.season}
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Regular-season records, point differentials, and 44-game win pace compared against preseason ensemble projections.
            </p>
          </div>
          <div className="flex items-center gap-3 text-xs text-slate-400">
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-400 block">Regular Season</span>
              <span className="text-white font-mono font-bold">44 Games / Team</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-400 block">Simulation Engines</span>
              <span className="text-white font-mono font-bold">4 Distinct Variants</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <StandingsClient
        teams={teams}
        metadata={metadata}
        actualRecords={actualRecords}
        initialTab="table"
        initialMode="reality"
      />
    </div>
  );
}
