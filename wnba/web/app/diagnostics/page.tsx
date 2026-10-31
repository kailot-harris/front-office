import { getDiagnostics, getMetadata } from '@/lib/data';
import { DiagnosticsClient } from '@/components/DiagnosticsClient';

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
          </div>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-violet-400 via-violet-500/40 to-transparent" />
      </div>

      <DiagnosticsClient diagnostics={diagnostics} metadata={metadata} />
    </div>
  );
}
