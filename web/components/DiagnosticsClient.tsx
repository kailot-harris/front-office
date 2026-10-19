'use client';

import { DiagnosticsDataset } from '@/lib/types';
import CalibrationCurve from './CalibrationCurve';
import { ShieldCheck, Target, Activity, BarChart2 } from 'lucide-react';

interface DiagnosticsClientProps {
  data: DiagnosticsDataset;
}

export default function DiagnosticsClient({ data }: DiagnosticsClientProps) {
  // Extract latest point from metrics arrays
  const getLatest = <T,>(val: T | T[]): T => {
    if (Array.isArray(val)) {
      return val[val.length - 1];
    }
    return val;
  };

  const latestAccuracy = getLatest(data.overall_accuracy);
  const latestBrier = getLatest(data.overall_brier);
  const latestLogLoss = getLatest(data.overall_logloss);
  const latestGames = getLatest(data.n_games_graded);
  const latestImprovement = getLatest(data.brier_improvement);

  // Trajectory history
  const historyGames = Array.isArray(data.n_games_graded) ? data.n_games_graded : [data.n_games_graded];
  const historyAccuracy = Array.isArray(data.overall_accuracy) ? data.overall_accuracy : [data.overall_accuracy];
  const historyBrier = Array.isArray(data.overall_brier) ? data.overall_brier : [data.overall_brier];
  const historyLogLoss = Array.isArray(data.overall_logloss) ? data.overall_logloss : [data.overall_logloss];

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
            Phase 8: Model Diagnostics & Calibration
          </span>
          <span className="text-xs font-mono text-slate-400">
            {latestGames} Games Graded Out-of-Sample
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
          Model Calibration, Brier Trajectory & Diagnostics
        </h1>
        <p className="text-slate-400 text-sm mt-1 max-w-3xl">
          Multi-decile probability reliability curves, out-of-sample Brier score trajectories,
          and statistical loss metrics evaluated continuously against consensus market baselines.
        </p>
      </div>

      {/* KPI Stats Grid */}
      <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
        {/* Straight-up Accuracy */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Straight-Up Accuracy</span>
            <Target className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-white">
            {Number(latestAccuracy).toFixed(1)}%
          </div>
          <p className="text-[11px] text-slate-400 mt-1">
            Over {latestGames} graded regular-season games
          </p>
        </div>

        {/* Brier Score */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Ensemble Brier Score</span>
            <ShieldCheck className="w-4 h-4 text-cyan-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-cyan-400">
            {Number(latestBrier).toFixed(4)}
          </div>
          <p className="text-[11px] text-emerald-400 font-mono mt-1">
            +{Number(latestImprovement).toFixed(2)}% vs uninformative (0.250)
          </p>
        </div>

        {/* Log Loss */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Cross-Entropy Log Loss</span>
            <Activity className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-indigo-400">
            {Number(latestLogLoss).toFixed(4)}
          </div>
          <p className="text-[11px] text-slate-400 mt-1">
            Penalizes overconfident misclassifications
          </p>
        </div>

        {/* Margin Sigma */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-lg">
          <div className="flex items-center justify-between text-slate-400 pb-2">
            <span className="text-xs font-medium">Margin Sigma (σ)</span>
            <BarChart2 className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-2xl font-bold font-mono text-amber-400">
            {data.margin_sigma.toFixed(1)} pts
          </div>
          <p className="text-[11px] text-slate-400 mt-1">
            HFA parameter: +{data.home_field_adv.toFixed(2)} pts
          </p>
        </div>
      </div>

      {/* Main Calibration Chart & Deciles Breakdown */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2">
          <CalibrationCurve bins={data.calibration_curve} />
        </div>

        {/* Calibration Decile Table */}
        <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-4 shadow-xl flex flex-col justify-between">
          <div>
            <h3 className="text-sm font-semibold text-white mb-2">Decile Probability Breakdown</h3>
            <p className="text-xs text-slate-400 mb-3">
              Sample count and realized win rate per 10% probability bucket.
            </p>

            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs font-mono">
                <thead className="bg-slate-950/80 text-slate-400 uppercase text-[10px] tracking-wider border-b border-slate-800">
                  <tr>
                    <th className="px-2 py-2">Bin</th>
                    <th className="px-2 py-2 text-right">Pred</th>
                    <th className="px-2 py-2 text-right">Actual</th>
                    <th className="px-2 py-2 text-right">Count</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-800/60">
                  {data.calibration_curve.map((bin) => {
                    const diff = bin.actual_win_rate - bin.predicted_mid;
                    return (
                      <tr key={bin.bin} className="hover:bg-slate-800/40">
                        <td className="px-2 py-1.5 text-slate-300">{bin.bin}</td>
                        <td className="px-2 py-1.5 text-right text-slate-400">
                          {(bin.predicted_mid * 100).toFixed(0)}%
                        </td>
                        <td className="px-2 py-1.5 text-right font-semibold">
                          <span
                            className={
                              Math.abs(diff) < 0.05
                                ? 'text-emerald-400'
                                : Math.abs(diff) < 0.1
                                ? 'text-amber-400'
                                : 'text-rose-400'
                            }
                          >
                            {(bin.actual_win_rate * 100).toFixed(1)}%
                          </span>
                        </td>
                        <td className="px-2 py-1.5 text-right text-slate-400">{bin.count}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>

          <div className="pt-3 border-t border-slate-800 text-[11px] text-slate-400">
            Total Evaluated Samples: {data.calibration_curve.reduce((s, b) => s + b.count, 0)} predictions
          </div>
        </div>
      </div>

      {/* Accuracy & Loss Trajectory History */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-xl">
        <div className="pb-3 border-b border-slate-800 mb-4 flex items-center justify-between">
          <div>
            <h3 className="text-base font-semibold text-white">
              Weekly Accuracy & Loss Trajectory
            </h3>
            <p className="text-xs text-slate-400">
              Progression of model diagnostics across evaluation cycles in the 2026 season.
            </p>
          </div>
          <span className="text-xs font-mono text-emerald-400 bg-slate-950 px-2.5 py-1 rounded border border-slate-800">
            {historyGames.length} Evaluation Checkpoints
          </span>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs font-mono">
            <thead className="bg-slate-950/80 text-slate-400 uppercase text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="px-3 py-2.5">Evaluation Cycle</th>
                <th className="px-3 py-2.5 text-right">Games Graded</th>
                <th className="px-3 py-2.5 text-right">SU Accuracy</th>
                <th className="px-3 py-2.5 text-right">Brier Score</th>
                <th className="px-3 py-2.5 text-right">Brier Edge</th>
                <th className="px-3 py-2.5 text-right">Log Loss</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              {historyGames.map((games, idx) => (
                <tr key={idx} className="hover:bg-slate-800/40">
                  <td className="px-3 py-2 text-slate-300">
                    Cycle #{idx + 1}
                  </td>
                  <td className="px-3 py-2 text-right text-slate-400 font-semibold">{games}</td>
                  <td className="px-3 py-2 text-right text-emerald-400 font-semibold">
                    {historyAccuracy[idx]?.toFixed(1)}%
                  </td>
                  <td className="px-3 py-2 text-right text-cyan-400 font-semibold">
                    {historyBrier[idx]?.toFixed(4)}
                  </td>
                  <td className="px-3 py-2 text-right text-emerald-400">
                    +{((0.25 - (historyBrier[idx] ?? 0.25)) / 0.25 * 100).toFixed(2)}%
                  </td>
                  <td className="px-3 py-2 text-right text-indigo-400">
                    {historyLogLoss[idx]?.toFixed(4)}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
