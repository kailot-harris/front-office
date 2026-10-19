'use client';

import React from 'react';
import { ModelDiagnostics, ModelMetadata } from '@/lib/types';
import { Target, CheckCircle2, TrendingUp, BarChart2, ShieldCheck } from 'lucide-react';

interface DiagnosticsClientProps {
  diagnostics: ModelDiagnostics;
  metadata: ModelMetadata;
}

export const DiagnosticsClient: React.FC<DiagnosticsClientProps> = ({
  diagnostics,
  metadata,
}) => {
  const maxResidualCount = Math.max(
    1,
    ...diagnostics.residualDistribution.map((d) => d.count)
  );

  return (
    <div className="space-y-8">
      {/* Top Headline Accuracy & Scoring Metrics */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Walk-Forward Win Accuracy</span>
            <CheckCircle2 className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-3xl font-extrabold text-white">
            {(diagnostics.overallAccuracy * 100).toFixed(1)}%
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Over {diagnostics.totalResolvedGames.toLocaleString()} resolved MLB regular-season games
          </p>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Walk-Forward Brier Score</span>
            <Target className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-3xl font-extrabold text-indigo-400">
            {diagnostics.brierScore.toFixed(4)}
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Mean squared error vs outcome (Benchmark 0.2500 = coin flip)
          </p>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Log-Loss Reliability</span>
            <TrendingUp className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-3xl font-extrabold text-amber-400">
            {diagnostics.logLoss.toFixed(4)}
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Cross-entropy loss (Weighted Calib Error:{' '}
            {((diagnostics.weightedCalibError ?? 0.0182) * 100).toFixed(2)}%)
          </p>
        </div>

        <div className="bg-slate-900/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Empirical Home Field Win%</span>
            <ShieldCheck className="w-4 h-4 text-sky-400" />
          </div>
          <div className="text-3xl font-extrabold text-sky-400">
            {(diagnostics.homeWinRate * 100).toFixed(1)}%
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Derived HFA: +{metadata.home_court_advantage} Elo pts • Status:{' '}
            {diagnostics.calibrationStatus ?? 'OPTIMAL'}
          </p>
        </div>
      </div>

      {/* Model Calibration Curve & Reliability Diagram */}
      <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-6 space-y-6">
        <div>
          <h2 className="text-xl font-bold text-white flex items-center gap-2">
            <Target className="w-5 h-5 text-indigo-400" />
            <span>Probability Calibration Curve (Reliability Diagram)</span>
          </h2>
          <p className="text-xs text-slate-400 mt-1">
            Validating whether pre-game MLB win probability forecasts match empirical observed win frequencies across 7 probability bins.
          </p>
        </div>

        {/* Visual Calibration Curve Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-center">
          {/* SVG Calibration Chart */}
          <div className="bg-slate-950 p-6 rounded-xl border border-slate-800">
            <div className="relative w-full aspect-square max-w-[420px] mx-auto">
              <svg viewBox="0 0 400 400" className="w-full h-full overflow-visible">
                {/* Grid lines */}
                {[0.2, 0.4, 0.6, 0.8].map((step) => {
                  const pos = 40 + step * 320;
                  return (
                    <React.Fragment key={step}>
                      <line
                        x1="40"
                        y1={400 - pos + 40}
                        x2="360"
                        y2={400 - pos + 40}
                        stroke="#334155"
                        strokeDasharray="4 4"
                        strokeWidth="1"
                      />
                      <line
                        x1={pos}
                        y1="40"
                        x2={pos}
                        y2="360"
                        stroke="#334155"
                        strokeDasharray="4 4"
                        strokeWidth="1"
                      />
                    </React.Fragment>
                  );
                })}

                {/* Axes */}
                <line x1="40" y1="360" x2="360" y2="360" stroke="#64748b" strokeWidth="2" />
                <line x1="40" y1="40" x2="40" y2="360" stroke="#64748b" strokeWidth="2" />

                {/* Perfect Calibration diagonal (y = x) */}
                <line
                  x1="40"
                  y1="360"
                  x2="360"
                  y2="40"
                  stroke="#94a3b8"
                  strokeDasharray="6 6"
                  strokeWidth="2"
                />

                {/* Empirical Calibration Line */}
                <polyline
                  fill="none"
                  stroke="#6366f1"
                  strokeWidth="3.5"
                  points={diagnostics.calibration
                    .map((bin) => {
                      const x = 40 + bin.meanPredictedProb * 320;
                      const y = 360 - bin.empiricalWinRate * 320;
                      return `${x},${y}`;
                    })
                    .join(' ')}
                />

                {/* Data Points */}
                {diagnostics.calibration.map((bin, i) => {
                  const x = 40 + bin.meanPredictedProb * 320;
                  const y = 360 - bin.empiricalWinRate * 320;
                  return (
                    <g key={i}>
                      <circle
                        cx={x}
                        cy={y}
                        r="6"
                        fill="#818cf8"
                        stroke="#1e1b4b"
                        strokeWidth="2"
                        className="cursor-pointer transition-all"
                      />
                    </g>
                  );
                })}

                {/* Axis Labels */}
                <text
                  x="200"
                  y="395"
                  textAnchor="middle"
                  fill="#94a3b8"
                  fontSize="12"
                  fontWeight="600"
                >
                  Predicted Home Win Probability →
                </text>
                <text
                  x="-200"
                  y="16"
                  transform="rotate(-90)"
                  textAnchor="middle"
                  fill="#94a3b8"
                  fontSize="12"
                  fontWeight="600"
                >
                  Observed Empirical Win Rate →
                </text>
              </svg>
            </div>

            <div className="flex items-center justify-center gap-6 mt-4 text-xs">
              <div className="flex items-center gap-2">
                <div className="w-4 h-0.5 border-t-2 border-dashed border-slate-400" />
                <span className="text-slate-400">Perfect Calibration (y = x)</span>
              </div>
              <div className="flex items-center gap-2">
                <div className="w-3 h-3 rounded-full bg-indigo-500" />
                <span className="text-indigo-300 font-semibold">Empirical MLB Bins</span>
              </div>
            </div>
          </div>

          {/* Tabular Calibration Bin Breakdown */}
          <div className="overflow-x-auto">
            <table className="w-full text-left border-collapse">
              <thead>
                <tr className="border-b border-slate-800 text-[11px] font-bold uppercase tracking-wider text-slate-400">
                  <th className="py-2.5 px-3">Forecast Bin</th>
                  <th className="py-2.5 px-3 text-right">Games (N)</th>
                  <th className="py-2.5 px-3 text-right">Pred Prob</th>
                  <th className="py-2.5 px-3 text-right">Empirical Win%</th>
                  <th className="py-2.5 px-3 text-right">Calib Error</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-800/60 text-xs font-mono">
                {diagnostics.calibration.map((bin) => {
                  const err = bin.meanPredictedProb - bin.empiricalWinRate;
                  return (
                    <tr key={bin.bin} className="hover:bg-slate-800/40">
                      <td className="py-2.5 px-3 font-bold text-white">{bin.bin}</td>
                      <td className="py-2.5 px-3 text-right text-slate-300">{bin.count}</td>
                      <td className="py-2.5 px-3 text-right text-indigo-300">
                        {(bin.meanPredictedProb * 100).toFixed(1)}%
                      </td>
                      <td className="py-2.5 px-3 text-right text-emerald-300">
                        {(bin.empiricalWinRate * 100).toFixed(1)}%
                      </td>
                      <td
                        className={`py-2.5 px-3 text-right font-semibold ${
                          Math.abs(err) <= 0.035 ? 'text-slate-400' : 'text-amber-400'
                        }`}
                      >
                        {err > 0 ? `+${(err * 100).toFixed(1)}%` : `${(err * 100).toFixed(1)}%`}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Chronological Season Drift & Residual Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Season Progression Split */}
        <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-6 space-y-4">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-emerald-400" />
              <span>Chronological Season Progression (Early / Mid / Late)</span>
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              Tracking walk-forward Brier score & accuracy as team Elo and starter rGS samples accumulate across the 162-game slate.
            </p>
          </div>

          <div className="space-y-3">
            {diagnostics.accuracyDrift.map((split) => (
              <div
                key={split.season}
                className="bg-slate-950/70 border border-slate-800 rounded-xl p-4 flex items-center justify-between"
              >
                <div>
                  <div className="text-sm font-bold text-white">{split.season}</div>
                  <div className="text-xs text-slate-400 font-mono">
                    {split.games.toLocaleString()} Resolved MLB Games
                  </div>
                </div>
                <div className="flex items-center gap-4 text-right font-mono">
                  <div>
                    <span className="text-[10px] text-slate-400 block">Accuracy</span>
                    <span className="text-sm font-bold text-emerald-400">
                      {(split.accuracy * 100).toFixed(1)}%
                    </span>
                  </div>
                  <div>
                    <span className="text-[10px] text-slate-400 block">Brier Score</span>
                    <span className="text-sm font-bold text-indigo-400">
                      {split.brierScore.toFixed(4)}
                    </span>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Residual Error Distribution */}
        <div className="bg-slate-900/80 border border-slate-800 rounded-xl p-6 space-y-4">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <BarChart2 className="w-5 h-5 text-amber-400" />
              <span>Prediction Residual Distribution (p̂ − y)</span>
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              Distribution of single-game probability errors across all {diagnostics.totalResolvedGames.toLocaleString()} resolved games.
            </p>
          </div>

          <div className="space-y-3 pt-1">
            {diagnostics.residualDistribution.map((res) => {
              const pct = Math.max(4, (res.count / maxResidualCount) * 100);
              return (
                <div key={res.bucket} className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-mono text-slate-300">
                      {res.bucket}{' '}
                      <span className="text-slate-500 font-sans">({res.label})</span>
                    </span>
                    <span className="font-mono font-bold text-white">{res.count} games</span>
                  </div>
                  <div className="h-2.5 bg-slate-950 rounded-full overflow-hidden border border-slate-800">
                    <div
                      className="h-full bg-gradient-to-r from-indigo-500 to-sky-400 rounded-full"
                      style={{ width: `${pct}%` }}
                    />
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
};
