import { Metadata } from 'next';
import {
  getTeamsData,
  getMetadata,
  getVisualMediaIndex,
  getActualTeamRecords,
} from '@/lib/data';
import { toVisualMediaItems } from '@/lib/visualMedia';
import { StandingsClient } from '@/components/StandingsClient';
import { HowToRead } from '@/components/HowToRead';
import { GlossaryTerm } from '@/components/Glossary';

export const metadata: Metadata = {
  title: 'Standings & Projections vs. Actual',
  description:
    '2026 MLB standings, 162-game win pace, run differential, and performance delta against preseason ensemble projections across all 30 clubs.',
};

export default function StandingsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();
  const mediaItems = toVisualMediaItems(getVisualMediaIndex());
  const actualRecords = getActualTeamRecords();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-sky-400">MLB</span> Standings &amp; Projections vs. Actual
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                162-Game Tracker
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Regular-season records, run differentials, and 162-game win pace benchmarked against preseason{' '}
              <GlossaryTerm term="Elo" />, <GlossaryTerm term="Empirical Bayes" />,{' '}
              <GlossaryTerm term="Pythagenpat" />, and <GlossaryTerm term="Marcel Projection">Marcel</GlossaryTerm> ensemble projections.
            </p>
            <div className="max-w-xl mt-4">
              <HowToRead pageKey="standings">
                Current 162-game win pace scales each club&apos;s regular-season win percentage to a
                full 162-game slate (and equals final wins once 162 games are complete). Performance
                Delta measures pace minus preseason ensemble projected wins — green indicates clubs
                outperforming expectations, red indicates clubs falling short.
              </HowToRead>
            </div>
          </div>
          <div className="flex items-center gap-3 text-xs text-slate-400">
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-400 block">Regular Season Slate</span>
              <span className="text-white font-mono font-bold">162 Games / Club</span>
            </div>
            <div className="bg-surface-raised border border-slate-800 rounded-lg px-3 py-2 text-right">
              <span className="text-slate-400 block">Franchises Tracked</span>
              <span className="text-white font-mono font-bold">30 MLB Clubs</span>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-emerald-500/40 to-transparent" />
      </div>

      <StandingsClient
        teams={teams}
        metadata={metadata}
        mediaItems={mediaItems}
        actualRecords={actualRecords}
        initialTab="table"
        initialTableMode="reality"
      />
    </div>
  );
}
