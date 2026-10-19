import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { DefensiveProfile } from '@/lib/defenseTypes';
import { DefenseClient } from '@/components/DefenseClient';

export const metadata: Metadata = {
  title: 'Defensive Versatility & Matchup Matrix | WNBA Analytics',
  description:
    'Evaluate WNBA defensive versatility (Shannon Entropy), rim contest field goal suppression, and positional matchup tracking shares across 15 franchises.',
};

async function getDefenseData(): Promise<DefensiveProfile[]> {
  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const filePath = path.join(dataDir, 'defensive_metrics.json');

    if (!fs.existsSync(filePath)) {
      return [];
    }

    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error('Failed to load defensive metrics:', err);
    return [];
  }
}

export default async function DefensePage() {
  const profiles = await getDefenseData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <DefenseClient initialProfiles={profiles} />
    </div>
  );
}
