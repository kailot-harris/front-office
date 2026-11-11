import { Metadata } from 'next';
import { getDiagnostics, getMetadata } from '@/lib/data';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { HowToRead } from '@/components/HowToRead';
import { GlossaryTerm } from '@/components/Glossary';

export const metadata: Metadata = {
  title: 'Walk-Forward Calibration & Diagnostics',
  description:
    'Empirical reliability curves, walk-forward Brier score, Early/Mid/Late season progression drift, and residual distributions.',
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
              <span><span className="text-sky-400">MLB</span> Walk-Forward Calibration & Diagnostics</span>
              <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                {diagnostics.calibrationStatus ?? 'OPTIMAL'}
              </span>
            </h1>
            <p className="text-slate-400 text-sm mt-1">
              Empirical reliability curves, walk-forward <GlossaryTerm term="Brier Score" /> score, Early/Mid/Late season progression drift, and residual distributions from tools/evaluate_season_calibration.R.
            </p>
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-sky-400 via-sky-500/40 to-transparent" />
        <div className="max-w-xl mt-4">
          <HowToRead pageKey="diagnostics">
            These charts back-test the model against actual outcomes it never saw during
            training. A perfectly calibrated model has predicted probabilities that line up
            with real win rates, and a lower <GlossaryTerm term="Brier Score" /> means more
            accurate forecasts.
          </HowToRead>
        </div>
      </div>

      <DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />
    </div>
  );
}
