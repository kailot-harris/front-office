import React from 'react';
import Link from 'next/link';
import { getMomentumMethodology } from '@/lib/data';
import { MomentumMethodology } from '@/components/MomentumMethodology';

export const metadata = {
  title: 'Momentum Board Methodology',
  description:
    'How the NFL Momentum Board is built and everything the two studies behind it tested: window lengths, carry-over, score weights, luck checks and availability.',
};

export default function MomentumMethodologyPage() {
  const data = getMomentumMethodology();
  return (
    <div className="max-w-5xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      {data ? (
        <MomentumMethodology data={data} />
      ) : (
        <div className="space-y-4">
          <h1 className="text-2xl font-bold text-slate-100">Momentum Board methodology</h1>
          <p className="text-sm text-slate-400">The methodology data is unavailable right now.</p>
          <Link href="/momentum" className="text-sm text-accent-400 underline underline-offset-2">
            Back to the Momentum Board
          </Link>
        </div>
      )}
    </div>
  );
}
