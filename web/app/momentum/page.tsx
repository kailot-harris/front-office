import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { MomentumClient } from '@/components/MomentumClient';
import type { MomentumPayload } from '@/lib/momentumTypes';

async function getMomentum(): Promise<MomentumPayload | null> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'momentum_board.json');
    return JSON.parse(await fs.readFile(filePath, 'utf8')) as MomentumPayload;
  } catch (error) {
    console.error('Error reading momentum_board.json:', error);
    return null;
  }
}

export const metadata = {
  title: 'Momentum Board | NBA Quantitative Analytics',
  description:
    'Which NBA teams are trending up or down: recent form against opponents faced, net rating trend, Elo change and results against model expectation.',
};

export default async function MomentumPage() {
  const data = await getMomentum();
  return (
    <div className="container mx-auto px-4 py-8 max-w-7xl">
      <MomentumClient data={data} />
    </div>
  );
}
