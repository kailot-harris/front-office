import { getPassingIndex, getPassingMetadata } from '@/lib/data';
import PassingExplorerClient from '@/components/PassingExplorerClient';
import { GlossaryTerm } from '@/components/Glossary';
import { HowToRead } from '@/components/HowToRead';

export const metadata = {
  title: 'QB Passing Charts & Throw Maps',
  description:
    'Interactive NextGenStats-style QB passing charts, depth sectors, CPOE, and EPA/pass throw distribution grounded in empirical play-by-play tracking.',
};

export default function PassingPage() {
  const catalog = getPassingIndex();
  const metadata = getPassingMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6 border-b border-slate-800/80">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex flex-wrap items-center gap-3 font-space">
              <span>
                <span className="text-emerald-400">NFL</span> NextGenStats QB Passing Charts & Throw Maps
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20 font-sans">
                Empirical PBP Tracking
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Interactive spatial throw charts: 12 discrete depth and horizontal sectors, rolling{' '}
              <GlossaryTerm term="CPOE" className="text-slate-300" /> baselines, and empirical{' '}
              <GlossaryTerm term="EPA" className="text-slate-300" /> per pass attempt.
            </p>
          </div>
        </div>
      </div>

      <HowToRead pageKey="passing">
        <p>
          Each throw is bucketed into one of <strong>12 depth/direction sectors</strong> (short/medium/deep,
          left/middle/right), so the chart shows where on the field a QB actually throws rather than just a season
          total. <GlossaryTerm term="CPOE" className="text-slate-300" /> compares a QB&apos;s completion rate in
          each sector to what an average QB would complete given the same depth and difficulty, isolating accuracy
          from scheme. <GlossaryTerm term="EPA" className="text-slate-300" /> per attempt shows how much those
          throws were actually worth in points, not just whether they were caught.
        </p>
      </HowToRead>

      <PassingExplorerClient catalog={catalog} metadata={metadata} />
    </div>
  );
}
