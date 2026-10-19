import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';

export const metadata: Metadata = {
  title: 'Player DNA & Historical Twins | WNBA Analytics',
  description:
    'High-dimensional 16-D player skill vectors, multivariate fingerprints, and cosine-similarity matching against all-time WNBA legends.',
};

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
  const profiles = await getPlayerDnaData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <PlayerDnaClient initialProfiles={profiles} />
    </div>
  );
}
