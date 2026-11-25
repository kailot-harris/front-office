import React from 'react';
import { getMomentumBoard } from '@/lib/data';
import { MomentumClient } from '@/components/MomentumClient';

export const metadata = {
  title: 'Momentum Board',
  description:
    'Which NFL teams are playing better or worse lately: opponent-adjusted form over the last 3, 6 or 9 games, trend, results against the Elo expectation and Elo change. Recent play, not a forecast.',
};

export default function MomentumPage() {
  const data = getMomentumBoard();
  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
      <MomentumClient data={data} />
    </div>
  );
}
