import { Metadata } from 'next';
import { getClutchData } from '@/lib/data';
import ClutchClient from '@/components/ClutchClient';

export const metadata: Metadata = {
  title: 'True Clutch Index & Leverage',
  description:
    '4th Quarter and overtime high-leverage execution, clutch EPA/play vs baseline, situational CPOE, turnover fragility under pressure, and 4th-down decision making.',
};

export default function ClutchPage() {
  const clutchProfiles = getClutchData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <ClutchClient initialProfiles={clutchProfiles} />
    </div>
  );
}
