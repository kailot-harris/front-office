'use client';

import React, { useRef } from 'react';
import { ModelDiagnostics, ModelMetadata } from '@/lib/types';
import { Target, CheckCircle2, TrendingUp, BarChart2, ShieldCheck, Download } from 'lucide-react';
import { seasonEndYearLabel } from '@/lib/season';
import { exportSvgAsPng } from '@/lib/exportSvgAsPng';
import { exportToCsv } from '@/lib/exportToCsv';

interface DiagnosticsClientProps {
  diagnostics: ModelDiagnostics;
  metadata: ModelMetadata;
}

export const DiagnosticsClient: React.FC<DiagnosticsClientProps> = ({
  diagnostics,
  metadata,
}) => {
  const maxResidualCount = Math.max(...diagnostics.residualDistribution.map((d) => d.count));
  const calibrationCardRef = useRef<HTMLDivElement | null>(null);

  const handleExportCalibrationPng = () => {
    if (calibrationCardRef.current) {
      exportSvgAsPng(calibrationCardRef.current, 'model-calibration-curve');
    }
  };

  const handleExportCalibrationCsv = () => {
    exportToCsv(
      diagnostics.calibration as unknown as Record<string, unknown>[],
      [
        { key: 'bin', label: 'Probability Bin' },
        { key: 'count', label: 'Sample N' },
        { key: 'meanPredictedProb', label: 'Mean Forecast' },
        { key: 'empiricalWinRate', label: 'Empirical Win %' },
      ],
      'model-calibration-bins'
    );
  };

  return (
    <div className="space-y-8">
      {/* Top Headline Accuracy & Scoring Metrics */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Overall Win Rate Accuracy</span>
            <CheckCircle2 className="w-4 h-4 text-emerald-400" />
          </div>
          <div className="text-3xl font-extrabold text-white">
            {(diagnostics.overallAccuracy * 100).toFixed(1)}%
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Over {diagnostics.totalResolvedGames.toLocaleString()} historical resolved games
          </p>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Ensemble Brier Score</span>
            <Target className="w-4 h-4 text-indigo-400" />
          </div>
          <div className="text-3xl font-extrabold text-indigo-400">
            {diagnostics.brierScore.toFixed(4)}
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Mean squared error vs outcome (Benchmark 0.25 = random)
          </p>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Log-Loss Reliability</span>
            <TrendingUp className="w-4 h-4 text-amber-400" />
          </div>
          <div className="text-3xl font-extrabold text-amber-400">
            {diagnostics.logLoss.toFixed(4)}
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Cross-entropy loss against empirical game outcomes
          </p>
        </div>

        <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-5">
          <div className="flex items-center justify-between text-slate-400 text-xs font-semibold uppercase tracking-wider mb-2">
            <span>Home Court Advantage Rate</span>
            <ShieldCheck className="w-4 h-4 text-blue-400" />
          </div>
          <div className="text-3xl font-extrabold text-blue-400">
            {(diagnostics.homeWinRate * 100).toFixed(1)}%
          </div>
          <p className="text-xs text-slate-400 mt-1">
            Baseline home court win rate (+{metadata.home_court_advantage} pts)
          </p>
        </div>
      </div>

      {/* Model Calibration Curve & Reliability Diagram */}
      <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-6 space-y-6">
        <div className="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 className="text-xl font-bold text-white flex items-center gap-2">
              <Target className="w-5 h-5 text-indigo-400" />
              <span>Probability Calibration Curve (Reliability Diagram)</span>
            </h2>
            <p className="text-xs text-slate-400 mt-1">
              Validating whether forecasts of 70% win probability win exactly 70% of the time in empirical data.
            </p>
          </div>
          <div className="flex items-center gap-2">
          <button
            type="button"
            onClick={handleExportCalibrationPng}
            title="Export chart as PNG"
            aria-label="Export calibration chart as PNG"
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-slate-800 text-xs text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Chart PNG</span>
          </button>
          <button
            type="button"
            onClick={handleExportCalibrationCsv}
            title="Export table as CSV"
            aria-label="Export calibration table as CSV"
            className="inline-flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg border border-slate-800 text-xs text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
            <span>Table CSV</span>
          </button>
          </div>
        </div>

        {/* Visual Calibration Curve Grid */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 items-center">
          {/* SVG Calibration Chart */}
          <div className="bg-surface p-6 rounded-xl border border-slate-800">
            <div ref={calibrationCardRef}>
            <div className="mb-3">
              <h3 className="text-xs font-bold text-white uppercase tracking-wider">
                Probability Calibration Curve (Reliability Diagram)
              </h3>
              <p className="text-[11px] text-slate-400 mt-1">
                Validating whether forecasts of 70% win probability win exactly 70% of the time in empirical data.
              </p>
            </div>
            <div className="relative w-full aspect-square max-w-[420px] mx-auto">
              <svg viewBox="0 0 400 400" className="w-full h-full overflow-visible">
                {/* Grid lines */}
                {[0.2, 0.4, 0.6, 0.8].map((step) => {
                  const pos = 40 + step * 320;
                  return (
                    <React.Fragment key={step}>
                      {/* Horizontal grid line */}
                      <line
                        x1="40"
                        y1={400 - pos + 40}
                        x2="360"
                        y2={400 - pos + 40}
                        stroke="#334155"
                        strokeDasharray="4 4"
                        strokeWidth="1"
                      />
                      {/* Vertical grid line */}
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
                        className="cursor-pointer hover:r-8 transition-all"
                      />
                    </g>
                  );
                })}

                {/* Axis Labels */}
                <text x="200" y="395" textAnchor="middle" fill="#94a3b8" fontSize="12" fontWeight="600">
                  Predicted Win Probability →
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
                  Empirical Win Rate →
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
                <span className="text-indigo-300 font-semibold">Empirical Model Bins</span>
              </div>
            </div>
            </div>
          </div>

          {/* Tabular Calibration Bin Breakdown */}
          <div className="bg-surface p-4 rounded-xl border border-slate-800 overflow-x-auto">
            <table className="w-full text-xs text-left">
              <thead>
                <tr className="border-b border-slate-800 text-slate-400 pb-2">
                  <th className="py-2 px-2">Probability Bin</th>
                  <th className="py-2 px-2 text-right">Sample N</th>
                  <th className="py-2 px-2 text-right">Mean Forecast</th>
                  <th className="py-2 px-2 text-right">Empirical Win %</th>
                  <th className="py-2 px-2 text-right">Calibration Error</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-900 font-mono">
                {diagnostics.calibration.map((bin) => {
                  const error = bin.empiricalWinRate - bin.meanPredictedProb;
                  const isClose = Math.abs(error) < 0.05;

                  return (
                    <tr key={bin.bin} className="hover:bg-surface-raised/60">
                      <td className="py-2 px-2 font-semibold text-slate-200">{bin.bin}</td>
                      <td className="py-2 px-2 text-right text-slate-400">{bin.count}</td>
                      <td className="py-2 px-2 text-right text-indigo-300">
                        {(bin.meanPredictedProb * 100).toFixed(1)}%
                      </td>
                      <td className="py-2 px-2 text-right text-white font-bold">
                        {(bin.empiricalWinRate * 100).toFixed(1)}%
                      </td>
                      <td className="py-2 px-2 text-right">
                        <span
                          className={`px-1.5 py-0.5 rounded ${
                            isClose
                              ? 'bg-emerald-500/10 text-emerald-400'
                              : 'bg-amber-500/10 text-amber-400'
                          }`}
                        >
                          {error >= 0 ? `+${(error * 100).toFixed(1)}%` : `${(error * 100).toFixed(1)}%`}
                        </span>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </div>
      </div>

      {/* Accuracy Drift & Residual Distribution */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Accuracy Drift Over Seasons */}
        <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-6 space-y-4">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <TrendingUp className="w-5 h-5 text-emerald-400" />
              <span>Accuracy Drift Over Time</span>
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              Tracking model stability across consecutive NBA seasons to monitor degradation or drift.
            </p>
          </div>

          <div className="space-y-4">
            {diagnostics.accuracyDrift.map((drift) => (
              <div
                key={drift.season}
                className="bg-surface p-4 rounded-xl border border-slate-800 flex items-center justify-between"
              >
                <div>
                  <div className="text-base font-bold text-white">
                    Season {seasonEndYearLabel(Number(drift.season))}
                  </div>
                  <div className="text-xs text-slate-400">{drift.games} resolved games evaluated</div>
                </div>
                <div className="text-right">
                  <div className="text-xl font-bold text-emerald-400">
                    {(drift.accuracy * 100).toFixed(1)}% Accuracy
                  </div>
                  <div className="text-xs text-slate-400 font-mono">
                    Brier: {drift.brierScore.toFixed(4)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Residual Distribution */}
        <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-6 space-y-4">
          <div>
            <h3 className="text-lg font-bold text-white flex items-center gap-2">
              <BarChart2 className="w-5 h-5 text-amber-400" />
              <span>Forecast Residual Distribution</span>
            </h3>
            <p className="text-xs text-slate-400 mt-1">
              Residual errors (Predicted Win Prob − Actual Outcome) across all resolved games.
            </p>
          </div>

          <div className="space-y-3">
            {diagnostics.residualDistribution.map((item) => {
              const widthPct = Math.max(5, (item.count / maxResidualCount) * 100);
              return (
                <div key={item.bucket} className="space-y-1">
                  <div className="flex items-center justify-between text-xs">
                    <span className="font-semibold text-slate-300">{item.bucket}</span>
                    <span className="text-slate-400 font-mono">
                      {item.count} games ({item.label})
                    </span>
                  </div>
                  <div className="w-full h-3 bg-surface rounded-full overflow-hidden border border-slate-800">
                    <div
                      className="h-full bg-gradient-to-r from-indigo-500 to-amber-500 rounded-full"
                      style={{ width: `${widthPct}%` }}
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
