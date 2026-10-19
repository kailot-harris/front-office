import fs from 'fs';
import path from 'path';
import { CbaLeagueOverview } from '@/lib/cbaTypes';
import { CapSheetClient } from '@/components/CapSheetClient';

export const metadata = {
  title: 'CBA Cap Sheet, Apron & Luxury Tax Architect | NBA Analytics',
  description: 'Analysis of NBA salary cap, luxury tax brackets, repeater surcharges, and second apron trade restrictions.',
};

function getCbaData(): CbaLeagueOverview {
  const filePath = path.join(process.cwd(), 'public', 'data', 'cba_cap_sheet.json');
  if (!fs.existsSync(filePath)) {
    return {
      season: '2026-2027',
      salaryCap: 140.6,
      luxuryTaxThreshold: 170.8,
      firstApron: 178.1,
      secondApron: 188.9,
      averagePayroll: 0,
      totalLeagueTaxRevenue: 0,
      secondApronTeamCount: 0,
      firstApronTeamCount: 0,
      taxTeamCount: 0,
      capRoomTeamCount: 0,
      teams: [],
    };
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as CbaLeagueOverview;
  } catch (err) {
    console.error('Failed to load cba_cap_sheet.json:', err);
    return {
      season: '2026-2027',
      salaryCap: 140.6,
      luxuryTaxThreshold: 170.8,
      firstApron: 178.1,
      secondApron: 188.9,
      averagePayroll: 0,
      totalLeagueTaxRevenue: 0,
      secondApronTeamCount: 0,
      firstApronTeamCount: 0,
      taxTeamCount: 0,
      capRoomTeamCount: 0,
      teams: [],
    };
  }
}

export default function CapSheetPage() {
  const cbaData = getCbaData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CapSheetClient initialData={cbaData} />
    </div>
  );
}
