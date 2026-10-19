import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { ClutchProfile } from '@/lib/clutchTypes';
import { ClutchClient } from '@/components/ClutchClient';

async function getClutchProfiles(): Promise<ClutchProfile[]> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'clutch_leverage_metrics.json');
    const fileContents = await fs.readFile(filePath, 'utf8');
    return JSON.parse(fileContents);
  } catch (error) {
    console.error('Error reading clutch_leverage_metrics.json:', error);
    return [];
  }
}

export const metadata = {
  title: 'True Clutch & Leverage Creation Index | NBA Quantitative Analytics',
  description: 'Unassisted Shot Creation Index (USCI), clutch True Shooting %, and late-game win probability added.',
};

export default async function ClutchPage() {
  const profiles = await getClutchProfiles();

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <ClutchClient initialProfiles={profiles} />
    </div>
  );
}
