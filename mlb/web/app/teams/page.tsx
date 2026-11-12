import { Metadata } from 'next';
import { getTeamsData, getMetadata } from '@/lib/data';
import { StandingsClient } from '@/components/StandingsClient';
import { HowToRead } from '@/components/HowToRead';
import { GlossaryTerm } from '@/components/Glossary';

export const metadata: Metadata = {
  title: 'Full Standings Table',
  description:
    'Expected 162-game win distributions, 4-Factor Pitcher Elo ratings, Pythagenpat luck differentials, and World Series equity for all 30 MLB franchises.',
};

export default function TeamsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Full Standings Table</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
                30 MLB Franchises
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Expected 162-game win distributions, 4-Factor Pitcher <GlossaryTerm term="Elo" /> ratings, <GlossaryTerm term="Pythagenpat" /> luck differentials, and World Series equity.
            </p>
            <div className="max-w-xl mt-4">
              <HowToRead pageKey="teams">
                Each row is one franchise&apos;s full-season outlook: a simulated win total, an{' '}
                <GlossaryTerm term="Elo" /> power rating, and how far its actual-or-projected
                record has drifted from its <GlossaryTerm term="Pythagenpat" /> expected win total — a
                gap commonly attributed to &quot;luck.&quot; World Series equity is each team&apos;s
                share of the title across all 2,430,000 simulated seasons.
              </HowToRead>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <StandingsClient teams={teams} metadata={metadata} initialTab="table" />
    </div>
  );
}
