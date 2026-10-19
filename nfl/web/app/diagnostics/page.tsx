import { getDiagnosticsData } from '@/lib/data';
import DiagnosticsClient from '@/components/DiagnosticsClient';

export const metadata = {
  title: 'Model Diagnostics & Calibration | NFL Analytics',
  description: 'Out-of-sample Brier score trajectories, calibration curves, and statistical loss tracking.',
};

export default function DiagnosticsPage() {
  const data = getDiagnosticsData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <DiagnosticsClient data={data} />
    </div>
  );
}
