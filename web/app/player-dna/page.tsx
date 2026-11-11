import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';

export const metadata: Metadata = {
  title: 'Player DNA & Historical Twins',
  description:
    'High-dimensional 16-D player skill vectors, multivariate fingerprints, and cosine-similarity matching against all-time WNBA legends.',
};

// Issue #134: serializing all ~220 player DNA profiles straight into page
// props inflated this route's generated index.html to ~608 KB. Only the
// first screen of rows is embedded in the static HTML now; PlayerDnaClient
// fetches the full dataset client-side from /data/player_dna_profiles.json
// (already published to public/data/ for exactly this purpose) once the
// page has hydrated.
const INITIAL_PROFILE_COUNT = 24;

async function getPlayerDnaData(): Promise<PlayerDnaProfile[]> {
  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const filePath = path.join(dataDir, 'player_dna_profiles.json');

    if (!fs.existsSync(filePath)) {
      return [];
    }

    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error('Failed to load player DNA profiles:', err);
    return [];
  }
}

export default async function PlayerDnaPage() {
  const allProfiles = await getPlayerDnaData();
  // Always include the default-selected marquee player (A'ja Wilson) in the
  // initial slice even if she'd otherwise fall outside the first screen, so
  // the default view never flashes a different player while the rest loads.
  const featured = allProfiles.find((p) => p.playerName.includes("A'ja Wilson"));
  const firstScreen = allProfiles.slice(0, INITIAL_PROFILE_COUNT);
  const initialProfiles =
    featured && !firstScreen.some((p) => p.playerId === featured.playerId)
      ? [featured, ...firstScreen]
      : firstScreen;

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient initialProfiles={initialProfiles} totalProfileCount={allProfiles.length} />
    </div>
  );
}
