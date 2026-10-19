import { getCoachingProfiles } from '@/lib/data';
import CoachingClient from '@/components/CoachingClient';

export const metadata = {
  title: 'Coaching Analysis & Decision Matrix | NFL Analytics',
  description: 'Head coach 4th-down aggression percentiles, pass rate over expected, pace of play, and staff scheme profiles.',
};

export default function CoachingPage() {
  const coaches = getCoachingProfiles();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <CoachingClient initialCoaches={coaches} />
    </div>
  );
}
