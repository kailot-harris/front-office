import { getPlayerDnaCatalog } from '@/lib/data';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: 'Player DNA & Historical Twins (1980–2026) | MLB Analytics',
  description: '16-D Statcast skill manifold, archetype clustering, and cosine similarity historical twins.',
};

export default function PlayerDnaPage() {
  const catalog = getPlayerDnaCatalog();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient catalog={catalog} />
    </div>
  );
}
