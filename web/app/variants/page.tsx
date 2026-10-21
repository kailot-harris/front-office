import { getTeamsData, getMetadata } from '@/lib/data';
import { VariantsClient } from '@/components/VariantsClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

export default function VariantsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Model Variants Breakout</span>
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
            Compare 1,000-season predictions across Production Bottom-Up BPM, Possession-Level RAPM, Shot Quality & Fatigue, and 16-D Embeddings.
          </p>
        </div>
      </div>

      <VariantsClient teams={teams} metadata={metadata} />
    </div>
  );
}
