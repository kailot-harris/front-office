import { Metadata } from 'next';
import { getTeamsData, getMetadata } from '@/lib/data';
import { VariantsClient } from '@/components/VariantsClient';
import { HowToRead } from '@/components/HowToRead';
import { GlossaryTerm } from '@/components/Glossary';

export const metadata: Metadata = {
  title: 'Sabermetric Model Variants Breakout',
  description:
    'Compare 162-game Monte Carlo projections across 4-Factor Starting-Pitcher Elo, Hierarchical Empirical Bayes Talent, Pythagenpat Run-Expectation, and Marcel/Bullpen Fatigue.',
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
              <span><span className="text-sky-400">MLB</span> Sabermetric Model Variants Breakout</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-indigo-500/10 text-indigo-400 border border-indigo-500/20">
                4 Engines + Ensemble
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Compare 162-game Monte Carlo projections across 4-Factor Starting-Pitcher <GlossaryTerm term="Elo" />, Hierarchical <GlossaryTerm term="Empirical Bayes" /> Talent, <GlossaryTerm term="Pythagenpat" /> Run-Expectation, and <GlossaryTerm term="Marcel Projection">Marcel</GlossaryTerm>/Bullpen Fatigue.
            </p>
            <div className="max-w-xl mt-4">
              <HowToRead pageKey="variants">
                The site&apos;s headline projections are an ensemble blend of four independent
                models. This page shows what each model says on its own — <GlossaryTerm term="Elo" /> (built
                from <GlossaryTerm term="rGS" /> and results), <GlossaryTerm term="Empirical Bayes" /> (pooled{' '}
                <GlossaryTerm term="wOBA" />/<GlossaryTerm term="xFIP" /> talent), <GlossaryTerm term="Pythagenpat" /> (run differential), and{' '}
                <GlossaryTerm term="Marcel Projection">Marcel</GlossaryTerm>/Bullpen (recent-weighted rates) — so you can see where
                the models agree and where one is driving a team&apos;s projection.
              </HowToRead>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
      </div>

      <VariantsClient teams={teams} metadata={metadata} />
    </div>
  );
}
