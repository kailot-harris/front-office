import { getQbProfiles } from '@/lib/data';
import PlayersClient from '@/components/PlayersClient';

export const metadata = {
  title: 'Quarterback & Player Analytics | NFL Analytics',
  description: 'Rolling per-dropback EPA and CPOE tracking, backup QB spread impact, and player efficiency tiers.',
};

export default function PlayersPage() {
  const qbs = getQbProfiles();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayersClient initialQbs={qbs} />
    </div>
  );
}
