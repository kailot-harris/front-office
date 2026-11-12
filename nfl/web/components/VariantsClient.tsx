'use client';

import { DiagnosticsDataset } from '@/lib/types';
import { Layers, Sliders, Cpu, Shuffle, HelpCircle, Download } from 'lucide-react';
import { exportToCsv } from '@/lib/exportToCsv';
import { GlossaryTerm } from './Glossary';
import { HowToRead } from './HowToRead';

interface VariantsClientProps {
  data: DiagnosticsDataset;
}

export default function VariantsClient({ data }: VariantsClientProps) {
  const weights = data.ensemble_weights || {
    ridge_massey: 0.5,
    elo_dynamic: 0.5,
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
  ];

  const candidateModels = [
    {
      id: 'epa_differential',
      number: 'Candidate Model #4',
      name: 'Net EPA / Early-Down Success Rate Regression',
      evaluatedWeight: 'Unverified',
      brierImpact: 'Unverified',
      liftStatus: 'Pending re-evaluation',
      finding:
        'An earlier one-off study (not saved as a reusable backtest candidate) reported this architecture degraded Brier score; those exact figures traced to a different, now-retired 3-model ensemble (Ridge 40% / Elo 35% / Market 25%) and cannot honestly be attributed to the current 2-model production ensemble. tools/model_backtest_harness.R has no saved predict_fn reconstructing this exact "EPA differential as an independent linear estimator" architecture against today’s Ridge+Elo base, so no number is shown here pending a real re-run (tools/ridge_situational_model.R’s situational-EPA ridge candidate is the closest existing building block, but it blends EPA features INTO the ridge fit rather than testing EPA as a separate estimator, so it is not a faithful substitute).',
      recommendation: 'Do not cite a Brier/log-loss number for this row until a dedicated walk-forward candidate is built and run against the current production base.',
    },
    {
      id: 'situational_fatigue',
      number: 'Candidate Model #5',
      name: 'Standalone Rest & Travel Circadian Model',
      evaluatedWeight: 'Unverified',
      brierImpact: 'Unverified',
      liftStatus: 'Pending re-evaluation',
      finding:
        'An earlier one-off study (not saved as a reusable backtest candidate) reported this architecture degraded log loss; those exact figures traced to the same now-retired 3-model (Ridge/Elo/Market) ensemble, not the current 2-model production ensemble. fatigue_engine.R’s fatigue_drag_pts is already used as an additive term inside the Elo candidate (tools/elo_model.R), but no STANDALONE rest/travel/circadian win-probability model has been built or backtested on its own against today’s base, so no number is shown here pending a real re-run.',
      recommendation: 'Do not cite a Brier/log-loss number for this row until a dedicated standalone walk-forward candidate is built and run against the current production base.',
    },
  ];

  const ablationBenchmarks = [
    {
      architecture: '2-Model Baseline (Production)',
      weight_distribution: 'Ridge (50%) + Elo (50%)',
      brier_score: 0.2228,
      log_loss: 0.6363,
      status: 'Active Production',
    },
    {
      architecture: '3-Model Variant (+ Net EPA)',
      weight_distribution: 'Ridge (45%) + Elo (45%) + EPA (10%)',
      brier_score: null,
      log_loss: null,
      status: 'Unverified (pending re-run)',
    },
    {
      architecture: '3-Model Variant (+ Rest / Fatigue)',
      weight_distribution: 'Ridge (45%) + Elo (45%) + Rest (10%)',
      brier_score: null,
      log_loss: null,
      status: 'Unverified (pending re-run)',
    },
  ];

  const handleExportAblationCsv = () => {
    exportToCsv(
      ablationBenchmarks as unknown as Record<string, unknown>[],
      [
        { key: 'architecture', label: 'Ensemble Architecture' },
        { key: 'weight_distribution', label: 'Weight Distribution' },
        { key: 'brier_score', label: 'Brier Score' },
        { key: 'log_loss', label: 'Log Loss' },
        { key: 'status', label: 'Ensemble Status' },
      ],
      'nfl-ablation-benchmarks'
    );
  };

  return (
    <div className="space-y-8">
      {/* Header */}
      <div className="relative pb-6">
        <div>
          <div className="flex items-center gap-2 mb-1">
            <span className="text-xs font-mono font-medium text-emerald-400 bg-emerald-950/60 border border-emerald-800/60 px-2 py-0.5 rounded-full">
              Model Architecture & Variants
            </span>
            <span className="text-xs font-mono text-slate-400">
              2-Model Production Ensemble
            </span>
          </div>
          <h1 className="text-2xl sm:text-3xl font-bold tracking-tight text-white">
            <span className="text-emerald-400">NFL</span> Multi-Model Architecture & Ensemble Weights
          </h1>
          <p className="text-slate-400 text-sm mt-1 max-w-3xl">
            The NFL Analytics platform merges two distinct, purely endogenous modeling philosophies into a
            single, robust meta-predictor to maximize out-of-sample log-likelihood and minimize <GlossaryTerm term="Brier Score" className="text-slate-300" />
            error. Every published prediction is built only from on-field game results.
          </p>
        </div>
        <div className="absolute bottom-0 left-0 right-0 h-[2px] bg-gradient-to-r from-emerald-400 via-emerald-500/40 to-transparent" />
      </div>

      <HowToRead pageKey="variants">
        <p>
          The published model is an <strong>ensemble</strong> &mdash; a weighted blend of two independently-built
          rating systems, not a single algorithm. Weights are tuned to minimize out-of-sample{' '}
          <GlossaryTerm term="Brier Score" className="text-slate-300" />, so a component only gets more influence
          if it actually improves prediction accuracy on games the model has not seen. Every input is derived from
          real on-field results; no synthetic or subjectively-assigned data feeds into any variant.
        </p>
      </HowToRead>

      {/* Ensemble Weight Visualization Bar */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-4">
          <div className="flex items-center gap-2">
            <Sliders className="w-4 h-4 text-emerald-400" />
            <h2 className="text-sm font-semibold text-white">Production Ensemble Weight Allocation</h2>
          </div>
          <span className="text-xs font-mono text-slate-400">Normalized ∑ = 100%</span>
        </div>

        {/* Visual Bar */}
        <div className="h-6 w-full rounded-lg overflow-hidden flex shadow-inner bg-surface p-0.5 border border-slate-800">
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
        </div>

        <div className="flex justify-between items-center text-xs font-mono text-slate-400 mt-3 pt-2 border-t border-slate-800/60">
          <span>Formula: P(final) = 0.50 · P(Ridge) + 0.50 · P(Elo) (100% Ridge when live Elo is unavailable)</span>
          <span className="text-emerald-400">Optimal via Walk-Forward Validation</span>
        </div>
      </div>

      {/* Model Cards Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {variants.map((v) => (
          <div
            key={v.id}
            className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-lg flex flex-col justify-between"
          >
            <div>
              <div className="flex items-center justify-between pb-3 border-b border-slate-800 mb-3">
                <div className="flex items-center gap-2">
                  {v.id === 'ridge_massey' ? (
                    <Cpu className="w-5 h-5 text-emerald-400" />
                  ) : (
                    <Shuffle className="w-5 h-5 text-cyan-400" />
                  )}
                  <h2 className="text-base font-bold text-white">{v.name}</h2>
                </div>
                <span className="text-xs font-mono font-bold px-2 py-0.5 rounded bg-surface border border-slate-800 text-white">
                  {(v.weight * 100).toFixed(0)}% Weight
                </span>
              </div>

              <p className="text-xs text-slate-300 leading-relaxed mb-4">
                {v.description}
              </p>

              {/* Core Features */}
              <div className="mb-4">
                <span className="text-[11px] sm:text-[10px] font-mono uppercase text-slate-500 block mb-1.5 font-bold">
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

      {/* Candidate Models #4 & #5 Ablation Study Section */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-xl space-y-4">
        <div className="flex items-center justify-between pb-3 border-b border-slate-800">
          <div className="flex items-center gap-2">
            <Layers className="w-5 h-5 text-amber-400" />
            <div>
              <h2 className="text-base font-bold text-white">
                Candidate Models Evaluation & Ablation Analysis (Models #4 & #5)
              </h2>
              <p className="text-xs text-slate-400">
                Evaluation of potential 4th and 5th ensemble components tested against 2026 walk-forward out-of-sample data.
              </p>
            </div>
          </div>
          <span className="text-xs font-mono px-2.5 py-1 rounded bg-surface border border-slate-800 text-amber-400 font-semibold">
            Empirical Ablation Study
          </span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {candidateModels.map((cand) => (
            <div
              key={cand.id}
              className="p-4 rounded-lg bg-surface/70 border border-slate-800/80 space-y-3"
            >
              <div className="flex items-center justify-between">
                <div>
                  <span className="text-[11px] sm:text-[10px] font-mono text-amber-400 block uppercase font-bold">
                    {cand.number}
                  </span>
                  <h3 className="text-sm font-bold text-white">{cand.name}</h3>
                </div>
                <span className="text-[11px] font-mono font-bold px-2 py-0.5 rounded bg-surface-raised border border-slate-700 text-slate-400">
                  Weight: {cand.evaluatedWeight}
                </span>
              </div>

              <div className="text-xs space-y-2">
                <div className="flex items-center justify-between text-[11px] font-mono bg-surface-raised/60 p-2 rounded border border-slate-800">
                  <span className="text-slate-400">Out-of-Sample Lift:</span>
                  <span className="text-rose-400 font-bold">{cand.liftStatus}</span>
                </div>
                <p className="text-slate-300 leading-relaxed text-xs">
                  {cand.finding}
                </p>
                <div className="pt-2 border-t border-slate-800/80 text-[11px] text-slate-400">
                  <strong className="text-slate-300">Decision: </strong>
                  {cand.recommendation}
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Ablation Benchmark Table */}
        <div className="flex items-center justify-end pt-2">
          <button
            type="button"
            onClick={handleExportAblationCsv}
            title="Export CSV"
            aria-label="Export ablation benchmark table as CSV"
            data-export-exclude
            className="p-1.5 rounded-lg border border-slate-800 text-slate-400 hover:text-white hover:border-slate-600 transition-colors"
          >
            <Download className="w-3.5 h-3.5" />
          </button>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs font-mono">
            <thead className="bg-surface/90 text-slate-400 uppercase text-[11px] sm:text-[10px] tracking-wider border-b border-slate-800">
              <tr>
                <th className="px-3 py-2">Ensemble Architecture</th>
                <th className="px-3 py-2">Weight Distribution</th>
                <th className="px-3 py-2 text-right">Brier Score</th>
                <th className="px-3 py-2 text-right">Log Loss</th>
                <th className="px-3 py-2 text-center">Ensemble Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-800/60">
              <tr className="bg-accent-950/20 hover:bg-accent-950/30">
                <td className="px-3 py-2 text-white font-bold">2-Model Baseline (Production)</td>
                <td className="px-3 py-2 text-slate-300">Ridge (50%) + Elo (50%)</td>
                <td className="px-3 py-2 text-right text-emerald-400 font-bold">0.2228</td>
                <td className="px-3 py-2 text-right text-emerald-400 font-bold">0.6363</td>
                <td className="px-3 py-2 text-center text-accent-400 font-bold">Active Production</td>
              </tr>
              <tr className="hover:bg-slate-800/40">
                <td className="px-3 py-2 text-slate-400">3-Model Variant (+ Net EPA)</td>
                <td className="px-3 py-2 text-slate-400">Ridge (45%) + Elo (45%) + EPA (10%)</td>
                <td className="px-3 py-2 text-right text-slate-500 font-semibold">&mdash;</td>
                <td className="px-3 py-2 text-right text-slate-500 font-semibold">&mdash;</td>
                <td className="px-3 py-2 text-center text-slate-500 font-semibold">Unverified (pending re-run)</td>
              </tr>
              <tr className="hover:bg-slate-800/40">
                <td className="px-3 py-2 text-slate-400">3-Model Variant (+ Rest / Fatigue)</td>
                <td className="px-3 py-2 text-slate-400">Ridge (45%) + Elo (45%) + Rest (10%)</td>
                <td className="px-3 py-2 text-right text-slate-500 font-semibold">&mdash;</td>
                <td className="px-3 py-2 text-right text-slate-500 font-semibold">&mdash;</td>
                <td className="px-3 py-2 text-center text-slate-500 font-semibold">Unverified (pending re-run)</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      {/* Mathematical Ensembling Notes */}
      <div className="bg-surface-raised/90 border border-slate-800 rounded-xl p-5 shadow-lg">
        <div className="flex items-center gap-2 pb-3 border-b border-slate-800 mb-3 text-white font-semibold">
          <HelpCircle className="w-4 h-4 text-emerald-400" />
          <span>Why Ensemble Independent Estimators?</span>
        </div>
        <p className="text-xs text-slate-300 leading-relaxed max-w-4xl">
          By ensembling an econometric regularized matrix regression (Ridge Massey) with a time-series Markovian
          rating updater (Elo), the meta-predictor suppresses individual model variance without inflating
          prediction bias. Empirically, the 50/50 blend achieves a ~9.6% Brier score improvement over an
          uninformative baseline (the home-win base rate&apos;s own Brier score, p(1&minus;p) &asymp; 0.2464,
          n=5,548 walk-forward games, seasons 2003&ndash;2025 &mdash; re-run this session via tools/model_
          backtest_harness.R&apos;s &quot;prod_ridge_elo_2model&quot; candidate, Brier 0.2228), yielding sharper
          margin estimates and protecting projections from statistical noise. When live Elo is unavailable for
          a matchup, the ensemble falls back to 100% Ridge-Massey.
        </p>
      </div>
    </div>
  );
}
