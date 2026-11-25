import { getPlayerLeaders, getQbProfiles } from '@/lib/data';
import { LeagueLeadersPanel } from '@/components/LeagueLeadersPanel';
import PlayersClient from '@/components/PlayersClient';

export const metadata = {
  title: 'Quarterback & Player Analytics',
  description: 'Rolling per-dropback EPA and CPOE tracking, backup QB projected margin impact, and player efficiency tiers.',
};

export default function PlayersPage() {
  const qbs = getQbProfiles();
  const leaders = getPlayerLeaders();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <LeagueLeadersPanel data={leaders} />
      <PlayersClient initialQbs={qbs} />
    </div>
  );
}
