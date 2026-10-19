import fs from 'fs';
import path from 'path';
import { PlayerCatalogEntry, ShotsMetadata } from '@/lib/shotTypes';
import { ShotsExplorerClient } from '@/components/ShotsExplorerClient';

function getShotsCatalog(): PlayerCatalogEntry[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'shots_index.json');
  if (!fs.existsSync(filePath)) return [];
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as PlayerCatalogEntry[];
}

function getShotsMetadata(): ShotsMetadata {
  const filePath = path.join(process.cwd(), 'public', 'data', 'shots_metadata.json');
  if (!fs.existsSync(filePath)) {
    return {
      updated_at: new Date().toISOString(),
      total_shots_sampled: 0,
      league_averages: [],
      zones: [],
    };
  }
  const content = fs.readFileSync(filePath, 'utf-8');
  return JSON.parse(content) as ShotsMetadata;
}

export default function ShotsPage() {
  const catalog = getShotsCatalog();
  const metadata = getShotsMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Player Shot Charts & Hot Zones</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
              Prior N Rolling Horizon
            </span>
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            Dynamic half-court spatial analytics: Empirical Bayes shrinkage, Binomial z-scores, and thermal hot/cold classification.
          </p>
        </div>
      </div>

      <ShotsExplorerClient catalog={catalog} metadata={metadata} />
    </div>
  );
}
