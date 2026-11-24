import React from 'react';
import { promises as fs } from 'fs';
import path from 'path';
import { MomentumMethodology } from '@/components/MomentumMethodology';
import type { MomentumMethodologyPayload } from '@/lib/momentumMethodologyTypes';

async function getMethodology(): Promise<MomentumMethodologyPayload | null> {
  try {
    const filePath = path.join(process.cwd(), 'public', 'data', 'momentum_methodology.json');
    return JSON.parse(await fs.readFile(filePath, 'utf8')) as MomentumMethodologyPayload;
  } catch (error) {
    console.error('Error reading momentum_methodology.json:', error);
    return null;
  }
}

export const metadata = {
  title: 'Momentum Board Methodology | NBA Quantitative Analytics',
  description:
    'How the NBA Momentum Board was tested: every momentum measure tried, kept or discarded, the validation protocol and the blend-weights result, read from the study results file.',
};

export default async function MomentumMethodologyPage() {
  const data = await getMethodology();
  return (
    <div className="container mx-auto max-w-7xl space-y-6 px-4 py-8">
      {data ? (
        <MomentumMethodology data={data} />
      ) : (
        <div className="space-y-2">
          <h1 className="text-2xl font-bold text-slate-100">Momentum Board: methodology and everything we tested</h1>
          <p className="text-sm text-slate-400">The study results are unavailable right now.</p>
        </div>
      )}
    </div>
  );
}
