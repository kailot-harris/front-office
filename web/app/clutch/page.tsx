import { getClutchCatalog } from '@/lib/data';
import { ClutchClient } from '@/components/ClutchClient';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'True Clutch & Leverage Index Engine | MLB Analytics',
  description: 'Tango Leverage Index (LI >= 1.50), pressure wOBA resilience, and relief Fireman strand ratings.',
};

export default function ClutchPage() {
  const catalog = getClutchCatalog();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <ClutchClient catalog={catalog} />
    </div>
  );
}
