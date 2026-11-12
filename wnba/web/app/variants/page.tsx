import { Metadata } from 'next';
import { getTeamsData, getMetadata } from '@/lib/data';
import { VariantsClient } from '@/components/VariantsClient';
import { GlossaryTerm } from '@/components/GlossaryTerm';
import { HowToRead } from '@/components/HowToRead';

export const metadata: Metadata = {
  title: 'Model Variants Breakout',
  description:
    'Compare the 4 underlying WNBA projection model variants and the ensemble blend across projected wins and playoff/title probabilities.',
};

export default function VariantsPage() {
  const teams = getTeamsData();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-accent-400">WNBA</span> Model Variants Breakout
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                4 Variants + Ensemble
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Compare 1,000-season predictions across Production Bottom-Up BPM, Bayesian RAPM, Shot Quality & Fatigue, and 16-D Embeddings.
            </p>
            <div className="mt-2">
              <HowToRead pageKey="variants">
                The Ensemble is not a fifth independent model — it is a fixed-weight blend of the
                other four (35% Bottom-Up BPM, 25% Bayesian{' '}
                <GlossaryTerm termKey="rapm" />, 20% Shot Quality/Fatigue, 20% Embeddings), so it
                will usually track closer to the historical outcome than any single variant.
                Compare variants by <GlossaryTerm termKey="brierScore" /> to see which one&apos;s
                probabilities were best calibrated historically, not just which picked the most
                winners.
              </HowToRead>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <VariantsClient teams={teams} metadata={metadata} />
    </div>
  );
}
