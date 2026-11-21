import { getPlayerDnaCatalog } from '@/lib/data';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';
import { PlayerDnaProfile, summarizePlayerDna } from '@/lib/playerDnaTypes';
import { Metadata } from 'next';

export const metadata: Metadata = {
  title: { absolute: 'Player DNA & Peer Comps | MLB Analytics' },
  description: 'Current-season skill percentiles, rule-based archetypes, and nearest same-season peer comps by cosine similarity for qualified MLB batters and pitchers.',
};

// Serializing every qualified player's profile (with peer comps) into the page
// props made this route's index.html about 1.7 MB. Only the first screen of each
// player type is embedded now; PlayerDnaClient fetches the full
// ${BASE_PATH}/data/player_dna_profiles.json after hydration (same pattern as the
// WNBA site's /player-dna). Whole-dataset facts the page shows before that fetch
// completes (counts, archetype list, dimension and category metadata) are computed
// here from the full file, so they are correct from the first paint.
const INITIAL_PROFILES_PER_TYPE = 24;

export default function PlayerDnaPage() {
  const catalog = getPlayerDnaCatalog();
  const summary = summarizePlayerDna(catalog.profiles);
  // Profiles are written best-first within each type, so the first screen of each
  // type is its first rows. The default selection (first batter) is always included.
  const firstScreen: PlayerDnaProfile[] = (['Batter', 'Pitcher'] as const).flatMap((type) =>
    catalog.profiles.filter((p) => p.playerType === type).slice(0, INITIAL_PROFILES_PER_TYPE),
  );

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient initialCatalog={{ ...catalog, profiles: firstScreen }} summary={summary} />
    </div>
  );
}
