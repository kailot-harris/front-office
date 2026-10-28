import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { WnbaCbaLeagueOverview } from '@/lib/cbaTypes';
import { CapSheetClient } from '@/components/CapSheetClient';

export const metadata: Metadata = {
  title: 'CBA Salary Cap & Roster Crunch Architect | WNBA Analytics',
  description:
    'Analysis of the 2026 WNBA hard salary cap ($1.520M), team salary floor, supermax player tags, and the 11-vs-12 roster spot crunch.',
};

async function getCbaData(): Promise<WnbaCbaLeagueOverview> {
  const defaultOverview: WnbaCbaLeagueOverview = {
    generated_at: new Date().toISOString(),
    season: '2026',
    hardSalaryCap: 1.52,
    capFloor: 1.368,
    supermaxSalary: 0.2492,
    vetMaxSalary: 0.2153,
    vetMinSalary: 0.0788,
    rookieMinSalary: 0.0672,
    averagePayroll: 1.46,
    hardCapSqueezeTeamCount: 8,
    twelvePlayerTeamCount: 7,
    maxCapSpaceTeamCount: 1,
    teams: [],
  };

  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const filePath = path.join(dataDir, 'cba_cap_sheet.json');

    if (!fs.existsSync(filePath)) {
      return defaultOverview;
    }

    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error('Failed to load cba_cap_sheet.json:', err);
    return defaultOverview;
  }
}

export default async function CapSheetPage() {
  const cbaData = await getCbaData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CapSheetClient initialData={cbaData} />
    </div>
  );
}
