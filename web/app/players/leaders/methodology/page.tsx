import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { LeaderMethodology } from '@/components/LeaderMethodology';
import type { LeaderMethodologyPayload } from '@/lib/leaderMethodologyTypes';

async function getLeaderMethodology(): Promise<LeaderMethodologyPayload | null> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'leader_methodology.json');
    return JSON.parse(await fs.readFile(filePath, 'utf8')) as LeaderMethodologyPayload;
  } catch (error) {
    console.error('Error reading leader_methodology.json:', error);
    return null;
  }
}

export const metadata = {
  title: 'League Leaders Methodology | NBA Quantitative Analytics',
  description:
    'How qualifying minimums for the NBA League Leaders panel were set from the split-half and rest-of-season reliability study.',
};

export default async function LeaderMethodologyPage() {
  const data = await getLeaderMethodology();
  return (
    <div className="container mx-auto max-w-7xl space-y-6 px-4 py-8">
      {data ? (
        <LeaderMethodology data={data} />
      ) : (
        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-slate-100">League Leaders Methodology: Qualifying Minimums</h1>
          <p className="text-sm text-slate-400">The leader methodology data is unavailable right now.</p>
        </div>
      )}
    </div>
  );
}
