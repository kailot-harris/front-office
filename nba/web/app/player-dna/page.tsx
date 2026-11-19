import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { PlayerDnaProfile } from '@/lib/playerDnaTypes';
import { PlayerDnaClient } from '@/components/PlayerDnaClient';
import { RapmSeasonWindow, splitSeasonPayload } from '@/lib/seasonWindow';

async function getPlayerDnaProfiles(): Promise<{ profiles: PlayerDnaProfile[]; seasonWindow: RapmSeasonWindow | null }> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'player_dna_profiles.json');
    const fileContents = await fs.readFile(filePath, 'utf8');
    return splitSeasonPayload<PlayerDnaProfile, RapmSeasonWindow>(JSON.parse(fileContents));
  } catch (error) {
    console.error('Error reading player_dna_profiles.json:', error);
    return { profiles: [], seasonWindow: null };
  }
}

export const metadata = {
  title: 'Player DNA & Peer Comps | NBA Quantitative Analytics',
  description: '15-Dimensional player skill vectors, archetypes, and nearest current-season comparables from the same season.',
};

export default async function PlayerDnaPage() {
  const { profiles, seasonWindow } = await getPlayerDnaProfiles();

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <PlayerDnaClient initialProfiles={profiles} seasonWindow={seasonWindow} />
    </div>
  );
}
