import { getDiagnostics, getMetadata } from '@/lib/data';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';
import { SeasonSourceBadge } from '@/components/SeasonSourceBadge';
import { SEASON_SOURCES } from '@/lib/season';

export default function DiagnosticsPage() {
  const diagnostics = getDiagnostics();
  const metadata = getMetadata();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Modeling Analysis & Diagnostics</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
              Calibration & Accuracy
            </span>
            <SeasonSourceBadge
              season={SEASON_SOURCES.diagnostics.season}
              kind="backtest"
              label="Backtest"
              title={SEASON_SOURCES.diagnostics.note}
            />
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            Empirical reliability curves, Brier score, accuracy drift over time, and residual distributions from historical evaluations.
          </p>
        </div>
      </div>

      <DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />
    </div>
  );
}
