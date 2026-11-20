import { getCoachingProfiles } from '@/lib/data';
import CoachingClient from '@/components/CoachingClient';

export const metadata = {
  title: 'Coaching Analysis & Decision Matrix',
  description:
    'Measured head coach decision tendencies from nflverse data: 4th-down go rate, nfl4th model comparisons, pass rate over expected, play-action rate, pace, challenges and timeouts.',
};

export default function CoachingPage() {
  const data = getCoachingProfiles();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CoachingClient data={data} />
    </div>
  );
}
