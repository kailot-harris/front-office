import { getPlayoffSeriesCatalog } from '@/lib/data';
import { PlayoffSeriesClient } from '@/components/PlayoffSeriesClient';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Interactive Playoff Series Simulator | MLB Analytics',
  description: '10,000 Monte Carlo series simulations with rotation matchups and tactical radars.',
};

export default function PlayoffSeriesPage() {
  const catalog = getPlayoffSeriesCatalog();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayoffSeriesClient catalog={catalog} />
    </div>
  );
}
