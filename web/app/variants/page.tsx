import { getTeamsData, getMetadata } from '@/lib/data';
import { VariantsClient } from '@/components/VariantsClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';
import { HowToReadDisclosure } from '@/components/HowToReadDisclosure';
import { GlossaryTerm } from '@/components/GlossaryTerm';

export const metadata = {
  title: 'Model Variants Breakout',
  description:
    'Compare 1,000-season projections across the Production Bottom-Up BPM, Possession-Level RAPM, Shot Quality & Fatigue, and 16-D Embeddings model variants plus the ensemble.',
};

export default function VariantsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span><span className="text-orange-400">NBA</span> Model Variants Breakout</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                4 Variants + Ensemble
              </span>
              <SeasonSourceBadge
                season={SEASON_SOURCES.variants.season}
                kind="projection"
                label="Projected season"
                title={SEASON_SOURCES.variants.note}
              />
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Compare 1,000-season predictions across Production Bottom-Up <GlossaryTerm term="BPM" />,
              Possession-Level <GlossaryTerm term="RAPM" />, Shot Quality & Fatigue, and 16-D <GlossaryTerm term="embeddings" />.
            </p>
          </div>
        </div>
        <div className="w-full h-[2px] bg-gradient-to-r from-orange-400 via-orange-500/40 to-transparent mt-4" />
      </div>

      <HowToReadDisclosure pageKey="variants">
        Each model variant projects the season independently using a different methodology
        (<GlossaryTerm term="BPM" />-based box score, <GlossaryTerm term="RAPM" /> play-by-play
        impact, shot-quality/fatigue adjustment, or 16-D <GlossaryTerm term="embeddings" />). The
        Ensemble column blends all four; large spreads between variants flag teams where the
        models disagree most.
      </HowToReadDisclosure>

      <VariantsClient teams={teams} metadata={metadata} />
    </div>
  );
}
