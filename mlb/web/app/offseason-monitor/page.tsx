import { Metadata } from 'next';
import { getOffseasonMonitorData } from '@/lib/offseasonData';
import { OffseasonMonitorClient } from '@/components/OffseasonMonitorClient';

export const metadata: Metadata = {
  title: '2026-2027 Off-Season Dynamics Monitor | MLB Analytics',
  description:
    'Weekly state-diff intelligence engine tracking 40-man roster moves, free agent signings, CBT luxury tax commitments, and 2027 Marcel baseline priors.',
};

export default function OffseasonMonitorPage() {
  const dataset = getOffseasonMonitorData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <OffseasonMonitorClient initialDataset={dataset} />
    </div>
  );
}
