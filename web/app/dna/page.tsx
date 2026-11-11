import { getPlayerDnaProfiles } from '@/lib/data';
import PlayerDnaClient from '@/components/PlayerDnaClient';

export const metadata = {
  title: 'Player DNA & Skill Fingerprints',
  description: 'Empirical multivariate player skill profiles, interactive SVG radar charts, and nearest historical twin comparables across NFL starters.',
};

// #134: this route was shipping all ~423 player profiles (922 KB) serialized straight into the
// page's HTML. Only the first screen's worth of rows need to be server-rendered — the rest is
// fetched client-side from the same /data/player_dna_profiles.json that already exists in
// public/ (see PlayerDnaClient's useEffect), which also means the full dataset stops
// round-tripping through Next's RSC payload on every page load.
const INITIAL_PROFILE_ROWS = 24;

export default function PlayerDnaPage() {
  const profiles = getPlayerDnaProfiles();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient initialProfiles={profiles.slice(0, INITIAL_PROFILE_ROWS)} totalCount={profiles.length} />
    </div>
  );
}
