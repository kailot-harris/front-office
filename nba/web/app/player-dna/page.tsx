import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';

async function getPlayerDnaProfiles(): Promise<PlayerDnaProfile[]> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'player_dna_profiles.json');
    const fileContents = await fs.readFile(filePath, 'utf8');
    return JSON.parse(fileContents);
  } catch (error) {
    console.error('Error reading player_dna_profiles.json:', error);
    return [];
  }
}

export const metadata = {
  title: 'Player DNA & Historical Twins | NBA Quantitative Analytics',
  description: '16-Dimensional player skill vectors, archetypes, and nearest historical comparables.',
};

export default async function PlayerDnaPage() {
  const profiles = await getPlayerDnaProfiles();

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <PlayerDnaClient initialProfiles={profiles} />
    </div>
  );
}
