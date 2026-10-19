import fs from 'fs';
import path from 'path';
import { CoachingStaffMetric } from '@/lib/coachingTypes';
import { CoachesClient } from '@/components/CoachesClient';

export const metadata = {
  title: 'Coaching Staffs & Tactical Impact | NBA Analytics',
  description: 'Analysis of NBA coaching staffs, ATO execution, challenge equity, and talent-adjusted impact ratings.',
};

function getCoachingMetrics(): CoachingStaffMetric[] {
  const filePath = path.join(process.cwd(), 'public', 'data', 'coaching_metrics.json');
  if (!fs.existsSync(filePath)) {
    return [];
  }
  try {
    const content = fs.readFileSync(filePath, 'utf-8');
    return JSON.parse(content) as CoachingStaffMetric[];
  } catch (err) {
    console.error('Failed to load coaching_metrics.json:', err);
    return [];
  }
}

export default function CoachesPage() {
  const coachingData = getCoachingMetrics();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CoachesClient initialData={coachingData} />
    </div>
  );
}
