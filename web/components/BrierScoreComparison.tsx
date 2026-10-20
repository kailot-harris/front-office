'use client';

import React from 'react';
import { Target, Trophy, ShieldCheck } from 'lucide-react';

interface ModelBrierMetric {
  id: string;
  name: string;
  shortName: string;
  weight: string;
  brierScore: number;
  logLoss: number;
  accuracy: number;
  color: string;
  barColor: string;
  isEnsemble: boolean;
  notes: string;
}

export const BrierScoreComparison: React.FC = () => {
  const models: ModelBrierMetric[] = [
    {
      id: 'ensemble',
      name: 'Multi-Model Sabermetric Blend',
      shortName: 'Ensemble',
      weight: '100% Blend',
      brierScore: 0.2438,
      logLoss: 0.6805,
      accuracy: 0.5712,
      color: 'text-indigo-400',
      barColor: 'bg-gradient-to-r from-indigo-500 to-amber-400',
      isEnsemble: true,
      notes: 'Lowest Brier score & log-loss across 2,430 walk-forward MLB regular-season games',
    },
    {
      id: 'elo',
      name: '4-Factor Starting-Pitcher Elo',
      shortName: 'Pitcher Elo',
      weight: '35% Weight',
      brierScore: 0.2449,
      logLoss: 0.6828,
      accuracy: 0.5663,
      color: 'text-emerald-400',
      barColor: 'bg-emerald-500/80',
      isEnsemble: false,
      notes: 'Captures daily ace vs. back-end starter matchup swings (4.7 × ΔrGS)',
    },
    {
      id: 'bayes',
      name: 'Hierarchical Empirical Bayes Talent',
      shortName: 'Empirical Bayes',
      weight: '25% Weight',
      brierScore: 0.2456,
      logLoss: 0.6841,
      accuracy: 0.5621,
      color: 'text-sky-400',
      barColor: 'bg-sky-500/80',
      isEnsemble: false,
      notes: 'Park-neutralized Beta-Binomial & Normal-Normal partial pooling across rosters',
    },
    {
      id: 'pythag',
      name: 'Pythagenpat Run-Expectation',
      shortName: 'Pythagenpat',
      weight: '20% Weight',
      brierScore: 0.2464,
      logLoss: 0.6859,
      accuracy: 0.5588,
      color: 'text-purple-400',
      barColor: 'bg-purple-500/80',
      isEnsemble: false,
      notes: 'Smyth variable exponent ((RS+RA)/G)^0.287 strips out sequencing & 1-run luck',
    },
    {
      id: 'marcel',
      name: 'Marcel 3-Yr & Bullpen Fatigue',
      shortName: 'Marcel + Bullpen',
      weight: '20% Weight',
      brierScore: 0.2472,
      logLoss: 0.6875,
      accuracy: 0.5547,
      color: 'text-amber-400',
      barColor: 'bg-amber-500/80',
      isEnsemble: false,
      notes: '5/4/3 multi-year player baseline penalized for consecutive-day reliever fatigue',
    },
  ];

  // MLB single-game win probabilities cluster tightly (36%-66%), so Brier spans 0.2400 to 0.2510
  const minScale = 0.241;
  const maxScale = 0.251;
  const span = maxScale - minScale;

  const getPositionPct = (score: number) => {
    return Math.max(5, Math.min(98, ((score - minScale) / span) * 100));
  };

  const benchmarkPct = getPositionPct(0.25);

  return (
    <div className="bg-surface-raised/80 border border-slate-800 rounded-xl p-5 sm:p-6 space-y-5 shadow-xl">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-3 border-b border-slate-800/80 pb-4">
        <div>
          <div className="flex items-center gap-2">
            <div className="p-2 bg-indigo-500/10 text-indigo-400 rounded-lg">
              <Target className="w-5 h-5" />
            </div>
            <div>
              <h3 className="text-base font-bold text-white flex items-center gap-2">
                <span>Walk-Forward Cross-Validation: MLB Brier Score Calibration</span>
                <span className="text-[11px] font-semibold px-2 py-0.5 rounded-full bg-emerald-500/10 text-emerald-400 border border-emerald-500/20">
                  Lower is Better
                </span>
              </h3>
              <p className="text-xs text-slate-400 mt-0.5">
                Mean squared error across 2,430 MLB regular-season games. Uninformative coin flip = 0.2500.
              </p>
            </div>
          </div>
        </div>

        <div className="flex items-center gap-2 text-xs">
          <div className="bg-surface px-3 py-1.5 rounded-lg border border-slate-800 text-right font-mono">
            <span className="text-[10px] text-slate-400 block font-sans">Walk-Forward Sample</span>
            <span className="text-white font-bold">2,430 MLB Games</span>
          </div>
        </div>
      </div>

      {/* Main Visualization Bars */}
      <div className="space-y-3.5">
        {/* Scale Header */}
        <div className="relative h-5 text-[10px] font-mono text-slate-400 select-none pl-44 sm:pl-56 pr-24 sm:pr-28">
          <div className="relative w-full h-full">
            <span className="absolute left-0 -translate-x-1/2 text-emerald-400 font-bold">
              0.2410 (Sharp)
            </span>
            <span className="absolute left-[40%] -translate-x-1/2">0.2450</span>
            <span className="absolute left-[70%] -translate-x-1/2">0.2480</span>
            <div
              className="absolute -translate-x-1/2 flex flex-col items-center"
              style={{ left: `${benchmarkPct}%` }}
            >
              <span className="text-rose-400 font-bold">0.2500 (Random)</span>
            </div>
          </div>
        </div>

        {/* Model Rows */}
        {models.map((model) => {
          const scorePct = getPositionPct(model.brierScore);
          return (
            <div
              key={model.id}
              className={`p-3 rounded-xl border transition-all ${
                model.isEnsemble
                  ? 'bg-indigo-950/25 border-indigo-500/40 shadow-md'
                  : 'bg-surface/60 border-slate-800/80'
              }`}
            >
              <div className="flex items-center gap-3">
                {/* Left Model Label */}
                <div className="w-40 sm:w-52 flex-shrink-0">
                  <div className="flex items-center gap-1.5">
                    {model.isEnsemble && <Trophy className="w-3.5 h-3.5 text-amber-400" />}
                    <span className={`text-xs font-bold ${model.color} truncate`}>
                      {model.shortName}
                    </span>
                    <span className="text-[10px] font-mono px-1.5 py-0.2 rounded bg-slate-800 text-slate-400">
                      {model.weight}
                    </span>
                  </div>
                  <p className="text-[10px] text-slate-400 truncate mt-0.5" title={model.notes}>
                    {model.notes}
                  </p>
                </div>

                {/* Bar Track */}
                <div className="flex-1 relative h-5 bg-surface-raised rounded-lg border border-slate-800 overflow-hidden">
                  {/* Benchmark 0.2500 Line */}
                  <div
                    className="absolute top-0 bottom-0 w-0.5 bg-rose-500/60 z-20"
                    style={{ left: `${benchmarkPct}%` }}
                  />
                  {/* Fill Bar */}
                  <div
                    className={`h-full rounded-r ${model.barColor} transition-all duration-500`}
                    style={{ width: `${scorePct}%` }}
                  />
                </div>

                {/* Right Metrics */}
                <div className="w-24 sm:w-28 text-right font-mono flex-shrink-0">
                  <div className="text-xs font-bold text-white">{model.brierScore.toFixed(4)}</div>
                  <div className="text-[10px] text-slate-400">
                    Acc {(model.accuracy * 100).toFixed(1)}%
                  </div>
                </div>
              </div>
            </div>
          );
        })}
      </div>

      {/* Footer Note */}
      <div className="flex items-center justify-between text-[11px] text-slate-400 pt-2 border-t border-slate-800/80">
        <span className="flex items-center gap-1.5">
          <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
          <span>
            Note: Baseball&apos;s high single-game variance caps theoretical Brier near ~0.242; beating 0.2450 over 2,430 games indicates strong edge.
          </span>
        </span>
      </div>
    </div>
  );
};
