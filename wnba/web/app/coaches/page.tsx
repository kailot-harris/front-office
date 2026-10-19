import React from 'react';
import { Metadata } from 'next';
import fs from 'fs';
import path from 'path';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { CoachesClient } from '@/components/CoachesClient';

export const metadata: Metadata = {
  title: 'Coaching Staffs & Tactical Impact | WNBA Analytics',
  description:
    'Evaluate 15 WNBA coaching staffs across ATO execution, in-game challenge leverage, rotational staggering, and system win lift.',
};

async function getCoachingData(): Promise<CoachingStaffMetric[]> {
  try {
    const dataDir = path.join(process.cwd(), 'public', 'data');
    const filePath = path.join(dataDir, 'coaching_metrics.json');

    if (!fs.existsSync(filePath)) {
      return [];
    }

    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (err) {
    console.error('Failed to load coaching metrics data:', err);
    return [];
  }
}

export default async function CoachesPage() {
  const coaches = await getCoachingData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CoachesClient initialData={coaches} />
    </div>
  );
}
