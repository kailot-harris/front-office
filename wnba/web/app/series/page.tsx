import fs from 'fs';
import path from 'path';
import { PlayoffMatchupsCatalog } from '@/lib/playoffTypes';
import { PlayoffSeriesClient } from '@/components/PlayoffSeriesClient';

export const metadata = {
  title: 'Playoff Series Simulator | WNBA Analytics',
  description: '10,000-sim Monte Carlo playoff series simulator with 8-man rotation shortening (200 team-minute WNBA regulation scale), pairwise tactical mismatch adjustments, and historical bracket analysis.',
};

function getPlayoffCatalog(): PlayoffMatchupsCatalog {
  const filePath = path.join(process.cwd(), 'public', 'data', 'playoff_series_matchups.json');
  if (!fs.existsSync(filePath)) {
    return {
      generated_at: new Date().toISOString(),
      teams: {},
      sampleMatchups: [],
      historicalBrackets: {},
    };
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as PlayoffMatchupsCatalog;
  } catch (err) {
    console.error('Failed to load playoff_series_matchups.json:', err);
    return {
      generated_at: new Date().toISOString(),
      teams: {},
      sampleMatchups: [],
      historicalBrackets: {},
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
