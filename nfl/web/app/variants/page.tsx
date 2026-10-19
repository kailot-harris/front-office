import { getDiagnosticsData } from '@/lib/data';
import VariantsClient from '@/components/VariantsClient';

export const metadata = {
  title: 'Model Variants & Architecture | NFL Analytics',
  description: 'Ridge Massey, Dynamic Elo, and Market Blend ensemble weighting and divergence analysis.',
};

export default function VariantsPage() {
  const data = getDiagnosticsData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <VariantsClient data={data} />
    </div>
  );
}
