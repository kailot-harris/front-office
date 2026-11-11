import { Metadata } from 'next';
import { getOffseasonMonitorData } from '@/lib/data';
import { OffseasonMonitorClient } from '@/components/OffseasonMonitorClient';

export const metadata: Metadata = {
  title: '2026-2027 Off-Season Dynamics Monitor',
  description:
    'Weekly state-diff intelligence engine tracking confirmed transactions, reported rumors, CBA hard cap metrics, and 2027 model baseline priors.',
};

export default function OffseasonMonitorPage() {
  const dataset = getOffseasonMonitorData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <OffseasonMonitorClient initialDataset={dataset} />
    </div>
  );
}
