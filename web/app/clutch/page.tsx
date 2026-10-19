import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { ClutchProfile } from '@/lib/clutchTypes';
import { ClutchClient } from '@/components/ClutchClient';

export const metadata: Metadata = {
  title: 'True Clutch Index & Leverage | WNBA Analytics',
  description:
    'High-leverage execution analysis, unassisted shot creation index (USCI), turnover fragility, and defensive win probability added in tight contests.',
};

async function getClutchData(): Promise<ClutchProfile[]> {
  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const filePath = path.join(dataDir, 'clutch_leverage_metrics.json');

    if (!fs.existsSync(filePath)) {
      return [];
    }

    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error('Failed to load clutch leverage metrics:', err);
    return [];
  }
}

export default async function ClutchPage() {
  const profiles = await getClutchData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <ClutchClient initialProfiles={profiles} />
    </div>
  );
}
