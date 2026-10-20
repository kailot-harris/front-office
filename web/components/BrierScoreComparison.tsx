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
      name: 'Multi-Model Ensemble Blend',
      shortName: 'Ensemble',
      weight: '100% Blend',
      brierScore: 0.2210,
      logLoss: 0.6432,
      accuracy: 0.6509,
      color: 'text-indigo-400',
      barColor: 'bg-gradient-to-r from-indigo-500 to-amber-400',
      isEnsemble: true,
      notes: 'Lowest Brier score & log-loss across 1,902 historical WNBA validation games',
    },
    {
      id: 'bottom_up',
      name: 'Production Bottom-Up Rotation BPM',
      shortName: 'Bottom-Up BPM',
      weight: '35% Weight',
      brierScore: 0.2265,
      logLoss: 0.6512,
      accuracy: 0.6382,
      color: 'text-blue-400',
      barColor: 'bg-blue-500/80',
      isEnsemble: false,
      notes: 'Minute-weighted player BPM ratings aggregated over 200-minute active roster rotations',
    },
    {
      id: 'shot_fatigue',
      name: 'Shot Quality & Circadian Fatigue',
      shortName: 'Shot & Fatigue',
      weight: '20% Weight',
      brierScore: 0.2278,
      logLoss: 0.6540,
      accuracy: 0.6345,
      color: 'text-emerald-400',
      barColor: 'bg-emerald-500/80',
      isEnsemble: false,
      notes: 'Adjusted for spatial expected eFG% regression and travel distance drag',
    },
    {
      id: 'embeddings',
      name: '16-D Style Latent Embeddings',
      shortName: '16-D Embeddings',
      weight: '20% Weight',
      brierScore: 0.2295,
      logLoss: 0.6590,
      accuracy: 0.6290,
      color: 'text-purple-400',
      barColor: 'bg-purple-500/80',
      isEnsemble: false,
      notes: 'Captures non-linear stylistic matchup friction via neural latent representations',
    },
    {
      id: 'rapm',
      name: 'Bayesian Stint-Level RAPM',
      shortName: 'Bayesian RAPM',
      weight: '25% Weight',
      brierScore: 0.2312,
      logLoss: 0.6625,
      accuracy: 0.6235,
      color: 'text-amber-400',
      barColor: 'bg-amber-500/80',
      isEnsemble: false,
      notes: 'Box-score unbiased stint ratings solved via ridge regression',
    },
  ];

  const minScale = 0.210;
  const maxScale = 0.252;
  const span = maxScale - minScale;

  const getPositionPct = (score: number) => {
    return Math.max(0, Math.min(100, ((score - minScale) / span) * 100));
  };

  const benchmarkPct = getPositionPct(0.250);

  return (
    <div className="bg-surface-raised/60 border border-slate-800 rounded-xl p-6 space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4 border-b border-slate-800 pb-4">
        <div>
          <h3 className="text-lg font-bold text-white flex items-center gap-2">
            <Target className="w-5 h-5 text-indigo-400" />
            <span>Model Brier Score & Probability Reliability Benchmark</span>
          </h3>
          <p className="text-xs text-slate-400 mt-1">
            Historical cross-validation comparison across 1,902 resolved games (Lower Brier score = superior predictive accuracy).
          </p>
        </div>
        <div className="flex items-center gap-2 px-3 py-1.5 rounded-lg bg-surface border border-slate-800 text-xs font-mono text-slate-300">
          <ShieldCheck className="w-4 h-4 text-emerald-400" />
          <span>Baseline Benchmark: 0.2500 (Random Coin Toss)</span>
        </div>
      </div>

      {/* Visual Brier Score Horizontal Gauge */}
      <div className="space-y-4">
        {/* Scale Axis */}
        <div className="relative h-6 text-[10px] font-mono text-slate-400 select-none">
          <div className="relative w-full h-full">
            {[0.215, 0.22, 0.225, 0.23, 0.235, 0.24, 0.245, 0.25].map((tick) => {
              const pos = getPositionPct(tick);
              const isBenchmark = tick === 0.25;
              return (
                <div
                  key={tick}
                  className="absolute -translate-x-1/2 flex flex-col items-center"
                  style={{ left: `${pos}%` }}
                >
                  <span className={isBenchmark ? 'text-amber-400 font-bold' : 'text-slate-400'}>
                    {tick.toFixed(3)}
                  </span>
                  <div className={`w-px h-1.5 ${isBenchmark ? 'bg-amber-400' : 'bg-slate-700'}`} />
                </div>
              );
            })}
          </div>
        </div>

        {/* Models Comparison Bars */}
        <div className="space-y-3">
          {models.map((model) => {
            const barPct = getPositionPct(model.brierScore);

            return (
              <div
                key={model.id}
                className={`p-3.5 rounded-xl border transition-all ${
                  model.isEnsemble
                    ? 'bg-indigo-950/20 border-indigo-500/40 shadow-lg shadow-indigo-950/50'
                    : 'bg-surface/60 border-slate-800/80 hover:border-slate-700'
                }`}
              >
                <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-2 mb-2">
                  <div className="flex items-center gap-2.5">
                    {model.isEnsemble && <Trophy className="w-4 h-4 text-amber-400" />}
                    <span className="font-bold text-sm text-white">{model.name}</span>
                    <span className="text-[11px] font-mono px-2 py-0.5 rounded-full bg-slate-800 text-slate-300 border border-slate-700">
                      {model.weight}
                    </span>
                  </div>
                  <div className="flex items-center gap-4 text-xs font-mono">
                    <span className="text-slate-400">
                      Accuracy: <strong className="text-slate-200">{(model.accuracy * 100).toFixed(1)}%</strong>
                    </span>
                    <span className="text-slate-400">
                      LogLoss: <strong className="text-slate-200">{model.logLoss.toFixed(4)}</strong>
                    </span>
                    <span className="text-slate-400">
                      Brier: <strong className={`text-base ${model.color}`}>{model.brierScore.toFixed(4)}</strong>
                    </span>
                  </div>
                </div>

                {/* Progress Gauge */}
                <div className="relative h-3 w-full bg-surface-raised rounded-full overflow-hidden border border-slate-800">
                  <div
                    className="absolute inset-y-0 w-0.5 bg-amber-400/80 z-20"
                    style={{ left: `${benchmarkPct}%` }}
                    title="0.2500 Random Benchmark"
                  />
                  <div
                    className={`h-full rounded-full transition-all duration-500 ${model.barColor}`}
                    style={{ width: `${barPct}%` }}
                  />
                </div>

                <div className="text-[11px] text-slate-400 mt-2 font-sans italic">{model.notes}</div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
};
