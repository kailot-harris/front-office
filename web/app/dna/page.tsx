import { getPlayerDnaProfiles } from '@/lib/data';
import PlayerDnaClient from '@/components/PlayerDnaClient';

export const metadata = {
  title: 'Player DNA & Skill Fingerprints',
  description: 'Empirical multivariate player skill profiles, interactive SVG radar charts, and nearest historical twin comparables across NFL starters.',
};

export default function PlayerDnaPage() {
  const profiles = getPlayerDnaProfiles();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient initialProfiles={profiles} />
    </div>
  );
}
