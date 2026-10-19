import fs from 'fs';
import path from 'path';
import { PlayoffMatchupsCatalog } from '@/lib/playoffTypes';
import { PlayoffSeriesClient } from '@/components/PlayoffSeriesClient';

export const metadata = {
  title: '7-Game Playoff Series Simulator | NBA Analytics',
  description: '10,000-sim Monte Carlo playoff series simulator with 8-man rotation shortening and tactical mismatch adjustments.',
};

function getPlayoffCatalog(): PlayoffMatchupsCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'playoff_series_matchups.json');
  if (!fs.existsSync(filePath)) {
    return {
      teams: {},
      sampleMatchups: [],
    };
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as PlayoffMatchupsCatalog;
  } catch (err) {
    console.error('Failed to load playoff_series_matchups.json:', err);
    return {
      teams: {},
      sampleMatchups: [],
    };
  }
}

export default function SeriesPage() {
  const catalog = getPlayoffCatalog();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayoffSeriesClient catalog={catalog} />
    </div>
  );
}
