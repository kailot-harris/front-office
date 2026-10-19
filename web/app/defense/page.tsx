import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { DefensiveProfile } from '@/lib/defenseTypes';
import { DefenseClient } from '@/components/DefenseClient';

async function getDefensiveProfiles(): Promise<DefensiveProfile[]> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'defensive_metrics.json');
    const fileContents = await fs.readFile(filePath, 'utf8');
    return JSON.parse(fileContents);
  } catch (error) {
    console.error('Error reading defensive_metrics.json:', error);
    return [];
  }
}

export const metadata = {
  title: 'Defensive Versatility & Coverage Matrix | NBA Quantitative Analytics',
  description: 'Shannon entropy positional versatility, rim deterrence residuals, and screen navigation metrics.',
};

export default async function DefensePage() {
  const profiles = await getDefensiveProfiles();

  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <DefenseClient initialProfiles={profiles} />
    </div>
  );
}
