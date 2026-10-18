import { getPostseasonOpsData } from '@/lib/data';
import { PostseasonOpsClient } from '@/components/PostseasonOpsClient';

export default function PostseasonPage() {
  const data = getPostseasonOpsData();

  return (
    <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8 space-y-6">
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 border-b border-slate-800 pb-6">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-white flex items-center gap-3">
            <span>Postseason Bracket, Bullpen & Market Edge</span>
            <span className="text-sm font-semibold px-2.5 py-0.5 rounded-full bg-amber-500/10 text-amber-400 border border-amber-500/20">
              10,000 Bracket Sims
            </span>
          </h1>
          <p className="text-slate-400 text-sm mt-1">
            12-team MLB Postseason Monte Carlo advancement probabilities (WC/DS/LCS/WS), 30-club bullpen workload diagnostics, and devigged +EV Kelly betting telemetry.
          </p>
        </div>
      </div>

      <PostseasonOpsClient data={data} />
    </div>
  );
}
