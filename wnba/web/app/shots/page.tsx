import fs from 'fs';
import path from 'path';
import { PlayerCatalogEntry, ShotsMetadata } from '@/lib/shotTypes';
import { ShotsExplorerClient } from '@/components/ShotsExplorerClient';

export const metadata = {
  title: 'Player Shot Charts & Hot Zones | WNBA Analytics',
  description: 'Dynamic half-court spatial analytics: Empirical Bayes shrinkage, Binomial z-scores, and thermal hot/cold 14-zone classification for WNBA rotation players.',
};

function getShotsCatalog(): PlayerCatalogEntry[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'shots_index.json');
  if (!fs.existsSync(filePath)) return [];
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as PlayerCatalogEntry[];
  } catch {
    return [];
  }
}

function getShotsMetadata(): ShotsMetadata {
  const filePath = path.join(process.cwd(), 'public', 'data', 'shots_metadata.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      total_shots_sampled: 0,
      league_averages: [],
      zones: [],
    };
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as ShotsMetadata;
  } catch {
    return {
      generated_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      total_shots_sampled: 0,
      league_averages: [],
      zones: [],
    };
  }
}

export default function ShotsPage() {
  const catalog = getShotsCatalog();
  const metadata = getShotsMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-accent-400">WNBA</span> Player Shot Charts & Hot Zones
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
                14 Discrete Spatial Zones
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1 max-w-3xl leading-relaxed">
              Dynamic half-court spatial analytics: Empirical Bayes shrinkage, Binomial z-scores,
              and thermal hot/cold classification across 260,000+ tracked WNBA shot attempts.
            </p>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <ShotsExplorerClient catalog={catalog} metadata={metadata} />
    </div>
  );
}
