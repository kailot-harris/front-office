'use client';

import { DiagnosticsDataset } from '@/lib/types';
import { Layers, Sliders, Cpu, Shuffle, HelpCircle } from 'lucide-react';

interface VariantsClientProps {
  data: DiagnosticsDataset;
}

export default function VariantsClient({ data }: VariantsClientProps) {
  const weights = data.ensemble_weights || {
    ridge_massey: 0.4,
    elo_dynamic: 0.35,
    market_blend: 0.25,
  };

  const variants = [
    {
      id: 'ridge_massey',
      name: 'Ridge Massey Ratings',
      weight: weights.ridge_massey,
      color: 'emerald',
      description:
        'L2-regularized point differential regression with opponent strength adjustments, home field advantage isolation, and rolling exponential time-decay weighting.',
      features: [
        'L2 regularization (λ tuned via 5-fold CV)',
        'Opponent-adjusted margin of victory',
        'Garbage time margin decay clamping',
        'Direct offensive/defensive rating decomposition',
      ],
      pros: 'Stable across large sample sizes, resists recency bias, highly predictive on neutral fields.',
      cons: 'Slower to adjust to sudden roster shocks or key injuries within short weeks.',
    },
    {
      id: 'elo_dynamic',
      name: 'Dynamic K-Factor Elo',
      weight: weights.elo_dynamic,
      color: 'cyan',
      description:
        'Sequential match-by-match rating engine with dynamic K-factors scaling on margin of victory and situational rest advantage. Anchored to a 1500 mean.',
      features: [
        'Dynamic K-factor: K = 20 * (MOV + 3)^0.8 / (7.5 + 0.006 * ΔElo)',
        'Mean reversion to 1500 between seasons (1/3 regression)',
        'Custom rest differential home field adjustment',
        'Weekly rapid convergence',
      ],
      pros: 'Rapidly catches momentum shifts, coaching upgrades, and breakout team streaks.',
      cons: 'Can overreact to blowout games against heavily compromised backup quarterbacks.',
    },
    {
      id: 'market_blend',
      name: 'Consensus Market Line Anchor',
      weight: weights.market_blend,
      color: 'indigo',
      description:
        'Consensus opening and midweek market closing lines transformed into implied point differentials and win probabilities via the normal CDF ($N(\\mu, \\sigma=14.6^2)$).',
      features: [
        'Closing line value (CLV) baseline calibration',
        'Wisdom-of-the-crowd liquidity filter',
        'Vigorish and margin extraction',
        'Bayesian shrinkage prior',
      ],
      pros: 'Prevents rogue algorithmic predictions on games with unquantified late-breaking news.',
      cons: 'Exposed to retail public bias on high-profile primetime teams (e.g. DAL, KC).',
    },
  ];

  return (
    <div className="space-y-8">
      {/* Header */}
      <div>
        <div className="flex items-center gap-2 mb-1">
          <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
            Phase 8: Model Architecture & Variants
          </span>
          <span className="text-xs font-mono text-slate-400">
            3-Model Production Ensemble
          </span>
        </div>
        <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
          Multi-Model Architecture & Ensemble Weights
        </h1>
        <p className="text-slate-400 text-sm mt-1 max-w-3xl">
          The NFL Analytics platform merges three distinct modeling philosophies into a single,
          robust meta-predictor to maximize out-of-sample log-likelihood and minimize Brier score error.
        </p>
      </div>

      {/* Ensemble Weight Visualization Bar */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-xl">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
          <div className="flex items-center gap-2">
            <Sliders className="w-4 h-4 text-emerald-400" />
            <h3 className="text-sm font-semibold text-white">Production Ensemble Weight Allocation</h3>
          </div>
          <span className="text-xs font-mono text-slate-400">Normalized ∑ = 100%</span>
        </div>

        {/* Visual Bar */}
        <div className="h-6 w-full rounded-lg overflow-hidden flex shadow-inner bg-slate-950 p-0.5 border border-slate-800">
          <div
            style={{ width: `${weights.ridge_massey * 100}%` }}
            className="h-full bg-gradient-to-r from-emerald-600 to-emerald-500 flex items-center justify-center text-[11px] font-mono font-bold text-white shadow-sm"
          >
            Ridge {(weights.ridge_massey * 100).toFixed(0)}%
          </div>
          <div
            style={{ width: `${weights.elo_dynamic * 100}%` }}
            className="h-full bg-gradient-to-r from-cyan-600 to-cyan-500 flex items-center justify-center text-[11px] font-mono font-bold text-white shadow-sm"
          >
            Elo {(weights.elo_dynamic * 100).toFixed(0)}%
          </div>
          <div
            style={{ width: `${weights.market_blend * 100}%` }}
            className="h-full bg-gradient-to-r from-indigo-600 to-indigo-500 flex items-center justify-center text-[11px] font-mono font-bold text-white shadow-sm"
          >
            Market {(weights.market_blend * 100).toFixed(0)}%
          </div>
        </div>

        <div className="flex justify-between items-center text-xs font-mono text-slate-400 mt-3 pt-2 border-t border-slate-800/60">
          <span>Formula: P(final) = 0.40 · P(Ridge) + 0.35 · P(Elo) + 0.25 · P(Market)</span>
          <span className="text-emerald-400">Optimal via Walk-Forward Validation</span>
        </div>
      </div>

      {/* Model Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {variants.map((v) => (
          <div
            key={v.id}
            className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-lg flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
                <div className="flex items-center gap-2">
                  {v.id === 'ridge_massey' ? (
                    <Cpu className="w-5 h-5 text-emerald-400" />
                  ) : v.id === 'elo_dynamic' ? (
                    <Shuffle className="w-5 h-5 text-cyan-400" />
                  ) : (
                    <Layers className="w-5 h-5 text-indigo-400" />
                  )}
                  <h3 className="text-base font-bold text-white">{v.name}</h3>
                </div>
                <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-slate-950 border border-slate-800 text-white">
                  {(v.weight * 100).toFixed(0)}% Weight
                </span>
              </div>

              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                {v.description}
              </p>

              {/* Core Features */}
              <div className="mb-4">
                <span className="text-[10px] font-mono uppercase text-slate-500 block mb-1.5 font-bold">
                  Core Mathematical Properties
                </span>
                <ul className="space-y-1.5">
                  {v.features.map((feat, i) => (
                    <li key={i} className="text-xs text-slate-400 flex items-start gap-1.5">
                      <span className="text-emerald-400 mt-0.5">•</span>
                      <span>{feat}</span>
                    </li>
                  ))}
                </ul>
              </div>
            </div>

            {/* Strengths & Weaknesses */}
            <div className="pt-3 border-t border-slate-800/80 space-y-2 text-xs">
              <div>
                <span className="text-emerald-400 font-semibold font-mono text-[11px]">Advantage: </span>
                <span className="text-slate-300">{v.pros}</span>
              </div>
              <div>
                <span className="text-amber-400 font-semibold font-mono text-[11px]">Mitigation: </span>
                <span className="text-slate-400">{v.cons}</span>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Mathematical Ensembling Notes */}
      <div className="bg-slate-900/90 border border-slate-800 rounded-xl p-5 shadow-lg">
        <div className="flex items-center gap-2 pb-3 border-b border-slate-800 mb-3 text-white font-semibold">
          <HelpCircle className="w-4 h-4 text-emerald-400" />
          <span>Why Ensemble Independent Estimators?</span>
        </div>
        <p className="text-xs text-slate-300 leading-relaxed max-w-4xl">
          By ensembling an econometric regularized matrix regression (Ridge Massey), a time-series Markovian
          rating updater (Elo), and real-time market liquidity (Market Consensus), the meta-predictor suppresses
          individual model variance without inflating prediction bias. Empirically, the 40/35/25 blend achieves a
          ~7.4% Brier score improvement over an uninformative baseline, yielding sharper spread estimates and
          protecting bankrolls from statistical noise.
        </p>
      </div>
    </div>
  );
}
