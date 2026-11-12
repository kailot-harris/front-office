import { Metadata } from 'next';
import { getPlayersData } from '@/lib/data';
import { PlayersClient } from '@/components/PlayersClient';
import { HowToRead } from '@/components/HowToRead';
import { GlossaryTerm } from '@/components/Glossary';

export const metadata: Metadata = {
  title: 'Batter & Pitcher Projections',
  description:
    '630 batters and 649 pitchers with Hierarchical Empirical Bayes pooled rates, Marcel counting projections, and spatial spray/strike-zone maps.',
};

// Only the first screen's worth of rows is serialized into the generated HTML
// (issue #134 — inlining the full ~1,279-player dataset ballooned the route to
// 1.6+ MB of HTML). PlayersClient fetches the full dataset client-side from
// /data/projections_season_players.json once the page is interactive.
const INITIAL_PLAYER_ROWS = 60;

export default function PlayersPage() {
  const players = getPlayersData().slice(0, INITIAL_PLAYER_ROWS);

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-sky-400">MLB</span> Batter & Pitcher Projections</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-rose-500/10 text-rose-400 border border-rose-500/20">
                1,279 Active MLB Players
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Toggle between 630 Batters and 649 Pitchers (SP/RP) with Hierarchical <GlossaryTerm term="Empirical Bayes" /> Pooled Rates, Tom Tango&apos;s <GlossaryTerm term="Marcel Projection">Marcel</GlossaryTerm> Counting Projections, Statistical Outlier Flags, and Interactive Spatial Spray & Strike Zone Maps for every player.
            </p>
            <div className="max-w-xl mt-4">
              <HowToRead pageKey="players">
                &quot;Raw&quot; columns are a player&apos;s unadjusted season rates — <GlossaryTerm term="wOBA" /> for
                batters, <GlossaryTerm term="xFIP" /> for pitchers. &quot;Pooled&quot; columns apply{' '}
                <GlossaryTerm term="Empirical Bayes" /> shrinkage toward the league average, which
                pulls small-sample players closer to a typical rate and matters most for anyone
                with limited playing time. Click a player to see their spray chart and strike-zone map.
              </HowToRead>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <PlayersClient players={players} />
    </div>
  );
}
