import { getTeamsData, getMetadata } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';

export default function TeamsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Full Standings Table</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
              30 NBA Franchises
            </span>
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            Expected win distributions, variance bounds, and playoff equity from 1,000-season Monte Carlo iterations.
          </p>
        </div>
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="table" />
    </div>
  );
}
