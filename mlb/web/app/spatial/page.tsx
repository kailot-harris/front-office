import { getSpatialData } from '@/lib/data';
import { SpatialAnalyticsClient } from '@/components/SpatialAnalyticsClient';

export const metadata = {
  title: 'Spatial Analytics & Statcast Tracking | MLB Analytics',
  description:
    'Trajectory modeling across 30-ballpark spray dimensions, 3x3 strike zone framing heatmaps, pitch movement (IVB vs HB), and shift defense penalties.',
};

export default function SpatialPage() {
  const spatialData = getSpatialData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <SpatialAnalyticsClient data={spatialData} />
    </div>
  );
}
