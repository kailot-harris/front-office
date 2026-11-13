import Link from 'next/link';
import { Metadata } from 'next';
import { getTeamsData, getMetadata, getPlayoffBracketData } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';
import { TeamLogo } from '@/components/TeamLogo';
import { BracketSeries } from '@/lib/playoffTypes';

export const metadata: Metadata = {
  title: 'Standings & Playoff Contenders',
  description:
    'Season-long WNBA standings, playoff contender distributions, and championship odds for all 15 franchises, projected from a 1,000-season Monte Carlo ensemble.',
};

export default function HomePage() {
  const teams = getTeamsData();
  const metadata = getMetadata();
  const bracketData = getPlayoffBracketData();

  const finalsSeries = bracketData?.series?.find((s: BracketSeries) => s.round === 'Finals');
  const championAbbr = bracketData?.champion || (finalsSeries?.seriesComplete ? finalsSeries.winner : null);
  const isSeriesDecided = Boolean(championAbbr);
  const championTeamName = championAbbr ? (teams.find((t) => t.team === championAbbr)?.team_name || championAbbr) : '';

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      {/* 2026 WNBA Finals / Championship Victory Banner */}
      <section
        aria-label="2026 WNBA Championship announcement"
        className="relative overflow-hidden rounded-xl border border-amber-500/30 bg-gradient-to-r from-slate-900 via-amber-950/20 to-slate-900 p-4 sm:p-5 text-slate-200 shadow-sm"
      >
        <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-center gap-3.5">
            <div className="p-1 rounded-lg bg-amber-500/10 border border-amber-500/20">
              <TeamLogo team={championAbbr || 'GS'} size="lg" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <span className="text-[11px] font-mono uppercase tracking-wider font-semibold px-2 py-0.5 rounded bg-amber-500/20 text-amber-300 border border-amber-500/30">
                  {isSeriesDecided ? '2026 WNBA Champions' : '2026 WNBA Finals Game 7 Tonight'}
                </span>
                <span className="text-xs text-slate-400">October 31, 2026</span>
              </div>
              <h2 className="text-base sm:text-lg font-semibold text-white tracking-tight mt-1">
                {isSeriesDecided
                  ? `${championTeamName} capture the 2026 WNBA Championship`
                  : 'Golden State Valkyries vs. Atlanta Dream: Game 7 Championship Decider'}
              </h2>
              <p className="text-xs sm:text-sm text-slate-300/90 mt-0.5">
                {isSeriesDecided
                  ? 'The 2026 WNBA season concludes. Postseason simulation brackets, leverage paths, and championship run metrics are now frozen.'
                  : 'Deadlocked 3-3, the Finals reach the ultimate decider at Chase Center tonight. Series outcomes and the S0 league state baseline freeze upon conclusion.'}
              </p>
            </div>
          </div>
          <div className="flex items-center gap-2.5 sm:self-center self-start pl-1 sm:pl-0">
            <Link
              href="/retrospective"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-amber-500/10 hover:bg-amber-500/20 text-amber-200 border border-amber-500/30 transition-colors"
            >
              Season Retrospective &rarr;
            </Link>
            <Link
              href="/bracket-2026"
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded-lg bg-slate-800 hover:bg-slate-700 text-slate-300 border border-slate-700 transition-colors"
            >
              2026 Bracket
            </Link>
          </div>
        </div>
      </section>

      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-accent-400">WNBA</span> Season Projections
              </span>
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
              <span className="text-slate-400 block">Total Schedule Games</span>
              <span className="text-white font-mono font-bold">330 Games</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-400 block">Simulation Engines</span>
              <span className="text-white font-mono font-bold">4 Distinct Variants</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="visualizer" />
    </div>
  );
}
