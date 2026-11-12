import { Metadata } from 'next';
import { getDiagnostics, getMetadata } from '@/lib/data';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { GlossaryTerm } from '@/components/GlossaryTerm';
import { HowToRead } from '@/components/HowToRead';

export const metadata: Metadata = {
  title: 'Modeling Analysis & Diagnostics',
  description:
    'Calibration and accuracy diagnostics for the WNBA projection model: backtests, residuals, and prediction-interval coverage.',
};

export default function DiagnosticsPage() {
  const diagnostics = getDiagnostics();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="relative pb-6">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
              <span>
                <span className="text-accent-400">WNBA</span> Modeling Analysis & Diagnostics
              </span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                Calibration & Accuracy
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Empirical reliability curves, Brier score, accuracy drift over time, and residual distributions from historical evaluations.
            </p>
            <div className="mt-2">
              <HowToRead pageKey="diagnostics">
                This page scores the model against what actually happened, not against itself.
                The calibration curve bins every historical forecast by predicted win probability
                and checks whether that bucket of games was actually won that often — a bucket far
                off the diagonal means the model is over- or under-confident there.{' '}
                <GlossaryTerm termKey="brierScore" /> and <GlossaryTerm termKey="logLoss" /> are two
                different penalties for the same miscalibration, and <GlossaryTerm termKey="hca" />{' '}
                rate is the empirical share of home teams that actually won, for comparison against
                the fixed HCA constant used in the projections.
              </HowToRead>
            </div>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />
    </div>
  );
}
